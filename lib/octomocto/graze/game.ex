defmodule Octomocto.Graze.Game do
  @moduledoc """
  One game of Graze: each player is a circle in one shared field (see
  `Octomocto.Graze.World`). The circles go through each other. A circle
  eats the food squares for points and energy. A perk square is food that
  also makes the circle invisible to the danger squares for some seconds.
  A circle that touches a danger square, or that has no energy left, is
  out, and its score stays.
  The field is finished when all circles are out. The player with the
  most points wins.

  The game process runs the field: it ticks every `@tick_ms` while the
  field runs, moves the squares in and out, and sends the state to the
  clients on each tick (without a copy in the store, see
  `Octomocto.RaceServer`). The browser of a player sends the place of its
  circle many times a second, with the time of the field when the player
  saw it (`{:steer, player_id, x, y, t}`). The game checks the way of the
  circle at that time, because the place of each square at any time is
  known. Thus the network delay does not change what the player saw. The
  game accepts times up to `@lag_ms` in the past. A circle that sends no
  places (for example, when the tab is in the background) stays where it
  is, and the tick checks it at that delay.

  The players, the clock, the lists of the settings page and the copy in
  `Octomocto.Graze.Store` are the same as in the other games, see
  `Octomocto.RaceServer`. Each change is broadcast on the
  `"graze_game:<id>"` PubSub topic as `{:graze_state, state}`.
  """
  use Octomocto.RaceServer,
    topic: "graze_game",
    state_message: :graze_state,
    lobby_topic: "graze_lobby",
    store: Octomocto.Graze.Store,
    context: Octomocto.Graze

  alias Octomocto.Graze.World
  alias Octomocto.{RaceServer, Seats}

  @tick_ms 50
  # Before the start, the tick only waits for the countdown
  @idle_tick_ms 250
  @lag_ms 300

  @doc "How far in the past a move can be, in milliseconds."
  def lag_ms, do: @lag_ms

  # Graze has no settings except the number of players
  @impl true
  def init_settings(_config), do: %{}

  @impl true
  def new_field(state) do
    schedule_tick(state.field_id, @idle_tick_ms)

    Map.merge(state, %{
      squares: [],
      next_square_id: 1,
      next_danger_at: nil,
      placed: false,
      perk_paused_until: 0
    })
  end

  @impl true
  def new_player(player), do: Map.merge(player, circle())

  @impl true
  def reset_player(player), do: Map.merge(player, circle())

  defp circle do
    center = World.size() / 2

    %{
      x: center,
      y: center,
      t: 0,
      alive: true,
      energy: 1.0,
      energy_at: 0,
      survived_ms: 0,
      invisible_until: 0
    }
  end

  # The game starts again on another node: its ticks were on the old node
  @impl true
  def restore(state) do
    schedule_tick(state.field_id, @tick_ms)
    state
  end

  @impl true
  def handle_move({:steer, player_id, x, y, t}, state)
      when is_map_key(state.players, player_id) and is_number(x) and is_number(y) and
             is_integer(t) do
    player = state.players[player_id]

    if running?(state) and player.alive do
      now = RaceServer.now()
      t = t |> min(now) |> max(now - @lag_ms) |> max(player.t)
      {state, changed} = trace(state, player_id, x, y, t)
      result(state, changed, :ignore)
    else
      {:ignore, :ok, state}
    end
  end

  def handle_move(_move, state), do: {:ignore, :ok, state}

  defp result(state, changed, quiet) do
    state = finish_when_all_out(state)

    cond do
      state.finished_at != nil -> {:publish, :ok, state}
      changed -> {:publish, :ok, state}
      true -> {quiet, :ok, state}
    end
  end

  @impl true
  def handle_message({:graze_tick, field_id}, %{field_id: field_id} = state) do
    cond do
      state.finished_at != nil ->
        {:ignore, state}

      state.started_at == nil ->
        schedule_tick(field_id, @idle_tick_ms)
        {:ignore, state}

      not state.placed ->
        schedule_tick(field_id, @tick_ms)
        {:publish, place(state)}

      not RaceServer.started?(state) ->
        schedule_tick(field_id, @tick_ms)
        {:ignore, state}

      true ->
        schedule_tick(field_id, @tick_ms)
        {kind, _reply, state} = tick(state, RaceServer.now())
        {kind, state}
    end
  end

  # A tick of an older field
  def handle_message(_message, state), do: {:ignore, state}

  defp schedule_tick(field_id, ms), do: Process.send_after(self(), {:graze_tick, field_id}, ms)

  defp running?(state),
    do: state.placed and RaceServer.started?(state) and state.finished_at == nil

  # The circles start on a ring around the center, in the order in which
  # the players joined, with full energy. One circle starts in the center.
  defp place(state) do
    ids = Seats.order(state)
    count = length(ids)
    center = World.size() / 2

    players =
      ids
      |> Enum.with_index()
      |> Map.new(fn {id, index} ->
        angle = 2 * :math.pi() * index / count - :math.pi() / 2
        distance = if count == 1, do: 0, else: 200

        player =
          Map.merge(state.players[id], %{
            x: center + distance * :math.cos(angle),
            y: center + distance * :math.sin(angle),
            t: state.started_at,
            alive: true,
            energy: 1.0,
            energy_at: state.started_at,
            survived_ms: 0,
            invisible_until: 0
          })

        {id, player}
      end)

    %{
      state
      | players: players,
        placed: true,
        next_danger_at: state.started_at + World.danger_delay_ms(),
        perk_paused_until: state.started_at + World.perk_delay_ms()
    }
  end

  # The squares move in and out. Then each circle that sent no place for a
  # time stays where it is, and the game checks it. A circle without
  # energy is out.
  defp tick(state, now) do
    check_at = now - @lag_ms

    state =
      state
      |> drop_gone(check_at)
      |> add_dangers(now)
      |> add_food(now)

    {state, changed} =
      Enum.reduce(alive_ids(state), {state, false}, fn id, {state, changed} ->
        player = state.players[id]

        {state, moved} =
          if player.t < check_at,
            do: trace(state, id, player.x, player.y, check_at),
            else: {state, false}

        {state, starved} = starve(state, id, check_at)
        {state, changed or moved or starved}
      end)

    result(state, changed, :broadcast)
  end

  defp alive_ids(state), do: for({id, %{alive: true}} <- state.players, do: id)

  defp drop_gone(state, check_at),
    do: %{state | squares: Enum.filter(state.squares, &(&1.until >= check_at))}

  # A new food square for each one that is eaten or gone, so that there are
  # always as many food squares as danger squares (at least
  # `World.food_count/0`)
  defp add_food(state, now) do
    food = Enum.count(state.squares, &(&1.kind == :food))
    dangers = length(state.squares) - food
    wanted = max(World.food_count(), dangers)

    Enum.reduce(food..(wanted - 1)//1, state, fn _, state ->
      # A game that started before the perks has no pause
      paused_until = Map.get(state, :perk_paused_until, 0)
      perk = if World.perk_food?(state.squares, now, paused_until), do: :invisible
      add(state, :food, now, perk: perk)
    end)
  end

  # The danger squares come at the times of `next_danger_at`, more and more
  # often
  defp add_dangers(state, now) do
    if state.next_danger_at <= now do
      at = state.next_danger_at
      elapsed_s = (at - state.started_at) / 1000

      state
      |> add(:danger, at)
      |> Map.put(:next_danger_at, at + World.danger_interval(elapsed_s))
      |> add_dangers(now)
    else
      state
    end
  end

  defp add(state, kind, t, opts \\ []) do
    elapsed_s = (t - state.started_at) / 1000
    square = World.spawn(kind, state.next_square_id, t, elapsed_s, opts)
    %{state | squares: state.squares ++ [square], next_square_id: state.next_square_id + 1}
  end

  # Moves the circle of the player to `x`, `y` at the time `t`, and checks
  # each point of its way. Gives true when the circle ate or is out.
  defp trace(state, id, x, y, t) do
    player = state.players[id]
    {x, y} = World.limit_move({player.x, player.y}, {x, y}, t - player.t)

    World.path({player.x, player.y, player.t}, {x, y, t})
    |> Enum.reduce_while({state, false}, fn {px, py, pt}, {state, changed} ->
      state = update_in(state.players[id], &%{&1 | x: px, y: py, t: pt})
      invisible = pt < invisible_until(state.players[id])

      case World.hit(state.squares, px, py, pt, invisible) do
        %{kind: :danger} ->
          {:halt, {out(state, id, pt), true}}

        %{kind: :food} = square ->
          {:cont, {eat(state, id, square, pt), true}}

        nil ->
          {:cont, {state, changed}}
      end
    end)
  end

  defp eat(state, id, square, t) do
    state =
      state
      |> Map.update!(:squares, &Enum.reject(&1, fn s -> s.id == square.id end))
      |> update_in([:players, id], &%{World.eat(&1, t, state.started_at) | score: &1.score + 1})

    # A square of a game that started before the perks has no perk key
    case Map.get(square, :perk) do
      :invisible ->
        state
        |> put_in([:players, id, :invisible_until], t + World.perk_ms())
        |> Map.put(:perk_paused_until, t + World.perk_pause_ms())

      nil ->
        state
    end
  end

  defp invisible_until(player), do: Map.get(player, :invisible_until, 0)

  defp starve(state, id, t) do
    if World.energy(state.players[id], t, state.started_at) <= 0,
      do: {out(state, id, t), true},
      else: {state, false}
  end

  defp out(state, id, t) do
    update_in(state.players[id], &%{&1 | alive: false, survived_ms: t - state.started_at})
  end

  defp finish_when_all_out(state) do
    if state.finished_at == nil and state.players != %{} and alive_ids(state) == [],
      do: RaceServer.finish(state),
      else: state
  end

  @impl true
  def lobby_settings(_state), do: %{}

  @impl true
  def result_settings(_state), do: %{}

  @impl true
  def public_field(state) do
    now = RaceServer.now()
    started_at = state.started_at || now

    circles =
      for {id, p} <- state.players do
        %{
          id: id,
          x: round1(p.x),
          y: round1(p.y),
          alive: p.alive,
          energy: if(state.placed, do: round3(World.energy(p, now, started_at)), else: 1.0),
          survived_ms: p.survived_ms,
          invisible_until: invisible_until(p)
        }
      end

    %{
      now: now,
      size: World.size(),
      radius: World.radius(),
      max_speed: World.max_speed(),
      drain: round3(World.drain_rate(now, started_at)),
      circles: circles,
      squares: Enum.map(state.squares, &public_square/1)
    }
  end

  defp public_square(square) do
    %{
      id: square.id,
      kind: square.kind,
      size: square.size,
      x: round1(square.x),
      y: round1(square.y),
      vx: round1(square.vx),
      vy: round1(square.vy),
      t: square.t,
      perk: Map.get(square, :perk)
    }
  end

  defp round1(value), do: Float.round(value * 1.0, 1)
  defp round3(value), do: Float.round(value * 1.0, 3)
end
