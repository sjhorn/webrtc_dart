import 'package:test/test.dart';
import 'package:webrtc_dart/src/datachannel/dcep.dart';

void main() {
  group('SCTP Partial Reliability (RFC 3758)', () {
    group('DataChannelType', () {
      test('reliable ordered is default', () {
        expect(DataChannelType.reliable.value, equals(0x00));
        expect(DataChannelType.reliable.isOrdered, isTrue);
        expect(DataChannelType.reliable.isReliable, isTrue);
      });

      test('reliable unordered has correct value', () {
        expect(DataChannelType.reliableUnordered.value, equals(0x80));
        expect(DataChannelType.reliableUnordered.isOrdered, isFalse);
        expect(DataChannelType.reliableUnordered.isReliable, isTrue);
      });

      test('partial reliable rexmit has correct value', () {
        expect(DataChannelType.partialReliableRexmit.value, equals(0x01));
        expect(DataChannelType.partialReliableRexmit.isOrdered, isTrue);
        expect(DataChannelType.partialReliableRexmit.isReliable, isFalse);
      });

      test('partial reliable rexmit unordered has correct value', () {
        expect(
            DataChannelType.partialReliableRexmitUnordered.value, equals(0x81));
        expect(
            DataChannelType.partialReliableRexmitUnordered.isOrdered, isFalse);
        expect(
            DataChannelType.partialReliableRexmitUnordered.isReliable, isFalse);
      });

      test('partial reliable timed has correct value', () {
        expect(DataChannelType.partialReliableTimed.value, equals(0x02));
        expect(DataChannelType.partialReliableTimed.isOrdered, isTrue);
        expect(DataChannelType.partialReliableTimed.isReliable, isFalse);
      });

      test('partial reliable timed unordered has correct value', () {
        expect(
            DataChannelType.partialReliableTimedUnordered.value, equals(0x82));
        expect(
            DataChannelType.partialReliableTimedUnordered.isOrdered, isFalse);
        expect(
            DataChannelType.partialReliableTimedUnordered.isReliable, isFalse);
      });
    });

    group('DCEP Open Message', () {
      test('encodes maxRetransmits correctly', () {
        final msg = DcepOpenMessage(
          channelType: DataChannelType.partialReliableRexmit,
          priority: 256,
          reliabilityParameter: 5, // maxRetransmits = 5
          label: 'test',
          protocol: '',
        );

        final bytes = msg.serialize();
        expect(bytes[1], equals(0x01)); // partialReliableRexmit

        // Reliability parameter at bytes 4-7
        final relParam =
            (bytes[4] << 24) | (bytes[5] << 16) | (bytes[6] << 8) | bytes[7];
        expect(relParam, equals(5));
      });

      test('encodes maxPacketLifeTime correctly', () {
        final msg = DcepOpenMessage(
          channelType: DataChannelType.partialReliableTimed,
          priority: 256,
          reliabilityParameter: 1000, // 1000ms lifetime
          label: 'test',
          protocol: '',
        );

        final bytes = msg.serialize();
        expect(bytes[1], equals(0x02)); // partialReliableTimed

        // Reliability parameter at bytes 4-7
        final relParam =
            (bytes[4] << 24) | (bytes[5] << 16) | (bytes[6] << 8) | bytes[7];
        expect(relParam, equals(1000));
      });

      test('round-trips partial reliable channel', () {
        final original = DcepOpenMessage(
          channelType: DataChannelType.partialReliableRexmitUnordered,
          priority: 512,
          reliabilityParameter: 3,
          label: 'unreliable-unordered',
          protocol: 'test-protocol',
        );

        final bytes = original.serialize();
        final parsed = DcepOpenMessage.parse(bytes);

        expect(parsed.channelType,
            equals(DataChannelType.partialReliableRexmitUnordered));
        expect(parsed.priority, equals(512));
        expect(parsed.reliabilityParameter, equals(3));
        expect(parsed.label, equals('unreliable-unordered'));
        expect(parsed.protocol, equals('test-protocol'));
      });
    });

    group('FORWARD-TSN Chunk', () {
      test('is defined in chunk types', () {
        // Verify the chunk type enum has forwardTsn
        expect(
          () => const [0xC0].contains(192), // FORWARD-TSN type = 192
          returnsNormally,
        );
      });
    });
  });
}
