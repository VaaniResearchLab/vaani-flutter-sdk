# Audio processing

Voice agents fail in two ways when audio processing is wrong. The agent hears its own voice from the speaker and answers itself, or background noise triggers it and cuts the user off. `VaaniAudioOptions` controls the processing that prevents both.

## Defaults

Everything is on:

| Option | Default | What it does |
|---|---|---|
| `echoCancellation` | on | Removes the agent's voice coming back through the mic on speakerphone |
| `noiseSuppression` | on | Removes steady background noise (fans, traffic, crowd) |
| `autoGainControl` | on | Evens out quiet and loud speakers |
| `highPassFilter` | on | Cuts low-frequency rumble. This differs from LiveKit's default, which is off |
| `voiceIsolation` | on | Platform voice isolation, where supported |
| `typingNoiseDetection` | on | Suppresses keyboard clatter, where supported |

The SDK sets these explicitly instead of inheriting LiveKit's defaults, so upgrading `livekit_client` can't change call quality silently.

## Where processing runs

```dart
const VaaniAudioOptions(
  echoCancellationMode: VaaniAudioProcessing.software,
  noiseSuppressionMode: VaaniAudioProcessing.automatic,
);
```

| Mode | iOS | Android |
|---|---|---|
| `automatic` (default) | Apple voice processing | The phone's hardware AEC/NS if it has them, otherwise WebRTC software |
| `platform` | Apple voice processing | The phone's hardware AEC/NS |
| `software` | WebRTC software | WebRTC software |

**When to change it:** Android phones vary a lot. Some built-in echo cancellers are weak, and the agent then hears itself on speakerphone. If you see that on particular devices, set `echoCancellationMode: VaaniAudioProcessing.software`. It costs a little CPU and behaves the same on every phone.

> The processing modes wrap an API that `livekit_client` marks **experimental**. They work today but may change in a future LiveKit release. The on/off flags are stable.

## Turning processing off

```dart
const VaaniAudioOptions.raw()   // every step off
```

Use this only for debugging, or when your own pipeline processes the audio. Without echo cancellation, a speakerphone call will loop.

## Server-side noise cancellation

These options run on the device. The Vaani agent pipeline may add its own noise cancellation on the server. Check your agent's configuration in the Vaani dashboard, or with Vaani. The two layers stack.

## What was verified

| Device | Result |
|---|---|
| vivo I2208, Android 14 (physical) | With the defaults, `getUserMedia(audio)` received every flag as `true`, including `googHighpassFilter` (LiveKit's own default is off), and WebRTC turned on the phone's built-in AEC and NS (`EnableBuiltInAEC(1)`, `EnableBuiltInNS(1)`). Two-way conversation worked |
| iPhone 17 Pro simulator, iOS 26.5 | Two-way conversation worked. Simulators can't show echo-cancellation quality |

**Test echo cancellation on a real phone on speakerphone in a noisy room.** Emulators and simulators route audio through the Mac and can't show it.

## Checking what was applied (Android)

```bash
adb logcat | grep -E "getUserMedia\(audio\)|EnableBuiltIn(AEC|NS)"
```

The `getUserMedia(audio)` line lists the constraints sent to WebRTC, and `EnableBuiltInAEC(1)` confirms hardware echo cancellation is on.
