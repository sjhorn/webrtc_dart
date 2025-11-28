import 'dart:typed_data';
import '../common/binary.dart';

/// VP9 RTP Payload
/// draft-ietf-payload-vp9-16 - RTP Payload Format for VP9 Video
///
/// This implementation handles RTP payload depacketization for VP9 video frames
/// with support for Scalable Video Coding (SVC), flexible mode, and temporal/spatial layers.
/// Actual video encoding/decoding should be done by external tools
/// (e.g., FFmpeg, libvpx) or platform-specific codecs.
class Vp9RtpPayload {
  // Core header flags
  /// Picture ID present flag
  int iBit = 0;

  /// Inter-picture predicted frame (0 = keyframe, 1 = P-frame)
  int pBit = 0;

  /// Layer indices present flag
  int lBit = 0;

  /// Flexible mode (1 = flexible, 0 = non-flexible)
  int fBit = 0;

  /// Start of a frame flag
  int bBit = 0;

  /// End of a frame flag
  int eBit = 0;

  /// Scalability structure (SS) present flag
  int vBit = 0;

  /// Not used for inter-layer prediction flag
  int zBit = 0;

  // Picture identification
  /// Extended PictureID bit (0 = 7-bit, 1 = 15-bit)
  int? m;

  /// Picture ID (7-bit or 15-bit)
  int? pictureId;

  // Layer indices
  /// Temporal ID (3 bits) - temporal layer index (0-7)
  int? tid;

  /// Switching up point flag
  int? u;

  /// Spatial ID (3 bits) - spatial layer index (0-7)
  int? sid;

  /// Inter-layer dependency flag
  int? d;

  /// Temporal layer 0 picture index (non-flexible mode only)
  int? tl0PicIdx;

  // Flexible mode reference indices
  /// Reference picture differences (P_DIFF array)
  final List<int> pDiff = [];

  // Scalability structure (SS) fields
  /// Number of spatial layers minus 1 (3 bits)
  int? nS;

  /// Resolution present flag
  int? y;

  /// Picture group descriptions present flag
  int? g;

  /// Resolution widths (16-bit values, N_S+1 entries)
  final List<int> width = [];

  /// Resolution heights (16-bit values, N_S+1 entries)
  final List<int> height = [];

  /// Number of picture groups
  int nG = 0;

  /// Temporal layer ID for each picture group
  final List<int> pgT = [];

  /// Switching up point for each picture group
  final List<int> pgU = [];

  /// Reference indices for each picture group
  final List<List<int>> pgPDiff = [];

  /// VP9 payload data
  late Uint8List payload;

  /// Deserialize VP9 RTP payload from buffer
  /// draft-ietf-payload-vp9 Section 4
  static Vp9RtpPayload deserialize(Uint8List buf) {
    final result = _parseRtpPayload(buf);
    result.vp9.payload = buf.sublist(result.offset);
    return result.vp9;
  }

  /// Parse VP9 RTP payload header
  static ({Vp9RtpPayload vp9, int offset}) _parseRtpPayload(Uint8List buf) {
    final vp9 = Vp9RtpPayload();
    var offset = 0;

    if (buf.isEmpty) {
      return (vp9: vp9, offset: 0);
    }

    // Parse required header byte (I P L F B E V Z)
    vp9.iBit = getBit(buf[offset], 0, 1);
    vp9.pBit = getBit(buf[offset], 1, 1);
    vp9.lBit = getBit(buf[offset], 2, 1);
    vp9.fBit = getBit(buf[offset], 3, 1);
    vp9.bBit = getBit(buf[offset], 4, 1);
    vp9.eBit = getBit(buf[offset], 5, 1);
    vp9.vBit = getBit(buf[offset], 6, 1);
    vp9.zBit = getBit(buf[offset], 7, 1);
    offset++;

    // Parse Picture ID if I-bit is set
    if (vp9.iBit == 1) {
      if (offset >= buf.length) {
        return (vp9: vp9, offset: offset);
      }

      vp9.m = getBit(buf[offset], 0, 1);

      if (vp9.m == 1) {
        // 15-bit extended picture ID
        if (offset + 1 >= buf.length) {
          return (vp9: vp9, offset: offset);
        }

        final highBits = paddingByte(getBit(buf[offset], 1, 7));
        final lowBits = paddingByte(buf[offset + 1]);
        vp9.pictureId = int.parse(highBits + lowBits, radix: 2);
        offset += 2;
      } else {
        // 7-bit picture ID
        vp9.pictureId = getBit(buf[offset], 1, 7);
        offset++;
      }
    }

    // Parse layer indices if L-bit is set
    if (vp9.lBit == 1) {
      if (offset >= buf.length) {
        return (vp9: vp9, offset: offset);
      }

      vp9.tid = getBit(buf[offset], 0, 3);
      vp9.u = getBit(buf[offset], 3, 1);
      vp9.sid = getBit(buf[offset], 4, 3);
      vp9.d = getBit(buf[offset], 7, 1);
      offset++;

      // TL0PICIDX only in non-flexible mode
      if (vp9.fBit == 0) {
        if (offset >= buf.length) {
          return (vp9: vp9, offset: offset);
        }
        vp9.tl0PicIdx = buf[offset];
        offset++;
      }
    }

    // Parse reference indices in flexible mode for P-frames
    if (vp9.fBit == 1 && vp9.pBit == 1) {
      while (offset < buf.length) {
        final pDiffValue = getBit(buf[offset], 0, 7);
        final n = getBit(buf[offset], 7, 1);
        vp9.pDiff.add(pDiffValue);
        offset++;

        if (n == 0) break; // Last reference
      }
    }

    // Parse scalability structure if V-bit is set
    if (vp9.vBit == 1) {
      if (offset >= buf.length) {
        return (vp9: vp9, offset: offset);
      }

      // Parse SS header
      vp9.nS = getBit(buf[offset], 0, 3);
      vp9.y = getBit(buf[offset], 3, 1);
      vp9.g = getBit(buf[offset], 4, 1);
      offset++;

      // Parse resolutions if Y-bit is set
      if (vp9.y == 1) {
        final numLayers = (vp9.nS ?? 0) + 1;
        for (var i = 0; i < numLayers; i++) {
          if (offset + 3 >= buf.length) {
            return (vp9: vp9, offset: offset);
          }

          final view = ByteData.sublistView(buf);
          vp9.width.add(view.getUint16(offset, Endian.big));
          offset += 2;
          vp9.height.add(view.getUint16(offset, Endian.big));
          offset += 2;
        }
      }

      // Parse picture group descriptions if G-bit is set
      if (vp9.g == 1) {
        if (offset >= buf.length) {
          return (vp9: vp9, offset: offset);
        }

        vp9.nG = buf[offset];
        offset++;
      }

      // Parse each picture group
      if (vp9.nG > 0) {
        for (var i = 0; i < vp9.nG; i++) {
          if (offset >= buf.length) {
            return (vp9: vp9, offset: offset);
          }

          vp9.pgT.add(getBit(buf[offset], 0, 3));
          vp9.pgU.add(getBit(buf[offset], 3, 1));
          final r = getBit(buf[offset], 4, 2); // Reference count
          offset++;

          // Parse reference indices for this picture group
          vp9.pgPDiff.add([]);
          if (r > 0) {
            for (var j = 0; j < r; j++) {
              if (offset >= buf.length) {
                return (vp9: vp9, offset: offset);
              }
              vp9.pgPDiff[i].add(buf[offset]);
              offset++;
            }
          }
        }
      }
    }

    return (vp9: vp9, offset: offset);
  }

  /// Check if this is a keyframe
  /// Must be intra-predicted (pBit=0), start of frame (bBit=1),
  /// and base spatial layer (sid=0) or no layer info (lBit=0)
  bool get isKeyframe {
    return pBit == 0 &&
        bBit == 1 &&
        (lBit == 0 || (sid != null && sid == 0));
  }

  /// Check if this is the start of a partition
  /// Must be start of frame and either no layer info or not inter-layer predicted
  bool get isPartitionHead {
    return bBit == 1 && (lBit == 0 || (d != null && d == 0));
  }

  @override
  String toString() {
    final parts = <String>[
      'Vp9RtpPayload(size=${payload.length}',
      'keyframe=$isKeyframe',
      'partitionHead=$isPartitionHead',
    ];

    if (pictureId != null) parts.add('pictureId=$pictureId');
    if (tid != null) parts.add('tid=$tid');
    if (sid != null) parts.add('sid=$sid');
    if (pDiff.isNotEmpty) parts.add('pDiff=$pDiff');
    if (nS != null) parts.add('spatialLayers=${(nS ?? 0) + 1}');

    return '${parts.join(', ')})';
  }
}
