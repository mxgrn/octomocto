// Sounds for the train game, made with the Web Audio API (no sound files).

let context = null

// Browsers start audio only after a user gesture, so call this on a click.
export function unlockAudio() {
  context ||= new AudioContext()
  if (context.state === "suspended") context.resume()
}

// Play one tone with a short fade in and a fade out.
function tone({type = "sine", freq, freqEnd, start = 0, duration, gain, attack = 0.005, filter}) {
  const t = context.currentTime + start
  const osc = context.createOscillator()
  const amp = context.createGain()

  osc.type = type
  osc.frequency.setValueAtTime(freq, t)
  if (freqEnd) osc.frequency.exponentialRampToValueAtTime(freqEnd, t + duration)

  amp.gain.setValueAtTime(0.0001, t)
  amp.gain.exponentialRampToValueAtTime(gain, t + attack)
  amp.gain.exponentialRampToValueAtTime(0.0001, t + duration)

  let node = osc
  if (filter) {
    const lowpass = context.createBiquadFilter()
    lowpass.type = "lowpass"
    lowpass.frequency.value = filter
    node = node.connect(lowpass)
  }
  node.connect(amp).connect(context.destination)
  osc.start(t)
  osc.stop(t + duration + 0.05)
}

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
  if (!context) return
  sounds[name]?.()
}
