import 'dart:typed_data';

/// REMB (Receiver Estimated Max Bitrate)
/// RFC 5104 Section 4.2.2.1 (draft-alvestrand-rmcat-remb)
///
/// REMB is used to convey the receiver's estimated maximum bitrate
/// that it can receive. This is a payload-specific feedback (PSFB)
/// message with FMT=15.
///
/// REMB Packet Structure:
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |V=2|P| FMT=15  |   PT=206      |             length            |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                  SSRC of packet sender                        |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                  SSRC of media source                         |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |  Unique identifier 'R' 'E' 'M' 'B'                            |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |  Num SSRC     | BR Exp    |  BR Mantissa (18 bits)            |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |   SSRC feedback n                                             |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |  ...                                                          |

/// Receiver Estimated Max Bitrate packet
class ReceiverEstimatedMaxBitrate {
  /// PSFB FMT value for REMB
  static const int fmt = 15;

  /// Unique identifier string "REMB"
  static const String uniqueId = 'REMB';

  /// SSRC of the sender of this feedback
  final int senderSsrc;

  /// SSRC of the media source (usually 0 for REMB)
  final int mediaSsrc;

  /// Number of SSRCs in feedback list
  final int ssrcCount;

  /// Bitrate exponent (6 bits)
  final int brExp;

  /// Bitrate mantissa (18 bits)
  final int brMantissa;

  /// Estimated bitrate in bits per second
  final BigInt bitrate;

  /// List of SSRCs this REMB applies to
  final List<int> ssrcFeedbacks;

  ReceiverEstimatedMaxBitrate({
    required this.senderSsrc,
    this.mediaSsrc = 0,
    required this.ssrcCount,
    required this.brExp,
    required this.brMantissa,
    required this.bitrate,
    this.ssrcFeedbacks = const [],
  });

  /// Create REMB from a bitrate value
  factory ReceiverEstimatedMaxBitrate.fromBitrate({
    required int senderSsrc,
    int mediaSsrc = 0,
    required BigInt bitrate,
    List<int> ssrcFeedbacks = const [],
  }) {
    // Calculate mantissa and exponent from bitrate
    // bitrate = mantissa * 2^exp
    // mantissa is 18 bits (max 262143)
    // exp is 6 bits (max 63)

    int brExp = 0;
    int brMantissa = 0;

    if (bitrate > BigInt.zero) {
      // Find the highest bit position
      var value = bitrate;

      // Shift right until mantissa fits in 18 bits
      while (value > BigInt.from(0x3FFFF)) {
        // 18 bits max
        value = value >> 1;
        brExp++;
      }

      brMantissa = value.toInt();

      // Clamp exponent to 6 bits
      if (brExp > 63) {
        brExp = 63;
        brMantissa = 0x3FFFF; // Max mantissa
      }
    }

    return ReceiverEstimatedMaxBitrate(
      senderSsrc: senderSsrc,
      mediaSsrc: mediaSsrc,
      ssrcCount: ssrcFeedbacks.length,
      brExp: brExp,
      brMantissa: brMantissa,
      bitrate: bitrate,
      ssrcFeedbacks: ssrcFeedbacks,
    );
  }

  /// Deserialize REMB from payload (after RTCP header)
  /// The payload should start with media SSRC
  factory ReceiverEstimatedMaxBitrate.deserialize(
    Uint8List data, {
    required int senderSsrc,
  }) {
    if (data.length < 12) {
      throw FormatException(
          'REMB payload too short: ${data.length} bytes, need at least 12');
    }

    final view = ByteData.sublistView(data);

    // Media SSRC (4 bytes)
    final mediaSsrc = view.getUint32(0);

    // Unique identifier "REMB" (4 bytes)
    final rembId = String.fromCharCodes(data.sublist(4, 8));
    if (rembId != uniqueId) {
      throw FormatException('Invalid REMB identifier: $rembId');
    }

    // Number of SSRCs (1 byte)
    final ssrcNum = data[8];

    // BR Exp (6 bits) + BR Mantissa high 2 bits
    final expMantissaByte = data[9];
    final brExp = (expMantissaByte >> 2) & 0x3F;
    final mantissaHigh = expMantissaByte & 0x03;

    // BR Mantissa low 16 bits
    final mantissaLow = (data[10] << 8) | data[11];
    final brMantissa = (mantissaHigh << 16) | mantissaLow;

    // Calculate bitrate: mantissa << exponent
    // Handle overflow for large exponents
    BigInt bitrate;
    if (brExp > 46) {
      bitrate = BigInt.parse('18446744073709551615'); // Max uint64
    } else {
      bitrate = BigInt.from(brMantissa) << brExp;
    }

    // Parse SSRC feedbacks
    final ssrcFeedbacks = <int>[];
    for (var i = 12; i + 4 <= data.length; i += 4) {
      final ssrc = view.getUint32(i);
      ssrcFeedbacks.add(ssrc);
    }

    return ReceiverEstimatedMaxBitrate(
      senderSsrc: senderSsrc,
      mediaSsrc: mediaSsrc,
      ssrcCount: ssrcNum,
      brExp: brExp,
      brMantissa: brMantissa,
      bitrate: bitrate,
      ssrcFeedbacks: ssrcFeedbacks,
    );
  }

  /// Serialize REMB FCI (Feedback Control Information)
  /// Returns payload after RTCP header (media SSRC + REMB data)
  Uint8List serialize() {
    // Calculate total size:
    // 4 (media SSRC) + 4 (REMB) + 1 (num SSRC) + 3 (exp+mantissa) + 4*N (SSRCs)
    final totalSize = 12 + (ssrcFeedbacks.length * 4);
    final buffer = Uint8List(totalSize);
    final view = ByteData.sublistView(buffer);

    // Media SSRC
    view.setUint32(0, mediaSsrc);

    // "REMB" identifier
    buffer[4] = 0x52; // 'R'
    buffer[5] = 0x45; // 'E'
    buffer[6] = 0x4D; // 'M'
    buffer[7] = 0x42; // 'B'

    // Number of SSRCs
    buffer[8] = ssrcFeedbacks.length;

    // BR Exp (6 bits) + BR Mantissa high 2 bits
    buffer[9] = ((brExp & 0x3F) << 2) | ((brMantissa >> 16) & 0x03);

    // BR Mantissa low 16 bits
    buffer[10] = (brMantissa >> 8) & 0xFF;
    buffer[11] = brMantissa & 0xFF;

    // SSRC feedbacks
    var offset = 12;
    for (final ssrc in ssrcFeedbacks) {
      view.setUint32(offset, ssrc);
      offset += 4;
    }

    return buffer;
  }

  /// Get bitrate as integer (may overflow for very large values)
  int get bitrateInt {
    if (bitrate > BigInt.from(0x7FFFFFFFFFFFFFFF)) {
      return 0x7FFFFFFFFFFFFFFF; // Max int64
    }
    return bitrate.toInt();
  }

  /// Get bitrate in kbps
  double get bitrateKbps => bitrateInt / 1000.0;

  /// Get bitrate in Mbps
  double get bitrateMbps => bitrateInt / 1000000.0;

  @override
  String toString() {
    return 'ReceiverEstimatedMaxBitrate('
        'senderSsrc=$senderSsrc, '
        'mediaSsrc=$mediaSsrc, '
        'bitrate=${bitrateMbps.toStringAsFixed(2)} Mbps, '
        'ssrcs=$ssrcFeedbacks)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReceiverEstimatedMaxBitrate &&
          runtimeType == other.runtimeType &&
          senderSsrc == other.senderSsrc &&
          mediaSsrc == other.mediaSsrc &&
          brExp == other.brExp &&
          brMantissa == other.brMantissa &&
          _listEquals(ssrcFeedbacks, other.ssrcFeedbacks);

  @override
  int get hashCode =>
      senderSsrc.hashCode ^
      mediaSsrc.hashCode ^
      brExp.hashCode ^
      brMantissa.hashCode ^
      _listHashCode(ssrcFeedbacks);

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static int _listHashCode(List<int> list) {
    var hash = 0;
    for (final item in list) {
      hash = (hash * 31 + item.hashCode) & 0x7FFFFFFF;
    }
    return hash;
  }
}
