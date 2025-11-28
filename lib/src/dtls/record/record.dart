import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/record/const.dart';

/// DTLS Record
/// RFC 6347 Section 4.1
class DtlsRecord {
  /// Content type
  final ContentType contentType;

  /// Protocol version
  final ProtocolVersion version;

  /// Epoch (for replay protection)
  final int epoch;

  /// Sequence number (48-bit)
  final int sequenceNumber;

  /// Payload data (plaintext or ciphertext)
  final Uint8List fragment;

  DtlsRecord({
    required this.contentType,
    required this.version,
    required this.epoch,
    required this.sequenceNumber,
    required this.fragment,
  });

  /// Serialize record to bytes
  Uint8List serialize() {
    final buffer = ByteData(dtlsRecordHeaderLength + fragment.length);
    int offset = 0;

    // Content type (1 byte)
    buffer.setUint8(offset, contentType.value);
    offset += 1;

    // Version (2 bytes)
    buffer.setUint8(offset, version.major);
    buffer.setUint8(offset + 1, version.minor);
    offset += 2;

    // Epoch (2 bytes)
    buffer.setUint16(offset, epoch);
    offset += 2;

    // Sequence number (6 bytes / 48 bits)
    // Write as big-endian 48-bit value
    buffer.setUint16(offset, (sequenceNumber >> 32) & 0xFFFF);
    buffer.setUint32(offset + 2, sequenceNumber & 0xFFFFFFFF);
    offset += 6;

    // Length (2 bytes)
    buffer.setUint16(offset, fragment.length);
    offset += 2;

    // Fragment data
    final bytes = buffer.buffer.asUint8List();
    bytes.setRange(offset, offset + fragment.length, fragment);

    return bytes;
  }

  /// Parse record from bytes
  static DtlsRecord parse(Uint8List data) {
    if (data.length < dtlsRecordHeaderLength) {
      throw ArgumentError(
        'Invalid record: too short (${data.length} < $dtlsRecordHeaderLength)',
      );
    }

    final buffer = ByteData.sublistView(data);
    int offset = 0;

    // Content type (1 byte)
    final contentTypeValue = buffer.getUint8(offset);
    final contentType = ContentType.fromValue(contentTypeValue);
    if (contentType == null) {
      throw ArgumentError('Invalid content type: $contentTypeValue');
    }
    offset += 1;

    // Version (2 bytes)
    final major = buffer.getUint8(offset);
    final minor = buffer.getUint8(offset + 1);
    final version = ProtocolVersion(major, minor);
    offset += 2;

    // Epoch (2 bytes)
    final epoch = buffer.getUint16(offset);
    offset += 2;

    // Sequence number (6 bytes / 48 bits)
    final seqHigh = buffer.getUint16(offset);
    final seqLow = buffer.getUint32(offset + 2);
    final sequenceNumber = (seqHigh << 32) | seqLow;
    offset += 6;

    // Length (2 bytes)
    final length = buffer.getUint16(offset);
    offset += 2;

    // Validate length
    if (data.length < offset + length) {
      throw ArgumentError(
        'Invalid record: fragment length mismatch '
        '(expected ${offset + length}, got ${data.length})',
      );
    }

    if (length > dtlsMaxRecordLength) {
      throw ArgumentError(
        'Invalid record: fragment too large ($length > $dtlsMaxRecordLength)',
      );
    }

    // Fragment data
    final fragment = Uint8List.fromList(
      data.sublist(offset, offset + length),
    );

    return DtlsRecord(
      contentType: contentType,
      version: version,
      epoch: epoch,
      sequenceNumber: sequenceNumber,
      fragment: fragment,
    );
  }

  /// Parse multiple records from a datagram
  static List<DtlsRecord> parseMultiple(Uint8List data) {
    final records = <DtlsRecord>[];
    int offset = 0;

    while (offset < data.length) {
      if (data.length - offset < dtlsRecordHeaderLength) {
        // Not enough data for another record
        break;
      }

      // Peek at the length
      final lengthOffset = offset + 11; // After type, version, epoch, seq
      final buffer = ByteData.sublistView(data, lengthOffset);
      final length = buffer.getUint16(0);

      final recordEnd = offset + dtlsRecordHeaderLength + length;
      if (recordEnd > data.length) {
        // Incomplete record
        break;
      }

      try {
        final recordData = data.sublist(offset, recordEnd);
        final record = DtlsRecord.parse(recordData);
        records.add(record);
        offset = recordEnd;
      } catch (e) {
        // Failed to parse record, skip
        break;
      }
    }

    return records;
  }

  @override
  String toString() {
    return 'DtlsRecord('
        'type: $contentType, '
        'version: $version, '
        'epoch: $epoch, '
        'seq: $sequenceNumber, '
        'length: ${fragment.length}'
        ')';
  }
}
