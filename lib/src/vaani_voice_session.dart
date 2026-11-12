import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import 'audio_options.dart';
import 'credentials_provider.dart';
import 'exceptions.dart';
import 'models.dart';
import 'sessions.dart';
import 'vaani_client.dart';

/// Lifecycle of a [VaaniVoiceSession].
enum VaaniVoiceSessionState {
  /// Not started.
  idle,

  /// Asking Vaani to dispatch the agent.
  dispatching,

  /// Joining the LiveKit room.
  connecting,

  /// In the room; the agent has not joined yet.
  waitingForAgent,

  /// Agent is in the room; conversation is live.
  active,

  /// LiveKit is reconnecting after a network drop.
  reconnecting,

  /// Ended normally.
  ended,

  /// Ended because of an error; see [VaaniVoiceSession.error].
  failed,
}

/// The agent did not join the room within the configured timeout.
class VaaniAgentTimeoutException extends VaaniException {
  /// Creates the timeout error.
  const VaaniAgentTimeoutException([super.message = 'Agent did not join the room in time']);
}

/// One transcription update from the room.
class VaaniTranscript {
  /// Creates a transcript segment.
  const VaaniTranscript({
    required this.segmentId,
    required this.participantIdentity,
    required this.text,
    required this.isFinal,
    required this.fromAgent,
  });

  /// Segment ID; interim and final updates for one utterance share it.
  final String segmentId;

  /// Identity of the speaker.
  final String participantIdentity;

  /// Transcribed text.
  final String text;

  /// Whether this is the final text for the segment.
  final bool isFinal;

  /// True when the agent spoke; false for the local user.
  final bool fromAgent;

  @override
  String toString() => 'VaaniTranscript(${fromAgent ? 'agent' : 'user'}: $text)';
}

/// Dispatches a Vaani agent and joins its LiveKit room.
///
/// ```dart
/// final session = VaaniVoiceSession.withApiKey(
///   apiKey: 'vaani_...',
///   agentId: 'd62cc9bd-...',
/// );
/// await session.start();   // dispatch → connect → mic on
/// ...
/// await session.end();
/// ```
///
/// It is a [ChangeNotifier], so it plugs into `ListenableBuilder` or
/// Provider. A session is single-use: create a new one per conversation.
class VaaniVoiceSession extends ChangeNotifier {
  /// Creates a session from any [VaaniCredentialsProvider], including one
  /// that calls your own backend.
  VaaniVoiceSession({
    required this.credentialsProvider,
    lk.RoomOptions roomOptions = const lk.RoomOptions(adaptiveStream: true, dynacast: true),
    this.enableMicrophone = true,
    this.audioOptions = const VaaniAudioOptions(),
    this.agentJoinTimeout = const Duration(seconds: 30),
    this.endWhenAgentLeaves = true,
    VaaniClient? ownedClient,
  })  : room = lk.Room(
          roomOptions:
              roomOptions.copyWith(defaultAudioCaptureOptions: audioOptions.toLiveKit()),
        ),
        _ownedClient = ownedClient;

  /// Convenience constructor that calls the Vaani API directly with an API key.
  ///
  /// [useSessionFlow] picks `session/create` + `session/connect` (reconnect
  /// grace period, session events). Otherwise it uses `trigger-call` with
  /// `medium: webrtc`.
  ///
  /// An API key in a mobile app can be extracted from the binary. Ship
  /// production apps with a backend-backed [VaaniCredentialsProvider].
  factory VaaniVoiceSession.withApiKey({
    required String apiKey,
    required String agentId,
    String baseUrl = vaaniDefaultBaseUrl,
    bool useSessionFlow = false,
    WebRtcDispatchOptions dispatchOptions = const WebRtcDispatchOptions(),
    Duration? gracePeriod,
    Duration? sessionTtl,
    String? initialMessage,
    Map<String, dynamic> sessionMetadata = const {},
    lk.RoomOptions roomOptions = const lk.RoomOptions(adaptiveStream: true, dynacast: true),
    bool enableMicrophone = true,
    VaaniAudioOptions audioOptions = const VaaniAudioOptions(),
    Duration? agentJoinTimeout = const Duration(seconds: 30),
  }) {
    final client = VaaniClient(apiKey: apiKey, baseUrl: baseUrl);
    final VaaniCredentialsProvider provider = useSessionFlow
        ? SessionCredentialsProvider(
            client: client,
            agentId: agentId,
            gracePeriod: gracePeriod,
            sessionTtl: sessionTtl,
            initialMessage: initialMessage,
            metadata: sessionMetadata,
          )
        : TriggerCallCredentialsProvider(
            client: client, agentId: agentId, options: dispatchOptions);
    return VaaniVoiceSession(
      credentialsProvider: provider,
      roomOptions: roomOptions,
      enableMicrophone: enableMicrophone,
      audioOptions: audioOptions,
      agentJoinTimeout: agentJoinTimeout,
      ownedClient: client,
    );
  }

  /// Source of LiveKit credentials (the dispatch step).
  final VaaniCredentialsProvider credentialsProvider;

  /// Publish the microphone as soon as the room is joined.
  final bool enableMicrophone;

  /// Echo cancellation, noise suppression and other mic processing.
  ///
  /// Overrides `roomOptions.defaultAudioCaptureOptions`.
  final VaaniAudioOptions audioOptions;

  /// Fail the session if no agent joins within this time; null disables.
  final Duration? agentJoinTimeout;

  /// End the session when the agent leaves the room (agent hung up).
  final bool endWhenAgentLeaves;

  /// The underlying LiveKit room, for anything this wrapper doesn't cover
  /// (audio tracks, RPC, data messages, custom events).
  final lk.Room room;

  final VaaniClient? _ownedClient;
  lk.EventsListener<lk.RoomEvent>? _listener;
  Timer? _agentTimer;
  StreamSubscription<VaaniSessionEvent>? _eventsSub;
  final _transcripts = StreamController<VaaniTranscript>.broadcast();
  final _sessionEvents = StreamController<VaaniSessionEvent>.broadcast();
  final Map<String, _TranscriptSource> _transcriptSourceBySpeaker = {};
  bool _textStreamRegistered = false;
  bool _disposed = false;

  static const _transcriptionTopic = 'lk.transcription';

  VaaniVoiceSessionState _state = VaaniVoiceSessionState.idle;

  /// Current lifecycle state.
  VaaniVoiceSessionState get state => _state;

  VaaniRoomCredentials? _credentials;

  /// Credentials returned by the dispatch step (room name, URL, ...).
  VaaniRoomCredentials? get credentials => _credentials;

  /// LiveKit room name the agent was dispatched into.
  String? get roomName => _credentials?.roomName;

  lk.RemoteParticipant? _agent;

  /// The agent participant, once it has joined.
  lk.RemoteParticipant? get agent => _agent;

  Object? _error;

  /// The error that moved the session to [VaaniVoiceSessionState.failed].
  Object? get error => _error;

  /// Whether the local microphone is published and unmuted.
  bool get isMicrophoneEnabled => room.localParticipant?.isMicrophoneEnabled() ?? false;

  /// Whether the LiveKit server currently hears the local user speaking.
  ///
  /// Computed server-side, so `true` also proves the mic audio is arriving.
  bool get isUserSpeaking => room.localParticipant?.isSpeaking ?? false;

  /// Whether the agent is currently speaking.
  bool get isAgentSpeaking => _agent?.isSpeaking ?? false;

  /// Server-reported speaking level of the local user, 0.0–1.0.
  double get userAudioLevel => room.localParticipant?.audioLevel ?? 0;

  /// Live transcription for both the agent and the user.
  Stream<VaaniTranscript> get transcripts => _transcripts.stream;

  /// Vaani session WebSocket events (session flow only).
  Stream<VaaniSessionEvent> get sessionEvents => _sessionEvents.stream;

  /// Dispatches the agent, joins the room and, by default, enables the mic.
  ///
  /// Completes once the room is joined; [state] moves to
  /// [VaaniVoiceSessionState.active] when the agent arrives. Throws on
  /// dispatch or connection failure (and sets [state] to failed).
  Future<void> start() async {
    if (_state != VaaniVoiceSessionState.idle) {
      throw StateError('VaaniVoiceSession.start() can only be called once (state: $_state)');
    }
    try {
      _setState(VaaniVoiceSessionState.dispatching);
      final creds = await credentialsProvider.fetchCredentials();
      _credentials = creds;
      if (_isClosed) {
        // end() ran while dispatching, before credentials existed to release.
        await credentialsProvider.release(creds, explicitEnd: true).catchError((_) {});
        return;
      }

      _setState(VaaniVoiceSessionState.connecting);
      _attachRoomListeners();
      _subscribeSessionEvents(creds);
      await room.connect(creds.serverUrl, creds.participantToken);
      if (_isClosed) return;

      if (enableMicrophone) {
        await room.localParticipant
            ?.setMicrophoneEnabled(true, audioCaptureOptions: audioOptions.toLiveKit());
      }

      final existing = _findAgent(room.remoteParticipants.values);
      if (existing != null) {
        _onAgentJoined(existing);
      } else {
        _setState(VaaniVoiceSessionState.waitingForAgent);
        _startAgentTimer();
      }
    } catch (e) {
      await _fail(e);
      rethrow;
    }
  }

  /// Mutes or unmutes the local microphone.
  Future<void> setMicrophoneEnabled(bool enabled) async {
    // Unmuting recreates the capture track, so pass the options every time.
    await room.localParticipant
        ?.setMicrophoneEnabled(enabled, audioCaptureOptions: audioOptions.toLiveKit());
    notifyListeners();
  }

  /// Leaves the room and releases the dispatch.
  ///
  /// For the session flow, [explicitEnd] true ends the Vaani session now;
  /// false leaves it in its grace period so it could be resumed.
  Future<void> end({bool explicitEnd = true}) async {
    if (_isClosed) return;
    await _teardown(explicitEnd: explicitEnd);
    _setState(VaaniVoiceSessionState.ended);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    if (!_isClosed && _state != VaaniVoiceSessionState.idle) {
      await _teardown(explicitEnd: true);
      _state = VaaniVoiceSessionState.ended;
    }
    _disposed = true;
    await room.dispose();
    await _transcripts.close();
    await _sessionEvents.close();
    _ownedClient?.close();
    super.dispose();
  }

  // ---------------------------------------------------------------------------

  // True from the moment teardown begins, so concurrent end()/fail paths
  // (agent leaves + room disconnects) run teardown only once.
  bool _closing = false;

  bool get _isClosed =>
      _closing ||
      _state == VaaniVoiceSessionState.ended ||
      _state == VaaniVoiceSessionState.failed;

  void _setState(VaaniVoiceSessionState s) {
    if (_disposed || _state == s) return;
    _state = s;
    notifyListeners();
  }

  void _attachRoomListeners() {
    final l = room.createListener();
    _listener = l;
    l
      ..on<lk.ParticipantConnectedEvent>((e) {
        if (_agent == null && _isAgent(e.participant)) _onAgentJoined(e.participant);
      })
      ..on<lk.ParticipantDisconnectedEvent>((e) {
        if (e.participant.identity == _agent?.identity) {
          _agent = null;
          if (endWhenAgentLeaves && !_isClosed) {
            unawaited(end());
          } else {
            notifyListeners();
          }
        }
      })
      ..on<lk.RoomReconnectingEvent>((_) => _setState(VaaniVoiceSessionState.reconnecting))
      ..on<lk.RoomReconnectedEvent>((_) => _setState(_agent == null
          ? VaaniVoiceSessionState.waitingForAgent
          : VaaniVoiceSessionState.active))
      ..on<lk.RoomDisconnectedEvent>((_) {
        if (!_isClosed) unawaited(end(explicitEnd: false));
      })
      ..on<lk.LocalTrackPublishedEvent>((_) => notifyListeners())
      ..on<lk.TrackMutedEvent>((_) => notifyListeners())
      ..on<lk.TrackUnmutedEvent>((_) => notifyListeners())
      ..on<lk.ActiveSpeakersChangedEvent>((_) => notifyListeners())
      ..on<lk.TranscriptionEvent>(_onLegacyTranscription);

    room.registerTextStreamHandler(_transcriptionTopic, _onTranscriptionStream);
    _textStreamRegistered = true;
  }

  void _subscribeSessionEvents(VaaniRoomCredentials creds) {
    final token = creds.sessionToken;
    final provider = credentialsProvider;
    if (token == null || provider is! SessionCredentialsProvider) return;
    _eventsSub = provider.client.sessions.events(token).listen(
      (event) {
        if (!_sessionEvents.isClosed) _sessionEvents.add(event);
        if (event.isSessionEnded && !_isClosed) unawaited(end());
        if (event.isAgentTimeout && !_isClosed) {
          unawaited(_fail(const VaaniAgentTimeoutException('Vaani reported agent_timeout')));
        }
      },
      onError: (Object e) {
        if (!_sessionEvents.isClosed) _sessionEvents.addError(e);
      },
    );
  }

  bool _isAgent(lk.Participant p) => p.kind == lk.ParticipantKind.AGENT;

  /// Prefers a participant marked as an agent; otherwise the first remote
  /// participant (the room is created for this one agent).
  lk.RemoteParticipant? _findAgent(Iterable<lk.RemoteParticipant> ps) {
    for (final p in ps) {
      if (_isAgent(p)) return p;
    }
    return ps.isEmpty ? null : ps.first;
  }

  void _onAgentJoined(lk.RemoteParticipant p) {
    _agentTimer?.cancel();
    _agent = p;
    _setState(VaaniVoiceSessionState.active);
    notifyListeners();
  }

  void _startAgentTimer() {
    final t = agentJoinTimeout;
    if (t == null) return;
    _agentTimer = Timer(t, () {
      if (_agent != null || _isClosed) return;
      // Agents that don't set ParticipantKind.AGENT still count once present.
      final fallback = _findAgent(room.remoteParticipants.values);
      if (fallback != null) {
        _onAgentJoined(fallback);
      } else {
        unawaited(_fail(const VaaniAgentTimeoutException()));
      }
    });
  }

  /// LiveKit agents may publish each transcript twice: as a legacy
  /// [lk.TranscriptionEvent] and on the `lk.transcription` text stream, with
  /// unrelated segment IDs (seen live against Vaani). Lock each speaker to
  /// whichever source delivers first and drop the other.
  bool _claimSource(String identity, _TranscriptSource source) =>
      (_transcriptSourceBySpeaker[identity] ??= source) == source;

  Future<void> _onTranscriptionStream(lk.TextStreamReader reader, String identity) async {
    if (!_claimSource(identity, _TranscriptSource.textStream)) return;
    final info = reader.info;
    final text = await reader.readAll();
    if (_transcripts.isClosed) return;
    final segmentId = info?.attributes['lk.segment_id'] ?? info?.id ?? '';
    // The stream has closed, so its text is complete unless marked interim.
    final isFinal = info?.attributes['lk.transcription_final'] != 'false';
    _transcripts.add(VaaniTranscript(
      segmentId: segmentId,
      participantIdentity: identity,
      text: text,
      isFinal: isFinal,
      fromAgent: identity != room.localParticipant?.identity,
    ));
  }

  void _onLegacyTranscription(lk.TranscriptionEvent e) {
    if (_transcripts.isClosed) return;
    if (!_claimSource(e.participant.identity, _TranscriptSource.legacyEvent)) return;
    for (final s in e.segments) {
      _transcripts.add(VaaniTranscript(
        segmentId: s.id,
        participantIdentity: e.participant.identity,
        text: s.text,
        isFinal: s.isFinal,
        fromAgent: e.participant is! lk.LocalParticipant,
      ));
    }
  }

  Future<void> _fail(Object e) async {
    if (_isClosed) return;
    _error = e;
    await _teardown(explicitEnd: true);
    _setState(VaaniVoiceSessionState.failed);
  }

  Future<void> _teardown({required bool explicitEnd}) async {
    _closing = true;
    _agentTimer?.cancel();
    _agentTimer = null;
    await _eventsSub?.cancel();
    _eventsSub = null;
    if (_textStreamRegistered) {
      room.unregisterTextStreamHandler(_transcriptionTopic);
      _textStreamRegistered = false;
    }
    await _listener?.dispose();
    _listener = null;
    try {
      await room.disconnect();
    } catch (_) {
      // Already disconnected.
    }
    final creds = _credentials;
    if (creds != null) {
      try {
        await credentialsProvider.release(creds, explicitEnd: explicitEnd);
      } catch (_) {
        // Best effort: the backend will expire the session on its own.
      }
    }
  }
}

enum _TranscriptSource { legacyEvent, textStream }
