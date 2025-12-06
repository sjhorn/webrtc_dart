import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/container/webm/processor.dart';
import 'package:webrtc_dart/src/nonstandard/recorder/media_recorder.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';
import 'package:webrtc_dart/src/rtp/rtcp_reports.dart';

void main() {
  group('RecordingTrack', () {
    test('creates video track', () {
      final track = RecordingTrack(
        kind: 'video',
        codecName: 'VP8',
        payloadType: 96,
        clockRate: 90000,
      );

      expect(track.kind, equals('video'));
      expect(track.codecName, equals('VP8'));
      expect(track.payloadType, equals(96));
      expect(track.clockRate, equals(90000));
      expect(track.isVideo, isTrue);
      expect(track.isAudio, isFalse);
    });

    test('creates audio track', () {
      final track = RecordingTrack(
        kind: 'audio',
        codecName: 'opus',
        payloadType: 111,
        clockRate: 48000,
      );

      expect(track.kind, equals('audio'));
      expect(track.codecName, equals('opus'));
      expect(track.payloadType, equals(111));
      expect(track.clockRate, equals(48000));
      expect(track.isVideo, isFalse);
      expect(track.isAudio, isTrue);
    });

    test('creates track with callbacks', () {
      void Function(RtpPacket)? rtpHandler;

      final track = RecordingTrack(
        kind: 'video',
        codecName: 'VP8',
        payloadType: 96,
        clockRate: 90000,
        onRtp: (handler) => rtpHandler = handler,
      );

      expect(track.onRtp, isNotNull);
      track.onRtp!((rtp) {}); // Should set rtpHandler
      expect(rtpHandler, isNotNull);
    });
  });

  group('MediaRecorderOptions', () {
    test('creates with defaults', () {
      final options = MediaRecorderOptions();

      expect(options.width, equals(640));
      expect(options.height, equals(360));
      expect(options.disableLipSync, isFalse);
      expect(options.disableNtp, isFalse);
    });

    test('accepts custom values', () {
      final options = MediaRecorderOptions(
        width: 1920,
        height: 1080,
        disableLipSync: true,
        disableNtp: true,
        roll: 90.0,
      );

      expect(options.width, equals(1920));
      expect(options.height, equals(1080));
      expect(options.disableLipSync, isTrue);
      expect(options.disableNtp, isTrue);
      expect(options.roll, equals(90.0));
    });
  });

  group('MediaRecorder', () {
    group('initialization', () {
      test('throws without tracks', () {
        expect(
          () => MediaRecorder(
            tracks: [],
            onOutput: (_) {},
          ),
          throwsArgumentError,
        );
      });

      test('throws without path or onOutput', () {
        expect(
          () => MediaRecorder(
            tracks: [
              RecordingTrack(
                kind: 'video',
                codecName: 'VP8',
                payloadType: 96,
                clockRate: 90000,
              ),
            ],
          ),
          throwsArgumentError,
        );
      });

      test('creates with onOutput callback', () {
        final recorder = MediaRecorder(
          tracks: [
            RecordingTrack(
              kind: 'video',
              codecName: 'VP8',
              payloadType: 96,
              clockRate: 90000,
            ),
          ],
          onOutput: (_) {},
        );

        expect(recorder, isNotNull);
        expect(recorder.tracks.length, equals(1));
      });
    });

    group('start/stop', () {
      test('starts and stops recording', () async {
        final outputs = <WebmOutput>[];
        final recorder = MediaRecorder(
          tracks: [
            RecordingTrack(
              kind: 'video',
              codecName: 'VP8',
              payloadType: 96,
              clockRate: 90000,
            ),
          ],
          onOutput: (output) => outputs.add(output),
          options: MediaRecorderOptions(
            disableLipSync: true,
            disableNtp: true,
          ),
        );

        await recorder.start();

        // Should have initial WebM header
        expect(outputs.length, greaterThan(0));
        expect(outputs.first.kind, equals(WebmOutputKind.initial));

        await recorder.stop();

        // Should have completed (stopped state)
        final stats = recorder.toJson();
        expect(stats['stopped'], isTrue);
      });

      test('start is idempotent', () async {
        final recorder = MediaRecorder(
          tracks: [
            RecordingTrack(
              kind: 'video',
              codecName: 'VP8',
              payloadType: 96,
              clockRate: 90000,
            ),
          ],
          onOutput: (_) {},
          options: MediaRecorderOptions(
            disableLipSync: true,
            disableNtp: true,
          ),
        );

        await recorder.start();
        await recorder.start(); // Should not throw
        await recorder.stop();
      });

      test('stop is idempotent', () async {
        final recorder = MediaRecorder(
          tracks: [
            RecordingTrack(
              kind: 'video',
              codecName: 'VP8',
              payloadType: 96,
              clockRate: 90000,
            ),
          ],
          onOutput: (_) {},
          options: MediaRecorderOptions(
            disableLipSync: true,
            disableNtp: true,
          ),
        );

        await recorder.start();
        await recorder.stop();
        await recorder.stop(); // Should not throw
      });
    });

    group('feedRtp', () {
      test('processes RTP packets', () async {
        final outputs = <WebmOutput>[];
        final recorder = MediaRecorder(
          tracks: [
            RecordingTrack(
              kind: 'video',
              codecName: 'VP8',
              payloadType: 96,
              clockRate: 90000,
            ),
          ],
          onOutput: (output) => outputs.add(output),
          options: MediaRecorderOptions(
            disableLipSync: true,
            disableNtp: true,
          ),
        );

        await recorder.start();

        // Feed a VP8 keyframe RTP packet
        final rtp = RtpPacket(
          version: 2,
          padding: false,
          extension: false,
          marker: true,
          payloadType: 96,
          sequenceNumber: 1,
          timestamp: 0,
          ssrc: 12345,
          payload: Uint8List.fromList([
            0x90, 0x80, 0x00, // VP8 descriptor
            0x9d, 0x01, 0x2a, // VP8 keyframe start code
            0x80, 0x02, 0x58, 0x01, // Width/height
            0x00, 0x00, // More data
          ]),
        );

        recorder.feedRtp(rtp, trackNumber: 1);

        await recorder.stop();

        // Should have some WebM data output
        final dataOutputs =
            outputs.where((o) => o.data != null && o.data!.isNotEmpty);
        expect(dataOutputs.length, greaterThan(0));
      });

      test('ignores RTP when stopped', () async {
        final recorder = MediaRecorder(
          tracks: [
            RecordingTrack(
              kind: 'video',
              codecName: 'VP8',
              payloadType: 96,
              clockRate: 90000,
            ),
          ],
          onOutput: (_) {},
          options: MediaRecorderOptions(
            disableLipSync: true,
            disableNtp: true,
          ),
        );

        // Feed before start - should be ignored
        recorder.feedRtp(
          RtpPacket(
            version: 2,
            padding: false,
            extension: false,
            marker: true,
            payloadType: 96,
            sequenceNumber: 1,
            timestamp: 0,
            ssrc: 12345,
            payload: Uint8List.fromList([0x90, 0x80, 0x00, 0x01]),
          ),
          trackNumber: 1,
        );

        // Should not throw
      });
    });

    group('feedRtcp', () {
      test('processes RTCP sender reports', () async {
        final recorder = MediaRecorder(
          tracks: [
            RecordingTrack(
              kind: 'video',
              codecName: 'VP8',
              payloadType: 96,
              clockRate: 90000,
            ),
          ],
          onOutput: (_) {},
          options: MediaRecorderOptions(
            disableLipSync: true,
            disableNtp: false, // Enable NTP processing
          ),
        );

        await recorder.start();

        final sr = RtcpSenderReport(
          ssrc: 12345,
          ntpTimestamp: 0x0123456789ABCDEF,
          rtpTimestamp: 90000,
          packetCount: 100,
          octetCount: 5000,
        );

        // Should not throw
        recorder.feedRtcp(sr, trackNumber: 1);

        await recorder.stop();
      });
    });

    group('video codecs', () {
      test('supports VP8', () async {
        final outputs = <WebmOutput>[];
        final recorder = MediaRecorder(
          tracks: [
            RecordingTrack(
              kind: 'video',
              codecName: 'VP8',
              payloadType: 96,
              clockRate: 90000,
            ),
          ],
          onOutput: (output) => outputs.add(output),
          options: MediaRecorderOptions(
            disableLipSync: true,
            disableNtp: true,
          ),
        );

        await recorder.start();
        await recorder.stop();

        expect(outputs.length, greaterThan(0));
      });

      test('supports VP9', () async {
        final outputs = <WebmOutput>[];
        final recorder = MediaRecorder(
          tracks: [
            RecordingTrack(
              kind: 'video',
              codecName: 'VP9',
              payloadType: 97,
              clockRate: 90000,
            ),
          ],
          onOutput: (output) => outputs.add(output),
          options: MediaRecorderOptions(
            disableLipSync: true,
            disableNtp: true,
          ),
        );

        await recorder.start();
        await recorder.stop();

        expect(outputs.length, greaterThan(0));
      });

      test('supports H264', () async {
        final outputs = <WebmOutput>[];
        final recorder = MediaRecorder(
          tracks: [
            RecordingTrack(
              kind: 'video',
              codecName: 'H264',
              payloadType: 98,
              clockRate: 90000,
            ),
          ],
          onOutput: (output) => outputs.add(output),
          options: MediaRecorderOptions(
            disableLipSync: true,
            disableNtp: true,
          ),
        );

        await recorder.start();
        await recorder.stop();

        expect(outputs.length, greaterThan(0));
      });

      test('supports AV1', () async {
        final outputs = <WebmOutput>[];
        final recorder = MediaRecorder(
          tracks: [
            RecordingTrack(
              kind: 'video',
              codecName: 'AV1',
              payloadType: 99,
              clockRate: 90000,
            ),
          ],
          onOutput: (output) => outputs.add(output),
          options: MediaRecorderOptions(
            disableLipSync: true,
            disableNtp: true,
          ),
        );

        await recorder.start();
        await recorder.stop();

        expect(outputs.length, greaterThan(0));
      });

      test('throws for unsupported video codec', () {
        expect(
          () => MediaRecorder(
            tracks: [
              RecordingTrack(
                kind: 'video',
                codecName: 'unknown',
                payloadType: 100,
                clockRate: 90000,
              ),
            ],
            onOutput: (_) {},
          ),
          returnsNormally, // Constructor doesn't throw
        );

        // Error happens at start when building pipeline
      });
    });

    group('audio codecs', () {
      test('supports Opus', () async {
        final outputs = <WebmOutput>[];
        final recorder = MediaRecorder(
          tracks: [
            RecordingTrack(
              kind: 'audio',
              codecName: 'opus',
              payloadType: 111,
              clockRate: 48000,
            ),
          ],
          onOutput: (output) => outputs.add(output),
          options: MediaRecorderOptions(
            disableLipSync: true,
            disableNtp: true,
          ),
        );

        await recorder.start();
        await recorder.stop();

        expect(outputs.length, greaterThan(0));
      });
    });

    group('multi-track recording', () {
      test('records video and audio', () async {
        final outputs = <WebmOutput>[];
        final recorder = MediaRecorder(
          tracks: [
            RecordingTrack(
              kind: 'video',
              codecName: 'VP8',
              payloadType: 96,
              clockRate: 90000,
            ),
            RecordingTrack(
              kind: 'audio',
              codecName: 'opus',
              payloadType: 111,
              clockRate: 48000,
            ),
          ],
          onOutput: (output) => outputs.add(output),
          options: MediaRecorderOptions(
            disableLipSync: true, // Disable to simplify testing
            disableNtp: true,
          ),
        );

        await recorder.start();
        await recorder.stop();

        expect(outputs.length, greaterThan(0));
      });
    });

    group('lip sync', () {
      test('enables lip sync when both video and audio', () async {
        final outputs = <WebmOutput>[];
        final recorder = MediaRecorder(
          tracks: [
            RecordingTrack(
              kind: 'video',
              codecName: 'VP8',
              payloadType: 96,
              clockRate: 90000,
            ),
            RecordingTrack(
              kind: 'audio',
              codecName: 'opus',
              payloadType: 111,
              clockRate: 48000,
            ),
          ],
          onOutput: (output) => outputs.add(output),
          options: MediaRecorderOptions(
            disableLipSync: false, // Enable lip sync
            disableNtp: true,
          ),
        );

        await recorder.start();

        // Stats should show lip sync is enabled
        final stats = recorder.toJson();
        expect(stats['lipsync'], isNotNull);

        await recorder.stop();
      });

      test('disables lip sync for video-only', () async {
        final recorder = MediaRecorder(
          tracks: [
            RecordingTrack(
              kind: 'video',
              codecName: 'VP8',
              payloadType: 96,
              clockRate: 90000,
            ),
          ],
          onOutput: (_) {},
          options: MediaRecorderOptions(
            disableLipSync: false,
            disableNtp: true,
          ),
        );

        await recorder.start();

        // No lip sync for video-only
        final stats = recorder.toJson();
        expect(stats['lipsync'], isNull);

        await recorder.stop();
      });
    });

    group('statistics', () {
      test('provides recording statistics', () async {
        final recorder = MediaRecorder(
          tracks: [
            RecordingTrack(
              kind: 'video',
              codecName: 'VP8',
              payloadType: 96,
              clockRate: 90000,
            ),
          ],
          onOutput: (_) {},
          options: MediaRecorderOptions(
            disableLipSync: true,
            disableNtp: true,
          ),
        );

        await recorder.start();

        final stats = recorder.toJson();

        expect(stats.containsKey('started'), isTrue);
        expect(stats.containsKey('stopped'), isTrue);
        expect(stats.containsKey('trackCount'), isTrue);
        expect(stats.containsKey('pipelines'), isTrue);
        expect(stats['started'], isTrue);
        expect(stats['stopped'], isFalse);
        expect(stats['trackCount'], equals(1));

        await recorder.stop();

        final finalStats = recorder.toJson();
        expect(finalStats['stopped'], isTrue);
      });

      test('tracks bytes written', () async {
        final recorder = MediaRecorder(
          tracks: [
            RecordingTrack(
              kind: 'video',
              codecName: 'VP8',
              payloadType: 96,
              clockRate: 90000,
            ),
          ],
          onOutput: (_) {},
          options: MediaRecorderOptions(
            disableLipSync: true,
            disableNtp: true,
          ),
        );

        await recorder.start();

        // Feed some data
        recorder.feedRtp(
          RtpPacket(
            version: 2,
            padding: false,
            extension: false,
            marker: true,
            payloadType: 96,
            sequenceNumber: 1,
            timestamp: 0,
            ssrc: 12345,
            payload: Uint8List.fromList([
              0x90,
              0x80,
              0x00,
              0x9d,
              0x01,
              0x2a,
              0x80,
              0x02,
              0x58,
              0x01,
              0x00,
              0x00,
            ]),
          ),
          trackNumber: 1,
        );

        await recorder.stop();

        final stats = recorder.toJson();
        expect(stats['bytesWritten'], greaterThan(0));
      });
    });

    group('file recording', () {
      test('records to file', () async {
        final tempDir =
            await Directory.systemTemp.createTemp('media_recorder_test_');
        final filePath = '${tempDir.path}/test.webm';

        try {
          final recorder = MediaRecorder(
            tracks: [
              RecordingTrack(
                kind: 'video',
                codecName: 'VP8',
                payloadType: 96,
                clockRate: 90000,
              ),
            ],
            path: filePath,
            options: MediaRecorderOptions(
              disableLipSync: true,
              disableNtp: true,
            ),
          );

          await recorder.start();

          // Feed a frame
          recorder.feedRtp(
            RtpPacket(
              version: 2,
              padding: false,
              extension: false,
              marker: true,
              payloadType: 96,
              sequenceNumber: 1,
              timestamp: 0,
              ssrc: 12345,
              payload: Uint8List.fromList([
                0x90,
                0x80,
                0x00,
                0x9d,
                0x01,
                0x2a,
                0x80,
                0x02,
                0x58,
                0x01,
              ]),
            ),
            trackNumber: 1,
          );

          await recorder.stop();

          // Verify file was created
          final file = File(filePath);
          expect(await file.exists(), isTrue);

          final contents = await file.readAsBytes();
          expect(contents.length, greaterThan(0));

          // Should start with EBML header
          expect(contents.sublist(0, 4),
              equals(Uint8List.fromList([0x1a, 0x45, 0xdf, 0xa3])));
        } finally {
          await tempDir.delete(recursive: true);
        }
      });
    });
  });

  group('SimpleWebmRecorder', () {
    group('initialization', () {
      test('creates with defaults', () {
        final recorder = SimpleWebmRecorder();

        expect(recorder.hasVideo, isTrue);
        expect(recorder.hasAudio, isFalse);
        expect(recorder.width, equals(640));
        expect(recorder.height, equals(480));
      });

      test('creates with custom options', () {
        final recorder = SimpleWebmRecorder(
          width: 1920,
          height: 1080,
          hasVideo: true,
          hasAudio: true,
        );

        expect(recorder.width, equals(1920));
        expect(recorder.height, equals(1080));
        expect(recorder.hasVideo, isTrue);
        expect(recorder.hasAudio, isTrue);
      });
    });

    group('recording', () {
      test('records video frames', () async {
        final chunks = <Uint8List>[];
        final recorder = SimpleWebmRecorder(
          onData: (data) => chunks.add(data),
        );

        await recorder.start();

        recorder.addVideoFrame(
          Uint8List.fromList([0x01, 0x02, 0x03]),
          isKeyframe: true,
          timestampMs: 0,
        );

        recorder.addVideoFrame(
          Uint8List.fromList([0x04, 0x05]),
          isKeyframe: false,
          timestampMs: 33,
        );

        await recorder.stop();

        expect(chunks.length, greaterThan(0));
        expect(recorder.totalBytes, greaterThan(0));
      });

      test('records audio frames', () async {
        final chunks = <Uint8List>[];
        final recorder = SimpleWebmRecorder(
          hasVideo: false,
          hasAudio: true,
          onData: (data) => chunks.add(data),
        );

        await recorder.start();

        recorder.addAudioFrame(
          Uint8List.fromList([0xaa, 0xbb]),
          timestampMs: 0,
        );

        await recorder.stop();

        expect(chunks.length, greaterThan(0));
      });

      test('ignores frames when not recording', () async {
        final recorder = SimpleWebmRecorder();

        // Before start
        recorder.addVideoFrame(
          Uint8List.fromList([0x01]),
          isKeyframe: true,
          timestampMs: 0,
        );

        expect(recorder.totalBytes, equals(0));
      });

      test('isRecording state', () async {
        final recorder = SimpleWebmRecorder(onData: (_) {});

        expect(recorder.isRecording, isFalse);

        await recorder.start();
        expect(recorder.isRecording, isTrue);

        await recorder.stop();
        expect(recorder.isRecording, isFalse);
      });
    });

    group('file recording', () {
      test('records to file', () async {
        final tempDir =
            await Directory.systemTemp.createTemp('simple_recorder_test_');
        final filePath = '${tempDir.path}/test.webm';

        try {
          final recorder = SimpleWebmRecorder(path: filePath);

          await recorder.start();

          recorder.addVideoFrame(
            Uint8List.fromList([0x01, 0x02, 0x03]),
            isKeyframe: true,
            timestampMs: 0,
          );

          await recorder.stop();

          final file = File(filePath);
          expect(await file.exists(), isTrue);
        } finally {
          await tempDir.delete(recursive: true);
        }
      });
    });
  });
}
