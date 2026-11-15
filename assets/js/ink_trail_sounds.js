// Sounds for the Ink Trail game: a soft "blop" for each jet of the leader,
// the same "blop" a bit lower for each jet of the player's octopus (both go
// one tone higher for each jet of distance above 3), and a
// short rising pair of notes when the player's octopus falls one jet further
// behind. After a wrong tap, the ghost of the leader makes a short stream of
// bubbles on each of its jets.

import {audioReady, countdownBeep, goBeep, noise, tone} from "./sounds"

// The smallest distance of the game (see Octomocto.InkTrail.Game)
const MIN_DISTANCE = 3

// The jets sound one tone (2 semitones) higher for each jet of distance
// above the smallest one. At the start, the leader jets from 1 jet ahead up
// to the start distance: below the smallest distance, the pitch stays the same.
function pitchUp(distance) {
  return 2 ** ((2 * Math.max(0, distance - MIN_DISTANCE)) / 12)
}

const sounds = {
  // The same countdown and start beeps in all games
  countdown: countdownBeep,
  go: goBeep,

  // The leader jets: a quick falling "blop", like a bubble
  jet(distance) {
    const up = pitchUp(distance)
    tone({type: "sine", freq: 620 * up, duration: 0.09, gain: 0.07, freqEnd: 380 * up})
  },

  // The player's octopus jets after a tap: like the leader, a bit lower, so
  // that the two octopi sound alike but not the same
  follow(distance) {
    const up = pitchUp(distance)
    tone({type: "sine", freq: 520 * up, duration: 0.09, gain: 0.07, freqEnd: 320 * up})
  },

  // A short dull buzz for a wrong tap
  wrong() {
    tone({type: "square", freq: 140, duration: 0.14, gain: 0.05, filter: 900})
    noise({duration: 0.05, gain: 0.03, filter: 500})
  },

  // A jet of the ghost after a wrong tap: a short stream of small bubbles.
  // Each bubble is a quick tone that slides up. The bubbles come at random
  // times and pitches, and get softer, so no two jets sound the same.
  ghost() {
    let start = 0
    for (let i = 0; i < 6; i++) {
      const freq = 700 + Math.random() * 600
      tone({freq, freqEnd: freq * 1.9, start, duration: 0.05 + Math.random() * 0.03, gain: 0.045 - i * 0.005})
      start += 0.04 + Math.random() * 0.05
    }
  },

  // The distance grows: two rising notes
  grow() {
    tone({freq: 1175, start: 0.06, duration: 0.1, gain: 0.08})
    tone({freq: 1568, start: 0.14, duration: 0.18, gain: 0.08})
  },

  // A happy rising tune at the end of the game
  end() {
    ;[523, 659, 784].forEach((freq, i) => tone({freq, start: i * 0.1, duration: 0.2, gain: 0.13}))
    tone({freq: 1047, start: 0.3, duration: 0.6, gain: 0.13})
  },
}

export function playInkTrailSound({name, distance}) {
  if (!audioReady()) return
  sounds[name]?.(distance)
}
