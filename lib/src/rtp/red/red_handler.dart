/// RED Handler for depacketizing redundant audio packets
/// RFC 2198: RTP Payload for Redundant Audio Data
library;

import '../../srtp/rtp_packet.dart';
import 'red_packet.dart';

/// RED handler for extracting packets from RED payloads
///
/// Handles depacketization of RED packets and duplicate detection
/// to avoid processing the same packet multiple times.
class RedHandler {
  /// Maximum number of sequence numbers to track for duplicate detection
  final int _bufferSize;

  /// Buffer of recently seen sequence numbers
  final List<int> _sequenceNumbers = [];

  /// Create a RED handler
  ///
  /// [bufferSize] - Number of sequence numbers to track (default 150)
  RedHandler({int bufferSize = 150}) : _bufferSize = bufferSize;

  /// Process a RED packet and extract individual RTP packets
  ///
  /// [red] - The parsed RED packet
  /// [basePacket] - The RTP packet containing the RED payload
  ///
  /// Returns a list of reconstructed RTP packets (deduplicated)
  List<RtpPacket> push(RedPacket red, RtpPacket basePacket) {
    final packets = <RtpPacket>[];
    final numBlocks = red.blocks.length;

    for (var i = 0; i < numBlocks; i++) {
      final block = red.blocks[i];

      // Calculate sequence number for this block
      // Redundant blocks have earlier sequence numbers
      final sequenceOffset = numBlocks - (i + 1);
      final sequenceNumber =
          _uint16Add(basePacket.sequenceNumber, -sequenceOffset);

      // Calculate timestamp
      int timestamp;
      if (block.timestampOffset != null) {
        // Redundant block - subtract offset from base timestamp
        timestamp = _uint32Add(basePacket.timestamp, -block.timestampOffset!);
      } else {
        // Primary block - use base timestamp
        timestamp = basePacket.timestamp;
      }

      // Create reconstructed packet
      final packet = RtpPacket(
        payloadType: block.blockPT,
        sequenceNumber: sequenceNumber,
        timestamp: timestamp,
        ssrc: basePacket.ssrc,
        marker: true,
        payload: block.block,
      );

      packets.add(packet);
    }

    // Filter out duplicates
    final filtered = <RtpPacket>[];
    for (final packet in packets) {
      if (_sequenceNumbers.contains(packet.sequenceNumber)) {
        // Duplicate - skip
        continue;
      }

      // Add to tracking buffer
      if (_sequenceNumbers.length >= _bufferSize) {
        _sequenceNumbers.removeAt(0);
      }
      _sequenceNumbers.add(packet.sequenceNumber);

      filtered.add(packet);
    }

    return filtered;
  }

  /// Clear the duplicate detection buffer
  void clear() {
    _sequenceNumbers.clear();
  }

  /// Get the number of sequence numbers being tracked
  int get trackedCount => _sequenceNumbers.length;
}

/// Add two 16-bit unsigned integers with wrapping
int _uint16Add(int a, int b) {
  return (a + b) & 0xFFFF;
}

/// Add two 32-bit unsigned integers with wrapping
int _uint32Add(int a, int b) {
  return (a + b) & 0xFFFFFFFF;
}
