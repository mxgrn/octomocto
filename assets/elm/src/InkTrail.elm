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
octopus goes to the correct cave, and the leader waits (at the distance 3,
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


{-| The number of browsers that only watch the game, after the join and
after each change.
-}
port inkTrailWatchers : (Int -> msg) -> Sub msg


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

    -- The cave of the last wrong tap, for a watcher
    , missedCave : Maybe Int
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

    -- After a wrong tap, a ghost of the leader jets along the path ahead,
    -- from the player's octopus to the leader
    , ghost : List Jet

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
    , sea : Sea

    -- The local time (in ms) when the game of the server started, and the
    -- local time now
    , clockStart : Int
    , now : Int

    -- The countdown step that last played its beep (see `countdownStep`)
    , beepedStep : Maybe Int

    -- The leader on the screen when the last jet sound played
    , jetCue : Maybe ( String, Int )

    -- The wrong tap (its time) and the jets of its ghost when the last
    -- ghost sound played
    , ghostCue : Maybe ( Int, Int )
    , muted : Bool
    , watchers : Int
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
      , sea = seaFor flags.narrow ""
      , clockStart = 0
      , now = 0
      , beepedStep = Nothing
      , jetCue = Nothing
      , ghostCue = Nothing
      , muted = flags.muted
      , watchers = 0
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


{-| After a wrong tap, the wrong cave shows red for this long
-}
missMs : Int
missMs =
    800


{-| After a wrong tap, the ghost of the leader starts this long after the
player's octopus lands, and it stays this long at its last cave before it
is gone
-}
ghostPauseMs : Int
ghostPauseMs =
    250


ghostStayMs : Int
ghostStayMs =
    500


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


{-| The places of the caves of a game: the middle of the bottom of each
cave, in units. Each game has its own random places, which come from its
field, so that a reload and a watcher see the same sea.
-}
type alias Sea =
    { narrow : Bool
    , field : String
    , caves : Array ( Float, Float )
    }


seaFor : Bool -> String -> Sea
seaFor narrow field =
    { narrow = narrow
    , field = field
    , caves = caves narrow (String.foldl (\c hash -> modBy 1000003 (hash * 31 + Char.toCode c)) 7 field)
    }


{-| Gives the sea of the game on the page, when the game or the size of
the screen changes
-}
withSea : Model -> Model
withSea model =
    case model.connection of
        Joined _ game ->
            if model.sea.field == game.field && model.sea.narrow == model.narrow then
                model

            else
                { model | sea = seaFor model.narrow game.field }

        _ ->
            model


{-| Random places for the caves. Each cave takes the best of many random
places: the place that is the farthest from the caves before it. A cave can
be in front of a higher cave, but not over its entrance. If the caves are
too near each other, it tries other random places, and at last it uses
fixed rows.
-}
caves : Bool -> Int -> Array ( Float, Float )
caves narrow seed =
    let
        attempt n =
            if n >= 12 then
                Array.fromList (fixedCaves narrow)

            else
                let
                    places =
                        scatter (seaHeight narrow) (seed + n * 7919)
                in
                if nearest places >= 1 then
                    Array.fromList places

                else
                    attempt (n + 1)
    in
    attempt 0


scatter : Float -> Int -> List ( Float, Float )
scatter height seed =
    let
        candidate i k =
            ( 42 + 316 * random seed (i * 200 + 2 * k)
            , 54 + (height - 62) * random seed (i * 200 + 2 * k + 1)
            )

        place i placed =
            let
                score p =
                    List.map (caveGap p) placed |> List.minimum |> Maybe.withDefault 0
            in
            List.range 0 99
                |> List.map (candidate i)
                |> List.foldl
                    (\p best ->
                        if score p > score best then
                            p

                        else
                            best
                    )
                    (candidate i 0)
                |> (\p -> placed ++ [ p ])
    in
    List.foldl place [] (List.range 0 (caveCount - 1))


{-| How far apart two caves are: 1 or more when they do not touch. A cave
is about 80 units wide, and a lower cave must be 48 units lower to show the
entrance of the cave behind it.
-}
caveGap : ( Float, Float ) -> ( Float, Float ) -> Float
caveGap ( x1, y1 ) ( x2, y2 ) =
    max (abs (x1 - x2) / 82) (abs (y1 - y2) / 48)


nearest : List ( Float, Float ) -> Float
nearest places =
    case places of
        p :: rest ->
            min (List.map (caveGap p) rest |> List.minimum |> Maybe.withDefault 2) (nearest rest)

        [] ->
            2


{-| Fixed places, in rows: a wide sea has 3 rows of 4 caves, and a phone
has 4 rows of 3
-}
fixedCaves : Bool -> List ( Float, Float )
fixedCaves narrow =
    if narrow then
        [ ( 68, 102 ), ( 198, 96 ), ( 330, 104 ), ( 82, 222 ), ( 210, 216 ), ( 338, 226 ), ( 66, 344 ), ( 196, 338 ), ( 326, 348 ), ( 84, 466 ), ( 212, 460 ), ( 338, 468 ) ]

    else
        [ ( 46, 92 ), ( 144, 84 ), ( 242, 94 ), ( 340, 86 ), ( 72, 188 ), ( 170, 180 ), ( 266, 190 ), ( 360, 182 ), ( 46, 284 ), ( 144, 278 ), ( 242, 286 ), ( 340, 280 ) ]


caveCount : Int
caveCount =
    12


caveBase : Sea -> Int -> ( Float, Float )
caveBase sea cave =
    Array.get cave sea.caves |> Maybe.withDefault ( 200, 150 )


{-| Where an octopus is when it sits at the cave: in the entrance, a bit
above the sand
-}
home : Sea -> Int -> ( Float, Float )
home sea cave =
    let
        ( x, y ) =
            caveBase sea cave
    in
    ( x, y - 11 )



-- UPDATE


type Msg
    = GotJoined Decode.Value
    | GotState Decode.Value
    | GotJoinFailed String
    | GotWatchers Int
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
                    ( withSea (sync game { model | connection = Joined me game }), syncClock game )

                Err err ->
                    ( { model | connection = Failed (Decode.errorToString err) }, Cmd.none )

        GotState value ->
            case ( model.connection, Decode.decodeValue gameDecoder value ) of
                ( Joined me _, Ok game ) ->
                    ( withSea (sync game { model | connection = Joined me game })
                    , Cmd.batch [ syncClock game, playSounds model (syncSounds game model) ]
                    )

                _ ->
                    ( model, Cmd.none )

        GotJoinFailed reason ->
            ( { model | connection = Failed reason }, Cmd.none )

        GotWatchers count ->
            ( { model | watchers = count }, Cmd.none )

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
            ( withSea { model | narrow = width <= 640 }, Cmd.none )


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

                    shown =
                        shownLeader model.now trail

                    -- As after a tap: the player's octopus jets first. After
                    -- a wrong tap, the ghost of the leader jets the path
                    -- ahead, and then the leader goes on.
                    ( miss, ghost, leaderAt ) =
                        case ( game.wrong > trail.wrong, game.missedCave ) of
                            ( True, Just cave ) ->
                                let
                                    jets =
                                        ghostJets model.now server game.follower shown
                                in
                                ( Just ( cave, model.now ), jets, max (model.now + missMs) (ghostEndOf jets) )

                            _ ->
                                ( Nothing, [], model.now + jetMs + leaderPauseMs )
                in
                { model
                    | trail =
                        Just
                            { server
                                | leaderFrom = shown
                                , leaderAt = leaderAt
                                , miss = miss
                                , ghost = ghost
                                , hit =
                                    if game.correct > trail.correct then
                                        Just ( caveAt server game.follower, model.now )

                                    else
                                        trail.hit
                                , grewAt =
                                    if grew game trail then
                                        Just model.now

                                    else
                                        trail.grewAt
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


{-| The sounds of the taps that came from the server (see `sync`), as
`tap` plays them: for a watcher, or another browser of the player
-}
syncSounds : Game -> Model -> List String
syncSounds game model =
    case model.trail of
        Just trail ->
            if trail.field == game.field && game.follower > trail.follower then
                List.filterMap
                    (\( play, name ) ->
                        if play then
                            Just name

                        else
                            Nothing
                    )
                    [ ( game.correct > trail.correct, "follow" )
                    , ( game.wrong > trail.wrong, "wrong" )
                    , ( grew game trail && not game.finished, "grow" )
                    ]

            else
                []

        Nothing ->
            []


{-| The distance of the game from the server is larger than on the page
-}
grew : Game -> Trail -> Bool
grew game trail =
    game.leader - game.follower > distance trail


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
    , ghost = []
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


{-| The player can tap when the leader landed and the red cave and the
ghost of a wrong tap are gone
-}
canTap : Int -> Trail -> Bool
canTap now trail =
    trail.endedAt
        == Nothing
        && shownLeader now trail
        == trail.leader
        && now
        >= leaderLandsAt trail
        && not (missing now trail)


{-| A wrong tap still shows: the red cave or the ghost
-}
missing : Int -> Trail -> Bool
missing now trail =
    case trail.miss of
        Just ( _, at ) ->
            now - at < missMs || now < ghostEnd trail

        Nothing ->
            False


{-| The local time when the ghost of a wrong tap is gone
-}
ghostEnd : Trail -> Int
ghostEnd trail =
    ghostEndOf trail.ghost


ghostEndOf : List Jet -> Int
ghostEndOf ghost =
    case List.reverse ghost of
        last :: _ ->
            last.at + jetMs + ghostStayMs

        [] ->
            0


{-| After a wrong tap at the local time `now`, the ghost of the leader jets
from the new cave of the player's octopus (the index `from` of the path) to
the leader (the index `to`), with short stops, as the leader does
-}
ghostJets : Int -> Trail -> Int -> Int -> List Jet
ghostJets now trail from to =
    let
        start =
            now + jetMs + ghostPauseMs
    in
    List.range from (to - 1)
        |> List.map
            (\k ->
                { from = caveAt trail k
                , to = caveAt trail (k + 1)
                , at = start + (k - from) * (jetMs + stopMs)
                }
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
            -- The distance is never less than 3
            jets =
                if gap > 3 then
                    0

                else
                    1

            missed =
                { moved | ghost = ghostJets now trail step trail.leader }
        in
        ( { model
            | trail =
                Just
                    { missed
                        | leader = trail.leader + jets
                        , streak = 0
                        , wrong = trail.wrong + 1

                        -- The leader goes on when the ghost is gone
                        , leaderAt = max (now + missMs) (ghostEnd missed)
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
                                if Maybe.withDefault 0 model.beepedStep > 0 then
                                    [ "go" ]

                                else
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

                -- A swish when a jet of the ghost of a wrong tap starts
                ( ghostCue, ghostSounds ) =
                    case trail of
                        Just current ->
                            case current.miss of
                                Just ( _, missAt ) ->
                                    let
                                        started =
                                            List.length (List.filter (\jet -> jet.at <= model.now) current.ghost)

                                        cue =
                                            Just ( missAt, started )
                                    in
                                    if cue /= model.ghostCue && started > 0 then
                                        ( cue, [ "ghost" ] )

                                    else
                                        ( cue, [] )

                                Nothing ->
                                    ( model.ghostCue, [] )

                        Nothing ->
                            ( model.ghostCue, [] )

                ended =
                    game.finished && phase model game /= Over && phase { model | trail = trail } game == Over
            in
            ( { model | beepedStep = step, trail = trail, jetCue = jetCue, ghostCue = ghostCue }
            , playSounds model
                (beeps
                    ++ jetSounds
                    ++ ghostSounds
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
        |> andMap (Decode.maybe (Decode.field "missed_cave" Decode.int))
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
        , inkTrailWatchers GotWatchers
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
        , viewWatchers (me == Nothing) model.watchers
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


{-| The eye with the number of watchers, when there are watchers. A
watcher sees it in the accent color.
-}
viewWatchers : Bool -> Int -> Html Msg
viewWatchers watching count =
    if watching || count > 0 then
        span
            [ id "ink-trail-watchers"
            , class "flex shrink-0 items-center gap-1 text-sm tabular-nums transition-colors"
            , classList
                [ ( "text-slate-500 dark:text-slate-400", not watching )
                , ( "font-medium text-octo-indigo dark:text-octo-indigo-light", watching )
                ]
            , Html.Attributes.title
                (if watching then
                    "You are watching this game."

                 else
                    "Watchers: " ++ String.fromInt count
                )
            ]
            [ span [ class "hero-eye size-4" ] [], text (String.fromInt (max count 1)) ]

    else
        text ""


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
        ( ( correct, wrong ), gap, streak ) =
            case model.trail of
                Just trail ->
                    ( ( trail.correct, trail.wrong ), distance trail, trail.streak )

                Nothing ->
                    ( ( game.correct, game.wrong ), game.leader - game.follower, game.streak )

        score =
            Maybe.map .score model.trail |> Maybe.withDefault (serverScore game)

        stat label content =
            div [ class "flex flex-col items-center justify-center gap-0.5 px-2" ]
                [ span [ class "text-[0.625rem] font-medium tracking-wide text-slate-400 uppercase lg:text-xs" ] [ text label ]
                , content
                ]
    in
    div [ id "ink-trail-stats", class "grid grid-cols-4 divide-x divide-slate-200 rounded-2xl bg-white py-3 shadow-sm ring-1 ring-slate-200 dark:divide-white/10 dark:bg-white/5 dark:shadow-none dark:ring-white/10" ]
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
        , stat "mistakes"
            (Html.Keyed.node "span"
                []
                [ ( String.fromInt wrong
                  , span
                        [ id "ink-trail-wrong"
                        , class "inline-block text-2xl leading-tight font-light tabular-nums lg:text-3xl"
                        , classList
                            [ ( "countdown-pop text-rose-500 dark:text-rose-400", wrong > 0 )
                            , ( "text-slate-400", wrong == 0 )
                            ]
                        ]
                        [ text (String.fromInt wrong) ]
                  )
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
                    , viewSwimmers model.sea model.now trail
                    ]

                Nothing ->
                    [ Html.Lazy.lazy5 viewCaveButtons model.sea False -1 -1 -1 ]
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

            else if missing now trail then
                "Missed. Watch the trail ahead"

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
    in
    Html.Lazy.lazy5 viewCaveButtons
        model.sea
        (active && not watching && canTap now trail)
        (recent trail.hit 400)
        (recent trail.miss missMs)
        (Array.length trail.path)


{-| A button for each cave, in the order of their rows, so that a lower
cave covers the cave above it. The last argument only tells Html.Lazy when
the path grows.
-}
viewCaveButtons : Sea -> Bool -> Int -> Int -> Int -> Html Msg
viewCaveButtons sea open hit missed _ =
    let
        height =
            seaHeight sea.narrow

        cave i =
            let
                ( x, y ) =
                    caveBase sea i
            in
            ( String.fromInt i
            , button
                [ id ("ink-trail-cave-" ++ String.fromInt i)
                , class "ink-trail-cave"
                , classList
                    [ ( "is-open", open )
                    , ( "is-hit", hit == i )
                    , ( "is-miss", missed == i )
                    ]
                , style "left" (String.fromFloat (x / 4) ++ "%")
                , style "top" (String.fromFloat (100 * y / height) ++ "%")
                , attribute "aria-label" ("Cave " ++ String.fromInt (i + 1))
                , Press.onPress (Tap i)
                , Press.onKeyClick (Tap i)
                ]
                [ viewCaveArt i ]
            )

        rows =
            List.range 0 (caveCount - 1)
                |> List.sortBy (\i -> Tuple.second (caveBase sea i))
    in
    Html.Keyed.node "div" [ class "contents" ] (List.map cave rows)


{-| A cave seen from the side: a low arch of big rocks around a dark
entrance, with a soft shadow on the sand. The light comes from the top left.
The bottom of the cave is at the point 0 0. Some caves are flipped, so that
they do not all look the same, and each third cave has seaweed that sways
and bubbles that rise.
-}
viewCaveArt : Int -> Html Msg
viewCaveArt cave =
    let
        flip =
            modBy 2 (cave + cave // 4) == 1

        -- The seaweed and the bubbles of the caves do not move together
        delay extra =
            SA.style ("animation-delay: " ++ String.fromFloat (-0.9 * toFloat cave - extra) ++ "s")

        weed d extra =
            Svg.g [ SA.class "ink-trail-weed", delay extra ]
                [ Svg.path [ SA.d d, SA.class "ink-trail-weed-edge" ] []
                , Svg.path [ SA.d d, SA.class "ink-trail-weed-leaf" ] []
                ]

        bubble ( x, y, r ) extra =
            Svg.circle [ SA.cx x, SA.cy y, SA.r r, SA.class "ink-trail-bubble", delay extra ] []

        life =
            if modBy 3 cave == 0 then
                [ weed "M-43.6 0C-45.5 -3 -41.8 -6 -43.6 -9C-45.2 -12 -42.5 -13 -43.6 -14.5" 0
                , weed "M38.6 0C36.6 -5 40.6 -9 38.6 -14C36.8 -19 40.4 -23 38.6 -28C37.2 -32 39.8 -34 38.6 -36.7" 0.7
                , weed "M42.9 0C41 -4 44.6 -8 42.9 -12C41.4 -15 44 -16.5 42.9 -18" 1.3
                , bubble ( "36.6", "-40.7", "1.4" ) 0
                , bubble ( "39.1", "-45.6", "1" ) 1
                , bubble ( "37.1", "-49.6", "0.7" ) 2
                ]

            else
                []

        boulder b =
            Svg.g []
                [ Svg.path [ SA.d b.outline, SA.class "ink-trail-rock" ] []
                , Svg.path [ SA.d b.light, SA.class "ink-trail-rock-light" ] []
                , Svg.path [ SA.d b.shade, SA.class "ink-trail-rock-shade" ] []
                , Svg.path [ SA.d b.outline, SA.class "ink-trail-rock-edge" ] []
                ]
    in
    svg
        [ SA.viewBox "-46 -54 92 58"
        , SA.class "ink-trail-cave-art"
        , attribute "aria-hidden" "true"
        ]
        [ Svg.g
            [ SA.transform
                (if flip then
                    "scale(-1 1)"

                 else
                    ""
                )
            ]
            ([ Svg.ellipse [ SA.cx "0", SA.cy "0.4", SA.rx "38", SA.ry "1.8", SA.class "ink-trail-sand-shadow" ] []
             , Svg.path [ SA.d caveBack, SA.class "ink-trail-rock-shade" ] []
             , Svg.path [ SA.d caveBack, SA.class "ink-trail-rock-edge" ] []
             , Svg.path [ SA.d caveHole, SA.class "ink-trail-entrance" ] []
             , Svg.path [ SA.d caveMound, SA.class "ink-trail-entrance-back" ] []
             ]
                ++ List.map boulder caveBoulders
                ++ [ Svg.path [ SA.d caveCracks, SA.class "ink-trail-crack" ] []
                   , Svg.ellipse [ SA.cx "-39", SA.cy "-0.7", SA.rx "2.9", SA.ry "1.4", SA.class "ink-trail-pebble" ] []
                   , Svg.ellipse [ SA.cx "35.4", SA.cy "-0.4", SA.rx "1.7", SA.ry "1", SA.class "ink-trail-pebble" ] []
                   ]
                ++ life
            )
        ]


{-| A rock of the arch of a cave: its outline, its light sides and its dark
sides
-}
type alias Boulder =
    { outline : String
    , light : String
    , shade : String
    }


caveBack : String
caveBack =
    "M-41.4 0L-40 -13.9L-36.4 -16L-35 -23.1L-29.3 -30.3L-22.1 -33.1L-15.7 -40.3L-7.1 -45L2.1 -46.4L11.4 -44.6L18.6 -40.3L25.7 -32.4L29.3 -23.9L31.4 -16L37.1 -16L40.6 -12.4L40.6 0Z"


caveHole : String
caveHole =
    "M-27.9 0L-25.7 -11L-20.7 -22.4L-12.9 -29.6L-2.9 -33.6L11.4 -33.6L17.9 -28.1L22.1 -21L25.7 -11L27.9 0Z"


caveMound : String
caveMound =
    "M-16.4 0L-14.3 -7.4L-7.1 -11.3L0 -12.7L7.1 -12.1L13.6 -9.3L16 0Z"


{-| The rocks of the arch, from the back to the front
-}
caveBoulders : List Boulder
caveBoulders =
    [ { outline = "M-17.1 -36.7L-15.4 -40.7L-7.1 -45L2.1 -46.4L11 -44.6L12.6 -41.3L10 -36.7L-1.4 -35.7L-10.7 -35.3Z"
      , light = "M-13.6 -40.3L-7.1 -43.6L1.7 -44.9L4.6 -43L-2.9 -40.7L-11.1 -38.4Z"
      , shade = "M-1.4 -35.7L10 -36.7L11.4 -38.9L5 -37.9Z"
      }
    , { outline = "M-35 -23.1L-29.3 -30.3L-21.7 -33.1L-17.1 -32.1L-18.6 -26.4L-23.6 -21.7L-29.7 -17.1L-34.3 -17.9Z"
      , light = "M-32.4 -23.9L-28 -28.7L-22.6 -30.7L-24.7 -26.7L-30 -22.9Z"
      , shade = "M-29.7 -17.1L-23.6 -21.7L-18.6 -26.4L-21.4 -22.4L-26.4 -18.4Z"
      }
    , { outline = "M-19.3 -25L-17.1 -31L-8.9 -35.7L-3.6 -34.4L-4.6 -28.7L-10 -25.9Z"
      , light = "M-16.7 -27.9L-13.6 -32.1L-6.9 -34.1L-9.1 -30.4Z"
      , shade = "M-17.1 -25L-10 -25.9L-4.6 -28.7L-6.9 -27.9L-12.9 -26.1Z"
      }
    , { outline = "M-2.3 -33.1L2 -35.3L6.6 -33.1L5.1 -31.3L-0.9 -31.3Z"
      , light = "M-0.9 -33.1L2 -34.4L4.6 -33.1Z"
      , shade = ""
      }
    , { outline = "M10 -36.7L11.4 -41.7L19.4 -39.9L25.7 -32.7L29.4 -23.9L25.1 -21.6L21.4 -28.1L17.1 -33Z"
      , light = "M12.9 -39L18.6 -37.9L23.7 -32.1L19.4 -32.7Z"
      , shade = "M21.4 -28.1L25.1 -21.6L29.4 -23.9L27.4 -25.6L24.6 -24.4Z"
      }
    , { outline = "M9.4 -30.1L12.9 -33.6L18 -32.7L22.3 -27.9L20.9 -19.6L15.7 -18.7L12.1 -23.9Z"
      , light = "M11.4 -30.3L15.4 -31.9L19.4 -27.9L15.1 -27.3Z"
      , shade = "M15.7 -18.7L20.9 -19.6L21.4 -23.9L18.3 -21Z"
      }
    , { outline = "M-41.4 0L-40 -13.1L-36.4 -15.9L-30.7 -14.4L-27.7 -9.3L-31.4 -3.9L-33.4 0Z"
      , light = "M-38.9 -11L-36 -14.3L-31.4 -13.3L-34.3 -10.1Z"
      , shade = "M-33.4 0L-31.4 -3.9L-27.7 -9.3L-29.4 -5Z"
      }
    , { outline = "M-33.4 0L-32.9 -6.4L-30 -8.7L-26.3 -7.3L-25.4 0Z"
      , light = "M-32 -5L-29.7 -7.6L-27.1 -6.4Z"
      , shade = ""
      }
    , { outline = "M27.4 0L26.6 -9.6L29.1 -15.9L37.1 -15.9L40.6 -12.4L40.6 0Z"
      , light = "M29.7 -13.6L36.6 -14.9L38.9 -12.1L32.9 -11Z"
      , shade = "M27.4 0L40.6 0L40.6 -3.9L31.4 -3Z"
      }
    , { outline = "M24.9 0L25.7 -4.4L29.1 -6.4L32.3 -3.9L31.7 0Z"
      , light = "M26.3 -3.9L28.9 -5.6L31.1 -3.9Z"
      , shade = ""
      }
    ]


caveCracks : String
caveCracks =
    "M6.9 -43.4L5.1 -40.4L7.1 -37M-26 -28.1L-28.6 -25M25.7 -29.3L26.9 -25.3M33.1 -12.4L36 -9.3"


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

    -- The caves where the octopus is under the arch: its cave when it
    -- sits, and both caves of a jet
    , caves : List Int
    }


{-| The octopi and the ink, over the caves. The sea has the same units as
the places of the caves.
-}
viewSwimmers : Sea -> Int -> Trail -> Html Msg
viewSwimmers sea now trail =
    let
        leader =
            leaderJets trail

        player =
            pose sea now (caveAt trail trail.follower) trail.followerPast

        leaderPose =
            pose sea now (caveAt trail (shownLeader now trail)) leader
    in
    svg
        [ SA.viewBox ("0 0 400 " ++ String.fromFloat (seaHeight sea.narrow))
        , SA.class "ink-trail-swimmers"
        , attribute "aria-hidden" "true"
        ]
        [ Svg.defs []
            [ Svg.filter [ SA.id "ink-trail-soft", SA.x "-20%", SA.y "-20%", SA.width "140%", SA.height "140%" ]
                [ Svg.feGaussianBlur [ SA.stdDeviation "1.6" ] [] ]

            -- The shadow of an arch, over the place of a head in the cave
            -- (see `viewHeadShadow`)
            , Svg.linearGradient [ SA.id "ink-trail-arch-shade", SA.x1 "0", SA.y1 "0", SA.x2 "0", SA.y2 "1" ]
                [ Svg.stop [ SA.offset "0.247", SA.stopColor "#000", SA.stopOpacity "0.5" ] []
                , Svg.stop [ SA.offset "0.435", SA.stopColor "#000", SA.stopOpacity "0.32" ] []
                , Svg.stop [ SA.offset "0.623", SA.stopColor "#000", SA.stopOpacity "0" ] []
                ]
            , headClip "player" player
            , headClip "leader" leaderPose
            ]
        , Svg.g [ SA.class "ink-trail-ink", SA.filter "url(#ink-trail-soft)" ]
            (viewInk sea now trail.followerPast ++ viewInk sea now leader)
        , viewOctopus "player" now player
        , viewHeadShadow sea "player" player
        , viewGhost sea now trail
        , viewOctopus "leader" now leaderPose
        , viewHeadShadow sea "leader" leaderPose
        ]


{-| After a wrong tap, a see-through ghost of the leader jets along the
path ahead, from the player's octopus to the leader. It comes in at the
player's octopus, and it fades out at the last cave.
-}
viewGhost : Sea -> Int -> Trail -> Svg Msg
viewGhost sea now trail =
    case trail.ghost of
        first :: _ ->
            let
                fadeIn =
                    clamp 0 1 (toFloat (now - first.at + ghostPauseMs) / toFloat ghostPauseMs)

                fadeOut =
                    clamp 0 1 (toFloat (ghostEnd trail - now) / 300)

                opacity =
                    0.5 * fadeIn * fadeOut
            in
            if opacity > 0 then
                Svg.g [ SA.opacity (num3 opacity) ]
                    [ viewOctopus "ghost" now (pose sea now first.from trail.ghost) ]

            else
                Svg.g [] []

        [] ->
            Svg.g [] []


{-| The head of an octopus, for the shadow of the arch on it
-}
headClip : String -> Pose -> Svg Msg
headClip who p =
    Svg.clipPath [ SA.id ("ink-trail-head-" ++ who) ]
        [ Svg.path [ SA.d headPath, SA.transform (octopusTransform p ++ " " ++ headStretch p) ] [] ]


{-| The shadow of the arch of a cave on the head of an octopus: dark at the
top of the head and gone a bit above the eyes, when the octopus sits in the
entrance. The shadow is fixed to the cave, so the head moves under it, and
the octopus jets out of it. Only the head shows it.
-}
viewHeadShadow : Sea -> String -> Pose -> Svg Msg
viewHeadShadow sea who p =
    Svg.g [ SA.clipPath ("url(#ink-trail-head-" ++ who ++ ")") ]
        (List.map
            (\cave ->
                let
                    ( x, y ) =
                        caveBase sea cave
                in
                Svg.rect
                    [ SA.x (num (x - 22))
                    , SA.y (num (y - 34))
                    , SA.width "44"
                    , SA.height "27.1"
                    , SA.fill "url(#ink-trail-arch-shade)"
                    ]
                    []
            )
            p.caves
        )


{-| The way from the cave of a jet to its next cave, in degrees: 0 is up
-}
heading : Sea -> Jet -> Float
heading sea jet =
    let
        ( x1, y1 ) =
            home sea jet.from

        ( x2, y2 ) =
            home sea jet.to
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
pose : Sea -> Int -> Int -> List Jet -> Pose
pose sea now cave jets =
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
                    home sea cave
            in
            { x = x, y = y + bob 1, turn = 0, spread = 1, calm = 1, caves = [ cave ] }

        jet :: before ->
            let
                age =
                    toFloat (now - jet.at)

                duration =
                    toFloat jetMs

                ( ax, ay ) =
                    home sea jet.from

                ( bx, by ) =
                    home sea jet.to

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
                            ( heading sea last, stopSpread )

                        Nothing ->
                            ( 0, 1 )

                turning =
                    easeInOut (clamp 0 1 (age / turnMs))

                turned =
                    wrapAngle (lastTurn + wrapAngle (heading sea jet - lastTurn) * turning)

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
            { x = lerp ax bx moved
            , y = lerp ay by moved + bob calm
            , turn = turn
            , spread = spread
            , calm = calm
            , caves = [ jet.from, jet.to ]
            }


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
    in
    Svg.g
        [ SA.class ("ink-trail-octopus is-" ++ who)
        , SA.transform (octopusTransform p)
        ]
        [ Svg.g [ SA.transform (headStretch p) ]
            (arms
                ++ [ Svg.path [ SA.d headPath ] []
                   , Svg.circle [ SA.cx "-5.8", SA.cy "-7", SA.r "4.3", SA.class "ink-trail-eye" ] []
                   , Svg.circle [ SA.cx "5.8", SA.cy "-7", SA.r "4.3", SA.class "ink-trail-eye" ] []
                   , Svg.circle [ SA.cx "-6.6", SA.cy "-6.2", SA.r "2.4", SA.class "ink-trail-pupil" ] []
                   , Svg.circle [ SA.cx "5", SA.cy "-6.2", SA.r "2.4", SA.class "ink-trail-pupil" ] []
                   , Svg.path [ SA.d "M-3.2 0.5Q-0.6 3 2 0.5", SA.class "ink-trail-smile" ] []
                   ]
            )
        ]


octopusTransform : Pose -> String
octopusTransform p =
    "translate(" ++ num p.x ++ " " ++ num p.y ++ ") rotate(" ++ num p.turn ++ ") scale(0.68)"


{-| In a jet, the head is a bit longer
-}
headStretch : Pose -> String
headStretch p =
    let
        stretch =
            1 - p.spread
    in
    "scale(" ++ num (1 - 0.08 * stretch) ++ " " ++ num (1 + 0.1 * stretch) ++ ")"


headPath : String
headPath =
    "M0 -24C9 -24 15.5 -15 15.5 -6C15.5 3 8 6 0 6C-8 6 -15.5 3 -15.5 -6C-15.5 -15 -9 -24 0 -24Z"


{-| One arm: a curve through 4 control points, thick at the head and thin
at the round tip. A row of white suckers goes along the arm to the tip, a
bit to one side, as on the logo.
-}
viewArm : List ( Float, Float ) -> List (Svg Msg)
viewArm points =
    case points of
        [ p0, p1, p2, p3 ] ->
            let
                -- A point at the part t of the arm, moved across the arm by
                -- the part s of its half width (-1 and 1 are the two sides)
                across s t =
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
                            s * lerp 3.5 1.7 t
                    in
                    ( coord Tuple.first - dy / length * half, coord Tuple.second + dx / length * half )

                at t =
                    ( across 1 t, across -1 t )

                sides =
                    List.map (\i -> at (toFloat i / 18)) (List.range 0 18)

                outline =
                    List.map Tuple.first sides ++ List.reverse (List.map Tuple.second sides)

                ( tipX, tipY ) =
                    p3

                sucker t =
                    let
                        ( x, y ) =
                            across suckerSide t
                    in
                    Svg.circle [ SA.cx (num x), SA.cy (num y), SA.r (num (lerp 0.85 0.55 t)), SA.class "ink-trail-sucker" ] []
            in
            Svg.path [ SA.d ("M" ++ String.join "L" (List.map (\( x, y ) -> num x ++ " " ++ num y) outline) ++ "Z") ] []
                :: Svg.circle [ SA.cx (num tipX), SA.cy (num tipY), SA.r "1.7" ] []
                :: List.map sucker [ 0.42, 0.56, 0.69, 0.81 ]

        _ ->
            []


{-| The side of an arm where its suckers are: -1 and 1 are the edges
-}
suckerSide : Float
suckerSide =
    0.35


{-| The ink of the jets that ended less than a second ago. At the start of
a jet, a few big puffs come out (fewer after a stop), and then a puff each
few units on the way, behind the head. Each puff stays where it came out,
grows, moves back a bit and fades. The puffs come from the times of the
jets, with fixed random sizes, so they are the same at each frame.
-}
viewInk : Sea -> Int -> List Jet -> List (Svg Msg)
viewInk sea now jets =
    List.map2
        (\before jet ->
            if now >= jet.at && now - jet.at < jetMs + 900 then
                jetPuffs sea now (Maybe.map (\b -> chained b jet) before |> Maybe.withDefault False) jet

            else
                []
        )
        (Nothing :: List.map Just jets)
        jets
        |> List.concat


jetPuffs : Sea -> Int -> Bool -> Jet -> List (Svg Msg)
jetPuffs sea now fromStop jet =
    let
        ( ax, ay ) =
            home sea jet.from

        ( bx, by ) =
            home sea jet.to

        angle =
            degrees (heading sea jet)

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
