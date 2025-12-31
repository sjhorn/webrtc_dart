import 'dart:typed_data';

import 'package:webrtc_dart/src/sctp/chunk.dart';

/// Compare 32-bit TSNs with wraparound (a > b)
bool uint32Gt(int a, int b) {
  return ((a - b) & 0xFFFFFFFF) < 0x80000000 && a != b;
}

/// Compare 32-bit TSNs with wraparound (a >= b)
bool uint32Gte(int a, int b) {
  return a == b || uint32Gt(a, b);
}

/// Compare 16-bit sequence numbers with wraparound (a > b)
bool uint16Gt(int a, int b) {
  return ((a - b) & 0xFFFF) < 0x8000 && a != b;
}

/// Inbound stream for fragment reassembly
/// Reference: werift-webrtc/packages/sctp/src/sctp.ts InboundStream class
///
/// Manages per-stream reassembly of fragmented DATA chunks.
/// Chunks are stored in TSN order and yielded as complete messages
/// when all fragments are received.
class InboundStream {
  /// Reassembly buffer - chunks waiting to be reassembled
  final List<SctpDataChunk> reassembly = [];

  /// Stream sequence number for ordered delivery
  int streamSequenceNumber = 0;

  /// Add a chunk to the reassembly buffer in TSN order
  void addChunk(SctpDataChunk chunk) {
    // Fast path: append if buffer is empty or chunk is newest
    if (reassembly.isEmpty || uint32Gt(chunk.tsn, reassembly.last.tsn)) {
      reassembly.add(chunk);
      return;
    }

    // Insert in TSN order
    for (var i = 0; i < reassembly.length; i++) {
      if (reassembly[i].tsn == chunk.tsn) {
        // Duplicate - already have this chunk
        return;
      }
      if (uint32Gt(reassembly[i].tsn, chunk.tsn)) {
        reassembly.insert(i, chunk);
        return;
      }
    }
  }

  /// Pop complete messages from the reassembly buffer
  /// Yields (streamId, userData, ppid) tuples for each complete message
  Iterable<(int streamId, Uint8List userData, int ppid)> popMessages() sync* {
    var pos = 0;
    int? startPos;
    int? expectedTsn;
    bool? ordered;

    while (pos < reassembly.length) {
      final chunk = reassembly[pos];

      if (startPos == null) {
        // Looking for a first fragment
        ordered = !chunk.unordered;

        if (!chunk.beginningFragment) {
          // Not a first fragment
          if (ordered) {
            // For ordered delivery, must wait for first fragment
            break;
          } else {
            // For unordered, skip and continue looking
            pos++;
            continue;
          }
        }

        // Check if we can deliver this ordered message yet
        if (ordered && uint16Gt(chunk.streamSeq, streamSequenceNumber)) {
          // Out of order - must wait
          break;
        }

        expectedTsn = chunk.tsn;
        startPos = pos;
      } else if (chunk.tsn != expectedTsn) {
        // TSN gap - missing chunk
        if (ordered!) {
          // For ordered delivery, must wait for missing chunk
          break;
        } else {
          // For unordered, reset and continue looking
          startPos = null;
          pos++;
          continue;
        }
      }

      if (chunk.endFragment) {
        // Found last fragment - reassemble complete message
        final chunks = reassembly.sublist(startPos, pos + 1);
        final userData = Uint8List.fromList(
          chunks.expand((c) => c.userData).toList(),
        );

        // Remove reassembled chunks from buffer
        reassembly.removeRange(startPos, pos + 1);

        // Update stream sequence number for ordered delivery
        if (ordered! && chunk.streamSeq == streamSequenceNumber) {
          streamSequenceNumber = (streamSequenceNumber + 1) & 0xFFFF;
        }

        // Reset position to check for more messages
        pos = startPos;

        yield (chunk.streamId, userData, chunk.ppid);
      } else {
        pos++;
      }

      // Advance expected TSN
      expectedTsn = (expectedTsn! + 1) & 0xFFFFFFFF;
    }
  }

  /// Prune chunks up to the given TSN (for forward TSN support)
  /// Returns the total size of pruned chunks
  int pruneChunks(int tsn) {
    var pos = -1;
    var size = 0;

    for (var i = 0; i < reassembly.length; i++) {
      final chunk = reassembly[i];
      if (uint32Gte(tsn, chunk.tsn)) {
        pos = i;
        size += chunk.userData.length;
      } else {
        break;
      }
    }

    if (pos >= 0) {
      reassembly.removeRange(0, pos + 1);
    }

    return size;
  }
}
