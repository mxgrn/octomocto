defmodule OctomoctoWeb.MatchController do
  use OctomoctoWeb, :controller

  alias Octomocto.Match
  alias Octomocto.Match.{Board, Themes}

  plug :put_seo

  def index(conn, params) do
    settings = settings(params)
    filter = %{"set" => settings.set, "cards" => settings.cards, "players" => settings.players}

    render(conn, :index,
      settings: settings,
      sizes: Board.sizes(settings.theme, settings.set),
      themes: Themes.list(),
      leaderboard: Match.leaderboard(filter),
      user_results: user_results(conn.assigns.current_scope, filter)
    )
  end

  def create(conn, params) do
    id = Match.create_game(settings(params))
    redirect(conn, to: ~p"/match/#{id}")
  end

  def show(conn, %{"id" => id}) do
    if Match.game_exists?(id) do
      render(conn, :show,
        id: id,
        user_token: user_token(conn.assigns.current_scope),
        noindex: true
      )
    else
      conn
      |> put_flash(:error, "This game does not exist (any more). Start a new one.")
      |> redirect(to: ~p"/match")
    end
  end

  # The first theme, pairs and one player, when the params do not say
  # otherwise. A number of cards that is not possible changes to the
  # nearest possible one.
  defp settings(params) do
    theme = if Themes.get(params["theme"] || ""), do: params["theme"], else: Themes.default()
    set = if params["set"] == "triplets", do: 3, else: 2

    cards =
      case Integer.parse(params["cards"] || "") do
        {n, ""} -> Board.nearest_size(theme, set, n)
        _ -> Board.nearest_size(theme, set, Board.default_cards(set))
      end

    players =
      case Integer.parse(params["players"] || "") do
        {n, ""} when n in 1..5 -> n
        _ -> 1
      end

    %{theme: theme, set: set, cards: cards, players: players}
  end

  defp put_seo(conn, _opts) do
    merge_assigns(conn,
      page_title: "Match: Memory Card Game",
      page_description:
        "Find the matching pairs or triplets of cards. Play alone against the clock, or take turns with up to 4 friends. Free, in your browser."
    )
  end

  # Nil for a guest
  defp user_results(%{user: _} = scope, filter), do: Match.user_results(scope, filter)
  defp user_results(nil, _filter), do: nil

  defp user_token(%{user: user}), do: OctomoctoWeb.UserSocket.user_token(user.id)
  defp user_token(nil), do: nil
end
