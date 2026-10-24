// Sounds for the Memory game.

import {audioReady, gameStart, noise, tone} from "./sounds"

const sounds = {
  // The same sound in all games when all players are ready
  start: gameStart,

  // A soft short swish when a card turns over
  flip() {
    noise({duration: 0.06, gain: 0.05, filter: 3000, filterEnd: 1200, filterType: "bandpass"})
  },

  // A short bright chime when a set is found
  match() {
    tone({freq: 660, duration: 0.12, gain: 0.12, start: 0.15})
    tone({freq: 990, duration: 0.2, gain: 0.12, start: 0.25})
  },

  // A low rumble when a player turns a bomb that was seen
  boom() {
    noise({duration: 0.6, gain: 0.25, filter: 900, filterEnd: 80, filterType: "lowpass"})
    tone({freq: 110, freqEnd: 40, duration: 0.5, gain: 0.15})
  },

  // Two quick notes when the turn comes to you
  turn() {
    tone({freq: 784, duration: 0.1, gain: 0.08, start: 0.3})
    tone({freq: 1047, duration: 0.15, gain: 0.08, start: 0.4})
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

export function playMemorySound(name) {
  if (audioReady()) sounds[name]?.()
}
