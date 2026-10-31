port module Echo exposing (main)

{-| Echo: a ring of colored pads. The pads light up in a sequence, and the
players tap them in the same order.

The server owns the game: the sequence, the turn and the scores. This
module draws the state that comes in through ports and sends the taps
out. app.js connects the ports to a Phoenix channel.

Alone, the server adds a random pad in each round. The state has the
sequence, and this module plays it back: the pads light up one by one,
with their tones. Then the player repeats it. This module checks each tap
at once, so that a wrong tap buzzes with no wait for the server.

With 2 or 3 players, the state has no sequence, and there is no playback.
The player of the turn repeats the sequence and then adds a pad. The
server checks the taps. Each tap is in the state as the last tap, so the
other browsers light up its pad. A player who taps a wrong pad is out.

The player can mute the sounds and hide the shapes on the pads. The port
names start with "echo", because Elm does not allow two ports with the
same name in one bundle.

-}

import Browser
import Browser.Dom
import Browser.Events
import Dict exposing (Dict)
import Html exposing (Html, a, aside, button, div, h1, img, input, li, ol, p, span, text, ul)
import Html.Attributes exposing (alt, attribute, class, classList, href, id, readonly, rel, src, style, target, value)
import Html.Events exposing (onClick, preventDefaultOn)
import Json.Decode as Decode exposing (Decoder)
import Process
import Svg exposing (svg)
import Svg.Attributes as SA
import Task
import Time



-- PORTS


port echoStart : () -> Cmd msg


port echoPress : Int -> Cmd msg


port echoRestart : () -> Cmd msg


{-| Starts the next game for all players, see OctomoctoWeb.NextGame
-}
port echoNextGame : () -> Cmd msg


port echoCopyText : String -> Cmd msg


port echoJoined : (Decode.Value -> msg) -> Sub msg


port echoState : (Decode.Value -> msg) -> Sub msg


port echoJoinFailed : (String -> msg) -> Sub msg


{-| The number of browsers that only watch the game, after the join and
after each change.
-}
port echoWatchers : (Int -> msg) -> Sub msg


{-| The `name` is "pad" (the tone of the `pad` for `ms`), "buzz", "turn",
"win" or "lose".
-}
port echoPlaySound : { name : String, pad : Int, ms : Int } -> Cmd msg


port echoSaveMuted : Bool -> Cmd msg


port echoSaveShapes : Bool -> Cmd msg



-- PADS


type alias Pad =
    { color : String
    , name : String
    , shape : String

    -- The shape on the pad, on a 24 x 24 view box
    , glyph : String
    }


{-| The neighbours alternate warm and cool colors. A game with n pads has
the first n.
-}
allPads : List Pad
allPads =
    [ Pad "#FF8A3D" "Orange" "circle" "M5 12a7 7 0 1 0 14 0a7 7 0 1 0 -14 0"
    , Pad "#3D8BFF" "Blue" "triangle" "M12 4.5L20 18.5H4Z"
    , Pad "#FFD23F" "Yellow" "square" "M6 6h12v12H6Z"
    , Pad "#9B6BFF" "Violet" "diamond" "M12 3.5L20.5 12L12 20.5L3.5 12Z"
    , Pad "#A6E04A" "Lime" "plus" "M12 5v14M5 12h14"
    , Pad "#FF5A4E" "Red" "star" "M12 3.8l2.5 5.3l5.7.7l-4.2 3.9l1.1 5.7L12 16.6l-5.1 2.8l1.1-5.7l-4.2-3.9l5.7-.7Z"
    , Pad "#2EC4B6" "Teal" "cross" "M6.5 6.5l11 11M17.5 6.5l-11 11"
    , Pad "#FF5FA2" "Pink" "hexagon" "M12 3.5l7.4 4.25v8.5L12 20.5l-7.4-4.25v-8.5Z"
    ]


padAt : Int -> Maybe Pad
padAt index =
    List.drop index allPads |> List.head



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
    }


{-| A pad that a player tapped. The `n` counts the taps of the game, so
that a new tap has a larger `n`.
-}
type alias Tap =
    { n : Int
    , pad : Int
    , player : String
    , ok : Bool
    }


type alias Game =
    { pads : Int

    -- Only in a game for one player
    , sequence : Maybe (List Int)
    , length : Int

    -- The number of pads that the player of the turn repeated
    , step : Int

    -- True until the game has all its players
    , waiting : Bool
    , finished : Bool
    , turn : Maybe String
    , winner : Maybe String
    , lastTap : Maybe Tap

    -- The time since the last tap of the turn, and the time limit of a
    -- turn (only with 2 or more players)
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


{-| The pads of the `sequence` light up one by one from the `start` (a
local time in ms). The `shown` is the last pad whose tone played.
-}
type alias Playback =
    { sequence : List Int
    , start : Int
    , shown : Int
    }


type alias Model =
    { gameUrl : String
    , indexUrl : String
    , settingsUrl : String
    , nextGame : NextGame
    , guest : Bool
    , connection : Connection
    , copied : Bool
    , muted : Bool
    , watchers : Int
    , shapes : Bool

    -- The local time now, and when the turn started
    , now : Int
    , turnStart : Int

    -- Alone: the playback, the length of the last sequence that played
    -- back, and the pads that the player tapped in this round
    , playback : Maybe Playback
    , played : Int
    , typed : Int

    -- The pad that lights up for a short time after a tap. The id tells
    -- the newest flash.
    , flash : Maybe ( Int, Int )
    , flashId : Int
    , shaking : Bool

    -- The width and the height of the browser window
    , viewport : ( Float, Float )
    , texts : Texts
    }


{-| The texts in the language of the page, by the English text (see
`OctomoctoWeb.EchoHTML.elm_texts/0`).
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
    , nextGame : NextGame
    , guest : Bool
    , muted : Bool
    , shapes : Bool
    , texts : Decode.Value
    }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { gameUrl = flags.gameUrl
      , indexUrl = flags.indexUrl
      , settingsUrl = flags.settingsUrl
      , nextGame = flags.nextGame
      , guest = flags.guest
      , connection = Connecting
      , copied = False
      , muted = flags.muted
      , watchers = 0
      , shapes = flags.shapes
      , now = 0
      , turnStart = 0
      , playback = Nothing
      , played = 0
      , typed = 0
      , flash = Nothing
      , flashId = 0
      , shaking = False
      , viewport = ( 1024, 768 )
      , texts = Decode.decodeValue (Decode.dict Decode.string) flags.texts |> Result.withDefault Dict.empty
      }
    , Task.perform (\vp -> Resized vp.viewport.width vp.viewport.height) Browser.Dom.getViewport
    )



-- TIMING


{-| A longer sequence plays faster, in three steps as in the Simon game
-}
flashMs : Int -> Int
flashMs length =
    if length <= 5 then
        420

    else if length <= 13 then
        320

    else
        220


gapMs : Int
gapMs =
    50


{-| The wait before the playback, and the extra wait after a round
-}
leadInMs : Int
leadInMs =
    600


nextRoundMs : Int
nextRoundMs =
    700


tapFlashMs : Int
tapFlashMs =
    220



-- UPDATE


type Msg
    = GotJoined Decode.Value
    | GotState Decode.Value
    | GotJoinFailed String
    | GotWatchers Int
    | Start
    | Press Int
    | Restart
    | StartNextGame
    | StartPlayback (List Int) Int Time.Posix
    | Frame Time.Posix
    | Unflash Int
    | Unshake
    | CopyLink
    | CopiedTimeout
    | SyncClock Game Time.Posix
    | Tick Time.Posix
    | ToggleMuted
    | ToggleShapes
    | Resized Float Float


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotJoined value ->
            case Decode.decodeValue joinedDecoder value of
                Ok ( me, game ) ->
                    let
                        ( next, cmd ) =
                            followSequence game { model | connection = Joined me game, typed = game.step }
                    in
                    ( next, Cmd.batch [ cmd, syncClock game ] )

                Err err ->
                    ( { model | connection = Failed (Decode.errorToString err) }, Cmd.none )

        GotState value ->
            case ( model.connection, Decode.decodeValue gameDecoder value ) of
                ( Joined me old, Ok game ) ->
                    let
                        ( next, cmd ) =
                            followSequence game { model | connection = Joined me game }

                        ( tapped, tapCmd ) =
                            showTap me old game next
                    in
                    ( tapped
                    , Cmd.batch [ cmd, tapCmd, syncClock game, playSounds model (stateSounds me old game) ]
                    )

                _ ->
                    ( model, Cmd.none )

        GotJoinFailed reason ->
            ( { model | connection = Failed reason }, Cmd.none )

        GotWatchers count ->
            ( { model | watchers = count }, Cmd.none )

        Start ->
            case model.connection of
                Joined (Just _) game ->
                    if solo game && game.length == 0 && not game.finished then
                        ( model, echoStart () )

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        Press pad ->
            case model.connection of
                Joined me game ->
                    if canPress model me game && pad < game.pads then
                        press model game pad

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        Restart ->
            ( model, echoRestart () )

        StartNextGame ->
            ( model, echoNextGame () )

        StartPlayback sequence delay time ->
            ( { model
                | playback = Just { sequence = sequence, start = Time.posixToMillis time + delay, shown = -1 }
                , now = Time.posixToMillis time
                , typed = 0
              }
            , Cmd.none
            )

        Frame time ->
            stepPlayback { model | now = Time.posixToMillis time }

        Unflash flashId ->
            if flashId == model.flashId then
                ( { model | flash = Nothing }, Cmd.none )

            else
                ( model, Cmd.none )

        Unshake ->
            ( { model | shaking = False }, Cmd.none )

        CopyLink ->
            ( { model | copied = True }
            , Cmd.batch
                [ echoCopyText model.gameUrl
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
            ( { model | muted = not model.muted }, echoSaveMuted (not model.muted) )

        ToggleShapes ->
            ( { model | shapes = not model.shapes }, echoSaveShapes (not model.shapes) )

        Resized width height ->
            ( { model | viewport = ( width, height ) }, Cmd.none )


{-| Alone, a new sequence plays back: after a round, after the start, or
after a reload. Until the playback starts, the player cannot tap.
-}
followSequence : Game -> Model -> ( Model, Cmd Msg )
followSequence game model =
    case game.sequence of
        Just sequence ->
            if game.length > 0 && game.length /= model.played && not game.finished then
                let
                    delay =
                        if game.length > 1 then
                            nextRoundMs + leadInMs

                        else
                            leadInMs
                in
                ( { model
                    | played = game.length
                    , playback = Just { sequence = sequence, start = model.now + 1000000, shown = -1 }
                  }
                , Time.now |> Task.perform (StartPlayback sequence delay)
                )

            else if game.finished then
                ( { model | playback = Nothing }, Cmd.none )

            else
                ( model, Cmd.none )

        Nothing ->
            ( model, Cmd.none )


{-| Lights up the pad of the playback at the time now, and plays its tone
once. The playback ends after its last pad.
-}
stepPlayback : Model -> ( Model, Cmd Msg )
stepPlayback model =
    case model.playback of
        Just playback ->
            let
                length =
                    List.length playback.sequence

                slot =
                    flashMs length + gapMs

                elapsed =
                    model.now - playback.start
            in
            if elapsed >= length * slot - gapMs then
                ( { model | playback = Nothing }, Cmd.none )

            else
                case playbackPad model of
                    Just ( index, pad ) ->
                        if index > playback.shown then
                            ( { model | playback = Just { playback | shown = index } }
                            , playSounds model [ { name = "pad", pad = pad, ms = flashMs length } ]
                            )

                        else
                            ( model, Cmd.none )

                    Nothing ->
                        ( model, Cmd.none )

        Nothing ->
            ( model, Cmd.none )


{-| The position in the sequence and the pad that the playback lights up
now
-}
playbackPad : Model -> Maybe ( Int, Int )
playbackPad model =
    case model.playback of
        Just playback ->
            let
                length =
                    List.length playback.sequence

                slot =
                    flashMs length + gapMs

                elapsed =
                    model.now - playback.start

                index =
                    elapsed // slot
            in
            if elapsed >= 0 && index < length && elapsed - index * slot < flashMs length then
                List.drop index playback.sequence |> List.head |> Maybe.map (Tuple.pair index)

            else
                Nothing

        Nothing ->
            Nothing


{-| A tap lights up the pad and plays its tone at once. Alone, this module
knows the sequence, so a wrong pad buzzes at once too. With 2 or more
players, the server tells if the pad is wrong (see `showTap`).
-}
press : Model -> Game -> Int -> ( Model, Cmd Msg )
press model game pad =
    let
        ( flashed, flashCmd ) =
            flashPad pad model
    in
    case game.sequence of
        Just sequence ->
            if List.drop model.typed sequence |> List.head |> (==) (Just pad) then
                ( { flashed | typed = model.typed + 1 }
                , Cmd.batch [ flashCmd, playSounds model [ padSound pad ], echoPress pad ]
                )

            else
                let
                    ( shaken, shakeCmd ) =
                        shake { flashed | typed = game.length + 1 }
                in
                ( shaken, Cmd.batch [ flashCmd, shakeCmd, playSounds model [ buzz ], echoPress pad ] )

        Nothing ->
            ( flashed, Cmd.batch [ flashCmd, playSounds model [ padSound pad ], echoPress pad ] )


{-| Lights up the pad of a new tap of another player, or of a watched
player. A wrong tap buzzes, also a wrong tap of mine with 2 or more
players.
-}
showTap : Me -> Game -> Game -> Model -> ( Model, Cmd Msg )
showTap me old new model =
    let
        oldN =
            Maybe.map .n old.lastTap |> Maybe.withDefault 0
    in
    case new.lastTap of
        Just tap ->
            if tap.n <= oldN then
                ( model, Cmd.none )

            else if me == Just tap.player then
                if tap.ok || solo new then
                    ( model, Cmd.none )

                else
                    shake model |> withSounds model [ buzz ]

            else
                let
                    ( flashed, flashCmd ) =
                        flashPad tap.pad model
                in
                if tap.ok then
                    ( flashed, Cmd.batch [ flashCmd, playSounds model [ padSound tap.pad ] ] )

                else
                    let
                        ( shaken, shakeCmd ) =
                            shake flashed
                    in
                    ( shaken, Cmd.batch [ flashCmd, shakeCmd, playSounds model [ buzz ] ] )

        Nothing ->
            ( model, Cmd.none )


withSounds : Model -> List Sound -> ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
withSounds model sounds ( next, cmd ) =
    ( next, Cmd.batch [ cmd, playSounds model sounds ] )


flashPad : Int -> Model -> ( Model, Cmd Msg )
flashPad pad model =
    let
        flashId =
            model.flashId + 1
    in
    ( { model | flash = Just ( pad, flashId ), flashId = flashId }
    , Process.sleep (toFloat tapFlashMs) |> Task.perform (\_ -> Unflash flashId)
    )


shake : Model -> ( Model, Cmd Msg )
shake model =
    ( { model | shaking = True }, Process.sleep 320 |> Task.perform (\_ -> Unshake) )


solo : Game -> Bool
solo game =
    game.playersNeeded == 1


{-| The player of the turn can tap when the game has all its players. Alone,
the player taps after the playback, until the end of the sequence or a
wrong pad.
-}
canPress : Model -> Me -> Game -> Bool
canPress model me game =
    myTurn me game
        && not game.waiting
        && not game.finished
        && (if solo game then
                game.length > 0 && model.playback == Nothing && model.typed < game.length

            else
                True
           )


myTurn : Me -> Game -> Bool
myTurn me game =
    me /= Nothing && me == game.turn


isMe : Me -> Player -> Bool
isMe me player =
    me == Just player.id


syncClock : Game -> Cmd Msg
syncClock game =
    Time.now |> Task.perform (SyncClock game)



-- SOUNDS


type alias Sound =
    { name : String, pad : Int, ms : Int }


padSound : Int -> Sound
padSound pad =
    { name = "pad", pad = pad, ms = tapFlashMs }


buzz : Sound
buzz =
    sound "buzz"


sound : String -> Sound
sound name =
    { name = name, pad = 0, ms = 0 }


playSounds : Model -> List Sound -> Cmd Msg
playSounds model sounds =
    if model.muted then
        Cmd.none

    else
        Cmd.batch (List.map echoPlaySound sounds)


{-| With 2 or more players: the start of the game, the start of my turn,
and the end of the game. The taps have their own sounds.
-}
stateSounds : Me -> Game -> Game -> List Sound
stateSounds me old new =
    if solo new then
        []

    else if new.finished && not old.finished then
        if me /= Nothing && new.winner == me then
            [ sound "win" ]

        else
            [ sound "lose" ]

    else
        List.concat
            [ -- All players are ready, and the game starts
              if old.waiting && not new.waiting then
                [ sound "start" ]

              else
                []
            , if myTurn me new && not (myTurn me old) && not new.finished && not new.waiting then
                [ sound "turn" ]

              else
                []
            ]



-- DECODERS


joinedDecoder : Decoder ( Me, Game )
joinedDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "player_id" (Decode.nullable Decode.string))
        (Decode.field "state" gameDecoder)


gameDecoder : Decoder Game
gameDecoder =
    Decode.succeed Game
        |> andMap (Decode.field "pads" Decode.int)
        |> andMap (Decode.field "sequence" (Decode.nullable (Decode.list Decode.int)))
        |> andMap (Decode.field "length" Decode.int)
        |> andMap (Decode.field "step" Decode.int)
        |> andMap (Decode.field "waiting" Decode.bool)
        |> andMap (Decode.field "finished" Decode.bool)
        |> andMap (Decode.field "turn" (Decode.nullable Decode.string))
        |> andMap (Decode.field "winner" (Decode.nullable Decode.string))
        |> andMap (Decode.field "last_tap" (Decode.nullable tapDecoder))
        |> andMap (Decode.field "turn_ms" Decode.int)
        |> andMap (Decode.field "turn_limit_ms" (Decode.nullable Decode.int))
        |> andMap (Decode.field "players" (Decode.list playerDecoder))
        |> andMap (Decode.field "players_needed" Decode.int)


andMap : Decoder a -> Decoder (a -> b) -> Decoder b
andMap =
    Decode.map2 (|>)


tapDecoder : Decoder Tap
tapDecoder =
    Decode.map4 Tap
        (Decode.field "n" Decode.int)
        (Decode.field "pad" Decode.int)
        (Decode.field "player" Decode.string)
        (Decode.field "ok" Decode.bool)


playerDecoder : Decoder Player
playerDecoder =
    Decode.map7 Player
        (Decode.field "id" Decode.string)
        (Decode.field "name" (Decode.nullable Decode.string))
        (Decode.field "color" Decode.string)
        (Decode.field "color_name" Decode.string)
        (Decode.field "score" Decode.int)
        (Decode.field "out" (Decode.nullable Decode.int))
        (Decode.field "away" Decode.bool)



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ echoJoined GotJoined
        , echoState GotState
        , echoJoinFailed GotJoinFailed
        , echoWatchers GotWatchers
        , Browser.Events.onKeyDown keyDecoder
        , Browser.Events.onResize (\w h -> Resized (toFloat w) (toFloat h))
        , if model.playback /= Nothing then
            Browser.Events.onAnimationFrame Frame

          else
            Sub.none
        , case model.connection of
            Joined _ game ->
                if not (solo game) && not game.waiting && not game.finished then
                    Time.every 200 Tick

                else
                    Sub.none

            _ ->
                Sub.none
        ]


{-| The keys 1 to 8 tap the pads
-}
keyDecoder : Decoder Msg
keyDecoder =
    Decode.map2 Tuple.pair (Decode.field "key" Decode.string) (Decode.field "repeat" Decode.bool)
        |> Decode.andThen
            (\( key, repeat ) ->
                case String.toInt key of
                    Just n ->
                        if n >= 1 && n <= 8 && not repeat then
                            Decode.succeed (Press (n - 1))

                        else
                            Decode.fail "not a pad"

                    Nothing ->
                        Decode.fail "not a pad"
            )



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
            p [ id "echo-connecting", class "py-24 text-center opacity-60" ] [ text (t model.texts "Joining the game…") ]

        Failed reason ->
            p [ id "echo-failed", class "py-24 text-center text-red-600" ] [ text (tf model.texts "Could not join the game: {reason}" [ ( "reason", reason ) ]) ]

        Joined me game ->
            viewGame model me game


viewGame : Model -> Me -> Game -> Html Msg
viewGame model me game =
    div
        [ id "echo-root"
        , class "flex w-full flex-col gap-2 select-none max-lg:landscape:flex-row max-lg:landscape:items-start max-lg:landscape:gap-3 lg:flex-row lg:items-start lg:gap-8"
        , classList [ ( "is-playing", not game.waiting && not game.finished ) ]
        ]
        [ aside [ id "echo-panel", class "flex flex-col gap-2 max-lg:landscape:w-48 max-lg:landscape:shrink-0 max-lg:landscape:gap-4 lg:sticky lg:top-6 lg:w-72 lg:shrink-0 lg:gap-5" ]
            -- On a small screen, the title, the buttons and the restart
            -- button are in one compact row. On a small screen that is wider
            -- than tall, they are in a narrow column at the left of the ring,
            -- so the ring can be as tall as the screen. On a large screen,
            -- the row is not a box (`contents`), so its items are in the
            -- column of the panel.
            [ div [ class "flex items-center gap-1 max-lg:landscape:flex-col max-lg:landscape:items-start max-lg:landscape:gap-4 lg:contents" ]
                [ div [ class "min-w-0 flex-1 lg:order-1" ]
                    [ div [ class "flex items-center gap-1" ]
                        [ a
                            [ id "echo-home"
                            , href "/"
                            , class "mr-1 shrink-0 transition hover:-translate-y-0.5 active:translate-y-0 lg:mr-0"
                            ]
                            [ img [ src "/images/mark.svg", alt "octomocto", class "h-8 w-auto dark:hidden lg:h-9" ] []
                            , img [ src "/images/mark-on-dark.svg", alt "octomocto", class "hidden h-8 w-auto dark:block lg:h-9" ] []
                            ]
                        , h1 [ class "mr-1 truncate text-xl font-semibold tracking-tight lg:text-2xl" ]
                            [ a [ id "echo-title-link", href model.indexUrl, class "transition hover:text-octo-indigo dark:hover:text-octo-indigo-light" ] [ text (t model.texts "Echo") ] ]
                        , viewMuteButton model.texts model.muted
                        , viewWatchers model.texts model.watchers
                        , viewShapesButton model.texts model.shapes
                        ]
                    , p [ class "hidden text-sm opacity-60 lg:block" ]
                        [ text
                            (t model.texts
                                (if solo game then
                                    "Watch the pads light up, then tap them in the same order."

                                 else
                                    "Repeat the sequence, then add a pad of your choice."
                                )
                            )
                        ]
                    ]
                , if me == Nothing then
                    text ""

                  else
                    viewRestartButton model.texts
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
                p [ id "echo-watching", class "rounded-2xl bg-amber-50 px-4 py-3 text-sm text-amber-900 ring-1 ring-amber-200 lg:order-5 dark:bg-amber-400/10 dark:text-amber-200 dark:ring-amber-400/25" ]
                    [ text (t model.texts "You are watching this game.") ]

              else
                text ""
            , a
                [ id "echo-leaderboards-link"
                , href model.settingsUrl
                , class "hidden text-sm font-medium text-octo-indigo underline-offset-4 transition hover:underline lg:order-6 lg:block dark:text-octo-indigo-light"
                ]
                [ text (t model.texts "Best results") ]
            ]

        -- On a small screen that is wider than tall, the status line is at
        -- the right of the ring, because the ring is as tall as the screen.
        , div [ class "flex min-w-0 flex-1 flex-col items-center gap-2 max-lg:landscape:flex-row max-lg:landscape:gap-3 lg:gap-5" ]
            [ div
                [ id "echo-board"
                , class "relative w-full rounded-2xl bg-white p-3 shadow-sm ring-1 ring-slate-200 sm:p-5 dark:bg-white/5 dark:shadow-none dark:ring-white/10"
                , style "max-width" (boardWidth model me game)
                ]
                [ viewRing model me game
                , if game.waiting then
                    viewWaiting model.texts game

                  else if game.finished then
                    viewResult model me game

                  else
                    text ""
                ]
            , p [ id "echo-status", class "min-h-12 max-w-sm text-center text-slate-600 max-lg:landscape:w-36 max-lg:landscape:shrink-0 max-lg:landscape:text-left dark:text-slate-300", attribute "aria-live" "polite" ]
                [ text (status model me game) ]
            ]
        ]


{-| The width of the screen from which the panel is at the left of the
ring. On a smaller screen, the panel is a compact row above the ring.
-}
largeScreen : Float
largeScreen =
    1024


{-| A small screen that is wider than tall. The panel is a narrow column at
the left of the ring, as the `max-lg:landscape:` classes make it.
-}
sideways : Model -> Bool
sideways model =
    let
        ( width, height ) =
            model.viewport
    in
    width < largeScreen && width > height


{-| The height in pixels of the screen that is not for the board. On a large
screen, it is the 1.5rem padding of the page at the top and at the bottom,
and the status line (3rem) under the board with the 1.25rem gap. On a small
screen, it is the 0.5rem padding of the page at the top and at the bottom,
the rows of the panel (the compact row, the link and the scores for a game
with more players, and maybe the message for a watcher), the status line,
and the 0.5rem gaps between them. The heights of the rows are approximate,
because the scores can wrap. On a small screen that is wider than tall, the
panel is at the left and the status line is at the right, so only the
padding is not for the board.
-}
reservedHeight : Model -> Me -> Game -> Float
reservedHeight model me game =
    if Tuple.first model.viewport >= largeScreen then
        48 + 20 + 48

    else if sideways model then
        16

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
            + row True 48


{-| Make the board as wide as possible, but small enough that it is all on
the screen. The board is square, so its width is also its height.
-}
boardWidth : Model -> Me -> Game -> String
boardWidth model me game =
    "min(100%, calc(100dvh - " ++ String.fromFloat (reservedHeight model me game) ++ "px))"


{-| The number of browsers that only watch the game, when there are any.
-}
viewWatchers : Texts -> Int -> Html Msg
viewWatchers texts count =
    if count > 0 then
        span
            [ id "echo-watchers"
            , class "flex shrink-0 items-center gap-1 text-sm tabular-nums text-slate-500 dark:text-slate-400"
            , Html.Attributes.title (tf texts "Watchers: {count}" [ ( "count", String.fromInt count ) ])
            ]
            [ span [ class "hero-eye size-4" ] [], text (String.fromInt count) ]

    else
        text ""


viewMuteButton : Texts -> Bool -> Html Msg
viewMuteButton texts muted =
    iconButton "echo-mute"
        ToggleMuted
        (t texts
            (if muted then
                "Turn the sounds on"

             else
                "Turn the sounds off"
            )
        )
        (if muted then
            "hero-speaker-x-mark"

         else
            "hero-speaker-wave"
        )


viewShapesButton : Texts -> Bool -> Html Msg
viewShapesButton texts shapes =
    iconButton "echo-shapes"
        ToggleShapes
        (t texts
            (if shapes then
                "Hide the shapes on the pads"

             else
                "Show the shapes on the pads"
            )
        )
        (if shapes then
            "hero-eye"

         else
            "hero-eye-slash"
        )


iconButton : String -> Msg -> String -> String -> Html Msg
iconButton buttonId msg title icon =
    button
        [ id buttonId
        , class "grid size-8 place-items-center rounded-full text-slate-500 transition hover:bg-slate-100 hover:text-slate-800 active:scale-90 dark:text-slate-400 dark:hover:bg-white/10 dark:hover:text-slate-100"
        , onClick msg
        , Html.Attributes.title title
        ]
        [ span [ class (icon ++ " size-5") ] [] ]


{-| Starts a new game for all players, also during a game. On a small
screen, only the icon shows, but not in the column of a screen that is wider
than tall.
-}
viewRestartButton : Texts -> Html Msg
viewRestartButton texts =
    button
        [ id "echo-restart"
        , class "group flex size-9 shrink-0 items-center justify-center gap-2 rounded-full text-sm font-medium text-slate-600 ring-1 ring-slate-200 transition hover:bg-slate-50 hover:text-slate-900 hover:ring-slate-300 active:scale-95 max-lg:landscape:size-auto max-lg:landscape:px-4 max-lg:landscape:py-2 lg:order-5 lg:size-auto lg:self-start lg:px-4 lg:py-2 dark:text-slate-300 dark:ring-white/20 dark:hover:bg-white/10 dark:hover:text-white dark:hover:ring-white/30"
        , onClick Restart
        , Html.Attributes.title (t texts "Restart game")
        ]
        [ span [ class "hero-arrow-path size-4 transition-transform duration-300 group-hover:-rotate-180" ] []
        , span [ class "hidden max-lg:landscape:inline lg:inline" ] [ text (t texts "Restart game") ]
        ]


viewShareLink : Model -> Html Msg
viewShareLink model =
    div [ class "flex items-center gap-2 rounded-full bg-octo-mist p-1 pl-4 text-sm ring-1 ring-octo-indigo/20 max-lg:landscape:flex-col max-lg:landscape:items-stretch max-lg:landscape:rounded-2xl max-lg:landscape:p-2 lg:order-3 lg:flex-col lg:items-stretch lg:rounded-2xl lg:p-2 lg:pl-2 dark:bg-octo-indigo/15 dark:ring-octo-indigo-light/25" ]
        [ input
            [ id "echo-link"
            , readonly True
            , value model.gameUrl
            , class "min-w-0 flex-1 truncate bg-transparent text-octo-navy outline-none max-lg:landscape:px-2 max-lg:landscape:py-1 lg:px-2 lg:py-1 dark:text-slate-100"
            ]
            []
        , button
            [ id "echo-copy-link"
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


{-| The players in the order of their turns, with the longest sequence
that each one repeated. The player of the turn has a ring in the player's
color, and a bar in the last seconds of the turn. A player who is out is
crossed out.
-}
viewScores : Model -> Me -> Game -> Html Msg
viewScores model me game =
    ul [ id "echo-scores", class "flex flex-wrap gap-2 max-lg:landscape:flex-col lg:order-4 lg:flex-col" ]
        (List.map
            (\player ->
                let
                    current =
                        game.turn == Just player.id && not game.waiting && not game.finished
                in
                li
                    [ id ("echo-score-" ++ player.id)
                    , class "relative flex items-center gap-2 overflow-hidden rounded-full bg-white px-3 py-1 text-sm text-slate-800 shadow-sm ring-1 ring-slate-200 transition dark:bg-white/5 dark:text-slate-100 dark:shadow-none dark:ring-white/10"
                    , classList [ ( "opacity-50", player.away || player.out /= Nothing ), ( "memory-current", current ) ]

                    -- Elm's `style` cannot set a CSS variable
                    , attribute "style" ("--player-color: " ++ player.color)
                    ]
                    [ span [ class "size-3 rounded-full", style "background" player.color ] []
                    , span [ class "max-lg:landscape:flex-1 lg:flex-1", classList [ ( "line-through", player.out /= Nothing ) ] ] [ text (playerName model.texts me player) ]
                    , if current then
                        span [ class "text-xs font-medium tracking-wide uppercase", style "color" player.color ] [ text (t model.texts "turn") ]

                      else if player.out /= Nothing then
                        span [ class "text-xs font-medium tracking-wide text-slate-400 uppercase" ] [ text (t model.texts "out") ]

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


playerName : Texts -> Me -> Player -> String
playerName texts me player =
    if isMe me player then
        tf texts "{name} (you)" [ ( "name", shortName texts player ) ]

    else
        shortName texts player


{-| The name of a player, or the color for a guest
-}
shortName : Texts -> Player -> String
shortName texts player =
    Maybe.withDefault (t texts player.colorName) player.name


{-| The name of a player in a sentence: "The pink player" for a guest
-}
sentenceName : Texts -> Player -> String
sentenceName texts player =
    case player.name of
        Just name ->
            name

        Nothing ->
            tf texts "The {color} player" [ ( "color", t texts player.colorName ) ]


turnPlayer : Game -> Maybe Player
turnPlayer game =
    List.filter (\player -> game.turn == Just player.id) game.players |> List.head


{-| The line under the ring that tells what to do now
-}
status : Model -> Me -> Game -> String
status model me game =
    let
        texts =
            model.texts
    in
    if game.waiting || game.finished then
        ""

    else if solo game then
        if game.length == 0 then
            t texts "Tap Go to start."

        else if model.playback /= Nothing || model.typed >= game.length then
            t texts "Watch closely…"

        else
            tf texts "Your turn: {taps} to go." [ ( "taps", taps texts (game.length - model.typed) ) ]

    else if me /= Nothing && List.any (\player -> isMe me player && player.out /= Nothing) game.players then
        t texts "You are out. Watch the others play."

    else if myTurn me game then
        if game.length == 0 then
            t texts "You start. Tap any pad to add it to the sequence."

        else if game.step < game.length then
            tf texts "Your turn: repeat the sequence. {taps} to go." [ ( "taps", taps texts (game.length - game.step) ) ]

        else
            t texts "Now add a pad of your choice."

    else
        case turnPlayer game of
            Just player ->
                let
                    name =
                        [ ( "name", sentenceName texts player ) ]
                in
                if game.length == 0 then
                    tf texts "{name} starts the sequence." name

                else if game.step < game.length then
                    tf texts "{name} repeats the sequence." name

                else
                    tf texts "{name} adds a pad." name

            Nothing ->
                ""


{-| The texts have one form for 1 and one for more, as in English and
Portuguese
-}
taps : Texts -> Int -> String
taps texts n =
    if n == 1 then
        t texts "1 tap"

    else
        tf texts "{count} taps" [ ( "count", String.fromInt n ) ]



-- THE RING


{-| The size of the ring, in the units of the view box
-}
center : Float
center =
    170


outerRadius : Float
outerRadius =
    168


innerRadius : Float
innerRadius =
    64


padGap : Float
padGap =
    8


{-| The pads in a ring around the hub. The field shakes after a wrong tap.
The sizes of the hub are in % of the field, so that the field can have any
size.
-}
viewRing : Model -> Me -> Game -> Html Msg
viewRing model me game =
    let
        lit =
            case ( playbackPad model, model.flash ) of
                ( Just ( _, pad ), _ ) ->
                    Just pad

                ( Nothing, Just ( pad, _ ) ) ->
                    Just pad

                _ ->
                    Nothing

        playable =
            canPress model me game

        pads =
            List.take game.pads allPads |> List.indexedMap Tuple.pair
    in
    div
        [ id "echo-field"
        , class "relative aspect-square w-full"
        , classList [ ( "echo-shake", model.shaking ), ( "echo-no-shapes", not model.shapes ) ]
        , style "container-type" "inline-size"
        ]
        [ svg [ SA.viewBox "0 0 340 340", SA.class "absolute inset-0 size-full overflow-visible" ]
            (Svg.defs []
                [ Svg.filter [ SA.id "echo-glow", SA.x "-50%", SA.y "-50%", SA.width "200%", SA.height "200%" ]
                    [ Svg.feGaussianBlur [ SA.stdDeviation "10" ] [] ]
                ]
                :: Svg.circle [ SA.cx "170", SA.cy "170", SA.r "170", SA.class "echo-backing" ] []
                :: List.concatMap (\( index, pad ) -> viewPad model.texts game.pads playable (lit == Just index) index pad) pads
            )
        , viewHub model me game lit
        ]


viewPad : Texts -> Int -> Bool -> Bool -> Int -> Pad -> List (Html Msg)
viewPad texts count playable lit index pad =
    let
        path =
            sectorPath index count

        angle =
            centerAngle index count

        middle =
            (outerRadius + innerRadius) / 2

        glyphX =
            center + middle * cos angle - 15

        glyphY =
            center + middle * sin angle - 15
    in
    [ if lit then
        Svg.path [ SA.d path, SA.fill pad.color, SA.filter "url(#echo-glow)", SA.class "pointer-events-none" ] []

      else
        text ""
    , Svg.path
        [ id ("echo-pad-" ++ String.fromInt index)
        , SA.d path
        , SA.fill pad.color
        , SA.class
            (String.join " "
                (List.filter (not << String.isEmpty)
                    [ "echo-pad"
                    , if lit then
                        "is-lit"

                      else
                        ""
                    , if playable then
                        "is-playable"

                      else
                        ""
                    ]
                )
            )
        , attribute "role" "button"
        , attribute "aria-label" (tf texts "{color} pad, {shape}" [ ( "color", t texts pad.name ), ( "shape", t texts pad.shape ) ])
        , preventDefaultOn "pointerdown" (Decode.succeed ( Press index, True ))
        ]
        []

    -- Makes the pad dark until it lights up. Safari does not apply a CSS
    -- filter to an SVG shape, so a filter cannot do this.
    , Svg.path
        [ SA.d path
        , SA.class
            (if lit then
                "echo-pad-shade is-lit pointer-events-none"

             else
                "echo-pad-shade pointer-events-none"
            )
        ]
        []
    , Svg.path
        [ SA.d pad.glyph
        , SA.class "echo-glyph pointer-events-none"
        , SA.transform ("translate(" ++ String.fromFloat glyphX ++ " " ++ String.fromFloat glyphY ++ ") scale(1.25)")
        , SA.fill "none"
        , SA.stroke "rgba(20,21,31,.72)"
        , SA.strokeWidth "2.4"
        , SA.strokeLinecap "round"
        , SA.strokeLinejoin "round"
        ]
        []
    ]


centerAngle : Int -> Int -> Float
centerAngle index count =
    -pi / 2 + toFloat index * 2 * pi / toFloat count


point : Float -> Float -> String
point radius angle =
    String.fromFloat (center + radius * cos angle) ++ " " ++ String.fromFloat (center + radius * sin angle)


{-| A part of the ring, with a gap of the same width to each neighbour
-}
sectorPath : Int -> Int -> String
sectorPath index count =
    let
        angle =
            centerAngle index count

        half =
            pi / toFloat count

        outerOffset =
            padGap / 2 / outerRadius

        innerOffset =
            padGap / 2 / innerRadius

        outer =
            String.fromFloat outerRadius

        inner =
            String.fromFloat innerRadius
    in
    String.join " "
        [ "M"
        , point outerRadius (angle - half + outerOffset)
        , "A"
        , outer
        , outer
        , "0 0 1"
        , point outerRadius (angle + half - outerOffset)
        , "L"
        , point innerRadius (angle + half - innerOffset)
        , "A"
        , inner
        , inner
        , "0 0 0"
        , point innerRadius (angle - half + innerOffset)
        , "Z"
        ]


{-| The hub in the middle shows the length of the sequence. Alone, it
starts the game. Its edge has the color of the lit pad, or of the player
of the turn.
-}
viewHub : Model -> Me -> Game -> Maybe Int -> Html Msg
viewHub model me game lit =
    let
        ( big, small ) =
            hubText model me game

        edge =
            case lit |> Maybe.andThen padAt of
                Just pad ->
                    pad.color

                Nothing ->
                    if solo game then
                        ""

                    else
                        turnPlayer game |> Maybe.map .color |> Maybe.withDefault ""

        startable =
            me /= Nothing && solo game && game.length == 0 && not game.finished
    in
    button
        [ id "echo-hub"
        , class "echo-hub absolute flex flex-col items-center justify-center rounded-full"
        , classList [ ( "is-startable", startable ) ]
        , style "left" "33.53%"
        , style "top" "33.53%"
        , style "width" "32.94%"
        , style "height" "32.94%"
        , style "border-color" edge
        , onClick Start
        , attribute "aria-label"
            (if startable then
                t model.texts "Start game"

             else
                tf model.texts "Level {level}" [ ( "level", String.fromInt game.length ) ]
            )
        ]
        [ span
            [ id "echo-hub-big"
            , class "leading-none font-semibold tabular-nums"
            , style "font-size"
                (if String.toInt big == Nothing then
                    "10cqw"

                 else
                    "11.7cqw"
                )
            ]
            [ text big ]
        , span [ class "mt-[1.2cqw] max-w-[85%] truncate tracking-wider text-slate-400 uppercase", style "font-size" "3.2cqw" ] [ text small ]
        ]


hubText : Model -> Me -> Game -> ( String, String )
hubText model me game =
    let
        level =
            String.fromInt game.length

        texts =
            model.texts
    in
    if solo game then
        if game.length == 0 then
            ( t texts "Go", t texts "tap to play" )

        else if model.playback /= Nothing || model.typed >= game.length then
            ( level, t texts "watch" )

        else
            ( level, t texts "your turn" )

    else if myTurn me game then
        if game.step < game.length then
            ( level, t texts "repeat" )

        else
            ( level, t texts "add a pad" )

    else
        ( level
        , turnPlayer game
            |> Maybe.map (shortName texts)
            |> Maybe.withDefault ""
        )


{-| Covers the field until all players are in.
-}
viewWaiting : Texts -> Game -> Html Msg
viewWaiting texts game =
    div
        [ id "echo-waiting"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-3 rounded-2xl bg-octo-navy/80 p-4 text-center text-white"
        ]
        [ p [ class "text-3xl font-semibold" ] [ text (t texts "Waiting for players") ]
        , p [ id "echo-waiting-count", class "text-lg tabular-nums opacity-80" ]
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


{-| The players from the winner to the first player who went out
-}
ranking : List Player -> List Player
ranking players =
    List.sortBy (\player -> negate (Maybe.withDefault 1000 player.out)) players


viewResult : Model -> Me -> Game -> Html Msg
viewResult model me game =
    let
        texts =
            model.texts

        nextGame =
            model.nextGame

        winner =
            List.filter (\player -> game.winner == Just player.id) game.players |> List.head

        ( message, detail ) =
            if solo game then
                ( t texts "Game over"
                , tf texts "You repeated {pads}." [ ( "pads", List.head game.players |> Maybe.map .score |> Maybe.withDefault 0 |> padsText texts ) ]
                )

            else
                case winner of
                    Just player ->
                        ( if isMe me player then
                            t texts "You win!"

                          else
                            tf texts "{name} wins!" [ ( "name", sentenceName texts player ) ]
                        , tf texts "The sequence had {pads}." [ ( "pads", padsText texts game.length ) ]
                        )

                    Nothing ->
                        ( t texts "Game over", "" )
    in
    div
        [ id "echo-result"
        , class "absolute inset-0 flex flex-col items-center justify-center gap-4 rounded-2xl bg-octo-navy/75 p-4 text-center text-white backdrop-blur-sm"
        ]
        [ p [ class "text-3xl font-semibold" ] [ text message ]
        , p [ id "echo-final", class "text-lg opacity-80" ] [ text detail ]
        , if solo game then
            text ""

          else
            ol [ class "flex flex-col gap-1 text-sm" ]
                (List.map
                    (\player ->
                        li [ class "flex items-center gap-2" ]
                            [ span [ class "size-3 rounded-full", style "background" player.color ] []
                            , span [ class "flex-1 text-left" ] [ text (playerName texts me player) ]
                            , span [ class "pl-6 font-semibold tabular-nums" ] [ text (String.fromInt player.score) ]
                            ]
                    )
                    (ranking game.players)
                )
        , if me == Nothing then
            text ""

          else
            button
                [ id "echo-play-again"
                , class "rounded-full bg-white px-6 py-2.5 font-medium text-octo-indigo shadow-lg transition hover:-translate-y-0.5 hover:bg-octo-mist active:translate-y-0"
                , onClick Restart
                ]
                [ text (t texts "Play again") ]
        , let
            -- In a game with other players, a player starts the next game for all of them
            ( element, action ) =
                if me /= Nothing && List.length game.players > 1 then
                    ( button, onClick StartNextGame )

                else
                    ( a, href nextGame.path )
          in
          element
            [ id "echo-next-game"
            , action
            , attribute "data-ga-link" "or_try"
            , attribute "data-ga-from" "Echo"
            , attribute "data-ga-to" nextGame.name
            , class "group text-sm font-medium text-white underline-offset-4 transition hover:underline"
            ]
            [ text (tf texts "Or try {game}" [ ( "game", nextGame.name ) ] ++ " ")
            , span [ class "inline-block transition group-hover:translate-x-0.5" ] [ text "→" ]
            ]

        -- Only a guest who played gets the call to sign in, not a spectator
        , if model.guest && me /= Nothing then
            p [ id "echo-sign-in", class "text-sm text-white/70" ]
                (withLink texts
                    "{sign_in} to keep your scores."
                    "sign_in"
                    (a
                        [ href "/signin"
                        , class "font-medium text-white underline underline-offset-4 transition hover:text-octo-mist"
                        ]
                        [ text (t texts "Sign in") ]
                    )
                )

          else
            text ""
        , viewFeed texts
        ]


{-| The call to support Octomocto on Patreon, at the bottom of a result.
The link opens in a new tab, so that the player stays in the game.
-}
viewFeed : Texts -> Html msg
viewFeed texts =
    p [ id "echo-feed", class "mt-2 max-w-sm border-t border-white/15 pt-4 text-center text-sm leading-10 text-balance text-white/80" ]
        (withLink texts
            "Enjoying Octomocto? {feed} to keep it ad-free."
            "feed"
            (a
                [ href "https://patreon.com/mxgrn"
                , target "_blank"
                , rel "noopener"
                , class "group mx-1 inline-flex items-center gap-1.5 whitespace-nowrap rounded-full bg-octo-orange px-4 py-1.5 align-middle leading-5 font-semibold text-white shadow-lg shadow-octo-orange/30 transition hover:-translate-y-0.5 hover:bg-octo-orange-light active:translate-y-0"
                ]
                [ span [ class "hero-heart-solid size-4 transition group-hover:scale-110" ] []
                , text (t texts "Feed Octo & Mocto")
                ]
            )
        )


{-| The text in the language of the page, with the link in its `{name}`
part
-}
withLink : Texts -> String -> String -> Html msg -> List (Html msg)
withLink texts english name link =
    case String.split ("{" ++ name ++ "}") (t texts english) of
        [ before, after ] ->
            [ text before, link, text after ]

        _ ->
            [ text (t texts english), link ]


{-| The texts have one form for 1 and one for more, as in English and
Portuguese
-}
padsText : Texts -> Int -> String
padsText texts n =
    if n == 1 then
        t texts "1 pad"

    else
        tf texts "{count} pads" [ ( "count", String.fromInt n ) ]



-- MAIN


main : Program Flags Model Msg
main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }
