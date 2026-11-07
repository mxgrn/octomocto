defmodule OctomoctoWeb.MemoryCampaignLiveTest do
  use OctomoctoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Octomocto.Memory.{Campaign, CampaignLevel}
  alias Octomocto.Repo

  setup :register_and_log_in_user

  test "the theme grid below the level card changes the theme of the level", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/memory/campaign")

    assert has_element?(view, "#theme-random[aria-checked=true]")

    view |> element("#theme-random") |> render_click()
    assert has_element?(view, "#theme-random[aria-checked=false]")

    [theme | _] = Campaign.themes(Campaign.get(1))
    view |> element("#theme-#{theme.name}") |> render_click()
    assert_patch(view, ~p"/memory/campaign?level=1&theme=#{theme.name}")
    assert has_element?(view, "#theme-#{theme.name}[aria-current=true]")
  end

  test "a locked level has no theme grid", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/memory/campaign?level=2")

    assert has_element?(view, "#level-locked")
    refute has_element?(view, "#theme-picker")
  end

  test "the theme grid shows only the themes with enough images for the level", %{
    conn: conn,
    user: user
  } do
    Repo.insert!(%CampaignLevel{
      user_id: user.id,
      level: 22,
      best_cleared: 63,
      completed_at: DateTime.utc_now()
    })

    level = Campaign.get(23)
    small = Octomocto.Memory.Themes.list() -- Campaign.themes(level)
    {:ok, view, _html} = live(conn, ~p"/memory/campaign?level=23&theme=#{hd(small).name}")

    # A theme that the level cannot use is random for the level
    assert has_element?(view, "#theme-random[aria-checked=true]")
    view |> element("#theme-random") |> render_click()

    assert has_element?(view, "#theme-#{hd(Campaign.themes(level)).name}")
    for theme <- small, do: refute(has_element?(view, "#theme-#{theme.name}"))
  end
end
