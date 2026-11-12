import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException, HandshakeException;

import 'package:http/http.dart' as http;

import 'exceptions.dart';
import 'models.dart';
import 'sessions.dart';

/// Default production API host.
const String vaaniDefaultBaseUrl = 'https://api.vaanivoice.ai';

/// HTTP client for the Vaani External API, authenticated with `X-API-Key`.
///
/// ```dart
/// final client = VaaniClient(apiKey: 'vaani_...');
/// final creds = await client.dispatchWebRtc(agentId: '...');
/// ```
///
/// Call [close] when done if you did not pass your own [http.Client].
class VaaniClient {
  /// Creates a client.
  ///
  /// [httpClient] is injectable for tests and custom transports; when given,
  /// [close] will not close it.
  VaaniClient({
    required String apiKey,
    String baseUrl = vaaniDefaultBaseUrl,
    this.timeout = const Duration(seconds: 30),
    http.Client? httpClient,
  })  : assert(apiKey.isNotEmpty, 'apiKey must not be empty'),
        _apiKey = apiKey,
        baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null {
    sessions = VaaniSessions(this);
  }

  final String _apiKey;
  final http.Client _http;
  final bool _ownsHttp;

  /// API base URL without trailing slash.
  final String baseUrl;

  /// Per-request timeout.
  final Duration timeout;

  /// WebRTC session-flow endpoints (`/api/webrtc/session/*`).
  late final VaaniSessions sessions;

  /// `GET /api/health`.
  Future<HealthResponse> health() async =>
      HealthResponse.fromJson(await request('GET', '/api/health'));

  /// `POST /api/trigger-call/` with `medium: webrtc`.
  ///
  /// Dispatches [agentId] into a fresh LiveKit room and returns the
  /// participant token, room name and server URL.
  Future<TriggerCallResponse> triggerWebRtcCall({
    required String agentId,
    WebRtcDispatchOptions options = const WebRtcDispatchOptions(),
  }) async {
    final body = <String, dynamic>{
      'agent_id': agentId,
      'medium': VaaniCallMedium.webrtc.value,
      'metadata': options.metadata,
      if (options.modifyAgent != null) 'modify_agent': options.modifyAgent!.toJson(),
      if (options.voiceGender != null) 'voice_gender': options.voiceGender!.value,
      if (options.primaryLanguage != null) 'primary_language': options.primaryLanguage,
      if (options.secondaryLanguage != null) 'secondary_language': options.secondaryLanguage,
      if (options.welcomeMessage != null) 'welcome_message': options.welcomeMessage,
      if (options.welcomeInterruptible != null)
        'welcome_interruptible': options.welcomeInterruptible,
      if (options.bgNoiseEnabled != null) 'bg_noise_enabled': options.bgNoiseEnabled,
      if (options.bgNoiseVolume != null) 'bg_noise_volume': options.bgNoiseVolume,
      if (options.voiceSpeed != null) 'voice_speed': options.voiceSpeed,
    };
    return TriggerCallResponse.fromJson(await request('POST', '/api/trigger-call/', body: body));
  }

  /// `POST /api/trigger-call/` with `medium: telephony` (outbound phone call).
  Future<TriggerCallResponse> triggerTelephonyCall({
    required String agentId,
    required TelephonyCallOptions options,
  }) async {
    final body = <String, dynamic>{
      'agent_id': agentId,
      'medium': VaaniCallMedium.telephony.value,
      'metadata': options.metadata,
      'contact_number': options.contactNumber,
      'name': options.name,
      if (options.voice != null && options.voice!.isNotEmpty) 'voice': options.voice,
      if (options.outboundNumber != null) 'outbound_number': options.outboundNumber,
      if (options.sipTrunkId != null) 'sip_trunk_id': options.sipTrunkId,
      if (options.testMode != null) 'test_mode': options.testMode,
      if (options.dndCheckSkipped != null) 'dnd_check_skipped': options.dndCheckSkipped,
      if (options.bypassTrai != null) 'bypass_trai': options.bypassTrai,
      if (options.modifyAgent != null) 'modify_agent': options.modifyAgent!.toJson(),
    };
    return TriggerCallResponse.fromJson(await request('POST', '/api/trigger-call/', body: body));
  }

  /// Dispatches [agentId] via trigger-call and returns LiveKit credentials.
  ///
  /// Throws [VaaniException] if the response lacks a token, room or URL.
  Future<VaaniRoomCredentials> dispatchWebRtc({
    required String agentId,
    WebRtcDispatchOptions options = const WebRtcDispatchOptions(),
  }) async {
    final r = await triggerWebRtcCall(agentId: agentId, options: options);
    if (r.token == null || r.roomName == null || r.connectionUrl == null) {
      throw const VaaniException(
          'trigger-call response is missing token, room_name or connection_url');
    }
    return VaaniRoomCredentials(
      serverUrl: r.connectionUrl!,
      participantToken: r.token!,
      roomName: r.roomName!,
      liveCaptionsUrl: r.liveCaptionsUrl,
      agentName: r.agentName,
    );
  }

  /// Sends an authenticated JSON request and returns the decoded body.
  ///
  /// Public so advanced callers can reach endpoints this SDK doesn't wrap yet.
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final req = http.Request(method, uri)
      ..headers['X-API-Key'] = _apiKey
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }

    final http.Response res;
    try {
      res = await _http.send(req).then(http.Response.fromStream).timeout(timeout);
    } on TimeoutException {
      throw const VaaniTimeoutException();
    } on SocketException catch (e) {
      throw VaaniConnectionException('Could not connect to Vaani API: ${e.message}');
    } on HandshakeException catch (e) {
      throw VaaniConnectionException('TLS handshake failed: ${e.message}');
    } on http.ClientException catch (e) {
      throw VaaniConnectionException('Could not connect to Vaani API: ${e.message}');
    }

    if (res.statusCode >= 400) {
      throw vaaniExceptionForStatus(res.statusCode, _errorDetail(res));
    }
    if (res.body.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return <String, dynamic>{'data': decoded};
  }

  /// Frees the underlying HTTP client if this instance created it.
  void close() {
    if (_ownsHttp) _http.close();
  }

  static String _errorDetail(http.Response res) {
    try {
      final data = jsonDecode(res.body);
      if (data is Map) {
        final detail = data['detail'] ?? data['message'];
        if (detail != null) return detail is String ? detail : jsonEncode(detail);
      }
    } catch (_) {
      // Non-JSON error body; fall through to raw text.
    }
    return res.body.isEmpty ? 'HTTP ${res.statusCode}' : res.body;
  }
}
