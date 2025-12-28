import 'dart:convert';
import 'dart:typed_data';

import '../srtp/rtcp_packet.dart';

/// RTCP BYE (Goodbye) Packet
/// RFC 3550 Section 6.6
///
/// BYE packet format:
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |V=2|P|    SC   |   PT=BYE=203  |             length            |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                           SSRC/CSRC                           |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// :                              ...                              :
/// +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
/// |     length    |               reason for leaving            ...
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
///
/// The BYE packet indicates that one or more sources are no longer active.
/// SC (source count) indicates the number of SSRC/CSRC identifiers included.
/// An optional reason string may follow, prefixed by an 8-bit length.
class RtcpBye {
  /// List of SSRC/CSRC identifiers that are leaving
  final List<int> ssrcs;

  /// Optional reason for leaving (human-readable string)
  final String? reason;

  const RtcpBye({
    required this.ssrcs,
    this.reason,
  });

  /// Create a BYE packet for a single source
  factory RtcpBye.single(int ssrc, {String? reason}) {
    return RtcpBye(ssrcs: [ssrc], reason: reason);
  }

  /// Convert to RTCP packet
  RtcpPacket toPacket() {
    // Build payload: SSRCs (after the first one) + optional reason
    // Note: First SSRC goes in the header's SSRC field
    // Remaining SSRCs go in payload

    final payloadParts = <int>[];

    // Add additional SSRCs (index 1+) to payload
    for (var i = 1; i < ssrcs.length; i++) {
      final ssrc = ssrcs[i];
      payloadParts.add((ssrc >> 24) & 0xFF);
      payloadParts.add((ssrc >> 16) & 0xFF);
      payloadParts.add((ssrc >> 8) & 0xFF);
      payloadParts.add(ssrc & 0xFF);
    }

    // Add optional reason string
    if (reason != null && reason!.isNotEmpty) {
      final reasonBytes = utf8.encode(reason!);
      // Limit to 255 bytes per RFC
      final truncatedLength =
          reasonBytes.length > 255 ? 255 : reasonBytes.length;
      payloadParts.add(truncatedLength);
      payloadParts.addAll(reasonBytes.take(truncatedLength));
    }

    // Calculate padding to 4-byte boundary
    // Header is 4 bytes (V/P/SC + PT + length), SSRC is 4 bytes, then payload
    // Total content = 8 + payload.length
    final contentSize = 8 + payloadParts.length;
    final paddingNeeded = (4 - (contentSize % 4)) % 4;
    final needsPadding = paddingNeeded > 0;

    final payload = Uint8List.fromList(payloadParts);

    // Length in 32-bit words minus 1
    // Total bytes = 8 (header + SSRC) + payload + padding
    final totalBytes = 8 + payload.length + (needsPadding ? paddingNeeded : 0);
    final length = (totalBytes ~/ 4) - 1;

    return RtcpPacket(
      version: 2,
      padding: needsPadding,
      reportCount: ssrcs.length, // SC = source count
      packetType: RtcpPacketType.goodbye,
      length: length,
      ssrc: ssrcs.isNotEmpty ? ssrcs[0] : 0,
      payload: payload,
      paddingLength: needsPadding ? paddingNeeded : 0,
    );
  }

  /// Parse from RTCP packet
  factory RtcpBye.fromPacket(RtcpPacket packet) {
    if (packet.packetType != RtcpPacketType.goodbye) {
      throw FormatException(
          'Expected BYE packet type (203), got ${packet.packetType.value}');
    }

    final sourceCount = packet.reportCount;
    final ssrcs = <int>[];

    // First SSRC is in the header
    if (sourceCount > 0) {
      ssrcs.add(packet.ssrc);
    }

    // Parse additional SSRCs from payload
    final payload = packet.payload;
    var offset = 0;

    for (var i = 1; i < sourceCount; i++) {
      if (offset + 4 > payload.length) {
        throw FormatException('BYE packet truncated: missing SSRC $i');
      }
      final buffer = ByteData.sublistView(payload, offset, offset + 4);
      ssrcs.add(buffer.getUint32(0));
      offset += 4;
    }

    // Parse optional reason string
    String? reason;
    if (offset < payload.length) {
      final reasonLength = payload[offset];
      offset++;
      if (offset + reasonLength <= payload.length) {
        final reasonBytes = payload.sublist(offset, offset + reasonLength);
        reason = utf8.decode(reasonBytes, allowMalformed: true);
      }
    }

    return RtcpBye(ssrcs: ssrcs, reason: reason);
  }

  /// Serialize directly to bytes
  Uint8List toBytes() {
    return toPacket().serialize();
  }

  /// Parse from raw bytes
  factory RtcpBye.fromBytes(Uint8List data) {
    final packet = RtcpPacket.parse(data);
    return RtcpBye.fromPacket(packet);
  }

  @override
  String toString() {
    final ssrcHex = ssrcs.map((s) => '0x${s.toRadixString(16)}').toList();
    final reasonPart = reason != null ? ', reason="$reason"' : '';
    return 'RtcpBye(ssrcs=$ssrcHex$reasonPart)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RtcpBye) return false;
    if (ssrcs.length != other.ssrcs.length) return false;
    for (var i = 0; i < ssrcs.length; i++) {
      if (ssrcs[i] != other.ssrcs[i]) return false;
    }
    return reason == other.reason;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(ssrcs), reason);
}
