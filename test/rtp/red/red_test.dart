import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/rtp/red/red_packet.dart';
import 'package:webrtc_dart/src/rtp/red/red_encoder.dart';
import 'package:webrtc_dart/src/rtp/red/red_handler.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';

void main() {
  group('RedPacket', () {
    test('serialize and deserialize single block', () {
      final red = RedPacket();
      red.blocks.add(RedBlock(
        block: Uint8List.fromList([1, 2, 3, 4, 5]),
        blockPT: 111, // Opus
      ));

      final serialized = red.serialize();
      final deserialized = RedPacket.deserialize(serialized);

      expect(deserialized.blocks.length, equals(1));
      expect(deserialized.blocks[0].blockPT, equals(111));
      expect(deserialized.blocks[0].block, equals([1, 2, 3, 4, 5]));
      expect(deserialized.blocks[0].timestampOffset, isNull);
    });

    test('serialize and deserialize multiple blocks', () {
      final red = RedPacket();

      // Add redundant block with timestamp offset
      red.blocks.add(RedBlock(
        block: Uint8List.fromList([10, 20, 30]),
        blockPT: 111,
        timestampOffset: 960, // 20ms at 48kHz
      ));

      // Add primary block (no offset)
      red.blocks.add(RedBlock(
        block: Uint8List.fromList([1, 2, 3, 4, 5]),
        blockPT: 111,
      ));

      final serialized = red.serialize();
      final deserialized = RedPacket.deserialize(serialized);

      expect(deserialized.blocks.length, equals(2));

      // First block is redundant
      expect(deserialized.blocks[0].blockPT, equals(111));
      expect(deserialized.blocks[0].timestampOffset, equals(960));
      expect(deserialized.blocks[0].block, equals([10, 20, 30]));

      // Second block is primary
      expect(deserialized.blocks[1].blockPT, equals(111));
      expect(deserialized.blocks[1].timestampOffset, isNull);
      expect(deserialized.blocks[1].block, equals([1, 2, 3, 4, 5]));
    });

    test('serialize and deserialize three blocks', () {
      final red = RedPacket();

      // Two redundant blocks
      red.blocks.add(RedBlock(
        block: Uint8List.fromList([100, 101]),
        blockPT: 111,
        timestampOffset: 1920, // 40ms
      ));
      red.blocks.add(RedBlock(
        block: Uint8List.fromList([200, 201, 202]),
        blockPT: 111,
        timestampOffset: 960, // 20ms
      ));

      // Primary block
      red.blocks.add(RedBlock(
        block: Uint8List.fromList([1, 2, 3, 4]),
        blockPT: 111,
      ));

      final serialized = red.serialize();
      final deserialized = RedPacket.deserialize(serialized);

      expect(deserialized.blocks.length, equals(3));
      expect(deserialized.redundantBlocks.length, equals(2));
      expect(deserialized.primaryBlock?.block, equals([1, 2, 3, 4]));
    });

    test('primaryBlock getter', () {
      final red = RedPacket();
      red.blocks.add(RedBlock(
        block: Uint8List.fromList([10, 20]),
        blockPT: 111,
        timestampOffset: 960,
      ));
      red.blocks.add(RedBlock(
        block: Uint8List.fromList([1, 2, 3]),
        blockPT: 111,
      ));

      final primary = red.primaryBlock;
      expect(primary, isNotNull);
      expect(primary!.block, equals([1, 2, 3]));
      expect(primary.isRedundant, isFalse);
    });

    test('redundantBlocks getter', () {
      final red = RedPacket();
      red.blocks.add(RedBlock(
        block: Uint8List.fromList([10]),
        blockPT: 111,
        timestampOffset: 1920,
      ));
      red.blocks.add(RedBlock(
        block: Uint8List.fromList([20]),
        blockPT: 111,
        timestampOffset: 960,
      ));
      red.blocks.add(RedBlock(
        block: Uint8List.fromList([30]),
        blockPT: 111,
      ));

      final redundant = red.redundantBlocks;
      expect(redundant.length, equals(2));
      expect(redundant[0].timestampOffset, equals(1920));
      expect(redundant[1].timestampOffset, equals(960));
    });

    test('handles large timestamp offset', () {
      final red = RedPacket();
      red.blocks.add(RedBlock(
        block: Uint8List.fromList([1, 2, 3]),
        blockPT: 96,
        timestampOffset: 16383, // Max 14-bit value
      ));
      red.blocks.add(RedBlock(
        block: Uint8List.fromList([4, 5, 6]),
        blockPT: 96,
      ));

      final serialized = red.serialize();
      final deserialized = RedPacket.deserialize(serialized);

      expect(deserialized.blocks[0].timestampOffset, equals(16383));
    });
  });

  group('RedHeader', () {
    test('serialize single field header', () {
      final header = RedHeader();
      header.fields.add(RedHeaderField(fBit: 0, blockPT: 111));

      final bytes = header.serialize();
      expect(bytes.length, equals(1));
      expect(bytes[0], equals(111)); // F=0, PT=111
    });

    test('serialize extended header', () {
      final header = RedHeader();
      header.fields.add(RedHeaderField(
        fBit: 1,
        blockPT: 111,
        timestampOffset: 960,
        blockLength: 50,
      ));
      header.fields.add(RedHeaderField(fBit: 0, blockPT: 111));

      final bytes = header.serialize();
      expect(bytes.length, equals(5)); // 4 + 1
    });

    test('deserialize single field header', () {
      final bytes = Uint8List.fromList([111]); // F=0, PT=111
      final (header, offset) = RedHeader.deserialize(bytes);

      expect(header.fields.length, equals(1));
      expect(header.fields[0].fBit, equals(0));
      expect(header.fields[0].blockPT, equals(111));
      expect(offset, equals(1));
    });

    test('deserialize extended header', () {
      // Build header: F=1, PT=111, offset=960, length=50, then F=0, PT=111
      final header = RedHeader();
      header.fields.add(RedHeaderField(
        fBit: 1,
        blockPT: 111,
        timestampOffset: 960,
        blockLength: 50,
      ));
      header.fields.add(RedHeaderField(fBit: 0, blockPT: 111));

      final bytes = header.serialize();
      final (parsed, offset) = RedHeader.deserialize(bytes);

      expect(parsed.fields.length, equals(2));
      expect(parsed.fields[0].fBit, equals(1));
      expect(parsed.fields[0].blockPT, equals(111));
      expect(parsed.fields[0].timestampOffset, equals(960));
      expect(parsed.fields[0].blockLength, equals(50));
      expect(parsed.fields[1].fBit, equals(0));
      expect(parsed.fields[1].blockPT, equals(111));
      expect(offset, equals(5));
    });
  });

  group('RedEncoder', () {
    test('basic encoding with distance=1', () {
      final encoder = RedEncoder(distance: 1);

      // Push first payload
      encoder.push(RedPayload(
        block: Uint8List.fromList([1, 2, 3]),
        timestamp: 0,
        blockPT: 111,
      ));

      var red = encoder.build();
      expect(red.blocks.length, equals(1)); // Just primary

      // Push second payload
      encoder.push(RedPayload(
        block: Uint8List.fromList([4, 5, 6]),
        timestamp: 960,
        blockPT: 111,
      ));

      red = encoder.build();
      expect(red.blocks.length, equals(2)); // Redundant + primary
      expect(red.blocks[0].timestampOffset, equals(960)); // First payload
      expect(red.blocks[1].timestampOffset, isNull); // Primary
    });

    test('encoding with distance=2', () {
      final encoder = RedEncoder(distance: 2);

      encoder.push(RedPayload(
        block: Uint8List.fromList([1]),
        timestamp: 0,
        blockPT: 111,
      ));
      encoder.push(RedPayload(
        block: Uint8List.fromList([2]),
        timestamp: 960,
        blockPT: 111,
      ));
      encoder.push(RedPayload(
        block: Uint8List.fromList([3]),
        timestamp: 1920,
        blockPT: 111,
      ));

      final red = encoder.build();
      expect(red.blocks.length, equals(3));
      expect(red.blocks[0].timestampOffset, equals(1920)); // ts=0
      expect(red.blocks[1].timestampOffset, equals(960)); // ts=960
      expect(red.blocks[2].timestampOffset, isNull); // ts=1920 (primary)
    });

    test('cache size limit', () {
      final encoder = RedEncoder(distance: 1, cacheSize: 3);

      for (var i = 0; i < 5; i++) {
        encoder.push(RedPayload(
          block: Uint8List.fromList([i]),
          timestamp: i * 960,
          blockPT: 111,
        ));
      }

      expect(encoder.cacheLength, equals(3));
    });

    test('distance setter validation', () {
      final encoder = RedEncoder();

      expect(() => encoder.distance = -1, throwsA(isA<ArgumentError>()));

      encoder.distance = 3;
      expect(encoder.distance, equals(3));
    });

    test('clear cache', () {
      final encoder = RedEncoder();

      encoder.push(RedPayload(
        block: Uint8List.fromList([1]),
        timestamp: 0,
        blockPT: 111,
      ));

      expect(encoder.cacheLength, equals(1));

      encoder.clear();

      expect(encoder.cacheLength, equals(0));
    });

    test('skips large timestamp offsets', () {
      final encoder = RedEncoder(distance: 1);

      // Push payload with very old timestamp
      encoder.push(RedPayload(
        block: Uint8List.fromList([1]),
        timestamp: 0,
        blockPT: 111,
      ));

      // Push payload with timestamp that would create > 14-bit offset
      encoder.push(RedPayload(
        block: Uint8List.fromList([2]),
        timestamp: 20000, // > 16383
        blockPT: 111,
      ));

      final red = encoder.build();
      // Should only have primary block since offset is too large
      expect(red.blocks.length, equals(1));
    });
  });

  group('RedHandler', () {
    test('extract single block', () {
      final handler = RedHandler();

      final red = RedPacket();
      red.blocks.add(RedBlock(
        block: Uint8List.fromList([1, 2, 3]),
        blockPT: 111,
      ));

      final base = RtpPacket(
        payloadType: 116, // RED
        sequenceNumber: 1000,
        timestamp: 48000,
        ssrc: 12345,
        payload: Uint8List(0),
      );

      final packets = handler.push(red, base);

      expect(packets.length, equals(1));
      expect(packets[0].payloadType, equals(111));
      expect(packets[0].sequenceNumber, equals(1000));
      expect(packets[0].timestamp, equals(48000));
      expect(packets[0].payload, equals([1, 2, 3]));
    });

    test('extract multiple blocks', () {
      final handler = RedHandler();

      final red = RedPacket();
      red.blocks.add(RedBlock(
        block: Uint8List.fromList([10, 20]),
        blockPT: 111,
        timestampOffset: 960,
      ));
      red.blocks.add(RedBlock(
        block: Uint8List.fromList([1, 2, 3]),
        blockPT: 111,
      ));

      final base = RtpPacket(
        payloadType: 116,
        sequenceNumber: 1001,
        timestamp: 48960,
        ssrc: 12345,
        payload: Uint8List(0),
      );

      final packets = handler.push(red, base);

      expect(packets.length, equals(2));

      // Redundant block
      expect(packets[0].sequenceNumber, equals(1000));
      expect(packets[0].timestamp, equals(48000));
      expect(packets[0].payload, equals([10, 20]));

      // Primary block
      expect(packets[1].sequenceNumber, equals(1001));
      expect(packets[1].timestamp, equals(48960));
      expect(packets[1].payload, equals([1, 2, 3]));
    });

    test('duplicate detection', () {
      final handler = RedHandler();

      final base1 = RtpPacket(
        payloadType: 116,
        sequenceNumber: 1000,
        timestamp: 48000,
        ssrc: 12345,
        payload: Uint8List(0),
      );

      final red1 = RedPacket();
      red1.blocks.add(RedBlock(
        block: Uint8List.fromList([1, 2, 3]),
        blockPT: 111,
      ));

      var packets = handler.push(red1, base1);
      expect(packets.length, equals(1));

      // Send same packet again
      packets = handler.push(red1, base1);
      expect(packets.length, equals(0)); // Filtered as duplicate
    });

    test('recovers lost packet from redundancy', () {
      final handler = RedHandler();

      // Simulate packet 1000 was lost, but we receive packet 1001
      // with redundant copy of packet 1000
      final red = RedPacket();
      red.blocks.add(RedBlock(
        block: Uint8List.fromList([10, 20]), // Lost packet 1000
        blockPT: 111,
        timestampOffset: 960,
      ));
      red.blocks.add(RedBlock(
        block: Uint8List.fromList([30, 40]), // Current packet 1001
        blockPT: 111,
      ));

      final base = RtpPacket(
        payloadType: 116,
        sequenceNumber: 1001,
        timestamp: 48960,
        ssrc: 12345,
        payload: Uint8List(0),
      );

      final packets = handler.push(red, base);

      expect(packets.length, equals(2));
      expect(packets[0].sequenceNumber, equals(1000)); // Recovered
      expect(packets[1].sequenceNumber, equals(1001)); // Current
    });

    test('clear tracking buffer', () {
      final handler = RedHandler();

      final red = RedPacket();
      red.blocks.add(RedBlock(
        block: Uint8List.fromList([1, 2, 3]),
        blockPT: 111,
      ));

      final base = RtpPacket(
        payloadType: 116,
        sequenceNumber: 1000,
        timestamp: 48000,
        ssrc: 12345,
        payload: Uint8List(0),
      );

      handler.push(red, base);
      expect(handler.trackedCount, equals(1));

      handler.clear();
      expect(handler.trackedCount, equals(0));
    });

    test('buffer overflow protection', () {
      final handler = RedHandler(bufferSize: 5);

      for (var i = 0; i < 10; i++) {
        final red = RedPacket();
        red.blocks.add(RedBlock(
          block: Uint8List.fromList([i]),
          blockPT: 111,
        ));

        final base = RtpPacket(
          payloadType: 116,
          sequenceNumber: i,
          timestamp: i * 960,
          ssrc: 12345,
          payload: Uint8List(0),
        );

        handler.push(red, base);
      }

      expect(handler.trackedCount, equals(5));
    });
  });

  group('RED round-trip', () {
    test('encode and decode preserves data', () {
      final encoder = RedEncoder(distance: 2);
      final handler = RedHandler();

      // Build up encoder state
      encoder.push(RedPayload(
        block: Uint8List.fromList([1, 2, 3]),
        timestamp: 0,
        blockPT: 111,
      ));
      encoder.push(RedPayload(
        block: Uint8List.fromList([4, 5, 6]),
        timestamp: 960,
        blockPT: 111,
      ));
      encoder.push(RedPayload(
        block: Uint8List.fromList([7, 8, 9]),
        timestamp: 1920,
        blockPT: 111,
      ));

      // Build RED packet
      final red = encoder.build();
      expect(red.blocks.length, equals(3));

      // Serialize and deserialize
      final serialized = red.serialize();
      final deserialized = RedPacket.deserialize(serialized);

      // Create base RTP packet
      final base = RtpPacket(
        payloadType: 116,
        sequenceNumber: 102,
        timestamp: 1920,
        ssrc: 12345,
        payload: serialized,
      );

      // Extract packets
      final packets = handler.push(deserialized, base);

      expect(packets.length, equals(3));
      expect(packets[0].payload, equals([1, 2, 3]));
      expect(packets[1].payload, equals([4, 5, 6]));
      expect(packets[2].payload, equals([7, 8, 9]));
    });
  });
}
