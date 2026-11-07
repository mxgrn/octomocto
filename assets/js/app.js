// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/octomocto"
import topbar from "../vendor/topbar"
import {inviteSound, muted, setMuted, unlockAudio} from "./sounds"
import {playTrainSound} from "./train_sounds"
import {playAstronautSound} from "./astronaut_sounds"
import {playNimbleMosaicSound} from "./nimble_mosaic_sounds"
import {playMemorySound} from "./memory_sounds"
import {playSetSound} from "./set_sounds"
import {playSudokuSound} from "./sudoku_sounds"
import {playEchoSound} from "./echo_sounds"
import {playMahjongSound} from "./mahjong_sounds"
import {playOverlapSound} from "./overlap_sounds"
import {playSnapSound} from "./snap_sounds"
import {playAfterglowSound} from "./afterglow_sounds"
import {LobbySound} from "./lobby_sounds"
import {setGameMenu} from "./game_menu"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

// A Join link of the lists of open games has ?from=lobby (see
// OctomoctoWeb.GamePageComponents). The game page takes it out of the
// address bar before the game reads the URL, so that a copied link does not
// have it, and sends it in the join params of the channel.
const fromLobby = (() => {
  const url = new URL(window.location.href)
  if (url.searchParams.get("from") !== "lobby") return false
  url.searchParams.delete("from")
  history.replaceState(history.state, "", url)
  return true
})()
const lobbyParams = fromLobby ? {from: "lobby"} : {}
// On a LiveView page, also after live navigation
const TelegramLogin = {
  mounted() { showTelegramLogin(this.el) },
}

const Turnstile = {
  mounted() { showTurnstile(this.el) },
  destroyed() { hideTurnstile(this.el) },
}

// The bar of notifications above the header (see `site_notifications` in
// layouts.ex). It shows the first notification that the user did not close,
// in the order the notifications were added. After the user closes it, the
// next one shows on the next page load. The server also gets each close
// (see NotificationCloseController).
const CLOSED_NOTIFICATIONS_KEY = "closed-notifications"
const closedNotifications = () => {
  try { return JSON.parse(localStorage.getItem(CLOSED_NOTIFICATIONS_KEY)) || [] } catch (_e) { return [] }
}
const closeNotification = (notification) => {
  const id = notification.dataset.notificationId
  const closed = new Set([...closedNotifications(), id])
  try { localStorage.setItem(CLOSED_NOTIFICATIONS_KEY, JSON.stringify([...closed])) } catch (_e) {}
  // The bar works the same when the request fails
  fetch(`/notifications/${id}/close`, {method: "POST", headers: {"x-csrf-token": csrfToken}})
    .catch(() => {})
  notification.classList.add("closing")
  setTimeout(() => { notification.hidden = true }, 150)
}
function showSiteNotification(container) {
  const closed = closedNotifications()
  const notification = [...container.querySelectorAll("[data-notification-id]")]
    .find(el => !closed.includes(el.dataset.notificationId))
  if (notification) notification.hidden = false
}
document.addEventListener("click", e => {
  const button = e.target.closest("[data-close-notification]")
  if (button) closeNotification(button.closest("[data-notification-id]"))
})
// On a LiveView page, also after live navigation
const SiteNotifications = {
  mounted() { showSiteNotification(this.el) },
}

// The settings page of a match (?match=<game id>) holds the seat of the
// player in the game, so it sends the token of the player in this tab
const matchToken = () => {
  const match = new URLSearchParams(window.location.search).get("match")
  if (!match) return {}
  // The last part of the path is the game, such as "memory" or "nimble-mosaic"
  const game = window.location.pathname.split("/").pop()
  try { return {match_token: sessionStorage.getItem(`${game}-token:${match}`)} } catch (_e) { return {} }
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: () => ({_csrf_token: csrfToken, ...matchToken()}),
  hooks: {...colocatedHooks, TelegramLogin, Turnstile, LobbySound, SiteNotifications},
})

// The socket often drops while the tab is in the background, and the error
// toast then shows before the user returns. Thus the toast stays hidden
// (see app.css) while the tab is hidden, and for some time after the tab is
// visible again, which is when the socket reconnects.
const RESUME_GRACE_MS = 5000
let resumeTimer
const markResuming = () => {
  clearTimeout(resumeTimer)
  const root = document.documentElement
  if (document.hidden) {
    root.dataset.resuming = ""
  } else {
    resumeTimer = setTimeout(() => delete root.dataset.resuming, RESUME_GRACE_MS)
  }
}
markResuming()
document.addEventListener("visibilitychange", markResuming)

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// A notice can come on any page, so each page unlocks the audio at the
// first click or key press of the player.
if (navigator.userActivation?.hasBeenActive) unlockAudio()
document.addEventListener("pointerdown", unlockAudio, {once: true})
document.addEventListener("keydown", unlockAudio, {once: true})

window.addEventListener("phx:notice-sound", e => {
  if (e.detail.sound === "invite") inviteSound()
})

// The sound switches of the user menu (`sound_switch` in layouts.ex). The
// server cannot know the state in the browser storage, so this sets
// `aria-checked` after each page load, and after a change in another tab.
const syncSoundSwitches = () => {
  for (const el of document.querySelectorAll("[data-sound-switch]")) {
    el.setAttribute("aria-checked", String(!muted(el.dataset.soundSwitch)))
  }
}
syncSoundSwitches()
window.addEventListener("phx:page-loading-stop", syncSoundSwitches)
window.addEventListener("storage", syncSoundSwitches)

document.addEventListener("click", e => {
  const el = e.target.closest("[data-sound-switch]")
  if (!el) return
  const kind = el.dataset.soundSwitch
  setMuted(kind, !muted(kind))
  syncSoundSwitches()
  // Play the sound that the switch turned on, so the player hears it
  if (!muted(kind)) {
    unlockAudio()
    if (kind === "invites") inviteSound()
  }
})

// The account menus in the header (`account_menu` in layouts.ex) open and
// close on a click on the button. A click outside the menu, a click on a link
// in the menu, the Escape key and a live navigation close the menu.
const closeAccountMenus = except => {
  for (const button of document.querySelectorAll("[data-account-menu-button]")) {
    if (button !== except) button.setAttribute("aria-expanded", "false")
  }
}
document.addEventListener("click", e => {
  const button = e.target.closest("[data-account-menu-button]")
  if (button) {
    const open = button.getAttribute("aria-expanded") === "true"
    button.setAttribute("aria-expanded", String(!open))
    closeAccountMenus(button)
  } else if (!e.target.closest("[data-account-menu]") || e.target.closest("a")) {
    closeAccountMenus()
  }
})
document.addEventListener("keydown", e => {
  if (e.key === "Escape") closeAccountMenus()
})
window.addEventListener("phx:page-loading-start", () => closeAccountMenus())

// Pick the eyes in the header wordmark that blink: the orange or the blue ones.
// pointerenter does not bubble, so the listener is on the capture phase.
document.addEventListener("pointerenter", e => {
  if (e.target.id === "home-link") {
    e.target.dataset.blink = Math.random() < 0.5 ? "orange" : "blue"
  }
}, true)

// The page of a game does not scroll during the play (see app.css). Mobile
// Safari scrolls also with `overflow: hidden`, so the moves of the finger
// are stopped here too.
document.addEventListener("touchmove", e => {
  if (document.querySelector(".is-playing")) e.preventDefault()
}, {passive: false})

// Hide the button of a form with a data-hide-on-submit attribute, so that the
// user cannot send the form twice.
document.addEventListener("submit", e => {
  if (e.target.matches("[data-hide-on-submit]")) {
    e.target.querySelectorAll("button").forEach(button => { button.hidden = true })
  }
})

// Send a Google Analytics event when a player clicks an internal link with a
// data-ga-link attribute. In a game with 2 or more players, the "Or try" link
// is a button that starts the next game for all players. gtag is only in prod.
document.addEventListener("click", e => {
  const link = e.target.closest("[data-ga-link]")
  if (!link || !window.gtag) return

  window.gtag("event", "internal_link_click", {
    link: link.dataset.gaLink,
    from_game: link.dataset.gaFrom,
    to_game: link.dataset.gaTo
  })
})

// Start the astronaut maze and connect its ports to the game channel.
// Stop the arrow keys from scrolling the page. The player can use only the
// keys, so a key press also unlocks the audio.
const astronautNode = document.getElementById("astronaut-main")
if (astronautNode) {
  document.addEventListener("pointerdown", unlockAudio, {once: true})
  document.addEventListener("keydown", unlockAudio, {once: true})
  window.addEventListener("keydown", e => {
    if (e.key.startsWith("Arrow")) e.preventDefault()
  })

  const astronaut = window.Elm.Astronaut.init({node: astronautNode, flags: {gameUrl: window.location.href}})
  const socket = new Socket("/socket", {params: {user_token: astronautNode.dataset.userToken}})
  socket.connect()

  const channel = socket.channel(`astronaut:${astronautNode.dataset.gameId}`)
  channel.on("state", state => astronaut.ports.astronautGameState.send(state))
  channel.join()
    .receive("ok", reply => astronaut.ports.astronautJoined.send(reply))
    .receive("error", ({reason}) => {
      // The game ended. The page redirects to the start of the game.
      if (reason === "not_found") return window.location.reload()
      channel.leave()
      astronaut.ports.astronautJoinFailed.send(reason)
    })

  astronaut.ports.astronautSendMove.subscribe(dir => channel.push("move", {dir}))
  astronaut.ports.astronautCopyText.subscribe(text => navigator.clipboard.writeText(text))
  astronaut.ports.playAstronautSound.subscribe(playAstronautSound)
}

// A player of a finished game can start the next game for all players (see
// OctomoctoWeb.NextGame). The port of the game sends the request, and the
// browsers of the players get the id of the new game.
const connectNextGame = (port, channel, node) => {
  port.subscribe(() => channel.push("next_game", {}))
  channel.on("next_game", ({id}) => window.location.assign(`${node.dataset.nextGamePath}/${id}`))
}

// Start the trains game and connect its ports to the game channel. The
// token gets the same player back after a reload, as in Nimble Mosaic
// below. The browser remembers if the player muted the sounds. Audio can
// start only after a click, so the first click on the page (normally on
// "Start game") unlocks it.
const trainsNode = document.getElementById("trains-main")
if (trainsNode) {
  if (navigator.userActivation?.hasBeenActive) unlockAudio()
  document.addEventListener("pointerdown", unlockAudio, {once: true})
  let muted = false
  try { muted = localStorage.getItem("trains-muted") === "true" } catch (_e) {}

  const trains = window.Elm.Trains.init({node: trainsNode, flags: {gameUrl: window.location.href, settingsUrl: trainsNode.dataset.settingsUrl, changeSettingsUrl: trainsNode.dataset.changeSettingsUrl || null, nextGame: {name: trainsNode.dataset.nextGameName, path: trainsNode.dataset.nextGamePath}, guest: !trainsNode.dataset.userToken, muted}})
  const socket = new Socket("/socket", {params: {user_token: trainsNode.dataset.userToken, _csrf_token: csrfToken}})
  socket.connect()

  const tokenKey = `trains-token:${trainsNode.dataset.gameId}`
  let token = null
  try { token = sessionStorage.getItem(tokenKey) } catch (_e) {}
  const joined = reply => {
    token = reply.token
    try {
      if (token) sessionStorage.setItem(tokenKey, token)
      else sessionStorage.removeItem(tokenKey)
    } catch (_e) {}
    trains.ports.trainsJoined.send(reply)
    trains.ports.trainsWatchers.send(reply.watchers ?? 0)
  }
  // A link with ?watch=1 only watches the game. The token of a player wins.
  const watch = new URLSearchParams(window.location.search).has("watch")
  // The menu of the game page joins its channel on this socket
  setGameMenu({kind: "trains", id: trainsNode.dataset.gameId, socket})
  const channel = socket.channel(`trains:${trainsNode.dataset.gameId}`, () => token ? {token} : (watch ? {watch} : lobbyParams))
  channel.on("state", state => trains.ports.trainsState.send(state))
  channel.on("flip", flip => trains.ports.trainsFlipped.send(flip))
  channel.on("decision", decision => trains.ports.trainsDecided.send(decision))
  channel.on("joined", joined)
  channel.on("watchers", ({count}) => trains.ports.trainsWatchers.send(count))
  channel.join()
    .receive("ok", joined)
    .receive("error", ({reason}) => {
      // The server of the game stopped a moment ago. The channel tries again.
      if (reason === "unavailable") return
      // The game ended. The page redirects to the settings of the game.
      if (reason === "not_found") return window.location.reload()
      channel.leave()
      trains.ports.trainsJoinFailed.send(reason)
    })

  trains.ports.trainsFlip.subscribe(flip => channel.push("flip", flip))
  trains.ports.trainsDecision.subscribe(decision => channel.push("decision", decision))
  trains.ports.trainsRestart.subscribe(() => channel.push("restart", {}))
  connectNextGame(trains.ports.trainsNextGame, channel, trainsNode)
  trains.ports.trainsNextLevel.subscribe(() => {
    channel.push("next_level", {})
      .receive("ok", ({id}) => window.location.assign(`/trains/${id}`))
  })
  trains.ports.trainsFinished.subscribe(result => channel.push("finished", result))
  trains.ports.trainsCopyText.subscribe(text => navigator.clipboard.writeText(text))
  trains.ports.playTrainSound.subscribe(playTrainSound)
  trains.ports.trainsSaveMuted.subscribe(value => {
    try { localStorage.setItem("trains-muted", String(value)) } catch (_e) {}
  })
}

// Start Nimble Mosaic and connect its ports to the game channel.
// The browser remembers if the player muted the sounds. The storage can
// be unavailable (for example, in a private window), so the sounds are
// then on.
//
// The countdown starts before the player can click on this page. After a
// click on "Start game", the browser lets the page start the audio at once,
// so that the countdown beeps. A player who opens a shared link gets the
// audio on the first click.
const nimbleMosaicNode = document.getElementById("nimble-mosaic-main")
if (nimbleMosaicNode) {
  if (navigator.userActivation?.hasBeenActive) unlockAudio()
  document.addEventListener("pointerdown", unlockAudio, {once: true})
  let muted = false
  try { muted = localStorage.getItem("nimble-mosaic-muted") === "true" } catch (_e) {}

  const nimbleMosaic = window.Elm.NimbleMosaic.init({node: nimbleMosaicNode, flags: {gameUrl: window.location.href, settingsUrl: nimbleMosaicNode.dataset.settingsUrl, changeSettingsUrl: nimbleMosaicNode.dataset.changeSettingsUrl || null, nextGame: {name: nimbleMosaicNode.dataset.nextGameName, path: nimbleMosaicNode.dataset.nextGamePath}, guest: !nimbleMosaicNode.dataset.userToken, muted}})
  const socket = new Socket("/socket", {params: {user_token: nimbleMosaicNode.dataset.userToken, _csrf_token: csrfToken}})
  socket.connect()

  // The token gets the same player back when the channel joins again, for
  // example after a reconnect to another server in a deploy, or after a
  // reload of the page. The tab remembers it, so that a new tab gets a new
  // player.
  const tokenKey = `nimble-mosaic-token:${nimbleMosaicNode.dataset.gameId}`
  let token = null
  try { token = sessionStorage.getItem(tokenKey) } catch (_e) {}
  const joined = reply => {
    token = reply.token
    try {
      if (token) sessionStorage.setItem(tokenKey, token)
      else sessionStorage.removeItem(tokenKey)
    } catch (_e) {}
    nimbleMosaic.ports.nimbleMosaicJoined.send(reply)
    nimbleMosaic.ports.nimbleMosaicWatchers.send(reply.watchers ?? 0)
  }
  // A link with ?watch=1 only watches the game. The token of a player wins.
  const watch = new URLSearchParams(window.location.search).has("watch")
  // The menu of the game page joins its channel on this socket
  setGameMenu({kind: "nimble-mosaic", id: nimbleMosaicNode.dataset.gameId, socket})
  const channel = socket.channel(`nimble-mosaic:${nimbleMosaicNode.dataset.gameId}`, () => token ? {token} : (watch ? {watch} : lobbyParams))
  channel.on("state", state => nimbleMosaic.ports.nimbleMosaicState.send(state))
  channel.on("joined", joined)
  channel.on("watchers", ({count}) => nimbleMosaic.ports.nimbleMosaicWatchers.send(count))
  channel.join()
    .receive("ok", joined)
    .receive("error", ({reason}) => {
      // The server of the game stopped a moment ago. The channel tries again.
      if (reason === "unavailable") return
      // The game ended. The page redirects to the settings of the game.
      if (reason === "not_found") return window.location.reload()
      channel.leave()
      nimbleMosaic.ports.nimbleMosaicJoinFailed.send(reason)
    })

  nimbleMosaic.ports.nimbleMosaicPick.subscribe(number => channel.push("pick", {number}))
  nimbleMosaic.ports.nimbleMosaicRestart.subscribe(() => channel.push("restart", {}))
  connectNextGame(nimbleMosaic.ports.nimbleMosaicNextGame, channel, nimbleMosaicNode)
  nimbleMosaic.ports.nimbleMosaicCopyText.subscribe(text => navigator.clipboard.writeText(text))
  nimbleMosaic.ports.nimbleMosaicPlaySound.subscribe(playNimbleMosaicSound)
  nimbleMosaic.ports.nimbleMosaicSaveMuted.subscribe(value => {
    try { localStorage.setItem("nimble-mosaic-muted", String(value)) } catch (_e) {}
  })
}

// Start the Schulte table and connect its ports to the game channel. It
// works as Nimble Mosaic above, with the same sounds.
const schulteNode = document.getElementById("schulte-main")
if (schulteNode) {
  if (navigator.userActivation?.hasBeenActive) unlockAudio()
  document.addEventListener("pointerdown", unlockAudio, {once: true})
  let muted = false
  try { muted = localStorage.getItem("schulte-muted") === "true" } catch (_e) {}

  const schulte = window.Elm.Schulte.init({node: schulteNode, flags: {gameUrl: window.location.href, settingsUrl: schulteNode.dataset.settingsUrl, changeSettingsUrl: schulteNode.dataset.changeSettingsUrl || null, nextGame: {name: schulteNode.dataset.nextGameName, path: schulteNode.dataset.nextGamePath}, guest: !schulteNode.dataset.userToken, muted}})
  const socket = new Socket("/socket", {params: {user_token: schulteNode.dataset.userToken, _csrf_token: csrfToken}})
  socket.connect()

  const tokenKey = `schulte-token:${schulteNode.dataset.gameId}`
  let token = null
  try { token = sessionStorage.getItem(tokenKey) } catch (_e) {}
  const joined = reply => {
    token = reply.token
    try {
      if (token) sessionStorage.setItem(tokenKey, token)
      else sessionStorage.removeItem(tokenKey)
    } catch (_e) {}
    schulte.ports.schulteJoined.send(reply)
    schulte.ports.schulteWatchers.send(reply.watchers ?? 0)
  }
  // A link with ?watch=1 only watches the game. The token of a player wins.
  const watch = new URLSearchParams(window.location.search).has("watch")
  // The menu of the game page joins its channel on this socket
  setGameMenu({kind: "schulte", id: schulteNode.dataset.gameId, socket})
  const channel = socket.channel(`schulte:${schulteNode.dataset.gameId}`, () => token ? {token} : (watch ? {watch} : lobbyParams))
  channel.on("state", state => schulte.ports.schulteState.send(state))
  channel.on("joined", joined)
  channel.on("watchers", ({count}) => schulte.ports.schulteWatchers.send(count))
  channel.join()
    .receive("ok", joined)
    .receive("error", ({reason}) => {
      // The server of the game stopped a moment ago. The channel tries again.
      if (reason === "unavailable") return
      // The game ended. The page redirects to the settings of the game.
      if (reason === "not_found") return window.location.reload()
      channel.leave()
      schulte.ports.schulteJoinFailed.send(reason)
    })

  schulte.ports.schultePick.subscribe(number => channel.push("pick", {number}))
  schulte.ports.schulteRestart.subscribe(() => channel.push("restart", {}))
  connectNextGame(schulte.ports.schulteNextGame, channel, schulteNode)
  schulte.ports.schulteCopyText.subscribe(text => navigator.clipboard.writeText(text))
  schulte.ports.schultePlaySound.subscribe(playNimbleMosaicSound)
  schulte.ports.schulteSaveMuted.subscribe(value => {
    try { localStorage.setItem("schulte-muted", String(value)) } catch (_e) {}
  })
}

// Start Graze and connect its ports to the game channel. It works as
// Nimble Mosaic above, with the same sounds. The browser sends the place
// of the circle of the player many times a second.
const grazeNode = document.getElementById("graze-main")
if (grazeNode) {
  if (navigator.userActivation?.hasBeenActive) unlockAudio()
  document.addEventListener("pointerdown", unlockAudio, {once: true})
  let muted = false
  try { muted = localStorage.getItem("graze-muted") === "true" } catch (_e) {}

  const graze = window.Elm.Graze.init({node: grazeNode, flags: {gameUrl: window.location.href, settingsUrl: grazeNode.dataset.settingsUrl, nextGame: {name: grazeNode.dataset.nextGameName, path: grazeNode.dataset.nextGamePath}, guest: !grazeNode.dataset.userToken, muted}})
  const socket = new Socket("/socket", {params: {user_token: grazeNode.dataset.userToken, _csrf_token: csrfToken}})
  socket.connect()

  const tokenKey = `graze-token:${grazeNode.dataset.gameId}`
  let token = null
  try { token = sessionStorage.getItem(tokenKey) } catch (_e) {}
  const joined = reply => {
    token = reply.token
    try {
      if (token) sessionStorage.setItem(tokenKey, token)
      else sessionStorage.removeItem(tokenKey)
    } catch (_e) {}
    graze.ports.grazeJoined.send(reply)
    graze.ports.grazeWatchers.send(reply.watchers ?? 0)
  }
  // A link with ?watch=1 only watches the game. The token of a player wins.
  const watch = new URLSearchParams(window.location.search).has("watch")
  // The menu of the game page joins its channel on this socket
  setGameMenu({kind: "graze", id: grazeNode.dataset.gameId, socket})
  const channel = socket.channel(`graze:${grazeNode.dataset.gameId}`, () => token ? {token} : (watch ? {watch} : lobbyParams))
  channel.on("state", state => graze.ports.grazeState.send(state))
  channel.on("joined", joined)
  channel.on("watchers", ({count}) => graze.ports.grazeWatchers.send(count))
  channel.join()
    .receive("ok", joined)
    .receive("error", ({reason}) => {
      // The server of the game stopped a moment ago. The channel tries again.
      if (reason === "unavailable") return
      // The game ended. The page redirects to the settings of the game.
      if (reason === "not_found") return window.location.reload()
      channel.leave()
      graze.ports.grazeJoinFailed.send(reason)
    })

  graze.ports.grazeSteer.subscribe(place => channel.push("steer", place))
  graze.ports.grazeRestart.subscribe(() => channel.push("restart", {}))
  connectNextGame(graze.ports.grazeNextGame, channel, grazeNode)
  graze.ports.grazeCopyText.subscribe(text => navigator.clipboard.writeText(text))
  graze.ports.grazePlaySound.subscribe(playNimbleMosaicSound)
  graze.ports.grazeSaveMuted.subscribe(value => {
    try { localStorage.setItem("graze-muted", String(value)) } catch (_e) {}
  })
}

// Start the Memory game and connect its ports to the game channel. It
// works as Nimble Mosaic above: the browser remembers if the player
// muted the sounds, and the tab remembers the token of the player.
const memoryNode = document.getElementById("memory-main")
if (memoryNode) {
  if (navigator.userActivation?.hasBeenActive) unlockAudio()
  document.addEventListener("pointerdown", unlockAudio, {once: true})
  let muted = false
  try { muted = localStorage.getItem("memory-muted") === "true" } catch (_e) {}

  const memory = window.Elm.Memory.init({node: memoryNode, flags: {gameUrl: window.location.href, indexUrl: memoryNode.dataset.indexUrl, settingsUrl: memoryNode.dataset.settingsUrl, changeSettingsUrl: memoryNode.dataset.changeSettingsUrl, nextGame: {name: memoryNode.dataset.nextGameName, path: memoryNode.dataset.nextGamePath}, donateUrl: memoryNode.dataset.donateUrl, guest: !memoryNode.dataset.userToken, muted, texts: JSON.parse(memoryNode.dataset.texts)}})
  const socket = new Socket("/socket", {params: {user_token: memoryNode.dataset.userToken, _csrf_token: csrfToken}})
  socket.connect()

  const tokenKey = `memory-token:${memoryNode.dataset.gameId}`
  let token = null
  try { token = sessionStorage.getItem(tokenKey) } catch (_e) {}
  const joined = reply => {
    preload(reply.state)
    token = reply.token
    try {
      if (token) sessionStorage.setItem(tokenKey, token)
      else sessionStorage.removeItem(tokenKey)
    } catch (_e) {}
    memory.ports.memoryJoined.send(reply)
    memory.ports.memoryWatchers.send(reply.watchers ?? 0)
  }
  // A link with ?watch=1 only watches the game. The token of a player wins.
  const watch = new URLSearchParams(window.location.search).has("watch")
  // The menu of the game page joins its channel on this socket
  setGameMenu({kind: "memory", id: memoryNode.dataset.gameId, socket})
  const channel = socket.channel(`memory:${memoryNode.dataset.gameId}`, () => token ? {token} : (watch ? {watch} : lobbyParams))
  // Loads the images of the field before the cards turn, so that a face
  // does not come in empty during the turn (slow on phones and tablets)
  const preloaded = new Map()
  const preload = state => {
    const urls = state.images.map(image => `/images/memory/${state.theme}/${image}.svg`)
    if (state.bombs > 0) urls.push("/images/memory/bomb.svg")
    for (const url of urls) {
      if (preloaded.has(url)) continue
      const img = new Image()
      img.src = url
      img.decode().catch(() => {})
      preloaded.set(url, img)
    }
  }
  channel.on("state", state => {
    preload(state)
    memory.ports.memoryState.send(state)
  })
  channel.on("joined", joined)
  channel.on("watchers", ({count}) => memory.ports.memoryWatchers.send(count))
  channel.join()
    .receive("ok", joined)
    .receive("error", ({reason}) => {
      // The server of the game stopped a moment ago. The channel tries again.
      if (reason === "unavailable") return
      // The game ended. The page redirects to the settings of the game.
      if (reason === "not_found") return window.location.reload()
      channel.leave()
      memory.ports.memoryJoinFailed.send(reason)
    })

  memory.ports.memoryFlip.subscribe(card => channel.push("flip", {card}))
  memory.ports.memoryRestart.subscribe(() => channel.push("restart", {}))
  connectNextGame(memory.ports.memoryNextGame, channel, memoryNode)
  memory.ports.memoryNextLevel.subscribe(() => {
    channel.push("next_level", {})
      .receive("ok", ({id}) => window.location.assign(`${memoryNode.dataset.indexUrl}/${id}`))
  })
  memory.ports.memoryCopyText.subscribe(text => navigator.clipboard.writeText(text))
  memory.ports.memoryPlaySound.subscribe(playMemorySound)
  memory.ports.memorySaveMuted.subscribe(value => {
    try { localStorage.setItem("memory-muted", String(value)) } catch (_e) {}
  })
}

// Start the Set game and connect its ports to the game channel. It works
// as Nimble Mosaic above: the browser remembers if the player muted the
// sounds, and the tab remembers the token of the player.
const setNode = document.getElementById("set-main")
if (setNode) {
  if (navigator.userActivation?.hasBeenActive) unlockAudio()
  document.addEventListener("pointerdown", unlockAudio, {once: true})
  let muted = false
  try { muted = localStorage.getItem("set-muted") === "true" } catch (_e) {}

  const setGame = window.Elm.SetGame.init({node: setNode, flags: {gameUrl: window.location.href, settingsUrl: setNode.dataset.settingsUrl, changeSettingsUrl: setNode.dataset.changeSettingsUrl || null, nextGame: {name: setNode.dataset.nextGameName, path: setNode.dataset.nextGamePath}, guest: !setNode.dataset.userToken, muted}})
  const socket = new Socket("/socket", {params: {user_token: setNode.dataset.userToken, _csrf_token: csrfToken}})
  socket.connect()

  const tokenKey = `set-token:${setNode.dataset.gameId}`
  let token = null
  try { token = sessionStorage.getItem(tokenKey) } catch (_e) {}
  const joined = reply => {
    token = reply.token
    try {
      if (token) sessionStorage.setItem(tokenKey, token)
      else sessionStorage.removeItem(tokenKey)
    } catch (_e) {}
    setGame.ports.setGameJoined.send(reply)
    setGame.ports.setGameWatchers.send(reply.watchers ?? 0)
  }
  // A link with ?watch=1 only watches the game. The token of a player wins.
  const watch = new URLSearchParams(window.location.search).has("watch")
  // The menu of the game page joins its channel on this socket
  setGameMenu({kind: "set", id: setNode.dataset.gameId, socket})
  const channel = socket.channel(`set:${setNode.dataset.gameId}`, () => token ? {token} : (watch ? {watch} : lobbyParams))
  channel.on("state", state => setGame.ports.setGameState.send(state))
  channel.on("joined", joined)
  channel.on("watchers", ({count}) => setGame.ports.setGameWatchers.send(count))
  channel.join()
    .receive("ok", joined)
    .receive("error", ({reason}) => {
      // The server of the game stopped a moment ago. The channel tries again.
      if (reason === "unavailable") return
      // The game ended. The page redirects to the settings of the game.
      if (reason === "not_found") return window.location.reload()
      channel.leave()
      setGame.ports.setGameJoinFailed.send(reason)
    })

  setGame.ports.setGameClaim.subscribe(cards => channel.push("claim", {cards}))
  setGame.ports.setGameRestart.subscribe(() => channel.push("restart", {}))
  connectNextGame(setGame.ports.setGameNextGame, channel, setNode)
  setGame.ports.setGameCopyText.subscribe(text => navigator.clipboard.writeText(text))
  setGame.ports.setGamePlaySound.subscribe(playSetSound)
  setGame.ports.setGameSaveMuted.subscribe(value => {
    try { localStorage.setItem("set-muted", String(value)) } catch (_e) {}
  })
}

// Start the sudoku game and connect its ports to the game channel. It works
// as the Set game above. The reply to a digit tells the page if the digit
// is wrong.
const sudokuNode = document.getElementById("sudoku-main")
if (sudokuNode) {
  if (navigator.userActivation?.hasBeenActive) unlockAudio()
  document.addEventListener("pointerdown", unlockAudio, {once: true})
  let muted = false
  try { muted = localStorage.getItem("sudoku-muted") === "true" } catch (_e) {}

  const sudoku = window.Elm.Sudoku.init({node: sudokuNode, flags: {gameUrl: window.location.href, settingsUrl: sudokuNode.dataset.settingsUrl, changeSettingsUrl: sudokuNode.dataset.changeSettingsUrl || null, nextGame: {name: sudokuNode.dataset.nextGameName, path: sudokuNode.dataset.nextGamePath}, guest: !sudokuNode.dataset.userToken, muted}})
  const socket = new Socket("/socket", {params: {user_token: sudokuNode.dataset.userToken, _csrf_token: csrfToken}})
  socket.connect()

  const tokenKey = `sudoku-token:${sudokuNode.dataset.gameId}`
  let token = null
  try { token = sessionStorage.getItem(tokenKey) } catch (_e) {}
  const joined = reply => {
    token = reply.token
    try {
      if (token) sessionStorage.setItem(tokenKey, token)
      else sessionStorage.removeItem(tokenKey)
    } catch (_e) {}
    sudoku.ports.sudokuJoined.send(reply)
    sudoku.ports.sudokuWatchers.send(reply.watchers ?? 0)
  }
  // A link with ?watch=1 only watches the game. The token of a player wins.
  const watch = new URLSearchParams(window.location.search).has("watch")
  // The menu of the game page joins its channel on this socket
  setGameMenu({kind: "sudoku", id: sudokuNode.dataset.gameId, socket})
  const channel = socket.channel(`sudoku:${sudokuNode.dataset.gameId}`, () => token ? {token} : (watch ? {watch} : lobbyParams))
  channel.on("state", state => sudoku.ports.sudokuState.send(state))
  channel.on("joined", joined)
  channel.on("watchers", ({count}) => sudoku.ports.sudokuWatchers.send(count))
  channel.join()
    .receive("ok", joined)
    .receive("error", ({reason}) => {
      // The server of the game stopped a moment ago. The channel tries again.
      if (reason === "unavailable") return
      // The game ended. The page redirects to the settings of the game.
      if (reason === "not_found") return window.location.reload()
      channel.leave()
      sudoku.ports.sudokuJoinFailed.send(reason)
    })

  sudoku.ports.sudokuPlace.subscribe(({cell, digit}) => {
    const placed = result => sudoku.ports.sudokuPlaced.send({cell, digit, result})
    channel.push("place", {cell, digit})
      .receive("ok", ({result}) => placed(result))
      .receive("error", () => placed("ignored"))
      .receive("timeout", () => placed("ignored"))
  })
  sudoku.ports.sudokuRestart.subscribe(() => channel.push("restart", {}))
  connectNextGame(sudoku.ports.sudokuNextGame, channel, sudokuNode)
  sudoku.ports.sudokuCopyText.subscribe(text => navigator.clipboard.writeText(text))
  sudoku.ports.sudokuPlaySound.subscribe(playSudokuSound)
  sudoku.ports.sudokuSaveMuted.subscribe(value => {
    try { localStorage.setItem("sudoku-muted", String(value)) } catch (_e) {}
  })
}

// Start the Echo game and connect its ports to the game channel. It works
// as the Memory game above. The browser also remembers if the player hid
// the shapes on the pads.
const echoNode = document.getElementById("echo-main")
if (echoNode) {
  if (navigator.userActivation?.hasBeenActive) unlockAudio()
  document.addEventListener("pointerdown", unlockAudio, {once: true})
  document.addEventListener("keydown", unlockAudio, {once: true})
  let muted = false
  let shapes = true
  try {
    muted = localStorage.getItem("echo-muted") === "true"
    shapes = localStorage.getItem("echo-shapes") !== "false"
  } catch (_e) {}

  const echo = window.Elm.Echo.init({node: echoNode, flags: {gameUrl: window.location.href, indexUrl: echoNode.dataset.indexUrl, settingsUrl: echoNode.dataset.settingsUrl, changeSettingsUrl: echoNode.dataset.changeSettingsUrl || null, nextGame: {name: echoNode.dataset.nextGameName, path: echoNode.dataset.nextGamePath}, donateUrl: echoNode.dataset.donateUrl, guest: !echoNode.dataset.userToken, muted, shapes, texts: JSON.parse(echoNode.dataset.texts)}})
  const socket = new Socket("/socket", {params: {user_token: echoNode.dataset.userToken, _csrf_token: csrfToken}})
  socket.connect()

  const tokenKey = `echo-token:${echoNode.dataset.gameId}`
  let token = null
  try { token = sessionStorage.getItem(tokenKey) } catch (_e) {}
  const joined = reply => {
    token = reply.token
    try {
      if (token) sessionStorage.setItem(tokenKey, token)
      else sessionStorage.removeItem(tokenKey)
    } catch (_e) {}
    echo.ports.echoJoined.send(reply)
    echo.ports.echoWatchers.send(reply.watchers ?? 0)
  }
  // A link with ?watch=1 only watches the game. The token of a player wins.
  const watch = new URLSearchParams(window.location.search).has("watch")
  // The menu of the game page joins its channel on this socket
  setGameMenu({kind: "echo", id: echoNode.dataset.gameId, socket})
  const channel = socket.channel(`echo:${echoNode.dataset.gameId}`, () => token ? {token} : (watch ? {watch} : lobbyParams))
  channel.on("state", state => echo.ports.echoState.send(state))
  channel.on("joined", joined)
  channel.on("watchers", ({count}) => echo.ports.echoWatchers.send(count))
  channel.join()
    .receive("ok", joined)
    .receive("error", ({reason}) => {
      // The server of the game stopped a moment ago. The channel tries again.
      if (reason === "unavailable") return
      // The game ended. The page redirects to the settings of the game.
      if (reason === "not_found") return window.location.reload()
      channel.leave()
      echo.ports.echoJoinFailed.send(reason)
    })

  echo.ports.echoStart.subscribe(() => channel.push("start", {}))
  echo.ports.echoPress.subscribe(pad => channel.push("press", {pad}))
  echo.ports.echoRestart.subscribe(() => channel.push("restart", {}))
  connectNextGame(echo.ports.echoNextGame, channel, echoNode)
  echo.ports.echoCopyText.subscribe(text => navigator.clipboard.writeText(text))
  echo.ports.echoPlaySound.subscribe(playEchoSound)
  echo.ports.echoSaveMuted.subscribe(value => {
    try { localStorage.setItem("echo-muted", String(value)) } catch (_e) {}
  })
  echo.ports.echoSaveShapes.subscribe(value => {
    try { localStorage.setItem("echo-shapes", String(value)) } catch (_e) {}
  })
}

// Start the mahjong game and connect its ports to the game channel. It
// works as the sudoku game above. The reply to a pair tells the page if the
// pair went off the board.
const mahjongNode = document.getElementById("mahjong-main")
if (mahjongNode) {
  if (navigator.userActivation?.hasBeenActive) unlockAudio()
  document.addEventListener("pointerdown", unlockAudio, {once: true})
  let muted = false
  try { muted = localStorage.getItem("mahjong-muted") === "true" } catch (_e) {}

  const mahjong = window.Elm.Mahjong.init({node: mahjongNode, flags: {gameUrl: window.location.href, settingsUrl: mahjongNode.dataset.settingsUrl, nextGame: {name: mahjongNode.dataset.nextGameName, path: mahjongNode.dataset.nextGamePath}, guest: !mahjongNode.dataset.userToken, muted}})
  const socket = new Socket("/socket", {params: {user_token: mahjongNode.dataset.userToken, _csrf_token: csrfToken}})
  socket.connect()

  const tokenKey = `mahjong-token:${mahjongNode.dataset.gameId}`
  let token = null
  try { token = sessionStorage.getItem(tokenKey) } catch (_e) {}
  const joined = reply => {
    token = reply.token
    try {
      if (token) sessionStorage.setItem(tokenKey, token)
      else sessionStorage.removeItem(tokenKey)
    } catch (_e) {}
    mahjong.ports.mahjongJoined.send(reply)
    mahjong.ports.mahjongWatchers.send(reply.watchers ?? 0)
  }
  // A link with ?watch=1 only watches the game. The token of a player wins.
  const watch = new URLSearchParams(window.location.search).has("watch")
  // The menu of the game page joins its channel on this socket
  setGameMenu({kind: "mahjong", id: mahjongNode.dataset.gameId, socket})
  const channel = socket.channel(`mahjong:${mahjongNode.dataset.gameId}`, () => token ? {token} : (watch ? {watch} : lobbyParams))
  channel.on("state", state => mahjong.ports.mahjongState.send(state))
  channel.on("joined", joined)
  channel.on("watchers", ({count}) => mahjong.ports.mahjongWatchers.send(count))
  channel.join()
    .receive("ok", joined)
    .receive("error", ({reason}) => {
      // The server of the game stopped a moment ago. The channel tries again.
      if (reason === "unavailable") return
      // The game ended. The page redirects to the settings of the game.
      if (reason === "not_found") return window.location.reload()
      channel.leave()
      mahjong.ports.mahjongJoinFailed.send(reason)
    })

  mahjong.ports.mahjongRemove.subscribe(({a, b}) => {
    const removed = result => mahjong.ports.mahjongRemoved.send({a, b, result})
    channel.push("remove", {a, b})
      .receive("ok", ({result}) => removed(result))
      .receive("error", () => removed("ignored"))
      .receive("timeout", () => removed("ignored"))
  })
  mahjong.ports.mahjongShuffle.subscribe(() => channel.push("shuffle", {}))
  mahjong.ports.mahjongRestart.subscribe(() => channel.push("restart", {}))
  connectNextGame(mahjong.ports.mahjongNextGame, channel, mahjongNode)
  mahjong.ports.mahjongCopyText.subscribe(text => navigator.clipboard.writeText(text))
  mahjong.ports.mahjongPlaySound.subscribe(playMahjongSound)
  mahjong.ports.mahjongSaveMuted.subscribe(value => {
    try { localStorage.setItem("mahjong-muted", String(value)) } catch (_e) {}
  })
}

// Start the Overlap game and connect its ports to the game channel. It works
// as the Set game above. The images of all symbols of the theme of the game
// load with its first state, so that a new card does not come in with empty
// places. With the theme "random", the next game can have another theme.
const overlapNode = document.getElementById("overlap-main")
if (overlapNode) {
  if (navigator.userActivation?.hasBeenActive) unlockAudio()
  document.addEventListener("pointerdown", unlockAudio, {once: true})
  let muted = false
  try { muted = localStorage.getItem("overlap-muted") === "true" } catch (_e) {}

  const symbols = JSON.parse(overlapNode.dataset.symbols)
  const loadedThemes = new Set()
  const loadImages = theme => {
    if (!theme || loadedThemes.has(theme) || !symbols[theme]) return
    loadedThemes.add(theme)
    symbols[theme].forEach((_name, symbol) => {
      const img = new Image()
      img.src = `/images/overlap/${theme}/${symbol}.svg`
    })
  }

  const overlap = window.Elm.Overlap.init({node: overlapNode, flags: {gameUrl: window.location.href, settingsUrl: overlapNode.dataset.settingsUrl, nextGame: {name: overlapNode.dataset.nextGameName, path: overlapNode.dataset.nextGamePath}, guest: !overlapNode.dataset.userToken, muted, symbols}})
  const socket = new Socket("/socket", {params: {user_token: overlapNode.dataset.userToken, _csrf_token: csrfToken}})
  socket.connect()

  const tokenKey = `overlap-token:${overlapNode.dataset.gameId}`
  let token = null
  try { token = sessionStorage.getItem(tokenKey) } catch (_e) {}
  const joined = reply => {
    token = reply.token
    try {
      if (token) sessionStorage.setItem(tokenKey, token)
      else sessionStorage.removeItem(tokenKey)
    } catch (_e) {}
    loadImages(reply.state?.theme)
    overlap.ports.overlapJoined.send(reply)
    overlap.ports.overlapWatchers.send(reply.watchers ?? 0)
  }
  // A link with ?watch=1 only watches the game. The token of a player wins.
  const watch = new URLSearchParams(window.location.search).has("watch")
  // The menu of the game page joins its channel on this socket
  setGameMenu({kind: "overlap", id: overlapNode.dataset.gameId, socket})
  const channel = socket.channel(`overlap:${overlapNode.dataset.gameId}`, () => token ? {token} : (watch ? {watch} : lobbyParams))
  channel.on("state", state => {
    loadImages(state.theme)
    overlap.ports.overlapState.send(state)
  })
  channel.on("joined", joined)
  channel.on("watchers", ({count}) => overlap.ports.overlapWatchers.send(count))
  channel.join()
    .receive("ok", joined)
    .receive("error", ({reason}) => {
      // The server of the game stopped a moment ago. The channel tries again.
      if (reason === "unavailable") return
      // The game ended. The page redirects to the settings of the game.
      if (reason === "not_found") return window.location.reload()
      channel.leave()
      overlap.ports.overlapJoinFailed.send(reason)
    })

  overlap.ports.overlapTap.subscribe(tap => channel.push("tap", tap))
  overlap.ports.overlapRestart.subscribe(() => channel.push("restart", {}))
  connectNextGame(overlap.ports.overlapNextGame, channel, overlapNode)
  overlap.ports.overlapCopyText.subscribe(text => navigator.clipboard.writeText(text))
  overlap.ports.overlapPlaySound.subscribe(playOverlapSound)
  overlap.ports.overlapSaveMuted.subscribe(value => {
    try { localStorage.setItem("overlap-muted", String(value)) } catch (_e) {}
  })
}

// Start the Snap game and connect its ports to the game channel. It works
// as the Overlap game above, without the link and the next game for all
// players, because Snap has one player.
const snapNode = document.getElementById("snap-main")
if (snapNode) {
  if (navigator.userActivation?.hasBeenActive) unlockAudio()
  document.addEventListener("pointerdown", unlockAudio, {once: true})
  document.addEventListener("keydown", unlockAudio, {once: true})
  let muted = false
  try { muted = localStorage.getItem("snap-muted") === "true" } catch (_e) {}

  const snap = window.Elm.Snap.init({node: snapNode, flags: {settingsUrl: snapNode.dataset.settingsUrl, nextGame: {name: snapNode.dataset.nextGameName, path: snapNode.dataset.nextGamePath}, guest: !snapNode.dataset.userToken, muted}})
  const socket = new Socket("/socket", {params: {user_token: snapNode.dataset.userToken, _csrf_token: csrfToken}})
  socket.connect()

  const tokenKey = `snap-token:${snapNode.dataset.gameId}`
  let token = null
  try { token = sessionStorage.getItem(tokenKey) } catch (_e) {}
  const joined = reply => {
    token = reply.token
    try {
      if (token) sessionStorage.setItem(tokenKey, token)
      else sessionStorage.removeItem(tokenKey)
    } catch (_e) {}
    snap.ports.snapJoined.send(reply)
  }
  const channel = socket.channel(`snap:${snapNode.dataset.gameId}`, () => token ? {token} : {})
  channel.on("state", state => snap.ports.snapState.send(state))
  channel.on("joined", joined)
  channel.join()
    .receive("ok", joined)
    .receive("error", ({reason}) => {
      // The server of the game stopped a moment ago. The channel tries again.
      if (reason === "unavailable") return
      // The game ended. The page redirects to the settings of the game.
      if (reason === "not_found") return window.location.reload()
      channel.leave()
      snap.ports.snapJoinFailed.send(reason)
    })

  snap.ports.snapAnswer.subscribe(answer => channel.push("answer", answer))
  snap.ports.snapTimeUp.subscribe(() => channel.push("time_up", {}))
  snap.ports.snapRestart.subscribe(() => channel.push("restart", {}))
  snap.ports.snapPlaySound.subscribe(playSnapSound)
  snap.ports.snapSaveMuted.subscribe(value => {
    try { localStorage.setItem("snap-muted", String(value)) } catch (_e) {}
  })
}

// Start the Afterglow game and connect its ports to the game channel. It
// works as the Snap game above.
const afterglowNode = document.getElementById("afterglow-main")
if (afterglowNode) {
  if (navigator.userActivation?.hasBeenActive) unlockAudio()
  document.addEventListener("pointerdown", unlockAudio, {once: true})
  document.addEventListener("keydown", unlockAudio, {once: true})
  let muted = false
  try { muted = localStorage.getItem("afterglow-muted") === "true" } catch (_e) {}

  const afterglow = window.Elm.Afterglow.init({node: afterglowNode, flags: {settingsUrl: afterglowNode.dataset.settingsUrl, nextGame: {name: afterglowNode.dataset.nextGameName, path: afterglowNode.dataset.nextGamePath}, guest: !afterglowNode.dataset.userToken, muted}})
  const socket = new Socket("/socket", {params: {user_token: afterglowNode.dataset.userToken, _csrf_token: csrfToken}})
  socket.connect()

  const tokenKey = `afterglow-token:${afterglowNode.dataset.gameId}`
  let token = null
  try { token = sessionStorage.getItem(tokenKey) } catch (_e) {}
  const joined = reply => {
    token = reply.token
    try {
      if (token) sessionStorage.setItem(tokenKey, token)
      else sessionStorage.removeItem(tokenKey)
    } catch (_e) {}
    afterglow.ports.afterglowJoined.send(reply)
  }
  const channel = socket.channel(`afterglow:${afterglowNode.dataset.gameId}`, () => token ? {token} : {})
  channel.on("state", state => afterglow.ports.afterglowState.send(state))
  channel.on("joined", joined)
  channel.join()
    .receive("ok", joined)
    .receive("error", ({reason}) => {
      // The server of the game stopped a moment ago. The channel tries again.
      if (reason === "unavailable") return
      // The game ended. The page redirects to the settings of the game.
      if (reason === "not_found") return window.location.reload()
      channel.leave()
      afterglow.ports.afterglowJoinFailed.send(reason)
    })

  afterglow.ports.afterglowTap.subscribe(tap => channel.push("tap", tap))
  afterglow.ports.afterglowRestart.subscribe(() => channel.push("restart", {}))
  afterglow.ports.afterglowPlaySound.subscribe(playAfterglowSound)
  afterglow.ports.afterglowSaveMuted.subscribe(value => {
    try { localStorage.setItem("afterglow-muted", String(value)) } catch (_e) {}
  })
}

// Start the Afterglow game with turns and connect its ports to the game
// channel. It works as the Echo game above. The token has the same key as
// in the single-player game, so that the settings page of a match finds it.
const afterglowTurnsNode = document.getElementById("afterglow-turns-main")
if (afterglowTurnsNode) {
  if (navigator.userActivation?.hasBeenActive) unlockAudio()
  document.addEventListener("pointerdown", unlockAudio, {once: true})
  document.addEventListener("keydown", unlockAudio, {once: true})
  let muted = false
  try { muted = localStorage.getItem("afterglow-muted") === "true" } catch (_e) {}

  const dataset = afterglowTurnsNode.dataset
  const afterglow = window.Elm.AfterglowTurns.init({node: afterglowTurnsNode, flags: {gameUrl: window.location.href, settingsUrl: dataset.settingsUrl, changeSettingsUrl: dataset.changeSettingsUrl || null, nextGame: {name: dataset.nextGameName, path: dataset.nextGamePath}, guest: !dataset.userToken, muted}})
  const socket = new Socket("/socket", {params: {user_token: dataset.userToken, _csrf_token: csrfToken}})
  socket.connect()

  const tokenKey = `afterglow-token:${dataset.gameId}`
  let token = null
  try { token = sessionStorage.getItem(tokenKey) } catch (_e) {}
  const joined = reply => {
    token = reply.token
    try {
      if (token) sessionStorage.setItem(tokenKey, token)
      else sessionStorage.removeItem(tokenKey)
    } catch (_e) {}
    afterglow.ports.afterglowTurnsJoined.send(reply)
    afterglow.ports.afterglowTurnsWatchers.send(reply.watchers ?? 0)
  }
  // A link with ?watch=1 only watches the game. The token of a player wins.
  const watch = new URLSearchParams(window.location.search).has("watch")
  // The menu of the game page joins its channel on this socket
  setGameMenu({kind: "afterglow", id: dataset.gameId, socket})
  const channel = socket.channel(`afterglow_turns:${dataset.gameId}`, () => token ? {token} : (watch ? {watch} : lobbyParams))
  channel.on("state", state => afterglow.ports.afterglowTurnsState.send(state))
  channel.on("flash", ({pattern}) => afterglow.ports.afterglowTurnsFlash.send(pattern))
  channel.on("joined", joined)
  channel.on("watchers", ({count}) => afterglow.ports.afterglowTurnsWatchers.send(count))
  channel.join()
    .receive("ok", joined)
    .receive("error", ({reason}) => {
      // The server of the game stopped a moment ago. The channel tries again.
      if (reason === "unavailable") return
      // The game ended. The page redirects to the settings of the game.
      if (reason === "not_found") return window.location.reload()
      channel.leave()
      afterglow.ports.afterglowTurnsJoinFailed.send(reason)
    })

  afterglow.ports.afterglowTurnsTap.subscribe(cell => channel.push("tap", {cell}))
  afterglow.ports.afterglowTurnsRestart.subscribe(() => channel.push("restart", {}))
  afterglow.ports.afterglowTurnsPlayLarger.subscribe(() => channel.push("play_larger", {}))
  connectNextGame(afterglow.ports.afterglowTurnsNextGame, channel, afterglowTurnsNode)
  afterglow.ports.afterglowTurnsCopyText.subscribe(text => navigator.clipboard.writeText(text))
  afterglow.ports.afterglowTurnsPlaySound.subscribe(playAfterglowSound)
  afterglow.ports.afterglowTurnsSaveMuted.subscribe(value => {
    try { localStorage.setItem("afterglow-muted", String(value)) } catch (_e) {}
  })
}

// Show the Telegram Login Widget. The widget script puts its iframe in the
// place of the script tag, so we add the script into each container.
// Telegram needs a full URL to send the user back to. A container that has
// the widget already is left as it is.
function showTelegramLogin(node) {
  if (node.childElementCount > 0) return
  const script = document.createElement("script")
  script.async = true
  script.src = "https://telegram.org/js/telegram-widget.js?22"
  script.dataset.telegramLogin = node.dataset.telegramLogin
  script.dataset.size = "large"
  // Telegram shows a checkbox that lets the bot send messages to the user
  script.dataset.requestAccess = "write"
  script.dataset.authUrl = new URL(node.dataset.authPath, window.location.href).href
  node.appendChild(script)
}

// Show the Cloudflare Turnstile widget ("I'm not a robot") in a form that
// sends a sign-in link. The widget adds a hidden input with its token to the
// form. A widget cannot start in a closed menu, so each widget shows when its
// container is visible for the first time. The script loads only then too.
let turnstileScript
function loadTurnstile() {
  turnstileScript ||= new Promise((resolve, reject) => {
    const script = document.createElement("script")
    script.src = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit"
    script.onload = () => resolve(window.turnstile)
    script.onerror = reject
    document.head.appendChild(script)
  })
  return turnstileScript
}
function showTurnstile(node) {
  if (node.turnstileObserver) return
  node.turnstileObserver = new IntersectionObserver(entries => {
    if (!entries.some(entry => entry.isIntersecting)) return
    node.turnstileObserver.disconnect()
    loadTurnstile().then(turnstile => {
      if (!node.isConnected) return
      node.turnstileWidgetId = turnstile.render(node, {
        sitekey: node.dataset.turnstileSitekey,
        size: "flexible",
        theme: document.documentElement.dataset.theme === "dark" ? "dark" : "light",
      })
    })
  })
  node.turnstileObserver.observe(node)
}
// After live navigation, the old widget must go, or it keeps refreshing its token.
// LiveView also destroys the hooks when a form sends, before the browser reads
// the form. Thus the widget goes later, and only when its container is gone.
function hideTurnstile(node) {
  node.turnstileObserver?.disconnect()
  setTimeout(() => {
    if (node.turnstileWidgetId && !node.isConnected) window.turnstile.remove(node.turnstileWidgetId)
  })
}

// On a page without a LiveView
document.querySelectorAll("[data-telegram-login]").forEach(showTelegramLogin)
document.querySelectorAll("[data-turnstile-sitekey]").forEach(showTurnstile)
// On a page without a LiveView
document.querySelectorAll("#site-notifications").forEach(showSiteNotification)

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

