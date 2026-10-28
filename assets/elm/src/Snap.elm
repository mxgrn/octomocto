port module Snap exposing (main)

{-| Snap: is the new card the same as the card some places back?

The server deals all cards of a round at the start, so that the next card
shows at once after each answer. This module checks each answer itself, for
the score on the screen, and sends it out through a port. The server checks
it again and saves the score at the end. app.js connects the ports to a
Phoenix channel.

A round has a countdown, then the first `back` cards to remember (each for
a short time), and then 45 seconds of play. Each 4 correct answers in a row
make the multiplier one larger, up to x5. A wrong answer sets it back to x1.
When the clock is over, the page tells the server, which ends the round and
sends the final score.

Snap is a single-player game. A browser that joins a game that has its
player only watches: it has no player id.

-}

import Array exposing (Array)
import Browser
import Browser.Events
import Html exposing (Html, a, button, div, h1, img, kbd, p, span, text)
import Html.Attributes exposing (alt, attribute, class, classList, disabled, href, id, rel, src, target)
import Html.Events exposing (onClick)
import Html.Keyed
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Svg
import Svg.Attributes as SA
import Task
import Time



-- PORTS


port snapAnswer : Encode.Value -> Cmd msg


port snapTimeUp : () -> Cmd msg


port snapRestart : () -> Cmd msg


port snapJoined : (Decode.Value -> msg) -> Sub msg


port snapState : (Decode.Value -> msg) -> Sub msg


port snapJoinFailed : (String -> msg) -> Sub msg


port snapPlaySound : String -> Cmd msg


port snapSaveMuted : Bool -> Cmd msg



-- MODEL


type alias Player =
    { id : String
    , score : Int
    }


type alias Shape =
    Int


type alias Game =
    { -- Tells a new round from the old one
      field : String
    , back : Int

    -- Empty before the start and during the countdown
    , cards : Array Shape
    , previewMs : Int
    , playMs : Int
    , points : Int
    , streakStep : Int
    , maxMultiplier : Int

    -- The answers of the player that the server has
    , correct : Int
    , wrong : Int
    , streak : Int
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


{-| The answers of the player in this round, as this page counts them
-}
type alias Progress =
    { field : String
    , correct : Int
    , wrong : Int
    , streak : Int
    , score : Int
    }


{-| The last answer, while its mark shows. The count tells the answers
apart, so that each answer shows its own mark.
-}
type alias Feedback =
    { count : Int
    , correct : Bool
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
    , progress : Progress
    , feedback : Maybe Feedback

    -- The local time (in ms) when the round started, and the local time now
    , clockStart : Int
    , now : Int

    -- The countdown step that last played its beep (see `countdownStep`)
    , beepedStep : Maybe Int

    -- The card to remember that last played its sound
    , shownPreview : Maybe Int
    , timeUpSent : Bool
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
      , progress = Progress "" 0 0 0 0
      , feedback = Nothing
      , clockStart = 0
      , now = 0
      , beepedStep = Nothing
      , shownPreview = Nothing
      , timeUpSent = False
      , muted = flags.muted
      }
    , Cmd.none
    )



-- UPDATE


type Msg
    = GotJoined Decode.Value
    | GotState Decode.Value
    | GotJoinFailed String
    | Answer Bool
    | Restart
    | SyncClock Int Time.Posix
    | Tick Time.Posix
    | SendTimeUp
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
                ( Joined me old, Ok game ) ->
                    ( sync game { model | connection = Joined me game }
                    , Cmd.batch
                        [ syncClock game
                        , if game.finished && not old.finished then
                            playSounds model [ "end" ]

                          else
                            Cmd.none
                        ]
                    )

                _ ->
                    ( model, Cmd.none )

        GotJoinFailed reason ->
            ( { model | connection = Failed reason }, Cmd.none )

        Answer same ->
            case model.connection of
                Joined (Just _) game ->
                    if phase model game == Play then
                        answer same game model

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        Restart ->
            ( model, snapRestart () )

        SyncClock elapsedMs time ->
            let
                ms =
                    Time.posixToMillis time
            in
            onTick { model | clockStart = ms - elapsedMs, now = ms }

        Tick time ->
            onTick { model | now = Time.posixToMillis time }

        SendTimeUp ->
            ( model, snapTimeUp () )

        ToggleMuted ->
            ( { model | muted = not model.muted }, snapSaveMuted (not model.muted) )


{-| Takes the answers from the server for a new round, after a reload, and
at the end. During a round, the page is ahead of the server, so it keeps
its own answers.
-}
sync : Game -> Model -> Model
sync game model =
    let
        server =
            { field = game.field
            , correct = game.correct
            , wrong = game.wrong
            , streak = game.streak
            , score = List.head game.players |> Maybe.map .score |> Maybe.withDefault 0
            }

        local =
            model.progress
    in
    if game.field == local.field && not game.finished && answered local >= answered server then
        model

    else if game.field == local.field then
        { model | progress = server }

    else
        { model
            | progress = server
            , feedback = Nothing
            , beepedStep = Nothing
            , shownPreview = Nothing
            , timeUpSent = False
        }


answered : Progress -> Int
answered progress =
    progress.correct + progress.wrong


{-| Checks the answer for the next card, shows it at once, and sends it to
the server.
-}
answer : Bool -> Game -> Model -> ( Model, Cmd Msg )
answer same game model =
    let
        progress =
            model.progress

        index =
            game.back + answered progress
    in
    case ( Array.get index game.cards, Array.get (index - game.back) game.cards ) of
        ( Just card, Just earlier ) ->
            let
                correct =
                    (card == earlier) == same

                before =
                    multiplier game progress.streak

                next =
                    if correct then
                        { progress
                            | correct = progress.correct + 1
                            , streak = progress.streak + 1
                            , score = progress.score + game.points * before
                        }

                    else
                        { progress | wrong = progress.wrong + 1, streak = 0 }

                sounds =
                    if not correct then
                        [ "wrong" ]

                    else if multiplier game next.streak > before then
                        [ "correct", "level_up" ]

                    else
                        [ "correct" ]
            in
            ( { model | progress = next, feedback = Just (Feedback (answered next) correct) }
            , Cmd.batch
                [ snapAnswer (Encode.object [ ( "index", Encode.int index ), ( "same", Encode.bool same ) ])
                , playSounds model sounds
                ]
            )

        _ ->
            ( model, Cmd.none )


{-| The multiplier for the next correct answer after a number of correct
answers in a row
-}
multiplier : Game -> Int -> Int
multiplier game streak =
    min game.maxMultiplier (1 + streak // game.streakStep)


type Phase
    = Countdown
      -- The index of the card to remember
    | Preview Int
    | Play
    | TimeUp
    | Over


{-| The time since the start of the round, in ms. Below zero during the
countdown.
-}
elapsed : Model -> Int
elapsed model =
    model.now - model.clockStart


playStart : Game -> Int
playStart game =
    game.back * game.previewMs


phase : Model -> Game -> Phase
phase model game =
    let
        t =
            elapsed model
    in
    if game.finished then
        Over

    else if game.waiting || t < 0 || Array.isEmpty game.cards then
        Countdown

    else if t < playStart game then
        Preview (t // game.previewMs)

    else if t < playStart game + game.playMs then
        Play

    else
        TimeUp


{-| The beeps of the countdown, the sound of each card to remember, and
the message to the server when the clock is over
-}
onTick : Model -> ( Model, Cmd Msg )
onTick model =
    case model.connection of
        Joined me game ->
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

                ( preview, previewSounds ) =
                    case phase model game of
                        Preview index ->
                            if model.shownPreview == Just index then
                                ( model.shownPreview, [] )

                            else
                                ( Just index, [ "card" ] )

                        Play ->
                            if model.shownPreview /= Just game.back then
                                ( Just game.back, [ "go" ] )

                            else
                                ( model.shownPreview, [] )

                        _ ->
                            ( model.shownPreview, [] )

                timeUp =
                    phase model game == TimeUp && me /= Nothing && not model.timeUpSent
            in
            ( { model
                | beepedStep = step
                , shownPreview = preview
                , timeUpSent = model.timeUpSent || timeUp
              }
            , Cmd.batch
                [ playSounds model (beeps ++ previewSounds)
                , if timeUp then
                    snapTimeUp ()

                  else
                    Cmd.none
                ]
            )

        _ ->
            ( model, Cmd.none )


{-| The seconds left in the countdown (3, 2, 1), 0 after it, and Nothing
when no round runs
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
        Cmd.batch (List.map snapPlaySound names)


syncClock : Game -> Cmd Msg
syncClock game =
    Time.now |> Task.perform (SyncClock game.elapsedMs)



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
        |> andMap (Decode.field "back" Decode.int)
        |> andMap (Decode.field "cards" (Decode.array Decode.int))
        |> andMap (Decode.field "preview_ms" Decode.int)
        |> andMap (Decode.field "play_ms" Decode.int)
        |> andMap (Decode.field "points" Decode.int)
        |> andMap (Decode.field "streak_step" Decode.int)
        |> andMap (Decode.field "max_multiplier" Decode.int)
        |> andMap (Decode.field "correct" Decode.int)
        |> andMap (Decode.field "wrong" Decode.int)
        |> andMap (Decode.field "streak" Decode.int)
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
        [ snapJoined GotJoined
        , snapState GotState
        , snapJoinFailed GotJoinFailed
        , case model.connection of
            Joined me game ->
                case phase model game of
                    Over ->
                        Sub.none

                    -- The server ends the round. A message that came too
                    -- early goes again.
                    TimeUp ->
                        if me /= Nothing then
                            Time.every 2000 (\_ -> SendTimeUp)

                        else
                            Sub.none

                    Play ->
                        Sub.batch [ Browser.Events.onAnimationFrame Tick, Browser.Events.onKeyDown keyDecoder ]

                    _ ->
                        Browser.Events.onAnimationFrame Tick

            _ ->
                Sub.none
        ]


{-| The right arrow says yes, and the left arrow says no. A key that is held
down does not answer again.
-}
keyDecoder : Decoder Msg
keyDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "key" Decode.string)
        (Decode.field "repeat" Decode.bool)
        |> Decode.andThen
            (\( key, repeat ) ->
                case ( key, repeat ) of
                    ( "ArrowRight", False ) ->
                        Decode.succeed (Answer True)

                    ( "ArrowLeft", False ) ->
                        Decode.succeed (Answer False)

                    _ ->
                        Decode.fail "not an answer"
            )



-- VIEW


view : Model -> Html Msg
view model =
    case model.connection of
        Connecting ->
            p [ id "snap-connecting", class "py-24 text-center opacity-60" ] [ text "Joining the game…" ]

        Failed reason ->
            p [ id "snap-failed", class "py-24 text-center text-red-600" ] [ text ("Could not join the game: " ++ reason) ]

        Joined me game ->
            div
                [ id "snap-root"
                , class "mx-auto flex w-full max-w-lg flex-col gap-4 select-none"

                -- The page does not scroll during the round
                , classList [ ( "is-playing", me /= Nothing && phase model game /= Over ) ]
                ]
                [ viewHeader model me
                , viewStats model game
                , if me == Nothing then
                    p [ id "snap-watching", class "rounded-2xl bg-amber-50 px-4 py-3 text-sm text-amber-900 ring-1 ring-amber-200 dark:bg-amber-400/10 dark:text-amber-200 dark:ring-amber-400/25" ]
                        [ text "Snap is a single-player game, and this game has its player already. "
                        , a [ href "/snap", class "font-medium underline underline-offset-4" ] [ text "Start your own game" ]
                        , text "."
                        ]

                  else
                    viewTable model game
                ]


viewHeader : Model -> Me -> Html Msg
viewHeader model me =
    div [ class "flex items-center gap-1 lg:gap-2" ]
        [ a
            [ id "snap-home"
            , href "/"
            , class "mr-1 shrink-0 transition hover:-translate-y-0.5 active:translate-y-0 lg:mr-0"
            ]
            [ img [ src "/images/mark.svg", alt "octomocto", class "h-8 w-auto dark:hidden lg:h-9" ] []
            , img [ src "/images/mark-on-dark.svg", alt "octomocto", class "hidden h-8 w-auto dark:block lg:h-9" ] []
            ]
        , h1 [ class "text-xl font-semibold tracking-tight lg:text-2xl" ]
            [ a [ id "snap-title-link", href model.settingsUrl, class "transition hover:text-octo-indigo dark:hover:text-octo-indigo-light" ] [ text "Snap" ] ]
        , viewMuteButton model.muted
        , if me == Nothing then
            text ""

          else
            button
                [ id "snap-restart"
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
        [ id "snap-mute"
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


{-| The time left, the score, and the multiplier with the correct answers
in a row to the next one
-}
viewStats : Model -> Game -> Html Msg
viewStats model game =
    let
        progress =
            model.progress

        leftMs =
            case phase model game of
                Play ->
                    playStart game + game.playMs - elapsed model

                Countdown ->
                    game.playMs

                Preview _ ->
                    game.playMs

                _ ->
                    0

        seconds =
            (leftMs + 999) // 1000

        current =
            multiplier game progress.streak

        filled =
            if current == game.maxMultiplier then
                game.streakStep

            else
                modBy game.streakStep progress.streak

        stat label content =
            div [ class "flex flex-col items-center justify-center gap-0.5 px-2" ]
                [ span [ class "text-[0.625rem] font-medium tracking-wide text-slate-400 uppercase lg:text-xs" ] [ text label ]
                , content
                ]
    in
    div [ id "snap-stats", class "grid grid-cols-3 divide-x divide-slate-200 rounded-2xl bg-white py-3 shadow-sm ring-1 ring-slate-200 dark:divide-white/10 dark:bg-white/5 dark:shadow-none dark:ring-white/10" ]
        [ stat "time"
            (span
                [ id "snap-time"
                , class "text-2xl leading-tight font-light tabular-nums lg:text-3xl"
                , classList
                    [ ( "text-slate-700 dark:text-slate-100", seconds > 5 )
                    , ( "text-red-500", seconds <= 5 )
                    ]
                ]
                [ text ("0:" ++ String.padLeft 2 '0' (String.fromInt seconds)) ]
            )
        , stat "score"
            (span [ id "snap-score", class "text-2xl leading-tight font-bold text-octo-indigo tabular-nums lg:text-3xl dark:text-octo-indigo-light" ]
                [ text (String.fromInt progress.score) ]
            )
        , stat "multiplier"
            (div [ class "flex flex-col items-center gap-1" ]
                [ Html.Keyed.node "span"
                    []
                    [ ( String.fromInt current
                      , span [ id "snap-multiplier", class "snap-multiplier text-2xl leading-tight font-semibold tabular-nums lg:text-3xl" ]
                            [ text ("×" ++ String.fromInt current) ]
                      )
                    ]
                , div [ class "flex gap-1" ]
                    (List.map
                        (\i ->
                            span
                                [ class "size-1.5 rounded-full transition-colors"
                                , classList
                                    [ ( "bg-octo-indigo dark:bg-octo-indigo-light", i < filled )
                                    , ( "bg-slate-200 dark:bg-white/15", i >= filled )
                                    ]
                                ]
                                []
                        )
                        (List.range 0 (game.streakStep - 1))
                    )
                ]
            )
        ]


{-| The question, the card, and the answer buttons, with the covers of the
countdown and the end over them
-}
viewTable : Model -> Game -> Html Msg
viewTable model game =
    let
        current =
            phase model game

        index =
            case current of
                Preview i ->
                    Just i

                Play ->
                    Just (game.back + answered model.progress)

                _ ->
                    Nothing

        shape =
            index |> Maybe.andThen (\i -> Array.get i game.cards)
    in
    div [ class "relative flex flex-col items-center gap-5 pt-2" ]
        [ p [ id "snap-question", class "h-7 text-center text-lg font-medium text-slate-600 dark:text-slate-300" ]
            [ text (question game current) ]
        , div [ class "relative" ]
            [ Html.Keyed.node "div"
                [ class "snap-stage" ]
                [ ( Maybe.withDefault "empty" (Maybe.map String.fromInt index)
                  , case shape of
                        Just s ->
                            div [ id "snap-card", class "snap-card" ] [ viewShape s ]

                        Nothing ->
                            div [ class "snap-card is-empty" ] []
                  )
                ]
            , Html.Keyed.node "div"
                [ class "pointer-events-none absolute -top-3 -right-3" ]
                [ case ( current, model.feedback ) of
                    ( Play, Just feedback ) ->
                        ( String.fromInt feedback.count, viewFeedback feedback )

                    _ ->
                        ( "none", text "" )
                ]
            ]
        , viewButtons (current == Play)
        , case current of
            Countdown ->
                viewCountdown (Maybe.withDefault 0 (countdownStep model game))

            TimeUp ->
                div [ id "snap-time-up", class "absolute inset-0 flex items-center justify-center rounded-2xl bg-octo-navy/70 backdrop-blur-sm" ]
                    [ p [ class "text-3xl font-semibold text-white" ] [ text "Time's up!" ] ]

            Over ->
                viewResult model game

            _ ->
                text ""
        ]


question : Game -> Phase -> String
question game current =
    case current of
        Preview i ->
            if game.back == 1 then
                "Remember this card"

            else
                "Remember this card (" ++ String.fromInt (i + 1) ++ " of " ++ String.fromInt game.back ++ ")"

        Play ->
            if game.back == 1 then
                "Same as the card before?"

            else
                "Same as " ++ String.fromInt game.back ++ " cards back?"

        _ ->
            ""


viewFeedback : Feedback -> Html Msg
viewFeedback feedback =
    span
        [ id "snap-feedback"
        , class "snap-feedback grid size-10 place-items-center rounded-full text-white shadow-lg"
        , classList [ ( "bg-emerald-500", feedback.correct ), ( "bg-red-500", not feedback.correct ) ]
        ]
        [ span
            [ class
                (if feedback.correct then
                    "hero-check-solid size-6"

                 else
                    "hero-x-mark-solid size-6"
                )
            ]
            []
        ]


viewButtons : Bool -> Html Msg
viewButtons enabled =
    let
        answerButton buttonId same label key =
            button
                [ id buttonId
                , class "flex flex-1 items-center justify-center gap-3 rounded-2xl py-4 text-lg font-semibold shadow-sm ring-1 transition active:scale-95 disabled:cursor-not-allowed disabled:opacity-40 disabled:active:scale-100"
                , classList
                    [ ( "bg-octo-indigo text-white ring-octo-indigo hover:bg-octo-indigo/90", same )
                    , ( "bg-white text-slate-700 ring-slate-200 hover:bg-slate-50 dark:bg-white/5 dark:text-slate-100 dark:ring-white/15 dark:hover:bg-white/10", not same )
                    ]
                , disabled (not enabled)
                , onClick (Answer same)
                ]
                (if same then
                    [ text label, viewKey key ]

                 else
                    [ viewKey key, text label ]
                )
    in
    div [ class "flex w-full max-w-sm gap-3" ]
        [ answerButton "snap-no" False "No" "←"
        , answerButton "snap-yes" True "Yes" "→"
        ]


{-| The arrow key of an answer, only on a screen that is large enough for
a keyboard
-}
viewKey : String -> Html Msg
viewKey key =
    kbd [ class "hidden rounded-md px-1.5 text-sm font-medium ring-1 ring-current/30 opacity-70 lg:inline" ] [ text key ]


{-| The shapes of the cards, on a view box from -50 to 50
-}
viewShape : Shape -> Html Msg
viewShape shape =
    let
        polygon points =
            Svg.polygon [ SA.points (String.join " " (List.map (\( x, y ) -> String.fromFloat x ++ "," ++ String.fromFloat y) points)) ] []

        around count radius turn =
            List.map
                (\i ->
                    let
                        angle =
                            degrees (turn + toFloat i * 360 / toFloat count)
                    in
                    ( radius i * cos angle, radius i * sin angle )
                )
                (List.range 0 (count - 1))

        path d =
            Svg.path [ SA.d d ] []

        body =
            case shape of
                0 ->
                    Svg.circle [ SA.r "31" ] []

                1 ->
                    Svg.rect [ SA.x "-27", SA.y "-27", SA.width "54", SA.height "54", SA.rx "5" ] []

                2 ->
                    polygon (around 3 (\_ -> 36) -90 |> List.map (\( x, y ) -> ( x, y + 6 )))

                3 ->
                    polygon
                        (around 10
                            (\i ->
                                if modBy 2 i == 0 then
                                    37

                                else
                                    15
                            )
                            -90
                            |> List.map (\( x, y ) -> ( x, y + 3 ))
                        )

                4 ->
                    path "M-11-33H11V-11H33V11H11V33H-11V11H-33V-11H-11Z"

                5 ->
                    path "M0 31C-42 4-36-31-17-31-7-31 0-23 0-16 0-23 7-31 17-31 36-31 42 4 0 31Z"

                6 ->
                    polygon (around 6 (\_ -> 32) 0)

                _ ->
                    path "M20-30.4A32 32 0 1 0 20 30.4 34 34 0 0 1 20-30.4Z"
    in
    Svg.svg
        [ SA.viewBox "-50 -50 100 100"
        , SA.class "snap-shape size-full"
        , attribute "aria-label" (shapeName shape)
        , attribute "role" "img"
        ]
        [ body ]


shapeName : Shape -> String
shapeName shape =
    Array.fromList [ "circle", "square", "triangle", "star", "plus", "heart", "hexagon", "moon" ]
        |> Array.get shape
        |> Maybe.withDefault "shape"


{-| The number is keyed, so that it pops in again on each step.
-}
viewCountdown : Int -> Html Msg
viewCountdown seconds =
    div
        [ id "snap-countdown"
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
        progress =
            model.progress

        total =
            answered progress

        accuracy =
            if total == 0 then
                "–"

            else
                String.fromInt (round (100 * toFloat progress.correct / toFloat total)) ++ "%"
    in
    div
        [ id "snap-result"
        , class "absolute inset-0 z-10 flex flex-col items-center justify-center gap-4 rounded-2xl bg-octo-navy/80 p-4 text-center text-white backdrop-blur-sm"
        ]
        [ p [ class "text-lg opacity-80" ] [ text "Time's up!" ]
        , p [ id "snap-final-score", class "text-6xl font-bold tabular-nums" ] [ text (String.fromInt progress.score) ]
        , p [ id "snap-final-answers", class "text-sm tabular-nums opacity-80" ]
            [ text (String.fromInt progress.correct ++ " of " ++ String.fromInt total ++ " correct · " ++ accuracy) ]
        , button
            [ id "snap-play-again"
            , class "rounded-full bg-white px-6 py-2.5 font-medium text-octo-indigo shadow-lg transition hover:-translate-y-0.5 hover:bg-octo-mist active:translate-y-0"
            , onClick Restart
            ]
            [ text "Play again" ]
        , a
            [ id "snap-leaderboards-link"
            , href model.settingsUrl
            , class "text-sm font-medium text-white/80 underline-offset-4 transition hover:text-white hover:underline"
            ]
            [ text "Best results" ]
        , a
            [ id "snap-next-game"
            , href model.nextGame.path
            , attribute "data-ga-link" "or_try"
            , attribute "data-ga-from" "Snap"
            , attribute "data-ga-to" model.nextGame.name
            , class "group text-sm font-medium text-white underline-offset-4 transition hover:underline"
            ]
            [ text ("Or try " ++ model.nextGame.name ++ " ")
            , span [ class "inline-block transition group-hover:translate-x-0.5" ] [ text "→" ]
            ]
        , if model.guest then
            p [ id "snap-sign-in", class "text-sm text-white/70" ]
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
    p [ id "snap-feed", class "mt-2 max-w-sm border-t border-white/15 pt-4 text-center text-sm leading-10 text-balance text-white/80" ]
        [ text "Enjoying Octomocto? "
        , a
            [ href "https://patreon.com/mxgrn"
            , target "_blank"
            , rel "noopener"
            , class "group mx-1 inline-flex items-center gap-1.5 whitespace-nowrap rounded-full bg-octo-orange px-4 py-1.5 align-middle leading-5 font-semibold text-white shadow-lg shadow-octo-orange/30 transition hover:-translate-y-0.5 hover:bg-octo-orange-light active:translate-y-0"
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
