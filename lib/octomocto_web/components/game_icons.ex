defmodule OctomoctoWeb.GameIcons do
  @moduledoc """
  The images of the games: flat shapes on a 48 x 48 view box, without a
  background. The page puts them on a colored tile.
  """
  use Phoenix.Component

  attr :game, :string, required: true, doc: "the id of the game, for example \"trains\""
  attr :class, :any, default: nil

  def game_icon(%{game: "trains"} = assigns) do
    ~H"""
    <svg viewBox="0 0 48 48" class={@class} aria-hidden="true">
      <circle cx="13" cy="9" r="3.5" fill="#CBD5E1" />
      <circle cx="19" cy="5.5" r="2.5" fill="#E2E8F0" />
      <rect x="10" y="14" width="6" height="10" rx="1.5" fill="#171532" />
      <rect x="6" y="22" width="22" height="13" rx="3" fill="#F26A1B" />
      <rect x="26" y="15" width="15" height="20" rx="2" fill="#4B4BE8" />
      <rect x="29" y="18" width="9" height="6" rx="1.5" fill="#fff" />
      <rect x="24" y="12" width="19" height="4" rx="2" fill="#171532" />
      <rect x="3" y="29" width="4" height="5" rx="1" fill="#171532" />
      <rect x="3" y="41" width="42" height="2.5" rx="1.25" fill="#171532" opacity="0.35" />
      <circle :for={x <- [12, 22, 34]} cx={x} cy="36" r="4.5" fill="#171532" />
      <circle :for={x <- [12, 22, 34]} cx={x} cy="36" r="1.5" fill="#fff" />
    </svg>
    """
  end

  def game_icon(%{game: "astronaut"} = assigns) do
    ~H"""
    <svg viewBox="0 0 48 48" class={@class} aria-hidden="true">
      <circle :for={{x, y} <- [{6, 8}, {42, 40}, {9, 41}, {44, 22}]} cx={x} cy={y} r="1" fill="#fff" />
      <g transform="rotate(20 21 27)">
        <path d="M21 13v28M7 27h28" stroke="#8C8CFF" stroke-width="2" />
        <circle cx="21" cy="27" r="13" fill="none" stroke="#8C8CFF" stroke-width="4" />
        <rect
          :for={{x, y} <- [{21, 14}, {21, 40}, {8, 27}, {34, 27}]}
          x={x - 4}
          y={y - 4}
          width="8"
          height="8"
          rx="2"
          fill="#C7C7FF"
        />
        <circle cx="21" cy="27" r="4" fill="#C7C7FF" />
      </g>
      <g transform="translate(2 -1) rotate(45 38 10)">
        <path d="M35 17h6l-3 5z" fill="#FFB020" />
        <rect x="34" y="3" width="8" height="14" rx="4" fill="#F26A1B" />
        <circle cx="38" cy="8.5" r="2" fill="#fff" />
      </g>
    </svg>
    """
  end

  def game_icon(%{game: "memory"} = assigns) do
    ~H"""
    <svg viewBox="0 0 48 48" class={@class} aria-hidden="true">
      <g :for={{x, angle} <- [{5, -10}, {23, 10}]} transform={"rotate(#{angle} #{x + 10} 26)"}>
        <rect
          x={x}
          y="12"
          width="20"
          height="28"
          rx="3.5"
          fill="#fff"
          stroke="#0EA5E9"
          stroke-opacity="0.35"
          stroke-width="1.5"
        />
        <path
          transform={"translate(#{x + 10} 26)"}
          d="M0-7.5l2.2 4.6 5 .6-3.7 3.5.9 5L0 3.8l-4.4 2.4.9-5-3.7-3.5 5-.6z"
          fill="#F26A1B"
        />
      </g>
    </svg>
    """
  end

  def game_icon(%{game: "set"} = assigns) do
    ~H"""
    <svg viewBox="0 0 48 48" class={@class} aria-hidden="true">
      <rect
        :for={{x, y} <- [{2, 14}, {17.5, 10}, {33, 14}]}
        x={x}
        y={y}
        width="13"
        height="22"
        rx="2.5"
        fill="#fff"
        stroke="#7C3AED"
        stroke-opacity="0.3"
        stroke-width="1.5"
      />
      <path d="M8.5 19l3.5 6-3.5 6-3.5-6z" fill="#7C3AED" />
      <rect x="21.25" y="15" width="5.5" height="12" rx="2.75" fill="#16A34A" />
      <path
        d="M37.5 20c2-2 4.5-.5 3.5 2-.8 2-.2 3 .5 4 1.4 2.2-1.5 5-3.8 3.2-1-.8-.2-2.2-.7-3.7-.6-1.8-1.6-3.4.5-5.5z"
        fill="#DC2626"
      />
    </svg>
    """
  end

  # A ring of 4 colored pads around a hub. Each pad is a part of the stroke
  # of one circle: the dash is a pad, and the rest of the circle is the gap.
  def game_icon(%{game: "echo"} = assigns) do
    ~H"""
    <svg viewBox="0 0 48 48" class={@class} aria-hidden="true">
      <circle
        :for={
          {color, index} <-
            Enum.with_index(["#FF8A3D", "#3D8BFF", "#FFD23F", "#A6E04A"])
        }
        cx="24"
        cy="24"
        r="15"
        fill="none"
        stroke={color}
        stroke-width="10"
        stroke-dasharray="21.06 73.19"
        transform={"rotate(#{index * 90 - 130} 24 24)"}
        opacity={if index == 0, do: "1", else: "0.75"}
      />
      <circle cx="24" cy="24" r="7.5" fill="#171532" />
    </svg>
    """
  end

  # Two mahjong tiles, one on the other. The front tile has one blue dot
  # of the dots suit, and the back tile shows the bamboo suit.
  def game_icon(%{game: "mahjong"} = assigns) do
    ~H"""
    <svg viewBox="0 0 48 48" class={@class} aria-hidden="true">
      <rect x="7" y="7" width="22" height="29" rx="3.5" fill="#C9C3B3" />
      <rect x="5" y="4" width="22" height="29" rx="3.5" fill="#FBF8F1" stroke="#D8D2C2" />
      <rect :for={x <- [11, 18]} x={x} y="9" width="3" height="19" rx="1.5" fill="#1E7D3A" />
      <rect x="21" y="18" width="22" height="29" rx="3.5" fill="#C9C3B3" />
      <rect x="19" y="15" width="22" height="29" rx="3.5" fill="#FBF8F1" stroke="#D8D2C2" />
      <circle cx="30" cy="29.5" r="7.5" fill="none" stroke="#1F3A93" stroke-width="2.5" />
      <circle cx="30" cy="29.5" r="3" fill="#C0392B" />
    </svg>
    """
  end

  # Two round cards, one on the other. Each card has 3 symbols, and the
  # star is on both cards.
  def game_icon(%{game: "overlap"} = assigns) do
    ~H"""
    <svg viewBox="0 0 48 48" class={@class} aria-hidden="true">
      <circle
        cx="17"
        cy="17"
        r="14.5"
        fill="#fff"
        stroke="#EC4899"
        stroke-opacity="0.35"
        stroke-width="1.5"
      />
      <path
        d="M11.5 11.4 L12.7 14.4 L15.9 14.6 L13.4 16.6 L14.2 19.7 L11.5 18.0 L8.8 19.7 L9.6 16.6 L7.1 14.6 L10.3 14.4Z"
        fill="#F59E0B"
      />
      <circle cx="21.5" cy="10.5" r="3.2" fill="#DC2626" />
      <rect x="17" y="20" width="6" height="6" rx="1.2" fill="#4B4BE8" transform="rotate(20 20 23)" />
      <circle
        cx="31"
        cy="31"
        r="14.5"
        fill="#fff"
        stroke="#EC4899"
        stroke-opacity="0.35"
        stroke-width="1.5"
      />
      <path
        d="M34.5 29.4 L35.7 32.4 L38.9 32.6 L36.4 34.6 L37.2 37.7 L34.5 36.0 L31.8 37.7 L32.6 34.6 L30.1 32.6 L33.3 32.4Z"
        fill="#F59E0B"
      />
      <path d="M26.5 22.5c2.4 2.6 3 4.2 3 5.4a3 3 0 0 1-6 0c0-1.2.6-2.8 3-5.4z" fill="#0EA5E9" />
      <circle cx="26" cy="37.5" r="3" fill="#16A34A" />
    </svg>
    """
  end

  # Two cards with the same shape, the new card on the old one, and a check
  def game_icon(%{game: "snap"} = assigns) do
    ~H"""
    <svg viewBox="0 0 48 48" class={@class} aria-hidden="true">
      <g :for={{x, angle} <- [{6, -12}, {19, 6}]} transform={"rotate(#{angle} #{x + 11} 25)"}>
        <rect
          x={x}
          y="10"
          width="22"
          height="30"
          rx="3.5"
          fill="#fff"
          stroke="#14B8A6"
          stroke-opacity="0.4"
          stroke-width="1.5"
        />
        <path transform={"translate(#{x + 11} 25)"} d="M0-6.5 7 5.5h-14z" fill="#1A9FCB" />
      </g>
      <circle cx="38" cy="10" r="7" fill="#16A34A" />
      <path
        d="m34.8 10.2 2.2 2.2 4.2-4.6"
        fill="none"
        stroke="#fff"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  # A circle with its energy ring, near a food square that it goes to and
  # a red square that it keeps away from
  def game_icon(%{game: "graze"} = assigns) do
    ~H"""
    <svg viewBox="0 0 48 48" class={@class} aria-hidden="true">
      <rect x="31" y="6" width="10" height="10" rx="1.5" fill="#EF4444" />
      <rect x="32" y="31" width="9" height="9" rx="1.5" fill="#374151" />
      <circle
        cx="18"
        cy="26"
        r="12"
        fill="none"
        stroke="#1A9FCB"
        stroke-opacity="0.25"
        stroke-width="3"
      />
      <circle
        cx="18"
        cy="26"
        r="12"
        fill="none"
        stroke="#1A9FCB"
        stroke-width="3"
        stroke-linecap="round"
        stroke-dasharray="52 76"
        transform="rotate(-90 18 26)"
      />
      <circle cx="18" cy="26" r="8" fill="#374151" />
    </svg>
    """
  end

  # A grid of tiles, some lit, and one with the glow that stays after it
  # went out
  def game_icon(%{game: "afterglow"} = assigns) do
    ~H"""
    <svg viewBox="0 0 48 48" class={@class} aria-hidden="true">
      <rect
        :for={{x, y} <- for(y <- 0..2, x <- 0..2, do: {x, y})}
        x={6 + x * 13}
        y={6 + y * 13}
        width="10"
        height="10"
        rx="2.5"
        fill={
          cond do
            {x, y} in [{0, 0}, {2, 1}, {1, 2}] -> "#1A9FCB"
            {x, y} == {1, 1} -> "#D946EF"
            true -> "#fff"
          end
        }
        fill-opacity={if {x, y} == {1, 1}, do: "0.35", else: "1"}
        stroke={if {x, y} in [{0, 0}, {2, 1}, {1, 2}, {1, 1}], do: "none", else: "#D946EF"}
        stroke-opacity="0.35"
        stroke-width="1.2"
      />
      <rect
        x="17"
        y="17"
        width="14"
        height="14"
        rx="4"
        fill="none"
        stroke="#D946EF"
        stroke-opacity="0.5"
        stroke-width="1.2"
      />
    </svg>
    """
  end

  def game_icon(%{game: "sudoku"} = assigns) do
    ~H"""
    <svg viewBox="0 0 48 48" class={@class} aria-hidden="true">
      <rect x="4" y="4" width="40" height="40" rx="6" fill="#fff" />
      <rect x="17.33" y="17.33" width="13.33" height="13.33" fill="#E11D48" />
      <path
        d="M17.33 4v40M30.67 4v40M4 17.33h40M4 30.67h40"
        stroke="#E11D48"
        stroke-opacity="0.25"
        stroke-width="1.5"
      />
      <text
        :for={
          {x, y, digit, fill} <- [
            {10.67, 14.2, "5", "#171532"},
            {37.33, 14.2, "3", "#171532"},
            {24, 27.5, "9", "#fff"},
            {10.67, 40.8, "1", "#171532"},
            {37.33, 40.8, "7", "#171532"}
          ]
        }
        x={x}
        y={y}
        text-anchor="middle"
        font-size="10"
        font-weight="700"
        fill={fill}
      >
        {digit}
      </text>
    </svg>
    """
  end

  # A small board as in the game: shapes of different forms and colors,
  # with numbers of different sizes. The colors are those of the board.
  # The shapes in the corners have the same round corners as the board, so
  # the icon needs no clip path: an id in the SVG would not be unique when
  # a page shows the icon more than once.
  def game_icon(%{game: "nimble-mosaic"} = assigns) do
    ~H"""
    <svg viewBox="0 0 48 48" class={@class} aria-hidden="true">
      <g stroke="#474d50" stroke-width="1.2" stroke-linejoin="round">
        <rect x="4" y="4" width="40" height="40" rx="6" fill="#fbf5e1" />
        <path d="M24 4H38A6 6 0 0 1 44 10V16H24Z" fill="#9dedc4" />
        <path d="M24 16H44V30H34L24 22Z" fill="#ff9c98" />
        <path d="M4 20A9 9 0 0 1 4 38Z" fill="#ffd06c" />
        <path d="M30 44L44 30V38A6 6 0 0 1 38 44Z" fill="#9dedc4" />
        <path d="M24 4V22M4 18H24M24 22L18 44" fill="none" />
      </g>
      <text
        :for={
          {x, y, digit, size} <- [
            {14, 15.5, "7", 11},
            {34, 13.5, "2", 8},
            {35, 27, "1", 9},
            {8.5, 31.5, "3", 7},
            {18.5, 31, "5", 6.5},
            {27.5, 39.5, "9", 8},
            {40, 41.5, "4", 5.5}
          ]
        }
        x={x}
        y={y}
        text-anchor="middle"
        font-size={size}
        font-weight="700"
        fill="#474d50"
      >
        {digit}
      </text>
      <rect x="4" y="4" width="40" height="40" rx="6" fill="none" stroke="#474d50" stroke-width="1.5" />
    </svg>
    """
  end

  # The classic Schulte table, as on its board: white cells with thin gray
  # lines, a dark border and the center dot. The dot is paler and larger
  # than on the board, so the middle number stays clear at a small size.
  def game_icon(%{game: "schulte"} = assigns) do
    ~H"""
    <svg viewBox="0 0 48 48" class={@class} aria-hidden="true">
      <rect x="4" y="4" width="40" height="40" rx="6" fill="#fff" />
      <path
        d="M17.33 4v40M30.67 4v40M4 17.33h40M4 30.67h40"
        stroke="#9aa5b1"
        stroke-width="1.2"
      />
      <circle cx="24" cy="24" r="5.2" fill="#1A9FCB" fill-opacity="0.25" />
      <text
        :for={{digit, x, y} <- schulte_cells()}
        x={x}
        y={y}
        text-anchor="middle"
        font-size="9.5"
        font-weight="700"
        fill="#1f2933"
      >
        {digit}
      </text>
      <rect x="4" y="4" width="40" height="40" rx="6" fill="none" stroke="#474d50" stroke-width="1.5" />
    </svg>
    """
  end

  # The digits of a 3 x 3 grid, with the positions of their text
  defp schulte_cells do
    for {digit, i} <- Enum.with_index([7, 2, 5, 4, 9, 1, 6, 3, 8]) do
      {digit, 10.67 + rem(i, 3) * 13.33, 13.9 + div(i, 3) * 13.33}
    end
  end
end
