defmodule OctomoctoWeb.ResultsPreview do
  @moduledoc """
  Made-up results for the "Your results" list of a guest. The list shows
  them blurred, under a call to sign in (see `score_list/1`), so that the
  guest sees what a signed-in player gets: a line that goes up with some
  noise, near the values of the best results of the same settings.
  """
  import Phoenix.Component, only: [assign: 3]

  @size 30
  @latest_size 5
  @default_time_ms 60_000
  @default_score 20

  @doc """
  Assigns `:results_preview`: made-up results for a guest, nil for a user.
  The values come from the `:best_results` of the page, so call it after
  `OctomoctoWeb.BestResults.assign_best/3`. `field` is the field of the
  results to show. The options are the options of `build/2`.

  The preview has a `:key` that changes with the settings: the page keeps
  the first random preview until the settings change (see `score_list/1`).
  """
  def assign_preview(socket, field, opts \\ [])

  def assign_preview(%{assigns: %{current_scope: %{user: _}}} = socket, _field, _opts),
    do: assign(socket, :results_preview, nil)

  def assign_preview(socket, field, opts) do
    preview =
      socket.assigns.best_results
      |> Enum.map(&Map.fetch!(&1, field))
      |> build(opts)
      |> Map.put(:key, :erlang.phash2(socket.assigns.best_query))

    assign(socket, :results_preview, preview)
  end

  @doc """
  Gives random results near the median of `values`: `:trend` (30 points
  that go up with a lot of noise, the oldest first, as
  `Octomocto.ResultQueries.trend/2`), `:latest` (the 5 newest points with
  a date and a rounded value, the newest first) and `:best`.

  Options:

    * `:lower_better` - true for times
    * `:max` - the highest possible value
  """
  def build(values, opts \\ []) do
    lower_better = Keyword.get(opts, :lower_better, false)
    max = Keyword.get(opts, :max)
    # Below the max, so that the line does not stay flat at the max
    base = values |> base(lower_better) |> at_most(max && max * 0.8)

    # The line has values with decimals: rounded values of small scores
    # make flat steps
    trend =
      for id <- 1..@size do
        progress = (id - 1) / (@size - 1)
        factor = if lower_better, do: 1.9 - 0.8 * progress, else: 0.45 + 0.5 * progress
        noise = 1 + (:rand.uniform() - 0.5) * 0.5
        %{id: id, value: (base * factor * noise) |> at_most(max)}
      end

    best =
      if lower_better,
        do: Enum.min_by(trend, & &1.value),
        else: Enum.max_by(trend, & &1.value)

    latest =
      trend
      |> Enum.take(-@latest_size)
      |> Enum.reverse()
      |> Enum.zip(dates(@latest_size))
      |> Enum.map(fn {point, date} ->
        %{point | value: point.value |> round() |> max(1)} |> Map.put(:inserted_at, date)
      end)

    %{trend: trend, latest: latest, best: best}
  end

  defp base([], true), do: @default_time_ms
  defp base([], false), do: @default_score

  defp base(values, _lower_better) do
    values |> Enum.sort() |> Enum.at(div(length(values), 2))
  end

  defp at_most(value, nil), do: value
  defp at_most(value, max), do: min(value, max)

  # Today first, then some days back, 0 to 2 days apart
  defp dates(count) do
    today = DateTime.utc_now()

    Enum.scan(1..count, today, fn index, date ->
      if index == 1, do: date, else: DateTime.add(date, -Enum.random(0..2), :day)
    end)
  end
end
