defmodule Octomocto.Schulte.Layout do
  @moduledoc """
  Makes a random Schulte board in the style of a hand-drawn puzzle: the
  board is cut again and again into rectangles, and some rectangles are cut
  into triangles or get a round shape (an ellipse or an arch) inside.

  Each region has an SVG path `d`, a `label` box `[x, y, w, h]` where the
  client stretches the number to fill the box, and a fill `color`. A path
  can have a hole for the round shape inside it, so the client draws it with
  `fill-rule="evenodd"`.
  """

  @width 1600
  @height 900
  @min_side 70

  @colors ["#fbf5e1", "#9dedc4", "#ff9c98", "#ffd06c"]
  @flat_weights [60, 15, 12, 13]
  @round_weights [30, 25, 20, 25]

  def size, do: {@width, @height}

  @doc "Returns `count` regions that together fill the board."
  def generate(count) do
    avg_area = @width * @height / count

    case cut([{0, 0, @width, @height}], [], count, avg_area) do
      {:ok, regions} -> Enum.map(regions, &finish/1)
      :stuck -> generate(count)
    end
  end

  # `open` has the rectangles that can be cut more, and `done` has the
  # regions that stay as they are.
  defp cut(open, done, count, avg_area) do
    room = count - length(open) - length(done)

    cond do
      room == 0 ->
        {:ok, done ++ Enum.map(open, &rect_region/1)}

      open == [] ->
        :stuck

      true ->
        rect = weighted(Enum.map(open, fn {_, _, w, h} = r -> {r, :math.pow(w * h, 1.5)} end))
        open = List.delete(open, rect)

        case ops(rect, room, avg_area) do
          [] ->
            cut(open, [rect_region(rect) | done], count, avg_area)

          ops ->
            {new_open, new_done} = apply_op(weighted(ops), rect)
            cut(new_open ++ open, new_done ++ done, count, avg_area)
        end
    end
  end

  defp ops({_x, _y, w, h}, room, avg_area) do
    short = min(w, h)
    long = max(w, h)
    split? = long >= 2 * @min_side

    if w * h > 3 * avg_area do
      if split?, do: [{:split, 1}], else: []
    else
      [
        split? && {:split, 50},
        (short >= 90 and long / short <= 2.5) && {:diagonal, 12},
        (room >= 3 and short >= 170) && {:cross, 5},
        (short >= 90 and long / short >= 1.7) && {:circle, 20},
        (h >= 110 and w / h >= 1.3) && {:arch, 12}
      ]
      |> Enum.filter(& &1)
    end
  end

  defp apply_op(:split, {x, y, w, h}) do
    axis =
      cond do
        w < 2 * @min_side -> :y
        h < 2 * @min_side -> :x
        :rand.uniform() < 0.75 -> if(w >= h, do: :x, else: :y)
        true -> if(w >= h, do: :y, else: :x)
      end

    len = if axis == :x, do: w, else: h
    at = (len * between(0.25, 0.75)) |> round() |> max(@min_side) |> min(len - @min_side)

    case axis do
      :x -> {[{x, y, at, h}, {x + at, y, w - at, h}], []}
      :y -> {[{x, y, w, at}, {x, y + at, w, h - at}], []}
    end
  end

  # Two right triangles. Each label is in the corner with the right angle.
  defp apply_op(:diagonal, {x, y, w, h}) do
    {x2, y2} = {x + w, y + h}

    if :rand.uniform() < 0.5 do
      {[],
       [
         poly([{x, y}, {x, y2}, {x2, y2}], {x, y + h / 2, w / 2, h / 2}),
         poly([{x, y}, {x2, y}, {x2, y2}], {x + w / 2, y, w / 2, h / 2})
       ]}
    else
      {[],
       [
         poly([{x, y}, {x2, y}, {x, y2}], {x, y, w / 2, h / 2}),
         poly([{x2, y}, {x2, y2}, {x, y2}], {x + w / 2, y + h / 2, w / 2, h / 2})
       ]}
    end
  end

  # Four triangles that meet in the center.
  defp apply_op(:cross, {x, y, w, h}) do
    {x2, y2} = {x + w, y + h}
    c = {x + w / 2, y + h / 2}

    {[],
     [
       poly([{x, y}, {x2, y}, c], {x + w / 4, y, w / 2, h / 4}),
       poly([{x2, y}, {x2, y2}, c], {x + 3 * w / 4, y + h / 4, w / 4, h / 2}),
       poly([{x, y2}, {x2, y2}, c], {x + w / 4, y + 3 * h / 4, w / 2, h / 4}),
       poly([{x, y}, {x, y2}, c], {x, y + h / 4, w / 4, h / 2})
     ]}
  end

  # An ellipse at one end of a long rectangle. The rest of the rectangle has
  # its label at the other end.
  defp apply_op(:circle, {x, y, w, h}) do
    at_start? = :rand.uniform() < 0.5

    {ellipse_zone, rest} =
      if w >= h do
        e = min(h * between(1.0, 1.3), w - @min_side)

        if at_start?,
          do: {{x, y, e, h}, {x + e, y, w - e, h}},
          else: {{x + w - e, y, e, h}, {x, y, w - e, h}}
      else
        e = min(w * between(1.0, 1.3), h - @min_side)

        if at_start?,
          do: {{x, y, w, e}, {x, y + e, w, h - e}},
          else: {{x, y + h - e, w, e}, {x, y, w, h - e}}
      end

    {ex, ey, ew, eh} = ellipse_zone
    {cx, cy, rx, ry} = {ex + ew / 2, ey + eh / 2, 0.44 * ew, 0.44 * eh}
    ellipse = ellipse_path(cx, cy, rx, ry)
    k = :math.sqrt(2)

    {[],
     [
       %{d: rect_path({x, y, w, h}) <> ellipse, label: rest, round: false},
       %{d: ellipse, label: {cx - rx / k, cy - ry / k, rx * k, ry * k}, round: true}
     ]}
  end

  # A half ellipse on the bottom or the top edge. The rest of the rectangle
  # has its label in the strip on the other side.
  defp apply_op(:arch, {x, y, w, h}) do
    cx = x + w / 2
    rx = w * between(0.42, 0.5)
    ry = h * between(0.55, 0.68)
    k = :math.sqrt(2)

    {arch, arch_label, rest} =
      if :rand.uniform() < 0.6 do
        {"M#{f(cx - rx)} #{f(y + h)}A#{f(rx)} #{f(ry)} 0 0 1 #{f(cx + rx)} #{f(y + h)}Z",
         {cx - rx / k, y + h - ry / k, rx * k, ry / k}, {x, y, w, h - ry}}
      else
        {"M#{f(cx - rx)} #{f(y)}A#{f(rx)} #{f(ry)} 0 0 0 #{f(cx + rx)} #{f(y)}Z",
         {cx - rx / k, y, rx * k, ry / k}, {x, y + ry, w, h - ry}}
      end

    {[],
     [
       %{d: rect_path({x, y, w, h}) <> arch, label: rest, round: false},
       %{d: arch, label: arch_label, round: true}
     ]}
  end

  defp rect_region(rect), do: %{d: rect_path(rect), label: rect, round: false}

  defp poly([{x, y} | rest], label) do
    d = "M#{f(x)} #{f(y)}" <> Enum.map_join(rest, fn {px, py} -> "L#{f(px)} #{f(py)}" end) <> "Z"
    %{d: d, label: label, round: false}
  end

  defp rect_path({x, y, w, h}) do
    "M#{f(x)} #{f(y)}H#{f(x + w)}V#{f(y + h)}H#{f(x)}Z"
  end

  defp ellipse_path(cx, cy, rx, ry) do
    "M#{f(cx - rx)} #{f(cy)}A#{f(rx)} #{f(ry)} 0 1 0 #{f(cx + rx)} #{f(cy)}" <>
      "A#{f(rx)} #{f(ry)} 0 1 0 #{f(cx - rx)} #{f(cy)}Z"
  end

  # Give each number a random size inside its box, and pick a color.
  defp finish(%{d: d, label: {x, y, w, h}, round: round?}) do
    {lw, lh} = {w * between(0.6, 0.88), h * between(0.6, 0.88)}
    weights = if round?, do: @round_weights, else: @flat_weights

    %{
      d: d,
      label: Enum.map([x + (w - lw) / 2, y + (h - lh) / 2, lw, lh], &Float.round(&1 / 1, 1)),
      color: weighted(Enum.zip(@colors, weights))
    }
  end

  defp weighted(items) do
    total = items |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    pick = :rand.uniform() * total

    Enum.reduce_while(items, pick, fn {item, weight}, left ->
      if left <= weight, do: {:halt, item}, else: {:cont, left - weight}
    end)
  end

  defp between(a, b), do: a + :rand.uniform() * (b - a)

  defp f(v), do: :erlang.float_to_binary(v / 1, decimals: 1)
end
