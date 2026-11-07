port module Graze exposing (main)

{-| Graze: each player is a circle in one shared field. A circle eats the
black squares (food) for points and energy, and keeps away from the red
squares (danger). The circles go through each other.

The server owns the game: it moves the squares, checks each circle and
sends the state many times a second. Each square flies on a straight line,
so its place at any time is known from its place at the time `t` and its
speed. This module draws the squares at the time of the server, as well as
this browser knows it (see `offset`).

The circle of this player follows the pointer (or the finger) with a top
speed, and this module draws it at once, without a wait for the server.
It sends the place of the circle many times a second, with the time of the
server when the player saw it. The server checks the circle at that time.
The circles of the other players move to their places from the server
softly.

The ring around a circle is its energy. It goes down all the time. When it
is empty, the circle is out.

The port names start with "graze", because Elm does not allow two ports
with the same name in one bundle.

-}

import Browser
import Browser.Dom
import Browser.Events
import Dict exposing (Dict)
import GameBar
import Html exposing (Html, a, aside, button, div, h1, img, input, li, ol, p, span, text, ul)
import Html.Attributes exposing (alt, attribute, class, classList, disabled, href, id, readonly, rel, src, style, target, value)
import Html.Events exposing (onClick)
import Html.Keyed
import Json.Decode as Decode exposing (Decoder)
import Process
import Svg exposing (Svg)
import Svg.Attributes as SA
import Svg.Keyed
import Task
import Time



-- PORTS


{-| The place of the circle of this player, and the time of the server when
the player saw it there.
-}
port grazeSteer : { x : Float, y : Float, t : Int } -> Cmd msg


port grazeRestart : () -> Cmd msg


{-| Starts the next game for all players, see OctomoctoWeb.NextGame
-}
port grazeNextGame : () -> Cmd msg


port grazeCopyText : String -> Cmd msg


port grazeJoined : (Decode.Value -> msg) -> Sub msg


port grazeState : (Decode.Value -> msg) -> Sub msg


port grazeJoinFailed : (String -> msg) -> Sub msg


{-| The number of browsers that only watch the game, after the join and
after each change.
-}
port grazeWatchers : (Int -> msg) -> Sub msg


port grazePlaySound : String -> Cmd msg


port grazeSaveMuted : Bool -> Cmd msg



-- MODEL


{-| The `name` is the display name of a signed-in player, or Nothing for a
guest. Then the player is known by the `colorName`.
-}
type alias Player =
    { id : String
    , name : Maybe String
    , colorName : String
    , score : Int
    }


type alias Circle =
    { id : String
    , x : Float
    , y : Float
    , alive : Bool
    , energy : Float
    , survivedMs : Int
    }


type Kind
    = Food
    | Danger


{-| A square is at `x`, `y` at the time `t` of the server, and moves `vx`,
`vy` units each second.
-}
type alias Square =
    { id : Int
    , kind : Kind
    , size : Float
    , x : Float
    , y : Float
    , vx : Float
    , vy : Float
    , t : Float
    }


type alias Game =
    { players : List Player
    , circles : List Circle
    , squares : List Square

    -- The time of the server when it sent the state
    , now : Float

    -- The time since the field started. After the end, the final time.
    , elapsedMs : Int
    , waiting : Bool
    , finished : Bool
    , playersNeeded : Int

    -- The energy that each circle loses in a second, now
    , drain : Float
    , size : Float
    , radius : Float

    -- The top speed of a circle, in units per millisecond
    , maxSpeed : Float
    }


{-| The player id of this browser. Nothing for a watcher.
-}
type alias Me =
    Maybe String


type Connection
    = Connecting
    | Joined Me Game
    | Failed String


{-| The game to try next, on the end screen
-}
type alias NextGame =
    { name : String
    , path : String
    }


type alias Model =
    { gameUrl : String
    , settingsUrl : String
    , nextGame : NextGame
    , guest : Bool
    , connection : Connection
    , copied : Bool

    -- The time of the server minus the local time, in milliseconds. It is
    -- the largest difference of all states: the state with the shortest
    -- delay on the network. Nothing before the first state.
    , offset : Maybe Float

    -- The local time (in ms) when the field started, and the local time
    -- of the last frame
    , clockStart : Float
    , now : Float

    -- The place in the field where the pointer of this player is. Nothing
    -- until the pointer first moves over the field.
    , pointer : Maybe ( Float, Float )

    -- The place of the circle of this player in this browser
    , mine : Maybe ( Float, Float )

    -- The local time when this browser last sent the place of its circle
    , lastSent : Float

    -- The places where this browser draws the other circles
    , others : Dict String ( Float, Float )

    -- The countdown step that last played its beep (see `countdownStep`)
    , beepedStep : Maybe Int
    , muted : Bool
    , watchers : Int

    -- The width and the height of the browser window
    , viewport : ( Float, Float )
    }


type alias Flags =
    { gameUrl : String
    , settingsUrl : String
    , nextGame : NextGame
    , guest : Bool
    , muted : Bool
    }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { gameUrl = flags.gameUrl
      , settingsUrl = flags.settingsUrl
      , nextGame = flags.nextGame
      , guest = flags.guest
      , connection = Connecting
      , copied = False
      , offset = Nothing
      , clockStart = 0
      , now = 0
      , pointer = Nothing
      , mine = Nothing
      , lastSent = 0
      , others = Dict.empty
      , beepedStep = Nothing
      , muted = flags.muted
      , watchers = 0
      , viewport = ( 1024, 768 )
      }
    , Task.perform (\vp -> Resized vp.viewport.width vp.viewport.height) Browser.Dom.getViewport
    )



-- UPDATE


type Msg
    = GotJoined Decode.Value
    | GotState Decode.Value
    | Received Me Game Time.Posix
    | GotJoinFailed String
    | GotWatchers Int
    | PointerAt Float Float
    | Frame Time.Posix
    | Restart
    | StartNextGame
    | CopyLink
    | CopiedTimeout
    | ToggleMuted
    | Resized Float Float


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotJoined value ->
            case Decode.decodeValue joinedDecoder value of
                Ok ( me, game ) ->
                    ( model, Task.perform (Received me game) Time.now )

                Err err ->
                    ( { model | connection = Failed (Decode.errorToString err) }, Cmd.none )

        GotState value ->
            case ( model.connection, Decode.decodeValue gameDecoder value ) of
                ( Joined me _, Ok game ) ->
                    ( model, Task.perform (Received me game) Time.now )

                _ ->
                    ( model, Cmd.none )

        Received me game time ->
            let
                local =
                    toFloat (Time.posixToMillis time)

                candidate =
                    game.now - local

                -- The clocks can drift, so an old difference goes down
                -- slowly
                offset =
                    case model.offset of
                        Just old ->
                            max candidate (old - 0.1)

                        Nothing ->
                            candidate

                sounds =
                    case model.connection of
                        Joined _ old ->
                            stateSounds me old game

                        _ ->
                            []

                received =
                    { model
                        | connection = Joined me game
                        , offset = Just offset
                        , clockStart = local - toFloat game.elapsedMs
                        , now = local
                    }
                        |> followServer me game
            in
            beepCountdown received |> Tuple.mapSecond (\cmd -> Cmd.batch [ cmd, playSounds model sounds ])

        GotJoinFailed reason ->
            ( { model | connection = Failed reason }, Cmd.none )

        GotWatchers count ->
            ( { model | watchers = count }, Cmd.none )

        PointerAt x y ->
            ( { model | pointer = Just ( x, y ) }, Cmd.none )

        Frame time ->
            frame (toFloat (Time.posixToMillis time)) model

        Restart ->
            ( model, grazeRestart () )

        StartNextGame ->
            ( model, grazeNextGame () )

        CopyLink ->
            ( { model | copied = True }
            , Cmd.batch
                [ grazeCopyText model.gameUrl
                , Process.sleep 1500 |> Task.perform (\_ -> CopiedTimeout)
                ]
            )

        CopiedTimeout ->
            ( { model | copied = False }, Cmd.none )

        Resized width height ->
            ( { model | viewport = ( width, height ) }, Cmd.none )

        ToggleMuted ->
            ( { model | muted = not model.muted }, grazeSaveMuted (not model.muted) )


{-| Until the field runs, and after the circle of this player is out, this
browser draws the circle where the server has it. The other circles are new
in the drawing at their places from the server.
-}
followServer : Me -> Game -> Model -> Model
followServer me game model =
    let
        mine =
            case myCircle me game of
                Just circle ->
                    if running model game && circle.alive && model.mine /= Nothing then
                        model.mine

                    else
                        Just ( circle.x, circle.y )

                Nothing ->
                    Nothing

        others =
            game.circles
                |> List.filter (\c -> Just c.id /= me)
                |> List.map
                    (\c ->
                        ( c.id
                        , if running model game then
                            Dict.get c.id model.others |> Maybe.withDefault ( c.x, c.y )

                          else
                            ( c.x, c.y )
                        )
                    )
                |> Dict.fromList

    in
    { model | mine = mine, others = others }


{-| True while the field runs: after the countdown and before the end.
-}
running : Model -> Game -> Bool
running model game =
    not game.waiting && not game.finished && model.now >= model.clockStart


{-| One frame: the circle of this player moves to the pointer, the other
circles move to their places from the server, and this browser sends the
place of its circle.
-}
frame : Float -> Model -> ( Model, Cmd Msg )
frame local model =
    case model.connection of
        Joined me game ->
            let
                dt =
                    min 100 (max 0 (local - model.now))

                moved =
                    { model | now = local }

                alive =
                    myCircle me game |> Maybe.map .alive |> Maybe.withDefault False

                mine =
                    case ( moved.mine, moved.pointer ) of
                        ( Just from, Just to ) ->
                            if running moved game && alive then
                                Just (moveToward game (game.maxSpeed * dt) from to)

                            else
                                moved.mine

                        _ ->
                            moved.mine

                ease =
                    min 1 (dt / 80)

                others =
                    game.circles
                        |> List.filterMap
                            (\c ->
                                Dict.get c.id moved.others
                                    |> Maybe.map
                                        (\( x, y ) ->
                                            ( c.id, ( x + (c.x - x) * ease, y + (c.y - y) * ease ) )
                                        )
                            )
                        |> Dict.fromList

                send =
                    running moved game && alive && local - model.lastSent >= 40

                ( sent, steer ) =
                    case ( send, mine, moved.offset ) of
                        ( True, Just ( x, y ), Just offset ) ->
                            ( local, grazeSteer { x = x, y = y, t = round (local + offset) } )

                        _ ->
                            ( model.lastSent, Cmd.none )
            in
            beepCountdown { moved | mine = mine, others = others, lastSent = sent }
                |> Tuple.mapSecond (\cmd -> Cmd.batch [ cmd, steer ])

        _ ->
            ( model, Cmd.none )


{-| A step from `from` to `to`, not longer than `step`, and in the field.
-}
moveToward : Game -> Float -> ( Float, Float ) -> ( Float, Float ) -> ( Float, Float )
moveToward game step ( fx, fy ) ( tx, ty ) =
    let
        inField v =
            clamp game.radius (game.size - game.radius) v

        ( dx, dy ) =
            ( inField tx - fx, inField ty - fy )

        distance =
            sqrt (dx * dx + dy * dy)
    in
    if distance <= step then
        ( inField tx, inField ty )

    else
        ( fx + dx * step / distance, fy + dy * step / distance )


myCircle : Me -> Game -> Maybe Circle
myCircle me game =
    List.head (List.filter (\c -> Just c.id == me) game.circles)


{-| The time of the server that this browser draws now.
-}
serverNow : Model -> Float
serverNow model =
    model.now + Maybe.withDefault 0 model.offset


{-| The seconds left in the countdown (3, 2, 1), 0 after it, and Nothing
when no field runs.
-}
countdownStep : Model -> Maybe Int
countdownStep model =
    case model.connection of
        Joined _ game ->
            if game.waiting || game.finished then
                Nothing

            else
                Just (max 0 (ceiling ((model.clockStart - model.now) / 1000)))

        _ ->
            Nothing


{-| A beep on each step of the countdown, and a higher beep at the start.
There is no start beep without a countdown before it, for example for a
watcher who joins later.
-}
beepCountdown : Model -> ( Model, Cmd Msg )
beepCountdown model =
    let
        step =
            countdownStep model

        sounds =
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
    in
    ( { model | beepedStep = step }, playSounds model sounds )


playSounds : Model -> List String -> Cmd Msg
playSounds model names =
    if model.muted then
        Cmd.none

    else
        Cmd.batch (List.map grazePlaySound names)


{-| The sounds for the change from the old state to the new one: the start
of the game, a food square that this player ate, the circle of this player
that is out, and the end of a game with more players.
-}
stateSounds : Me -> Game -> Game -> List String
stateSounds me old new =
    let
        startSound =
            if old.waiting && not new.waiting && List.length new.players > 1 then
                [ "start" ]

            else
                []

        score game =
            List.filter (\p -> Just p.id == me) game.players |> List.head |> Maybe.map .score

        ateSound =
            case ( score old, score new ) of
                ( Just before, Just after ) ->
                    if after > before then
                        [ "found" ]

                    else
                        []

                _ ->
                    []

        alive game =
            myCircle me game |> Maybe.map .alive

        outSound =
            if alive old == Just True && alive new == Just False && not old.waiting then
                [ "wrong" ]

            else
                []

        endSound =
            if new.finished && not old.finished && List.length new.players > 1 && me /= Nothing then
                case winners new.players of
                    [ winner ] ->
                        if Just winner.id == me then
                            [ "win" ]

                        else
                            [ "lose" ]

                    _ ->
                        [ "lose" ]

            else
                []
    in
    startSound ++ ateSound ++ outSound ++ endSound


winners : List Player -> List Player
winners players =
    let
        best =
            List.maximum (List.map .score players) |> Maybe.withDefault 0
    in
    List.filter (\p -> p.score == best) players



-- DECODERS


joinedDecoder : Decoder ( Me, Game )
joinedDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "player_id" (Decode.nullable Decode.string))
        (Decode.field "state" gameDecoder)


gameDecoder : Decoder Game
gameDecoder =
    Decode.succeed Game
        |> andMap (Decode.field "players" (Decode.list playerDecoder))
        |> andMap (Decode.field "circles" (Decode.list circleDecoder))
        |> andMap (Decode.field "squares" (Decode.list squareDecoder))
        |> andMap (Decode.field "now" Decode.float)
        |> andMap (Decode.field "elapsed_ms" Decode.int)
        |> andMap (Decode.field "waiting" Decode.bool)
        |> andMap (Decode.field "finished" Decode.bool)
        |> andMap (Decode.field "players_needed" Decode.int)
        |> andMap (Decode.field "drain" Decode.float)
        |> andMap (Decode.field "size" Decode.float)
        |> andMap (Decode.field "radius" Decode.float)
        |> andMap (Decode.field "max_speed" Decode.float)


andMap : Decoder a -> Decoder (a -> b) -> Decoder b
andMap =
    Decode.map2 (|>)


playerDecoder : Decoder Player
playerDecoder =
    Decode.map4 Player
        (Decode.field "id" Decode.string)
        (Decode.field "name" (Decode.nullable Decode.string))
        (Decode.field "color_name" Decode.string)
        (Decode.field "score" Decode.int)


circleDecoder : Decoder Circle
circleDecoder =
    Decode.map6 Circle
        (Decode.field "id" Decode.string)
        (Decode.field "x" Decode.float)
        (Decode.field "y" Decode.float)
        (Decode.field "alive" Decode.bool)
        (Decode.field "energy" Decode.float)
        (Decode.field "survived_ms" Decode.int)


squareDecoder : Decoder Square
squareDecoder =
    Decode.map8 Square
        (Decode.field "id" Decode.int)
        (Decode.field "kind" Decode.string
            |> Decode.map
                (\kind ->
                    if kind == "food" then
                        Food

                    else
                        Danger
                )
        )
        (Decode.field "size" Decode.float)
        (Decode.field "x" Decode.float)
        (Decode.field "y" Decode.float)
        (Decode.field "vx" Decode.float)
        (Decode.field "vy" Decode.float)
        (Decode.field "t" Decode.float)


{-| The place of the pointer in the field, from a pointer event on the layer
over the field. The layer has the size of the field.
-}
pointerDecoder : Float -> Decoder Msg
pointerDecoder size =
    Decode.map3
        (\x y width ->
            if width > 0 then
                PointerAt (x / width * size) (y / width * size)

            else
                PointerAt x y
        )
        (Decode.field "offsetX" Decode.float)
        (Decode.field "offsetY" Decode.float)
        (Decode.at [ "currentTarget", "clientWidth" ] Decode.float)



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ grazeJoined GotJoined
        , grazeState GotState
        , grazeJoinFailed GotJoinFailed
        , grazeWatchers GotWatchers
        , Browser.Events.onResize (\w h -> Resized (toFloat w) (toFloat h))
        , case model.connection of
            Joined _ game ->
                if not game.waiting && not game.finished then
                    Browser.Events.onAnimationFrame Frame

                else
                    Sub.none

            _ ->
                Sub.none
        ]



-- VIEW


view : Model -> Html Msg
view model =
    case model.connection of
        Connecting ->
            p [ id "graze-connecting", class "py-24 text-center opacity-60" ] [ text "Joining the game…" ]

        Failed reason ->
            p [ id "graze-failed", class "py-24 text-center text-red-600 dark:text-red-400" ] [ text ("Could not join the game: " ++ reason) ]

        Joined me game ->
            viewGame model me game


viewGame : Model -> Me -> Game -> Html Msg
viewGame model me game =
    div
        [ id "graze-root"
        , class "flex w-full flex-col gap-2 select-none max-lg:landscape:flex-row max-lg:landscape:items-start max-lg:landscape:gap-3 lg:flex-row lg:items-start lg:gap-8"
        , classList [ ( "is-playing", not game.waiting && not game.finished ) ]
        ]
        [ aside [ id "graze-panel", class "flex flex-col gap-2 max-lg:landscape:w-48 max-lg:landscape:shrink-0 max-lg:landscape:gap-4 lg:sticky lg:top-6 lg:w-72 lg:shrink-0 lg:gap-5" ]
            [ div [ class "flex items-center gap-1 max-lg:landscape:flex-col max-lg:landscape:items-start max-lg:landscape:gap-4 lg:contents" ]
                [ div [ class "min-w-0 lg:order-1" ]
                    [ div [ class "flex items-center gap-1 lg:gap-2" ]
                        [ a
                            [ id "graze-home"
                            , href "/"
                            , class "mr-1 shrink-0 transition lg:mr-0"
                            ]
                            [ img [ src "/images/mark.svg", alt "octomocto", class "h-8 w-auto dark:hidden lg:h-9" ] []
                            , img [ src "/images/mark-on-dark.svg", alt "octomocto", class "hidden h-8 w-auto dark:block lg:h-9" ] []
                            ]
                        , h1 [ class "truncate text-xl font-semibold tracking-tight lg:text-2xl" ]
                            [ a
                                [ id "graze-title-link"
                                , href "/graze"
                                , class "transition hover:text-octo-indigo dark:hover:text-octo-indigo-light"
                                ]
                                [ text "Graze" ]
                            ]
                        , viewWatchers (me == Nothing) model.watchers
                        ]
                    , p [ class "hidden text-sm opacity-60 lg:block" ] [ text "Eat the black squares. Keep away from the red ones." ]
                    ]
                , viewClock model me game
                , viewMenu model.muted (me /= Nothing)
                ]
            , if game.playersNeeded > 1 then
                viewShareLink model

              else
                text ""
            , if game.playersNeeded > 1 then
                viewScores me game

              else
                text ""
            ]
        , div [ class "min-w-0 flex-1" ] [ viewBoard model me game ]
        ]


{-| The board, with the message of the game over it.
-}
viewBoard : Model -> Me -> Game -> Html Msg
viewBoard model me game =
    let
        out =
            myCircle me game |> Maybe.map (not << .alive) |> Maybe.withDefault False
    in
    div [ class "relative mx-auto", style "width" (fieldWidth model me game) ]
        [ viewField model me game
        , div
            [ id "graze-pointer"
            , class "absolute inset-0 touch-none"
            , classList [ ( "cursor-none", running model game && not out && me /= Nothing ) ]
            , Html.Events.on "pointermove" (pointerDecoder game.size)
            , Html.Events.on "pointerdown" (pointerDecoder game.size)
            ]
            []
        , if game.waiting then
            viewWaiting game

          else if Maybe.withDefault 0 (countdownStep model) > 0 then
            viewCountdown (Maybe.withDefault 0 (countdownStep model))

          else if game.finished then
            viewResult model me game

          else if out then
            viewOut me game

          else
            text ""
        ]


{-| The width of the screen from which the panel is at the left of the
board. On a smaller screen, the panel is a compact row above the board.
-}
largeScreen : Float
largeScreen =
    1024


{-| The height in pixels of the screen that is not for the board, as in
Schulte: the bar at the top, the padding of the page, and on a small screen
that is taller than wide, the rows of the panel above the board.
-}
reservedHeight : Model -> Me -> Game -> Float
reservedHeight model me game =
    let
        ( width, height ) =
            model.viewport

        page =
            if width >= largeScreen then
                48

            else if width > height then
                16

            else
                16
                    + 48
                    + (if game.playersNeeded > 1 then
                        46 + 36

                       else
                        0
                      )
                    + (if me == Nothing then
                        52

                       else
                        0
                      )
    in
    GameBar.height + page


{-| The board is square. Make it as wide as possible, but small enough that
it is all on the screen.
-}
fieldWidth : Model -> Me -> Game -> String
fieldWidth model me game =
    "min(100%, calc(100dvh - " ++ String.fromFloat (reservedHeight model me game) ++ "px))"


viewWatchers : Bool -> Int -> Html Msg
viewWatchers watching count =
    if watching || count > 0 then
        span
            [ id "graze-watchers"
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


viewMenu : Bool -> Bool -> Html Msg
viewMenu muted player =
    Html.node "octo-game-menu"
        [ class "relative shrink-0 lg:order-5 lg:self-start"
        , attribute "menu-label" "Menu"
        , attribute "restart-label" "Restart game"
        , attribute "sound-on-label" "Turn the sounds on"
        , attribute "sound-off-label" "Turn the sounds off"
        , attribute "locked" "false"
        , attribute "muted" (boolAttribute muted)
        , attribute "player" (boolAttribute player)
        , Html.Events.on "octo-restart" (Decode.succeed Restart)
        , Html.Events.on "octo-toggle-mute" (Decode.succeed ToggleMuted)
        ]
        []


viewShareLink : Model -> Html Msg
viewShareLink model =
    div [ class "flex items-center gap-2 rounded-full bg-octo-mist p-1 pl-4 text-sm lg:order-3 ring-1 ring-octo-indigo/20 max-lg:landscape:flex-col max-lg:landscape:items-stretch max-lg:landscape:rounded-2xl max-lg:landscape:p-2 lg:flex-col lg:items-stretch lg:rounded-2xl lg:p-2 lg:pl-2 dark:bg-octo-indigo/15 dark:ring-octo-indigo-light/25" ]
        [ input
            [ id "graze-link"
            , readonly True
            , value model.gameUrl
            , class "min-w-0 flex-1 truncate bg-transparent text-octo-navy outline-none max-lg:landscape:px-2 max-lg:landscape:py-1 lg:px-2 lg:py-1 dark:text-slate-100"
            ]
            []
        , button
            [ id "graze-copy-link"
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


{-| The scores of all players. A circle that is out is pale. My circle has
the color of my circle in the field (black, or white in the dark theme), the
others are gray, as in the field.
-}
viewScores : Me -> Game -> Html Msg
viewScores me game =
    ul [ id "graze-scores", class "flex flex-wrap gap-2 max-lg:landscape:flex-col lg:order-4 lg:flex-col" ]
        (List.map
            (\player ->
                let
                    out =
                        game.circles
                            |> List.filter (\c -> c.id == player.id)
                            |> List.head
                            |> Maybe.map (not << .alive)
                            |> Maybe.withDefault False
                in
                li
                    [ id ("graze-score-" ++ player.id)
                    , class "flex items-center gap-2 rounded-full bg-white px-3 py-1 text-sm text-slate-800 shadow-sm ring-1 ring-slate-200 transition-opacity dark:bg-white/5 dark:text-slate-100 dark:shadow-none dark:ring-white/10"
                    , classList [ ( "opacity-50", out && not game.waiting ) ]
                    ]
                    [ span
                        [ class "size-3 rounded-full"
                        , class
                            (if Just player.id == me then
                                "graze-dot-me"

                             else
                                "graze-dot-other"
                            )
                        ]
                        []
                    , span [ class "max-lg:landscape:flex-1 lg:flex-1" ] [ text (playerName me player) ]
                    , span [ class "font-semibold tabular-nums" ] [ text (String.fromInt player.score) ]
                    ]
            )
            game.players
        )


playerName : Me -> Player -> String
playerName me player =
    if Just player.id == me then
        Maybe.withDefault player.colorName player.name ++ " (you)"

    else
        Maybe.withDefault player.colorName player.name


{-| The time on the left, and the score of this player (or the best score,
for a watcher) on the right.
-}
viewClock : Model -> Me -> Game -> Html Msg
viewClock model me game =
    let
        elapsedMs =
            if game.finished then
                game.elapsedMs

            else
                max 0 (round (model.now - model.clockStart))

        score =
            case List.filter (\p -> Just p.id == me) game.players of
                player :: _ ->
                    player.score

                [] ->
                    List.maximum (List.map .score game.players) |> Maybe.withDefault 0
    in
    div [ id "graze-clock", class "ml-auto flex gap-4 pr-2 max-lg:landscape:ml-0 max-lg:landscape:gap-6 max-lg:landscape:pr-0 max-lg:landscape:pl-2 lg:order-2 lg:ml-0 lg:grid lg:grid-cols-2 lg:gap-0 lg:divide-x lg:divide-slate-200 lg:rounded-2xl lg:bg-white lg:py-3 lg:pr-0 lg:shadow-sm lg:ring-1 lg:ring-slate-200 dark:lg:divide-white/10 dark:lg:bg-white/5 dark:lg:shadow-none dark:lg:ring-white/10" ]
        [ div [ class "flex flex-col items-center justify-center max-lg:landscape:items-start" ]
            [ span [ class "text-[0.625rem] font-medium tracking-wide text-slate-400 uppercase lg:text-xs" ] [ text "time" ]
            , span [ id "graze-time", class "text-lg leading-tight font-light text-slate-700 tabular-nums lg:text-3xl dark:text-slate-100" ] [ text (formatTime elapsedMs) ]
            ]
        , div [ class "flex flex-col items-center justify-center max-lg:landscape:items-start" ]
            [ span [ class "text-[0.625rem] font-medium tracking-wide text-slate-400 uppercase lg:text-xs" ] [ text "score" ]
            , Html.Keyed.node "span"
                [ class "text-xl leading-tight font-bold text-octo-indigo tabular-nums lg:text-4xl lg:leading-none dark:text-octo-indigo-light" ]
                [ ( String.fromInt score
                  , span [ id "graze-score", class "graze-score inline-block" ] [ text (String.fromInt score) ]
                  )
                ]
            ]
        ]


{-| Show the time as minutes, seconds and tenths, for example "0:19.4".
-}
formatTime : Int -> String
formatTime ms =
    let
        seconds =
            ms // 1000
    in
    String.fromInt (seconds // 60)
        ++ ":"
        ++ String.padLeft 2 '0' (String.fromInt (modBy 60 seconds))
        ++ "."
        ++ String.fromInt (modBy 10 (ms // 100))


{-| The field: the squares at the time of the server, the circles of the
other players, and my circle on top. The colors are in the CSS, for the
light and the dark theme.
-}
viewField : Model -> Me -> Game -> Html Msg
viewField model me game =
    let
        side =
            String.fromFloat game.size

        time =
            serverNow model

        -- Between two states, the energy goes down with the drain
        sinceState =
            if game.finished || not (running model game) then
                0

            else
                max 0 (time - game.now) / 1000

        energyOf circle =
            max 0 (circle.energy - game.drain * sinceState)

        others =
            game.circles
                |> List.filter (\c -> Just c.id /= me)
                |> List.map
                    (\c ->
                        let
                            ( x, y ) =
                                Dict.get c.id model.others |> Maybe.withDefault ( c.x, c.y )

                            name =
                                game.players
                                    |> List.filter (\p -> p.id == c.id)
                                    |> List.head
                                    |> Maybe.map (\p -> Maybe.withDefault p.colorName p.name)
                                    |> Maybe.withDefault ""
                        in
                        ( c.id, viewCircle game False (Just name) x y c.alive (energyOf c) )
                    )

        mine =
            case ( myCircle me game, model.mine ) of
                ( Just c, Just ( x, y ) ) ->
                    [ ( c.id, viewCircle game True Nothing x y c.alive (energyOf c) ) ]

                _ ->
                    []
    in
    Svg.svg
        [ SA.id "graze-field"
        , SA.viewBox ("0 0 " ++ side ++ " " ++ side)
        , SA.class "block h-auto w-full drop-shadow-sm"
        ]
        [ Svg.defs []
            [ Svg.clipPath [ SA.id "graze-board-shape" ]
                [ Svg.rect [ SA.width side, SA.height side, SA.rx "18" ] [] ]
            ]
        , Svg.g [ SA.clipPath "url(#graze-board-shape)" ]
            [ Svg.rect [ SA.width side, SA.height side, SA.class "graze-board" ] []
            , Svg.Keyed.node "g" [] (List.map (\s -> ( String.fromInt s.id, viewSquare time s )) game.squares)
            , Svg.Keyed.node "g" [] (others ++ mine)
            ]
        , Svg.rect
            [ SA.x "1.5"
            , SA.y "1.5"
            , SA.width (String.fromFloat (game.size - 3))
            , SA.height (String.fromFloat (game.size - 3))
            , SA.rx "16.5"
            , SA.class "graze-border"
            , SA.fill "none"
            , SA.strokeWidth "3"
            ]
            []
        ]


viewSquare : Float -> Square -> Svg Msg
viewSquare time square =
    let
        dt =
            (time - square.t) / 1000

        ( x, y ) =
            ( square.x + square.vx * dt, square.y + square.vy * dt )
    in
    Svg.rect
        [ SA.x (String.fromFloat (x - square.size / 2))
        , SA.y (String.fromFloat (y - square.size / 2))
        , SA.width (String.fromFloat square.size)
        , SA.height (String.fromFloat square.size)
        , SA.rx "3"
        , SA.class
            (case square.kind of
                Food ->
                    "graze-food"

                Danger ->
                    "graze-danger"
            )
        ]
        []


{-| A circle with its energy ring. The ring starts at the top and goes
clockwise. An almost empty ring of my circle blinks. Another player's
circle has the name above it.
-}
viewCircle : Game -> Bool -> Maybe String -> Float -> Float -> Bool -> Float -> Svg Msg
viewCircle game isMine name x y alive energy =
    let
        cx =
            String.fromFloat x

        cy =
            String.fromFloat y

        ringRadius =
            game.radius + 7

        ring attrs =
            Svg.circle
                ([ SA.cx cx
                 , SA.cy cy
                 , SA.r (String.fromFloat ringRadius)
                 , SA.fill "none"
                 , SA.strokeWidth "5"
                 , attribute "pathLength" "100"
                 ]
                    ++ attrs
                )
                []
    in
    Svg.g
        [ SA.class
            (String.join " "
                [ "graze-circle"
                , if isMine then
                    "graze-me"

                  else
                    "graze-other"
                , if alive then
                    ""

                  else
                    "is-out"
                ]
            )
        ]
        [ ring [ SA.class "graze-ring-track" ]
        , if alive then
            ring
                [ SA.class
                    (if isMine && energy < 0.25 then
                        "graze-ring graze-ring-low"

                     else
                        "graze-ring"
                    )
                , SA.strokeDasharray (String.fromFloat (energy * 100) ++ " 100")
                , SA.strokeLinecap "round"
                , SA.transform ("rotate(-90 " ++ cx ++ " " ++ cy ++ ")")
                ]

          else
            text ""
        , Svg.circle [ SA.cx cx, SA.cy cy, SA.r (String.fromFloat game.radius), SA.class "graze-body" ] []
        , case name of
            Just label ->
                Svg.text_
                    [ SA.x cx
                    , SA.y (String.fromFloat (y - ringRadius - 12))
                    , SA.textAnchor "middle"
                    , SA.fontSize "26"
                    , SA.class "graze-name"
                    ]
                    [ Svg.text label ]

            Nothing ->
                text ""
        ]


{-| Covers the empty field until all players are in.
-}
viewWaiting : Game -> Html Msg
viewWaiting game =
    div
        [ id "graze-waiting"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-3 rounded-2xl bg-octo-navy/80 p-4 text-center text-white"
        ]
        [ p [ class "text-3xl font-semibold" ] [ text "Waiting for players" ]
        , p [ id "graze-waiting-count", class "text-lg tabular-nums opacity-80" ]
            [ text
                (String.fromInt (List.length game.players)
                    ++ " of "
                    ++ String.fromInt game.playersNeeded
                    ++ " players are in"
                )
            ]
        , p [ class "text-sm opacity-60" ] [ text "Send the link to the other players. The game starts when all of them are in." ]
        ]


{-| The number is keyed, so that it pops in again on each step. The field
shows through, so that the players see where their circles start.
-}
viewCountdown : Int -> Html Msg
viewCountdown seconds =
    div
        [ id "graze-countdown"
        , class "pointer-events-none absolute inset-0 flex items-center justify-center rounded-2xl bg-octo-navy/40"
        ]
        [ Html.Keyed.node "div"
            []
            [ ( String.fromInt seconds
              , p [ class "countdown-pop text-9xl font-bold text-white tabular-nums drop-shadow-lg" ] [ text (String.fromInt seconds) ]
              )
            ]
        ]


{-| My circle is out, and other circles still play. The message is small and
at the top, so that the player can watch the others.
-}
viewOut : Me -> Game -> Html Msg
viewOut me game =
    let
        score =
            List.filter (\p -> Just p.id == me) game.players |> List.head |> Maybe.map .score |> Maybe.withDefault 0
    in
    div [ class "pointer-events-none absolute inset-x-0 top-4 flex justify-center" ]
        [ p
            [ id "graze-out"
            , class "rounded-full bg-octo-navy/80 px-5 py-2 text-sm font-medium text-white shadow-lg backdrop-blur-sm"
            ]
            [ text ("You are out with " ++ pointsText score ++ ". The others still play.") ]
        ]


pointsText : Int -> String
pointsText score =
    if score == 1 then
        "1 point"

    else
        String.fromInt score ++ " points"


viewResult : Model -> Me -> Game -> Html Msg
viewResult model me game =
    let
        players =
            game.players

        solo =
            List.length players == 1

        message =
            case ( solo, winners players ) of
                ( True, _ ) ->
                    "Game over"

                ( False, [ winner ] ) ->
                    if Just winner.id == me then
                        "You win!"

                    else
                        case winner.name of
                            Just name ->
                                name ++ " wins!"

                            Nothing ->
                                "The " ++ winner.colorName ++ " player wins!"

                ( False, _ ) ->
                    "It's a tie!"

        ranked =
            List.reverse (List.sortBy .score players)

        survived id =
            game.circles |> List.filter (\c -> c.id == id) |> List.head |> Maybe.map .survivedMs |> Maybe.withDefault 0
    in
    div
        [ id "graze-result"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-4 rounded-2xl bg-octo-navy/70 p-4 text-white backdrop-blur-sm"
        ]
        [ p [ class "text-3xl font-semibold" ] [ text message ]
        , if solo then
            p [ id "graze-final-score", class "text-lg tabular-nums opacity-80" ]
                [ text
                    (List.head players
                        |> Maybe.map (\player -> pointsText player.score ++ " · " ++ formatTime (survived player.id))
                        |> Maybe.withDefault ""
                    )
                ]

          else
            ol [ id "graze-final-scores", class "flex flex-col gap-1 text-sm" ]
                (List.map
                    (\player ->
                        li [ class "flex items-center gap-2" ]
                            [ span [ class "flex-1" ] [ text (playerName me player) ]
                            , span [ class "pl-6 tabular-nums opacity-60" ] [ text (formatTime (survived player.id)) ]
                            , span [ class "pl-4 font-semibold tabular-nums" ] [ text (String.fromInt player.score) ]
                            ]
                    )
                    ranked
                )
        , if me == Nothing then
            text ""

          else
            button
                [ id "graze-play-again"
                , class "rounded-full bg-white px-6 py-2.5 font-medium text-octo-indigo shadow-lg transition hover:bg-octo-mist"
                , onClick Restart
                ]
                [ text "Play again" ]
        , a
            [ id "graze-leaderboards-link"
            , href model.settingsUrl
            , class "text-sm font-medium text-white/80 underline-offset-4 transition hover:text-white hover:underline"
            ]
            [ text "Best results" ]
        , let
            -- In a game with other players, a player starts the next game for all of them
            ( element, action ) =
                if me /= Nothing && List.length game.players > 1 then
                    ( button, onClick StartNextGame )

                else
                    ( a, href model.nextGame.path )
          in
          element
            [ id "graze-next-game"
            , action
            , attribute "data-ga-link" "or_try"
            , attribute "data-ga-from" "Graze"
            , attribute "data-ga-to" model.nextGame.name
            , class "group text-sm font-medium text-white underline-offset-4 transition hover:underline"
            ]
            [ text ("Or try " ++ model.nextGame.name ++ " ")
            , span [ class "inline-block transition group-hover:translate-x-0.5" ] [ text "→" ]
            ]

        -- Only a guest who played gets the call to sign in, not a spectator
        , if model.guest && me /= Nothing then
            p [ id "graze-sign-in", class "text-sm text-white/70" ]
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
    p [ id "graze-feed", class "mt-2 max-w-sm border-t border-white/15 pt-4 text-center text-sm leading-10 text-balance text-white/80" ]
        [ text "Enjoying Octomocto? "
        , a
            [ href "/donate"
            , target "_blank"
            , rel "noopener"
            , class "group mx-1 inline-flex items-center gap-1.5 whitespace-nowrap rounded-full bg-octo-orange px-4 py-1.5 align-middle leading-5 font-semibold text-white shadow-lg shadow-octo-orange/30 transition hover:bg-octo-orange-light"
            ]
            [ span [ class "hero-heart-solid size-4 transition group-hover:scale-110" ] []
            , text "Support the author"
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


boolAttribute : Bool -> String
boolAttribute value =
    if value then
        "true"

    else
        "false"
