// ignore_for_file: experimental_member_use
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:vaani_flutter_sdk/vaani_flutter_sdk.dart';

void main() {
  test('defaults turn on every voice-processing step', () {
    final o = const VaaniAudioOptions().toLiveKit();
    expect(o.echoCancellation, isTrue);
    expect(o.noiseSuppression, isTrue);
    expect(o.autoGainControl, isTrue);
    expect(o.highPassFilter, isTrue);
    expect(o.voiceIsolation, isTrue);
    expect(o.typingNoiseDetection, isTrue);
    expect(o.echoCancellationMode, lk.AudioProcessingMode.automatic);
    expect(o.noiseSuppressionMode, lk.AudioProcessingMode.automatic);
  });

  test('raw() turns every step off', () {
    final o = const VaaniAudioOptions.raw().toLiveKit();
    expect(
      [o.echoCancellation, o.noiseSuppression, o.autoGainControl, o.highPassFilter,
        o.voiceIsolation, o.typingNoiseDetection],
      everyElement(isFalse),
    );
  });

  test('processing modes map to LiveKit modes', () {
    final o = const VaaniAudioOptions(
      echoCancellationMode: VaaniAudioProcessing.software,
      noiseSuppressionMode: VaaniAudioProcessing.platform,
    ).toLiveKit();
    expect(o.echoCancellationMode, lk.AudioProcessingMode.software);
    expect(o.noiseSuppressionMode, lk.AudioProcessingMode.platform);
  });

  test('session applies audio options to the room defaults', () {
    final session = VaaniVoiceSession(
      credentialsProvider: VaaniCredentialsProvider.custom(
          () async => throw UnimplementedError('not started in this test')),
      audioOptions: const VaaniAudioOptions(
        noiseSuppression: false,
        echoCancellationMode: VaaniAudioProcessing.software,
      ),
    );
    final applied = session.room.roomOptions.defaultAudioCaptureOptions;
    expect(applied.noiseSuppression, isFalse);
    expect(applied.echoCancellation, isTrue);
    expect(applied.echoCancellationMode, lk.AudioProcessingMode.software);
    expect(session.room.roomOptions.adaptiveStream, isTrue, reason: 'other room options kept');
  });
}
