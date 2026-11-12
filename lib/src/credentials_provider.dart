import 'models.dart';
import 'vaani_client.dart';

/// Produces LiveKit credentials for a Vaani agent's room.
///
/// The two built-in providers call the Vaani API straight from the app with
/// an API key. That is convenient for prototypes, but anything shipped in a
/// mobile binary can be extracted. For production, implement this against
/// your own backend: it holds the Vaani API key, dispatches the agent, and
/// returns only the LiveKit URL, token and room name to the app.
abstract class VaaniCredentialsProvider {
  /// Const constructor for subclasses.
  const VaaniCredentialsProvider();

  /// Wraps a callback (e.g. a call to your own backend) as a provider.
  const factory VaaniCredentialsProvider.custom(
      Future<VaaniRoomCredentials> Function() fetch) = _CallbackProvider;

  /// Dispatches the agent and returns room credentials.
  Future<VaaniRoomCredentials> fetchCredentials();

  /// Called when the voice session ends. Session-flow providers use it to
  /// end the Vaani session; the default does nothing.
  Future<void> release(VaaniRoomCredentials credentials, {required bool explicitEnd}) async {}
}

class _CallbackProvider extends VaaniCredentialsProvider {
  const _CallbackProvider(this._fetch);
  final Future<VaaniRoomCredentials> Function() _fetch;

  @override
  Future<VaaniRoomCredentials> fetchCredentials() => _fetch();
}

/// Dispatches via `POST /api/trigger-call/` with `medium: webrtc`.
class TriggerCallCredentialsProvider extends VaaniCredentialsProvider {
  /// Creates a trigger-call provider.
  const TriggerCallCredentialsProvider({
    required this.client,
    required this.agentId,
    this.options = const WebRtcDispatchOptions(),
  });

  /// Authenticated client.
  final VaaniClient client;

  /// Agent UUID (or name).
  final String agentId;

  /// Voice, language and greeting options.
  final WebRtcDispatchOptions options;

  @override
  Future<VaaniRoomCredentials> fetchCredentials() =>
      client.dispatchWebRtc(agentId: agentId, options: options);
}

/// Dispatches via the session flow: `session/create` then `session/connect`.
///
/// Supports reconnection grace periods and session events, and ends the
/// Vaani session on [release].
class SessionCredentialsProvider extends VaaniCredentialsProvider {
  /// Creates a session-flow provider.
  const SessionCredentialsProvider({
    required this.client,
    required this.agentId,
    this.uiType = VaaniUiType.fullpage,
    this.gracePeriod,
    this.sessionTtl,
    this.initialMessage,
    this.metadata = const {},
  });

  /// Authenticated client.
  final VaaniClient client;

  /// Agent UUID (or name).
  final String agentId;

  /// Display mode reported to the backend.
  final VaaniUiType uiType;

  /// Reconnection window.
  final Duration? gracePeriod;

  /// Session lifetime.
  final Duration? sessionTtl;

  /// Message injected into the agent's context at session start.
  final String? initialMessage;

  /// Key-value data forwarded to the agent.
  final Map<String, dynamic> metadata;

  @override
  Future<VaaniRoomCredentials> fetchCredentials() => client.sessions.createAndConnect(
        agentId: agentId,
        uiType: uiType,
        gracePeriod: gracePeriod,
        sessionTtl: sessionTtl,
        initialMessage: initialMessage,
        metadata: metadata,
      );

  @override
  Future<void> release(VaaniRoomCredentials credentials, {required bool explicitEnd}) async {
    final token = credentials.sessionToken;
    if (token == null) return;
    await client.sessions.disconnect(token, explicitEnd: explicitEnd);
  }
}
