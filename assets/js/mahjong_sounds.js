// Sounds for the mahjong game. The tiles click like stone or bone.

import {audioReady, gameStart, noise, tone} from "./sounds"

// A short hard click of a tile
function clack({start = 0, gain = 0.12, filter = 3200} = {}) {
  noise({start, duration: 0.035, gain, filter, filterType: "bandpass"})
  tone({type: "triangle", freq: 1900, freqEnd: 1300, start, duration: 0.04, gain: gain * 0.5})
}

const sounds = {
  // The same sound in all games when all players are ready
  start: gameStart,

  // The countdown beeps, the same as in the Schulte race
  countdown() {
    tone({freq: 880, duration: 0.15, gain: 0.2})
  },

  go() {
    tone({freq: 1760, duration: 0.5, gain: 0.2})
  },

  // One click when you select a tile
  select() {
    clack({gain: 0.08})
  },

  // Two clicks and a soft chime when you remove a pair
  found() {
    clack()
    clack({start: 0.06, filter: 2600})
    tone({freq: 784, start: 0.08, duration: 0.18, gain: 0.08})
  },

  // Two quiet clicks when another player removes a pair
  other_found() {
    clack({gain: 0.05, filter: 2200})
    clack({start: 0.06, gain: 0.05, filter: 1800})
  },

  // A short dull knock when the tile is not free
  blocked() {
    tone({type: "square", freq: 150, duration: 0.1, gain: 0.04, filter: 800})
  },

  // Many clicks, as when you mix tiles on a table
  shuffle() {
    for (let i = 0; i < 9; i++) clack({start: i * 0.045 + Math.random() * 0.02, gain: 0.05, filter: 1800 + Math.random() * 1800})
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

export function playMahjongSound(name) {
  if (audioReady()) sounds[name]?.()
}
