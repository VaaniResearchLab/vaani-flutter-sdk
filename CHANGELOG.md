## 0.1.0

- Initial release: `VaaniClient` (health, trigger-call, WebRTC sessions),
  `VaaniVoiceSession` (dispatch + LiveKit room), typed exceptions.
- Synced with Python `vaani-sdk` 0.3.2: `TelephonyCallOptions.bypassTrai`,
  `TriggerCallResponse.dispatchId` / `callDbId`.
- Fixed duplicate transcript lines when an agent publishes both legacy
  transcription events and `lk.transcription` text streams.
- Example app: generated iOS/Android projects with microphone permissions.
- `VaaniVoiceSession.isUserSpeaking`, `isAgentSpeaking`, `userAudioLevel`
  (server-reported speaking state; shown in the example app).
- Verified live: iOS Simulator (iOS 26.5) and a physical Android 14 phone
  (vivo), including two-way voice and hardware AEC/NS on Android.
- `VaaniAudioOptions`: explicit echo cancellation, noise suppression, auto
  gain, high-pass filter, voice isolation and typing-noise detection (all on by
  default), plus experimental per-step `automatic`/`platform`/`software`
  processing modes. Applied to room defaults and on every mic unmute.
- Developer docs in `docs/` (getting started, architecture, dispatch,
  voice sessions, audio, troubleshooting, Python mapping, contributing).
