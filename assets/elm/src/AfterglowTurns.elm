port module AfterglowTurns exposing (main)

{-| Afterglow with turns: 2 to 4 players make one pattern of tiles on a
grid together.

The first player only adds a tile. In each turn after that, the player
clicks all tiles of the pattern, in any order, and then adds a new tile.
The pattern never shows: the other players watch the clicks. A wrong tile
puts the player out. The last player who is in wins. When half of the
grid is in the pattern, all players who are still in share the win.

The server owns the game and checks each click. The state has the tiles
that the player of the turn clicked, and the last click, so that each
browser shows the clicks of the turn. app.js connects the ports to a
Phoenix channel. The port names start with "afterglowTurns", because Elm
does not allow two ports with the same name in one bundle.

-}

import Browser
import GameBar
import Html exposing (Html, a, aside, button, div, h1, img, input, li, ol, p, span, text, ul)
import Html.Attributes exposing (alt, attribute, class, classList, disabled, href, id, readonly, rel, src, style, target, value)
import Html.Events exposing (onClick)
import Html.Keyed
import Json.Decode as Decode exposing (Decoder)
import Press
import Process
import Set exposing (Set)
import Task
import Time



-- PORTS


port afterglowTurnsTap : Int -> Cmd msg


port afterglowTurnsRestart : () -> Cmd msg


{-| Starts the next game for all players, see OctomoctoWeb.NextGame
-}
port afterglowTurnsNextGame : () -> Cmd msg


{-| Starts the next game on the next larger grid after a tie, with the
same players
-}
port afterglowTurnsPlayLarger : () -> Cmd msg


port afterglowTurnsCopyText : String -> Cmd msg


port afterglowTurnsJoined : (Decode.Value -> msg) -> Sub msg


port afterglowTurnsState : (Decode.Value -> msg) -> Sub msg


port afterglowTurnsJoinFailed : (String -> msg) -> Sub msg


{-| The number of browsers that only watch the game
-}
port afterglowTurnsWatchers : (Int -> msg) -> Sub msg


{-| The sounds of the single-player game, see afterglow_sounds.js
-}
port afterglowTurnsPlaySound : String -> Cmd msg


port afterglowTurnsSaveMuted : Bool -> Cmd msg


{-| The full pattern after a new tile, to flash once
-}
port afterglowTurnsFlash : (List Int -> msg) -> Sub msg



-- MODEL


{-| The `name` is the display name of a signed-in player, or Nothing for a
guest. Then the player is known by the `colorName`. An `away` player lost
the connection, and can come back for a short time. The `out` is the
place in the order in which the players went out.
-}
type alias Player =
    { id : String
    , name : Maybe String
    , color : String
    , colorName : String
    , score : Int
    , out : Maybe Int
    , away : Bool
    , wins : Int
    }


{-| A tile that a player clicked. The `n` counts the clicks of the game, so
that a new click has a larger `n`.
-}
type alias Tap =
    { n : Int
    , cell : Int
    , player : String
    , ok : Bool
    }


type alias Game =
    { size : Int

    -- The length of the pattern that ends the game
    , target : Int

    -- Only after the end
    , pattern : Maybe (List Int)
    , length : Int

    -- The tiles of the pattern that the player of the turn clicked
    , found : List Int

    -- True until the game has all its players
    , waiting : Bool
    , finished : Bool
    , turn : Maybe String
    , winners : List String
    , lastTap : Maybe Tap

    -- The time since the start of the turn, and the time limit of a turn
    , turnMs : Int
    , turnLimitMs : Maybe Int
    , players : List Player
    , playersNeeded : Int

    -- The id of the player who changes the settings of the next game of
    -- the match (see `OctomoctoWeb.MatchPage`). The other players wait.
    , editing : Maybe String

    -- The grid to suggest after a tie, Nothing for the largest grid
    , nextSize : Maybe Int
    }


{-| The player id of this browser. Nothing for a watcher.
-}
type alias Me =
    Maybe String


type Connection
    = Connecting
    | Joined Me Game
    | Failed String


{-| The tiles that glow for a moment: the full pattern after a new tile,
or a wrong tile. The id tells the newest flash.
-}
type alias Flash =
    { cells : List Int
    , ok : Bool
    , id : Int
    }


type alias Model =
    { gameUrl : String
    , settingsUrl : String

    -- The settings page of the next game of the match
    , changeSettingsUrl : Maybe String
    , nextGame : NextGame
    , guest : Bool
    , connection : Connection
    , copied : Bool
    , muted : Bool
    , watchers : Int

    -- The local time now, and when the turn started
    , now : Int
    , turnStart : Int
    , flash : Maybe Flash
    , flashId : Int
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
      , muted = flags.muted
      , watchers = 0
      , now = 0
      , turnStart = 0
      , flash = Nothing
      , flashId = 0
      }
    , Cmd.none
    )


{-| The pattern is lit and fades out in this time (see `afterglow-blink`
in app.css)
-}
flashMs : Int
flashMs =
    1500



-- UPDATE


type Msg
    = GotJoined Decode.Value
    | GotState Decode.Value
    | GotJoinFailed String
    | GotWatchers Int
    | Click Int
    | Restart
    | StartNextGame
    | PlayLarger
    | GotFlash (List Int)
    | Unflash Int
    | CopyLink
    | CopiedTimeout
    | SyncClock Game Time.Posix
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
                    let
                        ( next, cmd ) =
                            showTap old game { model | connection = Joined me game }
                    in
                    ( next, Cmd.batch [ cmd, syncClock game, playSounds model (stateSounds me old game) ] )

                _ ->
                    ( model, Cmd.none )

        GotJoinFailed reason ->
            ( { model | connection = Failed reason }, Cmd.none )

        GotWatchers count ->
            ( { model | watchers = count }, Cmd.none )

        Click cell ->
            case model.connection of
                Joined me game ->
                    if canTap me game && not (List.member cell game.found) then
                        ( model, afterglowTurnsTap cell )

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        Restart ->
            ( model, afterglowTurnsRestart () )

        StartNextGame ->
            ( model, afterglowTurnsNextGame () )

        PlayLarger ->
            ( model, afterglowTurnsPlayLarger () )

        GotFlash pattern ->
            startFlash pattern True model |> withSound model "show"

        Unflash flashId ->
            if Maybe.map .id model.flash == Just flashId then
                ( { model | flash = Nothing }, Cmd.none )

            else
                ( model, Cmd.none )

        CopyLink ->
            ( { model | copied = True }
            , Cmd.batch
                [ afterglowTurnsCopyText model.gameUrl
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
            ( { model | turnStart = ms - game.turnMs, now = ms }, Cmd.none )

        Tick time ->
            ( { model | now = Time.posixToMillis time }, Cmd.none )

        ToggleMuted ->
            ( { model | muted = not model.muted }, afterglowTurnsSaveMuted (not model.muted) )


{-| A new click: a tile of the pattern pops with the next note, and a wrong
tile shakes and buzzes. A new tile has no flash of its own: the full
pattern flashes (see `GotFlash`). All browsers show it in the same way,
also the browser of the player who clicked.
-}
showTap : Game -> Game -> Model -> ( Model, Cmd Msg )
showTap old new model =
    let
        oldN =
            Maybe.map .n old.lastTap |> Maybe.withDefault 0
    in
    case new.lastTap of
        Just tap ->
            if tap.n <= oldN then
                ( model, Cmd.none )

            else if tap.ok && List.member tap.cell new.found then
                ( model, playSounds model [ "found-" ++ String.fromInt (List.length new.found - 1) ] )

            else if tap.ok then
                ( model, Cmd.none )

            else
                startFlash [ tap.cell ] False model |> withSound model "wrong"

        Nothing ->
            ( model, Cmd.none )


startFlash : List Int -> Bool -> Model -> ( Model, Cmd Msg )
startFlash cells ok model =
    let
        flashId =
            model.flashId + 1
    in
    ( { model | flash = Just { cells = cells, ok = ok, id = flashId }, flashId = flashId }
    , Process.sleep (toFloat flashMs) |> Task.perform (\_ -> Unflash flashId)
    )


withSound : Model -> String -> ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
withSound model name ( next, cmd ) =
    ( next, Cmd.batch [ cmd, playSounds model [ name ] ] )


{-| The player of the turn can click when the game has all its players
-}
canTap : Me -> Game -> Bool
canTap me game =
    myTurn me game && not game.waiting && not game.finished


myTurn : Me -> Game -> Bool
myTurn me game =
    me /= Nothing && me == game.turn


isMe : Me -> Player -> Bool
isMe me player =
    me == Just player.id


syncClock : Game -> Cmd Msg
syncClock game =
    Time.now |> Task.perform (SyncClock game)


playSounds : Model -> List String -> Cmd Msg
playSounds model sounds =
    if model.muted then
        Cmd.none

    else
        Cmd.batch (List.map afterglowTurnsPlaySound sounds)


{-| The start of my turn, and the end of the game. The clicks have their
own sounds.
-}
stateSounds : Me -> Game -> Game -> List String
stateSounds me old new =
    if new.finished && not old.finished then
        if me /= Nothing && List.any (\winner -> Just winner == me) new.winners then
            [ "end" ]

        else
            [ "wrong" ]

    else if myTurn me new && not (myTurn me old) && not new.finished && not new.waiting then
        [ "hide" ]

    else
        []



-- DECODERS


joinedDecoder : Decoder ( Me, Game )
joinedDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "player_id" (Decode.nullable Decode.string))
        (Decode.field "state" gameDecoder)


gameDecoder : Decoder Game
gameDecoder =
    Decode.succeed Game
        |> andMap (Decode.field "size" Decode.int)
        |> andMap (Decode.field "target" Decode.int)
        |> andMap (Decode.field "pattern" (Decode.nullable (Decode.list Decode.int)))
        |> andMap (Decode.field "length" Decode.int)
        |> andMap (Decode.field "found" (Decode.list Decode.int))
        |> andMap (Decode.field "waiting" Decode.bool)
        |> andMap (Decode.field "finished" Decode.bool)
        |> andMap (Decode.field "turn" (Decode.nullable Decode.string))
        |> andMap (Decode.field "winners" (Decode.list Decode.string))
        |> andMap (Decode.field "last_tap" (Decode.nullable tapDecoder))
        |> andMap (Decode.field "turn_ms" Decode.int)
        |> andMap (Decode.field "turn_limit_ms" (Decode.nullable Decode.int))
        |> andMap (Decode.field "players" (Decode.list playerDecoder))
        |> andMap (Decode.field "players_needed" Decode.int)
        |> andMap (Decode.field "editing" (Decode.nullable Decode.string))
        |> andMap (Decode.field "next_size" (Decode.nullable Decode.int))


andMap : Decoder a -> Decoder (a -> b) -> Decoder b
andMap =
    Decode.map2 (|>)


tapDecoder : Decoder Tap
tapDecoder =
    Decode.map4 Tap
        (Decode.field "n" Decode.int)
        (Decode.field "cell" Decode.int)
        (Decode.field "player" Decode.string)
        (Decode.field "ok" Decode.bool)


playerDecoder : Decoder Player
playerDecoder =
    Decode.succeed Player
        |> andMap (Decode.field "id" Decode.string)
        |> andMap (Decode.field "name" (Decode.nullable Decode.string))
        |> andMap (Decode.field "color" Decode.string)
        |> andMap (Decode.field "color_name" Decode.string)
        |> andMap (Decode.field "score" Decode.int)
        |> andMap (Decode.field "out" (Decode.nullable Decode.int))
        |> andMap (Decode.field "away" Decode.bool)
        |> andMap (Decode.oneOf [ Decode.field "wins" Decode.int, Decode.succeed 0 ])



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ afterglowTurnsJoined GotJoined
        , afterglowTurnsState GotState
        , afterglowTurnsJoinFailed GotJoinFailed
        , afterglowTurnsWatchers GotWatchers
        , afterglowTurnsFlash GotFlash
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
            p [ id "afterglow-connecting", class "py-24 text-center opacity-60" ] [ text "Joining the game…" ]

        Failed reason ->
            p [ id "afterglow-failed", class "py-24 text-center text-red-600" ] [ text ("Could not join the game: " ++ reason) ]

        Joined me game ->
            viewGame model me game


viewGame : Model -> Me -> Game -> Html Msg
viewGame model me game =
    div
        [ id "afterglow-root"
        , class "flex w-full flex-col gap-2 select-none lg:flex-row lg:items-start lg:gap-8"
        , classList [ ( "is-playing", not game.waiting && not game.finished ) ]
        ]
        [ aside [ id "afterglow-panel", class "flex flex-col gap-2 lg:sticky lg:top-6 lg:w-72 lg:shrink-0 lg:gap-5" ]
            -- On a small screen, the title and the buttons are in one compact
            -- row. On a large screen, the row is not a box (`contents`), so
            -- its items are in the column of the panel.
            [ div [ class "flex items-center gap-1 lg:contents" ]
                [ div [ class "min-w-0 flex-1 lg:order-1" ]
                    [ div [ class "flex items-center gap-1" ]
                        [ a [ id "afterglow-home", href "/", class "mr-1 shrink-0 transition lg:mr-0" ]
                            [ img [ src "/images/mark.svg", alt "octomocto", class "h-8 w-auto dark:hidden lg:h-9" ] []
                            , img [ src "/images/mark-on-dark.svg", alt "octomocto", class "hidden h-8 w-auto dark:block lg:h-9" ] []
                            ]
                        , h1 [ class "mr-1 truncate text-xl font-semibold tracking-tight lg:text-2xl" ]
                            [ a [ id "afterglow-title-link", href model.settingsUrl, class "transition hover:text-octo-indigo dark:hover:text-octo-indigo-light" ] [ text "Afterglow Memory" ] ]
                        , viewWatchers (me == Nothing) model.watchers
                        ]
                    , p [ class "hidden text-sm opacity-60 lg:block" ]
                        [ text "Click the pattern, then add a tile of your choice." ]
                    ]
                , viewMenu (game.editing /= Nothing) model.muted (me /= Nothing)
                ]
            -- The link is only for the players who are not in yet
            , if game.waiting then
                viewShareLink model

              else
                text ""
            , viewScores model me game
            , a
                [ id "afterglow-leaderboards-link"
                , href model.settingsUrl
                , class "hidden text-sm font-medium text-octo-indigo underline-offset-4 transition hover:underline lg:order-6 lg:block dark:text-octo-indigo-light"
                ]
                [ text "Best results" ]
            ]
        , div [ class "flex min-w-0 flex-1 flex-col items-center gap-2 lg:gap-5" ]
            [ div
                [ id "afterglow-board"
                , class "relative w-full rounded-2xl bg-white p-3 shadow-sm ring-1 ring-slate-200 sm:p-5 dark:bg-white/5 dark:shadow-none dark:ring-white/10"
                , style "max-width" (boardWidth me)
                ]
                [ viewGrid model me game
                , if game.waiting then
                    viewWaiting game

                  else if game.finished then
                    viewResult model me game

                  else
                    text ""
                ]
            , p
                [ id "afterglow-status"

                -- As wide as the board
                , class "min-h-12 w-full text-center text-balance text-slate-600 dark:text-slate-300"
                , style "max-width" (boardWidth me)
                , attribute "aria-live" "polite"
                ]
                [ text (status me game) ]
            ]
        ]


{-| Make the board as wide as possible, but small enough that it is all on
the screen. The board is square, so its width is also its height. The
height that is not for the board is approximate: the bar at the top, the
padding of the page, the rows of the panel on a small screen, and the
status line.
-}
boardWidth : Me -> String
boardWidth me =
    let
        watcherRow =
            if me == Nothing then
                52

            else
                0
    in
    "min(100%, 40rem, calc(100dvh - "
        ++ String.fromFloat (GameBar.height + 200 + watcherRow)
        ++ "px))"


{-| The number of browsers that only watch the game, when there are any.
-}
viewWatchers : Bool -> Int -> Html Msg
viewWatchers watching count =
    if watching || count > 0 then
        span
            [ id "afterglow-watchers"
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


{-| Restarts the game for all players, and turns the sounds on and off
-}
viewMenu : Bool -> Bool -> Bool -> Html Msg
viewMenu locked muted player =
    Html.node "octo-game-menu"
        [ class "relative shrink-0 lg:order-5 lg:self-start"
        , attribute "menu-label" "Menu"
        , attribute "restart-label" "Restart game"
        , attribute "locked" (boolAttribute locked)
        , attribute "sound-on-label" "Turn the sounds on"
        , attribute "sound-off-label" "Turn the sounds off"
        , attribute "muted" (boolAttribute muted)
        , attribute "player" (boolAttribute player)
        , Html.Events.on "octo-restart" (Decode.succeed Restart)
        , Html.Events.on "octo-toggle-mute" (Decode.succeed ToggleMuted)
        ]
        []


viewShareLink : Model -> Html Msg
viewShareLink model =
    div [ class "flex items-center gap-2 rounded-full bg-octo-mist p-1 pl-4 text-sm ring-1 ring-octo-indigo/20 lg:order-3 lg:flex-col lg:items-stretch lg:rounded-2xl lg:p-2 lg:pl-2 dark:bg-octo-indigo/15 dark:ring-octo-indigo-light/25" ]
        [ input
            [ id "afterglow-link"
            , readonly True
            , value model.gameUrl
            , class "min-w-0 flex-1 truncate bg-transparent text-octo-navy outline-none lg:px-2 lg:py-1 dark:text-slate-100"
            ]
            []
        , button
            [ id "afterglow-copy-link"
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


{-| The players in the order of their turns, with the longest pattern that
each one clicked. The player of the turn has a ring in the player's color,
and a bar in the last seconds of the turn. A player who is out is crossed
out.
-}
viewScores : Model -> Me -> Game -> Html Msg
viewScores model me game =
    ul [ id "afterglow-scores", class "flex flex-wrap gap-2 lg:order-4 lg:flex-col" ]
        (List.map
            (\player ->
                let
                    current =
                        game.turn == Just player.id && not game.waiting && not game.finished
                in
                li
                    [ id ("afterglow-score-" ++ player.id)
                    , class "relative flex items-center gap-2 overflow-hidden rounded-full bg-white px-3 py-1 text-sm text-slate-800 shadow-sm ring-1 ring-slate-200 transition dark:bg-white/5 dark:text-slate-100 dark:shadow-none dark:ring-white/10"
                    , classList [ ( "opacity-50", player.away || player.out /= Nothing ), ( "memory-current", current ) ]

                    -- Elm's `style` cannot set a CSS variable
                    , attribute "style" ("--player-color: " ++ player.color)
                    ]
                    [ span [ class "size-3 rounded-full", style "background" player.color ] []
                    , span [ class "lg:flex-1", classList [ ( "line-through", player.out /= Nothing ) ] ] [ text (playerName me player) ]
                    , if current then
                        span [ class "text-xs font-medium tracking-wide uppercase", style "color" player.color ] [ text "turn" ]

                      else if player.out /= Nothing then
                        span [ class "text-xs font-medium tracking-wide text-slate-400 uppercase" ] [ text "out" ]

                      else
                        text ""
                    , span [ class "font-semibold tabular-nums" ] [ text (String.fromInt player.score) ]
                    , if current then
                        viewTurnTimer model game

                      else
                        text ""
                    ]
            )
            game.players
        )


{-| The bar shows in the last 10 seconds of a turn
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
        shortName player ++ " (you)"

    else
        shortName player


{-| The name of a player, or the color for a guest
-}
shortName : Player -> String
shortName player =
    Maybe.withDefault player.colorName player.name


{-| The name of a player in a sentence: "The pink player" for a guest
-}
sentenceName : Player -> String
sentenceName player =
    case player.name of
        Just name ->
            name

        Nothing ->
            "The " ++ String.toLower player.colorName ++ " player"


turnPlayer : Game -> Maybe Player
turnPlayer game =
    List.filter (\player -> game.turn == Just player.id) game.players |> List.head


{-| The line under the grid that tells what to do now, with the length of
the pattern and the length that ends the game, for example "Your turn:
click the pattern. 2 tiles to go · 5 of 13"
-}
status : Me -> Game -> String
status me game =
    if game.waiting || game.finished then
        ""

    else if game.length == 0 then
        statusText me game ++ "."

    else
        -- No line break inside the count
        statusText me game ++ " ·\u{00A0}" ++ String.fromInt game.length ++ "\u{00A0}of\u{00A0}" ++ String.fromInt game.target


{-| The status line without its period
-}
statusText : Me -> Game -> String
statusText me game =
    let
        left =
            game.length - List.length game.found
    in
    if me /= Nothing && List.any (\player -> isMe me player && player.out /= Nothing) game.players then
        "You are out. Watch the others play"

    else if myTurn me game then
        if game.length == 0 then
            "You start. Click any tile to add it to the pattern"

        else if left > 0 then
            "Your turn: click the pattern. " ++ tiles left ++ " to go"

        else
            "Now add a new tile of your choice"

    else
        case turnPlayer game of
            Just player ->
                if game.length == 0 then
                    sentenceName player ++ " starts the pattern"

                else if left > 0 then
                    sentenceName player ++ " clicks the pattern. " ++ tiles left ++ " to go"

                else
                    sentenceName player ++ " adds a tile"

            Nothing ->
                ""


tiles : Int -> String
tiles n =
    if n == 1 then
        "1 tile"

    else
        String.fromInt n ++ " tiles"



-- THE GRID


{-| The tiles that the player of the turn clicked are lit for all. After
the end, the full pattern is lit.
-}
viewGrid : Model -> Me -> Game -> Html Msg
viewGrid model me game =
    let
        found =
            Set.fromList (Maybe.withDefault game.found game.pattern)

        open =
            canTap me game

        tile cell =
            let
                flash =
                    model.flash
                        |> Maybe.andThen
                            (\f ->
                                if List.member cell f.cells then
                                    Just f.ok

                                else
                                    Nothing
                            )
            in
            button
                [ id ("afterglow-tile-" ++ String.fromInt cell)
                , class "afterglow-tile"
                , classList
                    [ ( "is-found", Set.member cell found )
                    , ( "is-blink", flash == Just True )
                    , ( "is-wrong", flash == Just False )
                    , ( "is-open", open && not (Set.member cell found) )
                    ]
                , attribute "aria-label" ("Tile " ++ String.fromInt (cell + 1))
                , Press.onPress (Click cell)
                , Press.onKeyClick (Click cell)
                ]
                []
    in
    -- A new grid for each turn: the tiles of the last turn go out at once,
    -- so that their slow glow does not show the pattern again
    div [ class "flex flex-col items-center" ]
        [ Html.Keyed.node "div"
            [ class "w-full" ]
            [ ( Maybe.withDefault "" game.turn ++ "-" ++ String.fromInt game.length ++ "-" ++ boolAttribute game.finished
              , div
                    [ id "afterglow-grid"
                    , class "afterglow-grid afterglow-turns-grid w-full"
                    , style "grid-template-columns" ("repeat(" ++ String.fromInt game.size ++ ", minmax(0, 1fr))")
                    ]
                    (List.map tile (List.range 0 (game.size * game.size - 1)))
              )
            ]
        ]


{-| Covers the grid until all players are in.
-}
viewWaiting : Game -> Html Msg
viewWaiting game =
    div
        [ id "afterglow-waiting"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-3 rounded-2xl bg-octo-navy/80 p-4 text-center text-white"
        ]
        [ p [ class "text-3xl font-semibold" ] [ text "Waiting for players" ]
        , p [ id "afterglow-waiting-count", class "text-lg tabular-nums opacity-80" ]
            [ text (String.fromInt (List.length game.players) ++ " of " ++ String.fromInt game.playersNeeded ++ " players are in") ]
        , p [ class "text-sm opacity-60" ] [ text "Send the link to the other players. The game starts when all of them are in." ]
        ]


{-| The players from the winners to the first player who went out
-}
ranking : List Player -> List Player
ranking players =
    List.sortBy (\player -> negate (Maybe.withDefault 1000 player.out)) players


viewResult : Model -> Me -> Game -> Html Msg
viewResult model me game =
    let
        nextGame =
            model.nextGame

        winners =
            List.filter (\player -> List.member player.id game.winners) game.players

        tie =
            List.length winners > 1

        ( message, detail ) =
            case winners of
                [ player ] ->
                    ( if isMe me player then
                        "You win!"

                      else
                        sentenceName player ++ " wins!"
                    , "The pattern had " ++ tiles game.length ++ "."
                    )

                [] ->
                    ( "Game over", "" )

                _ ->
                    ( "A tie!", "Half of the grid is in the pattern: " ++ tiles game.length ++ "." )

        -- The player on the settings page. Nobody can start a game until
        -- that player is back.
        editor =
            game.editing
                |> Maybe.andThen (\editing -> List.head (List.filter (\player -> player.id == editing) game.players))

        locked =
            editor /= Nothing

        changeSettings label url =
            if locked then
                span
                    [ id "afterglow-change-settings"
                    , attribute "aria-disabled" "true"
                    , class "cursor-not-allowed rounded-full px-5 py-2.5 font-medium text-white opacity-50 ring-1 ring-white/40"
                    ]
                    [ text label ]

            else
                a
                    [ id "afterglow-change-settings"
                    , href url
                    , class "rounded-full px-5 py-2.5 font-medium text-white ring-1 ring-white/40 transition hover:bg-white/10"
                    ]
                    [ text label ]
    in
    div
        [ id "afterglow-result"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-4 overflow-y-auto rounded-2xl bg-octo-navy/75 p-4 text-center text-white backdrop-blur-sm"
        ]
        [ p [ class "text-3xl font-semibold" ] [ text message ]
        , p [ id "afterglow-final", class "text-lg opacity-80" ] [ text detail ]
        , case ( tie, game.nextSize ) of
            ( True, Just size ) ->
                p [ id "afterglow-larger-hint", class "max-w-xs text-sm text-white/80" ]
                    [ text ("Break the tie on a " ++ sizeText size ++ " grid.") ]

            _ ->
                text ""
        , ol [ class "flex flex-col gap-1 text-sm" ]
            (List.map
                (\player ->
                    li [ class "flex items-center gap-2" ]
                        [ span [ class "size-3 rounded-full", style "background" player.color ] []
                        , span [ class "flex-1 text-left" ] [ text (playerName me player) ]
                        , span [ class "pl-6 font-semibold tabular-nums" ] [ text (String.fromInt player.score) ]
                        ]
                )
                (ranking game.players)
            )
        , case editor of
            Just player ->
                p [ id "afterglow-editing", class "animate-pulse text-sm text-white/80" ]
                    [ text (sentenceName player ++ " changes the settings…") ]

            Nothing ->
                text ""
        , if me == Nothing then
            text ""

          else
            div [ class "flex flex-wrap items-center justify-center gap-3" ]
                [ button
                    [ id "afterglow-play-again"
                    , class "rounded-full bg-white px-6 py-2.5 font-medium text-octo-indigo shadow-lg transition hover:bg-octo-mist disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:bg-white"
                    , onClick Restart
                    , disabled locked
                    ]
                    [ text "Play again" ]
                , case ( model.changeSettingsUrl, tie, game.nextSize ) of
                    -- After a tie, the next game on a larger grid starts at once
                    ( _, True, Just size ) ->
                        button
                            [ id "afterglow-play-larger"
                            , class "rounded-full px-5 py-2.5 font-medium text-white ring-1 ring-white/40 transition hover:bg-white/10 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:bg-transparent"
                            , onClick PlayLarger
                            , disabled locked
                            ]
                            [ text ("Play on " ++ sizeText size) ]

                    ( Just url, _, _ ) ->
                        changeSettings "Change settings" url

                    ( Nothing, _, _ ) ->
                        text ""
                ]
        , let
            -- A player starts the next game for all players
            ( element, action ) =
                if me /= Nothing then
                    ( button, onClick StartNextGame )

                else
                    ( a, href nextGame.path )
          in
          element
            [ id "afterglow-next-game"
            , action
            , disabled locked
            , attribute "data-ga-link" "or_try"
            , attribute "data-ga-from" "Afterglow Memory"
            , attribute "data-ga-to" nextGame.name
            , class "group text-sm font-medium text-white underline-offset-4 transition hover:underline disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:no-underline"
            ]
            [ text ("Or try " ++ nextGame.name ++ " ")
            , span [ class "inline-block transition group-hover:translate-x-0.5" ] [ text "→" ]
            ]

        -- Only a guest who played gets the call to sign in, not a spectator
        , if model.guest && me /= Nothing then
            p [ id "afterglow-sign-in", class "text-sm text-white/70" ]
                [ a [ href "/signin", class "font-medium text-white underline underline-offset-4 transition hover:text-octo-mist" ] [ text "Sign in" ]
                , text " to keep your scores."
                ]

          else
            text ""
        , viewFeed
        ]


sizeText : Int -> String
sizeText size =
    String.fromInt size ++ "×" ++ String.fromInt size


{-| The link to the page to support Octomocto, at the bottom of a result.
The link opens in a new tab, so that the player stays in the game.
-}
viewFeed : Html msg
viewFeed =
    p [ id "afterglow-feed", class "mt-2 max-w-sm border-t border-white/15 pt-4 text-center text-sm leading-10 text-balance text-white/80" ]
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
