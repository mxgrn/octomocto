// Sounds for the train game.

import {audioReady, tone} from "./sounds"

const sounds = {
  // A short mechanical click
  switch() {
    tone({type: "square", freq: 2200, freqEnd: 700, duration: 0.04, gain: 0.05, filter: 3000})
    tone({type: "triangle", freq: 140, duration: 0.05, gain: 0.12})
  },

  // A steam whistle: a chord of 3 notes that starts slowly
  depart() {
    for (const freq of [587, 740, 880]) {
      tone({type: "triangle", freq, duration: 0.5, gain: 0.05, attack: 0.06, filter: 2500})
    }
  },

  // Two rising notes
  correct() {
    tone({freq: 784, duration: 0.18, gain: 0.18})
    tone({freq: 1047, start: 0.09, duration: 0.3, gain: 0.18})
  },

  // A low falling buzz
  wrong() {
    tone({type: "sawtooth", freq: 180, freqEnd: 110, duration: 0.35, gain: 0.12, filter: 900})
  },
}

export function playTrainSound(name) {
  if (audioReady()) sounds[name]?.()
}
