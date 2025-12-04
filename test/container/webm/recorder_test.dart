import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/container/webm/container.dart';
import 'package:webrtc_dart/src/container/webm/recorder.dart';

void main() {
  group('WebmRecorder', () {
    group('initialization', () {
      test('creates recorder with defaults', () {
        final recorder = WebmRecorder();

        expect(recorder.hasVideo, isTrue);
        expect(recorder.hasAudio, isFalse);
        expect(recorder.state, equals(RecorderState.inactive));
      });

      test('creates recorder with video and audio', () {
        final recorder = WebmRecorder(hasVideo: true, hasAudio: true);

        expect(recorder.hasVideo, isTrue);
        expect(recorder.hasAudio, isTrue);
      });

      test('creates recorder with audio only', () {
        final recorder = WebmRecorder(hasVideo: false, hasAudio: true);

        expect(recorder.hasVideo, isFalse);
        expect(recorder.hasAudio, isTrue);
      });

      test('creates recorder with custom options', () {
        final recorder = WebmRecorder(
          options: WebmRecorderOptions(
            width: 1920,
            height: 1080,
            videoCodec: WebmCodec.vp9,
          ),
        );

        expect(recorder.options.width, equals(1920));
        expect(recorder.options.height, equals(1080));
        expect(recorder.options.videoCodec, equals(WebmCodec.vp9));
      });
    });

    group('startBuffer', () {
      test('starts recording to buffer', () {
        final recorder = WebmRecorder();
        recorder.startBuffer();

        expect(recorder.state, equals(RecorderState.recording));
      });

      test('throws if already recording', () {
        final recorder = WebmRecorder();
        recorder.startBuffer();

        expect(() => recorder.startBuffer(), throwsStateError);
      });
    });

    group('startStream', () {
      test('starts recording with stream callback', () {
        final chunks = <Uint8List>[];
        final recorder = WebmRecorder();

        recorder.startStream((data) => chunks.add(data));

        expect(recorder.state, equals(RecorderState.recording));
        // Should have initial header
        expect(chunks.length, greaterThan(0));
      });

      test('callback receives data chunks', () {
        final chunks = <Uint8List>[];
        final recorder = WebmRecorder();

        recorder.startStream((data) => chunks.add(data));

        recorder.addVideoFrame(
          Uint8List.fromList([0x01, 0x02, 0x03]),
          isKeyframe: true,
          timestampMs: 0,
        );

        // Should have: initial + cluster + block
        expect(chunks.length, greaterThanOrEqualTo(2));
      });
    });

    group('addVideoFrame', () {
      test('adds video frame', () async {
        final recorder = WebmRecorder();
        recorder.startBuffer();

        recorder.addVideoFrame(
          Uint8List.fromList([0x01, 0x02, 0x03]),
          isKeyframe: true,
          timestampMs: 0,
        );

        final result = await recorder.stop();
        expect(result.totalBytes, greaterThan(0));
      });

      test('ignores frames when not recording', () async {
        final recorder = WebmRecorder();

        // Should not throw
        recorder.addVideoFrame(
          Uint8List.fromList([0x01]),
          isKeyframe: true,
          timestampMs: 0,
        );

        expect(recorder.totalBytes, equals(0));
      });

      test('ignores video frames when hasVideo is false', () async {
        final recorder = WebmRecorder(hasVideo: false, hasAudio: true);
        recorder.startBuffer();

        recorder.addVideoFrame(
          Uint8List.fromList([0x01]),
          isKeyframe: true,
          timestampMs: 0,
        );

        // Only has audio, so no video blocks
        recorder.addAudioFrame(
          Uint8List.fromList([0xaa]),
          timestampMs: 0,
        );

        final result = await recorder.stop();
        expect(result.totalBytes, greaterThan(0));
      });
    });

    group('addAudioFrame', () {
      test('adds audio frame', () async {
        final recorder = WebmRecorder(hasVideo: false, hasAudio: true);
        recorder.startBuffer();

        recorder.addAudioFrame(
          Uint8List.fromList([0xaa, 0xbb, 0xcc]),
          timestampMs: 0,
        );

        final result = await recorder.stop();
        expect(result.totalBytes, greaterThan(0));
      });

      test('ignores audio frames when hasAudio is false', () async {
        final recorder = WebmRecorder(hasVideo: true, hasAudio: false);
        recorder.startBuffer();

        recorder.addAudioFrame(
          Uint8List.fromList([0xaa]),
          timestampMs: 0,
        );

        recorder.addVideoFrame(
          Uint8List.fromList([0x01]),
          isKeyframe: true,
          timestampMs: 0,
        );

        final result = await recorder.stop();
        expect(result.totalBytes, greaterThan(0));
      });
    });

    group('addFrame', () {
      test('adds video frame via generic method', () async {
        final recorder = WebmRecorder();
        recorder.startBuffer();

        recorder.addFrame(MediaFrame(
          data: Uint8List.fromList([0x01, 0x02]),
          isKeyframe: true,
          timestampMs: 0,
          kind: MediaFrameKind.video,
        ));

        final result = await recorder.stop();
        expect(result.totalBytes, greaterThan(0));
      });

      test('adds audio frame via generic method', () async {
        final recorder = WebmRecorder(hasVideo: false, hasAudio: true);
        recorder.startBuffer();

        recorder.addFrame(MediaFrame(
          data: Uint8List.fromList([0xaa, 0xbb]),
          isKeyframe: true,
          timestampMs: 0,
          kind: MediaFrameKind.audio,
        ));

        final result = await recorder.stop();
        expect(result.totalBytes, greaterThan(0));
      });
    });

    group('pause/resume', () {
      test('pauses recording', () {
        final recorder = WebmRecorder();
        recorder.startBuffer();

        recorder.pause();

        expect(recorder.state, equals(RecorderState.paused));
      });

      test('resumes recording', () {
        final recorder = WebmRecorder();
        recorder.startBuffer();
        recorder.pause();

        recorder.resume();

        expect(recorder.state, equals(RecorderState.recording));
      });

      test('ignores frames when paused', () async {
        final recorder = WebmRecorder();
        recorder.startBuffer();

        recorder.addVideoFrame(
          Uint8List.fromList([0x01]),
          isKeyframe: true,
          timestampMs: 0,
        );

        recorder.pause();

        // These should be ignored
        recorder.addVideoFrame(
          Uint8List.fromList([0x02]),
          isKeyframe: false,
          timestampMs: 100,
        );

        recorder.resume();

        recorder.addVideoFrame(
          Uint8List.fromList([0x03]),
          isKeyframe: false,
          timestampMs: 200,
        );

        final result = await recorder.stop();
        expect(result.totalBytes, greaterThan(0));
      });
    });

    group('stop', () {
      test('stops recording', () async {
        final recorder = WebmRecorder();
        recorder.startBuffer();

        recorder.addVideoFrame(
          Uint8List.fromList([0x01]),
          isKeyframe: true,
          timestampMs: 0,
        );

        final result = await recorder.stop();

        expect(recorder.state, equals(RecorderState.stopped));
        expect(result.totalBytes, greaterThan(0));
      });

      test('returns buffer data', () async {
        final recorder = WebmRecorder();
        recorder.startBuffer();

        recorder.addVideoFrame(
          Uint8List.fromList([0x01]),
          isKeyframe: true,
          timestampMs: 0,
        );

        final result = await recorder.stop();

        expect(result.data, isNotNull);
        expect(result.data!.length, equals(result.totalBytes));
      });

      test('throws if not recording', () {
        final recorder = WebmRecorder();

        expect(() => recorder.stop(), throwsStateError);
      });

      test('returns duration', () async {
        final recorder = WebmRecorder();
        recorder.startBuffer();

        await Future.delayed(Duration(milliseconds: 50));

        recorder.addVideoFrame(
          Uint8List.fromList([0x01]),
          isKeyframe: true,
          timestampMs: 0,
        );

        final result = await recorder.stop();

        expect(result.duration.inMilliseconds, greaterThanOrEqualTo(50));
      });
    });

    group('onData stream', () {
      test('emits data chunks', () async {
        final recorder = WebmRecorder();
        final chunks = <Uint8List>[];

        recorder.onData.listen(chunks.add);
        recorder.startBuffer();

        recorder.addVideoFrame(
          Uint8List.fromList([0x01]),
          isKeyframe: true,
          timestampMs: 0,
        );

        await Future.delayed(Duration(milliseconds: 10));

        expect(chunks.length, greaterThan(0));

        await recorder.stop();
      });
    });

    group('dispose', () {
      test('disposes recorder', () async {
        final recorder = WebmRecorder();
        recorder.startBuffer();

        await recorder.dispose();

        expect(recorder.state, equals(RecorderState.stopped));
      });

      test('can dispose inactive recorder', () async {
        final recorder = WebmRecorder();

        await recorder.dispose();
        // Should not throw
      });
    });

    group('recording scenarios', () {
      test('records video only', () async {
        final recorder = WebmRecorder(hasVideo: true, hasAudio: false);
        recorder.startBuffer();

        for (var i = 0; i < 10; i++) {
          recorder.addVideoFrame(
            Uint8List.fromList([0x10 + i, 0x20 + i]),
            isKeyframe: i == 0 || i == 5,
            timestampMs: i * 33, // ~30fps
          );
        }

        final result = await recorder.stop();

        expect(result.totalBytes, greaterThan(100));
        expect(result.data, isNotNull);
        // Should start with EBML header
        expect(result.data!.sublist(0, 4),
            equals(Uint8List.fromList([0x1a, 0x45, 0xdf, 0xa3])));
      });

      test('records audio only', () async {
        final recorder = WebmRecorder(hasVideo: false, hasAudio: true);
        recorder.startBuffer();

        for (var i = 0; i < 10; i++) {
          recorder.addAudioFrame(
            Uint8List.fromList([0xa0 + i, 0xb0 + i]),
            timestampMs: i * 20, // 50fps audio
          );
        }

        final result = await recorder.stop();

        expect(result.totalBytes, greaterThan(100));
        expect(result.data, isNotNull);
      });

      test('records video and audio', () async {
        final recorder = WebmRecorder(hasVideo: true, hasAudio: true);
        recorder.startBuffer();

        for (var i = 0; i < 10; i++) {
          recorder.addVideoFrame(
            Uint8List.fromList([0x10 + i]),
            isKeyframe: i == 0,
            timestampMs: i * 33,
          );
          recorder.addAudioFrame(
            Uint8List.fromList([0xa0 + i]),
            timestampMs: i * 20,
          );
        }

        final result = await recorder.stop();

        expect(result.totalBytes, greaterThan(100));
      });

      test('records with custom codec', () async {
        final recorder = WebmRecorder(
          options: WebmRecorderOptions(
            videoCodec: WebmCodec.vp9,
            width: 1280,
            height: 720,
          ),
        );
        recorder.startBuffer();

        recorder.addVideoFrame(
          Uint8List.fromList([0x01, 0x02, 0x03]),
          isKeyframe: true,
          timestampMs: 0,
        );

        final result = await recorder.stop();
        expect(result.totalBytes, greaterThan(50));
      });
    });

    group('file recording', () {
      test('records to file', () async {
        final tempDir = await Directory.systemTemp.createTemp('webm_test_');
        final filePath = '${tempDir.path}/test.webm';

        try {
          final recorder = WebmRecorder();
          await recorder.startFile(filePath);

          recorder.addVideoFrame(
            Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0x05]),
            isKeyframe: true,
            timestampMs: 0,
          );

          recorder.addVideoFrame(
            Uint8List.fromList([0x06, 0x07, 0x08]),
            isKeyframe: false,
            timestampMs: 33,
          );

          final result = await recorder.stop();

          // Check file was created
          final file = File(filePath);
          expect(await file.exists(), isTrue);

          // Check file contents
          final contents = await file.readAsBytes();
          expect(contents.length, equals(result.totalBytes));

          // Should start with EBML header
          expect(contents.sublist(0, 4),
              equals(Uint8List.fromList([0x1a, 0x45, 0xdf, 0xa3])));
        } finally {
          await tempDir.delete(recursive: true);
        }
      });
    });
  });

  group('WebmRecorderOptions', () {
    test('has default values', () {
      final options = WebmRecorderOptions();

      expect(options.width, equals(640));
      expect(options.height, equals(480));
      expect(options.videoCodec, equals(WebmCodec.vp8));
      expect(options.audioCodec, equals(WebmCodec.opus));
      expect(options.durationMs, isNull);
      expect(options.roll, isNull);
    });

    test('accepts custom values', () {
      final options = WebmRecorderOptions(
        width: 3840,
        height: 2160,
        videoCodec: WebmCodec.av1,
        audioCodec: WebmCodec.opus,
        durationMs: 60000,
        roll: 90.0,
      );

      expect(options.width, equals(3840));
      expect(options.height, equals(2160));
      expect(options.videoCodec, equals(WebmCodec.av1));
      expect(options.durationMs, equals(60000));
      expect(options.roll, equals(90.0));
    });
  });

  group('MediaFrame', () {
    test('creates video frame', () {
      final frame = MediaFrame(
        data: Uint8List.fromList([0x01, 0x02]),
        isKeyframe: true,
        timestampMs: 100,
        kind: MediaFrameKind.video,
      );

      expect(frame.data.length, equals(2));
      expect(frame.isKeyframe, isTrue);
      expect(frame.timestampMs, equals(100));
      expect(frame.kind, equals(MediaFrameKind.video));
    });

    test('creates audio frame', () {
      final frame = MediaFrame(
        data: Uint8List.fromList([0xaa]),
        isKeyframe: false,
        timestampMs: 50,
        kind: MediaFrameKind.audio,
      );

      expect(frame.kind, equals(MediaFrameKind.audio));
    });
  });

  group('WebmRecordingResult', () {
    test('contains recording info', () {
      final result = WebmRecordingResult(
        totalBytes: 1000,
        duration: Duration(seconds: 5),
        data: Uint8List(1000),
      );

      expect(result.totalBytes, equals(1000));
      expect(result.duration.inSeconds, equals(5));
      expect(result.data?.length, equals(1000));
    });
  });
}
