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

  // ==========================================================================
  // Phase 5: W3C Constraints API Tests
  // ==========================================================================

  group('MediaStreamTrack Constraints API', () {
    group('getSettings()', () {
      test('audio track returns default settings', () {
        final track = AudioStreamTrack(id: 'audio1', label: 'Microphone');
        final settings = track.getSettings();

        expect(settings, isA<MediaTrackSettings>());
        // Default settings should have null values initially
        expect(settings.deviceId, isNull);
        expect(settings.groupId, isNull);
      });

      test('video track returns default settings', () {
        final track = VideoStreamTrack(id: 'video1', label: 'Camera');
        final settings = track.getSettings();

        expect(settings, isA<MediaTrackSettings>());
        expect(settings.width, isNull);
        expect(settings.height, isNull);
      });

      test('updateSettings changes getSettings result', () {
        final track = VideoStreamTrack(id: 'video1', label: 'Camera');

        track.updateSettings(MediaTrackSettings(
          width: 1920,
          height: 1080,
          frameRate: 30.0,
        ));

        final settings = track.getSettings();
        expect(settings.width, equals(1920));
        expect(settings.height, equals(1080));
        expect(settings.frameRate, equals(30.0));
      });

      test('audio track settings can include audio properties', () {
        final track = AudioStreamTrack(id: 'audio1', label: 'Microphone');

        track.updateSettings(MediaTrackSettings(
          sampleRate: 48000,
          channelCount: 2,
          echoCancellation: true,
        ));

        final settings = track.getSettings();
        expect(settings.sampleRate, equals(48000));
        expect(settings.channelCount, equals(2));
        expect(settings.echoCancellation, isTrue);
      });
    });

    group('getCapabilities()', () {
      test('audio track returns audio capabilities', () {
        final track = AudioStreamTrack(id: 'audio1', label: 'Microphone');
        final capabilities = track.getCapabilities();

        expect(capabilities, isA<MediaTrackCapabilities>());
        expect(capabilities.sampleRate, isNotNull);
        expect(capabilities.sampleRate!.min, equals(8000));
        expect(capabilities.sampleRate!.max, equals(48000));
        expect(capabilities.sampleSize, isNotNull);
        expect(capabilities.channelCount, isNotNull);
        expect(capabilities.echoCancellation, isNotNull);
        expect(capabilities.autoGainControl, isNotNull);
        expect(capabilities.noiseSuppression, isNotNull);
      });

      test('video track returns video capabilities', () {
        final track = VideoStreamTrack(id: 'video1', label: 'Camera');
        final capabilities = track.getCapabilities();

        expect(capabilities, isA<MediaTrackCapabilities>());
        expect(capabilities.width, isNotNull);
        expect(capabilities.width!.min, equals(1));
        expect(capabilities.width!.max, equals(4096));
        expect(capabilities.height, isNotNull);
        expect(capabilities.height!.min, equals(1));
        expect(capabilities.height!.max, equals(2160));
        expect(capabilities.frameRate, isNotNull);
        expect(capabilities.aspectRatio, isNotNull);
      });
    });

    group('getConstraints()', () {
      test('returns empty constraints initially', () {
        final track = VideoStreamTrack(id: 'video1', label: 'Camera');
        final constraints = track.getConstraints();

        expect(constraints, isA<MediaTrackConstraints>());
        expect(constraints.width, isNull);
        expect(constraints.height, isNull);
      });

      test('returns constraints after applyConstraints', () async {
        final track = VideoStreamTrack(id: 'video1', label: 'Camera');

        await track.applyConstraints(MediaTrackConstraints(
          width: 1280,
          height: 720,
        ));

        final constraints = track.getConstraints();
        expect(constraints.width, equals(1280));
        expect(constraints.height, equals(720));
      });
    });

    group('applyConstraints()', () {
      test('applies simple integer constraints to video track', () async {
        final track = VideoStreamTrack(id: 'video1', label: 'Camera');

        await track.applyConstraints(MediaTrackConstraints(
          width: 1920,
          height: 1080,
        ));

        final settings = track.getSettings();
        expect(settings.width, equals(1920));
        expect(settings.height, equals(1080));
      });

      test('applies ConstraintValue with exact', () async {
        final track = VideoStreamTrack(id: 'video1', label: 'Camera');

        await track.applyConstraints(MediaTrackConstraints(
          width: ConstraintValue<int>(exact: 640),
          height: ConstraintValue<int>(exact: 480),
        ));

        final settings = track.getSettings();
        expect(settings.width, equals(640));
        expect(settings.height, equals(480));
      });

      test('applies ConstraintValue with ideal', () async {
        final track = VideoStreamTrack(id: 'video1', label: 'Camera');

        await track.applyConstraints(MediaTrackConstraints(
          width: ConstraintValue<int>(ideal: 1280),
          height: ConstraintValue<int>(ideal: 720),
        ));

        final settings = track.getSettings();
        expect(settings.width, equals(1280));
        expect(settings.height, equals(720));
      });

      test('applies frameRate constraint', () async {
        final track = VideoStreamTrack(id: 'video1', label: 'Camera');

        await track.applyConstraints(MediaTrackConstraints(
          frameRate: 60.0,
        ));

        final settings = track.getSettings();
        expect(settings.frameRate, equals(60.0));
      });

      test('applies audio constraints', () async {
        final track = AudioStreamTrack(id: 'audio1', label: 'Microphone');

        await track.applyConstraints(MediaTrackConstraints(
          sampleRate: 44100,
          channelCount: 1,
          echoCancellation: true,
          noiseSuppression: false,
        ));

        final settings = track.getSettings();
        expect(settings.sampleRate, equals(44100));
        expect(settings.channelCount, equals(1));
        expect(settings.echoCancellation, isTrue);
        expect(settings.noiseSuppression, isFalse);
      });

      test('null constraints resets to empty', () async {
        final track = VideoStreamTrack(id: 'video1', label: 'Camera');

        // Apply some constraints
        await track.applyConstraints(MediaTrackConstraints(width: 1920));

        // Reset
        await track.applyConstraints();

        final constraints = track.getConstraints();
        expect(constraints.width, isNull);
      });
    });
  });

  group('MediaTrackSettings', () {
    test('toJson includes all set properties', () {
      final settings = MediaTrackSettings(
        width: 1920,
        height: 1080,
        frameRate: 30.0,
        aspectRatio: 16 / 9,
        deviceId: 'camera1',
      );

      final json = settings.toJson();
      expect(json['width'], equals(1920));
      expect(json['height'], equals(1080));
      expect(json['frameRate'], equals(30.0));
      expect(json['aspectRatio'], closeTo(1.778, 0.001));
      expect(json['deviceId'], equals('camera1'));
    });

    test('toJson excludes null properties', () {
      final settings = MediaTrackSettings(width: 640);

      final json = settings.toJson();
      expect(json.containsKey('width'), isTrue);
      expect(json.containsKey('height'), isFalse);
    });

    test('toString returns readable format', () {
      final settings = MediaTrackSettings(width: 640, height: 480);
      final str = settings.toString();

      expect(str, contains('MediaTrackSettings'));
      expect(str, contains('640'));
      expect(str, contains('480'));
    });
  });

  group('MediaTrackCapabilities', () {
    test('ULongRange stores min and max', () {
      final range = ULongRange(min: 1, max: 4096);

      expect(range.min, equals(1));
      expect(range.max, equals(4096));
    });

    test('DoubleRange stores min and max', () {
      final range = DoubleRange(min: 1.0, max: 60.0);

      expect(range.min, equals(1.0));
      expect(range.max, equals(60.0));
    });

    test('capabilities can have null ranges', () {
      final capabilities = MediaTrackCapabilities();

      expect(capabilities.width, isNull);
      expect(capabilities.height, isNull);
      expect(capabilities.sampleRate, isNull);
    });
  });

  group('ConstraintValue', () {
    test('stores exact value', () {
      final constraint = ConstraintValue<int>(exact: 1920);

      expect(constraint.exact, equals(1920));
      expect(constraint.ideal, isNull);
      expect(constraint.min, isNull);
      expect(constraint.max, isNull);
    });

    test('stores ideal value', () {
      final constraint = ConstraintValue<double>(ideal: 30.0);

      expect(constraint.exact, isNull);
      expect(constraint.ideal, equals(30.0));
    });

    test('stores min/max range', () {
      final constraint = ConstraintValue<int>(min: 640, max: 1920);

      expect(constraint.min, equals(640));
      expect(constraint.max, equals(1920));
    });

    test('can combine ideal with min/max', () {
      final constraint = ConstraintValue<int>(ideal: 1280, min: 640, max: 1920);

      expect(constraint.ideal, equals(1280));
      expect(constraint.min, equals(640));
      expect(constraint.max, equals(1920));
    });
  });
}
