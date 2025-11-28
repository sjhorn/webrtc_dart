import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// ICE Candidate
/// Represents a transport address that can be used for connectivity checks
class Candidate {
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

  Candidate({
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
  });

  /// Parse a candidate from SDP format
  /// Example: "6815297761 1 udp 659136 1.2.3.4 31102 typ host generation 0 ufrag b7l3"
  factory Candidate.fromSdp(String sdp) {
    final bits = sdp.split(' ');
    if (bits.length < 8) {
      throw ArgumentError('SDP does not have enough properties');
    }

    final kwargs = <String, dynamic>{
      'foundation': bits[0],
      'component': int.parse(bits[1]),
      'transport': bits[2],
      'priority': int.parse(bits[3]),
      'host': bits[4],
      'port': int.parse(bits[5]),
      'type': bits[7],
    };

    // Parse optional attributes
    for (var i = 8; i < bits.length - 1; i += 2) {
      switch (bits[i]) {
        case 'raddr':
          kwargs['relatedAddress'] = bits[i + 1];
          break;
        case 'rport':
          kwargs['relatedPort'] = int.parse(bits[i + 1]);
          break;
        case 'tcptype':
          kwargs['tcpType'] = bits[i + 1];
          break;
        case 'generation':
          kwargs['generation'] = int.parse(bits[i + 1]);
          break;
        case 'ufrag':
          kwargs['ufrag'] = bits[i + 1];
          break;
      }
    }

    return Candidate(
      foundation: kwargs['foundation'] as String,
      component: kwargs['component'] as int,
      transport: kwargs['transport'] as String,
      priority: kwargs['priority'] as int,
      host: kwargs['host'] as String,
      port: kwargs['port'] as int,
      type: kwargs['type'] as String,
      relatedAddress: kwargs['relatedAddress'] as String?,
      relatedPort: kwargs['relatedPort'] as int?,
      tcpType: kwargs['tcpType'] as String?,
      generation: kwargs['generation'] as int?,
      ufrag: kwargs['ufrag'] as String?,
    );
  }

  /// Check if this candidate can pair with another candidate
  /// A local candidate is paired with a remote candidate if and only if
  /// the two candidates have the same component ID and have the same IP
  /// address version.
  bool canPairWith(Candidate other) {
    final thisIsV4 = InternetAddress(host).type == InternetAddressType.IPv4;
    final otherIsV4 = InternetAddress(other.host).type == InternetAddressType.IPv4;

    return component == other.component &&
        transport.toLowerCase() == other.transport.toLowerCase() &&
        thisIsV4 == otherIsV4;
  }

  /// Convert candidate to SDP format
  String toSdp() {
    var sdp = '$foundation $component $transport $priority $host $port typ $type';

    if (relatedAddress != null) {
      sdp += ' raddr $relatedAddress';
    }
    if (relatedPort != null) {
      sdp += ' rport $relatedPort';
    }
    if (tcpType != null) {
      sdp += ' tcptype $tcpType';
    }
    if (generation != null) {
      sdp += ' generation $generation';
    }
    if (ufrag != null) {
      sdp += ' ufrag $ufrag';
    }

    return sdp;
  }

  @override
  String toString() {
    return 'Candidate($type, $host:$port, priority=$priority)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Candidate &&
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
int candidatePriority(String candidateType, [int localPref = 65535]) {
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

  // Priority formula: (2^24)*typePref + (2^8)*localPref + (256-componentId)
  return (1 << 24) * typePref + (1 << 8) * localPref + (256 - candidateComponent);
}
