/// Request and response models for the Vaani External API.
library;

/// Delivery medium for `POST /api/trigger-call/`.
enum VaaniCallMedium {
  /// Outbound phone call.
  telephony('telephony'),

  /// In-app voice session over LiveKit WebRTC.
  webrtc('webrtc');

  const VaaniCallMedium(this.value);

  /// Wire value sent to the API.
  final String value;
}

/// Display mode for `POST /api/webrtc/session/create`.
enum VaaniUiType {
  /// Full-page hosted UI.
  fullpage('fullpage'),

  /// Embeddable widget.
  widget('widget');

  const VaaniUiType(this.value);

  /// Wire value sent to the API.
  final String value;
}

/// Voice gender for WebRTC sessions.
enum VaaniVoiceGender {
  /// Male voice.
  male('male'),

  /// Female voice (server default).
  female('female');

  const VaaniVoiceGender(this.value);

  /// Wire value sent to the API.
  final String value;
}

/// Inline agent overrides applied for one call or session only.
class ModifyAgentConfig {
  /// Creates an override set. Omitted sections are left unchanged.
  const ModifyAgentConfig({this.persona, this.training, this.experience, this.analysis});

  /// Persona section override.
  final Map<String, dynamic>? persona;

  /// Training section override.
  final Map<String, dynamic>? training;

  /// Experience section override.
  final Map<String, dynamic>? experience;

  /// Analysis section override.
  final Map<String, dynamic>? analysis;

  /// JSON body, omitting null sections.
  Map<String, dynamic> toJson() => {
        if (persona != null) 'persona': persona,
        if (training != null) 'training': training,
        if (experience != null) 'experience': experience,
        if (analysis != null) 'analysis': analysis,
      };
}

/// Options for dispatching an agent into a WebRTC room via trigger-call.
class WebRtcDispatchOptions {
  /// Creates WebRTC dispatch options. Null fields use the server defaults.
  const WebRtcDispatchOptions({
    this.voiceGender,
    this.primaryLanguage,
    this.secondaryLanguage,
    this.welcomeMessage,
    this.welcomeInterruptible,
    this.bgNoiseEnabled,
    this.bgNoiseVolume,
    this.voiceSpeed,
    this.metadata = const {},
    this.modifyAgent,
  })  : assert(bgNoiseVolume == null || (bgNoiseVolume >= 0 && bgNoiseVolume <= 100),
            'bgNoiseVolume must be 0–100'),
        assert(voiceSpeed == null || (voiceSpeed >= 0.6 && voiceSpeed <= 1.4),
            'voiceSpeed must be 0.6–1.4');

  /// `male` or `female` (server default: female).
  final VaaniVoiceGender? voiceGender;

  /// Primary language code, e.g. `en`, `hi` (server default: `hi`).
  final String? primaryLanguage;

  /// Secondary language code (server default: `en`).
  final String? secondaryLanguage;

  /// Custom opening line spoken by the agent.
  final String? welcomeMessage;

  /// Whether the user can interrupt the welcome message.
  final bool? welcomeInterruptible;

  /// Enable background noise.
  final bool? bgNoiseEnabled;

  /// Background noise volume, 0–100.
  final int? bgNoiseVolume;

  /// Voice speed multiplier, 0.6–1.4.
  final double? voiceSpeed;

  /// Template variables / key-value data forwarded to the agent.
  final Map<String, dynamic> metadata;

  /// Inline agent overrides for this session.
  final ModifyAgentConfig? modifyAgent;
}

/// Options for an outbound telephony call via trigger-call.
class TelephonyCallOptions {
  /// Creates telephony options.
  const TelephonyCallOptions({
    required this.contactNumber,
    required this.name,
    this.voice,
    this.outboundNumber,
    this.sipTrunkId,
    this.testMode,
    this.dndCheckSkipped,
    this.bypassTrai,
    this.metadata = const {},
    this.modifyAgent,
  });

  /// Destination number in E.164 format.
  final String contactNumber;

  /// Customer display name.
  final String name;

  /// Override the agent's default voice.
  final String? voice;

  /// Caller ID override (E.164); must be configured in Vaani telephony settings.
  final String? outboundNumber;

  /// SIP trunk identifier.
  final String? sipTrunkId;

  /// Route the call to the agent's test-mode worker (internal testing;
  /// leave unset in production).
  final bool? testMode;

  /// Skip the Do-Not-Disturb registry check.
  final bool? dndCheckSkipped;

  /// Allow a call after 8 PM IST (TRAI calling hours). Requires the
  /// workspace permission.
  final bool? bypassTrai;

  /// Template variables injected into the agent prompt.
  final Map<String, dynamic> metadata;

  /// Inline agent overrides for this call.
  final ModifyAgentConfig? modifyAgent;
}

/// Response from `POST /api/trigger-call/`.
///
/// Telephony responses populate [callId] (with [roomName] equal to it),
/// [dispatchId] and [callDbId]; WebRTC responses populate [token],
/// [roomName] and [connectionUrl].
class TriggerCallResponse {
  /// Creates a response.
  const TriggerCallResponse({
    this.callId,
    this.token,
    this.roomName,
    this.connectionUrl,
    this.liveCaptionsUrl,
    this.agentName,
    this.dispatchId,
    this.callDbId,
    this.raw = const {},
  });

  /// Parses the API body (handles both flat and `output`-nested shapes).
  factory TriggerCallResponse.fromJson(Map<String, dynamic> json) {
    final output = json['output'] is Map ? Map<String, dynamic>.from(json['output'] as Map) : null;
    String? pick(String key) => (json[key] ?? output?[key]) as String?;
    return TriggerCallResponse(
      callId: pick('call_id'),
      token: pick('token'),
      roomName: pick('room_name'),
      connectionUrl: pick('connection_url'),
      liveCaptionsUrl: pick('live_captions_url'),
      agentName: pick('agent_name'),
      dispatchId: pick('dispatch_id'),
      callDbId: ((json['call_db_id'] ?? output?['call_db_id']) as num?)?.toInt(),
      raw: json,
    );
  }

  /// Telephony call ID.
  final String? callId;

  /// LiveKit participant JWT (WebRTC).
  final String? token;

  /// LiveKit room name (WebRTC).
  final String? roomName;

  /// LiveKit server URL (WebRTC).
  final String? connectionUrl;

  /// Signed live-captions URL. WebRTC: a `wss://` WebSocket URL.
  /// Telephony: an `https://` Server-Sent Events URL.
  final String? liveCaptionsUrl;

  /// Name of the agent handling the call.
  final String? agentName;

  /// Agent dispatch ID (telephony only).
  final String? dispatchId;

  /// Internal numeric call record ID (telephony only).
  final int? callDbId;

  /// Full response body.
  final Map<String, dynamic> raw;
}

/// Response from `POST /api/webrtc/session/create`.
class WebRtcSession {
  /// Creates a session.
  const WebRtcSession({
    required this.sessionToken,
    required this.sessionUrl,
    required this.expiresAt,
  });

  /// Parses the API body.
  factory WebRtcSession.fromJson(Map<String, dynamic> json) => WebRtcSession(
        sessionToken: json['session_token'] as String,
        sessionUrl: json['session_url'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );

  /// Session JWT; pass to connect / status / disconnect / events.
  final String sessionToken;

  /// Shareable URL for Vaani's hosted UI.
  final String sessionUrl;

  /// When the session token expires.
  final DateTime expiresAt;
}

/// Response from `POST /api/webrtc/session/connect`: LiveKit credentials.
class WebRtcSessionConnect {
  /// Creates connect credentials.
  const WebRtcSessionConnect({required this.lkUrl, required this.lkToken, required this.roomName});

  /// Parses the API body.
  factory WebRtcSessionConnect.fromJson(Map<String, dynamic> json) => WebRtcSessionConnect(
        lkUrl: json['lk_url'] as String,
        lkToken: json['lk_token'] as String,
        roomName: json['room_name'] as String,
      );

  /// LiveKit server URL.
  final String lkUrl;

  /// LiveKit participant JWT.
  final String lkToken;

  /// LiveKit room name.
  final String roomName;
}

/// Response from session status / disconnect.
class WebRtcSessionStatus {
  /// Creates a status snapshot.
  const WebRtcSessionStatus({
    required this.status,
    required this.expiresAt,
    required this.uiType,
    required this.roomName,
    required this.agentId,
    required this.clientId,
    this.metadata = const {},
    this.gracePeriodEndsAt,
  });

  /// Parses the API body.
  factory WebRtcSessionStatus.fromJson(Map<String, dynamic> json) => WebRtcSessionStatus(
        status: json['status'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
        uiType: json['ui_type'] as String,
        roomName: json['room_name'] as String,
        agentId: json['agent_id'] as String,
        clientId: json['client_id'] as String,
        metadata: json['metadata'] is Map
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : const {},
        gracePeriodEndsAt: json['grace_period_ends_at'] == null
            ? null
            : DateTime.parse(json['grace_period_ends_at'] as String),
      );

  /// `created` | `agent_ready` | `active` | `reconnecting` | `ended`.
  final String status;

  /// When the session expires.
  final DateTime expiresAt;

  /// `fullpage` | `widget`.
  final String uiType;

  /// LiveKit room name.
  final String roomName;

  /// Agent serving this session.
  final String agentId;

  /// Client identifier.
  final String clientId;

  /// Metadata passed at creation.
  final Map<String, dynamic> metadata;

  /// End of the reconnection grace period, if in one.
  final DateTime? gracePeriodEndsAt;
}

/// Response from `GET /api/health`.
class HealthResponse {
  /// Creates a health response.
  const HealthResponse({required this.status, required this.service, this.raw = const {}});

  /// Parses the API body.
  factory HealthResponse.fromJson(Map<String, dynamic> json) => HealthResponse(
        status: (json['status'] ?? '') as String,
        service: (json['service'] ?? '') as String,
        raw: json,
      );

  /// e.g. `healthy`.
  final String status;

  /// e.g. `vaani-external-api`.
  final String service;

  /// Full response body.
  final Map<String, dynamic> raw;
}

/// LiveKit credentials for joining a Vaani agent's room.
///
/// This is what the SDK hands to the LiveKit client, whichever dispatch
/// path produced it.
class VaaniRoomCredentials {
  /// Creates credentials.
  const VaaniRoomCredentials({
    required this.serverUrl,
    required this.participantToken,
    required this.roomName,
    this.sessionToken,
    this.liveCaptionsUrl,
    this.agentName,
  });

  /// LiveKit server URL (`wss://...`).
  final String serverUrl;

  /// LiveKit participant JWT.
  final String participantToken;

  /// LiveKit room name (the room the agent was dispatched into).
  final String roomName;

  /// Vaani session token, when the session flow was used. Needed to
  /// disconnect the session and to subscribe to session events.
  final String? sessionToken;

  /// Live-captions WebSocket URL, when the API returned one.
  final String? liveCaptionsUrl;

  /// Agent name, when the API returned one.
  final String? agentName;
}
