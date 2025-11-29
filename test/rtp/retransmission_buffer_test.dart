/// Retransmission Buffer Tests
///
/// Tests for the circular buffer used to cache sent RTP packets
/// for retransmission upon NACK feedback.

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/rtp/retransmission_buffer.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';

void main() {
  group('RetransmissionBuffer', () {
    group('initialization', () {
      test('creates buffer with default size', () {
        final buffer = RetransmissionBuffer();
        expect(buffer.bufferSize, equals(RetransmissionBuffer.defaultBufferSize));
        expect(buffer.packetCount, equals(0));
      });

      test('creates buffer with custom size', () {
        final buffer = RetransmissionBuffer(bufferSize: 64);
        expect(buffer.bufferSize, equals(64));
        expect(buffer.packetCount, equals(0));
      });

      test('default buffer size is 128', () {
        expect(RetransmissionBuffer.defaultBufferSize, equals(128));
      });
    });

    group('store', () {
      test('stores single packet', () {
        final buffer = RetransmissionBuffer();
        final packet = _createPacket(sequenceNumber: 100, payload: [1, 2, 3]);

        buffer.store(packet);

        expect(buffer.packetCount, equals(1));
        final retrieved = buffer.retrieve(100);
        expect(retrieved, isNotNull);
        expect(retrieved!.sequenceNumber, equals(100));
      });

      test('stores multiple packets', () {
        final buffer = RetransmissionBuffer();

        for (var i = 0; i < 10; i++) {
          buffer.store(_createPacket(sequenceNumber: 100 + i));
        }

        expect(buffer.packetCount, equals(10));

        // All should be retrievable
        for (var i = 0; i < 10; i++) {
          expect(buffer.retrieve(100 + i), isNotNull);
        }
      });

      test('stores packets at correct index based on sequence number modulo', () {
        final buffer = RetransmissionBuffer(bufferSize: 16);

        // Store packet at seq 5
        buffer.store(_createPacket(sequenceNumber: 5));
        expect(buffer.retrieve(5), isNotNull);

        // Store packet at seq 21 (5 + 16), same index
        buffer.store(_createPacket(sequenceNumber: 21));

        // Seq 5 should now be overwritten
        expect(buffer.retrieve(5), isNull);
        expect(buffer.retrieve(21), isNotNull);
      });
    });

    group('retrieve', () {
      test('retrieves stored packet', () {
        final buffer = RetransmissionBuffer();
        final packet = _createPacket(
          sequenceNumber: 12345,
          payload: [0xAA, 0xBB, 0xCC],
        );

        buffer.store(packet);
        final retrieved = buffer.retrieve(12345);

        expect(retrieved, isNotNull);
        expect(retrieved!.sequenceNumber, equals(12345));
        expect(retrieved.payload, equals([0xAA, 0xBB, 0xCC]));
      });

      test('returns null for non-existent packet', () {
        final buffer = RetransmissionBuffer();
        buffer.store(_createPacket(sequenceNumber: 100));

        expect(buffer.retrieve(200), isNull);
      });

      test('returns null when packet has been overwritten', () {
        final buffer = RetransmissionBuffer(bufferSize: 8);

        // Fill buffer and overwrite
        for (var i = 0; i < 16; i++) {
          buffer.store(_createPacket(sequenceNumber: i));
        }

        // First 8 packets should be overwritten
        for (var i = 0; i < 8; i++) {
          expect(buffer.retrieve(i), isNull,
              reason: 'Packet $i should be overwritten');
        }

        // Last 8 packets should still be available
        for (var i = 8; i < 16; i++) {
          expect(buffer.retrieve(i), isNotNull,
              reason: 'Packet $i should still be available');
        }
      });

      test('verifies sequence number to detect overwrites', () {
        final buffer = RetransmissionBuffer(bufferSize: 16);

        // Store at index 5 (seq 5)
        buffer.store(_createPacket(sequenceNumber: 5));

        // Overwrite with seq 21 (same index 5 = 21 % 16)
        buffer.store(_createPacket(sequenceNumber: 21));

        // Retrieving seq 5 should return null (overwritten)
        expect(buffer.retrieve(5), isNull);

        // Retrieving seq 21 should work
        expect(buffer.retrieve(21)?.sequenceNumber, equals(21));
      });
    });

    group('clear', () {
      test('removes all packets', () {
        final buffer = RetransmissionBuffer();

        for (var i = 0; i < 10; i++) {
          buffer.store(_createPacket(sequenceNumber: i));
        }

        expect(buffer.packetCount, equals(10));

        buffer.clear();

        expect(buffer.packetCount, equals(0));

        // All should return null
        for (var i = 0; i < 10; i++) {
          expect(buffer.retrieve(i), isNull);
        }
      });
    });

    group('sequence number handling', () {
      test('handles sequence number 0', () {
        final buffer = RetransmissionBuffer();
        buffer.store(_createPacket(sequenceNumber: 0));

        expect(buffer.retrieve(0), isNotNull);
        expect(buffer.retrieve(0)!.sequenceNumber, equals(0));
      });

      test('handles max sequence number (65535)', () {
        final buffer = RetransmissionBuffer();
        buffer.store(_createPacket(sequenceNumber: 65535));

        expect(buffer.retrieve(65535), isNotNull);
        expect(buffer.retrieve(65535)!.sequenceNumber, equals(65535));
      });

      test('handles sequence number wraparound', () {
        final buffer = RetransmissionBuffer(bufferSize: 32);

        // Store packets around wraparound point
        for (var i = 65530; i <= 65535; i++) {
          buffer.store(_createPacket(sequenceNumber: i));
        }
        for (var i = 0; i <= 5; i++) {
          buffer.store(_createPacket(sequenceNumber: i));
        }

        // All should be retrievable
        for (var i = 65530; i <= 65535; i++) {
          expect(buffer.retrieve(i), isNotNull,
              reason: 'Packet $i should be retrievable');
        }
        for (var i = 0; i <= 5; i++) {
          expect(buffer.retrieve(i), isNotNull,
              reason: 'Packet $i should be retrievable');
        }
      });
    });

    group('circular behavior', () {
      test('overwrites oldest packets when full', () {
        final buffer = RetransmissionBuffer(bufferSize: 4);

        // Store 6 packets in buffer of size 4
        for (var i = 0; i < 6; i++) {
          buffer.store(_createPacket(sequenceNumber: i));
        }

        // Only 4 packets should be stored
        expect(buffer.packetCount, equals(4));

        // First 2 should be overwritten
        expect(buffer.retrieve(0), isNull);
        expect(buffer.retrieve(1), isNull);

        // Last 4 should be present
        expect(buffer.retrieve(2), isNotNull);
        expect(buffer.retrieve(3), isNotNull);
        expect(buffer.retrieve(4), isNotNull);
        expect(buffer.retrieve(5), isNotNull);
      });

      test('handles gaps in sequence numbers', () {
        final buffer = RetransmissionBuffer(bufferSize: 16);

        // Store packets with gaps
        buffer.store(_createPacket(sequenceNumber: 100));
        buffer.store(_createPacket(sequenceNumber: 105));
        buffer.store(_createPacket(sequenceNumber: 110));

        expect(buffer.packetCount, equals(3));

        expect(buffer.retrieve(100), isNotNull);
        expect(buffer.retrieve(105), isNotNull);
        expect(buffer.retrieve(110), isNotNull);

        // Gaps should return null
        expect(buffer.retrieve(102), isNull);
        expect(buffer.retrieve(107), isNull);
      });
    });

    group('payload preservation', () {
      test('preserves full packet data', () {
        final buffer = RetransmissionBuffer();
        final packet = RtpPacket(
          version: 2,
          padding: false,
          extension: true,
          marker: true,
          payloadType: 96,
          sequenceNumber: 1234,
          timestamp: 567890,
          ssrc: 0x12345678,
          csrcs: [0x11111111, 0x22222222],
          extensionHeader: RtpExtension(
            profile: 0xBEDE,
            data: Uint8List.fromList([0x01, 0x02, 0x03, 0x04]),
          ),
          payload: Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD, 0xEE]),
          paddingLength: 0,
        );

        buffer.store(packet);
        final retrieved = buffer.retrieve(1234)!;

        expect(retrieved.version, equals(2));
        expect(retrieved.marker, isTrue);
        expect(retrieved.payloadType, equals(96));
        expect(retrieved.timestamp, equals(567890));
        expect(retrieved.ssrc, equals(0x12345678));
        expect(retrieved.csrcs, equals([0x11111111, 0x22222222]));
        expect(retrieved.extensionHeader?.profile, equals(0xBEDE));
        expect(retrieved.payload, equals([0xAA, 0xBB, 0xCC, 0xDD, 0xEE]));
      });

      test('preserves empty payload', () {
        final buffer = RetransmissionBuffer();
        buffer.store(_createPacket(sequenceNumber: 100, payload: []));

        final retrieved = buffer.retrieve(100);
        expect(retrieved, isNotNull);
        expect(retrieved!.payload.length, equals(0));
      });

      test('preserves large payload', () {
        final buffer = RetransmissionBuffer();
        final largePayload = List.generate(1400, (i) => i % 256);
        buffer.store(_createPacket(sequenceNumber: 100, payload: largePayload));

        final retrieved = buffer.retrieve(100);
        expect(retrieved, isNotNull);
        expect(retrieved!.payload.length, equals(1400));
        expect(retrieved.payload, equals(largePayload));
      });
    });

    group('concurrent access patterns', () {
      test('handles rapid store and retrieve', () {
        final buffer = RetransmissionBuffer(bufferSize: 64);

        // Simulate rapid sending with occasional retrieval
        for (var i = 0; i < 100; i++) {
          buffer.store(_createPacket(sequenceNumber: i));

          // Occasionally retrieve recent packets
          if (i >= 10 && i % 5 == 0) {
            final retrieved = buffer.retrieve(i - 5);
            expect(retrieved, isNotNull,
                reason: 'Recent packet ${i - 5} should be available');
          }
        }
      });

      test('handles store at same index multiple times', () {
        final buffer = RetransmissionBuffer(bufferSize: 8);

        // Store multiple packets that map to same index
        // All map to index 0: 0, 8, 16, 24
        for (var seq in [0, 8, 16, 24]) {
          buffer.store(_createPacket(sequenceNumber: seq, payload: [seq]));
        }

        // Only the last one (24) should be retrievable
        expect(buffer.retrieve(0), isNull);
        expect(buffer.retrieve(8), isNull);
        expect(buffer.retrieve(16), isNull);

        final retrieved = buffer.retrieve(24);
        expect(retrieved, isNotNull);
        expect(retrieved!.payload, equals([24]));
      });
    });
  });
}

/// Helper to create RTP packets for testing
RtpPacket _createPacket({
  required int sequenceNumber,
  List<int> payload = const [0x00],
}) {
  return RtpPacket(
    version: 2,
    padding: false,
    extension: false,
    marker: false,
    payloadType: 96,
    sequenceNumber: sequenceNumber,
    timestamp: sequenceNumber * 160,
    ssrc: 0x12345678,
    csrcs: [],
    extensionHeader: null,
    payload: Uint8List.fromList(payload),
    paddingLength: 0,
  );
}
