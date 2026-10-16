// The sound for a new open game in the Public games list on the front page.

import {tone, unlockAudio} from "./sounds"

// Two bright notes, so that the player hears it from another tab
function chime() {
  tone({freq: 880, duration: 0.15, gain: 0.1})
  tone({freq: 1319, start: 0.12, duration: 0.35, gain: 0.1})
}

// The bell button. A click turns the sound on or off. The sound is off
// after each page load: browsers start audio only after a user gesture,
// and the click that turns the sound on is one. So when the bell is on,
// the player hears the sound. A running audio context also plays in a
// background tab.
export const LobbySound = {
  mounted() {
    this.setOn(false)

    this.el.addEventListener("click", () => {
      this.setOn(!this.on)
      if (this.on) {
        unlockAudio()
        chime()
      }
    })

    this.handleEvent("lobby_new_game", () => {
      if (this.on) chime()
    })
  },

  setOn(on) {
    this.on = on
    this.el.setAttribute("aria-pressed", String(on))
    this.el.title = on ? "Sound for new games is on" : "Sound for new games is off"
  },
}
