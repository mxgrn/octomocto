port module Penguin exposing (main)

{-| Multiplayer "Penguin Pursuit" style maze.

The server owns the game: the maze, the rotation and all penguins. This
module draws the state that comes in through ports and sends the player's
moves out. app.js connects the ports to a Phoenix channel.

The arrow keys move the penguin relative to the maze, not the screen: Up
always means maze north. The penguin waddles one cell at a time while an
arrow key is held down.

Sounds come from changes in the game state. This module sends the sound
names out through a port.

-}

import Browser
import Browser.Events
import Html exposing (Html, aside, button, div, h1, input, li, p, span, text, ul)
import Html.Attributes exposing (class, id, readonly, style, value)
import Html.Events exposing (onClick)
import Json.Decode as Decode exposing (Decoder)
import Process
import Set exposing (Set)
import Svg exposing (Svg)
import Svg.Attributes as SA
import Task



-- PORTS


port sendMove : String -> Cmd msg


port copyText : String -> Cmd msg


{-| One of "step", "win", "lose", "new\_maze" or "join".
-}
port playPenguinSound : String -> Cmd msg


port joined : (Decode.Value -> msg) -> Sub msg


port gameState : (Decode.Value -> msg) -> Sub msg


port joinFailed : (String -> msg) -> Sub msg



-- CONSTANTS


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


type alias Player =
    { id : String
    , color : String
    , colorName : String
    , pos : Cell
    , facing : Dir
    , score : Int
    }


type alias Game =
    { size : Int
    , passages : Set Passage
    , fish : Cell
    , quarterTurns : Int
    , winner : Maybe String
    , players : List Player
    }


type Connection
    = Connecting
    | Joined String Game
    | Failed String


type alias Model =
    { gameUrl : String
    , connection : Connection
    , held : Maybe Dir
    , sinceStep : Float
    , walkTime : Float
    , copied : Bool
    }


type alias Flags =
    { gameUrl : String }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { gameUrl = flags.gameUrl
      , connection = Connecting
      , held = Nothing
      , sinceStep = 0
      , walkTime = 0
      , copied = False
      }
    , Cmd.none
    )



-- UPDATE


type Msg
    = GotJoined Decode.Value
    | GotState Decode.Value
    | GotJoinFailed String
    | KeyDown Dir
    | KeyUp Dir
    | ReleaseKeys
    | Frame Float
    | CopyLink
    | CopiedTimeout


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotJoined value ->
            case Decode.decodeValue joinedDecoder value of
                Ok ( me, game ) ->
                    ( { model | connection = Joined me game }, Cmd.none )

                Err err ->
                    ( { model | connection = Failed (Decode.errorToString err) }, Cmd.none )

        GotState value ->
            case ( model.connection, Decode.decodeValue gameDecoder value ) of
                ( Joined me oldGame, Ok game ) ->
                    let
                        newModel =
                            { model | connection = Joined me game }

                        sounds =
                            Cmd.batch (List.map playPenguinSound (stateSounds me oldGame game))
                    in
                    if game.winner /= Nothing then
                        ( stopWalking newModel, sounds )

                    else
                        ( newModel, sounds )

                _ ->
                    ( model, Cmd.none )

        GotJoinFailed reason ->
            ( { model | connection = Failed reason }, Cmd.none )

        KeyDown dir ->
            case model.connection of
                Joined _ game ->
                    if game.winner == Nothing then
                        ( { model | held = Just dir, sinceStep = 0 }, sendMove (dirToString dir) )

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

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
                        ( { walking | sinceStep = elapsed - walkStepMs }, sendMove (dirToString dir) )

                    else
                        ( { walking | sinceStep = elapsed }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        CopyLink ->
            ( { model | copied = True }
            , Cmd.batch
                [ copyText model.gameUrl
                , Process.sleep 1500 |> Task.perform (\_ -> CopiedTimeout)
                ]
            )

        CopiedTimeout ->
            ( { model | copied = False }, Cmd.none )


stopWalking : Model -> Model
stopWalking model =
    { model | held = Nothing, walkTime = 0 }


findPlayer : String -> List Player -> Maybe Player
findPlayer id players =
    List.head (List.filter (\p -> p.id == id) players)


{-| The sounds for a change from one game state to the next.
-}
stateSounds : String -> Game -> Game -> List String
stateSounds me old new =
    let
        newRound =
            old.winner /= Nothing && new.winner == Nothing

        myPos game =
            Maybe.map .pos (findPlayer me game.players)

        someoneJoined =
            List.any (\p -> p.id /= me && findPlayer p.id old.players == Nothing) new.players
    in
    List.filterMap identity
        [ case ( old.winner, new.winner ) of
            ( Nothing, Just winner ) ->
                if winner == me then
                    Just "win"

                else
                    Just "lose"

            _ ->
                Nothing
        , if newRound then
            Just "new_maze"

          else
            Nothing
        , if old.winner == Nothing && new.winner == Nothing && myPos old /= myPos new then
            Just "step"

          else
            Nothing
        , if someoneJoined then
            Just "join"

          else
            Nothing
        ]



-- MAZE


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


dirToString : Dir -> String
dirToString dir =
    case dir of
        North ->
            "north"

        East ->
            "east"

        South ->
            "south"

        West ->
            "west"



-- DECODERS


joinedDecoder : Decoder ( String, Game )
joinedDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "player_id" Decode.string)
        (Decode.field "state" gameDecoder)


gameDecoder : Decoder Game
gameDecoder =
    Decode.map6 Game
        (Decode.field "size" Decode.int)
        (Decode.field "passages" (Decode.list passageDecoder) |> Decode.map Set.fromList)
        (Decode.field "fish" cellDecoder)
        (Decode.field "quarter_turns" Decode.int)
        (Decode.field "winner" (Decode.nullable Decode.string))
        (Decode.field "players" (Decode.list playerDecoder))


passageDecoder : Decoder Passage
passageDecoder =
    Decode.list Decode.int
        |> Decode.andThen
            (\coords ->
                case coords of
                    [ x1, y1, x2, y2 ] ->
                        Decode.succeed (passage ( x1, y1 ) ( x2, y2 ))

                    _ ->
                        Decode.fail "a passage must have 4 numbers"
            )


cellDecoder : Decoder Cell
cellDecoder =
    Decode.map2 Tuple.pair (Decode.index 0 Decode.int) (Decode.index 1 Decode.int)


playerDecoder : Decoder Player
playerDecoder =
    Decode.map6 Player
        (Decode.field "id" Decode.string)
        (Decode.field "color" Decode.string)
        (Decode.field "color_name" Decode.string)
        (Decode.map2 Tuple.pair (Decode.field "x" Decode.int) (Decode.field "y" Decode.int))
        (Decode.field "facing" dirDecoder)
        (Decode.field "score" Decode.int)


dirDecoder : Decoder Dir
dirDecoder =
    Decode.string
        |> Decode.andThen
            (\s ->
                case s of
                    "north" ->
                        Decode.succeed North

                    "east" ->
                        Decode.succeed East

                    "south" ->
                        Decode.succeed South

                    "west" ->
                        Decode.succeed West

                    _ ->
                        Decode.fail ("unknown direction " ++ s)
            )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ joined GotJoined
        , gameState GotState
        , joinFailed GotJoinFailed
        , Browser.Events.onKeyDown keyDownDecoder
        , Browser.Events.onKeyUp (Decode.field "key" Decode.string |> Decode.andThen (arrowDecoder KeyUp))
        , Browser.Events.onVisibilityChange (\_ -> ReleaseKeys)
        , if model.held == Nothing then
            Sub.none

          else
            Browser.Events.onAnimationFrameDelta Frame
        ]


{-| Ignore key repeats: the frame loop moves the penguin while the key is down.
-}
keyDownDecoder : Decoder Msg
keyDownDecoder =
    Decode.map2 Tuple.pair (Decode.field "key" Decode.string) (Decode.field "repeat" Decode.bool)
        |> Decode.andThen
            (\( key, repeat ) ->
                if repeat then
                    Decode.fail "repeat"

                else
                    arrowDecoder KeyDown key
            )


arrowDecoder : (Dir -> Msg) -> String -> Decoder Msg
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
    case model.connection of
        Connecting ->
            p [ id "penguin-connecting", class "py-24 text-center opacity-60" ] [ text "Joining the game…" ]

        Failed reason ->
            p [ id "penguin-failed", class "py-24 text-center text-red-600" ] [ text ("Could not join the game: " ++ reason) ]

        Joined me game ->
            viewGame model me game


viewGame : Model -> String -> Game -> Html Msg
viewGame model me game =
    div [ id "penguin-root", class "relative left-1/2 flex w-[min(96vw,1400px)] -translate-x-1/2 flex-col gap-5 select-none lg:flex-row lg:items-start lg:gap-8" ]
        [ aside [ id "penguin-panel", class "flex flex-col gap-5 lg:sticky lg:top-6 lg:w-72 lg:shrink-0" ]
            [ div []
                [ h1 [ class "text-2xl font-semibold tracking-tight" ] [ text "Penguin Pursuit" ]
                , p [ class "text-sm opacity-60" ] [ text "Arrow keys move along the maze. Up is always the maze's N." ]
                ]
            , viewShareLink model
            , viewScores me game.players
            ]
        , div [ class "min-w-0 flex-1" ]
            [ div [ class "relative mx-auto", style "width" boardWidth ]
                [ div
                    [ id "penguin-board"
                    , style "transform" ("rotate(" ++ String.fromInt (game.quarterTurns * 90) ++ "deg)")
                    , style "transition" "transform 600ms cubic-bezier(0.65, 0, 0.35, 1)"
                    ]
                    [ viewMaze model me game ]
                , case game.winner of
                    Just winnerId ->
                        viewWinner me winnerId game.players

                    Nothing ->
                        text ""
                ]
            ]
        ]


{-| The maze is square. Make it as wide as possible, but never taller than
the screen (minus the 3rem header and the 1.5rem bottom padding of the page).
-}
boardWidth : String
boardWidth =
    "min(100%, calc(100dvh - 4.5rem))"


viewShareLink : Model -> Html Msg
viewShareLink model =
    div [ class "flex items-center gap-2 rounded-full bg-sky-50 p-1 pl-4 text-sm ring-1 ring-sky-200 lg:flex-col lg:items-stretch lg:rounded-2xl lg:p-2 lg:pl-2" ]
        [ input
            [ id "penguin-link"
            , readonly True
            , value model.gameUrl
            , class "min-w-0 flex-1 truncate bg-transparent text-sky-900 outline-none lg:px-2 lg:py-1"
            ]
            []
        , button
            [ id "penguin-copy-link"
            , class "rounded-full bg-sky-600 px-4 py-1.5 font-medium text-white transition hover:bg-sky-500 active:scale-95"
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


viewScores : String -> List Player -> Html Msg
viewScores me players =
    ul [ id "penguin-scores", class "flex flex-wrap gap-2 lg:flex-col" ]
        (List.map
            (\player ->
                li
                    [ id ("penguin-score-" ++ player.id)
                    , class "flex items-center gap-2 rounded-full bg-white px-3 py-1 text-sm shadow-sm ring-1 ring-slate-200"
                    ]
                    [ span [ class "size-3 rounded-full", style "background" player.color ] []
                    , span [ class "lg:flex-1" ]
                        [ text
                            (if player.id == me then
                                player.colorName ++ " (you)"

                             else
                                player.colorName
                            )
                        ]
                    , span [ class "font-semibold tabular-nums" ] [ text (String.fromInt player.score) ]
                    ]
            )
            players
        )


viewWinner : String -> String -> List Player -> Html Msg
viewWinner me winnerId players =
    let
        message =
            if winnerId == me then
                "You got the fish!"

            else
                case List.filter (\p -> p.id == winnerId) players of
                    winner :: _ ->
                        "The " ++ winner.colorName ++ " penguin got the fish!"

                    [] ->
                        "Somebody got the fish!"
    in
    div
        [ id "penguin-winner"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-2 rounded-2xl bg-sky-950/60 text-white backdrop-blur-sm"
        ]
        [ p [ class "text-2xl font-semibold" ] [ text message ]
        , span [ class "text-sm opacity-70" ] [ text "A new maze starts soon…" ]
        ]


viewMaze : Model -> String -> Game -> Html Msg
viewMaze model me game =
    let
        side =
            game.size * cellSize

        full =
            side + 2 * margin

        cells =
            List.concatMap (\y -> List.map (\x -> ( x, y )) (List.range 0 (game.size - 1))) (List.range 0 (game.size - 1))

        -- Draw the player's own penguin last, so it is on top.
        ( mine, others ) =
            List.partition (\p -> p.id == me) game.players
    in
    Svg.svg
        [ SA.viewBox (String.join " " (List.map String.fromInt [ -margin, -margin, full, full ]))
        , SA.class "block h-auto w-full"
        ]
        ([ Svg.rect
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
            (List.concatMap (viewWalls game.passages) cells)
         , Svg.g [ SA.transform (translateCell game.fish) ] [ viewFish ]
         ]
            ++ List.map (viewPlayer 0 False) others
            ++ List.map (\p -> viewPlayer (waddleAngle model game p) True p) mine
        )


viewPlayer : Float -> Bool -> Player -> Svg msg
viewPlayer angle isMe player =
    Svg.g
        [ SA.id ("penguin-" ++ player.id)
        , SA.style
            ("transform: translate("
                ++ String.fromInt (cellCenter (Tuple.first player.pos))
                ++ "px, "
                ++ String.fromInt (cellCenter (Tuple.second player.pos))
                ++ "px); transition: transform "
                ++ String.fromFloat walkStepMs
                ++ "ms linear"
            )
        ]
        [ if isMe then
            Svg.circle [ SA.r "19", SA.fill "none", SA.stroke player.color, SA.strokeWidth "2", SA.strokeDasharray "4 3" ] []

          else
            Svg.text ""
        , Svg.g [ SA.transform ("rotate(" ++ String.fromInt (dirAngle player.facing) ++ ")") ]
            [ Svg.g [ SA.transform ("rotate(" ++ String.fromFloat angle ++ ")") ] [ viewPenguin player.color ] ]
        ]


{-| Rock from side to side, one side for each step. Stand still at a wall.
-}
waddleAngle : Model -> Game -> Player -> Float
waddleAngle model game player =
    case model.held of
        Just dir ->
            if canMove game.passages player.pos dir || model.sinceStep < walkStepMs / 2 then
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
viewPenguin : String -> Svg msg
viewPenguin color =
    Svg.g []
        [ Svg.ellipse [ SA.cx "-11", SA.cy "3", SA.rx "4", SA.ry "8", SA.fill color, SA.transform "rotate(-20 -11 3)" ] []
        , Svg.ellipse [ SA.cx "11", SA.cy "3", SA.rx "4", SA.ry "8", SA.fill color, SA.transform "rotate(20 11 3)" ] []
        , Svg.ellipse [ SA.cx "0", SA.cy "3", SA.rx "11", SA.ry "13", SA.fill color ] []
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


main : Program Flags Model Msg
main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }
