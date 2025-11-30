import 'dart:typed_data';
import 'package:webrtc_dart/src/sctp/const.dart';
import 'package:webrtc_dart/src/sctp/chunk.dart';

/// SCTP Packet
/// RFC 4960 Section 3
///
/// SCTP Packet Format:
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |     Source Port Number        |     Destination Port Number   |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                      Verification Tag                         |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                           Checksum                            |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                            Chunk #1                           |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                            Chunk #2                           |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                            Chunk #N                           |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
class SctpPacket {
  /// Source port
  final int sourcePort;

  /// Destination port
  final int destinationPort;

  /// Verification tag
  final int verificationTag;

  /// Checksum (CRC32c)
  int checksum;

  /// Chunks
  final List<SctpChunk> chunks;

  SctpPacket({
    required this.sourcePort,
    required this.destinationPort,
    required this.verificationTag,
    this.checksum = 0,
    required this.chunks,
  });

  /// Serialize SCTP packet to bytes
  Uint8List serialize() {
    // Calculate total size
    var size = SctpConstants.headerSize;
    final chunkData = <Uint8List>[];

    for (final chunk in chunks) {
      final data = chunk.serialize();
      chunkData.add(data);
      size += data.length;
    }

    final result = Uint8List(size);
    final buffer = ByteData.sublistView(result);

    // Write header
    buffer.setUint16(0, sourcePort);
    buffer.setUint16(2, destinationPort);
    buffer.setUint32(4, verificationTag);

    // Write chunks
    var offset = SctpConstants.headerSize;
    for (final data in chunkData) {
      result.setRange(offset, offset + data.length, data);
      offset += data.length;
    }

    // Calculate and write checksum (little-endian per RFC 4960)
    checksum = _calculateChecksum(result);
    buffer.setUint32(8, checksum, Endian.little);

    return result;
  }

  /// Parse SCTP packet from bytes
  static SctpPacket parse(Uint8List data) {
    if (data.length < SctpConstants.headerSize) {
      throw FormatException('SCTP packet too short');
    }

    final buffer = ByteData.sublistView(data);

    final sourcePort = buffer.getUint16(0);
    final destinationPort = buffer.getUint16(2);
    final verificationTag = buffer.getUint32(4);
    final checksum = buffer.getUint32(8, Endian.little); // Little-endian per RFC 4960

    // Verify checksum
    final calculatedChecksum = _calculateChecksum(data);
    if (calculatedChecksum != checksum) {
      throw FormatException('SCTP checksum mismatch');
    }

    // Parse chunks
    final chunks = <SctpChunk>[];
    var offset = SctpConstants.headerSize;

    while (offset < data.length) {
      if (offset + SctpConstants.chunkHeaderSize > data.length) {
        break; // Not enough data for chunk header
      }

      // Read chunk length from header
      final buffer = ByteData.sublistView(data);
      final chunkLength = buffer.getUint16(offset + 2);

      // Make sure we have enough data for this chunk
      if (offset + chunkLength > data.length) {
        break; // Not enough data for this chunk
      }

      final chunk = SctpChunk.parse(data.sublist(offset));
      chunks.add(chunk);

      // Move to next chunk (with padding)
      final paddedLength = (chunkLength + 3) & ~3; // Round up to 4-byte boundary
      offset += paddedLength;
    }

    return SctpPacket(
      sourcePort: sourcePort,
      destinationPort: destinationPort,
      verificationTag: verificationTag,
      checksum: checksum,
      chunks: chunks,
    );
  }

  /// Calculate CRC32c checksum for SCTP packet
  /// RFC 4960 Appendix B
  static int _calculateChecksum(Uint8List data) {
    // Create a copy with checksum field zeroed
    final copy = Uint8List.fromList(data);
    final buffer = ByteData.sublistView(copy);
    buffer.setUint32(8, 0);

    return _crc32c(copy);
  }

  /// CRC32c calculation (Castagnoli polynomial, reflected)
  /// RFC 4960 Appendix B
  static int _crc32c(Uint8List data) {
    // Reflected Castagnoli polynomial
    const polynomial = 0x82F63B78;
    var crc = 0xFFFFFFFF;

    for (final byte in data) {
      crc ^= byte;
      for (var i = 0; i < 8; i++) {
        if (crc & 1 != 0) {
          crc = (crc >> 1) ^ polynomial;
        } else {
          crc = crc >> 1;
        }
      }
    }

    return crc ^ 0xFFFFFFFF;
  }

  /// Get chunks of a specific type
  List<T> getChunksOfType<T extends SctpChunk>() {
    return chunks.whereType<T>().toList();
  }

  /// Check if packet has chunk of specific type
  bool hasChunkType<T extends SctpChunk>() {
    return chunks.any((chunk) => chunk is T);
  }

  @override
  String toString() {
    return 'SctpPacket(src=$sourcePort, dst=$destinationPort, vtag=0x${verificationTag.toRadixString(16)}, chunks=${chunks.length})';
  }
}
