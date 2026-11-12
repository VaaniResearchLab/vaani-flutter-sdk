# Getting started

This guide takes you from an empty Flutter app to a working voice call with a Vaani agent.

## Requirements

| | Minimum | Why |
|---|---|---|
| Flutter / Dart | 3.38 / 3.10 | Required by `livekit_client` 2.13 |
| iOS | 13.0 | LiveKit's WebRTC build |
| Android | minSdk 21 | LiveKit's WebRTC build |
| Vaani | An API key and an agent ID | Both come from [app.vaanivoice.ai](https://app.vaanivoice.ai) |

To get an API key, go to **Settings → API Keys → Generate API Key** in the Vaani dashboard. The key is shown only once.

## 1. Add the dependency

```yaml
dependencies:
  vaani_flutter_sdk:
    path: ../vaani-flutter-sdk   # or git: / hosted once published
```

`livekit_client` comes along as a transitive dependency. You only need to import it yourself to use the raw LiveKit `Room`.

## 2. Platform setup

### iOS: `ios/Runner/Info.plist`

```xml
<key>NSMicrophoneUsageDescription</key>
<string>$(PRODUCT_NAME) uses the microphone to talk to the voice assistant.</string>
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

`UIBackgroundModes: audio` keeps the call alive when the app goes to the background. Leave it out if calls should stop when the user leaves the app.

### Android: `android/app/src/main/AndroidManifest.xml`

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

You don't need to request the microphone permission yourself. WebRTC asks for it the first time `start()` turns the mic on. That was verified on Android 14 and iOS 26.

## 3. Pass credentials at build time

Don't hard-code keys. Use `--dart-define` or a git-ignored defines file:

```json
// vaani_defines.json  (add to .gitignore)
{ "VAANI_API_KEY": "vaani_...", "VAANI_AGENT_ID": "<agent uuid>" }
```

```dart
const apiKey = String.fromEnvironment('VAANI_API_KEY');
const agentId = String.fromEnvironment('VAANI_AGENT_ID');
```

```bash
flutter run --dart-define-from-file=vaani_defines.json
```

> A key compiled into an app binary can be extracted. This is fine for development. Before shipping, move dispatch to your backend; see [Dispatch and credentials](dispatch-and-credentials.md#production-dispatch-from-your-backend).

## 4. Make a call

```dart
import 'package:flutter/material.dart';
import 'package:vaani_flutter_sdk/vaani_flutter_sdk.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});
  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  late final VaaniVoiceSession session = VaaniVoiceSession.withApiKey(
    apiKey: const String.fromEnvironment('VAANI_API_KEY'),
    agentId: const String.fromEnvironment('VAANI_AGENT_ID'),
    dispatchOptions: const WebRtcDispatchOptions(primaryLanguage: 'en'),
  );

  @override
  void initState() {
    super.initState();
    session.start().catchError((Object e) {
      // VaaniException subclasses tell you what went wrong; see troubleshooting.md
    });
  }

  @override
  void dispose() {
    session.dispose(); // ends the call if it's still running
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: session,
        builder: (context, _) => Scaffold(
          body: Center(child: Text(session.state.name)),
          floatingActionButton: FloatingActionButton(
            onPressed: session.end,
            child: const Icon(Icons.call_end),
          ),
        ),
      );
}
```

`start()` completes once the room is joined. `state` moves to `active` when the agent arrives, usually within a couple of seconds.

## 5. Run the example app

The repo ships a complete call screen with transcripts, a mute button and speaking indicators:

```bash
cd example
flutter create --platforms=android,ios .   # once: generates ios/ and android/
# add the permissions from step 2 to the generated files
flutter run --dart-define-from-file=vaani_defines.json
```

## Next

- [Voice sessions](voice-session.md): everything the session exposes for building a call UI.
- [Dispatch and credentials](dispatch-and-credentials.md): the two dispatch flows and the production setup.
