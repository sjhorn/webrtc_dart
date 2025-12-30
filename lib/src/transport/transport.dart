import 'dart:async';
import 'dart:typed_data';

import 'package:webrtc_dart/src/common/logging.dart';
import 'package:webrtc_dart/src/datachannel/data_channel.dart';
import 'package:webrtc_dart/src/datachannel/data_channel_manager.dart' as dcm;
import 'package:webrtc_dart/src/dtls/certificate/certificate_generator.dart';
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/client.dart';
import 'package:webrtc_dart/src/dtls/context/cipher_context.dart';
import 'package:webrtc_dart/src/dtls/context/transport.dart' as dtls_ctx;
import 'package:webrtc_dart/src/dtls/dtls_transport.dart';
import 'package:webrtc_dart/src/dtls/server.dart';
import 'package:webrtc_dart/src/dtls/socket.dart';
import 'package:webrtc_dart/src/ice/ice_connection.dart';
import 'package:webrtc_dart/src/sctp/association.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';
import 'package:webrtc_dart/src/srtp/srtp_session.dart';

final _log = WebRtcLogging.transport;
final _logMedia = WebRtcLogging.transportMedia;
final _logDemux = WebRtcLogging.transportDemux;

/// Transport state
enum TransportState {
  new_,
  connecting,
  connected,
  disconnected,
  failed,
  closed,
}

/// MediaTransport encapsulates ICE + DTLS + SRTP for a single media line
/// This supports bundlePolicy: "disable" where each m-line has its own transport
class MediaTransport {
  /// Unique identifier (typically the MID from SDP)
  final String id;

  /// Associated m-line index (position in SDP media sections)
  int? mLineIndex;

  /// ICE connection for this transport
  final IceConnection iceConnection;

  /// ICE to DTLS adapter (demultiplexes DTLS vs SRTP)
  late final IceToDtlsAdapter _dtlsAdapter;

  /// DTLS socket (client or server)
  DtlsSocket? dtlsSocket;

  /// DTLS role (client or server)
  DtlsRole dtlsRole;

  /// Server certificate (for DTLS handshake)
  final CertificateKeyPair? certificate;

  /// Debug label
  final String debugLabel;

  /// Current transport state
  TransportState _state = TransportState.new_;

  /// State change stream
  final _stateController = StreamController<TransportState>.broadcast();

  /// RTP/RTCP data stream (encrypted SRTP - for backwards compat)
  final _rtpDataController = StreamController<Uint8List>.broadcast();

  /// Decrypted RTP packet stream (matching werift DtlsTransport.onRtp)
  final _decryptedRtpController = StreamController<RtpPacket>.broadcast();

  /// Decrypted RTCP packet stream (matching werift DtlsTransport.onRtcp)
  final _decryptedRtcpController = StreamController<Uint8List>.broadcast();

  /// SRTP session for decrypting incoming media packets
  SrtpSession? _srtpSession;

  /// Whether SRTP has been started
  bool _srtpStarted = false;

  /// ICE state subscription
  StreamSubscription<IceState>? _iceStateSubscription;

  MediaTransport({
    required this.id,
    required this.iceConnection,
    this.dtlsRole = DtlsRole.auto,
    this.certificate,
    this.debugLabel = '',
    this.mLineIndex,
  }) {
    // Create ICE to DTLS adapter
    _dtlsAdapter = IceToDtlsAdapter(iceConnection);

    // Forward SRTP packets
    _dtlsAdapter.onSrtpData.listen((data) {
      if (!_rtpDataController.isClosed) {
        _rtpDataController.add(data);
      }
    });

    // Listen to ICE state changes
    _iceStateSubscription =
        iceConnection.onStateChanged.listen(_handleIceStateChange);
  }

  /// Get current state
  TransportState get state => _state;

  /// Stream of state changes
  Stream<TransportState> get onStateChange => _stateController.stream;

  /// Stream of RTP/RTCP packets (encrypted SRTP - for backwards compat)
  Stream<Uint8List> get onRtpData => _rtpDataController.stream;

  /// Stream of decrypted RTP packets (matching werift DtlsTransport.onRtp)
  Stream<RtpPacket> get onRtp => _decryptedRtpController.stream;

  /// Stream of decrypted RTCP packets (matching werift DtlsTransport.onRtcp)
  Stream<Uint8List> get onRtcp => _decryptedRtcpController.stream;

  /// Get the SRTP session (for encryption of outgoing packets)
  SrtpSession? get srtpSession => _srtpSession;

  /// Handle ICE state changes
  void _handleIceStateChange(IceState iceState) async {
    switch (iceState) {
      case IceState.newState:
        _setState(TransportState.new_);
        break;
      case IceState.checking:
      case IceState.gathering:
        // Don't regress from connected back to connecting
        // This can happen with late ICE candidates (trickle ICE)
        if (_state != TransportState.connected) {
          _setState(TransportState.connecting);
        }
        break;
      case IceState.connected:
      case IceState.completed:
        // Start DTLS handshake when ICE is connected
        await _startDtlsHandshake();
        break;
      case IceState.failed:
        _setState(TransportState.failed);
        break;
      case IceState.disconnected:
        _setState(TransportState.disconnected);
        break;
      case IceState.closed:
        _setState(TransportState.closed);
        break;
    }
  }

  /// Start DTLS handshake after ICE connection is established
  Future<void> _startDtlsHandshake() async {
    if (dtlsSocket != null) {
      _logMedia.fine('[$debugLabel] DTLS already started, skipping');
      return; // Already started
    }

    try {
      // Determine DTLS role
      DtlsRole effectiveRole = dtlsRole;
      if (dtlsRole == DtlsRole.auto) {
        // Convention: ICE controlling agent acts as DTLS client
        effectiveRole =
            iceConnection.iceControlling ? DtlsRole.client : DtlsRole.server;
        _log.fine(
            '[MEDIA-TRANSPORT:$debugLabel] DTLS role auto-detected: ${effectiveRole == DtlsRole.client ? "client" : "server"} (iceControlling=${iceConnection.iceControlling})');
      } else {
        _log.fine(
            '[MEDIA-TRANSPORT:$debugLabel] DTLS role preset: ${effectiveRole == DtlsRole.client ? "client" : "server"}');
      }

      // Create DTLS socket based on role
      if (effectiveRole == DtlsRole.client) {
        CipherContext? clientCipherContext;
        if (certificate != null) {
          clientCipherContext = CipherContext(isClient: true);
          clientCipherContext.localCertificate = certificate!.certificate;
          clientCipherContext.localSigningKey = certificate!.privateKey;
          clientCipherContext.localFingerprint =
              computeCertificateFingerprint(certificate!.certificate);
          _log.fine(
              '[MEDIA-TRANSPORT:$debugLabel] DTLS client configured with certificate');
        }
        dtlsSocket = DtlsClient(
          transport: _dtlsAdapter,
          cipherContext: clientCipherContext,
          cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
          supportedCurves: [NamedCurve.x25519, NamedCurve.secp256r1],
        );
      } else {
        // Server role requires certificate
        if (certificate == null) {
          throw StateError('Server certificate required for DTLS server role');
        }
        dtlsSocket = DtlsServer(
          transport: _dtlsAdapter,
          cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
          supportedCurves: [NamedCurve.x25519, NamedCurve.secp256r1],
          certificate: certificate!.certificate,
          privateKey: certificate!.privateKey,
        );
      }

      // Listen for DTLS state changes
      dtlsSocket!.onStateChange.listen((dtlsState) async {
        if (dtlsState == DtlsSocketState.connected) {
          _logMedia.fine('[$debugLabel] DTLS connected');
          _setState(TransportState.connected);

          // Start SRTP decryption (emits decrypted packets via onRtp/onRtcp)
          startSrtp();
        } else if (dtlsState == DtlsSocketState.failed) {
          _setState(TransportState.failed);
        }
      });

      // Start handshake
      await dtlsSocket!.connect();
    } catch (e) {
      _logMedia.fine('[$debugLabel] DTLS handshake failed: $e');
      _setState(TransportState.failed);
      rethrow;
    }
  }

  /// Start SRTP decryption after DTLS handshake completes.
  /// This matches werift's DtlsTransport pattern where onRtp emits decrypted packets.
  void startSrtp() {
    if (_srtpStarted) return;
    _srtpStarted = true;

    if (dtlsSocket == null) {
      _logMedia.warning('[$debugLabel] startSrtp called but dtlsSocket is null');
      return;
    }

    final srtpContext = dtlsSocket!.srtpContext;
    if (srtpContext.localMasterKey == null ||
        srtpContext.localMasterSalt == null ||
        srtpContext.remoteMasterKey == null ||
        srtpContext.remoteMasterSalt == null ||
        srtpContext.profile == null) {
      _logMedia.warning(
          '[$debugLabel] SRTP keys not available - skipping SRTP setup');
      return;
    }

    // Create SRTP session from DTLS-exported keys
    _srtpSession = SrtpSession(
      profile: srtpContext.profile!,
      localMasterKey: srtpContext.localMasterKey!,
      localMasterSalt: srtpContext.localMasterSalt!,
      remoteMasterKey: srtpContext.remoteMasterKey!,
      remoteMasterSalt: srtpContext.remoteMasterSalt!,
    );

    _logMedia.fine('[$debugLabel] SRTP session initialized');

    // Subscribe to encrypted SRTP packets and decrypt them
    _dtlsAdapter.onSrtpData.listen((data) async {
      if (_srtpSession == null) return;

      try {
        // Determine if this is RTP or RTCP based on payload type byte
        final payloadType = data[1] & 0x7F;
        final isRtcp = payloadType >= 72 && payloadType <= 76;

        if (isRtcp) {
          // Decrypt SRTCP and emit as raw bytes
          final rtcpPacket = await _srtpSession!.decryptSrtcp(data);
          if (!_decryptedRtcpController.isClosed) {
            _decryptedRtcpController.add(rtcpPacket.serialize());
          }
        } else {
          // Decrypt SRTP and emit as RtpPacket
          final packet = await _srtpSession!.decryptSrtp(data);
          if (!_decryptedRtpController.isClosed) {
            _decryptedRtpController.add(packet);
          }
        }
      } catch (e) {
        _logMedia.warning('[$debugLabel] SRTP decryption error: $e');
      }
    });
  }

  /// Set transport state
  void _setState(TransportState newState) {
    if (_state != newState) {
      _logMedia.fine('[$debugLabel] State: $_state -> $newState');
      _state = newState;
      if (!_stateController.isClosed) {
        _stateController.add(newState);
      }
    }
  }

  /// Close the transport
  Future<void> close() async {
    _setState(TransportState.closed);

    await _iceStateSubscription?.cancel();
    await dtlsSocket?.close();
    await _dtlsAdapter.close();
    await iceConnection.close();

    await _stateController.close();
    await _rtpDataController.close();
    await _decryptedRtpController.close();
    await _decryptedRtcpController.close();
  }

  @override
  String toString() {
    return 'MediaTransport(id=$id, state=$_state, ice=${iceConnection.state})';
  }
}

/// Adapter that bridges ICE connection to DTLS transport interface
/// Also handles demultiplexing of DTLS vs SRTP packets (RFC 5764)
class IceToDtlsAdapter implements dtls_ctx.DtlsTransport {
  final IceConnection iceConnection;
  final StreamController<Uint8List> _receiveController =
      StreamController<Uint8List>.broadcast();

  /// Stream of SRTP/SRTCP packets (first byte 128-191)
  /// These bypass DTLS and go directly to SRTP session for decryption
  final StreamController<Uint8List> _srtpController =
      StreamController<Uint8List>.broadcast();

  bool _isOpen = true;
  StreamSubscription? _iceDataSubscription;

  IceToDtlsAdapter(this.iceConnection) {
    // Demux packets from ICE based on first byte (RFC 5764 Section 5.1.2)
    // - 0-3: Reserved (STUN handled by ICE)
    // - 20-63: DTLS
    // - 128-191: RTP/RTCP (SRTP encrypted)
    _iceDataSubscription = iceConnection.onData.listen((data) {
      if (_isOpen && data.isNotEmpty) {
        final firstByte = data[0];

        if (firstByte >= 20 && firstByte <= 63) {
          // DTLS packet - forward to DTLS transport
          _logDemux.fine(
              ' DTLS packet received: ${data.length} bytes, firstByte=$firstByte');
          _receiveController.add(data);
        } else if (firstByte >= 128 && firstByte <= 191) {
          // RTP/RTCP packet (SRTP encrypted) - bypass DTLS
          // These need SRTP decryption, not DTLS decryption
          _logDemux.fine(
              ' SRTP packet received: ${data.length} bytes, firstByte=$firstByte');
          _srtpController.add(data);
        } else {
          // Unknown packet type - forward to DTLS as fallback
          _logDemux.fine(
              ' Unknown packet type: ${data.length} bytes, firstByte=$firstByte');
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
    _logDemux.fine(' Sending DTLS packet: ${data.length} bytes, firstByte=${data.isNotEmpty ? data[0] : "empty"}');
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

/// Integrated transport layer
/// Connects ICE → DTLS → SCTP for WebRTC data flow
class IntegratedTransport {
  /// ICE connection for network connectivity
  final IceConnection iceConnection;

  /// DTLS socket (client or server)
  DtlsSocket? dtlsSocket;

  /// DTLS role (client or server)
  /// Can be set by peer connection based on SDP negotiation
  DtlsRole dtlsRole;

  /// Effective DTLS role (after auto-detection)
  /// Used for DataChannel stream ID allocation per RFC 8832
  DtlsRole? _effectiveDtlsRole;

  /// Server certificate (required if acting as DTLS server)
  final CertificateKeyPair? serverCertificate;

  /// SCTP association for reliable data transport (optional)
  SctpAssociation? sctpAssociation;

  /// DataChannel manager
  dcm.DataChannelManager? dataChannelManager;

  /// Debug label
  final String debugLabel;

  /// Current transport state
  TransportState _state = TransportState.new_;

  /// State change stream
  final _stateController = StreamController<TransportState>.broadcast();

  /// Data received stream (decrypted application data from DTLS)
  final _dataController = StreamController<Uint8List>.broadcast();

  /// DataChannel stream
  final _dataChannelController = StreamController<DataChannel>.broadcast();

  /// RTP/RTCP data stream (encrypted SRTP - kept for backwards compat)
  final _rtpDataController = StreamController<Uint8List>.broadcast();

  /// Decrypted RTP packet stream (matching werift DtlsTransport.onRtp)
  final _decryptedRtpController = StreamController<RtpPacket>.broadcast();

  /// Decrypted RTCP packet stream (matching werift DtlsTransport.onRtcp)
  final _decryptedRtcpController = StreamController<Uint8List>.broadcast();

  /// SRTP session for decrypting incoming media packets
  SrtpSession? _srtpSession;

  /// Whether SRTP has been started
  bool _srtpStarted = false;

  /// ICE to DTLS adapter
  IceToDtlsAdapter? _dtlsAdapter;

  /// Buffer for SCTP packets that arrive before SCTP association is ready
  final List<Uint8List> _sctpPacketBuffer = [];

  /// Pending data channels created before SCTP is ready
  final List<PendingDataChannelConfig> _pendingDataChannels = [];

  IntegratedTransport({
    required this.iceConnection,
    this.dtlsRole = DtlsRole.auto,
    this.serverCertificate,
    this.debugLabel = '',
  }) {
    // Create ICE to DTLS adapter immediately
    // This ensures we're ready to receive DTLS packets as soon as they arrive
    _dtlsAdapter = IceToDtlsAdapter(iceConnection);

    // Listen to ICE state changes
    iceConnection.onStateChanged.listen(_handleIceStateChange);

    // Check current ICE state and handle it
    _handleIceStateChange(iceConnection.state);
  }

  /// Get current state
  TransportState get state => _state;

  /// Stream of state changes
  Stream<TransportState> get onStateChange => _stateController.stream;

  /// Stream of received data (after DTLS decryption)
  Stream<Uint8List> get onData => _dataController.stream;

  /// Stream of new incoming DataChannels
  Stream<DataChannel> get onDataChannel => _dataChannelController.stream;

  /// Stream of RTP/RTCP packets (encrypted SRTP - for backwards compat)
  Stream<Uint8List> get onRtpData => _rtpDataController.stream;

  /// Stream of decrypted RTP packets (matching werift DtlsTransport.onRtp)
  Stream<RtpPacket> get onRtp => _decryptedRtpController.stream;

  /// Stream of decrypted RTCP packets (matching werift DtlsTransport.onRtcp)
  Stream<Uint8List> get onRtcp => _decryptedRtcpController.stream;

  /// Get the SRTP session (for encryption of outgoing packets)
  SrtpSession? get srtpSession => _srtpSession;

  /// Handle ICE state changes
  void _handleIceStateChange(IceState iceState) async {
    switch (iceState) {
      case IceState.newState:
        _setState(TransportState.new_);
        break;
      case IceState.checking:
      case IceState.gathering:
        // Don't regress from connected back to connecting
        // This can happen with late ICE candidates (trickle ICE)
        if (_state != TransportState.connected) {
          _setState(TransportState.connecting);
        }
        break;
      case IceState.connected:
      case IceState.completed:
        // Start DTLS handshake when ICE is connected
        await _startDtlsHandshake();
        break;
      case IceState.failed:
        _setState(TransportState.failed);
        break;
      case IceState.disconnected:
        _setState(TransportState.disconnected);
        break;
      case IceState.closed:
        _setState(TransportState.closed);
        break;
    }
  }

  /// Start DTLS handshake after ICE connection is established
  Future<void> _startDtlsHandshake() async {
    if (dtlsSocket != null) {
      _log.fine('[$debugLabel] DTLS already started, skipping');
      return; // Already started
    }

    try {
      // Determine DTLS role
      DtlsRole effectiveRole = dtlsRole;
      if (dtlsRole == DtlsRole.auto) {
        // Convention: ICE controlling agent acts as DTLS client
        effectiveRole =
            iceConnection.iceControlling ? DtlsRole.client : DtlsRole.server;
        _log.fine(
            '[TRANSPORT:$debugLabel] DTLS role auto-detected: ${effectiveRole == DtlsRole.client ? "client" : "server"} (iceControlling=${iceConnection.iceControlling})');
      } else {
        _log.fine(
            '[TRANSPORT:$debugLabel] DTLS role preset: ${effectiveRole == DtlsRole.client ? "client" : "server"}');
      }

      // Store effective role for DataChannel stream ID allocation per RFC 8832
      _effectiveDtlsRole = effectiveRole;

      // Create DTLS socket based on role
      if (effectiveRole == DtlsRole.client) {
        // For WebRTC, client also needs certificate for mutual authentication
        CipherContext? clientCipherContext;
        if (serverCertificate != null) {
          clientCipherContext = CipherContext(isClient: true);
          clientCipherContext.localCertificate = serverCertificate!.certificate;
          clientCipherContext.localSigningKey = serverCertificate!.privateKey;
          clientCipherContext.localFingerprint =
              computeCertificateFingerprint(serverCertificate!.certificate);
          _log.fine(
              '[TRANSPORT:$debugLabel] DTLS client configured with certificate (fingerprint: ${clientCipherContext.localFingerprint})');
        }
        dtlsSocket = DtlsClient(
          transport: _dtlsAdapter!,
          cipherContext: clientCipherContext,
          cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
          supportedCurves: [NamedCurve.x25519, NamedCurve.secp256r1],
        );
      } else {
        // Server role requires certificate
        if (serverCertificate == null) {
          throw StateError('Server certificate required for DTLS server role');
        }
        dtlsSocket = DtlsServer(
          transport: _dtlsAdapter!,
          cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
          supportedCurves: [NamedCurve.x25519, NamedCurve.secp256r1],
          certificate: serverCertificate!.certificate,
          privateKey: serverCertificate!.privateKey,
        );
      }

      // Listen for DTLS state changes
      dtlsSocket!.onStateChange.listen((dtlsState) async {
        if (dtlsState == DtlsSocketState.connected) {
          // Set connected state immediately for media (RTP/RTCP) to work
          // SCTP may establish later for data channels, but media shouldn't wait
          _log.fine('[$debugLabel] DTLS handshake complete');
          _setState(TransportState.connected);

          // Start SRTP decryption (emits decrypted packets via onRtp/onRtcp)
          startSrtp();

          // Start SCTP for data channels (asynchronously)
          await _startSctp();
        } else if (dtlsState == DtlsSocketState.failed) {
          _setState(TransportState.failed);
        }
      });

      // Listen for SRTP packets from the ICE adapter (bypasses DTLS)
      // These are encrypted with SRTP keys (exported from DTLS), not DTLS keys
      _dtlsAdapter!.onSrtpData.listen((data) {
        // Forward SRTP/SRTCP packets to media handlers
        _rtpDataController.add(data);
      });

      // Listen for decrypted application data from DTLS
      // After demux at ICE layer, only SCTP data comes through here
      dtlsSocket!.onData.listen((data) async {
        // All data from DTLS at this point should be SCTP (DataChannel)
        // RTP/RTCP is now handled by the SRTP listener above
        if (sctpAssociation != null) {
          await sctpAssociation!.handlePacket(data);
        } else {
          // SCTP not ready yet, buffer the packet
          _sctpPacketBuffer.add(data);
        }
      });

      // Start handshake
      await dtlsSocket!.connect();
    } catch (e) {
      _setState(TransportState.failed);
      rethrow;
    }
  }

  /// Start SCTP association after DTLS is connected
  Future<void> _startSctp() async {
    if (sctpAssociation != null) {
      return; // Already started
    }

    try {
      // Create SCTP association
      sctpAssociation = SctpAssociation(
        localPort: 5000, // Standard SCTP port for WebRTC
        remotePort: 5000,
        onSendPacket: (packet) async {
          // Send SCTP packets through DTLS
          if (dtlsSocket != null &&
              dtlsSocket!.state == DtlsSocketState.connected) {
            await dtlsSocket!.send(packet);
          }
        },
        onReceiveData: (streamId, data, ppid) {
          // Route to DataChannel manager if available
          if (dataChannelManager != null) {
            dataChannelManager!.handleIncomingData(streamId, data, ppid);
          } else {
            // No DataChannel manager, deliver raw data
            _dataController.add(data);
          }
        },
      );

      // Listen for SCTP state changes
      sctpAssociation!.onStateChange.listen((sctpState) async {
        if (sctpState == SctpAssociationState.established) {
          _setState(TransportState.connected);

          // Initialize any pending data channels NOW that SCTP is established
          _initializePendingDataChannels();
        }
      });

      // Create DataChannel manager with proper stream ID allocation
      // Per RFC 8832: DTLS server uses odd stream IDs (1, 3, 5, ...)
      dataChannelManager = dcm.DataChannelManager(
        association: sctpAssociation!,
        isDtlsServer: _effectiveDtlsRole == DtlsRole.server,
      );

      // Forward new DataChannels to stream
      dataChannelManager!.onDataChannel.listen((channel) {
        _dataChannelController.add(channel);
      });

      // Process any buffered SCTP packets that arrived before association was ready
      if (_sctpPacketBuffer.isNotEmpty) {
        for (final packet in _sctpPacketBuffer) {
          await sctpAssociation!.handlePacket(packet);
        }
        _sctpPacketBuffer.clear();
      }

      // Start SCTP handshake
      // Following werift pattern: ICE controlling side initiates SCTP
      // This aligns with the common case where ICE controlling is also DTLS client,
      // but uses ICE role as the definitive signal (like werift does)
      _log.fine('[$debugLabel] SCTP: dtlsRole=$_effectiveDtlsRole, iceControlling=${iceConnection.iceControlling}');
      if (iceConnection.iceControlling) {
        // ICE controlling initiates SCTP (like werift)
        _log.fine('[$debugLabel] SCTP: initiating as ICE controlling');
        await sctpAssociation!.connect();
      } else {
        // ICE controlled waits for INIT from remote
        _log.fine('[$debugLabel] SCTP: waiting for INIT (ICE controlled)');
      }
    } catch (e) {
      // SCTP setup failed, but don't fail the whole transport
      // DataChannels may not be used
    }
  }

  /// Initialize pending data channels after SCTP is established
  void _initializePendingDataChannels() {
    _log.fine('[$debugLabel] _initializePendingDataChannels called, '
        'pending=${_pendingDataChannels.length}, '
        'manager=${dataChannelManager != null}');
    if (_pendingDataChannels.isEmpty || dataChannelManager == null) {
      return;
    }

    for (final config in _pendingDataChannels) {
      _log.fine('[$debugLabel] Creating real DataChannel: ${config.label}');
      // Create the real channel now that SCTP is ready
      final realChannel = dataChannelManager!.createDataChannel(
        label: config.label,
        protocol: config.protocol,
        ordered: config.ordered,
        maxRetransmits: config.maxRetransmits,
        maxPacketLifeTime: config.maxPacketLifeTime,
        priority: config.priority,
      );
      _log.fine('[$debugLabel] Real channel created: $realChannel');
      // Wire up the proxy to the real channel
      config.proxy.initializeWithChannel(realChannel);
      _log.fine('[$debugLabel] Proxy initialized');
    }
    _pendingDataChannels.clear();
  }

  /// Create a new DataChannel
  /// If SCTP is not yet ready, returns a ProxyDataChannel that will be
  /// initialized once the connection is established.
  /// Returns DataChannel for type compatibility (ProxyDataChannel has same API)
  dynamic createDataChannel({
    required String label,
    String protocol = '',
    bool ordered = true,
    int? maxRetransmits,
    int? maxPacketLifeTime,
    int priority = 0,
  }) {
    // If SCTP is established, create channel immediately
    if (dataChannelManager != null &&
        sctpAssociation != null &&
        sctpAssociation!.state == SctpAssociationState.established) {
      return dataChannelManager!.createDataChannel(
        label: label,
        protocol: protocol,
        ordered: ordered,
        maxRetransmits: maxRetransmits,
        maxPacketLifeTime: maxPacketLifeTime,
        priority: priority,
      );
    }

    // SCTP not ready yet - create proxy channel that will be wired up later
    final proxy = ProxyDataChannel(
      label: label,
      protocol: protocol,
      ordered: ordered,
      maxRetransmits: maxRetransmits,
      maxPacketLifeTime: maxPacketLifeTime,
      priority: priority,
    );

    final config = PendingDataChannelConfig(
      label: label,
      proxy: proxy,
      protocol: protocol,
      ordered: ordered,
      maxRetransmits: maxRetransmits,
      maxPacketLifeTime: maxPacketLifeTime,
      priority: priority,
    );

    _pendingDataChannels.add(config);
    return proxy;
  }

  /// Send data through the transport stack
  /// Data flows: Application → SCTP → DTLS encryption → ICE
  Future<void> send(Uint8List data) async {
    if (_state != TransportState.connected) {
      throw StateError('Transport not connected');
    }

    if (sctpAssociation != null &&
        sctpAssociation!.state == SctpAssociationState.established) {
      // Send via SCTP (will be encrypted by DTLS)
      await sctpAssociation!.sendData(
        streamId: 0,
        data: data,
        ppid: 51, // WebRTC String (PPID 51)
      );
    } else if (dtlsSocket != null &&
        dtlsSocket!.state == DtlsSocketState.connected) {
      // Send directly via DTLS if SCTP not established
      await dtlsSocket!.send(data);
    } else {
      throw StateError('Transport not connected');
    }
  }

  /// Start SRTP decryption after DTLS handshake completes.
  /// This matches werift's DtlsTransport pattern where onRtp emits decrypted packets.
  void startSrtp() {
    if (_srtpStarted) return;
    _srtpStarted = true;

    if (dtlsSocket == null) {
      _log.warning('[$debugLabel] startSrtp called but dtlsSocket is null');
      return;
    }

    final srtpContext = dtlsSocket!.srtpContext;
    if (srtpContext.localMasterKey == null ||
        srtpContext.localMasterSalt == null ||
        srtpContext.remoteMasterKey == null ||
        srtpContext.remoteMasterSalt == null ||
        srtpContext.profile == null) {
      _log.warning(
          '[$debugLabel] SRTP keys not available - skipping SRTP setup');
      return;
    }

    // Create SRTP session from DTLS-exported keys
    _srtpSession = SrtpSession(
      profile: srtpContext.profile!,
      localMasterKey: srtpContext.localMasterKey!,
      localMasterSalt: srtpContext.localMasterSalt!,
      remoteMasterKey: srtpContext.remoteMasterKey!,
      remoteMasterSalt: srtpContext.remoteMasterSalt!,
    );

    _log.fine('[$debugLabel] SRTP session initialized');

    // Subscribe to encrypted SRTP packets and decrypt them
    _dtlsAdapter!.onSrtpData.listen((data) async {
      if (_srtpSession == null) return;

      try {
        // Determine if this is RTP or RTCP based on payload type byte
        // RTP: payload type is in second byte bits 0-6 (0-127)
        // RTCP: payload type is in second byte (200-204 for SR, RR, SDES, BYE, APP)
        final payloadType = data[1] & 0x7F;
        final isRtcp = payloadType >= 72 && payloadType <= 76;
        // Note: RTCP types are 200-204, but after masking with 0x7F they become 72-76

        if (isRtcp) {
          // Decrypt SRTCP and emit as raw bytes
          final rtcpPacket = await _srtpSession!.decryptSrtcp(data);
          if (!_decryptedRtcpController.isClosed) {
            _decryptedRtcpController.add(rtcpPacket.serialize());
          }
        } else {
          // Decrypt SRTP and emit as RtpPacket
          final packet = await _srtpSession!.decryptSrtp(data);
          if (!_decryptedRtpController.isClosed) {
            _decryptedRtpController.add(packet);
          }
        }
      } catch (e) {
        _log.warning('[$debugLabel] SRTP decryption error: $e');
      }
    });
  }

  /// Set transport state
  void _setState(TransportState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  /// Close the transport
  Future<void> close() async {
    _setState(TransportState.closed);

    await dataChannelManager?.close();
    await sctpAssociation?.close();
    await dtlsSocket?.close();
    await _dtlsAdapter?.close();
    await iceConnection.close();

    await _stateController.close();
    await _dataController.close();
    await _dataChannelController.close();
    await _rtpDataController.close();
    await _decryptedRtpController.close();
    await _decryptedRtcpController.close();
  }

  @override
  String toString() {
    return 'IntegratedTransport(state=$_state, ice=${iceConnection.state})';
  }
}
