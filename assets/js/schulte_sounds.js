// Sounds for the Schulte race.

import {audioReady, noise, tone} from "./sounds"

const sounds = {
  // A short beep on each step of the countdown. Laptop speakers are weak
  // in low tones, so the beeps are high and a little louder than the others.
  countdown() {
    tone({freq: 880, duration: 0.15, gain: 0.2})
  },

  // A longer beep, one octave higher, when the race starts
  go() {
    tone({freq: 1760, duration: 0.5, gain: 0.2})
  },

  // A short bright pop when you get the point
  found() {
    tone({freq: 880, freqEnd: 1320, duration: 0.12, gain: 0.15})
    tone({freq: 1760, start: 0.05, duration: 0.1, gain: 0.06})
  },

  // A soft low tick when another player gets the point
  other_found() {
    tone({type: "triangle", freq: 320, freqEnd: 220, duration: 0.08, gain: 0.08})
  },

  // A short dull buzz with the shake on a wrong number
  wrong() {
    tone({type: "square", freq: 140, duration: 0.15, gain: 0.05, filter: 900})
    noise({duration: 0.05, gain: 0.03, filter: 500})
  },

  // A happy rising tune when you win
  win() {
    ;[523, 659, 784].forEach((freq, i) => tone({freq, start: i * 0.1, duration: 0.2, gain: 0.13}))
    tone({freq: 1047, start: 0.3, duration: 0.6, gain: 0.13})
  },

  // A calm falling tune when you lose or the game is a tie
  lose() {
    tone({freq: 659, duration: 0.3, gain: 0.1})
    tone({freq: 523, start: 0.25, duration: 0.6, gain: 0.1})
  },
}

export function playSchulteSound(name) {
  if (audioReady()) sounds[name]?.()
}
