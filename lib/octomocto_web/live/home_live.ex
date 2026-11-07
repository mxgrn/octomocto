defmodule OctomoctoWeb.HomeLive do
  @moduledoc """
  The front page: the list of all games, the public games of all games
  together (see `Octomocto.Lobby`), and the friends of the user who are
  online (see `Octomocto.Friends` and `Octomocto.OnlineUsers`). A guest
  sees a text that asks to sign in instead.
  """
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.SiteBanners, nil}

  import OctomoctoWeb.GamePageComponents

  alias Octomocto.{Accounts, Friends, Lobby, OnlineUsers}
  alias Octomocto.Memory.Themes

  alias OctomoctoWeb.{
    AfterglowLive,
    EchoLive,
    GameIcons,
    GrazeLive,
    MahjongLive,
    MemoryLive,
    OverlapLive,
    NimbleMosaicLive,
    SchulteLive,
    SetGameLive,
    SudokuLive,
    TrainsLive
  }

  @games [
    %{
      id: "nimble-mosaic",
      tags: ["speed", "attention"],
      name: "Nimble Mosaic",
      description:
        dgettext_noop(
          "home",
          "Find the numbers in order. The first player to click the next number gets the point."
        ),
      path: "/nimble-mosaic",
      badge: {dgettext_noop("home", "Trending this week"), "hero-fire-mini"},
      icon_class: "bg-octo-indigo/10 dark:bg-octo-indigo-light/15"
    },
    %{
      id: "schulte",
      tags: ["speed", "attention"],
      name: "Schulte Table",
      description:
        dgettext_noop(
          "home",
          "The classic Schulte table: find the numbers in order on a square grid, with your eyes on the center."
        ),
      path: "/schulte",
      badge: {"New", "hero-sparkles-mini"},
      icon_class: "bg-octo-indigo/10 dark:bg-octo-indigo-light/15"
    },
    %{
      id: "graze",
      tags: ["speed", "attention"],
      name: "Graze & Dodge",
      description:
        dgettext_noop(
          "home",
          "Eat the black squares and keep away from the red ones, with up to 3 friends in one field."
        ),
      path: "/graze",
      badge: {dgettext_noop("home", "Beta"), "hero-beaker-mini"},
      icon_class: "bg-octo-indigo/10 dark:bg-octo-indigo-light/15"
    },
    %{
      id: "trains",
      tags: ["attention"],
      name: "Right on Track",
      description:
        dgettext_noop(
          "home",
          "Click the switches to send each train to the house with its colors."
        ),
      path: "/trains",
      icon_class: "bg-octo-orange/10 dark:bg-octo-orange-light/15"
    },
    %{
      id: "memory",
      tags: ["memory"],
      name: "Memory",
      description:
        dgettext_noop(
          "home",
          "Find the cards with the same image. Play alone against the clock, or take turns."
        ),
      path: "/memory",
      badge: {dgettext_noop("home", "Most popular"), "hero-star-mini"},
      icon_class: "bg-sky-500/10 dark:bg-sky-400/15"
    },
    %{
      id: "set",
      tags: ["speed", "logic", "attention"],
      name: "Set",
      description:
        dgettext_noop(
          "home",
          "Find 3 cards where each feature is all the same or all different. Race your friends."
        ),
      path: "/set",
      icon_class: "bg-violet-500/10 dark:bg-violet-400/15"
    },
    %{
      id: "sudoku",
      tags: ["speed", "logic"],
      name: "Sudoku Race",
      description:
        dgettext_noop(
          "home",
          "Fill the same sudoku with your friends. The first player to put the correct digit gets the point."
        ),
      path: "/sudoku",
      icon_class: "bg-rose-500/10 dark:bg-rose-400/15"
    },
    %{
      id: "echo",
      tags: ["memory"],
      name: "Echo Chamber",
      description:
        dgettext_noop(
          "home",
          "A Simon-like game: repeat the sequence of colored pads. With friends, each player adds a pad."
        ),
      path: "/echo",
      icon_class: "bg-amber-500/10 dark:bg-amber-400/15"
    },
    %{
      id: "mahjong",
      tags: ["speed"],
      name: "Mahjong Race",
      description:
        dgettext_noop(
          "home",
          "Remove pairs of free tiles from the Turtle. With friends, the first to take a pair gets the point."
        ),
      path: "/mahjong",
      icon_class: "bg-emerald-500/10 dark:bg-emerald-400/15"
    },
    %{
      id: "overlap",
      tags: ["speed", "attention"],
      name: "Overlap",
      description:
        dgettext_noop(
          "home",
          "A Dobble-like game: any two cards have exactly one symbol in common. Spot it first."
        ),
      path: "/overlap",
      icon_class: "bg-pink-500/10 dark:bg-pink-400/15"
    },
    %{
      id: "snap",
      tags: ["speed", "memory"],
      name: "Snap",
      description:
        dgettext_noop(
          "home",
          "Is the new card the same as the card before it? You have 45 seconds. Make no mistakes to grow the multiplier up to x5."
        ),
      path: "/snap",
      icon_class: "bg-teal-500/10 dark:bg-teal-400/15",
      # Not suggested at the end of a multiplayer game, see `OctomoctoWeb.NextGame`
      single_player: true
    },
    %{
      id: "afterglow",
      tags: ["memory"],
      name: "Afterglow Memory",
      description:
        dgettext_noop(
          "home",
          "Tiles light up for a moment. Click the tiles that were lit. With friends, make one pattern in turns."
        ),
      path: "/afterglow",
      badge: {"New", "hero-sparkles-mini"},
      icon_class: "bg-fuchsia-500/10 dark:bg-fuchsia-400/15"
    }
    # Station Escape is archived: it is not on the front page and is not
    # suggested on the end screens. Do not change it for now.
    # %{
    #   id: "astronaut",
    #   name: "Station Escape",
    #   description:
    #     "Race your friends to the escape pod on a space station that spins while you play.",
    #   path: "/astronaut",
    #   icon_class: "bg-octo-navy dark:bg-black/30 dark:ring-1 dark:ring-white/10"
    # }
  ]

  # The tag filters above the games, in this order. Each game in @games has
  # one or more of these tags.
  @tags ["speed", "memory", "logic", "attention"]

  # The names of the tags. A new tag needs a line here.
  defp tag_name("speed"), do: dgettext("home", "Speed")
  defp tag_name("memory"), do: dgettext("home", "Memory")
  defp tag_name("logic"), do: dgettext("home", "Logic")
  defp tag_name("attention"), do: dgettext("home", "Attention")

  # The texts in @games are in the "home" domain. "New" stays in English in
  # all languages.
  defp badge_label("New"), do: "New"
  defp badge_label(label), do: Gettext.dgettext(OctomoctoWeb.Gettext, "home", label)

  defp game_description(game),
    do: Gettext.dgettext(OctomoctoWeb.Gettext, "home", game.description)

  @doc """
  The name of the game in the language of the process. Only a game with
  translations in the language has a translated name (in the domain of the
  game), so that the name is the same as on the page of the game.
  """
  def game_name(game) do
    if Locale.translated?(Gettext.get_locale(OctomoctoWeb.Gettext), game.id),
      do: Gettext.dgettext(OctomoctoWeb.Gettext, game.id, game.name),
      else: game.name
  end

  @doc """
  The list of all games, as on the front page.
  """
  def games, do: @games

  # The games that have lists of public games, by the id in
  # @games, with the game module, its store and the page that gives the
  # settings of a game in a row
  @lobbies %{
    "memory" => {Octomocto.Memory.Game, Octomocto.Memory.Store, MemoryLive},
    "trains" => {Octomocto.Trains.Game, Octomocto.Trains.Store, TrainsLive},
    "set" => {Octomocto.SetGame.Game, Octomocto.SetGame.Store, SetGameLive},
    "sudoku" => {Octomocto.Sudoku.Game, Octomocto.Sudoku.Store, SudokuLive},
    "nimble-mosaic" =>
      {Octomocto.NimbleMosaic.Game, Octomocto.NimbleMosaic.Store, NimbleMosaicLive},
    "echo" => {Octomocto.Echo.Game, Octomocto.Echo.Store, EchoLive},
    "mahjong" => {Octomocto.Mahjong.Game, Octomocto.Mahjong.Store, MahjongLive},
    "overlap" => {Octomocto.Overlap.Game, Octomocto.Overlap.Store, OverlapLive},
    "schulte" => {Octomocto.Schulte.Game, Octomocto.Schulte.TableStore, SchulteLive},
    "graze" => {Octomocto.Graze.Game, Octomocto.Graze.Store, GrazeLive},
    # Only the games with turns: the single-player games are never in the lists
    "afterglow" => {Octomocto.Afterglow.TurnGame, Octomocto.Afterglow.TurnStore, AfterglowLive}
  }

  @kinds_by_game Map.new(@lobbies, fn {kind, {game, _store, _page}} -> {game, kind} end)

  @doc """
  The game module, the store and the settings page of a game with lists of
  public games, by the id in `games/0`, or nil for another game.
  """
  def lobby_modules(id), do: @lobbies[id]

  @doc "The settings page of the game, by the id in `games/0`."
  def settings_page(id), do: @lobbies |> Map.fetch!(id) |> elem(2)

  def mount(_params, _session, socket) do
    # Nil for a guest. A friend that the user gets later shows after a
    # page load.
    friends =
      case socket.assigns.current_scope do
        %{user: user} -> Friends.friends(user.id)
        nil -> nil
      end

    if connected?(socket) do
      for {_kind, {game, _store, _page}} <- @lobbies, do: Lobby.subscribe(game)
      if friends, do: OnlineUsers.subscribe()
    end

    entries =
      for {kind, {game, store, _page}} <- @lobbies,
          entry <- Lobby.entries(game, store),
          do: Map.put(entry, :kind, kind)

    {:ok,
     socket
     |> assign(
       canonical_url: OctomoctoWeb.Endpoint.url() <> Locale.path(socket.assigns.locale, ~p"/"),
       alternate_urls: Locale.alternate_urls(:all, ~p"/"),
       tags: @tags,
       kinds: Map.new(@games, &{&1.id, &1})
     )
     |> assign_lobby(entries)
     |> assign(watchers: watchers())
     |> assign(friends: friends)
     |> assign_friends_online()}
  end

  # The tag filter is in the URL, for example /?tag=memory. An unknown tag
  # shows all games.
  def handle_params(params, _uri, socket) do
    tag = if params["tag"] in @tags, do: params["tag"]
    games = if tag, do: Enum.filter(@games, &(tag in &1.tags)), else: @games

    path = if tag, do: ~p"/?tag=#{tag}", else: ~p"/"

    {:noreply,
     assign(socket,
       tag: tag,
       games: games,
       languages: Locale.languages(:all, socket.assigns.locale, path)
     )}
  end

  def handle_info({:lobby_changed, game, id, entry}, socket) do
    entry = entry && Map.put(entry, :kind, Map.fetch!(@kinds_by_game, game))

    {:noreply,
     socket
     |> maybe_push_new_game(id, entry)
     |> assign_lobby(Lobby.put_entry(socket.assigns.lobby, id, entry))}
  end

  # A user came, left or changed the page, or a watcher came or left (see
  # `Octomocto.Lobby.watch/3`)
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", topic: topic}, socket) do
    if topic == OnlineUsers.topic(),
      do: {:noreply, assign_friends_online(socket)},
      else: {:noreply, assign(socket, watchers: watchers())}
  end

  # Tells the page to play a sound when a new open game enters the list
  defp maybe_push_new_game(socket, id, %{status: :open}) do
    if Enum.any?(socket.assigns.lobby, &(&1.id == id and &1.status == :open)),
      do: socket,
      else: push_event(socket, "lobby_new_game", %{})
  end

  defp maybe_push_new_game(socket, _id, _entry), do: socket

  # The game ids are random, so two kinds of games do not have the same id
  defp watchers do
    for {_kind, {game, _store, _page}} <- @lobbies, reduce: %{} do
      watchers -> Map.merge(watchers, Lobby.watchers(game))
    end
  end

  # The friends who are online, by name, each with an activity
  defp assign_friends_online(%{assigns: %{friends: nil}} = socket),
    do: assign(socket, friends_online: [])

  defp assign_friends_online(%{assigns: %{friends: friends}} = socket) do
    activities = OnlineUsers.activities(Enum.map(friends, & &1.id))

    friends_online =
      for friend <- friends, activity = activities[friend.id] do
        %{
          id: friend.id,
          name: Accounts.public_name(friend),
          avatar_url: friend.avatar_url,
          public_id: friend.public_id
        }
        |> Map.put(:activity, activity)
      end
      |> Enum.sort_by(&String.downcase(&1.name || ""))

    assign(socket, friends_online: friends_online)
  end

  @doc ~S|The text of the activity of an online user, for example "Playing Memory".|
  def activity_text(%{kind: kind, doing: doing}) do
    game = kind && Enum.find(@games, &(&1.id == kind))
    name = game && game_name(game)

    case doing do
      "playing" when name != nil -> dgettext("home", "Playing %{game}", game: name)
      "watching" when name != nil -> dgettext("home", "Watching %{game}", game: name)
      "settings" when name != nil -> dgettext("home", "On the %{game} page", game: name)
      _ -> dgettext("home", "Online")
    end
  end

  defp assign_lobby(socket, entries) do
    assign(socket, lobby: entries, lobby_games: Lobby.games(entries))
  end

  # The page of a game, in the language when the game has translations
  defp game_path(locale, game) do
    path = "/#{game.kind}/#{game.id}"
    if Locale.translated?(locale, game.kind), do: Locale.path(locale, path), else: path
  end

  # The settings of a row, as on the settings page of its kind of game. Nil
  # for a kind of game whose settings never change.
  defp game_summary(game) do
    {_game, _store, page} = Map.fetch!(@lobbies, game.kind)
    page.game_summary(game)
  end

  attr :game, :map, required: true, doc: "an item of @games"
  attr :small, :boolean, default: false, doc: "the size for a row of the lists"

  defp game_icon(assigns) do
    ~H"""
    <div class={[
      "flex shrink-0 items-center justify-center",
      if(@small,
        do: "size-9 rounded-xl",
        else: "size-12 rounded-2xl"
      ),
      @game.icon_class
    ]}>
      <GameIcons.game_icon game={@game.id} class={if(@small, do: "size-7", else: "size-9")} />
    </div>
    """
  end
end
