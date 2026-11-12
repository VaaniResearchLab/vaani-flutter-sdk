# Python SDK mapping

`vaani_flutter_sdk` ports the dispatch and WebRTC parts of the Python [`vaani-sdk`](https://pypi.org/project/vaani-sdk/) (synced with **0.3.2**). Endpoints and JSON fields are identical. Names follow Dart conventions.

## Client and endpoints

| Python | Dart | Endpoint |
|---|---|---|
| `VaaniClient(api_key, base_url, timeout)` | `VaaniClient(apiKey:, baseUrl:, timeout:)` | — |
| `client.health()` | `client.health()` | `GET /api/health` |
| `client.trigger_call(medium="webrtc", ...)` | `client.triggerWebRtcCall(agentId:, options:)` | `POST /api/trigger-call/` |
| `client.trigger_call(medium="telephony", ...)` | `client.triggerTelephonyCall(agentId:, options:)` | `POST /api/trigger-call/` |
| — | `client.dispatchWebRtc(...)` → `VaaniRoomCredentials` | `POST /api/trigger-call/` |
| `client.sessions.create(...)` | `client.sessions.create(...)` | `POST /api/webrtc/session/create` |
| `client.sessions.connect(token)` | `client.sessions.connect(token)` | `POST /api/webrtc/session/connect` |
| `client.sessions.get(token)` | `client.sessions.get(token)` | `GET /api/webrtc/session/status/{token}` |
| `client.sessions.disconnect(token, explicit_end)` | `client.sessions.disconnect(token, explicitEnd:)` | `POST /api/webrtc/session/disconnect` |
| `client.sessions.ws_url(token)` | `client.sessions.wsUrl(token)` → `Uri` | `/api/webrtc/session/ws/{token}` |
| — | `client.sessions.events(token)` → `Stream<VaaniSessionEvent>` | WebSocket |
| `client._request(...)` | `client.request(method, path, body:, query:)` | any |

Python's `grace_period` and `session_ttl` are integer seconds. In Dart they're `Duration`s, sent as seconds.

## Parameters

| Python (`trigger_call`) | Dart |
|---|---|
| `voice_gender="female"` | `WebRtcDispatchOptions(voiceGender: VaaniVoiceGender.female)` |
| `primary_language`, `secondary_language` | `primaryLanguage`, `secondaryLanguage` |
| `welcome_message`, `welcome_interruptible` | `welcomeMessage`, `welcomeInterruptible` |
| `bg_noise_enabled`, `bg_noise_volume` | `bgNoiseEnabled`, `bgNoiseVolume` |
| `voice_speed` | `voiceSpeed` |
| `metadata` | `metadata` |
| `modify_agent=ModifyAgentConfig(...)` | `modifyAgent: ModifyAgentConfig(...)` |
| `contact_number`, `name`, `voice` | `TelephonyCallOptions(contactNumber:, name:, voice:)` |
| `outbound_number`, `sip_trunk_id` | `outboundNumber`, `sipTrunkId` |
| `test_mode`, `dnd_check_skipped`, `bypass_trai` | `testMode`, `dndCheckSkipped`, `bypassTrai` |

## Responses

| Python | Dart |
|---|---|
| `TriggerCallResponse.call_id / token / room_name / connection_url / live_captions_url / agent_name / dispatch_id / call_db_id / raw` | `TriggerCallResponse.callId / token / roomName / connectionUrl / liveCaptionsUrl / agentName / dispatchId / callDbId / raw` |
| `WebRTCSession.session_token / session_url / expires_at` | `WebRtcSession.sessionToken / sessionUrl / expiresAt` |
| `WebRTCSessionConnect.lk_url / lk_token / room_name` | `WebRtcSessionConnect.lkUrl / lkToken / roomName` |
| `WebRTCSessionStatus.*` | `WebRtcSessionStatus.*` (camelCase) |

## Errors

| Python | Dart |
|---|---|
| `VaaniError` | `VaaniException` |
| `AuthenticationError` (401) | `VaaniAuthenticationException` |
| `InsufficientBalanceError` (402) | `VaaniInsufficientBalanceException` |
| `ForbiddenError` (403) | `VaaniForbiddenException` |
| `NotFoundError` (404) | `VaaniNotFoundException` |
| `SessionExpiredError` (410) | `VaaniSessionExpiredException` |
| `ValidationError` (422) | `VaaniValidationException` |
| `RateLimitError` (429) | `VaaniRateLimitException` |
| `ServerError` (5xx) | `VaaniServerException` |
| `TimeoutError` / `ConnectionError` | `VaaniTimeoutException` / `VaaniConnectionException` |

## Deliberately not ported

These are server-side administration and belong on a backend: call history, transcripts, call details, audio streaming, campaigns, and agent create/list/update/delete. If you really need one from the app, use `client.request(...)`.

## Only in Dart

`VaaniVoiceSession`, `VaaniCredentialsProvider`, `VaaniTokenSource`, `VaaniAudioOptions`, `VaaniTranscript`, and `VaaniAgentTimeoutException`. These are the mobile pieces with no Python equivalent.
