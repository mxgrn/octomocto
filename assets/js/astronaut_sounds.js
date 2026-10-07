// Sounds for the astronaut maze (Station Escape).

import {audioReady, noise, tone} from "./sounds"

const sounds = {
  // A very quiet, short puff of the jet pack for each cell
  step() {
    noise({duration: 0.07, gain: 0.03, filter: 2500, filterEnd: 600, filterType: "bandpass"})
  },

  // The pod launches: a rising whoosh under a rising tune
  win() {
    noise({duration: 1, gain: 0.1, filter: 300, filterEnd: 4000, filterType: "bandpass"})
    ;[523, 784, 1047].forEach((freq, i) => tone({freq, start: i * 0.09, duration: 0.18, gain: 0.14}))
    tone({freq: 1047, freqEnd: 2093, start: 0.27, duration: 0.6, gain: 0.12})
  },

  // A falling "wah" when another astronaut gets to the pod
  lose() {
    tone({type: "sawtooth", freq: 330, freqEnd: 110, duration: 0.6, gain: 0.08, filter: 1400, filterEnd: 300})
  },

  // Two radar pings when the next station starts
  new_maze() {
    tone({freq: 1319, duration: 0.45, gain: 0.12})
    tone({freq: 1760, start: 0.22, duration: 0.5, gain: 0.1})
  },

  // A radio blip when another astronaut joins
  join() {
    tone({type: "square", freq: 1200, duration: 0.05, gain: 0.04, filter: 3000})
    tone({type: "square", freq: 1600, start: 0.07, duration: 0.06, gain: 0.04, filter: 3000})
  },

  // A dull metal clunk when you push against a wall
  wall() {
    tone({type: "triangle", freq: 160, freqEnd: 70, duration: 0.15, gain: 0.2})
    noise({duration: 0.06, gain: 0.06, filter: 600})
  },
}

export function playAstronautSound(name) {
  if (audioReady()) sounds[name]?.()
}
