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
      <g class="octo-bottom text-octo-indigo">
        <g transform="translate(0 300) scale(1 -1)">
          <.octopus />
        </g>
      </g>
    </svg>
    """
  end

  @doc """
  Renders the two octopi side by side. They float up and down around the
  same line, in opposite directions.
  """
  attr :id, :string, required: true
  attr :class, :any, default: nil

  def octopi_side_by_side(assigns) do
    ~H"""
    <div id={@id} aria-hidden="true" class={["flex items-end", @class]}>
      <svg viewBox="0 10 240 140" overflow="visible" class="octo-float h-full">
        <g class="text-octo-orange dark:text-octo-orange-light"><.octopus /></g>
      </svg>
      <svg
        viewBox="0 10 240 140"
        overflow="visible"
        class="octo-float octo-float-reverse ms-0.5 h-full"
      >
        <g class="text-octo-indigo"><.octopus /></g>
      </svg>
    </div>
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

  @doc """
  Renders one benefit in a list of the FAQ page, with an icon, a title and a
  short text.
  """
  attr :id, :string, required: true
  attr :icon, :string, required: true
  slot :title, required: true
  slot :inner_block, required: true

  def faq_benefit(assigns) do
    ~H"""
    <li
      id={@id}
      class="flex gap-3 rounded-2xl bg-base-200/60 p-4 ring-1 ring-base-content/5 transition hover:bg-base-200"
    >
      <span class="flex size-9 shrink-0 items-center justify-center rounded-xl bg-octo-indigo/10 text-octo-indigo dark:text-octo-indigo-light">
        <.icon name={@icon} class="size-5" />
      </span>
      <div class="space-y-1">
        <h3 class="font-semibold text-base-content">{render_slot(@title)}</h3>
        <p class="text-sm leading-relaxed text-base-content/70">{render_slot(@inner_block)}</p>
      </div>
    </li>
    """
  end

  @doc """
  The questions of the FAQ page as `{id, question}`, in the order of the
  page. The table of contents and the headings of the answers use them.
  """
  def faq_questions do
    [
      {"faq-free", dgettext("faq", "Is Octomocto free?")},
      {"faq-play-with-friends", dgettext("faq", "How do I play with a friend?")},
      {"faq-public-private", dgettext("faq", "What are public and private games?")},
      {"faq-why-sign-in", dgettext("faq", "Why sign in?")},
      {"faq-friends-follow", dgettext("faq", "How do friends and follows work?")},
      {"faq-suggest", dgettext("faq", "Can I suggest a game or report a bug?")}
    ]
  end

  @doc """
  Renders one question of the FAQ page, with the question as a heading that
  links to itself and the answer below.
  """
  attr :id, :string, required: true
  slot :inner_block, required: true

  def faq_question(assigns) do
    assigns = assign(assigns, :question, :proplists.get_value(assigns.id, faq_questions()))

    ~H"""
    <section
      id={@id}
      class="scroll-mt-6 space-y-3 border-t border-base-content/10 pt-8 leading-relaxed text-base-content/70"
    >
      <h2 class="text-xl font-semibold tracking-tight text-base-content">
        <a
          href={"##{@id}"}
          class="transition hover:text-octo-indigo dark:hover:text-octo-indigo-light"
        >
          {@question}
        </a>
      </h2>
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc "Renders a link inside an answer of the FAQ page."
  attr :href, :string, required: true
  attr :rest, :global
  slot :inner_block, required: true

  def faq_link(assigns) do
    ~H"""
    <.link
      href={@href}
      class="font-medium text-octo-indigo underline underline-offset-2 transition hover:text-octo-indigo/80 dark:text-octo-indigo-light"
      {@rest}
    >{render_slot(@inner_block)}</.link>
    """
  end
end
