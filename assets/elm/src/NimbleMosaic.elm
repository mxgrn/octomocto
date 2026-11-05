port module NimbleMosaic exposing (main)

{-| Multiplayer Nimble Mosaic race.

The server owns the game: the field with the numbers 1 to 90, the next
number and the scores. The first player to click the next number gets a
point, and the number disappears for all players. This module draws the
state that comes in through ports and sends the player's clicks out.
app.js connects the ports to a Phoenix channel.

A click on a wrong number does nothing, but its number shakes for this
player only.

The module compares each new state with the old one and sends the names
of the sounds to play out through a port. The player can mute the sounds.

The game is for a set number of players. Before all of them are in, the
board is hidden and nobody can pick. A countdown with beeps comes before
each field. A browser that joins a full game only
watches: it has no player id.

The port names start with "nimble-mosaic", because Elm does not allow two ports
with the same name in one bundle.

-}

import Browser
import Browser.Dom
import Browser.Events
import GameBar
import Html exposing (Html, a, aside, button, div, h1, img, input, li, ol, p, span, text, ul)
import Html.Attributes exposing (alt, attribute, class, classList, href, id, readonly, rel, src, style, target, value)
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


port nimbleMosaicPick : Int -> Cmd msg


port nimbleMosaicRestart : () -> Cmd msg


{-| Starts the next game for all players, see OctomoctoWeb.NextGame
-}
port nimbleMosaicNextGame : () -> Cmd msg


port nimbleMosaicCopyText : String -> Cmd msg


port nimbleMosaicJoined : (Decode.Value -> msg) -> Sub msg


port nimbleMosaicState : (Decode.Value -> msg) -> Sub msg


port nimbleMosaicJoinFailed : (String -> msg) -> Sub msg


{-| The number of browsers that only watch the game, after the join and
after each change.
-}
port nimbleMosaicWatchers : (Int -> msg) -> Sub msg


port nimbleMosaicPlaySound : String -> Cmd msg


port nimbleMosaicSaveMuted : Bool -> Cmd msg



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


{-| A region of the board. `d` is its SVG path, and the number is
stretched to fill the `label` box.
-}
type alias Cell =
    { number : Int
    , d : String
    , label : Label
    , color : String
    , foundBy : Maybe String
    }


type alias Label =
    { x : Float
    , y : Float
    , w : Float
    , h : Float
    }


type alias Game =
    { width : Float
    , height : Float
    , total : Int
    , next : Int
    , cells : List Cell
    , players : List Player

    -- How narrow a number can get, as a part of its normal width
    , minStretch : Float

    -- The time since the field started. After the end, the final time.
    , elapsedMs : Int

    -- True until the game has all its players. The cells are empty then.
    , waiting : Bool
    , playersNeeded : Int

    -- True in the easy mode. In the normal mode, the found numbers stay.
    , hidesFound : Bool
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

    -- The number that shakes after a wrong click. The count makes sure
    -- that only the newest timeout stops the shake.
    , shaking : Maybe Int
    , shakeCount : Int

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
      , shaking = Nothing
      , shakeCount = 0
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
                    ( { model | connection = Joined me game }, syncClock game )

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
                    in
                    ( { withFinder | connection = Joined me game }
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

                    else if number == game.next then
                        ( model, nimbleMosaicPick number )

                    else if number > game.next || not game.hidesFound then
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
            ( model, nimbleMosaicRestart () )

        StartNextGame ->
            ( model, nimbleMosaicNextGame () )

        CopyLink ->
            ( { model | copied = True }
            , Cmd.batch
                [ nimbleMosaicCopyText model.gameUrl
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
            ( { model | muted = not model.muted }, nimbleMosaicSaveMuted (not model.muted) )


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
        Cmd.batch (List.map nimbleMosaicPlaySound names)


{-| The sounds for the change from the old state to the new one: the start
of the game, a found number (by this player or by another one), and the end
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

        finders =
            newFinders old new

        foundSound =
            if List.any (\id -> me == Just id) finders then
                [ "found" ]

            else if finders /= [] then
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
        (Decode.field "board" (Decode.index 0 Decode.float))
        (Decode.field "board" (Decode.index 1 Decode.float))
        (Decode.field "total" Decode.int)
        (Decode.field "next" Decode.int)
        (Decode.field "cells" (Decode.list cellDecoder))
        (Decode.field "players" (Decode.list playerDecoder))
        (Decode.field "min_stretch" Decode.float)
        (Decode.field "elapsed_ms" Decode.int)
        |> andMap (Decode.field "waiting" Decode.bool)
        |> andMap (Decode.field "players_needed" Decode.int)
        |> andMap (Decode.field "mode" (Decode.map ((==) "easy") Decode.string))


andMap : Decoder a -> Decoder (a -> b) -> Decoder b
andMap =
    Decode.map2 (|>)


cellDecoder : Decoder Cell
cellDecoder =
    Decode.map5 Cell
        (Decode.field "number" Decode.int)
        (Decode.field "d" Decode.string)
        (Decode.field "label" labelDecoder)
        (Decode.field "color" Decode.string)
        (Decode.field "found_by" (Decode.nullable Decode.string))


labelDecoder : Decoder Label
labelDecoder =
    Decode.map4 Label
        (Decode.index 0 Decode.float)
        (Decode.index 1 Decode.float)
        (Decode.index 2 Decode.float)
        (Decode.index 3 Decode.float)


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
        [ nimbleMosaicJoined GotJoined
        , nimbleMosaicState GotState
        , nimbleMosaicJoinFailed GotJoinFailed
        , nimbleMosaicWatchers GotWatchers
        , Browser.Events.onResize (\w h -> Resized (toFloat w) (toFloat h))
        , case model.connection of
            Joined _ game ->
                -- The numbers come only after the countdown, so no cells
                -- means a countdown. It ticks on each frame, so that the
                -- beeps are on time.
                if not game.waiting && not (finished game) && game.cells == [] then
                    Browser.Events.onAnimationFrame Tick

                else if not game.waiting && not (finished game) then
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
            p [ id "nimble-mosaic-connecting", class "py-24 text-center opacity-60" ] [ text "Joining the game…" ]

        Failed reason ->
            p [ id "nimble-mosaic-failed", class "py-24 text-center text-red-600 dark:text-red-400" ] [ text ("Could not join the game: " ++ reason) ]

        Joined me game ->
            viewGame model me game


viewGame : Model -> Me -> Game -> Html Msg
viewGame model me game =
    let
        tall =
            isTall model me game
    in
    div
        [ id "nimble-mosaic-root"
        , class "flex w-full flex-col gap-2 select-none max-lg:landscape:flex-row max-lg:landscape:items-start max-lg:landscape:gap-3 lg:flex-row lg:items-start lg:gap-8"
        , classList [ ( "is-playing", not game.waiting && not (finished game) ) ]
        ]
        [ aside [ id "nimble-mosaic-panel", class "flex flex-col gap-2 max-lg:landscape:w-48 max-lg:landscape:shrink-0 max-lg:landscape:gap-4 lg:sticky lg:top-6 lg:w-72 lg:shrink-0 lg:gap-5" ]
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
                            [ id "nimble-mosaic-home"
                            , href "/"
                            , class "mr-1 shrink-0 transition lg:mr-0"
                            ]
                            [ img [ src "/images/mark.svg", alt "octomocto", class "h-8 w-auto dark:hidden lg:h-9" ] []
                            , img [ src "/images/mark-on-dark.svg", alt "octomocto", class "hidden h-8 w-auto dark:block lg:h-9" ] []
                            ]
                        , h1 [ class "truncate text-xl font-semibold tracking-tight lg:text-2xl" ]
                            [ a
                                [ id "nimble-mosaic-title-link"
                                , href "/nimble-mosaic"
                                , class "transition hover:text-octo-indigo dark:hover:text-octo-indigo-light"
                                ]
                                [ text "Nimble Mosaic" ]
                            ]
                        , viewWatchers model.watchers
                        ]
                    , p [ class "hidden text-sm opacity-60 lg:block" ] [ text "Click the numbers in order. The first click gets the point." ]
                    ]
                , viewClock model game
                , viewMenu model.muted (me /= Nothing)
                ]
            , if game.playersNeeded > 1 then
                viewShareLink model

              else
                text ""
            , if game.playersNeeded > 1 then
                viewScores model me game.players

              else
                text ""
            , if me == Nothing then
                p [ id "nimble-mosaic-watching", class "rounded-2xl bg-amber-50 px-4 py-3 text-sm text-amber-900 ring-1 ring-amber-200 lg:order-5 dark:bg-amber-400/10 dark:text-amber-200 dark:ring-amber-400/25" ]
                    [ text "This game is full, so you can only watch it." ]

              else
                text ""
            ]
        , div [ class "min-w-0 flex-1" ]
            [ viewBoard model me tall game ]
        ]


{-| The board, with the message of the game over it.
-}
viewBoard : Model -> Me -> Bool -> Game -> Html Msg
viewBoard model me tall game =
    div [ class "relative mx-auto", style "width" (fieldWidth model me tall game) ]
        [ viewField model tall game
        , if game.waiting then
            viewWaiting game

          else if Maybe.withDefault 0 (countdownStep model) > 0 then
            viewCountdown (Maybe.withDefault 0 (countdownStep model))

          else if finished game then
            viewResult model.settingsUrl model.nextGame model.guest me game

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


{-| The width and the height in pixels of the space for the board. On a
large screen, the panel is at the left of the board. On a small screen that
is wider than tall, the 12rem panel is at the left with a 0.75rem gap.
-}
boardSpace : Model -> Me -> Game -> ( Float, Float )
boardSpace model me game =
    let
        ( width, height ) =
            model.viewport
    in
    ( if width >= largeScreen then
        width - 384

      else if sideways model then
        width - 220

      else
        width - 16
    , height - reservedHeight model me game
    )


{-| The height in pixels of the screen that is not for the board. On a large
screen, it is the 1.5rem padding of the page at the top and at the bottom.
The page of a game has no header and no footer. On a small screen, it is the 0.5rem padding of the page at the
top and at the bottom, and the rows of the panel (the compact row, the link
and the scores for a game with more players, and maybe the message for a
watcher) with the 0.5rem gaps between them. The heights of the rows are approximate, because the scores can wrap. On a small screen that is wider
than tall, the panel is at the left, so only the padding is not for the
board.
-}
reservedHeight : Model -> Me -> Game -> Float
reservedHeight model me game =
    GameBar.height + reservedPageHeight model me game


{-| The height of the page around the field, without the bar at the top.
-}
reservedPageHeight : Model -> Me -> Game -> Float
reservedPageHeight model me game =
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


{-| True when the board is larger turned 90 degrees, so that it is taller
than wide. This is on a large screen that is taller than wide, for example
a tablet. The player turns the tablet to read the numbers. On a small
screen, for example a phone, the board is never turned, so that the
numbers are upright.
-}
isTall : Model -> Me -> Game -> Bool
isTall model me game =
    let
        ( width, height ) =
            boardSpace model me game
    in
    Tuple.first model.viewport
        >= largeScreen
        && min (width / game.height) (height / game.width)
        > min (width / game.width) (height / game.height)


{-| Make the board as wide as possible, but small enough that it is all on
the screen.
-}
fieldWidth : Model -> Me -> Bool -> Game -> String
fieldWidth model me tall game =
    let
        ratio =
            if tall then
                game.height / game.width

            else
                game.width / game.height
    in
    "min(100%, calc((100dvh - "
        ++ String.fromFloat (reservedHeight model me game)
        ++ "px) * "
        ++ String.fromFloat ratio
        ++ "))"


{-| The number of browsers that only watch the game, when there are any.
-}
viewWatchers : Int -> Html Msg
viewWatchers count =
    if count > 0 then
        span
            [ id "nimble-mosaic-watchers"
            , class "flex shrink-0 items-center gap-1 text-sm tabular-nums text-slate-500 dark:text-slate-400"
            , Html.Attributes.title ("Watchers: " ++ String.fromInt count)
            ]
            [ span [ class "hero-eye size-4" ] [], text (String.fromInt count) ]

    else
        text ""



{-| Starts a new field for all players, also during a race. On a small
screen, only the icon shows, but not in the column of a screen that is wider
than tall.
-}
viewMenu : Bool -> Bool -> Html Msg
viewMenu muted player =
    Html.node "octo-game-menu"
        [ class "relative shrink-0 lg:order-5 lg:self-start"
        , attribute "menu-label" "Menu"
        , attribute "restart-label" "Restart game"
        , attribute "sound-on-label" "Turn the sounds on"
        , attribute "sound-off-label" "Turn the sounds off"
        , attribute "muted" (boolAttribute muted)
        , attribute "player" (boolAttribute player)
        , Html.Events.on "octo-restart" (Decode.succeed Restart)
        , Html.Events.on "octo-toggle-mute" (Decode.succeed ToggleMuted)
        ]
        []


nextText : Game -> String
nextText game =
    if finished game then
        "✓"

    else
        String.fromInt game.next


viewShareLink : Model -> Html Msg
viewShareLink model =
    div [ class "flex items-center gap-2 rounded-full bg-octo-mist p-1 pl-4 text-sm lg:order-3 ring-1 ring-octo-indigo/20 max-lg:landscape:flex-col max-lg:landscape:items-stretch max-lg:landscape:rounded-2xl max-lg:landscape:p-2 lg:flex-col lg:items-stretch lg:rounded-2xl lg:p-2 lg:pl-2 dark:bg-octo-indigo/15 dark:ring-octo-indigo-light/25" ]
        [ input
            [ id "nimble-mosaic-link"
            , readonly True
            , value model.gameUrl
            , class "min-w-0 flex-1 truncate bg-transparent text-octo-navy outline-none max-lg:landscape:px-2 max-lg:landscape:py-1 lg:px-2 lg:py-1 dark:text-slate-100"
            ]
            []
        , button
            [ id "nimble-mosaic-copy-link"
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
    Html.Keyed.ul [ id "nimble-mosaic-scores", class "flex flex-wrap gap-2 max-lg:landscape:flex-col lg:order-4 lg:flex-col" ]
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
                    [ id ("nimble-mosaic-score-" ++ player.id)
                    , class "flex items-center gap-2 rounded-full bg-white px-3 py-1 text-sm text-slate-800 shadow-sm ring-1 ring-slate-200 dark:bg-white/5 dark:text-slate-100 dark:shadow-none dark:ring-white/10"
                    , class
                        (if flashing then
                            "nimble-mosaic-flash"

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


{-| The board. When it is tall, all of it (the cells and the numbers) is
turned 90 degrees clockwise: the top of the board is at the right.
-}
viewField : Model -> Bool -> Game -> Html Msg
viewField model tall game =
    let
        viewBox =
            if tall then
                "0 0 " ++ String.fromFloat game.height ++ " " ++ String.fromFloat game.width

            else
                "0 0 " ++ String.fromFloat game.width ++ " " ++ String.fromFloat game.height

        turn =
            if tall then
                [ SA.transform ("matrix(0 1 -1 0 " ++ String.fromFloat game.height ++ " 0)") ]

            else
                []

        -- The board has rounded corners. The cells are clipped to the
        -- rounded shape, and the border is drawn inside its edge, so that
        -- the border follows the corners.
        boardRect inset radius attrs =
            Svg.rect
                ([ SA.x (String.fromFloat inset)
                 , SA.y (String.fromFloat inset)
                 , SA.width (String.fromFloat (game.width - 2 * inset))
                 , SA.height (String.fromFloat (game.height - 2 * inset))
                 , SA.rx (String.fromFloat radius)
                 ]
                    ++ attrs
                )
                []
    in
    Svg.svg
        [ SA.id "nimble-mosaic-field"
        , SA.viewBox viewBox
        , SA.class "block h-auto w-full drop-shadow-sm"
        , SA.strokeLinejoin "round"
        ]
        [ Svg.g turn
            [ Svg.defs []
                [ Svg.clipPath [ SA.id "nimble-mosaic-board-shape" ] [ boardRect 0 cornerRadius [] ] ]
            , Svg.g [ SA.clipPath "url(#nimble-mosaic-board-shape)" ]
                (boardRect 0 cornerRadius [ SA.fill "#fbf5e1" ]
                    :: List.map (viewCell model game) game.cells
                    -- The bursts are on top of all the cells, so that the
                    -- next cells do not cover the particles
                    ++ [ Svg.Keyed.node "g"
                            [ SA.pointerEvents "none" ]
                            (game.cells
                                |> List.filter (\cell -> cell.foundBy /= Nothing)
                                |> List.map (\cell -> ( String.fromInt cell.number, viewBurst cell ))
                            )
                       ]
                )
            , boardRect 1.5
                (cornerRadius - 1.5)
                [ SA.fill "none"
                , SA.stroke ink
                , SA.strokeWidth "3"
                , SA.pointerEvents "none"
                ]
            ]
        ]


{-| The radius of the board corners, in board units.
-}
cornerRadius : Float
cornerRadius =
    18


ink : String
ink =
    "#474d50"


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
    div [ id "nimble-mosaic-clock", class "ml-auto flex gap-4 pr-2 max-lg:landscape:ml-0 max-lg:landscape:gap-6 max-lg:landscape:pr-0 max-lg:landscape:pl-2 lg:order-2 lg:ml-0 lg:grid lg:grid-cols-2 lg:gap-0 lg:divide-x lg:divide-slate-200 lg:rounded-2xl lg:bg-white lg:py-3 lg:pr-0 lg:shadow-sm lg:ring-1 lg:ring-slate-200 dark:lg:divide-white/10 dark:lg:bg-white/5 dark:lg:shadow-none dark:lg:ring-white/10" ]
        [ div [ class "flex flex-col items-center justify-center max-lg:landscape:items-start" ]
            [ span [ class "text-[0.625rem] font-medium tracking-wide text-slate-400 uppercase lg:text-xs" ] [ text "time" ]
            , span [ id "nimble-mosaic-time", class "text-lg leading-tight font-light text-slate-700 tabular-nums lg:text-3xl dark:text-slate-100" ] [ text (formatTime elapsedMs) ]
            ]
        , div [ class "flex flex-col items-center justify-center max-lg:landscape:items-start" ]
            [ span [ class "text-[0.625rem] font-medium tracking-wide whitespace-nowrap text-slate-400 uppercase lg:text-xs" ] [ text "looking for" ]
            , Html.Keyed.node "span"
                [ class "text-xl leading-tight font-bold text-[#d9534f] tabular-nums lg:text-4xl lg:leading-none dark:text-[#f0807b]" ]
                [ ( nextText game
                  , span [ id "nimble-mosaic-next", class "nimble-mosaic-next inline-block" ] [ text (nextText game) ]
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


{-| In the normal mode, a found cell looks the same as the other cells.
-}
viewCell : Model -> Game -> Cell -> Svg Msg
viewCell model game cell =
    let
        found =
            game.hidesFound && cell.foundBy /= Nothing

        minStretch =
            game.minStretch
    in
    Svg.g
        [ SA.id ("nimble-mosaic-cell-" ++ String.fromInt cell.number)
        , SA.class
            (if found then
                "nimble-mosaic-cell nimble-mosaic-found"

             else
                "nimble-mosaic-cell"
            )
        , Press.onPress (Pick cell.number)
        ]
        [ Svg.path [ SA.d cell.d, SA.fill cell.color, SA.fillRule "evenodd", SA.stroke ink, SA.strokeWidth "3" ] []
        , if found then
            -- The found number grows and fades out one time
            Svg.g [ SA.class "nimble-mosaic-pop" ] [ viewNumber minStretch cell ]

          else
            -- Only the number shakes after a wrong click, not the cell
            Svg.g
                [ SA.class
                    (if model.shaking == Just cell.number then
                        "nimble-mosaic-shake"

                     else
                        ""
                    )
                ]
                [ viewNumber minStretch cell ]
        ]


{-| Dots that fly out to all sides from the center of a found number.
The animation is in the CSS. It runs one time, when the burst is added.
-}
viewBurst : Cell -> Svg msg
viewBurst cell =
    let
        { x, y, w, h } =
            cell.label

        count =
            64

        -- A fixed "random" number from 0 to 1 for each dot and each use,
        -- so that the dots are scattered but do not change on each render
        scatter i salt =
            let
                v =
                    sin (toFloat cell.number * 12.9898 + toFloat i * 78.233 + salt) * 43758.5453
            in
            v - toFloat (floor v)

        dot i =
            let
                -- Each dot gets a random angle inside its own part of the
                -- circle, so that the dots go to all sides
                angle =
                    2 * pi * (toFloat i + scatter i 1) / count

                -- In board units, the same for all cells
                distance =
                    60 + 90 * scatter i 2

                radius =
                    3 + 4 * scatter i 3
            in
            Svg.circle
                [ SA.cx (String.fromFloat (x + w / 2))
                , SA.cy (String.fromFloat (y + h / 2))
                , SA.r (String.fromFloat radius)
                , SA.fill ink
                , SA.class "nimble-mosaic-particle"
                , SA.style
                    ("--dx: "
                        ++ String.fromFloat (distance * cos angle)
                        ++ "px; --dy: "
                        ++ String.fromFloat (distance * sin angle)
                        ++ "px"
                    )
                ]
                []
    in
    Svg.g [] (List.map dot (List.range 0 (count - 1)))


{-| Stretch the number to fill its label box, like the tall narrow and the
wide numbers in a printed puzzle. The stretch is kept between `minStretch` and
3 times the normal width, so that the digits stay readable.
-}
viewNumber : Float -> Cell -> Svg msg
viewNumber minStretch cell =
    let
        { x, y, w, h } =
            cell.label

        digits =
            toFloat (String.length (String.fromInt cell.number))

        -- Digit width and cap height, as parts of the font size
        digitWidth =
            0.5

        capHeight =
            0.72

        fullSize =
            h / capHeight

        size =
            min fullSize (w / (minStretch * digitWidth * digits))

        width =
            min w (3 * digitWidth * digits * size)
    in
    Svg.text_
        [ SA.x (String.fromFloat (x + w / 2))
        , SA.y (String.fromFloat (y + h / 2 + capHeight * size / 2))
        , SA.textAnchor "middle"
        , SA.fontSize (String.fromFloat size)
        , SA.textLength (String.fromFloat width)
        , SA.lengthAdjust "spacingAndGlyphs"
        , SA.fontFamily "'Arial Narrow', 'Roboto Condensed', 'Helvetica Neue', Arial, sans-serif"
        , SA.fontWeight "700"
        , SA.fill ink
        , SA.pointerEvents "none"
        ]
        [ Svg.text (String.fromInt cell.number) ]


{-| Covers the empty board until all players are in.
-}
viewWaiting : Game -> Html Msg
viewWaiting game =
    div
        [ id "nimble-mosaic-waiting"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-3 rounded-2xl bg-octo-navy/80 p-4 text-center text-white"
        ]
        [ p [ class "text-3xl font-semibold" ] [ text "Waiting for players" ]
        , p [ id "nimble-mosaic-waiting-count", class "text-lg tabular-nums opacity-80" ]
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
        [ id "nimble-mosaic-countdown"
        , class "absolute inset-0 flex items-center justify-center rounded-2xl bg-octo-navy/80"
        ]
        [ Html.Keyed.node "div"
            []
            [ ( String.fromInt seconds
              , p [ class "countdown-pop text-9xl font-bold text-white tabular-nums" ] [ text (String.fromInt seconds) ]
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
    in
    div
        [ id "nimble-mosaic-result"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-4 rounded-2xl bg-octo-navy/70 p-4 text-white backdrop-blur-sm"
        ]
        [ p [ class "text-3xl font-semibold" ] [ text message ]
        , p [ id "nimble-mosaic-final-time", class "text-lg tabular-nums opacity-80" ]
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
                [ id "nimble-mosaic-play-again"
                , class "rounded-full bg-white px-6 py-2.5 font-medium text-octo-indigo shadow-lg transition hover:bg-octo-mist"
                , onClick Restart
                ]
                [ text "Play again" ]
        , a
            [ id "nimble-mosaic-leaderboards-link"
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
            [ id "nimble-mosaic-next-game"
            , action
            , attribute "data-ga-link" "or_try"
            , attribute "data-ga-from" "Nimble Mosaic"
            , attribute "data-ga-to" nextGame.name
            , class "group text-sm font-medium text-white underline-offset-4 transition hover:underline"
            ]
            [ text ("Or try " ++ nextGame.name ++ " ")
            , span [ class "inline-block transition group-hover:translate-x-0.5" ] [ text "→" ]
            ]

        -- Only a guest who played gets the call to sign in, not a spectator
        , if guest && me /= Nothing then
            p [ id "nimble-mosaic-sign-in", class "text-sm text-white/70" ]
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
    p [ id "nimble-mosaic-feed", class "mt-2 max-w-sm border-t border-white/15 pt-4 text-center text-sm leading-10 text-balance text-white/80" ]
        [ text "Enjoying Octomocto? "
        , a
            [ href "https://patreon.com/mxgrn"
            , target "_blank"
            , rel "noopener"
            , class "group mx-1 inline-flex items-center gap-1.5 whitespace-nowrap rounded-full bg-octo-orange px-4 py-1.5 align-middle leading-5 font-semibold text-white shadow-lg shadow-octo-orange/30 transition hover:bg-octo-orange-light"
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


boolAttribute : Bool -> String
boolAttribute value =
    if value then
        "true"

    else
        "false"
