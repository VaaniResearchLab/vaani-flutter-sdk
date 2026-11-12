# vaani_flutter_sdk

Flutter SDK for [Vaani](https://vaanivoice.ai) voice agents on **iOS and Android**.

You give it a Vaani API key and an agent ID. It dispatches the agent
through the Vaani External API, then joins the LiveKit room the agent was
sent to, using [`livekit_client`](https://pub.dev/packages/livekit_client).

```
VaaniClient ── POST /api/trigger-call/ (medium: webrtc) ──┐
           └── POST /api/webrtc/session/create + connect ─┤→ VaaniRoomCredentials
                                                          │   (server URL, token, room name)
VaaniVoiceSession ─────── livekit_client Room.connect() ◄─┘ → mic on → agent joins
```

This is a Dart port of the WebRTC and dispatch parts of the Python
[`vaani-sdk`](https://pypi.org/project/vaani-sdk/) (0.3.2). It uses the same
endpoints, field names and error types.

**Developer docs:** [docs/](docs/README.md) has guides on getting started,
architecture, dispatch and credentials, voice sessions, audio processing,
troubleshooting and the Python SDK mapping. Run `dart doc --output doc/api`
for the API reference.

## Install

```yaml
dependencies:
  vaani_flutter_sdk:
    path: ../vaani-flutter-sdk   # or a git: / hosted reference once published
```

Requires Flutter ≥ 3.38 / Dart ≥ 3.10 (inherited from `livekit_client` 2.13).

### iOS (`ios/Runner/Info.plist`, deployment target ≥ 13.0)

```xml
<key>NSMicrophoneUsageDescription</key>
<string>$(PRODUCT_NAME) uses the microphone to talk to the voice assistant.</string>
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

### Android (`android/app/src/main/AndroidManifest.xml`, minSdk ≥ 21)

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
```

LiveKit asks for the microphone permission when the mic is first enabled.

## Quick start

```dart
import 'package:vaani_flutter_sdk/vaani_flutter_sdk.dart';

final session = VaaniVoiceSession.withApiKey(
  apiKey: 'vaani_...',
  agentId: 'd62cc9bd-2f51-4581-9f38-6c3b7d58a988',
  dispatchOptions: const WebRtcDispatchOptions(
    primaryLanguage: 'en',
    welcomeMessage: 'Hi! How can I help you today?',
  ),
);

session.addListener(() => print(session.state)); // dispatching → connecting → waitingForAgent → active
session.transcripts.listen((t) => print('${t.fromAgent ? "agent" : "me"}: ${t.text}'));
session.isUserSpeaking; session.isAgentSpeaking; session.userAudioLevel; // server-reported, for UI indicators

await session.start();   // dispatch + join room + enable mic
print(session.roomName); // LiveKit room the agent was dispatched into

await session.setMicrophoneEnabled(false);
await session.end();
await session.dispose();
```

`VaaniVoiceSession` is a `ChangeNotifier`, so it works with `ListenableBuilder`.
`session.room` is the raw LiveKit `Room` if you need tracks, RPC or data
messages. See [example/lib/main.dart](example/lib/main.dart) for a full screen.

## Echo cancellation and noise suppression

`VaaniVoiceSession` sets the microphone's voice processing explicitly through
`audioOptions`, so a `livekit_client` upgrade can't change it silently. By
default everything is on: echo cancellation, noise suppression, auto gain, a
high-pass filter, voice isolation and typing-noise detection.

```dart
VaaniVoiceSession.withApiKey(
  apiKey: key,
  agentId: agentId,
  audioOptions: const VaaniAudioOptions(
    // Some Android phones have a weak built-in echo canceller. If the agent
    // hears itself on speakerphone, force WebRTC's software one:
    echoCancellationMode: VaaniAudioProcessing.software,
  ),
);
```

| `VaaniAudioProcessing` | Effect |
|---|---|
| `automatic` (default) | Device's built-in effect when available, otherwise software |
| `platform` | iOS: Apple voice processing. Android: the phone's hardware AEC/NS |
| `software` | WebRTC's software implementation on any device |

The processing modes wrap an API that `livekit_client` marks experimental. The
on/off flags are stable. Use `VaaniAudioOptions.raw()` to turn everything off.

Verified on a vivo phone running Android 14: with the defaults, WebRTC turned
on the phone's built-in echo canceller and noise suppressor
(`EnableBuiltInAEC(1)` / `EnableBuiltInNS(1)` in logcat). Judge echo
cancellation on a real device on speakerphone; simulators and emulators
can't show it.

## Keep the API key off the device (production)

A string compiled into an iOS or Android binary can be extracted. `withApiKey`
is fine for prototypes and internal builds. In production, put the key on
your backend: the backend dispatches the agent and returns only the LiveKit
credentials.

```dart
final session = VaaniVoiceSession(
  credentialsProvider: VaaniCredentialsProvider.custom(() async {
    final res = await myApi.post('/voice/start');          // your server calls Vaani
    return VaaniRoomCredentials(
      serverUrl: res['connection_url'],
      participantToken: res['token'],
      roomName: res['room_name'],
    );
  }),
);
```

## Two dispatch flows

| | `trigger-call` (default) | Session flow (`useSessionFlow: true`) |
|---|---|---|
| Endpoints | `POST /api/trigger-call/` with `medium: webrtc` | `session/create` → `session/connect` → `session/disconnect` |
| Options | voice gender, languages, welcome message, background noise, voice speed, `modify_agent` | UI type, grace period, session TTL, initial message |
| Reconnect grace period | — | ✓ |
| Session events (`agent_ready`, `session_ended`, …) | — | ✓ via `session.sessionEvents` |
| On `end()` | leaves room | leaves room and calls `session/disconnect` |

## Lower-level API

```dart
final client = VaaniClient(apiKey: 'vaani_...');

await client.health();
final creds = await client.dispatchWebRtc(agentId: id);           // VaaniRoomCredentials
final raw   = await client.triggerWebRtcCall(agentId: id);        // TriggerCallResponse
final call  = await client.triggerTelephonyCall(                  // outbound phone call
  agentId: id,
  options: const TelephonyCallOptions(contactNumber: '+919876543210', name: 'Rahul'),
);

final s     = await client.sessions.create(agentId: id, gracePeriod: const Duration(minutes: 1));
final lk    = await client.sessions.connect(s.sessionToken);
client.sessions.events(s.sessionToken).listen(print);
await client.sessions.disconnect(s.sessionToken, explicitEnd: true);

client.close();
```

### Using LiveKit's own agent `Session`

`VaaniTokenSource` implements LiveKit's `TokenSourceFixed`:

```dart
import 'package:livekit_client/livekit_client.dart' as lk;

final source = VaaniTokenSource(TriggerCallCredentialsProvider(client: client, agentId: id));
final lkSession = lk.Session.fromFixedTokenSource(source);
await lkSession.start();
// ...
await lkSession.end();
await source.release();
```

## Errors

Every error extends `VaaniException`, which has `message` and `statusCode`:

| Exception | Cause |
|---|---|
| `VaaniAuthenticationException` | 401: bad or missing API key |
| `VaaniInsufficientBalanceException` | 402: wallet balance too low |
| `VaaniForbiddenException` | 403 |
| `VaaniNotFoundException` | 404: unknown agent, call or session |
| `VaaniSessionExpiredException` | 410: session ended or expired |
| `VaaniValidationException` | 422 |
| `VaaniRateLimitException` | 429 |
| `VaaniServerException` | 5xx |
| `VaaniTimeoutException` / `VaaniConnectionException` | network |
| `VaaniAgentTimeoutException` | agent didn't join within `agentJoinTimeout` (default 30 s) |

## Not covered yet

The Python SDK's server-side admin endpoints aren't ported: call history,
transcripts, recordings, campaigns, and agent create/update/delete. They
belong on a backend, not in a mobile app. If you need one, call
`client.request(method, path, body: ...)`.

## Development

```bash
flutter pub get
flutter analyze
flutter test
cd example && flutter create --platforms=android,ios . && flutter run \
  --dart-define=VAANI_API_KEY=vaani_... --dart-define=VAANI_AGENT_ID=<uuid>
```
