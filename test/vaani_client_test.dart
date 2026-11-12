import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vaani_flutter_sdk/vaani_flutter_sdk.dart';

const _agentId = 'd62cc9bd-2f51-4581-9f38-6c3b7d58a988';

typedef _Handler = http.Response Function(http.Request req);

VaaniClient _client(_Handler handler, {List<http.Request>? log}) => VaaniClient(
      apiKey: 'vaani_test',
      baseUrl: 'https://api.example.test/',
      httpClient: MockClient((req) async {
        log?.add(req);
        return handler(req);
      }),
    );

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  group('VaaniClient', () {
    test('sends X-API-Key and strips trailing slash from base URL', () async {
      final log = <http.Request>[];
      final c = _client((_) => _json({'status': 'healthy', 'service': 'vaani-external-api'}),
          log: log);
      final h = await c.health();
      expect(h.status, 'healthy');
      expect(log.single.url.toString(), 'https://api.example.test/api/health');
      expect(log.single.headers['X-API-Key'], 'vaani_test');
    });

    test('triggerWebRtcCall sends only non-null fields', () async {
      final log = <http.Request>[];
      final c = _client(
        (_) => _json({
          'token': 'lk-jwt',
          'room_name': 'room_x',
          'agent_name': 'a',
          'connection_url': 'wss://lk.example.test',
          'live_captions_url': 'wss://captions',
        }),
        log: log,
      );
      final r = await c.triggerWebRtcCall(
        agentId: _agentId,
        options: const WebRtcDispatchOptions(
          primaryLanguage: 'en',
          voiceGender: VaaniVoiceGender.female,
          metadata: {'user_id': 'u1'},
        ),
      );
      final body = jsonDecode(log.single.body) as Map<String, dynamic>;
      expect(log.single.method, 'POST');
      expect(log.single.url.path, '/api/trigger-call/');
      expect(body, {
        'agent_id': _agentId,
        'medium': 'webrtc',
        'metadata': {'user_id': 'u1'},
        'voice_gender': 'female',
        'primary_language': 'en',
      });
      expect(r.token, 'lk-jwt');
      expect(r.roomName, 'room_x');
      expect(r.connectionUrl, 'wss://lk.example.test');
    });

    test('dispatchWebRtc maps response to room credentials', () async {
      final c = _client((_) => _json({
            'token': 't',
            'room_name': 'room_1',
            'connection_url': 'wss://lk',
          }));
      final creds = await c.dispatchWebRtc(agentId: _agentId);
      expect(creds.serverUrl, 'wss://lk');
      expect(creds.participantToken, 't');
      expect(creds.roomName, 'room_1');
      expect(creds.sessionToken, isNull);
    });

    test('dispatchWebRtc throws when LiveKit fields are missing', () async {
      final c = _client((_) => _json({'success': true}));
      expect(c.dispatchWebRtc(agentId: _agentId), throwsA(isA<VaaniException>()));
    });

    test('telephony response reads call_id from nested output', () async {
      final log = <http.Request>[];
      final c = _client(
          (_) => _json({
                'success': true,
                'output': {'call_id': 'outbound-1', 'agent_name': 'sales'},
              }),
          log: log);
      final r = await c.triggerTelephonyCall(
        agentId: _agentId,
        options: const TelephonyCallOptions(contactNumber: '+919876543210', name: 'Rahul'),
      );
      expect(r.callId, 'outbound-1');
      expect(r.agentName, 'sales');
      final body = jsonDecode(log.single.body) as Map<String, dynamic>;
      expect(body['medium'], 'telephony');
      expect(body['contact_number'], '+919876543210');
      expect(body.containsKey('voice'), isFalse);
      expect(body.containsKey('bypass_trai'), isFalse);
    });

    test('telephony 0.3.2 fields: bypass_trai, dispatch_id, call_db_id', () async {
      final log = <http.Request>[];
      final c = _client(
          (_) => _json({
                'success': true,
                'message': 'Call initiated successfully',
                'output': {
                  'agent_name': 'sales',
                  'call_id': 'outbound-1776774443-863aa698',
                  'live_captions_url': 'https://api/live-transcripts/stream/outbound-...',
                },
                'error': null,
                'live_captions_url': 'https://api/live-transcripts/stream/outbound-...',
                'room_name': 'outbound-1776774443-863aa698',
                'dispatch_id': 'dispatch-outbound-1776774443-863aa698',
                'call_db_id': 40167,
              }),
          log: log);
      final r = await c.triggerTelephonyCall(
        agentId: _agentId,
        options: const TelephonyCallOptions(
            contactNumber: '+919876543210', name: 'Rahul', bypassTrai: true),
      );
      expect(jsonDecode(log.single.body)['bypass_trai'], true);
      expect(r.callId, 'outbound-1776774443-863aa698');
      expect(r.roomName, r.callId);
      expect(r.dispatchId, 'dispatch-outbound-1776774443-863aa698');
      expect(r.callDbId, 40167);
      expect(r.liveCaptionsUrl, startsWith('https://'));
    });

    final cases = <int, Matcher>{
      401: isA<VaaniAuthenticationException>(),
      402: isA<VaaniInsufficientBalanceException>(),
      403: isA<VaaniForbiddenException>(),
      404: isA<VaaniNotFoundException>(),
      410: isA<VaaniSessionExpiredException>(),
      422: isA<VaaniValidationException>(),
      429: isA<VaaniRateLimitException>(),
      503: isA<VaaniServerException>(),
      418: isA<VaaniException>(),
    };
    cases.forEach((status, matcher) {
      test('maps HTTP $status to typed exception with detail', () async {
        final c = _client((_) => _json({'detail': 'boom $status'}, status));
        await expectLater(
          c.health(),
          throwsA(allOf(
            matcher,
            isA<VaaniException>()
                .having((e) => e.statusCode, 'statusCode', status)
                .having((e) => e.message, 'message', 'boom $status'),
          )),
        );
      });
    });

    test('maps transport errors to VaaniConnectionException', () async {
      final c = VaaniClient(
        apiKey: 'k',
        httpClient: MockClient((_) async => throw http.ClientException('offline')),
      );
      expect(c.health(), throwsA(isA<VaaniConnectionException>()));
    });

    test('maps slow responses to VaaniTimeoutException', () async {
      final c = VaaniClient(
        apiKey: 'k',
        timeout: const Duration(milliseconds: 10),
        httpClient: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return _json({});
        }),
      );
      expect(c.health(), throwsA(isA<VaaniTimeoutException>()));
    });
  });

  group('VaaniSessions', () {
    test('createAndConnect runs create then connect and keeps session token', () async {
      final log = <http.Request>[];
      final c = _client((req) {
        if (req.url.path.endsWith('/create')) {
          return _json({
            'session_token': 'sess-1',
            'session_url': 'https://app/s/sess-1',
            'expires_at': '2026-11-12T10:00:00Z',
          });
        }
        return _json({'lk_url': 'wss://lk', 'lk_token': 'jwt', 'room_name': 'room_s'});
      }, log: log);

      final creds = await c.sessions.createAndConnect(
        agentId: _agentId,
        gracePeriod: const Duration(minutes: 1),
        metadata: {'user_id': 'u'},
      );

      expect(log.map((r) => r.url.path),
          ['/api/webrtc/session/create', '/api/webrtc/session/connect']);
      expect(jsonDecode(log.first.body), {
        'agent_id': _agentId,
        'ui_type': 'fullpage',
        'metadata': {'user_id': 'u'},
        'grace_period': 60,
      });
      expect(jsonDecode(log.last.body), {'session_token': 'sess-1'});
      expect(creds.sessionToken, 'sess-1');
      expect(creds.roomName, 'room_s');
    });

    test('disconnect sends explicit_end and parses status', () async {
      final log = <http.Request>[];
      final c = _client(
          (_) => _json({
                'status': 'ended',
                'expires_at': '2026-11-12T10:00:00Z',
                'ui_type': 'fullpage',
                'room_name': 'room_s',
                'agent_id': _agentId,
                'client_id': 'c1',
              }),
          log: log);
      final s = await c.sessions.disconnect('sess-1', explicitEnd: true);
      expect(jsonDecode(log.single.body), {'session_token': 'sess-1', 'explicit_end': true});
      expect(s.status, 'ended');
      expect(s.gracePeriodEndsAt, isNull);
    });

    test('wsUrl swaps scheme to wss', () {
      final c = _client((_) => _json({}));
      expect(c.sessions.wsUrl('abc').toString(),
          'wss://api.example.test/api/webrtc/session/ws/abc');
    });

    test('session event frames parse', () {
      final e = VaaniSessionEvent.fromFrame('{"type":"agent_ready"}');
      expect(e.isAgentReady, isTrue);
      expect(VaaniSessionEvent.fromFrame('not json').type, 'unknown');
    });
  });

  group('credential providers', () {
    test('SessionCredentialsProvider.release disconnects the session', () async {
      final log = <http.Request>[];
      final c = _client(
          (_) => _json({
                'status': 'ended',
                'expires_at': '2026-11-12T10:00:00Z',
                'ui_type': 'fullpage',
                'room_name': 'r',
                'agent_id': _agentId,
                'client_id': 'c',
              }),
          log: log);
      final p = SessionCredentialsProvider(client: c, agentId: _agentId);
      await p.release(
        const VaaniRoomCredentials(
            serverUrl: 'wss://lk', participantToken: 't', roomName: 'r', sessionToken: 's'),
        explicitEnd: false,
      );
      expect(log.single.url.path, '/api/webrtc/session/disconnect');
      expect(jsonDecode(log.single.body)['explicit_end'], false);
    });

    test('VaaniTokenSource returns LiveKit TokenSourceResponse', () async {
      final source = VaaniTokenSource(VaaniCredentialsProvider.custom(() async =>
          const VaaniRoomCredentials(
              serverUrl: 'wss://lk', participantToken: 'jwt', roomName: 'room_t')));
      final r = await source.fetch();
      expect(r.serverUrl, 'wss://lk');
      expect(r.participantToken, 'jwt');
      expect(r.roomName, 'room_t');
      expect(source.lastCredentials?.roomName, 'room_t');
    });
  });
}
