import 'package:test/test.dart';
import 'package:webrtc_dart/src/media/media_stream_track.dart';

void main() {
  group('AudioStreamTrack', () {
    test('creates audio track with correct properties', () {
      final track = AudioStreamTrack(
        id: 'audio1',
        label: 'Microphone',
      );

      expect(track.id, equals('audio1'));
      expect(track.label, equals('Microphone'));
      expect(track.kind, equals(MediaStreamTrackKind.audio));
      expect(track.state, equals(MediaStreamTrackState.live));
      expect(track.enabled, isTrue);
      expect(track.muted, isFalse);
      expect(track.isAudio, isTrue);
      expect(track.isVideo, isFalse);
    });

    test('can be stopped', () {
      final track = AudioStreamTrack(id: 'audio1', label: 'Microphone');

      expect(track.state, equals(MediaStreamTrackState.live));

      track.stop();

      expect(track.state, equals(MediaStreamTrackState.ended));
    });

    test('enabled flag works', () {
      final track = AudioStreamTrack(id: 'audio1', label: 'Microphone');

      expect(track.enabled, isTrue);

      track.enabled = false;

      expect(track.enabled, isFalse);
    });

    test('can send audio frames', () async {
      final track = AudioStreamTrack(id: 'audio1', label: 'Microphone');
      final receivedFrames = <AudioFrame>[];

      track.onAudioFrame.listen((frame) {
        receivedFrames.add(frame);
      });

      // Allow event loop to process subscription
      await Future.delayed(Duration.zero);

      final frame = AudioFrame(
        samples: [1, 2, 3, 4],
        sampleRate: 48000,
        channels: 2,
        timestamp: 1000,
      );

      track.sendAudioFrame(frame);

      // Allow event loop to process event
      await Future.delayed(Duration.zero);

      expect(receivedFrames, hasLength(1));
      expect(receivedFrames[0].samples, equals([1, 2, 3, 4]));
      expect(receivedFrames[0].sampleRate, equals(48000));
    });

    test('does not send frames when disabled', () {
      final track = AudioStreamTrack(id: 'audio1', label: 'Microphone');
      final receivedFrames = <AudioFrame>[];

      track.onAudioFrame.listen((frame) {
        receivedFrames.add(frame);
      });

      track.enabled = false;

      final frame = AudioFrame(
        samples: [1, 2, 3, 4],
        sampleRate: 48000,
        channels: 2,
        timestamp: 1000,
      );

      track.sendAudioFrame(frame);

      expect(receivedFrames, isEmpty);
    });

    test('does not send frames when stopped', () {
      final track = AudioStreamTrack(id: 'audio1', label: 'Microphone');
      final receivedFrames = <AudioFrame>[];

      track.onAudioFrame.listen((frame) {
        receivedFrames.add(frame);
      });

      track.stop();

      final frame = AudioFrame(
        samples: [1, 2, 3, 4],
        sampleRate: 48000,
        channels: 2,
        timestamp: 1000,
      );

      track.sendAudioFrame(frame);

      expect(receivedFrames, isEmpty);
    });

    test('can be cloned', () {
      final track = AudioStreamTrack(id: 'audio1', label: 'Microphone');
      final clone = track.clone();

      expect(clone.label, equals(track.label));
      expect(clone.kind, equals(track.kind));
      expect(clone.id, isNot(equals(track.id))); // Clone has different ID
    });

    test('state change events work', () async {
      final track = AudioStreamTrack(id: 'audio1', label: 'Microphone');
      final states = <MediaStreamTrackState>[];

      track.onStateChange.listen((state) {
        states.add(state);
      });

      track.stop();

      await Future.delayed(Duration(milliseconds: 10));

      expect(states, contains(MediaStreamTrackState.ended));
    });

    test('ended event fires when stopped', () async {
      final track = AudioStreamTrack(id: 'audio1', label: 'Microphone');
      var endedFired = false;

      track.onEnded.listen((_) {
        endedFired = true;
      });

      track.stop();

      await Future.delayed(Duration(milliseconds: 10));

      expect(endedFired, isTrue);
    });
  });

  group('VideoStreamTrack', () {
    test('creates video track with correct properties', () {
      final track = VideoStreamTrack(
        id: 'video1',
        label: 'Camera',
      );

      expect(track.id, equals('video1'));
      expect(track.label, equals('Camera'));
      expect(track.kind, equals(MediaStreamTrackKind.video));
      expect(track.state, equals(MediaStreamTrackState.live));
      expect(track.isAudio, isFalse);
      expect(track.isVideo, isTrue);
    });

    test('can send video frames', () async {
      final track = VideoStreamTrack(id: 'video1', label: 'Camera');
      final receivedFrames = <VideoFrame>[];

      track.onVideoFrame.listen((frame) {
        receivedFrames.add(frame);
      });

      // Allow event loop to process subscription
      await Future.delayed(Duration.zero);

      final frame = VideoFrame(
        data: [1, 2, 3, 4],
        width: 640,
        height: 480,
        timestamp: 1000,
        format: 'I420',
      );

      track.sendVideoFrame(frame);

      // Allow event loop to process event
      await Future.delayed(Duration.zero);

      expect(receivedFrames, hasLength(1));
      expect(receivedFrames[0].width, equals(640));
      expect(receivedFrames[0].height, equals(480));
    });
  });

  group('AudioFrame', () {
    test('calculates duration correctly', () {
      final frame = AudioFrame(
        samples: List.filled(48000 * 2, 0), // 1 second of stereo audio
        sampleRate: 48000,
        channels: 2,
        timestamp: 0,
      );

      expect(frame.durationUs, equals(1000000)); // 1 second in microseconds
    });

    test('calculates duration for mono audio', () {
      final frame = AudioFrame(
        samples: List.filled(8000, 0), // 1 second of mono audio at 8kHz
        sampleRate: 8000,
        channels: 1,
        timestamp: 0,
      );

      expect(frame.durationUs, equals(1000000));
    });
  });
}
