import 'dart:typed_data';
import '../srtp/rtcp_packet.dart';

/// Generic NACK (Negative Acknowledgement) Feedback
/// RFC 4585 - Extended RTP Profile for Real-time Transport Control Protocol (RTCP)
///
/// Generic NACK is used to request retransmission of lost RTP packets.
/// It efficiently encodes ranges of lost packets using PID (Packet ID)
/// and BLP (Bitmask of Lost Packets).
///
/// Generic NACK FCI (Feedback Control Information) Format:
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |            PID                |             BLP               |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
///
/// PID: 16-bit RTP sequence number of first lost packet
/// BLP: 16-bit bitmask of following lost packets (PID+1 through PID+16)
///      Bit 0 (LSB) = PID+1, Bit 15 (MSB) = PID+16
///      Set bit indicates lost packet

/// Generic NACK feedback message
class GenericNack {
  /// Feedback message type (FMT) for Generic NACK
  static const int fmt = 1;

  /// SSRC of packet sender (RTCP sender)
  final int senderSsrc;

  /// SSRC of media source being reported on
  final int mediaSourceSsrc;

  /// List of lost sequence numbers
  final List<int> lostSeqNumbers;

  GenericNack({
    required this.senderSsrc,
    required this.mediaSourceSsrc,
    required this.lostSeqNumbers,
  });

  /// Serialize Generic NACK to RTCP packet
  RtcpPacket toRtcpPacket() {
    final payload = serialize();

    // Calculate length in 32-bit words minus one
    // Header (8 bytes) + FCI payload
    final totalSize = 8 + payload.length;
    final length = (totalSize ~/ 4) - 1;

    return RtcpPacket(
      version: 2,
      padding: false,
      reportCount: fmt, // FMT field in transport feedback
      packetType: RtcpPacketType.transportFeedback,
      length: length,
      ssrc: senderSsrc,
      payload: payload,
    );
  }

  /// Serialize FCI (Feedback Control Information)
  /// Returns the payload after the RTCP header
  Uint8List serialize() {
    final parts = <Uint8List>[];

    // Add media source SSRC (4 bytes)
    final ssrcBytes = Uint8List(4);
    ByteData.sublistView(ssrcBytes).setUint32(0, mediaSourceSsrc);
    parts.add(ssrcBytes);

    // Encode lost sequence numbers as PID+BLP pairs
    if (lostSeqNumbers.isNotEmpty) {
      // Sort sequence numbers (handle wraparound)
      final sorted = List<int>.from(lostSeqNumbers)..sort(_compareSeqNum);

      int headPid = sorted[0];
      int blp = 0;

      for (var i = 1; i < sorted.length; i++) {
        final seqNum = sorted[i];
        final diff = _seqNumDiff(headPid, seqNum) - 1;

        if (diff >= 0 && diff < 16) {
          // Within BLP range, set bit
          blp |= 1 << diff;
        } else {
          // Outside range, write current PID+BLP and start new pair
          parts.add(_encodePidBlp(headPid, blp));
          headPid = seqNum;
          blp = 0;
        }
      }

      // Write final PID+BLP pair
      parts.add(_encodePidBlp(headPid, blp));
    }

    // Concatenate all parts
    final totalLength = parts.fold(0, (sum, part) => sum + part.length);
    final result = Uint8List(totalLength);
    var offset = 0;
    for (final part in parts) {
      result.setRange(offset, offset + part.length, part);
      offset += part.length;
    }

    return result;
  }

  /// Deserialize Generic NACK from RTCP packet payload
  static GenericNack deserialize(RtcpPacket packet) {
    if (packet.packetType != RtcpPacketType.transportFeedback) {
      throw FormatException('Not a transport feedback packet');
    }

    if (packet.reportCount != fmt) {
      throw FormatException('Not a Generic NACK (FMT=${packet.reportCount})');
    }

    final data = packet.payload;
    if (data.length < 4) {
      throw FormatException('NACK payload too short');
    }

    final buffer = ByteData.sublistView(data);
    final senderSsrc = packet.ssrc;
    final mediaSourceSsrc = buffer.getUint32(0);

    final lost = <int>[];
    var offset = 4;

    // Parse PID+BLP pairs
    while (offset + 4 <= data.length) {
      final pid = buffer.getUint16(offset);
      final blp = buffer.getUint16(offset + 2);
      offset += 4;

      // Add PID
      lost.add(pid);

      // Check each bit in BLP
      for (var i = 0; i < 16; i++) {
        if ((blp >> i) & 1 != 0) {
          lost.add((pid + i + 1) & 0xFFFF);
        }
      }
    }

    return GenericNack(
      senderSsrc: senderSsrc,
      mediaSourceSsrc: mediaSourceSsrc,
      lostSeqNumbers: lost,
    );
  }

  /// Encode PID+BLP pair
  Uint8List _encodePidBlp(int pid, int blp) {
    final bytes = Uint8List(4);
    final buffer = ByteData.sublistView(bytes);
    buffer.setUint16(0, pid);
    buffer.setUint16(2, blp);
    return bytes;
  }

  /// Calculate difference between sequence numbers (handles wraparound)
  int _seqNumDiff(int a, int b) {
    final diff = (b - a) & 0xFFFF;
    return diff < 0x8000 ? diff : diff - 0x10000;
  }

  /// Compare sequence numbers (handles wraparound)
  int _compareSeqNum(int a, int b) {
    final diff = _seqNumDiff(a, b);
    return diff.sign;
  }

  @override
  String toString() {
    return 'GenericNack(sender=$senderSsrc, mediaSource=$mediaSourceSsrc, lost=${lostSeqNumbers.length} packets)';
  }
}

/// Create a compound RTCP packet containing Generic NACK
RtcpCompoundPacket createNackPacket({
  required int senderSsrc,
  required int mediaSourceSsrc,
  required List<int> lostSeqNumbers,
}) {
  final nack = GenericNack(
    senderSsrc: senderSsrc,
    mediaSourceSsrc: mediaSourceSsrc,
    lostSeqNumbers: lostSeqNumbers,
  );

  return RtcpCompoundPacket([nack.toRtcpPacket()]);
}
