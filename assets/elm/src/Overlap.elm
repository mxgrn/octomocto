port module Overlap exposing (main)

{-| Multiplayer Overlap: any two cards have exactly one symbol in common.
Find it first to win the card.

The server owns the game: the cards, the deck and the scores. This module
draws the state that comes in through ports and sends the player's taps
out. app.js connects the ports to a Phoenix channel.

The table has two cards: the top card of the pile at the left (or at the
top, on a narrow screen) and the card to win. Each card has 8 symbols: one
in the middle and 7 in a ring around it. The server gives each symbol its
size and turn, so that all players see the same cards.

The player taps a symbol on one of the cards. The common symbol goes to the
server, which gives the card to the first player who taps it. The won card
then slides onto the pile, and a new card comes. A wrong symbol shakes and
blocks the taps for 1 second. It also goes to the server, which blocks the
taps of the player too, so that a player cannot find the symbol by tapping
all symbols fast.

All players race on the same cards. Before all of them are in, nobody sees
the cards. A countdown with beeps comes before each deck. A browser that
joins a full game only watches: it has no player id.

The module compares each new state with the old one and sends the names of
the sounds to play out through a port. The player can mute the sounds.

-}

import Array exposing (Array)
import Browser
import Browser.Dom
import Browser.Events
import Html exposing (Html, a, aside, button, div, h1, img, input, li, ol, p, span, text, ul)
import Html.Attributes exposing (alt, attribute, class, classList, href, id, readonly, src, style, value)
import Html.Events exposing (onClick)
import Html.Keyed
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Process
import Task
import Time



-- PORTS


port overlapTap : Encode.Value -> Cmd msg


port overlapRestart : () -> Cmd msg


{-| Starts the next game for all players, see OctomoctoWeb.NextGame
-}
port overlapNextGame : () -> Cmd msg


port overlapCopyText : String -> Cmd msg


port overlapJoined : (Decode.Value -> msg) -> Sub msg


port overlapState : (Decode.Value -> msg) -> Sub msg


port overlapJoinFailed : (String -> msg) -> Sub msg


{-| The number of browsers that only watch the game, after the join and
after each change.
-}
port overlapWatchers : (Int -> msg) -> Sub msg


port overlapPlaySound : String -> Cmd msg


port overlapSaveMuted : Bool -> Cmd msg



-- MODEL


{-| The `name` is the display name of a signed-in player, or Nothing for a
guest. Then the player is known by the `colorName`. An `away` player lost
the connection, and can come back for a short time.
-}
type alias Player =
    { id : String
    , name : Maybe String
    , color : String
    , colorName : String
    , score : Int
    , away : Bool
    }


type alias Symbol =
    Int


{-| A symbol on a card. The `size` is from 0.6 to 1 of the room of its
place, and `rotate` is its turn in degrees.
-}
type alias Placed =
    { symbol : Symbol
    , size : Float
    , rotate : Int
    }


{-| The first symbol is in the middle, and the others are in a ring that is
turned by `turn` degrees.
-}
type alias Card =
    { id : Int
    , symbols : List Placed
    , turn : Int
    }


{-| The last symbol that a player found, with the color of the player
-}
type alias Found =
    { playerId : String
    , color : String
    , symbol : Symbol
    }


type alias Game =
    { -- Nothing before the start and during the countdown
      pile : Maybe Card
    , card : Maybe Card
    , cardsLeft : Int
    , last : Maybe Found

    -- True until the game has all its players
    , waiting : Bool
    , finished : Bool

    -- The time since the start, below zero during the countdown. After the
    -- end, the final time.
    , elapsedMs : Int
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


{-| The game to try next, on the end screen
-}
type alias NextGame =
    { name : String
    , path : String
    }


{-| The symbol that the player tapped on the card, while it shakes
-}
type alias WrongTap =
    { card : Int
    , symbol : Symbol
    }


type alias Model =
    { gameUrl : String
    , settingsUrl : String
    , nextGame : NextGame
    , guest : Bool

    -- The names of the symbols, for the screen readers
    , names : Array String
    , connection : Connection
    , copied : Bool

    -- The last wrong symbol, while it shakes. The taps are blocked while
    -- `frozen` is True. The number tells the wrong taps apart, so that the
    -- end of an old block does not stop a new one.
    , wrong : Maybe WrongTap
    , frozen : Bool
    , wrongCount : Int

    -- The local time (in ms) when the deck started, and the local time now.
    -- The clock ticks between the server updates.
    , clockStart : Int
    , now : Int

    -- The countdown step that last played its beep (see `countdownStep`)
    , beepedStep : Maybe Int

    -- The size of the window, to pick the shape of the table
    , viewport : ( Float, Float )
    , muted : Bool
    , watchers : Int
    }


type alias Flags =
    { gameUrl : String
    , settingsUrl : String
    , nextGame : NextGame
    , guest : Bool
    , muted : Bool
    , symbols : List String
    }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { gameUrl = flags.gameUrl
      , settingsUrl = flags.settingsUrl
      , nextGame = flags.nextGame
      , guest = flags.guest
      , names = Array.fromList flags.symbols
      , connection = Connecting
      , copied = False
      , wrong = Nothing
      , frozen = False
      , wrongCount = 0
      , clockStart = 0
      , now = 0
      , beepedStep = Nothing
      , viewport = ( 1024, 768 )
      , muted = flags.muted
      , watchers = 0
      }
    , Task.perform (\vp -> Resized vp.viewport.width vp.viewport.height) Browser.Dom.getViewport
    )



-- UPDATE


type Msg
    = GotJoined Decode.Value
    | GotState Decode.Value
    | GotJoinFailed String
    | GotWatchers Int
    | Tap Int Symbol
    | ShakeDone Int
    | Unfreeze Int
    | Restart
    | StartNextGame
    | CopyLink
    | CopiedTimeout
    | SyncClock Int Time.Posix
    | Tick Time.Posix
    | Resized Float Float
    | ToggleMuted


{-| How long the taps are blocked after a wrong symbol
-}
freezeMs : Float
freezeMs =
    1000


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
                    ( { model
                        | connection = Joined me game

                        -- A new deck starts without a block
                        , frozen = model.frozen && game.cardsLeft <= old.cardsLeft
                      }
                    , Cmd.batch [ syncClock game, playSounds model (stateSounds me old game) ]
                    )

                _ ->
                    ( model, Cmd.none )

        GotJoinFailed reason ->
            ( { model | connection = Failed reason }, Cmd.none )

        GotWatchers count ->
            ( { model | watchers = count }, Cmd.none )

        Tap cardId symbol ->
            case ( model.connection, onTable model ) of
                ( Joined me game, Just ( pile, card ) ) ->
                    if canPlay me game && not model.frozen then
                        tap pile card cardId symbol model

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        ShakeDone count ->
            if count == model.wrongCount then
                ( { model | wrong = Nothing }, Cmd.none )

            else
                ( model, Cmd.none )

        Unfreeze count ->
            if count == model.wrongCount then
                ( { model | frozen = False }, Cmd.none )

            else
                ( model, Cmd.none )

        Restart ->
            ( model, overlapRestart () )

        StartNextGame ->
            ( model, overlapNextGame () )

        CopyLink ->
            ( { model | copied = True }
            , Cmd.batch
                [ overlapCopyText model.gameUrl
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
            ( { model | muted = not model.muted }, overlapSaveMuted (not model.muted) )


{-| The common symbol goes to the server, which checks it again. A wrong
symbol shakes and blocks the taps at once, and also goes to the server.
-}
tap : Card -> Card -> Int -> Symbol -> Model -> ( Model, Cmd Msg )
tap pile card cardId symbol model =
    let
        send =
            overlapTap
                (Encode.object
                    [ ( "pile", Encode.int pile.id )
                    , ( "card", Encode.int card.id )
                    , ( "symbol", Encode.int symbol )
                    ]
                )

        count =
            model.wrongCount + 1
    in
    if common pile card == Just symbol then
        ( model, send )

    else
        ( { model | wrong = Just (WrongTap cardId symbol), frozen = True, wrongCount = count }
        , Cmd.batch
            [ send
            , playSounds model [ "wrong" ]
            , Process.sleep 400 |> Task.perform (\_ -> ShakeDone count)
            , Process.sleep freezeMs |> Task.perform (\_ -> Unfreeze count)
            ]
        )


{-| The two cards on the table, after the countdown
-}
onTable : Model -> Maybe ( Card, Card )
onTable model =
    case model.connection of
        Joined _ game ->
            Maybe.map2 Tuple.pair game.pile game.card

        _ ->
            Nothing


{-| The symbol that the two cards have in common
-}
common : Card -> Card -> Maybe Symbol
common a b =
    let
        symbols card =
            List.map .symbol card.symbols
    in
    List.filter (\symbol -> List.member symbol (symbols b)) (symbols a) |> List.head


{-| A player can tap symbols while the cards are on the screen
-}
canPlay : Me -> Game -> Bool
canPlay me game =
    me /= Nothing && not game.waiting && not game.finished && game.card /= Nothing


{-| The seconds left in the countdown (3, 2, 1), 0 after it, and Nothing
when no deck runs. The step is right only after the clock is in sync.
-}
countdownStep : Model -> Maybe Int
countdownStep model =
    case model.connection of
        Joined _ game ->
            if game.waiting || game.finished then
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
        Cmd.batch (List.map overlapPlaySound names)


{-| The sounds for the change from the old state to the new one: a card that
I won or that another player won, and the end of the game.
-}
stateSounds : Me -> Game -> Game -> List String
stateSounds me old new =
    let
        foundSound =
            case new.last of
                Just found ->
                    if new.cardsLeft >= old.cardsLeft || new.finished then
                        []

                    else if me == Just found.playerId then
                        [ "found" ]

                    else
                        [ "other_found" ]

                Nothing ->
                    []

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
    foundSound ++ endSound


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


{-| Adds one more field to a decoder, for records with more than 8 fields
-}
andMap : Decoder a -> Decoder (a -> b) -> Decoder b
andMap =
    Decode.map2 (|>)


gameDecoder : Decoder Game
gameDecoder =
    Decode.succeed Game
        |> andMap (Decode.field "pile" (Decode.nullable cardDecoder))
        |> andMap (Decode.field "card" (Decode.nullable cardDecoder))
        |> andMap (Decode.field "cards_left" Decode.int)
        |> andMap (Decode.field "last" (Decode.nullable foundDecoder))
        |> andMap (Decode.field "waiting" Decode.bool)
        |> andMap (Decode.field "finished" Decode.bool)
        |> andMap (Decode.field "elapsed_ms" Decode.int)
        |> andMap (Decode.field "players" (Decode.list playerDecoder))
        |> andMap (Decode.field "players_needed" Decode.int)


cardDecoder : Decoder Card
cardDecoder =
    Decode.map3 Card
        (Decode.field "id" Decode.int)
        (Decode.field "symbols"
            (Decode.list
                (Decode.map3 Placed
                    (Decode.field "symbol" Decode.int)
                    (Decode.field "size" Decode.float)
                    (Decode.field "rotate" Decode.int)
                )
            )
        )
        (Decode.field "turn" Decode.int)


foundDecoder : Decoder Found
foundDecoder =
    Decode.map3 Found
        (Decode.field "player_id" Decode.string)
        (Decode.field "color" Decode.string)
        (Decode.field "symbol" Decode.int)


playerDecoder : Decoder Player
playerDecoder =
    Decode.map6 Player
        (Decode.field "id" Decode.string)
        (Decode.field "name" (Decode.nullable Decode.string))
        (Decode.field "color" Decode.string)
        (Decode.field "color_name" Decode.string)
        (Decode.field "score" Decode.int)
        (Decode.field "away" Decode.bool)



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ overlapJoined GotJoined
        , overlapState GotState
        , overlapJoinFailed GotJoinFailed
        , overlapWatchers GotWatchers
        , Browser.Events.onResize (\w h -> Resized (toFloat w) (toFloat h))
        , case model.connection of
            Joined _ game ->
                -- The cards come only after the countdown, so a table with
                -- no cards means a countdown. It ticks on each frame, so
                -- that the beeps are on time.
                if not game.waiting && not game.finished && game.card == Nothing then
                    Browser.Events.onAnimationFrame Tick

                else if not game.waiting && not game.finished then
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
            p [ id "overlap-connecting", class "py-24 text-center opacity-60" ] [ text "Joining the game…" ]

        Failed reason ->
            p [ id "overlap-failed", class "py-24 text-center text-red-600" ] [ text ("Could not join the game: " ++ reason) ]

        Joined me game ->
            viewGame model me game


viewGame : Model -> Me -> Game -> Html Msg
viewGame model me game =
    let
        width =
            tableWidth model me game

        countdown =
            Maybe.withDefault 0 (countdownStep model)
    in
    div
        [ id "overlap-root"
        , class "flex w-full max-w-[1400px] flex-col gap-2 select-none max-lg:landscape:flex-row max-lg:landscape:items-start max-lg:landscape:gap-3 lg:flex-row lg:items-start lg:gap-8"
        , classList [ ( "is-playing", playing game ) ]
        ]
        [ aside [ id "overlap-panel", class "flex flex-col gap-2 max-lg:landscape:w-44 max-lg:landscape:shrink-0 max-lg:landscape:gap-3 lg:sticky lg:top-6 lg:w-72 lg:shrink-0 lg:gap-4" ]
            -- On a small screen, the title, the stats and the restart
            -- button are in one compact row. On a small screen that is
            -- wider than tall, they are in a narrow column at the left of
            -- the cards, so the cards can be as tall as the screen. On a
            -- large screen, the row is not a box (`contents`), so its items
            -- are in the column of the panel.
            [ div [ class "flex items-center gap-1 max-lg:landscape:flex-col max-lg:landscape:items-start max-lg:landscape:gap-3 lg:contents" ]
                [ div [ class "min-w-0 lg:order-1" ]
                    [ div [ class "flex items-center gap-1 lg:gap-2" ]
                        [ a
                            [ id "overlap-home"
                            , href "/"
                            , class "mr-1 shrink-0 transition hover:-translate-y-0.5 active:translate-y-0 lg:mr-0"
                            ]
                            [ img [ src "/images/mark.svg", alt "octomocto", class "h-8 w-auto dark:hidden lg:h-9" ] []
                            , img [ src "/images/mark-on-dark.svg", alt "octomocto", class "hidden h-8 w-auto dark:block lg:h-9" ] []
                            ]
                        , h1 [ class "text-xl font-semibold tracking-tight lg:text-2xl" ]
                            [ a [ id "overlap-title-link", href "/overlap", class "transition hover:text-octo-indigo dark:hover:text-octo-indigo-light" ] [ text "Overlap" ] ]
                        , viewMuteButton model.muted
                        , viewWatchers model.watchers
                        ]
                    , p [ class "hidden text-sm opacity-60 lg:block" ]
                        [ text "Find the one symbol that the two cards have in common." ]
                    ]
                , viewClock model game
                , if me == Nothing then
                    text ""

                  else
                    viewRestartButton
                ]

            -- The link is only for the players who did not join yet
            , if game.playersNeeded > 1 && not (playing game) then
                viewShareLink model

              else
                text ""
            , if List.length game.players > 1 then
                viewScores me game

              else
                text ""
            , if me == Nothing then
                p [ id "overlap-watching", class "rounded-2xl bg-amber-50 px-4 py-3 text-sm text-amber-900 ring-1 ring-amber-200 lg:order-7 dark:bg-amber-400/10 dark:text-amber-200 dark:ring-amber-400/25" ]
                    [ text "This game is full, so you can only watch it." ]

              else
                text ""
            ]
        , div [ class "min-w-0 flex-1" ]
            [ div [ class "relative mx-auto", style "width" width ]
                [ viewTable model me game
                , if game.waiting then
                    viewWaiting game

                  else if game.finished then
                    viewResult model.settingsUrl model.nextGame model.guest me game

                  else if countdown > 0 || game.card == Nothing then
                    viewCountdown countdown

                  else
                    text ""
                ]
            ]
        ]


{-| True from the countdown until the end of the game. Then the page does
not scroll.
-}
playing : Game -> Bool
playing game =
    not game.waiting && not game.finished


{-| The width of the screen from which the panel is at the left of the
cards. On a smaller screen, the panel is a compact row above the cards.
-}
largeScreen : Float
largeScreen =
    1024


{-| A small screen that is wider than tall. The panel is a narrow column at
the left of the cards, as the `max-lg:landscape:` classes make it.
-}
sideways : Model -> Bool
sideways model =
    let
        ( width, height ) =
            model.viewport
    in
    width < largeScreen && width > height


{-| On a narrow screen that is taller than wide, the cards are one above
the other. Else they are side by side.
-}
stacked : Model -> Bool
stacked model =
    let
        ( width, height ) =
            model.viewport
    in
    width < 640 && height > width


{-| The gap in pixels between the cards, as the `gap-3 sm:gap-6` classes of
the table make it
-}
cardGap : Model -> Float
cardGap model =
    if Tuple.first model.viewport >= 640 then
        24

    else
        12


{-| The height in pixels of the screen that is not for the cards. The page
of a game has no header and no footer. On a large screen, the panel is at
the left, so it is the 1.5rem padding of the page at the top and at the
bottom. On a small screen that is wider than tall, the panel is also at the
left, so it is the 0.5rem padding of the page at the top and at the bottom.
On other small screens, it is the padding, and the rows of the panel with
the 0.5rem gaps between them. The heights of the rows are approximate,
because the text can wrap.
-}
reservedHeight : Model -> Me -> Game -> Float
reservedHeight model me game =
    let
        row condition rowHeight =
            if condition then
                rowHeight + 8

            else
                0
    in
    if Tuple.first model.viewport >= largeScreen then
        48

    else if sideways model then
        16

    else
        16
            + row True 40
            + row (game.playersNeeded > 1 && not (playing game)) 40
            + row (List.length game.players > 1) 30
            + row (me == Nothing) 44


{-| Make the cards as large as possible, but small enough that both are on
the screen, and never larger than 30rem.
-}
tableWidth : Model -> Me -> Game -> String
tableWidth model me game =
    let
        px value =
            String.fromFloat value ++ "px"

        gap =
            cardGap model

        free =
            "(100dvh - " ++ px (reservedHeight model me game) ++ ")"
    in
    if stacked model then
        "min(100%, 30rem, calc((" ++ free ++ " - " ++ px gap ++ ") / 2))"

    else
        "min(100%, calc(60rem + " ++ px gap ++ "), calc(" ++ free ++ " * 2 + " ++ px gap ++ "))"


{-| The number of browsers that only watch the game, when there are any.
-}
viewWatchers : Int -> Html Msg
viewWatchers count =
    if count > 0 then
        span
            [ id "overlap-watchers"
            , class "flex shrink-0 items-center gap-1 text-sm tabular-nums text-slate-500 dark:text-slate-400"
            , Html.Attributes.title ("Watchers: " ++ String.fromInt count)
            ]
            [ span [ class "hero-eye size-4" ] [], text (String.fromInt count) ]

    else
        text ""


viewMuteButton : Bool -> Html Msg
viewMuteButton muted =
    button
        [ id "overlap-mute"
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


{-| Starts a new deck for all players, also during a game. On a small
screen, only the icon shows, but not in the column of a screen that is wider
than tall.
-}
viewRestartButton : Html Msg
viewRestartButton =
    button
        [ id "overlap-restart"
        , class "group flex size-9 shrink-0 items-center justify-center gap-2 rounded-full text-sm font-medium text-slate-600 ring-1 ring-slate-200 transition hover:bg-slate-50 hover:text-slate-900 hover:ring-slate-300 active:scale-95 max-lg:landscape:size-auto max-lg:landscape:px-4 max-lg:landscape:py-2 lg:order-7 lg:size-auto lg:self-start lg:px-4 lg:py-2 dark:text-slate-300 dark:ring-white/20 dark:hover:bg-white/10 dark:hover:text-white dark:hover:ring-white/30"
        , onClick Restart
        , Html.Attributes.title "Restart game"
        ]
        [ span [ class "hero-arrow-path size-4 transition-transform duration-300 group-hover:-rotate-180" ] []
        , span [ class "hidden max-lg:landscape:inline lg:inline" ] [ text "Restart game" ]
        ]


viewShareLink : Model -> Html Msg
viewShareLink model =
    div [ class "flex items-center gap-2 rounded-full bg-octo-mist p-1 pl-4 text-sm ring-1 ring-octo-indigo/20 max-lg:landscape:flex-col max-lg:landscape:items-stretch max-lg:landscape:rounded-2xl max-lg:landscape:p-2 lg:order-3 lg:flex-col lg:items-stretch lg:rounded-2xl lg:p-2 lg:pl-2 dark:bg-octo-indigo/15 dark:ring-octo-indigo-light/25" ]
        [ input
            [ id "overlap-link"
            , readonly True
            , value model.gameUrl
            , class "min-w-0 flex-1 truncate bg-transparent text-octo-navy outline-none max-lg:landscape:px-2 max-lg:landscape:py-1 lg:px-2 lg:py-1 dark:text-slate-100"
            ]
            []
        , button
            [ id "overlap-copy-link"
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


{-| The time on the left, and the cards that the players can still win on
the right. On a small screen, they are small and without a box, at the
right of the compact row of the panel, or under the title in the column of
a screen that is wider than tall.
-}
viewClock : Model -> Game -> Html Msg
viewClock model game =
    let
        elapsedMs =
            if game.finished then
                game.elapsedMs

            else if game.waiting then
                0

            else
                max 0 (model.now - model.clockStart)

        stat label valueId valueClass value =
            div [ class "flex flex-col items-center justify-center max-lg:landscape:items-start" ]
                [ span [ class "text-[0.625rem] font-medium tracking-wide text-slate-400 uppercase lg:text-xs" ] [ text label ]
                , span [ id valueId, class ("text-lg leading-tight tabular-nums lg:text-3xl " ++ valueClass) ] [ text value ]
                ]
    in
    div [ id "overlap-clock", class "ml-auto flex gap-4 pr-2 max-lg:landscape:ml-0 max-lg:landscape:gap-6 max-lg:landscape:pr-0 max-lg:landscape:pl-2 lg:order-2 lg:ml-0 lg:grid lg:grid-cols-2 lg:gap-0 lg:divide-x lg:divide-slate-200 lg:rounded-2xl lg:bg-white lg:py-3 lg:pr-0 lg:shadow-sm lg:ring-1 lg:ring-slate-200 dark:lg:divide-white/10 dark:lg:bg-white/5 dark:lg:shadow-none dark:lg:ring-white/10" ]
        [ stat "time" "overlap-time" "font-light text-slate-700 dark:text-slate-100" (formatTime elapsedMs)
        , stat "cards" "overlap-cards-left" "font-bold text-octo-indigo dark:text-octo-indigo-light" (String.fromInt game.cardsLeft)
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


{-| The players in the order in which they joined, with the cards they won
-}
viewScores : Me -> Game -> Html Msg
viewScores me game =
    ul [ id "overlap-scores", class "flex flex-wrap gap-2 max-lg:landscape:flex-col lg:order-4 lg:flex-col" ]
        (List.map
            (\player ->
                li
                    [ id ("overlap-score-" ++ player.id)
                    , class "flex items-center gap-2 rounded-full bg-white px-3 py-1 text-sm text-slate-800 shadow-sm ring-1 ring-slate-200 transition dark:bg-white/5 dark:text-slate-100 dark:shadow-none dark:ring-white/10"
                    , classList [ ( "opacity-50", player.away ) ]
                    ]
                    [ span [ class "size-3 rounded-full", style "background" player.color ] []
                    , span [ class "max-lg:landscape:flex-1 lg:flex-1" ] [ text (playerName me player) ]
                    , span [ class "font-semibold tabular-nums" ] [ text (String.fromInt player.score) ]
                    ]
            )
            game.players
        )


playerName : Me -> Player -> String
playerName me player =
    if isMe me player then
        Maybe.withDefault player.colorName player.name ++ " (you)"

    else
        Maybe.withDefault player.colorName player.name



-- CARDS


{-| The pile and the card to win. Before the start, two empty places keep
the size of the table under the cover.

The cards are keyed by their ids and places. A won card is a new element
on the pile, so that it slides there from the place of the card. A new card
is dealt with an animation. The block after a wrong symbol shows as a bar
under the cards that gets shorter. It is keyed, so that it starts again on
each wrong symbol.

-}
viewTable : Model -> Me -> Game -> Html Msg
viewTable model me game =
    let
        playable =
            canPlay me game && not model.frozen

        cards =
            case ( game.pile, game.card ) of
                ( Just pile, Just card ) ->
                    [ ( "pile-" ++ String.fromInt pile.id
                      , viewCard model
                            playable
                            [ ( "overlap-to-pile", game.last /= Nothing && not game.finished ) ]
                            (Maybe.map .symbol game.last |> Maybe.map (\symbol -> ( symbol, lastColor game )))
                            pile
                      )
                    , ( "card-" ++ String.fromInt card.id
                      , viewCard model
                            playable
                            []
                            -- After the end, the last symbol is on both
                            -- cards. Before that, it could give a clue.
                            (if game.finished then
                                Maybe.map (\found -> ( found.symbol, found.color )) game.last

                             else
                                Nothing
                            )
                            card
                      )
                    ]

                _ ->
                    List.map (\place -> ( "empty-" ++ place, div [ class "overlap-card is-empty" ] [] )) [ "pile", "card" ]
    in
    div []
        [ Html.Keyed.node "div"
            [ id "overlap-table"
            , class "grid gap-3 sm:gap-6"

            -- For the slide of a won card onto the pile. The `style` function
            -- cannot set a CSS variable.
            , Html.Attributes.attribute "style" ("--gap: " ++ String.fromFloat (cardGap model) ++ "px")
            , classList
                [ ( "grid-cols-2", not (stacked model) )
                , ( "is-stacked", stacked model )
                , ( "is-frozen", canPlay me game && model.frozen )
                ]
            ]
            cards
        , Html.Keyed.node "div"
            [ class "mx-auto mt-3 h-1 w-1/3 overflow-hidden rounded-full" ]
            [ ( String.fromInt model.wrongCount
              , if model.frozen && canPlay me game then
                    div [ id "overlap-freeze", class "overlap-freeze h-full rounded-full bg-red-500" ] []

                else
                    text ""
              )
            ]
        ]


lastColor : Game -> String
lastColor game =
    Maybe.map .color game.last |> Maybe.withDefault "#1a9fcb"


{-| The room of the place of a symbol, as a part of the radius of the card,
and the distance of the ring from the middle. The 7 places of the ring
touch each other, and the place in the middle is a bit larger.
-}
middleRoom : Float
middleRoom =
    0.36


ringRoom : Float
ringRoom =
    0.27


ringDistance : Float
ringDistance =
    0.66


viewCard : Model -> Bool -> List ( String, Bool ) -> Maybe ( Symbol, String ) -> Card -> Html Msg
viewCard model playable classes highlight card =
    div
        [ id ("overlap-card-" ++ String.fromInt card.id)
        , class "overlap-card"
        , classList (( "is-playable", playable ) :: classes)
        ]
        (List.indexedMap (viewSymbol model playable highlight card) card.symbols)


{-| A symbol at its place on the card. The tap area is the box of the
image. The turn is on the button and the shake on the image, so that the
two do not clash.
-}
viewSymbol : Model -> Bool -> Maybe ( Symbol, String ) -> Card -> Int -> Placed -> Html Msg
viewSymbol model playable highlight card index placed =
    let
        ( x, y, room ) =
            if index == 0 then
                ( 0, 0, middleRoom )

            else
                let
                    angle =
                        degrees (toFloat card.turn + toFloat (index - 1) * 360 / 7)
                in
                ( ringDistance * cos angle, ringDistance * sin angle, ringRoom )

        percent value =
            String.fromFloat value ++ "%"

        name =
            Array.get placed.symbol model.names |> Maybe.withDefault "symbol"

        shaking =
            model.wrong == Just (WrongTap card.id placed.symbol)
    in
    button
        [ id ("overlap-symbol-" ++ String.fromInt card.id ++ "-" ++ String.fromInt placed.symbol)
        , class "overlap-symbol"
        , classList [ ( "is-wrong", shaking ) ]
        , Html.Attributes.attribute "style"
            (String.concat
                [ "left: "
                , percent (50 + 50 * x)
                , "; top: "
                , percent (50 + 50 * y)
                , "; width: "
                , percent (100 * room * placed.size * 0.95)
                , "; --turn: "
                , String.fromInt placed.rotate
                , "deg"
                ]
            )
        , Html.Attributes.disabled (not playable)
        , onClick (Tap card.id placed.symbol)
        , Html.Attributes.attribute "aria-label" name
        ]
        [ case highlight of
            Just ( symbol, color ) ->
                if symbol == placed.symbol then
                    span [ class "overlap-found", Html.Attributes.attribute "style" ("--found: " ++ color) ] []

                else
                    text ""

            Nothing ->
                text ""
        , img [ src ("/images/overlap/" ++ String.fromInt placed.symbol ++ ".svg"), alt "", Html.Attributes.attribute "draggable" "false" ] []
        ]



-- COVERS


{-| Covers the table until all players are in.
-}
viewWaiting : Game -> Html Msg
viewWaiting game =
    div
        [ id "overlap-waiting"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-3 rounded-2xl bg-octo-navy/80 p-4 text-center text-white"
        ]
        [ p [ class "text-3xl font-semibold" ] [ text "Waiting for players" ]
        , p [ id "overlap-waiting-count", class "text-lg tabular-nums opacity-80" ]
            [ text
                (String.fromInt (List.length game.players)
                    ++ " of "
                    ++ String.fromInt game.playersNeeded
                    ++ " players are in"
                )
            ]
        , p [ class "text-sm opacity-60" ] [ text "Send the link to the other players. The game starts when all of them are in." ]
        ]


{-| The number is keyed, so that it pops in again on each step.
-}
viewCountdown : Int -> Html Msg
viewCountdown seconds =
    div
        [ id "overlap-countdown"
        , class "absolute inset-0 flex items-center justify-center rounded-2xl bg-octo-navy/80"
        ]
        [ Html.Keyed.node "div"
            []
            [ ( String.fromInt seconds
              , p [ class "countdown-pop text-9xl font-bold text-white tabular-nums" ]
                    [ text
                        (if seconds > 0 then
                            String.fromInt seconds

                         else
                            ""
                        )
                    ]
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
        [ id "overlap-result"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-4 rounded-2xl bg-octo-navy/70 p-4 text-white backdrop-blur-sm"
        ]
        [ p [ class "text-3xl font-semibold" ] [ text message ]
        , p [ id "overlap-final-time", class "text-lg tabular-nums opacity-80" ]
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
                [ id "overlap-play-again"
                , class "rounded-full bg-white px-6 py-2.5 font-medium text-octo-indigo shadow-lg transition hover:-translate-y-0.5 hover:bg-octo-mist active:translate-y-0"
                , onClick Restart
                ]
                [ text "Play again" ]
        , a
            [ id "overlap-leaderboards-link"
            , href settingsUrl
            , class "text-sm font-medium text-white/80 underline-offset-4 transition hover:text-white hover:underline"
            ]
            [ text "Latest games and best results" ]
        , let
            -- In a game with other players, a player starts the next game for all of them
            ( element, action ) =
                if me /= Nothing && List.length game.players > 1 then
                    ( button, onClick StartNextGame )

                else
                    ( a, href nextGame.path )
          in
          element
            [ id "overlap-next-game"
            , action
            , attribute "data-ga-link" "or_try"
            , attribute "data-ga-from" "Overlap"
            , attribute "data-ga-to" nextGame.name
            , class "group text-sm font-medium text-white underline-offset-4 transition hover:underline"
            ]
            [ text ("Or try " ++ nextGame.name ++ " ")
            , span [ class "inline-block transition group-hover:translate-x-0.5" ] [ text "→" ]
            ]

        -- Only a guest who played gets the call to sign in, not a spectator
        , if guest && me /= Nothing then
            p [ id "overlap-sign-in", class "text-sm text-white/70" ]
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
