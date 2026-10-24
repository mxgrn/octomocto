port module Sudoku exposing (main)

{-| Multiplayer sudoku: put a digit from 1 to 9 in each empty cell, so that
each row, each column and each box of 3 by 3 cells has each digit one time.

The server owns the game: the grid, the solution and the scores. This
module draws the state that comes in through ports and sends the digits of
the player out. app.js connects the ports to a Phoenix channel.

The player selects a cell, then types a digit or clicks it on the pad. A
digit that is already in the row, the column or the box of the cell is
wrong at once: it shakes, the cell with the same digit turns red, and it
does not go to the server. Other digits go to the server, which compares
them with the solution. The first player who puts the correct digit in a
cell gets the point. The reply of the server tells if the digit is wrong,
and then it shakes too.

All players race on the same grid. Before all of them are in, nobody sees
the grid. A countdown with beeps comes before each puzzle. A browser that
joins a full game only watches: it has no player id.

The module compares each new state with the old one and sends the names of
the sounds to play out through a port. The player can mute the sounds.

-}

import Array exposing (Array)
import Browser
import Browser.Dom
import Browser.Events
import Html exposing (Html, a, aside, button, div, h1, img, input, li, ol, p, span, text, ul)
import Html.Attributes exposing (alt, attribute, class, classList, href, id, readonly, rel, src, style, target, value)
import Html.Events exposing (onClick)
import Html.Keyed
import Json.Decode as Decode exposing (Decoder)
import Process
import Task
import Time



-- PORTS


port sudokuPlace : { cell : Int, digit : Int } -> Cmd msg


port sudokuRestart : () -> Cmd msg


{-| Starts the next game for all players, see OctomoctoWeb.NextGame
-}
port sudokuNextGame : () -> Cmd msg


port sudokuCopyText : String -> Cmd msg


port sudokuJoined : (Decode.Value -> msg) -> Sub msg


port sudokuState : (Decode.Value -> msg) -> Sub msg


port sudokuJoinFailed : (String -> msg) -> Sub msg


{-| The number of browsers that only watch the game, after the join and
after each change.
-}
port sudokuWatchers : (Int -> msg) -> Sub msg


{-| The reply of the server to a digit: "ok", "wrong" or "ignored"
-}
port sudokuPlaced : ({ cell : Int, digit : Int, result : String } -> msg) -> Sub msg


port sudokuPlaySound : String -> Cmd msg


port sudokuSaveMuted : Bool -> Cmd msg



-- MODEL


{-| The `name` is the display name of a signed-in player, or Nothing for a
guest. Then the player is known by the `colorName`. An `away` player lost
the connection, and can come back for a short time.
-}
type alias Player =
    { id : String
    , name : Maybe String
    , color : String
    , colorName : String
    , score : Int
    , away : Bool
    }


{-| A digit on the grid. A digit of the puzzle has no player and no color.
-}
type alias Filled =
    { digit : Int
    , playerId : Maybe String
    , color : Maybe String
    }


{-| The last cell that a player filled
-}
type alias Last =
    { playerId : String
    , cell : Int
    }


type alias Game =
    { -- The 81 cells, row by row. Empty before the start and during the
      -- countdown.
      cells : Array (Maybe Filled)
    , last : Maybe Last
    , difficulty : String

    -- True until the game has all its players
    , waiting : Bool
    , finished : Bool

    -- The time since the start, below zero during the countdown. After the
    -- end, the final time.
    , elapsedMs : Int
    , players : List Player
    , playersNeeded : Int
    }


{-| The player id of this browser. Nothing for a watcher.
-}
type alias Me =
    Maybe String


type Connection
    = Connecting
    | Joined Me Game
    | Failed String


{-| A digit in a cell
-}
type alias Move =
    { cell : Int
    , digit : Int
    }


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

    -- The selected cell
    , selected : Maybe Int

    -- The digit that went to the server, until it is on the grid or the
    -- server rejects it
    , pending : Maybe Move

    -- The last wrong digit, while it shakes, and the cells with the same
    -- digit in its row, column or box. The number tells the shakes apart,
    -- so that the end of an old shake does not stop a new one.
    , wrong : Maybe Move
    , conflicts : List Int
    , wrongCount : Int

    -- The local time (in ms) when the puzzle started, and the local time
    -- now. The clock ticks between the server updates.
    , clockStart : Int
    , now : Int

    -- The countdown step that last played its beep (see `countdownStep`)
    , beepedStep : Maybe Int
    , muted : Bool
    , watchers : Int

    -- The width and the height of the screen in pixels
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
      , selected = Nothing
      , pending = Nothing
      , wrong = Nothing
      , conflicts = []
      , wrongCount = 0
      , clockStart = 0
      , now = 0
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
    | GotJoinFailed String
    | GotWatchers Int
    | GotPlaced { cell : Int, digit : Int, result : String }
    | Select Int
    | Place Int
    | KeyDown String
    | WrongDone Int
    | Restart
    | StartNextGame
    | CopyLink
    | CopiedTimeout
    | SyncClock Int Time.Posix
    | Tick Time.Posix
    | ToggleMuted
    | Resized Float Float


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotJoined value ->
            case Decode.decodeValue joinedDecoder value of
                Ok ( me, game ) ->
                    ( { model | connection = Joined me game, pending = Nothing }, syncClock game )

                Err err ->
                    ( { model | connection = Failed (Decode.errorToString err) }, Cmd.none )

        GotState value ->
            case ( model.connection, Decode.decodeValue gameDecoder value ) of
                ( Joined me old, Ok game ) ->
                    ( { model
                        | connection = Joined me game

                        -- The digit is on the grid, or another player
                        -- filled the cell first
                        , pending =
                            model.pending
                                |> Maybe.andThen
                                    (\placed ->
                                        if digitAt game placed.cell == Nothing then
                                            Just placed

                                        else
                                            Nothing
                                    )
                        , selected =
                            if Array.isEmpty game.cells then
                                Nothing

                            else
                                model.selected
                      }
                    , Cmd.batch [ syncClock game, playSounds model (stateSounds me old game) ]
                    )

                _ ->
                    ( model, Cmd.none )

        GotJoinFailed reason ->
            ( { model | connection = Failed reason }, Cmd.none )

        GotWatchers count ->
            ( { model | watchers = count }, Cmd.none )

        Resized width height ->
            ( { model | viewport = ( width, height ) }, Cmd.none )

        GotPlaced placed ->
            if model.pending /= Just { cell = placed.cell, digit = placed.digit } then
                ( model, Cmd.none )

            else
                case placed.result of
                    "wrong" ->
                        shake { cell = placed.cell, digit = placed.digit } [] { model | pending = Nothing }

                    -- The new state removes the pending digit
                    "ok" ->
                        ( model, Cmd.none )

                    _ ->
                        ( { model | pending = Nothing }, Cmd.none )

        Select cell ->
            case model.connection of
                Joined me game ->
                    if canPlay me game then
                        ( { model
                            | selected =
                                if model.selected == Just cell then
                                    Nothing

                                else
                                    Just cell
                          }
                        , Cmd.none
                        )

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        Place digit ->
            place digit model

        KeyDown key ->
            case String.toInt key of
                Just digit ->
                    if digit >= 1 && digit <= 9 then
                        place digit model

                    else
                        ( model, Cmd.none )

                Nothing ->
                    case key of
                        "ArrowUp" ->
                            move -9 model

                        "ArrowDown" ->
                            move 9 model

                        "ArrowLeft" ->
                            move -1 model

                        "ArrowRight" ->
                            move 1 model

                        "Escape" ->
                            ( { model | selected = Nothing }, Cmd.none )

                        _ ->
                            ( model, Cmd.none )

        WrongDone count ->
            if count == model.wrongCount then
                ( { model | wrong = Nothing, conflicts = [] }, Cmd.none )

            else
                ( model, Cmd.none )

        Restart ->
            ( { model | selected = Nothing, pending = Nothing }, sudokuRestart () )

        StartNextGame ->
            ( model, sudokuNextGame () )

        CopyLink ->
            ( { model | copied = True }
            , Cmd.batch
                [ sudokuCopyText model.gameUrl
                , Process.sleep 1500 |> Task.perform (\_ -> CopiedTimeout)
                ]
            )

        CopiedTimeout ->
            ( { model | copied = False }, Cmd.none )

        SyncClock elapsedMs time ->
            let
                ms =
                    Time.posixToMillis time
            in
            beepCountdown { model | clockStart = ms - elapsedMs, now = ms }

        Tick time ->
            beepCountdown { model | now = Time.posixToMillis time }

        ToggleMuted ->
            ( { model | muted = not model.muted }, sudokuSaveMuted (not model.muted) )


{-| Puts the digit in the selected empty cell. Only one digit at a time
goes to the server.
-}
place : Int -> Model -> ( Model, Cmd Msg )
place digit model =
    case ( model.connection, model.selected ) of
        ( Joined me game, Just cell ) ->
            if canPlay me game && digitAt game cell == Nothing && model.pending == Nothing then
                case conflicts game cell digit of
                    [] ->
                        ( { model | pending = Just { cell = cell, digit = digit } }
                        , sudokuPlace { cell = cell, digit = digit }
                        )

                    others ->
                        shake { cell = cell, digit = digit } others model

            else
                ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


shake : Move -> List Int -> Model -> ( Model, Cmd Msg )
shake wrong others model =
    ( { model | wrong = Just wrong, conflicts = others, wrongCount = model.wrongCount + 1 }
    , Cmd.batch
        [ playSounds model [ "wrong" ]
        , Process.sleep 600 |> Task.perform (\_ -> WrongDone (model.wrongCount + 1))
        ]
    )


{-| Moves the selection with the arrow keys. With no selection, the first
key selects the center of the grid. The selection stops at the edges.
-}
move : Int -> Model -> ( Model, Cmd Msg )
move step model =
    case model.connection of
        Joined me game ->
            if canPlay me game then
                case model.selected of
                    Nothing ->
                        ( { model | selected = Just 40 }, Cmd.none )

                    Just cell ->
                        let
                            next =
                                cell + step

                            inside =
                                next >= 0 && next < 81 && (abs step == 9 || next // 9 == cell // 9)
                        in
                        if inside then
                            ( { model | selected = Just next }, Cmd.none )

                        else
                            ( model, Cmd.none )

            else
                ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


{-| A player can put digits while the grid is on the screen
-}
canPlay : Me -> Game -> Bool
canPlay me game =
    me /= Nothing && not game.waiting && not game.finished && not (Array.isEmpty game.cells)


digitAt : Game -> Int -> Maybe Int
digitAt game cell =
    Array.get cell game.cells
        |> Maybe.andThen identity
        |> Maybe.map .digit


rowOf : Int -> Int
rowOf cell =
    cell // 9


colOf : Int -> Int
colOf cell =
    modBy 9 cell


boxOf : Int -> Int
boxOf cell =
    (rowOf cell // 3) * 3 + colOf cell // 3


{-| True when the two cells are in the same row, column or box
-}
sameUnit : Int -> Int -> Bool
sameUnit a b =
    rowOf a == rowOf b || colOf a == colOf b || boxOf a == boxOf b


{-| The other cells in the row, the column and the box of the cell that
have the digit
-}
conflicts : Game -> Int -> Int -> List Int
conflicts game cell digit =
    List.filter
        (\other -> other /= cell && sameUnit cell other && digitAt game other == Just digit)
        (List.range 0 80)


{-| The cells that are still empty
-}
emptyCount : Game -> Int
emptyCount game =
    Array.foldl
        (\filled count ->
            if filled == Nothing then
                count + 1

            else
                count
        )
        0
        game.cells


{-| How many times the digit is on the grid
-}
digitCount : Game -> Int -> Int
digitCount game digit =
    Array.foldl
        (\filled count ->
            if Maybe.map .digit filled == Just digit then
                count + 1

            else
                count
        )
        0
        game.cells


{-| The seconds left in the countdown (3, 2, 1), 0 after it, and Nothing
when no puzzle runs. The step is right only after the clock is in sync.
-}
countdownStep : Model -> Maybe Int
countdownStep model =
    case model.connection of
        Joined _ game ->
            if game.waiting || game.finished then
                Nothing

            else
                Just (max 0 (ceiling (toFloat (model.clockStart - model.now) / 1000)))

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
        Cmd.batch (List.map sudokuPlaySound names)


{-| The sounds for the change from the old state to the new one: the start
of the game, a cell that I filled or that another player filled, and the end
of the game.
-}
stateSounds : Me -> Game -> Game -> List String
stateSounds me old new =
    let
        -- All players are ready, and the game starts
        startSound =
            if old.waiting && not new.waiting && List.length new.players > 1 then
                [ "start" ]

            else
                []

        filledSound =
            case new.last of
                Just last ->
                    if new.last == old.last || new.finished then
                        []

                    else if me == Just last.playerId then
                        [ "found" ]

                    else
                        [ "other_found" ]

                Nothing ->
                    []

        endSound =
            if new.finished && not old.finished then
                case winners new.players of
                    [ winner ] ->
                        if isMe me winner || List.length new.players == 1 then
                            [ "win" ]

                        else
                            [ "lose" ]

                    _ ->
                        [ "lose" ]

            else
                []
    in
    startSound ++ filledSound ++ endSound


isMe : Me -> Player -> Bool
isMe me player =
    me == Just player.id


winners : List Player -> List Player
winners players =
    let
        best =
            List.maximum (List.map .score players) |> Maybe.withDefault 0
    in
    List.filter (\p -> p.score == best) players


syncClock : Game -> Cmd Msg
syncClock game =
    Time.now |> Task.perform (SyncClock game.elapsedMs)



-- DECODERS


joinedDecoder : Decoder ( Me, Game )
joinedDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "player_id" (Decode.nullable Decode.string))
        (Decode.field "state" gameDecoder)


gameDecoder : Decoder Game
gameDecoder =
    Decode.map8 Game
        (Decode.field "cells" (Decode.array (Decode.nullable filledDecoder)))
        (Decode.field "last" (Decode.nullable lastDecoder))
        (Decode.field "difficulty" Decode.string)
        (Decode.field "waiting" Decode.bool)
        (Decode.field "finished" Decode.bool)
        (Decode.field "elapsed_ms" Decode.int)
        (Decode.field "players" (Decode.list playerDecoder))
        (Decode.field "players_needed" Decode.int)


filledDecoder : Decoder Filled
filledDecoder =
    Decode.map3 Filled
        (Decode.field "digit" Decode.int)
        (Decode.field "player_id" (Decode.nullable Decode.string))
        (Decode.field "color" (Decode.nullable Decode.string))


lastDecoder : Decoder Last
lastDecoder =
    Decode.map2 Last
        (Decode.field "player_id" Decode.string)
        (Decode.field "cell" Decode.int)


playerDecoder : Decoder Player
playerDecoder =
    Decode.map6 Player
        (Decode.field "id" Decode.string)
        (Decode.field "name" (Decode.nullable Decode.string))
        (Decode.field "color" Decode.string)
        (Decode.field "color_name" Decode.string)
        (Decode.field "score" Decode.int)
        (Decode.field "away" Decode.bool)



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ sudokuJoined GotJoined
        , sudokuState GotState
        , sudokuJoinFailed GotJoinFailed
        , sudokuWatchers GotWatchers
        , sudokuPlaced GotPlaced
        , Browser.Events.onKeyDown (Decode.map KeyDown (Decode.field "key" Decode.string))
        , Browser.Events.onResize (\w h -> Resized (toFloat w) (toFloat h))
        , case model.connection of
            Joined _ game ->
                -- The grid comes only after the countdown, so an empty grid
                -- means a countdown. It ticks on each frame, so that the
                -- beeps are on time.
                if not game.waiting && not game.finished && Array.isEmpty game.cells then
                    Browser.Events.onAnimationFrame Tick

                else if not game.waiting && not game.finished then
                    Time.every 200 Tick

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
            p [ id "sudoku-connecting", class "py-24 text-center opacity-60" ] [ text "Joining the game…" ]

        Failed reason ->
            p [ id "sudoku-failed", class "py-24 text-center text-red-600 dark:text-red-400" ] [ text ("Could not join the game: " ++ reason) ]

        Joined me game ->
            viewGame model me game


viewGame : Model -> Me -> Game -> Html Msg
viewGame model me game =
    let
        countdown =
            Maybe.withDefault 0 (countdownStep model)
    in
    div
        [ id "sudoku-root"
        , class "flex w-full max-w-[1100px] flex-col gap-2 select-none max-lg:landscape:flex-row max-lg:landscape:items-start max-lg:landscape:gap-3 lg:flex-row lg:items-start lg:gap-8"
        , classList [ ( "is-playing", not game.waiting && not game.finished ) ]
        ]
        [ aside [ id "sudoku-panel", class "flex flex-col gap-2 max-lg:landscape:w-48 max-lg:landscape:shrink-0 max-lg:landscape:gap-4 lg:sticky lg:top-6 lg:w-72 lg:shrink-0 lg:gap-5" ]
            -- On a small screen, the title, the stats and the restart button
            -- are in one compact row. On a small screen that is wider than
            -- tall, they are in a narrow column at the left of the board, so
            -- the board can be as tall as the screen. On a large screen, the
            -- row is not a box (`contents`), so its items are in the column
            -- of the panel.
            [ div [ class "flex items-center gap-1 max-lg:landscape:flex-col max-lg:landscape:items-start max-lg:landscape:gap-4 lg:contents" ]
                [ div [ class "min-w-0 lg:order-1" ]
                    [ div [ class "flex items-center gap-1 lg:gap-2" ]
                        [ a
                            [ id "sudoku-home"
                            , href "/"
                            , class "mr-1 shrink-0 transition hover:-translate-y-0.5 active:translate-y-0 lg:mr-0"
                            ]
                            [ img [ src "/images/mark.svg", alt "octomocto", class "h-8 w-auto dark:hidden lg:h-9" ] []
                            , img [ src "/images/mark-on-dark.svg", alt "octomocto", class "hidden h-8 w-auto dark:block lg:h-9" ] []
                            ]
                        , h1 [ class "truncate text-xl font-semibold tracking-tight lg:text-2xl" ]
                            [ a [ id "sudoku-title-link", href "/sudoku", class "transition hover:text-octo-indigo dark:hover:text-octo-indigo-light" ] [ text "Sudoku Race" ] ]
                        , viewMuteButton model.muted
                        , viewWatchers model.watchers
                        ]
                    , p [ class "hidden text-sm opacity-60 lg:block" ]
                        [ text (String.toUpper (String.left 1 game.difficulty) ++ String.dropLeft 1 game.difficulty ++ ". Each row, column and box has each digit one time.") ]
                    ]
                , viewClock model game
                , if me == Nothing then
                    text ""

                  else
                    viewRestartButton
                ]
            , if game.playersNeeded > 1 then
                viewShareLink model

              else
                text ""
            , if List.length game.players > 1 then
                viewScores me game

              else
                text ""
            , if me == Nothing then
                p [ id "sudoku-watching", class "rounded-2xl bg-amber-50 px-4 py-3 text-sm text-amber-900 ring-1 ring-amber-200 lg:order-5 dark:bg-amber-400/10 dark:text-amber-200 dark:ring-amber-400/25" ]
                    [ text "This game is full, so you can only watch it." ]

              else
                text ""
            ]

        -- On a small screen that is wider than tall, the pad is at the right
        -- of the grid. On other screens, it is below the grid.
        , div [ class "mx-auto flex w-full min-w-0 flex-1 flex-col items-center gap-2 max-lg:landscape:flex-row max-lg:landscape:items-start max-lg:landscape:justify-center max-lg:landscape:gap-3 lg:gap-4" ]
            [ div [ class "relative w-full min-w-0", style "max-width" (boardWidth model me game) ]
                [ viewBoard model me game
                , if game.waiting then
                    viewWaiting game

                  else if game.finished then
                    viewResult model.settingsUrl model.nextGame model.guest me game

                  else if countdown > 0 || Array.isEmpty game.cells then
                    viewCountdown countdown

                  else
                    text ""
                ]
            , if canPlay me game then
                viewPad model me game

              else
                text ""
            ]
        ]


{-| The width of the screen from which the panel is at the left of the
board. On a smaller screen, the panel is a compact row above the board.
-}
largeScreen : Float
largeScreen =
    1024


{-| A small screen that is wider than tall. The panel is a narrow column at
the left of the grid and the pad is at the right of the grid, as the
`max-lg:landscape:` classes make it.
-}
sideways : Model -> Bool
sideways model =
    let
        ( width, height ) =
            model.viewport
    in
    width < largeScreen && width > height


{-| The height in pixels of the screen that is not for the grid. On a large
screen, it is the 1.5rem padding of the page at the top and at the bottom,
and the pad (4rem) with the 1rem gap above it. On a small screen, it is the
0.5rem padding of the page at the top and at the bottom, the rows of the
panel (the compact row, the link and the scores for a game with more
players, and maybe the message for a watcher), the pad and the 0.5rem gaps
between them. The heights of the rows are approximate, because the scores
can wrap. On a small screen that is wider than tall, the panel and the pad
are at the sides of the grid, so only the padding is not for the grid.

The pad shows only during a puzzle, but there is always space for it, so
that the grid does not change its size when the puzzle starts. A watcher
has no pad.

-}
reservedHeight : Model -> Me -> Game -> Float
reservedHeight model me game =
    let
        pad gap =
            if me == Nothing then
                0

            else
                64 + gap
    in
    if Tuple.first model.viewport >= largeScreen then
        48 + pad 16

    else if sideways model then
        16

    else
        16
            + 48
            + (if game.playersNeeded > 1 then
                46

               else
                0
              )
            + (if List.length game.players > 1 then
                36

               else
                0
              )
            + (if me == Nothing then
                52

               else
                0
              )
            + pad 8


{-| Make the grid as wide as possible, but small enough that the grid and
the pad are all on the screen. The grid is square.
-}
boardWidth : Model -> Me -> Game -> String
boardWidth model me game =
    "min(100%, 36rem, calc(100dvh - "
        ++ String.fromFloat (reservedHeight model me game)
        ++ "px))"


{-| The number of browsers that only watch the game, when there are any.
-}
viewWatchers : Int -> Html Msg
viewWatchers count =
    if count > 0 then
        span
            [ id "sudoku-watchers"
            , class "flex shrink-0 items-center gap-1 text-sm tabular-nums text-slate-500 dark:text-slate-400"
            , Html.Attributes.title ("Watchers: " ++ String.fromInt count)
            ]
            [ span [ class "hero-eye size-4" ] [], text (String.fromInt count) ]

    else
        text ""


viewMuteButton : Bool -> Html Msg
viewMuteButton muted =
    button
        [ id "sudoku-mute"
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


{-| Starts a new puzzle for all players, also during a game.
-}
viewRestartButton : Html Msg
viewRestartButton =
    button
        [ id "sudoku-restart"
        , class "group flex size-9 shrink-0 items-center justify-center gap-2 rounded-full text-sm font-medium text-slate-600 ring-1 ring-slate-200 transition hover:bg-slate-50 hover:text-slate-900 hover:ring-slate-300 active:scale-95 max-lg:landscape:size-auto max-lg:landscape:px-4 max-lg:landscape:py-2 lg:order-5 lg:size-auto lg:self-start lg:px-4 lg:py-2 dark:text-slate-300 dark:ring-white/20 dark:hover:bg-white/10 dark:hover:text-white dark:hover:ring-white/30"
        , onClick Restart
        , Html.Attributes.title "Restart game"
        ]
        [ span [ class "hero-arrow-path size-4 transition-transform duration-300 group-hover:-rotate-180" ] []
        , span [ class "hidden max-lg:landscape:inline lg:inline" ] [ text "Restart game" ]
        ]


viewShareLink : Model -> Html Msg
viewShareLink model =
    div [ class "flex items-center gap-2 rounded-full bg-octo-mist p-1 pl-4 text-sm ring-1 ring-octo-indigo/20 max-lg:landscape:flex-col max-lg:landscape:items-stretch max-lg:landscape:rounded-2xl max-lg:landscape:p-2 lg:order-3 lg:flex-col lg:items-stretch lg:rounded-2xl lg:p-2 lg:pl-2 dark:bg-octo-indigo/15 dark:ring-octo-indigo-light/25" ]
        [ input
            [ id "sudoku-link"
            , readonly True
            , value model.gameUrl
            , class "min-w-0 flex-1 truncate bg-transparent text-octo-navy outline-none max-lg:landscape:px-2 max-lg:landscape:py-1 lg:px-2 lg:py-1 dark:text-slate-100"
            ]
            []
        , button
            [ id "sudoku-copy-link"
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


{-| The time on the left, and the empty cells on the right. Before the
start, the grid is not known, so the right side shows a dash.
-}
viewClock : Model -> Game -> Html Msg
viewClock model game =
    let
        elapsedMs =
            if game.finished then
                game.elapsedMs

            else if game.waiting then
                0

            else
                max 0 (model.now - model.clockStart)
    in
    div [ id "sudoku-clock", class "ml-auto flex gap-4 pr-2 max-lg:landscape:ml-0 max-lg:landscape:gap-6 max-lg:landscape:pr-0 max-lg:landscape:pl-2 lg:order-2 lg:ml-0 lg:grid lg:grid-cols-2 lg:gap-0 lg:divide-x lg:divide-slate-200 lg:rounded-2xl lg:bg-white lg:py-3 lg:pr-0 lg:shadow-sm lg:ring-1 lg:ring-slate-200 dark:lg:divide-white/10 dark:lg:bg-white/5 dark:lg:shadow-none dark:lg:ring-white/10" ]
        [ div [ class "flex flex-col items-center justify-center max-lg:landscape:items-start" ]
            [ span [ class "text-[0.625rem] font-medium tracking-wide text-slate-400 uppercase lg:text-xs" ] [ text "time" ]
            , span [ id "sudoku-time", class "text-lg leading-tight font-light text-slate-700 tabular-nums lg:text-3xl dark:text-slate-100" ] [ text (formatTime elapsedMs) ]
            ]
        , div [ class "flex flex-col items-center justify-center max-lg:landscape:items-start" ]
            [ span [ class "text-[0.625rem] font-medium tracking-wide text-slate-400 uppercase lg:text-xs" ] [ text "empty" ]
            , span [ id "sudoku-empty-left", class "text-xl leading-tight font-bold text-octo-indigo tabular-nums lg:text-3xl dark:text-octo-indigo-light" ]
                [ text
                    (if Array.isEmpty game.cells then
                        "–"

                     else
                        String.fromInt (emptyCount game)
                    )
                ]
            ]
        ]


{-| Show the time as minutes and seconds, for example "1:05".
-}
formatTime : Int -> String
formatTime ms =
    let
        seconds =
            ms // 1000
    in
    String.fromInt (seconds // 60) ++ ":" ++ String.padLeft 2 '0' (String.fromInt (modBy 60 seconds))


{-| The players in the order in which they joined, with the cells they
filled
-}
viewScores : Me -> Game -> Html Msg
viewScores me game =
    ul [ id "sudoku-scores", class "flex flex-wrap gap-2 max-lg:landscape:flex-col lg:order-4 lg:flex-col" ]
        (List.map
            (\player ->
                li
                    [ id ("sudoku-score-" ++ player.id)
                    , class "flex items-center gap-2 rounded-full bg-white px-3 py-1 text-sm text-slate-800 shadow-sm ring-1 ring-slate-200 transition dark:bg-white/5 dark:text-slate-100 dark:shadow-none dark:ring-white/10"
                    , classList [ ( "opacity-50", player.away ) ]
                    ]
                    [ span [ class "size-3 rounded-full", style "background" player.color ] []
                    , span [ class "max-lg:landscape:flex-1 lg:flex-1" ] [ text (playerName me player) ]
                    , span [ class "font-semibold tabular-nums" ] [ text (String.fromInt player.score) ]
                    ]
            )
            game.players
        )


playerName : Me -> Player -> String
playerName me player =
    if isMe me player then
        Maybe.withDefault player.colorName player.name ++ " (you)"

    else
        Maybe.withDefault player.colorName player.name



-- BOARD


{-| The grid as 9 boxes of 9 cells. The gaps between the cells are the
lines of the grid (see app.css). Before the start, the cells are empty.
-}
viewBoard : Model -> Me -> Game -> Html Msg
viewBoard model me game =
    let
        playable =
            canPlay me game

        selectedDigit =
            model.selected |> Maybe.andThen (digitAt game)

        viewCell cell =
            viewBoardCell model game playable selectedDigit cell
    in
    div [ id "sudoku-board", class "sudoku-board grid grid-cols-3 shadow-sm" ]
        (List.map
            (\box ->
                div [ class "sudoku-box grid grid-cols-3" ]
                    (List.map
                        (\inner ->
                            viewCell (((box // 3) * 3 + inner // 3) * 9 + modBy 3 box * 3 + modBy 3 inner)
                        )
                        (List.range 0 8)
                    )
            )
            (List.range 0 8)
        )


viewBoardCell : Model -> Game -> Bool -> Maybe Int -> Int -> Html Msg
viewBoardCell model game playable selectedDigit cell =
    let
        filled =
            Array.get cell game.cells |> Maybe.andThen identity

        wrong =
            model.wrong
                |> Maybe.andThen
                    (\w ->
                        if w.cell == cell then
                            Just w.digit

                        else
                            Nothing
                    )

        pending =
            model.pending
                |> Maybe.andThen
                    (\p ->
                        if p.cell == cell then
                            Just p.digit

                        else
                            Nothing
                    )

        isLast =
            Maybe.map .cell game.last == Just cell

        digitView =
            case ( filled, wrong, pending ) of
                ( Just f, _, _ ) ->
                    -- Keyed by the digit, so that a new digit pops in
                    Html.Keyed.node "span"
                        []
                        [ ( String.fromInt f.digit
                          , span
                                [ classList
                                    [ ( "font-semibold text-slate-800 dark:text-slate-100", f.color == Nothing )
                                    , ( "font-bold", f.color /= Nothing )
                                    , ( "sudoku-pop inline-block", f.color /= Nothing )
                                    ]
                                , style "color" (Maybe.withDefault "" f.color)
                                ]
                                [ text (String.fromInt f.digit) ]
                          )
                        ]

                ( Nothing, Just digit, _ ) ->
                    -- Keyed by the shake, so that each wrong digit shakes
                    Html.Keyed.node "span"
                        []
                        [ ( String.fromInt model.wrongCount
                          , span [ class "sudoku-digit inline-block font-bold" ] [ text (String.fromInt digit) ]
                          )
                        ]

                ( Nothing, Nothing, Just digit ) ->
                    span [ class "sudoku-digit font-bold text-slate-300 dark:text-slate-500" ] [ text (String.fromInt digit) ]

                _ ->
                    text ""
    in
    button
        [ id ("sudoku-cell-" ++ String.fromInt cell)
        , class "sudoku-cell"
        , classList
            [ ( "is-playable", playable )
            , ( "is-selected", model.selected == Just cell )
            , ( "is-same", selectedDigit /= Nothing && Maybe.map .digit filled == selectedDigit && model.selected /= Just cell )
            , ( "is-peer"
              , case model.selected of
                    Just selected ->
                        selected /= cell && sameUnit selected cell

                    Nothing ->
                        False
              )
            , ( "is-wrong", wrong /= Nothing )
            , ( "is-conflict", List.member cell model.conflicts )
            , ( "ring-2 ring-inset ring-octo-indigo/40 dark:ring-octo-indigo-light/50", isLast && not game.finished && model.selected /= Just cell )
            ]
        , onClick (Select cell)
        , Html.Attributes.attribute "aria-label" (cellName cell filled)
        ]
        [ digitView ]


{-| For example, "Row 3, column 5, 7" or "Row 3, column 5, empty"
-}
cellName : Int -> Maybe Filled -> String
cellName cell filled =
    "Row "
        ++ String.fromInt (rowOf cell + 1)
        ++ ", column "
        ++ String.fromInt (colOf cell + 1)
        ++ ", "
        ++ (case filled of
                Just f ->
                    String.fromInt f.digit

                Nothing ->
                    "empty"
           )


{-| The digits 1 to 9, each with the number of times that it must still go
on the grid. A digit that is on the grid 9 times is off. Below the grid, the
digits are in one row as wide as the grid. At the right of the grid, they
are in 3 rows.
-}
viewPad : Model -> Me -> Game -> Html Msg
viewPad model me game =
    let
        ready =
            case model.selected of
                Just cell ->
                    digitAt game cell == Nothing && model.pending == Nothing

                Nothing ->
                    False
    in
    div [ id "sudoku-pad", class "grid w-full grid-cols-9 gap-1.5 max-lg:landscape:w-40 max-lg:landscape:shrink-0 max-lg:landscape:grid-cols-3 sm:gap-2", style "max-width" (boardWidth model me game) ]
        (List.map
            (\digit ->
                let
                    left =
                        9 - digitCount game digit
                in
                button
                    [ id ("sudoku-key-" ++ String.fromInt digit)
                    , class "sudoku-pad-key flex flex-col items-center justify-center rounded-xl bg-white py-2 shadow-sm ring-1 ring-slate-200 dark:bg-white/5 dark:shadow-none dark:ring-white/10"
                    , classList
                        [ ( "enabled:hover:-translate-y-0.5 enabled:hover:bg-octo-mist enabled:hover:ring-octo-indigo/40 enabled:active:scale-95 dark:enabled:hover:bg-octo-indigo/20 dark:enabled:hover:ring-octo-indigo-light/40", ready )
                        , ( "opacity-30", left == 0 )
                        ]
                    , Html.Attributes.disabled (left == 0)
                    , onClick (Place digit)
                    ]
                    [ span [ class "text-xl font-semibold text-slate-800 sm:text-2xl dark:text-slate-100" ] [ text (String.fromInt digit) ]
                    , span [ class "text-[10px] text-slate-400 tabular-nums sm:text-xs" ] [ text (String.fromInt left) ]
                    ]
            )
            (List.range 1 9)
        )



-- COVERS


{-| Covers the grid until all players are in.
-}
viewWaiting : Game -> Html Msg
viewWaiting game =
    div
        [ id "sudoku-waiting"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-3 rounded-xl bg-octo-navy/80 p-4 text-center text-white"
        ]
        [ p [ class "text-3xl font-semibold" ] [ text "Waiting for players" ]
        , p [ id "sudoku-waiting-count", class "text-lg tabular-nums opacity-80" ]
            [ text
                (String.fromInt (List.length game.players)
                    ++ " of "
                    ++ String.fromInt game.playersNeeded
                    ++ " players are in"
                )
            ]
        , p [ class "text-sm opacity-60" ] [ text "Send the link to the other players. The game starts when all of them are in." ]
        ]


{-| The number is keyed, so that it pops in again on each step.
-}
viewCountdown : Int -> Html Msg
viewCountdown seconds =
    div
        [ id "sudoku-countdown"
        , class "absolute inset-0 flex items-center justify-center rounded-xl bg-octo-navy/80"
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


viewResult : String -> NextGame -> Bool -> Me -> Game -> Html Msg
viewResult settingsUrl nextGame guest me game =
    let
        players =
            game.players

        solo =
            List.length players == 1

        message =
            case ( solo, winners players ) of
                ( True, _ ) ->
                    "Solved!"

                ( False, [ winner ] ) ->
                    if isMe me winner then
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
    in
    div
        [ id "sudoku-result"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-4 rounded-xl bg-octo-navy/70 p-4 text-white backdrop-blur-sm"
        ]
        [ p [ class "text-3xl font-semibold" ] [ text message ]
        , p [ id "sudoku-final-time", class "text-lg tabular-nums opacity-80" ]
            [ text ("Time " ++ formatTime game.elapsedMs) ]
        , if solo then
            text ""

          else
            ol [ class "flex flex-col gap-1 text-sm" ]
                (List.map
                    (\player ->
                        li [ class "flex items-center gap-2" ]
                            [ span [ class "size-3 rounded-full", style "background" player.color ] []
                            , span [ class "flex-1" ] [ text (playerName me player) ]
                            , span [ class "pl-6 font-semibold tabular-nums" ] [ text (String.fromInt player.score) ]
                            ]
                    )
                    ranked
                )
        , if me == Nothing then
            text ""

          else
            button
                [ id "sudoku-play-again"
                , class "rounded-full bg-white px-6 py-2.5 font-medium text-octo-indigo shadow-lg transition hover:-translate-y-0.5 hover:bg-octo-mist active:translate-y-0"
                , onClick Restart
                ]
                [ text "Play again" ]
        , a
            [ id "sudoku-leaderboards-link"
            , href settingsUrl
            , class "text-sm font-medium text-white/80 underline-offset-4 transition hover:text-white hover:underline"
            ]
            [ text "Best results" ]
        , let
            -- In a game with other players, a player starts the next game for all of them
            ( element, action ) =
                if me /= Nothing && List.length game.players > 1 then
                    ( button, onClick StartNextGame )

                else
                    ( a, href nextGame.path )
          in
          element
            [ id "sudoku-next-game"
            , action
            , attribute "data-ga-link" "or_try"
            , attribute "data-ga-from" "Sudoku Race"
            , attribute "data-ga-to" nextGame.name
            , class "group text-sm font-medium text-white underline-offset-4 transition hover:underline"
            ]
            [ text ("Or try " ++ nextGame.name ++ " ")
            , span [ class "inline-block transition group-hover:translate-x-0.5" ] [ text "→" ]
            ]

        -- Only a guest who played gets the call to sign in, not a spectator
        , if guest && me /= Nothing then
            p [ id "sudoku-sign-in", class "text-sm text-white/70" ]
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
    p [ id "sudoku-feed", class "mt-2 max-w-sm border-t border-white/15 pt-4 text-center text-sm leading-10 text-balance text-white/80" ]
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
