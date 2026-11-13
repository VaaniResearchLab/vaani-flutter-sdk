# Contributing

## Setup

```bash
flutter pub get
flutter analyze        # must be clean; public_member_api_docs is enforced
flutter test           # unit tests, no network
```

Run a single test:

```bash
flutter test test/vaani_client_test.dart
flutter test --plain-name "maps HTTP 401"
```

## Layout

```
lib/
  vaani_flutter_sdk.dart        public exports
  src/vaani_client.dart         HTTP layer
  src/sessions.dart             /api/webrtc/session/* + WebSocket events
  src/models.dart               request/response models
  src/exceptions.dart           typed errors + status mapping
  src/credentials_provider.dart dispatch abstraction
  src/vaani_voice_session.dart  LiveKit session wrapper
  src/vaani_token_source.dart   adapter for LiveKit's agent Session
  src/audio_options.dart        mic voice processing
test/                           MockClient-based unit tests
example/                        demo app (platform folders generated, not curated)
docs/                           these guides
```

## Conventions

- **Match the Python SDK on the wire.** Endpoint paths, JSON field names and error mapping come from `vaani-sdk`. Read its source before adding an endpoint, and update [the mapping table](python-sdk-mapping.md).
- **Include optional fields only when they're non-null,** as the Python `to_dict()` methods do. Tests assert exact JSON bodies.
- **Import `livekit_client` as `lk`** inside `lib/src`. It exports names that clash (`ConnectionState`, `Session`, `SessionError`).
- **Prefix public types with `Vaani`,** unless they mirror a Python model name.
- **Inject `http.Client` in tests** through `VaaniClient(httpClient: MockClient(...))`. Nothing may hit the network.

## Syncing with a new Python SDK release

```bash
mkdir -p /tmp/vaani-diff && cd /tmp/vaani-diff
for v in OLD NEW; do pip download --no-deps --no-binary :all: vaani-sdk==$v; done
# unpack both, then:
diff -ru vaani_sdk-OLD/vaani_sdk vaani_sdk-NEW/vaani_sdk
```

Port changes to trigger-call, the session endpoints, models and errors. Ignore the admin endpoints. Bump the version reference in `README.md`, `docs/architecture.md` and `docs/python-sdk-mapping.md`, and add a CHANGELOG entry.

## Testing against the live API

`VaaniVoiceSession` isn't unit-tested, because it needs a real LiveKit room. Test it live with the example app:

```bash
cd example
cp vaani_defines.json.example vaani_defines.json   # or create it; it's git-ignored
flutter run --dart-define-from-file=vaani_defines.json
```

| Target | Voice works? | Notes |
|---|---|---|
| iOS Simulator | ✓ | Uses the Mac mic |
| Physical Android phone | ✓ | `adb -s <serial> install -r build/app/outputs/flutter-apk/app-debug.apk` |
| Android emulator on macOS | ✗ (voice in) | Dispatch, agent audio and transcripts work; the user's voice doesn't reach the agent. Use a phone |
| Physical iPhone | Not yet tested | Needs a signing team in Xcode |

Each test call dispatches a real agent and may use wallet credit.

Before a release, check on a real device:
- [ ] The agent greets, and its transcript appears once
- [ ] Your speech appears on the right and the agent replies
- [ ] Mute and unmute; the agent stops and resumes hearing you
- [ ] Speakerphone: the agent doesn't respond to itself (echo cancellation)
- [ ] End returns to idle; no agent is left running

## API reference

```bash
dart doc --output doc/api
open doc/api/index.html
```

`doc/api/` is generated output and git-ignored.
