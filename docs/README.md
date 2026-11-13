# vaani_flutter_sdk developer docs

Guides for building voice-agent features with `vaani_flutter_sdk` on iOS and Android.

| Guide | Read it when |
|---|---|
| [Getting started](getting-started.md) | You're adding the SDK to an app for the first time |
| [Architecture](architecture.md) | You want to know how dispatch, the WebRTC room and the session fit together |
| [Dispatch and credentials](dispatch-and-credentials.md) | You're choosing between `trigger-call` and the session flow, or moving the API key to your backend |
| [Voice sessions](voice-session.md) | You're building the call screen: state, transcripts, mute, speaking indicators |
| [Audio processing](audio-processing.md) | You're tuning echo cancellation and noise suppression |
| [Errors and troubleshooting](troubleshooting.md) | A call fails, the agent doesn't hear you, or something looks wrong in the logs |
| [Python SDK mapping](python-sdk-mapping.md) | You know the Python `vaani-sdk` and want the Dart equivalents |
| [Contributing](contributing.md) | You're changing the SDK itself |

**API reference:** generate it locally with `dart doc` (see [Contributing](contributing.md#api-reference)). Every public symbol has a doc comment; the analyzer enforces this.

## The 30-second version

```dart
final session = VaaniVoiceSession.withApiKey(apiKey: key, agentId: agentId);
await session.start();          // dispatch → join the call → mic on
session.transcripts.listen(print);
await session.end();
await session.dispose();
```

For production, swap `withApiKey` for a [backend-backed credentials provider](dispatch-and-credentials.md#production-dispatch-from-your-backend) so the API key never ships in the app.
