module Main exposing (main)

import Browser
import Html exposing (Html, button, div, h1, p, text)
import Html.Attributes exposing (class, id)
import Html.Events exposing (onClick)


type alias Model =
    Int


type Msg
    = Increment
    | Decrement


main : Program () Model Msg
main =
    Browser.element
        { init = \_ -> ( 0, Cmd.none )
        , view = view
        , update = update
        , subscriptions = \_ -> Sub.none
        }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Increment ->
            ( model + 1, Cmd.none )

        Decrement ->
            ( model - 1, Cmd.none )


view : Model -> Html Msg
view model =
    div [ id "elm-root", class "flex flex-col items-center gap-4" ]
        [ h1 [ class "text-2xl font-semibold" ] [ text "Hello from Elm" ]
        , div [ class "flex items-center gap-4" ]
            [ button [ id "elm-decrement", class "btn", onClick Decrement ] [ text "-" ]
            , p [ id "elm-count", class "text-xl tabular-nums" ] [ text (String.fromInt model) ]
            , button [ id "elm-increment", class "btn", onClick Increment ] [ text "+" ]
            ]
        ]
