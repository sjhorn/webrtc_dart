/// RTX SDP Support
/// RFC 4588 - RTP Retransmission Payload Format
///
/// Handles RTX-specific SDP attributes:
/// - rtpmap: `a=rtpmap:97 rtx/90000`
/// - fmtp apt: `a=fmtp:97 apt=96`
/// - ssrc-group FID: `a=ssrc-group:FID 12345678 87654321`
library;

import 'sdp.dart';

/// RTX Codec information extracted from SDP
class RtxCodecInfo {
  /// RTX payload type
  final int rtxPayloadType;

  /// Associated (original) payload type
  final int associatedPayloadType;

  /// Clock rate (typically 90000 for video)
  final int clockRate;

  RtxCodecInfo({
    required this.rtxPayloadType,
    required this.associatedPayloadType,
    required this.clockRate,
  });

  @override
  String toString() {
    return 'RtxCodecInfo(rtx=$rtxPayloadType, apt=$associatedPayloadType, clock=$clockRate)';
  }
}

/// SSRC Group information (FID = Flow Identification)
class SsrcGroup {
  /// Group semantics (e.g., "FID" for RTX, "SIM" for simulcast)
  final String semantics;

  /// List of SSRCs in the group
  final List<int> ssrcs;

  SsrcGroup({required this.semantics, required this.ssrcs});

  /// Parse from SDP attribute value (e.g., "FID 12345678 87654321")
  static SsrcGroup parse(String value) {
    final parts = value.split(' ');
    if (parts.length < 2) {
      throw FormatException('Invalid ssrc-group: $value');
    }
    return SsrcGroup(
      semantics: parts[0],
      ssrcs: parts.sublist(1).map((s) => int.parse(s)).toList(),
    );
  }

  /// Serialize to SDP attribute value
  String serialize() {
    return '$semantics ${ssrcs.join(' ')}';
  }

  @override
  String toString() {
    return 'SsrcGroup($semantics: $ssrcs)';
  }
}

/// SSRC information from SDP
class SsrcInfo {
  /// SSRC value
  final int ssrc;

  /// CNAME (canonical name)
  String? cname;

  /// Media stream ID
  String? msid;

  /// Media stream track ID
  String? mslabel;

  /// Label
  String? label;

  SsrcInfo({required this.ssrc, this.cname, this.msid, this.mslabel, this.label});

  @override
  String toString() {
    return 'SsrcInfo(ssrc=$ssrc, cname=$cname)';
  }
}

/// Extension methods for SdpMedia to handle RTX
extension SdpMediaRtxExtension on SdpMedia {
  /// Parse rtpmap attribute
  /// Format: "payload_type codec_name/clock_rate[/channels]"
  /// Example: "96 VP8/90000" or "97 rtx/90000"
  static RtpMapInfo? parseRtpMap(String value) {
    final parts = value.split(' ');
    if (parts.length < 2) return null;

    final payloadType = int.tryParse(parts[0]);
    if (payloadType == null) return null;

    final codecParts = parts[1].split('/');
    if (codecParts.isEmpty) return null;

    final codecName = codecParts[0];
    final clockRate = codecParts.length > 1 ? int.tryParse(codecParts[1]) ?? 90000 : 90000;
    final channels = codecParts.length > 2 ? int.tryParse(codecParts[2]) : null;

    return RtpMapInfo(
      payloadType: payloadType,
      codecName: codecName,
      clockRate: clockRate,
      channels: channels,
    );
  }

  /// Parse fmtp attribute
  /// Format: "payload_type param1=value1;param2=value2"
  /// Example: "97 apt=96"
  static FmtpInfo? parseFmtp(String value) {
    final spaceIndex = value.indexOf(' ');
    if (spaceIndex == -1) return null;

    final payloadType = int.tryParse(value.substring(0, spaceIndex));
    if (payloadType == null) return null;

    final paramsStr = value.substring(spaceIndex + 1);
    final params = <String, String>{};

    // Parse semicolon or space separated params
    for (final param in paramsStr.split(RegExp(r'[;\s]+'))) {
      if (param.isEmpty) continue;
      final eqIndex = param.indexOf('=');
      if (eqIndex == -1) {
        params[param] = '';
      } else {
        params[param.substring(0, eqIndex)] = param.substring(eqIndex + 1);
      }
    }

    return FmtpInfo(payloadType: payloadType, parameters: params);
  }

  /// Get all rtpmap entries from this media
  List<RtpMapInfo> getRtpMaps() {
    final rtpMaps = <RtpMapInfo>[];
    for (final attr in getAttributes('rtpmap')) {
      if (attr.value != null) {
        final info = parseRtpMap(attr.value!);
        if (info != null) rtpMaps.add(info);
      }
    }
    return rtpMaps;
  }

  /// Get all fmtp entries from this media
  List<FmtpInfo> getFmtps() {
    final fmtps = <FmtpInfo>[];
    for (final attr in getAttributes('fmtp')) {
      if (attr.value != null) {
        final info = parseFmtp(attr.value!);
        if (info != null) fmtps.add(info);
      }
    }
    return fmtps;
  }

  /// Get all SSRC groups from this media
  List<SsrcGroup> getSsrcGroups() {
    final groups = <SsrcGroup>[];
    for (final attr in getAttributes('ssrc-group')) {
      if (attr.value != null) {
        try {
          groups.add(SsrcGroup.parse(attr.value!));
        } catch (_) {
          // Ignore invalid ssrc-group
        }
      }
    }
    return groups;
  }

  /// Get all SSRC info from this media
  List<SsrcInfo> getSsrcInfos() {
    final ssrcMap = <int, SsrcInfo>{};

    for (final attr in getAttributes('ssrc')) {
      if (attr.value == null) continue;

      // Format: "ssrc attr:value" (e.g., "12345678 cname:user@example.com")
      final spaceIndex = attr.value!.indexOf(' ');
      if (spaceIndex == -1) continue;

      final ssrc = int.tryParse(attr.value!.substring(0, spaceIndex));
      if (ssrc == null) continue;

      final attrPart = attr.value!.substring(spaceIndex + 1);
      final colonIndex = attrPart.indexOf(':');

      final ssrcInfo = ssrcMap.putIfAbsent(ssrc, () => SsrcInfo(ssrc: ssrc));

      if (colonIndex == -1) continue;
      final attrName = attrPart.substring(0, colonIndex);
      final attrValue = attrPart.substring(colonIndex + 1);

      switch (attrName) {
        case 'cname':
          ssrcInfo.cname = attrValue;
          break;
        case 'msid':
          ssrcInfo.msid = attrValue;
          break;
        case 'mslabel':
          ssrcInfo.mslabel = attrValue;
          break;
        case 'label':
          ssrcInfo.label = attrValue;
          break;
      }
    }

    return ssrcMap.values.toList();
  }

  /// Find RTX codec info for this media
  /// Returns mapping of original payload type to RTX codec info
  Map<int, RtxCodecInfo> getRtxCodecs() {
    final rtxCodecs = <int, RtxCodecInfo>{};
    final rtpMaps = getRtpMaps();
    final fmtps = getFmtps();

    // Find all rtx rtpmap entries
    for (final rtpMap in rtpMaps) {
      if (rtpMap.codecName.toLowerCase() == 'rtx') {
        // Find the apt (associated payload type) in fmtp
        final fmtp = fmtps.firstWhere(
          (f) => f.payloadType == rtpMap.payloadType,
          orElse: () => FmtpInfo(payloadType: rtpMap.payloadType, parameters: {}),
        );

        final aptStr = fmtp.parameters['apt'];
        if (aptStr != null) {
          final apt = int.tryParse(aptStr);
          if (apt != null) {
            rtxCodecs[apt] = RtxCodecInfo(
              rtxPayloadType: rtpMap.payloadType,
              associatedPayloadType: apt,
              clockRate: rtpMap.clockRate,
            );
          }
        }
      }
    }

    return rtxCodecs;
  }

  /// Find RTX SSRC mapping from ssrc-group FID
  /// Returns map of original SSRC to RTX SSRC
  Map<int, int> getRtxSsrcMapping() {
    final mapping = <int, int>{};

    for (final group in getSsrcGroups()) {
      if (group.semantics == 'FID' && group.ssrcs.length >= 2) {
        // First SSRC is original, second is RTX
        mapping[group.ssrcs[0]] = group.ssrcs[1];
      }
    }

    return mapping;
  }
}

/// RTP Map information
class RtpMapInfo {
  final int payloadType;
  final String codecName;
  final int clockRate;
  final int? channels;

  RtpMapInfo({
    required this.payloadType,
    required this.codecName,
    required this.clockRate,
    this.channels,
  });

  /// Check if this is an RTX codec
  bool get isRtx => codecName.toLowerCase() == 'rtx';

  /// Serialize to rtpmap value
  String serialize() {
    var value = '$payloadType $codecName/$clockRate';
    if (channels != null) {
      value += '/$channels';
    }
    return value;
  }

  @override
  String toString() {
    return 'RtpMap($payloadType $codecName/$clockRate${channels != null ? "/$channels" : ""})';
  }
}

/// FMTP (Format Parameters) information
class FmtpInfo {
  final int payloadType;
  final Map<String, String> parameters;

  FmtpInfo({required this.payloadType, required this.parameters});

  /// Get apt (associated payload type) for RTX
  int? get apt {
    final aptStr = parameters['apt'];
    return aptStr != null ? int.tryParse(aptStr) : null;
  }

  /// Serialize to fmtp value
  String serialize() {
    if (parameters.isEmpty) {
      return '$payloadType';
    }
    final paramStr = parameters.entries
        .map((e) => e.value.isEmpty ? e.key : '${e.key}=${e.value}')
        .join(';');
    return '$payloadType $paramStr';
  }

  @override
  String toString() {
    return 'Fmtp($payloadType ${parameters.entries.map((e) => "${e.key}=${e.value}").join("; ")})';
  }
}

/// RTX SDP Builder - helps generate RTX-related SDP attributes
class RtxSdpBuilder {
  /// Create rtpmap attribute for RTX
  static SdpAttribute createRtxRtpMap(int rtxPayloadType, {int clockRate = 90000}) {
    return SdpAttribute(
      key: 'rtpmap',
      value: '$rtxPayloadType rtx/$clockRate',
    );
  }

  /// Create fmtp attribute for RTX with apt (associated payload type)
  static SdpAttribute createRtxFmtp(int rtxPayloadType, int associatedPayloadType) {
    return SdpAttribute(
      key: 'fmtp',
      value: '$rtxPayloadType apt=$associatedPayloadType',
    );
  }

  /// Create ssrc-group FID attribute for RTX
  static SdpAttribute createSsrcGroupFid(int originalSsrc, int rtxSsrc) {
    return SdpAttribute(
      key: 'ssrc-group',
      value: 'FID $originalSsrc $rtxSsrc',
    );
  }

  /// Create ssrc attribute with cname
  static SdpAttribute createSsrcCname(int ssrc, String cname) {
    return SdpAttribute(
      key: 'ssrc',
      value: '$ssrc cname:$cname',
    );
  }

  /// Create ssrc attribute with msid
  static SdpAttribute createSsrcMsid(int ssrc, String streamId, String trackId) {
    return SdpAttribute(
      key: 'ssrc',
      value: '$ssrc msid:$streamId $trackId',
    );
  }

  /// Generate all RTX-related attributes for a media section
  /// Returns list of attributes to add to the media section
  static List<SdpAttribute> generateRtxAttributes({
    required int originalPayloadType,
    required int rtxPayloadType,
    required int originalSsrc,
    required int rtxSsrc,
    required String cname,
    int clockRate = 90000,
    String? streamId,
    String? trackId,
  }) {
    final attrs = <SdpAttribute>[
      // RTX rtpmap
      createRtxRtpMap(rtxPayloadType, clockRate: clockRate),
      // RTX fmtp with apt
      createRtxFmtp(rtxPayloadType, originalPayloadType),
      // SSRC-group FID
      createSsrcGroupFid(originalSsrc, rtxSsrc),
      // RTX SSRC cname
      createSsrcCname(rtxSsrc, cname),
    ];

    // Add msid if provided
    if (streamId != null && trackId != null) {
      attrs.add(createSsrcMsid(rtxSsrc, streamId, trackId));
    }

    return attrs;
  }
}
