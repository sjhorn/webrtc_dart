import 'dart:async';
import 'dart:typed_data';

/// DTLS connection state
enum DtlsState {
  /// Initial state
  newState,

  /// Handshake in progress
  connecting,

  /// Handshake complete, secure channel established
  connected,

  /// Connection failed
  failed,

  /// Connection closed
  closed,
}

/// DTLS role in handshake
enum DtlsRole {
  /// Acts as DTLS client
  client,

  /// Acts as DTLS server
  server,

  /// Role determined automatically
  auto,
}

/// SRTP key material extracted from DTLS
class SrtpKeys {
  /// Local (send) key material
  final Uint8List localKey;

  /// Local (send) salt
  final Uint8List localSalt;

  /// Remote (receive) key material
  final Uint8List remoteKey;

  /// Remote (receive) salt
  final Uint8List remoteSalt;

  SrtpKeys({
    required this.localKey,
    required this.localSalt,
    required this.remoteKey,
    required this.remoteSalt,
  });
}

/// Certificate fingerprint
class CertificateFingerprint {
  /// Hash algorithm (e.g., "sha-256")
  final String algorithm;

  /// Fingerprint value (hex string with colons)
  final String value;

  CertificateFingerprint({
    required this.algorithm,
    required this.value,
  });

  @override
  String toString() => '$algorithm $value';
}

/// DTLS transport for secure communication over UDP
///
/// DTLS (Datagram TLS) provides encryption and authentication for
/// UDP-based communication. It's used in WebRTC to secure the data
/// channel (SCTP) and to derive keys for SRTP.
abstract class DtlsTransport {
  /// Current DTLS state
  DtlsState get state;

  /// Local certificate fingerprint
  CertificateFingerprint get localFingerprint;

  /// Remote certificate fingerprint (set during handshake)
  CertificateFingerprint? get remoteFingerprint;

  /// DTLS role
  DtlsRole get role;

  /// Stream of state changes
  Stream<DtlsState> get onStateChanged;

  /// Stream of decrypted application data
  Stream<Uint8List> get onData;

  /// Set remote fingerprint for verification
  void setRemoteFingerprint(CertificateFingerprint fingerprint);

  /// Start DTLS handshake
  ///
  /// [role] specifies whether to act as client or server
  Future<void> start({required DtlsRole role});

  /// Send encrypted application data
  ///
  /// Data will be encrypted and sent over the underlying transport.
  /// Can only be called after handshake is complete.
  Future<void> send(Uint8List data);

  /// Get SRTP key material after successful handshake
  ///
  /// This extracts the keying material using the DTLS-SRTP exporter.
  /// Must be called after handshake is complete.
  SrtpKeys getSrtpKeys();

  /// Close the DTLS transport
  Future<void> close();
}
