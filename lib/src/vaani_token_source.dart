import 'package:livekit_client/livekit_client.dart' as lk;

import 'credentials_provider.dart';
import 'models.dart';

/// Adapts a Vaani dispatch to LiveKit's [lk.TokenSourceFixed], so it works
/// with LiveKit's own agent API:
///
/// ```dart
/// final source = VaaniTokenSource(TriggerCallCredentialsProvider(
///   client: VaaniClient(apiKey: key),
///   agentId: agentId,
/// ));
/// final session = lk.Session.fromFixedTokenSource(source);
/// await session.start();
/// ```
///
/// Each [fetch] dispatches the agent again into a new room. Use
/// [VaaniVoiceSession] instead if you want the session flow's
/// disconnect/grace-period handling done for you.
class VaaniTokenSource implements lk.TokenSourceFixed {
  /// Wraps [provider].
  VaaniTokenSource(this.provider);

  /// Underlying dispatch.
  final VaaniCredentialsProvider provider;

  VaaniRoomCredentials? _last;

  /// Credentials from the most recent [fetch] (room name, session token, ...).
  VaaniRoomCredentials? get lastCredentials => _last;

  @override
  Future<lk.TokenSourceResponse> fetch() async {
    final c = await provider.fetchCredentials();
    _last = c;
    return lk.TokenSourceResponse(
      serverUrl: c.serverUrl,
      participantToken: c.participantToken,
      roomName: c.roomName,
    );
  }

  /// Releases the last dispatch (ends a session-flow session). Call after
  /// ending the LiveKit session.
  Future<void> release({bool explicitEnd = true}) async {
    final c = _last;
    if (c != null) await provider.release(c, explicitEnd: explicitEnd);
  }
}
