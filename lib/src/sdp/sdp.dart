/// Session Description Protocol (SDP)
/// RFC 4566 - SDP: Session Description Protocol
/// RFC 8866 - SDP: Session Description Protocol (updated)
library;

import '../media/parameters.dart';

/// SDP Session Description
class RTCSessionDescription {
  /// Type (offer, answer, pranswer, rollback)
  final String type;

  /// SDP string
  final String sdp;

  const RTCSessionDescription({
    required this.type,
    required this.sdp,
  });

  /// Parse SDP string into structured format
  SdpMessage parse() {
    return SdpMessage.parse(sdp);
  }

  @override
  String toString() {
    return 'RTCSessionDescription(type=$type)';
  }
}

// =============================================================================
// Backward Compatibility TypeDef
// =============================================================================

/// @deprecated Use RTCSessionDescription instead
@Deprecated('Use RTCSessionDescription instead')
typedef SessionDescription = RTCSessionDescription;

/// SDP Message
/// Structured representation of an SDP
class SdpMessage {
  /// Version (v=)
  final int version;

  /// Origin (o=)
  final SdpOrigin origin;

  /// Session name (s=)
  final String sessionName;

  /// Session information (i=)
  final String? sessionInformation;

  /// Connection information (c=)
  final SdpConnection? connection;

  /// Timing (t=)
  final List<SdpTiming> timing;

  /// Attributes (a=)
  final List<SdpAttribute> attributes;

  /// Media descriptions (m=)
  final List<SdpMedia> mediaDescriptions;

  SdpMessage({
    this.version = 0,
    required this.origin,
    required this.sessionName,
    this.sessionInformation,
    this.connection,
    required this.timing,
    this.attributes = const [],
    this.mediaDescriptions = const [],
  });

  /// Parse SDP string
  static SdpMessage parse(String sdp) {
    final lines = sdp
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    int version = 0;
    SdpOrigin? origin;
    String sessionName = '';
    String? sessionInformation;
    SdpConnection? connection;
    final timing = <SdpTiming>[];
    final attributes = <SdpAttribute>[];
    final mediaDescriptions = <SdpMedia>[];

    var inMedia = false;
    var currentMedia = <String>[];

    for (final line in lines) {
      if (line.length < 2 || line[1] != '=') {
        continue; // Invalid line
      }

      final type = line[0];
      final value = line.substring(2);

      // Check if we're starting a new media section
      if (type == 'm') {
        // Save previous media section if any
        if (currentMedia.isNotEmpty) {
          mediaDescriptions.add(SdpMedia.parse(currentMedia));
        }
        currentMedia = [line];
        inMedia = true;
        continue;
      }

      if (inMedia) {
        currentMedia.add(line);
        continue;
      }

      // Parse session-level fields
      switch (type) {
        case 'v':
          version = int.parse(value);
          break;
        case 'o':
          origin = SdpOrigin.parse(value);
          break;
        case 's':
          sessionName = value;
          break;
        case 'i':
          sessionInformation = value;
          break;
        case 'c':
          connection = SdpConnection.parse(value);
          break;
        case 't':
          timing.add(SdpTiming.parse(value));
          break;
        case 'a':
          attributes.add(SdpAttribute.parse(value));
          break;
      }
    }

    // Save last media section
    if (currentMedia.isNotEmpty) {
      mediaDescriptions.add(SdpMedia.parse(currentMedia));
    }

    if (origin == null) {
      throw FormatException('Missing origin line');
    }

    return SdpMessage(
      version: version,
      origin: origin,
      sessionName: sessionName,
      sessionInformation: sessionInformation,
      connection: connection,
      timing: timing.isEmpty ? [SdpTiming(startTime: 0, stopTime: 0)] : timing,
      attributes: attributes,
      mediaDescriptions: mediaDescriptions,
    );
  }

  /// Serialize to SDP string
  String serialize() {
    final lines = <String>[];

    lines.add('v=$version');
    lines.add('o=${origin.serialize()}');
    lines.add('s=$sessionName');

    if (sessionInformation != null) {
      lines.add('i=$sessionInformation');
    }

    if (connection != null) {
      lines.add('c=${connection!.serialize()}');
    }

    for (final t in timing) {
      lines.add('t=${t.serialize()}');
    }

    for (final attr in attributes) {
      lines.add('a=${attr.serialize()}');
    }

    for (final media in mediaDescriptions) {
      lines.addAll(media.serialize());
    }

    return '${lines.join('\r\n')}\r\n';
  }

  /// Get session-level attribute value by key
  String? getAttributeValue(String key) {
    for (final attr in attributes) {
      if (attr.key == key) {
        return attr.value;
      }
    }
    return null;
  }

  /// Check if session-level attribute exists (flag attribute)
  bool hasAttribute(String key) {
    return attributes.any((attr) => attr.key == key);
  }

  /// Check if remote peer is ICE-lite
  /// ICE-lite can be specified at session level or media level
  bool get isIceLite {
    // Check session-level first
    if (hasAttribute('ice-lite')) {
      return true;
    }
    // Check media-level
    for (final media in mediaDescriptions) {
      if (media.hasAttribute('ice-lite')) {
        return true;
      }
    }
    return false;
  }

  @override
  String toString() {
    return 'SdpMessage(version=$version, media=${mediaDescriptions.length})';
  }
}

/// SDP Origin (o=)
class SdpOrigin {
  final String username;
  final String sessionId;
  final String sessionVersion;
  final String netType;
  final String addrType;
  final String unicastAddress;

  SdpOrigin({
    required this.username,
    required this.sessionId,
    required this.sessionVersion,
    this.netType = 'IN',
    this.addrType = 'IP4',
    required this.unicastAddress,
  });

  static SdpOrigin parse(String value) {
    final parts = value.split(' ');
    if (parts.length < 6) {
      throw FormatException('Invalid origin line');
    }

    return SdpOrigin(
      username: parts[0],
      sessionId: parts[1],
      sessionVersion: parts[2],
      netType: parts[3],
      addrType: parts[4],
      unicastAddress: parts[5],
    );
  }

  String serialize() {
    return '$username $sessionId $sessionVersion $netType $addrType $unicastAddress';
  }
}

/// SDP Connection (c=)
class SdpConnection {
  final String netType;
  final String addrType;
  final String connectionAddress;

  const SdpConnection({
    this.netType = 'IN',
    this.addrType = 'IP4',
    required this.connectionAddress,
  });

  static SdpConnection parse(String value) {
    final parts = value.split(' ');
    if (parts.length < 3) {
      throw FormatException('Invalid connection line');
    }

    return SdpConnection(
      netType: parts[0],
      addrType: parts[1],
      connectionAddress: parts[2],
    );
  }

  String serialize() {
    return '$netType $addrType $connectionAddress';
  }
}

/// SDP Timing (t=)
class SdpTiming {
  final int startTime;
  final int stopTime;

  SdpTiming({required this.startTime, required this.stopTime});

  static SdpTiming parse(String value) {
    final parts = value.split(' ');
    if (parts.length < 2) {
      throw FormatException('Invalid timing line');
    }

    return SdpTiming(
      startTime: int.parse(parts[0]),
      stopTime: int.parse(parts[1]),
    );
  }

  String serialize() {
    return '$startTime $stopTime';
  }
}

/// SDP Attribute (a=)
class SdpAttribute {
  final String key;
  final String? value;

  SdpAttribute({required this.key, this.value});

  static SdpAttribute parse(String value) {
    final colonIndex = value.indexOf(':');
    if (colonIndex == -1) {
      return SdpAttribute(key: value);
    }

    return SdpAttribute(
      key: value.substring(0, colonIndex),
      value: value.substring(colonIndex + 1),
    );
  }

  String serialize() {
    return value == null ? key : '$key:$value';
  }

  @override
  String toString() {
    return 'a=$key${value != null ? ":$value" : ""}';
  }
}

/// SDP Media Description (m=)
class SdpMedia {
  final String type; // audio, video, application, etc.
  final int port;
  final String protocol; // UDP/TLS/RTP/SAVPF, etc.
  final List<String> formats; // Payload types or other format identifiers

  final SdpConnection? connection;
  final List<SdpAttribute> attributes;

  SdpMedia({
    required this.type,
    required this.port,
    required this.protocol,
    required this.formats,
    this.connection,
    this.attributes = const [],
  });

  static SdpMedia parse(List<String> lines) {
    if (lines.isEmpty) {
      throw FormatException('Empty media section');
    }

    // Parse m= line
    final mLine = lines[0].substring(2); // Remove 'm='
    final parts = mLine.split(' ');
    if (parts.length < 4) {
      throw FormatException('Invalid media line');
    }

    final type = parts[0];
    final port = int.parse(parts[1]);
    final protocol = parts[2];
    final formats = parts.sublist(3);

    SdpConnection? connection;
    final attributes = <SdpAttribute>[];

    // Parse remaining lines
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.length < 2 || line[1] != '=') continue;

      final lineType = line[0];
      final value = line.substring(2);

      switch (lineType) {
        case 'c':
          connection = SdpConnection.parse(value);
          break;
        case 'a':
          attributes.add(SdpAttribute.parse(value));
          break;
      }
    }

    return SdpMedia(
      type: type,
      port: port,
      protocol: protocol,
      formats: formats,
      connection: connection,
      attributes: attributes,
    );
  }

  List<String> serialize() {
    final lines = <String>[];

    lines.add('m=$type $port $protocol ${formats.join(' ')}');

    if (connection != null) {
      lines.add('c=${connection!.serialize()}');
    }

    for (final attr in attributes) {
      lines.add('a=${attr.serialize()}');
    }

    return lines;
  }

  /// Get attribute value by key
  String? getAttributeValue(String key) {
    for (final attr in attributes) {
      if (attr.key == key) {
        return attr.value;
      }
    }
    return null;
  }

  /// Get all attributes with key
  List<SdpAttribute> getAttributes(String key) {
    return attributes.where((attr) => attr.key == key).toList();
  }

  /// Check if attribute exists (flag attribute)
  bool hasAttribute(String key) {
    return attributes.any((attr) => attr.key == key);
  }

  /// Get simulcast parameters from RID attributes
  /// Parses a=rid:high send, a=rid:low send etc.
  List<RTCRtpSimulcastParameters> getSimulcastParameters() {
    final params = <RTCRtpSimulcastParameters>[];

    for (final attr in getAttributes('rid')) {
      if (attr.value != null) {
        try {
          params.add(RTCRtpSimulcastParameters.fromSdpRid(attr.value!));
        } catch (e) {
          // Skip invalid RID attributes
        }
      }
    }

    return params;
  }

  /// Get parsed simulcast attribute
  /// Returns map with 'send' and 'recv' lists of RIDs
  /// Parses a=simulcast:send high;low recv mid
  SimulcastAttribute? getSimulcastAttribute() {
    final attr = getAttributeValue('simulcast');
    if (attr == null) return null;

    return SimulcastAttribute.parse(attr);
  }

  /// Get RTP header extensions
  /// Parses a=extmap:1 urn:ietf:params:rtp-hdrext:sdes:mid
  List<RtpHeaderExtension> getHeaderExtensions() {
    final extensions = <RtpHeaderExtension>[];

    for (final attr in getAttributes('extmap')) {
      if (attr.value != null) {
        try {
          extensions.add(RtpHeaderExtension.parse(attr.value!));
        } catch (e) {
          // Skip invalid extmap
        }
      }
    }

    return extensions;
  }

  /// Get media direction (sendrecv, sendonly, recvonly, inactive)
  MediaDirection getDirection() {
    if (hasAttribute('sendrecv')) return MediaDirection.sendrecv;
    if (hasAttribute('sendonly')) return MediaDirection.sendonly;
    if (hasAttribute('recvonly')) return MediaDirection.recvonly;
    if (hasAttribute('inactive')) return MediaDirection.inactive;
    return MediaDirection.sendrecv; // Default
  }

  /// Get mid (media ID)
  String? getMid() => getAttributeValue('mid');

  @override
  String toString() {
    return 'SdpMedia(type=$type, port=$port, protocol=$protocol, formats=$formats)';
  }
}

/// Simulcast attribute (a=simulcast:)
/// Format: a=simulcast:send rid1;rid2 recv rid3;rid4
class SimulcastAttribute {
  /// RIDs to send
  final List<String> send;

  /// RIDs to receive
  final List<String> recv;

  const SimulcastAttribute({
    this.send = const [],
    this.recv = const [],
  });

  /// Parse simulcast attribute value
  /// Format: "send high;low recv mid" or "recv high;low"
  static SimulcastAttribute parse(String value) {
    final send = <String>[];
    final recv = <String>[];

    final parts = value.trim().split(RegExp(r'\s+'));
    var currentDirection = '';

    for (final part in parts) {
      if (part == 'send') {
        currentDirection = 'send';
      } else if (part == 'recv') {
        currentDirection = 'recv';
      } else if (currentDirection.isNotEmpty) {
        // Parse RID list (semicolon-separated)
        final rids = part.split(';').where((r) => r.isNotEmpty).toList();
        if (currentDirection == 'send') {
          send.addAll(rids);
        } else {
          recv.addAll(rids);
        }
      }
    }

    return SimulcastAttribute(send: send, recv: recv);
  }

  /// Serialize to SDP attribute value
  String serialize() {
    final parts = <String>[];

    if (recv.isNotEmpty) {
      parts.add('recv ${recv.join(";")}');
    }
    if (send.isNotEmpty) {
      parts.add('send ${send.join(";")}');
    }

    return parts.join(' ');
  }

  @override
  String toString() => 'SimulcastAttribute(send: $send, recv: $recv)';
}

/// RTP Header Extension from extmap attribute
/// Format: a=extmap:1 urn:ietf:params:rtp-hdrext:sdes:mid
class RtpHeaderExtension {
  /// Extension ID (1-14 for one-byte, 1-255 for two-byte)
  final int id;

  /// Extension URI
  final String uri;

  /// Direction (optional)
  final String? direction;

  const RtpHeaderExtension({
    required this.id,
    required this.uri,
    this.direction,
  });

  /// Parse extmap attribute value
  /// Format: "1 urn:..." or "1/sendonly urn:..."
  static RtpHeaderExtension parse(String value) {
    final parts = value.split(' ');
    if (parts.length < 2) {
      throw FormatException('Invalid extmap: $value');
    }

    final idPart = parts[0];
    final uri = parts[1];

    // Check for direction: "1/sendonly"
    String? direction;
    int id;
    if (idPart.contains('/')) {
      final idParts = idPart.split('/');
      id = int.parse(idParts[0]);
      direction = idParts[1];
    } else {
      id = int.parse(idPart);
    }

    return RtpHeaderExtension(id: id, uri: uri, direction: direction);
  }

  /// Serialize to extmap attribute value
  String serialize() {
    if (direction != null) {
      return '$id/$direction $uri';
    }
    return '$id $uri';
  }

  @override
  String toString() => 'RtpHeaderExtension(id: $id, uri: $uri)';
}
