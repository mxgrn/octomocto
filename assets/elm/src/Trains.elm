port module Trains exposing (main)

{-| Cooperative "Right on Track" game for 1 to 4 players.

Trains leave the station one at a time. Each train has the colors of one of
the houses. The players click the switches to send each train to the house
with its colors. Each round has a new random track layout.

The board is a grid. The tracks make a tree: the station is the root, each
switch has two branches and each house is at the end of a branch.

The server keeps the players, the seed of the round, its start time, the
switch positions and the route decisions (see `Octomocto.Trains.Game`).
Each browser makes the board and the trains from the seed and runs the
round itself, on a clock that starts at the start time of the round.

Each player owns some of the switches and can flip only those. The owner
decides the route of each train at a switch: when a train is a little
before the center of a switch cell (see `decisionPoint`), the owner's
browser picks the exit from its own switch position and sends this
decision out. The other browsers use the switch position that they know. When a decision comes and the train went the
other way, they move the train back to the switch and run it again on the
correct branch. Trains do not affect each other, so a correction changes
only one train.

A browser that joins in the middle of a round makes the round from the
seed, the switch positions and the decisions, and runs it fast up to now.

The game sends the names of sounds out through a port. app.js plays them
and connects the other ports to a Phoenix channel. The names of the
channel ports start with "trains", because Elm does not allow two ports
with the same name in one bundle.

-}

import Browser
import Browser.Events
import Dict exposing (Dict)
import Html exposing (Html, a, aside, button, div, h1, input, li, p, span, text, ul)
import Html.Attributes exposing (class, href, id, readonly, style, value)
import Html.Events exposing (onClick)
import Html.Keyed
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Random exposing (Generator)
import Set exposing (Set)
import Svg exposing (Svg)
import Svg.Attributes as SA
import Svg.Events
import Task
import Time



-- PORTS


{-| One of "switch", "depart", "correct" or "wrong".
-}
port playTrainSound : String -> Cmd msg


{-| `{cell: [x, y], value: 0 or 1}`
-}
port trainsFlip : Encode.Value -> Cmd msg


{-| `{train, cell: [x, y], exit: [x, y]}`
-}
port trainsDecision : Encode.Value -> Cmd msg


port trainsRestart : () -> Cmd msg


{-| `{seed, correct}`: the round with the seed ended, and `correct` trains
got home.
-}
port trainsFinished : Encode.Value -> Cmd msg


port trainsCopyText : String -> Cmd msg


port trainsJoined : (Decode.Value -> msg) -> Sub msg


port trainsState : (Decode.Value -> msg) -> Sub msg


port trainsFlipped : (Decode.Value -> msg) -> Sub msg


port trainsDecided : (Decode.Value -> msg) -> Sub msg


port trainsJoinFailed : (String -> msg) -> Sub msg



-- CONSTANTS


{-| The size of the board and the settings of the round. There is one
more house than there are switches.
-}
type alias Board =
    { switches : Int
    , trainsPerHouse : Int
    , pace : Pace
    , cols : Int
    , rows : Int
    }


{-| How the pause between trains changes during a round, see `pauseAfter`.
-}
type Pace
    = Easy
    | Normal
    | Hard
    | Expert


{-| The players can select 4, 6, 8 or 12 switches. All boards have the
same size.
-}
boardFor : Int -> Int -> Pace -> Board
boardFor switches trainsPerHouse pace =
    { switches = switches, trainsPerHouse = trainsPerHouse, pace = pace, cols = 9, rows = 7 }


cellSize : Float
cellSize =
    60


{-| The number of cells from the station to the first switch. Each later
switch and each house is at least 2 cells after the switch before it.
-}
firstSwitchRun : Int
firstSwitchRun =
    3


trainCount : Board -> Int
trainCount board =
    board.trainsPerHouse * (board.switches + 1)


{-| Except in the easy pace, the pause between trains gets shorter after
each train: from the pause after the first train to the pause before the
last train (see `pauseAfter`).
-}
firstPauseMs : Float
firstPauseMs =
    8000


lastPauseMs : Float
lastPauseMs =
    2000


{-| Time for a train to go through one cell on a straight track.
-}
cellMs : Float
cellMs =
    1860


{-| The time from the start of a round to the first train.
-}
firstDepartureMs : Float
firstDepartureMs =
    600


{-| A round that must run more than this to get to now runs without sounds,
for example after a join or when the tab was hidden.
-}
quietCatchUpMs : Float
quietCatchUpMs =
    1000


{-| How far a train goes through a switch cell (from 0 to 1) before its
exit is final. Up to this point, a switch change also moves the train.
-}
decisionPoint : Float
decisionPoint =
    0.4


{-| Time to show the mark above a house after a train arrives.
-}
arrivalMs : Float
arrivalMs =
    900



-- MODEL


type alias Cell =
    ( Int, Int )


type alias Point =
    ( Float, Float )


type Dir
    = North
    | East
    | South
    | West


{-| `children` has one cell for a plain track and two cells for a switch.
A house cell has no children. `houses` gives the number of each house,
from 0. The board shows the colors of the house with this number (see
`houseColors`).
-}
type alias Layout =
    { board : Board
    , station : Cell
    , children : Dict Cell (List Cell)
    , houses : Dict Cell Int
    }


{-| The track in one cell, from the side where trains come in to the side
where they go out. The station track starts at the cell center and a house
track stops there.
-}
type alias Piece =
    { start : Point
    , control : Point
    , end : Point
    , length : Float
    }


{-| A train is in `cell` and goes from the `from` side to the `exit` side.
`t` is how far it is through the cell, from 0 to 1. On a switch, the exit
follows the switch position until the train gets to `decisionPoint`. Then
the exit is final. The `id` is the number of the train in the order
of departure. `passed` has the game time when the train got to
`decisionPoint` in each switch cell, and the exit that it took there.
-}
type alias Train =
    { id : Int
    , number : Int
    , cell : Cell
    , from : Maybe Cell
    , exit : Maybe Cell
    , t : Float
    , passed : Dict Cell ( Float, Cell )
    }


type alias Arrival =
    { cell : Cell
    , correct : Bool
    , age : Float
    }


{-| One round on one board. `time` is the game time in ms since the start
of the round. `decisions` has the exits of the trains (by their ids) at
the switches. `numbers` has the house numbers of the trains that did not
leave yet.
-}
type alias Round =
    { seed : Int
    , layout : Layout
    , switches : Dict Cell Int
    , decisions : Dict ( Int, Cell ) Cell
    , time : Float
    , trains : List Train
    , numbers : List Int
    , sent : Int
    , nextDeparture : Float
    , correct : Int
    , arrived : Int
    , arrivals : List Arrival
    }


{-| The `name` is the display name of a signed-in player, or Nothing for a
guest. Then the player is known by the `colorName`. The `slot` (from 0)
selects the switches of the player.
-}
type alias Player =
    { id : String
    , name : Maybe String
    , color : String
    , colorName : String
    , slot : Int
    }


{-| `started` is True after the game has all its players.
-}
type alias Game =
    { players : List Player
    , needed : Int
    , started : Bool
    , round : Round
    }


{-| The player id of this browser. Nothing for a watcher.
-}
type alias Me =
    Maybe String


type Connection
    = Connecting
    | Joined Me Game
    | Failed String


{-| `clockStart` is the local time (in ms) at the start of the round. It is
Nothing until the round starts and the clock is in sync.
-}
type alias Model =
    { gameUrl : String
    , connection : Connection
    , copied : Bool
    , clockStart : Maybe Int
    , now : Int
    }


type alias Flags =
    { gameUrl : String }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { gameUrl = flags.gameUrl
      , connection = Connecting
      , copied = False
      , clockStart = Nothing
      , now = 0
      }
    , Cmd.none
    )


newRound : Int -> Board -> Round
newRound seed board =
    let
        ( layout, seed1 ) =
            generateLayout board (Random.initialSeed seed)

        ( switches, seed2 ) =
            Random.step (randomSwitches layout) seed1

        ( numbers, _ ) =
            Random.step (trainNumbers board) seed2
    in
    { seed = seed
    , layout = layout
    , switches = switches
    , decisions = Dict.empty
    , time = 0
    , trains = []
    , numbers = numbers
    , sent = 0
    , nextDeparture = firstDepartureMs
    , correct = 0
    , arrived = 0
    , arrivals = []
    }


randomSwitches : Layout -> Generator (Dict Cell Int)
randomSwitches layout =
    let
        cells =
            switchCells layout
    in
    Random.list (List.length cells) (Random.int 0 1)
        |> Random.map (\states -> Dict.fromList (List.map2 Tuple.pair cells states))


over : Round -> Bool
over round =
    round.arrived >= trainCount round.layout.board



-- UPDATE


type Msg
    = GotJoined Decode.Value
    | GotState Decode.Value
    | GotFlip Decode.Value
    | GotDecision Decode.Value
    | GotJoinFailed String
    | SyncClock Int Time.Posix
    | Tick Time.Posix
    | Toggle Cell
    | Restart
    | CopyLink


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotJoined value ->
            case Decode.decodeValue joinedDecoder value of
                Ok ( me, state ) ->
                    ( { model | connection = Joined me (gameFromState state), clockStart = Nothing }
                    , syncClock state
                    )

                Err error ->
                    ( { model | connection = Failed (Decode.errorToString error) }, Cmd.none )

        GotState value ->
            case ( model.connection, Decode.decodeValue stateDecoder value ) of
                ( Joined me game, Ok state ) ->
                    if state.seed /= game.round.seed then
                        -- A new round
                        ( { model | connection = Joined me (gameFromState state), clockStart = Nothing }
                        , syncClock state
                        )

                    else
                        -- The switches and the decisions come through their own
                        -- events. The state can be older than my last flip.
                        ( { model
                            | connection =
                                Joined me
                                    { game
                                        | players = state.players
                                        , needed = state.needed
                                        , started = state.elapsedMs /= Nothing
                                    }
                          }
                        , syncClock state
                        )

                _ ->
                    ( model, Cmd.none )

        GotFlip value ->
            case ( model.connection, Decode.decodeValue flipDecoder value ) of
                ( Joined me game, Ok flip ) ->
                    if Just flip.playerId == me || not (Dict.member flip.cell game.round.switches) then
                        ( model, Cmd.none )

                    else
                        let
                            round =
                                game.round
                        in
                        ( { model | connection = Joined me { game | round = { round | switches = Dict.insert flip.cell flip.value round.switches } } }
                        , Cmd.none
                        )

                _ ->
                    ( model, Cmd.none )

        GotDecision value ->
            case ( model.connection, Decode.decodeValue decisionDecoder value ) of
                ( Joined me game, Ok decision ) ->
                    if Just decision.playerId == me then
                        ( model, Cmd.none )

                    else
                        let
                            ( round, events ) =
                                applyDecision (mySwitches me game) decision game.round
                        in
                        ( { model | connection = Joined me { game | round = round } }, eventsCmd True events )

                _ ->
                    ( model, Cmd.none )

        GotJoinFailed reason ->
            ( { model | connection = Failed reason }, Cmd.none )

        SyncClock elapsedMs time ->
            let
                ms =
                    Time.posixToMillis time

                -- The state with the shortest delay gives the best clock.
                clockStart =
                    case model.clockStart of
                        Just old ->
                            min old (ms - elapsedMs)

                        Nothing ->
                            ms - elapsedMs
            in
            ( { model | clockStart = Just clockStart, now = ms }, Cmd.none )

        Tick time ->
            let
                ms =
                    Time.posixToMillis time
            in
            case ( model.connection, model.clockStart ) of
                ( Joined me game, Just clockStart ) ->
                    let
                        target =
                            toFloat (ms - clockStart)

                        -- No sounds when the round runs fast up to now, for
                        -- example after a join or when the tab was hidden.
                        sounds =
                            target - game.round.time < quietCatchUpMs

                        ( round, events ) =
                            advance (mySwitches me game) target game.round

                        -- Each player reports, and the server keeps the first
                        -- report. A watcher cannot report.
                        finished =
                            if me /= Nothing && over round && not (over game.round) then
                                trainsFinished (Encode.object [ ( "seed", Encode.int round.seed ), ( "correct", Encode.int round.correct ) ])

                            else
                                Cmd.none
                    in
                    ( { model | now = ms, connection = Joined me { game | round = round } }
                    , Cmd.batch [ eventsCmd sounds events, finished ]
                    )

                _ ->
                    ( { model | now = ms }, Cmd.none )

        Toggle cell ->
            case model.connection of
                Joined me game ->
                    if Set.member cell (mySwitches me game) then
                        let
                            round =
                                game.round

                            position =
                                1 - Maybe.withDefault 0 (Dict.get cell round.switches)
                        in
                        ( { model | connection = Joined me { game | round = { round | switches = Dict.insert cell position round.switches } } }
                        , Cmd.batch
                            [ playTrainSound "switch"
                            , trainsFlip (Encode.object [ ( "cell", encodeCell cell ), ( "value", Encode.int position ) ])
                            ]
                        )

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        Restart ->
            ( model, trainsRestart () )

        CopyLink ->
            ( { model | copied = True }, trainsCopyText model.gameUrl )


gameFromState : ServerState -> Game
gameFromState state =
    let
        round =
            newRound state.seed state.board

        switches =
            List.foldl
                (\( cell, position ) ->
                    Dict.update cell (Maybe.map (\_ -> position))
                )
                round.switches
                state.switches
    in
    { players = state.players
    , needed = state.needed
    , started = state.elapsedMs /= Nothing
    , round = { round | switches = switches, decisions = Dict.fromList state.decisions }
    }


syncClock : ServerState -> Cmd Msg
syncClock state =
    case state.elapsedMs of
        Just elapsedMs ->
            Task.perform (SyncClock elapsedMs) Time.now

        Nothing ->
            Cmd.none


type Event
    = Departed
    | Arrived Bool
    | Decided Int Cell Cell


eventsCmd : Bool -> List Event -> Cmd Msg
eventsCmd sounds events =
    Cmd.batch
        (List.map
            (\event ->
                case event of
                    Departed ->
                        if sounds then
                            playTrainSound "depart"

                        else
                            Cmd.none

                    Arrived correct ->
                        if sounds && correct then
                            playTrainSound "correct"

                        else if sounds then
                            playTrainSound "wrong"

                        else
                            Cmd.none

                    Decided train cell exit ->
                        trainsDecision
                            (Encode.object
                                [ ( "train", Encode.int train )
                                , ( "cell", encodeCell cell )
                                , ( "exit", encodeCell exit )
                                ]
                            )
            )
            (List.reverse events)
        )


encodeCell : Cell -> Encode.Value
encodeCell ( x, y ) =
    Encode.list Encode.int [ x, y ]



-- SIMULATION


{-| Run the round up to the game time `target`. `mine` has the switches
of this browser: it sends the decisions for them out.
-}
advance : Set Cell -> Float -> Round -> ( Round, List Event )
advance mine target round =
    advanceHelp mine target ( round, [] )


advanceHelp : Set Cell -> Float -> ( Round, List Event ) -> ( Round, List Event )
advanceHelp mine target ( round, events ) =
    if round.time >= target then
        ( round, events )

    else
        case round.numbers of
            number :: rest ->
                if round.nextDeparture <= target then
                    moveAll mine (max round.time round.nextDeparture) ( round, events )
                        |> depart number rest
                        |> advanceHelp mine target

                else
                    moveAll mine target ( round, events )

            [] ->
                moveAll mine target ( round, events )


depart : Int -> List Int -> ( Round, List Event ) -> ( Round, List Event )
depart number rest ( round, events ) =
    let
        train =
            enterCell round
                { id = round.sent
                , number = number
                , cell = round.layout.station
                , from = Nothing
                , exit = Nothing
                , t = 0
                , passed = Dict.empty
                }
    in
    ( { round
        | trains = round.trains ++ [ train ]
        , numbers = rest
        , sent = round.sent + 1
        , nextDeparture = round.nextDeparture + pauseAfter round.layout.board round.sent
      }
    , Departed :: events
    )


{-| Move all trains up to the game time `until`.
-}
moveAll : Set Cell -> Float -> ( Round, List Event ) -> ( Round, List Event )
moveAll mine until ( round, events ) =
    let
        delta =
            until - round.time

        aged =
            round.arrivals
                |> List.map (\arrival -> { arrival | age = arrival.age + delta })
                |> List.filter (\arrival -> arrival.age < arrivalMs)

        ( kept, round1, events1 ) =
            List.foldl
                (\train ( trains, r, evs ) ->
                    case moveTrain mine round.time delta train ( r, evs ) of
                        ( Just moved, r1, evs1 ) ->
                            ( moved :: trains, r1, evs1 )

                        ( Nothing, r1, evs1 ) ->
                            ( trains, r1, evs1 )
                )
                ( [], { round | arrivals = aged }, events )
                round.trains
    in
    ( { round1 | trains = List.reverse kept, time = until }, events1 )


{-| Move a train forward by `left` ms from the game time `clock`. Nothing
when the train gets to its house.
-}
moveTrain : Set Cell -> Float -> Float -> Train -> ( Round, List Event ) -> ( Maybe Train, Round, List Event )
moveTrain mine clock left current ( round, events ) =
    let
        train =
            followSwitch round current

        duration =
            cellMs * (trainPiece train).length

        toDecision =
            (decisionPoint - train.t) * duration

        toEnd =
            (1 - train.t) * duration
    in
    if undecided round train && left >= toDecision then
        let
            ( decided, round1, events1 ) =
                decideExit mine (clock + toDecision) { train | t = decisionPoint } ( round, events )
        in
        moveTrain mine (clock + toDecision) (left - toDecision) decided ( round1, events1 )

    else if left < toEnd then
        ( Just { train | t = train.t + left / duration }, round, events )

    else
        case train.exit of
            Just next ->
                moveTrain mine
                    (clock + toEnd)
                    (left - toEnd)
                    (enterCell round { train | cell = next, from = Just train.cell, t = 0 })
                    ( round, events )

            Nothing ->
                let
                    correct =
                        Dict.get train.cell round.layout.houses == Just train.number

                    arrival =
                        { cell = train.cell, correct = correct, age = left - toEnd }
                in
                ( Nothing
                , { round
                    | arrived = round.arrived + 1
                    , correct =
                        if correct then
                            round.correct + 1

                        else
                            round.correct
                    , arrivals = arrival :: round.arrivals
                  }
                , Arrived correct :: events
                )


{-| The train came into its cell: select its exit. On a switch, this exit
can still change, see `followSwitch`.
-}
enterCell : Round -> Train -> Train
enterCell round train =
    case Dict.get train.cell round.layout.children of
        Just [ next ] ->
            { train | exit = Just next }

        Just _ ->
            followSwitch round train

        Nothing ->
            { train | exit = Nothing }


{-| A train on a switch before `decisionPoint` has no final exit.
-}
undecided : Round -> Train -> Bool
undecided round train =
    switchExits round train /= Nothing && not (Dict.member train.cell train.passed)


{-| Before `decisionPoint`, the exit of a train on a switch follows the
switch position. A known decision comes first.
-}
followSwitch : Round -> Train -> Train
followSwitch round train =
    case ( undecided round train, switchExits round train ) of
        ( True, Just ( exit, _ ) ) ->
            { train | exit = Just exit }

        _ ->
            train


{-| The exit that a known decision or the switch position gives, and if it
comes from a decision.
-}
switchExits : Round -> Train -> Maybe ( Cell, Bool )
switchExits round train =
    case Dict.get train.cell round.layout.children of
        Just [ first, second ] ->
            case Dict.get ( train.id, train.cell ) round.decisions of
                Just decided ->
                    Just ( decided, True )

                Nothing ->
                    if Dict.get train.cell round.switches == Just 1 then
                        Just ( second, False )

                    else
                        Just ( first, False )

        _ ->
            Nothing


{-| The train got to `decisionPoint` in a switch cell at the game time `at`:
its exit is final now. Without a known decision, the owner sends this
decision out.
-}
decideExit : Set Cell -> Float -> Train -> ( Round, List Event ) -> ( Train, Round, List Event )
decideExit mine at train ( round, events ) =
    case switchExits round train of
        Just ( exit, known ) ->
            let
                ( round1, events1 ) =
                    if not known && Set.member train.cell mine then
                        ( { round | decisions = Dict.insert ( train.id, train.cell ) exit round.decisions }
                        , Decided train.id train.cell exit :: events
                        )

                    else
                        ( round, events )
            in
            ( { train | exit = Just exit, passed = Dict.insert train.cell ( at, exit ) train.passed }, round1, events1 )

        Nothing ->
            ( train, round, events )


{-| A decision of another browser. When the train already went the other
way at that switch, it goes back to `decisionPoint` on the switch and runs again
on the decided branch up to now.
-}
applyDecision : Set Cell -> RemoteDecision -> Round -> ( Round, List Event )
applyDecision mine { train, cell, exit } round =
    let
        decided =
            { round | decisions = Dict.insert ( train, cell ) exit round.decisions }

        wrong t =
            case Dict.get cell t.passed of
                Just ( _, taken ) ->
                    t.id == train && taken /= exit

                Nothing ->
                    False
    in
    case List.filter wrong round.trains of
        moved :: _ ->
            case Dict.get cell moved.passed of
                Just ( at, _ ) ->
                    let
                        again =
                            { moved
                                | cell = cell
                                , from = Dict.get cell (parents round.layout)
                                , exit = Just exit
                                , t = decisionPoint
                                , passed =
                                    moved.passed
                                        |> Dict.filter (\_ ( time, _ ) -> time < at)
                                        |> Dict.insert cell ( at, exit )
                            }

                        others =
                            { decided | trains = List.filter (\t -> t.id /= train) round.trains }

                        ( result, round1, events ) =
                            moveTrain mine at (round.time - at) again ( others, [] )
                    in
                    case result of
                        Just t ->
                            ( { round1 | trains = List.sortBy .id (t :: round1.trains) }, events )

                        Nothing ->
                            ( round1, events )

                Nothing ->
                    ( decided, [] )

        [] ->
            ( decided, [] )



-- OWNERS


{-| The switches in the order of their distance from the station.
-}
switchOrder : Layout -> List Cell
switchOrder layout =
    let
        walk queue found =
            case queue of
                [] ->
                    List.reverse found

                cell :: rest ->
                    let
                        next =
                            Dict.get cell layout.children |> Maybe.withDefault []
                    in
                    if List.length next == 2 then
                        walk (rest ++ next) (cell :: found)

                    else
                        walk (rest ++ next) found
    in
    walk [ layout.station ] []


{-| The owner of each switch. The switches are shuffled with the seed of the
round and dealt to the slots one by one, so the counts differ by 1 at most.
The switches of an empty slot (a player left) are dealt in the same way to
the players in the game, first to the players with fewer switches. The other
switches keep their owners.
-}
owners : Game -> Dict Cell Player
owners game =
    let
        ( order, _ ) =
            Random.step
                (shuffle (switchOrder game.round.layout))
                (Random.initialSeed game.round.seed)

        bySlot =
            game.players
                |> List.map (\player -> ( player.slot, player ))
                |> Dict.fromList

        dealt =
            List.indexedMap
                (\i cell -> ( cell, Dict.get (modBy (max 1 game.needed) i) bySlot ))
                order

        owned =
            List.filterMap (\( cell, owner ) -> Maybe.map (Tuple.pair cell) owner) dealt

        orphans =
            List.filterMap
                (\( cell, owner ) ->
                    if owner == Nothing then
                        Just cell

                    else
                        Nothing
                )
                dealt

        count player =
            List.length (List.filter (\( _, owner ) -> owner.id == player.id) owned)

        heirs =
            List.sortBy (\player -> ( count player, player.slot )) game.players
    in
    orphans
        |> List.indexedMap
            (\i cell ->
                List.drop (modBy (max 1 (List.length heirs)) i) heirs
                    |> List.head
                    |> Maybe.map (Tuple.pair cell)
            )
        |> List.filterMap identity
        |> (++) owned
        |> Dict.fromList


mySwitches : Me -> Game -> Set Cell
mySwitches me game =
    case me of
        Just playerId ->
            owners game
                |> Dict.filter (\_ player -> player.id == playerId)
                |> Dict.keys
                |> Set.fromList

        Nothing ->
            Set.empty



-- DECODERS


type alias ServerState =
    { seed : Int
    , board : Board
    , players : List Player
    , needed : Int
    , elapsedMs : Maybe Int
    , switches : List ( Cell, Int )
    , decisions : List ( ( Int, Cell ), Cell )
    }


type alias RemoteFlip =
    { playerId : String
    , cell : Cell
    , value : Int
    }


type alias RemoteDecision =
    { playerId : String
    , train : Int
    , cell : Cell
    , exit : Cell
    }


joinedDecoder : Decoder ( Me, ServerState )
joinedDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "player_id" (Decode.nullable Decode.string))
        (Decode.field "state" stateDecoder)


stateDecoder : Decoder ServerState
stateDecoder =
    Decode.map7 ServerState
        (Decode.field "seed" Decode.int)
        (Decode.map3 boardFor
            (Decode.field "switch_count" Decode.int)
            (Decode.field "trains_per_house" Decode.int)
            (Decode.field "pace" paceDecoder)
        )
        (Decode.field "players" (Decode.list playerDecoder))
        (Decode.field "players_needed" Decode.int)
        (Decode.field "elapsed_ms" (Decode.nullable Decode.int))
        (Decode.field "switches"
            (Decode.list
                (Decode.map2 Tuple.pair
                    (Decode.field "cell" cellDecoder)
                    (Decode.field "value" Decode.int)
                )
            )
        )
        (Decode.field "decisions"
            (Decode.list
                (Decode.map3 (\train cell exit -> ( ( train, cell ), exit ))
                    (Decode.field "train" Decode.int)
                    (Decode.field "cell" cellDecoder)
                    (Decode.field "exit" cellDecoder)
                )
            )
        )


playerDecoder : Decoder Player
playerDecoder =
    Decode.map5 Player
        (Decode.field "id" Decode.string)
        (Decode.field "name" (Decode.nullable Decode.string))
        (Decode.field "color" Decode.string)
        (Decode.field "color_name" Decode.string)
        (Decode.field "slot" Decode.int)


flipDecoder : Decoder RemoteFlip
flipDecoder =
    Decode.map3 RemoteFlip
        (Decode.field "player_id" Decode.string)
        (Decode.field "cell" cellDecoder)
        (Decode.field "value" Decode.int)


decisionDecoder : Decoder RemoteDecision
decisionDecoder =
    Decode.map4 RemoteDecision
        (Decode.field "player_id" Decode.string)
        (Decode.field "train" Decode.int)
        (Decode.field "cell" cellDecoder)
        (Decode.field "exit" cellDecoder)


paceDecoder : Decoder Pace
paceDecoder =
    Decode.string
        |> Decode.map
            (\pace ->
                case pace of
                    "easy" ->
                        Easy

                    "hard" ->
                        Hard

                    "expert" ->
                        Expert

                    _ ->
                        Normal
            )


cellDecoder : Decoder Cell
cellDecoder =
    Decode.map2 Tuple.pair (Decode.index 0 Decode.int) (Decode.index 1 Decode.int)



-- TRAINS


{-| The house numbers of all trains in one game, in order. Each house gets
the same number of trains, or one more if the trains do not divide equally.
Two trains in a row never go to the same house.
-}
trainNumbers : Board -> Generator (List Int)
trainNumbers board =
    let
        houseCount =
            board.switches + 1

        count =
            trainCount board
    in
    shuffle (List.range 0 board.switches)
        |> Random.andThen
            (\order ->
                order
                    |> List.indexedMap
                        (\i number ->
                            if i < modBy houseCount count then
                                ( number, count // houseCount + 1 )

                            else
                                ( number, count // houseCount )
                        )
                    |> Dict.fromList
                    |> orderNumbers
            )


{-| Put the numbers in a random order. Try again if the last trains left
can only have the same number in a row.
-}
orderNumbers : Dict Int Int -> Generator (List Int)
orderNumbers counts =
    pickNumbers counts Nothing []
        |> Random.andThen
            (\result ->
                case result of
                    Just numbers ->
                        Random.constant numbers

                    Nothing ->
                        Random.lazy (\_ -> orderNumbers counts)
            )


{-| Numbers with more trains left are more likely, so the last trains do
not all have the same number.
-}
pickNumbers : Dict Int Int -> Maybe Int -> List Int -> Generator (Maybe (List Int))
pickNumbers counts last picked =
    let
        options =
            Dict.toList counts
                |> List.filter (\( number, left ) -> left > 0 && Just number /= last)
                |> List.map (\( number, left ) -> ( toFloat left, number ))
    in
    if List.all (\left -> left == 0) (Dict.values counts) then
        Random.constant (Just (List.reverse picked))

    else
        case options of
            first :: rest ->
                Random.weighted first rest
                    |> Random.andThen
                        (\number ->
                            pickNumbers (Dict.update number (Maybe.map (\left -> left - 1)) counts) (Just number) (number :: picked)
                        )

            [] ->
                Random.constant Nothing


{-| The pause after the train with the index `sent` (from 0). Easy keeps
the first pause. The other paces go from the first pause to the last pause:
normal on a line, hard on a square curve, and expert on a steep exponential
curve. The harder curves get short sooner.
-}
pauseAfter : Board -> Int -> Float
pauseAfter board sent =
    let
        pauses =
            trainCount board - 1

        -- How far through the round, from 0 to 1
        x =
            if pauses <= 1 then
                0

            else
                toFloat sent / toFloat (pauses - 1)

        -- From 1 at the start to 0 at the end
        left =
            case board.pace of
                Easy ->
                    1

                Normal ->
                    1 - x

                Hard ->
                    (1 - x) ^ 2

                Expert ->
                    (e ^ (-5 * x) - e ^ -5) / (1 - e ^ -5)
    in
    lastPauseMs + (firstPauseMs - lastPauseMs) * left



-- LAYOUT


{-| The end of a track that is still growing. `run` is the number of cells
since the last switch (or the station).
-}
type alias Tip =
    { cell : Cell
    , dir : Dir
    , run : Int
    }


type alias Growth =
    { board : Board
    , occupied : Set Cell
    , children : Dict Cell (List Cell)
    , tips : List Tip
    , houses : List Cell
    , splits : Int
    , failed : Bool
    }


{-| Make some correct layouts and keep the one with the shortest tracks.
-}
generateLayout : Board -> Random.Seed -> ( Layout, Random.Seed )
generateLayout board seed =
    let
        ( first, seed1 ) =
            generateLayoutHelp board 1000 seed
    in
    pickBestLayout board (layoutCandidates - 1) first seed1


layoutCandidates : Int
layoutCandidates =
    40


pickBestLayout : Board -> Int -> Layout -> Random.Seed -> ( Layout, Random.Seed )
pickBestLayout board left best seed =
    if left <= 0 then
        ( best, seed )

    else
        let
            ( layout, nextSeed ) =
                generateLayoutHelp board 1000 seed
        in
        if layoutScore layout > layoutScore best then
            pickBestLayout board (left - 1) layout nextSeed

        else
            pickBestLayout board (left - 1) best nextSeed


{-| Fewer cells with a track give a better score, so the tracks do not wind
more than necessary. Between layouts with the same number of cells, the
tracks that spread more evenly win: the board is divided into 3 × 3 areas,
and each area with a track counts, then each row and each column with a
track.
-}
layoutScore : Layout -> Int
layoutScore layout =
    let
        cells =
            layout.station :: Dict.keys (parents layout)

        area ( x, y ) =
            ( x * 3 // layout.board.cols, y * 3 // layout.board.rows )

        count f =
            Set.size (Set.fromList (List.map f cells))
    in
    10 * count area + count Tuple.first + count Tuple.second - 100 * List.length cells


generateLayoutHelp : Board -> Int -> Random.Seed -> ( Layout, Random.Seed )
generateLayoutHelp board attemptsLeft seed =
    let
        ( ( station, growth ), seed1 ) =
            Random.step (growLayout board) seed

        ( numbers, seed2 ) =
            Random.step (shuffle (List.range 0 board.switches)) seed1

        layout =
            { board = board
            , station = station
            , children = growth.children
            , houses = Dict.fromList (List.map2 Tuple.pair growth.houses numbers)
            }
    in
    if (not growth.failed && growth.splits == board.switches) || attemptsLeft <= 1 then
        ( layout, seed2 )

    else
        generateLayoutHelp board (attemptsLeft - 1) seed2


growLayout : Board -> Generator ( Cell, Growth )
growLayout board =
    Random.int 1 (board.rows - 2)
        |> Random.andThen
            (\row ->
                let
                    station =
                        ( 0, row )
                in
                grow
                    { board = board
                    , occupied = Set.singleton station
                    , children = Dict.empty
                    , tips = [ { cell = station, dir = East, run = 0 } ]
                    , houses = []
                    , splits = 0
                    , failed = False
                    }
                    |> Random.map (Tuple.pair station)
            )


grow : Growth -> Generator Growth
grow growth =
    if List.isEmpty growth.tips || growth.failed then
        Random.constant growth

    else
        Random.map2 (growTip growth)
            (Random.int 0 (List.length growth.tips - 1))
            (Random.float 0 1)
            |> Random.andThen grow


{-| Make one tip split into a switch, stop at a house, or go one cell forward.
The first switch is `firstSwitchRun` cells after the station. Each other
switch and each house has one plain cell before it. A tip goes further
only when it has no space to split.
-}
growTip : Growth -> Int -> Float -> Growth
growTip growth index dirRoll =
    case List.drop index growth.tips of
        [] ->
            growth

        tip :: _ ->
            let
                rest =
                    { growth | tips = List.take index growth.tips ++ List.drop (index + 1) growth.tips }

                options =
                    [ tip.dir, turnLeft tip.dir, turnRight tip.dir ]
                        |> List.map (\d -> ( d, step d tip.cell ))
                        |> List.filter (\( _, cell ) -> free growth.board growth.occupied cell)

                allSplit =
                    growth.splits == growth.board.switches

                -- Before the first split, the only tip is the station track.
                splitRun =
                    if growth.splits == 0 then
                        firstSwitchRun

                    else
                        2
            in
            if tip.run >= splitRun && not allSplit && List.length options >= 2 then
                split tip (pickTwo dirRoll options) rest

            else if List.isEmpty options || (allSplit && tip.run >= 2) then
                if tip.run >= 2 then
                    { rest | houses = tip.cell :: rest.houses }

                else
                    { rest | failed = True }

            else
                -- Go straight more often than turn.
                case List.drop (floor (dirRoll * toFloat (List.length options + 1))) (List.take 1 options ++ options) of
                    ( dir, cell ) :: _ ->
                        { rest
                            | occupied = Set.insert cell rest.occupied
                            , children = Dict.insert tip.cell [ cell ] rest.children
                            , tips = { cell = cell, dir = dir, run = tip.run + 1 } :: rest.tips
                        }

                    [] ->
                        { rest | failed = True }


split : Tip -> List ( Dir, Cell ) -> Growth -> Growth
split tip branches growth =
    { growth
        | occupied = List.foldl (\( _, cell ) -> Set.insert cell) growth.occupied branches
        , children = Dict.insert tip.cell (List.map Tuple.second branches) growth.children
        , tips = List.map (\( dir, cell ) -> { cell = cell, dir = dir, run = 1 }) branches ++ growth.tips
        , splits = growth.splits + 1
    }


pickTwo : Float -> List a -> List a
pickTwo roll options =
    if List.length options > 2 then
        let
            skip =
                floor (roll * toFloat (List.length options))
        in
        List.take skip options ++ List.drop (skip + 1) options

    else
        options


shuffle : List a -> Generator (List a)
shuffle items =
    Random.list (List.length items) (Random.float 0 1)
        |> Random.map
            (\keys ->
                List.map2 Tuple.pair keys items
                    |> List.sortBy Tuple.first
                    |> List.map Tuple.second
            )


free : Board -> Set Cell -> Cell -> Bool
free board occupied (( x, y ) as cell) =
    x >= 0 && x < board.cols && y >= 0 && y < board.rows && not (Set.member cell occupied)


step : Dir -> Cell -> Cell
step dir ( x, y ) =
    case dir of
        North ->
            ( x, y - 1 )

        East ->
            ( x + 1, y )

        South ->
            ( x, y + 1 )

        West ->
            ( x - 1, y )


turnLeft : Dir -> Dir
turnLeft dir =
    case dir of
        North ->
            West

        East ->
            North

        South ->
            East

        West ->
            South


turnRight : Dir -> Dir
turnRight dir =
    case dir of
        North ->
            East

        East ->
            South

        South ->
            West

        West ->
            North


switchCells : Layout -> List Cell
switchCells layout =
    Dict.keys (Dict.filter (\_ next -> List.length next == 2) layout.children)


parents : Layout -> Dict Cell Cell
parents layout =
    Dict.foldl
        (\cell next acc -> List.foldl (\child -> Dict.insert child cell) acc next)
        Dict.empty
        layout.children



-- GEOMETRY


center : Cell -> Point
center ( x, y ) =
    ( (toFloat x + 0.5) * cellSize, (toFloat y + 0.5) * cellSize )


piece : Cell -> Maybe Cell -> Maybe Cell -> Piece
piece cell from exit =
    let
        c =
            center cell

        side other =
            midpoint c (center other)
    in
    { start = Maybe.map side from |> Maybe.withDefault c
    , control = c
    , end = Maybe.map side exit |> Maybe.withDefault c
    , length =
        case ( from, exit ) of
            ( Just ( ax, ay ), Just ( bx, by ) ) ->
                if ax == bx || ay == by then
                    1

                else
                    -- A quarter circle with a radius of half a cell
                    pi / 4

            _ ->
                0.5
    }


trainPiece : Train -> Piece
trainPiece train =
    piece train.cell train.from train.exit


midpoint : Point -> Point -> Point
midpoint ( ax, ay ) ( bx, by ) =
    ( (ax + bx) / 2, (ay + by) / 2 )


pointAt : Piece -> Float -> Point
pointAt { start, control, end } t =
    let
        mix a b c =
            (1 - t) * (1 - t) * a + 2 * (1 - t) * t * b + t * t * c
    in
    ( mix (Tuple.first start) (Tuple.first control) (Tuple.first end)
    , mix (Tuple.second start) (Tuple.second control) (Tuple.second end)
    )


{-| The direction of travel, in degrees. 0 is east.
-}
angleAt : Piece -> Float -> Float
angleAt { start, control, end } t =
    let
        slope a b c =
            2 * (1 - t) * (b - a) + 2 * t * (c - b)

        dx =
            slope (Tuple.first start) (Tuple.first control) (Tuple.first end)

        dy =
            slope (Tuple.second start) (Tuple.second control) (Tuple.second end)
    in
    atan2 dy dx * 180 / pi



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ trainsJoined GotJoined
        , trainsState GotState
        , trainsFlipped GotFlip
        , trainsDecided GotDecision
        , trainsJoinFailed GotJoinFailed
        , case model.connection of
            Joined _ game ->
                if game.started && not (over game.round) then
                    Browser.Events.onAnimationFrame Tick

                else
                    Sub.none

            _ ->
                Sub.none
        ]



-- VIEW


type Phase
    = Waiting
    | Countdown Int
    | Playing
    | Over


phase : Model -> Game -> Phase
phase model game =
    if not game.started then
        Waiting

    else if over game.round then
        Over

    else
        case model.clockStart of
            Just clockStart ->
                if model.now < clockStart then
                    Countdown (ceiling (toFloat (clockStart - model.now) / 1000))

                else
                    Playing

            Nothing ->
                Playing


view : Model -> Html Msg
view model =
    case model.connection of
        Connecting ->
            p [ id "trains-connecting", class "py-24 text-center opacity-60" ] [ text "Joining the game…" ]

        Failed reason ->
            p [ id "trains-failed", class "py-24 text-center text-red-600 dark:text-red-400" ] [ text ("Could not join the game: " ++ reason) ]

        Joined me game ->
            viewGame model me game


viewGame : Model -> Me -> Game -> Html Msg
viewGame model me game =
    let
        owned =
            owners game

        solo =
            game.needed == 1
    in
    div [ id "trains-root", class "flex w-full max-w-[1400px] flex-col gap-5 select-none lg:flex-row lg:items-start lg:gap-8" ]
        [ aside [ id "trains-panel", class "flex flex-col gap-4 lg:sticky lg:top-6 lg:w-72 lg:shrink-0" ]
            [ div []
                [ h1 [ class "text-2xl font-semibold tracking-tight" ]
                    [ a [ id "trains-title-link", href "/trains", class "transition hover:text-octo-indigo dark:hover:text-octo-indigo-light" ] [ text "Right on Track" ] ]
                , p [ class "text-sm opacity-60" ]
                    [ text
                        (if solo then
                            "Click the switches to send each train to the house with its colors."

                         else
                            "Send each train to the house with its colors. You can flip only the switches in your color."
                        )
                    ]
                ]
            , viewStats game.round
            , if solo then
                text ""

              else
                viewShareLink model
            , if solo then
                text ""

              else
                viewPlayers me game owned
            , if me == Nothing then
                p [ id "trains-watching", class "rounded-2xl bg-amber-50 px-4 py-3 text-sm text-amber-900 ring-1 ring-amber-200 dark:bg-amber-400/10 dark:text-amber-200 dark:ring-amber-400/25" ]
                    [ text "This game is full or has started, so you can only watch it." ]

              else
                viewRestartButton
            ]
        , div [ class "min-w-0 flex-1" ]
            [ div [ class "relative mx-auto", style "width" (boardWidth game.round.layout.board) ]
                [ if phase model game == Waiting then
                    -- The players see the board only when all can see it
                    viewEmptyBoard game.round.layout.board

                  else
                    viewBoard me game owned
                , viewOverlay model me game
                ]
            ]
        ]


{-| Make the board as wide as possible, but never taller than the screen,
so that the footer is also on the screen (minus the 4rem header, the 1.5rem
bottom padding of the page and the 4rem footer).
-}
boardWidth : Board -> String
boardWidth board =
    "min(100%, calc((100dvh - 9.5rem) * " ++ String.fromFloat (toFloat board.cols / toFloat board.rows) ++ "))"


viewStats : Round -> Html Msg
viewStats round =
    div [ class "flex gap-2 text-sm" ]
        [ div [ id "trains-correct", class "rounded-full bg-emerald-50 px-3 py-1 text-emerald-900 ring-1 ring-emerald-200 dark:bg-emerald-400/10 dark:text-emerald-200 dark:ring-emerald-400/25" ]
            [ text "Correct ", span [ class "font-semibold tabular-nums" ] [ text (String.fromInt round.correct) ] ]
        , div [ id "trains-sent", class "rounded-full bg-white px-3 py-1 text-slate-700 shadow-sm ring-1 ring-slate-200 dark:bg-white/5 dark:text-slate-200 dark:shadow-none dark:ring-white/10" ]
            [ text "Train "
            , span [ class "font-semibold tabular-nums" ]
                [ text (String.fromInt round.sent ++ " / " ++ String.fromInt (trainCount round.layout.board)) ]
            ]
        ]


viewShareLink : Model -> Html Msg
viewShareLink model =
    div [ class "flex items-center gap-2 rounded-full bg-octo-mist p-1 pl-4 text-sm ring-1 ring-octo-indigo/20 lg:flex-col lg:items-stretch lg:rounded-2xl lg:p-2 lg:pl-2 dark:bg-octo-indigo/15 dark:ring-octo-indigo-light/25" ]
        [ input
            [ id "trains-link"
            , readonly True
            , value model.gameUrl
            , class "min-w-0 flex-1 truncate bg-transparent text-octo-navy outline-none lg:px-2 lg:py-1 dark:text-slate-100"
            ]
            []
        , button
            [ id "trains-copy-link"
            , class "rounded-full bg-octo-indigo px-4 py-1.5 font-medium text-white transition hover:bg-octo-indigo/90 active:scale-95"
            , onClick CopyLink
            ]
            [ text
                (if model.copied then
                    "Copied!"

                 else
                    "Copy link"
                )
            ]
        ]


viewPlayers : Me -> Game -> Dict Cell Player -> Html Msg
viewPlayers me game owned =
    Html.Keyed.ul [ id "trains-players", class "flex flex-wrap gap-2 lg:flex-col" ]
        (List.map
            (\player ->
                let
                    count =
                        Dict.size (Dict.filter (\_ owner -> owner.id == player.id) owned)
                in
                ( player.id
                , li
                    [ id ("trains-player-" ++ player.id)
                    , class "flex items-center gap-2 rounded-full bg-white px-3 py-1 text-sm text-slate-800 shadow-sm ring-1 ring-slate-200 dark:bg-white/5 dark:text-slate-100 dark:shadow-none dark:ring-white/10"
                    ]
                    [ span [ class "size-3 rounded-full", style "background" player.color ] []
                    , span [ class "lg:flex-1" ] [ text (playerName me player) ]
                    , span [ class "text-xs text-slate-500 tabular-nums dark:text-slate-400" ]
                        [ text
                            (String.fromInt count
                                ++ (if count == 1 then
                                        " switch"

                                    else
                                        " switches"
                                   )
                            )
                        ]
                    ]
                )
            )
            game.players
        )


playerName : Me -> Player -> String
playerName me player =
    if me == Just player.id then
        Maybe.withDefault player.colorName player.name ++ " (you)"

    else
        Maybe.withDefault player.colorName player.name


{-| Starts a new round with a new board for all players, also during a
round.
-}
viewRestartButton : Html Msg
viewRestartButton =
    button
        [ id "trains-restart"
        , class "group flex items-center justify-center gap-2 rounded-full px-4 py-2 text-sm font-medium text-slate-600 ring-1 ring-slate-200 transition hover:bg-slate-50 hover:text-slate-900 hover:ring-slate-300 active:scale-95 lg:self-start dark:text-slate-300 dark:ring-white/20 dark:hover:bg-white/10 dark:hover:text-white dark:hover:ring-white/30"
        , onClick Restart
        ]
        [ span [ class "hero-arrow-path size-4 transition-transform duration-300 group-hover:-rotate-180" ] []
        , text "New board"
        ]


viewOverlay : Model -> Me -> Game -> Html Msg
viewOverlay model me game =
    case phase model game of
        Waiting ->
            overlay "trains-waiting"
                [ p [ class "text-2xl font-semibold" ] [ text "Waiting for players" ]
                , p [ id "trains-waiting-count", class "text-lg tabular-nums opacity-80" ]
                    [ text
                        (String.fromInt (List.length game.players)
                            ++ " of "
                            ++ String.fromInt game.needed
                            ++ " players are in"
                        )
                    ]
                , span [ class "text-sm opacity-70" ] [ text "Send the link to the other players." ]
                ]

        Countdown seconds ->
            -- No dark layer, so that the players can still look at the board
            div
                [ id "trains-countdown"
                , class "pointer-events-none absolute inset-0 flex items-center justify-center"
                ]
                [ Html.Keyed.node "div"
                    []
                    [ ( String.fromInt seconds
                      , p
                            [ class "countdown-pop text-9xl font-bold text-white tabular-nums"
                            , style "text-shadow" "0 4px 24px rgb(15 23 42 / 0.6), 0 0 2px rgb(15 23 42 / 0.8)"
                            ]
                            [ text (String.fromInt seconds) ]
                      )
                    ]
                ]

        Playing ->
            text ""

        Over ->
            overlay "trains-over"
                [ p [ id "trains-result", class "text-2xl font-semibold" ]
                    [ text (String.fromInt game.round.correct ++ " of " ++ String.fromInt (trainCount game.round.layout.board) ++ " trains got home") ]
                , span [ class "text-sm opacity-80" ] [ text (verdict game.round) ]
                , if me == Nothing then
                    text ""

                  else
                    overlayButton "trains-again" Restart "Play again"
                ]


verdict : Round -> String
verdict round =
    let
        total =
            trainCount round.layout.board
    in
    if round.correct == total then
        "Perfect!"

    else if round.correct * 3 >= total * 2 then
        "Good work."

    else
        "Try again with a new layout."


overlay : String -> List (Html Msg) -> Html Msg
overlay overlayId =
    div [ id overlayId, class "absolute inset-0 flex flex-col items-center justify-center gap-2 rounded-2xl bg-slate-900/55 p-4 text-center text-white backdrop-blur-[2px]" ]


overlayButton : String -> Msg -> String -> Html Msg
overlayButton buttonId msg label =
    button
        [ id buttonId
        , class "mt-3 rounded-full bg-octo-indigo px-6 py-2.5 font-medium text-white shadow-lg shadow-octo-indigo/30 transition hover:-translate-y-0.5 hover:bg-octo-indigo/90 active:translate-y-0"
        , onClick msg
        ]
        [ text label ]


{-| Only the ground, with the same size as the board
-}
viewEmptyBoard : Board -> Html Msg
viewEmptyBoard board =
    let
        width =
            toFloat board.cols * cellSize

        height =
            toFloat board.rows * cellSize
    in
    Svg.svg
        [ SA.id "trains-board-hidden"
        , SA.viewBox ("0 0 " ++ String.fromFloat width ++ " " ++ String.fromFloat height)
        , SA.class "block h-auto w-full"
        ]
        [ Svg.rect [ SA.width (String.fromFloat width), SA.height (String.fromFloat height), SA.rx "16", SA.fill "#ecfccb", SA.class "trains-ground" ] [] ]


viewBoard : Me -> Game -> Dict Cell Player -> Html Msg
viewBoard me game owned =
    let
        round =
            game.round

        width =
            toFloat round.layout.board.cols * cellSize

        height =
            toFloat round.layout.board.rows * cellSize

        rails =
            trackPieces round

        switches =
            switchCells round.layout

        mine cell =
            me /= Nothing && Maybe.map .id (Dict.get cell owned) == me
    in
    Svg.svg
        [ SA.id "trains-board"
        , SA.viewBox ("0 0 " ++ String.fromFloat width ++ " " ++ String.fromFloat height)
        , SA.class "block h-auto w-full"
        ]
        [ Svg.rect [ SA.width (String.fromFloat width), SA.height (String.fromFloat height), SA.rx "16", SA.fill "#ecfccb", SA.class "trains-ground" ] []
        , Svg.g []
            (List.map
                (\cell ->
                    if game.needed == 1 then
                        viewSwitchPad cell

                    else
                        viewOwnedPad (mine cell) (Dict.get cell owned) cell
                )
                switches
            )
        , Svg.defs []
            [ Svg.mask [ SA.id "trains-outside-switches" ]
                (Svg.rect [ SA.width (String.fromFloat width), SA.height (String.fromFloat height), SA.fill "white" ] []
                    :: List.map (\cell -> switchCircle cell [ SA.fill "black" ]) switches
                )
            ]
        , Svg.g [ SA.opacity "0.2" ] (railsOf SwitchOff "#57534e" rails)

        -- Outside the switch circle, the branch that is off looks like a plain track.
        , Svg.g [ SA.mask "url(#trains-outside-switches)" ] (railsOf SwitchOff "#57534e" rails)
        , Svg.g [] (railsOf Plain "#57534e" rails)
        , Svg.g [] (railsOf SwitchOn "#57534e" rails)
        , Svg.g [] (List.map viewSwitchTarget (List.filter mine switches))
        , Svg.g [ SA.pointerEvents "none" ] (List.map viewTrain round.trains)
        , viewStation round.layout.station
        , Svg.g [ SA.pointerEvents "none" ] (List.map viewHouse (Dict.toList round.layout.houses))
        , Svg.g [ SA.pointerEvents "none" ] (List.map viewArrival round.arrivals)
        ]


{-| A switch shows the branch that it points to now in full color and the
other branch faded, so the player can see where the next train goes.
-}
type Rail
    = Plain
    | SwitchOn
    | SwitchOff


trackPieces : Round -> List ( Piece, Rail )
trackPieces round =
    let
        layout =
            round.layout

        parentOf =
            parents layout

        cellPieces cell =
            let
                from =
                    Dict.get cell parentOf
            in
            case Dict.get cell layout.children of
                Just [ exit ] ->
                    [ ( piece cell from (Just exit), Plain ) ]

                Just [ first, second ] ->
                    let
                        on =
                            if Dict.get cell round.switches == Just 1 then
                                second

                            else
                                first
                    in
                    List.map
                        (\exit ->
                            ( piece cell from (Just exit)
                            , if exit == on then
                                SwitchOn

                              else
                                SwitchOff
                            )
                        )
                        [ first, second ]

                _ ->
                    [ ( piece cell from Nothing, Plain ) ]
    in
    List.concatMap cellPieces (layout.station :: Dict.keys parentOf)


viewSwitchPad : Cell -> Svg msg
viewSwitchPad cell =
    switchCircle cell [ SA.fill "#fef3c7", SA.stroke "#fcd34d", SA.strokeWidth "2", SA.class "trains-pad" ]


{-| A switch in the color of its owner. The switches of the other players
are lighter and have a dashed border.
-}
viewOwnedPad : Bool -> Maybe Player -> Cell -> Svg msg
viewOwnedPad mine owner cell =
    let
        color =
            Maybe.map .color owner |> Maybe.withDefault "#a8a29e"
    in
    if mine then
        switchCircle cell [ SA.fill color, SA.fillOpacity "0.22", SA.stroke color, SA.strokeWidth "3" ]

    else
        switchCircle cell
            [ SA.fill color
            , SA.fillOpacity "0.08"
            , SA.stroke color
            , SA.strokeOpacity "0.7"
            , SA.strokeWidth "2"
            , SA.strokeDasharray "5 4"
            ]


{-| An invisible click target above the rails. It lights up on hover.
-}
viewSwitchTarget : Cell -> Svg Msg
viewSwitchTarget (( x, y ) as cell) =
    switchCircle cell
        [ SA.id ("trains-switch-" ++ String.fromInt x ++ "-" ++ String.fromInt y)
        , SA.class "cursor-pointer fill-transparent transition-colors hover:fill-amber-300/30"
        , Svg.Events.onClick (Toggle cell)
        ]


pathData : Piece -> String
pathData { start, control, end } =
    let
        pt ( x, y ) =
            String.fromFloat x ++ " " ++ String.fromFloat y
    in
    "M" ++ pt start ++ " Q" ++ pt control ++ " " ++ pt end


railsOf : Rail -> String -> List ( Piece, Rail ) -> List (Svg msg)
railsOf rail color =
    List.filterMap
        (\( p, r ) ->
            if r == rail then
                Just (viewRails color p)

            else
                Nothing
        )


{-| Two rails.
-}
viewRails : String -> Piece -> Svg msg
viewRails color p =
    Svg.g [ SA.fill "none" ]
        [ Svg.path [ SA.d (pathData p), SA.stroke color, SA.strokeWidth "11", SA.class "trains-rail" ] []
        , Svg.path [ SA.d (pathData p), SA.stroke "#e7e5e4", SA.strokeWidth "6", SA.class "trains-track-bed" ] []
        ]


switchCircle : Cell -> List (Svg.Attribute msg) -> Svg msg
switchCircle cell attrs =
    let
        ( cx, cy ) =
            center cell
    in
    Svg.circle
        ([ SA.cx (String.fromFloat cx)
         , SA.cy (String.fromFloat cy)
         , SA.r (String.fromFloat (cellSize / 2 - 4))
         ]
            ++ attrs
        )
        []


{-| The roof and wall colors of each house, by its number. The first houses
have one color, and the next houses have two colors, so that the colors stay
different also on the largest boards. No two houses have the same two colors
in the opposite order.
-}
houseColors : Int -> { roof : String, walls : String }
houseColors number =
    let
        red =
            "#c93636"

        blue =
            "#3b82f6"

        yellow =
            "#facc15"

        purple =
            "#a855f7"

        orange =
            "#fb923c"

        black =
            "#334155"

        white =
            "#f8fafc"

        pairs =
            [ ( red, red )
            , ( blue, blue )
            , ( yellow, yellow )
            , ( purple, purple )
            , ( orange, orange )
            , ( black, black )
            , ( white, white )
            , ( black, yellow )
            , ( red, white )
            , ( blue, orange )
            , ( yellow, purple )
            , ( white, blue )
            , ( orange, black )
            ]
    in
    case List.drop (modBy (List.length pairs) number) pairs of
        ( roof, walls ) :: _ ->
            { roof = roof, walls = walls }

        [] ->
            { roof = black, walls = black }


{-| The body of the train has the wall color of its house, and the cab has
the roof color.
-}
viewTrain : Train -> Svg msg
viewTrain train =
    let
        p =
            trainPiece train

        colors =
            houseColors train.number
    in
    Svg.g
        [ SA.transform
            (translate (pointAt p train.t) ++ " rotate(" ++ String.fromFloat (angleAt p train.t) ++ ")")
        ]
        [ Svg.rect [ SA.x "-16", SA.y "-11", SA.width "32", SA.height "22", SA.rx "6", SA.fill colors.walls, SA.stroke "#1e293b", SA.strokeWidth "2" ] []
        , Svg.rect [ SA.x "-11", SA.y "-7", SA.width "14", SA.height "14", SA.rx "3", SA.fill colors.roof, SA.stroke "#1e293b", SA.strokeWidth "1.5" ] []
        ]


viewStation : Cell -> Svg msg
viewStation cell =
    Svg.g [ SA.id "trains-station", SA.transform (translate (center cell)), SA.pointerEvents "none" ]
        [ Svg.rect [ SA.x "-24", SA.y "-22", SA.width "44", SA.height "44", SA.rx "9", SA.fill "#334155" ] []
        , Svg.rect [ SA.x "-16", SA.y "-14", SA.width "28", SA.height "7", SA.rx "2", SA.fill "#fbbf24" ] []
        , Svg.rect [ SA.x "-16", SA.y "1", SA.width "11", SA.height "13", SA.rx "2", SA.fill "#94a3b8" ] []
        , Svg.rect [ SA.x "1", SA.y "1", SA.width "11", SA.height "13", SA.rx "2", SA.fill "#94a3b8" ] []
        ]


viewHouse : ( Cell, Int ) -> Svg msg
viewHouse ( ( x, y ) as cell, number ) =
    let
        colors =
            houseColors number
    in
    Svg.g
        [ SA.id ("trains-house-" ++ String.fromInt x ++ "-" ++ String.fromInt y)
        , SA.transform (translate (center cell))
        ]
        [ Svg.ellipse [ SA.cx "0", SA.cy "17", SA.rx "18", SA.ry "4", SA.fill "#365314", SA.opacity "0.2", SA.class "trains-shadow" ] []
        , Svg.rect [ SA.x "-15", SA.y "-9", SA.width "30", SA.height "25", SA.rx "3", SA.fill colors.walls, SA.stroke "#1e293b", SA.strokeWidth "2" ] []
        , Svg.rect [ SA.x "-4", SA.y "4", SA.width "8", SA.height "12", SA.rx "1", SA.fill "#1e293b", SA.fillOpacity "0.35" ] []
        , Svg.polygon [ SA.points "-20,-7 0,-25 20,-7", SA.fill colors.roof, SA.strokeLinejoin "round", SA.stroke "#1e293b", SA.strokeWidth "2" ] []
        ]


{-| The mark is on the walls of the house, so that it stays on the board
also for a house in the top row. It grows a little and fades out. The white
border keeps it visible on a red or a green house.
-}
viewArrival : Arrival -> Svg msg
viewArrival arrival =
    let
        ( x, y ) =
            center arrival.cell

        progress =
            arrival.age / arrivalMs
    in
    Svg.g
        [ SA.transform (translate ( x, y + 5 ) ++ " scale(" ++ String.fromFloat (0.8 + 0.3 * progress) ++ ")")
        , SA.opacity (String.fromFloat (1 - progress * progress))
        ]
        [ Svg.circle
            [ SA.r "11"
            , SA.stroke "white"
            , SA.strokeWidth "2"
            , SA.fill
                (if arrival.correct then
                    "#16a34a"

                 else
                    "#dc2626"
                )
            ]
            []
        , Svg.path
            [ SA.d
                (if arrival.correct then
                    "M-5 0 L-1.5 4 L5 -4"

                 else
                    "M-4 -4 L4 4 M4 -4 L-4 4"
                )
            , SA.fill "none"
            , SA.stroke "white"
            , SA.strokeWidth "2.5"
            , SA.strokeLinecap "round"
            , SA.strokeLinejoin "round"
            ]
            []
        ]


translate : Point -> String
translate ( x, y ) =
    "translate(" ++ String.fromFloat x ++ " " ++ String.fromFloat y ++ ")"



-- MAIN


main : Program Flags Model Msg
main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }
