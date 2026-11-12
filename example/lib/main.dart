// Flutter 3.47+ moves Material to package:material_ui; keep the framework
// import so the example still builds on the SDK's minimum (Flutter 3.38).
// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vaani_flutter_sdk/vaani_flutter_sdk.dart';

// Pass these at build time; never hard-code a real key:
//   flutter run --dart-define=VAANI_API_KEY=vaani_... --dart-define=VAANI_AGENT_ID=<uuid>
const _apiKey = String.fromEnvironment('VAANI_API_KEY');
const _agentId = String.fromEnvironment('VAANI_AGENT_ID');

void main() => runApp(const MaterialApp(home: VoiceDemo()));

class VoiceDemo extends StatefulWidget {
  const VoiceDemo({super.key});

  @override
  State<VoiceDemo> createState() => _VoiceDemoState();
}

class _VoiceDemoState extends State<VoiceDemo> {
  VaaniVoiceSession? _session;
  StreamSubscription<VaaniTranscript>? _transcriptSub;
  final _lines = <String, VaaniTranscript>{};

  Future<void> _start() async {
    final session = VaaniVoiceSession.withApiKey(
      apiKey: _apiKey,
      agentId: _agentId,
      dispatchOptions: const WebRtcDispatchOptions(
        primaryLanguage: 'en',
        welcomeMessage: 'Hi! How can I help you today?',
      ),
    );
    _transcriptSub = session.transcripts.listen((t) => setState(() => _lines[t.segmentId] = t));
    setState(() {
      _session = session;
      _lines.clear();
    });
    try {
      await session.start();
    } on VaaniException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _stop() async {
    final s = _session;
    if (s == null) return;
    await _transcriptSub?.cancel();
    await s.end();
    await s.dispose();
    setState(() => _session = null);
  }

  @override
  void dispose() {
    unawaited(_stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_apiKey.isEmpty || _agentId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Set VAANI_API_KEY and VAANI_AGENT_ID via --dart-define')),
      );
    }
    final session = _session;
    return Scaffold(
      appBar: AppBar(title: const Text('Vaani voice')),
      body: session == null
          ? Center(
              child: FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.call),
                label: const Text('Talk to agent'),
              ),
            )
          : ListenableBuilder(
              listenable: session,
              builder: (context, _) => Column(
                children: [
                  ListTile(
                    title: Text('State: ${session.state.name}'),
                    subtitle: Text('Room: ${session.roomName ?? '—'}'),
                  ),
                  ListTile(
                    dense: true,
                    title: Text(
                      'You: ${session.isUserSpeaking ? 'speaking' : 'silent'}'
                      '   ·   Agent: ${session.isAgentSpeaking ? 'speaking' : 'silent'}',
                    ),
                    subtitle: LinearProgressIndicator(value: session.userAudioLevel.clamp(0, 1)),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final t in _lines.values)
                          Align(
                            alignment: t.fromAgent ? Alignment.centerLeft : Alignment.centerRight,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                t.text,
                                style: TextStyle(color: t.isFinal ? null : Colors.grey),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton.filledTonal(
                          onPressed: () =>
                              session.setMicrophoneEnabled(!session.isMicrophoneEnabled),
                          icon: Icon(session.isMicrophoneEnabled ? Icons.mic : Icons.mic_off),
                        ),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: Colors.red),
                          onPressed: _stop,
                          icon: const Icon(Icons.call_end),
                          label: const Text('End'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
