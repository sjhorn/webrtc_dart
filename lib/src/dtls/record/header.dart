import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/record/const.dart';

/// DTLS plaintext record header (13 bytes)
/// Structure:
/// - contentType (1 byte)
/// - protocolVersion (2 bytes: major, minor)
/// - epoch (2 bytes)
/// - sequenceNumber (6 bytes - 48-bit integer)
/// - contentLen (2 bytes)
class RecordHeader {
  final int contentType;
  final ProtocolVersion protocolVersion;
  final int epoch;
  final int sequenceNumber; // 48-bit unsigned integer
  final int contentLen;

  const RecordHeader({
    required this.contentType,
    required this.protocolVersion,
    required this.epoch,
    required this.sequenceNumber,
    required this.contentLen,
  });

  /// Parse record header from bytes
  factory RecordHeader.deserialize(Uint8List data) {
    if (data.length < dtlsRecordHeaderLength) {
      throw ArgumentError(
        'Invalid DTLS record header: expected at least $dtlsRecordHeaderLength bytes, got ${data.length}',
      );
    }

    final buffer = ByteData.sublistView(data);

    final contentType = buffer.getUint8(0);
    final major = buffer.getUint8(1);
    final minor = buffer.getUint8(2);
    final epoch = buffer.getUint16(3);

    // Read 48-bit sequence number (6 bytes)
    // Split into high 16 bits and low 32 bits
    final seqHigh = buffer.getUint16(5);
    final seqLow = buffer.getUint32(7);
    final sequenceNumber = (seqHigh << 32) | seqLow;

    final contentLen = buffer.getUint16(11);

    return RecordHeader(
      contentType: contentType,
      protocolVersion: ProtocolVersion(major, minor),
      epoch: epoch,
      sequenceNumber: sequenceNumber,
      contentLen: contentLen,
    );
  }

  /// Serialize record header to bytes
  Uint8List serialize() {
    final buffer = ByteData(dtlsRecordHeaderLength);

    buffer.setUint8(0, contentType);
    buffer.setUint8(1, protocolVersion.major);
    buffer.setUint8(2, protocolVersion.minor);
    buffer.setUint16(3, epoch);

    // Write 48-bit sequence number (6 bytes)
    // Split into high 16 bits and low 32 bits
    final seqHigh = (sequenceNumber >> 32) & 0xFFFF;
    final seqLow = sequenceNumber & 0xFFFFFFFF;
    buffer.setUint16(5, seqHigh);
    buffer.setUint32(7, seqLow);

    buffer.setUint16(11, contentLen);

    return buffer.buffer.asUint8List();
  }

  @override
  String toString() {
    return 'RecordHeader(type=$contentType, version=${protocolVersion.major}.${protocolVersion.minor}, '
        'epoch=$epoch, seq=$sequenceNumber, len=$contentLen)';
  }

  @override
  bool operator ==(Object other) =>
      other is RecordHeader &&
      contentType == other.contentType &&
      protocolVersion == other.protocolVersion &&
      epoch == other.epoch &&
      sequenceNumber == other.sequenceNumber &&
      contentLen == other.contentLen;

  @override
  int get hashCode => Object.hash(
        contentType,
        protocolVersion,
        epoch,
        sequenceNumber,
        contentLen,
      );
}

/// MAC header for AEAD additional authenticated data
/// Used in encryption/decryption of DTLS records
/// Structure (11 bytes):
/// - epoch (2 bytes)
/// - sequenceNumber (6 bytes)
/// - contentType (1 byte)
/// - protocolVersion (2 bytes)
/// - contentLen (2 bytes)
class MACHeader {
  final int epoch;
  final int sequenceNumber; // 48-bit unsigned integer
  final int contentType;
  final ProtocolVersion protocolVersion;
  final int contentLen;

  const MACHeader({
    required this.epoch,
    required this.sequenceNumber,
    required this.contentType,
    required this.protocolVersion,
    required this.contentLen,
  });

  /// Create MAC header from record header
  factory MACHeader.fromRecordHeader(RecordHeader header) {
    return MACHeader(
      epoch: header.epoch,
      sequenceNumber: header.sequenceNumber,
      contentType: header.contentType,
      protocolVersion: header.protocolVersion,
      contentLen: header.contentLen,
    );
  }

  /// Serialize MAC header for use in AEAD additional data
  Uint8List serialize() {
    final buffer = ByteData(11); // 2 + 6 + 1 + 2 = 11 bytes

    buffer.setUint16(0, epoch);

    // Write 48-bit sequence number (6 bytes)
    final seqHigh = (sequenceNumber >> 32) & 0xFFFF;
    final seqLow = sequenceNumber & 0xFFFFFFFF;
    buffer.setUint16(2, seqHigh);
    buffer.setUint32(4, seqLow);

    buffer.setUint8(8, contentType);
    buffer.setUint8(9, protocolVersion.major);
    buffer.setUint8(10, protocolVersion.minor);

    // Note: contentLen is intentionally omitted in the serialized form
    // It's part of the struct but not transmitted in the MAC header

    return buffer.buffer.asUint8List();
  }

  @override
  String toString() {
    return 'MACHeader(epoch=$epoch, seq=$sequenceNumber, type=$contentType, '
        'version=${protocolVersion.major}.${protocolVersion.minor}, len=$contentLen)';
  }

  @override
  bool operator ==(Object other) =>
      other is MACHeader &&
      epoch == other.epoch &&
      sequenceNumber == other.sequenceNumber &&
      contentType == other.contentType &&
      protocolVersion == other.protocolVersion &&
      contentLen == other.contentLen;

  @override
  int get hashCode => Object.hash(
        epoch,
        sequenceNumber,
        contentType,
        protocolVersion,
        contentLen,
      );
}
