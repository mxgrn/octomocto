// The menu of a game page, in the panel of the Elm game, in place of the
// old Restart and mute buttons. Each Elm game renders an empty
//
//   <octo-game-menu menu-label="Menu" restart-label="Restart game"
//     sound-on-label="Turn the sounds on" sound-off-label="Turn the sounds off"
//     muted="false" player="true" locked="false">
//
// and handles its "octo-toggle-mute" and "octo-restart" events. The
// element owns its children, so Elm never changes them.
//
// It has the sound switch, and for a player (not a watcher) "Restart game"
// and the friends of the user who are online, each with an Invite button.
// On a small screen, they are in the dropdown of a burger button, which
// floats over the page, so it moves nothing. On a large screen, the panel
// is at the left of the field, so they are in the panel: the buttons in a
// row, and a card with the friends, only when the player can invite one of
// them (the game waits for players and a friend is online).
//
// The friends come from the invites channel (OctomoctoWeb.InviteChannel)
// on the socket of the game, which the page gives with setGameMenu/1 after
// it connects. The menu joins the channel at once on a large screen, and
// the first time that the dropdown opens on a small one.

let game = null

export const setGameMenu = g => { game = g }

// A small helper to make elements: h("div", {class: "a"}, [child, "text"])
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

const icon = name => h("span", {class: `${name} size-4`})

// The same as `lg` of Tailwind
const largeScreen = window.matchMedia("(min-width: 64rem)")

// The round outline button of the panel, as the old Restart button
const panelButton = "group flex size-9 shrink-0 cursor-pointer items-center justify-center gap-2 rounded-full text-sm font-medium text-slate-600 ring-1 ring-slate-200 transition hover:bg-slate-50 hover:text-slate-900 hover:ring-slate-300 active:scale-95 disabled:pointer-events-none disabled:opacity-50 dark:text-slate-300 dark:ring-white/20 dark:hover:bg-white/10 dark:hover:text-white dark:hover:ring-white/30"

class OctoGameMenu extends HTMLElement {
  static observedAttributes = [
    "locked", "menu-label", "restart-label", "muted", "player", "sound-on-label", "sound-off-label"
  ]

  connectedCallback() {
    this.open = false
    this.menu = null
    this.onOutside = e => { if (this.open && !this.contains(e.target)) this.toggle(false) }
    this.onKey = e => { if (e.key === "Escape") this.toggle(false) }
    this.onResize = () => { this.open = false; this.render() }
    document.addEventListener("click", this.onOutside)
    document.addEventListener("keydown", this.onKey)
    largeScreen.addEventListener("change", this.onResize)
    this.render()
  }

  disconnectedCallback() {
    document.removeEventListener("click", this.onOutside)
    document.removeEventListener("keydown", this.onKey)
    largeScreen.removeEventListener("change", this.onResize)
    if (this.channel) this.channel.leave()
    this.channel = null
  }

  attributeChangedCallback() {
    if (this.isConnected) this.render()
  }

  toggle(open) {
    this.open = open
    this.render()
  }

  // A player needs the friends on a large screen, or in an open dropdown
  maybeJoin() {
    const player = this.getAttribute("player") === "true"
    if (player && !this.channel && game && (largeScreen.matches || this.open)) this.join()
  }

  join() {
    this.channel = game.socket.channel(`invites:${game.kind}:${game.id}`, {
      locale: document.documentElement.lang
    })
    this.channel.on("update", menu => { this.menu = menu; this.render() })
    this.channel.join().receive("ok", menu => { this.menu = menu; this.render() })
  }

  invite(friendId) {
    this.channel.push("invite", {friend_id: friendId})
  }

  render() {
    this.maybeJoin()

    if (largeScreen.matches) {
      // The host has `self-start` from Elm, so that the burger keeps its size
      this.style.alignSelf = "stretch"
      this.replaceChildren(this.panel())
    } else {
      this.style.alignSelf = ""
      this.replaceChildren(...[this.burger(), this.open && this.dropdown()].filter(Boolean))
    }
  }

  // Large screen: the buttons in a row, and the card of the friends
  panel() {
    const muted = this.getAttribute("muted") === "true"
    const player = this.getAttribute("player") === "true"
    const soundLabel = this.soundLabel()

    const buttons = h("div", {class: "flex items-center gap-2"}, [
      h("button", {
        type: "button",
        id: "game-menu-sound",
        title: soundLabel,
        "aria-label": soundLabel,
        "aria-pressed": String(!muted),
        class: panelButton,
        onclick: () => this.dispatchEvent(new CustomEvent("octo-toggle-mute"))
      }, icon(muted ? "hero-speaker-x-mark" : "hero-speaker-wave")),
      player && h("button", {
        type: "button",
        id: "game-menu-restart",
        disabled: this.getAttribute("locked") === "true",
        class: `${panelButton} size-auto px-4 py-2`,
        onclick: () => this.dispatchEvent(new CustomEvent("octo-restart"))
      }, [
        h("span", {class: "hero-arrow-path size-4 transition-transform duration-300 group-hover:-rotate-180"}),
        this.getAttribute("restart-label") || "Restart game"
      ])
    ].filter(Boolean))

    const menu = this.menu
    const card = player && menu && menu.multiplayer && menu.can_invite && menu.friends.length > 0
      ? h("div", {id: "game-menu-invites", class: "mt-4 rounded-2xl bg-base-100 p-2 shadow-sm ring-1 ring-base-content/10"}, [
          h("p", {class: "px-3 pt-1 pb-1 text-xs font-semibold tracking-wide text-base-content/50 uppercase"}, menu.texts.invite_title),
          this.friendList(menu)
        ])
      : null

    return h("div", {id: "game-menu"}, [buttons, card].filter(Boolean))
  }

  soundLabel() {
    return this.getAttribute("muted") === "true"
      ? this.getAttribute("sound-on-label") || "Turn the sounds on"
      : this.getAttribute("sound-off-label") || "Turn the sounds off"
  }

  // Small screen: the burger button of the dropdown
  burger() {
    const label = this.getAttribute("menu-label") || "Menu"

    return h("button", {
      type: "button",
      id: "game-menu-button",
      title: label,
      "aria-haspopup": "true",
      "aria-expanded": String(this.open),
      class: `${panelButton} max-lg:landscape:size-auto max-lg:landscape:px-4 max-lg:landscape:py-2`,
      onclick: e => { e.stopPropagation(); this.toggle(!this.open) }
    }, [
      icon("hero-bars-3"),
      h("span", {class: "hidden max-lg:landscape:inline"}, label)
    ])
  }

  dropdown() {
    const locked = this.getAttribute("locked") === "true"
    const restartLabel = this.getAttribute("restart-label") || "Restart game"
    const muted = this.getAttribute("muted") === "true"
    const item = "group flex w-full cursor-pointer items-center gap-2 rounded-xl px-3 py-2 text-left text-sm font-medium transition hover:bg-base-200 disabled:pointer-events-none disabled:opacity-50"

    // The menu stays open, so that the new state shows
    const sound = h("button", {
      type: "button",
      id: "game-menu-sound",
      "aria-pressed": String(!muted),
      class: item,
      onclick: e => {
        e.stopPropagation()
        this.dispatchEvent(new CustomEvent("octo-toggle-mute"))
      }
    }, [
      icon(muted ? "hero-speaker-x-mark" : "hero-speaker-wave"),
      this.soundLabel()
    ])

    const player = this.getAttribute("player") === "true"

    const restart = !player ? null : h("button", {
      type: "button",
      id: "game-menu-restart",
      disabled: locked,
      class: item,
      onclick: () => {
        this.toggle(false)
        this.dispatchEvent(new CustomEvent("octo-restart"))
      }
    }, [
      h("span", {class: "hero-arrow-path size-4 transition-transform duration-300 group-hover:-rotate-180"}),
      restartLabel
    ])

    return h("div", {
      id: "game-menu",
      role: "menu",
      class: "absolute top-full right-0 z-50 mt-2 w-72 max-w-[calc(100vw-1rem)] rounded-2xl bg-base-100 p-2 text-base-content shadow-xl ring-1 ring-base-content/10"
    }, [sound, restart, player && this.invites()].filter(Boolean))
  }

  invites() {
    const menu = this.menu
    if (!menu || !menu.multiplayer) return null

    const t = menu.texts
    const note = text => h("p", {class: "px-3 py-2 text-sm text-base-content/60"}, text)
    let body

    if (menu.guest) {
      body = note(t.sign_in)
    } else if (!menu.can_invite) {
      body = note(t.not_waiting)
    } else if (menu.friends.length === 0) {
      body = note(t.no_friends)
    } else {
      body = this.friendList(menu)
    }

    return h("div", {class: "mt-1 border-t border-base-content/10 pt-2"}, [
      h("p", {class: "px-3 pb-1 text-xs font-semibold tracking-wide text-base-content/50 uppercase"}, t.invite_title),
      body
    ])
  }

  friendList(menu) {
    const t = menu.texts

    return h("ul", {id: "game-menu-friends", class: "space-y-0.5"}, menu.friends.map(friend =>
        h("li", {id: `game-menu-friend-${friend.id}`, class: "flex items-center gap-3 rounded-xl px-3 py-1.5"}, [
          friend.avatar_url
            ? h("img", {src: friend.avatar_url, alt: "", class: "size-7 shrink-0 rounded-full object-cover"})
            : h("span", {class: "flex size-7 shrink-0 items-center justify-center rounded-full bg-octo-indigo/10 text-xs font-semibold text-octo-indigo dark:bg-octo-indigo-light/15 dark:text-octo-indigo-light"},
                (friend.name || "?").charAt(0).toUpperCase()),
          h("span", {class: "min-w-0 flex-1 truncate text-sm font-medium"}, friend.name),
          friend.status === "invited"
            ? h("span", {class: "flex shrink-0 items-center gap-1 text-xs font-medium text-emerald-600 dark:text-emerald-400"}, [
                icon("hero-check"), t.invited
              ])
            : friend.status === "declined"
            ? h("span", {class: "flex shrink-0 items-center gap-1 text-xs font-medium text-base-content/50"}, [
                icon("hero-x-mark"), t.declined
              ])
            : h("button", {
                type: "button",
                class: "shrink-0 cursor-pointer rounded-full bg-octo-indigo px-3 py-1 text-xs font-medium text-white transition hover:bg-octo-indigo/90 active:scale-95",
                onclick: e => { e.stopPropagation(); this.invite(friend.id) }
              }, t.invite)
        ])
      ))
  }
}

customElements.define("octo-game-menu", OctoGameMenu)
