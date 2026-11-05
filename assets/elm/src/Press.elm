module Press exposing (onKeyClick, onPress)

{-| Game pieces react when the finger touches the screen, not when it lifts.
-}

import Html
import Html.Events
import Json.Decode as Decode


{-| Send the message on the primary-button `pointerdown`.
-}
onPress : msg -> Html.Attribute msg
onPress msg =
    Html.Events.preventDefaultOn "pointerdown"
        (Decode.field "button" Decode.int
            |> Decode.andThen
                (\button ->
                    if button == 0 then
                        Decode.succeed ( msg, True )

                    else
                        Decode.fail "not the primary button"
                )
        )


{-| Send the message on a click from the keyboard (Enter or Space on a
button, `detail` 0). Use it with `onPress` on buttons: a click from a pointer
is ignored, because its `pointerdown` already sent the message.
-}
onKeyClick : msg -> Html.Attribute msg
onKeyClick msg =
    Html.Events.on "click"
        (Decode.field "detail" Decode.int
            |> Decode.andThen
                (\detail ->
                    if detail == 0 then
                        Decode.succeed msg

                    else
                        Decode.fail "pointer click"
                )
        )
