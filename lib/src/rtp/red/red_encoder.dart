/// RED Encoder for creating redundant audio packets
/// RFC 2198: RTP Payload for Redundant Audio Data
library;

import 'dart:typed_data';

import 'red_packet.dart';

/// Maximum value for 14-bit timestamp offset
const int _max14Uint = (1 << 14) - 1; // 16383

/// Payload to be encoded with RED
class RedPayload {
  /// The payload data
  final Uint8List block;

  /// RTP timestamp
  final int timestamp;

  /// Payload type
  final int blockPT;

  RedPayload({
    required this.block,
    required this.timestamp,
    required this.blockPT,
  });
}

/// RED encoder that adds redundancy to audio packets
///
/// The encoder maintains a cache of recent payloads and includes
/// previous payloads in each RED packet for loss recovery.
class RedEncoder {
  /// Cache of recent payloads
  final List<RedPayload> _cache = [];

  /// Maximum cache size
  final int cacheSize;

  /// Number of previous payloads to include as redundancy
  int _distance;

  /// Create a RED encoder
  ///
  /// [distance] - Number of previous packets to include (default 1)
  /// [cacheSize] - Maximum cache size (default 10)
  RedEncoder({
    int distance = 1,
    this.cacheSize = 10,
  }) : _distance = distance;

  /// Get the current redundancy distance
  int get distance => _distance;

  /// Set the redundancy distance
  set distance(int value) {
    if (value < 0) {
      throw ArgumentError('Distance must be non-negative');
    }
    _distance = value;
  }

  /// Add a payload to the encoder cache
  void push(RedPayload payload) {
    _cache.add(payload);
    if (_cache.length > cacheSize) {
      _cache.removeAt(0);
    }
  }

  /// Build a RED packet from the current cache
  ///
  /// Returns a RED packet containing:
  /// - Up to [distance] previous payloads as redundant blocks
  /// - The current (most recent) payload as the primary block
  RedPacket build() {
    final red = RedPacket();

    // Get the payloads to include (up to distance+1 from cache)
    final redundantPayloads = _cache.length > _distance + 1
        ? _cache.sublist(_cache.length - (_distance + 1))
        : List<RedPayload>.from(_cache);

    if (redundantPayloads.isEmpty) {
      return red;
    }

    // The primary payload is the last one
    final primaryPayload = redundantPayloads.removeLast();

    // Add redundant blocks
    for (final redundant in redundantPayloads) {
      // Calculate timestamp offset from primary
      final timestampOffset =
          _uint32Add(primaryPayload.timestamp, -redundant.timestamp);

      // Skip if offset is too large for 14 bits
      if (timestampOffset > _max14Uint) {
        continue;
      }

      red.blocks.add(RedBlock(
        block: redundant.block,
        blockPT: redundant.blockPT,
        timestampOffset: timestampOffset,
      ));
    }

    // Add primary block (no timestamp offset)
    red.blocks.add(RedBlock(
      block: primaryPayload.block,
      blockPT: primaryPayload.blockPT,
    ));

    return red;
  }

  /// Clear the encoder cache
  void clear() {
    _cache.clear();
  }

  /// Get the number of payloads in the cache
  int get cacheLength => _cache.length;
}

/// Add two 32-bit unsigned integers with wrapping
int _uint32Add(int a, int b) {
  return (a + b) & 0xFFFFFFFF;
}
