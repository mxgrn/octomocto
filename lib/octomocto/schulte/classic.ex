defmodule Octomocto.Schulte.Classic do
  @moduledoc """
  The classic Schulte board: a fixed drawing with 90 shapes, traced from a
  printed puzzle. The shapes and their colors never change, but the game
  puts the numbers into them in a random order.

  The regions have the same format as in `Octomocto.Schulte.Layout`. The
  list order is the drawing order: some shapes are drawn on top of others
  (for example, the half ellipses on top of the stripes), so a region can
  be larger than the part that is visible.

  The coordinates below are pixels in the traced picture, where the board
  starts at `{82, 3}`. The helpers move them to the board origin. The
  comment on each region is its number in the picture.
  """

  @ox 82
  @oy 3

  @cream "#fbf5e1"
  @teal "#9dedc4"
  @pink "#ff9c98"
  @orange "#ffd06c"

  def size, do: {1116, 834}

  @doc """
  Returns the empty box in the top right corner as `[x, y, w, h]`. The game
  shows the time and the next number in it.
  """
  def info_box, do: [913 - @ox, 3 - @oy, 1187 - 913, 77 - 3]

  @doc "Returns the 90 regions in the drawing order."
  def regions do
    left_fan = fan({222, 320}, {211, 320}, 134)
    right_fan = fan({1048, 265}, {1050, 274}, 137)

    [
      # Top left: a pill, stripes and two half ellipses
      region(pill(92, 13, 330, 67), {195, 28, 40, 34}, @cream),
      region(rect(82, 77, 345, 135), {193, 90, 40, 35}, @cream),
      region(rect(82, 135, 345, 199), {195, 152, 40, 35}, @cream),
      region(rect(82, 199, 345, 254), {195, 208, 40, 37}, @pink),
      region(rect(82, 254, 345, 320), {195, 268, 40, 37}, @teal),
      region(arc_shape({82, 77}, {82, 320}, 73, 121.5, 1), {103, 158, 20, 87}, @orange),
      region(arc_shape({345, 77}, {345, 320}, 80, 121.5, 0), {307, 158, 22, 88}, @cream),

      # Left: the regions around the half disk with wedges
      region(rect(82, 320, 179, 470), {95, 433, 27, 23}, @teal),
      region(rect(82, 470, 179, 574), {100, 485, 30, 28}, @cream),
      region(rect(179, 420, 242, 574), {192, 477, 32, 27}, @cream),
      region(
        poly([{242, 320}, {345, 320}, {345, 418}, {419, 418}, {419, 462}, {242, 462}]),
        {308, 435, 25, 23},
        @cream
      ),
      region(
        poly([{242, 462}, {380, 462}, {350, 502}, {292, 540}, {242, 560}]),
        {267, 483, 32, 27},
        @cream
      ),
      region(
        poly([{292, 540}, {350, 502}, {380, 520}, {380, 574}, {300, 574}]),
        {323, 528, 30, 28},
        @cream
      ),
      region(left_fan.(153.4, 180), {108, 330, 32, 27}, @cream),
      region(left_fan.(120.5, 153.4), {130, 372, 27, 28}, @cream),
      region(left_fan.(90, 120.5), {180, 398, 28, 28}, @pink),
      region(left_fan.(58.1, 90), {232, 403, 32, 27}, @cream),
      region(left_fan.(32, 58.1), {277, 382, 30, 25}, @orange),
      region(left_fan.(0, 32), {295, 330, 32, 27}, @cream),
      region(arc_shape({161, 320}, {283, 320}, 61, 61, 0), {207, 335, 20, 33}, @cream),
      region(arc_shape({82, 574}, {312, 574}, 115, 56, 1), {178, 523, 37, 38}, @cream),

      # Top middle
      region(rect(345, 3, 419, 418), {355, 70, 50, 280}, @cream),
      region(rect(419, 3, 493, 152), {433, 38, 48, 83}, @cream),
      region(rect(419, 152, 493, 216), {433, 167, 40, 35}, @teal),
      region(rect(419, 216, 493, 310), {435, 232, 35, 57}, @cream),
      region(rect(493, 3, 638, 144), {523, 45, 78, 70}, @pink),
      region(rect(493, 144, 595, 310), {507, 178, 38, 92}, @cream),
      region(rect(638, 3, 747, 172), {663, 53, 65, 58}, @cream),
      region(rect(747, 3, 833, 172), {767, 33, 47, 98}, @orange),
      region(rect(700, 172, 760, 310), {730, 200, 22, 82}, @cream),
      region(rect(760, 172, 833, 233), {775, 185, 40, 37}, @cream),
      region(rect(760, 233, 833, 310), {775, 248, 40, 45}, @teal),
      region(arc_shape({595, 141.7}, {595, 292.3}, 84, 88, 0), {567, 187, 25, 62}, @cream),
      region(arc_shape({595, 141.7}, {595, 292.3}, 84, 88, 1, 1), {612, 153, 50, 130}, @cream),
      region(ellipse(697, 220, 26, 26), {685, 205, 24, 28}, @teal),
      region(rect(833, 3, 900, 428), {843, 68, 50, 280}, @cream),

      # Middle
      region(poly([{419, 310}, {493, 310}, {460, 345}]), {447, 317, 20, 15}, @cream),
      region(poly([{419, 310}, {460, 345}, {460, 470}, {419, 470}]), {423, 352, 25, 53}, @cream),
      region(
        poly([
          {460, 345},
          {493, 310},
          {600, 310},
          {600, 438},
          {580, 472},
          {500, 472},
          {480, 508},
          {460, 508}
        ]),
        {488, 347, 93, 83},
        @cream
      ),
      region(rect(600, 310, 690, 438), {607, 335, 76, 90}, @teal),
      region(
        poly([{690, 310}, {760, 310}, {792, 347}, {792, 472}, {707, 472}, {690, 440}]),
        {727, 343, 35, 100},
        @cream
      ),
      region(poly([{760, 310}, {833, 310}, {792, 347}]), {782, 315, 20, 18}, @cream),
      region(poly([{792, 347}, {833, 310}, {833, 450}, {792, 450}]), {800, 355, 27, 50}, @cream),
      region(
        poly([
          {833, 428},
          {900, 428},
          {900, 3},
          {913, 3},
          {913, 274},
          {1011, 274},
          {1011, 453},
          {833, 453}
        ]),
        {913, 390, 55, 55},
        @cream
      ),
      region(arc_shape({417, 418}, {417, 570}, 66, 76, 0), {367, 460, 43, 67}, @orange),
      region(arc_shape({417, 418}, {417, 570}, 66, 76, 1), {425, 460, 43, 67}, @orange),

      # Houses and diamonds
      region(poly([{500, 472}, {580, 472}, {540, 548}]), {523, 485, 32, 25}, @teal),
      region(
        poly([{480, 508}, {500, 472}, {540, 548}, {540, 737}, {480, 737}]),
        {492, 560, 38, 133},
        @cream
      ),
      region(poly([{600, 438}, {650, 545}, {600, 650}, {540, 548}]), {573, 503, 43, 87}, @cream),
      region(poly([{600, 438}, {690, 438}, {650, 545}]), {630, 448, 30, 55}, @cream),
      region(poly([{690, 440}, {747, 545}, {703, 650}, {650, 545}]), {672, 503, 43, 87}, @pink),
      region(
        poly([{650, 545}, {703, 650}, {703, 737}, {600, 737}, {600, 650}]),
        {622, 612, 53, 110},
        @orange
      ),
      region(poly([{540, 548}, {600, 650}, {600, 737}, {540, 737}]), {550, 630, 33, 92}, @cream),
      region(poly([{703, 650}, {747, 545}, {747, 737}, {703, 737}]), {712, 633, 28, 88}, @cream),
      region(
        poly([{707, 472}, {788, 472}, {788, 737}, {747, 737}, {747, 545}]),
        {752, 520, 30, 200},
        @teal
      ),
      region(poly([{788, 508}, {901, 737}, {788, 737}]), {797, 608, 35, 110}, @cream),
      region(
        poly([{800, 480}, {872, 492}, {960, 530}, {960, 562}, {815, 562}, {788, 508}]),
        {867, 520, 43, 30},
        @teal
      ),
      region(
        poly([{860, 453}, {1011, 453}, {1011, 562}, {960, 530}, {872, 492}]),
        {920, 470, 53, 40},
        @cream
      ),
      region(ellipse(826, 479, 46.5, 52), {817, 445, 27, 68}, @pink),

      # Right: stripes with two half ellipses, a half disk with wedges
      region(rect(913, 77, 1187, 123), {1028, 85, 38, 30}, @teal),
      region(rect(913, 123, 1187, 170), {1028, 132, 38, 32}, @pink),
      region(rect(913, 170, 1187, 211), {1028, 175, 38, 33}, @cream),
      region(rect(913, 211, 1187, 265), {1028, 222, 38, 30}, @cream),
      region(arc_shape({913, 77}, {913, 265}, 47, 94, 1), {917, 122, 28, 96}, @teal),
      region(arc_shape({1187, 77}, {1187, 265}, 47, 94, 0), {1150, 122, 30, 98}, @pink),
      region(rect(1011, 380, 1100, 562), {1030, 427, 52, 63}, @cream),
      region(
        poly([{1100, 274}, {1187, 274}, {1187, 3}, {1198, 3}, {1198, 457}, {1100, 457}]),
        {1162, 372, 17, 77},
        @cream
      ),
      region(rect(1100, 457, 1198, 562), {1150, 468, 30, 43}, @teal),
      region(right_fan.(143, 180), {940, 280, 32, 27}, @pink),
      region(right_fan.(108.2, 143), {975, 330, 33, 35}, @cream),
      region(right_fan.(72.2, 108.2), {1032, 335, 33, 55}, @orange),
      region(right_fan.(35.8, 72.2), {1093, 328, 27, 42}, @cream),
      region(right_fan.(0, 35.8), {1127, 280, 32, 27}, @cream),
      region(arc_shape({1001, 265}, {1095, 265}, 47, 47, 0), {1030, 272, 33, 28}, @cream),
      region(arc_shape({942, 562}, {1198, 562}, 128, 62, 1), {1027, 520, 83, 30}, @cream),

      # Bottom
      region(poly([{82, 574}, {97, 574}, {194, 837}, {82, 837}]), {92, 685, 35, 108}, @teal),
      region(poly([{97, 574}, {296, 574}, {194, 837}]), {158, 588, 77, 125}, @cream),
      region(
        poly([{296, 574}, {355, 735}, {355, 837}, {194, 837}]),
        {255, 683, 67, 122},
        @orange
      ),
      region(poly([{296, 574}, {480, 574}, {355, 737}]), {350, 600, 40, 73}, @cream),
      region(poly([{355, 737}, {480, 574}, {480, 737}]), {423, 657, 37, 60}, @teal),
      region(rect(355, 737, 469, 837), {387, 760, 55, 60}, @cream),
      region(rect(469, 737, 797, 837), {552, 755, 150, 65}, @cream),
      region(poly([{797, 737}, {901, 737}, {849, 787}]), {833, 747, 27, 23}, @teal),
      region(poly([{901, 737}, {901, 837}, {849, 787}]), {867, 775, 25, 25}, @teal),
      region(poly([{797, 837}, {901, 837}, {849, 787}]), {837, 805, 23, 25}, @teal),
      region(poly([{797, 737}, {797, 837}, {849, 787}]), {806, 776, 18, 22}, @teal),
      region(poly([{815, 562}, {993, 562}, {901, 737}]), {870, 585, 62, 80}, @cream),
      region(poly([{993, 562}, {993, 837}, {901, 837}, {901, 737}]), {930, 702, 43, 112}, @cream),
      region(poly([{993, 562}, {1198, 837}, {993, 837}]), {1020, 670, 48, 155}, @cream),
      region(poly([{993, 562}, {1198, 562}, {1198, 837}]), {1103, 590, 53, 82}, @orange)
    ]
  end

  defp region(d, {x, y, w, h}, color) do
    %{d: d, label: [x - @ox, y - @oy, w, h], color: color}
  end

  defp rect(x1, y1, x2, y2), do: poly([{x1, y1}, {x2, y1}, {x2, y2}, {x1, y2}])

  defp poly([first | rest]) do
    "M#{pt(first)}" <> Enum.map_join(rest, &"L#{pt(&1)}") <> "Z"
  end

  defp pill(x1, y1, x2, y2) do
    r = (y2 - y1) / 2

    "M#{pt({x1 + r, y1})}H#{f(x2 - r - @ox)}A#{f(r)} #{f(r)} 0 0 1 #{pt({x2 - r, y2})}" <>
      "H#{f(x1 + r - @ox)}A#{f(r)} #{f(r)} 0 0 1 #{pt({x1 + r, y1})}Z"
  end

  defp ellipse(cx, cy, rx, ry) do
    arc = "A#{f(rx)} #{f(ry)} 0 0 1 "
    "M#{pt({cx - rx, cy})}#{arc}#{pt({cx + rx, cy})}#{arc}#{pt({cx - rx, cy})}Z"
  end

  # An elliptic arc from one point to the other, closed with a straight
  # line. `sweep` 1 goes clockwise on the screen.
  defp arc_shape(from, to, rx, ry, sweep, large \\ 0) do
    "M#{pt(from)}A#{f(rx)} #{f(ry)} 0 #{large} #{sweep} #{pt(to)}Z"
  end

  # Wedges of a half disk. The cut lines start at the center `c` of the
  # small half disk and stop on the circle around `o`. The angles are in
  # degrees, clockwise from the right.
  defp fan(c, o, r) do
    fn from, to ->
      "M#{pt(c)}L#{pt(on_circle(c, o, r, from))}A#{f(r)} #{f(r)} 0 0 1 " <>
        "#{pt(on_circle(c, o, r, to))}Z"
    end
  end

  defp on_circle({cx, cy}, {ox, oy}, r, degrees) do
    a = degrees * :math.pi() / 180
    {dx, dy} = {:math.cos(a), :math.sin(a)}
    b = dx * (cx - ox) + dy * (cy - oy)
    k = (cx - ox) ** 2 + (cy - oy) ** 2 - r ** 2
    t = -b + :math.sqrt(b * b - k)
    {cx + t * dx, cy + t * dy}
  end

  defp pt({x, y}), do: "#{f(x - @ox)} #{f(y - @oy)}"

  defp f(v), do: :erlang.float_to_binary(v / 1, decimals: 1)
end
