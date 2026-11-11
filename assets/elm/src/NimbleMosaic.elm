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
        |> andMap (Decode.field "editing" (Decode.nullable Decode.string))


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
        arrangement =
            arrange model me game
    in
    div
        [ id "nimble-mosaic-root"
        , attribute "data-layout" (layoutName arrangement.layout)
        , class "flex w-full flex-col gap-2 select-none side:lg:px-6 side:lg:py-4 side:max-lg:flex-row side:max-lg:items-start side:max-lg:gap-3 side:lg:flex-row side:lg:items-start side:lg:gap-8"
        , classList [ ( "is-playing", not game.waiting && not (finished game) ) ]
        ]
        [ aside [ id "nimble-mosaic-panel", class "flex flex-col gap-2 side:max-lg:w-48 side:max-lg:shrink-0 side:max-lg:gap-4 side:lg:sticky side:lg:top-6 side:lg:w-72 side:lg:shrink-0 side:lg:gap-5" ]
            -- In the row layout, the title, the stats and the menu are in one
            -- compact row above the board. In the side layout, they are in a
            -- narrow column at the left of the board, or on a large screen,
            -- the row is not a box (`contents`), so its items are in the
            -- wide column of the panel.
            [ div [ class "flex items-center gap-1 side:max-lg:flex-col side:max-lg:items-start side:max-lg:gap-4 side:lg:contents" ]
                [ div [ class "min-w-0 side:lg:order-1" ]
                    [ div [ class "flex items-center gap-1 side:lg:gap-2" ]
                        [ a
                            [ id "nimble-mosaic-home"
                            , href "/"
                            , class "mr-1 shrink-0 transition side:lg:mr-0"
                            ]
                            [ img [ src "/images/mark.svg", alt "octomocto", class "h-8 w-auto dark:hidden side:lg:h-9" ] []
                            , img [ src "/images/mark-on-dark.svg", alt "octomocto", class "hidden h-8 w-auto dark:block side:lg:h-9" ] []
                            ]
                        , h1 [ class "truncate text-xl font-semibold tracking-tight side:lg:text-2xl" ]
                            [ a
                                [ id "nimble-mosaic-title-link"
                                , href "/nimble-mosaic"
                                , class "transition hover:text-octo-indigo dark:hover:text-octo-indigo-light"
                                ]
                                [ text "Nimble Mosaic" ]
                            ]
                        , viewWatchers (me == Nothing) model.watchers
                        ]
                    , p [ class "hidden text-sm opacity-60 side:lg:block" ] [ text "Click the numbers in order. The first click gets the point." ]
                    ]
                , viewClock model game
                , viewMenu arrangement.layout (game.editing /= Nothing) model.muted (me /= Nothing)
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
        , div [ class "min-w-0 flex-1" ]
            [ viewBoard model me arrangement game ]
        ]


{-| The board, with the message of the game over it.
-}
viewBoard : Model -> Me -> Arrangement -> Game -> Html Msg
viewBoard model me arrangement game =
    div [ class "relative mx-auto", style "width" (fieldWidth model me arrangement game) ]
        [ viewField model arrangement.tall game
        , if game.waiting then
            viewWaiting game

          else if Maybe.withDefault 0 (countdownStep model) > 0 then
            viewCountdown (Maybe.withDefault 0 (countdownStep model))

          else if finished game then
            viewResult model.settingsUrl model.changeSettingsUrl model.nextGame model.guest me game

          else
            text ""
        ]


{-| Where the panel is: in a compact row above the board, or in a column at
the left of the board. The `side:` classes are for the column.
-}
type PanelLayout
    = Row
    | Side


layoutName : PanelLayout -> String
layoutName layout =
    case layout of
        Row ->
            "row"

        Side ->
            "side"


{-| The layout of the page, and if the board is turned (see `viewField`).
-}
type alias Arrangement =
    { layout : PanelLayout
    , tall : Bool
    }


{-| The width of the screen from which the column of the panel is wide (the
`lg:` classes), and from which the board can turn.
-}
largeScreen : Float
largeScreen =
    1024


{-| The arrangement that shows the largest board. Each layout takes a
different part of the screen, so the shape of the screen decides, not its
size. When the two layouts give almost the same board, the column wins,
because it shows more.

The board turns 90 degrees when it is larger turned, but only on a large
screen, for example a tablet. The player turns the tablet to read the
numbers. On a small screen, for example a phone, the board is never turned,
so that the numbers are upright.

-}
arrange : Model -> Me -> Game -> Arrangement
arrange model me game =
    let
        ( width, height ) =
            model.viewport

        large =
            width >= largeScreen

        scale layout tall =
            let
                ( reservedWidth, reservedHeight ) =
                    reserved model me game layout

                ( boardWidth, boardHeight ) =
                    if tall then
                        ( game.height, game.width )

                    else
                        ( game.width, game.height )
            in
            min ((width - reservedWidth) / boardWidth) ((height - reservedHeight) / boardHeight)

        best layout =
            if large && scale layout True > scale layout False then
                ( scale layout True, True )

            else
                ( scale layout False, False )

        ( sideScale, sideTall ) =
            best Side

        ( rowScale, rowTall ) =
            best Row
    in
    if sideScale >= 0.97 * rowScale then
        { layout = Side, tall = sideTall }

    else
        { layout = Row, tall = rowTall }


{-| The width and the height in pixels of the page around the board. The
column of the panel is 18rem wide on a large screen, with the padding of
the page and a 2rem gap, and 12rem wide on a small screen, with a 0.75rem
gap.
-}
reserved : Model -> Me -> Game -> PanelLayout -> ( Float, Float )
reserved model me game layout =
    case layout of
        Side ->
            if Tuple.first model.viewport >= largeScreen then
                ( 384, 48 )

            else
                ( 220, 16 )

        Row ->
            ( 16
            , 16
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
            )


{-| Make the board as wide as possible, but small enough that it is all on
the screen. The height is the one that `arrange` uses, not `100dvh`: Safari
on an iPad keeps the old `dvh` in full screen.
-}
fieldWidth : Model -> Me -> Arrangement -> Game -> String
fieldWidth model me arrangement game =
    let
        ratio =
            if arrangement.tall then
                game.height / game.width

            else
                game.width / game.height

        height =
            Tuple.second model.viewport - Tuple.second (reserved model me game arrangement.layout)
    in
    "min(100%, " ++ String.fromFloat (max 0 height * ratio) ++ "px)"


{-| The number of browsers that only watch the game, when there are any.
-}
viewWatchers : Bool -> Int -> Html Msg
viewWatchers watching count =
    if watching || count > 0 then
        span
            [ id "nimble-mosaic-watchers"
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


{-| Starts a new field for all players, also during a race. In the row
layout, only the icon shows.
-}
viewMenu : PanelLayout -> Bool -> Bool -> Bool -> Html Msg
viewMenu layout locked muted player =
    Html.node "octo-game-menu"
        [ class "relative shrink-0 side:lg:order-5 side:lg:self-start"
        , attribute "layout" (layoutName layout)
        , attribute "fullscreen" "true"
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


nextText : Game -> String
nextText game =
    if finished game then
        "✓"

    else
        String.fromInt game.next


viewShareLink : Model -> Html Msg
viewShareLink model =
    div [ class "flex items-center gap-2 rounded-full bg-octo-mist p-1 pl-4 text-sm side:lg:order-3 ring-1 ring-octo-indigo/20 side:max-lg:flex-col side:max-lg:items-stretch side:max-lg:rounded-2xl side:max-lg:p-2 side:lg:flex-col side:lg:items-stretch side:lg:rounded-2xl side:lg:p-2 side:lg:pl-2 dark:bg-octo-indigo/15 dark:ring-octo-indigo-light/25" ]
        [ input
            [ id "nimble-mosaic-link"
            , readonly True
            , value model.gameUrl
            , class "min-w-0 flex-1 truncate bg-transparent text-octo-navy outline-none side:max-lg:px-2 side:max-lg:py-1 side:lg:px-2 side:lg:py-1 dark:text-slate-100"
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
    Html.Keyed.ul [ id "nimble-mosaic-scores", class "flex flex-wrap gap-2 side:max-lg:flex-col side:lg:order-4 side:lg:flex-col" ]
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
                    , span [ class "side:max-lg:flex-1 side:lg:flex-1" ] [ text (playerName me player) ]
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
    div [ id "nimble-mosaic-clock", class "ml-auto flex gap-4 pr-2 side:max-lg:ml-0 side:max-lg:gap-6 side:max-lg:pr-0 side:max-lg:pl-2 side:lg:order-2 side:lg:ml-0 side:lg:grid side:lg:grid-cols-2 side:lg:gap-0 side:lg:divide-x side:lg:divide-slate-200 side:lg:rounded-2xl side:lg:bg-white side:lg:py-3 side:lg:pr-0 side:lg:shadow-sm side:lg:ring-1 side:lg:ring-slate-200 dark:side:lg:divide-white/10 dark:side:lg:bg-white/5 dark:side:lg:shadow-none dark:side:lg:ring-white/10" ]
        [ div [ class "flex flex-col items-center justify-center side:max-lg:items-start" ]
            [ span [ class "text-[0.625rem] font-medium tracking-wide text-slate-400 uppercase side:lg:text-xs" ] [ text "time" ]
            , span [ id "nimble-mosaic-time", class "text-lg leading-tight font-light text-slate-700 tabular-nums side:lg:text-3xl dark:text-slate-100" ] [ text (formatTime elapsedMs) ]
            ]
        , div [ class "flex flex-col items-center justify-center side:max-lg:items-start" ]
            [ span [ class "text-[0.625rem] font-medium tracking-wide whitespace-nowrap text-slate-400 uppercase side:lg:text-xs" ] [ text "looking for" ]
            , Html.Keyed.node "span"
                [ class "text-xl leading-tight font-bold text-[#d9534f] tabular-nums side:lg:text-4xl side:lg:leading-none dark:text-[#f0807b]" ]
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
        , case editor of
            Just player ->
                p [ id "nimble-mosaic-editing", class "animate-pulse text-sm text-white/80" ]
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
                    [ id "nimble-mosaic-play-again"
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
                                [ id "nimble-mosaic-change-settings"
                                , attribute "aria-disabled" "true"
                                , class "cursor-not-allowed rounded-full px-5 py-2.5 font-medium text-white opacity-50 ring-1 ring-white/40"
                                ]
                                [ text "Change settings" ]

                        else
                            a
                                [ id "nimble-mosaic-change-settings"
                                , href url
                                , class "rounded-full px-5 py-2.5 font-medium text-white ring-1 ring-white/40 transition hover:bg-white/10"
                                ]
                                [ text "Change settings" ]
                ]
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
            , disabled locked
            , attribute "data-ga-link" "or_try"
            , attribute "data-ga-from" "Nimble Mosaic"
            , attribute "data-ga-to" nextGame.name
            , class "group text-sm font-medium text-white underline-offset-4 transition hover:underline disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:no-underline"
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


{-| The link to the page to support Octomocto, at the bottom of a result.
The link opens in a new tab, so that the player stays in the game.
-}
viewFeed : Html msg
viewFeed =
    p [ id "nimble-mosaic-feed", class "mt-2 max-w-sm border-t border-white/15 pt-4 text-center text-sm leading-10 text-balance text-white/80" ]
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
