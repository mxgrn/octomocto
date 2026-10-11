defmodule OctomoctoWeb.TrainsController do
  use OctomoctoWeb, :controller

  alias Octomocto.Trains

  plug :put_seo

  def index(conn, params) do
    settings = settings(params)

    render(conn, :index,
      settings: settings,
      switch_counts: Trains.switch_counts(settings.players)
    )
  end

  def create(conn, params) do
    id = Trains.create_game(settings(params))
    redirect(conn, to: ~p"/trains/#{id}")
  end

  def show(conn, %{"id" => id}) do
    if Trains.game_exists?(id) do
      render(conn, :show,
        id: id,
        user_token: user_token(conn.assigns.current_scope),
        noindex: true
      )
    else
      conn
      |> put_flash(:error, "This game does not exist (any more). Start a new one.")
      |> redirect(to: ~p"/trains")
    end
  end

  # One player, 12 switches, 2 trains for each house and the normal pace,
  # when the params do not say otherwise. The switches must divide equally
  # between the players.
  defp settings(params) do
    players = int_param(params["players"], 1..4, 1)
    switches = int_param(params["switches"], 1..12, 12)

    %{
      players: players,
      switch_count: Trains.fit_switch_count(switches, players),
      trains_per_house: int_param(params["trains"], 1..7, 2),
      pace: if(params["pace"] in Trains.paces(), do: params["pace"], else: "normal")
    }
  end

  defp int_param(value, range, default) do
    case Integer.parse(value || "") do
      {n, ""} -> if n in range, do: n, else: default
      _ -> default
    end
  end

  defp put_seo(conn, _opts) do
    merge_assigns(conn,
      page_title: "Right on Track: Train Switching Puzzle",
      page_description:
        "Click the switches to send each train to the house with its colors. A free train puzzle game in your browser, alone or together with up to 3 friends."
    )
  end

  defp user_token(%{user: user}), do: OctomoctoWeb.UserSocket.user_token(user.id)
  defp user_token(nil), do: nil
end
