import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// ICE Candidate
/// Represents a transport address that can be used for connectivity checks
class RTCIceCandidate {
  /// Foundation - identifier for candidates from the same base
  final String foundation;

  /// Component ID (1 = RTP, 2 = RTCP)
  final int component;

  /// Transport protocol (udp, tcp)
  final String transport;

  /// Priority value
  final int priority;

  /// IP address
  final String host;

  /// Port number
  final int port;

  /// Candidate type (host, srflx, prflx, relay)
  final String type;

  /// Related address (for reflexive/relay candidates)
  final String? relatedAddress;

  /// Related port (for reflexive/relay candidates)
  final int? relatedPort;

  /// TCP type (active, passive, so) - only for TCP candidates
  final String? tcpType;

  /// Generation (for ICE restarts)
  final int? generation;

  /// Username fragment
  final String? ufrag;

  /// SDP m-line index (0-indexed) for bundlePolicy:disable routing
  final int? sdpMLineIndex;

  /// SDP media identifier (MID)
  final String? sdpMid;

  RTCIceCandidate({
    required this.foundation,
    required this.component,
    required this.transport,
    required this.priority,
    required this.host,
    required this.port,
    required this.type,
    this.relatedAddress,
    this.relatedPort,
    this.tcpType,
    this.generation,
    this.ufrag,
    this.sdpMLineIndex,
    this.sdpMid,
  });

  // ===========================================================================
  // W3C Standard Property Aliases
  // ===========================================================================

  /// IP address (W3C standard name for 'host')
  String get address => host;

  /// Transport protocol (W3C standard name - same as 'transport')
  String get protocol => transport;

  /// Username fragment (W3C standard name for 'ufrag')
  String? get usernameFragment => ufrag;

  /// Candidate string in SDP format (W3C standard property)
  /// Returns the candidate-attribute value, e.g., "candidate:123 1 udp ..."
  String get candidate => 'candidate:${toSdp()}';

  /// Parse a candidate from SDP format
  /// Example: "6815297761 1 udp 659136 1.2.3.4 31102 typ host generation 0 ufrag b7l3"
  /// Also accepts with "candidate:" prefix: "candidate:6815297761 1 udp ..."
  factory RTCIceCandidate.fromSdp(String sdp) {
    // Strip "candidate:" or "a=candidate:" prefix if present
    var s = sdp;
    var start = 0;
    var end = sdp.length;

    // Trim leading whitespace
    while (start < end && s.codeUnitAt(start) == 0x20) {
      start++;
    }
    // Trim trailing whitespace
    while (end > start && s.codeUnitAt(end - 1) == 0x20) {
      end--;
    }

    // Check for prefixes
    if (end - start > 12 &&
        s.codeUnitAt(start) == 0x61 && // 'a'
        s.codeUnitAt(start + 1) == 0x3D && // '='
        s.codeUnitAt(start + 2) == 0x63) {
      // 'c'
      // a=candidate:
      start += 12;
    } else if (end - start > 10 && s.codeUnitAt(start) == 0x63) {
      // 'c'
      // candidate:
      start += 10;
    }

    // Parse using indexOf to avoid split() allocation
    // Format: foundation component transport priority host port typ type [optional...]

    int nextSpace(int from) {
      final idx = s.indexOf(' ', from);
      return idx == -1 ? end : idx;
    }

    // Field 0: foundation
    var pos = start;
    var spacePos = nextSpace(pos);
    if (spacePos >= end) {
      throw ArgumentError('SDP does not have enough properties: $sdp');
    }
    final foundation = s.substring(pos, spacePos);

    // Field 1: component
    pos = spacePos + 1;
    spacePos = nextSpace(pos);
    if (spacePos >= end) {
      throw ArgumentError('SDP does not have enough properties: $sdp');
    }
    final component = int.parse(s.substring(pos, spacePos));

    // Field 2: transport
    pos = spacePos + 1;
    spacePos = nextSpace(pos);
    if (spacePos >= end) {
      throw ArgumentError('SDP does not have enough properties: $sdp');
    }
    final transport = s.substring(pos, spacePos);

    // Field 3: priority
    pos = spacePos + 1;
    spacePos = nextSpace(pos);
    if (spacePos >= end) {
      throw ArgumentError('SDP does not have enough properties: $sdp');
    }
    final priority = int.parse(s.substring(pos, spacePos));

    // Field 4: host
    pos = spacePos + 1;
    spacePos = nextSpace(pos);
    if (spacePos >= end) {
      throw ArgumentError('SDP does not have enough properties: $sdp');
    }
    final host = s.substring(pos, spacePos);

    // Field 5: port
    pos = spacePos + 1;
    spacePos = nextSpace(pos);
    if (spacePos >= end) {
      throw ArgumentError('SDP does not have enough properties: $sdp');
    }
    final port = int.parse(s.substring(pos, spacePos));

    // Field 6: "typ" keyword - skip it
    pos = spacePos + 1;
    spacePos = nextSpace(pos);
    if (spacePos >= end) {
      throw ArgumentError('SDP does not have enough properties: $sdp');
    }

    // Field 7: type
    pos = spacePos + 1;
    spacePos = nextSpace(pos);
    final type = s.substring(pos, spacePos);

    // Optional attributes
    String? relatedAddress;
    int? relatedPort;
    String? tcpType;
    int? generation;
    String? ufrag;

    pos = spacePos + 1;
    while (pos < end) {
      spacePos = nextSpace(pos);
      final key = s.substring(pos, spacePos);

      pos = spacePos + 1;
      if (pos >= end) break;

      spacePos = nextSpace(pos);
      final value = s.substring(pos, spacePos);

      // Use first character for fast dispatch
      switch (key.isNotEmpty ? key.codeUnitAt(0) : 0) {
        case 0x72: // 'r' - raddr or rport
          if (key == 'raddr') {
            relatedAddress = value;
          } else if (key == 'rport') {
            relatedPort = int.parse(value);
          }
          break;
        case 0x74: // 't' - tcptype
          if (key == 'tcptype') {
            tcpType = value;
          }
          break;
        case 0x67: // 'g' - generation
          if (key == 'generation') {
            generation = int.parse(value);
          }
          break;
        case 0x75: // 'u' - ufrag
          if (key == 'ufrag') {
            ufrag = value;
          }
          break;
      }

      pos = spacePos + 1;
    }

    return RTCIceCandidate(
      foundation: foundation,
      component: component,
      transport: transport,
      priority: priority,
      host: host,
      port: port,
      type: type,
      relatedAddress: relatedAddress,
      relatedPort: relatedPort,
      tcpType: tcpType,
      generation: generation,
      ufrag: ufrag,
    );
  }

  /// Check if this candidate can pair with another candidate
  /// A local candidate is paired with a remote candidate if and only if
  /// the two candidates have the same component ID and have the same IP
  /// address version.
  ///
  /// For TCP candidates (RFC 6544), additional tcpType compatibility is required:
  /// - active can pair with passive
  /// - passive can pair with active
  /// - so (simultaneous-open) can pair with so
  bool canPairWith(RTCIceCandidate other) {
    final thisIsV4 = InternetAddress(host).type == InternetAddressType.IPv4;
    final otherIsV4 =
        InternetAddress(other.host).type == InternetAddressType.IPv4;

    // Basic requirements: same component and IP version
    if (component != other.component || thisIsV4 != otherIsV4) {
      return false;
    }

    // Transport must match (UDP with UDP, TCP with TCP)
    final thisTransport = transport.toLowerCase();
    final otherTransport = other.transport.toLowerCase();
    if (thisTransport != otherTransport) {
      return false;
    }

    // For TCP candidates, check tcpType compatibility (RFC 6544)
    if (thisTransport == 'tcp') {
      return _tcpTypesCompatible(tcpType, other.tcpType);
    }

    // UDP candidates don't have tcpType restrictions
    return true;
  }

  /// Check if two TCP types are compatible for pairing (RFC 6544)
  /// - active pairs with passive
  /// - passive pairs with active
  /// - so pairs with so
  static bool _tcpTypesCompatible(String? local, String? remote) {
    // If either tcpType is missing, allow pairing for backwards compatibility
    if (local == null || remote == null) {
      return true;
    }

    final localType = local.toLowerCase();
    final remoteType = remote.toLowerCase();

    // Active pairs with passive
    if (localType == 'active' && remoteType == 'passive') {
      return true;
    }

    // Passive pairs with active
    if (localType == 'passive' && remoteType == 'active') {
      return true;
    }

    // SO pairs with SO
    if (localType == 'so' && remoteType == 'so') {
      return true;
    }

    return false;
  }

  /// Convert candidate to SDP format
  String toSdp() {
    // String interpolation is 3x faster than StringBuffer in Dart
    final base =
        '$foundation $component $transport $priority $host $port typ $type';

    // Fast path: no optional attributes
    if (relatedAddress == null &&
        relatedPort == null &&
        tcpType == null &&
        generation == null &&
        ufrag == null) {
      return base;
    }

    // Build optional suffix
    final raddr = relatedAddress != null ? ' raddr $relatedAddress' : '';
    final rport = relatedPort != null ? ' rport $relatedPort' : '';
    final tcp = tcpType != null ? ' tcptype $tcpType' : '';
    final gen = generation != null ? ' generation $generation' : '';
    final uf = ufrag != null ? ' ufrag $ufrag' : '';

    return '$base$raddr$rport$tcp$gen$uf';
  }

  /// Create a copy with modified fields
  RTCIceCandidate copyWith({
    String? foundation,
    int? component,
    String? transport,
    int? priority,
    String? host,
    int? port,
    String? type,
    String? relatedAddress,
    int? relatedPort,
    String? tcpType,
    int? generation,
    String? ufrag,
    int? sdpMLineIndex,
    String? sdpMid,
  }) {
    return RTCIceCandidate(
      foundation: foundation ?? this.foundation,
      component: component ?? this.component,
      transport: transport ?? this.transport,
      priority: priority ?? this.priority,
      host: host ?? this.host,
      port: port ?? this.port,
      type: type ?? this.type,
      relatedAddress: relatedAddress ?? this.relatedAddress,
      relatedPort: relatedPort ?? this.relatedPort,
      tcpType: tcpType ?? this.tcpType,
      generation: generation ?? this.generation,
      ufrag: ufrag ?? this.ufrag,
      sdpMLineIndex: sdpMLineIndex ?? this.sdpMLineIndex,
      sdpMid: sdpMid ?? this.sdpMid,
    );
  }

  /// Serialize to JSON format (W3C standard)
  ///
  /// Returns a Map matching the RTCIceCandidateInit dictionary.
  Map<String, dynamic> toJSON() {
    return {
      'candidate': candidate,
      'sdpMid': sdpMid,
      'sdpMLineIndex': sdpMLineIndex,
      if (usernameFragment != null) 'usernameFragment': usernameFragment,
    };
  }

  @override
  String toString() {
    return 'RTCIceCandidate($type, $host:$port, priority=$priority)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RTCIceCandidate &&
        foundation == other.foundation &&
        component == other.component &&
        transport == other.transport &&
        host == other.host &&
        port == other.port &&
        type == other.type;
  }

  @override
  int get hashCode {
    return Object.hash(foundation, component, transport, host, port, type);
  }
}

// =============================================================================
// Backward Compatibility TypeDef
// =============================================================================

/// @deprecated Use RTCIceCandidate instead
@Deprecated('Use RTCIceCandidate instead')
typedef Candidate = RTCIceCandidate;

/// Compute foundation for a candidate
/// See RFC 5245 - 4.1.1.3. Computing Foundations
String candidateFoundation(
  String candidateType,
  String candidateTransport,
  String baseAddress,
) {
  final key = '$candidateType|$candidateTransport|$baseAddress';
  final bytes = Uint8List.fromList(key.codeUnits);
  final digest = md5.convert(bytes);
  return digest.toString().substring(7);
}

/// Compute priority for a candidate
/// See RFC 5245 - 4.1.2.1. Recommended Formula
/// See RFC 6544 - Section 4.2 for TCP transport preference
///
/// Transport preference (0-15): UDP = 15, TCP = 6 (per RFC 6544)
/// Local preference formula when including transport:
///   localPref = (2^13) * direction + (2^9) * other + transportPref
/// For simplicity, we fold transportPref into localPref directly.
int candidatePriority(
  String candidateType, {
  int localPref = 65535,
  int? transportPreference,
}) {
  const candidateComponent = 1;

  // Type preference values from RFC 5245
  int typePref;
  switch (candidateType) {
    case 'host':
      typePref = 126;
      break;
    case 'prflx':
      typePref = 110;
      break;
    case 'srflx':
      typePref = 100;
      break;
    case 'relay':
      typePref = 0;
      break;
    default:
      typePref = 0;
  }

  // If transport preference is specified, adjust localPref to include it
  // This gives TCP lower priority than UDP for same candidate type
  var effectiveLocalPref = localPref;
  if (transportPreference != null) {
    // Scale down localPref and add transport preference
    // This ensures TCP candidates have lower priority than UDP
    effectiveLocalPref = (localPref & 0xFFF0) | (transportPreference & 0x0F);
  }

  // Priority formula: (2^24)*typePref + (2^8)*localPref + (256-componentId)
  return (1 << 24) * typePref +
      (1 << 8) * effectiveLocalPref +
      (256 - candidateComponent);
}
