# Errors and troubleshooting

## Exceptions

Every error extends `VaaniException`, which has `message` (usually the API's `detail`) and `statusCode`.

| Exception | Status | Usual cause | What to do |
|---|---|---|---|
| `VaaniAuthenticationException` | 401 | Wrong, revoked or empty API key | Check the key; regenerate it in the dashboard |
| `VaaniInsufficientBalanceException` | 402 | Wallet empty | Top up in the Vaani dashboard |
| `VaaniForbiddenException` | 403 | Key not allowed to do this; DND block (telephony) | Check workspace permissions |
| `VaaniNotFoundException` | 404 | Unknown agent ID, call or session | Check the agent ID |
| `VaaniSessionExpiredException` | 410 | Session ended or expired | Create a new session |
| `VaaniValidationException` | 422 | Bad parameter (e.g. `voiceSpeed` out of range) | Read `message`; it names the field |
| `VaaniRateLimitException` | 429 | Too many requests | Back off and retry |
| `VaaniServerException` | 5xx | Vaani-side error | Retry; report with `roomName` if it persists |
| `VaaniTimeoutException` | — | No response within `timeout` (30 s) | Retry; check connectivity |
| `VaaniConnectionException` | — | Offline, DNS, TLS | Check connectivity |
| `VaaniAgentTimeoutException` | — | No agent joined within `agentJoinTimeout`, or Vaani sent `agent_timeout` | Check the agent is deployed; retry |

```dart
try {
  await session.start();
} on VaaniInsufficientBalanceException {
  showTopUpPrompt();
} on VaaniException catch (e) {
  showError(e.message);
}
```

After a failure, `session.state == failed` and `session.error` holds the exception.

## "The agent can't hear me"

Work down this list:

1. **Watch `session.isUserSpeaking` while talking.**
   - It turns `true`: audio reaches the server. If the agent still doesn't respond, look at the agent side (language settings, prompt).
   - It stays `false`: the audio isn't arriving. Keep going.
2. **Mic muted?** Check `session.isMicrophoneEnabled`.
3. **Permission denied?** iOS: Settings → your app → Microphone. Android: `adb shell dumpsys package <your.app.id> | grep RECORD_AUDIO`.
4. **On the Android emulator?** On macOS, emulator mic input generally doesn't reach the agent, even when Android shows it recording. Test on a physical phone. This was confirmed in testing: the same APK failed on the emulator and worked on a real phone.
5. **On the iOS Simulator?** It uses the Mac's microphone and works. macOS must allow microphone access for the app running the simulator.

## "The agent hears itself" / echo

Speakerphone on a phone with a weak built-in echo canceller. Set `echoCancellationMode: VaaniAudioProcessing.software`; see [Audio processing](audio-processing.md).

## Every transcript line appears twice

This was fixed in 0.1.0. The session locks each speaker to one transcript source. If you still see duplicates, check you aren't subscribing to `room` transcription events yourself as well as `session.transcripts`.

## State stuck on `waitingForAgent`, then `failed`

The room was joined but no agent arrived within `agentJoinTimeout`. Check the agent ID is the agent's UUID and that the agent is deployed. Raise `agentJoinTimeout` if your agent takes long to start.

## Reading logs

### Android

```bash
adb logcat | grep -iE "flutter|FlutterWebRTCPlugin|webrtc_voice_engine|audio_record"
adb shell dumpsys audio | grep "rec "    # is the app recording, and is it silenced?
```

| Log line | Meaning |
|---|---|
| `rec start … src:VOICE_COMMUNICATION not silenced` | The app is recording the mic, and Android isn't blocking it |
| `HISTOGRAM(WebRTC.Audio.RecordedOnlyZeros): 0` | The mic delivered real audio (1 would mean pure silence) |
| `AddSendStream` / `MuteStream: APM:0` | The outgoing audio stream exists and isn't muted |
| `EnableBuiltInAEC(1)` / `EnableBuiltInNS(1)` | Hardware echo cancellation and noise suppression are on |
| `DTLS transport closed by remote` / `User-Initiated Abort` | The call's connection closed. **This also appears when your app ends the call**, so it doesn't mean the agent hung up |

### iOS

```bash
xcrun simctl launch --console-pty booted <bundle.id>   # simulator console
```

WebRTC's `stun_port.cc … failed with error 49/65` lines are harmless network probes on loopback interfaces.

## Getting help from Vaani

Include `session.roomName` (e.g. `webrtc-1794481532-5effcd48`). It identifies the call on Vaani's side.
