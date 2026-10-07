defmodule OctomoctoWeb.PageController do
  use OctomoctoWeb, :controller

  @games [
    %{
      id: "trains",
      name: "Train of Thought",
      description: "Click the switches to send each train to the house of its color.",
      path: "/trains",
      icon: "🚂",
      icon_class: "bg-amber-100"
    },
    %{
      id: "penguin",
      name: "Penguin Pursuit",
      description: "Race your friends to the fish in a maze that turns while you play.",
      path: "/penguin",
      icon: "🐧",
      icon_class: "bg-sky-100"
    },
    %{
      id: "schulte",
      name: "Schulte Race",
      description:
        "Find the numbers in order. The first player to click the next number gets the point.",
      path: "/schulte",
      icon: "123",
      icon_class: "bg-emerald-100 text-base font-bold text-emerald-700 tabular-nums"
    }
  ]

  def home(conn, _params) do
    render(conn, :home, games: @games)
  end

  def elm(conn, _params) do
    render(conn, :elm)
  end
end
