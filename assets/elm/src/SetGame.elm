port module SetGame exposing (main)

{-| Multiplayer Set: find 3 cards where each feature is the same on all
cards or different on all cards.

The server owns the game: the table, the deck and the scores. This module
draws the state that comes in through ports and sends the player's claims
out. app.js connects the ports to a Phoenix channel.

A card is an integer from 0 to 80. Its 4 features are its digits in base
3: the number of shapes, the shape, the shading and the color. Three cards
are a set when the sum of each digit can be divided by 3.

The player selects 3 cards. A set goes to the server, which gives the
point to the first player who claims it. A wrong set shakes and changes
nothing, so it does not go to the server.

All players race on the same table. Before all of them are in, nobody sees
the cards. A countdown with beeps comes before each table. A browser that
joins a full game only watches: it has no player id.

The module compares each new state with the old one and sends the names of
the sounds to play out through a port. The player can mute the sounds.

The module is not named `Set`, because elm/core has a `Set` module. The
port names start with "setGame", because Elm does not allow two ports with
the same name in one bundle.

-}

import Browser
import Browser.Dom
import Browser.Events
import Html exposing (Html, a, aside, button, div, h1, img, input, li, ol, p, span, text, ul)
import Html.Attributes exposing (alt, attribute, class, classList, href, id, readonly, src, style, value)
import Html.Events exposing (onClick)
import Html.Keyed
import Json.Decode as Decode exposing (Decoder)
import Process
import Random
import Svg exposing (Svg)
import Svg.Attributes as SA
import Task
import Time



-- PORTS


port setGameClaim : List Int -> Cmd msg


port setGameRestart : () -> Cmd msg


{-| Starts the next game for all players, see OctomoctoWeb.NextGame
-}
port setGameNextGame : () -> Cmd msg


port setGameCopyText : String -> Cmd msg


port setGameJoined : (Decode.Value -> msg) -> Sub msg


port setGameState : (Decode.Value -> msg) -> Sub msg


port setGameJoinFailed : (String -> msg) -> Sub msg


{-| The number of browsers that only watch the game, after the join and
after each change.
-}
port setGameWatchers : (Int -> msg) -> Sub msg


port setGamePlaySound : String -> Cmd msg


port setGameSaveMuted : Bool -> Cmd msg



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


type alias Card =
    Int


{-| The last set that a player found
-}
type alias FoundSet =
    { playerId : String
    , cards : List Card
    }


type alias Game =
    { -- Empty before the start and during the countdown
      table : List Card
    , deckLeft : Int
    , lastSet : Maybe FoundSet

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


type alias Model =
    { gameUrl : String
    , settingsUrl : String
    , nextGame : NextGame
    , guest : Bool
    , connection : Connection
    , copied : Bool

    -- The selected cards, in the order of the clicks
    , selected : List Card

    -- The cards of the last wrong set, while they shake. The number tells
    -- the shakes apart, so that the end of an old shake does not stop a
    -- new one.
    , wrong : List Card
    , wrongCount : Int

    -- Why the last wrong set is not a set, with the number of its shake,
    -- until the next click on a card
    , hint : Maybe ( Int, String )

    -- The clues about one set on the table, from the Hint button. They go
    -- when a card of the set leaves the table.
    , clue : Maybe Clue

    -- The local time (in ms) when the table started, and the local time
    -- now. The clock ticks between the server updates.
    , clockStart : Int
    , now : Int

    -- The countdown step that last played its beep (see `countdownStep`)
    , beepedStep : Maybe Int

    -- The size of the window, to pick the shape of the table
    , viewport : ( Float, Float )
    , muted : Bool
    , watchers : Int
    }


{-| The cards of the set, the clues on the screen (the newest last), and
the clues for the next clicks
-}
type alias Clue =
    { cards : List Card
    , shown : List String
    , next : List String
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
      , selected = []
      , wrong = []
      , wrongCount = 0
      , hint = Nothing
      , clue = Nothing
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
    | Pick Card
    | WrongDone Int
    | GotHint Int String
    | AskClue
    | GotClue Clue
    | Restart
    | StartNextGame
    | CopyLink
    | CopiedTimeout
    | SyncClock Int Time.Posix
    | Tick Time.Posix
    | Resized Float Float
    | ToggleMuted


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotJoined value ->
            case Decode.decodeValue joinedDecoder value of
                Ok ( me, game ) ->
                    ( { model | connection = Joined me game, selected = [] }, syncClock game )

                Err err ->
                    ( { model | connection = Failed (Decode.errorToString err) }, Cmd.none )

        GotState value ->
            case ( model.connection, Decode.decodeValue gameDecoder value ) of
                ( Joined me old, Ok game ) ->
                    ( { model
                        | connection = Joined me game

                        -- Another player can take a selected card
                        , selected = List.filter (\card -> List.member card game.table) model.selected
                        , clue =
                            Maybe.andThen
                                (\clue ->
                                    if List.all (\card -> List.member card game.table) clue.cards then
                                        model.clue

                                    else
                                        Nothing
                                )
                                model.clue
                      }
                    , Cmd.batch [ syncClock game, playSounds model (stateSounds me old game) ]
                    )

                _ ->
                    ( model, Cmd.none )

        GotJoinFailed reason ->
            ( { model | connection = Failed reason }, Cmd.none )

        GotWatchers count ->
            ( { model | watchers = count }, Cmd.none )

        Pick card ->
            case model.connection of
                Joined me game ->
                    if canPlay me game then
                        pick card { model | hint = Nothing }

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        WrongDone count ->
            if count == model.wrongCount then
                ( { model | wrong = [] }, Cmd.none )

            else
                ( model, Cmd.none )

        GotHint count hint ->
            if count == model.wrongCount then
                ( { model | hint = Just ( count, hint ) }, Cmd.none )

            else
                ( model, Cmd.none )

        AskClue ->
            case ( model.connection, model.clue ) of
                ( _, Just clue ) ->
                    case clue.next of
                        sentence :: next ->
                            ( { model | clue = Just { clue | shown = clue.shown ++ [ sentence ], next = next } }, Cmd.none )

                        [] ->
                            ( model, Cmd.none )

                ( Joined _ game, Nothing ) ->
                    case sets game.table of
                        first :: others ->
                            ( model, Random.generate GotClue (newClue first others) )

                        [] ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        GotClue clue ->
            ( { model | clue = Just clue }, Cmd.none )

        Restart ->
            ( model, setGameRestart () )

        StartNextGame ->
            ( model, setGameNextGame () )

        CopyLink ->
            ( { model | copied = True }
            , Cmd.batch
                [ setGameCopyText model.gameUrl
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
            ( { model | muted = not model.muted }, setGameSaveMuted (not model.muted) )


{-| A click on a selected card removes it from the selection. The third card
makes a claim. After a claim, the cards stay selected until the server
takes them, and the next click starts a new selection.
-}
pick : Card -> Model -> ( Model, Cmd Msg )
pick card model =
    let
        selection =
            if List.length model.selected == 3 then
                [ card ]

            else
                model.selected ++ [ card ]
    in
    if List.member card model.selected then
        ( { model | selected = List.filter ((/=) card) model.selected }, Cmd.none )

    else if List.length selection < 3 then
        ( { model | selected = selection }, playSounds model [ "select" ] )

    else if isSet selection then
        ( { model | selected = selection }, setGameClaim selection )

    else
        ( { model | selected = [], wrong = selection, wrongCount = model.wrongCount + 1 }
        , Cmd.batch
            [ playSounds model [ "wrong" ]
            , Process.sleep 500 |> Task.perform (\_ -> WrongDone (model.wrongCount + 1))
            , case hints selection of
                first :: others ->
                    Random.generate (GotHint (model.wrongCount + 1)) (Random.uniform first others)

                [] ->
                    Cmd.none
            ]
        )


{-| A random set of the table, with its 4 clues in a random order. The
first clue is on the screen at once.
-}
newClue : List Card -> List (List Card) -> Random.Generator Clue
newClue first others =
    Random.map2
        (\cards keys ->
            case List.map Tuple.second (List.sortBy Tuple.first (List.map2 Tuple.pair keys (clues cards))) of
                sentence :: next ->
                    Clue cards [ sentence ] next

                [] ->
                    Clue cards [] []
        )
        (Random.uniform first others)
        (Random.list 4 (Random.float 0 1))


{-| One clue for each feature of a set, for example "Each of them is red"
or "Each of them has a different shape"
-}
clues : List Card -> List String
clues cards =
    let
        sentence index =
            case List.map (feature index) cards of
                [ a, b, _ ] ->
                    if a == b then
                        "Each of them "
                            ++ (case index of
                                    0 ->
                                        if a == 0 then
                                            "has 1 shape"

                                        else
                                            "has " ++ String.fromInt (a + 1) ++ " shapes"

                                    1 ->
                                        "has the " ++ name [ "diamond", "oval", "squiggle" ] a ++ " shape"

                                    2 ->
                                        "is " ++ name [ "solid", "striped", "open" ] a

                                    _ ->
                                        "is " ++ name [ "red", "green", "purple" ] a
                               )

                    else
                        "Each of them has a different "
                            ++ name [ "number of shapes", "shape", "shading", "color" ] index

                _ ->
                    ""

        name list value =
            List.drop value list |> List.head |> Maybe.withDefault ""
    in
    List.map sentence [ 0, 1, 2, 3 ]


{-| All sets among the cards
-}
sets : List Card -> List (List Card)
sets cards =
    case cards of
        a :: rest ->
            List.concatMap
                (\( b, others ) ->
                    List.filter (\c -> isSet [ a, b, c ]) others
                        |> List.map (\c -> [ a, b, c ])
                )
                (tails rest)
                ++ sets rest

        [] ->
            []


{-| Each card with the cards after it
-}
tails : List Card -> List ( Card, List Card )
tails cards =
    case cards of
        a :: rest ->
            ( a, rest ) :: tails rest

        [] ->
            []


{-| One sentence for each feature that two cards have and the third card
does not have, for example "Two cards are red, but one is green."
-}
hints : List Card -> List String
hints cards =
    let
        names index =
            case index of
                0 ->
                    ( "have", [ "1 shape", "2 shapes", "3 shapes" ] )

                1 ->
                    ( "have", [ "diamonds", "ovals", "squiggles" ] )

                2 ->
                    ( "are", [ "solid", "striped", "open" ] )

                _ ->
                    ( "are", [ "red", "green", "purple" ] )

        name list value =
            List.drop value list |> List.head |> Maybe.withDefault ""

        hint index =
            case List.map (feature index) cards of
                [ a, b, c ] ->
                    let
                        ( verb, list ) =
                            names index

                        ( pair, odd ) =
                            if a == b then
                                ( a, c )

                            else if a == c then
                                ( a, b )

                            else
                                ( b, a )

                        oneVerb =
                            if verb == "are" then
                                "is"

                            else
                                "has"
                    in
                    if modBy 3 (a + b + c) == 0 then
                        Nothing

                    else
                        Just ("Two cards " ++ verb ++ " " ++ name list pair ++ ", but one " ++ oneVerb ++ " " ++ name list odd ++ ".")

                _ ->
                    Nothing
    in
    List.filterMap hint [ 0, 1, 2, 3 ]


{-| A player can select cards while the table is on the screen
-}
canPlay : Me -> Game -> Bool
canPlay me game =
    me /= Nothing && not game.waiting && not game.finished && game.table /= []


{-| The digit of the card for the feature: 0 for the number of shapes, 1 for
the shape, 2 for the shading and 3 for the color.
-}
feature : Int -> Card -> Int
feature index card =
    modBy 3 (card // (3 ^ index))


isSet : List Card -> Bool
isSet cards =
    List.length cards
        == 3
        && List.all (\index -> modBy 3 (List.sum (List.map (feature index) cards)) == 0) [ 0, 1, 2, 3 ]


{-| The seconds left in the countdown (3, 2, 1), 0 after it, and Nothing
when no table runs. The step is right only after the clock is in sync.
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
        Cmd.batch (List.map setGamePlaySound names)


{-| The sounds for the change from the old state to the new one: the start
of the game, a set that I found or that another player found, and the end of
the game.
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

        foundSound =
            case new.lastSet of
                Just found ->
                    if new.lastSet == old.lastSet || new.finished then
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
    startSound ++ foundSound ++ endSound


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
        (Decode.field "table" (Decode.list Decode.int))
        (Decode.field "deck_left" Decode.int)
        (Decode.field "last_set" (Decode.nullable foundSetDecoder))
        (Decode.field "waiting" Decode.bool)
        (Decode.field "finished" Decode.bool)
        (Decode.field "elapsed_ms" Decode.int)
        (Decode.field "players" (Decode.list playerDecoder))
        (Decode.field "players_needed" Decode.int)


foundSetDecoder : Decoder FoundSet
foundSetDecoder =
    Decode.map2 FoundSet
        (Decode.field "player_id" Decode.string)
        (Decode.field "cards" (Decode.list Decode.int))


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
        [ setGameJoined GotJoined
        , setGameState GotState
        , setGameJoinFailed GotJoinFailed
        , setGameWatchers GotWatchers
        , Browser.Events.onResize (\w h -> Resized (toFloat w) (toFloat h))
        , case model.connection of
            Joined _ game ->
                -- The cards come only after the countdown, so an empty table
                -- means a countdown. It ticks on each frame, so that the
                -- beeps are on time.
                if not game.waiting && not game.finished && game.table == [] then
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
            p [ id "set-connecting", class "py-24 text-center opacity-60" ] [ text "Joining the game…" ]

        Failed reason ->
            p [ id "set-failed", class "py-24 text-center text-red-600" ] [ text ("Could not join the game: " ++ reason) ]

        Joined me game ->
            viewGame model me game


viewGame : Model -> Me -> Game -> Html Msg
viewGame model me game =
    let
        layout =
            tableLayout model game

        width =
            tableWidth model me game layout

        countdown =
            Maybe.withDefault 0 (countdownStep model)
    in
    div
        [ id "set-root"
        , class "flex w-full max-w-[1400px] flex-col gap-2 select-none max-lg:landscape:flex-row max-lg:landscape:items-start max-lg:landscape:gap-3 lg:flex-row lg:items-start lg:gap-8"
        , classList [ ( "is-playing", playing game ) ]
        ]
        [ stripePatterns
        , aside [ id "set-panel", class "flex flex-col gap-2 max-lg:landscape:w-44 max-lg:landscape:shrink-0 max-lg:landscape:gap-3 lg:sticky lg:top-6 lg:w-72 lg:shrink-0 lg:gap-4" ]
            -- On a small screen, the title, the stats, the Hint button and
            -- the restart button are in one compact row. On a small screen
            -- that is wider than tall, they are in a narrow column at the
            -- left of the table, so the table can be as tall as the screen.
            -- On a large screen, the row is not a box (`contents`), so its
            -- items are in the column of the panel.
            [ div [ class "flex items-center gap-1 max-lg:landscape:flex-col max-lg:landscape:items-start max-lg:landscape:gap-3 lg:contents" ]
                [ div [ class "min-w-0 lg:order-1" ]
                    [ div [ class "flex items-center gap-1 lg:gap-2" ]
                        [ a
                            [ id "set-home"
                            , href "/"
                            , class "mr-1 shrink-0 transition hover:-translate-y-0.5 active:translate-y-0 lg:mr-0"
                            ]
                            [ img [ src "/images/mark.svg", alt "octomocto", class "h-8 w-auto dark:hidden lg:h-9" ] []
                            , img [ src "/images/mark-on-dark.svg", alt "octomocto", class "hidden h-8 w-auto dark:block lg:h-9" ] []
                            ]
                        , h1 [ class "text-xl font-semibold tracking-tight lg:text-2xl" ]
                            [ a [ id "set-title-link", href "/set", class "transition hover:text-octo-indigo dark:hover:text-octo-indigo-light" ] [ text "Set" ] ]
                        , viewMuteButton model.muted
                        , viewWatchers model.watchers
                        ]
                    , p [ class "hidden text-sm opacity-60 lg:block" ]
                        [ text "Find 3 cards where each feature is all the same or all different." ]
                    ]
                , viewClock model game
                , if canPlay me game then
                    viewClueButton model.clue

                  else
                    text ""
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
            , viewLastSet me game
            , if me == Nothing then
                p [ id "set-watching", class "rounded-2xl bg-amber-50 px-4 py-3 text-sm text-amber-900 ring-1 ring-amber-200 lg:order-7 dark:bg-amber-400/10 dark:text-amber-200 dark:ring-amber-400/25" ]
                    [ text "This game is full, so you can only watch it." ]

              else
                text ""
            ]
        , div [ class "min-w-0 flex-1" ]
            [ div [ class "relative mx-auto", style "width" width ]
                [ viewTable model me game layout
                , if game.waiting then
                    viewWaiting game

                  else if game.finished then
                    viewResult model.settingsUrl model.nextGame model.guest me game

                  else if countdown > 0 || game.table == [] then
                    viewCountdown countdown

                  else
                    text ""
                ]
            , viewNotes model me game width
            ]
        ]


{-| True from the countdown until the end of the game. Then the page does
not scroll.
-}
playing : Game -> Bool
playing game =
    not game.waiting && not game.finished


{-| The clues and why the last wrong set is not a set, under the table and
as wide as the table
-}
viewNotes : Model -> Me -> Game -> String -> Html Msg
viewNotes model me game width =
    let
        clue =
            if canPlay me game then
                viewClues model.clue

            else
                text ""
    in
    if clueLines model me game == 0 && model.hint == Nothing then
        text ""

    else
        div [ class "mx-auto mt-2 flex flex-col gap-2", style "width" width ]
            [ clue, viewHint model.hint ]


{-| The number of clues on the screen
-}
clueLines : Model -> Me -> Game -> Int
clueLines model me game =
    if canPlay me game then
        Maybe.map (.shown >> List.length) model.clue |> Maybe.withDefault 0

    else
        0


{-| Why the last wrong set is not a set. It is keyed, so that it pops in
again for each wrong set.
-}
viewHint : Maybe ( Int, String ) -> Html Msg
viewHint hint =
    case hint of
        Just ( count, sentence ) ->
            Html.Keyed.node "div"
                []
                [ ( String.fromInt count
                  , p [ id "set-hint", class "set-last-pop text-center text-sm text-slate-500 dark:text-slate-400" ]
                        [ span [ class "hero-light-bulb mr-1 size-4 align-[-3px] text-amber-500" ] []
                        , text sentence
                        ]
                  )
                ]

        Nothing ->
            text ""


{-| The width of a card divided by its height
-}
cardRatio : Float
cardRatio =
    1.6


type alias Layout =
    { columns : Int
    , rows : Int

    -- True when the cards fill the columns first, so that 3 more cards
    -- make a new column
    , byColumn : Bool
    }


{-| On a wide screen, the table has 3 rows, and 3 more cards make a new
column. On a narrow screen, it has 3 columns, and 3 more cards make a new
row. Before the start, the table has room for 12 cards.
-}
tableLayout : Model -> Game -> Layout
tableLayout model game =
    let
        lines =
            max 4 (List.length game.table // 3)
    in
    if Tuple.first model.viewport >= 640 then
        Layout lines 3 True

    else
        Layout 3 lines False


{-| The width of the screen from which the panel is at the left of the
table. On a smaller screen, the panel is a compact row above the table.
-}
largeScreen : Float
largeScreen =
    1024


{-| A small screen that is wider than tall. The panel is a narrow column at
the left of the table, as the `max-lg:landscape:` classes make it.
-}
sideways : Model -> Bool
sideways model =
    let
        ( width, height ) =
            model.viewport
    in
    width < largeScreen && width > height


{-| The gap in pixels between the cards, as the `gap-2 sm:gap-3` classes of
the table make it
-}
cardGap : Model -> Float
cardGap model =
    if Tuple.first model.viewport >= 640 then
        12

    else
        8


{-| The height in pixels of the screen that is not for the table. The page
of a game has no header and no footer. On a large screen, the panel is at
the left, so it is the 1.5rem padding of the page at the top and at the
bottom. On a small screen that is wider than tall, the panel is also at the
left, so it is the 0.5rem padding of the page at the top and at the bottom.
On other small screens, it is the padding, and the rows of the panel with
the 0.5rem gaps between them.

On all screens, the clues and the reason for a wrong set are under the
table. A clue has one line, and a reason has 2 lines on a narrow screen.
The heights of the rows are approximate, because the text can wrap.

-}
reservedHeight : Model -> Me -> Game -> Float
reservedHeight model me game =
    let
        width =
            Tuple.first model.viewport

        row condition rowHeight =
            if condition then
                rowHeight + 8

            else
                0

        lines =
            toFloat (clueLines model me game)

        panel =
            if width >= largeScreen then
                48

            else if sideways model then
                16

            else
                16
                    + row True 40
                    + row (game.playersNeeded > 1 && not (playing game)) 40
                    + row (List.length game.players > 1) 30
                    + row (game.lastSet /= Nothing) 46
                    + row (me == Nothing) 44
    in
    panel
        + row (lines > 0) (16 + 24 * lines)
        + row (model.hint /= Nothing)
            (if width >= 640 then
                20

             else
                40
            )


{-| Make the table as wide as possible, but small enough that it is all on
the screen, and never with cards wider than 14rem. The width comes from
the height of the space without the gaps between the rows.
-}
tableWidth : Model -> Me -> Game -> Layout -> String
tableWidth model me game layout =
    let
        px value =
            String.fromFloat value ++ "px"

        gap =
            cardGap model

        gaps =
            px (gap * toFloat (layout.columns - 1))
    in
    "min(100%, calc("
        ++ String.fromInt (layout.columns * 14)
        ++ "rem + "
        ++ gaps
        ++ "), calc((100dvh - "
        ++ px (reservedHeight model me game + gap * toFloat (layout.rows - 1))
        ++ ") * "
        ++ String.fromFloat (toFloat layout.columns * cardRatio / toFloat layout.rows)
        ++ " + "
        ++ gaps
        ++ "))"


{-| The number of browsers that only watch the game, when there are any.
-}
viewWatchers : Int -> Html Msg
viewWatchers count =
    if count > 0 then
        span
            [ id "set-watchers"
            , class "flex shrink-0 items-center gap-1 text-sm tabular-nums text-slate-500 dark:text-slate-400"
            , Html.Attributes.title ("Watchers: " ++ String.fromInt count)
            ]
            [ span [ class "hero-eye size-4" ] [], text (String.fromInt count) ]

    else
        text ""


viewMuteButton : Bool -> Html Msg
viewMuteButton muted =
    button
        [ id "set-mute"
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


{-| The Hint button. It is off when all clues of the set are on the screen.
On a small screen, only the icon shows, but not in the column of a screen
that is wider than tall.
-}
viewClueButton : Maybe Clue -> Html Msg
viewClueButton clue =
    let
        shown =
            Maybe.map .shown clue |> Maybe.withDefault []

        more =
            Maybe.map (\c -> c.next /= []) clue |> Maybe.withDefault True

        label =
            if shown == [] then
                "Hint"

            else if more then
                "Next hint"

            else
                "No more hints"
    in
    button
        [ id "set-hint-button"
        , class "group flex size-9 shrink-0 items-center justify-center gap-2 rounded-full text-sm font-medium text-amber-700 ring-1 ring-amber-200 transition enabled:hover:bg-amber-50 enabled:hover:ring-amber-300 enabled:active:scale-95 disabled:opacity-50 max-lg:landscape:size-auto max-lg:landscape:px-4 max-lg:landscape:py-2 lg:order-5 lg:size-auto lg:self-start lg:px-4 lg:py-2 dark:text-amber-300 dark:ring-amber-400/30 dark:enabled:hover:bg-amber-400/10 dark:enabled:hover:ring-amber-400/50"
        , Html.Attributes.disabled (not more)
        , onClick AskClue
        , Html.Attributes.title label
        ]
        [ span [ class "hero-light-bulb size-4 transition-transform group-enabled:group-hover:-rotate-12" ] []
        , span [ class "hidden max-lg:landscape:inline lg:inline" ] [ text label ]
        ]


{-| The clues from the Hint button. Each clue is keyed, so that only the new
clue pops in.
-}
viewClues : Maybe Clue -> Html Msg
viewClues clue =
    case Maybe.map .shown clue |> Maybe.withDefault [] of
        [] ->
            text ""

        shown ->
            Html.Keyed.ul [ id "set-clues", class "flex flex-col gap-1 rounded-2xl bg-amber-50 px-4 py-2.5 text-sm text-amber-900 ring-1 ring-amber-200 dark:bg-amber-400/10 dark:text-amber-200 dark:ring-amber-400/25" ]
                (List.map (\sentence -> ( sentence, li [ class "set-last-pop" ] [ text sentence ] )) shown)


{-| Starts a new table for all players, also during a game. On a small
screen, only the icon shows, but not in the column of a screen that is wider
than tall.
-}
viewRestartButton : Html Msg
viewRestartButton =
    button
        [ id "set-restart"
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
            [ id "set-link"
            , readonly True
            , value model.gameUrl
            , class "min-w-0 flex-1 truncate bg-transparent text-octo-navy outline-none max-lg:landscape:px-2 max-lg:landscape:py-1 lg:px-2 lg:py-1 dark:text-slate-100"
            ]
            []
        , button
            [ id "set-copy-link"
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


{-| The time on the left, and the cards that are still in the deck on the
right. On a small screen, they are small and without a box, at the right of
the compact row of the panel, or under the title in the column of a screen
that is wider than tall.
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
    div [ id "set-clock", class "ml-auto flex gap-4 pr-2 max-lg:landscape:ml-0 max-lg:landscape:gap-6 max-lg:landscape:pr-0 max-lg:landscape:pl-2 lg:order-2 lg:ml-0 lg:grid lg:grid-cols-2 lg:gap-0 lg:divide-x lg:divide-slate-200 lg:rounded-2xl lg:bg-white lg:py-3 lg:pr-0 lg:shadow-sm lg:ring-1 lg:ring-slate-200 dark:lg:divide-white/10 dark:lg:bg-white/5 dark:lg:shadow-none dark:lg:ring-white/10" ]
        [ stat "time" "set-time" "font-light text-slate-700 dark:text-slate-100" (formatTime elapsedMs)
        , stat "deck" "set-deck-left" "font-bold text-octo-indigo dark:text-octo-indigo-light" (String.fromInt game.deckLeft)
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


{-| The players in the order in which they joined, with the sets they found
-}
viewScores : Me -> Game -> Html Msg
viewScores me game =
    ul [ id "set-scores", class "flex flex-wrap gap-2 max-lg:landscape:flex-col lg:order-4 lg:flex-col" ]
        (List.map
            (\player ->
                li
                    [ id ("set-score-" ++ player.id)
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


{-| The last set that a player found, in small cards. With more than one
player, a dot in the color of the player shows who found it. The set is
keyed, so that it pops in again for each new set. On a small screen that is
taller than wide, the label is at the left of the cards, so the box is low.
-}
viewLastSet : Me -> Game -> Html Msg
viewLastSet me game =
    case game.lastSet of
        Just found ->
            let
                finder =
                    List.filter (\player -> player.id == found.playerId) game.players |> List.head
            in
            div [ id "set-last", class "flex items-center gap-3 rounded-2xl bg-white p-2 shadow-sm max-lg:landscape:block max-lg:landscape:p-3 lg:order-6 lg:block lg:p-3 ring-1 ring-slate-200 dark:bg-white/5 dark:shadow-none dark:ring-white/10" ]
                [ p [ class "flex min-w-0 flex-1 items-center gap-2 text-xs font-medium max-lg:landscape:mb-2 lg:mb-2 tracking-wide text-slate-400 uppercase" ]
                    (text "last set"
                        :: (case ( finder, List.length game.players > 1 ) of
                                ( Just player, True ) ->
                                    [ span [ class "size-2 rounded-full", style "background" player.color ] []
                                    , span [ class "truncate tracking-normal normal-case text-slate-500 dark:text-slate-400" ] [ text (playerName me player) ]
                                    ]

                                _ ->
                                    []
                           )
                    )
                , Html.Keyed.node "div"
                    []
                    [ ( String.join "-" (List.map String.fromInt found.cards)
                      , div [ class "set-last-pop grid w-36 grid-cols-3 gap-2 max-lg:landscape:w-auto lg:w-auto" ]
                            (List.map (\card -> div [ class "set-mini-card" ] [ cardImage card ]) found.cards)
                      )
                    ]
                ]

        Nothing ->
            text ""


{-| The cards in a grid. Each card is keyed, so that a new card is dealt
with an animation and the other cards stay as they are. Before the start,
empty places keep the size of the table under the cover.
-}
viewTable : Model -> Me -> Game -> Layout -> Html Msg
viewTable model me game layout =
    let
        playable =
            canPlay me game

        cards =
            if game.table == [] then
                List.map (\index -> ( "empty-" ++ String.fromInt index, div [ class "set-card is-empty" ] [] )) (List.range 1 12)

            else
                List.map (\card -> ( String.fromInt card, viewCard model playable card )) game.table
    in
    Html.Keyed.node "div"
        ([ id "set-table"
         , class "grid gap-2 sm:gap-3"
         , style "grid-template-columns" ("repeat(" ++ String.fromInt layout.columns ++ ", minmax(0, 1fr))")
         ]
            ++ (if layout.byColumn then
                    [ style "grid-template-rows" "repeat(3, auto)", style "grid-auto-flow" "column" ]

                else
                    []
               )
        )
        cards


viewCard : Model -> Bool -> Card -> Html Msg
viewCard model playable card =
    button
        [ id ("set-card-" ++ String.fromInt card)
        , class "set-card"
        , classList
            [ ( "is-selected", List.member card model.selected )
            , ( "is-wrong", List.member card model.wrong )
            , ( "is-playable", playable )
            ]
        , onClick (Pick card)
        , Html.Attributes.attribute "aria-label" (cardName card)
        ]
        [ div [ class "set-card-face" ] [ cardImage card ] ]


{-| For example, "2 green striped ovals"
-}
cardName : Card -> String
cardName card =
    let
        count =
            feature 0 card + 1

        pick3 index names =
            List.drop (feature index card) names |> List.head |> Maybe.withDefault ""
    in
    String.join " "
        [ String.fromInt count
        , pick3 3 [ "red", "green", "purple" ]
        , pick3 2 [ "solid", "striped", "open" ]
        , pick3 1 [ "diamond", "oval", "squiggle" ]
            ++ (if count > 1 then
                    "s"

                else
                    ""
               )
        ]



-- CARD IMAGES


{-| The class that gives the color of a card. The colors are in app.css,
because they are brighter in the dark theme.
-}
colorClass : Int -> String
colorClass index =
    "set-color-" ++ String.fromInt index


{-| One pattern of stripes for each color. The shapes of all cards use
them. The SVG has no size, but it is not hidden with "display: none":
some browsers do not draw patterns from a hidden SVG.
-}
stripePatterns : Html Msg
stripePatterns =
    Svg.svg [ SA.width "0", SA.height "0", SA.class "absolute" ]
        [ Svg.defs []
            (List.map
                (\index ->
                    Svg.pattern
                        [ SA.id ("set-stripes-" ++ String.fromInt index)
                        , SA.patternUnits "userSpaceOnUse"
                        , SA.width "10"
                        , SA.height "9"
                        ]
                        [ Svg.rect [ SA.width "10", SA.height "3.5", SA.fill "currentColor", SA.class (colorClass index) ] [] ]
                )
                (List.range 0 2)
            )
        ]


{-| The shapes stand side by side in the middle of a wide card. Each shape
is drawn in a box of 50 by 100 units.
-}
cardImage : Card -> Html Msg
cardImage card =
    let
        count =
            feature 0 card + 1

        width =
            toFloat count * 35 + toFloat (count - 1) * 10

        left =
            (160 - width) / 2

        fill =
            case feature 2 card of
                0 ->
                    "currentColor"

                1 ->
                    "url(#set-stripes-" ++ String.fromInt (feature 3 card) ++ ")"

                _ ->
                    "none"
    in
    Svg.svg [ SA.viewBox "0 0 160 100", SA.class ("size-full " ++ colorClass (feature 3 card)) ]
        (List.map
            (\index ->
                Svg.g
                    [ SA.transform ("translate(" ++ String.fromFloat (left + toFloat index * 45) ++ " 15) scale(0.7)") ]
                    [ shape (feature 1 card)
                        [ SA.fill fill
                        , SA.stroke "currentColor"
                        , SA.strokeWidth "6"
                        , SA.strokeLinejoin "round"
                        ]
                    ]
            )
            (List.range 0 (count - 1))
        )


shape : Int -> List (Svg.Attribute Msg) -> Svg Msg
shape index attributes =
    case index of
        0 ->
            Svg.path (SA.d "M25 5 L46 50 L25 95 L4 50 Z" :: attributes) []

        1 ->
            Svg.rect ([ SA.x "5", SA.y "5", SA.width "40", SA.height "90", SA.rx "20" ] ++ attributes) []

        _ ->
            -- The squiggle of setwithfriends.com (MIT license, (c) 2020 Eric
            -- Zhang, Cynthia Du), scaled from its 200 by 400 box to ours
            Svg.path
                (SA.d "m16.97,3.19c10.81,-1.68 26.84,1.65 30.26,14.69c3.42,13.03 -11.21,40.37 -11.27,51.16c1.14,14.24 20.95,21.98 5.58,26.45c-15.37,4.47 -31.53,-0.46 -35.93,-10.48c-4.4,-10.02 12.32,-30.03 11.54,-47.02c-0.78,-17 -5.47,-17.56 -12.4,-20.04c-6.93,-2.48 1.42,-13.07 12.23,-14.75z"
                    :: attributes
                )
                []



-- COVERS


{-| Covers the table until all players are in.
-}
viewWaiting : Game -> Html Msg
viewWaiting game =
    div
        [ id "set-waiting"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-3 rounded-2xl bg-octo-navy/80 p-4 text-center text-white"
        ]
        [ p [ class "text-3xl font-semibold" ] [ text "Waiting for players" ]
        , p [ id "set-waiting-count", class "text-lg tabular-nums opacity-80" ]
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
        [ id "set-countdown"
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
        [ id "set-result"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-4 rounded-2xl bg-octo-navy/70 p-4 text-white backdrop-blur-sm"
        ]
        [ p [ class "text-3xl font-semibold" ] [ text message ]
        , p [ id "set-final-time", class "text-lg tabular-nums opacity-80" ]
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
                [ id "set-play-again"
                , class "rounded-full bg-white px-6 py-2.5 font-medium text-octo-indigo shadow-lg transition hover:-translate-y-0.5 hover:bg-octo-mist active:translate-y-0"
                , onClick Restart
                ]
                [ text "Play again" ]
        , a
            [ id "set-leaderboards-link"
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
            [ id "set-next-game"
            , action
            , attribute "data-ga-link" "or_try"
            , attribute "data-ga-from" "Set"
            , attribute "data-ga-to" nextGame.name
            , class "group text-sm font-medium text-white underline-offset-4 transition hover:underline"
            ]
            [ text ("Or try " ++ nextGame.name ++ " ")
            , span [ class "inline-block transition group-hover:translate-x-0.5" ] [ text "→" ]
            ]

        -- Only a guest who played gets the call to sign in, not a spectator
        , if guest && me /= Nothing then
            p [ id "set-sign-in", class "text-sm text-white/70" ]
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
