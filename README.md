# vaani_flutter_sdk

Flutter SDK for [Vaani](https://vaanivoice.ai) voice agents on **iOS and Android**.

You give it a Vaani API key and an agent ID. It dispatches the agent through
the Vaani External API, then joins the call the agent was sent to over WebRTC.

```
VaaniClient ── POST /api/trigger-call/ (medium: webrtc) ──┐
           └── POST /api/webrtc/session/create + connect ─┤→ VaaniRoomCredentials
                                                          │   (server URL, token, room name)
VaaniVoiceSession ──────────────── joins the WebRTC room ◄┘ → mic on → agent joins
```

Included: call state, live transcripts, mute, speaking indicators, echo
cancellation and noise suppression, and typed errors.

It is a Dart port of the WebRTC and dispatch parts of the Python
[`vaani-sdk`](https://pypi.org/project/vaani-sdk/) (0.3.3), with the same
endpoints, field names and error types.

**Docs:** [docs.vaanivoice.ai/flutter-sdk](https://docs.vaanivoice.ai/flutter-sdk).
The [docs/](docs/README.md) folder has longer guides: getting started,
architecture, dispatch and credentials, voice sessions, audio processing,
troubleshooting and the Python SDK mapping.

## Install

The package is not on pub.dev yet. Add it as a git dependency:

```yaml
dependencies:
  vaani_flutter_sdk:
    git:
      url: https://github.com/VaaniResearchLab/vaani-flutter-sdk.git
      ref: main
```

Or, with a local checkout, `path: ../vaani-flutter-sdk`.

Requires Flutter 3.38+ and Dart 3.10+ (required by the WebRTC dependency).

### iOS (`ios/Runner/Info.plist`, deployment target 13.0+)

```xml
<key>NSMicrophoneUsageDescription</key>
<string>$(PRODUCT_NAME) uses the microphone to talk to the voice assistant.</string>
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

`UIBackgroundModes: audio` keeps the call running in the background. Leave it
out if the call should stop when the user leaves the app.

### Android (`android/app/src/main/AndroidManifest.xml`, minSdk 21+)

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

The SDK asks for the microphone permission when the mic is first enabled.

## Authentication

Every request sends your API key as the `X-API-Key` header. Generate a key at
[platform.vaani.dev](https://platform.vaani.dev) → **Settings → API Keys**.

| `VaaniClient` parameter | Description | Default |
|---|---|---|
| `apiKey` | Your Vaani API key | *(required)* |
| `baseUrl` | Base URL of the Vaani API | `https://api.vaanivoice.ai` |
| `timeout` | Per-request timeout | 30 s |
| `httpClient` | Your own `http.Client` | a new one |

`VaaniVoiceSession.withApiKey` creates and closes its own client, so a normal
call doesn't need one.

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

await session.start();   // dispatch + join the call + enable mic
print(session.roomName); // e.g. webrtc-1794481532-5effcd48; also the call's call_id

await session.setMicrophoneEnabled(false);
await session.end();
await session.dispose();
```

`VaaniVoiceSession` is a `ChangeNotifier`, so it works with `ListenableBuilder`.
For speaking indicators use `isUserSpeaking`, `isAgentSpeaking` and
`userAudioLevel` (server-reported). A session is single-use: create a new one
per call. See [example/lib/main.dart](example/lib/main.dart) for a full call
screen.

| `state` | Meaning |
|---|---|
| `idle` | Not started |
| `dispatching` / `connecting` | Dispatching the agent / joining the call |
| `waitingForAgent` | Joined; the agent hasn't arrived yet |
| `active` | The conversation is live |
| `reconnecting` | Network dropped; reconnecting automatically |
| `ended` | Ended normally (you, the agent, or Vaani ended it) |
| `failed` | Ended because of an error; see `session.error` |

## Two dispatch flows

| | `trigger-call` (default) | Session flow (`useSessionFlow: true`) |
|---|---|---|
| Endpoints | `POST /api/trigger-call/` with `medium: webrtc` | `session/create` → `session/connect` → `session/disconnect` |
| Options | `WebRtcDispatchOptions`: voice gender, languages, welcome message, background noise, voice speed, metadata, `modifyAgent` | grace period, session TTL, initial message, metadata |
| Reconnect grace period | — | ✓ |
| Session events (`agent_ready`, `agent_timeout`, `session_ended`) | — | ✓ via `session.sessionEvents` |
| On `end()` | leaves the call | leaves the call and calls `session/disconnect` |

`withApiKey` always creates sessions with `ui_type: fullpage`. For `widget`,
pass a `SessionCredentialsProvider(client:, agentId:, uiType: VaaniUiType.widget)`
to the `VaaniVoiceSession` constructor.

See [docs/dispatch-and-credentials.md](docs/dispatch-and-credentials.md) for
every option and its range.

## Echo cancellation and noise suppression

`VaaniVoiceSession` sets the microphone's voice processing explicitly through
`audioOptions`, so a dependency upgrade can't change it silently. By default
everything is on: echo cancellation, noise suppression, auto gain, a
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

The processing modes wrap an API that the WebRTC library marks experimental.
The on/off flags are stable. Use `VaaniAudioOptions.raw()` to turn everything
off.

Verified on a vivo phone running Android 14: with the defaults, WebRTC turned
on the phone's built-in echo canceller and noise suppressor
(`EnableBuiltInAEC(1)` / `EnableBuiltInNS(1)` in logcat). Judge echo
cancellation on a real device on speakerphone; simulators and emulators
can't show it.

## Keep the API key off the device (production)

A string compiled into an iOS or Android binary can be extracted. `withApiKey`
is fine for prototypes and internal builds. In production, put the key on
your backend: the backend dispatches the agent and returns only the call
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

A backend example (Python) and session-flow cleanup through `release()` are in
[docs/dispatch-and-credentials.md](docs/dispatch-and-credentials.md#production-dispatch-from-your-backend).

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

final s      = await client.sessions.create(agentId: id, gracePeriod: const Duration(minutes: 1));
final conn   = await client.sessions.connect(s.sessionToken);     // lkUrl, lkToken, roomName
final status = await client.sessions.get(s.sessionToken);         // created | agent_ready | active | reconnecting
client.sessions.events(s.sessionToken).listen(print);
await client.sessions.disconnect(s.sessionToken, explicitEnd: true);

client.close();
```

`client.request(method, path, body:, query:)` calls any other endpoint with
the same authentication and error mapping.

## Errors

Every error extends `VaaniException`, which has `message` and `statusCode`:

| Exception | HTTP status | Cause |
|---|---|---|
| `VaaniAuthenticationException` | 401 | Invalid or missing API key |
| `VaaniInsufficientBalanceException` | 402 | Wallet balance too low |
| `VaaniForbiddenException` | 403 | Operation not allowed for this API key |
| `VaaniNotFoundException` | 404 | Unknown agent, call or session |
| `VaaniSessionExpiredException` | 410 | Session ended or expired |
| `VaaniValidationException` | 422 | Request parameters failed validation |
| `VaaniRateLimitException` | 429 | Too many requests |
| `VaaniServerException` | 5xx | Vaani server-side error |
| `VaaniTimeoutException` | — | No response within the client timeout (30 s) |
| `VaaniConnectionException` | — | Could not reach the API (offline, DNS, TLS) |
| `VaaniAgentTimeoutException` | — | Agent didn't join within `agentJoinTimeout` (default 30 s), or Vaani sent `agent_timeout` |

`start()` throws on dispatch or connection errors. Errors after that (such as
the agent timeout) set `state` to `failed` and `session.error`.

## Call history, transcripts and agent settings

This SDK runs the live call. Everything around it is done elsewhere:

| You want to | Where |
|---|---|
| Change the agent's prompt, voice, language or tools | The Vaani portal at [platform.vaani.dev](https://platform.vaani.dev). The SDK only overrides settings for one call (`WebRtcDispatchOptions`, `modifyAgent`) |
| See call history, transcripts, recordings, summaries | The portal, or from your backend with the [Python SDK](https://docs.vaanivoice.ai/sdk) / [API reference](https://docs.vaanivoice.ai/api-reference/call-history) |
| Find one call from the app | Send `session.roomName` to your backend. It is the call's `call_id` in call history, transcripts and call details |
| Run campaigns, create or delete agents | The portal, or the Python SDK from your backend |
| Show the conversation during the call | `session.transcripts` |

These features need an API key, so call them from your backend, not from the
app. `client.request(...)` can reach any endpoint if you need a one-off call.

## Development

```bash
flutter pub get
flutter analyze
flutter test
cd example && flutter run --dart-define-from-file=vaani_defines.json
```

See [docs/contributing.md](docs/contributing.md).
