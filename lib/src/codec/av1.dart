import 'dart:typed_data';
import '../common/binary.dart';

/// AV1 RTP Payload Format
/// https://aomediacodec.github.io/av1-rtp-spec/
///
/// This implementation handles RTP payload depacketization for AV1 video frames.
/// Ported from werift-webrtc TypeScript implementation.

/// OBU (Open Bitstream Unit) Types
const Map<int, String> obuTypes = {
  0: 'Reserved',
  1: 'OBU_SEQUENCE_HEADER',
  2: 'OBU_TEMPORAL_DELIMITER',
  3: 'OBU_FRAME_HEADER',
  4: 'OBU_TILE_GROUP',
  5: 'OBU_METADATA',
  6: 'OBU_FRAME',
  7: 'OBU_REDUNDANT_FRAME_HEADER',
  8: 'OBU_TILE_LIST',
  15: 'OBU_PADDING',
};

/// Reverse mapping: OBU type name to ID
final Map<String, int> obuTypeIds = {
  for (final entry in obuTypes.entries) entry.value: entry.key,
};

/// Decode LEB128 (Little Endian Base 128) variable-length integer
/// Returns [value, bytesRead]
List<int> leb128decode(Uint8List buf) {
  int value = 0;
  int leb128bytes = 0;

  for (int i = 0; i < 8 && i < buf.length; i++) {
    final leb128byte = buf[i];
    value |= (leb128byte & 0x7F) << (i * 7);
    leb128bytes++;
    if ((leb128byte & 0x80) == 0) {
      break;
    }
  }

  return [value, leb128bytes];
}

/// Encode value as LEB128
Uint8List leb128encode(int value) {
  final bytes = <int>[];

  do {
    int byte = value & 0x7F;
    value >>= 7;
    if (value != 0) {
      byte |= 0x80; // More bytes to come
    }
    bytes.add(byte);
  } while (value != 0);

  return Uint8List.fromList(bytes);
}

/// OBU or Fragment element from RTP payload
class Av1ObuElement {
  /// OBU data
  final Uint8List data;

  /// Whether this is a fragment (continuation or to be continued)
  final bool isFragment;

  Av1ObuElement({required this.data, required this.isFragment});

  @override
  String toString() {
    return 'Av1ObuElement(size=${data.length}, isFragment=$isFragment)';
  }
}

/// AV1 OBU (Open Bitstream Unit)
class Av1Obu {
  /// Forbidden bit (must be 0)
  int obuForbiddenBit = 0;

  /// OBU type name
  String obuType = 'Reserved';

  /// Extension flag
  int obuExtensionFlag = 0;

  /// Has size field flag
  int obuHasSizeField = 0;

  /// Reserved bit
  int obuReserved1Bit = 0;

  /// OBU payload (everything after the header byte)
  late Uint8List payload;

  /// Deserialize OBU from buffer
  /// Note: This matches TypeScript which just takes everything after header byte as payload
  static Av1Obu deserialize(Uint8List buf) {
    final obu = Av1Obu();

    if (buf.isEmpty) {
      obu.payload = Uint8List(0);
      return obu;
    }

    int offset = 0;

    // Parse OBU header (1 byte)
    // Bit layout: F | TYPE(4) | X | S | R
    obu.obuForbiddenBit = getBit(buf[offset], 0, 1);
    final typeId = getBit(buf[offset], 1, 4);
    obu.obuType = obuTypes[typeId] ?? 'Reserved';
    obu.obuExtensionFlag = getBit(buf[offset], 5, 1);
    obu.obuHasSizeField = getBit(buf[offset], 6, 1);
    obu.obuReserved1Bit = getBit(buf[offset], 7, 1);
    offset++;

    // Payload is everything after the header byte
    obu.payload = buf.sublist(offset);
    return obu;
  }

  /// Serialize OBU to buffer
  Uint8List serialize() {
    // Build header byte using MSB-first bit layout to match getBit:
    // Bit layout: F | TYPE(4) | X | S | R
    // Bit 0 (MSB) = forbidden, bits 1-4 = type, bit 5 = extension, bit 6 = has_size, bit 7 = reserved
    int header = 0;
    header |= (obuForbiddenBit & 0x01) << 7; // bit 0 -> position 7
    header |= ((obuTypeIds[obuType] ?? 0) & 0x0F) << 3; // bits 1-4 -> positions 6-3
    header |= (obuExtensionFlag & 0x01) << 2; // bit 5 -> position 2
    header |= (obuHasSizeField & 0x01) << 1; // bit 6 -> position 1
    header |= (obuReserved1Bit & 0x01); // bit 7 -> position 0

    Uint8List obuSize = Uint8List(0);
    if (obuHasSizeField == 1) {
      obuSize = leb128encode(payload.length);
    }

    // Concatenate header + size (if any) + payload
    final result = Uint8List(1 + obuSize.length + payload.length);
    result[0] = header;
    if (obuSize.isNotEmpty) {
      result.setRange(1, 1 + obuSize.length, obuSize);
    }
    result.setRange(1 + obuSize.length, result.length, payload);
    return result;
  }

  @override
  String toString() {
    return 'Av1Obu(type=$obuType, hasSize=$obuHasSizeField, payloadSize=${payload.length})';
  }
}

/// AV1 RTP Payload
/// https://aomediacodec.github.io/av1-rtp-spec/
///
/// Aggregation Header (1 byte):
///  0 1 2 3 4 5 6 7
/// +-+-+-+-+-+-+-+-+
/// |Z|Y| W |N|-|-|-|
/// +-+-+-+-+-+-+-+-+
class Av1RtpPayload {
  /// Z bit: RtpStartsWithFragment
  /// MUST be 1 if first OBU element is a continuation of previous packet
  int zBit = 0;

  /// Y bit: RtpEndsWithFragment
  /// MUST be 1 if last OBU element will continue in next packet
  int yBit = 0;

  /// W field: RtpNumObus (2 bits)
  /// Number of OBU elements in packet (0 means each OBU preceded by length)
  int wField = 0;

  /// N bit: RtpStartsNewCodedVideoSequence
  /// MUST be 1 if packet is first of coded video sequence
  int nBit = 0;

  /// OBU elements or fragments
  final List<Av1ObuElement> obuOrFragment = [];

  /// Deserialize AV1 RTP payload from buffer
  /// Matches TypeScript deSerialize exactly
  static Av1RtpPayload deserialize(Uint8List buf) {
    final p = Av1RtpPayload();

    if (buf.isEmpty) {
      return p;
    }

    int offset = 0;

    // Parse aggregation header (1 byte)
    p.zBit = getBit(buf[offset], 0, 1);
    p.yBit = getBit(buf[offset], 1, 1);
    p.wField = getBit(buf[offset], 2, 2);
    p.nBit = getBit(buf[offset], 4, 1);
    offset++;

    // Validation: N and Z cannot both be 1
    if (p.nBit == 1 && p.zBit == 1) {
      throw FormatException(
          'Invalid AV1 RTP payload: N and Z bits cannot both be 1');
    }

    // Parse W-1 elements with LEB128 size prefix
    for (int i = 0; i < p.wField - 1; i++) {
      final sizeResult = leb128decode(buf.sublist(offset));
      final elementSize = sizeResult[0];
      final bytes = sizeResult[1];

      final start = offset + bytes;
      final end = start + elementSize;

      bool isFragment = false;
      if (p.zBit == 1 && i == 0) {
        isFragment = true;
      }
      p.obuOrFragment.add(Av1ObuElement(
        data: buf.sublist(start, end),
        isFragment: isFragment,
      ));

      offset += bytes + elementSize;
    }

    // Last element uses remaining data (no size prefix)
    bool isFragment = false;
    if (p.yBit == 1 || (p.wField == 1 && p.zBit == 1)) {
      isFragment = true;
    }
    p.obuOrFragment.add(Av1ObuElement(
      data: buf.sublist(offset),
      isFragment: isFragment,
    ));

    return p;
  }

  /// Check if this is a keyframe (new coded video sequence)
  bool get isKeyframe => nBit == 1;

  /// Check if RTP marker indicates final packet in sequence
  static bool isDetectedFinalPacketInSequence(bool rtpMarker) {
    return rtpMarker;
  }

  /// Reassemble complete frame from multiple RTP payloads
  /// Returns the reassembled OBU stream suitable for decoder
  /// Matches TypeScript getFrame exactly
  static Uint8List getFrame(List<Av1RtpPayload> payloads) {
    final frames = <Uint8List>[];

    // Flatten all OBU elements and index them
    final objects = <int, Av1ObuElement>{};
    int idx = 0;
    for (final p in payloads) {
      for (final element in p.obuOrFragment) {
        objects[idx] = element;
        idx++;
      }
    }
    final length = objects.length;

    // Process elements, merging fragments
    for (final i in objects.keys.toList()..sort()) {
      final exist = objects[i];
      if (exist == null) continue;

      if (exist.isFragment) {
        final fragments = <Uint8List>[];
        for (int head = i; head < length; head++) {
          final target = objects[head];
          if (target != null && target.isFragment) {
            fragments.add(target.data);
            objects.remove(head);
          } else {
            break;
          }
        }
        if (fragments.length <= 1) {
          // Fragment lost, maybe packet lost - clear fragments
          continue;
        }
        // Concatenate fragments
        final totalLen = fragments.fold<int>(0, (sum, f) => sum + f.length);
        final merged = Uint8List(totalLen);
        int off = 0;
        for (final fragment in fragments) {
          merged.setRange(off, off + fragment.length, fragment);
          off += fragment.length;
        }
        frames.add(merged);
      } else {
        frames.add(exist.data);
      }
    }

    // Parse OBUs and serialize with size fields
    final obus = frames.map((f) => Av1Obu.deserialize(f)).toList();

    if (obus.isEmpty) {
      return Uint8List(0);
    }

    // All OBUs except last get size field set
    final lastObu = obus.removeLast();

    final serialized = <Uint8List>[];
    for (final obu in obus) {
      obu.obuHasSizeField = 1;
      serialized.add(obu.serialize());
    }
    serialized.add(lastObu.serialize());

    // Concatenate all
    final totalLength = serialized.fold<int>(0, (sum, s) => sum + s.length);
    final result = Uint8List(totalLength);
    int offset = 0;
    for (final s in serialized) {
      result.setRange(offset, offset + s.length, s);
      offset += s.length;
    }

    return result;
  }

  @override
  String toString() {
    return 'Av1RtpPayload(Z=$zBit, Y=$yBit, W=$wField, N=$nBit, '
        'elements=${obuOrFragment.length}, keyframe=$isKeyframe)';
  }
}
