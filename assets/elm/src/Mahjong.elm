port module Mahjong exposing (main)

{-| Mahjong solitaire on the Turtle layout: remove the 144 tiles two at a
time. Two tiles make a pair when they have the same face (any flower
matches any flower, and any season matches any season). A tile is free
when no tile lies on it, and its left or its right side is open.

The server owns the game: the tiles, the scores and the clock. This module
draws the state that comes in through ports, and sends the pairs of the
player out. app.js connects the ports to a Phoenix channel.

The player clicks a free tile to select it, then a free tile with the same
face. The pair goes to the server, which checks it again: another player
can take one of the tiles first. A click on a tile that is not free shakes
it. A click on a free tile with another face selects that tile instead.

The Hint button shows a free pair for a short time. Each click shows the
next free pair. Hints are free, also with other players.

All players race on the same board. Before all of them are in, the tiles
show no faces. A countdown with beeps comes before each board. When no pair
is free, any player can shuffle the faces of the tiles that are left. A
browser that joins a full game only watches: it has no player id.

The module compares each new state with the old one and sends the names of
the sounds to play out through a port. The player can mute the sounds.

-}

import Browser
import Browser.Dom
import Browser.Events
import Dict exposing (Dict)
import Html exposing (Html, a, aside, button, div, h1, img, input, li, ol, p, span, text, ul)
import Html.Attributes exposing (alt, attribute, class, classList, href, id, readonly, src, style, value)
import Html.Events exposing (onClick)
import Html.Keyed
import Json.Decode as Decode exposing (Decoder)
import Process
import Svg exposing (Svg)
import Svg.Attributes as SA
import Svg.Events
import Svg.Keyed
import Task
import Time



-- PORTS


port mahjongRemove : { a : Int, b : Int } -> Cmd msg


port mahjongShuffle : () -> Cmd msg


port mahjongRestart : () -> Cmd msg


{-| Starts the next game for all players, see OctomoctoWeb.NextGame
-}
port mahjongNextGame : () -> Cmd msg


port mahjongCopyText : String -> Cmd msg


port mahjongJoined : (Decode.Value -> msg) -> Sub msg


port mahjongState : (Decode.Value -> msg) -> Sub msg


port mahjongJoinFailed : (String -> msg) -> Sub msg


{-| The number of browsers that only watch the game, after the join and
after each change.
-}
port mahjongWatchers : (Int -> msg) -> Sub msg


{-| The reply of the server to a pair: "ok" or "ignored"
-}
port mahjongRemoved : ({ a : Int, b : Int, result : String } -> msg) -> Sub msg


port mahjongPlaySound : String -> Cmd msg


port mahjongSaveMuted : Bool -> Cmd msg



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


{-| A tile on the board. The `col` and the `row` are in half tiles, and the
layer 0 is the bottom. The face is Nothing before the start.
-}
type alias Tile =
    { id : Int
    , face : Maybe String
    , layer : Int
    , col : Int
    , row : Int
    }


{-| The last pair that a player removed
-}
type alias Last =
    { playerId : String
    , color : String
    , tiles : List Tile
    }


type alias Game =
    { tiles : List Tile
    , last : Maybe Last

    -- Goes up by one with each shuffle
    , shuffles : Int

    -- True when no pair is free
    , stuck : Bool

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

    -- The selected tile
    , selected : Maybe Int

    -- The pair that went to the server, until it is off the board or the
    -- server ignores it
    , pending : Maybe ( Int, Int )

    -- The tile that is not free, while it shakes. The number tells the
    -- shakes apart, so that the end of an old shake does not stop a new one.
    , blocked : Maybe Int
    , blockedCount : Int

    -- The free pair from the Hint button, while it shows. The number goes
    -- up with each hint: it picks the next pair, and tells the hints apart,
    -- so that the end of an old hint does not stop a new one.
    , hint : Maybe ( Int, Int )
    , hintCount : Int

    -- The local time (in ms) when the board started, and the local time
    -- now. The clock ticks between the server updates.
    , clockStart : Int
    , now : Int

    -- During a shuffle, the places (x and y) of the tiles before it, by id.
    -- The tiles slide from there to their new places.
    , shuffling : Maybe (Dict Int ( Int, Int ))

    -- True for a moment after the countdown, while the faces flip in. The
    -- flip is only on the tiles then: the page moves the nodes of the
    -- tiles after a shuffle, and a moved node plays its animation again.
    , revealing : Bool

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
      , selected = Nothing
      , pending = Nothing
      , blocked = Nothing
      , blockedCount = 0
      , hint = Nothing
      , hintCount = 0
      , clockStart = 0
      , now = 0
      , shuffling = Nothing
      , revealing = False
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
    | GotRemoved { a : Int, b : Int, result : String }
    | ClickTile Int
    | KeyDown String
    | BlockedDone Int
    | Hint
    | HintDone Int
    | Shuffle
    | Restart
    | StartNextGame
    | CopyLink
    | CopiedTimeout
    | ShuffleDone Int
    | RevealDone
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
                    ( { model | connection = Joined me game, selected = Nothing, pending = Nothing, hint = Nothing }, syncClock game )

                Err err ->
                    ( { model | connection = Failed (Decode.errorToString err) }, Cmd.none )

        GotState value ->
            case ( model.connection, Decode.decodeValue gameDecoder value ) of
                ( Joined me old, Ok game ) ->
                    let
                        onBoard tileId =
                            List.any (\tile -> tile.id == tileId) game.tiles

                        shuffled =
                            game.shuffles > old.shuffles

                        revealed =
                            hasFaces game && not (hasFaces old)

                        -- A shuffle moves the tiles, so the selection has no
                        -- meaning after it
                        keep tileId =
                            not shuffled && hasFaces game && onBoard tileId
                    in
                    ( { model
                        | connection = Joined me game
                        , selected = model.selected |> Maybe.andThen (keepIf keep)
                        , pending = model.pending |> Maybe.andThen (keepIf (\( a, b ) -> onBoard a && onBoard b))
                        , hint = model.hint |> Maybe.andThen (keepIf (\( a, b ) -> keep a && keep b))
                        , shuffling =
                            if shuffled then
                                Just (Dict.fromList (List.map (\tile -> ( tile.id, ( tileX tile, tileY tile ) )) old.tiles))

                            else
                                model.shuffling
                        , revealing = model.revealing || revealed
                      }
                    , Cmd.batch
                        [ syncClock game
                        , playSounds model (stateSounds me old game)
                        , if shuffled then
                            Process.sleep shuffleMs |> Task.perform (\_ -> ShuffleDone game.shuffles)

                          else
                            Cmd.none
                        , if revealed then
                            Process.sleep 400 |> Task.perform (\_ -> RevealDone)

                          else
                            Cmd.none
                        ]
                    )

                _ ->
                    ( model, Cmd.none )

        GotJoinFailed reason ->
            ( { model | connection = Failed reason }, Cmd.none )

        GotWatchers count ->
            ( { model | watchers = count }, Cmd.none )

        GotRemoved removed ->
            if model.pending /= Just ( removed.a, removed.b ) then
                ( model, Cmd.none )

            else if removed.result == "ok" then
                -- The new state removes the pending pair
                ( model, Cmd.none )

            else
                -- Another player took one of the tiles first
                ( { model | pending = Nothing, selected = Nothing }, Cmd.none )

        ClickTile tileId ->
            clickTile tileId model

        KeyDown key ->
            if key == "Escape" then
                ( { model | selected = Nothing }, Cmd.none )

            else
                ( model, Cmd.none )

        BlockedDone count ->
            if count == model.blockedCount then
                ( { model | blocked = Nothing }, Cmd.none )

            else
                ( model, Cmd.none )

        Hint ->
            case model.connection of
                Joined _ game ->
                    let
                        pairs =
                            freePairs game.tiles
                    in
                    ( { model
                        | hint = List.head (List.drop (modBy (max 1 (List.length pairs)) model.hintCount) pairs)
                        , hintCount = model.hintCount + 1
                      }
                    , Process.sleep hintMs |> Task.perform (\_ -> HintDone (model.hintCount + 1))
                    )

                _ ->
                    ( model, Cmd.none )

        HintDone count ->
            if count == model.hintCount then
                ( { model | hint = Nothing }, Cmd.none )

            else
                ( model, Cmd.none )

        Shuffle ->
            ( { model | selected = Nothing }, mahjongShuffle () )

        Restart ->
            ( { model | selected = Nothing, pending = Nothing, hint = Nothing }, mahjongRestart () )

        StartNextGame ->
            ( model, mahjongNextGame () )

        CopyLink ->
            ( { model | copied = True }
            , Cmd.batch
                [ mahjongCopyText model.gameUrl
                , Process.sleep 1500 |> Task.perform (\_ -> CopiedTimeout)
                ]
            )

        CopiedTimeout ->
            ( { model | copied = False }, Cmd.none )

        RevealDone ->
            ( { model | revealing = False }, Cmd.none )

        ShuffleDone shuffles ->
            case model.connection of
                Joined _ game ->
                    if game.shuffles == shuffles then
                        ( { model | shuffling = Nothing }, Cmd.none )

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        SyncClock elapsedMs time ->
            let
                ms =
                    Time.posixToMillis time
            in
            beepCountdown { model | clockStart = ms - elapsedMs, now = ms }

        Tick time ->
            beepCountdown { model | now = Time.posixToMillis time }

        ToggleMuted ->
            ( { model | muted = not model.muted }, mahjongSaveMuted (not model.muted) )

        Resized width height ->
            ( { model | viewport = ( width, height ) }, Cmd.none )


keepIf : (a -> Bool) -> a -> Maybe a
keepIf keep item =
    if keep item then
        Just item

    else
        Nothing


{-| Selects a free tile, or sends a pair to the server. Only one pair at a
time goes to the server.
-}
clickTile : Int -> Model -> ( Model, Cmd Msg )
clickTile tileId model =
    case model.connection of
        Joined me game ->
            case ( canPlay me game && model.pending == Nothing, findTile game tileId ) of
                ( True, Just tile ) ->
                    if not (isFree game.tiles tile) then
                        ( { model | blocked = Just tileId, blockedCount = model.blockedCount + 1 }
                        , Cmd.batch
                            [ playSounds model [ "blocked" ]
                            , Process.sleep 400 |> Task.perform (\_ -> BlockedDone (model.blockedCount + 1))
                            ]
                        )

                    else
                        case model.selected |> Maybe.andThen (findTile game) of
                            Just selected ->
                                if selected.id == tileId then
                                    ( { model | selected = Nothing }, Cmd.none )

                                else if pair selected tile then
                                    ( { model | pending = Just ( selected.id, tileId ) }
                                    , mahjongRemove { a = selected.id, b = tileId }
                                    )

                                else
                                    ( { model | selected = Just tileId }, playSounds model [ "select" ] )

                            Nothing ->
                                ( { model | selected = Just tileId }, playSounds model [ "select" ] )

                _ ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


{-| A player can remove pairs while the faces are on the board
-}
canPlay : Me -> Game -> Bool
canPlay me game =
    me /= Nothing && not game.waiting && not game.finished && hasFaces game


hasFaces : Game -> Bool
hasFaces game =
    List.any (\tile -> tile.face /= Nothing) game.tiles


findTile : Game -> Int -> Maybe Tile
findTile game tileId =
    List.filter (\tile -> tile.id == tileId) game.tiles |> List.head


{-| True when no tile lies on the tile, and its left or its right side
touches no tile of the same layer
-}
isFree : List Tile -> Tile -> Bool
isFree tiles tile =
    let
        covered =
            List.any (\o -> o.layer == tile.layer + 1 && abs (o.col - tile.col) < 2 && abs (o.row - tile.row) < 2) tiles

        side dc =
            List.any (\o -> o.layer == tile.layer && o.col == tile.col + dc && abs (o.row - tile.row) < 2) tiles
    in
    not covered && not (side -2 && side 2)


{-| The pairs of free tiles with the same face, by tile ids
-}
freePairs : List Tile -> List ( Int, Int )
freePairs tiles =
    let
        free =
            List.filter (isFree tiles) tiles

        pairsOf rest =
            case rest of
                tile :: others ->
                    List.filterMap
                        (\other ->
                            if pair tile other then
                                Just ( tile.id, other.id )

                            else
                                Nothing
                        )
                        others
                        ++ pairsOf others

                [] ->
                    []
    in
    pairsOf free


{-| How long a hint shows
-}
hintMs : Float
hintMs =
    3000


pair : Tile -> Tile -> Bool
pair a b =
    a.face /= Nothing && Maybe.map matchKey a.face == Maybe.map matchKey b.face


matchKey : String -> String
matchKey face =
    if String.startsWith "flower-" face then
        "flower"

    else if String.startsWith "season-" face then
        "season"

    else
        face


{-| The seconds left in the countdown (3, 2, 1), 0 after it, and Nothing
when no board runs. The step is right only after the clock is in sync.
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
        Cmd.batch (List.map mahjongPlaySound names)


{-| The sounds for the change from the old state to the new one: a pair
that I removed or that another player removed, a shuffle, and the end of
the game.
-}
stateSounds : Me -> Game -> Game -> List String
stateSounds me old new =
    let
        pairSound =
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

        shuffleSound =
            if new.shuffles > old.shuffles then
                [ "shuffle" ]

            else
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
    pairSound ++ shuffleSound ++ endSound


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


andMap : Decoder a -> Decoder (a -> b) -> Decoder b
andMap =
    Decode.map2 (|>)


joinedDecoder : Decoder ( Me, Game )
joinedDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "player_id" (Decode.nullable Decode.string))
        (Decode.field "state" gameDecoder)


gameDecoder : Decoder Game
gameDecoder =
    Decode.succeed Game
        |> andMap (Decode.field "tiles" (Decode.list tileDecoder))
        |> andMap (Decode.field "last" (Decode.nullable lastDecoder))
        |> andMap (Decode.field "shuffles" Decode.int)
        |> andMap (Decode.field "stuck" Decode.bool)
        |> andMap (Decode.field "waiting" Decode.bool)
        |> andMap (Decode.field "finished" Decode.bool)
        |> andMap (Decode.field "elapsed_ms" Decode.int)
        |> andMap (Decode.field "players" (Decode.list playerDecoder))
        |> andMap (Decode.field "players_needed" Decode.int)


tileDecoder : Decoder Tile
tileDecoder =
    Decode.map5 Tile
        (Decode.field "id" Decode.int)
        (Decode.field "face" (Decode.nullable Decode.string))
        (Decode.field "layer" Decode.int)
        (Decode.field "col" Decode.int)
        (Decode.field "row" Decode.int)


lastDecoder : Decoder Last
lastDecoder =
    Decode.map3 Last
        (Decode.field "player_id" Decode.string)
        (Decode.field "color" Decode.string)
        (Decode.field "tiles" (Decode.list tileDecoder))


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
        [ mahjongJoined GotJoined
        , mahjongState GotState
        , mahjongJoinFailed GotJoinFailed
        , mahjongWatchers GotWatchers
        , mahjongRemoved GotRemoved
        , Browser.Events.onKeyDown (Decode.map KeyDown (Decode.field "key" Decode.string))
        , Browser.Events.onResize (\w h -> Resized (toFloat w) (toFloat h))
        , case model.connection of
            Joined _ game ->
                -- The faces come only after the countdown, so a board with
                -- no faces means a countdown. It ticks on each frame, so
                -- that the beeps are on time.
                if not game.waiting && not game.finished && not (hasFaces game) then
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
            p [ id "mahjong-connecting", class "py-24 text-center opacity-60" ] [ text "Joining the game…" ]

        Failed reason ->
            p [ id "mahjong-failed", class "py-24 text-center text-red-600 dark:text-red-400" ] [ text ("Could not join the game: " ++ reason) ]

        Joined me game ->
            viewGame model me game


viewGame : Model -> Me -> Game -> Html Msg
viewGame model me game =
    div
        [ id "mahjong-root"
        , class "flex w-full max-w-[1320px] flex-col gap-2 select-none max-lg:landscape:flex-row max-lg:landscape:items-start max-lg:landscape:gap-3 lg:flex-row lg:items-start lg:gap-8"
        , classList [ ( "is-playing", not game.waiting && not game.finished ) ]
        ]
        [ aside [ id "mahjong-panel", class "flex flex-col gap-2 max-lg:landscape:w-48 max-lg:landscape:shrink-0 max-lg:landscape:gap-4 lg:sticky lg:top-6 lg:w-64 lg:shrink-0 lg:gap-5" ]
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
                            [ id "mahjong-home"
                            , href "/"
                            , class "mr-1 shrink-0 transition hover:-translate-y-0.5 active:translate-y-0 lg:mr-0"
                            ]
                            [ img [ src "/images/mark.svg", alt "octomocto", class "h-8 w-auto dark:hidden lg:h-9" ] []
                            , img [ src "/images/mark-on-dark.svg", alt "octomocto", class "hidden h-8 w-auto dark:block lg:h-9" ] []
                            ]
                        , h1 [ class "truncate text-xl font-semibold tracking-tight lg:text-2xl" ]
                            [ a [ id "mahjong-title-link", href "/mahjong", class "transition hover:text-octo-indigo dark:hover:text-octo-indigo-light" ] [ text "Mahjong" ] ]
                        , viewMuteButton model.muted
                        , viewWatchers model.watchers
                        ]
                    , p [ class "hidden text-sm opacity-60 lg:block" ] [ text "Remove pairs of free tiles with the same face." ]
                    ]
                , viewClock model game
                , if canPlay me game then
                    viewHintButton game.stuck

                  else
                    text ""
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
                p [ id "mahjong-watching", class "rounded-2xl bg-amber-50 px-4 py-3 text-sm text-amber-900 ring-1 ring-amber-200 lg:order-5 dark:bg-amber-400/10 dark:text-amber-200 dark:ring-amber-400/25" ]
                    [ text "This game is full, so you can only watch it." ]

              else
                text ""
            ]
        , div [ class "min-w-0 flex-1" ]
            [ if upright model then
                viewTurnRequest model me game

              else
                viewBoardArea model me game
            ]
        ]


{-| The board, with the message of the game over it. The board is as large
as possible, but all of it is on the screen.
-}
viewBoardArea : Model -> Me -> Game -> Html Msg
viewBoardArea model me game =
    let
        countdown =
            Maybe.withDefault 0 (countdownStep model)
    in
    div [ class "relative mx-auto", style "width" (fieldWidth model me game) ]
        [ viewBoard model me game
        , if game.waiting then
            viewWaiting game

          else if game.finished then
            viewResult model.nextGame model.guest me game

          else if countdown > 0 || not (hasFaces game) then
            viewCountdown countdown

          else if game.stuck then
            viewStuck me

          else
            text ""
        ]


{-| On a phone that is taller than wide, the tiles are too small to click,
so the request to turn the screen is in the place of the board. It fills the
free height, so that the result of a game that ends shows over it.
-}
viewTurnRequest : Model -> Me -> Game -> Html Msg
viewTurnRequest model me game =
    div
        [ id "mahjong-turn"
        , class "relative flex flex-col items-center justify-center gap-3 rounded-2xl bg-octo-mist p-6 text-center ring-1 ring-octo-indigo/15 dark:bg-octo-indigo/15 dark:ring-octo-indigo-light/25"
        , style "height" ("calc(100dvh - " ++ String.fromFloat (reservedHeight model me game) ++ "px)")
        ]
        [ span [ class "turn-phone hero-device-phone-mobile size-14 text-octo-indigo dark:text-octo-indigo-light" ] []
        , p [ class "mt-2 text-xl font-semibold text-octo-navy dark:text-slate-100" ] [ text "Turn your screen" ]
        , p [ class "max-w-60 text-sm text-slate-500 dark:text-slate-400" ] [ text "The board needs a screen that is wider than tall." ]
        , if game.finished then
            viewResult model.nextGame model.guest me game

          else
            text ""
        ]


{-| The width of the screen from which the panel is at the left of the
board. On a smaller screen, the panel is a compact row above the board.
-}
largeScreen : Float
largeScreen =
    1024


{-| A small screen that is wider than tall. The panel is a narrow column at
the left of the board, as the `max-lg:landscape:` classes make it.
-}
sideways : Model -> Bool
sideways model =
    let
        ( width, height ) =
            model.viewport
    in
    width < largeScreen && width > height


{-| A phone that is taller than wide. The board is 15 tiles wide, so on a
screen that is narrower than 640px, the tiles are too small to click. The
player gets a request to turn the screen. On a tablet that is taller than
wide, the board is above the panel, and the tiles are large enough.
-}
upright : Model -> Bool
upright model =
    let
        ( width, height ) =
            model.viewport
    in
    width < 640 && width <= height


{-| The height in pixels of the screen that is not for the board. On a large
screen, it is the 1.5rem padding of the page at the top and at the bottom.
The page of a game has no header and no footer. On a small screen, it is the
0.5rem padding of the page at the top and at the bottom, and the rows of the
panel (the compact row, the link for a game with more players, the scores
when more players are in, and maybe the message for a watcher) with the
0.5rem gaps between them. The heights of the rows are approximate, because
the scores can wrap. On a small screen that is wider than tall, the panel is
at the left, so only the padding is not for the board.
-}
reservedHeight : Model -> Me -> Game -> Float
reservedHeight model me game =
    if Tuple.first model.viewport >= largeScreen then
        48

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


{-| Make the board as wide as possible, but small enough that it is all on
the screen.
-}
fieldWidth : Model -> Me -> Game -> String
fieldWidth model me game =
    "min(100%, calc((100dvh - "
        ++ String.fromFloat (reservedHeight model me game)
        ++ "px) * "
        ++ String.fromFloat (toFloat boardWidth / toFloat boardHeight)
        ++ "))"


{-| The number of browsers that only watch the game, when there are any.
-}
viewWatchers : Int -> Html Msg
viewWatchers count =
    if count > 0 then
        span
            [ id "mahjong-watchers"
            , class "flex shrink-0 items-center gap-1 text-sm tabular-nums text-slate-500 dark:text-slate-400"
            , Html.Attributes.title ("Watchers: " ++ String.fromInt count)
            ]
            [ span [ class "hero-eye size-4" ] [], text (String.fromInt count) ]

    else
        text ""


viewMuteButton : Bool -> Html Msg
viewMuteButton muted =
    button
        [ id "mahjong-mute"
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


{-| Shows a free pair. It is off when no pair is free: then the player
must shuffle. On a small screen, only the icon shows, but not in the column
of a screen that is wider than tall.
-}
viewHintButton : Bool -> Html Msg
viewHintButton stuck =
    button
        [ id "mahjong-hint"
        , class "group flex size-9 shrink-0 items-center justify-center gap-2 rounded-full text-sm font-medium text-amber-700 ring-1 ring-amber-200 transition enabled:hover:bg-amber-50 enabled:hover:ring-amber-300 enabled:active:scale-95 disabled:opacity-50 max-lg:landscape:size-auto max-lg:landscape:px-4 max-lg:landscape:py-2 lg:order-5 lg:size-auto lg:self-start lg:px-4 lg:py-2 dark:text-amber-300 dark:ring-amber-400/30 dark:enabled:hover:bg-amber-400/10 dark:enabled:hover:ring-amber-400/50"
        , Html.Attributes.disabled stuck
        , onClick Hint
        , Html.Attributes.title "Show a free pair"
        ]
        [ span [ class "hero-light-bulb size-4 transition-transform group-enabled:group-hover:-rotate-12" ] []
        , span [ class "hidden max-lg:landscape:inline lg:inline" ] [ text "Hint" ]
        ]


{-| Starts a new board for all players, also during a game. On a small
screen, only the icon shows, but not in the column of a screen that is wider
than tall.
-}
viewRestartButton : Html Msg
viewRestartButton =
    button
        [ id "mahjong-restart"
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
            [ id "mahjong-link"
            , readonly True
            , value model.gameUrl
            , class "min-w-0 flex-1 truncate bg-transparent text-octo-navy outline-none max-lg:landscape:px-2 max-lg:landscape:py-1 lg:px-2 lg:py-1 dark:text-slate-100"
            ]
            []
        , button
            [ id "mahjong-copy-link"
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


{-| The time on the left, and the tiles on the board on the right. On a
small screen, it is small and at the right of the compact row.
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
    div [ id "mahjong-clock", class "ml-auto flex gap-4 pr-2 max-lg:landscape:ml-0 max-lg:landscape:gap-6 max-lg:landscape:pr-0 max-lg:landscape:pl-2 lg:order-2 lg:ml-0 lg:grid lg:grid-cols-2 lg:gap-0 lg:divide-x lg:divide-slate-200 lg:rounded-2xl lg:bg-white lg:py-3 lg:pr-0 lg:shadow-sm lg:ring-1 lg:ring-slate-200 dark:lg:divide-white/10 dark:lg:bg-white/5 dark:lg:shadow-none dark:lg:ring-white/10" ]
        [ div [ class "flex flex-col items-center justify-center max-lg:landscape:items-start" ]
            [ span [ class "text-[0.625rem] font-medium tracking-wide text-slate-400 uppercase lg:text-xs" ] [ text "time" ]
            , span [ id "mahjong-time", class "text-lg leading-tight font-light text-slate-700 tabular-nums lg:text-3xl dark:text-slate-100" ] [ text (formatTime elapsedMs) ]
            ]
        , div [ class "flex flex-col items-center justify-center max-lg:landscape:items-start" ]
            [ span [ class "text-[0.625rem] font-medium tracking-wide text-slate-400 uppercase lg:text-xs" ] [ text "tiles" ]
            , span [ id "mahjong-tiles-left", class "text-lg leading-tight font-bold text-octo-indigo tabular-nums lg:text-3xl dark:text-octo-indigo-light" ]
                [ text (String.fromInt (List.length game.tiles)) ]
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


{-| The players in the order in which they joined, with the pairs they
removed
-}
viewScores : Me -> Game -> Html Msg
viewScores me game =
    ul [ id "mahjong-scores", class "flex flex-wrap gap-2 max-lg:landscape:flex-col lg:order-4 lg:flex-col" ]
        (List.map
            (\player ->
                li
                    [ id ("mahjong-score-" ++ player.id)
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


{-| No pair is free. A player can shuffle, and a watcher only reads the
notice. The notice is on the bottom of the board, so that it is always on
the screen with the board.
-}
viewStuck : Me -> Html Msg
viewStuck me =
    div
        [ id "mahjong-stuck"
        , class "mahjong-notice absolute inset-x-0 bottom-3 mx-auto flex w-fit max-w-[calc(100%-1.5rem)] flex-wrap items-center justify-center gap-3 rounded-2xl bg-amber-50 px-4 py-2.5 text-sm text-amber-900 shadow-lg ring-1 ring-amber-200 dark:bg-[#3A3322] dark:text-amber-200 dark:ring-amber-400/25"
        ]
        [ span [ class "flex items-center gap-2" ]
            [ span [ class "hero-exclamation-triangle size-4" ] []
            , text "No free pairs are left."
            ]
        , if me == Nothing then
            text ""

          else
            button
                [ id "mahjong-shuffle"
                , class "group flex items-center gap-2 rounded-full bg-octo-indigo px-4 py-1.5 font-medium text-white shadow-sm transition hover:bg-octo-indigo/90 active:scale-95"
                , onClick Shuffle
                ]
                [ span [ class "hero-arrows-right-left size-4 transition-transform duration-300 group-hover:rotate-180" ] []
                , text "Shuffle"
                ]
        ]



-- BOARD


{-| The size of a half tile in the view box. A tile is 2 by 2 half tiles.
-}
halfWidth : Int
halfWidth =
    30


halfHeight : Int
halfHeight =
    40


{-| The face of a tile, a bit smaller than 2 by 2 half tiles, so that the
tiles have thin gaps
-}
faceWidth : Int
faceWidth =
    58


faceHeight : Int
faceHeight =
    78


{-| Each layer moves up and to the left by this, so that the sides of the
tiles below show
-}
layerX : Int
layerX =
    5


layerY : Int
layerY =
    7


{-| The space around the tiles: the top layer moves 4 layers up and to the
left, and the sides stick out on the right and at the bottom.
-}
marginLeft : Int
marginLeft =
    4 * layerX + 2


marginTop : Int
marginTop =
    4 * layerY + 2


{-| The Turtle is 30 by 16 half tiles
-}
boardWidth : Int
boardWidth =
    marginLeft + 30 * halfWidth + layerX + 4


boardHeight : Int
boardHeight =
    marginTop + 16 * halfHeight + layerY + 4


{-| The tiles from the bottom layer up. In a layer, a tile comes after the
tiles on its left and above it, so that it covers their sides.
-}
viewBoard : Model -> Me -> Game -> Html Msg
viewBoard model me game =
    let
        playable =
            canPlay me game

        tiles =
            List.sortBy drawOrder game.tiles

        ghosts =
            case game.last of
                Just last ->
                    List.map (viewGhost (List.length game.players > 1) last) last.tiles

                Nothing ->
                    []
    in
    Svg.svg
        [ id "mahjong-board"
        , SA.class "mahjong-board block h-auto w-full"
        , SA.viewBox ("0 0 " ++ String.fromInt boardWidth ++ " " ++ String.fromInt boardHeight)
        , Html.Attributes.attribute "role" "group"
        , Html.Attributes.attribute "aria-label" "Mahjong board"
        ]
        [ Svg.defs []
            [ Svg.linearGradient [ SA.id "mahjong-face", SA.x1 "0", SA.y1 "0", SA.x2 "0", SA.y2 "1" ]
                [ Svg.stop [ SA.offset "0", SA.stopColor "#FFFDF8" ] []
                , Svg.stop [ SA.offset "1", SA.stopColor "#F1ECE0" ] []
                ]
            ]
        , Svg.Keyed.node "g" [] (List.map (\tile -> viewTile model game playable tile) tiles)
        , Svg.Keyed.node "g" [ SA.class "pointer-events-none" ] ghosts
        ]


{-| In a layer, a tile comes after the tiles on its left and above it, so
that it covers their sides.
-}
drawOrder : Tile -> ( Int, Int, Int )
drawOrder tile =
    ( tile.layer, tile.col + tile.row, tile.col )


{-| How long the tiles slide in a shuffle, with the longest delay (see
`viewTile`)
-}
shuffleMs : Float
shuffleMs =
    500


tileX : Tile -> Int
tileX tile =
    marginLeft + tile.col * halfWidth - tile.layer * layerX


tileY : Tile -> Int
tileY tile =
    marginTop + tile.row * halfHeight - tile.layer * layerY


{-| Keyed by the id and the face, so that the faces flip in after the
countdown (see `revealing`).

In a shuffle, each tile is at once in its new place and in the new draw
order, so that the layers are right during the shuffle. An animation moves
it there from the old place (`--from-x` and `--from-y`, see app.css), each
tile with a small delay of its own. A transition cannot do this: the page
moves the nodes for the new draw order, and a moved node stops its
transition.

The shake is on an inner node, keyed by the shake, so that each click on a
tile that is not free shakes it again. The pulse of a hint is there too, so
that each hint pulses again.

-}
viewTile : Model -> Game -> Bool -> Tile -> ( String, Svg Msg )
viewTile model game playable tile =
    let
        free =
            playable && isFree game.tiles tile

        picked =
            model.selected == Just tile.id || (model.pending |> Maybe.map (\( a, b ) -> a == tile.id || b == tile.id) |> Maybe.withDefault False)

        blocked =
            model.blocked == Just tile.id

        hinted =
            model.hint |> Maybe.map (\( a, b ) -> a == tile.id || b == tile.id) |> Maybe.withDefault False

        shakeKey =
            if blocked then
                String.fromInt model.blockedCount

            else
                ""

        hintKey =
            if hinted then
                "h" ++ String.fromInt model.hintCount

            else
                ""

        -- The way from the old place to the new one
        from =
            model.shuffling
                |> Maybe.andThen (Dict.get tile.id)
                |> Maybe.map (\( x, y ) -> ( x - tileX tile, y - tileY tile ))
    in
    ( String.fromInt tile.id ++ ":" ++ Maybe.withDefault "" tile.face
    , Svg.g
        [ -- One attribute, because `style` cannot set a CSS variable
          Html.Attributes.attribute "style"
            ("transform: translate("
                ++ String.fromInt (tileX tile)
                ++ "px, "
                ++ String.fromInt (tileY tile)
                ++ "px)"
                ++ (case from of
                        Just ( x, y ) ->
                            "; --from-x: "
                                ++ String.fromInt x
                                ++ "px; --from-y: "
                                ++ String.fromInt y
                                ++ "px; animation-delay: "
                                ++ String.fromInt (modBy 9 (tile.id * 7) * 12)
                                ++ "ms"

                        Nothing ->
                            ""
                   )
            )
        , classes
            [ ( "mahjong-tile", True )
            , ( "is-playable", playable )
            , ( "is-free", free )
            , ( "is-selected", picked )
            , ( "is-hinted", hinted )
            , ( "is-shuffling", from /= Nothing )
            ]
        , Svg.Events.onClick (ClickTile tile.id)
        , Html.Attributes.attribute "aria-label" (faceName tile.face)
        , Html.Attributes.attribute "role" "button"
        ]
        [ Svg.g
            [ classes
                [ ( "mahjong-tile-body", True )
                , ( "mahjong-flip", model.revealing )
                ]
            ]
            [ Svg.Keyed.node "g"
                []
                [ ( shakeKey ++ hintKey
                  , Svg.g [ classes [ ( "mahjong-shake", blocked ), ( "mahjong-pulse", hinted ) ] ]
                        (tileShape ++ [ viewFace tile.face, viewShade tile ])
                  )
                ]
            ]
        ]
    )


{-| The lower layers are a bit darker, so that the layers are easy to tell
apart. The layer 3 and the top have no shade.
-}
viewShade : Tile -> Svg Msg
viewShade tile =
    if tile.layer >= 3 then
        Svg.g [] []

    else
        Svg.rect
            [ SA.width (String.fromInt faceWidth)
            , SA.height (String.fromInt faceHeight)
            , SA.rx "7"
            , SA.class "mahjong-shade"
            , SA.opacity (String.fromFloat (toFloat (3 - tile.layer) * 0.045))
            ]
            []


{-| The pair that a player removed last fades out where it was. With other
players, it has the color of the player who removed it.
-}
viewGhost : Bool -> Last -> Tile -> ( String, Svg Msg )
viewGhost multiplayer last tile =
    ( "ghost-" ++ String.fromInt tile.id
    , Svg.g [ SA.transform (translate (tileX tile) (tileY tile)) ]
        [ Svg.g [ SA.class "mahjong-ghost" ]
            (tileShape
                ++ [ viewFace tile.face
                   , Svg.rect
                        [ SA.width (String.fromInt faceWidth)
                        , SA.height (String.fromInt faceHeight)
                        , SA.rx "7"
                        , SA.fill "none"
                        , SA.stroke
                            (if multiplayer then
                                last.color

                             else
                                "#1A9FCB"
                            )
                        , SA.strokeWidth "3"
                        ]
                        []
                   ]
            )
        ]
    )


{-| The side and the face of a tile, without the image
-}
tileShape : List (Svg Msg)
tileShape =
    [ Svg.rect
        [ SA.x (String.fromInt layerX)
        , SA.y (String.fromInt layerY)
        , SA.width (String.fromInt faceWidth)
        , SA.height (String.fromInt faceHeight)
        , SA.rx "7"
        , SA.class "mahjong-side"
        ]
        []
    , Svg.rect
        [ SA.x "2"
        , SA.y "3"
        , SA.width (String.fromInt faceWidth)
        , SA.height (String.fromInt faceHeight)
        , SA.rx "7"
        , SA.class "mahjong-edge"
        ]
        []
    , Svg.rect
        [ SA.width (String.fromInt faceWidth)
        , SA.height (String.fromInt faceHeight)
        , SA.rx "7"
        , SA.class "mahjong-face"
        ]
        []
    ]


translate : Int -> Int -> String
translate x y =
    "translate(" ++ String.fromInt x ++ " " ++ String.fromInt y ++ ")"


classes : List ( String, Bool ) -> Svg.Attribute msg
classes list =
    list
        |> List.filter Tuple.second
        |> List.map Tuple.first
        |> String.join " "
        |> SA.class


{-| For example, "3 of dots" or "East wind"
-}
faceName : Maybe String -> String
faceName face =
    case Maybe.map (String.split "-") face of
        Just [ "dots", n ] ->
            n ++ " of dots"

        Just [ "bamboo", n ] ->
            n ++ " of bamboo"

        Just [ "chars", n ] ->
            n ++ " of characters"

        Just [ "wind", w ] ->
            (case w of
                "e" ->
                    "East"

                "s" ->
                    "South"

                "w" ->
                    "West"

                _ ->
                    "North"
            )
                ++ " wind"

        Just [ "dragon", d ] ->
            (case d of
                "r" ->
                    "Red"

                "g" ->
                    "Green"

                _ ->
                    "White"
            )
                ++ " dragon"

        Just [ "flower", n ] ->
            "Flower " ++ n

        Just [ "season", n ] ->
            "Season " ++ n

        _ ->
            "Tile"



-- FACES


blue : String
blue =
    "#1F3A93"


red : String
red =
    "#C0392B"


green : String
green =
    "#1E7D3A"


{-| The image on a tile, in a box of 58 by 78
-}
viewFace : Maybe String -> Svg msg
viewFace face =
    case Maybe.map (String.split "-") face of
        Just [ "dots", n ] ->
            Svg.g [] (dots (Maybe.withDefault 1 (String.toInt n)))

        Just [ "bamboo", n ] ->
            Svg.g [] (bamboo (Maybe.withDefault 1 (String.toInt n)))

        Just [ "chars", n ] ->
            Svg.g []
                [ glyph 29 31 26 blue (numeral (Maybe.withDefault 1 (String.toInt n)))
                , glyph 29 67 30 red "萬"
                ]

        Just [ "wind", w ] ->
            glyph 29
                54
                40
                blue
                (case w of
                    "e" ->
                        "東"

                    "s" ->
                        "南"

                    "w" ->
                        "西"

                    _ ->
                        "北"
                )

        Just [ "dragon", "r" ] ->
            glyph 29 55 44 red "中"

        Just [ "dragon", "g" ] ->
            glyph 29 54 40 green "發"

        Just [ "dragon", _ ] ->
            Svg.g [ SA.fill "none", SA.stroke blue ]
                [ Svg.rect [ SA.x "9", SA.y "10", SA.width "40", SA.height "58", SA.rx "4", SA.strokeWidth "3" ] []
                , Svg.rect [ SA.x "14", SA.y "15", SA.width "30", SA.height "48", SA.rx "2", SA.strokeWidth "1.2" ] []
                ]

        Just [ "flower", n ] ->
            Svg.g [] (flower (Maybe.withDefault 1 (String.toInt n)) ++ [ corner n ])

        Just [ "season", n ] ->
            let
                ( char, color ) =
                    case n of
                        "1" ->
                            ( "春", green )

                        "2" ->
                            ( "夏", red )

                        "3" ->
                            ( "秋", "#C2581B" )

                        _ ->
                            ( "冬", blue )
            in
            Svg.g [] [ glyph 29 55 38 color char, corner n ]

        _ ->
            Svg.g [] []


{-| A Chinese character. The `y` is the base line.
-}
glyph : Float -> Float -> Float -> String -> String -> Svg msg
glyph x y size color char =
    Svg.text_
        [ SA.x (String.fromFloat x)
        , SA.y (String.fromFloat y)
        , SA.fontSize (String.fromFloat size)
        , SA.fill color
        , SA.textAnchor "middle"
        , SA.class "mahjong-glyph"
        ]
        [ Svg.text char ]


{-| The number of a flower or a season, in the top left corner
-}
corner : String -> Svg msg
corner n =
    Svg.text_
        [ SA.x "7"
        , SA.y "15"
        , SA.fontSize "11"
        , SA.fontWeight "700"
        , SA.fill "#8A8270"
        ]
        [ Svg.text n ]


numeral : Int -> String
numeral n =
    case n of
        1 ->
            "一"

        2 ->
            "二"

        3 ->
            "三"

        4 ->
            "四"

        5 ->
            "五"

        6 ->
            "六"

        7 ->
            "七"

        8 ->
            "八"

        _ ->
            "九"


{-| The coins of the dots suit, in the usual patterns and colors
-}
dots : Int -> List (Svg msg)
dots n =
    let
        at r color ( x, y ) =
            coin x y r color
    in
    case n of
        1 ->
            [ coin 29 39 20 blue
            , Svg.circle [ SA.cx "29", SA.cy "39", SA.r "9", SA.fill "none", SA.stroke red, SA.strokeWidth "2.2" ] []
            ]

        2 ->
            List.map2 (at 12) [ green, blue ] [ ( 29, 21 ), ( 29, 57 ) ]

        3 ->
            List.map2 (at 10) [ blue, red, green ] [ ( 14, 15 ), ( 29, 39 ), ( 44, 63 ) ]

        4 ->
            List.map2 (at 10) [ blue, green, green, blue ] [ ( 16, 22 ), ( 42, 22 ), ( 16, 56 ), ( 42, 56 ) ]

        5 ->
            List.map2 (at 9) [ blue, green, red, green, blue ] [ ( 15, 17 ), ( 43, 17 ), ( 29, 39 ), ( 15, 61 ), ( 43, 61 ) ]

        6 ->
            List.map2 (at 9) [ green, green, red, red, red, red ] (grid [ 17, 41 ] [ 15, 39, 63 ])

        7 ->
            List.map2 (at 7) [ green, green, green ] [ ( 12, 12 ), ( 29, 19 ), ( 46, 26 ) ]
                ++ List.map2 (at 8) [ red, red, red, red ] (grid [ 18, 40 ] [ 45, 65 ])

        8 ->
            List.map (at 8 blue) (grid [ 17, 41 ] [ 12, 30, 48, 66 ])

        _ ->
            List.map2 (at 7.5) (List.concatMap (List.repeat 3) [ blue, red, green ]) (grid [ 13, 29, 45 ] [ 15, 39, 63 ])


{-| The points of a grid, row by row
-}
grid : List Float -> List Float -> List ( Float, Float )
grid xs ys =
    List.concatMap (\y -> List.map (\x -> ( x, y )) xs) ys


{-| A coin: a ring, a thin inner ring and a dot
-}
coin : Float -> Float -> Float -> String -> Svg msg
coin x y r color =
    Svg.g [ SA.stroke color, SA.fill "none" ]
        [ Svg.circle [ SA.cx (String.fromFloat x), SA.cy (String.fromFloat y), SA.r (String.fromFloat r), SA.strokeWidth (String.fromFloat (max 1.6 (r / 6))) ] []
        , Svg.circle [ SA.cx (String.fromFloat x), SA.cy (String.fromFloat y), SA.r (String.fromFloat (r * 0.6)), SA.strokeWidth "1.1" ] []
        , Svg.circle [ SA.cx (String.fromFloat x), SA.cy (String.fromFloat y), SA.r (String.fromFloat (r * 0.22)), SA.fill color, SA.stroke "none" ] []
        ]


{-| The sticks of the bamboo suit. The 1 of bamboo is a bird.
-}
bamboo : Int -> List (Svg msg)
bamboo n =
    let
        at h color ( x, y ) =
            stick x y h color
    in
    case n of
        1 ->
            bird

        2 ->
            List.map (at 26 green) [ ( 29, 23 ), ( 29, 55 ) ]

        3 ->
            [ stick 29 22 24 blue ] ++ List.map (at 24 green) [ ( 17, 55 ), ( 41, 55 ) ]

        4 ->
            List.map2 (at 26) [ blue, green, green, blue ] (grid [ 17, 41 ] [ 23, 55 ])

        5 ->
            List.map (at 26 green) (grid [ 13, 45 ] [ 23, 55 ]) ++ [ stick 29 39 26 red ]

        6 ->
            List.map (at 26 green) (grid [ 13, 29, 45 ] [ 23, 55 ])

        7 ->
            stick 29 14 20 red :: List.map (at 21 green) (grid [ 13, 29, 45 ] [ 40, 64 ])

        8 ->
            List.map (at 26 green) (grid [ 9.5, 22.5, 35.5, 48.5 ] [ 23, 55 ])

        _ ->
            List.map2 (at 20) (List.concat (List.repeat 3 [ green, red, green ])) (grid [ 13, 29, 45 ] [ 15, 39, 63 ])


{-| One stick: a rounded bar with a joint at the middle and at each end
-}
stick : Float -> Float -> Float -> String -> Svg msg
stick x y h color =
    let
        w =
            6

        band by =
            Svg.rect [ SA.x (String.fromFloat (x - w / 2 - 1)), SA.y (String.fromFloat (by - 1.2)), SA.width (String.fromFloat (w + 2)), SA.height "2.4", SA.rx "1.2", SA.fill color ] []
    in
    Svg.g []
        [ Svg.rect [ SA.x (String.fromFloat (x - w / 2)), SA.y (String.fromFloat (y - h / 2)), SA.width (String.fromFloat w), SA.height (String.fromFloat h), SA.rx "3", SA.fill color ] []
        , Svg.line [ SA.x1 (String.fromFloat x), SA.y1 (String.fromFloat (y - h / 2 + 3)), SA.x2 (String.fromFloat x), SA.y2 (String.fromFloat (y + h / 2 - 3)), SA.stroke "#fff", SA.strokeWidth "1", SA.opacity "0.55" ] []
        , band (y - h / 2 + 1.2)
        , band y
        , band (y + h / 2 - 1.2)
        ]


{-| A small green bird with a red wing, as on the 1 of bamboo
-}
bird : List (Svg msg)
bird =
    [ -- The tail
      Svg.path [ SA.d "M22 46 L5 62 L10 64 Z M23 48 L9 70 L14 70 Z M25 49 L17 74 L22 72 Z", SA.fill green ] []

    -- The body and the neck
    , Svg.path [ SA.d "M20 47 C20 36 30 31 37 33 C40 28 38 22 41 19 C45 15 51 18 50 23 C49 27 45 28 45 33 C46 43 38 52 28 52 C24 52 20 50 20 47 Z", SA.fill green ] []

    -- The wing
    , Svg.path [ SA.d "M26 44 C29 37 36 36 40 38 C38 44 32 47 26 44 Z", SA.fill red ] []

    -- The beak and the eye
    , Svg.path [ SA.d "M49 20 L56 22 L49 24 Z", SA.fill red ] []
    , Svg.circle [ SA.cx "45", SA.cy "21", SA.r "1.6", SA.fill "#fff" ] []

    -- The legs
    , Svg.path [ SA.d "M32 51 L30 60 M37 50 L38 60 M27 60 L33 60 M35 60 L41 60", SA.stroke red, SA.strokeWidth "1.8", SA.strokeLinecap "round", SA.fill "none" ] []
    ]


{-| The 4 flowers: a plum, a tulip, a chrysanthemum and a lotus
-}
flower : Int -> List (Svg msg)
flower n =
    case n of
        1 ->
            List.map
                (\i ->
                    let
                        angle =
                            degrees (toFloat i * 72 - 90)
                    in
                    Svg.circle
                        [ SA.cx (String.fromFloat (29 + 10 * cos angle))
                        , SA.cy (String.fromFloat (40 + 10 * sin angle))
                        , SA.r "8"
                        , SA.fill "#E07A8B"
                        , SA.stroke red
                        , SA.strokeWidth "1"
                        ]
                        []
                )
                (List.range 0 4)
                ++ [ Svg.circle [ SA.cx "29", SA.cy "40", SA.r "4.5", SA.fill "#E8B931" ] [] ]

        2 ->
            [ Svg.path [ SA.d "M29 44 C29 54 28 62 26 70 M28 58 C34 52 40 52 44 50 C40 58 34 60 28 60", SA.stroke green, SA.strokeWidth "2", SA.fill "none", SA.strokeLinecap "round" ] []
            , Svg.path [ SA.d "M19 22 C17 32 20 44 29 45 C38 44 41 32 39 22 L34 29 L29 18 L24 29 Z", SA.fill "#E74C3C", SA.stroke red, SA.strokeWidth "1.2", SA.strokeLinejoin "round" ] []
            ]

        3 ->
            List.map
                (\i ->
                    Svg.ellipse
                        [ SA.cx "29"
                        , SA.cy "27"
                        , SA.rx "2.6"
                        , SA.ry "11"
                        , SA.fill "none"
                        , SA.stroke red
                        , SA.strokeWidth "1"
                        , SA.transform ("rotate(" ++ String.fromInt (i * 20) ++ " 29 39)")
                        ]
                        []
                )
                (List.range 0 17)
                ++ [ Svg.circle [ SA.cx "29", SA.cy "39", SA.r "3", SA.fill red ] [] ]

        _ ->
            [ Svg.path [ SA.d "M8 58 C18 62 40 62 50 58", SA.stroke blue, SA.strokeWidth "2", SA.fill "none", SA.strokeLinecap "round" ] [] ]
                ++ List.map
                    (\angle ->
                        Svg.ellipse
                            [ SA.cx "29"
                            , SA.cy "38"
                            , SA.rx "6"
                            , SA.ry "16"
                            , SA.fill "#9CC3F0"
                            , SA.stroke blue
                            , SA.strokeWidth "1.2"
                            , SA.transform ("rotate(" ++ String.fromInt angle ++ " 29 54)")
                            ]
                            []
                    )
                    [ -50, 50, -25, 25, 0 ]



-- COVERS


{-| Covers the board until all players are in.
-}
viewWaiting : Game -> Html Msg
viewWaiting game =
    div
        [ id "mahjong-waiting"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-3 rounded-2xl bg-octo-navy/80 p-4 text-center text-white"
        ]
        [ p [ class "text-3xl font-semibold" ] [ text "Waiting for players" ]
        , p [ id "mahjong-waiting-count", class "text-lg tabular-nums opacity-80" ]
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
        [ id "mahjong-countdown"
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


viewResult : NextGame -> Bool -> Me -> Game -> Html Msg
viewResult nextGame guest me game =
    let
        players =
            game.players

        solo =
            List.length players == 1

        message =
            case ( solo, winners players ) of
                ( True, _ ) ->
                    "Cleared!"

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
        [ id "mahjong-result"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-4 rounded-2xl bg-octo-navy/75 p-4 text-center text-white backdrop-blur-sm"
        ]
        [ p [ class "text-3xl font-semibold" ] [ text message ]
        , p [ id "mahjong-final-time", class "text-lg tabular-nums opacity-80" ]
            [ text ("Time " ++ formatTime game.elapsedMs) ]
        , if solo then
            text ""

          else
            ol [ class "flex flex-col gap-1 text-sm" ]
                (List.map
                    (\player ->
                        li [ class "flex items-center gap-2" ]
                            [ span [ class "size-3 rounded-full", style "background" player.color ] []
                            , span [ class "flex-1 text-left" ] [ text (playerName me player) ]
                            , span [ class "pl-6 font-semibold tabular-nums" ] [ text (String.fromInt player.score) ]
                            ]
                    )
                    ranked
                )
        , if me == Nothing then
            text ""

          else
            button
                [ id "mahjong-play-again"
                , class "rounded-full bg-white px-6 py-2.5 font-medium text-octo-indigo shadow-lg transition hover:-translate-y-0.5 hover:bg-octo-mist active:translate-y-0"
                , onClick Restart
                ]
                [ text "Play again" ]
        , let
            -- In a game with other players, a player starts the next game for all of them
            ( element, action ) =
                if me /= Nothing && List.length game.players > 1 then
                    ( button, onClick StartNextGame )

                else
                    ( a, href nextGame.path )
          in
          element
            [ id "mahjong-next-game"
            , action
            , attribute "data-ga-link" "or_try"
            , attribute "data-ga-from" "Mahjong"
            , attribute "data-ga-to" nextGame.name
            , class "group text-sm font-medium text-white underline-offset-4 transition hover:underline"
            ]
            [ text ("Or try " ++ nextGame.name ++ " ")
            , span [ class "inline-block transition group-hover:translate-x-0.5" ] [ text "→" ]
            ]

        -- Only a guest who played gets the call to sign in, not a spectator
        , if guest && me /= Nothing then
            p [ id "mahjong-sign-in", class "text-sm text-white/70" ]
                [ a
                    [ href "/signin"
                    , class "font-medium text-white underline underline-offset-4 transition hover:text-octo-mist"
                    ]
                    [ text "Sign in" ]
                , text " to keep your scores."
                ]

          else
            text ""
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
