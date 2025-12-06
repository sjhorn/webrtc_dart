/// RED (Redundant Encoding) packet implementation
/// RFC 2198: RTP Payload for Redundant Audio Data
///
/// RED Header format:
///
/// For blocks with follow-on headers (F=1):
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |F|   block PT  |  timestamp offset         |   block length    |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
///
/// For final block (F=0):
///  0 1 2 3 4 5 6 7
/// +-+-+-+-+-+-+-+-+
/// |0|   Block PT  |
/// +-+-+-+-+-+-+-+-+
library;

import 'dart:typed_data';

/// A single block within a RED packet
class RedBlock {
  /// The payload data
  final Uint8List block;

  /// Payload type of this block
  final int blockPT;

  /// Timestamp offset from primary (14 bits, only for redundant blocks)
  final int? timestampOffset;

  RedBlock({
    required this.block,
    required this.blockPT,
    this.timestampOffset,
  });

  /// Whether this is a redundant block (has timestamp offset)
  bool get isRedundant => timestampOffset != null;

  @override
  String toString() {
    return 'RedBlock(pt=$blockPT, size=${block.length}, offset=$timestampOffset)';
  }
}

/// RED header field
class RedHeaderField {
  /// F-bit: 1 if more headers follow, 0 for final header
  final int fBit;

  /// Block payload type (7 bits)
  final int blockPT;

  /// Timestamp offset (14 bits, only present when fBit=1)
  final int? timestampOffset;

  /// Block length (10 bits, only present when fBit=1)
  final int? blockLength;

  RedHeaderField({
    required this.fBit,
    required this.blockPT,
    this.timestampOffset,
    this.blockLength,
  });
}

/// RED header containing multiple header fields
class RedHeader {
  final List<RedHeaderField> fields = [];

  RedHeader();

  /// Deserialize RED header from buffer
  /// Returns the header and the number of bytes consumed
  static (RedHeader, int) deserialize(Uint8List buf) {
    final header = RedHeader();
    var offset = 0;

    while (true) {
      if (offset >= buf.length) break;

      final firstByte = buf[offset];
      final fBit = (firstByte >> 7) & 0x01;
      final blockPT = firstByte & 0x7F;

      offset++;

      if (fBit == 0) {
        // Final header - only 1 byte
        header.fields.add(RedHeaderField(
          fBit: fBit,
          blockPT: blockPT,
        ));
        break;
      }

      // Extended header - 4 bytes total
      if (offset + 3 > buf.length) break;

      // Read 14-bit timestamp offset and 10-bit block length
      // Bits: [F(1)][blockPT(7)][timestampOffset(14)][blockLength(10)]
      final byte2 = buf[offset];
      final byte3 = buf[offset + 1];
      final byte4 = buf[offset + 2];

      final timestampOffset = ((byte2 << 6) | (byte3 >> 2)) & 0x3FFF;
      final blockLength = ((byte3 & 0x03) << 8) | byte4;

      header.fields.add(RedHeaderField(
        fBit: fBit,
        blockPT: blockPT,
        timestampOffset: timestampOffset,
        blockLength: blockLength,
      ));

      offset += 3;
    }

    return (header, offset);
  }

  /// Serialize RED header to buffer
  Uint8List serialize() {
    final chunks = <Uint8List>[];

    for (final field in fields) {
      if (field.timestampOffset != null && field.blockLength != null) {
        // Extended header - 4 bytes
        final buf = Uint8List(4);
        buf[0] = (1 << 7) | (field.blockPT & 0x7F);
        buf[1] = (field.timestampOffset! >> 6) & 0xFF;
        buf[2] = ((field.timestampOffset! & 0x3F) << 2) |
            ((field.blockLength! >> 8) & 0x03);
        buf[3] = field.blockLength! & 0xFF;
        chunks.add(buf);
      } else {
        // Final header - 1 byte
        final buf = Uint8List(1);
        buf[0] = field.blockPT & 0x7F; // F=0
        chunks.add(buf);
      }
    }

    // Concatenate all chunks
    final totalLength = chunks.fold<int>(0, (sum, c) => sum + c.length);
    final result = Uint8List(totalLength);
    var offset = 0;
    for (final chunk in chunks) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    return result;
  }
}

/// RED (Redundant Encoding) packet
/// Contains multiple blocks of audio data for redundancy
class RedPacket {
  /// The RED header
  RedHeader header = RedHeader();

  /// List of blocks (redundant + primary)
  final List<RedBlock> blocks = [];

  RedPacket();

  /// Deserialize RED packet from RTP payload
  static RedPacket deserialize(Uint8List buf) {
    final red = RedPacket();

    // Parse header
    final (header, headerOffset) = RedHeader.deserialize(buf);
    red.header = header;

    // Parse blocks based on header fields
    var offset = headerOffset;
    for (var i = 0; i < header.fields.length; i++) {
      final field = header.fields[i];

      if (field.blockLength != null && field.timestampOffset != null) {
        // Redundant block with known length
        final blockData = buf.sublist(offset, offset + field.blockLength!);
        red.blocks.add(RedBlock(
          block: blockData,
          blockPT: field.blockPT,
          timestampOffset: field.timestampOffset,
        ));
        offset += field.blockLength!;
      } else {
        // Primary block - rest of the data
        final blockData = buf.sublist(offset);
        red.blocks.add(RedBlock(
          block: blockData,
          blockPT: field.blockPT,
        ));
      }
    }

    return red;
  }

  /// Serialize RED packet to RTP payload
  Uint8List serialize() {
    // Build header from blocks
    header = RedHeader();

    for (final block in blocks) {
      if (block.timestampOffset != null) {
        header.fields.add(RedHeaderField(
          fBit: 1,
          blockPT: block.blockPT,
          blockLength: block.block.length,
          timestampOffset: block.timestampOffset,
        ));
      } else {
        header.fields.add(RedHeaderField(
          fBit: 0,
          blockPT: block.blockPT,
        ));
      }
    }

    // Serialize header
    final headerBytes = header.serialize();

    // Calculate total size
    var totalSize = headerBytes.length;
    for (final block in blocks) {
      totalSize += block.block.length;
    }

    // Build result
    final result = Uint8List(totalSize);
    result.setRange(0, headerBytes.length, headerBytes);

    var offset = headerBytes.length;
    for (final block in blocks) {
      result.setRange(offset, offset + block.block.length, block.block);
      offset += block.block.length;
    }

    return result;
  }

  /// Get the primary (non-redundant) block
  RedBlock? get primaryBlock {
    for (final block in blocks) {
      if (!block.isRedundant) {
        return block;
      }
    }
    return blocks.isNotEmpty ? blocks.last : null;
  }

  /// Get all redundant blocks
  List<RedBlock> get redundantBlocks {
    return blocks.where((b) => b.isRedundant).toList();
  }

  @override
  String toString() {
    return 'RedPacket(blocks=${blocks.length}, redundant=${redundantBlocks.length})';
  }
}
