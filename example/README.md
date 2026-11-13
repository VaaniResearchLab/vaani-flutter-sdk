# vaani_flutter_sdk example

A call screen for a Vaani voice agent, built with `vaani_flutter_sdk`. It shows:

- Start and end a call (`VaaniVoiceSession.withApiKey`, `start()`, `end()`)
- Call state
- Live transcripts for both sides
- Mute and unmute
- Speaking indicators for you and the agent

The iOS and Android projects are included, with microphone permissions already set.

## Run it

1. Copy the credentials template and fill in your API key and agent ID (from
   [platform.vaani.dev](https://platform.vaani.dev)):

   ```bash
   cp vaani_defines.json.example vaani_defines.json   # git-ignored
   ```

2. Run on a device or simulator:

   ```bash
   flutter pub get
   flutter run --dart-define-from-file=vaani_defines.json
   ```

Each call dispatches a real agent and may use wallet credit.

Test the user's voice on a physical Android phone or the iOS Simulator. On
macOS, Android emulator mic input doesn't reach the agent. Test echo
cancellation on a real phone on speakerphone.

The API key is compiled into the app here, which is fine for development. For
production, dispatch from your backend; see
[Dispatch and credentials](../docs/dispatch-and-credentials.md#production-dispatch-from-your-backend).
