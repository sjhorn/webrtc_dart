import 'dart:typed_data';
import '../common/binary.dart';

/// H.264 RTP Payload
/// RFC 6184 - RTP Payload Format for H.264 Video
///
/// This implementation handles RTP payload depacketization for H.264 video frames.
/// Actual video encoding/decoding should be done by external tools
/// (e.g., FFmpeg, libavcodec) or platform-specific codecs.
///
/// NAL Unit Types:
/// - 1-23: Single NAL Unit packets
/// - 24 (STAP-A): Single-Time Aggregation Packet
/// - 28 (FU-A): Fragmentation Unit
class H264RtpPayload {
  /// Forbidden zero bit (should always be 0)
  int f = 0;

  /// NAL reference IDC (2 bits)
  /// Indicates importance of NAL unit (00 = not referenced, 11 = highest)
  int nri = 0;

  /// NAL unit type (5 bits: 1-23 = single, 24 = STAP-A, 28 = FU-A)
  int nalUnitType = 0;

  /// Start bit (FU-A only): indicates first fragment
  int s = 0;

  /// End bit (FU-A only): indicates last fragment
  int e = 0;

  /// Reserved bit (FU-A only)
  int r = 0;

  /// NAL unit payload type (used in FU-A fragments)
  int nalUnitPayloadType = 0;

  /// Depacketized NAL unit payload with Annex B start code (0x00000001)
  late Uint8List payload;

  /// Fragment buffer for FU-A reassembly
  Uint8List? fragment;

  /// Deserialize H.264 RTP payload from buffer
  /// RFC 6184 Section 5
  ///
  /// [buf] - RTP payload data
  /// [fragment] - Previous fragment data (for FU-A reassembly)
  static H264RtpPayload deserialize(Uint8List buf, [Uint8List? fragment]) {
    final h264 = H264RtpPayload();
    var offset = 0;

    if (buf.isEmpty) {
      h264.payload = Uint8List(0);
      return h264;
    }

    // Parse NAL unit header (1 byte)
    // Bit layout: F|NRI|NRI|Type|Type|Type|Type|Type
    final naluHeader = buf[offset];
    h264.f = getBit(naluHeader, 0, 1);
    h264.nri = getBit(naluHeader, 1, 2);
    h264.nalUnitType = getBit(naluHeader, 3, 5);
    offset++;

    // Single NAL Unit Packet (types 1-23)
    // RFC 6184 Section 5.6
    if (h264.nalUnitType >= 1 && h264.nalUnitType <= 23) {
      h264.payload = _packaging(buf);
      return h264;
    }

    // Single-Time Aggregation Packet Type A (STAP-A, type 24)
    // RFC 6184 Section 5.7.1
    if (h264.nalUnitType == NalUnitType.stapA) {
      h264.payload = _parseStapA(buf);
      return h264;
    }

    // Fragmentation Unit A (FU-A, type 28)
    // RFC 6184 Section 5.8
    if (h264.nalUnitType == NalUnitType.fuA) {
      if (offset >= buf.length) {
        h264.payload = Uint8List(0);
        return h264;
      }

      // Parse FU header (1 byte)
      // Bit layout: S|E|R|Type|Type|Type|Type|Type
      final fuHeader = buf[offset];
      h264.s = getBit(fuHeader, 0, 1);
      h264.e = getBit(fuHeader, 1, 1);
      h264.r = getBit(fuHeader, 2, 1);
      h264.nalUnitPayloadType = getBit(fuHeader, 3, 5);
      offset++;

      // Append fragment data
      final fu = buf.sublist(offset);
      final previousFragment = fragment ?? Uint8List(0);
      h264.fragment = Uint8List(previousFragment.length + fu.length)
        ..setAll(0, previousFragment)
        ..setAll(previousFragment.length, fu);

      // If end bit is set, reassemble complete NAL unit
      if (h264.e == 1) {
        // Reconstruct NAL header from FU indicator and FU header
        final nalHeader =
            (h264.f << 7) | (h264.nri << 5) | h264.nalUnitPayloadType;

        // Create complete NAL unit: NAL header + fragment data
        final nalu = Uint8List(1 + h264.fragment!.length)
          ..[0] = nalHeader
          ..setAll(1, h264.fragment!);

        h264.fragment = null;
        h264.payload = _packaging(nalu);
      } else {
        // Fragment is incomplete, return empty payload
        h264.payload = Uint8List(0);
      }

      return h264;
    }

    // Unsupported NAL unit type
    h264.payload = Uint8List(0);
    return h264;
  }

  /// Parse STAP-A (Single-Time Aggregation Packet)
  /// RFC 6184 Section 5.7.1
  ///
  /// Format: [STAP-A header] [NAL size (2 bytes)] [NAL unit] [NAL size] [NAL unit] ...
  static Uint8List _parseStapA(Uint8List buf) {
    var offset = 1; // Skip STAP-A header
    final nalUnits = <Uint8List>[];

    while (offset + 2 <= buf.length) {
      // Read NAL unit size (2 bytes, big-endian)
      final naluSize = ByteData.sublistView(buf, offset).getUint16(0);
      offset += 2;

      if (offset + naluSize > buf.length) {
        break; // Malformed packet
      }

      // Extract and package NAL unit
      final nalu = buf.sublist(offset, offset + naluSize);
      nalUnits.add(_packaging(nalu));
      offset += naluSize;
    }

    // Concatenate all NAL units
    if (nalUnits.isEmpty) {
      return Uint8List(0);
    }

    final totalLength = nalUnits.fold(0, (sum, nalu) => sum + nalu.length);
    final result = Uint8List(totalLength);
    var resultOffset = 0;
    for (final nalu in nalUnits) {
      result.setAll(resultOffset, nalu);
      resultOffset += nalu.length;
    }

    return result;
  }

  /// Add Annex B start code (0x00 0x00 0x00 0x01) to NAL unit
  /// This is the standard framing for H.264 bitstreams
  static Uint8List _packaging(Uint8List buf) {
    const startCode = [0x00, 0x00, 0x00, 0x01];
    return Uint8List(startCode.length + buf.length)
      ..setAll(0, startCode)
      ..setAll(startCode.length, buf);
  }

  /// Check if this is a keyframe (IDR slice)
  /// NAL type 5 indicates an IDR (Instantaneous Decoder Refresh) frame
  bool get isKeyframe {
    return nalUnitType == NalUnitType.idrSlice ||
        nalUnitPayloadType == NalUnitType.idrSlice;
  }

  /// Check if this is the start of a partition
  /// For FU-A/FU-B, check the S (start) bit
  /// For other types, always true (single NAL unit or STAP-A)
  bool get isPartitionHead {
    if (nalUnitType == NalUnitType.fuA || nalUnitType == NalUnitType.fuB) {
      return s != 0;
    }
    return true;
  }

  @override
  String toString() {
    return 'H264RtpPayload(type=$nalUnitType, nri=$nri, '
        'keyframe=$isKeyframe, payloadSize=${payload.length})';
  }
}

/// NAL Unit Type constants
/// RFC 6184 Section 5.4
class NalUnitType {
  /// IDR (Instantaneous Decoder Refresh) coded slice - keyframe
  static const int idrSlice = 5;

  /// Single-Time Aggregation Packet Type A
  static const int stapA = 24;

  /// Single-Time Aggregation Packet Type B
  static const int stapB = 25;

  /// Multi-Time Aggregation Packet 16-bit offset
  static const int mtap16 = 26;

  /// Multi-Time Aggregation Packet 24-bit offset
  static const int mtap24 = 27;

  /// Fragmentation Unit A
  static const int fuA = 28;

  /// Fragmentation Unit B
  static const int fuB = 29;
}
