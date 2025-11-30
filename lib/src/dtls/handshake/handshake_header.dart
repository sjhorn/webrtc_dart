import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';

/// DTLS Handshake Header
/// RFC 6347 Section 4.2.2
///
/// Structure:
///   struct {
///     HandshakeType msg_type;
///     uint24 length;
///     uint16 message_seq;
///     uint24 fragment_offset;
///     uint24 fragment_length;
///     select (HandshakeType) {
///       ...
///     } body;
///   } Handshake;
class HandshakeHeader {
  final HandshakeType messageType;
  final int length;
  final int messageSeq;
  final int fragmentOffset;
  final int fragmentLength;

  const HandshakeHeader({
    required this.messageType,
    required this.length,
    required this.messageSeq,
    required this.fragmentOffset,
    required this.fragmentLength,
  });

  /// Serialize header to bytes (12 bytes)
  Uint8List serialize() {
    final result = Uint8List(12);
    final buffer = ByteData.sublistView(result);

    // Message type (1 byte)
    buffer.setUint8(0, messageType.value);

    // Length (3 bytes)
    buffer.setUint8(1, (length >> 16) & 0xFF);
    buffer.setUint8(2, (length >> 8) & 0xFF);
    buffer.setUint8(3, length & 0xFF);

    // Message sequence (2 bytes)
    buffer.setUint16(4, messageSeq);

    // Fragment offset (3 bytes)
    buffer.setUint8(6, (fragmentOffset >> 16) & 0xFF);
    buffer.setUint8(7, (fragmentOffset >> 8) & 0xFF);
    buffer.setUint8(8, fragmentOffset & 0xFF);

    // Fragment length (3 bytes)
    buffer.setUint8(9, (fragmentLength >> 16) & 0xFF);
    buffer.setUint8(10, (fragmentLength >> 8) & 0xFF);
    buffer.setUint8(11, fragmentLength & 0xFF);

    return result;
  }

  /// Parse header from bytes
  static HandshakeHeader parse(Uint8List data) {
    if (data.length < 12) {
      throw FormatException('Handshake header too short: ${data.length} bytes');
    }

    final buffer = ByteData.sublistView(data);

    // Message type (1 byte)
    final messageTypeValue = buffer.getUint8(0);
    final messageType = HandshakeType.fromValue(messageTypeValue);
    if (messageType == null) {
      throw FormatException('Unknown handshake type: $messageTypeValue');
    }

    // Length (3 bytes)
    final length = (buffer.getUint8(1) << 16) |
        (buffer.getUint8(2) << 8) |
        buffer.getUint8(3);

    // Message sequence (2 bytes)
    final messageSeq = buffer.getUint16(4);

    // Fragment offset (3 bytes)
    final fragmentOffset = (buffer.getUint8(6) << 16) |
        (buffer.getUint8(7) << 8) |
        buffer.getUint8(8);

    // Fragment length (3 bytes)
    final fragmentLength = (buffer.getUint8(9) << 16) |
        (buffer.getUint8(10) << 8) |
        buffer.getUint8(11);

    return HandshakeHeader(
      messageType: messageType,
      length: length,
      messageSeq: messageSeq,
      fragmentOffset: fragmentOffset,
      fragmentLength: fragmentLength,
    );
  }

  @override
  String toString() {
    return 'HandshakeHeader('
        'type: $messageType, '
        'length: $length, '
        'seq: $messageSeq, '
        'offset: $fragmentOffset, '
        'fragLen: $fragmentLength'
        ')';
  }
}

/// Wrap a handshake message body with a header
Uint8List wrapHandshakeMessage(
  HandshakeType messageType,
  Uint8List body, {
  int messageSeq = 0,
}) {
  final header = HandshakeHeader(
    messageType: messageType,
    length: body.length,
    messageSeq: messageSeq,
    fragmentOffset: 0,
    fragmentLength: body.length,
  );

  final result = Uint8List(12 + body.length);
  result.setRange(0, 12, header.serialize());
  result.setRange(12, 12 + body.length, body);

  return result;
}

/// Parse a handshake message and extract the body
class HandshakeMessage {
  final HandshakeHeader header;
  final Uint8List body;

  /// Raw bytes (header + body) as originally received
  /// Used to preserve exact bytes for handshake hash computation
  final Uint8List? rawBytes;

  HandshakeMessage({
    required this.header,
    required this.body,
    this.rawBytes,
  });

  /// Parse from complete handshake message (header + body)
  static HandshakeMessage parse(Uint8List data) {
    if (data.length < 12) {
      throw FormatException('Handshake message too short: ${data.length} bytes');
    }

    final header = HandshakeHeader.parse(data);

    // Extract body
    if (data.length < 12 + header.fragmentLength) {
      throw FormatException(
        'Handshake message body too short: '
        'expected ${12 + header.fragmentLength}, got ${data.length}',
      );
    }

    final body = Uint8List.fromList(
      data.sublist(12, 12 + header.fragmentLength),
    );

    // Preserve original bytes for handshake hash computation
    final rawBytes = Uint8List.fromList(
      data.sublist(0, 12 + header.fragmentLength),
    );

    return HandshakeMessage(header: header, body: body, rawBytes: rawBytes);
  }

  /// Get the complete message (header + body)
  Uint8List serialize() {
    return wrapHandshakeMessage(
      header.messageType,
      body,
      messageSeq: header.messageSeq,
    );
  }

  /// Parse multiple handshake messages from a single buffer
  /// DTLS allows multiple handshake messages in a single record
  static List<HandshakeMessage> parseMultiple(Uint8List data) {
    final messages = <HandshakeMessage>[];
    var offset = 0;

    while (offset < data.length) {
      // Need at least 12 bytes for header
      if (data.length - offset < 12) {
        break;
      }

      final header = HandshakeHeader.parse(data.sublist(offset));
      final messageLength = 12 + header.fragmentLength;

      // Check we have enough data for the body
      if (data.length - offset < messageLength) {
        break;
      }

      final body = Uint8List.fromList(
        data.sublist(offset + 12, offset + messageLength),
      );

      // Preserve original bytes for handshake hash computation
      final rawBytes = Uint8List.fromList(
        data.sublist(offset, offset + messageLength),
      );

      messages.add(HandshakeMessage(header: header, body: body, rawBytes: rawBytes));
      offset += messageLength;
    }

    return messages;
  }
}
