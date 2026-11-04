module GameBar exposing (height)

{-| The bar at the top of a game page, outside the Elm game (see
`OctomoctoWeb.GameBarLive`). The games keep its height free, so that the
field fits on the screen below it.
-}


{-| The height in pixels, the same as `h-8` of the bar.
-}
height : Float
height =
    32
