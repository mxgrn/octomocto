// The star card of the result screen of a game. The Elm game renders an
// empty
//
//   <octo-rating game="memory">
//
// in its result for a player (not a watcher). The element owns its
// children, so Elm never changes them. It joins the rating channel
// (OctomoctoWeb.RatingChannel) on the socket of the game page (see
// pageGame/0 in game_menu.js). The server tells if the card shows: only to
// a signed-in user who played the game 5 times or more and did not vote
// yet. Else the element stays empty.
//
// A click on a star saves the vote at once. Then, for 1 to 4 stars, a
// field asks what we can do better (optional). For 5 stars, the stars
// jump and sparkle.

import {pageGame} from "./game_menu"

const h = (tag, attrs = {}, children = []) => {
  const el = document.createElement(tag)
  for (const [key, value] of Object.entries(attrs)) {
    if (key.startsWith("on")) el.addEventListener(key.slice(2), value)
    else if (value !== false && value != null) el.setAttribute(key, value === true ? "" : value)
  }
  for (const child of [children].flat()) {
    if (child != null) el.append(child)
  }
  return el
}

const starPath = "M11.48 3.5a.56.56 0 0 1 1.04 0l2.13 5.11a.56.56 0 0 0 .47.35l5.52.44c.5.04.7.66.32.99l-4.2 3.6a.56.56 0 0 0-.18.56l1.28 5.39a.56.56 0 0 1-.84.61l-4.72-2.88a.56.56 0 0 0-.59 0l-4.72 2.88a.56.56 0 0 1-.84-.6l1.28-5.4a.56.56 0 0 0-.18-.56l-4.2-3.6a.56.56 0 0 1 .32-.99l5.52-.44a.56.56 0 0 0 .47-.35l2.13-5.1Z"

const star = () => {
  const ns = "http://www.w3.org/2000/svg"
  const svg = document.createElementNS(ns, "svg")
  svg.setAttribute("viewBox", "0 0 24 24")
  svg.setAttribute("aria-hidden", "true")
  svg.setAttribute("class", "size-8 sm:size-9")
  const path = document.createElementNS(ns, "path")
  path.setAttribute("d", starPath)
  path.setAttribute("stroke-width", "1.5")
  path.setAttribute("stroke-linejoin", "round")
  svg.append(path)
  return svg
}

const filledClass = ["fill-amber-300", "stroke-amber-300"]
const emptyClass = ["fill-transparent", "stroke-white/60"]

class OctoRating extends HTMLElement {
  connectedCallback() {
    // "hidden" until the server says that the card shows. Then "vote",
    // "saving", "comment", "sending", "thanks" or "love".
    this.state = "hidden"
    this.stars = 0
    // The keys in the comment field must not reach the game
    this.addEventListener("keydown", e => e.stopPropagation())
    this.render()
    this.join()
  }

  disconnectedCallback() {
    if (this.channel) this.channel.leave()
    this.channel = null
  }

  join() {
    const game = pageGame()
    const kind = this.getAttribute("game")
    if (!game || !kind) return

    this.channel = game.socket.channel(`rating:${kind}`, {locale: document.documentElement.lang})
    this.channel.join().receive("ok", reply => {
      this.texts = reply.texts
      if (reply.show) {
        this.setState("vote")
      } else {
        this.channel.leave()
        this.channel = null
      }
    })
  }

  push(event, payload, onOk) {
    this.channel.push(event, payload)
      .receive("ok", onOk)
      .receive("error", () => this.setState("hidden"))
      .receive("timeout", () => this.setState("hidden"))
  }

  setState(state) {
    this.state = state
    this.render()
  }

  vote(stars) {
    if (this.state !== "vote") return
    this.stars = stars
    this.setState("saving")
    this.push("vote", {stars}, () => this.setState(stars === 5 ? "love" : "comment"))
  }

  sendComment(text) {
    if (text.trim() === "") return this.setState("thanks")
    this.setState("sending")
    this.push("comment", {text}, () => this.setState("thanks"))
  }

  render() {
    this.replaceChildren()
    if (this.state === "hidden" || !this.texts) return

    const t = this.texts
    // Fades in only when it first shows, not at each change
    const fadeIn = !this.shown
    this.shown = true
    const card = h("div", {
      id: "rating-card",
      class: (fadeIn ? "rating-in " : "") + "mt-2 flex w-full max-w-xs flex-col items-center gap-2 rounded-2xl bg-white/10 px-4 py-3 text-white ring-1 ring-white/15 backdrop-blur-sm"
    })

    switch (this.state) {
      case "comment":
      case "sending":
        card.append(this.commentForm(t))
        break
      case "thanks":
        card.append(this.starRow(t), h("p", {id: "rating-thanks", class: "text-sm font-medium"}, t.thanks))
        break
      case "love":
        card.append(this.starRow(t), h("p", {id: "rating-love", class: "rating-in text-sm font-medium"}, t.love))
        break
      default:
        card.append(h("p", {class: "text-sm font-medium text-white/90"}, t.title), this.starRow(t))
    }

    this.append(card)
  }

  starRow(t) {
    const active = this.state === "vote"
    const buttons = []
    // Fills the stars up to n, in place: a new button under the mouse
    // would get mouseenter again
    const paint = n => buttons.forEach((button, i) => {
      button.classList.remove(...filledClass, ...emptyClass)
      button.classList.add(...(i < n ? filledClass : emptyClass))
    })

    const row = h("div", {
      id: "rating-stars",
      class: ["relative flex items-center", this.state === "love" && "rating-love"].filter(Boolean).join(" "),
      role: active ? "radiogroup" : null,
      "aria-label": t.title,
      onmouseleave: () => { if (active) paint(this.stars) }
    })

    for (let n = 1; n <= 5; n++) {
      const button = h("button", {
        type: "button",
        id: `rating-star-${n}`,
        "aria-label": t.stars[n - 1],
        disabled: !active,
        style: `--n: ${n}`,
        class: [
          "rating-star rounded-md p-0.5 transition duration-150 focus-visible:outline-2 focus-visible:outline-white",
          active ? "cursor-pointer hover:scale-110 active:scale-95" : "cursor-default"
        ].join(" "),
        onmouseenter: () => { if (active) paint(n) },
        onfocus: () => { if (active) paint(n) },
        onblur: () => { if (active) paint(this.stars) },
        onclick: () => this.vote(n)
      }, star())
      buttons.push(button)
      row.append(button)
    }
    paint(this.stars)

    if (this.state === "love") {
      for (let i = 0; i < 12; i++) {
        const angle = (i / 12) * Math.PI * 2
        row.append(h("span", {
          class: "rating-spark",
          "aria-hidden": "true",
          style: `--dx: ${Math.round(Math.cos(angle) * 100)}px; --dy: ${Math.round(Math.sin(angle) * 45)}px; --d: ${(i % 3) * 70}ms`
        }))
      }
    }
    return row
  }

  commentForm(t) {
    const sending = this.state === "sending"
    const field = h("textarea", {
      id: "rating-comment",
      rows: "2",
      maxlength: "2000",
      placeholder: t.comment_placeholder,
      disabled: sending,
      class: "w-full resize-none rounded-xl bg-white/90 px-3 py-2 text-sm text-slate-900 placeholder:text-slate-400 focus:outline-2 focus:outline-amber-300"
    })
    if (this.draft) field.value = this.draft
    field.addEventListener("input", () => { this.draft = field.value })

    const form = h("form", {
      id: "rating-comment-form",
      class: "flex w-full flex-col items-center gap-2",
      onsubmit: e => { e.preventDefault(); this.sendComment(field.value) }
    }, [
      h("label", {for: "rating-comment", class: "text-sm font-medium"}, t.comment_title),
      field,
      h("button", {
        type: "submit",
        id: "rating-send",
        disabled: sending,
        class: "cursor-pointer rounded-full bg-white px-4 py-1.5 text-sm font-medium text-octo-indigo transition hover:bg-octo-mist active:scale-95 disabled:cursor-default disabled:opacity-60"
      }, t.send)
    ])
    if (!sending) requestAnimationFrame(() => field.focus({preventScroll: true}))
    return form
  }
}

customElements.define("octo-rating", OctoRating)
