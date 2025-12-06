import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/container/webm/ebml/id.dart';

void main() {
  group('EbmlId', () {
    group('EBML Header IDs', () {
      test('ebml header ID has correct bytes', () {
        expect(EbmlId.ebml, equals(Uint8List.fromList([0x1a, 0x45, 0xdf, 0xa3])));
      });

      test('ebmlVersion ID has correct bytes', () {
        expect(EbmlId.ebmlVersion, equals(Uint8List.fromList([0x42, 0x86])));
      });

      test('ebmlReadVersion ID has correct bytes', () {
        expect(EbmlId.ebmlReadVersion, equals(Uint8List.fromList([0x42, 0xf7])));
      });

      test('ebmlMaxIdLength ID has correct bytes', () {
        expect(EbmlId.ebmlMaxIdLength, equals(Uint8List.fromList([0x42, 0xf2])));
      });

      test('ebmlMaxSizeLength ID has correct bytes', () {
        expect(EbmlId.ebmlMaxSizeLength, equals(Uint8List.fromList([0x42, 0xf3])));
      });

      test('docType ID has correct bytes', () {
        expect(EbmlId.docType, equals(Uint8List.fromList([0x42, 0x82])));
      });

      test('docTypeVersion ID has correct bytes', () {
        expect(EbmlId.docTypeVersion, equals(Uint8List.fromList([0x42, 0x87])));
      });

      test('docTypeReadVersion ID has correct bytes', () {
        expect(EbmlId.docTypeReadVersion, equals(Uint8List.fromList([0x42, 0x85])));
      });
    });

    group('Global Element IDs', () {
      test('voidElement ID has correct bytes', () {
        expect(EbmlId.voidElement, equals(Uint8List.fromList([0xec])));
      });

      test('crc32 ID has correct bytes', () {
        expect(EbmlId.crc32, equals(Uint8List.fromList([0xbf])));
      });
    });

    group('Segment IDs', () {
      test('segment ID has correct bytes', () {
        expect(EbmlId.segment, equals(Uint8List.fromList([0x18, 0x53, 0x80, 0x67])));
      });
    });

    group('Seek Head IDs', () {
      test('seekHead ID has correct bytes', () {
        expect(EbmlId.seekHead, equals(Uint8List.fromList([0x11, 0x4d, 0x9b, 0x74])));
      });

      test('seek ID has correct bytes', () {
        expect(EbmlId.seek, equals(Uint8List.fromList([0x4d, 0xbb])));
      });

      test('seekId ID has correct bytes', () {
        expect(EbmlId.seekId, equals(Uint8List.fromList([0x53, 0xab])));
      });

      test('seekPosition ID has correct bytes', () {
        expect(EbmlId.seekPosition, equals(Uint8List.fromList([0x53, 0xac])));
      });
    });

    group('Segment Info IDs', () {
      test('info ID has correct bytes', () {
        expect(EbmlId.info, equals(Uint8List.fromList([0x15, 0x49, 0xa9, 0x66])));
      });

      test('timecodeScale ID has correct bytes', () {
        expect(EbmlId.timecodeScale, equals(Uint8List.fromList([0x2a, 0xd7, 0xb1])));
      });

      test('duration ID has correct bytes', () {
        expect(EbmlId.duration, equals(Uint8List.fromList([0x44, 0x89])));
      });

      test('muxingApp ID has correct bytes', () {
        expect(EbmlId.muxingApp, equals(Uint8List.fromList([0x4d, 0x80])));
      });

      test('writingApp ID has correct bytes', () {
        expect(EbmlId.writingApp, equals(Uint8List.fromList([0x57, 0x41])));
      });
    });

    group('Cluster IDs', () {
      test('cluster ID has correct bytes', () {
        expect(EbmlId.cluster, equals(Uint8List.fromList([0x1f, 0x43, 0xb6, 0x75])));
      });

      test('timecode ID has correct bytes', () {
        expect(EbmlId.timecode, equals(Uint8List.fromList([0xe7])));
      });

      test('simpleBlock ID has correct bytes', () {
        expect(EbmlId.simpleBlock, equals(Uint8List.fromList([0xa3])));
      });

      test('blockGroup ID has correct bytes', () {
        expect(EbmlId.blockGroup, equals(Uint8List.fromList([0xa0])));
      });

      test('block ID has correct bytes', () {
        expect(EbmlId.block, equals(Uint8List.fromList([0xa1])));
      });
    });

    group('Track IDs', () {
      test('tracks ID has correct bytes', () {
        expect(EbmlId.tracks, equals(Uint8List.fromList([0x16, 0x54, 0xae, 0x6b])));
      });

      test('trackEntry ID has correct bytes', () {
        expect(EbmlId.trackEntry, equals(Uint8List.fromList([0xae])));
      });

      test('trackNumber ID has correct bytes', () {
        expect(EbmlId.trackNumber, equals(Uint8List.fromList([0xd7])));
      });

      test('trackUid ID has correct bytes', () {
        expect(EbmlId.trackUid, equals(Uint8List.fromList([0x73, 0xc5])));
      });

      test('trackType ID has correct bytes', () {
        expect(EbmlId.trackType, equals(Uint8List.fromList([0x83])));
      });

      test('codecId ID has correct bytes', () {
        expect(EbmlId.codecId, equals(Uint8List.fromList([0x86])));
      });

      test('codecPrivate ID has correct bytes', () {
        expect(EbmlId.codecPrivate, equals(Uint8List.fromList([0x63, 0xa2])));
      });
    });

    group('Video IDs', () {
      test('video ID has correct bytes', () {
        expect(EbmlId.video, equals(Uint8List.fromList([0xe0])));
      });

      test('pixelWidth ID has correct bytes', () {
        expect(EbmlId.pixelWidth, equals(Uint8List.fromList([0xb0])));
      });

      test('pixelHeight ID has correct bytes', () {
        expect(EbmlId.pixelHeight, equals(Uint8List.fromList([0xba])));
      });

      test('displayWidth ID has correct bytes', () {
        expect(EbmlId.displayWidth, equals(Uint8List.fromList([0x54, 0xb0])));
      });

      test('displayHeight ID has correct bytes', () {
        expect(EbmlId.displayHeight, equals(Uint8List.fromList([0x54, 0xba])));
      });
    });

    group('Audio IDs', () {
      test('audio ID has correct bytes', () {
        expect(EbmlId.audio, equals(Uint8List.fromList([0xe1])));
      });

      test('samplingFrequency ID has correct bytes', () {
        expect(EbmlId.samplingFrequency, equals(Uint8List.fromList([0xb5])));
      });

      test('channels ID has correct bytes', () {
        expect(EbmlId.channels, equals(Uint8List.fromList([0x9f])));
      });

      test('bitDepth ID has correct bytes', () {
        expect(EbmlId.bitDepth, equals(Uint8List.fromList([0x62, 0x64])));
      });
    });

    group('Cue IDs', () {
      test('cues ID has correct bytes', () {
        expect(EbmlId.cues, equals(Uint8List.fromList([0x1c, 0x53, 0xbb, 0x6b])));
      });

      test('cuePoint ID has correct bytes', () {
        expect(EbmlId.cuePoint, equals(Uint8List.fromList([0xbb])));
      });

      test('cueTime ID has correct bytes', () {
        expect(EbmlId.cueTime, equals(Uint8List.fromList([0xb3])));
      });

      test('cueTrack ID has correct bytes', () {
        expect(EbmlId.cueTrack, equals(Uint8List.fromList([0xf7])));
      });
    });

    group('Chapter IDs', () {
      test('chapters ID has correct bytes', () {
        expect(EbmlId.chapters, equals(Uint8List.fromList([0x10, 0x43, 0xa7, 0x70])));
      });

      test('chapterAtom ID has correct bytes', () {
        expect(EbmlId.chapterAtom, equals(Uint8List.fromList([0xb6])));
      });

      test('chapterTimeStart ID has correct bytes', () {
        expect(EbmlId.chapterTimeStart, equals(Uint8List.fromList([0x91])));
      });

      test('chapterTimeEnd ID has correct bytes', () {
        expect(EbmlId.chapterTimeEnd, equals(Uint8List.fromList([0x92])));
      });
    });

    group('Tag IDs', () {
      test('tags ID has correct bytes', () {
        expect(EbmlId.tags, equals(Uint8List.fromList([0x12, 0x54, 0xc3, 0x67])));
      });

      test('tag ID has correct bytes', () {
        expect(EbmlId.tag, equals(Uint8List.fromList([0x73, 0x73])));
      });

      test('tagName ID has correct bytes', () {
        expect(EbmlId.tagName, equals(Uint8List.fromList([0x45, 0xa3])));
      });

      test('tagString ID has correct bytes', () {
        expect(EbmlId.tagString, equals(Uint8List.fromList([0x44, 0x87])));
      });
    });

    group('ID lengths', () {
      test('1-byte IDs exist', () {
        expect(EbmlId.voidElement.length, equals(1));
        expect(EbmlId.crc32.length, equals(1));
        expect(EbmlId.timecode.length, equals(1));
      });

      test('2-byte IDs exist', () {
        expect(EbmlId.ebmlVersion.length, equals(2));
        expect(EbmlId.docType.length, equals(2));
        expect(EbmlId.seek.length, equals(2));
      });

      test('3-byte IDs exist', () {
        expect(EbmlId.timecodeScale.length, equals(3));
        expect(EbmlId.prevUid.length, equals(3));
        expect(EbmlId.defaultDuration.length, equals(3));
      });

      test('4-byte IDs exist', () {
        expect(EbmlId.ebml.length, equals(4));
        expect(EbmlId.segment.length, equals(4));
        expect(EbmlId.cluster.length, equals(4));
        expect(EbmlId.tracks.length, equals(4));
      });
    });
  });

  group('MatroskaTrackType', () {
    test('video type is 1', () {
      expect(MatroskaTrackType.video, equals(1));
    });

    test('audio type is 2', () {
      expect(MatroskaTrackType.audio, equals(2));
    });

    test('complex type is 3', () {
      expect(MatroskaTrackType.complex, equals(3));
    });

    test('logo type is 0x10', () {
      expect(MatroskaTrackType.logo, equals(0x10));
    });

    test('subtitle type is 0x11', () {
      expect(MatroskaTrackType.subtitle, equals(0x11));
    });

    test('buttons type is 0x12', () {
      expect(MatroskaTrackType.buttons, equals(0x12));
    });

    test('control type is 0x20', () {
      expect(MatroskaTrackType.control, equals(0x20));
    });
  });
}
