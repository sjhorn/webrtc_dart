import 'rtc_stats.dart';

/// DTLS transport state
enum RTCDtlsTransportState {
  newState('new'),
  connecting('connecting'),
  connected('connected'),
  closed('closed'),
  failed('failed');

  final String value;
  const RTCDtlsTransportState(this.value);

  @override
  String toString() => value;
}

/// ICE transport state for stats
enum RTCIceTransportState {
  newState('new'),
  checking('checking'),
  connected('connected'),
  completed('completed'),
  disconnected('disconnected'),
  failed('failed'),
  closed('closed');

  final String value;
  const RTCIceTransportState(this.value);

  @override
  String toString() => value;
}

/// ICE role
enum RTCIceRole {
  unknown('unknown'),
  controlling('controlling'),
  controlled('controlled');

  final String value;
  const RTCIceRole(this.value);

  @override
  String toString() => value;
}

/// RTCTransportStats - Statistics for the transport layer
/// Includes ICE and DTLS transport statistics
class RTCTransportStats extends RTCStats {
  /// Number of bytes sent
  final int? bytesSent;

  /// Number of bytes received
  final int? bytesReceived;

  /// Number of packets sent
  final int? packetsSent;

  /// Number of packets received
  final int? packetsReceived;

  /// RTCP transport stats ID (if using separate RTCP transport)
  final String? rtcpTransportStatsId;

  /// ICE local candidate type
  final String? iceLocalCandidateId;

  /// ICE remote candidate type
  final String? iceRemoteCandidateId;

  /// Current ICE state
  final RTCIceTransportState? iceState;

  /// Selected candidate pair ID
  final String? selectedCandidatePairId;

  /// Selected candidate pair changes count
  final int? selectedCandidatePairChanges;

  /// Local certificate stats ID
  final String? localCertificateId;

  /// Remote certificate stats ID
  final String? remoteCertificateId;

  /// TLS version used
  final String? tlsVersion;

  /// DTLS cipher suite
  final String? dtlsCipher;

  /// DTLS state
  final RTCDtlsTransportState? dtlsState;

  /// SRTP cipher suite
  final String? srtpCipher;

  /// TLS group (key exchange algorithm)
  final String? tlsGroup;

  /// ICE role (controlling or controlled)
  final RTCIceRole? iceRole;

  /// ICE local username fragment
  final String? iceLocalUsernameFragment;

  const RTCTransportStats({
    required super.timestamp,
    required super.id,
    this.bytesSent,
    this.bytesReceived,
    this.packetsSent,
    this.packetsReceived,
    this.rtcpTransportStatsId,
    this.iceLocalCandidateId,
    this.iceRemoteCandidateId,
    this.iceState,
    this.selectedCandidatePairId,
    this.selectedCandidatePairChanges,
    this.localCertificateId,
    this.remoteCertificateId,
    this.tlsVersion,
    this.dtlsCipher,
    this.dtlsState,
    this.srtpCipher,
    this.tlsGroup,
    this.iceRole,
    this.iceLocalUsernameFragment,
  }) : super(type: RTCStatsType.transport);

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json.addAll({
      if (bytesSent != null) 'bytesSent': bytesSent,
      if (bytesReceived != null) 'bytesReceived': bytesReceived,
      if (packetsSent != null) 'packetsSent': packetsSent,
      if (packetsReceived != null) 'packetsReceived': packetsReceived,
      if (rtcpTransportStatsId != null)
        'rtcpTransportStatsId': rtcpTransportStatsId,
      if (iceLocalCandidateId != null)
        'iceLocalCandidateId': iceLocalCandidateId,
      if (iceRemoteCandidateId != null)
        'iceRemoteCandidateId': iceRemoteCandidateId,
      if (iceState != null) 'iceState': iceState!.value,
      if (selectedCandidatePairId != null)
        'selectedCandidatePairId': selectedCandidatePairId,
      if (selectedCandidatePairChanges != null)
        'selectedCandidatePairChanges': selectedCandidatePairChanges,
      if (localCertificateId != null) 'localCertificateId': localCertificateId,
      if (remoteCertificateId != null)
        'remoteCertificateId': remoteCertificateId,
      if (tlsVersion != null) 'tlsVersion': tlsVersion,
      if (dtlsCipher != null) 'dtlsCipher': dtlsCipher,
      if (dtlsState != null) 'dtlsState': dtlsState!.value,
      if (srtpCipher != null) 'srtpCipher': srtpCipher,
      if (tlsGroup != null) 'tlsGroup': tlsGroup,
      if (iceRole != null) 'iceRole': iceRole!.value,
      if (iceLocalUsernameFragment != null)
        'iceLocalUsernameFragment': iceLocalUsernameFragment,
    });
    return json;
  }
}

/// RTCCertificateStats - Statistics for certificates
class RTCCertificateStats extends RTCStats {
  /// Fingerprint of the certificate
  final String fingerprint;

  /// Algorithm used for the fingerprint (e.g., 'sha-256')
  final String fingerprintAlgorithm;

  /// Base64-encoded DER certificate
  final String? base64Certificate;

  /// ID of the issuer certificate stats (for certificate chains)
  final String? issuerCertificateId;

  const RTCCertificateStats({
    required super.timestamp,
    required super.id,
    required this.fingerprint,
    required this.fingerprintAlgorithm,
    this.base64Certificate,
    this.issuerCertificateId,
  }) : super(type: RTCStatsType.certificate);

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json.addAll({
      'fingerprint': fingerprint,
      'fingerprintAlgorithm': fingerprintAlgorithm,
      if (base64Certificate != null) 'base64Certificate': base64Certificate,
      if (issuerCertificateId != null)
        'issuerCertificateId': issuerCertificateId,
    });
    return json;
  }
}
