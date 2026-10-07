port module Schulte exposing (main)

{-| Multiplayer Schulte table race.

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
board is hidden and nobody can pick. A browser that joins a full game only
watches: it has no player id.

The port names start with "schulte", because Elm does not allow two ports
with the same name in one bundle.

-}

import Browser
import Html exposing (Html, a, aside, button, div, h1, input, li, ol, p, span, text, ul)
import Html.Attributes exposing (class, href, id, readonly, style, value)
import Html.Events exposing (onClick)
import Json.Decode as Decode exposing (Decoder)
import Process
import Svg exposing (Svg)
import Svg.Attributes as SA
import Svg.Events as SE
import Task
import Time



-- PORTS


port schultePick : Int -> Cmd msg


port schulteRestart : () -> Cmd msg


port schulteCopyText : String -> Cmd msg


port schulteJoined : (Decode.Value -> msg) -> Sub msg


port schulteState : (Decode.Value -> msg) -> Sub msg


port schulteJoinFailed : (String -> msg) -> Sub msg


port schultePlaySound : String -> Cmd msg


port schulteSaveMuted : Bool -> Cmd msg



-- MODEL


type alias Player =
    { id : String
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

    -- The box for the time and the next number
    , infoBox : Maybe Label

    -- True until the game has all its players. The cells are empty then.
    , waiting : Bool
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


type alias Model =
    { gameUrl : String
    , connection : Connection
    , copied : Bool

    -- The number that shakes after a wrong click. The count makes sure
    -- that only the newest timeout stops the shake.
    , shaking : Maybe Int
    , shakeCount : Int

    -- The local time (in ms) when the field started, and the local time
    -- now. The clock ticks between the server updates.
    , clockStart : Int
    , now : Int
    , muted : Bool
    }


type alias Flags =
    { gameUrl : String
    , muted : Bool
    }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { gameUrl = flags.gameUrl
      , connection = Connecting
      , copied = False
      , shaking = Nothing
      , shakeCount = 0
      , clockStart = 0
      , now = 0
      , muted = flags.muted
      }
    , Cmd.none
    )


finished : Game -> Bool
finished game =
    game.next > game.total



-- UPDATE


type Msg
    = GotJoined Decode.Value
    | GotState Decode.Value
    | GotJoinFailed String
    | Pick Int
    | ShakeDone Int
    | Restart
    | CopyLink
    | CopiedTimeout
    | SyncClock Int Time.Posix
    | Tick Time.Posix
    | ToggleMuted


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
                    ( { model | connection = Joined me game }
                    , Cmd.batch [ syncClock game, playSounds model (stateSounds me old game) ]
                    )

                _ ->
                    ( model, Cmd.none )

        GotJoinFailed reason ->
            ( { model | connection = Failed reason }, Cmd.none )

        Pick number ->
            case model.connection of
                Joined (Just _) game ->
                    if game.waiting then
                        ( model, Cmd.none )

                    else if number == game.next then
                        ( model, schultePick number )

                    else if number > game.next then
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
            ( { model | clockStart = ms - elapsedMs, now = ms }, Cmd.none )

        Tick time ->
            ( { model | now = Time.posixToMillis time }, Cmd.none )

        ToggleMuted ->
            ( { model | muted = not model.muted }, schulteSaveMuted (not model.muted) )


playSounds : Model -> List String -> Cmd Msg
playSounds model names =
    if model.muted then
        Cmd.none

    else
        Cmd.batch (List.map schultePlaySound names)


{-| The sounds for the change from the old state to the new one: a found
number (by this player or by another one), and the end of the game.
-}
stateSounds : Me -> Game -> Game -> List String
stateSounds me old new =
    let
        wasFound number =
            List.any (\c -> c.number == number && c.foundBy /= Nothing) old.cells

        newFinders =
            new.cells
                |> List.filter (\c -> not (wasFound c.number))
                |> List.filterMap .foundBy

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
    (if List.any (\id -> me == Just id) newFinders then
        [ "found" ]

     else if newFinders /= [] then
        [ "other_found" ]

     else
        []
    )
        ++ endSound


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
        |> andMap (Decode.field "info_box" (Decode.nullable labelDecoder))
        |> andMap (Decode.field "waiting" Decode.bool)
        |> andMap (Decode.field "players_needed" Decode.int)


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
    Decode.map4 Player
        (Decode.field "id" Decode.string)
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
        , case model.connection of
            Joined _ game ->
                if game.infoBox /= Nothing && not game.waiting && not (finished game) then
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
            p [ id "schulte-connecting", class "py-24 text-center opacity-60" ] [ text "Joining the game…" ]

        Failed reason ->
            p [ id "schulte-failed", class "py-24 text-center text-red-600" ] [ text ("Could not join the game: " ++ reason) ]

        Joined me game ->
            viewGame model me game


viewGame : Model -> Me -> Game -> Html Msg
viewGame model me game =
    div [ id "schulte-root", class "flex w-full max-w-[1400px] flex-col gap-5 select-none lg:flex-row lg:items-start lg:gap-8" ]
        [ aside [ id "schulte-panel", class "flex flex-col gap-5 lg:sticky lg:top-6 lg:w-72 lg:shrink-0" ]
            [ div [ class "flex items-end justify-between gap-4 lg:flex-col lg:items-start" ]
                [ div []
                    [ div [ class "flex items-center gap-2" ]
                        [ h1 [ class "text-2xl font-semibold tracking-tight" ]
                            [ a
                                [ id "schulte-title-link"
                                , href "/schulte"
                                , class "transition hover:text-emerald-600"
                                ]
                                [ text "Schulte Race" ]
                            ]
                        , viewMuteButton model.muted
                        ]
                    , p [ class "text-sm opacity-60" ] [ text "Click the numbers in order. The first click gets the point." ]
                    ]
                ]
            , viewShareLink model
            , viewScores me game.players
            , if me == Nothing then
                p [ id "schulte-watching", class "rounded-2xl bg-amber-50 px-4 py-3 text-sm text-amber-900 ring-1 ring-amber-200" ]
                    [ text "This game is full, so you can only watch it." ]

              else
                text ""
            ]
        , div [ class "min-w-0 flex-1" ]
            [ div [ class "relative mx-auto", style "width" (fieldWidth game) ]
                [ viewField model game
                , if game.waiting then
                    viewWaiting game

                  else if finished game then
                    viewResult me game

                  else
                    text ""
                ]
            ]
        ]


{-| Make the board as wide as possible, but never taller than the screen
(minus the 3rem header and the 1.5rem bottom padding of the page).
-}
fieldWidth : Game -> String
fieldWidth game =
    "min(100%, calc((100dvh - 4.5rem) * " ++ String.fromFloat (game.width / game.height) ++ "))"


viewMuteButton : Bool -> Html Msg
viewMuteButton muted =
    button
        [ id "schulte-mute"
        , class "grid size-8 place-items-center rounded-full text-slate-500 transition hover:bg-slate-100 hover:text-slate-800 active:scale-90"
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


nextText : Game -> String
nextText game =
    if finished game then
        "✓"

    else
        String.fromInt game.next


viewShareLink : Model -> Html Msg
viewShareLink model =
    div [ class "flex items-center gap-2 rounded-full bg-emerald-50 p-1 pl-4 text-sm ring-1 ring-emerald-200 lg:flex-col lg:items-stretch lg:rounded-2xl lg:p-2 lg:pl-2" ]
        [ input
            [ id "schulte-link"
            , readonly True
            , value model.gameUrl
            , class "min-w-0 flex-1 truncate bg-transparent text-emerald-900 outline-none lg:px-2 lg:py-1"
            ]
            []
        , button
            [ id "schulte-copy-link"
            , class "rounded-full bg-emerald-600 px-4 py-1.5 font-medium text-white transition hover:bg-emerald-500 active:scale-95"
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


viewScores : Me -> List Player -> Html Msg
viewScores me players =
    ul [ id "schulte-scores", class "flex flex-wrap gap-2 lg:flex-col" ]
        (List.map
            (\player ->
                li
                    [ id ("schulte-score-" ++ player.id)
                    , class "flex items-center gap-2 rounded-full bg-white px-3 py-1 text-sm text-slate-800 shadow-sm ring-1 ring-slate-200"
                    ]
                    [ span [ class "size-3 rounded-full", style "background" player.color ] []
                    , span [ class "lg:flex-1" ] [ text (playerName me player) ]
                    , span [ class "font-semibold tabular-nums" ] [ text (String.fromInt player.score) ]
                    ]
            )
            players
        )


playerName : Me -> Player -> String
playerName me player =
    if isMe me player then
        player.colorName ++ " (you)"

    else
        player.colorName


viewField : Model -> Game -> Html Msg
viewField model game =
    let
        viewBox =
            "0 0 " ++ String.fromFloat game.width ++ " " ++ String.fromFloat game.height

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
        [ SA.id "schulte-field"
        , SA.viewBox viewBox
        , SA.class "block h-auto w-full drop-shadow-sm"
        , SA.strokeLinejoin "round"
        ]
        [ Svg.defs []
            [ Svg.clipPath [ SA.id "schulte-board-shape" ] [ boardRect 0 cornerRadius [] ] ]
        , Svg.g [ SA.clipPath "url(#schulte-board-shape)" ]
            (boardRect 0 cornerRadius [ SA.fill "#fbf5e1" ]
                :: List.map (viewCell model game.minStretch) game.cells
                ++ [ case game.infoBox of
                        Just box ->
                            viewInfoBox model game box

                        Nothing ->
                            text ""
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


{-| The radius of the board corners, in board units.
-}
cornerRadius : Float
cornerRadius =
    18


ink : String
ink =
    "#474d50"


{-| The time in the left half of the box, and the next number (large, in
a color that stands out, under a small "looking for" label) in the right half.
-}
viewInfoBox : Model -> Game -> Label -> Svg Msg
viewInfoBox model game { x, y, w, h } =
    let
        elapsedMs =
            if finished game then
                game.elapsedMs

            else
                max 0 (model.now - model.clockStart)

        middle =
            x + w / 2

        -- `cy` is the vertical middle of the text
        boxText textId cx cy size color weight content =
            Svg.text_
                [ SA.id textId
                , SA.x (String.fromFloat cx)
                , SA.y (String.fromFloat (cy + 0.36 * size))
                , SA.textAnchor "middle"
                , SA.fontSize (String.fromFloat size)
                , SA.fontFamily "'Helvetica Neue', Arial, sans-serif"
                , SA.fontWeight weight
                , SA.fill color
                , SA.style "font-variant-numeric: tabular-nums"
                ]
                [ Svg.text content ]
    in
    Svg.g [ SA.id "schulte-info", SA.pointerEvents "none" ]
        [ -- A white fill and a thick border, so that the box does not look
          -- like a cell. The border is inside the box, so that all four
          -- sides are equally thick.
          Svg.rect
            [ SA.x (String.fromFloat (x + 1.5))
            , SA.y (String.fromFloat (y + 1.5))
            , SA.width (String.fromFloat (w - 3))
            , SA.height (String.fromFloat (h - 3))
            , SA.fill "#ffffff"
            , SA.stroke ink
            , SA.strokeWidth "3"
            ]
            []
        , Svg.line
            [ SA.x1 (String.fromFloat middle)
            , SA.y1 (String.fromFloat (y + h * 0.2))
            , SA.x2 (String.fromFloat middle)
            , SA.y2 (String.fromFloat (y + h * 0.8))
            , SA.stroke ink
            , SA.strokeOpacity "0.3"
            , SA.strokeWidth "2"
            ]
            []
        , boxText "schulte-time" (x + w / 4) (y + h / 2) (h * 0.45) ink "300" (formatTime elapsedMs)
        , boxText "schulte-info-label" (x + 3 * w / 4) (y + h * 0.24) (h * 0.17) ink "400" "looking for"
        , boxText "schulte-info-next" (x + 3 * w / 4) (y + h * 0.6) (h * 0.6) "#d9534f" "700" (nextText game)
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


viewCell : Model -> Float -> Cell -> Svg Msg
viewCell model minStretch cell =
    let
        found =
            cell.foundBy /= Nothing
    in
    Svg.g
        [ SA.id ("schulte-cell-" ++ String.fromInt cell.number)
        , SA.class
            (if found then
                "schulte-cell schulte-found"

             else
                "schulte-cell"
            )
        , SE.onClick (Pick cell.number)
        ]
        [ Svg.path [ SA.d cell.d, SA.fill cell.color, SA.fillRule "evenodd", SA.stroke ink, SA.strokeWidth "3" ] []
        , if found then
            text ""

          else
            -- Only the number shakes after a wrong click, not the cell
            Svg.g
                [ SA.class
                    (if model.shaking == Just cell.number then
                        "schulte-shake"

                     else
                        ""
                    )
                ]
                [ viewNumber minStretch cell ]
        ]


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
        [ id "schulte-waiting"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-3 rounded-2xl bg-emerald-950/80 p-4 text-center text-white"
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


viewResult : Me -> Game -> Html Msg
viewResult me game =
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
                        "The " ++ winner.colorName ++ " player wins!"

                ( False, _ ) ->
                    "It's a tie!"

        ranked =
            List.reverse (List.sortBy .score players)
    in
    div
        [ id "schulte-result"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-4 rounded-2xl bg-emerald-950/70 p-4 text-white backdrop-blur-sm"
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
        , if me == Nothing then
            text ""

          else
            button
                [ id "schulte-play-again"
                , class "rounded-full bg-white px-6 py-2.5 font-medium text-emerald-800 shadow-lg transition hover:-translate-y-0.5 hover:bg-emerald-50 active:translate-y-0"
                , onClick Restart
                ]
                [ text "Play again" ]
        , a
            [ id "schulte-leaderboards-link"
            , href "/schulte"
            , class "text-sm font-medium text-white/80 underline-offset-4 transition hover:text-white hover:underline"
            ]
            [ text "Latest games and best results" ]
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
