import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/rtp/jitter_buffer.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';

void main() {
  group('JitterBuffer', () {
    /// Create a test RTP packet with given sequence number and timestamp
    RtpPacket createRtpPacket(int sequenceNumber, int timestamp) {
      return RtpPacket(
        payloadType: 96,
        sequenceNumber: sequenceNumber,
        timestamp: timestamp,
        ssrc: 12345,
        payload: Uint8List.fromList([1, 2, 3]),
      );
    }

    test('handles continuous packets', () {
      final jitterBuffer = JitterBuffer(90000);

      for (var i = 0; i < 5; i++) {
        final outputs = jitterBuffer.processInput(
          rtp: createRtpPacket(i, i),
        );
        expect(outputs.length, equals(1));
        expect(outputs[0].rtp!.sequenceNumber, equals(i));
      }
    });

    test('handles jitter (out-of-order packets)', () {
      final jitterBuffer = JitterBuffer(90000);

      // First packet
      var outputs = jitterBuffer.processInput(rtp: createRtpPacket(0, 0));
      expect(outputs.length, equals(1));
      expect(outputs[0].rtp!.sequenceNumber, equals(0));

      // Packet 2 arrives before packet 1 (out of order)
      outputs = jitterBuffer.processInput(rtp: createRtpPacket(2, 2));
      expect(outputs, isEmpty); // Buffered, waiting for seq 1

      // Packet 1 arrives - should release both 1 and 2
      outputs = jitterBuffer.processInput(rtp: createRtpPacket(1, 1));
      expect(outputs.length, equals(2));
      expect(outputs[0].rtp!.sequenceNumber, equals(1));
      expect(outputs[1].rtp!.sequenceNumber, equals(2));

      // Packet 3 arrives normally
      outputs = jitterBuffer.processInput(rtp: createRtpPacket(3, 3));
      expect(outputs.length, equals(1));
      expect(outputs[0].rtp!.sequenceNumber, equals(3));
    });

    test('detects packet loss based on timeout', () {
      final jitterBuffer = JitterBuffer(90000);

      // First packet
      var outputs = jitterBuffer.processInput(rtp: createRtpPacket(0, 0));
      expect(outputs.length, equals(1));

      // Packets 2 and 3 arrive (packet 1 is missing)
      outputs = jitterBuffer.processInput(rtp: createRtpPacket(2, 2));
      expect(outputs, isEmpty);

      outputs = jitterBuffer.processInput(rtp: createRtpPacket(3, 3));
      expect(outputs, isEmpty);

      // Packet 4 arrives with timestamp indicating >200ms elapsed
      // 90000 Hz * 1 sec = 90000 timestamp units
      // So timestamp 4 + 90000 = 1 second later
      outputs = jitterBuffer.processInput(rtp: createRtpPacket(4, 4 + 90000));

      // First output should be packet loss notification
      expect(outputs[0].isPacketLost, isNotNull);
      expect(outputs[0].isPacketLost!.from, equals(1));
      expect(outputs[0].isPacketLost!.to, equals(3));

      // Check presentSeqNum is updated
      expect(jitterBuffer.presentSeqNum, equals(4));

      // Then we should get the buffered packets and current packet
      expect(outputs[1].rtp!.sequenceNumber, equals(2));
      expect(outputs[2].rtp!.sequenceNumber, equals(3));
      expect(outputs[3].rtp!.sequenceNumber, equals(4));

      // Next packet should work normally
      outputs = jitterBuffer.processInput(rtp: createRtpPacket(5, 5));
      expect(outputs.length, equals(1));
      expect(outputs[0].rtp!.sequenceNumber, equals(5));
    });

    test('handles duplicate packets', () {
      final jitterBuffer = JitterBuffer(90000);

      // First packet
      var outputs = jitterBuffer.processInput(rtp: createRtpPacket(0, 0));
      expect(outputs.length, equals(1));

      // Duplicate of first packet
      outputs = jitterBuffer.processInput(rtp: createRtpPacket(0, 0));
      expect(outputs, isEmpty);

      // Confirm stats recorded duplicate
      final stats = jitterBuffer.toJson();
      expect(stats['duplicate'], isNotNull);
      expect(stats['duplicate']['count'], equals(1));
    });

    test('handles end-of-stream (eol)', () {
      final jitterBuffer = JitterBuffer(90000);

      // First packet
      jitterBuffer.processInput(rtp: createRtpPacket(0, 0));

      // Buffer some packets out of order
      jitterBuffer.processInput(rtp: createRtpPacket(3, 3));
      jitterBuffer.processInput(rtp: createRtpPacket(2, 2));

      // Send EOL - should flush all buffered packets
      final outputs = jitterBuffer.processInput(eol: true);

      // Should get packets 2 and 3, then EOL
      expect(outputs.length, equals(3));
      expect(outputs[0].rtp!.sequenceNumber, equals(2));
      expect(outputs[1].rtp!.sequenceNumber, equals(3));
      expect(outputs[2].eol, isTrue);

      // Buffer should be cleared
      expect(jitterBuffer.bufferLength, equals(0));
    });

    test('handles sequence number wraparound', () {
      final jitterBuffer = JitterBuffer(90000);

      // Start near wraparound point
      var outputs =
          jitterBuffer.processInput(rtp: createRtpPacket(65534, 1000));
      expect(outputs.length, equals(1));

      // Packet at wraparound
      outputs = jitterBuffer.processInput(rtp: createRtpPacket(65535, 1001));
      expect(outputs.length, equals(1));
      expect(outputs[0].rtp!.sequenceNumber, equals(65535));

      // Packet after wraparound
      outputs = jitterBuffer.processInput(rtp: createRtpPacket(0, 1002));
      expect(outputs.length, equals(1));
      expect(outputs[0].rtp!.sequenceNumber, equals(0));

      // Continue after wraparound
      outputs = jitterBuffer.processInput(rtp: createRtpPacket(1, 1003));
      expect(outputs.length, equals(1));
      expect(outputs[0].rtp!.sequenceNumber, equals(1));
    });

    test('handles out-of-order across wraparound', () {
      final jitterBuffer = JitterBuffer(90000);

      // Start near wraparound
      var outputs =
          jitterBuffer.processInput(rtp: createRtpPacket(65534, 1000));
      expect(outputs.length, equals(1));

      // Packet 0 (after wrap) arrives before 65535
      outputs = jitterBuffer.processInput(rtp: createRtpPacket(0, 1002));
      expect(outputs, isEmpty);

      // Now 65535 arrives - should release both
      outputs = jitterBuffer.processInput(rtp: createRtpPacket(65535, 1001));
      expect(outputs.length, equals(2));
      expect(outputs[0].rtp!.sequenceNumber, equals(65535));
      expect(outputs[1].rtp!.sequenceNumber, equals(0));
    });

    test('respects buffer size limit', () {
      final jitterBuffer = JitterBuffer(
        90000,
        options: const JitterBufferOptions(bufferSize: 5),
      );

      // First packet to initialize
      jitterBuffer.processInput(rtp: createRtpPacket(0, 0));

      // Try to buffer more packets than bufferSize
      // Note: buffer allows up to bufferSize before rejecting new packets
      // So with bufferSize=5, we can have 5 packets, then next is rejected
      for (var i = 2; i < 10; i++) {
        jitterBuffer.processInput(rtp: createRtpPacket(i, i));
      }

      // Buffer should not exceed limit + 1 (due to > check matching TypeScript)
      // The check is "length > bufferSize" which allows bufferSize items
      expect(jitterBuffer.bufferLength, lessThanOrEqualTo(6));

      // Stats should record overflow
      final stats = jitterBuffer.toJson();
      expect(stats['buffer_overflow'], isNotNull);
    });

    test('toJson returns correct stats', () {
      final jitterBuffer = JitterBuffer(90000);

      jitterBuffer.processInput(rtp: createRtpPacket(0, 0));
      jitterBuffer.processInput(rtp: createRtpPacket(2, 2)); // Buffer this

      final stats = jitterBuffer.toJson();
      expect(stats['rtpBufferLength'], equals(1));
      expect(stats['presentSeqNum'], equals(0));
      expect(stats['expectNextSeqNum'], equals(1));
    });

    test('custom latency option', () {
      // Use a very short latency (10ms instead of default 200ms)
      final jitterBuffer = JitterBuffer(
        90000,
        options: const JitterBufferOptions(latencyMs: 10),
      );

      // First packet
      jitterBuffer.processInput(rtp: createRtpPacket(0, 0));

      // Buffer packet 2 (skip 1)
      jitterBuffer.processInput(rtp: createRtpPacket(2, 2));

      // Packet 3 with timestamp ~20ms later (90000 Hz * 0.02s = 1800)
      // This should trigger timeout for packet 2
      final outputs = jitterBuffer.processInput(rtp: createRtpPacket(3, 1800));

      // Should detect packet loss
      expect(outputs.any((o) => o.isPacketLost != null), isTrue);
    });
  });
}
