port module InkTrail exposing (main)

{-| Ink Trail: follow the path of a leader octopus, some jets behind it.

A leader octopus jets between caves on a random path. The player's
octopus follows the same path, `leader - follower` jets behind: the
distance. At the start, after the countdown, the leader makes its first
jets alone, and the player watches. Then, at each tap, the player picks
the next cave for the player's octopus, and the leader jets once more.
The player sees only the two octopi, so the player must remember the path
between them.

Each 5 correct taps in a row make the leader jet once more, so the
distance grows. A wrong tap makes the distance one smaller: the player's
octopus goes to the correct cave, and the leader waits (at the distance 2,
it jets). The game ends after 40 correct taps.

The server gives the whole path. This module checks each tap itself, for
the score on the screen, and sends it out through a port. The server
checks it again and saves the score at the end. app.js connects the ports
to a Phoenix channel.

The octopi and their ink are drawn again at each animation frame from the
times of their jets (see `pose` and `viewInk`), so the page keeps no
animation state.

Ink Trail is a single-player game. A browser that joins a game that has
its player only watches: it has no player id.

-}

import Array exposing (Array)
import Browser
import Browser.Events
import Html exposing (Html, a, button, div, h1, img, p, span, text)
import Html.Attributes exposing (alt, attribute, class, classList, href, id, rel, src, style, target)
import Html.Events exposing (onClick)
import Html.Keyed
import Html.Lazy
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Press
import Svg exposing (Svg, svg)
import Svg.Attributes as SA
import Task
import Time



-- PORTS


port inkTrailTap : Encode.Value -> Cmd msg


port inkTrailRestart : () -> Cmd msg


port inkTrailJoined : (Decode.Value -> msg) -> Sub msg


port inkTrailState : (Decode.Value -> msg) -> Sub msg


port inkTrailJoinFailed : (String -> msg) -> Sub msg


port inkTrailPlaySound : String -> Cmd msg


port inkTrailSaveMuted : Bool -> Cmd msg



-- MODEL


type alias Player =
    { id : String
    , score : Int
    }


type alias Game =
    { -- Tells a new game from the old one
      field : String

    -- Empty before the start and during the countdown
    , path : List Int
    , leader : Int
    , follower : Int
    , goal : Int
    , points : Int
    , streakStep : Int
    , maxDistance : Int
    , correct : Int
    , wrong : Int
    , streak : Int
    , bestDistance : Int
    , lastDistance : Int
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


{-| One jet of an octopus from a cave to a cave, which starts at the local
time `at`
-}
type alias Jet =
    { from : Int
    , to : Int
    , at : Int
    }


{-| The game on the screen, with the taps of the player as this page counts
them. The times are local times in ms.
-}
type alias Trail =
    { field : String
    , path : Array Int
    , leader : Int
    , follower : Int
    , streak : Int
    , correct : Int
    , wrong : Int
    , bestDistance : Int
    , score : Int

    -- The leader on the screen jets from the index `leaderFrom` of the
    -- path, first at `leaderAt`, and then each time a short stop after it
    -- landed, up to `leader`
    , leaderFrom : Int
    , leaderAt : Int

    -- The last jets of the leader before `leaderFrom`, and the last jet of
    -- the player's octopus: their ink and their landing still show
    , leaderPast : List Jet
    , followerPast : List Jet

    -- The last correct tap, and the last wrong tap: the cave and the time
    , hit : Maybe ( Int, Int )
    , miss : Maybe ( Int, Int )

    -- The last time when the distance grew
    , grewAt : Maybe Int
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
    , trail : Maybe Trail

    -- A phone screen has a taller sea, with another place for each cave
    -- (see the CSS of `.ink-trail-sea`)
    , narrow : Bool

    -- The local time (in ms) when the game of the server started, and the
    -- local time now
    , clockStart : Int
    , now : Int

    -- The countdown step that last played its beep (see `countdownStep`)
    , beepedStep : Maybe Int

    -- The leader on the screen when the last jet sound played
    , jetCue : Maybe ( String, Int )
    , muted : Bool
    }


type alias Flags =
    { settingsUrl : String
    , nextGame : NextGame
    , guest : Bool
    , muted : Bool
    , narrow : Bool
    }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { settingsUrl = flags.settingsUrl
      , nextGame = flags.nextGame
      , guest = flags.guest
      , connection = Connecting
      , trail = Nothing
      , narrow = flags.narrow
      , clockStart = 0
      , now = 0
      , beepedStep = Nothing
      , jetCue = Nothing
      , muted = flags.muted
      }
    , Cmd.none
    )


{-| The first jets of the leader at the start come after a short pause
-}
introDelayMs : Int
introDelayMs =
    600


{-| One jet from a cave to a cave. All jets take the same time: a long jet
is faster.
-}
jetMs : Int
jetMs =
    560


{-| When the leader jets more than once in a row (at the start, and when
the distance grows), it stops this long at each cave between the jets
-}
stopMs : Int
stopMs =
    150


{-| At the start of a jet, the octopus turns to the next cave in this time
-}
turnMs : Float
turnMs =
    110


{-| At the end of the last jet, the octopus turns back up and spreads its
arms in this time
-}
settleMs : Float
settleMs =
    450


{-| How far the arms open at a stop between two jets (1 is the full
spread of an octopus that sits)
-}
stopSpread : Float
stopSpread =
    0.35


{-| After a tap, the player's octopus jets first, and the leader jets this
long after the player's octopus lands (or when its new cave comes from the
server, if later)
-}
leaderPauseMs : Int
leaderPauseMs =
    300


{-| After a wrong tap, the correct cave shows for this long, and the
player cannot tap
-}
missMs : Int
missMs =
    800


{-| The end of the game shows for a moment before the result
-}
endMs : Int
endMs =
    900


{-| The sea is 400 units wide. It is 300 units high on a wide screen
(4:3), and 500 units high on a phone (4:5).
-}
seaHeight : Bool -> Float
seaHeight narrow =
    if narrow then
        500

    else
        300


{-| Where the caves are in the sea: the middle of the bottom of each cave,
in units. A wide sea has 3 rows of 4 caves, and a phone has 4 rows of 3.
-}
caves : Bool -> Array ( Float, Float )
caves narrow =
    if narrow then
        Array.fromList
            [ ( 68, 102 )
            , ( 198, 96 )
            , ( 330, 104 )
            , ( 82, 222 )
            , ( 210, 216 )
            , ( 338, 226 )
            , ( 66, 344 )
            , ( 196, 338 )
            , ( 326, 348 )
            , ( 84, 466 )
            , ( 212, 460 )
            , ( 338, 468 )
            ]

    else
        Array.fromList
            [ ( 46, 92 )
            , ( 144, 84 )
            , ( 242, 94 )
            , ( 340, 86 )
            , ( 72, 188 )
            , ( 170, 180 )
            , ( 266, 190 )
            , ( 360, 182 )
            , ( 46, 284 )
            , ( 144, 278 )
            , ( 242, 286 )
            , ( 340, 280 )
            ]


caveCount : Int
caveCount =
    12


caveBase : Bool -> Int -> ( Float, Float )
caveBase narrow cave =
    Array.get cave (caves narrow) |> Maybe.withDefault ( 200, 150 )


{-| Where an octopus is when it sits at the cave: in the entrance, a bit
above the sand
-}
home : Bool -> Int -> ( Float, Float )
home narrow cave =
    let
        ( x, y ) =
            caveBase narrow cave
    in
    ( x, y - 11 )



-- UPDATE


type Msg
    = GotJoined Decode.Value
    | GotState Decode.Value
    | GotJoinFailed String
    | Tap Int
    | Restart
    | SyncClock Int Time.Posix
    | Tick Time.Posix
    | ToggleMuted
    | Resized Int


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

        Tap cave ->
            case ( model.connection, model.trail ) of
                ( Joined (Just _) game, Just trail ) ->
                    if canTap model.now trail then
                        tap game cave trail model

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        Restart ->
            ( model, inkTrailRestart () )

        SyncClock elapsedMs time ->
            let
                ms =
                    Time.posixToMillis time
            in
            onTick { model | clockStart = ms - elapsedMs, now = ms }

        Tick time ->
            onTick { model | now = Time.posixToMillis time }

        ToggleMuted ->
            ( { model | muted = not model.muted }, inkTrailSaveMuted (not model.muted) )

        -- The same width as the `40rem` of the CSS
        Resized width ->
            ( { model | narrow = width <= 640 }, Cmd.none )


serverScore : Game -> Int
serverScore game =
    List.head game.players |> Maybe.map .score |> Maybe.withDefault 0


{-| Takes a new game from the server, and the taps of another browser of
the player (or of the player, for a watcher). During the game, the page is
ahead of the server, so it keeps its own copy, but the new caves of the
leader come from the server. When they come late, the leader jets from
now on, one jet at a time.
-}
sync : Game -> Model -> Model
sync game model =
    case model.trail of
        Just trail ->
            if trail.field /= game.field then
                { model | trail = Nothing, beepedStep = Nothing, jetCue = Nothing }

            else if game.follower > trail.follower then
                let
                    server =
                        trailFrom game model.clockStart model.now

                    past =
                        keepPast model.now trail
                in
                { model
                    | trail =
                        Just
                            { server
                                | leaderFrom = shownLeader model.now trail
                                , leaderAt = model.now
                                , leaderPast = past.leaderPast
                                , followerPast =
                                    [ { from = caveAt trail trail.follower
                                      , to = caveAt server game.follower
                                      , at = model.now
                                      }
                                    ]
                                , endedAt =
                                    if game.finished then
                                        Just model.now

                                    else
                                        Nothing
                            }
                }

            else if List.length game.path > Array.length trail.path then
                let
                    shown =
                        shownLeader model.now trail

                    late =
                        shown < dueLeader model.now trail

                    withPath =
                        { trail | path = Array.fromList game.path }
                in
                { model
                    | trail =
                        Just
                            (if late then
                                { withPath
                                    | leaderFrom = shown
                                    , leaderAt = model.now
                                    , leaderPast = (keepPast model.now trail).leaderPast
                                }

                             else
                                withPath
                            )
                }

            else
                model

        Nothing ->
            model


{-| Keeps the last jets of the leader that started, before the page
changes when the leader jets next
-}
keepPast : Int -> Trail -> Trail
keepPast now trail =
    let
        started =
            List.filter (\jet -> jet.at <= now) (leaderJets trail)
    in
    { trail | leaderPast = List.drop (List.length started - 2) started }


{-| The game of the server, shown from the local time `now`. A new game
starts with the first jets of the leader after the countdown, at the
local time `clockStart`.
-}
trailFrom : Game -> Int -> Int -> Trail
trailFrom game clockStart now =
    let
        new =
            game.correct == 0 && game.wrong == 0
    in
    { field = game.field
    , path = Array.fromList game.path
    , leader = game.leader
    , follower = game.follower
    , streak = game.streak
    , correct = game.correct
    , wrong = game.wrong
    , bestDistance = game.bestDistance
    , score = serverScore game
    , leaderFrom =
        -- At the start, the leader is one jet ahead
        if new then
            game.follower + 1

        else
            game.leader
    , leaderAt =
        if new then
            clockStart + introDelayMs

        else
            now
    , leaderPast = []
    , followerPast = []
    , hit = Nothing
    , miss = Nothing
    , grewAt = Nothing
    , endedAt =
        if game.finished then
            Just 0

        else
            Nothing
    }


{-| The cave at the index of the path
-}
caveAt : Trail -> Int -> Int
caveAt trail index =
    Array.get index trail.path |> Maybe.withDefault 0


{-| The local times when the next jets of the leader start. Each jet
starts a short stop after the jet before it landed.
-}
jetTimes : Trail -> List Int
jetTimes trail =
    List.range 0 (trail.leader - trail.leaderFrom - 1)
        |> List.map (\i -> trail.leaderAt + i * (jetMs + stopMs))


{-| The jets of the leader: the last ones before `leaderFrom`, then the
ones from `leaderFrom`, also the ones that did not start yet. The page
knows a jet only when the server gave its cave.
-}
leaderJets : Trail -> List Jet
leaderJets trail =
    trail.leaderPast
        ++ List.filterMap
            (\( index, at ) ->
                if index < Array.length trail.path then
                    Just { from = caveAt trail (index - 1), to = caveAt trail index, at = at }

                else
                    Nothing
            )
            (List.map2 Tuple.pair (List.range (trail.leaderFrom + 1) trail.leader) (jetTimes trail))


{-| The index of the path where the leader would be on the screen by its
times
-}
dueLeader : Int -> Trail -> Int
dueLeader now trail =
    min trail.leader
        (trail.leaderFrom + List.length (List.filter (\at -> at <= now) (jetTimes trail)))


{-| The index of the path where the leader is on the screen. The server
picks each new cave of the leader, so the leader waits for its cave.
-}
shownLeader : Int -> Trail -> Int
shownLeader now trail =
    min (dueLeader now trail) (Array.length trail.path - 1)


{-| The local time when the leader lands at its last cave
-}
leaderLandsAt : Trail -> Int
leaderLandsAt trail =
    case List.reverse (jetTimes trail) of
        last :: _ ->
            last + jetMs

        [] ->
            0


{-| The first jets of the leader at the start
-}
watchingIntro : Int -> Trail -> Bool
watchingIntro now trail =
    trail.correct == 0 && trail.wrong == 0 && shownLeader now trail < trail.leader


{-| The player can tap when the leader landed and the correct cave of a
wrong tap is gone
-}
canTap : Int -> Trail -> Bool
canTap now trail =
    trail.endedAt
        == Nothing
        && shownLeader now trail
        == trail.leader
        && now
        >= leaderLandsAt trail
        && (case trail.miss of
                Just ( _, at ) ->
                    now - at >= missMs

                Nothing ->
                    True
           )


distance : Trail -> Int
distance trail =
    trail.leader - trail.follower


{-| Checks the tap at once, and sends it to the server
-}
tap : Game -> Int -> Trail -> Model -> ( Model, Cmd Msg )
tap game cave trail model =
    let
        now =
            model.now

        step =
            trail.follower + 1

        send =
            inkTrailTap (Encode.object [ ( "step", Encode.int step ), ( "cave", Encode.int cave ) ])

        gap =
            distance trail

        -- The player's octopus jets to the correct cave, also after a
        -- wrong tap
        past =
            keepPast now trail

        moved =
            { past
                | follower = step
                , leaderFrom = trail.leader
                , followerPast = [ { from = caveAt trail trail.follower, to = caveAt trail step, at = now } ]
            }
    in
    if Array.get step trail.path == Just cave then
        let
            streak =
                trail.streak + 1

            grow =
                modBy game.streakStep streak == 0 && gap < game.maxDistance

            jets =
                if grow then
                    2

                else
                    1

            correct =
                trail.correct + 1

            done =
                correct >= game.goal
        in
        ( { model
            | trail =
                Just
                    { moved
                        | leader = trail.leader + jets
                        , streak =
                            if grow then
                                0

                            else
                                streak
                        , correct = correct
                        , score = trail.score + game.points * gap
                        , bestDistance = max trail.bestDistance (gap - 1 + jets)

                        -- The leader jets a moment after the player's octopus lands
                        , leaderAt = now + jetMs + leaderPauseMs
                        , hit = Just ( cave, now )
                        , grewAt =
                            if grow then
                                Just now

                            else
                                trail.grewAt
                        , endedAt =
                            if done then
                                Just now

                            else
                                Nothing
                    }
          }
        , Cmd.batch
            [ send
            , playSounds model
                ("follow"
                    :: (if grow && not done then
                            [ "grow" ]

                        else
                            []
                       )
                )
            ]
        )

    else
        let
            -- The distance is never less than 2
            jets =
                if gap > 2 then
                    0

                else
                    1
        in
        ( { model
            | trail =
                Just
                    { moved
                        | leader = trail.leader + jets
                        , streak = 0
                        , wrong = trail.wrong + 1
                        , leaderAt = now + missMs
                        , miss = Just ( cave, now )
                    }
          }
        , Cmd.batch [ send, playSounds model [ "wrong" ] ]
        )


type Phase
    = Countdown
    | Playing Trail
    | Over


{-| The page shows the end of its game before the result
-}
phase : Model -> Game -> Phase
phase model game =
    case model.trail of
        Just trail ->
            if game.finished && canLeave model trail then
                Over

            else
                Playing trail

        Nothing ->
            if game.finished then
                Over

            else
                Countdown


canLeave : Model -> Trail -> Bool
canLeave model trail =
    case trail.endedAt of
        Just endedAt ->
            model.now - endedAt >= endMs

        -- The server finished without this page, for example in another tab
        Nothing ->
            True


{-| The time since the start of the game, in ms. Below zero during the
countdown.
-}
elapsed : Model -> Int
elapsed model =
    model.now - model.clockStart


{-| Starts the game on the screen after the countdown (or the game of the
server after a reload), and plays the beeps of the countdown, the jets of
the leader, and the end.
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

                trail =
                    case model.trail of
                        Nothing ->
                            if not game.waiting && not (List.isEmpty game.path) && elapsed model >= 0 then
                                Just (trailFrom game model.clockStart model.now)

                            else
                                Nothing

                        Just current ->
                            Just current

                ( jetCue, jetSounds ) =
                    case trail of
                        Just current ->
                            let
                                cue =
                                    Just ( current.field, shownLeader model.now current )
                            in
                            if cue == model.jetCue then
                                ( model.jetCue, [] )

                            else
                                case model.jetCue of
                                    Just ( field, _ ) ->
                                        if field == current.field then
                                            ( cue, [ "jet" ] )

                                        else
                                            ( cue, [] )

                                    -- No sound for the leader at the start
                                    Nothing ->
                                        ( cue, [] )

                        Nothing ->
                            ( model.jetCue, [] )

                ended =
                    game.finished && phase model game /= Over && phase { model | trail = trail } game == Over
            in
            ( { model | beepedStep = step, trail = trail, jetCue = jetCue }
            , playSounds model
                (beeps
                    ++ jetSounds
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
        Cmd.batch (List.map inkTrailPlaySound names)


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
        |> andMap (Decode.field "path" (Decode.list Decode.int))
        |> andMap (Decode.field "leader" Decode.int)
        |> andMap (Decode.field "follower" Decode.int)
        |> andMap (Decode.field "goal" Decode.int)
        |> andMap (Decode.field "points" Decode.int)
        |> andMap (Decode.field "streak_step" Decode.int)
        |> andMap (Decode.field "max_distance" Decode.int)
        |> andMap (Decode.field "correct" Decode.int)
        |> andMap (Decode.field "wrong" Decode.int)
        |> andMap (Decode.field "streak" Decode.int)
        |> andMap (Decode.field "best_distance" Decode.int)
        |> andMap (Decode.field "last_distance" Decode.int)
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
        [ inkTrailJoined GotJoined
        , inkTrailState GotState
        , inkTrailJoinFailed GotJoinFailed
        , Browser.Events.onResize (\width _ -> Resized width)
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
            p [ id "ink-trail-connecting", class "py-24 text-center opacity-60" ] [ text "Joining the game…" ]

        Failed reason ->
            p [ id "ink-trail-failed", class "py-24 text-center text-red-600" ] [ text ("Could not join the game: " ++ reason) ]

        Joined me game ->
            div
                [ id "ink-trail-root"
                , class "mx-auto flex w-full max-w-2xl flex-col gap-4 select-none"

                -- The page does not scroll during the game
                , classList [ ( "is-playing", me /= Nothing && phase model game /= Over ) ]
                ]
                [ viewHeader model me
                , viewStats model game
                , viewBoard model (me == Nothing) game
                ]


viewHeader : Model -> Me -> Html Msg
viewHeader model me =
    div [ class "flex items-center gap-1 lg:gap-2" ]
        [ a
            [ id "ink-trail-home"
            , href "/"
            , class "mr-1 shrink-0 transition lg:mr-0"
            ]
            [ img [ src "/images/mark.svg", alt "octomocto", class "h-8 w-auto dark:hidden lg:h-9" ] []
            , img [ src "/images/mark-on-dark.svg", alt "octomocto", class "hidden h-8 w-auto dark:block lg:h-9" ] []
            ]
        , h1 [ class "text-xl font-semibold tracking-tight lg:text-2xl" ]
            [ a [ id "ink-trail-title-link", href model.settingsUrl, class "transition hover:text-octo-indigo dark:hover:text-octo-indigo-light" ] [ text "Ink Trail" ] ]
        , if me == Nothing then
            span
                [ id "ink-trail-watching"
                , class "flex shrink-0 items-center text-octo-indigo dark:text-octo-indigo-light"
                , Html.Attributes.title "You are watching this game."
                ]
                [ span [ class "hero-eye size-4" ] [] ]

          else
            text ""
        , viewMuteButton model.muted
        , if me == Nothing then
            text ""

          else
            button
                [ id "ink-trail-restart"
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
        [ id "ink-trail-mute"
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


{-| The correct taps with a progress bar, the score, and the distance with
a dot for each correct tap in a row
-}
viewStats : Model -> Game -> Html Msg
viewStats model game =
    let
        ( correct, gap, streak ) =
            case model.trail of
                Just trail ->
                    ( trail.correct, distance trail, trail.streak )

                Nothing ->
                    ( game.correct, game.leader - game.follower, game.streak )

        score =
            Maybe.map .score model.trail |> Maybe.withDefault (serverScore game)

        stat label content =
            div [ class "flex flex-col items-center justify-center gap-0.5 px-2" ]
                [ span [ class "text-[0.625rem] font-medium tracking-wide text-slate-400 uppercase lg:text-xs" ] [ text label ]
                , content
                ]
    in
    div [ id "ink-trail-stats", class "grid grid-cols-3 divide-x divide-slate-200 rounded-2xl bg-white py-3 shadow-sm ring-1 ring-slate-200 dark:divide-white/10 dark:bg-white/5 dark:shadow-none dark:ring-white/10" ]
        [ stat "jets"
            (div [ class "flex w-full max-w-24 flex-col items-center gap-1.5" ]
                [ span [ id "ink-trail-correct", class "text-2xl leading-tight font-light tabular-nums lg:text-3xl" ]
                    [ text (String.fromInt correct ++ "/" ++ String.fromInt game.goal) ]
                , div [ class "h-1 w-full overflow-hidden rounded-full bg-slate-200 dark:bg-white/15" ]
                    [ div
                        [ class "h-full rounded-full bg-octo-indigo transition-[width] duration-300 dark:bg-octo-indigo-light"
                        , style "width" (String.fromFloat (100 * toFloat correct / toFloat (max 1 game.goal)) ++ "%")
                        ]
                        []
                    ]
                ]
            )
        , stat "score"
            (span [ id "ink-trail-score", class "text-2xl leading-tight font-bold text-octo-indigo tabular-nums lg:text-3xl dark:text-octo-indigo-light" ]
                [ text (String.fromInt score) ]
            )
        , stat "distance"
            (div [ class "flex flex-col items-center gap-1" ]
                [ Html.Keyed.node "span"
                    []
                    [ ( String.fromInt gap
                      , span [ id "ink-trail-distance", class "countdown-pop inline-block text-2xl leading-tight font-semibold tabular-nums lg:text-3xl" ]
                            [ text (String.fromInt gap) ]
                      )
                    ]
                , viewStreak game.streakStep streak
                ]
            )
        ]


{-| A dot for each correct tap in a row: when all dots are full, the
distance grows
-}
viewStreak : Int -> Int -> Html Msg
viewStreak steps streak =
    div [ id "ink-trail-streak", class "flex gap-1", Html.Attributes.title "Correct in a row" ]
        (List.map
            (\i ->
                span
                    [ class "ink-trail-dot size-1.5 rounded-full"
                    , classList
                        [ ( "bg-octo-indigo dark:bg-octo-indigo-light is-on", i <= streak )
                        , ( "bg-slate-200 dark:bg-white/15", i > streak )
                        ]
                    ]
                    []
            )
            (List.range 1 steps)
        )


{-| The prompt and the sea, with the covers of the countdown and the end
over them. A watcher sees the same sea, but it cannot tap the caves.
-}
viewBoard : Model -> Bool -> Game -> Html Msg
viewBoard model watching game =
    let
        current =
            phase model game
    in
    div [ class "relative flex flex-col items-center gap-4 pt-1" ]
        [ p [ id "ink-trail-prompt", class "h-7 text-center text-lg font-medium text-slate-600 dark:text-slate-300" ]
            [ text (prompt model watching current) ]
        , div [ id "ink-trail-sea", class "ink-trail-sea" ]
            (case model.trail of
                Just trail ->
                    [ viewCaves model watching (current /= Over) trail
                    , viewSwimmers model.narrow model.now trail
                    ]

                Nothing ->
                    [ Html.Lazy.lazy6 viewCaveButtons model.narrow False -1 -1 -1 -1 ]
            )
        , case current of
            Countdown ->
                viewCountdown (Maybe.withDefault 0 (countdownStep model game))

            Over ->
                viewResult model watching game

            _ ->
                text ""
        ]


prompt : Model -> Bool -> Phase -> String
prompt model watching current =
    case current of
        Playing trail ->
            let
                now =
                    model.now

                jets n =
                    if n == 1 then
                        "1 jet"

                    else
                        String.fromInt n ++ " jets"
            in
            if trail.endedAt /= Nothing then
                "Well followed!"

            else if watchingIntro now trail then
                "Watch the leader"

            else if Maybe.map (\( _, at ) -> now - at < missMs) trail.miss == Just True then
                "Missed. Your octopus goes here"

            else if Maybe.map (\at -> now - at < 1200) trail.grewAt == Just True then
                "One jet further behind!"

            else if watching then
                "The player follows " ++ jets (distance trail) ++ " behind"

            else
                "Follow " ++ jets (distance trail) ++ " behind"

        _ ->
            ""


{-| The caves, with the state of the last tap. The caves change only at a
tap, so they are drawn again only then.
-}
viewCaves : Model -> Bool -> Bool -> Trail -> Html Msg
viewCaves model watching active trail =
    let
        now =
            model.now

        recent maybe ms =
            case maybe of
                Just ( cave, at ) ->
                    if now - at < ms then
                        cave

                    else
                        -1

                Nothing ->
                    -1

        missed =
            recent trail.miss missMs

        answer =
            if missed >= 0 then
                caveAt trail trail.follower

            else
                -1
    in
    Html.Lazy.lazy6 viewCaveButtons
        model.narrow
        (active && not watching && canTap now trail)
        (recent trail.hit 400)
        missed
        answer
        (Array.length trail.path)


{-| A button for each cave, in the order of their rows, so that a lower
cave covers the cave above it. The last argument only tells Html.Lazy when
the path grows.
-}
viewCaveButtons : Bool -> Bool -> Int -> Int -> Int -> Int -> Html Msg
viewCaveButtons narrow open hit missed answer _ =
    let
        height =
            seaHeight narrow

        cave i =
            let
                ( x, y ) =
                    caveBase narrow i
            in
            ( String.fromInt i
            , button
                [ id ("ink-trail-cave-" ++ String.fromInt i)
                , class "ink-trail-cave"
                , classList
                    [ ( "is-open", open )
                    , ( "is-hit", hit == i )
                    , ( "is-miss", missed == i )
                    , ( "is-answer", answer == i )
                    ]
                , style "left" (String.fromFloat (x / 4) ++ "%")
                , style "top" (String.fromFloat (100 * y / height) ++ "%")
                , attribute "aria-label" ("Cave " ++ String.fromInt (i + 1))
                , Press.onPress (Tap i)
                , Press.onKeyClick (Tap i)
                ]
                [ viewCaveArt (modBy 2 (i + i // 4) == 1) ]
            )

        rows =
            List.range 0 (caveCount - 1)
                |> List.sortBy (\i -> Tuple.second (caveBase narrow i))
    in
    Html.Keyed.node "div" [ class "contents" ] (List.map cave rows)


{-| A cave seen from the side: a high round rock with a dark arched
entrance, on a patch of sand. The bottom of the cave is at the point 0 0.
Some caves are flipped, so that they do not all look the same.
-}
viewCaveArt : Bool -> Html Msg
viewCaveArt flip =
    svg
        [ SA.viewBox "-44 -72 88 84"
        , SA.class "ink-trail-cave-art"
        , attribute "aria-hidden" "true"
        ]
        [ Svg.path [ SA.d "M-38 3Q-22 -4 -2 -1Q18 -5 38 3Q0 10 -38 3Z", SA.class "ink-trail-sand" ] []
        , Svg.g
            [ SA.transform
                (if flip then
                    "scale(-1 1)"

                 else
                    ""
                )
            ]
            [ Svg.path [ SA.d rockPath, SA.class "ink-trail-rock" ] []
            , Svg.path [ SA.d "M-23 -24Q-23 -42 -12 -50", SA.class "ink-trail-rock-light" ] []
            , Svg.path [ SA.d entrancePath, SA.class "ink-trail-entrance" ] []
            , Svg.path [ SA.d entrancePath, SA.class "ink-trail-answer" ] []
            ]
        , Svg.path [ SA.d "M-36 3Q-20 -2 -2 0Q18 -3 36 3", SA.class "ink-trail-sand-line" ] []
        ]


rockPath : String
rockPath =
    smoothPath
        [ ( -26, 0 )
        , ( -27.8, -8.4 )
        , ( -28.7, -23.6 )
        , ( -26.9, -39.6 )
        , ( -21.4, -50.2 )
        , ( -14.1, -54.7 )
        , ( -3.2, -60 )
        , ( 8.7, -64 )
        , ( 19.6, -61.8 )
        , ( 25.1, -57.3 )
        , ( 26, -48.4 )
        , ( 26, -37.8 )
        , ( 28.7, -26.2 )
        , ( 31.9, -16.4 )
        , ( 29.6, -11.1 )
        , ( 26.9, -4.9 )
        , ( 26, 0 )
        ]


entrancePath : String
entrancePath =
    smoothPath
        [ ( -14.1, 0 )
        , ( -14.1, -3.1 )
        , ( -18.2, -9.3 )
        , ( -18.7, -26.2 )
        , ( -18.7, -36 )
        , ( -16, -41.3 )
        , ( -8.7, -45.3 )
        , ( 3.2, -46.2 )
        , ( 8.7, -44 )
        , ( 13.2, -37.8 )
        , ( 16.9, -28.9 )
        , ( 19.2, -23.6 )
        , ( 20.1, -12.9 )
        , ( 19.6, -4 )
        , ( 19.6, 0 )
        ]


{-| A closed path through the points: a straight line from the first point
and to the last point, and smooth curves between them
-}
smoothPath : List ( Float, Float ) -> String
smoothPath points =
    let
        mid ( x1, y1 ) ( x2, y2 ) =
            num ((x1 + x2) / 2) ++ " " ++ num ((y1 + y2) / 2)

        point ( x, y ) =
            num x ++ " " ++ num y

        curves =
            List.map2 (\p q -> "Q" ++ point p ++ " " ++ mid p q)
                (List.drop 1 points)
                (List.drop 2 points)
    in
    case ( points, List.reverse points ) of
        ( first :: second :: _, last :: _ ) ->
            "M" ++ point first ++ "L" ++ mid first second ++ String.concat curves ++ "L" ++ point last ++ "Z"

        _ ->
            ""


num : Float -> String
num value =
    String.fromFloat (toFloat (round (value * 10)) / 10)



-- OCTOPI AND INK


{-| Where an octopus is, how it turns (0 is up, in degrees), how far its
arms are open (1 when it sits, 0 in a jet), and how calm it is (1 when it
sits: its arms wave and it floats up and down a bit)
-}
type alias Pose =
    { x : Float
    , y : Float
    , turn : Float
    , spread : Float
    , calm : Float
    }


{-| The octopi and the ink, over the caves. The sea has the same units as
the places of the caves.
-}
viewSwimmers : Bool -> Int -> Trail -> Html Msg
viewSwimmers narrow now trail =
    let
        leader =
            leaderJets trail
    in
    svg
        [ SA.viewBox ("0 0 400 " ++ String.fromFloat (seaHeight narrow))
        , SA.class "ink-trail-swimmers"
        , attribute "aria-hidden" "true"
        ]
        [ Svg.defs []
            [ Svg.filter [ SA.id "ink-trail-soft", SA.x "-20%", SA.y "-20%", SA.width "140%", SA.height "140%" ]
                [ Svg.feGaussianBlur [ SA.stdDeviation "1.6" ] [] ]
            ]
        , Svg.g [ SA.class "ink-trail-ink", SA.filter "url(#ink-trail-soft)" ]
            (viewInk narrow now trail.followerPast ++ viewInk narrow now leader)
        , viewOctopus "player" now (pose narrow now (caveAt trail trail.follower) trail.followerPast)
        , viewOctopus "leader" now (pose narrow now (caveAt trail (shownLeader now trail)) leader)
        ]


{-| The way from the cave of a jet to its next cave, in degrees: 0 is up
-}
heading : Bool -> Jet -> Float
heading narrow jet =
    let
        ( x1, y1 ) =
            home narrow jet.from

        ( x2, y2 ) =
            home narrow jet.to
    in
    atan2 (x2 - x1) (y1 - y2) * 180 / pi


{-| The jet comes right after the jet before it, with only a short stop at
the cave between them
-}
chained : Jet -> Jet -> Bool
chained before jet =
    jet.at - (before.at + jetMs) <= stopMs + 60


{-| Where the octopus is at the time `now`, from its jets (in the order of
their times, also the jets that did not start yet). With no jet, it sits
at its cave.

A jet has three parts: the octopus turns to the next cave and closes its
arms, then it shoots there fast and slows down, and then it opens its arms
again. Between two jets in a row, it stops with its arms a bit open and
turns from its last way to the next one. After the last jet, it turns back
up and its arms open fully.

-}
pose : Bool -> Int -> Int -> List Jet -> Pose
pose narrow now cave jets =
    let
        ( started, next ) =
            List.partition (\jet -> jet.at <= now) jets

        bob calm =
            sin (toFloat now / 520 + toFloat cave) * 0.6 * calm
    in
    case List.reverse started of
        [] ->
            let
                ( x, y ) =
                    home narrow cave
            in
            { x = x, y = y + bob 1, turn = 0, spread = 1, calm = 1 }

        jet :: before ->
            let
                age =
                    toFloat (now - jet.at)

                duration =
                    toFloat jetMs

                ( ax, ay ) =
                    home narrow jet.from

                ( bx, by ) =
                    home narrow jet.to

                start =
                    turnMs * 0.6

                moved =
                    easeOut (clamp 0 1 ((age - start) / (duration - start)))

                fromStop =
                    case before of
                        last :: _ ->
                            if chained last jet then
                                Just last

                            else
                                Nothing

                        [] ->
                            Nothing

                toStop =
                    case next of
                        first :: _ ->
                            chained jet first

                        [] ->
                            False

                ( lastTurn, lastSpread ) =
                    case fromStop of
                        Just last ->
                            ( heading narrow last, stopSpread )

                        Nothing ->
                            ( 0, 1 )

                turning =
                    easeInOut (clamp 0 1 (age / turnMs))

                turned =
                    wrapAngle (lastTurn + wrapAngle (heading narrow jet - lastTurn) * turning)

                ( turn, spread, calm ) =
                    if age < turnMs then
                        ( turned, lastSpread * (1 - turning), 0 )

                    else if toStop then
                        ( turned, stopSpread * easeInOut (clamp 0 1 ((age - duration * 0.72) / (duration * 0.28))), 0 )

                    else
                        let
                            settled =
                                easeInOut (clamp 0 1 ((age - duration * 0.9) / settleMs))
                        in
                        ( turned * (1 - settled)
                        , easeInOut (clamp 0 1 ((age - duration * 0.7) / (duration * 0.2 + settleMs * 0.8)))
                        , settled
                        )
            in
            { x = lerp ax bx moved, y = lerp ay by moved + bob calm, turn = turn, spread = spread, calm = calm }


lerp : Float -> Float -> Float -> Float
lerp a b t =
    a + (b - a) * t


easeOut : Float -> Float
easeOut t =
    1 - (1 - t) ^ 3


easeInOut : Float -> Float
easeInOut t =
    if t < 0.5 then
        4 * t ^ 3

    else
        1 - ((2 - 2 * t) ^ 3) / 2


{-| The same angle, from -180 to 180 degrees
-}
wrapAngle : Float -> Float
wrapAngle angle =
    angle - 360 * toFloat (round (angle / 360))


{-| The control points of the two arms on the right side, for an octopus
that sits (out to the side, the tips up) and for one in a jet (behind the
head, a bit apart). The left arms are the same, flipped.
-}
sitArms : List (List ( Float, Float ))
sitArms =
    [ [ ( 9, -1 ), ( 15, 7 ), ( 25, 7 ), ( 35, -2 ) ]
    , [ ( 4, 3 ), ( 7, 13 ), ( 18, 17 ), ( 31, 13 ) ]
    ]


jetArms : List (List ( Float, Float ))
jetArms =
    [ [ ( 6, 2 ), ( 8, 11 ), ( 10, 21 ), ( 9, 32 ) ]
    , [ ( 3, 4 ), ( 3, 13 ), ( 4, 23 ), ( 3, 34 ) ]
    ]


{-| An octopus: a round head, big eyes, a smile, and 4 arms that become
thin at the tips. The color comes from the CSS: the leader is orange and
the player's octopus is blue.
-}
viewOctopus : String -> Int -> Pose -> Svg Msg
viewOctopus who now p =
    let
        wave side k =
            sin (toFloat now / 430 + toFloat k * 1.9 + side) * p.calm

        arm side k sit jet =
            List.indexedMap
                (\i ( ( sx, sy ), ( jx, jy ) ) ->
                    ( side * lerp jx sx p.spread
                    , lerp jy sy p.spread
                        + (if i >= 2 then
                            wave side k * toFloat (i - 1) * 0.9

                           else
                            0
                          )
                    )
                )
                (List.map2 Tuple.pair sit jet)
                |> viewArm

        arms =
            List.concatMap
                (\side -> List.map3 (arm side) [ 0, 1 ] sitArms jetArms)
                [ -1, 1 ]
                |> List.concat

        -- In a jet, the head is a bit longer
        stretch =
            1 - p.spread
    in
    Svg.g
        [ SA.class ("ink-trail-octopus is-" ++ who)
        , SA.transform
            ("translate("
                ++ num p.x
                ++ " "
                ++ num p.y
                ++ ") rotate("
                ++ num p.turn
                ++ ") scale(0.68)"
            )
        ]
        [ Svg.g [ SA.transform ("scale(" ++ num (1 - 0.08 * stretch) ++ " " ++ num (1 + 0.1 * stretch) ++ ")") ]
            (arms
                ++ [ Svg.path [ SA.d "M0 -24C9 -24 15.5 -15 15.5 -6C15.5 3 8 6 0 6C-8 6 -15.5 3 -15.5 -6C-15.5 -15 -9 -24 0 -24Z" ] []
                   , Svg.circle [ SA.cx "-5.8", SA.cy "-7", SA.r "4.3", SA.class "ink-trail-eye" ] []
                   , Svg.circle [ SA.cx "5.8", SA.cy "-7", SA.r "4.3", SA.class "ink-trail-eye" ] []
                   , Svg.circle [ SA.cx "-6.6", SA.cy "-6.2", SA.r "2.4", SA.class "ink-trail-pupil" ] []
                   , Svg.circle [ SA.cx "5", SA.cy "-6.2", SA.r "2.4", SA.class "ink-trail-pupil" ] []
                   , Svg.path [ SA.d "M-3.2 0.5Q-0.6 3 2 0.5", SA.class "ink-trail-smile" ] []
                   ]
            )
        ]


{-| One arm: a curve through 4 control points, thick at the head and thin
at the round tip
-}
viewArm : List ( Float, Float ) -> List (Svg Msg)
viewArm points =
    case points of
        [ p0, p1, p2, p3 ] ->
            let
                at t =
                    let
                        u =
                            1 - t

                        coord f =
                            u * u * u * f p0 + 3 * u * u * t * f p1 + 3 * u * t * t * f p2 + t * t * t * f p3

                        slope f =
                            3 * u * u * (f p1 - f p0) + 6 * u * t * (f p2 - f p1) + 3 * t * t * (f p3 - f p2)

                        ( dx, dy ) =
                            ( slope Tuple.first, slope Tuple.second )

                        length =
                            max 0.001 (sqrt (dx * dx + dy * dy))

                        half =
                            lerp 3.5 1.7 t

                        ( x, y ) =
                            ( coord Tuple.first, coord Tuple.second )
                    in
                    ( ( x - dy / length * half, y + dx / length * half )
                    , ( x + dy / length * half, y - dx / length * half )
                    )

                sides =
                    List.map (\i -> at (toFloat i / 18)) (List.range 0 18)

                outline =
                    List.map Tuple.first sides ++ List.reverse (List.map Tuple.second sides)

                ( tipX, tipY ) =
                    p3
            in
            [ Svg.path [ SA.d ("M" ++ String.join "L" (List.map (\( x, y ) -> num x ++ " " ++ num y) outline) ++ "Z") ] []
            , Svg.circle [ SA.cx (num tipX), SA.cy (num tipY), SA.r "1.7" ] []
            ]

        _ ->
            []


{-| The ink of the jets that ended less than a second ago. At the start of
a jet, a few big puffs come out (fewer after a stop), and then a puff each
few units on the way, behind the head. Each puff stays where it came out,
grows, moves back a bit and fades. The puffs come from the times of the
jets, with fixed random sizes, so they are the same at each frame.
-}
viewInk : Bool -> Int -> List Jet -> List (Svg Msg)
viewInk narrow now jets =
    List.map2
        (\before jet ->
            if now >= jet.at && now - jet.at < jetMs + 900 then
                jetPuffs narrow now (Maybe.map (\b -> chained b jet) before |> Maybe.withDefault False) jet

            else
                []
        )
        (Nothing :: List.map Just jets)
        jets
        |> List.concat


jetPuffs : Bool -> Int -> Bool -> Jet -> List (Svg Msg)
jetPuffs narrow now fromStop jet =
    let
        ( ax, ay ) =
            home narrow jet.from

        ( bx, by ) =
            home narrow jet.to

        angle =
            degrees (heading narrow jet)

        -- The ink comes out a bit behind the middle of the octopus
        ( backX, backY ) =
            ( -7 * sin angle, 7 * cos angle )

        length =
            max 1 (sqrt ((bx - ax) ^ 2 + (by - ay) ^ 2))

        duration =
            toFloat jetMs

        start =
            turnMs * 0.6

        step =
            3.2

        -- No ink at the slow end of the jet
        count =
            floor (length * easeOut (clamp 0 1 ((duration * 0.92 - start) / (duration - start))) / step)

        seed =
            modBy 100000 jet.at

        burst =
            List.range 0
                (if fromStop then
                    1

                 else
                    2
                )
                |> List.map (\k -> puff now seed k True ( ax + backX, ay + backY ) angle (toFloat jet.at + start))

        trail =
            List.range 1 count
                |> List.map
                    (\k ->
                        let
                            part =
                                toFloat k * step / length

                            -- When the octopus passes this point (see `pose`)
                            time =
                                start + (1 - (1 - part) ^ (1 / 3)) * (duration - start)
                        in
                        puff now seed (k + 10) False ( lerp ax bx part + backX, lerp ay by part + backY ) angle (toFloat jet.at + time)
                    )
    in
    List.filterMap identity (burst ++ trail)


puff : Int -> Int -> Int -> Bool -> ( Float, Float ) -> Float -> Float -> Maybe (Svg Msg)
puff now seed k big ( x, y ) angle bornAt =
    let
        r i =
            random seed (k * 8 + i)

        size =
            if big then
                1.4

            else
                1

        life =
            lerp 450 650 (r 1)
                * (if big then
                    1.15

                   else
                    1
                  )

        age =
            toFloat now - bornAt
    in
    if age < 0 || age >= life then
        Nothing

    else
        let
            opacity =
                0.3 * (1 - age / life) ^ 1.6 * min 1 (age / 60)

            radius =
                lerp 2.2 3.6 (r 2) * size + age * 0.011

            px =
                x + (r 3 - 0.5) * 4 + (-(sin angle) * 0.012 + (r 5 - 0.5) * 0.01) * age

            py =
                y + (r 4 - 0.5) * 4 + (cos angle * 0.012 + (r 6 - 0.5) * 0.01 - 0.004) * age

            side =
                r 7 * 2 * pi
        in
        Just
            (Svg.g [ SA.opacity (num3 opacity) ]
                [ Svg.circle [ SA.cx (num px), SA.cy (num py), SA.r (num radius) ] []
                , Svg.circle
                    [ SA.cx (num (px + cos side * radius * 0.6))
                    , SA.cy (num (py + sin side * radius * 0.6))
                    , SA.r (num (radius * (0.5 + r 8 * 0.4)))
                    , SA.class "ink-trail-ink-light"
                    ]
                    []
                ]
            )


num3 : Float -> String
num3 value =
    String.fromFloat (toFloat (round (value * 1000)) / 1000)


{-| A fixed random number from 0 to 1 for the two numbers
-}
random : Int -> Int -> Float
random seed i =
    let
        value =
            sin (toFloat seed * 0.0137 + toFloat i * 12.9898) * 43758.5453
    in
    value - toFloat (floor value)


{-| The number is keyed, so that it pops in again on each step.
-}
viewCountdown : Int -> Html Msg
viewCountdown seconds =
    div
        [ id "ink-trail-countdown"
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


viewResult : Model -> Bool -> Game -> Html Msg
viewResult model watching game =
    let
        score =
            List.head game.players |> Maybe.map .score |> Maybe.withDefault 0

        mistakes =
            if game.wrong == 1 then
                "1 mistake"

            else
                String.fromInt game.wrong ++ " mistakes"
    in
    div
        [ id "ink-trail-result"
        , class "absolute inset-0 z-10 flex flex-col items-center justify-center gap-4 rounded-2xl bg-octo-navy/80 p-4 text-center text-white backdrop-blur-sm"
        ]
        [ p [ class "text-lg opacity-80" ] [ text "Game over!" ]
        , p [ id "ink-trail-final-score", class "text-6xl font-bold tabular-nums" ] [ text (String.fromInt score) ]
        , p [ id "ink-trail-final-stats", class "text-sm tabular-nums opacity-80" ]
            [ text ("Best distance " ++ String.fromInt game.bestDistance ++ " · " ++ mistakes) ]
        , if watching then
            text ""

          else
            button
                [ id "ink-trail-play-again"
                , class "rounded-full bg-white px-6 py-2.5 font-medium text-octo-indigo shadow-lg transition hover:bg-octo-mist"
                , onClick Restart
                ]
                [ text ("Play again at distance " ++ String.fromInt (max 3 game.lastDistance)) ]
        , a
            [ id "ink-trail-leaderboards-link"
            , href model.settingsUrl
            , class "text-sm font-medium text-white/80 underline-offset-4 transition hover:text-white hover:underline"
            ]
            [ text "Best results" ]
        , a
            [ id "ink-trail-next-game"
            , href model.nextGame.path
            , attribute "data-ga-link" "or_try"
            , attribute "data-ga-from" "Ink Trail"
            , attribute "data-ga-to" model.nextGame.name
            , class "group text-sm font-medium text-white underline-offset-4 transition hover:underline"
            ]
            [ text ("Or try " ++ model.nextGame.name ++ " ")
            , span [ class "inline-block transition group-hover:translate-x-0.5" ] [ text "→" ]
            ]
        , if model.guest then
            p [ id "ink-trail-sign-in", class "text-sm text-white/70" ]
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


{-| The link to the page to support Octomocto, at the bottom of a result.
The link opens in a new tab, so that the player stays in the game.
-}
viewFeed : Html msg
viewFeed =
    p [ id "ink-trail-feed", class "mt-2 max-w-sm border-t border-white/15 pt-4 text-center text-sm leading-10 text-balance text-white/80" ]
        [ a
            [ href "/donate"
            , target "_blank"
            , rel "noopener"
            , class "group mx-1 inline-flex items-center gap-1.5 whitespace-nowrap rounded-full bg-octo-orange px-4 py-1.5 align-middle leading-5 font-semibold text-white shadow-lg shadow-octo-orange/30 transition hover:bg-octo-orange-light"
            ]
            [ span [ class "hero-heart-solid size-4 transition group-hover:scale-110" ] []
            , text "Support the author"
            ]
        , text " to keep Octomocto ad-free."
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
