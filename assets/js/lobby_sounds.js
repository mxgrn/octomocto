// The sound for a new open game in the Public games list on the front page.

import {audioReady, tone, unlockAudio} from "./sounds"

const STORAGE_KEY = "lobby-sound"

// Two bright notes, so that the player hears it from another tab
function chime() {
  tone({freq: 880, duration: 0.15, gain: 0.1})
  tone({freq: 1319, start: 0.12, duration: 0.35, gain: 0.1})
}

// The bell button. A click turns the sound on or off, and the browser
// remembers it. The storage can be unavailable (for example, in a private
// window), so the sound is then off after a reload.
//
// Browsers start audio only after a user gesture. The click on the button
// is one. After a reload, the sound starts after the first click or key
// press on the page. A running audio context also plays in a background tab.
export const LobbySound = {
  mounted() {
    let on = false
    try { on = localStorage.getItem(STORAGE_KEY) === "true" } catch (_e) {}
    this.setOn(on)

    if (on && navigator.userActivation?.hasBeenActive) unlockAudio()
    this.unlock = () => { if (this.on) unlockAudio() }
    document.addEventListener("pointerdown", this.unlock)
    document.addEventListener("keydown", this.unlock)

    this.el.addEventListener("click", () => {
      this.setOn(!this.on)
      try { localStorage.setItem(STORAGE_KEY, String(this.on)) } catch (_e) {}
      if (this.on) {
        unlockAudio()
        chime()
      }
    })

    this.handleEvent("lobby_new_game", () => {
      if (this.on && audioReady()) chime()
    })
  },

  destroyed() {
    document.removeEventListener("pointerdown", this.unlock)
    document.removeEventListener("keydown", this.unlock)
  },

  setOn(on) {
    this.on = on
    this.el.setAttribute("aria-pressed", String(on))
    this.el.title = on ? "Sound for new games is on" : "Sound for new games is off"
  },
}
