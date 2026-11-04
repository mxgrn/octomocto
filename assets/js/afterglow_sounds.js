// Sounds for the Afterglow game. Each correct tile of a round plays the next
// note of a scale, so that a good round sounds like a short tune.

import {audioReady, countdownBeep, noise, tone} from "./sounds"

// A major pentatonic scale, so that any notes go well together
const scale = [523, 587, 659, 784, 880, 1047, 1175, 1319, 1568, 1760]

const sounds = {
  // The same countdown beeps in all games
  countdown: countdownBeep,

  // A soft shimmer when the tiles light up
  show() {
    tone({type: "triangle", freq: 1319, duration: 0.25, gain: 0.06})
    tone({type: "triangle", freq: 1976, start: 0.04, duration: 0.3, gain: 0.04})
  },

  // The tiles go out: now the player clicks
  hide() {
    tone({type: "triangle", freq: 660, duration: 0.12, gain: 0.06})
  },

  // A short dull buzz for a wrong tile
  wrong() {
    tone({type: "square", freq: 140, duration: 0.14, gain: 0.05, filter: 900})
    noise({duration: 0.05, gain: 0.03, filter: 500})
  },

  // Two rising notes for a fully correct round
  perfect() {
    tone({freq: 1319, start: 0.08, duration: 0.1, gain: 0.08})
    tone({freq: 1760, start: 0.16, duration: 0.2, gain: 0.08})
  },

  // A happy rising tune at the end of the game
  end() {
    ;[523, 659, 784].forEach((freq, i) => tone({freq, start: i * 0.1, duration: 0.2, gain: 0.13}))
    tone({freq: 1047, start: 0.3, duration: 0.6, gain: 0.13})
  },
}

// "found-N" is the Nth correct tile of the round, from 0
export function playAfterglowSound(name) {
  if (!audioReady()) return
  const [kind, n] = name.split("-")
  if (kind === "found") {
    const i = Number(n)
    tone({freq: scale[i % scale.length] * (i >= scale.length ? 2 : 1), duration: 0.12, gain: 0.08})
  } else {
    sounds[kind]?.()
  }
}
