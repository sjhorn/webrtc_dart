import 'dart:typed_data';
import '../srtp/rtp_packet.dart';

/// RTX (Retransmission) Payload Format
/// RFC 4588 - RTP Retransmission Payload Format
///
/// RTX packets encapsulate the original RTP packet with a different SSRC
/// and payload type. The original sequence number (OSN) is prepended to
/// the original payload.
///
/// RTX Payload Format:
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                         RTP Header                            |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |            OSN                |                               |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+                               |
/// |                  Original RTP Payload                         |
/// |                                                               |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

/// RTX Handler for wrapping and unwrapping retransmission packets
class RtxHandler {
  /// RTX payload type
  final int rtxPayloadType;

  /// RTX SSRC (separate from original stream)
  final int rtxSsrc;

  /// RTX sequence number counter (separate sequence space)
  int rtxSequenceNumber;

  RtxHandler({
    required this.rtxPayloadType,
    required this.rtxSsrc,
    this.rtxSequenceNumber = 0,
  });

  /// Wrap an RTP packet as an RTX packet
  /// Returns a new RTP packet with RTX header and OSN prepended to payload
  RtpPacket wrapRtx(RtpPacket original) {
    // Prepend OSN (Original Sequence Number) to payload
    final osnBytes = Uint8List(2);
    final osnView = ByteData.sublistView(osnBytes);
    osnView.setUint16(0, original.sequenceNumber);

    final rtxPayload = Uint8List(2 + original.payload.length);
    rtxPayload.setRange(0, 2, osnBytes);
    rtxPayload.setRange(2, rtxPayload.length, original.payload);

    // Create RTX packet with separate SSRC and sequence number
    final rtxPacket = RtpPacket(
      version: original.version,
      padding: original.padding,
      extension: original.extension,
      marker: original.marker,
      payloadType: rtxPayloadType, // RTX payload type
      sequenceNumber: rtxSequenceNumber, // RTX sequence number
      timestamp: original.timestamp, // Preserved from original
      ssrc: rtxSsrc, // RTX SSRC
      csrcs: original.csrcs, // Preserved from original
      extensionHeader: original.extensionHeader, // Preserved from original
      payload: rtxPayload,
      paddingLength: original.paddingLength,
    );

    // Increment RTX sequence number
    rtxSequenceNumber = uint16Add(rtxSequenceNumber, 1);

    return rtxPacket;
  }

  /// Unwrap an RTX packet to restore the original RTP packet
  /// Extracts OSN from payload and restores original SSRC and payload type
  static RtpPacket unwrapRtx(
    RtpPacket rtx,
    int originalPayloadType,
    int originalSsrc,
  ) {
    if (rtx.payload.length < 2) {
      throw FormatException('RTX payload too short: ${rtx.payload.length}');
    }

    // Extract OSN from first 2 bytes
    final osnView = ByteData.sublistView(rtx.payload);
    final osn = osnView.getUint16(0);

    // Extract original payload (skip 2-byte OSN)
    final originalPayload = rtx.payload.sublist(2);

    return RtpPacket(
      version: rtx.version,
      padding: rtx.padding,
      extension: rtx.extension,
      marker: rtx.marker,
      payloadType: originalPayloadType, // Restore original payload type
      sequenceNumber: osn, // Restore original sequence number
      timestamp: rtx.timestamp, // Preserved in RTX
      ssrc: originalSsrc, // Restore original SSRC
      csrcs: rtx.csrcs,
      extensionHeader: rtx.extensionHeader,
      payload: originalPayload,
      paddingLength: rtx.paddingLength,
    );
  }
}

/// Uint16 addition with wraparound
int uint16Add(int a, int b) => (a + b) & 0xFFFF;

/// Uint16 greater-than comparison with wraparound handling
/// Uses "half modulo" comparison to handle sequence number rollover
bool uint16Gt(int a, int b) {
  const halfMod = 0x8000; // 32768
  return (a < b && b - a > halfMod) || (a > b && a - b < halfMod);
}

/// Uint16 less-than comparison with wraparound handling
bool uint16Lt(int a, int b) => uint16Gt(b, a);
