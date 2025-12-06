import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/container/webm/container.dart';
import 'package:webrtc_dart/src/container/webm/processor.dart';

void main() {
  group('WebmProcessor', () {
    group('start', () {
      test('writes initial header and segment', () {
        final outputs = <WebmOutput>[];
        final processor = WebmProcessor(
          tracks: [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8),
          ],
          onOutput: outputs.add,
        );

        processor.start();

        expect(outputs.length, equals(1));
        expect(outputs[0].kind, equals(WebmOutputKind.initial));
        expect(outputs[0].data, isNotNull);
        expect(outputs[0].data!.length, greaterThan(50));

        // Should start with EBML header
        expect(outputs[0].data!.sublist(0, 4),
            equals(Uint8List.fromList([0x1a, 0x45, 0xdf, 0xa3])));
      });

      test('only writes header once', () {
        final outputs = <WebmOutput>[];
        final processor = WebmProcessor(
          tracks: [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8),
          ],
          onOutput: outputs.add,
        );

        processor.start();
        processor.start();

        expect(outputs.length, equals(1));
      });
    });

    group('processFrame', () {
      test('creates cluster on first frame', () {
        final outputs = <WebmOutput>[];
        final processor = WebmProcessor(
          tracks: [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8),
          ],
          onOutput: outputs.add,
        );

        processor.start();
        processor.processFrame(WebmFrame(
          data: Uint8List.fromList([0x01, 0x02, 0x03]),
          isKeyframe: true,
          timeMs: 0,
          trackNumber: 1,
        ));

        // Should have: initial, cluster, block
        expect(outputs.length, equals(3));
        expect(outputs[0].kind, equals(WebmOutputKind.initial));
        expect(outputs[1].kind, equals(WebmOutputKind.cluster));
        expect(outputs[2].kind, equals(WebmOutputKind.block));
      });

      test('creates new cluster on video keyframe', () {
        final outputs = <WebmOutput>[];
        final processor = WebmProcessor(
          tracks: [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8),
          ],
          onOutput: outputs.add,
        );

        processor.start();

        // First keyframe
        processor.processFrame(WebmFrame(
          data: Uint8List.fromList([0x01]),
          isKeyframe: true,
          timeMs: 0,
          trackNumber: 1,
        ));

        // Non-keyframe
        processor.processFrame(WebmFrame(
          data: Uint8List.fromList([0x02]),
          isKeyframe: false,
          timeMs: 100,
          trackNumber: 1,
        ));

        // Second keyframe - should create new cluster
        processor.processFrame(WebmFrame(
          data: Uint8List.fromList([0x03]),
          isKeyframe: true,
          timeMs: 200,
          trackNumber: 1,
        ));

        final clusterCount =
            outputs.where((o) => o.kind == WebmOutputKind.cluster).length;
        expect(clusterCount, equals(2));
      });

      test('handles multiple tracks', () {
        final outputs = <WebmOutput>[];
        final processor = WebmProcessor(
          tracks: [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8),
            WebmTrack(
                trackNumber: 2, kind: TrackKind.audio, codec: WebmCodec.opus),
          ],
          onOutput: outputs.add,
        );

        processor.start();

        processor.processFrame(WebmFrame(
          data: Uint8List.fromList([0x01]),
          isKeyframe: true,
          timeMs: 0,
          trackNumber: 1,
        ));

        processor.processFrame(WebmFrame(
          data: Uint8List.fromList([0xaa]),
          isKeyframe: true,
          timeMs: 10,
          trackNumber: 2,
        ));

        final blockCount =
            outputs.where((o) => o.kind == WebmOutputKind.block).length;
        expect(blockCount, equals(2));
      });

      test('throws on unknown track', () {
        final outputs = <WebmOutput>[];
        final processor = WebmProcessor(
          tracks: [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8),
          ],
          onOutput: outputs.add,
        );

        processor.start();

        expect(
          () => processor.processFrame(WebmFrame(
            data: Uint8List.fromList([0x01]),
            isKeyframe: true,
            timeMs: 0,
            trackNumber: 99,
          )),
          throwsArgumentError,
        );
      });
    });

    group('processVideoFrame', () {
      test('waits for keyframe before processing', () {
        final outputs = <WebmOutput>[];
        final processor = WebmProcessor(
          tracks: [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8),
          ],
          onOutput: outputs.add,
        );

        processor.start();

        // Non-keyframe first - should be ignored
        processor.processVideoFrame(WebmFrame(
          data: Uint8List.fromList([0x01]),
          isKeyframe: false,
          timeMs: 0,
          trackNumber: 1,
        ));

        expect(outputs.length, equals(1)); // Only initial

        // Now send keyframe
        processor.processVideoFrame(WebmFrame(
          data: Uint8List.fromList([0x02]),
          isKeyframe: true,
          timeMs: 100,
          trackNumber: 1,
        ));

        expect(outputs.length, equals(3)); // initial + cluster + block
      });

      test('sets videoKeyframeReceived flag', () {
        final outputs = <WebmOutput>[];
        final processor = WebmProcessor(
          tracks: [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8),
          ],
          onOutput: outputs.add,
        );

        expect(processor.videoKeyframeReceived, isFalse);

        processor.start();
        processor.processVideoFrame(WebmFrame(
          data: Uint8List.fromList([0x01]),
          isKeyframe: true,
          timeMs: 0,
          trackNumber: 1,
        ));

        expect(processor.videoKeyframeReceived, isTrue);
      });
    });

    group('processAudioFrame', () {
      test('processes audio frames', () {
        final outputs = <WebmOutput>[];
        final processor = WebmProcessor(
          tracks: [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.audio, codec: WebmCodec.opus),
          ],
          onOutput: outputs.add,
        );

        processor.start();
        processor.processAudioFrame(WebmFrame(
          data: Uint8List.fromList([0xaa, 0xbb]),
          isKeyframe: true,
          timeMs: 0,
          trackNumber: 1,
        ));

        expect(outputs.length, equals(3)); // initial + cluster + block
      });
    });

    group('stop', () {
      test('writes cue points and end of stream', () {
        final outputs = <WebmOutput>[];
        final processor = WebmProcessor(
          tracks: [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8),
          ],
          onOutput: outputs.add,
        );

        processor.start();
        processor.processFrame(WebmFrame(
          data: Uint8List.fromList([0x01]),
          isKeyframe: true,
          timeMs: 0,
          trackNumber: 1,
        ));

        processor.stop();

        expect(outputs.any((o) => o.kind == WebmOutputKind.cuePoints), isTrue);
        expect(
            outputs.any((o) => o.kind == WebmOutputKind.endOfStream), isTrue);

        final eos =
            outputs.firstWhere((o) => o.kind == WebmOutputKind.endOfStream);
        expect(eos.endOfStream, isNotNull);
        expect(eos.endOfStream!.header, isNotNull);
        expect(eos.endOfStream!.durationElement, isNotNull);
      });

      test('sets stopped flag', () {
        final outputs = <WebmOutput>[];
        final processor = WebmProcessor(
          tracks: [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8),
          ],
          onOutput: outputs.add,
        );

        expect(processor.stopped, isFalse);

        processor.start();
        processor.stop();

        expect(processor.stopped, isTrue);
      });

      test('only stops once', () {
        final outputs = <WebmOutput>[];
        final processor = WebmProcessor(
          tracks: [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8),
          ],
          onOutput: outputs.add,
        );

        processor.start();
        processor.stop();
        final outputCount = outputs.length;
        processor.stop();

        expect(outputs.length, equals(outputCount));
      });

      test('ignores frames after stop', () {
        final outputs = <WebmOutput>[];
        final processor = WebmProcessor(
          tracks: [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8),
          ],
          onOutput: outputs.add,
        );

        processor.start();
        processor.stop();
        final outputCount = outputs.length;

        processor.processFrame(WebmFrame(
          data: Uint8List.fromList([0x01]),
          isKeyframe: true,
          timeMs: 0,
          trackNumber: 1,
        ));

        expect(outputs.length, equals(outputCount));
      });
    });

    group('endAudio/endVideo', () {
      test('stops when both tracks end', () {
        final outputs = <WebmOutput>[];
        final processor = WebmProcessor(
          tracks: [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8),
            WebmTrack(
                trackNumber: 2, kind: TrackKind.audio, codec: WebmCodec.opus),
          ],
          onOutput: outputs.add,
        );

        processor.start();

        processor.endAudio();
        expect(processor.stopped, isFalse);

        processor.endVideo();
        expect(processor.stopped, isTrue);
      });

      test('does not stop with single track', () {
        final outputs = <WebmOutput>[];
        final processor = WebmProcessor(
          tracks: [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8),
          ],
          onOutput: outputs.add,
        );

        processor.start();
        processor.endVideo();

        // Should not auto-stop with single track
        expect(processor.videoStopped, isTrue);
      });
    });

    group('timestamp handling', () {
      test('handles sequential timestamps', () {
        final outputs = <WebmOutput>[];
        final processor = WebmProcessor(
          tracks: [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8),
          ],
          onOutput: outputs.add,
        );

        processor.start();

        for (var i = 0; i < 10; i++) {
          processor.processFrame(WebmFrame(
            data: Uint8List.fromList([i]),
            isKeyframe: i == 0,
            timeMs: i * 100,
            trackNumber: 1,
          ));
        }

        final blockCount =
            outputs.where((o) => o.kind == WebmOutputKind.block).length;
        expect(blockCount, equals(10));
      });

      test('creates new cluster on timestamp overflow', () {
        final outputs = <WebmOutput>[];
        final processor = WebmProcessor(
          tracks: [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8),
          ],
          onOutput: outputs.add,
        );

        processor.start();

        // First frame
        processor.processFrame(WebmFrame(
          data: Uint8List.fromList([0x01]),
          isKeyframe: true,
          timeMs: 0,
          trackNumber: 1,
        ));

        // Frame at > maxSigned16Int (32767) ms
        processor.processFrame(WebmFrame(
          data: Uint8List.fromList([0x02]),
          isKeyframe: false,
          timeMs: 40000,
          trackNumber: 1,
        ));

        final clusterCount =
            outputs.where((o) => o.kind == WebmOutputKind.cluster).length;
        expect(clusterCount, equals(2));
      });
    });

    group('strict timestamp mode', () {
      test('rejects out-of-order frames when enabled', () {
        final outputs = <WebmOutput>[];
        final processor = WebmProcessor(
          tracks: [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8),
          ],
          onOutput: outputs.add,
          options: WebmProcessorOptions(strictTimestamp: true),
        );

        processor.start();

        // First frame at t=0
        processor.processFrame(WebmFrame(
          data: Uint8List.fromList([0x01]),
          isKeyframe: true,
          timeMs: 0,
          trackNumber: 1,
        ));

        // Skip to t=200
        processor.processFrame(WebmFrame(
          data: Uint8List.fromList([0x02]),
          isKeyframe: false,
          timeMs: 200,
          trackNumber: 1,
        ));

        // Out of order frame (t=100 < t=200 elapsed, but still positive elapsed)
        // With strict=true, this should be rejected
        processor.processFrame(WebmFrame(
          data: Uint8List.fromList([0x03]),
          isKeyframe: false,
          timeMs: 100,
          trackNumber: 1,
        ));

        // Should only have 2 blocks (third frame rejected due to strict mode)
        final blockCount =
            outputs.where((o) => o.kind == WebmOutputKind.block).length;
        expect(blockCount, equals(2));
      });

      test('accepts out-of-order frames when disabled', () {
        final outputs = <WebmOutput>[];
        final processor = WebmProcessor(
          tracks: [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8),
          ],
          onOutput: outputs.add,
          options: WebmProcessorOptions(strictTimestamp: false),
        );

        processor.start();

        // First frame at t=0
        processor.processFrame(WebmFrame(
          data: Uint8List.fromList([0x01]),
          isKeyframe: true,
          timeMs: 0,
          trackNumber: 1,
        ));

        // Skip to t=200
        processor.processFrame(WebmFrame(
          data: Uint8List.fromList([0x02]),
          isKeyframe: false,
          timeMs: 200,
          trackNumber: 1,
        ));

        // Out of order frame (t=100 < t=200 elapsed, but still positive elapsed)
        processor.processFrame(WebmFrame(
          data: Uint8List.fromList([0x03]),
          isKeyframe: false,
          timeMs: 100,
          trackNumber: 1,
        ));

        // Should have 3 blocks (strict=false allows out-of-order within cluster)
        final blockCount =
            outputs.where((o) => o.kind == WebmOutputKind.block).length;
        expect(blockCount, equals(3));
      });
    });

    group('duration', () {
      test('calculates duration on stop', () {
        final outputs = <WebmOutput>[];
        final processor = WebmProcessor(
          tracks: [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8),
          ],
          onOutput: outputs.add,
        );

        processor.start();

        processor.processFrame(WebmFrame(
          data: Uint8List.fromList([0x01]),
          isKeyframe: true,
          timeMs: 0,
          trackNumber: 1,
        ));

        processor.processFrame(WebmFrame(
          data: Uint8List.fromList([0x02]),
          isKeyframe: false,
          timeMs: 5000,
          trackNumber: 1,
        ));

        processor.stop();

        final eos =
            outputs.firstWhere((o) => o.kind == WebmOutputKind.endOfStream);
        expect(eos.endOfStream!.durationMs, equals(5000));
      });

      test('uses expected duration in header', () {
        final outputs = <WebmOutput>[];
        final processor = WebmProcessor(
          tracks: [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8),
          ],
          onOutput: outputs.add,
          options: WebmProcessorOptions(durationMs: 10000),
        );

        processor.start();

        // Initial output should include duration in segment
        expect(outputs[0].kind, equals(WebmOutputKind.initial));
        expect(outputs[0].data!.length, greaterThan(50));
      });
    });

    group('full recording scenario', () {
      test('records video and audio together', () {
        final outputs = <WebmOutput>[];
        final processor = WebmProcessor(
          tracks: [
            WebmTrack(
                trackNumber: 1,
                kind: TrackKind.video,
                codec: WebmCodec.vp8,
                width: 640,
                height: 480),
            WebmTrack(
                trackNumber: 2, kind: TrackKind.audio, codec: WebmCodec.opus),
          ],
          onOutput: outputs.add,
        );

        processor.start();

        // Interleaved video and audio
        for (var i = 0; i < 5; i++) {
          processor.processVideoFrame(WebmFrame(
            data: Uint8List.fromList([0x10 + i]),
            isKeyframe: i == 0,
            timeMs: i * 40,
            trackNumber: 1,
          ));

          processor.processAudioFrame(WebmFrame(
            data: Uint8List.fromList([0xa0 + i]),
            isKeyframe: true,
            timeMs: i * 20,
            trackNumber: 2,
          ));
        }

        processor.stop();

        // Verify outputs
        expect(outputs.any((o) => o.kind == WebmOutputKind.initial), isTrue);
        expect(outputs.any((o) => o.kind == WebmOutputKind.cluster), isTrue);
        expect(outputs.any((o) => o.kind == WebmOutputKind.block), isTrue);
        expect(outputs.any((o) => o.kind == WebmOutputKind.cuePoints), isTrue);
        expect(
            outputs.any((o) => o.kind == WebmOutputKind.endOfStream), isTrue);

        // Should have blocks for both tracks
        final blockCount =
            outputs.where((o) => o.kind == WebmOutputKind.block).length;
        expect(blockCount, equals(10)); // 5 video + 5 audio
      });

      test('assembles valid WebM file', () {
        final chunks = <Uint8List>[];
        final processor = WebmProcessor(
          tracks: [
            WebmTrack(
                trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8),
          ],
          onOutput: (output) {
            if (output.data != null) {
              chunks.add(output.data!);
            }
          },
        );

        processor.start();

        processor.processFrame(WebmFrame(
          data: Uint8List.fromList([0x01, 0x02, 0x03]),
          isKeyframe: true,
          timeMs: 0,
          trackNumber: 1,
        ));

        processor.processFrame(WebmFrame(
          data: Uint8List.fromList([0x04, 0x05, 0x06]),
          isKeyframe: false,
          timeMs: 100,
          trackNumber: 1,
        ));

        processor.stop();

        // Assemble file
        final totalSize =
            chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
        final file = Uint8List(totalSize);
        var offset = 0;
        for (final chunk in chunks) {
          file.setAll(offset, chunk);
          offset += chunk.length;
        }

        // Verify starts with EBML header
        expect(file.sublist(0, 4),
            equals(Uint8List.fromList([0x1a, 0x45, 0xdf, 0xa3])));

        // Should be reasonable size
        expect(file.length, greaterThan(100));
      });
    });
  });

  group('WebmFrame', () {
    test('creates frame with required fields', () {
      final frame = WebmFrame(
        data: Uint8List.fromList([0x01, 0x02]),
        isKeyframe: true,
        timeMs: 100,
        trackNumber: 1,
      );

      expect(frame.data, equals(Uint8List.fromList([0x01, 0x02])));
      expect(frame.isKeyframe, isTrue);
      expect(frame.timeMs, equals(100));
      expect(frame.trackNumber, equals(1));
    });
  });

  group('WebmOutput', () {
    test('creates output with data', () {
      final output = WebmOutput(
        data: Uint8List.fromList([0x01]),
        kind: WebmOutputKind.block,
      );

      expect(output.data, isNotNull);
      expect(output.kind, equals(WebmOutputKind.block));
      expect(output.endOfStream, isNull);
    });

    test('creates end of stream output', () {
      final output = WebmOutput(
        data: null,
        kind: WebmOutputKind.endOfStream,
        endOfStream: WebmEndOfStream(
          durationMs: 5000,
          durationElement: Uint8List(8),
          header: Uint8List(100),
        ),
      );

      expect(output.endOfStream, isNotNull);
      expect(output.endOfStream!.durationMs, equals(5000));
    });
  });
}
