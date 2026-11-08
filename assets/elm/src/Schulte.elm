port module Schulte exposing (main)

{-| Multiplayer race on a classic Schulte table.

The server owns the game: a square grid with the numbers from 1 to
size², the next number and the scores. The first player to click the next
number gets a point. A found number flashes in the color of its finder.
With marks, it then stays pale. Without marks (the classic rule), it looks
the same as the other numbers. This module draws the state that comes in
through ports and sends the player's clicks out. app.js connects the ports
to a Phoenix channel.

A click on a wrong number does nothing, but its number shakes for this
player only.

A click on the right number shows at once, before the server confirms it:
the number flashes and is marked, the sound plays and the score goes up
(see `optimistic`). When another player was faster, the next state of the
server corrects it.

The module compares each new state with the old one and sends the names
of the sounds to play out through a port. The player can mute the sounds.

The game is for a set number of players. Before all of them are in, the
board is hidden and nobody can pick. A countdown with beeps comes before
each field. A browser that joins a full game only
watches: it has no player id.

The port names start with "schulte", because Elm does not allow two ports
with the same name in one bundle.

-}

import Browser
import Browser.Dom
import Browser.Events
import Html exposing (Html, a, aside, button, div, h1, img, input, li, ol, p, span, text, ul)
import Html.Attributes exposing (alt, attribute, class, classList, disabled, href, id, readonly, rel, src, style, target, value)
import Html.Events exposing (onClick)
import Html.Keyed
import Json.Decode as Decode exposing (Decoder)
import Press
import Process
import Svg exposing (Svg)
import Svg.Attributes as SA
import Svg.Keyed
import Task
import Time



-- PORTS


port schultePick : Int -> Cmd msg


port schulteRestart : () -> Cmd msg


{-| Starts the next game for all players, see OctomoctoWeb.NextGame
-}
port schulteNextGame : () -> Cmd msg


port schulteCopyText : String -> Cmd msg


port schulteJoined : (Decode.Value -> msg) -> Sub msg


port schulteState : (Decode.Value -> msg) -> Sub msg


port schulteJoinFailed : (String -> msg) -> Sub msg


{-| The number of browsers that only watch the game, after the join and
after each change.
-}
port schulteWatchers : (Int -> msg) -> Sub msg


port schultePlaySound : String -> Cmd msg


port schulteSaveMuted : Bool -> Cmd msg



-- MODEL


{-| The `name` is the display name of a signed-in player, or Nothing for a
guest. Then the player is known by the `colorName`.
-}
type alias Player =
    { id : String
    , name : Maybe String
    , color : String
    , colorName : String
    , score : Int
    }


{-| A cell of the grid. The cells come row by row, from the top left.
-}
type alias Cell =
    { number : Int
    , foundBy : Maybe String
    }


type alias Game =
    { size : Int
    , total : Int
    , next : Int
    , cells : List Cell
    , players : List Player

    -- The time since the field started. After the end, the final time.
    , elapsedMs : Int

    -- True until the game has all its players. The cells are empty then.
    , waiting : Bool
    , playersNeeded : Int

    -- True when the found numbers become pale
    , marks : Bool

    -- The id of the player who changes the settings of the next game
    -- of the match (see `OctomoctoWeb.MatchPage`). The other players wait.
    , editing : Maybe String
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

    -- The settings page of the next game of the match. Nothing for a
    -- game with one player.
    , changeSettingsUrl : Maybe String
    , nextGame : NextGame
    , guest : Bool
    , connection : Connection
    , copied : Bool

    -- The number that shakes after a wrong click. The count makes sure
    -- that only the newest timeout stops the shake.
    , shaking : Maybe Int
    , shakeCount : Int

    -- The last number that this browser sent, 0 before the first. The
    -- player can click the next number before the server confirms the
    -- last one, see `expectedNext`.
    , sent : Int

    -- The player who found the last number. The count goes up on each
    -- found number, so that the row flashes again for the same player.
    , lastFinder : Maybe String
    , findCount : Int

    -- The local time (in ms) when the field started, and the local time
    -- now. The clock ticks between the server updates.
    , clockStart : Int
    , now : Int

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

    -- The settings page of the next game of the match. Nothing for a
    -- game with one player.
    , changeSettingsUrl : Maybe String
    , nextGame : NextGame
    , guest : Bool
    , muted : Bool
    }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { gameUrl = flags.gameUrl
      , settingsUrl = flags.settingsUrl
      , changeSettingsUrl = flags.changeSettingsUrl
      , nextGame = flags.nextGame
      , guest = flags.guest
      , connection = Connecting
      , copied = False
      , shaking = Nothing
      , shakeCount = 0
      , sent = 0
      , lastFinder = Nothing
      , findCount = 0
      , clockStart = 0
      , now = 0
      , beepedStep = Nothing
      , muted = flags.muted
      , watchers = 0
      , viewport = ( 1024, 768 )
      }
    , Task.perform (\vp -> Resized vp.viewport.width vp.viewport.height) Browser.Dom.getViewport
    )


finished : Game -> Bool
finished game =
    game.next > game.total



-- UPDATE


type Msg
    = GotJoined Decode.Value
    | GotState Decode.Value
    | GotJoinFailed String
    | GotWatchers Int
    | Pick Int
    | ShakeDone Int
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
                    ( { model | connection = Joined me game, sent = 0 }, syncClock game )

                Err err ->
                    ( { model | connection = Failed (Decode.errorToString err) }, Cmd.none )

        GotState value ->
            case ( model.connection, Decode.decodeValue gameDecoder value ) of
                ( Joined me old, Ok game ) ->
                    let
                        withFinder =
                            case List.reverse (newFinders old game) of
                                finder :: _ ->
                                    { model | lastFinder = Just finder, findCount = model.findCount + 1 }

                                [] ->
                                    model

                        -- A new table starts again from 1
                        sent =
                            if game.next < old.next then
                                0

                            else
                                model.sent
                    in
                    ( { withFinder | connection = Joined me game, sent = sent }
                    , Cmd.batch [ syncClock game, playSounds model (stateSounds me old game) ]
                    )

                _ ->
                    ( model, Cmd.none )

        GotJoinFailed reason ->
            ( { model | connection = Failed reason }, Cmd.none )

        GotWatchers count ->
            ( { model | watchers = count }, Cmd.none )

        Pick number ->
            case model.connection of
                Joined (Just _) game ->
                    if game.waiting then
                        ( model, Cmd.none )

                    else if number == expectedNext model game then
                        ( { model | sent = number }
                        , Cmd.batch [ schultePick number, playSounds model [ "found" ] ]
                        )

                    else if number > expectedNext model game || not game.marks then
                        let
                            count =
                                model.shakeCount + 1
                        in
                        ( { model | shaking = Just number, shakeCount = count }
                        , Cmd.batch
                            [ Process.sleep 400 |> Task.perform (\_ -> ShakeDone count)
                            , playSounds model [ "wrong" ]
                            ]
                        )

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        ShakeDone count ->
            if count == model.shakeCount then
                ( { model | shaking = Nothing }, Cmd.none )

            else
                ( model, Cmd.none )

        Restart ->
            ( model, schulteRestart () )

        StartNextGame ->
            ( model, schulteNextGame () )

        CopyLink ->
            ( { model | copied = True }
            , Cmd.batch
                [ schulteCopyText model.gameUrl
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

        Resized width height ->
            ( { model | viewport = ( width, height ) }, Cmd.none )

        ToggleMuted ->
            ( { model | muted = not model.muted }, schulteSaveMuted (not model.muted) )


{-| The number that the player looks for: the next number of the server,
or the number after the last number that this browser sent, when the
server did not confirm it yet. Then the player can click the numbers as
fast as the hand allows. When another player was faster, the server
ignores the click, and its next state corrects the number.
-}
expectedNext : Model -> Game -> Int
expectedNext model game =
    if model.sent >= game.next && not (finished game) then
        model.sent + 1

    else
        game.next


{-| The game with the numbers that this browser sent, but the server did
not confirm yet, as found by me: they flash and are marked, and my score
counts them.
-}
optimistic : Model -> Me -> Game -> Game
optimistic model me game =
    case me of
        Just id ->
            if model.sent >= game.next && not (finished game) then
                let
                    pending number =
                        number >= game.next && number <= model.sent
                in
                { game
                    | cells =
                        List.map
                            (\cell ->
                                if pending cell.number then
                                    { cell | foundBy = Just id }

                                else
                                    cell
                            )
                            game.cells
                    , players =
                        List.map
                            (\player ->
                                if player.id == id then
                                    { player | score = player.score + model.sent - game.next + 1 }

                                else
                                    player
                            )
                            game.players
                }

            else
                game

        Nothing ->
            game


{-| The seconds left in the countdown (3, 2, 1), 0 after it, and Nothing
when no field runs. The step is right only after the clock is in sync.
-}
countdownStep : Model -> Maybe Int
countdownStep model =
    case model.connection of
        Joined _ game ->
            if game.waiting || finished game then
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
        Cmd.batch (List.map schultePlaySound names)


{-| The sounds for the change from the old state to the new one: the start
of the game, a number found by another player, and the end of the game. My
own found numbers play their sound on the click, see `optimistic`.
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

        finders =
            newFinders old new

        foundSound =
            if List.any (\id -> me /= Just id) finders then
                [ "other_found" ]

            else
                []

        endSound =
            if finished new && not (finished old) then
                case winners new.players of
                    [ winner ] ->
                        if isMe me winner then
                            [ "win" ]

                        else
                            [ "lose" ]

                    _ ->
                        [ "lose" ]

            else
                []
    in
    startSound ++ foundSound ++ endSound


{-| The ids of the players who found numbers between the old state and the
new one, in the order of the cells.
-}
newFinders : Game -> Game -> List String
newFinders old new =
    let
        wasFound number =
            List.any (\c -> c.number == number && c.foundBy /= Nothing) old.cells
    in
    new.cells
        |> List.filter (\c -> not (wasFound c.number))
        |> List.filterMap .foundBy


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
        (Decode.field "size" Decode.int)
        (Decode.field "total" Decode.int)
        (Decode.field "next" Decode.int)
        (Decode.field "cells" (Decode.list cellDecoder))
        (Decode.field "players" (Decode.list playerDecoder))
        (Decode.field "elapsed_ms" Decode.int)
        (Decode.field "waiting" Decode.bool)
        (Decode.field "players_needed" Decode.int)
        |> andMap (Decode.field "marks" Decode.bool)
        |> andMap (Decode.field "editing" (Decode.nullable Decode.string))


andMap : Decoder a -> Decoder (a -> b) -> Decoder b
andMap =
    Decode.map2 (|>)


cellDecoder : Decoder Cell
cellDecoder =
    Decode.map2 Cell
        (Decode.field "number" Decode.int)
        (Decode.field "found_by" (Decode.nullable Decode.string))


playerDecoder : Decoder Player
playerDecoder =
    Decode.map5 Player
        (Decode.field "id" Decode.string)
        (Decode.field "name" (Decode.nullable Decode.string))
        (Decode.field "color" Decode.string)
        (Decode.field "color_name" Decode.string)
        (Decode.field "score" Decode.int)



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ schulteJoined GotJoined
        , schulteState GotState
        , schulteJoinFailed GotJoinFailed
        , schulteWatchers GotWatchers
        , Browser.Events.onResize (\w h -> Resized (toFloat w) (toFloat h))
        , case model.connection of
            Joined _ game ->
                -- The numbers come only after the countdown, so no cells
                -- means a countdown. It ticks on each frame, so that the
                -- beeps are on time.
                if not game.waiting && not (finished game) && game.cells == [] then
                    Browser.Events.onAnimationFrame Tick

                else if not game.waiting && not (finished game) then
                    Time.every 100 Tick

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
            p [ id "schulte-connecting", class "py-24 text-center opacity-60" ] [ text "Joining the game…" ]

        Failed reason ->
            p [ id "schulte-failed", class "py-24 text-center text-red-600 dark:text-red-400" ] [ text ("Could not join the game: " ++ reason) ]

        Joined me game ->
            viewGame model me (optimistic model me game)


viewGame : Model -> Me -> Game -> Html Msg
viewGame model me game =
    div
        [ id "schulte-root"
        , class "flex w-full flex-col gap-2 select-none max-lg:landscape:flex-row max-lg:landscape:items-start max-lg:landscape:gap-3 lg:flex-row lg:items-start lg:gap-8"
        , classList [ ( "is-playing", not game.waiting && not (finished game) ) ]
        ]
        [ aside [ id "schulte-panel", class "flex flex-col gap-2 max-lg:landscape:w-48 max-lg:landscape:shrink-0 max-lg:landscape:gap-4 lg:sticky lg:top-6 lg:w-72 lg:shrink-0 lg:gap-5" ]
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
                            [ id "schulte-home"
                            , href "/"
                            , class "mr-1 shrink-0 transition lg:mr-0"
                            ]
                            [ img [ src "/images/mark.svg", alt "octomocto", class "h-8 w-auto dark:hidden lg:h-9" ] []
                            , img [ src "/images/mark-on-dark.svg", alt "octomocto", class "hidden h-8 w-auto dark:block lg:h-9" ] []
                            ]
                        , h1 [ class "truncate text-xl font-semibold tracking-tight lg:text-2xl" ]
                            [ a
                                [ id "schulte-title-link"
                                , href "/schulte"
                                , class "transition hover:text-octo-indigo dark:hover:text-octo-indigo-light"
                                ]
                                [ text "Schulte Table" ]
                            ]
                        , viewWatchers (me == Nothing) model.watchers
                        ]
                    , p [ class "hidden text-sm opacity-60 lg:block" ] [ text "Keep your eyes on the center of the table. Click the numbers in order." ]
                    ]
                , viewClock model game
                , viewMenu (game.editing /= Nothing) model.muted (me /= Nothing)
                ]
            , if game.playersNeeded > 1 then
                viewShareLink model

              else
                text ""
            , if game.playersNeeded > 1 then
                viewScores model me game.players

              else
                text ""
            ]
        , div [ class "min-w-0 flex-1" ] [ viewBoard model me game ]
        ]


{-| The board, with the message of the game over it.
-}
viewBoard : Model -> Me -> Game -> Html Msg
viewBoard model me game =
    div [ class "relative mx-auto", style "width" (fieldWidth model me game) ]
        [ viewField model game
        , if game.waiting then
            viewWaiting game

          else if Maybe.withDefault 0 (countdownStep model) > 0 then
            viewCountdown (Maybe.withDefault 0 (countdownStep model))

          else if finished game then
            viewResult model.settingsUrl model.changeSettingsUrl model.nextGame model.guest me game

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


{-| The height of the page around the board.
On a large screen, it is the 1.5rem padding of the page at the top and at
the bottom. On a small screen, it is the 0.5rem padding of the page at the
top and at the bottom, and the rows of the panel (the compact row, the link
and the scores for a game with more players, and maybe the message for a
watcher) with the 0.5rem gaps between them. The heights of the rows are
approximate, because the scores can wrap. On a small screen that is wider
than tall, the panel is at the left, so only the padding is not for the
board.
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
                46 + 36

               else
                0
              )
            + (if me == Nothing then
                52

               else
                0
              )


{-| The board is square. Make it as wide as possible, but small enough that
it is all on the screen.
-}
fieldWidth : Model -> Me -> Game -> String
fieldWidth model me game =
    "min(100%, calc(100dvh - " ++ String.fromFloat (reservedHeight model me game) ++ "px))"


{-| The number of browsers that only watch the game, when there are any.
-}
viewWatchers : Bool -> Int -> Html Msg
viewWatchers watching count =
    if watching || count > 0 then
        span
            [ id "schulte-watchers"
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


{-| Starts a new field for all players, also during a race. On a small
screen, only the icon shows, but not in the column of a screen that is wider
than tall.
-}
viewMenu : Bool -> Bool -> Bool -> Html Msg
viewMenu locked muted player =
    Html.node "octo-game-menu"
        [ class "relative shrink-0 lg:order-5 lg:self-start"
        , attribute "menu-label" "Menu"
        , attribute "restart-label" "Restart game"
        , attribute "sound-on-label" "Turn the sounds on"
        , attribute "sound-off-label" "Turn the sounds off"
        , attribute "locked" (boolAttribute locked)
        , attribute "muted" (boolAttribute muted)
        , attribute "player" (boolAttribute player)
        , Html.Events.on "octo-restart" (Decode.succeed Restart)
        , Html.Events.on "octo-toggle-mute" (Decode.succeed ToggleMuted)
        ]
        []


nextText : Model -> Game -> String
nextText model game =
    if finished game || expectedNext model game > game.total then
        "✓"

    else
        String.fromInt (expectedNext model game)


viewShareLink : Model -> Html Msg
viewShareLink model =
    div [ class "flex items-center gap-2 rounded-full bg-octo-mist p-1 pl-4 text-sm lg:order-3 ring-1 ring-octo-indigo/20 max-lg:landscape:flex-col max-lg:landscape:items-stretch max-lg:landscape:rounded-2xl max-lg:landscape:p-2 lg:flex-col lg:items-stretch lg:rounded-2xl lg:p-2 lg:pl-2 dark:bg-octo-indigo/15 dark:ring-octo-indigo-light/25" ]
        [ input
            [ id "schulte-link"
            , readonly True
            , value model.gameUrl
            , class "min-w-0 flex-1 truncate bg-transparent text-octo-navy outline-none max-lg:landscape:px-2 max-lg:landscape:py-1 lg:px-2 lg:py-1 dark:text-slate-100"
            ]
            []
        , button
            [ id "schulte-copy-link"
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


{-| The row of the player who found the last number flashes in orange,
but not my own row. The key changes on each found number, so that the row
is made again and the flash starts again.
-}
viewScores : Model -> Me -> List Player -> Html Msg
viewScores model me players =
    Html.Keyed.ul [ id "schulte-scores", class "flex flex-wrap gap-2 max-lg:landscape:flex-col lg:order-4 lg:flex-col" ]
        (List.map
            (\player ->
                let
                    flashing =
                        model.lastFinder == Just player.id && not (isMe me player)
                in
                ( if flashing then
                    player.id ++ "-" ++ String.fromInt model.findCount

                  else
                    player.id
                , li
                    [ id ("schulte-score-" ++ player.id)
                    , class "flex items-center gap-2 rounded-full bg-white px-3 py-1 text-sm text-slate-800 shadow-sm ring-1 ring-slate-200 dark:bg-white/5 dark:text-slate-100 dark:shadow-none dark:ring-white/10"
                    , class
                        (if flashing then
                            "schulte-flash"

                         else
                            ""
                        )
                    ]
                    [ span [ class "size-3 rounded-full", style "background" player.color ] []
                    , span [ class "max-lg:landscape:flex-1 lg:flex-1" ] [ text (playerName me player) ]
                    , span [ class "font-semibold tabular-nums" ] [ text (String.fromInt player.score) ]
                    ]
                )
            )
            players
        )


playerName : Me -> Player -> String
playerName me player =
    if isMe me player then
        Maybe.withDefault player.colorName player.name ++ " (you)"

    else
        Maybe.withDefault player.colorName player.name


{-| The size of a cell, in board units
-}
cellSize : Float
cellSize =
    100


{-| The grid of cells, and the flashes of the found numbers
on top of all cells. The colors are in the CSS, for the light and the dark
theme.
-}
viewField : Model -> Game -> Html Msg
viewField model game =
    let
        side =
            toFloat game.size * cellSize

        -- The board has rounded corners. The cells are clipped to the
        -- rounded shape, and the border is drawn inside its edge, so that
        -- the border follows the corners.
        boardRect inset radius attrs =
            Svg.rect
                ([ SA.x (String.fromFloat inset)
                 , SA.y (String.fromFloat inset)
                 , SA.width (String.fromFloat (side - 2 * inset))
                 , SA.height (String.fromFloat (side - 2 * inset))
                 , SA.rx (String.fromFloat radius)
                 ]
                    ++ attrs
                )
                []

        line x1 y1 x2 y2 =
            Svg.line
                [ SA.x1 (String.fromFloat x1)
                , SA.y1 (String.fromFloat y1)
                , SA.x2 (String.fromFloat x2)
                , SA.y2 (String.fromFloat y2)
                ]
                []

        inner =
            List.map (\i -> toFloat i * cellSize) (List.range 1 (game.size - 1))

        colorOf id =
            game.players
                |> List.filter (\p -> p.id == id)
                |> List.head
                |> Maybe.map .color
                |> Maybe.withDefault "#888"
    in
    Svg.svg
        [ SA.id "schulte-field"
        , SA.viewBox ("0 0 " ++ String.fromFloat side ++ " " ++ String.fromFloat side)
        , SA.class "block h-auto w-full drop-shadow-sm"
        ]
        [ Svg.defs []
            [ Svg.clipPath [ SA.id "schulte-board-shape" ] [ boardRect 0 cornerRadius [] ] ]
        , Svg.g [ SA.clipPath "url(#schulte-board-shape)" ]
            [ boardRect 0 cornerRadius [ SA.class "schulte-board" ]
            , Svg.g [] (List.indexedMap (viewCell game) game.cells)

            -- The flashes are on top of all cells, so that the next cells
            -- do not cover them. Each flash is keyed, so that it runs one
            -- time, when its number is found. The key has the finder, so
            -- that the flash runs again in the right color when another
            -- player was faster than my click (see `optimistic`).
            , Svg.Keyed.node "g"
                [ SA.pointerEvents "none" ]
                (game.cells
                    |> List.indexedMap Tuple.pair
                    |> List.filterMap
                        (\( index, cell ) ->
                            cell.foundBy
                                |> Maybe.map
                                    (\finder ->
                                        ( String.fromInt cell.number ++ "-" ++ finder
                                        , Svg.rect
                                            [ SA.x (String.fromFloat (toFloat (modBy game.size index) * cellSize))
                                            , SA.y (String.fromFloat (toFloat (index // game.size) * cellSize))
                                            , SA.width (String.fromFloat cellSize)
                                            , SA.height (String.fromFloat cellSize)
                                            , SA.fill (colorOf finder)
                                            , SA.class "schulte-hit"
                                            ]
                                            []
                                        )
                                    )
                        )
                )
            , Svg.g [ SA.class "schulte-line", SA.pointerEvents "none" ]
                (List.map (\x -> line x 0 x side) inner ++ List.map (\y -> line 0 y side y) inner)
            , Svg.g [] (List.indexedMap (viewNumber model game) game.cells)
            ]
        , boardRect 1.5 (cornerRadius - 1.5) [ SA.class "schulte-border", SA.fill "none", SA.strokeWidth "3", SA.pointerEvents "none" ]
        ]


{-| The radius of the board corners, in board units.
-}
cornerRadius : Float
cornerRadius =
    18


{-| The time on the left, and the next number (large, in a color that
stands out, under a small "looking for" label) on the right. The next number
is keyed, so that it pops in again when it changes.
-}
viewClock : Model -> Game -> Html Msg
viewClock model game =
    let
        elapsedMs =
            if finished game then
                game.elapsedMs

            else
                max 0 (model.now - model.clockStart)
    in
    div [ id "schulte-clock", class "ml-auto flex gap-4 pr-2 max-lg:landscape:ml-0 max-lg:landscape:gap-6 max-lg:landscape:pr-0 max-lg:landscape:pl-2 lg:order-2 lg:ml-0 lg:grid lg:grid-cols-2 lg:gap-0 lg:divide-x lg:divide-slate-200 lg:rounded-2xl lg:bg-white lg:py-3 lg:pr-0 lg:shadow-sm lg:ring-1 lg:ring-slate-200 dark:lg:divide-white/10 dark:lg:bg-white/5 dark:lg:shadow-none dark:lg:ring-white/10" ]
        [ div [ class "flex flex-col items-center justify-center max-lg:landscape:items-start" ]
            [ span [ class "text-[0.625rem] font-medium tracking-wide text-slate-400 uppercase lg:text-xs" ] [ text "time" ]
            , span [ id "schulte-time", class "text-lg leading-tight font-light text-slate-700 tabular-nums lg:text-3xl dark:text-slate-100" ] [ text (formatTime elapsedMs) ]
            ]
        , div [ class "flex flex-col items-center justify-center max-lg:landscape:items-start" ]
            [ span [ class "text-[0.625rem] font-medium tracking-wide whitespace-nowrap text-slate-400 uppercase lg:text-xs" ] [ text "looking for" ]
            , Html.Keyed.node "span"
                [ class "text-xl leading-tight font-bold text-octo-indigo tabular-nums lg:text-4xl lg:leading-none dark:text-octo-indigo-light" ]
                [ ( nextText model game
                  , span [ id "schulte-next", class "schulte-next inline-block" ] [ text (nextText model game) ]
                  )
                ]
            ]
        ]


{-| Show the time as minutes, seconds and tenths, for example "0:19.4". A
small table takes only some seconds, so the tenths count.
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


{-| The place of the cell with the index in the grid, in board units: the
left and the top edge.
-}
cellPlace : Game -> Int -> ( Float, Float )
cellPlace game index =
    ( toFloat (modBy game.size index) * cellSize, toFloat (index // game.size) * cellSize )


{-| True when the number of the cell is pale: with marks, after it is found.
-}
marked : Game -> Cell -> Bool
marked game cell =
    game.marks && cell.foundBy /= Nothing


{-| The square of a cell, which gets the clicks. Its number is in a layer
above the flashes and the lines, see `viewNumber`.
-}
viewCell : Game -> Int -> Cell -> Svg Msg
viewCell game index cell =
    let
        ( x, y ) =
            cellPlace game index
    in
    Svg.rect
        [ SA.id ("schulte-cell-" ++ String.fromInt cell.number)
        , SA.x (String.fromFloat x)
        , SA.y (String.fromFloat y)
        , SA.width (String.fromFloat cellSize)
        , SA.height (String.fromFloat cellSize)
        , SA.class
            (if marked game cell then
                "schulte-cell schulte-found"

             else
                "schulte-cell"
            )
        , Press.onPress (Pick cell.number)
        ]
        []


{-| Only the number shakes after a wrong click, not the cell.
-}
viewNumber : Model -> Game -> Int -> Cell -> Svg Msg
viewNumber model game index cell =
    let
        ( x, y ) =
            cellPlace game index
    in
    Svg.text_
        [ SA.x (String.fromFloat (x + cellSize / 2))
        , SA.y (String.fromFloat (y + cellSize / 2))
        , SA.dy "0.36em"
        , SA.textAnchor "middle"
        , SA.fontSize "44"
        , SA.fontWeight "600"
        , SA.class
            (String.join " "
                (List.filterMap identity
                    [ Just "schulte-number"
                    , if marked game cell then
                        Just "is-found"

                      else
                        Nothing
                    , if model.shaking == Just cell.number then
                        Just "schulte-shake"

                      else
                        Nothing
                    ]
                )
            )
        , SA.pointerEvents "none"
        ]
        [ Svg.text (String.fromInt cell.number) ]


{-| Covers the empty board until all players are in.
-}
viewWaiting : Game -> Html Msg
viewWaiting game =
    div
        [ id "schulte-waiting"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-3 rounded-2xl bg-octo-navy/80 p-4 text-center text-white"
        ]
        [ p [ class "text-3xl font-semibold" ] [ text "Waiting for players" ]
        , p [ id "schulte-waiting-count", class "text-lg tabular-nums opacity-80" ]
            [ text
                (String.fromInt (List.length game.players)
                    ++ " of "
                    ++ String.fromInt game.playersNeeded
                    ++ " players are in"
                )
            ]
        , p [ class "text-sm opacity-60" ] [ text "Send the link to the other players. The race starts when all of them are in." ]
        ]


{-| The number is keyed, so that it pops in again on each step.
-}
viewCountdown : Int -> Html Msg
viewCountdown seconds =
    div
        [ id "schulte-countdown"
        , class "absolute inset-0 flex items-center justify-center rounded-2xl bg-octo-navy/80"
        ]
        [ Html.Keyed.node "div"
            []
            [ ( String.fromInt seconds
              , p [ class "countdown-pop text-9xl font-bold text-white tabular-nums" ] [ text (String.fromInt seconds) ]
              )
            ]
        ]


viewResult : String -> Maybe String -> NextGame -> Bool -> Me -> Game -> Html Msg
viewResult settingsUrl changeSettingsUrl nextGame guest me game =
    let
        players =
            game.players

        solo =
            List.length players == 1

        message =
            case ( solo, winners players ) of
                ( True, _ ) ->
                    "Done!"

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

        -- The player on the settings page. Nobody can start a game until
        -- that player is back.
        editor =
            game.editing
                |> Maybe.andThen (\editing -> List.head (List.filter (\player -> player.id == editing) players))

        locked =
            editor /= Nothing
    in
    div
        [ id "schulte-result"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-4 rounded-2xl bg-octo-navy/70 p-4 text-white backdrop-blur-sm"
        ]
        [ p [ class "text-3xl font-semibold" ] [ text message ]
        , p [ id "schulte-final-time", class "text-lg tabular-nums opacity-80" ]
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
        , case editor of
            Just player ->
                p [ id "schulte-editing", class "animate-pulse text-sm text-white/80" ]
                    [ text
                        (case player.name of
                            Just name ->
                                name ++ " changes the settings…"

                            Nothing ->
                                "The " ++ player.colorName ++ " player changes the settings…"
                        )
                    ]

            Nothing ->
                text ""
        , if me == Nothing then
            text ""

          else
            div [ class "flex flex-wrap items-center justify-center gap-3" ]
                [ button
                    [ id "schulte-play-again"
                    , class "rounded-full bg-white px-6 py-2.5 font-medium text-octo-indigo shadow-lg transition hover:bg-octo-mist disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:bg-white"
                    , onClick Restart
                    , disabled locked
                    ]
                    [ text "Play again" ]
                , case changeSettingsUrl of
                    Nothing ->
                        text ""

                    Just url ->
                        if locked then
                            span
                                [ id "schulte-change-settings"
                                , attribute "aria-disabled" "true"
                                , class "cursor-not-allowed rounded-full px-5 py-2.5 font-medium text-white opacity-50 ring-1 ring-white/40"
                                ]
                                [ text "Change settings" ]

                        else
                            a
                                [ id "schulte-change-settings"
                                , href url
                                , class "rounded-full px-5 py-2.5 font-medium text-white ring-1 ring-white/40 transition hover:bg-white/10"
                                ]
                                [ text "Change settings" ]
                ]
        , a
            [ id "schulte-leaderboards-link"
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
            [ id "schulte-next-game"
            , action
            , disabled locked
            , attribute "data-ga-link" "or_try"
            , attribute "data-ga-from" "Schulte Table"
            , attribute "data-ga-to" nextGame.name
            , class "group text-sm font-medium text-white underline-offset-4 transition hover:underline disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:no-underline"
            ]
            [ text ("Or try " ++ nextGame.name ++ " ")
            , span [ class "inline-block transition group-hover:translate-x-0.5" ] [ text "→" ]
            ]

        -- Only a guest who played gets the call to sign in, not a spectator
        , if guest && me /= Nothing then
            p [ id "schulte-sign-in", class "text-sm text-white/70" ]
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
    p [ id "schulte-feed", class "mt-2 max-w-sm border-t border-white/15 pt-4 text-center text-sm leading-10 text-balance text-white/80" ]
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


boolAttribute : Bool -> String
boolAttribute value =
    if value then
        "true"

    else
        "false"
