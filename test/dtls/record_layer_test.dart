import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/record/const.dart';
import 'package:webrtc_dart/src/dtls/record/header.dart';
import 'package:webrtc_dart/src/dtls/record/plaintext.dart';
import 'package:webrtc_dart/src/dtls/record/fragment.dart';
import 'package:webrtc_dart/src/dtls/record/anti_replay_window.dart';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';

void main() {
  group('RecordHeader', () {
    test('serializes and deserializes correctly', () {
      final header = RecordHeader(
        contentType: ContentType.handshake.value,
        protocolVersion: ProtocolVersion.dtls12,
        epoch: 0,
        sequenceNumber: 42,
        contentLen: 100,
      );

      final serialized = header.serialize();
      expect(serialized.length, dtlsRecordHeaderLength);

      final deserialized = RecordHeader.deserialize(serialized);
      expect(deserialized, equals(header));
    });

    test('handles large sequence numbers (48-bit)', () {
      final largeSeqNum = 0xFFFFFFFFFFFF; // Maximum 48-bit value

      final header = RecordHeader(
        contentType: ContentType.applicationData.value,
        protocolVersion: ProtocolVersion.dtls12,
        epoch: 1,
        sequenceNumber: largeSeqNum,
        contentLen: 256,
      );

      final serialized = header.serialize();
      final deserialized = RecordHeader.deserialize(serialized);

      expect(deserialized.sequenceNumber, largeSeqNum);
    });

    test('handles different content types', () {
      for (final type in ContentType.values) {
        final header = RecordHeader(
          contentType: type.value,
          protocolVersion: ProtocolVersion.dtls12,
          epoch: 0,
          sequenceNumber: 0,
          contentLen: 0,
        );

        final serialized = header.serialize();
        final deserialized = RecordHeader.deserialize(serialized);

        expect(deserialized.contentType, type.value);
      }
    });

    test('handles different protocol versions', () {
      final versions = [
        ProtocolVersion.dtls10,
        ProtocolVersion.dtls12,
        const ProtocolVersion(254, 252), // Custom version
      ];

      for (final version in versions) {
        final header = RecordHeader(
          contentType: ContentType.handshake.value,
          protocolVersion: version,
          epoch: 0,
          sequenceNumber: 0,
          contentLen: 0,
        );

        final serialized = header.serialize();
        final deserialized = RecordHeader.deserialize(serialized);

        expect(deserialized.protocolVersion, version);
      }
    });

    test('throws on invalid data', () {
      expect(
        () => RecordHeader.deserialize(Uint8List(5)),
        throwsArgumentError,
      );
    });

    test('equality works correctly', () {
      final header1 = RecordHeader(
        contentType: ContentType.handshake.value,
        protocolVersion: ProtocolVersion.dtls12,
        epoch: 0,
        sequenceNumber: 42,
        contentLen: 100,
      );

      final header2 = RecordHeader(
        contentType: ContentType.handshake.value,
        protocolVersion: ProtocolVersion.dtls12,
        epoch: 0,
        sequenceNumber: 42,
        contentLen: 100,
      );

      final header3 = RecordHeader(
        contentType: ContentType.alert.value,
        protocolVersion: ProtocolVersion.dtls12,
        epoch: 0,
        sequenceNumber: 42,
        contentLen: 100,
      );

      expect(header1, equals(header2));
      expect(header1.hashCode, equals(header2.hashCode));
      expect(header1, isNot(equals(header3)));
    });
  });

  group('MACHeader', () {
    test('serializes correctly for AEAD', () {
      final macHeader = MACHeader(
        epoch: 1,
        sequenceNumber: 100,
        contentType: ContentType.applicationData.value,
        protocolVersion: ProtocolVersion.dtls12,
        contentLen: 200,
      );

      final serialized = macHeader.serialize();
      expect(serialized.length, 11); // MAC header is 11 bytes

      // Verify structure
      final buffer = ByteData.sublistView(serialized);
      expect(buffer.getUint16(0), 1); // epoch
      expect(buffer.getUint8(8), ContentType.applicationData.value);
      expect(buffer.getUint8(9), 254); // DTLS 1.2 major
      expect(buffer.getUint8(10), 253); // DTLS 1.2 minor
    });

    test('creates from record header', () {
      final recordHeader = RecordHeader(
        contentType: ContentType.handshake.value,
        protocolVersion: ProtocolVersion.dtls12,
        epoch: 2,
        sequenceNumber: 500,
        contentLen: 150,
      );

      final macHeader = MACHeader.fromRecordHeader(recordHeader);

      expect(macHeader.epoch, recordHeader.epoch);
      expect(macHeader.sequenceNumber, recordHeader.sequenceNumber);
      expect(macHeader.contentType, recordHeader.contentType);
      expect(macHeader.protocolVersion, recordHeader.protocolVersion);
      expect(macHeader.contentLen, recordHeader.contentLen);
    });

    test('equality works correctly', () {
      final mac1 = MACHeader(
        epoch: 1,
        sequenceNumber: 42,
        contentType: ContentType.handshake.value,
        protocolVersion: ProtocolVersion.dtls12,
        contentLen: 100,
      );

      final mac2 = MACHeader(
        epoch: 1,
        sequenceNumber: 42,
        contentType: ContentType.handshake.value,
        protocolVersion: ProtocolVersion.dtls12,
        contentLen: 100,
      );

      expect(mac1, equals(mac2));
      expect(mac1.hashCode, equals(mac2.hashCode));
    });
  });

  group('DtlsPlaintext', () {
    test('serializes and deserializes correctly', () {
      final fragment = Uint8List.fromList([1, 2, 3, 4, 5]);
      final header = RecordHeader(
        contentType: ContentType.handshake.value,
        protocolVersion: ProtocolVersion.dtls12,
        epoch: 0,
        sequenceNumber: 10,
        contentLen: fragment.length,
      );

      final plaintext = DtlsPlaintext(header: header, fragment: fragment);

      final serialized = plaintext.serialize();
      final deserialized = DtlsPlaintext.deserialize(serialized);

      expect(deserialized, equals(plaintext));
      expect(deserialized.fragment, equals(fragment));
    });

    test('computes MAC header correctly', () {
      final fragment = Uint8List.fromList([0xAA, 0xBB, 0xCC]);
      final header = RecordHeader(
        contentType: ContentType.applicationData.value,
        protocolVersion: ProtocolVersion.dtls12,
        epoch: 1,
        sequenceNumber: 100,
        contentLen: fragment.length,
      );

      final plaintext = DtlsPlaintext(header: header, fragment: fragment);
      final macHeader = plaintext.computeMACHeader();

      expect(macHeader.epoch, header.epoch);
      expect(macHeader.sequenceNumber, header.sequenceNumber);
      expect(macHeader.contentType, header.contentType);
    });

    test('throws on buffer too short', () {
      expect(
        () => DtlsPlaintext.deserialize(Uint8List(5)),
        throwsArgumentError,
      );
    });

    test('throws on fragment length mismatch', () {
      final data = Uint8List(20);
      final buffer = ByteData.sublistView(data);

      // Set content length to 100 (more than available)
      buffer.setUint16(11, 100);

      expect(
        () => DtlsPlaintext.deserialize(data),
        throwsArgumentError,
      );
    });

    test('handles empty fragment', () {
      final header = RecordHeader(
        contentType: ContentType.handshake.value,
        protocolVersion: ProtocolVersion.dtls12,
        epoch: 0,
        sequenceNumber: 0,
        contentLen: 0,
      );

      final plaintext = DtlsPlaintext(
        header: header,
        fragment: Uint8List(0),
      );

      final serialized = plaintext.serialize();
      expect(serialized.length, dtlsRecordHeaderLength);

      final deserialized = DtlsPlaintext.deserialize(serialized);
      expect(deserialized.fragment.length, 0);
    });

    test('handles maximum size fragment', () {
      final fragment = Uint8List(dtlsMaxRecordLength);
      for (var i = 0; i < fragment.length; i++) {
        fragment[i] = i & 0xFF;
      }

      final header = RecordHeader(
        contentType: ContentType.applicationData.value,
        protocolVersion: ProtocolVersion.dtls12,
        epoch: 1,
        sequenceNumber: 1000,
        contentLen: fragment.length,
      );

      final plaintext = DtlsPlaintext(header: header, fragment: fragment);

      final serialized = plaintext.serialize();
      final deserialized = DtlsPlaintext.deserialize(serialized);

      expect(deserialized.fragment.length, dtlsMaxRecordLength);
      expect(deserialized.fragment, equals(fragment));
    });

    test('provides convenient accessors', () {
      final header = RecordHeader(
        contentType: ContentType.alert.value,
        protocolVersion: ProtocolVersion.dtls12,
        epoch: 3,
        sequenceNumber: 999,
        contentLen: 10,
      );

      final plaintext = DtlsPlaintext(
        header: header,
        fragment: Uint8List(10),
      );

      expect(plaintext.contentType, ContentType.alert);
      expect(plaintext.epoch, 3);
      expect(plaintext.sequenceNumber, 999);
      expect(plaintext.protocolVersion, ProtocolVersion.dtls12);
    });
  });

  group('FragmentedHandshake', () {
    test('serializes and deserializes correctly', () {
      final fragment = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final fragmented = FragmentedHandshake(
        msgType: HandshakeType.clientHello.value,
        length: 100,
        messageSeq: 0,
        fragmentOffset: 0,
        fragmentLength: fragment.length,
        fragment: fragment,
      );

      final serialized = fragmented.serialize();
      final deserialized = FragmentedHandshake.deserialize(serialized);

      expect(deserialized, equals(fragmented));
    });

    test('handles 24-bit fields correctly', () {
      final fragment = Uint8List(10);
      final fragmented = FragmentedHandshake(
        msgType: HandshakeType.serverHello.value,
        length: 0xFFFFFF, // Maximum 24-bit value
        messageSeq: 100,
        fragmentOffset: 0xABCDEF, // Large 24-bit offset
        fragmentLength: fragment.length,
        fragment: fragment,
      );

      final serialized = fragmented.serialize();
      final deserialized = FragmentedHandshake.deserialize(serialized);

      expect(deserialized.length, 0xFFFFFF);
      expect(deserialized.fragmentOffset, 0xABCDEF);
    });

    test('chunks message into fragments', () {
      final data = Uint8List(5000); // Large message
      for (var i = 0; i < data.length; i++) {
        data[i] = i & 0xFF;
      }

      final message = FragmentedHandshake(
        msgType: HandshakeType.certificate.value,
        length: data.length,
        messageSeq: 1,
        fragmentOffset: 0,
        fragmentLength: data.length,
        fragment: data,
      );

      final fragments = message.chunk(1200); // Chunk with 1200 byte max

      expect(fragments.length, greaterThan(1));

      // Verify all fragments have same type, length, and seq
      for (final frag in fragments) {
        expect(frag.msgType, message.msgType);
        expect(frag.length, message.length);
        expect(frag.messageSeq, message.messageSeq);
        expect(frag.fragmentLength, lessThanOrEqualTo(1200));
      }

      // Verify offsets are correct
      var expectedOffset = 0;
      for (final frag in fragments) {
        expect(frag.fragmentOffset, expectedOffset);
        expectedOffset += frag.fragmentLength;
      }
      expect(expectedOffset, data.length);
    });

    test('handles empty fragment chunking', () {
      final message = FragmentedHandshake(
        msgType: HandshakeType.serverHelloDone.value,
        length: 0,
        messageSeq: 0,
        fragmentOffset: 0,
        fragmentLength: 0,
        fragment: Uint8List(0),
      );

      final fragments = message.chunk();
      expect(fragments.length, 1);
      expect(fragments[0].fragmentLength, 0);
    });

    test('assembles fragments correctly', () {
      final originalData = Uint8List(3000);
      for (var i = 0; i < originalData.length; i++) {
        originalData[i] = i & 0xFF;
      }

      final message = FragmentedHandshake(
        msgType: HandshakeType.certificate.value,
        length: originalData.length,
        messageSeq: 5,
        fragmentOffset: 0,
        fragmentLength: originalData.length,
        fragment: originalData,
      );

      // Fragment and reassemble
      final fragments = message.chunk(800);
      final assembled = FragmentedHandshake.assemble(fragments);

      expect(assembled.msgType, message.msgType);
      expect(assembled.length, message.length);
      expect(assembled.messageSeq, message.messageSeq);
      expect(assembled.fragment, equals(originalData));
    });

    test('assembles fragments in any order', () {
      final data = Uint8List(2000);
      for (var i = 0; i < data.length; i++) {
        data[i] = i & 0xFF;
      }

      final message = FragmentedHandshake(
        msgType: HandshakeType.serverKeyExchange.value,
        length: data.length,
        messageSeq: 2,
        fragmentOffset: 0,
        fragmentLength: data.length,
        fragment: data,
      );

      final fragments = message.chunk(600);

      // Shuffle fragments
      fragments.shuffle();

      final assembled = FragmentedHandshake.assemble(fragments);
      expect(assembled.fragment, equals(data));
    });

    test('throws on empty fragment list', () {
      expect(
        () => FragmentedHandshake.assemble([]),
        throwsArgumentError,
      );
    });

    test('findAllFragments filters correctly', () {
      final fragments = <FragmentedHandshake>[
        FragmentedHandshake(
          msgType: HandshakeType.clientHello.value,
          length: 100,
          messageSeq: 0,
          fragmentOffset: 0,
          fragmentLength: 50,
          fragment: Uint8List(50),
        ),
        FragmentedHandshake(
          msgType: HandshakeType.clientHello.value,
          length: 100,
          messageSeq: 0,
          fragmentOffset: 50,
          fragmentLength: 50,
          fragment: Uint8List(50),
        ),
        FragmentedHandshake(
          msgType: HandshakeType.serverHello.value,
          length: 80,
          messageSeq: 1,
          fragmentOffset: 0,
          fragmentLength: 80,
          fragment: Uint8List(80),
        ),
      ];

      final clientHelloFrags = FragmentedHandshake.findAllFragments(
        fragments,
        HandshakeType.clientHello,
      );

      expect(clientHelloFrags.length, 2);
      for (final frag in clientHelloFrags) {
        expect(frag.msgType, HandshakeType.clientHello.value);
      }
    });

    test('findAllFragments returns empty for non-existent type', () {
      final fragments = <FragmentedHandshake>[
        FragmentedHandshake(
          msgType: HandshakeType.clientHello.value,
          length: 100,
          messageSeq: 0,
          fragmentOffset: 0,
          fragmentLength: 100,
          fragment: Uint8List(100),
        ),
      ];

      final result = FragmentedHandshake.findAllFragments(
        fragments,
        HandshakeType.finished,
      );

      expect(result, isEmpty);
    });

    test('handshakeType accessor works', () {
      final frag = FragmentedHandshake(
        msgType: HandshakeType.certificate.value,
        length: 100,
        messageSeq: 0,
        fragmentOffset: 0,
        fragmentLength: 100,
        fragment: Uint8List(100),
      );

      expect(frag.handshakeType, HandshakeType.certificate);
    });
  });

  group('AntiReplayWindow', () {
    test('accepts new packets', () {
      final window = AntiReplayWindow();

      expect(window.mayReceive(64), isTrue); // First valid packet
      expect(window.mayReceive(65), isTrue); // Newer packet
      expect(window.mayReceive(100), isTrue); // Much newer
    });

    test('rejects duplicate packets', () {
      final window = AntiReplayWindow();

      window.markAsReceived(64);
      expect(window.mayReceive(64), isFalse); // Duplicate
    });

    test('rejects packets outside window (too old)', () {
      final window = AntiReplayWindow();

      window.markAsReceived(200);
      expect(window.mayReceive(100), isFalse); // Too old (200 - 64 = 136)
    });

    test('rejects packets too far ahead', () {
      final window = AntiReplayWindow();

      window.markAsReceived(64);
      expect(window.mayReceive(200), isFalse); // Too far (64 + 65 = 129 < 200)
    });

    test('accepts packets within window', () {
      final window = AntiReplayWindow();

      window.markAsReceived(100);

      // Within window: [100 - 64 + 1, 100] = [37, 100]
      expect(window.mayReceive(50), isTrue);
      expect(window.mayReceive(75), isTrue);
      expect(window.mayReceive(99), isTrue);
    });

    test('tracks received packets correctly', () {
      final window = AntiReplayWindow();

      window.markAsReceived(64);
      window.markAsReceived(65);
      window.markAsReceived(70);

      expect(window.hasReceived(64), isTrue);
      expect(window.hasReceived(65), isTrue);
      expect(window.hasReceived(70), isTrue);
      expect(window.hasReceived(66), isFalse);
      expect(window.hasReceived(71), isFalse);
    });

    test('slides window correctly', () {
      final window = AntiReplayWindow();

      window.markAsReceived(64);
      window.markAsReceived(65);

      expect(window.ceiling, 65);

      window.markAsReceived(100);
      expect(window.ceiling, 100);

      // Old packets should now be outside window
      expect(window.mayReceive(64), isFalse);
      expect(window.mayReceive(65), isFalse);

      // But we should remember them if queried
      expect(window.hasReceived(65), isTrue);
    });

    test('handles large sequence number jumps', () {
      final window = AntiReplayWindow();

      window.markAsReceived(100);
      window.markAsReceived(200); // Jump of 100

      expect(window.ceiling, 200);
      expect(window.hasReceived(200), isTrue);

      // Old value should be forgotten
      expect(window.mayReceive(100), isFalse);
    });

    test('reset clears state', () {
      final window = AntiReplayWindow();

      window.markAsReceived(100);
      window.markAsReceived(101);
      window.markAsReceived(102);

      window.reset();

      expect(window.ceiling, 63); // Back to initial state
      expect(window.mayReceive(100), isTrue); // Can receive again
    });

    test('handles sequential packet stream', () {
      final window = AntiReplayWindow();

      // Simulate receiving packets 64-200 in order
      for (var i = 64; i <= 200; i++) {
        expect(window.mayReceive(i), isTrue);
        window.markAsReceived(i);
        expect(window.hasReceived(i), isTrue);
      }

      expect(window.ceiling, 200);
    });

    test('handles out-of-order packets', () {
      final window = AntiReplayWindow();

      // Receive packets out of order
      window.markAsReceived(100);
      window.markAsReceived(98);
      window.markAsReceived(99);
      window.markAsReceived(97);

      expect(window.hasReceived(97), isTrue);
      expect(window.hasReceived(98), isTrue);
      expect(window.hasReceived(99), isTrue);
      expect(window.hasReceived(100), isTrue);

      // Try to receive duplicates
      expect(window.mayReceive(97), isFalse);
      expect(window.mayReceive(98), isFalse);
    });

    test('window state is readable', () {
      final window = AntiReplayWindow();

      window.markAsReceived(64);
      window.markAsReceived(65);

      expect(window.ceiling, 65);
      expect(window.window.length, 2); // width(64) / intSize(32) = 2
    });
  });
}
