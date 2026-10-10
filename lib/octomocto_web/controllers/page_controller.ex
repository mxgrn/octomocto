defmodule OctomoctoWeb.PageController do
  use OctomoctoWeb, :controller

  @games [
    %{
      id: "trains",
      name: "Right on Track",
      description: "Click the switches to send each train to the house of its color.",
      path: "/trains",
      icon: "🚂",
      icon_class: "bg-octo-orange/10 dark:bg-octo-orange-light/15"
    },
    %{
      id: "astronaut",
      name: "Station Escape",
      description:
        "Race your friends to the escape pod on a space station that spins while you play.",
      path: "/astronaut",
      icon: "🧑‍🚀",
      icon_class: "bg-octo-navy dark:bg-black/30 dark:ring-1 dark:ring-white/10"
    },
    %{
      id: "schulte",
      name: "Schulte Race",
      description:
        "Find the numbers in order. The first player to click the next number gets the point.",
      path: "/schulte",
      icon: "123",
      icon_class:
        "bg-octo-indigo/10 text-base font-bold text-octo-indigo tabular-nums dark:bg-octo-indigo-light/15 dark:text-octo-indigo-light"
    }
  ]

  def home(conn, _params) do
    render(conn, :home, games: @games)
  end

  def elm(conn, _params) do
    render(conn, :elm)
  end
end
