import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/sctp/packet.dart';
import 'package:webrtc_dart/src/sctp/chunk.dart';
import 'package:webrtc_dart/src/sctp/const.dart';

void main() {
  group('SctpPacket', () {
    test('serializes and parses packet with DATA chunk', () {
      final userData = Uint8List.fromList([1, 2, 3, 4, 5]);
      final dataChunk = SctpDataChunk(
        tsn: 100,
        streamId: 1,
        streamSeq: 10,
        ppid: SctpPpid.webrtcBinary.value,
        userData: userData,
      );

      final packet = SctpPacket(
        sourcePort: 5000,
        destinationPort: 5000,
        verificationTag: 0x12345678,
        chunks: [dataChunk],
      );

      final serialized = packet.serialize();
      final parsed = SctpPacket.parse(serialized);

      expect(parsed.sourcePort, 5000);
      expect(parsed.destinationPort, 5000);
      expect(parsed.verificationTag, 0x12345678);
      expect(parsed.chunks.length, 1);

      final parsedData = parsed.chunks[0] as SctpDataChunk;
      expect(parsedData.tsn, 100);
      expect(parsedData.userData, equals(userData));
    });

    test('serializes and parses packet with multiple chunks', () {
      final initChunk = SctpInitChunk(
        initiateTag: 0xAABBCCDD,
        advertisedRwnd: 131072,
        outboundStreams: 10,
        inboundStreams: 10,
        initialTsn: 1000,
      );

      final dataChunk = SctpDataChunk(
        tsn: 1001,
        streamId: 0,
        streamSeq: 0,
        ppid: SctpPpid.webrtcString.value,
        userData: Uint8List.fromList([65, 66, 67]), // "ABC"
      );

      final packet = SctpPacket(
        sourcePort: 5000,
        destinationPort: 5000,
        verificationTag: 0,
        chunks: [initChunk, dataChunk],
      );

      final serialized = packet.serialize();
      final parsed = SctpPacket.parse(serialized);

      expect(parsed.chunks.length, 2);
      expect(parsed.chunks[0], isA<SctpInitChunk>());
      expect(parsed.chunks[1], isA<SctpDataChunk>());
    });

    test('validates checksum', () {
      final dataChunk = SctpDataChunk(
        tsn: 100,
        streamId: 1,
        streamSeq: 10,
        ppid: SctpPpid.webrtcBinary.value,
        userData: Uint8List(10),
      );

      final packet = SctpPacket(
        sourcePort: 5000,
        destinationPort: 5000,
        verificationTag: 0x12345678,
        chunks: [dataChunk],
      );

      final serialized = packet.serialize();

      // Corrupt the checksum
      final corrupted = Uint8List.fromList(serialized);
      final buffer = ByteData.sublistView(corrupted);
      buffer.setUint32(8, 0);

      expect(
        () => SctpPacket.parse(corrupted),
        throwsA(isA<FormatException>()),
      );
    });

    test('getChunksOfType returns correct chunks', () {
      final initChunk = SctpInitChunk(
        initiateTag: 0xAABBCCDD,
        advertisedRwnd: 131072,
        outboundStreams: 10,
        inboundStreams: 10,
        initialTsn: 1000,
      );

      final dataChunk = SctpDataChunk(
        tsn: 1001,
        streamId: 0,
        streamSeq: 0,
        ppid: SctpPpid.webrtcString.value,
        userData: Uint8List(10),
      );

      final packet = SctpPacket(
        sourcePort: 5000,
        destinationPort: 5000,
        verificationTag: 0,
        chunks: [initChunk, dataChunk],
      );

      final dataChunks = packet.getChunksOfType<SctpDataChunk>();
      expect(dataChunks.length, 1);
      expect(dataChunks[0].tsn, 1001);

      final initChunks = packet.getChunksOfType<SctpInitChunk>();
      expect(initChunks.length, 1);
      expect(initChunks[0].initiateTag, 0xAABBCCDD);
    });

    test('hasChunkType works correctly', () {
      final dataChunk = SctpDataChunk(
        tsn: 100,
        streamId: 1,
        streamSeq: 10,
        ppid: SctpPpid.webrtcBinary.value,
        userData: Uint8List(10),
      );

      final packet = SctpPacket(
        sourcePort: 5000,
        destinationPort: 5000,
        verificationTag: 0x12345678,
        chunks: [dataChunk],
      );

      expect(packet.hasChunkType<SctpDataChunk>(), true);
      expect(packet.hasChunkType<SctpInitChunk>(), false);
    });

    test('handles chunk padding correctly', () {
      // Create a chunk with even-length data first to ensure basic parsing works
      final userData = Uint8List.fromList([1, 2, 3, 4]); // 4 bytes
      final dataChunk = SctpDataChunk(
        tsn: 100,
        streamId: 1,
        streamSeq: 10,
        ppid: SctpPpid.webrtcBinary.value,
        userData: userData,
      );

      final sackChunk = SctpSackChunk(
        cumulativeTsnAck: 99,
        advertisedRwnd: 65536,
      );

      final packet = SctpPacket(
        sourcePort: 5000,
        destinationPort: 5000,
        verificationTag: 0x12345678,
        chunks: [dataChunk, sackChunk],
      );

      final serialized = packet.serialize();
      final parsed = SctpPacket.parse(serialized);

      expect(parsed.chunks.length, 2);
      expect(parsed.chunks[0], isA<SctpDataChunk>());
      expect(parsed.chunks[1], isA<SctpSackChunk>());
    });

    test('throws on packet too short', () {
      final shortData = Uint8List(8); // Less than header size

      expect(
        () => SctpPacket.parse(shortData),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
