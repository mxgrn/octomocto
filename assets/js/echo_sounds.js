// Sounds for the Echo game.

import {audioReady, tone} from "./sounds"

// The tone of each pad: the C major pentatonic scale over two octaves
const PAD_FREQS = [261.63, 293.66, 329.63, 392.0, 440.0, 523.25, 587.33, 659.25]

const sounds = {
  // A triangle wave with a short attack, so that it does not click
  pad({pad, ms}) {
    tone({type: "triangle", freq: PAD_FREQS[pad], duration: ms / 1000, gain: 0.22, attack: 0.02})
  },

  // A wrong pad: two low sawtooth waves that are a bit out of tune
  buzz() {
    ;[98, 103].forEach(freq => tone({type: "sawtooth", freq, duration: 0.55, gain: 0.12, attack: 0.02, filter: 900}))
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

  // A calm falling tune when you lose
  lose() {
    tone({freq: 659, duration: 0.3, gain: 0.1, start: 0.6})
    tone({freq: 523, start: 0.85, duration: 0.6, gain: 0.1})
  },
}

export function playEchoSound(sound) {
  if (audioReady()) sounds[sound.name]?.(sound)
}
