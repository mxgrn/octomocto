defmodule Octomocto.GameSettingsTest do
  use Octomocto.DataCase, async: true

  alias Octomocto.GameSettings

  @guest_id Ecto.UUID.generate()

  test "saving the settings keeps the tab" do
    GameSettings.put_tab(nil, @guest_id, "memory", "lobby")
    GameSettings.put(nil, @guest_id, "memory", %{"cards" => "16"})

    assert GameSettings.get(nil, @guest_id, "memory") == %{"cards" => "16"}
    assert GameSettings.get_tab(nil, @guest_id, "memory") == "lobby"
  end

  test "saving the tab keeps the settings" do
    GameSettings.put(nil, @guest_id, "memory", %{"cards" => "16"})
    GameSettings.put_tab(nil, @guest_id, "memory", "lobby")

    assert GameSettings.get(nil, @guest_id, "memory") == %{"cards" => "16"}
    assert GameSettings.get_tab(nil, @guest_id, "memory") == "lobby"
  end

  test "a saved tab without settings gives no settings" do
    GameSettings.put_tab(nil, @guest_id, "memory", "lobby")

    assert GameSettings.get(nil, @guest_id, "memory") == nil
  end
end
