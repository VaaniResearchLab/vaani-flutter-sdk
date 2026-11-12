import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'models.dart';
import 'vaani_client.dart';

/// A push event from the session WebSocket
/// (`agent_ready`, `agent_timeout`, `session_ended`, ...).
class VaaniSessionEvent {
  /// Creates an event.
  const VaaniSessionEvent({required this.type, this.raw = const {}});

  /// Parses a WebSocket frame. Unknown shapes become type `unknown`.
  factory VaaniSessionEvent.fromFrame(dynamic frame) {
    try {
      final data = jsonDecode(frame is String ? frame : utf8.decode(frame as List<int>));
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        final type = (map['type'] ?? map['event'] ?? map['status'] ?? 'unknown').toString();
        return VaaniSessionEvent(type: type, raw: map);
      }
    } catch (_) {
      // Not JSON; surface as unknown.
    }
    return VaaniSessionEvent(type: 'unknown', raw: {'frame': frame.toString()});
  }

  /// Event name.
  final String type;

  /// Full decoded payload.
  final Map<String, dynamic> raw;

  /// The agent joined the room.
  bool get isAgentReady => type == 'agent_ready';

  /// The agent failed to join in time.
  bool get isAgentTimeout => type == 'agent_timeout';

  /// The session ended (by the agent, expiry, or explicit end).
  bool get isSessionEnded => type == 'session_ended';

  @override
  String toString() => 'VaaniSessionEvent($type)';
}

/// `/api/webrtc/session/*` endpoints: create → connect → (events) → disconnect.
class VaaniSessions {
  /// Created by [VaaniClient]; use `client.sessions`.
  VaaniSessions(this._client);

  final VaaniClient _client;

  /// `POST /api/webrtc/session/create`.
  ///
  /// [gracePeriod] is the reconnection window (0–3600 s); [sessionTtl] the
  /// session lifetime (60–86400 s, server default 30 min).
  Future<WebRtcSession> create({
    required String agentId,
    VaaniUiType uiType = VaaniUiType.fullpage,
    Duration? gracePeriod,
    Duration? sessionTtl,
    String? initialMessage,
    Map<String, dynamic> metadata = const {},
  }) async {
    final body = <String, dynamic>{
      'agent_id': agentId,
      'ui_type': uiType.value,
      'metadata': metadata,
      if (gracePeriod != null) 'grace_period': gracePeriod.inSeconds,
      if (sessionTtl != null) 'session_ttl': sessionTtl.inSeconds,
      'initial_message': ?initialMessage,
    };
    return WebRtcSession.fromJson(
        await _client.request('POST', '/api/webrtc/session/create', body: body));
  }

  /// `POST /api/webrtc/session/connect` — exchanges the session token for
  /// LiveKit credentials. The backend dispatches the agent at this point.
  Future<WebRtcSessionConnect> connect(String sessionToken) async =>
      WebRtcSessionConnect.fromJson(await _client.request(
          'POST', '/api/webrtc/session/connect',
          body: {'session_token': sessionToken}));

  /// `GET /api/webrtc/session/status/{token}`.
  Future<WebRtcSessionStatus> get(String sessionToken) async => WebRtcSessionStatus.fromJson(
      await _client.request('GET', '/api/webrtc/session/status/${Uri.encodeComponent(sessionToken)}'));

  /// `POST /api/webrtc/session/disconnect`.
  ///
  /// With [explicitEnd] false the session enters its grace period and can be
  /// reconnected; true ends it immediately.
  Future<WebRtcSessionStatus> disconnect(String sessionToken, {bool explicitEnd = false}) async =>
      WebRtcSessionStatus.fromJson(await _client.request(
          'POST', '/api/webrtc/session/disconnect',
          body: {'session_token': sessionToken, 'explicit_end': explicitEnd}));

  /// WebSocket URL for real-time session events.
  Uri wsUrl(String sessionToken) {
    final base = _client.baseUrl
        .replaceFirst(RegExp('^https://'), 'wss://')
        .replaceFirst(RegExp('^http://'), 'ws://');
    return Uri.parse('$base/api/webrtc/session/ws/${Uri.encodeComponent(sessionToken)}');
  }

  /// Opens the session WebSocket and streams decoded events.
  ///
  /// Cancelling the subscription closes the socket.
  Stream<VaaniSessionEvent> events(String sessionToken) {
    WebSocketChannel? channel;
    StreamSubscription<dynamic>? sub;
    late final StreamController<VaaniSessionEvent> controller;
    controller = StreamController<VaaniSessionEvent>(
      onListen: () {
        channel = WebSocketChannel.connect(wsUrl(sessionToken));
        sub = channel!.stream.listen(
          (frame) => controller.add(VaaniSessionEvent.fromFrame(frame)),
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onCancel: () async {
        await sub?.cancel();
        await channel?.sink.close();
      },
    );
    return controller.stream;
  }

  /// create + connect in one call, returning LiveKit credentials that carry
  /// the session token.
  Future<VaaniRoomCredentials> createAndConnect({
    required String agentId,
    VaaniUiType uiType = VaaniUiType.fullpage,
    Duration? gracePeriod,
    Duration? sessionTtl,
    String? initialMessage,
    Map<String, dynamic> metadata = const {},
  }) async {
    final session = await create(
      agentId: agentId,
      uiType: uiType,
      gracePeriod: gracePeriod,
      sessionTtl: sessionTtl,
      initialMessage: initialMessage,
      metadata: metadata,
    );
    final lk = await connect(session.sessionToken);
    return VaaniRoomCredentials(
      serverUrl: lk.lkUrl,
      participantToken: lk.lkToken,
      roomName: lk.roomName,
      sessionToken: session.sessionToken,
    );
  }
}
