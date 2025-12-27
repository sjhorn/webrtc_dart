import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/rtcp/sdes.dart';

void main() {
  group('RTCP SDES', () {
    group('SourceDescriptionItem', () {
      test('should serialize CNAME item', () {
        final item = SourceDescriptionItem(type: 1, text: 'A');

        final bytes = item.serialize();

        expect(bytes, equals([0x01, 0x01, 0x41]));
      });

      test('should serialize item with longer text', () {
        final item = SourceDescriptionItem(type: 1, text: 'BCD');

        final bytes = item.serialize();

        expect(bytes, equals([0x01, 0x03, 0x42, 0x43, 0x44]));
      });

      test('should deserialize CNAME item', () {
        final data = Uint8List.fromList([0x01, 0x01, 0x41]);

        final item = SourceDescriptionItem.deserialize(data);

        expect(item.type, equals(1));
        expect(item.text, equals('A'));
      });

      test('should report correct length', () {
        final item = SourceDescriptionItem(type: 1, text: 'ABC');

        expect(item.length, equals(5)); // 1 (type) + 1 (len) + 3 (text)
      });

      test('should use typed factory', () {
        final item = SourceDescriptionItem.typed(
          type: SdesItemType.cname,
          text: 'test@example.com',
        );

        expect(item.type, equals(1));
        expect(item.text, equals('test@example.com'));
      });
    });

    group('SourceDescriptionChunk', () {
      test('should serialize chunk with single item', () {
        final chunk = SourceDescriptionChunk(
          source: 0x01020304,
          items: [SourceDescriptionItem(type: 1, text: 'A')],
        );

        final bytes = chunk.serialize();

        // 4 (SSRC) + 3 (item) + 1 (END) = 8 bytes (already 4-byte aligned)
        expect(bytes, equals([
          0x01, 0x02, 0x03, 0x04, // SSRC
          0x01, 0x01, 0x41, // CNAME item
          0x00, // END
        ]));
      });

      test('should serialize chunk with multiple items', () {
        final chunk = SourceDescriptionChunk(
          source: 0x10000000,
          items: [
            SourceDescriptionItem(type: 1, text: 'A'), // CNAME
            SourceDescriptionItem(type: 4, text: 'B'), // PHONE
          ],
        );

        final bytes = chunk.serialize();

        // Should include padding to 4-byte boundary
        expect(bytes, equals([
          0x10, 0x00, 0x00, 0x00, // SSRC
          0x01, 0x01, 0x41, // CNAME
          0x04, 0x01, 0x42, // PHONE
          0x00, 0x00, // END + padding
        ]));
      });

      test('should deserialize chunk', () {
        final data = Uint8List.fromList([
          0x01, 0x02, 0x03, 0x04, // SSRC
          0x01, 0x01, 0x41, // CNAME
          0x00, // END
        ]);

        final chunk = SourceDescriptionChunk.deserialize(data);

        expect(chunk.source, equals(0x01020304));
        expect(chunk.items.length, equals(1));
        expect(chunk.items[0].type, equals(1));
        expect(chunk.items[0].text, equals('A'));
      });
    });

    group('RtcpSourceDescription', () {
      test('should serialize packet with two items (golden test)', () {
        // Test vector from werift TypeScript tests
        final expected = Uint8List.fromList([
          // v=2, p=0, count=1, SDES, len=3
          0x81, 0xca, 0x00, 0x03,
          // ssrc=0x10000000
          0x10, 0x00, 0x00, 0x00,
          // CNAME, len=1, content=A
          0x01, 0x01, 0x41,
          // PHONE, len=1, content=B
          0x04, 0x01, 0x42,
          // END + padding
          0x00, 0x00,
        ]);

        final sdes = RtcpSourceDescription(
          chunks: [
            SourceDescriptionChunk(
              source: 0x10000000,
              items: [
                SourceDescriptionItem(type: 1, text: 'A'),
                SourceDescriptionItem(type: 4, text: 'B'),
              ],
            ),
          ],
        );

        final bytes = sdes.serialize();

        expect(bytes, equals(expected));
      });

      test('should serialize packet with two chunks (golden test)', () {
        // Test vector from werift TypeScript tests
        final expected = Uint8List.fromList([
          // v=2, p=0, count=2, SDES, len=5
          0x82, 0xca, 0x00, 0x05,
          // Chunk 1: ssrc=0x01020304
          0x01, 0x02, 0x03, 0x04,
          // CNAME, len=1, content=A
          0x01, 0x01, 0x41,
          // END
          0x00,
          // Chunk 2: SSRC 0x05060708
          0x05, 0x06, 0x07, 0x08,
          // CNAME, len=3, content=BCD
          0x01, 0x03, 0x42, 0x43, 0x44,
          // END + padding
          0x00, 0x00, 0x00,
        ]);

        final sdes = RtcpSourceDescription(
          chunks: [
            SourceDescriptionChunk(
              source: 0x01020304,
              items: [SourceDescriptionItem(type: 1, text: 'A')],
            ),
            SourceDescriptionChunk(
              source: 0x05060708,
              items: [SourceDescriptionItem(type: 1, text: 'BCD')],
            ),
          ],
        );

        final bytes = sdes.serialize();

        expect(bytes, equals(expected));
      });

      test('should deserialize packet with two items', () {
        final data = Uint8List.fromList([
          0x81, 0xca, 0x00, 0x03,
          0x10, 0x00, 0x00, 0x00,
          0x01, 0x01, 0x41,
          0x04, 0x01, 0x42,
          0x00, 0x00,
        ]);

        // Parse payload (skip 4-byte header)
        final payload = data.sublist(4);
        final sdes = RtcpSourceDescription.deserialize(payload, 1);

        expect(sdes.chunks.length, equals(1));
        expect(sdes.chunks[0].source, equals(0x10000000));
        expect(sdes.chunks[0].items.length, equals(2));
        expect(sdes.chunks[0].items[0].type, equals(1));
        expect(sdes.chunks[0].items[0].text, equals('A'));
        expect(sdes.chunks[0].items[1].type, equals(4));
        expect(sdes.chunks[0].items[1].text, equals('B'));
      });

      test('should deserialize packet with two chunks', () {
        final data = Uint8List.fromList([
          0x82, 0xca, 0x00, 0x05,
          0x01, 0x02, 0x03, 0x04,
          0x01, 0x01, 0x41,
          0x00,
          0x05, 0x06, 0x07, 0x08,
          0x01, 0x03, 0x42, 0x43, 0x44,
          0x00, 0x00, 0x00,
        ]);

        // Parse payload (skip 4-byte header)
        final payload = data.sublist(4);
        final sdes = RtcpSourceDescription.deserialize(payload, 2);

        expect(sdes.chunks.length, equals(2));
        expect(sdes.chunks[0].source, equals(0x01020304));
        expect(sdes.chunks[0].items[0].text, equals('A'));
        expect(sdes.chunks[1].source, equals(0x05060708));
        expect(sdes.chunks[1].items[0].text, equals('BCD'));
      });

      test('should round-trip serialize/deserialize', () {
        final original = RtcpSourceDescription(
          chunks: [
            SourceDescriptionChunk(
              source: 0xDEADBEEF,
              items: [
                SourceDescriptionItem.typed(
                  type: SdesItemType.cname,
                  text: 'user@example.com',
                ),
                SourceDescriptionItem.typed(
                  type: SdesItemType.name,
                  text: 'Test User',
                ),
              ],
            ),
          ],
        );

        final bytes = original.serialize();

        // Parse (skip header, use SC from byte 0)
        final sc = bytes[0] & 0x1F;
        final payload = bytes.sublist(4);
        final parsed = RtcpSourceDescription.deserialize(payload, sc);

        expect(parsed.chunks.length, equals(1));
        expect(parsed.chunks[0].source, equals(0xDEADBEEF));
        expect(parsed.chunks[0].items.length, equals(2));
        expect(parsed.chunks[0].items[0].type, equals(1));
        expect(parsed.chunks[0].items[0].text, equals('user@example.com'));
        expect(parsed.chunks[0].items[1].type, equals(2));
        expect(parsed.chunks[0].items[1].text, equals('Test User'));
      });

      test('should create CNAME convenience constructor', () {
        final sdes = RtcpSourceDescription.withCname(
          ssrc: 0x12345678,
          cname: 'test-cname',
        );

        expect(sdes.chunks.length, equals(1));
        expect(sdes.chunks[0].source, equals(0x12345678));
        expect(sdes.chunks[0].items.length, equals(1));
        expect(sdes.chunks[0].items[0].type, equals(1));
        expect(sdes.chunks[0].items[0].text, equals('test-cname'));
      });
    });

    group('SdesItemType enum', () {
      test('should have correct values', () {
        expect(SdesItemType.end.value, equals(0));
        expect(SdesItemType.cname.value, equals(1));
        expect(SdesItemType.name.value, equals(2));
        expect(SdesItemType.email.value, equals(3));
        expect(SdesItemType.phone.value, equals(4));
        expect(SdesItemType.loc.value, equals(5));
        expect(SdesItemType.tool.value, equals(6));
        expect(SdesItemType.note.value, equals(7));
        expect(SdesItemType.priv.value, equals(8));
      });

      test('should look up from value', () {
        expect(SdesItemType.fromValue(1), equals(SdesItemType.cname));
        expect(SdesItemType.fromValue(4), equals(SdesItemType.phone));
        expect(SdesItemType.fromValue(99), isNull);
      });
    });
  });
}
