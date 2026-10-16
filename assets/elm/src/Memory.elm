port module Memory exposing (main)

{-| Multiplayer memory game: find the cards with the same image.

The server owns the game: the cards, the turn and the scores. It sends the
images of the face-up cards only. This module draws the state that comes in
through ports and sends the player's clicks out. app.js connects the ports
to a Phoenix channel.

The player of the turn turns the cards face up. A set (2 or 3 cards with
the same image) goes off the field, and the player turns again. After a
miss, the cards stay face up until the next player turns a card.

The module compares each new state with the old one and sends the names
of the sounds to play out through a port. The player can mute the sounds.

The game is for a set number of players. Before all of them are in, nobody
can turn a card. A browser that joins a full game only watches: it has no
player id.

The port names start with "memory", because Elm does not allow two ports
with the same name in one bundle.

-}

import Browser
import Browser.Dom
import Browser.Events
import Dict exposing (Dict)
import Html exposing (Html, a, aside, button, div, h1, img, input, li, ol, p, span, text, ul)
import Html.Attributes exposing (alt, class, classList, href, id, readonly, src, style, value)
import Html.Events exposing (onClick)
import Json.Decode as Decode exposing (Decoder)
import Process
import Task
import Time



-- PORTS


port memoryFlip : Int -> Cmd msg


port memoryRestart : () -> Cmd msg


port memoryCopyText : String -> Cmd msg


port memoryJoined : (Decode.Value -> msg) -> Sub msg


port memoryState : (Decode.Value -> msg) -> Sub msg


port memoryJoinFailed : (String -> msg) -> Sub msg


port memoryPlaySound : String -> Cmd msg


port memorySaveMuted : Bool -> Cmd msg



-- MODEL


{-| The `name` is the display name of a signed-in player, or Nothing for a
guest. Then the player is known by the `colorName`. An `away` player lost
the connection, and can come back for a short time. The `accuracy` is in
percent, Nothing until the server counts a flip of the player.
-}
type alias Player =
    { id : String
    , name : Maybe String
    , color : String
    , colorName : String
    , score : Int
    , accuracy : Maybe Int
    , away : Bool
    }


{-| The state is "down", "up" or "cleared". The image is a number of an
image of the theme. A face-down card has no image.
-}
type alias Card =
    { state : String
    , image : Maybe Int
    }


{-| A grid for the cards: the columns, the rows and the number of empty
places (0 or 1).
-}
type alias Layout =
    { columns : Int
    , rows : Int
    , gaps : Int
    }


type alias Game =
    { theme : String
    , set : Int
    , cards : List Card
    , layouts : List Layout

    -- True until the game has all its players
    , waiting : Bool

    -- The clock runs from the first card
    , started : Bool
    , finished : Bool

    -- The time since the first card. After the end, the final time.
    , elapsedMs : Int

    -- The id of the player whose turn it is
    , turn : Maybe String

    -- True while the player of the turn has turned some cards of a set
    , ongoing : Bool

    -- The time since the last card of the turn, and the time limit of a
    -- turn (only with more than 2 players)
    , turnMs : Int
    , turnLimitMs : Maybe Int
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


type alias Model =
    { gameUrl : String
    , settingsUrl : String
    , nextGame : NextGame
    , guest : Bool
    , connection : Connection
    , copied : Bool

    -- The last image of each card, by its position. A card that turns face
    -- down keeps its image until it is turned over.
    , images : Dict Int Int

    -- The local time (in ms) when the field started, when the turn
    -- started, and the local time now. The clock ticks between the server
    -- updates.
    , clockStart : Int
    , turnStart : Int
    , now : Int

    -- The size of the window, to pick the grid that fits best
    , viewport : ( Float, Float )
    , muted : Bool
    }


{-| The other game that the end screen invites the player to try
-}
type alias NextGame =
    { name : String
    , path : String
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
      , images = Dict.empty
      , clockStart = 0
      , turnStart = 0
      , now = 0
      , viewport = ( 1024, 768 )
      , muted = flags.muted
      }
    , Task.perform (\vp -> Resized vp.viewport.width vp.viewport.height) Browser.Dom.getViewport
    )



-- UPDATE


type Msg
    = GotJoined Decode.Value
    | GotState Decode.Value
    | GotJoinFailed String
    | Flip Int
    | Restart
    | CopyLink
    | CopiedTimeout
    | SyncClock Game Time.Posix
    | Tick Time.Posix
    | Resized Float Float
    | ToggleMuted


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotJoined value ->
            case Decode.decodeValue joinedDecoder value of
                Ok ( me, game ) ->
                    ( { model | connection = Joined me game, images = rememberImages game Dict.empty }, syncClock game )

                Err err ->
                    ( { model | connection = Failed (Decode.errorToString err) }, Cmd.none )

        GotState value ->
            case ( model.connection, Decode.decodeValue gameDecoder value ) of
                ( Joined me old, Ok game ) ->
                    ( { model | connection = Joined me game, images = rememberImages game model.images }
                    , Cmd.batch [ syncClock game, playSounds model (stateSounds me old game) ]
                    )

                _ ->
                    ( model, Cmd.none )

        GotJoinFailed reason ->
            ( { model | connection = Failed reason }, Cmd.none )

        Flip index ->
            case model.connection of
                Joined me game ->
                    if canFlip me game (List.drop index game.cards |> List.head) then
                        ( model, memoryFlip index )

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        Restart ->
            ( model, memoryRestart () )

        CopyLink ->
            ( { model | copied = True }
            , Cmd.batch
                [ memoryCopyText model.gameUrl
                , Process.sleep 1500 |> Task.perform (\_ -> CopiedTimeout)
                ]
            )

        CopiedTimeout ->
            ( { model | copied = False }, Cmd.none )

        SyncClock game time ->
            let
                ms =
                    Time.posixToMillis time
            in
            ( { model | clockStart = ms - game.elapsedMs, turnStart = ms - game.turnMs, now = ms }, Cmd.none )

        Tick time ->
            ( { model | now = Time.posixToMillis time }, Cmd.none )

        Resized width height ->
            ( { model | viewport = ( width, height ) }, Cmd.none )

        ToggleMuted ->
            ( { model | muted = not model.muted }, memorySaveMuted (not model.muted) )


{-| A field with no face-up and no cleared cards is new, so the old images
are not needed any more.
-}
rememberImages : Game -> Dict Int Int -> Dict Int Int
rememberImages game images =
    let
        start =
            if List.all (\card -> card.state == "down") game.cards then
                Dict.empty

            else
                images
    in
    game.cards
        |> List.indexedMap Tuple.pair
        |> List.foldl
            (\( index, card ) dict ->
                case card.image of
                    Just image ->
                        Dict.insert index image dict

                    Nothing ->
                        dict
            )
            start


{-| The player of the turn can turn a face-down card. After a miss, the
cards of the miss can be turned again too: they go face down first.
-}
canFlip : Me -> Game -> Maybe Card -> Bool
canFlip me game maybeCard =
    case maybeCard of
        Just card ->
            myTurn me game
                && not game.waiting
                && not game.finished
                && (card.state == "down" || (card.state == "up" && not game.ongoing))

        Nothing ->
            False


myTurn : Me -> Game -> Bool
myTurn me game =
    me /= Nothing && me == game.turn


playSounds : Model -> List String -> Cmd Msg
playSounds model names =
    if model.muted then
        Cmd.none

    else
        Cmd.batch (List.map memoryPlaySound names)


{-| The sounds for the change from the old state to the new one: a card
that turns face up, a found set, the start of my turn, and the end of
the game. A miss has no sound of its own.
-}
stateSounds : Me -> Game -> Game -> List String
stateSounds me old new =
    let
        count state game =
            List.length (List.filter (\card -> card.state == state) game.cards)

        -- A card went from face down to face up. The first card of a turn
        -- after a miss can be one of the missed cards, which are face up
        -- before and after, so the start of a turn counts as a flip too.
        flipped =
            List.any (\( o, n ) -> o.state == "down" && n.state /= "down") (List.map2 Tuple.pair old.cards new.cards)
                || (new.ongoing && not old.ongoing)

        found =
            count "cleared" new > count "cleared" old

        myNewTurn =
            List.length new.players > 1 && myTurn me new && not (myTurn me old) && not new.finished

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
    List.concat
        [ if flipped then
            [ "flip" ]

          else
            []
        , if found && not new.finished then
            [ "match" ]

          else
            []
        , if myNewTurn then
            [ "turn" ]

          else
            []
        , endSound
        ]


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
    Time.now |> Task.perform (SyncClock game)



-- DECODERS


joinedDecoder : Decoder ( Me, Game )
joinedDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "player_id" (Decode.nullable Decode.string))
        (Decode.field "state" gameDecoder)


gameDecoder : Decoder Game
gameDecoder =
    Decode.succeed Game
        |> andMap (Decode.field "theme" Decode.string)
        |> andMap (Decode.field "set" Decode.int)
        |> andMap (Decode.field "cards" (Decode.list cardDecoder))
        |> andMap (Decode.field "layouts" (Decode.list layoutDecoder))
        |> andMap (Decode.field "waiting" Decode.bool)
        |> andMap (Decode.field "started" Decode.bool)
        |> andMap (Decode.field "finished" Decode.bool)
        |> andMap (Decode.field "elapsed_ms" Decode.int)
        |> andMap (Decode.field "turn" (Decode.nullable Decode.string))
        |> andMap (Decode.field "ongoing" Decode.bool)
        |> andMap (Decode.field "turn_ms" Decode.int)
        |> andMap (Decode.field "turn_limit_ms" (Decode.nullable Decode.int))
        |> andMap (Decode.field "players" (Decode.list playerDecoder))
        |> andMap (Decode.field "players_needed" Decode.int)


andMap : Decoder a -> Decoder (a -> b) -> Decoder b
andMap =
    Decode.map2 (|>)


cardDecoder : Decoder Card
cardDecoder =
    Decode.map2 Card
        (Decode.field "state" Decode.string)
        (Decode.field "image" (Decode.nullable Decode.int))


layoutDecoder : Decoder Layout
layoutDecoder =
    Decode.map3 Layout
        (Decode.index 0 Decode.int)
        (Decode.index 1 Decode.int)
        (Decode.index 2 Decode.int)


playerDecoder : Decoder Player
playerDecoder =
    Decode.map7 Player
        (Decode.field "id" Decode.string)
        (Decode.field "name" (Decode.nullable Decode.string))
        (Decode.field "color" Decode.string)
        (Decode.field "color_name" Decode.string)
        (Decode.field "score" Decode.int)
        (Decode.field "accuracy" (Decode.nullable Decode.int))
        (Decode.field "away" Decode.bool)



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ memoryJoined GotJoined
        , memoryState GotState
        , memoryJoinFailed GotJoinFailed
        , Browser.Events.onResize (\w h -> Resized (toFloat w) (toFloat h))
        , case model.connection of
            Joined _ game ->
                if not game.waiting && not game.finished then
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
            p [ id "memory-connecting", class "py-24 text-center opacity-60" ] [ text "Joining the game…" ]

        Failed reason ->
            p [ id "memory-failed", class "py-24 text-center text-red-600" ] [ text ("Could not join the game: " ++ reason) ]

        Joined me game ->
            viewGame model me game


viewGame : Model -> Me -> Game -> Html Msg
viewGame model me game =
    let
        layout =
            bestLayout model me game

        gap =
            cardGap (fieldSpace model me game) layout
    in
    div
        [ id "memory-root"
        , class "flex w-full flex-col gap-2 select-none lg:flex-row lg:items-start lg:gap-8"
        , classList [ ( "is-playing", not game.waiting && not game.finished ) ]
        ]
        [ aside [ id "memory-panel", class "flex flex-col gap-2 lg:sticky lg:top-6 lg:w-72 lg:shrink-0 lg:gap-5" ]
            -- On a small screen, the title, the stats and the restart button
            -- are in one compact row. On a large screen, the row is not a
            -- box (`contents`), so its items are in the column of the panel.
            [ div [ class "flex items-center gap-1 lg:contents" ]
                [ div [ class "min-w-0 lg:order-1" ]
                    [ div [ class "flex items-center gap-1 lg:gap-2" ]
                        [ a
                            [ id "memory-back"
                            , href model.settingsUrl
                            , class "grid size-8 shrink-0 place-items-center rounded-full text-slate-500 transition hover:bg-slate-100 hover:text-slate-800 active:scale-90 lg:hidden dark:text-slate-400 dark:hover:bg-white/10 dark:hover:text-slate-100"
                            , Html.Attributes.title "Back to the settings"
                            ]
                            [ span [ class "hero-arrow-left size-5" ] [] ]
                        , h1 [ class "text-xl font-semibold tracking-tight lg:text-2xl" ]
                            [ a [ id "memory-title-link", href "/memory", class "transition hover:text-octo-indigo dark:hover:text-octo-indigo-light" ] [ text "Memory" ] ]
                        , viewMuteButton model.muted
                        ]
                    , p [ class "hidden text-sm opacity-60 lg:block" ]
                        [ text
                            (if game.set == 2 then
                                "Find the pairs of cards with the same image."

                             else
                                "Find the triplets of cards with the same image."
                            )
                        ]
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
                viewScores model me game

              else
                text ""
            , if me == Nothing then
                p [ id "memory-watching", class "rounded-2xl bg-amber-50 px-4 py-3 text-sm text-amber-900 ring-1 ring-amber-200 lg:order-5 dark:bg-amber-400/10 dark:text-amber-200 dark:ring-amber-400/25" ]
                    [ text "This game is full, so you can only watch it." ]

              else
                text ""
            , a
                [ id "memory-leaderboards-link"
                , href model.settingsUrl
                , class "hidden text-sm font-medium text-octo-indigo underline-offset-4 transition hover:underline lg:order-6 lg:block dark:text-octo-indigo-light"
                ]
                [ text "Latest games and best results" ]
            ]
        , div [ class "min-w-0 flex-1" ]
            [ div [ id "memory-board", class "relative mx-auto lg:rounded-2xl lg:bg-white lg:p-2 lg:shadow-sm lg:ring-1 lg:ring-slate-200 dark:lg:bg-white/5 dark:lg:shadow-none dark:lg:ring-white/10", style "width" (fieldWidth model me game layout gap) ]
                [ viewField model me game layout gap
                , if game.waiting then
                    viewWaiting game

                  else if game.finished then
                    viewResult model.settingsUrl model.nextGame model.guest me game

                  else
                    text ""
                ]
            ]
        ]


{-| The width of the screen from which the panel is at the left of the
field. On a smaller screen, the panel is a compact row above the field, and
the page has no header and no footer.
-}
largeScreen : Float
largeScreen =
    1024


{-| The grid with the largest cards in the space for the field. With the
same size of the cards, the grid with fewer empty places.
-}
bestLayout : Model -> Me -> Game -> Layout
bestLayout model me game =
    let
        space =
            fieldSpace model me game
    in
    game.layouts
        |> List.sortBy (\layout -> ( -(cardSize space layout), layout.gaps ))
        |> List.head
        |> Maybe.withDefault (Layout (List.length game.cards) 1 0)


{-| The width and the height in pixels of the space for the field. On a
large screen, the panel is at the left of the field. On a small screen, it
is above the field, so the field can be as tall as the screen.
-}
fieldSpace : Model -> Me -> Game -> ( Float, Float )
fieldSpace model me game =
    let
        ( width, height ) =
            model.viewport
    in
    ( if width >= largeScreen then
        width - 416

      else
        width - 16
    , height - reservedHeight model me game
    )


{-| The gap in pixels between the cards. It is approximately 6% of the size
of a card, so that smaller cards have smaller gaps, from 2 to 8 pixels.
-}
cardGap : ( Float, Float ) -> Layout -> Float
cardGap ( width, height ) layout =
    min (width / toFloat layout.columns) (height / toFloat layout.rows)
        * 0.06
        |> round
        |> clamp 2 8
        |> toFloat


cardSize : ( Float, Float ) -> Layout -> Float
cardSize (( width, height ) as space) layout =
    let
        gap =
            cardGap space layout
    in
    min
        ((width - gap * toFloat (layout.columns - 1)) / toFloat layout.columns)
        ((height - gap * toFloat (layout.rows - 1)) / toFloat layout.rows)


{-| The height in pixels of the screen that is not for the field. On a large
screen, it is the 4rem header, the 1.5rem bottom padding of the page and the
4rem footer, and the 0.5rem padding of the board on each side. On a small
screen, it is the 0.5rem padding of the page at the top and at the bottom,
and the rows of the panel with the 0.5rem gaps between them. The heights of
the rows are approximate, because the scores can wrap.
-}
reservedHeight : Model -> Me -> Game -> Float
reservedHeight model me game =
    if Tuple.first model.viewport >= largeScreen then
        168

    else
        let
            row condition rowHeight =
                if condition then
                    rowHeight + 8

                else
                    0
        in
        16
            + row True 40
            + row (game.playersNeeded > 1) 40
            + row (List.length game.players > 1) 30
            + row (me == Nothing) 44


{-| Make the board as wide as possible, but small enough that it is all on
the screen. The cards are square, so the width comes from the height of
the space without the gaps between the rows.
-}
fieldWidth : Model -> Me -> Game -> Layout -> Float -> String
fieldWidth model me game layout gap =
    let
        px value =
            String.fromFloat value ++ "px"

        padding =
            if Tuple.first model.viewport >= largeScreen then
                " + 1rem"

            else
                ""
    in
    "min(100%, calc((100dvh - "
        ++ px (reservedHeight model me game + gap * toFloat (layout.rows - 1))
        ++ ") * "
        ++ String.fromFloat (toFloat layout.columns / toFloat layout.rows)
        ++ " + "
        ++ px (gap * toFloat (layout.columns - 1))
        ++ padding
        ++ "))"


viewMuteButton : Bool -> Html Msg
viewMuteButton muted =
    button
        [ id "memory-mute"
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


{-| Starts a new field for all players, also during a game. On a small
screen, only the icon shows.
-}
viewRestartButton : Html Msg
viewRestartButton =
    button
        [ id "memory-restart"
        , class "group flex size-9 shrink-0 items-center justify-center gap-2 rounded-full text-sm font-medium text-slate-600 ring-1 ring-slate-200 transition hover:bg-slate-50 hover:text-slate-900 hover:ring-slate-300 active:scale-95 lg:order-5 lg:size-auto lg:self-start lg:px-4 lg:py-2 dark:text-slate-300 dark:ring-white/20 dark:hover:bg-white/10 dark:hover:text-white dark:hover:ring-white/30"
        , onClick Restart
        , Html.Attributes.title "Restart game"
        ]
        [ span [ class "hero-arrow-path size-4 transition-transform duration-300 group-hover:-rotate-180" ] []
        , span [ class "hidden lg:inline" ] [ text "Restart game" ]
        ]


viewShareLink : Model -> Html Msg
viewShareLink model =
    div [ class "flex items-center gap-2 rounded-full bg-octo-mist p-1 pl-4 lg:order-3 text-sm ring-1 ring-octo-indigo/20 lg:flex-col lg:items-stretch lg:rounded-2xl lg:p-2 lg:pl-2 dark:bg-octo-indigo/15 dark:ring-octo-indigo-light/25" ]
        [ input
            [ id "memory-link"
            , readonly True
            , value model.gameUrl
            , class "min-w-0 flex-1 truncate bg-transparent text-octo-navy outline-none lg:px-2 lg:py-1 dark:text-slate-100"
            ]
            []
        , button
            [ id "memory-copy-link"
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


{-| The time, and for one player, the accuracy (with more players, it is
next to each score). On a small screen, they are small and without a box,
at the right of the compact row of the panel.
-}
viewClock : Model -> Game -> Html Msg
viewClock model game =
    let
        elapsedMs =
            if game.finished then
                game.elapsedMs

            else if game.started then
                max 0 (model.now - model.clockStart)

            else
                0

        solo =
            List.length game.players == 1

        stat label valueId value =
            div [ class "flex flex-col items-center justify-center" ]
                [ span [ class "text-[0.625rem] font-medium tracking-wide text-slate-400 uppercase lg:text-xs" ] [ text label ]
                , span [ id valueId, class "text-lg leading-tight font-light text-slate-700 tabular-nums lg:text-3xl dark:text-slate-100" ] [ text value ]
                ]
    in
    div
        [ id "memory-clock"
        , class "ml-auto flex gap-4 pr-2 lg:order-2 lg:ml-0 lg:grid lg:gap-0 lg:divide-x lg:divide-slate-200 lg:rounded-2xl lg:bg-white lg:py-3 lg:pr-0 lg:shadow-sm lg:ring-1 lg:ring-slate-200 dark:lg:divide-white/10 dark:lg:bg-white/5 dark:lg:shadow-none dark:lg:ring-white/10"
        , classList [ ( "lg:grid-cols-2", solo ), ( "lg:grid-cols-1", not solo ) ]
        ]
        [ stat "time" "memory-time" (formatTime elapsedMs)
        , if solo then
            stat "accuracy" "memory-accuracy" (formatAccuracy (List.head game.players |> Maybe.andThen .accuracy))

          else
            text ""
        ]


{-| Show the accuracy in percent, for example "92%", or "—" before the
first counted flip.
-}
formatAccuracy : Maybe Int -> String
formatAccuracy accuracy =
    case accuracy of
        Just percent ->
            String.fromInt percent ++ "%"

        Nothing ->
            "—"


{-| Show the time as minutes and seconds, for example "1:05".
-}
formatTime : Int -> String
formatTime ms =
    let
        seconds =
            ms // 1000
    in
    String.fromInt (seconds // 60) ++ ":" ++ String.padLeft 2 '0' (String.fromInt (modBy 60 seconds))


{-| The players in the order of their turns. The player of the turn has a
ring in the player's color. When a turn has a time limit, a bar shows the
time that is left in the last seconds of the turn.
-}
viewScores : Model -> Me -> Game -> Html Msg
viewScores model me game =
    ul [ id "memory-scores", class "flex flex-wrap gap-2 lg:order-4 lg:flex-col" ]
        (List.map
            (\player ->
                let
                    current =
                        game.turn == Just player.id && not game.waiting && not game.finished
                in
                li
                    [ id ("memory-score-" ++ player.id)
                    , class "relative flex items-center gap-2 overflow-hidden rounded-full bg-white px-3 py-1 text-sm text-slate-800 shadow-sm ring-1 ring-slate-200 transition dark:bg-white/5 dark:text-slate-100 dark:shadow-none dark:ring-white/10"
                    , classList [ ( "opacity-50", player.away ), ( "memory-current", current ) ]

                    -- Elm's `style` cannot set a CSS variable
                    , Html.Attributes.attribute "style" ("--player-color: " ++ player.color)
                    ]
                    [ span [ class "size-3 rounded-full", style "background" player.color ] []
                    , span [ class "lg:flex-1" ] [ text (playerName me player) ]
                    , if current then
                        span [ class "text-xs font-medium tracking-wide uppercase", style "color" player.color ] [ text "turn" ]

                      else
                        text ""
                    , span [ class "font-semibold tabular-nums" ] [ text (String.fromInt player.score) ]
                    , span [ id ("memory-accuracy-" ++ player.id), class "text-xs text-slate-400 tabular-nums", Html.Attributes.title "Accuracy" ]
                        [ text (formatAccuracy player.accuracy) ]
                    , if current then
                        viewTurnTimer model game

                      else
                        text ""
                    ]
            )
            game.players
        )


{-| The bar shows in the last 10 seconds of a turn with a time limit.
-}
viewTurnTimer : Model -> Game -> Html Msg
viewTurnTimer model game =
    case game.turnLimitMs of
        Just limit ->
            let
                shownMs =
                    10000

                left =
                    limit - (model.now - model.turnStart)
            in
            if left < shownMs then
                span
                    [ class "absolute bottom-0 left-0 h-0.5 bg-current transition-[width] duration-200 ease-linear"
                    , style "width" (String.fromFloat (100 * toFloat (max 0 left) / shownMs) ++ "%")
                    , style "color" "var(--player-color)"
                    ]
                    []

            else
                text ""

        Nothing ->
            text ""


playerName : Me -> Player -> String
playerName me player =
    if isMe me player then
        Maybe.withDefault player.colorName player.name ++ " (you)"

    else
        Maybe.withDefault player.colorName player.name


{-| The cards in a grid. The empty places of the grid are at equal
distances along the rows and along the columns, so each one is in a
different column. One empty place is in the middle.
-}
viewField : Model -> Me -> Game -> Layout -> Float -> Html Msg
viewField model me game layout gap =
    let
        cards =
            List.indexedMap (viewCard model me game) game.cards

        -- The middle of part k of the equal parts of the rows or the columns
        middle k count =
            (2 * k + 1) * count // (2 * layout.gaps)

        gapPlaces =
            List.map (\k -> middle k layout.rows * layout.columns + middle k layout.columns) (List.range 0 (layout.gaps - 1))
    in
    div
        [ id "memory-field"
        , class "grid"
        , style "gap" (String.fromFloat gap ++ "px")
        , style "grid-template-columns" ("repeat(" ++ String.fromInt layout.columns ++ ", minmax(0, 1fr))")
        ]
        (withGaps 0 gapPlaces cards)


{-| Puts an empty place at each of the places of the grid in the list.
-}
withGaps : Int -> List Int -> List (Html Msg) -> List (Html Msg)
withGaps place gapPlaces cards =
    case ( gapPlaces, cards ) of
        ( gap :: otherGaps, _ ) ->
            if place == gap then
                div [] [] :: withGaps (place + 1) otherGaps cards

            else
                case cards of
                    card :: otherCards ->
                        card :: withGaps (place + 1) gapPlaces otherCards

                    [] ->
                        []

        ( [], _ ) ->
            cards


viewCard : Model -> Me -> Game -> Int -> Card -> Html Msg
viewCard model me game index card =
    let
        image =
            case card.image of
                Just i ->
                    Just i

                Nothing ->
                    Dict.get index model.images
    in
    button
        [ id ("memory-card-" ++ String.fromInt index)
        , class "memory-card aspect-square"
        , classList
            [ ( "is-up", card.state /= "down" )
            , ( "is-cleared", card.state == "cleared" )
            , ( "is-clickable", canFlip me game (Just card) )
            ]
        , onClick (Flip index)
        ]
        [ div [ class "memory-card-inner" ]
            [ div [ class "memory-card-back" ] []
            , div [ class "memory-card-face" ]
                [ case image of
                    Just i ->
                        img
                            [ src ("/images/memory/" ++ game.theme ++ "/" ++ String.fromInt i ++ ".svg")
                            , alt ""
                            , class "size-3/4 object-contain"
                            ]
                            []

                    Nothing ->
                        text ""
                ]
            ]
        ]


{-| Covers the field until all players are in.
-}
viewWaiting : Game -> Html Msg
viewWaiting game =
    div
        [ id "memory-waiting"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-3 rounded-2xl bg-octo-navy/80 p-4 text-center text-white"
        ]
        [ p [ class "text-3xl font-semibold" ] [ text "Waiting for players" ]
        , p [ id "memory-waiting-count", class "text-lg tabular-nums opacity-80" ]
            [ text
                (String.fromInt (List.length game.players)
                    ++ " of "
                    ++ String.fromInt game.playersNeeded
                    ++ " players are in"
                )
            ]
        , p [ class "text-sm opacity-60" ] [ text "Send the link to the other players. The game starts when all of them are in." ]
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
        [ id "memory-result"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-4 rounded-2xl bg-octo-navy/70 p-4 text-white backdrop-blur-sm"
        ]
        [ p [ class "text-3xl font-semibold" ] [ text message ]
        , p [ id "memory-final-time", class "text-lg tabular-nums opacity-80" ]
            [ text
                ("Time "
                    ++ formatTime game.elapsedMs
                    ++ (if solo then
                            " · Accuracy " ++ formatAccuracy (List.head players |> Maybe.andThen .accuracy)

                        else
                            ""
                       )
                )
            ]
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
                            , span [ class "w-10 text-right tabular-nums opacity-70", Html.Attributes.title "Accuracy" ] [ text (formatAccuracy player.accuracy) ]
                            ]
                    )
                    ranked
                )
        , if me == Nothing then
            text ""

          else
            button
                [ id "memory-play-again"
                , class "rounded-full bg-white px-6 py-2.5 font-medium text-octo-indigo shadow-lg transition hover:-translate-y-0.5 hover:bg-octo-mist active:translate-y-0"
                , onClick Restart
                ]
                [ text "Play again" ]
        , a
            [ id "memory-next-game"
            , href nextGame.path
            , class "group text-sm font-medium text-white underline-offset-4 transition hover:underline"
            ]
            [ text ("Or try " ++ nextGame.name ++ " ")
            , span [ class "inline-block transition group-hover:translate-x-0.5" ] [ text "→" ]
            ]

        -- On a large screen, the link is in the panel
        , a
            [ id "memory-result-leaderboards-link"
            , href settingsUrl
            , class "text-sm font-medium text-white underline-offset-4 transition hover:underline lg:hidden"
            ]
            [ text "Latest games and best results" ]

        -- Only a guest who played gets the call to sign in, not a spectator
        , if guest && me /= Nothing then
            p [ id "memory-sign-in", class "text-sm text-white/70" ]
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
