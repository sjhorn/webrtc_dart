import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/container/webm/container.dart';
import 'package:webrtc_dart/src/container/webm/ebml/ebml.dart';

void main() {
  group('WebmContainer', () {
    group('ebmlHeader', () {
      test('creates valid EBML header', () {
        final container = WebmContainer([
          WebmTrack(
            trackNumber: 1,
            kind: TrackKind.video,
            codec: WebmCodec.vp8,
          ),
        ]);

        final header = container.ebmlHeader;

        // Should start with EBML element ID [0x1a, 0x45, 0xdf, 0xa3]
        expect(header.sublist(0, 4),
            equals(Uint8List.fromList([0x1a, 0x45, 0xdf, 0xa3])));

        // Header should be reasonable size
        expect(header.length, greaterThan(20));
        expect(header.length, lessThan(100));
      });

      test('contains doctype webm', () {
        final container = WebmContainer([]);
        final header = container.ebmlHeader;

        // Search for 'webm' string in the header
        final webmBytes = [0x77, 0x65, 0x62, 0x6d]; // 'webm'
        var found = false;
        for (var i = 0; i < header.length - 3; i++) {
          if (header[i] == webmBytes[0] &&
              header[i + 1] == webmBytes[1] &&
              header[i + 2] == webmBytes[2] &&
              header[i + 3] == webmBytes[3]) {
            found = true;
            break;
          }
        }
        expect(found, isTrue, reason: 'DocType "webm" not found in header');
      });
    });

    group('createSegment', () {
      test('creates segment with video track', () {
        final container = WebmContainer([
          WebmTrack(
            trackNumber: 1,
            kind: TrackKind.video,
            codec: WebmCodec.vp8,
            width: 640,
            height: 480,
          ),
        ]);

        final segment = container.createSegment();

        // Should start with Segment element ID [0x18, 0x53, 0x80, 0x67]
        expect(segment.sublist(0, 4),
            equals(Uint8List.fromList([0x18, 0x53, 0x80, 0x67])));

        // Should have unknown size marker after ID
        expect(segment.sublist(4, 12),
            equals(Uint8List.fromList([0x01, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff])));
      });

      test('creates segment with audio track', () {
        final container = WebmContainer([
          WebmTrack(
            trackNumber: 1,
            kind: TrackKind.audio,
            codec: WebmCodec.opus,
          ),
        ]);

        final segment = container.createSegment();

        // Should start with Segment element ID
        expect(segment.sublist(0, 4),
            equals(Uint8List.fromList([0x18, 0x53, 0x80, 0x67])));

        // Should contain OpusHead string
        final opusHead = [0x4f, 0x70, 0x75, 0x73, 0x48, 0x65, 0x61, 0x64];
        var found = false;
        for (var i = 0; i < segment.length - 7; i++) {
          if (segment[i] == opusHead[0] &&
              segment[i + 1] == opusHead[1] &&
              segment[i + 2] == opusHead[2] &&
              segment[i + 3] == opusHead[3]) {
            found = true;
            break;
          }
        }
        expect(found, isTrue, reason: 'OpusHead not found in segment');
      });

      test('creates segment with multiple tracks', () {
        final container = WebmContainer([
          WebmTrack(
            trackNumber: 1,
            kind: TrackKind.video,
            codec: WebmCodec.vp8,
            width: 1280,
            height: 720,
          ),
          WebmTrack(
            trackNumber: 2,
            kind: TrackKind.audio,
            codec: WebmCodec.opus,
          ),
        ]);

        final segment = container.createSegment();

        // Should have reasonable size for two tracks
        expect(segment.length, greaterThan(100));
      });

      test('creates segment with duration', () {
        final container = WebmContainer([
          WebmTrack(
            trackNumber: 1,
            kind: TrackKind.video,
            codec: WebmCodec.vp9,
          ),
        ]);

        final segmentWithDuration = container.createSegment(duration: 5000.0);
        final segmentWithoutDuration = container.createSegment();

        // Segment with duration should be slightly larger
        expect(segmentWithDuration.length, greaterThan(segmentWithoutDuration.length));
      });

      test('creates segment with video roll angle', () {
        final container = WebmContainer([
          WebmTrack(
            trackNumber: 1,
            kind: TrackKind.video,
            codec: WebmCodec.vp8,
            roll: 90.0,
          ),
        ]);

        final segment = container.createSegment();

        // Should have reasonable size including projection info
        expect(segment.length, greaterThan(50));
      });
    });

    group('createCluster', () {
      test('creates cluster with timecode 0', () {
        final container = WebmContainer([]);

        final cluster = container.createCluster(0);

        // Should start with Cluster element ID [0x1f, 0x43, 0xb6, 0x75]
        expect(cluster.sublist(0, 4),
            equals(Uint8List.fromList([0x1f, 0x43, 0xb6, 0x75])));

        // Should have unknown size marker
        expect(cluster.sublist(4, 12),
            equals(Uint8List.fromList([0x01, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff])));
      });

      test('creates cluster with non-zero timecode', () {
        final container = WebmContainer([]);

        final cluster1 = container.createCluster(0);
        final cluster2 = container.createCluster(5000);

        // Both should start with cluster ID
        expect(cluster1.sublist(0, 4), equals(cluster2.sublist(0, 4)));

        // Timecode 5000 should have different bytes than timecode 0
        expect(cluster1, isNot(equals(cluster2)));
      });
    });

    group('createSimpleBlock', () {
      test('creates SimpleBlock for keyframe', () {
        final container = WebmContainer([]);
        final frame = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);

        final block = container.createSimpleBlock(frame, true, 1, 0);

        // Should start with SimpleBlock element ID [0xa3]
        expect(block[0], equals(0xa3));

        // Should contain the frame data at the end
        expect(block.sublist(block.length - 4), equals(frame));
      });

      test('creates SimpleBlock for non-keyframe', () {
        final container = WebmContainer([]);
        final frame = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);

        final keyframeBlock = container.createSimpleBlock(frame, true, 1, 0);
        final nonKeyframeBlock = container.createSimpleBlock(frame, false, 1, 0);

        // Both should start with SimpleBlock ID
        expect(keyframeBlock[0], equals(0xa3));
        expect(nonKeyframeBlock[0], equals(0xa3));

        // They should differ in the flags byte
        expect(keyframeBlock, isNot(equals(nonKeyframeBlock)));
      });

      test('creates SimpleBlock with different track numbers', () {
        final container = WebmContainer([]);
        final frame = Uint8List.fromList([0xaa, 0xbb]);

        final block1 = container.createSimpleBlock(frame, true, 1, 0);
        final block2 = container.createSimpleBlock(frame, true, 2, 0);

        // Different track numbers should produce different blocks
        expect(block1, isNot(equals(block2)));
      });

      test('creates SimpleBlock with relative timestamp', () {
        final container = WebmContainer([]);
        final frame = Uint8List.fromList([0xcc, 0xdd]);

        final block0 = container.createSimpleBlock(frame, true, 1, 0);
        final block100 = container.createSimpleBlock(frame, true, 1, 100);

        // Different timestamps should produce different blocks
        expect(block0, isNot(equals(block100)));
      });

      test('creates SimpleBlock with negative relative timestamp', () {
        final container = WebmContainer([]);
        final frame = Uint8List.fromList([0xee, 0xff]);

        // Should not throw for negative timestamp
        final block = container.createSimpleBlock(frame, true, 1, -50);
        expect(block[0], equals(0xa3));
      });

      test('creates SimpleBlock with larger frame', () {
        final container = WebmContainer([]);
        final frame = Uint8List(1000);
        for (var i = 0; i < frame.length; i++) {
          frame[i] = i % 256;
        }

        final block = container.createSimpleBlock(frame, true, 1, 0);

        // Should contain all frame data
        expect(block.sublist(block.length - 1000), equals(frame));
      });
    });

    group('createCuePoint', () {
      test('creates cue point element', () {
        final container = WebmContainer([]);

        final cue = container.createCuePoint(1000, 1, 500, 1);

        // CuePoint is EbmlData, verify it can be built
        final built = ebmlBuild(cue);

        // Should start with CuePoint ID [0xbb]
        expect(built[0], equals(0xbb));
      });

      test('creates different cue points for different positions', () {
        final container = WebmContainer([]);

        final cue1 = container.createCuePoint(1000, 1, 500, 1);
        final cue2 = container.createCuePoint(2000, 1, 1000, 2);

        final built1 = ebmlBuild(cue1);
        final built2 = ebmlBuild(cue2);

        expect(built1, isNot(equals(built2)));
      });
    });

    group('createCues', () {
      test('creates cues element with multiple cue points', () {
        final container = WebmContainer([]);

        final cuePoints = [
          container.createCuePoint(0, 1, 0, 1),
          container.createCuePoint(5000, 1, 5000, 50),
          container.createCuePoint(10000, 1, 10000, 100),
        ];

        final cues = container.createCues(cuePoints);

        // Should start with Cues element ID [0x1c, 0x53, 0xbb, 0x6b]
        expect(cues.sublist(0, 4),
            equals(Uint8List.fromList([0x1c, 0x53, 0xbb, 0x6b])));
      });

      test('creates empty cues element', () {
        final container = WebmContainer([]);

        final cues = container.createCues([]);

        // Should start with Cues element ID
        expect(cues.sublist(0, 4),
            equals(Uint8List.fromList([0x1c, 0x53, 0xbb, 0x6b])));
      });
    });

    group('createDuration', () {
      test('creates duration element', () {
        final container = WebmContainer([]);

        final duration = container.createDuration(10000.0);

        // Should start with Duration element ID [0x44, 0x89]
        expect(duration.sublist(0, 2), equals(Uint8List.fromList([0x44, 0x89])));
      });

      test('creates different durations', () {
        final container = WebmContainer([]);

        final duration1 = container.createDuration(5000.0);
        final duration2 = container.createDuration(10000.0);

        expect(duration1, isNot(equals(duration2)));
      });
    });

    group('codec support', () {
      test('supports VP8 video codec', () {
        final container = WebmContainer([
          WebmTrack(trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp8),
        ]);

        final segment = container.createSegment();
        expect(segment.length, greaterThan(50));
      });

      test('supports VP9 video codec', () {
        final container = WebmContainer([
          WebmTrack(trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.vp9),
        ]);

        final segment = container.createSegment();
        expect(segment.length, greaterThan(50));
      });

      test('supports AV1 video codec', () {
        final container = WebmContainer([
          WebmTrack(trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.av1),
        ]);

        final segment = container.createSegment();
        expect(segment.length, greaterThan(50));
      });

      test('supports H.264 video codec', () {
        final container = WebmContainer([
          WebmTrack(trackNumber: 1, kind: TrackKind.video, codec: WebmCodec.h264),
        ]);

        final segment = container.createSegment();
        expect(segment.length, greaterThan(50));
      });

      test('supports Opus audio codec', () {
        final container = WebmContainer([
          WebmTrack(trackNumber: 1, kind: TrackKind.audio, codec: WebmCodec.opus),
        ]);

        final segment = container.createSegment();
        expect(segment.length, greaterThan(50));
      });
    });

    group('full file structure', () {
      test('creates valid WebM structure', () {
        final container = WebmContainer([
          WebmTrack(
            trackNumber: 1,
            kind: TrackKind.video,
            codec: WebmCodec.vp8,
            width: 640,
            height: 480,
          ),
          WebmTrack(
            trackNumber: 2,
            kind: TrackKind.audio,
            codec: WebmCodec.opus,
          ),
        ]);

        // Build full file structure
        final header = container.ebmlHeader;
        final segment = container.createSegment();
        final cluster = container.createCluster(0);
        final videoBlock = container.createSimpleBlock(
          Uint8List.fromList([0x01, 0x02, 0x03]),
          true,
          1,
          0,
        );
        final audioBlock = container.createSimpleBlock(
          Uint8List.fromList([0x04, 0x05, 0x06]),
          true,
          2,
          10,
        );

        // Concatenate all parts
        final totalLength = header.length +
            segment.length +
            cluster.length +
            videoBlock.length +
            audioBlock.length;

        final file = Uint8List(totalLength);
        var offset = 0;

        file.setAll(offset, header);
        offset += header.length;

        file.setAll(offset, segment);
        offset += segment.length;

        file.setAll(offset, cluster);
        offset += cluster.length;

        file.setAll(offset, videoBlock);
        offset += videoBlock.length;

        file.setAll(offset, audioBlock);

        // Verify structure
        expect(file.length, equals(totalLength));

        // Should start with EBML header
        expect(file.sublist(0, 4),
            equals(Uint8List.fromList([0x1a, 0x45, 0xdf, 0xa3])));

        // Should have Segment after header
        final segmentStart = header.length;
        expect(file.sublist(segmentStart, segmentStart + 4),
            equals(Uint8List.fromList([0x18, 0x53, 0x80, 0x67])));

        // Should have Cluster after segment
        final clusterStart = header.length + segment.length;
        expect(file.sublist(clusterStart, clusterStart + 4),
            equals(Uint8List.fromList([0x1f, 0x43, 0xb6, 0x75])));
      });
    });
  });

  group('WebmCodec', () {
    test('has correct codec names', () {
      expect(WebmCodec.vp8.name, equals('VP8'));
      expect(WebmCodec.vp9.name, equals('VP9'));
      expect(WebmCodec.av1.name, equals('AV1'));
      expect(WebmCodec.h264.name, equals('MPEG4/ISO/AVC'));
      expect(WebmCodec.opus.name, equals('OPUS'));
    });
  });

  group('TrackKind', () {
    test('has correct values', () {
      expect(TrackKind.video.value, equals(1));
      expect(TrackKind.audio.value, equals(2));
    });
  });

  group('WebmTrack', () {
    test('creates video track with dimensions', () {
      final track = WebmTrack(
        trackNumber: 1,
        kind: TrackKind.video,
        codec: WebmCodec.vp8,
        width: 1920,
        height: 1080,
      );

      expect(track.trackNumber, equals(1));
      expect(track.kind, equals(TrackKind.video));
      expect(track.codec, equals(WebmCodec.vp8));
      expect(track.width, equals(1920));
      expect(track.height, equals(1080));
    });

    test('creates audio track', () {
      final track = WebmTrack(
        trackNumber: 2,
        kind: TrackKind.audio,
        codec: WebmCodec.opus,
      );

      expect(track.trackNumber, equals(2));
      expect(track.kind, equals(TrackKind.audio));
      expect(track.codec, equals(WebmCodec.opus));
      expect(track.width, isNull);
      expect(track.height, isNull);
    });

    test('creates track with roll angle', () {
      final track = WebmTrack(
        trackNumber: 1,
        kind: TrackKind.video,
        codec: WebmCodec.vp8,
        roll: 180.0,
      );

      expect(track.roll, equals(180.0));
    });
  });
}
