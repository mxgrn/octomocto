// Helpers to make game sounds with the Web Audio API (no sound files).

let context = null

// Browsers start audio only after a user gesture, so call this on a click
// or a key press.
export function unlockAudio() {
  context ||= new AudioContext()
  if (context.state === "suspended") context.resume()
}

export function audioReady() {
  return context !== null
}

// Send a source through an optional filter and a fade in and out.
function play(source, {start, duration, gain, attack, filter, filterEnd, filterType}) {
  const t = context.currentTime + start
  const amp = context.createGain()
  amp.gain.setValueAtTime(0.0001, t)
  amp.gain.exponentialRampToValueAtTime(gain, t + attack)
  amp.gain.exponentialRampToValueAtTime(0.0001, t + duration)

  let node = source
  if (filter) {
    const biquad = context.createBiquadFilter()
    biquad.type = filterType
    biquad.frequency.setValueAtTime(filter, t)
    if (filterEnd) biquad.frequency.exponentialRampToValueAtTime(filterEnd, t + duration)
    node = node.connect(biquad)
  }
  node.connect(amp).connect(context.destination)
  source.start(t)
  source.stop(t + duration + 0.05)
}

// Play one tone.
export function tone({type = "sine", freq, freqEnd, start = 0, duration, gain, attack = 0.005, filter, filterEnd, filterType = "lowpass"}) {
  const t = context.currentTime + start
  const osc = context.createOscillator()
  osc.type = type
  osc.frequency.setValueAtTime(freq, t)
  if (freqEnd) osc.frequency.exponentialRampToValueAtTime(freqEnd, t + duration)
  play(osc, {start, duration, gain, attack, filter, filterEnd, filterType})
}

// Play white noise, for example for steps and a whoosh.
export function noise({start = 0, duration, gain, attack = 0.005, filter, filterEnd, filterType = "lowpass"}) {
  const length = Math.ceil(context.sampleRate * (duration + 0.05))
  const buffer = context.createBuffer(1, length, context.sampleRate)
  const data = buffer.getChannelData(0)
  for (let i = 0; i < length; i++) data[i] = Math.random() * 2 - 1

  const source = context.createBufferSource()
  source.buffer = buffer
  play(source, {start, duration, gain, attack, filter, filterEnd, filterType})
}
