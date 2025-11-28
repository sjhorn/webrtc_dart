import 'dart:typed_data';

/// TURN ChannelData format (RFC 5766)
///
/// More efficient format for sending data through TURN than Send/Data indications
///
/// Format:
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |         Channel Number        |            Length             |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                       Application Data                        |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

/// Channel number range for TURN
const int channelNumberMin = 0x4000;
const int channelNumberMax = 0x7FFF;

/// ChannelData header length (4 bytes)
const int channelDataHeaderLength = 4;

/// ChannelData message
class ChannelData {
  /// Channel number (0x4000-0x7FFF)
  final int channelNumber;

  /// Application data
  final Uint8List data;

  ChannelData({
    required this.channelNumber,
    required this.data,
  }) {
    if (channelNumber < channelNumberMin || channelNumber > channelNumberMax) {
      throw ArgumentError(
        'Channel number must be in range 0x4000-0x7FFF, got: 0x${channelNumber.toRadixString(16)}'
      );
    }
  }

  /// Check if data starts with ChannelData header
  /// Detection: (data[0] & 0xC0) == 0x40
  static bool isChannelData(Uint8List data) {
    if (data.length < channelDataHeaderLength) {
      return false;
    }
    return (data[0] & 0xC0) == 0x40;
  }

  /// Encode ChannelData to bytes
  Uint8List encode() {
    final buffer = ByteData(channelDataHeaderLength);
    buffer.setUint16(0, channelNumber);
    buffer.setUint16(2, data.length);

    final result = Uint8List(channelDataHeaderLength + data.length);
    result.setAll(0, buffer.buffer.asUint8List());
    result.setAll(channelDataHeaderLength, data);

    return result;
  }

  /// Decode ChannelData from bytes
  static ChannelData decode(Uint8List data) {
    if (data.length < channelDataHeaderLength) {
      throw ArgumentError(
        'ChannelData too short: ${data.length} bytes, expected at least $channelDataHeaderLength'
      );
    }

    final buffer = ByteData.view(data.buffer, data.offsetInBytes);
    final channelNumber = buffer.getUint16(0);
    final length = buffer.getUint16(2);

    if (channelNumber < channelNumberMin || channelNumber > channelNumberMax) {
      throw ArgumentError(
        'Invalid channel number: 0x${channelNumber.toRadixString(16)}'
      );
    }

    if (data.length < channelDataHeaderLength + length) {
      throw ArgumentError(
        'ChannelData incomplete: got ${data.length} bytes, expected ${channelDataHeaderLength + length}'
      );
    }

    final appData = data.sublist(channelDataHeaderLength, channelDataHeaderLength + length);

    return ChannelData(
      channelNumber: channelNumber,
      data: appData,
    );
  }

  @override
  String toString() {
    return 'ChannelData(channel: 0x${channelNumber.toRadixString(16)}, length: ${data.length})';
  }
}
