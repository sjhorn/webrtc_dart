import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';

/// Fragmented handshake message for DTLS
/// Structure (12 bytes header + fragment):
/// - msg_type (1 byte)
/// - length (3 bytes) - total message length
/// - message_seq (2 bytes)
/// - fragment_offset (3 bytes)
/// - fragment_length (3 bytes)
/// - fragment (variable length)
class FragmentedHandshake {
  final int msgType;
  final int length; // Total message length
  final int messageSeq;
  final int fragmentOffset;
  final int fragmentLength;
  final Uint8List fragment;

  const FragmentedHandshake({
    required this.msgType,
    required this.length,
    required this.messageSeq,
    required this.fragmentOffset,
    required this.fragmentLength,
    required this.fragment,
  });

  /// Parse fragmented handshake from bytes
  factory FragmentedHandshake.deserialize(Uint8List data) {
    if (data.length < 12) {
      throw ArgumentError(
        'Invalid fragmented handshake: expected at least 12 bytes, got ${data.length}',
      );
    }

    final buffer = ByteData.sublistView(data);

    final msgType = buffer.getUint8(0);

    // Read 24-bit length
    final length = (buffer.getUint8(1) << 16) |
        (buffer.getUint8(2) << 8) |
        buffer.getUint8(3);

    final messageSeq = buffer.getUint16(4);

    // Read 24-bit fragment offset
    final fragmentOffset = (buffer.getUint8(6) << 16) |
        (buffer.getUint8(7) << 8) |
        buffer.getUint8(8);

    // Read 24-bit fragment length
    final fragmentLength = (buffer.getUint8(9) << 16) |
        (buffer.getUint8(10) << 8) |
        buffer.getUint8(11);

    // Extract fragment
    if (data.length < 12 + fragmentLength) {
      throw ArgumentError(
        'Invalid fragmented handshake: fragment length ($fragmentLength) '
        'exceeds available data (${data.length - 12})',
      );
    }

    final fragment = Uint8List.sublistView(data, 12, 12 + fragmentLength);

    return FragmentedHandshake(
      msgType: msgType,
      length: length,
      messageSeq: messageSeq,
      fragmentOffset: fragmentOffset,
      fragmentLength: fragmentLength,
      fragment: fragment,
    );
  }

  /// Serialize fragmented handshake to bytes
  Uint8List serialize() {
    final result = Uint8List(12 + fragment.length);
    final buffer = ByteData.sublistView(result);

    buffer.setUint8(0, msgType);

    // Write 24-bit length
    buffer.setUint8(1, (length >> 16) & 0xFF);
    buffer.setUint8(2, (length >> 8) & 0xFF);
    buffer.setUint8(3, length & 0xFF);

    buffer.setUint16(4, messageSeq);

    // Write 24-bit fragment offset
    buffer.setUint8(6, (fragmentOffset >> 16) & 0xFF);
    buffer.setUint8(7, (fragmentOffset >> 8) & 0xFF);
    buffer.setUint8(8, fragmentOffset & 0xFF);

    // Write 24-bit fragment length
    buffer.setUint8(9, (fragmentLength >> 16) & 0xFF);
    buffer.setUint8(10, (fragmentLength >> 8) & 0xFF);
    buffer.setUint8(11, fragmentLength & 0xFF);

    // Copy fragment data
    result.setRange(12, 12 + fragment.length, fragment);

    return result;
  }

  /// Split this handshake message into fragments
  /// [maxFragmentLength] - maximum fragment size (default: 1228 bytes for MTU 1280)
  /// Default calculation: MTU(1280) - IP(20) - UDP(8) - DTLS_header(13) - handshake_header(12) = 1227
  List<FragmentedHandshake> chunk([int? maxFragmentLength]) {
    maxFragmentLength ??= 1227; // Default based on MTU 1280

    final totalLength = fragment.length;

    // Handle empty fragment
    if (totalLength == 0) {
      return [
        FragmentedHandshake(
          msgType: msgType,
          length: totalLength,
          messageSeq: messageSeq,
          fragmentOffset: 0,
          fragmentLength: 0,
          fragment: fragment,
        ),
      ];
    }

    final fragments = <FragmentedHandshake>[];
    var start = 0;

    while (start < totalLength) {
      final chunkLength = (start + maxFragmentLength < totalLength)
          ? maxFragmentLength
          : totalLength - start;

      if (chunkLength <= 0) {
        throw StateError(
          'Zero or less bytes processed while fragmenting handshake message',
        );
      }

      final data = Uint8List.sublistView(fragment, start, start + chunkLength);

      fragments.add(
        FragmentedHandshake(
          msgType: msgType,
          length: totalLength,
          messageSeq: messageSeq,
          fragmentOffset: start,
          fragmentLength: data.length,
          fragment: data,
        ),
      );

      start += chunkLength;
    }

    return fragments;
  }

  /// Assemble multiple fragments into a complete message
  static FragmentedHandshake assemble(List<FragmentedHandshake> messages) {
    if (messages.isEmpty) {
      throw ArgumentError('Cannot reassemble handshake from empty array');
    }

    // Sort by fragment offset
    final sorted = List<FragmentedHandshake>.from(messages)
      ..sort((a, b) => a.fragmentOffset.compareTo(b.fragmentOffset));

    // Allocate buffer for complete message
    final combined = Uint8List(sorted.first.length);

    // Copy each fragment into the correct position
    for (final msg in sorted) {
      combined.setRange(
        msg.fragmentOffset,
        msg.fragmentOffset + msg.fragment.length,
        msg.fragment,
      );
    }

    return FragmentedHandshake(
      msgType: sorted.first.msgType,
      length: sorted.first.length,
      messageSeq: sorted.first.messageSeq,
      fragmentOffset: 0,
      fragmentLength: combined.length,
      fragment: combined,
    );
  }

  /// Find all fragments matching a specific handshake type
  static List<FragmentedHandshake> findAllFragments(
    List<FragmentedHandshake> fragments,
    HandshakeType type,
  ) {
    if (fragments.isEmpty) return [];

    // Find reference fragment
    final reference = fragments.cast<FragmentedHandshake?>().firstWhere(
          (v) => v?.msgType == type.value,
          orElse: () => null,
        );

    if (reference == null) return [];

    // Return all fragments with matching type, sequence, and length
    return fragments.where((f) {
      return f.msgType == reference.msgType &&
          f.messageSeq == reference.messageSeq &&
          f.length == reference.length;
    }).toList();
  }

  /// Get handshake type as enum
  HandshakeType? get handshakeType => HandshakeType.fromValue(msgType);

  @override
  String toString() {
    return 'FragmentedHandshake(type=$msgType, len=$length, seq=$messageSeq, '
        'offset=$fragmentOffset, fragLen=$fragmentLength)';
  }

  @override
  bool operator ==(Object other) =>
      other is FragmentedHandshake &&
      msgType == other.msgType &&
      length == other.length &&
      messageSeq == other.messageSeq &&
      fragmentOffset == other.fragmentOffset &&
      fragmentLength == other.fragmentLength &&
      _bytesEqual(fragment, other.fragment);

  @override
  int get hashCode => Object.hash(
        msgType,
        length,
        messageSeq,
        fragmentOffset,
        fragmentLength,
        Object.hashAll(fragment),
      );

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
