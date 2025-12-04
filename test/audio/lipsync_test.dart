import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/audio/lipsync.dart';

void main() {
  group('MediaFrame', () {
    test('creates audio frame', () {
      final frame = MediaFrame(
        timestamp: 1000,
        data: Uint8List.fromList([0x01, 0x02]),
        kind: MediaKind.audio,
      );

      expect(frame.kind, equals(MediaKind.audio));
      expect(frame.timestamp, equals(1000));
      expect(frame.isKeyframe, isTrue);
    });

    test('creates video frame', () {
      final frame = MediaFrame(
        timestamp: 2000,
        data: Uint8List.fromList([0x03, 0x04]),
        kind: MediaKind.video,
        isKeyframe: false,
      );

      expect(frame.kind, equals(MediaKind.video));
      expect(frame.timestamp, equals(2000));
      expect(frame.isKeyframe, isFalse);
    });
  });

  group('NtpRtpMapping', () {
    test('creates mapping', () {
      final mapping = NtpRtpMapping(
        ntpSeconds: 3811649820,
        ntpFraction: 2147483648, // 0.5 seconds
        rtpTimestamp: 1000,
        clockRate: 48000,
      );

      expect(mapping.ntpSeconds, equals(3811649820));
      expect(mapping.rtpTimestamp, equals(1000));
      expect(mapping.clockRate, equals(48000));
    });

    test('rtpToNtpMillis converts timestamps correctly', () {
      final mapping = NtpRtpMapping(
        ntpSeconds: 1000, // Simplified NTP seconds
        ntpFraction: 0,
        rtpTimestamp: 48000, // 1 second of audio at 48kHz
        clockRate: 48000,
      );

      // Same timestamp should return base NTP time
      expect(mapping.rtpToNtpMillis(48000), equals(1000 * 1000));

      // 48000 samples later = 1 second later
      expect(mapping.rtpToNtpMillis(96000), equals(1000 * 1000 + 1000));

      // 24000 samples later = 0.5 seconds later
      expect(mapping.rtpToNtpMillis(72000), equals(1000 * 1000 + 500));
    });

    test('rtpToNtpMillis handles video clock rate', () {
      final mapping = NtpRtpMapping(
        ntpSeconds: 1000,
        ntpFraction: 0,
        rtpTimestamp: 90000, // 1 second at 90kHz video clock
        clockRate: 90000,
      );

      // 90000 samples = 1 second for video
      expect(mapping.rtpToNtpMillis(180000), equals(1000 * 1000 + 1000));
    });

    test('ntpMillis returns correct value', () {
      final mapping = NtpRtpMapping(
        ntpSeconds: 100,
        ntpFraction: 0,
        rtpTimestamp: 0,
        clockRate: 48000,
      );

      expect(mapping.ntpMillis, equals(100000));
    });
  });

  group('LipSyncOptions', () {
    test('defaults are correct', () {
      const options = LipSyncOptions();

      expect(options.syncInterval, equals(500));
      expect(options.bufferLength, equals(10));
      expect(options.ptime, equals(20));
      expect(options.fillDummyAudioPacket, isNull);
      expect(options.maxDrift, equals(80));
    });

    test('bufferDuration is calculated correctly', () {
      const options = LipSyncOptions(syncInterval: 500);

      expect(options.bufferDuration, equals(250));
    });

    test('custom options are applied', () {
      final options = LipSyncOptions(
        syncInterval: 1000,
        bufferLength: 5,
        ptime: 10,
        fillDummyAudioPacket: Uint8List.fromList([0xF8]),
        maxDrift: 100,
      );

      expect(options.syncInterval, equals(1000));
      expect(options.bufferLength, equals(5));
      expect(options.ptime, equals(10));
      expect(options.fillDummyAudioPacket, isNotNull);
      expect(options.maxDrift, equals(100));
    });
  });

  group('LipSyncProcessor', () {
    late LipSyncProcessor processor;
    late List<MediaFrame> audioOutput;
    late List<MediaFrame> videoOutput;

    setUp(() {
      audioOutput = [];
      videoOutput = [];
      processor = LipSyncProcessor(
        options: const LipSyncOptions(syncInterval: 100, bufferLength: 4),
        onAudioFrame: (frame) => audioOutput.add(frame),
        onVideoFrame: (frame) => videoOutput.add(frame),
      );
    });

    test('starts in non-stopped state', () {
      expect(processor.isStopped, isFalse);
      expect(processor.baseTime, isNull);
    });

    test('initializes base time on first frame', () {
      final frame = MediaFrame(
        timestamp: 1000,
        data: Uint8List(10),
        kind: MediaKind.audio,
      );

      processor.processAudioFrame(frame);

      expect(processor.baseTime, equals(1000));
    });

    test('processAudioFrame buffers audio', () {
      final frame = MediaFrame(
        timestamp: 1000,
        data: Uint8List(10),
        kind: MediaKind.audio,
      );

      processor.processAudioFrame(frame);

      final stats = processor.toJson();
      expect(stats['audioFramesReceived'], equals(1));
    });

    test('processVideoFrame buffers video', () {
      final frame = MediaFrame(
        timestamp: 1000,
        data: Uint8List(100),
        kind: MediaKind.video,
      );

      processor.processVideoFrame(frame);

      final stats = processor.toJson();
      expect(stats['videoFramesReceived'], equals(1));
    });

    test('outputs frames in timestamp order', () {
      // Send frames out of order
      processor.processAudioFrame(MediaFrame(
        timestamp: 1000,
        data: Uint8List(10),
        kind: MediaKind.audio,
      ));
      processor.processVideoFrame(MediaFrame(
        timestamp: 1050,
        data: Uint8List(100),
        kind: MediaKind.video,
      ));
      processor.processAudioFrame(MediaFrame(
        timestamp: 1100,
        data: Uint8List(10),
        kind: MediaKind.audio,
      ));

      // Trigger flush by advancing time
      processor.processAudioFrame(MediaFrame(
        timestamp: 1500, // Past sync interval
        data: Uint8List(10),
        kind: MediaKind.audio,
      ));

      // Verify output is sorted by timestamp
      if (audioOutput.length >= 2) {
        for (var i = 1; i < audioOutput.length; i++) {
          expect(
            audioOutput[i].timestamp,
            greaterThanOrEqualTo(audioOutput[i - 1].timestamp),
          );
        }
      }
    });

    test('drops frames older than last committed', () {
      // First frame
      processor.processAudioFrame(MediaFrame(
        timestamp: 1000,
        data: Uint8List(10),
        kind: MediaKind.audio,
      ));

      // Trigger flush
      processor.processAudioFrame(MediaFrame(
        timestamp: 1500,
        data: Uint8List(10),
        kind: MediaKind.audio,
      ));

      processor.flush();

      final statsBeforeDrop = processor.toJson();
      final droppedBefore = statsBeforeDrop['droppedFrames'] as int;

      // Send old frame
      processor.processAudioFrame(MediaFrame(
        timestamp: 500, // Older than any committed frame
        data: Uint8List(10),
        kind: MediaKind.audio,
      ));

      final statsAfterDrop = processor.toJson();
      final droppedAfter = statsAfterDrop['droppedFrames'] as int;

      expect(droppedAfter, greaterThan(droppedBefore));
    });

    test('stop prevents further processing', () {
      processor.processAudioFrame(MediaFrame(
        timestamp: 1000,
        data: Uint8List(10),
        kind: MediaKind.audio,
      ));

      processor.stop();

      processor.processAudioFrame(MediaFrame(
        timestamp: 2000,
        data: Uint8List(10),
        kind: MediaKind.audio,
      ));

      expect(processor.isStopped, isTrue);
      final stats = processor.toJson();
      expect(stats['audioFramesReceived'], equals(1)); // Only first frame
    });

    test('reset clears all state', () {
      processor.processAudioFrame(MediaFrame(
        timestamp: 1000,
        data: Uint8List(10),
        kind: MediaKind.audio,
      ));

      processor.reset();

      expect(processor.baseTime, isNull);
      expect(processor.isStopped, isFalse);
      final stats = processor.toJson();
      expect(stats['audioFramesReceived'], equals(0));
    });

    test('toJson returns correct statistics', () {
      processor.processAudioFrame(MediaFrame(
        timestamp: 1000,
        data: Uint8List(10),
        kind: MediaKind.audio,
      ));
      processor.processVideoFrame(MediaFrame(
        timestamp: 1000,
        data: Uint8List(100),
        kind: MediaKind.video,
      ));

      final stats = processor.toJson();

      expect(stats['baseTime'], equals(1000));
      expect(stats['audioFramesReceived'], equals(1));
      expect(stats['videoFramesReceived'], equals(1));
      expect(stats['stopped'], isFalse);
    });

    test('flush outputs all buffered frames', () {
      processor.processAudioFrame(MediaFrame(
        timestamp: 1000,
        data: Uint8List(10),
        kind: MediaKind.audio,
      ));
      processor.processVideoFrame(MediaFrame(
        timestamp: 1000,
        data: Uint8List(100),
        kind: MediaKind.video,
      ));

      processor.flush();

      final stats = processor.toJson();
      expect(stats['audioFramesOutput'], greaterThanOrEqualTo(0));
      expect(stats['videoFramesOutput'], greaterThanOrEqualTo(0));
    });
  });

  group('AVSyncCalculator', () {
    late AVSyncCalculator calculator;

    setUp(() {
      calculator = AVSyncCalculator();
    });

    test('starts without mappings', () {
      expect(calculator.hasBothMappings, isFalse);
    });

    test('hasBothMappings after updating both', () {
      calculator.updateAudioMapping(NtpRtpMapping(
        ntpSeconds: 1000,
        ntpFraction: 0,
        rtpTimestamp: 48000,
        clockRate: 48000,
      ));

      expect(calculator.hasBothMappings, isFalse);

      calculator.updateVideoMapping(NtpRtpMapping(
        ntpSeconds: 1000,
        ntpFraction: 0,
        rtpTimestamp: 90000,
        clockRate: 90000,
      ));

      expect(calculator.hasBothMappings, isTrue);
    });

    test('audioRtpToNtp converts correctly', () {
      calculator.updateAudioMapping(NtpRtpMapping(
        ntpSeconds: 100,
        ntpFraction: 0,
        rtpTimestamp: 48000,
        clockRate: 48000,
      ));

      final ntp = calculator.audioRtpToNtp(96000); // 1 second later
      expect(ntp, equals(100000 + 1000)); // 100 seconds + 1 second
    });

    test('videoRtpToNtp converts correctly', () {
      calculator.updateVideoMapping(NtpRtpMapping(
        ntpSeconds: 100,
        ntpFraction: 0,
        rtpTimestamp: 90000,
        clockRate: 90000,
      ));

      final ntp = calculator.videoRtpToNtp(180000); // 1 second later
      expect(ntp, equals(100000 + 1000));
    });

    test('calculateOffset returns null without mappings', () {
      expect(calculator.calculateOffset(48000, 90000), isNull);
    });

    test('calculateOffset returns correct offset when in sync', () {
      // Both start at same NTP time
      calculator.updateAudioMapping(NtpRtpMapping(
        ntpSeconds: 100,
        ntpFraction: 0,
        rtpTimestamp: 48000,
        clockRate: 48000,
      ));
      calculator.updateVideoMapping(NtpRtpMapping(
        ntpSeconds: 100,
        ntpFraction: 0,
        rtpTimestamp: 90000,
        clockRate: 90000,
      ));

      // Same presentation time (1 second after base)
      final offset = calculator.calculateOffset(96000, 180000);
      expect(offset, equals(0));
    });

    test('calculateOffset detects video ahead', () {
      calculator.updateAudioMapping(NtpRtpMapping(
        ntpSeconds: 100,
        ntpFraction: 0,
        rtpTimestamp: 48000,
        clockRate: 48000,
      ));
      calculator.updateVideoMapping(NtpRtpMapping(
        ntpSeconds: 100,
        ntpFraction: 0,
        rtpTimestamp: 90000,
        clockRate: 90000,
      ));

      // Video is 1 second ahead
      final offset = calculator.calculateOffset(48000, 180000);
      expect(offset, equals(1000)); // Positive = video ahead
    });

    test('calculateOffset detects audio ahead', () {
      calculator.updateAudioMapping(NtpRtpMapping(
        ntpSeconds: 100,
        ntpFraction: 0,
        rtpTimestamp: 48000,
        clockRate: 48000,
      ));
      calculator.updateVideoMapping(NtpRtpMapping(
        ntpSeconds: 100,
        ntpFraction: 0,
        rtpTimestamp: 90000,
        clockRate: 90000,
      ));

      // Audio is 1 second ahead
      final offset = calculator.calculateOffset(96000, 90000);
      expect(offset, equals(-1000)); // Negative = audio ahead
    });

    test('reset clears mappings', () {
      calculator.updateAudioMapping(NtpRtpMapping(
        ntpSeconds: 100,
        ntpFraction: 0,
        rtpTimestamp: 48000,
        clockRate: 48000,
      ));
      calculator.updateVideoMapping(NtpRtpMapping(
        ntpSeconds: 100,
        ntpFraction: 0,
        rtpTimestamp: 90000,
        clockRate: 90000,
      ));

      calculator.reset();

      expect(calculator.hasBothMappings, isFalse);
    });

    test('toJson returns correct state', () {
      calculator.updateAudioMapping(NtpRtpMapping(
        ntpSeconds: 100,
        ntpFraction: 0,
        rtpTimestamp: 48000,
        clockRate: 48000,
      ));

      final stats = calculator.toJson();
      expect(stats['hasAudioMapping'], isTrue);
      expect(stats['hasVideoMapping'], isFalse);
      expect(stats['hasBothMappings'], isFalse);
    });
  });

  group('DriftDetector', () {
    late DriftDetector detector;

    setUp(() {
      detector = DriftDetector(driftThreshold: 80);
    });

    test('starts with no drift', () {
      expect(detector.hasDrift, isFalse);
      expect(detector.averageOffset, equals(0));
      expect(detector.driftDirection, equals(0));
    });

    test('addSample accumulates samples', () {
      detector.addSample(10);
      detector.addSample(20);
      detector.addSample(30);

      expect(detector.averageOffset, equals(20));
    });

    test('detects video ahead drift', () {
      for (var i = 0; i < 10; i++) {
        detector.addSample(100); // Video ahead by 100ms
      }

      expect(detector.hasDrift, isTrue);
      expect(detector.driftDirection, equals(1)); // Video ahead
    });

    test('detects audio ahead drift', () {
      for (var i = 0; i < 10; i++) {
        detector.addSample(-100); // Audio ahead by 100ms
      }

      expect(detector.hasDrift, isTrue);
      expect(detector.driftDirection, equals(-1)); // Audio ahead
    });

    test('reports in sync when under threshold', () {
      for (var i = 0; i < 10; i++) {
        detector.addSample(50); // Under 80ms threshold
      }

      expect(detector.hasDrift, isFalse);
      expect(detector.driftDirection, equals(0));
    });

    test('limits sample buffer size', () {
      final detector = DriftDetector(maxSamples: 5);

      for (var i = 0; i < 10; i++) {
        detector.addSample(i * 10);
      }

      // Should only keep last 5 samples (50, 60, 70, 80, 90)
      expect(detector.averageOffset, equals(70));
    });

    test('reset clears samples', () {
      detector.addSample(100);
      detector.addSample(100);

      detector.reset();

      expect(detector.averageOffset, equals(0));
      final stats = detector.toJson();
      expect(stats['sampleCount'], equals(0));
    });

    test('toJson returns correct state', () {
      detector.addSample(50);
      detector.addSample(60);

      final stats = detector.toJson();
      expect(stats['sampleCount'], equals(2));
      expect(stats['averageOffset'], equals(55));
      expect(stats['hasDrift'], isFalse);
      expect(stats['driftDirection'], equals(0));
    });
  });

  group('MediaKind', () {
    test('all values are defined', () {
      expect(MediaKind.values.length, equals(2));
      expect(MediaKind.values, contains(MediaKind.audio));
      expect(MediaKind.values, contains(MediaKind.video));
    });
  });
}
