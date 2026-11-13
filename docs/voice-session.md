# Voice sessions

`VaaniVoiceSession` is the object your call screen talks to. It's a `ChangeNotifier`, so wrap your UI in `ListenableBuilder` (or use Provider or Riverpod) and read its getters.

## Creating one

```dart
// Development: API key in the app
VaaniVoiceSession.withApiKey(apiKey: key, agentId: id, /* dispatch options */);

// Production: any credentials provider
VaaniVoiceSession(credentialsProvider: myProvider);
```

| Constructor option | Default | Meaning |
|---|---|---|
| `enableMicrophone` | `true` | Publish the mic as soon as the room is joined |
| `audioOptions` | all processing on | Echo cancellation, noise suppression and more; see [Audio processing](audio-processing.md) |
| `agentJoinTimeout` | 30 s | Fail if no agent joins in time. `null` waits forever |
| `endWhenAgentLeaves` | `true` | End the call when the agent hangs up |
| `roomOptions` | SDK defaults | Advanced options for the underlying WebRTC room (`audioOptions` overrides its audio capture defaults) |

## Lifecycle

```dart
await session.start();                 // throws on dispatch or connect failure
await session.end();                   // leave room + release dispatch
await session.end(explicitEnd: false); // session flow: keep the grace period
await session.dispose();               // always call; ends the call if still running
```

`start()` completes once the room is joined, not when the agent arrives. Watch `state`:

| `state` | Show the user |
|---|---|
| `idle` | Start button |
| `dispatching`, `connecting` | "Connecting…" |
| `waitingForAgent` | "Waiting for the assistant…" |
| `active` | Live call UI |
| `reconnecting` | "Reconnecting…" (the SDK retries automatically) |
| `ended` | Call ended |
| `failed` | Error, from `session.error` |

The [architecture guide](architecture.md#state-machine) has the full state diagram.

## Getters

| Getter | Type | Notes |
|---|---|---|
| `state` | `VaaniVoiceSessionState` | See above |
| `error` | `Object?` | Set when `state == failed` |
| `credentials` | `VaaniRoomCredentials?` | After dispatch |
| `roomName` | `String?` | The room the agent was sent to. It is also the call's `call_id` in call history. Log it; Vaani support can trace calls by it |
| `agent` | `RemoteParticipant?` | The agent once it has joined |
| `isMicrophoneEnabled` | `bool` | Local mic published and unmuted |
| `isUserSpeaking` | `bool` | Server-reported: the user is speaking now |
| `isAgentSpeaking` | `bool` | Server-reported: the agent is speaking now |
| `userAudioLevel` | `double` | 0.0–1.0, server-reported |
| `room` | `Room` | The underlying WebRTC room |

`isUserSpeaking` and `userAudioLevel` are computed on the server, so they double as proof that the user's audio is arriving. They're the fastest way to diagnose "the agent can't hear me".

## Microphone

```dart
await session.setMicrophoneEnabled(false); // mute
await session.setMicrophoneEnabled(true);  // unmute (re-applies audioOptions)
```

## Transcripts

```dart
final lines = <String, VaaniTranscript>{};
session.transcripts.listen((t) {
  lines[t.segmentId] = t;   // interim updates replace earlier text with the same segmentId
  setState(() {});
});
```

| Field | Meaning |
|---|---|
| `segmentId` | Stable per utterance. Key your list by it |
| `text` | Current text |
| `isFinal` | `false` while the text is still changing (show it greyed out) |
| `fromAgent` | `true` for the agent, `false` for the user |
| `participantIdentity` | Identity of the speaker in the room |

Both the agent's speech and the user's speech come through. Transcripts are a broadcast stream, so subscribe before `start()` to catch the greeting.

## Session events (session flow only)

```dart
session.sessionEvents.listen((e) {
  if (e.isAgentReady) { /* ... */ }
  if (e.isSessionEnded) { /* the SDK also ends the call */ }
  print(e.raw);  // full payload
});
```

## Things the SDK handles for you

- Microphone permission prompts (through WebRTC).
- Echo cancellation and noise suppression (through `audioOptions`).
- Reconnection after network drops, shown as `reconnecting`.
- Ending the call when the agent leaves, the room closes, or Vaani sends `session_ended`.
- Releasing the dispatch exactly once, even if several end paths fire together.
- De-duplicating transcripts when the agent sends them over two channels.

## Going beyond the wrapper

`session.room` is the underlying WebRTC room. Use it for anything the session doesn't wrap, such as audio tracks, RPC, data messages and custom events.

If you add your own listeners to it, dispose them yourself. The session only cleans up its own.
