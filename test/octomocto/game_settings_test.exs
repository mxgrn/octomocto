defmodule Octomocto.GameSettingsTest do
  use Octomocto.DataCase, async: true

  alias Octomocto.GameSettings

  @guest_id Ecto.UUID.generate()

  test "saving the settings keeps the tab" do
    GameSettings.put_value(nil, @guest_id, "memory", "tab", "lobby")
    GameSettings.put(nil, @guest_id, "memory", %{"cards" => "16"})

    assert GameSettings.get(nil, @guest_id, "memory") == %{"cards" => "16"}
    assert GameSettings.get_value(nil, @guest_id, "memory", "tab") == "lobby"
  end

  test "saving the tab keeps the settings" do
    GameSettings.put(nil, @guest_id, "memory", %{"cards" => "16"})
    GameSettings.put_value(nil, @guest_id, "memory", "tab", "lobby")

    assert GameSettings.get(nil, @guest_id, "memory") == %{"cards" => "16"}
    assert GameSettings.get_value(nil, @guest_id, "memory", "tab") == "lobby"
  end

  test "the tab and the campaign theme are kept together" do
    GameSettings.put_value(nil, @guest_id, "memory", "tab", "campaign")
    GameSettings.put_value(nil, @guest_id, "memory", "campaign_theme", "ocean")
    GameSettings.put(nil, @guest_id, "memory", %{"cards" => "16"})

    assert GameSettings.get_value(nil, @guest_id, "memory", "tab") == "campaign"
    assert GameSettings.get_value(nil, @guest_id, "memory", "campaign_theme") == "ocean"
  end

  test "a saved tab without settings gives no settings" do
    GameSettings.put_value(nil, @guest_id, "memory", "tab", "lobby")

    assert GameSettings.get(nil, @guest_id, "memory") == nil
  end
end
