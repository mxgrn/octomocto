// Sounds for the Ink Trail game: a soft "blop" for each jet of the leader,
// the same "blop" a bit lower for each jet of the player's octopus, and a
// short rising pair of notes when the player's octopus falls one jet further
// behind.

import {audioReady, countdownBeep, noise, tone} from "./sounds"

const sounds = {
  // The same countdown beeps in all games
  countdown: countdownBeep,

  // The leader jets: a quick falling "blop", like a bubble
  jet() {
    tone({type: "sine", freq: 620, duration: 0.09, gain: 0.07, freqEnd: 380})
  },

  // The player's octopus jets after a tap: like the leader, a bit lower, so
  // that the two octopi sound alike but not the same
  follow() {
    tone({type: "sine", freq: 520, duration: 0.09, gain: 0.07, freqEnd: 320})
  },

  // A short dull buzz for a wrong tap
  wrong() {
    tone({type: "square", freq: 140, duration: 0.14, gain: 0.05, filter: 900})
    noise({duration: 0.05, gain: 0.03, filter: 500})
  },

  // The distance grows: two rising notes
  grow() {
    tone({freq: 1175, start: 0.06, duration: 0.1, gain: 0.08})
    tone({freq: 1568, start: 0.14, duration: 0.18, gain: 0.08})
  },

  // A happy rising tune at the end of the game
  end() {
    ;[523, 659, 784].forEach((freq, i) => tone({freq, start: i * 0.1, duration: 0.2, gain: 0.13}))
    tone({freq: 1047, start: 0.3, duration: 0.6, gain: 0.13})
  },
}

export function playInkTrailSound(name) {
  if (!audioReady()) return
  sounds[name]?.()
}
