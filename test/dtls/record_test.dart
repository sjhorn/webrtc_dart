import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/context/cipher_context.dart';
import 'package:webrtc_dart/src/dtls/context/dtls_context.dart';
import 'package:webrtc_dart/src/dtls/record/const.dart';
import 'package:webrtc_dart/src/dtls/record/record.dart';
import 'package:webrtc_dart/src/dtls/record/record_layer.dart';

void main() {
  group('DtlsRecord', () {
    test('serializes and parses correctly', () {
      final fragment = Uint8List.fromList([1, 2, 3, 4, 5]);
      final record = DtlsRecord(
        contentType: ContentType.handshake,
        version: ProtocolVersion.dtls12,
        epoch: 0,
        sequenceNumber: 42,
        fragment: fragment,
      );

      final serialized = record.serialize();
      expect(serialized.length, dtlsRecordHeaderLength + fragment.length);

      final parsed = DtlsRecord.parse(serialized);
      expect(parsed.contentType, record.contentType);
      expect(parsed.version, record.version);
      expect(parsed.epoch, record.epoch);
      expect(parsed.sequenceNumber, record.sequenceNumber);
      expect(parsed.fragment, equals(fragment));
    });

    test('parses multiple records from datagram', () {
      final record1 = DtlsRecord(
        contentType: ContentType.handshake,
        version: ProtocolVersion.dtls12,
        epoch: 0,
        sequenceNumber: 1,
        fragment: Uint8List.fromList([1, 2, 3]),
      );

      final record2 = DtlsRecord(
        contentType: ContentType.alert,
        version: ProtocolVersion.dtls12,
        epoch: 0,
        sequenceNumber: 2,
        fragment: Uint8List.fromList([4, 5]),
      );

      final data = Uint8List.fromList([
        ...record1.serialize(),
        ...record2.serialize(),
      ]);

      final records = DtlsRecord.parseMultiple(data);
      expect(records.length, 2);

      expect(records[0].contentType, ContentType.handshake);
      expect(records[0].sequenceNumber, 1);
      expect(records[0].fragment, equals(Uint8List.fromList([1, 2, 3])));

      expect(records[1].contentType, ContentType.alert);
      expect(records[1].sequenceNumber, 2);
      expect(records[1].fragment, equals(Uint8List.fromList([4, 5])));
    });

    test('handles large sequence numbers', () {
      final largeSeq = 0xFFFFFFFFFFFF;
      final record = DtlsRecord(
        contentType: ContentType.applicationData,
        version: ProtocolVersion.dtls12,
        epoch: 1,
        sequenceNumber: largeSeq,
        fragment: Uint8List.fromList([1]),
      );

      final serialized = record.serialize();
      final parsed = DtlsRecord.parse(serialized);
      expect(parsed.sequenceNumber, largeSeq);
    });
  });

  group('DtlsRecordLayer', () {
    test('creates plaintext records', () {
      final dtlsContext = DtlsContext();
      final cipherContext = CipherContext(isClient: true);
      final recordLayer = DtlsRecordLayer(
        dtlsContext: dtlsContext,
        cipherContext: cipherContext,
      );

      final data = Uint8List.fromList([1, 2, 3, 4]);
      final record = recordLayer.wrapHandshake(data);

      expect(record.contentType, ContentType.handshake);
      expect(record.version, ProtocolVersion.dtls12);
      expect(record.epoch, 0);
      expect(record.fragment, equals(data));
    });

    test('increments sequence number', () {
      final dtlsContext = DtlsContext();
      final cipherContext = CipherContext(isClient: true);
      final recordLayer = DtlsRecordLayer(
        dtlsContext: dtlsContext,
        cipherContext: cipherContext,
      );

      final data = Uint8List.fromList([1]);
      final record1 = recordLayer.wrapHandshake(data);
      final record2 = recordLayer.wrapHandshake(data);
      final record3 = recordLayer.wrapHandshake(data);

      expect(record1.sequenceNumber, 0);
      expect(record2.sequenceNumber, 1);
      expect(record3.sequenceNumber, 2);
    });

    test('processes plaintext records', () async {
      final dtlsContext = DtlsContext();
      final cipherContext = CipherContext(isClient: false);
      final recordLayer = DtlsRecordLayer(
        dtlsContext: dtlsContext,
        cipherContext: cipherContext,
      );

      final fragment = Uint8List.fromList([1, 2, 3, 4]);
      final record = DtlsRecord(
        contentType: ContentType.handshake,
        version: ProtocolVersion.dtls12,
        epoch: 0,
        sequenceNumber: 0,
        fragment: fragment,
      );

      final serialized = record.serialize();
      final processed = await recordLayer.processRecords(serialized);

      expect(processed.length, 1);
      expect(processed[0].contentType, ContentType.handshake);
      expect(processed[0].data, equals(fragment));
    });
  });
}
