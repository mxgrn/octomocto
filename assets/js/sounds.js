// Helpers to make game sounds with the Web Audio API (no sound files).

let context = null

// The two sound switches of the user menu (see the layout). Each one is a
// "true" or "false" in the browser storage, and sounds are on by default.
// "sounds" mutes all sounds of the site except the invite sound.
const muteKeys = {invites: "octo:mute-invites", sounds: "octo:mute-sounds"}

export function muted(kind) {
  try { return localStorage.getItem(muteKeys[kind]) === "true" } catch (_e) { return false }
}

export function setMuted(kind, value) {
  try { localStorage.setItem(muteKeys[kind], String(value)) } catch (_e) {}
}

// True only while the invite sound plays, so that it ignores the "sounds" switch
let invitePlaying = false
const silent = () => !invitePlaying && muted("sounds")

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
  if (silent()) return
  const t = context.currentTime + start
  const osc = context.createOscillator()
  osc.type = type
  osc.frequency.setValueAtTime(freq, t)
  if (freqEnd) osc.frequency.exponentialRampToValueAtTime(freqEnd, t + duration)
  play(osc, {start, duration, gain, attack, filter, filterEnd, filterType})
}

// Play white noise, for example for steps and a whoosh.
export function noise({start = 0, duration, gain, attack = 0.005, filter, filterEnd, filterType = "lowpass"}) {
  if (silent()) return
  const length = Math.ceil(context.sampleRate * (duration + 0.05))
  const buffer = context.createBuffer(1, length, context.sampleRate)
  const data = buffer.getChannelData(0)
  for (let i = 0; i < length; i++) data[i] = Math.random() * 2 - 1

  const source = context.createBufferSource()
  source.buffer = buffer
  play(source, {start, duration, gain, attack, filter, filterEnd, filterType})
}

// The sound of all multiplayer games when all players are ready and the
// game starts: 3 quick rising notes and a bright chord. In the games with a
// countdown, it plays with the first beep, so the first note makes a
// sweet interval with that beep (C and A).
export function gameStart() {
  ;[523, 659, 784].forEach((freq, i) => tone({type: "triangle", freq, start: i * 0.08, duration: 0.12, gain: 0.14}))
  for (const freq of [659, 784, 1047]) {
    tone({type: "triangle", freq, start: 0.24, duration: 0.5, gain: 0.07, attack: 0.01})
  }
}

// The sound of an invite from a friend. No other sound of the site is like
// it: a soft "knock, knock" on the same note, a short stop, and then a
// warm "bing": a major chord (B, D sharp, F sharp) that rolls up quickly
// and rings for a short time. The second sine of the root is a little
// out of tune, so the bell shimmers softly. Pure sine tones with slow
// starts, so that it is clear but not loud.
export function inviteSound() {
  if (!context || muted("invites")) return
  invitePlaying = true
  try {
    for (const start of [0, 0.16]) {
      tone({freq: 659, start, duration: 0.14, gain: 0.05, attack: 0.015})
    }
    tone({freq: 988, start: 0.42, duration: 0.9, gain: 0.04, attack: 0.02})
    tone({freq: 990.5, start: 0.42, duration: 0.9, gain: 0.025, attack: 0.02})
    tone({freq: 1245, start: 0.45, duration: 0.8, gain: 0.025, attack: 0.02})
    tone({freq: 1480, start: 0.48, duration: 0.7, gain: 0.018, attack: 0.02})
  } finally {
    invitePlaying = false
  }
}
