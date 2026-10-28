// Sounds for the Snap game. The answers come fast, so their sounds are
// short and soft.

import {noise, audioReady, tone} from "./sounds"

const sounds = {
  // The countdown beeps, the same as in the Schulte race
  countdown() {
    tone({freq: 880, duration: 0.15, gain: 0.2})
  },

  // A soft tap for each card to remember
  card() {
    tone({type: "triangle", freq: 660, duration: 0.08, gain: 0.1})
  },

  // The clock of the round starts
  go() {
    tone({freq: 1760, duration: 0.4, gain: 0.18})
  },

  // A short bright tick for a correct answer
  correct() {
    tone({freq: 1047, duration: 0.07, gain: 0.08})
  },

  // A short dull buzz for a wrong answer
  wrong() {
    tone({type: "square", freq: 140, duration: 0.12, gain: 0.05, filter: 900})
    noise({duration: 0.04, gain: 0.03, filter: 500})
  },

  // Two rising notes when the multiplier gets larger
  level_up() {
    tone({freq: 1319, start: 0.05, duration: 0.08, gain: 0.08})
    tone({freq: 1568, start: 0.12, duration: 0.14, gain: 0.08})
  },

  // A happy rising tune at the end of the round
  end() {
    ;[523, 659, 784].forEach((freq, i) => tone({freq, start: i * 0.1, duration: 0.2, gain: 0.13}))
    tone({freq: 1047, start: 0.3, duration: 0.6, gain: 0.13})
  },
}

export function playSnapSound(name) {
  if (audioReady()) sounds[name]?.()
}
