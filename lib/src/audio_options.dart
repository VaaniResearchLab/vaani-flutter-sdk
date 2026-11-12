// The processing-mode fields wrap livekit_client's AudioProcessingMode,
// which LiveKit marks experimental. See VaaniAudioProcessing.
// ignore_for_file: experimental_member_use

import 'package:livekit_client/livekit_client.dart' as lk;

/// Where a voice-processing step runs.
///
/// Experimental: this wraps an API that `livekit_client` marks experimental,
/// so it may change in a future LiveKit release. The on/off flags on
/// [VaaniAudioOptions] are stable.
enum VaaniAudioProcessing {
  /// Let WebRTC choose: the device's built-in effect when available,
  /// otherwise the software implementation.
  automatic,

  /// Force the device's built-in effect (Apple voice processing on iOS,
  /// the phone's hardware AEC/NS on Android).
  platform,

  /// Force WebRTC's software implementation. Use this on Android phones
  /// whose built-in echo canceller performs poorly.
  software,
}

/// Microphone voice-processing settings for a [VaaniVoiceSession].
///
/// The defaults are tuned for talking to a voice agent: echo cancellation
/// (so the agent doesn't hear itself on speakerphone), noise suppression,
/// auto gain, a high-pass filter against low-frequency rumble, and voice
/// isolation where the platform supports it.
///
/// These are set explicitly rather than inherited from `livekit_client`, so
/// a LiveKit upgrade can't silently change how the microphone sounds.
class VaaniAudioOptions {
  /// Creates audio options. Every flag defaults to on.
  const VaaniAudioOptions({
    this.echoCancellation = true,
    this.noiseSuppression = true,
    this.autoGainControl = true,
    this.highPassFilter = true,
    this.voiceIsolation = true,
    this.typingNoiseDetection = true,
    this.echoCancellationMode = VaaniAudioProcessing.automatic,
    this.noiseSuppressionMode = VaaniAudioProcessing.automatic,
  });

  /// Turns every processing step off, for raw capture (debugging, or when
  /// your own audio pipeline handles it).
  const VaaniAudioOptions.raw()
      : echoCancellation = false,
        noiseSuppression = false,
        autoGainControl = false,
        highPassFilter = false,
        voiceIsolation = false,
        typingNoiseDetection = false,
        echoCancellationMode = VaaniAudioProcessing.automatic,
        noiseSuppressionMode = VaaniAudioProcessing.automatic;

  /// Acoustic echo cancellation.
  final bool echoCancellation;

  /// Background noise suppression.
  final bool noiseSuppression;

  /// Automatic gain control (levels out quiet and loud speakers).
  final bool autoGainControl;

  /// High-pass filter that removes low-frequency rumble (fans, traffic).
  final bool highPassFilter;

  /// Voice isolation, where the platform supports it.
  final bool voiceIsolation;

  /// Keyboard typing-noise detection, where supported.
  final bool typingNoiseDetection;

  /// Where echo cancellation runs.
  final VaaniAudioProcessing echoCancellationMode;

  /// Where noise suppression runs.
  final VaaniAudioProcessing noiseSuppressionMode;

  /// The equivalent `livekit_client` capture options.
  lk.AudioCaptureOptions toLiveKit() => lk.AudioCaptureOptions(
        echoCancellation: echoCancellation,
        noiseSuppression: noiseSuppression,
        autoGainControl: autoGainControl,
        highPassFilter: highPassFilter,
        voiceIsolation: voiceIsolation,
        typingNoiseDetection: typingNoiseDetection,
        echoCancellationMode: _mode(echoCancellationMode),
        noiseSuppressionMode: _mode(noiseSuppressionMode),
      );

  static lk.AudioProcessingMode _mode(VaaniAudioProcessing m) => switch (m) {
        VaaniAudioProcessing.automatic => lk.AudioProcessingMode.automatic,
        VaaniAudioProcessing.platform => lk.AudioProcessingMode.platform,
        VaaniAudioProcessing.software => lk.AudioProcessingMode.software,
      };
}
