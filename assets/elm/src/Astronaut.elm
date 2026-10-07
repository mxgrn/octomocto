port module Astronaut exposing (main)

{-| "Station Escape": the penguin maze with a space theme.

The astronauts race to the escape pod on a space station that spins. The
server is the same as for the penguin maze (the penguin channel), so the
game state still calls the goal "fish".

The server owns the game: the maze, the rotation and all astronauts. This
module draws the state that comes in through ports and sends the player's
moves out. app.js connects the ports to a Phoenix channel.

The arrow keys move the astronaut relative to the station, not the screen:
Up always means station north. The astronaut floats one cell at a time while
an arrow key is held down.

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


port astronautSendMove : String -> Cmd msg


port astronautCopyText : String -> Cmd msg


{-| One of "step", "win", "lose", "new\_maze", "join" or "wall".
-}
port playAstronautSound : String -> Cmd msg


port astronautJoined : (Decode.Value -> msg) -> Sub msg


port astronautGameState : (Decode.Value -> msg) -> Sub msg


port astronautJoinFailed : (String -> msg) -> Sub msg



-- CONSTANTS


cellSize : Int
cellSize =
    44


{-| Space around the maze for the north marker.
-}
margin : Int
margin =
    28


{-| Time to float one cell while a key is held down.
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
    , pod : Cell
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
                            Cmd.batch (List.map playAstronautSound (stateSounds me oldGame game))
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
                Joined me game ->
                    if game.winner == Nothing then
                        ( { model | held = Just dir, sinceStep = 0 }
                        , Cmd.batch [ astronautSendMove (dirToString dir), wallSound me game dir ]
                        )

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
                        ( { walking | sinceStep = elapsed - walkStepMs }, astronautSendMove (dirToString dir) )

                    else
                        ( { walking | sinceStep = elapsed }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        CopyLink ->
            ( { model | copied = True }
            , Cmd.batch
                [ astronautCopyText model.gameUrl
                , Process.sleep 1500 |> Task.perform (\_ -> CopiedTimeout)
                ]
            )

        CopiedTimeout ->
            ( { model | copied = False }, Cmd.none )


stopWalking : Model -> Model
stopWalking model =
    { model | held = Nothing, walkTime = 0 }


{-| A new key press toward a wall next to the astronaut hits the wall. A
held key that floats the astronaut up to a wall does not come here, so that
first bump is silent.
-}
wallSound : String -> Game -> Dir -> Cmd msg
wallSound me game dir =
    case findPlayer me game.players of
        Just player ->
            if canMove game.passages player.pos dir then
                Cmd.none

            else
                playAstronautSound "wall"

        Nothing ->
            Cmd.none


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
        [ astronautJoined GotJoined
        , astronautGameState GotState
        , astronautJoinFailed GotJoinFailed
        , Browser.Events.onKeyDown keyDownDecoder
        , Browser.Events.onKeyUp (Decode.field "key" Decode.string |> Decode.andThen (arrowDecoder KeyUp))
        , Browser.Events.onVisibilityChange (\_ -> ReleaseKeys)
        , if model.held == Nothing then
            Sub.none

          else
            Browser.Events.onAnimationFrameDelta Frame
        ]


{-| Ignore key repeats: the frame loop moves the astronaut while the key is down.
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
            p [ id "astronaut-connecting", class "py-24 text-center opacity-60" ] [ text "Joining the game…" ]

        Failed reason ->
            p [ id "astronaut-failed", class "py-24 text-center text-red-600" ] [ text ("Could not join the game: " ++ reason) ]

        Joined me game ->
            viewGame model me game


viewGame : Model -> String -> Game -> Html Msg
viewGame model me game =
    div [ id "astronaut-root", class "relative left-1/2 flex w-[min(96vw,1400px)] -translate-x-1/2 flex-col gap-5 select-none lg:flex-row lg:items-start lg:gap-8" ]
        [ aside [ id "astronaut-panel", class "flex flex-col gap-5 lg:sticky lg:top-6 lg:w-72 lg:shrink-0" ]
            [ div []
                [ h1 [ class "text-2xl font-semibold tracking-tight" ] [ text "Station Escape" ]
                , p [ class "text-sm opacity-60" ] [ text "Arrow keys move along the station. Up is always the station's N." ]
                ]
            , viewShareLink model
            , viewScores me game.players
            ]
        , div [ class "min-w-0 flex-1" ]
            [ div [ class "relative mx-auto", style "width" boardWidth ]
                [ div
                    [ id "astronaut-board"
                    , style "transform" ("rotate(" ++ String.fromInt (game.quarterTurns * 90) ++ "deg)")
                    , style "transition" "transform 900ms cubic-bezier(0.65, 0, 0.35, 1)"
                    ]
                    [ viewStation model me game ]
                , case game.winner of
                    Just winnerId ->
                        viewWinner me winnerId game.players

                    Nothing ->
                        text ""
                ]
            ]
        ]


{-| The station is square. Make it as wide as possible, but never taller than
the screen (minus the 3rem header and the 1.5rem bottom padding of the page).
-}
boardWidth : String
boardWidth =
    "min(100%, calc(100dvh - 4.5rem))"


viewShareLink : Model -> Html Msg
viewShareLink model =
    div [ class "flex items-center gap-2 rounded-full bg-indigo-50 p-1 pl-4 text-sm ring-1 ring-indigo-200 lg:flex-col lg:items-stretch lg:rounded-2xl lg:p-2 lg:pl-2" ]
        [ input
            [ id "astronaut-link"
            , readonly True
            , value model.gameUrl
            , class "min-w-0 flex-1 truncate bg-transparent text-indigo-950 outline-none lg:px-2 lg:py-1"
            ]
            []
        , button
            [ id "astronaut-copy-link"
            , class "rounded-full bg-indigo-600 px-4 py-1.5 font-medium text-white transition hover:bg-indigo-500 active:scale-95"
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
    ul [ id "astronaut-scores", class "flex flex-wrap gap-2 lg:flex-col" ]
        (List.map
            (\player ->
                li
                    [ id ("astronaut-score-" ++ player.id)
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
                "You reached the escape pod!"

            else
                case List.filter (\p -> p.id == winnerId) players of
                    winner :: _ ->
                        "The " ++ winner.colorName ++ " astronaut reached the pod!"

                    [] ->
                        "Somebody reached the pod!"
    in
    div
        [ id "astronaut-winner"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-2 rounded-3xl bg-indigo-950/70 text-white backdrop-blur-sm"
        ]
        [ p [ class "text-2xl font-semibold" ] [ text message ]
        , span [ class "text-sm opacity-70" ] [ text "A new station docks soon…" ]
        ]


viewStation : Model -> String -> Game -> Html Msg
viewStation model me game =
    let
        side =
            game.size * cellSize

        full =
            side + 2 * margin

        cells =
            List.concatMap (\y -> List.map (\x -> ( x, y )) (List.range 0 (game.size - 1))) (List.range 0 (game.size - 1))

        -- Draw the player's own astronaut last, so it is on top.
        ( mine, others ) =
            List.partition (\p -> p.id == me) game.players

        walls attrs =
            Svg.g (SA.strokeLinecap "round" :: attrs) (List.concatMap (viewWalls game.passages) cells)
    in
    Svg.svg
        [ SA.viewBox (String.join " " (List.map String.fromInt [ -margin, -margin, full, full ]))
        , SA.class "block h-auto w-full"
        ]
        ([ Svg.rect
            [ SA.x (String.fromInt -margin)
            , SA.y (String.fromInt -margin)
            , SA.width (String.fromInt full)
            , SA.height (String.fromInt full)
            , SA.rx "24"
            , SA.fill "#070b1f"
            ]
            []
         , Svg.g [ SA.fill "#e0e7ff" ] (viewStars full)
         , Svg.rect
            [ SA.x "0"
            , SA.y "0"
            , SA.width (String.fromInt side)
            , SA.height (String.fromInt side)
            , SA.rx "6"
            , SA.fill "#1e1b4b"
            , SA.fillOpacity "0.55"
            ]
            []
         , viewNorthMarker side
         , walls [ SA.stroke "#22d3ee", SA.strokeOpacity "0.25", SA.strokeWidth "9" ]
         , walls [ SA.stroke "#a5f3fc", SA.strokeWidth "3" ]
         , Svg.g [ SA.transform (translateCell game.pod) ] [ viewPod ]
         ]
            ++ List.map (viewPlayer 0 False False) others
            ++ List.map (\p -> viewPlayer (driftAngle model game p) (thrusting model game p) True p) mine
        )


{-| Small stars at fixed pseudo-random places, so they do not jump between
renders.
-}
viewStars : Int -> List (Svg msg)
viewStars full =
    let
        next seed =
            modBy 2147483647 (seed * 48271)

        star ( i, seed ) =
            let
                s1 =
                    next seed

                s2 =
                    next s1

                s3 =
                    next s2
            in
            Svg.circle
                [ SA.cx (String.fromInt (modBy full s1 - margin))
                , SA.cy (String.fromInt (modBy full s2 - margin))
                , SA.r
                    (if modBy 5 s3 == 0 then
                        "1.6"

                     else
                        "0.9"
                    )
                , SA.fillOpacity (String.fromFloat (0.3 + toFloat (modBy 7 s3) / 10))
                ]
                []
    in
    List.range 1 70
        |> List.map (\i -> ( i, i * 7919 ))
        |> List.map star


viewPlayer : Float -> Bool -> Bool -> Player -> Svg msg
viewPlayer angle thrust isMe player =
    Svg.g
        [ SA.id ("astronaut-" ++ player.id)
        , SA.style
            ("transform: translate("
                ++ String.fromInt (cellCenter (Tuple.first player.pos))
                ++ "px, "
                ++ String.fromInt (cellCenter (Tuple.second player.pos))
                ++ "px); transition: transform "
                ++ String.fromFloat walkStepMs
                ++ "ms ease-out"
            )
        ]
        [ if isMe then
            Svg.circle [ SA.r "20", SA.fill "none", SA.stroke player.color, SA.strokeWidth "2", SA.strokeDasharray "4 3" ] []

          else
            Svg.text ""
        , Svg.g [ SA.transform ("rotate(" ++ String.fromInt (dirAngle player.facing) ++ ")") ]
            [ Svg.g [ SA.transform ("rotate(" ++ String.fromFloat angle ++ ")") ] [ viewAstronaut player.color thrust ] ]
        ]


{-| True while the player's own astronaut fires its jet pack to move.
-}
thrusting : Model -> Game -> Player -> Bool
thrusting model game player =
    case model.held of
        Just dir ->
            canMove game.passages player.pos dir || model.sinceStep < walkStepMs / 2

        Nothing ->
            False


{-| Sway softly while the jet pack fires. Stay still at a wall.
-}
driftAngle : Model -> Game -> Player -> Float
driftAngle model game player =
    if thrusting model game player then
        7 * sin (model.walkTime / walkStepMs * pi / 2)

    else
        0


viewNorthMarker : Int -> Svg msg
viewNorthMarker side =
    let
        cx =
            String.fromInt (side // 2)
    in
    Svg.g [ SA.fill "#a5b4fc" ]
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


{-| Top-down astronaut, helmet to the north. The suit has the player's color.
Centered on 0,0. The jet pack flame shows while it moves.
-}
viewAstronaut : String -> Bool -> Svg msg
viewAstronaut color thrust =
    Svg.g []
        [ if thrust then
            Svg.g []
                [ Svg.polygon [ SA.points "-5,14 5,14 0,27", SA.fill "#f97316" ] []
                , Svg.polygon [ SA.points "-2.5,14 2.5,14 0,21", SA.fill "#fde68a" ] []
                ]

          else
            Svg.text ""
        , Svg.rect [ SA.x "-9", SA.y "3", SA.width "18", SA.height "12", SA.rx "3", SA.fill "#cbd5e1", SA.stroke "#64748b", SA.strokeWidth "1" ] []
        , Svg.ellipse [ SA.cx "-12", SA.cy "1", SA.rx "4", SA.ry "7", SA.fill color, SA.transform "rotate(-15 -12 1)" ] []
        , Svg.ellipse [ SA.cx "12", SA.cy "1", SA.rx "4", SA.ry "7", SA.fill color, SA.transform "rotate(15 12 1)" ] []
        , Svg.ellipse [ SA.cx "0", SA.cy "2", SA.rx "10", SA.ry "9", SA.fill color ] []
        , Svg.circle [ SA.cx "0", SA.cy "-7", SA.r "9", SA.fill "#f8fafc", SA.stroke "#cbd5e1", SA.strokeWidth "1" ] []
        , Svg.ellipse [ SA.cx "0", SA.cy "-10", SA.rx "6.5", SA.ry "4", SA.fill "#1e293b" ] []
        , Svg.ellipse [ SA.cx "-2.5", SA.cy "-11", SA.rx "2", SA.ry "1.2", SA.fill "#7dd3fc", SA.fillOpacity "0.8" ] []
        ]


{-| The escape pod, nose to the north, in a softly pulsing glow.
-}
viewPod : Svg msg
viewPod =
    Svg.g []
        [ Svg.circle [ SA.r "19", SA.fill "#a78bfa", SA.fillOpacity "0.25" ]
            [ Svg.animate [ SA.attributeName "r", SA.values "15;20;15", SA.dur "2s", SA.repeatCount "indefinite" ] [] ]
        , Svg.polygon [ SA.points "-9,8 -14,15 -6,13", SA.fill "#f43f5e" ] []
        , Svg.polygon [ SA.points "9,8 14,15 6,13", SA.fill "#f43f5e" ] []
        , Svg.path [ SA.d "M 0 -16 C 9 -10 10 4 8 13 L -8 13 C -10 4 -9 -10 0 -16 Z", SA.fill "#e2e8f0", SA.stroke "#94a3b8", SA.strokeWidth "1" ] []
        , Svg.circle [ SA.cx "0", SA.cy "-3", SA.r "4", SA.fill "#38bdf8", SA.stroke "#475569", SA.strokeWidth "1.5" ] []
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
