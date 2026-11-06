defmodule OctomoctoWeb.PlayerLive do
  @moduledoc """
  The public profile page of a user or a guest, at `/players/:public_id`
  (see `Octomocto.Players`): the date of the first visit that the site
  saved, the games played in all, the games played in each game in the
  last 30 days (with a graph of the games per day), the time of the last
  finished game ("Online now" for a user that is online), and the number
  of friends of a user. Anyone can open it. A signed-in user can follow
  another user here (see `Octomocto.Friends`).
  """
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.SiteNotifications, nil}

  alias Octomocto.{Friends, Players}
  alias OctomoctoWeb.{GameIcons, HomeLive, NotFoundError}

  # The number of days of the activity graphs (see `Octomocto.Players`)
  @days 30

  # The size of the view box of a sparkline
  @width 100
  @height 24

  def mount(%{"public_id" => public_id}, _session, socket) do
    profile = Players.profile(public_id) || raise NotFoundError

    # Only the games played in the last 30 days, with their counts in these days
    games =
      HomeLive.games()
      |> Enum.filter(&Map.has_key?(profile.activity, &1.id))
      |> Enum.map(fn game ->
        days = Map.fetch!(profile.activity, game.id)
        game |> Map.put(:days, days) |> Map.put(:count, Enum.sum(days))
      end)
      |> Enum.sort_by(& &1.count, :desc)

    {:ok,
     socket
     |> assign(
       page_title: profile.name,
       noindex: true,
       profile: profile,
       public_id: public_id,
       games: games,
       days: @days,
       # All sparklines have the same scale, as the bars of the counts
       most_in_day: games |> Enum.flat_map(& &1.days) |> Enum.max(fn -> 0 end),
       total: profile.games |> Map.values() |> Enum.sum()
     )
     |> assign_follow()}
  end

  def handle_event("follow", _params, socket) do
    Friends.follow(viewer_id(socket), socket.assigns.profile.user_id)
    {:noreply, reload(socket)}
  end

  def handle_event("unfollow", _params, socket) do
    Friends.unfollow(viewer_id(socket), socket.assigns.profile.user_id)
    {:noreply, reload(socket)}
  end

  # A follow can make or end a friendship, so the count of friends changes
  defp reload(socket) do
    socket
    |> assign(:profile, Players.profile(socket.assigns.public_id))
    |> assign_follow()
  end

  # `follow` is nil when there is no Follow button: for a guest who looks,
  # for the profile of a guest, and for the user's own profile. Else it
  # tells if the user follows the player, and if they are friends.
  defp assign_follow(socket) do
    viewer_id = viewer_id(socket)
    player_id = socket.assigns.profile.user_id

    follow =
      if viewer_id && player_id && viewer_id != player_id do
        following = Friends.following?(viewer_id, player_id)
        %{following: following, friends: following && Friends.following?(player_id, viewer_id)}
      end

    assign(socket, :follow, follow)
  end

  defp viewer_id(socket) do
    case socket.assigns.current_scope do
      %{user: %{id: id}} -> id
      _ -> nil
    end
  end

  @doc """
  Renders a small line graph of the games per day, oldest first. The top of
  the graph is `most`, the most games of one game in a day.
  """
  attr :id, :string, required: true
  attr :days, :list, required: true, doc: "the number of games in each day"
  attr :most, :integer, required: true

  def sparkline(assigns) do
    count = length(assigns.days)
    most = max(assigns.most, 1)

    points =
      assigns.days
      |> Enum.with_index()
      |> Enum.map(fn {n, i} ->
        x = i * @width / max(count - 1, 1)
        # Keep the line inside the box, also at 0 and at the top
        y = @height - 1 - n / most * (@height - 2)
        "#{Float.round(x * 1.0, 2)},#{Float.round(y * 1.0, 2)}"
      end)

    total = Enum.sum(assigns.days)

    assigns =
      assign(assigns,
        line: "M" <> Enum.join(points, " L"),
        area: "M0,#{@height} L" <> Enum.join(points, " L") <> " L#{@width},#{@height} Z",
        label: "#{total} #{if total == 1, do: "game", else: "games"} in the last #{count} days",
        view_box: "0 0 #{@width} #{@height}"
      )

    ~H"""
    <svg
      id={@id}
      viewBox={@view_box}
      preserveAspectRatio="none"
      role="img"
      aria-label={@label}
      class="h-6 w-20 shrink-0 overflow-visible text-octo-indigo sm:w-28 dark:text-octo-indigo-light"
    >
      <title>{@label}</title>
      <path d={@area} fill="currentColor" fill-opacity="0.12" />
      <path
        d={@line}
        fill="none"
        stroke="currentColor"
        stroke-width="1.5"
        stroke-linejoin="round"
        stroke-linecap="round"
        vector-effect="non-scaling-stroke"
      />
    </svg>
    """
  end

  @doc ~S|How long ago `time` was, before `now`, for example "5 minutes ago".|
  def ago(time, now \\ DateTime.utc_now()) do
    seconds = max(DateTime.diff(now, time), 0)

    cond do
      seconds < 60 -> "just now"
      seconds < 3600 -> plural(div(seconds, 60), "minute")
      seconds < 86_400 -> plural(div(seconds, 3600), "hour")
      seconds < 30 * 86_400 -> plural(div(seconds, 86_400), "day")
      seconds < 365 * 86_400 -> plural(div(seconds, 30 * 86_400), "month")
      true -> plural(div(seconds, 365 * 86_400), "year")
    end
  end

  defp plural(1, unit), do: "1 #{unit} ago"
  defp plural(n, unit), do: "#{n} #{unit}s ago"
end
