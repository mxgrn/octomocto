port module Schulte exposing (main)

{-| Multiplayer Schulte table race.

The server owns the game: the field with the numbers 1 to 90, the next
number and the scores. The first player to click the next number gets a
point, and the number becomes gray for all players. This module draws the
state that comes in through ports and sends the player's clicks out.
app.js connects the ports to a Phoenix channel.

A click on a wrong number does nothing, but the cell shakes for this
player only.

The port names start with "schulte", because Elm does not allow two ports
with the same name in one bundle.

-}

import Browser
import Html exposing (Html, button, div, h1, input, li, ol, p, span, text, ul)
import Html.Attributes exposing (class, id, readonly, style, value)
import Html.Events exposing (onClick)
import Json.Decode as Decode exposing (Decoder)
import Process
import Svg exposing (Svg)
import Svg.Attributes as SA
import Svg.Events as SE
import Task



-- PORTS


port schultePick : Int -> Cmd msg


port schulteRestart : () -> Cmd msg


port schulteCopyText : String -> Cmd msg


port schulteJoined : (Decode.Value -> msg) -> Sub msg


port schulteState : (Decode.Value -> msg) -> Sub msg


port schulteJoinFailed : (String -> msg) -> Sub msg



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
    }


type Connection
    = Connecting
    | Joined String Game
    | Failed String


type alias Model =
    { gameUrl : String
    , connection : Connection
    , copied : Bool

    -- The number that shakes after a wrong click. The count makes sure
    -- that only the newest timeout stops the shake.
    , shaking : Maybe Int
    , shakeCount : Int
    }


type alias Flags =
    { gameUrl : String }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { gameUrl = flags.gameUrl
      , connection = Connecting
      , copied = False
      , shaking = Nothing
      , shakeCount = 0
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
                ( Joined me _, Ok game ) ->
                    ( { model | connection = Joined me game }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        GotJoinFailed reason ->
            ( { model | connection = Failed reason }, Cmd.none )

        Pick number ->
            case model.connection of
                Joined _ game ->
                    if number == game.next then
                        ( model, schultePick number )

                    else if number > game.next then
                        let
                            count =
                                model.shakeCount + 1
                        in
                        ( { model | shaking = Just number, shakeCount = count }
                        , Process.sleep 400 |> Task.perform (\_ -> ShakeDone count)
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


-- DECODERS


joinedDecoder : Decoder ( String, Game )
joinedDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "player_id" Decode.string)
        (Decode.field "state" gameDecoder)


gameDecoder : Decoder Game
gameDecoder =
    Decode.map6 Game
        (Decode.field "board" (Decode.index 0 Decode.float))
        (Decode.field "board" (Decode.index 1 Decode.float))
        (Decode.field "total" Decode.int)
        (Decode.field "next" Decode.int)
        (Decode.field "cells" (Decode.list cellDecoder))
        (Decode.field "players" (Decode.list playerDecoder))


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
subscriptions _ =
    Sub.batch
        [ schulteJoined GotJoined
        , schulteState GotState
        , schulteJoinFailed GotJoinFailed
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


viewGame : Model -> String -> Game -> Html Msg
viewGame model me game =
    div [ id "schulte-root", class "relative left-1/2 flex w-[min(96vw,1100px)] -translate-x-1/2 flex-col gap-5 select-none" ]
        [ div [ class "flex items-end justify-between gap-4" ]
            [ div []
                [ h1 [ class "text-2xl font-semibold tracking-tight" ] [ text "Schulte Race" ]
                , p [ class "text-sm opacity-60" ] [ text "Click the numbers in order. The first click gets the point." ]
                ]
            , viewNext game
            ]
        , viewShareLink model
        , viewScores me game.players
        , div [ class "relative" ]
            [ viewField model game
            , if finished game then
                viewResult me game.players

              else
                text ""
            ]
        ]


viewNext : Game -> Html Msg
viewNext game =
    div [ id "schulte-next", class "flex shrink-0 flex-col items-center rounded-2xl bg-emerald-600 px-4 py-1.5 text-white shadow-lg shadow-emerald-600/25" ]
        [ span [ class "text-[10px] font-medium uppercase tracking-widest opacity-80" ] [ text "Find" ]
        , span [ class "text-2xl font-bold leading-tight tabular-nums" ]
            [ text
                (if finished game then
                    "✓"

                 else
                    String.fromInt game.next
                )
            ]
        ]


viewShareLink : Model -> Html Msg
viewShareLink model =
    div [ class "flex items-center gap-2 rounded-full bg-emerald-50 p-1 pl-4 text-sm ring-1 ring-emerald-200" ]
        [ input
            [ id "schulte-link"
            , readonly True
            , value model.gameUrl
            , class "min-w-0 flex-1 truncate bg-transparent text-emerald-900 outline-none"
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


viewScores : String -> List Player -> Html Msg
viewScores me players =
    ul [ id "schulte-scores", class "flex flex-wrap gap-2" ]
        (List.map
            (\player ->
                li
                    [ id ("schulte-score-" ++ player.id)
                    , class "flex items-center gap-2 rounded-full bg-white px-3 py-1 text-sm text-slate-800 shadow-sm ring-1 ring-slate-200"
                    ]
                    [ span [ class "size-3 rounded-full", style "background" player.color ] []
                    , span [] [ text (playerName me player) ]
                    , span [ class "font-semibold tabular-nums" ] [ text (String.fromInt player.score) ]
                    ]
            )
            players
        )


playerName : String -> Player -> String
playerName me player =
    if player.id == me then
        player.colorName ++ " (you)"

    else
        player.colorName


viewField : Model -> Game -> Html Msg
viewField model game =
    let
        viewBox =
            "0 0 " ++ String.fromFloat game.width ++ " " ++ String.fromFloat game.height
    in
    Svg.svg
        [ SA.id "schulte-field"
        , SA.viewBox viewBox
        , SA.class "block h-auto w-full rounded-2xl bg-[#fbf5e1] shadow-sm ring-1 ring-slate-300"
        , SA.strokeLinejoin "round"
        ]
        (List.map (viewCell model) game.cells
            ++ [ Svg.rect
                    [ SA.width (String.fromFloat game.width)
                    , SA.height (String.fromFloat game.height)
                    , SA.fill "none"
                    , SA.stroke ink
                    , SA.strokeWidth "6"
                    , SA.pointerEvents "none"
                    ]
                    []
               ]
        )


ink : String
ink =
    "#474d50"


viewCell : Model -> Cell -> Svg Msg
viewCell model cell =
    let
        shaking =
            model.shaking == Just cell.number

        found =
            cell.foundBy /= Nothing

        fill =
            if shaking then
                "#fca5a5"

            else if found then
                "#d6d3d1"

            else
                cell.color
    in
    Svg.g
        [ SA.id ("schulte-cell-" ++ String.fromInt cell.number)
        , SA.class
            (String.join " "
                [ "schulte-cell"
                , if found then
                    "schulte-found"

                  else
                    ""
                , if shaking then
                    "schulte-shake"

                  else
                    ""
                ]
            )
        , SE.onClick (Pick cell.number)
        ]
        [ Svg.path [ SA.d cell.d, SA.fill fill, SA.fillRule "evenodd", SA.stroke ink, SA.strokeWidth "3" ] []
        , viewNumber found cell
        ]


{-| Stretch the number to fill its label box, like the tall narrow and the
wide numbers in a printed puzzle. The stretch is kept between about 0.3 and
3 times the normal width, so that the digits stay readable.
-}
viewNumber : Bool -> Cell -> Svg msg
viewNumber found cell =
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
            min fullSize (w / (0.3 * digitWidth * digits))

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
        , SA.opacity
            (if found then
                "0.3"

             else
                "1"
            )
        , SA.pointerEvents "none"
        ]
        [ Svg.text (String.fromInt cell.number) ]


viewResult : String -> List Player -> Html Msg
viewResult me players =
    let
        best =
            List.maximum (List.map .score players) |> Maybe.withDefault 0

        winners =
            List.filter (\p -> p.score == best) players

        message =
            case winners of
                [ winner ] ->
                    if winner.id == me then
                        "You win!"

                    else
                        "The " ++ winner.colorName ++ " player wins!"

                _ ->
                    "It's a tie!"

        ranked =
            List.reverse (List.sortBy .score players)
    in
    div
        [ id "schulte-result"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-4 rounded-2xl bg-emerald-950/70 p-4 text-white backdrop-blur-sm"
        ]
        [ p [ class "text-3xl font-semibold" ] [ text message ]
        , ol [ class "flex flex-col gap-1 text-sm" ]
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
        , button
            [ id "schulte-play-again"
            , class "rounded-full bg-white px-6 py-2.5 font-medium text-emerald-800 shadow-lg transition hover:-translate-y-0.5 hover:bg-emerald-50 active:translate-y-0"
            , onClick Restart
            ]
            [ text "Play again" ]
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
