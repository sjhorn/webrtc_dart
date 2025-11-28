import 'dart:typed_data';

/// RTCP Packet Types
/// RFC 3550 Section 6.4
enum RtcpPacketType {
  senderReport(200),
  receiverReport(201),
  sourceDescription(202),
  goodbye(203),
  applicationDefined(204),
  transportFeedback(205),
  payloadFeedback(206);

  final int value;
  const RtcpPacketType(this.value);

  static RtcpPacketType? fromValue(int value) {
    for (final type in values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// RTCP Packet
/// RFC 3550 - RTP Control Protocol (RTCP)
///
/// RTCP Header Format:
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |V=2|P|    RC   |   PT          |             length            |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                         SSRC/CSRC                             |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                          payload...                           |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
class RtcpPacket {
  /// RTCP version (always 2)
  final int version;

  /// Padding flag
  final bool padding;

  /// Report count (or subtype for some packet types)
  final int reportCount;

  /// Packet type
  final RtcpPacketType packetType;

  /// Length in 32-bit words minus one
  final int length;

  /// SSRC of sender or other identifier
  final int ssrc;

  /// Payload data
  final Uint8List payload;

  /// Padding length (if padding flag is set)
  final int paddingLength;

  const RtcpPacket({
    this.version = 2,
    this.padding = false,
    required this.reportCount,
    required this.packetType,
    required this.length,
    required this.ssrc,
    required this.payload,
    this.paddingLength = 0,
  });

  /// Fixed header size
  static const int headerSize = 8;

  /// Get total packet size in bytes
  int get size {
    // Length field is number of 32-bit words minus one
    // So actual size is (length + 1) * 4
    return (length + 1) * 4;
  }

  /// Serialize RTCP packet to bytes
  Uint8List serialize() {
    final totalSize = size;
    final result = Uint8List(totalSize);
    final buffer = ByteData.sublistView(result);
    var offset = 0;

    // Byte 0: V(2), P(1), RC(5)
    int byte0 = (version << 6) |
        (padding ? 1 << 5 : 0) |
        (reportCount & 0x1F);
    buffer.setUint8(offset++, byte0);

    // Byte 1: Packet Type
    buffer.setUint8(offset++, packetType.value);

    // Bytes 2-3: Length
    buffer.setUint16(offset, length);
    offset += 2;

    // Bytes 4-7: SSRC
    buffer.setUint32(offset, ssrc);
    offset += 4;

    // Payload
    result.setRange(offset, offset + payload.length, payload);
    offset += payload.length;

    // Padding
    if (padding && paddingLength > 0) {
      for (var i = 0; i < paddingLength - 1; i++) {
        result[offset++] = 0;
      }
      result[offset] = paddingLength;
    }

    return result;
  }

  /// Parse RTCP packet from bytes
  static RtcpPacket parse(Uint8List data) {
    if (data.length < headerSize) {
      throw FormatException('RTCP packet too short: ${data.length} bytes');
    }

    final buffer = ByteData.sublistView(data);
    var offset = 0;

    // Byte 0
    final byte0 = buffer.getUint8(offset++);
    final version = (byte0 >> 6) & 0x03;
    final padding = (byte0 & 0x20) != 0;
    final reportCount = byte0 & 0x1F;

    if (version != 2) {
      throw FormatException('Invalid RTCP version: $version');
    }

    // Byte 1
    final packetTypeValue = buffer.getUint8(offset++);
    final packetType = RtcpPacketType.fromValue(packetTypeValue);
    if (packetType == null) {
      throw FormatException('Unknown RTCP packet type: $packetTypeValue');
    }

    // Length (in 32-bit words minus one)
    final length = buffer.getUint16(offset);
    offset += 2;

    // SSRC
    final ssrc = buffer.getUint32(offset);
    offset += 4;

    // Calculate actual packet size
    final packetSize = (length + 1) * 4;
    if (data.length < packetSize) {
      throw FormatException('RTCP packet truncated: expected $packetSize, got ${data.length}');
    }

    // Payload and padding
    var paddingLength = 0;
    var payloadEnd = packetSize;

    if (padding) {
      paddingLength = data[packetSize - 1];
      if (paddingLength == 0 || paddingLength > packetSize - offset) {
        throw FormatException('Invalid padding length: $paddingLength');
      }
      payloadEnd -= paddingLength;
    }

    final payload = data.sublist(offset, payloadEnd);

    return RtcpPacket(
      version: version,
      padding: padding,
      reportCount: reportCount,
      packetType: packetType,
      length: length,
      ssrc: ssrc,
      payload: payload,
      paddingLength: paddingLength,
    );
  }

  @override
  String toString() {
    return 'RtcpPacket(type=$packetType, ssrc=$ssrc, length=$length)';
  }
}

/// RTCP Compound Packet
/// RFC 3550 requires RTCP packets to be sent in compound packets
class RtcpCompoundPacket {
  final List<RtcpPacket> packets;

  const RtcpCompoundPacket(this.packets);

  /// Serialize compound packet
  Uint8List serialize() {
    final parts = <Uint8List>[];
    var totalLength = 0;

    for (final packet in packets) {
      final serialized = packet.serialize();
      parts.add(serialized);
      totalLength += serialized.length;
    }

    final result = Uint8List(totalLength);
    var offset = 0;
    for (final part in parts) {
      result.setRange(offset, offset + part.length, part);
      offset += part.length;
    }

    return result;
  }

  /// Parse compound packet
  static RtcpCompoundPacket parse(Uint8List data) {
    final packets = <RtcpPacket>[];
    var offset = 0;

    while (offset < data.length) {
      if (data.length - offset < RtcpPacket.headerSize) {
        break; // Not enough data for another packet
      }

      final packet = RtcpPacket.parse(data.sublist(offset));
      packets.add(packet);
      offset += packet.size;
    }

    return RtcpCompoundPacket(packets);
  }

  @override
  String toString() {
    return 'RtcpCompoundPacket(${packets.length} packets)';
  }
}
