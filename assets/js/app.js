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
import {unlockAudio} from "./sounds"
import {playTrainSound} from "./train_sounds"
import {playAstronautSound} from "./astronaut_sounds"
import {playSchulteSound} from "./schulte_sounds"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Pick the eyes in the header wordmark that blink: the orange or the blue ones.
// pointerenter does not bubble, so the listener is on the capture phase.
document.addEventListener("pointerenter", e => {
  if (e.target.id === "home-link") {
    e.target.dataset.blink = Math.random() < 0.5 ? "orange" : "blue"
  }
}, true)

// Start the Elm app if the page has a mount node for it
const elmNode = document.getElementById("elm-main")
if (elmNode) {
  window.Elm.Main.init({node: elmNode})
}

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
      channel.leave()
      astronaut.ports.astronautJoinFailed.send(reason)
    })

  astronaut.ports.astronautSendMove.subscribe(dir => channel.push("move", {dir}))
  astronaut.ports.astronautCopyText.subscribe(text => navigator.clipboard.writeText(text))
  astronaut.ports.playAstronautSound.subscribe(playAstronautSound)
}

// Start the train game. It is single player, so it needs no channel.
// Audio can start only after a click, so the first click on the page
// (normally on Start) unlocks it.
const trainsNode = document.getElementById("trains-main")
if (trainsNode) {
  document.addEventListener("pointerdown", unlockAudio, {once: true})
  const trains = window.Elm.Trains.init({node: trainsNode, flags: {seed: Date.now()}})
  trains.ports.playTrainSound.subscribe(playTrainSound)
}

// Start the Schulte race and connect its ports to the game channel.
// The browser remembers if the player muted the sounds. The storage can
// be unavailable (for example, in a private window), so the sounds are
// then on.
//
// The countdown starts before the player can click on this page. After a
// click on "New game", the browser lets the page start the audio at once,
// so that the countdown beeps. A player who opens a shared link gets the
// audio on the first click.
const schulteNode = document.getElementById("schulte-main")
if (schulteNode) {
  if (navigator.userActivation?.hasBeenActive) unlockAudio()
  document.addEventListener("pointerdown", unlockAudio, {once: true})
  let muted = false
  try { muted = localStorage.getItem("schulte-muted") === "true" } catch (_e) {}

  const schulte = window.Elm.Schulte.init({node: schulteNode, flags: {gameUrl: window.location.href, muted}})
  const socket = new Socket("/socket", {params: {user_token: schulteNode.dataset.userToken}})
  socket.connect()

  // The token gets the same player back when the channel joins again, for
  // example after a reconnect to another server in a deploy, or after a
  // reload of the page. The tab remembers it, so that a new tab gets a new
  // player.
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
  }
  const channel = socket.channel(`schulte:${schulteNode.dataset.gameId}`, () => token ? {token} : {})
  channel.on("state", state => schulte.ports.schulteState.send(state))
  channel.on("joined", joined)
  channel.join()
    .receive("ok", joined)
    .receive("error", ({reason}) => {
      // The server of the game stopped a moment ago. The channel tries again.
      if (reason === "unavailable") return
      channel.leave()
      schulte.ports.schulteJoinFailed.send(reason)
    })

  schulte.ports.schultePick.subscribe(number => channel.push("pick", {number}))
  schulte.ports.schulteRestart.subscribe(() => channel.push("restart", {}))
  schulte.ports.schulteCopyText.subscribe(text => navigator.clipboard.writeText(text))
  schulte.ports.schultePlaySound.subscribe(playSchulteSound)
  schulte.ports.schulteSaveMuted.subscribe(value => {
    try { localStorage.setItem("schulte-muted", String(value)) } catch (_e) {}
  })
}

// Show the Telegram Login Widget. The widget script puts its iframe in the
// place of the script tag, so we add the script into each container.
// Telegram needs a full URL to send the user back to.
document.querySelectorAll("[data-telegram-login]").forEach(node => {
  const script = document.createElement("script")
  script.async = true
  script.src = "https://telegram.org/js/telegram-widget.js?22"
  script.dataset.telegramLogin = node.dataset.telegramLogin
  script.dataset.size = "large"
  script.dataset.authUrl = new URL(node.dataset.authPath, window.location.href).href
  node.appendChild(script)
})

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

