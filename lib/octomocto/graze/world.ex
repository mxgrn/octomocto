defmodule Octomocto.Graze.World do
  @moduledoc """
  The rules of the field of Graze, as functions without side effects
  (except the random numbers of new squares).

  The field is a square of `size/0` × `size/0` units. Each player is a
  circle with the radius `radius/0`. Squares fly into the field from its
  edges, vertically or horizontally, and fly out at the other side. A square
  is a map with its `:kind` (`:food` or `:danger`), its side (`:size`),
  the place of its center (`:x`, `:y`) at the time `:t`, its speed
  (`:vx`, `:vy`, in units per second), and the time `:until` when it is
  out of the field. Thus the place of a square at any time is known
  (`position/2`), and the game can check a move of a player at the time
  when the player made it (see `Octomocto.Graze.Game`).

  The times are the system time in milliseconds, the same on all nodes.

  Each circle has energy from 0 to 1. The energy goes down all the time,
  faster and faster after the start (see `energy/3`). A food square gives
  energy back.
  """

  @size 1000
  @radius 22

  # The fewest food squares in the field. With more danger squares, there
  # are as many food squares as danger squares.
  @food_count 3
  @food_size 32
  @eat_energy 0.3

  # Sometimes a perk square comes in place of a food square: larger and
  # faster. It is food, and it also gives a perk for `@perk_ms`. Only one
  # perk square is in the field at a time, and no perk square comes for
  # half of `@perk_ms` after a circle eats one, or in the first
  # `@perk_delay_ms` of the field.
  @perk_delay_ms 10_000
  @perk_food_odds 30
  @perk_food_size 44
  @perk_food_speedup 1.6
  @perk_ms 10_000

  # The energy goes down by `@drain_base` per second at the start, and the
  # rate goes up by `@drain_growth` each second. A circle with full energy
  # that eats nothing lasts about 11 seconds at the start.
  @drain_base 0.07
  @drain_growth 0.0015

  # Nothing dangerous comes in the first seconds of the field
  @danger_delay_ms 2000

  # The speed of a circle in units per millisecond. The browser moves the
  # circle to the pointer with this speed, and the game does not accept a
  # faster move (with some slack for the network).
  @max_speed 5.0
  @speed_slack 80

  def size, do: @size
  def radius, do: @radius
  def food_count, do: @food_count
  def danger_delay_ms, do: @danger_delay_ms
  def max_speed, do: @max_speed
  def perk_ms, do: @perk_ms
  def perk_pause_ms, do: div(@perk_ms, 2)
  def perk_delay_ms, do: @perk_delay_ms

  @doc "The place of the center of the square at the time `t`."
  def position(square, t) do
    dt = (t - square.t) / 1000
    {square.x + square.vx * dt, square.y + square.vy * dt}
  end

  @doc "True when the square is in the field at the time `t`."
  def present?(square, t), do: t >= square.t and t <= square.until

  @doc """
  The square that a circle at `x`, `y` touches at the time `t`: a danger
  square first, then a food square. Nil when it touches no square. An
  `invisible` circle does not see the danger squares.
  """
  def hit(squares, x, y, t, invisible \\ false) do
    touched =
      Enum.filter(
        squares,
        &(present?(&1, t) and not (invisible and &1.kind == :danger) and touches?(&1, x, y, t))
      )

    Enum.find(touched, &(&1.kind == :danger)) || List.first(touched)
  end

  @doc "True when a circle at `x`, `y` touches the square at the time `t`."
  def touches?(square, x, y, t) do
    {sx, sy} = position(square, t)
    half = square.size / 2
    dx = max(abs(x - sx) - half, 0)
    dy = max(abs(y - sy) - half, 0)
    dx * dx + dy * dy < @radius * @radius
  end

  @doc """
  The place where a circle goes from `from` to `to` in `dt` milliseconds:
  `to` in the field, but not farther from `from` than the circle can go.
  """
  def limit_move({fx, fy}, {x, y}, dt) do
    {x, y} = {clamp(x), clamp(y)}
    {dx, dy} = {x - fx, y - fy}
    distance = :math.sqrt(dx * dx + dy * dy)
    allowed = @max_speed * max(dt, 0) + @speed_slack

    if distance <= allowed do
      {x, y}
    else
      {fx + dx * allowed / distance, fy + dy * allowed / distance}
    end
  end

  defp clamp(value), do: value |> max(@radius) |> min(@size - @radius)

  @doc """
  The points on the way of a circle from `{x, y, t}` to `{x, y, t}`, after
  the start and with the end. The points are near enough to each other
  that a circle does not jump over a square.
  """
  def path({fx, fy, ft}, {tx, ty, tt}) do
    distance = :math.sqrt((tx - fx) * (tx - fx) + (ty - fy) * (ty - fy))
    steps = max(ceil(distance / 10), ceil((tt - ft) / 16)) |> max(1) |> min(40)

    for i <- 1..steps do
      f = i / steps
      {fx + (tx - fx) * f, fy + (ty - fy) * f, round(ft + (tt - ft) * f)}
    end
  end

  @doc """
  The energy of a player at the time `t`. The player has `:energy` at the
  time `:energy_at`. The field started at `started_at`.
  """
  def energy(%{energy: energy, energy_at: energy_at}, t, started_at) do
    used = drained((t - started_at) / 1000) - drained((energy_at - started_at) / 1000)
    max(energy - used, 0.0)
  end

  @doc "The energy after the player eats a food square at the time `t`."
  def eat(player, t, started_at) do
    %{player | energy: min(energy(player, t, started_at) + @eat_energy, 1.0), energy_at: t}
  end

  @doc """
  True when the next food square at the time `t` must be a perk square: by
  chance, only when no perk square is in `squares`, and not before
  `paused_until`.
  """
  def perk_food?(squares, t, paused_until) do
    t >= paused_until and not Enum.any?(squares, &Map.get(&1, :perk)) and
      :rand.uniform(@perk_food_odds) == 1
  end

  @doc "The energy that a circle loses each second at the time `t`."
  def drain_rate(t, started_at), do: @drain_base + @drain_growth * max(t - started_at, 0) / 1000

  # The energy that a circle loses in the first `s` seconds of the field
  defp drained(s), do: @drain_base * s + @drain_growth * s * s / 2

  @doc """
  The time in milliseconds between two danger squares, `elapsed_s` seconds
  after the start. It gets shorter, so more and more danger squares come.
  """
  def danger_interval(elapsed_s), do: max(300, round(1000 - 10 * elapsed_s))

  @doc """
  A new square of the `kind` with the `id` that comes into the field at
  the time `t`, `elapsed_s` seconds after the start. It starts just out of
  a random edge and flies straight across the field: vertically from the
  top or the bottom edge, horizontally from the left or the right edge.
  All squares get faster and faster. With `perk: perk` (only
  `:invisible` now), a food square is a perk square.
  """
  def spawn(kind, id, t, elapsed_s, opts \\ []) do
    perk = if kind == :food, do: Keyword.get(opts, :perk)

    size =
      cond do
        perk -> @perk_food_size
        kind == :food -> @food_size
        true -> 23 + :rand.uniform(21)
      end

    speed = min(250 + 4 * elapsed_s, 420) * (0.8 + :rand.uniform() * 0.45)
    speed = if perk, do: speed * @perk_food_speedup, else: speed

    half = size / 2
    # Anywhere along the edge, so that no strip of the field is safe
    along = half + :rand.uniform() * (@size - size)

    # The square flies straight across the field, away from its edge
    {x, y, vx, vy} =
      case :rand.uniform(4) do
        1 -> {along, -half, 0.0, speed}
        2 -> {@size + half, along, -speed, 0.0}
        3 -> {along, @size + half, 0.0, -speed}
        4 -> {-half, along, speed, 0.0}
      end

    exit_s = min(exit_time(x, vx, half), exit_time(y, vy, half))

    %{
      id: id,
      kind: kind,
      size: size,
      x: x,
      y: y,
      vx: vx,
      vy: vy,
      t: t,
      until: t + round(exit_s * 1000),
      perk: perk
    }
  end

  # The seconds until the square is out of the field on one axis. A square
  # that does not move on the axis never goes out on it.
  defp exit_time(_p, v, _half) when v == 0, do: :infinity
  defp exit_time(p, v, half) when v > 0, do: (@size + half - p) / v
  defp exit_time(p, v, half), do: (-half - p) / v
end
