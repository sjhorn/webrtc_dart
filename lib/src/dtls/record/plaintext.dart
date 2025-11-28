import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/record/const.dart';
import 'package:webrtc_dart/src/dtls/record/header.dart';

/// DTLS plaintext record
/// Complete record with header and fragment data
class DtlsPlaintext {
  final RecordHeader header;
  final Uint8List fragment;

  const DtlsPlaintext({
    required this.header,
    required this.fragment,
  });

  /// Parse DTLS plaintext record from bytes
  factory DtlsPlaintext.deserialize(Uint8List data) {
    if (data.length < dtlsRecordHeaderLength) {
      throw ArgumentError(
        'Invalid DTLS record: buffer too short (${data.length} < $dtlsRecordHeaderLength)',
      );
    }

    // Parse header
    final header = RecordHeader.deserialize(data);

    // Validate fragment length
    if (data.length < dtlsRecordHeaderLength + header.contentLen) {
      throw ArgumentError(
        'Invalid DTLS record: fragment length (${header.contentLen}) '
        'exceeds available data (${data.length - dtlsRecordHeaderLength})',
      );
    }

    // Extract fragment
    final fragment = Uint8List.sublistView(
      data,
      dtlsRecordHeaderLength,
      dtlsRecordHeaderLength + header.contentLen,
    );

    return DtlsPlaintext(
      header: header,
      fragment: fragment,
    );
  }

  /// Serialize DTLS plaintext record to bytes
  Uint8List serialize() {
    final totalLength = dtlsRecordHeaderLength + fragment.length;
    final result = Uint8List(totalLength);

    // Update header with actual fragment length
    final updatedHeader = RecordHeader(
      contentType: header.contentType,
      protocolVersion: header.protocolVersion,
      epoch: header.epoch,
      sequenceNumber: header.sequenceNumber,
      contentLen: fragment.length,
    );

    // Write header
    final headerBytes = updatedHeader.serialize();
    result.setRange(0, dtlsRecordHeaderLength, headerBytes);

    // Write fragment
    result.setRange(dtlsRecordHeaderLength, totalLength, fragment);

    return result;
  }

  /// Compute MAC header for this record (used in encryption)
  MACHeader computeMACHeader() {
    return MACHeader.fromRecordHeader(header);
  }

  /// Get content type as enum
  ContentType? get contentType => ContentType.fromValue(header.contentType);

  /// Get protocol version
  ProtocolVersion get protocolVersion => header.protocolVersion;

  /// Get epoch
  int get epoch => header.epoch;

  /// Get sequence number
  int get sequenceNumber => header.sequenceNumber;

  @override
  String toString() {
    return 'DtlsPlaintext(header=$header, fragmentLen=${fragment.length})';
  }

  @override
  bool operator ==(Object other) =>
      other is DtlsPlaintext &&
      header == other.header &&
      _bytesEqual(fragment, other.fragment);

  @override
  int get hashCode => Object.hash(header, Object.hashAll(fragment));

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
