defmodule OctomoctoWeb.TrainsController do
  use OctomoctoWeb, :controller

  def index(conn, _params) do
    render(conn, :index,
      page_title: "Train of Thought: Train Switching Puzzle",
      page_description:
        "Click the switches to send each train to the house of its color. A free train puzzle game in your browser that trains your attention and quick thinking."
    )
  end
end
