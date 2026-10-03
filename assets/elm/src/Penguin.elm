module Penguin exposing (main)

{-| Draft of a "Penguin Pursuit" style maze.

The arrow keys move the penguin relative to the maze, not the screen: Up
always means maze north. The penguin waddles one cell at a time while an
arrow key is held down. The maze turns 90 degrees at random times, so the
on-screen direction of each key changes with it.

-}

import Browser
import Browser.Events
import Html exposing (Html, button, div, h1, p, span, text)
import Html.Attributes exposing (class, id, style)
import Html.Events exposing (onClick)
import Json.Decode as Decode
import Process
import Random
import Set exposing (Set)
import Svg exposing (Svg)
import Svg.Attributes as SA
import Task



-- CONSTANTS


mazeSize : Int
mazeSize =
    9


cellSize : Int
cellSize =
    44


{-| Space around the maze for the north marker.
-}
margin : Int
margin =
    28


{-| Time to waddle one cell while a key is held down.
-}
walkStepMs : Float
walkStepMs =
    180



-- MODEL


type alias Cell =
    ( Int, Int )


{-| An open passage between two adjacent cells. The smaller cell is first.
-}
type alias Passage =
    ( Cell, Cell )


type Dir
    = North
    | East
    | South
    | West


type alias Model =
    { passages : Set Passage
    , penguin : Cell
    , fish : Cell
    , facing : Dir
    , held : Maybe Dir
    , sinceStep : Float
    , walkTime : Float
    , quarterTurns : Int
    , caught : Int
    , won : Bool
    }


init : () -> ( Model, Cmd Msg )
init _ =
    ( { passages = Set.empty
      , penguin = ( 0, 0 )
      , fish = ( mazeSize - 1, mazeSize - 1 )
      , facing = South
      , held = Nothing
      , sinceStep = 0
      , walkTime = 0
      , quarterTurns = 0
      , caught = 0
      , won = False
      }
    , Cmd.batch [ newMaze, scheduleRotation ]
    )



-- UPDATE


type Msg
    = GotSeed Random.Seed
    | KeyDown Dir
    | KeyUp Dir
    | ReleaseKeys
    | Frame Float
    | NextMaze
    | RotationScheduled ( Int, Int )
    | Rotate Int


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotSeed seed ->
            ( { model
                | passages = generateMaze seed
                , penguin = ( 0, 0 )
                , facing = South
                , won = False
              }
            , Cmd.none
            )

        KeyDown dir ->
            if model.won then
                ( model, Cmd.none )

            else
                ( walk dir { model | held = Just dir, sinceStep = 0 }, Cmd.none )

        KeyUp dir ->
            if model.held == Just dir then
                ( stopWalking model, Cmd.none )

            else
                ( model, Cmd.none )

        ReleaseKeys ->
            ( stopWalking model, Cmd.none )

        Frame delta ->
            case model.held of
                Just dir ->
                    let
                        elapsed =
                            model.sinceStep + delta

                        walking =
                            { model | walkTime = model.walkTime + delta }
                    in
                    if elapsed >= walkStepMs then
                        ( walk dir { walking | sinceStep = elapsed - walkStepMs }, Cmd.none )

                    else
                        ( { walking | sinceStep = elapsed }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        NextMaze ->
            if model.won then
                ( model, newMaze )

            else
                ( model, Cmd.none )

        RotationScheduled ( delayMs, turn ) ->
            ( model, Process.sleep (toFloat delayMs) |> Task.perform (\_ -> Rotate turn) )

        Rotate turn ->
            ( { model | quarterTurns = model.quarterTurns + turn }, scheduleRotation )


{-| Move one cell, if there is no wall. Stop at the fish.
-}
walk : Dir -> Model -> Model
walk dir model =
    if canMove model.passages model.penguin dir then
        let
            next =
                step dir model.penguin
        in
        if next == model.fish then
            stopWalking { model | penguin = next, facing = dir, won = True, caught = model.caught + 1 }

        else
            { model | penguin = next, facing = dir }

    else
        { model | facing = dir }


stopWalking : Model -> Model
stopWalking model =
    { model | held = Nothing, walkTime = 0 }


newMaze : Cmd Msg
newMaze =
    Random.generate GotSeed Random.independentSeed


{-| Wait 3-7 seconds, then turn the maze 90 degrees clockwise or
counterclockwise.
-}
scheduleRotation : Cmd Msg
scheduleRotation =
    Random.generate RotationScheduled
        (Random.pair (Random.int 3000 7000) (Random.uniform 1 [ -1 ]))



-- MAZE


{-| Make a perfect maze with an iterative depth-first search
("recursive backtracker").
-}
generateMaze : Random.Seed -> Set Passage
generateMaze seed =
    carve [ ( 0, 0 ) ] (Set.singleton ( 0, 0 )) Set.empty seed


carve : List Cell -> Set Cell -> Set Passage -> Random.Seed -> Set Passage
carve stack visited passages seed =
    case stack of
        [] ->
            passages

        current :: rest ->
            case List.filter (\c -> not (Set.member c visited)) (neighbors current) of
                [] ->
                    carve rest visited passages seed

                first :: others ->
                    let
                        ( next, nextSeed ) =
                            Random.step (Random.uniform first others) seed
                    in
                    carve (next :: stack)
                        (Set.insert next visited)
                        (Set.insert (passage current next) passages)
                        nextSeed


neighbors : Cell -> List Cell
neighbors cell =
    [ North, East, South, West ]
        |> List.map (\dir -> step dir cell)
        |> List.filter inBounds


inBounds : Cell -> Bool
inBounds ( x, y ) =
    x >= 0 && y >= 0 && x < mazeSize && y < mazeSize


passage : Cell -> Cell -> Passage
passage a b =
    if a < b then
        ( a, b )

    else
        ( b, a )


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


canMove : Set Passage -> Cell -> Dir -> Bool
canMove passages cell dir =
    Set.member (passage cell (step dir cell)) passages


dirAngle : Dir -> Int
dirAngle dir =
    case dir of
        North ->
            0

        East ->
            90

        South ->
            180

        West ->
            270



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Browser.Events.onKeyDown keyDownDecoder
        , Browser.Events.onKeyUp (Decode.field "key" Decode.string |> Decode.andThen (arrowDecoder KeyUp))
        , Browser.Events.onVisibilityChange (\_ -> ReleaseKeys)
        , if model.held == Nothing then
            Sub.none

          else
            Browser.Events.onAnimationFrameDelta Frame
        ]


{-| Ignore key repeats: the frame loop moves the penguin while the key is down.
-}
keyDownDecoder : Decode.Decoder Msg
keyDownDecoder =
    Decode.map2 Tuple.pair (Decode.field "key" Decode.string) (Decode.field "repeat" Decode.bool)
        |> Decode.andThen
            (\( key, repeat ) ->
                if repeat then
                    Decode.fail "repeat"

                else if key == " " || key == "Enter" then
                    Decode.succeed NextMaze

                else
                    arrowDecoder KeyDown key
            )


arrowDecoder : (Dir -> Msg) -> String -> Decode.Decoder Msg
arrowDecoder toMsg key =
    case key of
        "ArrowUp" ->
            Decode.succeed (toMsg North)

        "ArrowRight" ->
            Decode.succeed (toMsg East)

        "ArrowDown" ->
            Decode.succeed (toMsg South)

        "ArrowLeft" ->
            Decode.succeed (toMsg West)

        _ ->
            Decode.fail "ignored key"



-- VIEW


view : Model -> Html Msg
view model =
    div [ id "penguin-root", class "flex flex-col items-center gap-6 select-none" ]
        [ div [ class "flex w-full max-w-md items-end justify-between" ]
            [ div []
                [ h1 [ class "text-2xl font-semibold tracking-tight" ] [ text "Penguin Pursuit" ]
                , p [ class "text-sm opacity-60" ] [ text "Arrow keys move along the maze. Up is always the maze's N." ]
                ]
            , div [ class "text-right" ]
                [ p [ class "text-xs uppercase tracking-wider opacity-60" ] [ text "Fish" ]
                , p [ id "penguin-caught", class "text-2xl font-semibold tabular-nums" ] [ text (String.fromInt model.caught) ]
                ]
            ]
        , div [ class "relative" ]
            [ div
                [ id "penguin-board"
                , style "transform" ("rotate(" ++ String.fromInt (model.quarterTurns * 90) ++ "deg)")
                , style "transition" "transform 600ms cubic-bezier(0.65, 0, 0.35, 1)"
                ]
                [ viewMaze model ]
            , if model.won then
                viewWon

              else
                text ""
            ]
        ]


viewWon : Html Msg
viewWon =
    div
        [ id "penguin-won"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-3 rounded-2xl bg-sky-950/60 text-white backdrop-blur-sm"
        ]
        [ p [ class "text-2xl font-semibold" ] [ text "Fish caught!" ]
        , button
            [ id "penguin-next"
            , class "rounded-full bg-white px-5 py-2 text-sm font-medium text-sky-900 shadow transition hover:scale-105 hover:shadow-lg"
            , onClick NextMaze
            ]
            [ text "Next maze" ]
        , span [ class "text-xs opacity-70" ] [ text "or press Space" ]
        ]


viewMaze : Model -> Html Msg
viewMaze model =
    let
        side =
            mazeSize * cellSize

        full =
            side + 2 * margin

        cells =
            List.concatMap (\y -> List.map (\x -> ( x, y )) (List.range 0 (mazeSize - 1))) (List.range 0 (mazeSize - 1))
    in
    Svg.svg
        [ SA.viewBox (String.join " " (List.map String.fromInt [ -margin, -margin, full, full ]))
        , SA.width (String.fromInt full)
        , SA.height (String.fromInt full)
        , SA.class "max-w-full h-auto"
        ]
        [ Svg.rect
            [ SA.x "0"
            , SA.y "0"
            , SA.width (String.fromInt side)
            , SA.height (String.fromInt side)
            , SA.rx "6"
            , SA.fill "#e0f2fe"
            ]
            []
        , viewNorthMarker side
        , Svg.g [ SA.stroke "#0c4a6e", SA.strokeWidth "4", SA.strokeLinecap "round" ]
            (List.concatMap (viewWalls model.passages) cells)
        , Svg.g [ SA.transform (translateCell model.fish) ] [ viewFish ]
        , Svg.g
            [ SA.style
                ("transform: translate("
                    ++ String.fromInt (cellCenter (Tuple.first model.penguin))
                    ++ "px, "
                    ++ String.fromInt (cellCenter (Tuple.second model.penguin))
                    ++ "px); transition: transform "
                    ++ String.fromFloat walkStepMs
                    ++ "ms linear"
                )
            ]
            [ Svg.g [ SA.transform ("rotate(" ++ String.fromInt (dirAngle model.facing) ++ ")") ]
                [ Svg.g [ SA.transform ("rotate(" ++ String.fromFloat (waddleAngle model) ++ ")") ] [ viewPenguin ] ]
            ]
        ]


{-| Rock from side to side, one side for each step. Stand still at a wall.
-}
waddleAngle : Model -> Float
waddleAngle model =
    case model.held of
        Just dir ->
            if canMove model.passages model.penguin dir || model.sinceStep < walkStepMs / 2 then
                12 * sin (model.walkTime / walkStepMs * pi)

            else
                0

        Nothing ->
            0


viewNorthMarker : Int -> Svg msg
viewNorthMarker side =
    let
        cx =
            String.fromInt (side // 2)
    in
    Svg.g [ SA.fill "#0369a1" ]
        [ Svg.polygon [ SA.points (String.fromInt (side // 2 - 7) ++ ",-8 " ++ cx ++ ",-20 " ++ String.fromInt (side // 2 + 7) ++ ",-8") ] []
        , Svg.text_ [ SA.x (String.fromInt (side // 2 + 12)), SA.y "-8", SA.fontSize "14", SA.fontWeight "700" ] [ Svg.text "N" ]
        ]


viewWalls : Set Passage -> Cell -> List (Svg msg)
viewWalls passages (( x, y ) as cell) =
    let
        x0 =
            x * cellSize

        y0 =
            y * cellSize

        x1 =
            x0 + cellSize

        y1 =
            y0 + cellSize

        wall dir ( ax, ay ) ( bx, by ) =
            if canMove passages cell dir then
                Nothing

            else
                Just
                    (Svg.line
                        [ SA.x1 (String.fromInt ax)
                        , SA.y1 (String.fromInt ay)
                        , SA.x2 (String.fromInt bx)
                        , SA.y2 (String.fromInt by)
                        ]
                        []
                    )
    in
    List.filterMap identity
        [ wall North ( x0, y0 ) ( x1, y0 )
        , wall East ( x1, y0 ) ( x1, y1 )
        , wall South ( x0, y1 ) ( x1, y1 )
        , wall West ( x0, y0 ) ( x0, y1 )
        ]


cellCenter : Int -> Int
cellCenter i =
    i * cellSize + cellSize // 2


translateCell : Cell -> String
translateCell ( x, y ) =
    "translate(" ++ String.fromInt (cellCenter x) ++ " " ++ String.fromInt (cellCenter y) ++ ")"


{-| Top-down penguin, beak to the north. Centered on 0,0.
-}
viewPenguin : Svg msg
viewPenguin =
    Svg.g []
        [ Svg.ellipse [ SA.cx "-11", SA.cy "3", SA.rx "4", SA.ry "8", SA.fill "#1e293b", SA.transform "rotate(-20 -11 3)" ] []
        , Svg.ellipse [ SA.cx "11", SA.cy "3", SA.rx "4", SA.ry "8", SA.fill "#1e293b", SA.transform "rotate(20 11 3)" ] []
        , Svg.ellipse [ SA.cx "0", SA.cy "3", SA.rx "11", SA.ry "13", SA.fill "#1e293b" ] []
        , Svg.ellipse [ SA.cx "0", SA.cy "5", SA.rx "6", SA.ry "8", SA.fill "#f8fafc" ] []
        , Svg.circle [ SA.cx "0", SA.cy "-9", SA.r "7", SA.fill "#0f172a" ] []
        , Svg.circle [ SA.cx "-3", SA.cy "-11", SA.r "1.5", SA.fill "#f8fafc" ] []
        , Svg.circle [ SA.cx "3", SA.cy "-11", SA.r "1.5", SA.fill "#f8fafc" ] []
        , Svg.polygon [ SA.points "-3,-15 3,-15 0,-21", SA.fill "#f97316" ] []
        ]


viewFish : Svg msg
viewFish =
    Svg.g []
        [ Svg.polygon [ SA.points "8,0 15,-6 15,6", SA.fill "#fb7185" ] []
        , Svg.ellipse [ SA.cx "-1", SA.cy "0", SA.rx "11", SA.ry "6", SA.fill "#fb7185" ] []
        , Svg.circle [ SA.cx "-7", SA.cy "-1", SA.r "1.5", SA.fill "#0f172a" ] []
        ]



-- MAIN


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }
