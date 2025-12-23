import 'dart:convert';
import 'dart:typed_data';

/// RTP Header Extension URIs
/// Based on werift-webrtc headerExtension.ts
class RtpExtensionUri {
  /// Mid (Media ID) - RFC 8843
  static const sdesMid = 'urn:ietf:params:rtp-hdrext:sdes:mid';

  /// RTP Stream ID (RID) - RFC 8851
  static const sdesRtpStreamId =
      'urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id';

  /// Repaired RTP Stream ID - RFC 8851
  static const repairedRtpStreamId =
      'urn:ietf:params:rtp-hdrext:sdes:repaired-rtp-stream-id';

  /// Transport-Wide Congestion Control
  static const transportWideCC =
      'http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01';

  /// Audio Level - RFC 6464
  static const ssrcAudioLevel = 'urn:ietf:params:rtp-hdrext:ssrc-audio-level';

  /// Client-to-Mixer Audio Level - RFC 6465
  static const csrcAudioLevel = 'urn:ietf:params:rtp-hdrext:csrc-audio-level';

  /// Absolute Send Time - Google
  static const absoluteSendTime =
      'http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time';

  /// Transmission Time Offset - RFC 5450
  static const transmissionTimeOffset = 'urn:ietf:params:rtp-hdrext:toffset';

  /// Video Orientation - RFC 7742
  static const videoOrientation = 'urn:3gpp:video-orientation';

  /// Dependency Descriptor - Google/AV1
  static const dependencyDescriptor =
      'https://aomediacodec.github.io/av1-rtp-spec/#dependency-descriptor-rtp-header-extension';
}

/// Serialize SDES MID header extension
Uint8List serializeSdesMid(String mid) {
  return Uint8List.fromList(utf8.encode(mid));
}

/// Deserialize SDES MID header extension
String deserializeSdesMid(Uint8List data) {
  return utf8.decode(data);
}

/// Serialize SDES RTP Stream ID (RID) header extension
Uint8List serializeSdesRtpStreamId(String rid) {
  return Uint8List.fromList(utf8.encode(rid));
}

/// Deserialize SDES RTP Stream ID (RID) header extension
String deserializeSdesRtpStreamId(Uint8List data) {
  return utf8.decode(data);
}

/// Serialize Repaired RTP Stream ID header extension
Uint8List serializeRepairedRtpStreamId(String rid) {
  return Uint8List.fromList(utf8.encode(rid));
}

/// Deserialize Repaired RTP Stream ID header extension
String deserializeRepairedRtpStreamId(Uint8List data) {
  return utf8.decode(data);
}

/// Serialize Transport-Wide CC sequence number (uint16)
Uint8List serializeTransportWideCC(int sequenceNumber) {
  final buf = Uint8List(2);
  final view = ByteData.sublistView(buf);
  view.setUint16(0, sequenceNumber & 0xFFFF);
  return buf;
}

/// Deserialize Transport-Wide CC sequence number (uint16)
int deserializeTransportWideCC(Uint8List data) {
  if (data.length < 2) return 0;
  final view = ByteData.sublistView(data);
  return view.getUint16(0);
}

/// Deserialize uint16 big-endian (generic helper)
int deserializeUint16BE(Uint8List data) {
  if (data.length < 2) return 0;
  final view = ByteData.sublistView(data);
  return view.getUint16(0);
}

/// Serialize Audio Level (RFC 6464)
/// Format: V bit (1) + level (7 bits)
Uint8List serializeAudioLevel({required bool voice, required int level}) {
  final value = ((voice ? 1 : 0) << 7) | (level & 0x7F);
  return Uint8List.fromList([value]);
}

/// Deserialize Audio Level (RFC 6464)
({bool voice, int level}) deserializeAudioLevel(Uint8List data) {
  if (data.isEmpty) return (voice: false, level: 0);
  final value = data[0];
  return (
    voice: (value >> 7) == 1,
    level: value & 0x7F,
  );
}

/// Serialize Absolute Send Time (24-bit, 6.18 fixed point seconds)
/// Takes a pre-converted 24-bit timestamp value.
Uint8List serializeAbsoluteSendTime(int timestamp24bit) {
  return Uint8List.fromList([
    (timestamp24bit >> 16) & 0xFF,
    (timestamp24bit >> 8) & 0xFF,
    timestamp24bit & 0xFF,
  ]);
}

/// Deserialize Absolute Send Time (24-bit)
int deserializeAbsoluteSendTime(Uint8List data) {
  if (data.length < 3) return 0;
  return (data[0] << 16) | (data[1] << 8) | data[2];
}

/// NTP epoch: January 1, 1900, 00:00:00 UTC
/// Unix epoch: January 1, 1970, 00:00:00 UTC
/// Difference in seconds: 2208988800
const int _ntpUnixEpochDiff = 2208988800;

/// Get current NTP time as a 64-bit value.
///
/// Returns NTP timestamp where:
/// - Upper 32 bits: seconds since 1900
/// - Lower 32 bits: fractional seconds
///
/// Matches werift-webrtc utils.ts:ntpTime behavior.
int ntpTime() {
  final now = DateTime.now().microsecondsSinceEpoch;
  final seconds = now ~/ 1000000;
  final micros = now % 1000000;

  // Convert Unix epoch to NTP epoch
  final ntpSeconds = seconds + _ntpUnixEpochDiff;

  // Convert microseconds to NTP fractional seconds (2^32 / 10^6)
  // fraction = micros * 4294967296 / 1000000 = micros * 4294.967296
  final ntpFraction = (micros * 4294967296) ~/ 1000000;

  return (ntpSeconds << 32) | (ntpFraction & 0xFFFFFFFF);
}

/// Serialize Absolute Send Time from NTP timestamp.
///
/// Takes a 64-bit NTP timestamp and converts to 24-bit format for RTP header.
/// Matches werift-webrtc headerExtension.ts:serializeAbsSendTime behavior:
/// `const time = (ntpTime >> 14n) & 0x00ffffffn;`
Uint8List serializeAbsSendTimeFromNtp(int ntpTimestamp) {
  // Shift right by 14 bits and mask to 24 bits
  final time24 = (ntpTimestamp >> 14) & 0x00FFFFFF;
  return Uint8List.fromList([
    (time24 >> 16) & 0xFF,
    (time24 >> 8) & 0xFF,
    time24 & 0xFF,
  ]);
}

/// Parsed RTP header extensions map
typedef RtpExtensions = Map<String, dynamic>;

/// Parse RTP header extensions from extension data
/// Returns a map of URI -> value
RtpExtensions parseRtpExtensions(
  Uint8List extensionData,
  Map<int, String> idToUri,
) {
  final extensions = <String, dynamic>{};

  if (extensionData.isEmpty) return extensions;

  var offset = 0;
  while (offset < extensionData.length) {
    // One-byte header format: ID (4 bits) + Length (4 bits)
    final firstByte = extensionData[offset];

    // Check for padding (0x00) or termination (0x00 after data)
    if (firstByte == 0) {
      offset++;
      continue;
    }

    final id = (firstByte >> 4) & 0x0F;
    final length = (firstByte & 0x0F) + 1; // Length is L+1

    if (id == 0 || id == 15) {
      // Reserved values
      offset++;
      continue;
    }

    offset++; // Move past header byte

    if (offset + length > extensionData.length) break;

    final data = extensionData.sublist(offset, offset + length);
    offset += length;

    // Look up URI for this ID
    final uri = idToUri[id];
    if (uri == null) continue;

    // Deserialize based on URI
    switch (uri) {
      case RtpExtensionUri.sdesMid:
        extensions[uri] = deserializeSdesMid(data);
        break;
      case RtpExtensionUri.sdesRtpStreamId:
        extensions[uri] = deserializeSdesRtpStreamId(data);
        break;
      case RtpExtensionUri.repairedRtpStreamId:
        extensions[uri] = deserializeRepairedRtpStreamId(data);
        break;
      case RtpExtensionUri.transportWideCC:
        extensions[uri] = deserializeTransportWideCC(data);
        break;
      case RtpExtensionUri.ssrcAudioLevel:
        extensions[uri] = deserializeAudioLevel(data);
        break;
      case RtpExtensionUri.absoluteSendTime:
        extensions[uri] = deserializeAbsoluteSendTime(data);
        break;
      default:
        extensions[uri] = data;
    }
  }

  return extensions;
}

/// Build RTP header extension data from a map of values
Uint8List buildRtpExtensions(
  Map<String, dynamic> extensions,
  Map<String, int> uriToId,
) {
  final parts = <int>[];

  for (final entry in extensions.entries) {
    final uri = entry.key;
    final id = uriToId[uri];
    if (id == null || id < 1 || id > 14) continue;

    Uint8List data;
    switch (uri) {
      case RtpExtensionUri.sdesMid:
        data = serializeSdesMid(entry.value as String);
        break;
      case RtpExtensionUri.sdesRtpStreamId:
        data = serializeSdesRtpStreamId(entry.value as String);
        break;
      case RtpExtensionUri.repairedRtpStreamId:
        data = serializeRepairedRtpStreamId(entry.value as String);
        break;
      case RtpExtensionUri.transportWideCC:
        data = serializeTransportWideCC(entry.value as int);
        break;
      case RtpExtensionUri.absoluteSendTime:
        data = serializeAbsoluteSendTime(entry.value as int);
        break;
      default:
        if (entry.value is Uint8List) {
          data = entry.value;
        } else {
          continue;
        }
    }

    if (data.isEmpty || data.length > 16) continue;

    // One-byte header: ID (4 bits) + L (4 bits, where length = L+1)
    final header = (id << 4) | ((data.length - 1) & 0x0F);
    parts.add(header);
    parts.addAll(data);
  }

  // Pad to 4-byte boundary
  while (parts.length % 4 != 0) {
    parts.add(0);
  }

  return Uint8List.fromList(parts);
}
