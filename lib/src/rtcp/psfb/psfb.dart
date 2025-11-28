import 'dart:typed_data';
import '../../srtp/rtcp_packet.dart';
import 'pli.dart';
import 'fir.dart';

/// Payload-Specific Feedback Message Types
/// RFC 4585 and RFC 5104
enum PayloadFeedbackType {
  pli(PictureLossIndication.fmt),
  fir(FullIntraRequest.fmt);

  final int value;
  const PayloadFeedbackType(this.value);

  static PayloadFeedbackType? fromValue(int value) {
    for (final type in values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// Payload-Specific Feedback Message (PSFB)
/// RFC 4585 Section 6.3
///
/// PSFB is used for codec control messages like PLI and FIR.
/// Packet type is 206 (payloadFeedback), with FMT field indicating specific type.
///
/// PSFB Packet Structure:
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |V=2|P|  FMT    |   PT=206      |             length            |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                    Sender SSRC (32 bits)                      |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                     Media SSRC (32 bits)                      |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                   FCI (Feedback Control Information)          |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
class PayloadSpecificFeedback {
  /// Feedback message (PLI or FIR)
  final Object feedback;

  const PayloadSpecificFeedback(this.feedback);

  /// Create PLI feedback
  factory PayloadSpecificFeedback.pli({
    required int senderSsrc,
    required int mediaSsrc,
  }) {
    return PayloadSpecificFeedback(
      PictureLossIndication(
        senderSsrc: senderSsrc,
        mediaSsrc: mediaSsrc,
      ),
    );
  }

  /// Create FIR feedback
  factory PayloadSpecificFeedback.fir({
    required int senderSsrc,
    required int mediaSsrc,
    List<FirEntry> entries = const [],
  }) {
    return PayloadSpecificFeedback(
      FullIntraRequest(
        senderSsrc: senderSsrc,
        mediaSsrc: mediaSsrc,
        entries: entries,
      ),
    );
  }

  /// Get feedback type
  PayloadFeedbackType get type {
    if (feedback is PictureLossIndication) {
      return PayloadFeedbackType.pli;
    } else if (feedback is FullIntraRequest) {
      return PayloadFeedbackType.fir;
    }
    throw StateError('Unknown feedback type: ${feedback.runtimeType}');
  }

  /// Get FMT value
  int get fmt {
    if (feedback is PictureLossIndication) {
      return PictureLossIndication.fmt;
    } else if (feedback is FullIntraRequest) {
      return FullIntraRequest.fmt;
    }
    throw StateError('Unknown feedback type: ${feedback.runtimeType}');
  }

  /// Serialize PSFB to RTCP packet
  RtcpPacket toRtcpPacket() {
    final payload = serialize();

    // Calculate length in 32-bit words minus one
    // Header (8 bytes) + FCI payload
    final totalSize = 8 + payload.length;
    final length = (totalSize ~/ 4) - 1;

    // Get sender SSRC from feedback
    final senderSsrc = feedback is PictureLossIndication
        ? (feedback as PictureLossIndication).senderSsrc
        : (feedback as FullIntraRequest).senderSsrc;

    return RtcpPacket(
      version: 2,
      padding: false,
      reportCount: fmt, // FMT field in payload feedback
      packetType: RtcpPacketType.payloadFeedback,
      length: length,
      ssrc: senderSsrc,
      payload: payload,
    );
  }

  /// Serialize FCI (Feedback Control Information)
  /// Returns the payload after the RTCP header (media SSRC + type-specific data)
  Uint8List serialize() {
    if (feedback is PictureLossIndication) {
      return (feedback as PictureLossIndication).serialize();
    } else if (feedback is FullIntraRequest) {
      return (feedback as FullIntraRequest).serialize();
    }
    throw StateError('Unknown feedback type: ${feedback.runtimeType}');
  }

  /// Deserialize PSFB from RTCP packet
  static PayloadSpecificFeedback deserialize(RtcpPacket packet) {
    if (packet.packetType != RtcpPacketType.payloadFeedback) {
      throw FormatException('Not a payload feedback packet');
    }

    final fmt = packet.reportCount;
    final data = packet.payload;

    switch (fmt) {
      case PictureLossIndication.fmt:
        final pli = PictureLossIndication.deserialize(data);
        return PayloadSpecificFeedback(pli);

      case FullIntraRequest.fmt:
        final fir = FullIntraRequest.deserialize(data);
        return PayloadSpecificFeedback(fir);

      default:
        throw FormatException('Unknown PSFB FMT: $fmt');
    }
  }

  @override
  String toString() {
    return 'PayloadSpecificFeedback($feedback)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PayloadSpecificFeedback &&
          runtimeType == other.runtimeType &&
          feedback == other.feedback;

  @override
  int get hashCode => feedback.hashCode;
}

/// Create a compound RTCP packet containing PLI
RtcpCompoundPacket createPliPacket({
  required int senderSsrc,
  required int mediaSsrc,
}) {
  final psfb = PayloadSpecificFeedback.pli(
    senderSsrc: senderSsrc,
    mediaSsrc: mediaSsrc,
  );

  return RtcpCompoundPacket([psfb.toRtcpPacket()]);
}

/// Create a compound RTCP packet containing FIR
RtcpCompoundPacket createFirPacket({
  required int senderSsrc,
  required int mediaSsrc,
  List<FirEntry> entries = const [],
}) {
  final psfb = PayloadSpecificFeedback.fir(
    senderSsrc: senderSsrc,
    mediaSsrc: mediaSsrc,
    entries: entries,
  );

  return RtcpCompoundPacket([psfb.toRtcpPacket()]);
}
