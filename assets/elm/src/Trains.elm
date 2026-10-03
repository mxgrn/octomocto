port module Trains exposing (main)

{-| Single player "Train of Thought" style game.

Trains leave the station one at a time. Each train has the color of one of
the houses. The player clicks the switches to send each train to the house
of its color. Each game has a new random track layout.

The board is a grid. The tracks make a tree: the station is the root, each
switch has two branches and each house is at the end of a branch.

The game sends the names of sounds out through a port. app.js plays them.

-}

import Browser
import Browser.Events
import Dict exposing (Dict)
import Html exposing (Html, button, div, h1, p, span, text)
import Html.Attributes exposing (class, id, style)
import Html.Events exposing (onClick)
import Random exposing (Generator)
import Set exposing (Set)
import Svg exposing (Svg)
import Svg.Attributes as SA
import Svg.Events



-- PORTS


{-| One of "switch", "depart", "correct" or "wrong".
-}
port playTrainSound : String -> Cmd msg



-- CONSTANTS


cols : Int
cols =
    9


rows : Int
rows =
    7


cellSize : Float
cellSize =
    60


{-| There is one more house than there are switches.
-}
switchCount : Int
switchCount =
    4


{-| The number of cells from the station to the first switch. Each later
switch and each house is at least 2 cells after the switch before it.
-}
firstSwitchRun : Int
firstSwitchRun =
    4


trainCount : Int
trainCount =
    15


{-| The pause between trains gets shorter for each train, down to the minimum.
-}
firstPauseMs : Float
firstPauseMs =
    8000


pauseStepMs : Float
pauseStepMs =
    400


minPauseMs : Float
minPauseMs =
    4400


{-| Time for a train to go through one cell on a straight track.
-}
cellMs : Float
cellMs =
    1860


{-| Time to show the mark above a house after a train arrives.
-}
arrivalMs : Float
arrivalMs =
    900


houseColors : List String
houseColors =
    [ "#ef4444", "#3b82f6", "#eab308", "#22c55e", "#a855f7" ]



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
A house cell has no children. `houses` gives the color of each house.
-}
type alias Layout =
    { station : Cell
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
`t` is how far it is through the cell, from 0 to 1. The train selects its
exit when it comes into a cell, so a switch change has no effect on a train
that is already on the switch.
-}
type alias Train =
    { color : Int
    , cell : Cell
    , from : Maybe Cell
    , exit : Maybe Cell
    , t : Float
    }


type alias Arrival =
    { cell : Cell
    , correct : Bool
    , age : Float
    }


type Phase
    = Ready
    | Playing
    | Over


type alias Model =
    { seed : Random.Seed
    , layout : Layout
    , switches : Dict Cell Int
    , phase : Phase
    , trains : List Train
    , sent : Int
    , untilNext : Float
    , colors : List Int
    , correct : Int
    , arrivals : List Arrival
    }


type alias Flags =
    { seed : Int }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( newGame (Random.initialSeed flags.seed), Cmd.none )


newGame : Random.Seed -> Model
newGame seed0 =
    let
        ( layout, seed1 ) =
            generateLayout seed0

        ( switches, seed2 ) =
            Random.step (randomSwitches layout) seed1

        ( colors, seed3 ) =
            Random.step trainColors seed2
    in
    { seed = seed3
    , layout = layout
    , switches = switches
    , phase = Ready
    , trains = []
    , sent = 0
    , untilNext = 0
    , colors = colors
    , correct = 0
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



-- UPDATE


type Msg
    = Start
    | PlayAgain
    | Toggle Cell
    | Frame Float


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Start ->
            ( { model | phase = Playing, untilNext = 600 }, Cmd.none )

        PlayAgain ->
            ( newGame model.seed, Cmd.none )

        Toggle cell ->
            ( { model | switches = Dict.update cell (Maybe.map (\i -> 1 - i)) model.switches }, playTrainSound "switch" )

        Frame delta ->
            let
                moved =
                    model |> moveTrains delta |> sendTrain delta
            in
            ( checkOver moved, Cmd.batch (List.map playTrainSound (frameSounds model moved)) )


{-| The sounds for the trains that arrived or left in one frame.
-}
frameSounds : Model -> Model -> List String
frameSounds before after =
    let
        arrivals =
            after.arrivals
                |> List.filter (\a -> a.age == 0)
                |> List.map
                    (\a ->
                        if a.correct then
                            "correct"

                        else
                            "wrong"
                    )
    in
    if after.sent > before.sent then
        "depart" :: arrivals

    else
        arrivals


moveTrains : Float -> Model -> Model
moveTrains delta model =
    let
        moved =
            List.map (moveTrain model delta) model.trains

        newArrivals =
            List.filterMap
                (\( train, arrived ) ->
                    if arrived then
                        Just
                            { cell = train.cell
                            , correct = Dict.get train.cell model.layout.houses == Just train.color
                            , age = 0
                            }

                    else
                        Nothing
                )
                moved

        oldArrivals =
            model.arrivals
                |> List.map (\a -> { a | age = a.age + delta })
                |> List.filter (\a -> a.age < arrivalMs)
    in
    { model
        | trains = List.filterMap (\( train, arrived ) -> if arrived then Nothing else Just train) moved
        , arrivals = newArrivals ++ oldArrivals
        , correct = model.correct + List.length (List.filter .correct newArrivals)
    }


{-| Move a train forward. The Bool is True when the train is at its house.
-}
moveTrain : Model -> Float -> Train -> ( Train, Bool )
moveTrain model delta train =
    let
        t =
            train.t + delta / (cellMs * (trainPiece train).length)
    in
    if t < 1 then
        ( { train | t = t }, False )

    else
        case train.exit of
            Just next ->
                ( { train | cell = next, from = Just train.cell, exit = route model next, t = 0 }, False )

            Nothing ->
                ( train, True )


route : Model -> Cell -> Maybe Cell
route model cell =
    case Dict.get cell model.layout.children of
        Just [ next ] ->
            Just next

        Just [ first, second ] ->
            if Dict.get cell model.switches == Just 1 then
                Just second

            else
                Just first

        _ ->
            Nothing


sendTrain : Float -> Model -> Model
sendTrain delta model =
    let
        untilNext =
            model.untilNext - delta
    in
    case model.colors of
        color :: colors ->
            if untilNext <= 0 then
                let
                    station =
                        model.layout.station

                    train =
                        { color = color, cell = station, from = Nothing, exit = route model station, t = 0 }
                in
                { model
                    | colors = colors
                    , trains = model.trains ++ [ train ]
                    , sent = model.sent + 1
                    , untilNext = untilNext + pauseAfter model.sent
                }

            else
                { model | untilNext = untilNext }

        [] ->
            { model | untilNext = untilNext }


{-| The colors of all trains in one game, in order. Each color has the same
number of trains, or one more if the trains do not divide equally. Two trains
in a row never have the same color.
-}
trainColors : Generator (List Int)
trainColors =
    let
        colorCount =
            switchCount + 1
    in
    shuffle (List.range 0 switchCount)
        |> Random.andThen
            (\order ->
                order
                    |> List.indexedMap
                        (\i color ->
                            if i < modBy colorCount trainCount then
                                ( color, trainCount // colorCount + 1 )

                            else
                                ( color, trainCount // colorCount )
                        )
                    |> Dict.fromList
                    |> orderColors
            )


{-| Put the colors in a random order. Try again if the last trains left
can only have the same color in a row.
-}
orderColors : Dict Int Int -> Generator (List Int)
orderColors counts =
    pickColors counts Nothing []
        |> Random.andThen
            (\result ->
                case result of
                    Just colors ->
                        Random.constant colors

                    Nothing ->
                        Random.lazy (\_ -> orderColors counts)
            )


{-| Colors with more trains left are more likely, so the last trains do
not all have the same color.
-}
pickColors : Dict Int Int -> Maybe Int -> List Int -> Generator (Maybe (List Int))
pickColors counts last picked =
    let
        options =
            Dict.toList counts
                |> List.filter (\( color, left ) -> left > 0 && Just color /= last)
                |> List.map (\( color, left ) -> ( toFloat left, color ))
    in
    if List.all (\left -> left == 0) (Dict.values counts) then
        Random.constant (Just (List.reverse picked))

    else
        case options of
            first :: rest ->
                Random.weighted first rest
                    |> Random.andThen
                        (\color ->
                            pickColors (Dict.update color (Maybe.map (\left -> left - 1)) counts) (Just color) (color :: picked)
                        )

            [] ->
                Random.constant Nothing


pauseAfter : Int -> Float
pauseAfter sent =
    max minPauseMs (firstPauseMs - toFloat sent * pauseStepMs)


checkOver : Model -> Model
checkOver model =
    if model.sent == trainCount && List.isEmpty model.trains then
        { model | phase = Over, arrivals = [] }

    else
        model



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
    { occupied : Set Cell
    , children : Dict Cell (List Cell)
    , tips : List Tip
    , houses : List Cell
    , splits : Int
    , failed : Bool
    }


{-| Make some correct layouts and keep the one that covers the board best.
-}
generateLayout : Random.Seed -> ( Layout, Random.Seed )
generateLayout seed =
    let
        ( first, seed1 ) =
            generateLayoutHelp 1000 seed
    in
    pickBestLayout (layoutCandidates - 1) first seed1


layoutCandidates : Int
layoutCandidates =
    40


pickBestLayout : Int -> Layout -> Random.Seed -> ( Layout, Random.Seed )
pickBestLayout left best seed =
    if left <= 0 then
        ( best, seed )

    else
        let
            ( layout, nextSeed ) =
                generateLayoutHelp 1000 seed
        in
        if coverage layout > coverage best then
            pickBestLayout (left - 1) layout nextSeed

        else
            pickBestLayout (left - 1) best nextSeed


{-| How evenly the tracks cover the board. The board is divided into 3 × 3
areas. Each area with a track counts most, then each row and each column
with a track.
-}
coverage : Layout -> Int
coverage layout =
    let
        cells =
            layout.station :: Dict.keys (parents layout)

        area ( x, y ) =
            ( x * 3 // cols, y * 3 // rows )

        count f =
            Set.size (Set.fromList (List.map f cells))
    in
    10 * count area + count Tuple.first + count Tuple.second


generateLayoutHelp : Int -> Random.Seed -> ( Layout, Random.Seed )
generateLayoutHelp attemptsLeft seed =
    let
        ( ( station, growth ), seed1 ) =
            Random.step growLayout seed

        ( colors, seed2 ) =
            Random.step (shuffle (List.range 0 switchCount)) seed1

        layout =
            { station = station
            , children = growth.children
            , houses = Dict.fromList (List.map2 Tuple.pair growth.houses colors)
            }
    in
    if (not growth.failed && growth.splits == switchCount) || attemptsLeft <= 1 then
        ( layout, seed2 )

    else
        generateLayoutHelp (attemptsLeft - 1) seed2


growLayout : Generator ( Cell, Growth )
growLayout =
    Random.int 1 (rows - 2)
        |> Random.andThen
            (\row ->
                let
                    station =
                        ( 0, row )
                in
                grow
                    { occupied = Set.singleton station
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
        Random.map4 (growTip growth)
            (Random.int 0 (List.length growth.tips - 1))
            (Random.float 0 1)
            (Random.float 0 1)
            (Random.float 0 1)
            |> Random.andThen grow


{-| Make one tip split into a switch, stop at a house, or go one cell forward.
The first switch is `firstSwitchRun` cells after the station. Each other
switch and each house has at least one plain cell before it.
-}
growTip : Growth -> Int -> Float -> Float -> Float -> Growth
growTip growth index splitRoll stopRoll dirRoll =
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
                        |> List.filter (\( _, cell ) -> free growth.occupied cell)

                allSplit =
                    growth.splits == switchCount

                -- Before the first split, the only tip is the station track.
                splitRun =
                    if growth.splits == 0 then
                        firstSwitchRun

                    else
                        2
            in
            if tip.run >= splitRun && not allSplit && List.length options >= 2 && (splitRoll < 0.45 || tip.run >= splitRun + 2) then
                split tip (pickTwo dirRoll options) rest

            else if List.isEmpty options || (allSplit && tip.run >= 2 && (stopRoll < 0.3 || tip.run >= 5)) then
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


free : Set Cell -> Cell -> Bool
free occupied (( x, y ) as cell) =
    x >= 0 && x < cols && y >= 0 && y < rows && not (Set.member cell occupied)


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
    if model.phase == Playing then
        -- Limit the step, so that trains do not jump after the tab was hidden.
        Browser.Events.onAnimationFrameDelta (min 100 >> Frame)

    else
        Sub.none



-- VIEW


view : Model -> Html Msg
view model =
    let
        boardWidth =
            String.fromFloat (toFloat cols * cellSize) ++ "px"
    in
    div [ id "trains-root", class "flex flex-col items-center gap-6 select-none" ]
        [ div [ class "flex w-full flex-wrap items-end justify-between gap-3", style "max-width" boardWidth ]
            [ div []
                [ h1 [ class "text-2xl font-semibold tracking-tight" ] [ text "Train of Thought" ]
                , p [ class "text-sm opacity-60" ] [ text "Click the switches to send each train to the house of its color." ]
                ]
            , viewStats model
            ]
        , div [ class "relative" ]
            [ viewBoard model
            , viewOverlay model
            ]
        ]


viewStats : Model -> Html Msg
viewStats model =
    div [ class "flex gap-2 text-sm" ]
        [ div [ id "trains-correct", class "rounded-full bg-emerald-50 px-3 py-1 text-emerald-900 ring-1 ring-emerald-200" ]
            [ text "Correct ", span [ class "font-semibold tabular-nums" ] [ text (String.fromInt model.correct) ] ]
        , div [ id "trains-sent", class "rounded-full bg-white px-3 py-1 text-slate-700 shadow-sm ring-1 ring-slate-200" ]
            [ text "Train "
            , span [ class "font-semibold tabular-nums" ]
                [ text (String.fromInt model.sent ++ " / " ++ String.fromInt trainCount) ]
            ]
        ]


viewOverlay : Model -> Html Msg
viewOverlay model =
    case model.phase of
        Ready ->
            overlay
                [ p [ class "text-2xl font-semibold" ] [ text (String.fromInt trainCount ++ " trains are ready") ]
                , span [ class "text-sm opacity-80" ] [ text "Look at the tracks, then start." ]
                , overlayButton "trains-start" Start "Start"
                ]

        Playing ->
            text ""

        Over ->
            overlay
                [ p [ id "trains-result", class "text-2xl font-semibold" ]
                    [ text (String.fromInt model.correct ++ " of " ++ String.fromInt trainCount ++ " trains got home") ]
                , span [ class "text-sm opacity-80" ] [ text (verdict model.correct) ]
                , overlayButton "trains-again" PlayAgain "Play again"
                ]


verdict : Int -> String
verdict correct =
    if correct == trainCount then
        "Perfect!"

    else if correct * 3 >= trainCount * 2 then
        "Good work."

    else
        "Try again with a new layout."


overlay : List (Html Msg) -> Html Msg
overlay =
    div [ class "absolute inset-0 flex flex-col items-center justify-center gap-2 rounded-2xl bg-slate-900/55 text-white backdrop-blur-[2px]" ]


overlayButton : String -> Msg -> String -> Html Msg
overlayButton buttonId msg label =
    button
        [ id buttonId
        , class "mt-3 rounded-full bg-amber-400 px-6 py-2.5 font-medium text-slate-900 shadow-lg shadow-amber-500/30 transition hover:-translate-y-0.5 hover:bg-amber-300 active:translate-y-0"
        , onClick msg
        ]
        [ text label ]


viewBoard : Model -> Html Msg
viewBoard model =
    let
        width =
            toFloat cols * cellSize

        height =
            toFloat rows * cellSize

        rails =
            trackPieces model
    in
    Svg.svg
        [ SA.id "trains-board"
        , SA.viewBox ("0 0 " ++ String.fromFloat width ++ " " ++ String.fromFloat height)
        , SA.width (String.fromFloat width)
        , SA.height (String.fromFloat height)
        , SA.class "max-w-full h-auto"
        ]
        [ Svg.rect [ SA.width (String.fromFloat width), SA.height (String.fromFloat height), SA.rx "16", SA.fill "#ecfccb" ] []
        , Svg.g [] (List.map viewSwitchPad (switchCells model.layout))
        , Svg.g [ SA.opacity "0.2" ] (railsOf SwitchOff "#57534e" rails)
        , Svg.g [] (railsOf Plain "#57534e" rails)
        , Svg.g [] (railsOf SwitchOn "#d97706" rails)
        , Svg.g [] (List.map viewSwitchTarget (switchCells model.layout))
        , Svg.g [ SA.pointerEvents "none" ] (List.map viewTrain model.trains)
        , viewStation model.layout.station
        , Svg.g [ SA.pointerEvents "none" ] (List.map viewHouse (Dict.toList model.layout.houses))
        , Svg.g [ SA.pointerEvents "none" ] (List.map viewArrival model.arrivals)
        ]


{-| A switch shows the branch that it points to now in a different color,
so the player can see where the next train goes.
-}
type Rail
    = Plain
    | SwitchOn
    | SwitchOff


trackPieces : Model -> List ( Piece, Rail )
trackPieces model =
    let
        layout =
            model.layout

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

                Just next ->
                    List.map
                        (\exit ->
                            ( piece cell from (Just exit)
                            , if route model cell == Just exit then
                                SwitchOn

                              else
                                SwitchOff
                            )
                        )
                        next

                Nothing ->
                    [ ( piece cell from Nothing, Plain ) ]
    in
    List.concatMap cellPieces (layout.station :: Dict.keys parentOf)


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


{-| Two rails, with the ties between them.
-}
viewRails : String -> Piece -> Svg msg
viewRails color p =
    Svg.g [ SA.fill "none" ]
        [ Svg.path [ SA.d (pathData p), SA.stroke color, SA.strokeWidth "11" ] []
        , Svg.path [ SA.d (pathData p), SA.stroke "#e7e5e4", SA.strokeWidth "6" ] []
        , Svg.path [ SA.d (pathData p), SA.stroke "#a16207", SA.strokeOpacity "0.6", SA.strokeWidth "6", SA.strokeDasharray "2.5 4.5" ] []
        ]


switchRect : Cell -> List (Svg.Attribute msg) -> Svg msg
switchRect ( x, y ) attrs =
    Svg.rect
        ([ SA.x (String.fromFloat (toFloat x * cellSize + 4))
         , SA.y (String.fromFloat (toFloat y * cellSize + 4))
         , SA.width (String.fromFloat (cellSize - 8))
         , SA.height (String.fromFloat (cellSize - 8))
         , SA.rx "14"
         ]
            ++ attrs
        )
        []


viewSwitchPad : Cell -> Svg msg
viewSwitchPad cell =
    switchRect cell [ SA.fill "#fef3c7", SA.stroke "#fcd34d", SA.strokeWidth "2" ]


{-| An invisible click target above the rails. It lights up on hover.
-}
viewSwitchTarget : Cell -> Svg Msg
viewSwitchTarget (( x, y ) as cell) =
    switchRect cell
        [ SA.id ("trains-switch-" ++ String.fromInt x ++ "-" ++ String.fromInt y)
        , SA.class "cursor-pointer fill-transparent transition-colors hover:fill-amber-300/30"
        , Svg.Events.onClick (Toggle cell)
        ]


viewTrain : Train -> Svg msg
viewTrain train =
    let
        p =
            trainPiece train

        ( x, y ) =
            pointAt p train.t
    in
    Svg.g
        [ SA.transform
            ("translate("
                ++ String.fromFloat x
                ++ " "
                ++ String.fromFloat y
                ++ ") rotate("
                ++ String.fromFloat (angleAt p train.t)
                ++ ")"
            )
        ]
        [ Svg.rect [ SA.x "-15", SA.y "-10", SA.width "30", SA.height "20", SA.rx "6", SA.fill (houseColor train.color), SA.stroke "#1e293b", SA.strokeWidth "2" ] []
        , Svg.rect [ SA.x "4", SA.y "-6", SA.width "6", SA.height "12", SA.rx "2", SA.fill "#f8fafc", SA.opacity "0.85" ] []
        , Svg.circle [ SA.cx "-6", SA.cy "0", SA.r "3.5", SA.fill "#1e293b", SA.opacity "0.35" ] []
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
viewHouse ( ( x, y ) as cell, color ) =
    Svg.g
        [ SA.id ("trains-house-" ++ String.fromInt x ++ "-" ++ String.fromInt y)
        , SA.transform (translate (center cell))
        ]
        [ Svg.ellipse [ SA.cx "0", SA.cy "17", SA.rx "18", SA.ry "4", SA.fill "#365314", SA.opacity "0.2" ] []
        , Svg.rect [ SA.x "-15", SA.y "-6", SA.width "30", SA.height "22", SA.rx "3", SA.fill (houseColor color) ] []
        , Svg.polygon [ SA.points "-20,-4 0,-22 20,-4", SA.fill "#334155", SA.strokeLinejoin "round", SA.stroke "#334155", SA.strokeWidth "3" ] []
        , Svg.rect [ SA.x "-4", SA.y "4", SA.width "8", SA.height "12", SA.rx "1.5", SA.fill "#1e293b", SA.opacity "0.45" ] []
        ]


viewArrival : Arrival -> Svg msg
viewArrival arrival =
    let
        ( x, y ) =
            center arrival.cell

        progress =
            arrival.age / arrivalMs
    in
    Svg.g
        [ SA.transform (translate ( x, y - 32 - 14 * progress ))
        , SA.opacity (String.fromFloat (1 - progress * progress))
        ]
        [ Svg.circle
            [ SA.r "11"
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


houseColor : Int -> String
houseColor i =
    List.drop i houseColors |> List.head |> Maybe.withDefault "#64748b"



-- MAIN


main : Program Flags Model Msg
main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }
