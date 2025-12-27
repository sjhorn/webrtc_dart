import 'dart:typed_data';
import '../srtp/rtcp_packet.dart';

/// RTCP Source Description (SDES) Packet
/// RFC 3550 Section 6.5
///
/// SDES packet format:
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |V=2|P|    SC   |  PT=SDES=202  |             length            |
/// +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
/// |                          SSRC/CSRC_1                          |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                           SDES items                          |
/// |                              ...                              |
/// +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
/// |                          SSRC/CSRC_2                          |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                           SDES items                          |
/// |                              ...                              |
/// +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+

/// SDES item types from RFC 3550
enum SdesItemType {
  end(0), // End of SDES list
  cname(1), // Canonical name
  name(2), // User name
  email(3), // Email address
  phone(4), // Phone number
  loc(5), // Geographic location
  tool(6), // Application or tool name
  note(7), // Notice/status
  priv(8); // Private extension

  final int value;
  const SdesItemType(this.value);

  static SdesItemType? fromValue(int value) {
    for (final type in values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// A single SDES item (type + text)
class SourceDescriptionItem {
  /// Item type (CNAME, NAME, etc.)
  final int type;

  /// Text content
  final String text;

  SourceDescriptionItem({
    required this.type,
    required this.text,
  });

  /// Create an item with a typed enum
  factory SourceDescriptionItem.typed({
    required SdesItemType type,
    required String text,
  }) {
    return SourceDescriptionItem(type: type.value, text: text);
  }

  /// Item length: 1 (type) + 1 (length) + text bytes
  int get length {
    final textBytes = _encodeText(text);
    return 1 + 1 + textBytes.length;
  }

  /// Serialize to bytes
  Uint8List serialize() {
    final textBytes = _encodeText(text);
    final result = Uint8List(1 + 1 + textBytes.length);
    result[0] = type;
    result[1] = textBytes.length;
    result.setRange(2, 2 + textBytes.length, textBytes);
    return result;
  }

  /// Deserialize from bytes
  static SourceDescriptionItem deserialize(Uint8List data) {
    if (data.length < 2) {
      throw FormatException('SDES item too short: ${data.length}');
    }

    final type = data[0];
    final octetCount = data[1];

    if (data.length < 2 + octetCount) {
      throw FormatException(
          'SDES item truncated: need ${2 + octetCount}, have ${data.length}');
    }

    final text = String.fromCharCodes(data.sublist(2, 2 + octetCount));
    return SourceDescriptionItem(type: type, text: text);
  }

  /// Encode text to UTF-8 bytes
  static Uint8List _encodeText(String text) {
    // UTF-8 encoding
    final units = text.codeUnits;
    return Uint8List.fromList(units);
  }

  @override
  String toString() {
    final typeName = SdesItemType.fromValue(type)?.name ?? 'unknown($type)';
    return 'SdesItem($typeName: "$text")';
  }
}

/// A chunk containing SSRC and its SDES items
class SourceDescriptionChunk {
  /// SSRC/CSRC identifier
  final int source;

  /// List of SDES items for this source
  final List<SourceDescriptionItem> items;

  SourceDescriptionChunk({
    required this.source,
    List<SourceDescriptionItem>? items,
  }) : items = items ?? [];

  /// Chunk length: 4 (SSRC) + items + 1 (END) + padding to 4-byte boundary
  int get length {
    int len = 4; // SSRC
    for (final item in items) {
      len += item.length;
    }
    len += 1; // END item (type 0)
    len += _getPadding(len);
    return len;
  }

  /// Serialize to bytes
  Uint8List serialize() {
    final parts = <int>[];

    // SSRC (4 bytes, big-endian)
    parts.add((source >> 24) & 0xFF);
    parts.add((source >> 16) & 0xFF);
    parts.add((source >> 8) & 0xFF);
    parts.add(source & 0xFF);

    // Items
    for (final item in items) {
      parts.addAll(item.serialize());
    }

    // END item (type 0) - no length byte needed for END
    parts.add(0);

    // Padding to 4-byte boundary
    final padding = _getPadding(parts.length);
    for (var i = 0; i < padding; i++) {
      parts.add(0);
    }

    return Uint8List.fromList(parts);
  }

  /// Deserialize from bytes
  static SourceDescriptionChunk deserialize(Uint8List data) {
    if (data.length < 4) {
      throw FormatException('SDES chunk too short: ${data.length}');
    }

    final buffer = ByteData.sublistView(data);
    final source = buffer.getUint32(0);

    final items = <SourceDescriptionItem>[];
    var offset = 4;

    while (offset < data.length) {
      final type = data[offset];
      if (type == 0) break; // END item

      final item = SourceDescriptionItem.deserialize(data.sublist(offset));
      items.add(item);
      offset += item.length;
    }

    return SourceDescriptionChunk(source: source, items: items);
  }

  /// Calculate padding needed to reach 4-byte boundary
  static int _getPadding(int len) {
    if (len % 4 == 0) return 0;
    return 4 - (len % 4);
  }

  @override
  String toString() {
    return 'SdesChunk(ssrc=$source, items=$items)';
  }
}

/// RTCP Source Description packet
class RtcpSourceDescription {
  /// RTCP packet type for SDES
  static const int type = 202;

  /// Chunks in this SDES packet
  final List<SourceDescriptionChunk> chunks;

  RtcpSourceDescription({
    List<SourceDescriptionChunk>? chunks,
  }) : chunks = chunks ?? [];

  /// Convenience constructor for a single SSRC with CNAME
  factory RtcpSourceDescription.withCname({
    required int ssrc,
    required String cname,
  }) {
    return RtcpSourceDescription(
      chunks: [
        SourceDescriptionChunk(
          source: ssrc,
          items: [
            SourceDescriptionItem.typed(
              type: SdesItemType.cname,
              text: cname,
            ),
          ],
        ),
      ],
    );
  }

  /// Payload length (sum of all chunk lengths)
  int get payloadLength {
    int len = 0;
    for (final chunk in chunks) {
      len += chunk.length;
    }
    return len;
  }

  /// Serialize to RTCP packet
  RtcpPacket toRtcpPacket() {
    // Serialize all chunks
    final parts = <int>[];
    for (final chunk in chunks) {
      parts.addAll(chunk.serialize());
    }

    // Ensure 4-byte alignment
    while (parts.length % 4 != 0) {
      parts.add(0);
    }

    final payload = Uint8List.fromList(parts);

    // Length in 32-bit words minus one
    // For SDES, header is 4 bytes (no SSRC in header) + payload
    final length = (4 + payload.length) ~/ 4 - 1;

    return RtcpPacket(
      version: 2,
      padding: false,
      reportCount: chunks.length, // SC = source count
      packetType: RtcpPacketType.sourceDescription,
      length: length,
      ssrc: chunks.isNotEmpty ? chunks.first.source : 0,
      payload: payload.length > 4 ? payload.sublist(4) : Uint8List(0),
    );
  }

  /// Serialize to bytes (full RTCP packet)
  Uint8List serialize() {
    // Serialize all chunks
    final parts = <int>[];
    for (final chunk in chunks) {
      parts.addAll(chunk.serialize());
    }

    // Ensure 4-byte alignment
    while (parts.length % 4 != 0) {
      parts.add(0);
    }

    final payload = Uint8List.fromList(parts);

    // Build RTCP header
    final headerAndPayload = Uint8List(4 + payload.length);
    final buffer = ByteData.sublistView(headerAndPayload);

    // Byte 0: V=2, P=0, SC (source count)
    headerAndPayload[0] = (2 << 6) | (chunks.length & 0x1F);

    // Byte 1: PT=202
    headerAndPayload[1] = type;

    // Bytes 2-3: Length in 32-bit words minus one
    final length = (headerAndPayload.length ~/ 4) - 1;
    buffer.setUint16(2, length);

    // Payload (chunks)
    headerAndPayload.setRange(4, 4 + payload.length, payload);

    return headerAndPayload;
  }

  /// Deserialize from RTCP packet payload
  static RtcpSourceDescription fromRtcpPacket(RtcpPacket packet) {
    if (packet.packetType != RtcpPacketType.sourceDescription) {
      throw FormatException('Not an SDES packet: ${packet.packetType}');
    }

    // Reconstruct full payload including first SSRC
    final fullPayload = Uint8List(4 + packet.payload.length);
    final buffer = ByteData.sublistView(fullPayload);
    buffer.setUint32(0, packet.ssrc);
    fullPayload.setRange(4, fullPayload.length, packet.payload);

    return deserialize(fullPayload, packet.reportCount);
  }

  /// Deserialize from raw bytes (payload only, after RTCP header)
  static RtcpSourceDescription deserialize(Uint8List payload, int chunkCount) {
    final chunks = <SourceDescriptionChunk>[];
    var offset = 0;

    while (offset < payload.length && chunks.length < chunkCount) {
      if (payload.length - offset < 4) break;

      final chunk = SourceDescriptionChunk.deserialize(payload.sublist(offset));
      chunks.add(chunk);
      offset += chunk.length;
    }

    return RtcpSourceDescription(chunks: chunks);
  }

  @override
  String toString() {
    return 'RtcpSourceDescription(${chunks.length} chunks: $chunks)';
  }
}
