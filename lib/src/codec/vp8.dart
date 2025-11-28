import 'dart:typed_data';
import '../common/binary.dart';

/// VP8 RTP Payload
/// RFC 7741 - RTP Payload Format for VP8 Video
///
/// This implementation handles RTP payload depacketization for VP8 video frames.
/// Actual video encoding/decoding should be done by external tools
/// (e.g., FFmpeg, libvpx) or platform-specific codecs.
class Vp8RtpPayload {
  // Required RTP Payload Descriptor fields
  /// Extended control bits present flag
  int xBit = 0;

  /// Non-reference frame flag
  int nBit = 0;

  /// Start of VP8 partition flag
  int sBit = 0;

  /// Partition index (3 bits: 0-7)
  int pid = 0;

  // Optional extended fields (present when xBit=1)
  /// Picture ID present flag
  int? iBit;

  /// TL0PICIDX present flag
  int? lBit;

  /// TID/KEYIDX present flag
  int? tBit;

  /// KEYIDX present flag
  int? kBit;

  /// Extended Picture ID flag (7-bit or 15-bit mode)
  int? mBit;

  /// Picture identification (7-bit or 15-bit)
  int? pictureId;

  /// VP8 payload data
  late Uint8List payload;

  // VP8 Payload Header fields (when payloadHeaderExist)
  /// Frame size bits 0-2
  int size0 = 0;

  /// Show frame flag
  int? hBit;

  /// Version (3 bits)
  int? ver;

  /// Keyframe flag (0=keyframe, 1=interframe)
  int? pBit;

  /// Frame size bits 3-10
  int size1 = 0;

  /// Frame size bits 11-18
  int size2 = 0;

  /// Deserialize VP8 RTP payload from buffer
  /// RFC 7741 Section 4
  static Vp8RtpPayload deserialize(Uint8List buf) {
    final vp8 = Vp8RtpPayload();
    var offset = 0;

    if (buf.isEmpty) {
      vp8.payload = Uint8List(0);
      return vp8;
    }

    // Parse required RTP payload descriptor (1 byte minimum)
    // Bit layout: X|R|N|S|R|PID|PID|PID
    vp8.xBit = getBit(buf[offset], 0, 1);
    vp8.nBit = getBit(buf[offset], 2, 1);
    vp8.sBit = getBit(buf[offset], 3, 1);
    vp8.pid = getBit(buf[offset], 5, 3);
    offset++;

    // Parse extended control bits if X=1
    if (vp8.xBit == 1) {
      if (offset >= buf.length) {
        vp8.payload = Uint8List(0);
        return vp8;
      }

      // Bit layout: I|L|T|K|RSV|RSV|RSV|RSV
      vp8.iBit = getBit(buf[offset], 0, 1);
      vp8.lBit = getBit(buf[offset], 1, 1);
      vp8.tBit = getBit(buf[offset], 2, 1);
      vp8.kBit = getBit(buf[offset], 3, 1);
      offset++;
    }

    // Parse Picture ID if I=1
    if (vp8.iBit == 1) {
      if (offset >= buf.length) {
        vp8.payload = Uint8List(0);
        return vp8;
      }

      // Check M bit to determine 7-bit or 15-bit mode
      vp8.mBit = getBit(buf[offset], 0, 1);

      if (vp8.mBit == 1) {
        // 15-bit extended picture ID
        if (offset + 1 >= buf.length) {
          vp8.payload = Uint8List(0);
          return vp8;
        }

        final highBits = paddingByte(getBit(buf[offset], 1, 7));
        final lowBits = paddingByte(buf[offset + 1]);
        vp8.pictureId = int.parse(highBits + lowBits, radix: 2);
        offset += 2;
      } else {
        // 7-bit picture ID
        vp8.pictureId = getBit(buf[offset], 1, 7);
        offset++;
      }
    }

    // Skip TL0PICIDX if L=1
    if (vp8.lBit == 1) {
      if (offset >= buf.length) {
        vp8.payload = Uint8List(0);
        return vp8;
      }
      offset++;
    }

    // Skip TID/KEYIDX if T=1 or K=1
    if (vp8.lBit == 1 || vp8.kBit == 1) {
      if (offset >= buf.length) {
        vp8.payload = Uint8List(0);
        return vp8;
      }
      offset++;
    }

    // Extract VP8 payload
    vp8.payload = buf.sublist(offset);

    // Parse VP8 payload header if this is the start of a partition (S=1 && PID=0)
    if (vp8.payloadHeaderExist && vp8.payload.length >= 3) {
      final payloadOffset = offset;

      // First byte: SIZE0 (3 bits) | H | VER (3 bits) | P
      vp8.size0 = getBit(buf[payloadOffset], 0, 3);
      vp8.hBit = getBit(buf[payloadOffset], 3, 1);
      vp8.ver = getBit(buf[payloadOffset], 4, 3);
      vp8.pBit = getBit(buf[payloadOffset], 7, 1);

      // Second byte: SIZE1 (8 bits)
      vp8.size1 = buf[payloadOffset + 1];

      // Third byte: SIZE2 (8 bits)
      vp8.size2 = buf[payloadOffset + 2];
    }

    return vp8;
  }

  /// Check if this is a keyframe
  /// P bit = 0 indicates keyframe
  bool get isKeyframe => pBit == 0;

  /// Check if this is the start of a partition
  /// S bit = 1 indicates partition head
  bool get isPartitionHead => sBit == 1;

  /// Check if VP8 payload header exists
  /// Only in first partition (S=1 && PID=0)
  bool get payloadHeaderExist => sBit == 1 && pid == 0;

  /// Calculate frame size from size fields
  /// size = size0 + (8 × size1) + (2048 × size2)
  int get frameSize {
    if (!payloadHeaderExist) return 0;
    return size0 + (8 * size1) + (2048 * size2);
  }

  @override
  String toString() {
    return 'Vp8RtpPayload(size=${payload.length}, '
        'keyframe=$isKeyframe, '
        'partitionHead=$isPartitionHead'
        '${pictureId != null ? ', pictureId=$pictureId' : ''})';
  }
}
