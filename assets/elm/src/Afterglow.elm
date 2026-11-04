port module Afterglow exposing (main)

{-| Afterglow: remember which tiles of a grid lit up.

A game has a countdown and then 10 rounds. In each round, the grid shows
for a moment, the tiles of the round light up and go out, and then the
player clicks the tiles that were lit. A wrong tile ends the round, and the
missed tiles show as rings. After a fully correct round, the next round has
one tile more, else it has one tile less.

The server gives the tiles of each round. This module checks each click
itself, for the score on the screen, and sends it out through a port. The
server checks it again and saves the score at the end. The server goes to
the next round at once when a round ends, but the page shows the end of
the round for a moment first, so it keeps its own copy of the round on the
screen. app.js connects the ports to a Phoenix channel.

Afterglow is a single-player game. A browser that joins a game that has
its player only watches: it has no player id.

-}

import Browser
import Browser.Events
import Html exposing (Html, a, button, div, h1, img, p, span, text)
import Html.Attributes exposing (alt, attribute, class, classList, href, id, rel, src, style, target)
import Html.Events exposing (onClick)
import Html.Keyed
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Set exposing (Set)
import Task
import Time



-- PORTS


port afterglowTap : Encode.Value -> Cmd msg


port afterglowRestart : () -> Cmd msg


port afterglowJoined : (Decode.Value -> msg) -> Sub msg


port afterglowState : (Decode.Value -> msg) -> Sub msg


port afterglowJoinFailed : (String -> msg) -> Sub msg


port afterglowPlaySound : String -> Cmd msg


port afterglowSaveMuted : Bool -> Cmd msg



-- MODEL


type alias Player =
    { id : String
    , score : Int
    }


type alias RoundResult =
    { level : Int
    , perfect : Bool
    }


type alias Game =
    { -- Tells a new game from the old one
      field : String
    , round : Int
    , rounds : Int
    , level : Int
    , size : Int

    -- Empty before the start and during the countdown
    , pattern : List Int
    , showMs : Int
    , points : Int

    -- The time since the start of the round, below zero during the countdown
    , roundMs : Int

    -- The correct tiles of the round that the server has
    , found : List Int
    , history : List RoundResult
    , bestLevel : Maybe Int
    , perfect : Int
    , lastLevel : Maybe Int
    , waiting : Bool
    , finished : Bool

    -- The time since the start, below zero during the countdown
    , elapsedMs : Int
    , players : List Player
    }


{-| The player id of this browser. Nothing for a watcher.
-}
type alias Me =
    Maybe String


type Connection
    = Connecting
    | Joined Me Game
    | Failed String


{-| The round on the screen, with the clicks of the player as this page
counts them. The times are local times in ms.
-}
type alias Round =
    { field : String
    , number : Int
    , level : Int
    , size : Int
    , pattern : Set Int
    , showMs : Int
    , found : Set Int
    , wrong : Maybe Int
    , startedAt : Int
    , endedAt : Maybe Int
    }


{-| The game to try next, on the end screen
-}
type alias NextGame =
    { name : String
    , path : String
    }


type alias Model =
    { settingsUrl : String
    , nextGame : NextGame
    , guest : Bool
    , connection : Connection
    , current : Maybe Round
    , score : Int

    -- The local times (in ms) when the game and the round of the server
    -- started, and the local time now
    , clockStart : Int
    , roundClock : Int
    , now : Int

    -- The countdown step that last played its beep (see `countdownStep`)
    , beepedStep : Maybe Int

    -- The round and the stage that last played its sound
    , cue : Maybe ( Int, Stage )
    , muted : Bool
    }


type alias Flags =
    { settingsUrl : String
    , nextGame : NextGame
    , guest : Bool
    , muted : Bool
    }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { settingsUrl = flags.settingsUrl
      , nextGame = flags.nextGame
      , guest = flags.guest
      , connection = Connecting
      , current = Nothing
      , score = 0
      , clockStart = 0
      , roundClock = 0
      , now = 0
      , beepedStep = Nothing
      , cue = Nothing
      , muted = flags.muted
      }
    , Cmd.none
    )


{-| The empty grid shows for a moment before the tiles light up
-}
leadMs : Int
leadMs =
    600


{-| How long the end of a round shows. A missed round shows longer, so
that the player sees the missed tiles.
-}
feedbackMs : Round -> Int
feedbackMs round =
    if round.wrong == Nothing then
        900

    else
        1600



-- UPDATE


type Msg
    = GotJoined Decode.Value
    | GotState Decode.Value
    | GotJoinFailed String
    | Tap Int
    | Restart
    | SyncClock Int Int Time.Posix
    | Tick Time.Posix
    | ToggleMuted


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotJoined value ->
            case Decode.decodeValue joinedDecoder value of
                Ok ( me, game ) ->
                    ( sync game { model | connection = Joined me game }, syncClock game )

                Err err ->
                    ( { model | connection = Failed (Decode.errorToString err) }, Cmd.none )

        GotState value ->
            case ( model.connection, Decode.decodeValue gameDecoder value ) of
                ( Joined me _, Ok game ) ->
                    ( sync game { model | connection = Joined me game }, syncClock game )

                _ ->
                    ( model, Cmd.none )

        GotJoinFailed reason ->
            ( { model | connection = Failed reason }, Cmd.none )

        Tap cell ->
            case ( model.connection, model.current ) of
                ( Joined (Just _) _, Just round ) ->
                    if stage model round == Recall && not (Set.member cell round.found) then
                        tap cell round model

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        Restart ->
            ( model, afterglowRestart () )

        SyncClock elapsedMs roundMs time ->
            let
                ms =
                    Time.posixToMillis time
            in
            onTick { model | clockStart = ms - elapsedMs, roundClock = ms - roundMs, now = ms }

        Tick time ->
            onTick { model | now = Time.posixToMillis time }

        ToggleMuted ->
            ( { model | muted = not model.muted }, afterglowSaveMuted (not model.muted) )


{-| Takes the score from the server for a new game, after a reload, and
after each round. During a round, the page is ahead of the server, so it
keeps its own score.
-}
sync : Game -> Model -> Model
sync game model =
    let
        server =
            List.head game.players |> Maybe.map .score |> Maybe.withDefault 0
    in
    case model.current of
        Just round ->
            if round.field /= game.field then
                { model | current = Nothing, score = server, beepedStep = Nothing, cue = Nothing }

            else if game.round > round.number || game.finished then
                { model | score = server }

            else
                model

        Nothing ->
            { model | score = server }


{-| Checks the click at once, and sends it to the server
-}
tap : Int -> Round -> Model -> ( Model, Cmd Msg )
tap cell round model =
    let
        send =
            afterglowTap (Encode.object [ ( "round", Encode.int round.number ), ( "cell", Encode.int cell ) ])
    in
    if Set.member cell round.pattern then
        let
            found =
                Set.insert cell round.found

            done =
                Set.size found == round.level

            points =
                case model.connection of
                    Joined _ game ->
                        game.points * round.level

                    _ ->
                        0
        in
        ( { model
            | current =
                Just
                    { round
                        | found = found
                        , endedAt =
                            if done then
                                Just model.now

                            else
                                Nothing
                    }
            , score = model.score + points
          }
        , Cmd.batch
            [ send
            , playSounds model
                (("found-" ++ String.fromInt (Set.size round.found))
                    :: (if done then
                            [ "perfect" ]

                        else
                            []
                       )
                )
            ]
        )

    else
        ( { model | current = Just { round | wrong = Just cell, endedAt = Just model.now } }
        , Cmd.batch [ send, playSounds model [ "wrong" ] ]
        )


type Stage
    = Ready
    | Show
    | Recall
    | Done


stage : Model -> Round -> Stage
stage model round =
    let
        t =
            model.now - round.startedAt
    in
    if round.endedAt /= Nothing then
        Done

    else if t < leadMs then
        Ready

    else if t < leadMs + round.showMs then
        Show

    else
        Recall


type Phase
    = Countdown
    | Playing Round
    | Over


{-| The page shows the end of its round before it goes on with the server
-}
phase : Model -> Game -> Phase
phase model game =
    case model.current of
        Just round ->
            if game.finished && canLeave model round then
                Over

            else
                Playing round

        Nothing ->
            if game.finished then
                Over

            else
                Countdown


canLeave : Model -> Round -> Bool
canLeave model round =
    case round.endedAt of
        Just endedAt ->
            model.now - endedAt >= feedbackMs round

        -- The server went on without this page, for example in another tab
        Nothing ->
            True


{-| The time since the start of the game, in ms. Below zero during the
countdown.
-}
elapsed : Model -> Int
elapsed model =
    model.now - model.clockStart


{-| The round of the server, shown from the local time `startedAt`
-}
roundFrom : Game -> Int -> Round
roundFrom game startedAt =
    { field = game.field
    , number = game.round
    , level = game.level
    , size = game.size
    , pattern = Set.fromList game.pattern
    , showMs = game.showMs
    , found = Set.fromList game.found
    , wrong = Nothing
    , startedAt = startedAt
    , endedAt = Nothing
    }


{-| Starts the first round after the countdown (or the round of the server
after a reload), goes to the next round after the end of a round, and
plays the beeps of the countdown and the sounds of the stages.
-}
onTick : Model -> ( Model, Cmd Msg )
onTick model =
    case model.connection of
        Joined _ game ->
            let
                step =
                    countdownStep model game

                beeps =
                    if step == model.beepedStep then
                        []

                    else
                        case step of
                            Just 0 ->
                                []

                            Just _ ->
                                [ "countdown" ]

                            Nothing ->
                                []

                running =
                    not game.waiting && not game.finished && not (List.isEmpty game.pattern)

                current =
                    case model.current of
                        Nothing ->
                            if running && elapsed model >= 0 then
                                -- After a reload, the round of the server
                                -- starts where the page would show it
                                Just
                                    (roundFrom game
                                        (if game.round == 1 then
                                            model.roundClock

                                         else
                                            model.roundClock + 1200
                                        )
                                    )

                            else
                                Nothing

                        Just round ->
                            if running && game.field == round.field && game.round > round.number && canLeave model round then
                                Just (roundFrom game model.now)

                            else
                                Just round

                ( cue, cueSounds ) =
                    case current of
                        Just round ->
                            let
                                now =
                                    stage model round

                                sound =
                                    case now of
                                        Show ->
                                            [ "show" ]

                                        Recall ->
                                            [ "hide" ]

                                        _ ->
                                            []
                            in
                            if model.cue == Just ( round.number, now ) || sound == [] then
                                ( model.cue, [] )

                            else
                                ( Just ( round.number, now ), sound )

                        Nothing ->
                            ( model.cue, [] )

                ended =
                    game.finished && phase model game /= Over && phase { model | current = current } game == Over
            in
            ( { model | beepedStep = step, current = current, cue = cue }
            , playSounds model
                (beeps
                    ++ cueSounds
                    ++ (if ended then
                            [ "end" ]

                        else
                            []
                       )
                )
            )

        _ ->
            ( model, Cmd.none )


{-| The seconds left in the countdown (3, 2, 1), 0 after it, and Nothing
when no game runs
-}
countdownStep : Model -> Game -> Maybe Int
countdownStep model game =
    if game.waiting || game.finished then
        Nothing

    else
        Just (max 0 (ceiling (toFloat (negate (elapsed model)) / 1000)))


playSounds : Model -> List String -> Cmd Msg
playSounds model names =
    if model.muted then
        Cmd.none

    else
        Cmd.batch (List.map afterglowPlaySound names)


syncClock : Game -> Cmd Msg
syncClock game =
    Time.now |> Task.perform (SyncClock game.elapsedMs game.roundMs)



-- DECODERS


joinedDecoder : Decoder ( Me, Game )
joinedDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "player_id" (Decode.nullable Decode.string))
        (Decode.field "state" gameDecoder)


{-| Adds one more field to a decoder, for records with more than 8 fields
-}
andMap : Decoder a -> Decoder (a -> b) -> Decoder b
andMap =
    Decode.map2 (|>)


gameDecoder : Decoder Game
gameDecoder =
    Decode.succeed Game
        |> andMap (Decode.field "field" Decode.string)
        |> andMap (Decode.field "round" Decode.int)
        |> andMap (Decode.field "rounds" Decode.int)
        |> andMap (Decode.field "level" Decode.int)
        |> andMap (Decode.field "size" Decode.int)
        |> andMap (Decode.field "pattern" (Decode.list Decode.int))
        |> andMap (Decode.field "show_ms" Decode.int)
        |> andMap (Decode.field "points" Decode.int)
        |> andMap (Decode.field "round_ms" Decode.int)
        |> andMap (Decode.field "found" (Decode.list Decode.int))
        |> andMap
            (Decode.field "history"
                (Decode.list
                    (Decode.map2 RoundResult
                        (Decode.field "level" Decode.int)
                        (Decode.field "perfect" Decode.bool)
                    )
                )
            )
        |> andMap (Decode.field "best_level" (Decode.nullable Decode.int))
        |> andMap (Decode.field "perfect" Decode.int)
        |> andMap (Decode.field "last_level" (Decode.nullable Decode.int))
        |> andMap (Decode.field "waiting" Decode.bool)
        |> andMap (Decode.field "finished" Decode.bool)
        |> andMap (Decode.field "elapsed_ms" Decode.int)
        |> andMap
            (Decode.field "players"
                (Decode.list
                    (Decode.map2 Player
                        (Decode.field "id" Decode.string)
                        (Decode.field "score" Decode.int)
                    )
                )
            )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ afterglowJoined GotJoined
        , afterglowState GotState
        , afterglowJoinFailed GotJoinFailed
        , case model.connection of
            Joined _ game ->
                if phase model game == Over then
                    Sub.none

                else
                    Browser.Events.onAnimationFrame Tick

            _ ->
                Sub.none
        ]



-- VIEW


view : Model -> Html Msg
view model =
    case model.connection of
        Connecting ->
            p [ id "afterglow-connecting", class "py-24 text-center opacity-60" ] [ text "Joining the game…" ]

        Failed reason ->
            p [ id "afterglow-failed", class "py-24 text-center text-red-600" ] [ text ("Could not join the game: " ++ reason) ]

        Joined me game ->
            div
                [ id "afterglow-root"
                , class "mx-auto flex w-full max-w-lg flex-col gap-4 select-none"

                -- The page does not scroll during the game
                , classList [ ( "is-playing", me /= Nothing && phase model game /= Over ) ]
                ]
                [ viewHeader model me
                , viewStats model game
                , if me == Nothing then
                    p [ id "afterglow-watching", class "rounded-2xl bg-amber-50 px-4 py-3 text-sm text-amber-900 ring-1 ring-amber-200 dark:bg-amber-400/10 dark:text-amber-200 dark:ring-amber-400/25" ]
                        [ text "Afterglow is a single-player game, and this game has its player already. "
                        , a [ href "/afterglow", class "font-medium underline underline-offset-4" ] [ text "Start your own game" ]
                        , text "."
                        ]

                  else
                    viewBoard model game
                ]


viewHeader : Model -> Me -> Html Msg
viewHeader model me =
    div [ class "flex items-center gap-1 lg:gap-2" ]
        [ a
            [ id "afterglow-home"
            , href "/"
            , class "mr-1 shrink-0 transition lg:mr-0"
            ]
            [ img [ src "/images/mark.svg", alt "octomocto", class "h-8 w-auto dark:hidden lg:h-9" ] []
            , img [ src "/images/mark-on-dark.svg", alt "octomocto", class "hidden h-8 w-auto dark:block lg:h-9" ] []
            ]
        , h1 [ class "text-xl font-semibold tracking-tight lg:text-2xl" ]
            [ a [ id "afterglow-title-link", href model.settingsUrl, class "transition hover:text-octo-indigo dark:hover:text-octo-indigo-light" ] [ text "Afterglow" ] ]
        , viewMuteButton model.muted
        , if me == Nothing then
            text ""

          else
            button
                [ id "afterglow-restart"
                , class "group ml-auto flex shrink-0 items-center gap-2 rounded-full px-4 py-2 text-sm font-medium text-slate-600 ring-1 ring-slate-200 transition hover:bg-slate-50 hover:text-slate-900 hover:ring-slate-300 active:scale-95 dark:text-slate-300 dark:ring-white/20 dark:hover:bg-white/10 dark:hover:text-white dark:hover:ring-white/30"
                , onClick Restart
                , Html.Attributes.title "Restart game"
                ]
                [ span [ class "hero-arrow-path size-4 transition-transform duration-300 group-hover:-rotate-180" ] []
                , span [ class "max-sm:hidden" ] [ text "Restart" ]
                ]
        ]


viewMuteButton : Bool -> Html Msg
viewMuteButton muted =
    button
        [ id "afterglow-mute"
        , class "grid size-8 place-items-center rounded-full text-slate-500 transition hover:bg-slate-100 hover:text-slate-800 active:scale-90 dark:text-slate-400 dark:hover:bg-white/10 dark:hover:text-slate-100"
        , onClick ToggleMuted
        , Html.Attributes.title
            (if muted then
                "Turn the sounds on"

             else
                "Turn the sounds off"
            )
        ]
        [ span
            [ class
                (if muted then
                    "hero-speaker-x-mark size-5"

                 else
                    "hero-speaker-wave size-5"
                )
            ]
            []
        ]


{-| The round with a dot for each round, the score, and the tiles of the
round
-}
viewStats : Model -> Game -> Html Msg
viewStats model game =
    let
        ( number, level ) =
            case model.current of
                Just round ->
                    ( round.number, round.level )

                Nothing ->
                    ( game.round, game.level )

        stat label content =
            div [ class "flex flex-col items-center justify-center gap-0.5 px-2" ]
                [ span [ class "text-[0.625rem] font-medium tracking-wide text-slate-400 uppercase lg:text-xs" ] [ text label ]
                , content
                ]
    in
    div [ id "afterglow-stats", class "grid grid-cols-3 divide-x divide-slate-200 rounded-2xl bg-white py-3 shadow-sm ring-1 ring-slate-200 dark:divide-white/10 dark:bg-white/5 dark:shadow-none dark:ring-white/10" ]
        [ stat "round"
            (div [ class "flex flex-col items-center gap-1" ]
                [ span [ id "afterglow-round", class "text-2xl leading-tight font-light tabular-nums lg:text-3xl" ]
                    [ text (String.fromInt (min number game.rounds) ++ "/" ++ String.fromInt game.rounds) ]
                , viewDots model game
                ]
            )
        , stat "score"
            (span [ id "afterglow-score", class "text-2xl leading-tight font-bold text-octo-indigo tabular-nums lg:text-3xl dark:text-octo-indigo-light" ]
                [ text (String.fromInt model.score) ]
            )
        , stat "tiles"
            (Html.Keyed.node "span"
                []
                [ ( String.fromInt level
                  , span [ id "afterglow-level", class "countdown-pop inline-block text-2xl leading-tight font-semibold tabular-nums lg:text-3xl" ]
                        [ text (String.fromInt level) ]
                  )
                ]
            )
        ]


{-| A dot for each round: filled for a fully correct round, red for a
missed round, and larger for the current round
-}
viewDots : Model -> Game -> Html Msg
viewDots model game =
    let
        dot i =
            let
                done =
                    case model.current of
                        Just round ->
                            if i == round.number then
                                round.endedAt |> Maybe.map (\_ -> round.wrong == Nothing)

                            else if i < round.number then
                                List.drop (i - 1) game.history |> List.head |> Maybe.map .perfect

                            else
                                Nothing

                        Nothing ->
                            List.drop (i - 1) game.history |> List.head |> Maybe.map .perfect

                isCurrent =
                    Maybe.map .number model.current == Just i && done == Nothing
            in
            span
                [ class "afterglow-dot size-1.5 rounded-full"
                , classList
                    [ ( "bg-octo-indigo dark:bg-octo-indigo-light", done == Just True )
                    , ( "bg-red-400", done == Just False )
                    , ( "bg-slate-400 dark:bg-slate-300 is-current", isCurrent )
                    , ( "bg-slate-200 dark:bg-white/15", done == Nothing && not isCurrent )
                    ]
                ]
                []
    in
    div [ class "flex gap-1" ] (List.map dot (List.range 1 game.rounds))


{-| The prompt and the grid, with the covers of the countdown and the end
over them
-}
viewBoard : Model -> Game -> Html Msg
viewBoard model game =
    let
        current =
            phase model game
    in
    div [ class "relative flex flex-col items-center gap-4 pt-1" ]
        [ p [ id "afterglow-prompt", class "h-7 text-center text-lg font-medium text-slate-600 dark:text-slate-300" ]
            [ text (prompt model game current) ]
        , div [ class "afterglow-stage" ]
            [ case ( current, model.current ) of
                ( Playing round, _ ) ->
                    viewGrid model round

                ( Over, Just round ) ->
                    viewGrid model round

                _ ->
                    viewEmptyGrid game.size
            ]
        , case current of
            Countdown ->
                viewCountdown (Maybe.withDefault 0 (countdownStep model game))

            Over ->
                viewResult model game

            _ ->
                text ""
        ]


prompt : Model -> Game -> Phase -> String
prompt model game current =
    case current of
        Playing round ->
            case stage model round of
                Ready ->
                    "Get ready…"

                Show ->
                    "Remember the tiles"

                Recall ->
                    "Click the tiles that were lit · " ++ String.fromInt (round.level - Set.size round.found) ++ " left"

                Done ->
                    if round.number >= game.rounds then
                        if round.wrong == Nothing then
                            "Perfect!"

                        else
                            "Missed"

                    else if round.wrong == Nothing then
                        "Perfect! One tile more"

                    else if round.level > 3 then
                        "Missed. One tile less"

                    else
                        "Missed. Try again"

        _ ->
            ""


{-| The grid is keyed by the round, so that each round fades in
-}
viewGrid : Model -> Round -> Html Msg
viewGrid model round =
    let
        now =
            stage model round

        tile cell =
            let
                found =
                    Set.member cell round.found

                lit =
                    Set.member cell round.pattern
            in
            button
                [ id ("afterglow-tile-" ++ String.fromInt cell)
                , class "afterglow-tile"
                , classList
                    [ ( "is-lit", now == Show && lit )
                    , ( "is-found", found )
                    , ( "is-wrong", round.wrong == Just cell )
                    , ( "is-missed", now == Done && round.wrong /= Nothing && lit && not found )
                    , ( "is-open", now == Recall && not found )
                    ]
                , attribute "aria-label" ("Tile " ++ String.fromInt (cell + 1))
                , onClick (Tap cell)
                ]
                []
    in
    Html.Keyed.node "div"
        []
        [ ( round.field ++ "-" ++ String.fromInt round.number
          , div
                [ id "afterglow-grid"
                , class "afterglow-grid"
                , classList [ ( "is-perfect", now == Done && round.wrong == Nothing ) ]
                , style "grid-template-columns" ("repeat(" ++ String.fromInt round.size ++ ", minmax(0, 1fr))")
                ]
                (List.map tile (List.range 0 (round.size * round.size - 1)))
          )
        ]


viewEmptyGrid : Int -> Html Msg
viewEmptyGrid size =
    div
        [ class "afterglow-grid"
        , style "grid-template-columns" ("repeat(" ++ String.fromInt size ++ ", minmax(0, 1fr))")
        ]
        (List.map (\_ -> span [ class "afterglow-tile" ] []) (List.range 1 (size * size)))


{-| The number is keyed, so that it pops in again on each step.
-}
viewCountdown : Int -> Html Msg
viewCountdown seconds =
    div
        [ id "afterglow-countdown"
        , class "absolute inset-0 flex items-center justify-center rounded-2xl bg-octo-navy/80"
        ]
        [ Html.Keyed.node "div"
            []
            [ ( String.fromInt seconds
              , p [ class "countdown-pop text-9xl font-bold text-white tabular-nums" ]
                    [ text
                        (if seconds > 0 then
                            String.fromInt seconds

                         else
                            ""
                        )
                    ]
              )
            ]
        ]


viewResult : Model -> Game -> Html Msg
viewResult model game =
    let
        score =
            List.head game.players |> Maybe.map .score |> Maybe.withDefault model.score
    in
    div
        [ id "afterglow-result"
        , class "absolute inset-0 z-10 flex flex-col items-center justify-center gap-4 rounded-2xl bg-octo-navy/80 p-4 text-center text-white backdrop-blur-sm"
        ]
        [ p [ class "text-lg opacity-80" ] [ text "Game over!" ]
        , p [ id "afterglow-final-score", class "text-6xl font-bold tabular-nums" ] [ text (String.fromInt score) ]
        , p [ id "afterglow-final-rounds", class "text-sm tabular-nums opacity-80" ]
            [ text
                (String.fromInt game.perfect
                    ++ " of "
                    ++ String.fromInt game.rounds
                    ++ " rounds perfect"
                    ++ (case game.bestLevel of
                            Just best ->
                                " · best " ++ String.fromInt best ++ " tiles"

                            Nothing ->
                                ""
                       )
                )
            ]
        , button
            [ id "afterglow-play-again"
            , class "rounded-full bg-white px-6 py-2.5 font-medium text-octo-indigo shadow-lg transition hover:bg-octo-mist"
            , onClick Restart
            ]
            [ text
                ("Play again with "
                    ++ String.fromInt (Maybe.withDefault game.level game.lastLevel)
                    ++ " tiles"
                )
            ]
        , a
            [ id "afterglow-leaderboards-link"
            , href model.settingsUrl
            , class "text-sm font-medium text-white/80 underline-offset-4 transition hover:text-white hover:underline"
            ]
            [ text "Best results" ]
        , a
            [ id "afterglow-next-game"
            , href model.nextGame.path
            , attribute "data-ga-link" "or_try"
            , attribute "data-ga-from" "Afterglow"
            , attribute "data-ga-to" model.nextGame.name
            , class "group text-sm font-medium text-white underline-offset-4 transition hover:underline"
            ]
            [ text ("Or try " ++ model.nextGame.name ++ " ")
            , span [ class "inline-block transition group-hover:translate-x-0.5" ] [ text "→" ]
            ]
        , if model.guest then
            p [ id "afterglow-sign-in", class "text-sm text-white/70" ]
                [ a
                    [ href "/signin"
                    , class "font-medium text-white underline underline-offset-4 transition hover:text-octo-mist"
                    ]
                    [ text "Sign in" ]
                , text " to keep your scores."
                ]

          else
            text ""
        , viewFeed
        ]


{-| The call to support Octomocto on Patreon, at the bottom of a result.
The link opens in a new tab, so that the player stays in the game.
-}
viewFeed : Html msg
viewFeed =
    p [ id "afterglow-feed", class "mt-2 max-w-sm border-t border-white/15 pt-4 text-center text-sm leading-10 text-balance text-white/80" ]
        [ text "Enjoying Octomocto? "
        , a
            [ href "https://patreon.com/mxgrn"
            , target "_blank"
            , rel "noopener"
            , class "group mx-1 inline-flex items-center gap-1.5 whitespace-nowrap rounded-full bg-octo-orange px-4 py-1.5 align-middle leading-5 font-semibold text-white shadow-lg shadow-octo-orange/30 transition hover:bg-octo-orange-light"
            ]
            [ span [ class "hero-heart-solid size-4 transition group-hover:scale-110" ] []
            , text "Feed Octo & Mocto"
            ]
        , text " to keep it ad-free."
        ]



-- MAIN


main : Program Flags Model Msg
main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }
