import 'dart:async';
import 'dart:typed_data';

import 'package:webrtc_dart/src/common/logging.dart';
import 'package:webrtc_dart/src/dtls/certificate/certificate_generator.dart';
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/client.dart';
import 'package:webrtc_dart/src/dtls/context/cipher_context.dart';
import 'package:webrtc_dart/src/dtls/context/transport.dart' as dtls_ctx;
import 'package:webrtc_dart/src/dtls/server.dart';
import 'package:webrtc_dart/src/dtls/socket.dart';
import 'package:webrtc_dart/src/srtp/rtcp_packet.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';
import 'package:webrtc_dart/src/srtp/srtp_session.dart';
import 'package:webrtc_dart/src/transport/ice_transport.dart';

final _log = WebRtcLogging.transport;

/// DTLS transport state
/// Reference: https://w3c.github.io/webrtc-pc/#dom-rtcdtlstransportstate
enum RtcDtlsState {
  /// Initial state, DTLS has not started
  new_,

  /// DTLS handshake is in progress
  connecting,

  /// DTLS handshake complete, secure connection established
  connected,

  /// DTLS connection has been closed
  closed,

  /// DTLS connection failed
  failed,
}

/// DTLS role in the handshake
/// Reference: werift-webrtc/packages/webrtc/src/transport/dtls.ts
enum RtcDtlsRole {
  /// Auto-detect based on ICE role (controlling = server)
  auto,

  /// Act as DTLS server (wait for client hello)
  server,

  /// Act as DTLS client (send client hello)
  client,
}

/// DTLS fingerprint (certificate hash)
class RtcDtlsFingerprint {
  /// Hash algorithm (e.g., "sha-256")
  final String algorithm;

  /// Fingerprint value (colon-separated hex)
  final String value;

  const RtcDtlsFingerprint({
    required this.algorithm,
    required this.value,
  });

  @override
  String toString() => 'RtcDtlsFingerprint($algorithm: ${value.substring(0, 20)}...)';
}

/// DTLS parameters for negotiation
class RtcDtlsParameters {
  /// Certificate fingerprints
  final List<RtcDtlsFingerprint> fingerprints;

  /// DTLS role
  final RtcDtlsRole role;

  const RtcDtlsParameters({
    this.fingerprints = const [],
    this.role = RtcDtlsRole.auto,
  });
}

/// RTCDtlsTransport - Wraps DTLS socket and manages SRTP
/// Reference: werift-webrtc/packages/webrtc/src/transport/dtls.ts RTCDtlsTransport
///
/// The DTLS transport manages:
/// - DTLS handshake (client or server)
/// - SRTP key extraction after handshake
/// - RTP/RTCP encryption and decryption
/// - Data channel data transport (via sendData)
class RtcDtlsTransport {
  /// The associated ICE transport
  final RtcIceTransport iceTransport;

  /// Local certificate for DTLS handshake
  final CertificateKeyPair? localCertificate;

  /// Current DTLS state
  RtcDtlsState _state = RtcDtlsState.new_;

  /// DTLS role
  final RtcDtlsRole _role;

  /// Effective DTLS role (after auto-detection)
  RtcDtlsRole? _effectiveRole;

  /// Whether SRTP has been started
  bool srtpStarted = false;

  /// Transport-wide sequence number (for TWCC)
  int transportSequenceNumber = 0;

  /// Statistics tracking
  int bytesSent = 0;
  int bytesReceived = 0;
  int packetsSent = 0;
  int packetsReceived = 0;

  /// DTLS socket (client or server)
  DtlsSocket? dtls;

  /// SRTP session for encryption/decryption
  SrtpSession? srtp;

  /// Remote DTLS parameters
  RtcDtlsParameters? _remoteParameters;

  /// ICE to DTLS adapter (handles demux)
  late final _IceToDtlsAdapter _dtlsAdapter;

  /// Data receiver callback (for SCTP/DataChannel)
  void Function(Uint8List data)? dataReceiver;

  /// State change stream controller
  final _stateController = StreamController<RtcDtlsState>.broadcast();

  /// Decrypted RTP packet stream controller
  final _rtpController = StreamController<RtpPacket>.broadcast();

  /// Decrypted RTCP packet stream controller
  final _rtcpController = StreamController<RtcpPacket>.broadcast();

  /// Subscription to DTLS state changes
  StreamSubscription<DtlsSocketState>? _dtlsStateSubscription;

  /// Debug label
  String debugLabel = '';

  /// Creates an RTCDtlsTransport.
  ///
  /// [iceTransport] - The underlying ICE transport
  /// [localCertificate] - Local certificate for DTLS (required for server role)
  /// [role] - DTLS role (auto-detect if not specified)
  RtcDtlsTransport({
    required this.iceTransport,
    this.localCertificate,
    RtcDtlsRole role = RtcDtlsRole.auto,
  }) : _role = role {
    // Create the ICE-to-DTLS adapter for packet demuxing
    _dtlsAdapter = _IceToDtlsAdapter(iceTransport.connection);
  }

  /// Current DTLS state
  RtcDtlsState get state => _state;

  /// DTLS role
  RtcDtlsRole get role => _role;

  /// Effective DTLS role (after auto-detection)
  RtcDtlsRole? get effectiveRole => _effectiveRole;

  /// Stream of state changes
  Stream<RtcDtlsState> get onStateChange => _stateController.stream;

  /// Stream of decrypted RTP packets
  Stream<RtpPacket> get onRtp => _rtpController.stream;

  /// Stream of decrypted RTCP packets
  Stream<RtcpPacket> get onRtcp => _rtcpController.stream;

  /// Local DTLS parameters (fingerprints, role)
  RtcDtlsParameters get localParameters {
    if (localCertificate == null) {
      return RtcDtlsParameters(fingerprints: [], role: _role);
    }

    final fingerprint = computeCertificateFingerprint(localCertificate!.certificate);
    return RtcDtlsParameters(
      fingerprints: [
        RtcDtlsFingerprint(algorithm: 'sha-256', value: fingerprint),
      ],
      role: _role,
    );
  }

  /// Set remote DTLS parameters
  void setRemoteParams(RtcDtlsParameters params) {
    _remoteParameters = params;
  }

  /// Start DTLS handshake
  ///
  /// Throws if:
  /// - State is not "new"
  /// - Remote fingerprints are missing
  Future<void> start() async {
    if (_state != RtcDtlsState.new_) {
      throw StateError('DTLS state must be new, got $_state');
    }

    if (_remoteParameters?.fingerprints.isEmpty ?? true) {
      throw StateError('Remote DTLS fingerprints not set');
    }

    // Determine effective role
    if (_role == RtcDtlsRole.auto) {
      // Convention: ICE controlling agent acts as DTLS server
      // (This is the opposite of what you might expect, but matches werift)
      _effectiveRole = iceTransport.connection.iceControlling
          ? RtcDtlsRole.server
          : RtcDtlsRole.client;
      _log.fine('$_debugPrefix DTLS role auto-detected: $_effectiveRole '
          '(iceControlling=${iceTransport.connection.iceControlling})');
    } else {
      _effectiveRole = _role;
      _log.fine('$_debugPrefix DTLS role preset: $_effectiveRole');
    }

    _setState(RtcDtlsState.connecting);

    try {
      await _createDtlsSocket();
      await _performHandshake();
    } catch (e) {
      _log.warning('$_debugPrefix DTLS handshake failed: $e');
      _setState(RtcDtlsState.failed);
      rethrow;
    }
  }

  /// Create DTLS socket based on role
  Future<void> _createDtlsSocket() async {
    if (_effectiveRole == RtcDtlsRole.client) {
      CipherContext? clientCipherContext;
      if (localCertificate != null) {
        clientCipherContext = CipherContext(isClient: true);
        clientCipherContext.localCertificate = localCertificate!.certificate;
        clientCipherContext.localSigningKey = localCertificate!.privateKey;
        clientCipherContext.localFingerprint =
            computeCertificateFingerprint(localCertificate!.certificate);
      }

      dtls = DtlsClient(
        transport: _dtlsAdapter,
        cipherContext: clientCipherContext,
        cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
        supportedCurves: [NamedCurve.x25519, NamedCurve.secp256r1],
      );
    } else {
      // Server role requires certificate
      if (localCertificate == null) {
        throw StateError('Server certificate required for DTLS server role');
      }

      dtls = DtlsServer(
        transport: _dtlsAdapter,
        cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
        supportedCurves: [NamedCurve.x25519, NamedCurve.secp256r1],
        certificate: localCertificate!.certificate,
        privateKey: localCertificate!.privateKey,
      );
    }

    // Listen for DTLS data (for SCTP)
    dtls!.onData.listen((data) {
      if (dataReceiver != null) {
        dataReceiver!(data);
      }
    });

    // Note: DtlsSocket doesn't have onClose - closed state is detected via onStateChange
  }

  /// Perform DTLS handshake
  Future<void> _performHandshake() async {
    final completer = Completer<void>();

    _dtlsStateSubscription = dtls!.onStateChange.listen((dtlsState) {
      if (dtlsState == DtlsSocketState.connected) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      } else if (dtlsState == DtlsSocketState.failed) {
        _setState(RtcDtlsState.failed);
        if (!completer.isCompleted) {
          completer.completeError(StateError('DTLS handshake failed'));
        }
      } else if (dtlsState == DtlsSocketState.closed) {
        _setState(RtcDtlsState.closed);
      }
    });

    // Start handshake
    await dtls!.connect();

    // Wait for connected state
    await completer.future;

    // Start SRTP
    startSrtp();

    // Set state to connected
    _setState(RtcDtlsState.connected);

    _log.fine('$_debugPrefix DTLS connected');
  }

  /// Update SRTP session from DTLS keys
  void updateSrtpSession() {
    if (dtls == null) {
      throw StateError('DTLS socket not initialized');
    }

    final srtpContext = dtls!.srtpContext;
    if (srtpContext.localMasterKey == null ||
        srtpContext.localMasterSalt == null ||
        srtpContext.remoteMasterKey == null ||
        srtpContext.remoteMasterSalt == null ||
        srtpContext.profile == null) {
      throw StateError('SRTP keys not available from DTLS');
    }

    _log.fine('$_debugPrefix SRTP profile: ${srtpContext.profile}');

    srtp = SrtpSession(
      profile: srtpContext.profile!,
      localMasterKey: srtpContext.localMasterKey!,
      localMasterSalt: srtpContext.localMasterSalt!,
      remoteMasterKey: srtpContext.remoteMasterKey!,
      remoteMasterSalt: srtpContext.remoteMasterSalt!,
    );
  }

  /// Start SRTP session after DTLS connected
  void startSrtp() {
    if (srtpStarted) return;
    srtpStarted = true;

    updateSrtpSession();

    // Subscribe to encrypted SRTP packets from the adapter
    _dtlsAdapter.onSrtpData.listen((data) async {
      if (srtp == null) return;

      try {
        // Track received statistics
        bytesReceived += data.length;
        packetsReceived++;

        // Determine if this is RTP or RTCP based on payload type byte
        final isRtcpPacket = _isRtcp(data);

        if (isRtcpPacket) {
          // Decrypt SRTCP
          final rtcpPacket = await srtp!.decryptSrtcp(data);
          if (!_rtcpController.isClosed) {
            _rtcpController.add(rtcpPacket);
          }
        } else {
          // Decrypt SRTP
          final packet = await srtp!.decryptSrtp(data);
          if (!_rtpController.isClosed) {
            _rtpController.add(packet);
          }
        }
      } catch (e) {
        _log.warning('$_debugPrefix SRTP decryption error: $e');
      }
    });

    _log.fine('$_debugPrefix SRTP session started');
  }

  /// Check if a packet is RTCP (vs RTP)
  /// Uses payload type field (second byte, bits 0-6)
  bool _isRtcp(Uint8List data) {
    if (data.length < 2) return false;
    final payloadType = data[1] & 0x7F;
    // RTCP payload types are 72-76 (200-204 before masking)
    return payloadType >= 72 && payloadType <= 76;
  }

  /// Send application data (via DTLS)
  /// Used by SCTP for DataChannel data
  Future<void> sendData(Uint8List data) async {
    if (dtls == null) {
      throw StateError('DTLS not established');
    }
    await dtls!.send(data);
  }

  /// Send RTP packet (encrypts and sends via ICE)
  ///
  /// Returns the number of bytes sent (encrypted)
  Future<int> sendRtp(RtpPacket packet) async {
    if (srtp == null) {
      throw StateError('SRTP session not initialized');
    }

    try {
      final encrypted = await srtp!.encryptRtp(packet);

      // Track statistics
      bytesSent += encrypted.length;
      packetsSent++;

      await iceTransport.connection.send(encrypted);
      return encrypted.length;
    } catch (e) {
      _log.warning('$_debugPrefix Failed to send RTP: $e');
      return 0;
    }
  }

  /// Send RTCP packets (encrypts and sends via ICE)
  Future<void> sendRtcp(List<RtcpPacket> packets) async {
    if (srtp == null) {
      throw StateError('SRTP session not initialized');
    }

    // Serialize all RTCP packets into a compound packet
    final payloadParts = packets.map((p) => p.serialize()).toList();
    var totalLength = 0;
    for (final part in payloadParts) {
      totalLength += part.length;
    }
    final payload = Uint8List(totalLength);
    var offset = 0;
    for (final part in payloadParts) {
      payload.setRange(offset, offset + part.length, part);
      offset += part.length;
    }

    final encrypted = await srtp!.encryptRtcpCompound(payload);

    // Track statistics
    bytesSent += encrypted.length;
    packetsSent++;

    await iceTransport.connection.send(encrypted);
  }

  /// Stop and close the transport
  Future<void> stop() async {
    _setState(RtcDtlsState.closed);

    await _dtlsStateSubscription?.cancel();
    _dtlsStateSubscription = null;

    await dtls?.close();
    await _dtlsAdapter.close();
    await iceTransport.stop();

    await _stateController.close();
    await _rtpController.close();
    await _rtcpController.close();
  }

  /// Set state and emit event
  void _setState(RtcDtlsState state) {
    if (state != _state) {
      _log.fine('$_debugPrefix state change $_state -> $state');
      _state = state;
      if (!_stateController.isClosed) {
        _stateController.add(state);
      }
    }
  }

  String get _debugPrefix => '[RtcDtlsTransport${debugLabel.isNotEmpty ? ":$debugLabel" : ""}]';
}

/// Adapter that bridges ICE connection to DTLS transport interface
/// Also handles demultiplexing of DTLS vs SRTP packets (RFC 5764)
class _IceToDtlsAdapter implements dtls_ctx.DtlsTransport {
  final dynamic iceConnection; // IceConnection interface
  final StreamController<Uint8List> _receiveController =
      StreamController<Uint8List>.broadcast();

  /// Stream of SRTP/SRTCP packets (first byte 128-191)
  /// These bypass DTLS and go directly to SRTP session for decryption
  final StreamController<Uint8List> _srtpController =
      StreamController<Uint8List>.broadcast();

  bool _isOpen = true;
  StreamSubscription? _iceDataSubscription;

  _IceToDtlsAdapter(this.iceConnection) {
    // Demux packets from ICE based on first byte (RFC 5764 Section 5.1.2)
    // - 0-3: Reserved (STUN handled by ICE)
    // - 20-63: DTLS
    // - 128-191: RTP/RTCP (SRTP encrypted)
    _iceDataSubscription = iceConnection.onData.listen((Uint8List data) {
      if (_isOpen && data.isNotEmpty) {
        final firstByte = data[0];

        if (firstByte >= 20 && firstByte <= 63) {
          // DTLS packet - forward to DTLS transport
          _receiveController.add(data);
        } else if (firstByte >= 128 && firstByte <= 191) {
          // RTP/RTCP packet (SRTP encrypted) - bypass DTLS
          _srtpController.add(data);
        } else {
          // Unknown packet type - forward to DTLS as fallback
          _receiveController.add(data);
        }
      }
    });
  }

  /// Stream of SRTP/SRTCP packets that bypass DTLS
  Stream<Uint8List> get onSrtpData => _srtpController.stream;

  @override
  Future<void> send(Uint8List data) async {
    if (!_isOpen) {
      throw StateError('Transport is closed');
    }
    await iceConnection.send(data);
  }

  @override
  Stream<Uint8List> get onData => _receiveController.stream;

  @override
  Future<void> close() async {
    if (_isOpen) {
      _isOpen = false;
      await _iceDataSubscription?.cancel();
      await _receiveController.close();
      await _srtpController.close();
    }
  }

  @override
  bool get isOpen => _isOpen;
}
