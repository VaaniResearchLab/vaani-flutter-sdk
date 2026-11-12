# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A pure-Dart Flutter package (no native code) for iOS and Android. It dispatches a Vaani voice agent through the Vaani External API, using an API key and an agent ID. Then it joins the resulting LiveKit room through `livekit_client`. All native and platform work, including audio, permissions and WebRTC, comes from `livekit_client`.

It ports the WebRTC and dispatch parts of the Python `vaani-sdk` 0.3.2 (https://pypi.org/project/vaani-sdk/). That package is the reference for endpoint paths, JSON field names and error semantics. Keep wire formats identical to it. When adding an endpoint, read the Python source first (`vaani_sdk/client.py`, `resources/*.py`, `models.py`).

## Commands

```bash
flutter pub get
flutter analyze
flutter test                                   # all tests
flutter test test/vaani_client_test.dart       # one file
flutter test --plain-name "maps HTTP 401"      # one test by name substring
cd example && flutter create --platforms=android,ios . && \
  flutter run --dart-define=VAANI_API_KEY=... --dart-define=VAANI_AGENT_ID=...
```

`example/` has no platform folders checked in. `flutter create .` generates them without overwriting `lib/main.dart`. After generating them, add the mic permissions listed in README.md. Minimums: Flutter 3.38 / Dart 3.10, iOS 13, Android minSdk 21. These come from `livekit_client` 2.13.

## Architecture

The layers run bottom-up. Each one depends only on the layers below it:

1. **`VaaniClient`** (`lib/src/vaani_client.dart`) is the HTTP layer. It sends the `X-API-Key` header and maps HTTP status codes to the typed `VaaniException` subclasses in `exceptions.dart`, matching the Python SDK's `_raise_for_status`. `request()` is public as an escape hatch for unwrapped endpoints. `client.sessions` (`sessions.dart`) wraps `/api/webrtc/session/*`, plus a WebSocket event stream.
2. **`VaaniCredentialsProvider`** (`credentials_provider.dart`) is the "dispatch" abstraction. `fetchCredentials()` produces `VaaniRoomCredentials` (LiveKit URL + token + room name). `release()` cleans up afterwards. There are three implementations:
   - `TriggerCallCredentialsProvider`: `POST /api/trigger-call/` with `medium: webrtc`. Nothing to release.
   - `SessionCredentialsProvider`: create → connect. `release` calls `session/disconnect`. Credentials carry `sessionToken`.
   - `.custom(fn)`: the app's own backend. This is the recommended production path, because an API key embedded in a mobile binary is extractable.
3. **Consumers of a provider:**
   - `VaaniVoiceSession` (`vaani_voice_session.dart`) is a single-use `ChangeNotifier` that owns an `lk.Room`. `start()` runs dispatch → `room.connect` → mic on → waits for the agent. It treats a participant with `ParticipantKind.AGENT` as the agent, and falls back to the first remote participant. The state machine is `VaaniVoiceSessionState`. A `_closing` flag makes concurrent end/fail paths run `_teardown` only once. Teardown always calls `provider.release`.
   - `VaaniTokenSource` adapts a provider to LiveKit's `TokenSourceFixed`, so LiveKit's own agent `Session` can be used instead.

Transcripts reach `VaaniVoiceSession.transcripts` two ways: the `lk.transcription` text-stream topic (LiveKit Agents 1.x) and legacy `TranscriptionEvent`. Each speaker is locked to whichever source delivers first, because live Vaani agents send both with unrelated segment IDs.

Mic voice processing (AEC, NS, AGC, high-pass) comes from `VaaniAudioOptions` (`audio_options.dart`). It is applied both as the room's `defaultAudioCaptureOptions` and on every `setMicrophoneEnabled` call, because unmuting recreates the capture track. Its processing-mode enum wraps LiveKit's experimental `AudioProcessingMode`; `experimental_member_use` is ignored only in that file and its test.

## Testing on devices

Android emulator mic input on macOS doesn't reach the agent, even though it records non-zero audio. Test Android voice on a physical phone (`adb -s <serial> install -r example/build/app/outputs/flutter-apk/app-debug.apk`). The iOS Simulator mic works. Build the example with `--dart-define-from-file=vaani_defines.json` (git-ignored credentials). In logcat, "DTLS transport closed by remote" also appears when the app itself disconnects, so it doesn't mean the agent hung up.

## Docs

`docs/` holds the developer guides (index: `docs/README.md`). When the public API, defaults or verified-device results change, update the matching guide, and `docs/python-sdk-mapping.md` when syncing with a new Python SDK release. `dart doc --output doc/api` generates the API reference into git-ignored `doc/api/`.

## Conventions

- Import `livekit_client` with the `as lk` prefix inside `lib/src`. It exports many common names, including `ConnectionState`, `Session` and `SessionError`.
- Public SDK types are prefixed `Vaani…` unless they mirror a Python model name (`TriggerCallResponse`, `WebRtcSession`, ...).
- Request bodies include optional fields only when non-null, as the Python `to_dict()` methods do. Tests assert exact JSON bodies.
- Tests use `package:http/testing.dart` `MockClient` injected through `VaaniClient(httpClient: ...)`. Nothing hits the network, and `VaaniVoiceSession` is not unit-tested because it needs a live LiveKit server.
- `analysis_options.yaml` enables `public_member_api_docs`, so every public member needs a doc comment.
- The Python SDK's admin endpoints (call history, transcripts, recordings, campaigns, agent CRUD) are deliberately not ported, since they belong server-side.
