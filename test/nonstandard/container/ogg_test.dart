import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/nonstandard/container/ogg.dart';

/// Build an OGG page with given parameters
Uint8List buildOggPage({
  int granulePosition = 0,
  int bitstreamSerial = 0x12345678,
  int pageSequence = 0,
  required List<Uint8List> segments,
  int headerType = 0,
}) {
  // Build segment table
  final segmentTable = segments.map((s) => s.length).toList();
  final segmentCount = segmentTable.length;

  // Calculate total size
  final headerSize = 27 + segmentCount;
  final dataSize = segments.fold<int>(0, (sum, s) => sum + s.length);
  final totalSize = headerSize + dataSize;

  final page = Uint8List(totalSize);
  final view = ByteData.sublistView(page);

  // Magic "OggS"
  page[0] = 0x4F; // O
  page[1] = 0x67; // g
  page[2] = 0x67; // g
  page[3] = 0x53; // S

  // Version
  page[4] = 0;

  // Header type
  page[5] = headerType;

  // Granule position (64-bit LE)
  view.setInt64(6, granulePosition, Endian.little);

  // Bitstream serial (32-bit LE)
  view.setUint32(14, bitstreamSerial, Endian.little);

  // Page sequence (32-bit LE)
  view.setUint32(18, pageSequence, Endian.little);

  // CRC (placeholder - not validated in parser)
  view.setUint32(22, 0, Endian.little);

  // Segment count
  page[26] = segmentCount;

  // Segment table
  for (var i = 0; i < segmentCount; i++) {
    page[27 + i] = segmentTable[i];
  }

  // Segment data
  var offset = 27 + segmentCount;
  for (final segment in segments) {
    page.setRange(offset, offset + segment.length, segment);
    offset += segment.length;
  }

  return page;
}

/// Build OpusHead ID header
Uint8List buildOpusHead({
  int channelCount = 2,
  int preSkip = 312,
  int sampleRate = 48000,
  int outputGain = 0,
}) {
  final data = Uint8List(19);
  final view = ByteData.sublistView(data);

  // Magic "OpusHead"
  data.setRange(0, 8, 'OpusHead'.codeUnits);

  // Version
  data[8] = 1;

  // Channel count
  data[9] = channelCount;

  // Pre-skip
  view.setUint16(10, preSkip, Endian.little);

  // Sample rate
  view.setUint32(12, sampleRate, Endian.little);

  // Output gain
  view.setInt16(16, outputGain, Endian.little);

  // Channel mapping family (0 = mono/stereo)
  data[18] = 0;

  return data;
}

/// Build OpusTags comment header
Uint8List buildOpusTags({String vendor = 'test'}) {
  final vendorBytes = vendor.codeUnits;
  final data = Uint8List(8 + 4 + vendorBytes.length + 4);
  final view = ByteData.sublistView(data);

  // Magic "OpusTags"
  data.setRange(0, 8, 'OpusTags'.codeUnits);

  // Vendor string length
  view.setUint32(8, vendorBytes.length, Endian.little);

  // Vendor string
  data.setRange(12, 12 + vendorBytes.length, vendorBytes);

  // User comment count
  view.setUint32(12 + vendorBytes.length, 0, Endian.little);

  return data;
}

void main() {
  group('OggPage', () {
    test('stores properties correctly', () {
      final segments = [
        Uint8List.fromList([1, 2, 3])
      ];
      final page = OggPage(
        granulePosition: 12345,
        segments: segments,
        segmentTable: [3],
      );

      expect(page.granulePosition, equals(12345));
      expect(page.segments, equals(segments));
      expect(page.segmentTable, equals([3]));
    });
  });

  group('OggParser', () {
    test('creates empty parser', () {
      final parser = OggParser();
      expect(parser.pages, isEmpty);
    });

    test('parses single page with one segment', () {
      final parser = OggParser();
      final segment = Uint8List.fromList([1, 2, 3, 4, 5]);
      final page = buildOggPage(segments: [segment]);

      parser.read(page);

      expect(parser.pages.length, equals(1));
      expect(parser.pages[0].segments.length, equals(1));
      expect(parser.pages[0].segments[0], equals(segment));
    });

    test('parses granule position correctly', () {
      final parser = OggParser();
      final page = buildOggPage(
        granulePosition: 48000,
        segments: [
          Uint8List.fromList([1, 2, 3])
        ],
      );

      parser.read(page);

      expect(parser.pages[0].granulePosition, equals(48000));
    });

    test('parses negative granule position', () {
      final parser = OggParser();
      final page = buildOggPage(
        granulePosition: -1,
        segments: [
          Uint8List.fromList([1, 2, 3])
        ],
      );

      parser.read(page);

      expect(parser.pages[0].granulePosition, equals(-1));
    });

    test('parses multiple segments in one page', () {
      final parser = OggParser();
      final seg1 = Uint8List.fromList([1, 2, 3]);
      final seg2 = Uint8List.fromList([4, 5, 6, 7]);
      final seg3 = Uint8List.fromList([8]);
      final page = buildOggPage(segments: [seg1, seg2, seg3]);

      parser.read(page);

      expect(parser.pages[0].segments.length, equals(3));
      expect(parser.pages[0].segments[0], equals(seg1));
      expect(parser.pages[0].segments[1], equals(seg2));
      expect(parser.pages[0].segments[2], equals(seg3));
    });

    test('parses multiple pages', () {
      final parser = OggParser();
      final page1 = buildOggPage(
        pageSequence: 0,
        segments: [
          Uint8List.fromList([1, 2])
        ],
      );
      final page2 = buildOggPage(
        pageSequence: 1,
        segments: [
          Uint8List.fromList([3, 4])
        ],
      );

      final combined = Uint8List(page1.length + page2.length);
      combined.setRange(0, page1.length, page1);
      combined.setRange(page1.length, combined.length, page2);

      parser.read(combined);

      expect(parser.pages.length, equals(2));
    });

    test('stops on invalid magic', () {
      final parser = OggParser();
      final data = Uint8List.fromList([0x00, 0x00, 0x00, 0x00, 0x00]);

      parser.read(data);

      expect(parser.pages, isEmpty);
    });

    test('stops on incomplete header', () {
      final parser = OggParser();
      final data = Uint8List.fromList(
          [0x4F, 0x67, 0x67, 0x53, 0x00]); // Just magic + version

      parser.read(data);

      expect(parser.pages, isEmpty);
    });

    test('exportSegments returns all segments and clears pages', () {
      final parser = OggParser();
      final seg1 = Uint8List.fromList([1, 2, 3]);
      final seg2 = Uint8List.fromList([4, 5]);
      final page = buildOggPage(segments: [seg1, seg2]);

      parser.read(page);
      final segments = parser.exportSegments();

      expect(segments.length, equals(2));
      expect(segments[0], equals(seg1));
      expect(segments[1], equals(seg2));
      expect(parser.pages, isEmpty);
    });

    test('handles empty segment', () {
      final parser = OggParser();
      final page = buildOggPage(segments: [Uint8List(0)]);

      parser.read(page);

      expect(parser.pages.length, equals(1));
      expect(parser.pages[0].segments[0].length, equals(0));
    });

    test('handles max segment size (255 bytes)', () {
      final parser = OggParser();
      final segment = Uint8List(255);
      for (var i = 0; i < 255; i++) {
        segment[i] = i;
      }
      final page = buildOggPage(segments: [segment]);

      parser.read(page);

      expect(parser.pages[0].segments[0].length, equals(255));
      expect(parser.pages[0].segments[0], equals(segment));
    });

    test('clear removes all pages', () {
      final parser = OggParser();
      final page = buildOggPage(segments: [
        Uint8List.fromList([1, 2, 3])
      ]);

      parser.read(page);
      expect(parser.pages.length, equals(1));

      parser.clear();
      expect(parser.pages, isEmpty);
    });

    test('read returns parser for chaining', () {
      final parser = OggParser();
      final page = buildOggPage(segments: [
        Uint8List.fromList([1])
      ]);

      final result = parser.read(page);

      expect(result, same(parser));
    });
  });

  group('OggOpusExtractor', () {
    test('creates extractor', () {
      final extractor = OggOpusExtractor();
      expect(extractor.channelCount, isNull);
      expect(extractor.preSkip, isNull);
    });

    test('parses OpusHead from first segment', () {
      final extractor = OggOpusExtractor();
      final opusHead = buildOpusHead(
        channelCount: 2,
        preSkip: 312,
        sampleRate: 48000,
      );
      final page = buildOggPage(segments: [opusHead]);

      extractor.feed(page);

      expect(extractor.channelCount, equals(2));
      expect(extractor.preSkip, equals(312));
      expect(extractor.originalSampleRate, equals(48000));
    });

    test('parses OpusTags from second segment', () {
      final extractor = OggOpusExtractor();

      // Page 1: OpusHead
      final opusHead = buildOpusHead();
      final page1 = buildOggPage(pageSequence: 0, segments: [opusHead]);

      // Page 2: OpusTags
      final opusTags = buildOpusTags();
      final page2 = buildOggPage(pageSequence: 1, segments: [opusTags]);

      final combined = Uint8List(page1.length + page2.length);
      combined.setRange(0, page1.length, page1);
      combined.setRange(page1.length, combined.length, page2);

      final packets = extractor.feed(combined);

      // Headers consumed, no audio packets yet
      expect(packets, isEmpty);
    });

    test('extracts audio packets after headers', () {
      final extractor = OggOpusExtractor();

      // Page 1: OpusHead
      final opusHead = buildOpusHead();
      final page1 = buildOggPage(pageSequence: 0, segments: [opusHead]);

      // Page 2: OpusTags
      final opusTags = buildOpusTags();
      final page2 = buildOggPage(pageSequence: 1, segments: [opusTags]);

      // Page 3: Audio
      final audioPacket1 = Uint8List.fromList([0xFC, 0x01, 0x02, 0x03]);
      final audioPacket2 = Uint8List.fromList([0xFC, 0x04, 0x05, 0x06]);
      final page3 =
          buildOggPage(pageSequence: 2, segments: [audioPacket1, audioPacket2]);

      final combined = Uint8List(page1.length + page2.length + page3.length);
      var offset = 0;
      combined.setRange(offset, offset + page1.length, page1);
      offset += page1.length;
      combined.setRange(offset, offset + page2.length, page2);
      offset += page2.length;
      combined.setRange(offset, offset + page3.length, page3);

      final packets = extractor.feed(combined);

      expect(packets.length, equals(2));
      expect(packets[0], equals(audioPacket1));
      expect(packets[1], equals(audioPacket2));
    });

    test('handles incremental feeding', () {
      final extractor = OggOpusExtractor();

      // Feed headers
      final opusHead = buildOpusHead();
      final page1 = buildOggPage(segments: [opusHead]);
      extractor.feed(page1);

      final opusTags = buildOpusTags();
      final page2 = buildOggPage(segments: [opusTags]);
      extractor.feed(page2);

      // Feed audio
      final audio = Uint8List.fromList([0xFC, 0x01, 0x02]);
      final page3 = buildOggPage(segments: [audio]);
      final packets = extractor.feed(page3);

      expect(packets.length, equals(1));
      expect(packets[0], equals(audio));
    });

    test('reset clears state', () {
      final extractor = OggOpusExtractor();

      // Feed header
      final opusHead = buildOpusHead(channelCount: 2);
      final page = buildOggPage(segments: [opusHead]);
      extractor.feed(page);

      expect(extractor.channelCount, equals(2));

      extractor.reset();

      expect(extractor.channelCount, isNull);
      expect(extractor.preSkip, isNull);
    });

    test('parses output gain correctly', () {
      final extractor = OggOpusExtractor();
      final opusHead = buildOpusHead(outputGain: -256);
      final page = buildOggPage(segments: [opusHead]);

      extractor.feed(page);

      expect(extractor.outputGain, equals(-256));
    });

    test('rejects invalid OpusHead version', () {
      final extractor = OggOpusExtractor();

      // Create invalid OpusHead with version 2
      final invalidHead = buildOpusHead();
      invalidHead[8] = 2; // Invalid version

      final page = buildOggPage(segments: [invalidHead]);
      extractor.feed(page);

      // Should not parse
      expect(extractor.channelCount, isNull);
    });

    test('rejects non-OpusHead first packet', () {
      final extractor = OggOpusExtractor();

      final notOpus = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);
      final page = buildOggPage(segments: [notOpus]);
      extractor.feed(page);

      expect(extractor.channelCount, isNull);
    });
  });
}
