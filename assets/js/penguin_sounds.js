// Sounds for the penguin maze.

import {audioReady, noise, tone} from "./sounds"

const sounds = {
  // A very quiet, short pat for each cell
  step() {
    noise({duration: 0.035, gain: 0.025, filter: 900})
  },

  // A rising tune when you get the fish
  win() {
    ;[523, 659, 784].forEach((freq, i) => tone({type: "triangle", freq, start: i * 0.1, duration: 0.2, gain: 0.18}))
    tone({type: "triangle", freq: 1047, start: 0.3, duration: 0.5, gain: 0.18})
  },

  // A short falling tune when another penguin gets the fish
  lose() {
    tone({type: "triangle", freq: 392, duration: 0.2, gain: 0.15})
    tone({type: "triangle", freq: 262, start: 0.16, duration: 0.4, gain: 0.15})
  },

  // Two quick notes when the next maze starts
  new_maze() {
    tone({freq: 659, duration: 0.12, gain: 0.14})
    tone({freq: 988, start: 0.08, duration: 0.2, gain: 0.14})
  },

  // A soft pop when another penguin joins
  join() {
    tone({freq: 500, freqEnd: 950, duration: 0.09, gain: 0.15})
  },
}

export function playPenguinSound(name) {
  if (audioReady()) sounds[name]?.()
}
