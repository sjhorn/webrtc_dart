import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/rtcp/nack.dart';
import 'package:webrtc_dart/src/srtp/rtcp_packet.dart';

void main() {
  group('Generic NACK', () {
    test('should serialize NACK with single lost packet', () {
      final nack = GenericNack(
        senderSsrc: 0x12345678,
        mediaSourceSsrc: 0x87654321,
        lostSeqNumbers: [1234],
      );

      final packet = nack.toRtcpPacket();

      // Verify RTCP header
      expect(packet.packetType, equals(RtcpPacketType.transportFeedback));
      expect(packet.reportCount,
          equals(GenericNack.fmt)); // fmt=1 for Generic NACK
      expect(packet.ssrc, equals(0x12345678)); // Sender SSRC

      // Parse FCI payload
      final view = ByteData.sublistView(packet.payload);
      expect(view.getUint32(0), equals(0x87654321)); // Media source SSRC

      // Parse PID+BLP
      expect(view.getUint16(4), equals(1234)); // PID
      expect(view.getUint16(6), equals(0)); // BLP (no additional lost packets)
    });

    test('should serialize NACK with consecutive lost packets', () {
      final nack = GenericNack(
        senderSsrc: 0x11111111,
        mediaSourceSsrc: 0x22222222,
        lostSeqNumbers: [100, 101, 102, 103],
      );

      final packet = nack.toRtcpPacket();

      // Verify can deserialize and all packets preserved
      final deserialized = GenericNack.deserialize(packet);
      expect(
        deserialized.lostSeqNumbers.toSet(),
        equals({100, 101, 102, 103}),
      );
    });

    test('should serialize NACK with gap in lost packets', () {
      final nack = GenericNack(
        senderSsrc: 0x11111111,
        mediaSourceSsrc: 0x22222222,
        lostSeqNumbers: [100, 102, 105], // Gaps at 101, 103, 104
      );

      final packet = nack.toRtcpPacket();

      // Verify can deserialize and all packets preserved
      final deserialized = GenericNack.deserialize(packet);
      expect(
        deserialized.lostSeqNumbers.toSet(),
        equals({100, 102, 105}),
      );
    });

    test('should serialize NACK with full BLP (16 consecutive packets)', () {
      // Lost packets: 200, 201, 202, ..., 216 (17 packets total)
      final lost = List.generate(17, (i) => 200 + i);

      final nack = GenericNack(
        senderSsrc: 0xAAAAAAAA,
        mediaSourceSsrc: 0xBBBBBBBB,
        lostSeqNumbers: lost,
      );

      final packet = nack.toRtcpPacket();

      // Verify can deserialize and all packets preserved
      final deserialized = GenericNack.deserialize(packet);
      expect(
        deserialized.lostSeqNumbers.toSet(),
        equals(lost.toSet()),
      );
    });

    test('should serialize NACK with multiple PID+BLP pairs', () {
      // Lost: 100, 101, 150, 151, 152
      final nack = GenericNack(
        senderSsrc: 0x11111111,
        mediaSourceSsrc: 0x22222222,
        lostSeqNumbers: [100, 101, 150, 151, 152],
      );

      final packet = nack.toRtcpPacket();

      // Verify can deserialize and all packets preserved
      final deserialized = GenericNack.deserialize(packet);
      expect(
        deserialized.lostSeqNumbers.toSet(),
        equals({100, 101, 150, 151, 152}),
      );
    });

    test('should deserialize NACK with single lost packet', () {
      final nack = GenericNack(
        senderSsrc: 0x12345678,
        mediaSourceSsrc: 0x87654321,
        lostSeqNumbers: [5000],
      );

      final packet = nack.toRtcpPacket();
      final deserialized = GenericNack.deserialize(packet);

      expect(deserialized.senderSsrc, equals(0x12345678));
      expect(deserialized.mediaSourceSsrc, equals(0x87654321));
      expect(deserialized.lostSeqNumbers, equals([5000]));
    });

    test('should deserialize NACK with multiple lost packets', () {
      final nack = GenericNack(
        senderSsrc: 0xAAAAAAAA,
        mediaSourceSsrc: 0xBBBBBBBB,
        lostSeqNumbers: [100, 102, 103, 105, 200],
      );

      final packet = nack.toRtcpPacket();
      final deserialized = GenericNack.deserialize(packet);

      expect(deserialized.senderSsrc, equals(0xAAAAAAAA));
      expect(deserialized.mediaSourceSsrc, equals(0xBBBBBBBB));

      // Lost sequence numbers should match
      final expected = [100, 102, 103, 105, 200];
      expect(deserialized.lostSeqNumbers.length, equals(expected.length));
      expect(
        deserialized.lostSeqNumbers.toSet().containsAll(expected),
        isTrue,
      );
    });

    test('should handle round-trip serialization', () {
      final original = GenericNack(
        senderSsrc: 0x11223344,
        mediaSourceSsrc: 0x55667788,
        lostSeqNumbers: [1, 2, 3, 100, 101, 102, 500, 502, 504],
      );

      final packet = original.toRtcpPacket();
      final deserialized = GenericNack.deserialize(packet);

      expect(deserialized.senderSsrc, equals(original.senderSsrc));
      expect(deserialized.mediaSourceSsrc, equals(original.mediaSourceSsrc));

      // Check all lost packets are preserved
      expect(
        deserialized.lostSeqNumbers.toSet(),
        equals(original.lostSeqNumbers.toSet()),
      );
    });

    test('should handle sequence number wraparound in PID+BLP', () {
      // Lost packets near wraparound boundary
      final nack = GenericNack(
        senderSsrc: 0x12345678,
        mediaSourceSsrc: 0x87654321,
        lostSeqNumbers: [0xFFFE, 0xFFFF, 0x0000, 0x0001],
      );

      final packet = nack.toRtcpPacket();
      final deserialized = GenericNack.deserialize(packet);

      // Should preserve all lost packets across wraparound
      expect(
        deserialized.lostSeqNumbers.toSet(),
        equals({0xFFFE, 0xFFFF, 0x0000, 0x0001}),
      );
    });

    test('should handle empty lost packets list', () {
      final nack = GenericNack(
        senderSsrc: 0x12345678,
        mediaSourceSsrc: 0x87654321,
        lostSeqNumbers: [],
      );

      final packet = nack.toRtcpPacket();

      // Should have media SSRC but no PID+BLP pairs
      expect(packet.payload.length, equals(4)); // Media SSRC only (4 bytes)
    });

    test('should handle maximum BLP value (all 16 bits set)', () {
      // PID + next 16 packets all lost
      final lost = List.generate(17, (i) => 1000 + i);

      final nack = GenericNack(
        senderSsrc: 0x11111111,
        mediaSourceSsrc: 0x22222222,
        lostSeqNumbers: lost,
      );

      final packet = nack.toRtcpPacket();

      // Verify can deserialize and all packets preserved
      final deserialized = GenericNack.deserialize(packet);
      expect(
        deserialized.lostSeqNumbers.toSet(),
        equals(lost.toSet()),
      );
    });

    test('should handle out-of-order lost sequence numbers', () {
      // Provide lost packets in non-sorted order
      final nack = GenericNack(
        senderSsrc: 0xAAAAAAAA,
        mediaSourceSsrc: 0xBBBBBBBB,
        lostSeqNumbers: [105, 100, 103, 101, 104],
      );

      final packet = nack.toRtcpPacket();
      final deserialized = GenericNack.deserialize(packet);

      // Should preserve all packets regardless of input order
      expect(
        deserialized.lostSeqNumbers.toSet(),
        equals({100, 101, 103, 104, 105}),
      );
    });

    test('should handle duplicate lost sequence numbers', () {
      final nack = GenericNack(
        senderSsrc: 0x11111111,
        mediaSourceSsrc: 0x22222222,
        lostSeqNumbers: [100, 101, 100, 102, 101], // Duplicates
      );

      final packet = nack.toRtcpPacket();
      final deserialized = GenericNack.deserialize(packet);

      // Should deduplicate
      expect(
        deserialized.lostSeqNumbers.toSet(),
        equals({100, 101, 102}),
      );
    });

    test('toString should include lost packet count', () {
      final nack = GenericNack(
        senderSsrc: 0x12345678,
        mediaSourceSsrc: 0x87654321,
        lostSeqNumbers: [1, 2, 3, 4, 5],
      );

      final str = nack.toString();
      expect(str, contains('GenericNack'));
    });

    test('should verify RTCP packet structure', () {
      final nack = GenericNack(
        senderSsrc: 0x12345678,
        mediaSourceSsrc: 0x87654321,
        lostSeqNumbers: [100, 101],
      );

      final packet = nack.toRtcpPacket();

      // Verify RTCP packet fields
      expect(packet.version, equals(2));
      expect(packet.padding, isFalse);
      expect(packet.reportCount, equals(GenericNack.fmt));
      expect(packet.packetType, equals(RtcpPacketType.transportFeedback));
      expect(packet.ssrc, equals(0x12345678));
    });

    test('should calculate correct RTCP packet length', () {
      final nack = GenericNack(
        senderSsrc: 0x12345678,
        mediaSourceSsrc: 0x87654321,
        lostSeqNumbers: [100],
      );

      final packet = nack.toRtcpPacket();

      // Length should be: Media SSRC (4) + PID+BLP (4) = 8 bytes
      expect(packet.payload.length, equals(8));

      // RTCP length field is (total bytes / 4) - 1
      // Total = Header (8 bytes) + payload (8 bytes) = 16 bytes
      final expectedLength = (16 ~/ 4) - 1; // 3
      expect(packet.length, equals(expectedLength));
    });
  });
}
