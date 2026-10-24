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
import Html.Attributes exposing (alt, attribute, class, classList, disabled, href, id, readonly, src, style, value)
import Html.Events exposing (onClick)
import Json.Decode as Decode exposing (Decoder)
import Process
import Task
import Time



-- PORTS


port memoryFlip : Int -> Cmd msg


port memoryRestart : () -> Cmd msg


{-| Starts the next game for all players, see OctomoctoWeb.NextGame
-}
port memoryNextGame : () -> Cmd msg


{-| Starts the next level of the campaign, see OctomoctoWeb.MemoryChannel
-}
port memoryNextLevel : () -> Cmd msg


port memoryCopyText : String -> Cmd msg


port memoryJoined : (Decode.Value -> msg) -> Sub msg


port memoryState : (Decode.Value -> msg) -> Sub msg


port memoryJoinFailed : (String -> msg) -> Sub msg


{-| The number of browsers that only watch the game, after the join and
after each change.
-}
port memoryWatchers : (Int -> msg) -> Sub msg


port memoryPlaySound : String -> Cmd msg


port memorySaveMuted : Bool -> Cmd msg



-- MODEL


{-| The `name` is the display name of a signed-in player, or Nothing for a
guest. Then the player is known by the `colorName`. An `away` player lost
the connection, and can come back for a short time. The `accuracy` is in
percent, Nothing until the server counts a flip of the player. A `dead`
player turned a bomb that was seen, or a card that is not a bomb during a
demining (`failedDemining`), and has no more turns. A `deminer` demined
the field.
-}
type alias Player =
    { id : String
    , name : Maybe String
    , color : String
    , colorName : String
    , score : Int
    , accuracy : Maybe Int
    , away : Bool
    , dead : Bool
    , failedDemining : Bool
    , deminer : Bool
    }


{-| The state is "down", "up", "cleared" or "revealed" (a card that the
player had to turn, shown after an error in the campaign, or a bomb at the
end of the field). The image is a number of an image of the theme. A
face-down card has no image, and is not shown as a bomb.
-}
type alias Card =
    { state : String
    , image : Maybe Int
    , bomb : Bool
    }


{-| The face of a card: an image of the theme, or a bomb
-}
type Face
    = Picture Int
    | Bomb


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

    -- The id of the player who changes the settings of the next field of
    -- the match (see `OctomoctoWeb.MemoryLive`). The other players wait.
    , editing : Maybe String

    -- The level of a game of the campaign, Nothing for other games
    , campaign : Maybe Campaign

    -- True when a field of the campaign stopped at an error, or when the
    -- only player turned a bomb that was seen
    , failed : Bool

    -- The number of bombs, and the bombs that were face up at some time
    , bombs : Int
    , bombsSeen : Int

    -- True while the next card of the player of the turn decides if the
    -- player demines the field, and while the player demines it
    , offer : Bool
    , demining : Bool
    }


{-| The level of a game of the campaign (from 1), and the number of levels
-}
type alias Campaign =
    { level : Int
    , levels : Int
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
    , indexUrl : String
    , settingsUrl : String
    , changeSettingsUrl : String
    , nextGame : NextGame
    , guest : Bool
    , connection : Connection
    , copied : Bool

    -- The last face of each card, by its position. A card that turns face
    -- down keeps its face until it is turned over.
    , images : Dict Int Face

    -- The local time (in ms) when the field started, when the turn
    -- started, and the local time now. The clock ticks between the server
    -- updates.
    , clockStart : Int
    , turnStart : Int
    , now : Int

    -- The size of the window, to pick the grid that fits best
    , viewport : ( Float, Float )
    , muted : Bool
    , watchers : Int
    , texts : Texts
    }


{-| The texts in the language of the page, by the English text (see
`OctomoctoWeb.MemoryHTML.elm_texts/0`).
-}
type alias Texts =
    Dict String String


{-| The other game that the end screen invites the player to try
-}
type alias NextGame =
    { name : String
    , path : String
    }


type alias Flags =
    { gameUrl : String
    , indexUrl : String
    , settingsUrl : String
    , changeSettingsUrl : String
    , nextGame : NextGame
    , guest : Bool
    , muted : Bool
    , texts : Decode.Value
    }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { gameUrl = flags.gameUrl
      , indexUrl = flags.indexUrl
      , settingsUrl = flags.settingsUrl
      , changeSettingsUrl = flags.changeSettingsUrl
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
      , watchers = 0
      , texts = Decode.decodeValue (Decode.dict Decode.string) flags.texts |> Result.withDefault Dict.empty
      }
    , Task.perform (\vp -> Resized vp.viewport.width vp.viewport.height) Browser.Dom.getViewport
    )



-- UPDATE


type Msg
    = GotJoined Decode.Value
    | GotState Decode.Value
    | GotJoinFailed String
    | GotWatchers Int
    | Flip Int
    | Restart
    | StartNextGame
    | StartNextLevel
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

        GotWatchers count ->
            ( { model | watchers = count }, Cmd.none )

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

        StartNextGame ->
            ( model, memoryNextGame () )

        StartNextLevel ->
            ( model, memoryNextLevel () )

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
rememberImages : Game -> Dict Int Face -> Dict Int Face
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
                case ( card.image, card.bomb ) of
                    ( Just image, _ ) ->
                        Dict.insert index (Picture image) dict

                    ( Nothing, True ) ->
                        Dict.insert index Bomb dict

                    ( Nothing, False ) ->
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


{-| The sounds for the change from the old state to the new one: the start
of the game, a card that turns face up, a found set, a player who is out,
the start of my turn, and the end of the game. A miss has no sound of its
own.
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

        dead game =
            List.length (List.filter .dead game.players)

        exploded =
            dead new > dead old

        myNewTurn =
            List.length new.players > 1 && myTurn me new && not (myTurn me old) && not new.finished

        endSound =
            if new.failed && not old.failed then
                [ "lose" ]

            else if new.finished && not old.finished then
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
        [ startSound
        , if flipped then
            [ "flip" ]

          else
            []
        , if found && not new.finished then
            [ "match" ]

          else
            []
        , if exploded then
            [ "boom" ]

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
        |> andMap (Decode.field "editing" (Decode.nullable Decode.string))
        |> andMap (Decode.field "campaign" (Decode.nullable campaignDecoder))
        |> andMap (Decode.field "failed" Decode.bool)
        |> andMap (Decode.field "bombs" Decode.int)
        |> andMap (Decode.field "bombs_seen" Decode.int)
        |> andMap (Decode.field "offer" Decode.bool)
        |> andMap (Decode.field "demining" Decode.bool)


campaignDecoder : Decoder Campaign
campaignDecoder =
    Decode.map2 Campaign
        (Decode.field "level" Decode.int)
        (Decode.field "levels" Decode.int)


andMap : Decoder a -> Decoder (a -> b) -> Decoder b
andMap =
    Decode.map2 (|>)


cardDecoder : Decoder Card
cardDecoder =
    Decode.map3 Card
        (Decode.field "state" Decode.string)
        (Decode.field "image" (Decode.nullable Decode.int))
        (Decode.field "bomb" Decode.bool)


layoutDecoder : Decoder Layout
layoutDecoder =
    Decode.map3 Layout
        (Decode.index 0 Decode.int)
        (Decode.index 1 Decode.int)
        (Decode.index 2 Decode.int)


playerDecoder : Decoder Player
playerDecoder =
    Decode.succeed Player
        |> andMap (Decode.field "id" Decode.string)
        |> andMap (Decode.field "name" (Decode.nullable Decode.string))
        |> andMap (Decode.field "color" Decode.string)
        |> andMap (Decode.field "color_name" Decode.string)
        |> andMap (Decode.field "score" Decode.int)
        |> andMap (Decode.field "accuracy" (Decode.nullable Decode.int))
        |> andMap (Decode.field "away" Decode.bool)
        |> andMap (Decode.field "dead" Decode.bool)
        |> andMap (Decode.field "failed_demining" Decode.bool)
        |> andMap (Decode.field "deminer" Decode.bool)



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ memoryJoined GotJoined
        , memoryState GotState
        , memoryJoinFailed GotJoinFailed
        , memoryWatchers GotWatchers
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


{-| The text in the language of the page. A text without a translation
stays in English.
-}
t : Texts -> String -> String
t texts english =
    Dict.get english texts |> Maybe.withDefault english


{-| The text in the language of the page, with the values in its `{name}`
parts.
-}
tf : Texts -> String -> List ( String, String ) -> String
tf texts english values =
    List.foldl (\( name, value ) result -> String.replace ("{" ++ name ++ "}") value result) (t texts english) values


view : Model -> Html Msg
view model =
    case model.connection of
        Connecting ->
            p [ id "memory-connecting", class "py-24 text-center opacity-60" ] [ text (t model.texts "Joining the game…") ]

        Failed reason ->
            p [ id "memory-failed", class "py-24 text-center text-red-600" ] [ text (tf model.texts "Could not join the game: {reason}" [ ( "reason", reason ) ]) ]

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
            -- are in one compact row. A message about the bombs slides in
            -- from the top of the screen over the row, so that the field
            -- does not move. On a large screen, the row is not a box
            -- (`contents`), so its items are in the column of the panel.
            [ div [ class "flex items-center gap-1 lg:contents" ]
                [ div [ class "min-w-0 lg:order-1" ]
                    [ div [ class "flex items-center gap-1 lg:gap-2" ]
                        [ a
                            [ id "memory-home"
                            , href "/"
                            , class "mr-1 shrink-0 transition hover:-translate-y-0.5 active:translate-y-0 lg:mr-0"
                            ]
                            [ img [ src "/images/mark.svg", alt "octomocto", class "h-8 w-auto dark:hidden lg:h-9" ] []
                            , img [ src "/images/mark-on-dark.svg", alt "octomocto", class "hidden h-8 w-auto dark:block lg:h-9" ] []
                            ]
                        , h1 [ class "text-xl font-semibold tracking-tight lg:text-2xl" ]
                            [ a [ id "memory-title-link", href model.indexUrl, class "transition hover:text-octo-indigo dark:hover:text-octo-indigo-light" ] [ text (t model.texts "Memory") ] ]
                        , case game.campaign of
                            Just campaign ->
                                span [ id "memory-level", class "shrink-0 rounded-full bg-octo-mist px-2.5 py-0.5 text-xs font-semibold whitespace-nowrap text-octo-indigo dark:bg-octo-indigo/15 dark:text-octo-indigo-light" ]
                                    [ text (tf model.texts "Level {level}" [ ( "level", String.fromInt campaign.level ) ]) ]

                            Nothing ->
                                text ""
                        , viewMuteButton model.texts model.muted
                        , viewWatchers model.texts model.watchers
                        ]
                    , p [ class "hidden text-sm opacity-60 lg:block" ]
                        [ text
                            (t model.texts
                                (if game.set == 2 then
                                    "Find the pairs of cards with the same image."

                                 else
                                    "Find the triplets of cards with the same image."
                                )
                            )
                        ]
                    ]
                , viewClock model game
                , if bombMessageShown game then
                    viewBombMessage model.texts me game True

                  else
                    text ""
                , if me == Nothing then
                    text ""

                  else
                    viewRestartButton model.texts (game.editing /= Nothing)
                ]
            , if bombMessageShown game then
                viewBombMessage model.texts me game False

              else
                text ""
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
                    [ text (t model.texts "This game is full, so you can only watch it.") ]

              else
                text ""
            , a
                [ id "memory-leaderboards-link"
                , href model.settingsUrl
                , class "hidden text-sm font-medium text-octo-indigo underline-offset-4 transition hover:underline lg:order-6 lg:block dark:text-octo-indigo-light"
                ]
                [ text
                    (t model.texts
                        (if game.campaign /= Nothing then
                            "Back to the map"

                         else
                            "Best results"
                        )
                    )
                ]
            ]
        , div [ class "min-w-0 flex-1" ]
            [ div [ id "memory-board", class "relative mx-auto lg:rounded-2xl lg:bg-white lg:p-2 lg:shadow-sm lg:ring-1 lg:ring-slate-200 dark:lg:bg-white/5 dark:lg:shadow-none dark:lg:ring-white/10", style "width" (fieldWidth model me game layout gap) ]
                [ viewField model me game layout gap
                , if game.waiting then
                    viewWaiting model.texts game

                  else if game.finished then
                    case game.campaign of
                        Just campaign ->
                            viewCampaignResult model me game campaign

                        Nothing ->
                            viewResult model me game

                  else
                    text ""
                ]
            ]
        ]


{-| The width of the screen from which the panel is at the left of the
field. On a smaller screen, the panel is a compact row above the field.
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
is above the field, so the field can be as wide as the screen.
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


{-| The height in pixels of the screen that is not for the field. The page
of a game has no header and no footer. On a large screen, it is the 1.5rem
padding of the page at the top and at the bottom, and the 0.5rem padding of
the board on each side. On a small
screen, it is the 0.5rem padding of the page at the top and at the bottom,
and the rows of the panel with the 0.5rem gaps between them. The heights of
the rows are approximate, because the scores can wrap.
-}
reservedHeight : Model -> Me -> Game -> Float
reservedHeight model me game =
    if Tuple.first model.viewport >= largeScreen then
        64

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


{-| The number of browsers that only watch the game, when there are any.
-}
viewWatchers : Texts -> Int -> Html Msg
viewWatchers texts count =
    if count > 0 then
        span
            [ id "memory-watchers"
            , class "flex shrink-0 items-center gap-1 text-sm tabular-nums text-slate-500 dark:text-slate-400"
            , Html.Attributes.title (tf texts "Watchers: {count}" [ ( "count", String.fromInt count ) ])
            ]
            [ span [ class "hero-eye size-4" ] [], text (String.fromInt count) ]

    else
        text ""


viewMuteButton : Texts -> Bool -> Html Msg
viewMuteButton texts muted =
    button
        [ id "memory-mute"
        , class "grid size-8 place-items-center rounded-full text-slate-500 transition hover:bg-slate-100 hover:text-slate-800 active:scale-90 dark:text-slate-400 dark:hover:bg-white/10 dark:hover:text-slate-100"
        , onClick ToggleMuted
        , Html.Attributes.title
            (t texts
                (if muted then
                    "Turn the sounds on"

                 else
                    "Turn the sounds off"
                )
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
screen, only the icon shows. It is disabled while a player changes the
settings.
-}
viewRestartButton : Texts -> Bool -> Html Msg
viewRestartButton texts locked =
    button
        [ id "memory-restart"
        , class "group flex size-9 shrink-0 items-center justify-center gap-2 rounded-full text-sm font-medium text-slate-600 ring-1 ring-slate-200 transition hover:bg-slate-50 hover:text-slate-900 hover:ring-slate-300 active:scale-95 disabled:pointer-events-none disabled:opacity-50 lg:order-5 lg:size-auto lg:self-start lg:px-4 lg:py-2 dark:text-slate-300 dark:ring-white/20 dark:hover:bg-white/10 dark:hover:text-white dark:hover:ring-white/30"
        , onClick Restart
        , disabled locked
        , Html.Attributes.title (t texts "Restart game")
        ]
        [ span [ class "hero-arrow-path size-4 transition-transform duration-300 group-hover:-rotate-180" ] []
        , span [ class "hidden lg:inline" ] [ text (t texts "Restart game") ]
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
                (t model.texts
                    (if model.copied then
                        "Copied!"

                     else
                        "Copy link"
                    )
                )
            ]
        ]


{-| The time, and for one player, the accuracy (with more players, it is
next to each score). In a field with bombs, the bombs that were seen, or
during a demining, the bombs that are face up. On a small screen, they are
small and without a box, at the right of the compact row of the panel.
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

        bombsUp =
            List.length (List.filter (\card -> card.bomb && card.state == "up") game.cards)

        columns =
            (if solo then
                2

             else
                1
            )
                + (if game.bombs > 0 then
                    1

                   else
                    0
                  )

        stat label valueId value =
            div [ class "flex flex-col items-center justify-center" ]
                [ span [ class "text-[0.625rem] font-medium tracking-wide text-slate-400 uppercase lg:text-xs" ] [ text (t model.texts label) ]
                , span [ id valueId, class "text-lg leading-tight font-light text-slate-700 tabular-nums lg:text-3xl dark:text-slate-100" ] [ text value ]
                ]
    in
    div
        [ id "memory-clock"
        , class "ml-auto flex gap-4 pr-2 lg:order-2 lg:ml-0 lg:grid lg:gap-0 lg:divide-x lg:divide-slate-200 lg:rounded-2xl lg:bg-white lg:py-3 lg:pr-0 lg:shadow-sm lg:ring-1 lg:ring-slate-200 dark:lg:divide-white/10 dark:lg:bg-white/5 dark:lg:shadow-none dark:lg:ring-white/10"
        , classList
            [ ( "lg:grid-cols-1", columns == 1 )
            , ( "lg:grid-cols-2", columns == 2 )
            , ( "lg:grid-cols-3", columns == 3 )
            ]
        ]
        [ stat "time" "memory-time" (formatTime elapsedMs)
        , if solo then
            stat "accuracy" "memory-accuracy" (formatAccuracy (List.head game.players |> Maybe.andThen .accuracy))

          else
            text ""
        , if game.bombs == 0 then
            text ""

          else if game.demining then
            stat "demining" "memory-bombs" (String.fromInt bombsUp ++ "/" ++ String.fromInt game.bombs)

          else
            stat "bombs" "memory-bombs" (String.fromInt game.bombsSeen ++ "/" ++ String.fromInt game.bombs)
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
                    , classList [ ( "opacity-50", player.away || player.dead ), ( "memory-current", current ) ]

                    -- Elm's `style` cannot set a CSS variable
                    , Html.Attributes.attribute "style" ("--player-color: " ++ player.color)
                    ]
                    [ span [ class "size-3 rounded-full", style "background" player.color ] []
                    , span [ class "lg:flex-1", classList [ ( "line-through", player.dead ) ] ] [ text (playerName model.texts me player) ]
                    , viewBadges model.texts player
                    , if current then
                        span [ class "text-xs font-medium tracking-wide uppercase", style "color" player.color ]
                            [ text
                                (t model.texts
                                    (if game.demining then
                                        "demining"

                                     else
                                        "turn"
                                    )
                                )
                            ]

                      else
                        text ""
                    , span [ class "font-semibold tabular-nums" ] [ text (String.fromInt player.score) ]
                    , span [ id ("memory-accuracy-" ++ player.id), class "text-xs text-slate-400 tabular-nums", Html.Attributes.title (t model.texts "Accuracy") ]
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


{-| A shield for a player who demined the field, and a bomb for a player
who is out
-}
viewBadges : Texts -> Player -> Html Msg
viewBadges texts player =
    span [ class "flex shrink-0 items-center gap-1 empty:hidden" ]
        [ if player.deminer then
            span [ class "hero-shield-check-solid size-4 text-amber-500", Html.Attributes.title (t texts "Deminer") ] []

          else
            text ""
        , if player.dead then
            img [ src bombImage, alt (t texts "Out"), Html.Attributes.title (t texts "Out"), class "size-4" ] []

          else
            text ""
        ]


bombImage : String
bombImage =
    "/images/memory/bomb.svg"


{-| A guest has the name of the color.
-}
playerName : Texts -> Me -> Player -> String
playerName texts me player =
    let
        name =
            Maybe.withDefault (t texts player.colorName) player.name
    in
    if isMe me player then
        tf texts "{name} (you)" [ ( "name", name ) ]

    else
        name


{-| The cards in a grid. A grid with an empty place has it in the middle.
-}
viewField : Model -> Me -> Game -> Layout -> Float -> Html Msg
viewField model me game layout gap =
    let
        cards =
            List.indexedMap (viewCard model me game) game.cards

        middle =
            List.length cards // 2

        places =
            if layout.gaps > 0 then
                List.take middle cards ++ div [] [] :: List.drop middle cards

            else
                cards
    in
    div
        [ id "memory-field"
        , class "grid"
        , style "gap" (String.fromFloat gap ++ "px")
        , style "grid-template-columns" ("repeat(" ++ String.fromInt layout.columns ++ ", minmax(0, 1fr))")
        ]
        places


viewCard : Model -> Me -> Game -> Int -> Card -> Html Msg
viewCard model me game index card =
    let
        face =
            case ( card.image, card.bomb ) of
                ( Just i, _ ) ->
                    Just (Picture i)

                ( Nothing, True ) ->
                    Just Bomb

                ( Nothing, False ) ->
                    Dict.get index model.images
    in
    button
        [ id ("memory-card-" ++ String.fromInt index)
        , class "memory-card aspect-square"
        , classList
            [ ( "is-up", card.state /= "down" )
            , ( "is-cleared", card.state == "cleared" )
            , ( "is-bomb", face == Just Bomb )
            , ( "is-clickable", canFlip me game (Just card) )
            ]
        , onClick (Flip index)
        ]
        [ div [ class "memory-card-inner" ]
            [ div [ class "memory-card-back" ] []
            , div [ class "memory-card-face" ]
                [ case face of
                    Just (Picture i) ->
                        img
                            [ src ("/images/memory/" ++ game.theme ++ "/" ++ String.fromInt i ++ ".svg")
                            , alt ""
                            , class "size-3/4 object-contain"
                            ]
                            []

                    Just Bomb ->
                        img [ src bombImage, alt "", class "size-3/4 object-contain" ] []

                    Nothing ->
                        text ""
                ]
            ]
        ]


{-| True while the player of the turn can demine the field or demines it
-}
bombMessageShown : Game -> Bool
bombMessageShown game =
    (game.offer || game.demining) && not game.finished


{-| The player of the turn turned the last bomb that was not seen, and can
demine the field: the next card decides. Or the player demines the field,
and the message shows the bombs that are face up. The message does not
cover the cards: on a small screen, it hangs from the top of the screen
over the compact row (`inRow`), else it is in the panel.
-}
viewBombMessage : Texts -> Me -> Game -> Bool -> Html Msg
viewBombMessage texts me game inRow =
    let
        bombsUp =
            List.length (List.filter (\card -> card.bomb && card.state == "up") game.cards)

        player =
            List.head (List.filter (\p -> Just p.id == game.turn) game.players)

        -- The text for the other players, with the name or the color
        ( named, colored ) =
            if game.demining then
                ( "{name} demines the field…", "The {color} player demines the field…" )

            else
                ( "{name} found the last bomb and can demine the field…", "The {color} player found the last bomb and can demine the field…" )

        message =
            if myTurn me game then
                if game.demining then
                    t texts "Demine the field now: turn all other bombs. A wrong card puts you out."

                else
                    t texts "You found the last bomb! Turn another bomb now to demine the field, or any other card to play on."

            else
                case player of
                    Just { name, colorName } ->
                        case name of
                            Just n ->
                                tf texts named [ ( "name", n ) ]

                            Nothing ->
                                tf texts colored [ ( "color", t texts colorName ) ]

                    Nothing ->
                        ""
    in
    div
        (if inRow then
            [ id "memory-bomb-message-row"
            -- It hangs from the top of the screen over the compact row, with
            -- the 0.5rem side padding of the page. It is at least as tall as
            -- the 0.5rem padding and the row, and taller only for a long text
            , class "memory-slide-in fixed inset-x-2 top-0 z-30 flex min-h-12 items-center gap-2 rounded-b-2xl bg-octo-indigo px-4 py-2 text-xs leading-tight font-medium text-white shadow-lg lg:hidden"
            ]

         else
            [ id "memory-bomb-message"
            , class "hidden items-center gap-3 rounded-2xl bg-octo-indigo px-4 py-2.5 text-sm font-medium text-white shadow-sm lg:order-2 lg:flex lg:py-3"
            ]
        )
        [ img
            [ src bombImage
            , alt ""
            , class "shrink-0 animate-bounce"
            , classList [ ( "size-6", inRow ), ( "size-8", not inRow ) ]
            ]
            []
        , p [ class "flex-1" ] [ text message ]
        , if game.demining then
            span
                [ id
                    ("memory-bomb-progress"
                        ++ (if inRow then
                                "-row"

                            else
                                ""
                           )
                    )
                , class "shrink-0 rounded-full bg-white/20 px-2 py-0.5 font-semibold tabular-nums"
                ]
                [ text (String.fromInt bombsUp ++ "/" ++ String.fromInt game.bombs) ]

          else
            text ""
        ]


{-| Covers the field until all players are in.
-}
viewWaiting : Texts -> Game -> Html Msg
viewWaiting texts game =
    div
        [ id "memory-waiting"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-3 rounded-2xl bg-octo-navy/80 p-4 text-center text-white"
        ]
        [ p [ class "text-3xl font-semibold" ] [ text (t texts "Waiting for players") ]
        , p [ id "memory-waiting-count", class "text-lg tabular-nums opacity-80" ]
            [ text
                (tf texts
                    "{players} of {needed} players are in"
                    [ ( "players", String.fromInt (List.length game.players) )
                    , ( "needed", String.fromInt game.playersNeeded )
                    ]
                )
            ]
        , p [ class "text-sm opacity-60" ] [ text (t texts "Send the link to the other players. The game starts when all of them are in.") ]
        ]


viewResult : Model -> Me -> Game -> Html Msg
viewResult model me game =
    let
        texts =
            model.texts

        players =
            game.players

        solo =
            List.length players == 1

        message =
            case ( solo, winners players ) of
                ( True, _ ) ->
                    if game.failed then
                        t texts "Boom!"

                    else
                        t texts "Done!"

                ( False, [ winner ] ) ->
                    if isMe me winner then
                        t texts "You win!"

                    else
                        case winner.name of
                            Just name ->
                                tf texts "{name} wins!" [ ( "name", name ) ]

                            Nothing ->
                                tf texts "The {color} player wins!" [ ( "color", t texts winner.colorName ) ]

                ( False, _ ) ->
                    t texts "It's a tie!"

        ranked =
            List.reverse (List.sortBy .score players)

        -- The player on the settings page. Nobody can start a field until
        -- that player is back.
        editor =
            game.editing
                |> Maybe.andThen (\editing -> List.head (List.filter (\player -> player.id == editing) players))

        locked =
            editor /= Nothing
    in
    div
        [ id "memory-result"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-4 rounded-2xl bg-octo-navy/70 p-4 text-white backdrop-blur-sm"
        ]
        [ p [ class "text-3xl font-semibold" ] [ text message ]
        , p [ id "memory-final-time", class "text-lg tabular-nums opacity-80" ]
            [ text
                (tf texts "Time {time}" [ ( "time", formatTime game.elapsedMs ) ]
                    ++ (if solo then
                            " · " ++ tf texts "Accuracy {accuracy}" [ ( "accuracy", formatAccuracy (List.head players |> Maybe.andThen .accuracy) ) ]

                        else
                            ""
                       )
                )
            ]
        , if solo && game.failed then
            p [ id "memory-exploded", class "text-sm text-white/80" ]
                [ text
                    (t texts
                        (if List.any .failedDemining players then
                            "The demining failed: the last card was not a bomb."

                         else
                            "You turned a bomb that was seen."
                        )
                    )
                ]

          else if solo && List.any .deminer players then
            p [ id "memory-deminer", class "flex items-center gap-1.5 text-sm font-medium text-amber-300" ]
                [ span [ class "hero-shield-check-solid size-5" ] [], text (t texts "You demined the field!") ]

          else if game.bombs > 0 && not (List.any .deminer players) then
            p [ id "memory-not-demined", class "flex items-center gap-1.5 text-sm text-white/80" ]
                [ img [ src bombImage, alt "", class "size-5" ] [], text (t texts "The field wasn't demined.") ]

          else
            text ""
        , if solo then
            text ""

          else
            ol [ class "flex flex-col gap-1 text-sm" ]
                (List.map
                    (\player ->
                        li [ class "flex items-center gap-2" ]
                            [ span [ class "size-3 rounded-full", style "background" player.color ] []
                            , span [ class "flex-1" ] [ text (playerName texts me player) ]
                            , viewBadges texts player
                            , span [ class "pl-6 font-semibold tabular-nums" ] [ text (String.fromInt player.score) ]
                            , span [ class "w-10 text-right tabular-nums opacity-70", Html.Attributes.title (t texts "Accuracy") ] [ text (formatAccuracy player.accuracy) ]
                            ]
                    )
                    ranked
                )
        , case editor of
            Just player ->
                p [ id "memory-editing", class "animate-pulse text-sm text-white/80" ]
                    [ text
                        (case player.name of
                            Just name ->
                                tf texts "{name} changes the settings…" [ ( "name", name ) ]

                            Nothing ->
                                tf texts "The {color} player changes the settings…" [ ( "color", t texts player.colorName ) ]
                        )
                    ]

            Nothing ->
                text ""
        , if me == Nothing then
            text ""

          else
            div [ class "flex flex-wrap items-center justify-center gap-3" ]
                [ button
                    [ id "memory-play-again"
                    , class "rounded-full bg-white px-6 py-2.5 font-medium text-octo-indigo shadow-lg transition hover:-translate-y-0.5 hover:bg-octo-mist active:translate-y-0 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:translate-y-0 disabled:hover:bg-white"
                    , onClick Restart
                    , disabled locked
                    ]
                    [ text (t texts "Play again") ]
                , if locked then
                    span
                        [ id "memory-change-settings"
                        , attribute "aria-disabled" "true"
                        , class "cursor-not-allowed rounded-full px-5 py-2.5 font-medium text-white opacity-50 ring-1 ring-white/40"
                        ]
                        [ text (t texts "Change settings") ]

                  else
                    a
                        [ id "memory-change-settings"
                        , href model.changeSettingsUrl
                        , class "rounded-full px-5 py-2.5 font-medium text-white ring-1 ring-white/40 transition hover:-translate-y-0.5 hover:bg-white/10 active:translate-y-0"
                        ]
                        [ text (t texts "Change settings") ]
                ]
        , let
            -- In a game with other players, a player starts the next game for all of them
            ( element, action ) =
                if me /= Nothing && List.length game.players > 1 then
                    ( button, onClick StartNextGame )

                else
                    ( a, href model.nextGame.path )
          in
          element
            [ id "memory-next-game"
            , action
            , disabled locked
            , attribute "data-ga-link" "or_try"
            , attribute "data-ga-from" "Memory"
            , attribute "data-ga-to" model.nextGame.name
            , class "group text-sm font-medium text-white underline-offset-4 transition hover:underline disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:no-underline"
            ]
            [ text (tf texts "Or try {game}" [ ( "game", model.nextGame.name ) ] ++ " ")
            , span [ class "inline-block transition group-hover:translate-x-0.5" ] [ text "→" ]
            ]

        -- Only a guest who played gets the call to sign in, not a spectator
        , if model.guest && me /= Nothing then
            let
                -- The text around the link, which can be at any place of the text
                ( before, after ) =
                    case String.split "{sign_in}" (t texts "{sign_in} to keep your scores.") of
                        [ b, c ] ->
                            ( b, c )

                        _ ->
                            ( "", "" )
            in
            p [ id "memory-sign-in", class "text-sm text-white/70" ]
                [ text before
                , a
                    [ href "/signin"
                    , class "font-medium text-white underline underline-offset-4 transition hover:text-octo-mist"
                    ]
                    [ text (t texts "Sign in") ]
                , text after
                ]

          else
            text ""
        ]


{-| The end of a field of the campaign: after an error, the player tries
the level again. After a field with no errors, the player goes to the next
level.
-}
viewCampaignResult : Model -> Me -> Game -> Campaign -> Html Msg
viewCampaignResult model me game campaign =
    let
        texts =
            model.texts

        cleared =
            List.length (List.filter (\card -> card.state == "cleared") game.cards)

        last =
            campaign.level >= campaign.levels

        ( message, details ) =
            if game.failed then
                ( t texts "Wrong card!"
                , tf texts "You cleared {cleared} of {cards} cards." [ ( "cleared", String.fromInt cleared ), ( "cards", String.fromInt (List.length game.cards) ) ]
                )

            else if last then
                ( t texts "You finished the campaign!", tf texts "Time {time}" [ ( "time", formatTime game.elapsedMs ) ] )

            else
                ( t texts "Perfect!"
                , tf texts "Level {level} done" [ ( "level", String.fromInt campaign.level ) ]
                    ++ " · "
                    ++ tf texts "Time {time}" [ ( "time", formatTime game.elapsedMs ) ]
                )

        primary =
            "rounded-full bg-white px-6 py-2.5 font-medium text-octo-indigo shadow-lg transition hover:-translate-y-0.5 hover:bg-octo-mist active:translate-y-0"
    in
    div
        [ id "memory-result"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-4 rounded-2xl bg-octo-navy/70 p-4 text-center text-white backdrop-blur-sm"
        ]
        [ p [ class "text-3xl font-semibold" ] [ text message ]
        , p [ id "memory-final-time", class "text-lg tabular-nums opacity-80" ] [ text details ]
        , if me == Nothing then
            text ""

          else
            div [ class "flex flex-wrap items-center justify-center gap-3" ]
                [ if game.failed then
                    button [ id "memory-retry", class primary, onClick Restart ] [ text (t texts "Try again") ]

                  else if last then
                    text ""

                  else
                    button [ id "memory-next-level", class primary, onClick StartNextLevel ] [ text (t texts "Next level") ]
                , a
                    [ id "memory-campaign-map"
                    , href model.settingsUrl
                    , class "rounded-full px-5 py-2.5 font-medium text-white ring-1 ring-white/40 transition hover:-translate-y-0.5 hover:bg-white/10 active:translate-y-0"
                    ]
                    [ text (t texts "Back to the map") ]
                ]
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
