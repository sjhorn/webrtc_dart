import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/nonstandard/processor/stream_statistics.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';

RtpPacket _createPacket({
  required int sequenceNumber,
  required int timestamp,
}) {
  return RtpPacket(
    version: 2,
    padding: false,
    extension: false,
    marker: false,
    payloadType: 96,
    sequenceNumber: sequenceNumber,
    timestamp: timestamp,
    ssrc: 0x12345678,
    csrcs: [],
    payload: Uint8List(100),
  );
}

void main() {
  group('StreamStatistics', () {
    test('creates with clock rate', () {
      final stats = StreamStatistics(90000);

      expect(stats.clockRate, equals(90000));
      expect(stats.packetsReceived, equals(0));
      expect(stats.baseSeq, isNull);
      expect(stats.maxSeq, isNull);
    });

    test('tracks first packet', () {
      final stats = StreamStatistics(90000);

      stats.add(_createPacket(sequenceNumber: 1000, timestamp: 0));

      expect(stats.packetsReceived, equals(1));
      expect(stats.baseSeq, equals(1000));
      expect(stats.maxSeq, equals(1000));
    });

    test('tracks sequence numbers in order', () {
      final stats = StreamStatistics(90000);

      stats.add(_createPacket(sequenceNumber: 100, timestamp: 0));
      stats.add(_createPacket(sequenceNumber: 101, timestamp: 3000));
      stats.add(_createPacket(sequenceNumber: 102, timestamp: 6000));

      expect(stats.packetsReceived, equals(3));
      expect(stats.baseSeq, equals(100));
      expect(stats.maxSeq, equals(102));
    });

    test('handles out of order packets', () {
      final stats = StreamStatistics(90000);

      stats.add(_createPacket(sequenceNumber: 100, timestamp: 0));
      stats.add(_createPacket(sequenceNumber: 102, timestamp: 6000));
      stats.add(_createPacket(sequenceNumber: 101, timestamp: 3000)); // Out of order

      expect(stats.packetsReceived, equals(3));
      expect(stats.maxSeq, equals(102)); // Still 102
    });

    test('calculates packets expected', () {
      final stats = StreamStatistics(90000);

      stats.add(_createPacket(sequenceNumber: 100, timestamp: 0));
      stats.add(_createPacket(sequenceNumber: 105, timestamp: 15000));

      // Expected: 105 - 100 + 1 = 6
      expect(stats.packetsExpected, equals(6));
    });

    test('calculates packets lost', () {
      final stats = StreamStatistics(90000);

      stats.add(_createPacket(sequenceNumber: 100, timestamp: 0));
      stats.add(_createPacket(sequenceNumber: 105, timestamp: 15000));

      // Expected 6, received 2 = 4 lost
      expect(stats.packetsLost, equals(4));
    });

    test('handles sequence wraparound', () {
      final stats = StreamStatistics(90000);

      stats.add(_createPacket(sequenceNumber: 65530, timestamp: 0));
      stats.add(_createPacket(sequenceNumber: 65535, timestamp: 15000));
      stats.add(_createPacket(sequenceNumber: 5, timestamp: 33000)); // Wrapped

      expect(stats.cycles, equals(65536));
      expect(stats.maxSeq, equals(5));
      // Extended: 65536 + 5 - 65530 + 1 = 12
      expect(stats.packetsExpected, equals(12));
    });

    test('calculates jitter', () {
      final stats = StreamStatistics(90000);

      // Packets arriving at consistent intervals
      final baseTime = DateTime.now().millisecondsSinceEpoch / 1000.0;
      stats.add(
        _createPacket(sequenceNumber: 100, timestamp: 0),
        baseTime,
      );
      stats.add(
        _createPacket(sequenceNumber: 101, timestamp: 3000),
        baseTime + (3000 / 90000), // Perfect timing
      );

      // Jitter should be low for perfectly timed packets
      expect(stats.jitter, lessThan(100));
    });

    test('jitter increases with network variation', () {
      final stats = StreamStatistics(90000);

      final baseTime = 0.0;
      stats.add(
        _createPacket(sequenceNumber: 100, timestamp: 0),
        baseTime,
      );
      stats.add(
        _createPacket(sequenceNumber: 101, timestamp: 3000),
        baseTime + 0.1, // 100ms instead of 33ms - high jitter!
      );

      // Jitter should be significant
      expect(stats.jitter, greaterThan(0));
    });

    test('fraction lost calculation', () {
      final stats = StreamStatistics(90000);

      stats.add(_createPacket(sequenceNumber: 100, timestamp: 0));
      stats.add(_createPacket(sequenceNumber: 103, timestamp: 9000)); // 2 lost

      // First call: 4 expected, 2 received = 50% = 128
      final fraction1 = stats.fractionLost;
      expect(fraction1, equals(128));

      // Add more without loss
      stats.add(_createPacket(sequenceNumber: 104, timestamp: 12000));
      stats.add(_createPacket(sequenceNumber: 105, timestamp: 15000));

      // Second call: 2 expected, 2 received = 0% = 0
      final fraction2 = stats.fractionLost;
      expect(fraction2, equals(0));
    });

    test('fraction lost returns 0 for no packets', () {
      final stats = StreamStatistics(90000);
      // Reading before any packets
      expect(stats.fractionLost, equals(0));
    });

    test('extended highest sequence', () {
      final stats = StreamStatistics(90000);

      stats.add(_createPacket(sequenceNumber: 100, timestamp: 0));
      expect(stats.extendedHighestSequence, equals(100));

      // After wraparound - packets need to be close enough for uint16Gt to work
      // Start near the wraparound point
      final stats2 = StreamStatistics(90000);
      stats2.add(_createPacket(sequenceNumber: 65530, timestamp: 0));
      stats2.add(_createPacket(sequenceNumber: 65535, timestamp: 1000));
      stats2.add(_createPacket(sequenceNumber: 5, timestamp: 2000)); // Wrapped
      expect(stats2.extendedHighestSequence, equals(65536 + 5));
    });

    test('packets lost never negative', () {
      final stats = StreamStatistics(90000);

      // More packets received than expected (duplicates)
      stats.add(_createPacket(sequenceNumber: 100, timestamp: 0));
      stats.add(_createPacket(sequenceNumber: 100, timestamp: 0)); // Duplicate

      expect(stats.packetsLost, equals(0));
    });

    test('toJson includes all fields', () {
      final stats = StreamStatistics(48000);

      stats.add(_createPacket(sequenceNumber: 500, timestamp: 0));
      stats.add(_createPacket(sequenceNumber: 501, timestamp: 960));

      final json = stats.toJson();

      expect(json['clockRate'], equals(48000));
      expect(json['baseSeq'], equals(500));
      expect(json['maxSeq'], equals(501));
      expect(json['packetsReceived'], equals(2));
      expect(json.containsKey('packetsExpected'), isTrue);
      expect(json.containsKey('packetsLost'), isTrue);
      expect(json.containsKey('jitter'), isTrue);
    });
  });
}
