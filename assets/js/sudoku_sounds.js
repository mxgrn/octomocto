// Sounds for the sudoku game.

import {audioReady, noise, tone} from "./sounds"

const sounds = {
  // The countdown beeps, the same as in the Schulte race
  countdown() {
    tone({freq: 880, duration: 0.15, gain: 0.2})
  },

  go() {
    tone({freq: 1760, duration: 0.5, gain: 0.2})
  },

  // A short bright chime when you fill a cell
  found() {
    tone({freq: 660, duration: 0.12, gain: 0.12})
    tone({freq: 990, start: 0.1, duration: 0.2, gain: 0.12})
  },

  // A soft low tick when another player fills a cell
  other_found() {
    tone({type: "triangle", freq: 320, freqEnd: 220, duration: 0.08, gain: 0.08})
  },

  // A short dull buzz with the shake of a wrong digit
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

export function playSudokuSound(name) {
  if (audioReady()) sounds[name]?.()
}
