import 'dart:typed_data';

/// RTP Packet
/// RFC 3550 - RTP: A Transport Protocol for Real-Time Applications
///
/// RTP Header Format:
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |V=2|P|X|  CC   |M|     PT      |       sequence number         |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                           timestamp                           |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |           synchronization source (SSRC) identifier            |
/// +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
/// |            contributing source (CSRC) identifiers             |
/// |                             ....                              |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
class RtpPacket {
  /// RTP version (always 2)
  final int version;

  /// Padding flag
  final bool padding;

  /// Extension flag
  final bool extension;

  /// CSRC count
  final int csrcCount;

  /// Marker bit
  final bool marker;

  /// Payload type
  final int payloadType;

  /// Sequence number (16-bit)
  final int sequenceNumber;

  /// Timestamp (32-bit)
  final int timestamp;

  /// Synchronization source identifier
  final int ssrc;

  /// Contributing source identifiers
  final List<int> csrcs;

  /// Extension header (if extension flag is set)
  final RtpExtension? extensionHeader;

  /// Payload data
  final Uint8List payload;

  /// Padding length (if padding flag is set)
  final int paddingLength;

  const RtpPacket({
    this.version = 2,
    this.padding = false,
    this.extension = false,
    int? csrcCount,
    this.marker = false,
    required this.payloadType,
    required this.sequenceNumber,
    required this.timestamp,
    required this.ssrc,
    this.csrcs = const [],
    this.extensionHeader,
    required this.payload,
    this.paddingLength = 0,
  }) : csrcCount = csrcCount ?? csrcs.length;

  /// Fixed header size (without CSRCs)
  static const int fixedHeaderSize = 12;

  /// Get total header size (including CSRCs and extension)
  int get headerSize {
    var size = fixedHeaderSize;
    size += csrcs.length * 4; // Each CSRC is 4 bytes
    if (extension && extensionHeader != null) {
      size += 4 + extensionHeader!.data.length; // 4-byte header + data
    }
    return size;
  }

  /// Get total packet size
  int get size {
    var totalSize = headerSize + payload.length;
    if (padding) {
      totalSize += paddingLength;
    }
    return totalSize;
  }

  /// Serialize only the RTP header (without payload)
  Uint8List serializeHeader() {
    final size = headerSize;
    final result = Uint8List(size);
    final buffer = ByteData.sublistView(result);
    var offset = 0;

    // Byte 0: V(2), P(1), X(1), CC(4)
    int byte0 = (version << 6) |
        (padding ? 1 << 5 : 0) |
        (extension ? 1 << 4 : 0) |
        (csrcCount & 0x0F);
    buffer.setUint8(offset++, byte0);

    // Byte 1: M(1), PT(7)
    int byte1 = (marker ? 1 << 7 : 0) | (payloadType & 0x7F);
    buffer.setUint8(offset++, byte1);

    // Bytes 2-3: Sequence number
    buffer.setUint16(offset, sequenceNumber);
    offset += 2;

    // Bytes 4-7: Timestamp
    buffer.setUint32(offset, timestamp);
    offset += 4;

    // Bytes 8-11: SSRC
    buffer.setUint32(offset, ssrc);
    offset += 4;

    // CSRCs
    for (final csrc in csrcs) {
      buffer.setUint32(offset, csrc);
      offset += 4;
    }

    // Extension header
    if (extension && extensionHeader != null) {
      final ext = extensionHeader!;
      buffer.setUint16(offset, ext.profile);
      offset += 2;
      buffer.setUint16(offset, (ext.data.length / 4).floor());
      offset += 2;
      result.setRange(offset, offset + ext.data.length, ext.data);
    }

    return result;
  }

  /// Serialize RTP packet to bytes
  Uint8List serialize() {
    final size = this.size;
    final result = Uint8List(size);
    final buffer = ByteData.sublistView(result);
    var offset = 0;

    // Byte 0: V(2), P(1), X(1), CC(4)
    int byte0 = (version << 6) |
        (padding ? 1 << 5 : 0) |
        (extension ? 1 << 4 : 0) |
        (csrcCount & 0x0F);
    buffer.setUint8(offset++, byte0);

    // Byte 1: M(1), PT(7)
    int byte1 = (marker ? 1 << 7 : 0) | (payloadType & 0x7F);
    buffer.setUint8(offset++, byte1);

    // Bytes 2-3: Sequence number
    buffer.setUint16(offset, sequenceNumber);
    offset += 2;

    // Bytes 4-7: Timestamp
    buffer.setUint32(offset, timestamp);
    offset += 4;

    // Bytes 8-11: SSRC
    buffer.setUint32(offset, ssrc);
    offset += 4;

    // CSRCs
    for (final csrc in csrcs) {
      buffer.setUint32(offset, csrc);
      offset += 4;
    }

    // Extension header
    if (extension && extensionHeader != null) {
      final ext = extensionHeader!;
      buffer.setUint16(offset, ext.profile);
      offset += 2;
      buffer.setUint16(offset, (ext.data.length / 4).floor());
      offset += 2;
      result.setRange(offset, offset + ext.data.length, ext.data);
      offset += ext.data.length;
    }

    // Payload
    result.setRange(offset, offset + payload.length, payload);
    offset += payload.length;

    // Padding
    if (padding && paddingLength > 0) {
      // Fill with zeros except last byte which contains padding length
      for (var i = 0; i < paddingLength - 1; i++) {
        result[offset++] = 0;
      }
      result[offset] = paddingLength;
    }

    return result;
  }

  /// Parse RTP packet from bytes
  static RtpPacket parse(Uint8List data) {
    if (data.length < fixedHeaderSize) {
      throw FormatException('RTP packet too short: ${data.length} bytes');
    }

    final buffer = ByteData.sublistView(data);
    var offset = 0;

    // Byte 0
    final byte0 = buffer.getUint8(offset++);
    final version = (byte0 >> 6) & 0x03;
    final padding = (byte0 & 0x20) != 0;
    final extension = (byte0 & 0x10) != 0;
    final csrcCount = byte0 & 0x0F;

    if (version != 2) {
      throw FormatException('Invalid RTP version: $version');
    }

    // Byte 1
    final byte1 = buffer.getUint8(offset++);
    final marker = (byte1 & 0x80) != 0;
    final payloadType = byte1 & 0x7F;

    // Sequence number
    final sequenceNumber = buffer.getUint16(offset);
    offset += 2;

    // Timestamp
    final timestamp = buffer.getUint32(offset);
    offset += 4;

    // SSRC
    final ssrc = buffer.getUint32(offset);
    offset += 4;

    // CSRCs
    final csrcs = <int>[];
    for (var i = 0; i < csrcCount; i++) {
      if (offset + 4 > data.length) {
        throw FormatException('Truncated CSRC list');
      }
      csrcs.add(buffer.getUint32(offset));
      offset += 4;
    }

    // Extension header
    RtpExtension? extensionHeader;
    if (extension) {
      if (offset + 4 > data.length) {
        throw FormatException('Truncated extension header');
      }
      final profile = buffer.getUint16(offset);
      offset += 2;
      final length = buffer.getUint16(offset) * 4; // Length is in 32-bit words
      offset += 2;

      if (offset + length > data.length) {
        throw FormatException('Truncated extension data');
      }
      final extData = data.sublist(offset, offset + length);
      offset += length;

      extensionHeader = RtpExtension(profile: profile, data: extData);
    }

    // Payload and padding
    var paddingLength = 0;
    var payloadEnd = data.length;

    if (padding) {
      if (offset >= data.length) {
        throw FormatException('Missing padding length byte');
      }
      paddingLength = data[data.length - 1];
      if (paddingLength == 0 || paddingLength > data.length - offset) {
        throw FormatException('Invalid padding length: $paddingLength');
      }
      payloadEnd -= paddingLength;
    }

    if (offset > payloadEnd) {
      throw FormatException('Invalid packet structure');
    }

    final payload = data.sublist(offset, payloadEnd);

    return RtpPacket(
      version: version,
      padding: padding,
      extension: extension,
      csrcCount: csrcCount,
      marker: marker,
      payloadType: payloadType,
      sequenceNumber: sequenceNumber,
      timestamp: timestamp,
      ssrc: ssrc,
      csrcs: csrcs,
      extensionHeader: extensionHeader,
      payload: payload,
      paddingLength: paddingLength,
    );
  }

  @override
  String toString() {
    return 'RtpPacket(pt=$payloadType, seq=$sequenceNumber, ts=$timestamp, ssrc=$ssrc, payload=${payload.length}B)';
  }
}

/// RTP Extension Header
class RtpExtension {
  final int profile;
  final Uint8List data;

  const RtpExtension({
    required this.profile,
    required this.data,
  });
}
