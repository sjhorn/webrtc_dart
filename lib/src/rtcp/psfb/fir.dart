import 'dart:typed_data';

/// FIR Entry
/// Represents a single FIR request for a specific SSRC
class FirEntry {
  /// Media stream SSRC
  final int ssrc;

  /// 8-bit FIR sequence number (increments with each new FIR request)
  final int sequenceNumber;

  const FirEntry({
    required this.ssrc,
    required this.sequenceNumber,
  }) : assert(sequenceNumber >= 0 && sequenceNumber <= 255,
            'Sequence number must be 8-bit (0-255)');

  @override
  String toString() {
    return 'FirEntry(ssrc: 0x${ssrc.toRadixString(16)}, seq: $sequenceNumber)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FirEntry &&
          runtimeType == other.runtimeType &&
          ssrc == other.ssrc &&
          sequenceNumber == other.sequenceNumber;

  @override
  int get hashCode => Object.hash(ssrc, sequenceNumber);
}

/// Full Intra Request (FIR)
/// RFC 5104 Section 4.3.1
///
/// Codec Control Message used to request a full intra (keyframe) refresh
/// for one or more media streams. More specific than PLI.
///
/// FIR includes sequence numbers to track requests and can target
/// multiple SSRCs in a single message.
class FullIntraRequest {
  /// FMT (Feedback Message Type) value for FIR in PSFB packets
  static const int fmt = 4;

  /// SSRC of the FIR sender
  final int senderSsrc;

  /// SSRC of the primary media stream (can be 0)
  final int mediaSsrc;

  /// List of FIR entries (one per media stream being requested)
  final List<FirEntry> entries;

  const FullIntraRequest({
    required this.senderSsrc,
    required this.mediaSsrc,
    this.entries = const [],
  });

  /// Calculate packet length in 32-bit words
  /// Length = (header + all entries) / 4 - 1
  int get length {
    final bytes = serialize().length;
    return (bytes ~/ 4) - 1;
  }

  /// Serialize FIR to bytes
  ///
  /// Format:
  ///  0                   1                   2                   3
  ///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  /// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  /// |                    Sender SSRC (32 bits)                      |
  /// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  /// |                     Media SSRC (32 bits)                      |
  /// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  /// |                       SSRC (32 bits)                          |
  /// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  /// | Seq nr.       |    Reserved (0)              ...              |
  /// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  /// ...                     (repeated for each entry)
  ///
  /// Each entry is 8 bytes: SSRC (4 bytes) + SeqNum (1 byte) + Reserved (3 bytes)
  Uint8List serialize() {
    // Header: 8 bytes (sender SSRC + media SSRC)
    // Each entry: 8 bytes
    final totalSize = 8 + (entries.length * 8);
    final buffer = ByteData(totalSize);

    // Write header
    buffer.setUint32(0, senderSsrc);
    buffer.setUint32(4, mediaSsrc);

    // Write each FIR entry
    for (var i = 0; i < entries.length; i++) {
      final offset = 8 + (i * 8);
      final entry = entries[i];
      buffer.setUint32(offset, entry.ssrc);
      buffer.setUint8(offset + 4, entry.sequenceNumber);
      // Bytes offset+5, offset+6, offset+7 are reserved (zeros)
    }

    return buffer.buffer.asUint8List();
  }

  /// Deserialize FIR from bytes
  static FullIntraRequest deserialize(Uint8List data) {
    if (data.length < 8) {
      throw ArgumentError('FIR data too short: ${data.length} bytes, expected at least 8');
    }

    if ((data.length - 8) % 8 != 0) {
      throw ArgumentError(
          'FIR data invalid: ${data.length} bytes, entries must be 8-byte aligned');
    }

    final buffer = ByteData.view(data.buffer, data.offsetInBytes);

    // Read header
    final senderSsrc = buffer.getUint32(0);
    final mediaSsrc = buffer.getUint32(4);

    // Read FIR entries
    final entries = <FirEntry>[];
    for (var i = 8; i < data.length; i += 8) {
      final ssrc = buffer.getUint32(i);
      final sequenceNumber = buffer.getUint8(i + 4);
      entries.add(FirEntry(ssrc: ssrc, sequenceNumber: sequenceNumber));
    }

    return FullIntraRequest(
      senderSsrc: senderSsrc,
      mediaSsrc: mediaSsrc,
      entries: entries,
    );
  }

  @override
  String toString() {
    return 'FullIntraRequest(sender: 0x${senderSsrc.toRadixString(16)}, '
        'media: 0x${mediaSsrc.toRadixString(16)}, entries: ${entries.length})';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FullIntraRequest &&
          runtimeType == other.runtimeType &&
          senderSsrc == other.senderSsrc &&
          mediaSsrc == other.mediaSsrc &&
          _listEquals(entries, other.entries);

  @override
  int get hashCode => Object.hash(senderSsrc, mediaSsrc, Object.hashAll(entries));

  /// Helper to compare lists
  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
