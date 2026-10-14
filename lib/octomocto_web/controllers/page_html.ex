defmodule OctomoctoWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use OctomoctoWeb, :html

  embed_templates "page_html/*"

  @doc """
  Renders the two octopi from `mark.svg` inline, so that each one can move.
  """
  attr :class, :any, default: nil

  def octopi(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 240 300"
      overflow="visible"
      aria-hidden="true"
      class={@class}
    >
      <g class="octo-top text-octo-orange dark:text-octo-orange-light">
        <.octopus />
      </g>
      <g class="octo-bottom text-octo-indigo dark:text-octo-indigo-light">
        <g transform="translate(0 300) scale(1 -1)">
          <.octopus />
        </g>
      </g>
    </svg>
    """
  end

  defp octopus(assigns) do
    ~H"""
    <g fill="none" stroke="currentColor" stroke-width="18" stroke-linecap="round">
      <path d="M78 120C52 128 34 112 30 86" />
      <path d="M92 134C64 142 30 140 10 118" />
      <path d="M162 120C188 128 206 112 210 86" />
      <path d="M148 134C176 142 210 140 230 118" />
    </g>
    <circle cx="120" cy="88" r="62" fill="currentColor" />
    <circle cx="98" cy="84" r="15" fill="#fff" />
    <circle cx="142" cy="84" r="15" fill="#fff" />
    <circle cx="98" cy="90" r="7" fill="#171532" />
    <circle cx="142" cy="90" r="7" fill="#171532" />
    <path
      d="M110 112Q120 120 130 112"
      fill="none"
      stroke="#171532"
      stroke-width="5"
      stroke-linecap="round"
    />
    """
  end

  @doc """
  Renders a legal page, such as the Privacy Policy, with a title, the date
  of the last change and styles for the headings, paragraphs and lists inside.
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :updated, :string, required: true
  slot :inner_block, required: true

  def legal_page(assigns) do
    ~H"""
    <article
      id={@id}
      class={[
        "space-y-4 pt-4 text-sm leading-relaxed text-base-content/80",
        "[&_h2]:pt-4 [&_h2]:text-base [&_h2]:font-semibold [&_h2]:text-base-content",
        "[&_ul]:list-disc [&_ul]:space-y-1 [&_ul]:pl-5",
        "[&_a]:text-octo-indigo [&_a]:underline [&_a]:underline-offset-2 dark:[&_a]:text-octo-indigo-light"
      ]}
    >
      <header class="space-y-1">
        <h1 class="text-2xl font-semibold tracking-tight text-base-content">{@title}</h1>
        <p class="text-xs text-base-content/50">Last updated: {@updated}</p>
      </header>
      {render_slot(@inner_block)}
    </article>
    """
  end
end
