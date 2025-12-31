import 'dart:async';
import 'dart:typed_data';

import 'package:webrtc_dart/src/common/logging.dart';
import 'package:webrtc_dart/src/datachannel/data_channel.dart';
import 'package:webrtc_dart/src/datachannel/data_channel_manager.dart' as dcm;
import 'package:webrtc_dart/src/dtls/certificate/certificate_generator.dart';
import 'package:webrtc_dart/src/dtls/context/transport.dart' as dtls_ctx;
import 'package:webrtc_dart/src/dtls/dtls_transport.dart';
import 'package:webrtc_dart/src/dtls/socket.dart';
import 'package:webrtc_dart/src/ice/ice_connection.dart';
import 'package:webrtc_dart/src/sctp/association.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';
import 'package:webrtc_dart/src/srtp/srtp_session.dart';
import 'package:webrtc_dart/src/transport/dtls_transport.dart' as rtc;
import 'package:webrtc_dart/src/transport/ice_gatherer.dart';
import 'package:webrtc_dart/src/transport/ice_transport.dart';

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
///
/// Internally uses RtcIceGatherer, RtcIceTransport, and RtcDtlsTransport wrappers
/// to align with werift-webrtc architecture.
class MediaTransport {
  /// Unique identifier (typically the MID from SDP)
  final String id;

  /// Associated m-line index (position in SDP media sections)
  int? mLineIndex;

  /// Debug label
  final String debugLabel;

  // ============= Internal Transport Wrappers =============

  /// ICE Gatherer (wraps IceConnection for candidate gathering)
  late final RtcIceGatherer _iceGatherer;

  /// ICE Transport (manages ICE connectivity state)
  late final RtcIceTransport _iceTransport;

  /// DTLS Transport (manages DTLS handshake and SRTP)
  late final rtc.RtcDtlsTransport _dtlsTransport;

  // ============= State and Event Streams =============

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

  /// Subscriptions
  StreamSubscription<RtcIceConnectionState>? _iceStateSubscription;
  StreamSubscription<RtpPacket>? _rtpSubscription;
  StreamSubscription<dynamic>? _rtcpSubscription;
  StreamSubscription<rtc.RtcDtlsState>? _dtlsStateSubscription;

  /// Whether DTLS handshake has been started
  bool _dtlsStarted = false;

  MediaTransport({
    required this.id,
    required IceConnection iceConnection,
    DtlsRole dtlsRole = DtlsRole.auto,
    CertificateKeyPair? certificate,
    this.debugLabel = '',
    this.mLineIndex,
  }) {
    // Create transport wrapper chain: IceGatherer -> IceTransport -> DtlsTransport
    _iceGatherer = RtcIceGatherer(iceConnection);
    _iceTransport = RtcIceTransport(_iceGatherer);

    // Map DtlsRole to RtcDtlsRole
    final rtcDtlsRole = switch (dtlsRole) {
      DtlsRole.auto => rtc.RtcDtlsRole.auto,
      DtlsRole.client => rtc.RtcDtlsRole.client,
      DtlsRole.server => rtc.RtcDtlsRole.server,
    };

    _dtlsTransport = rtc.RtcDtlsTransport(
      iceTransport: _iceTransport,
      localCertificate: certificate,
      role: rtcDtlsRole,
    );
    _dtlsTransport.debugLabel = debugLabel;

    // Subscribe to ICE transport state changes
    _iceStateSubscription =
        _iceTransport.onStateChange.listen(_handleIceStateChange);

    // Subscribe to DTLS transport state changes
    _dtlsStateSubscription =
        _dtlsTransport.onStateChange.listen(_handleDtlsStateChange);

    // Forward decrypted RTP packets from DTLS transport
    _rtpSubscription = _dtlsTransport.onRtp.listen((packet) {
      if (!_decryptedRtpController.isClosed) {
        _decryptedRtpController.add(packet);
      }
    });

    // Forward decrypted RTCP packets from DTLS transport (serialize to bytes)
    _rtcpSubscription = _dtlsTransport.onRtcp.listen((packet) {
      if (!_decryptedRtcpController.isClosed) {
        _decryptedRtcpController.add(packet.serialize());
      }
    });
  }

  // ============= Public API (backwards compatible) =============

  /// ICE connection for this transport
  IceConnection get iceConnection => _iceTransport.connection;

  /// DTLS socket (client or server)
  DtlsSocket? get dtlsSocket => _dtlsTransport.dtls;

  /// DTLS role getter
  DtlsRole get dtlsRole {
    final role = _dtlsTransport.role;
    return switch (role) {
      rtc.RtcDtlsRole.auto => DtlsRole.auto,
      rtc.RtcDtlsRole.client => DtlsRole.client,
      rtc.RtcDtlsRole.server => DtlsRole.server,
    };
  }

  /// DTLS role setter (must be set before connection is established)
  set dtlsRole(DtlsRole value) {
    final rtcRole = switch (value) {
      DtlsRole.auto => rtc.RtcDtlsRole.auto,
      DtlsRole.client => rtc.RtcDtlsRole.client,
      DtlsRole.server => rtc.RtcDtlsRole.server,
    };
    _dtlsTransport.role = rtcRole;
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
  SrtpSession? get srtpSession => _dtlsTransport.srtp;

  // ============= Internal State Handling =============

  /// Handle ICE transport state changes
  void _handleIceStateChange(RtcIceConnectionState iceState) async {
    switch (iceState) {
      case RtcIceConnectionState.new_:
        _setState(TransportState.new_);
        break;
      case RtcIceConnectionState.checking:
        // Don't regress from connected back to connecting
        if (_state != TransportState.connected) {
          _setState(TransportState.connecting);
        }
        break;
      case RtcIceConnectionState.connected:
      case RtcIceConnectionState.completed:
        // Start DTLS handshake when ICE is connected
        await _startDtlsHandshake();
        break;
      case RtcIceConnectionState.failed:
        _setState(TransportState.failed);
        break;
      case RtcIceConnectionState.disconnected:
        _setState(TransportState.disconnected);
        break;
      case RtcIceConnectionState.closed:
        _setState(TransportState.closed);
        break;
    }
  }

  /// Handle DTLS transport state changes
  void _handleDtlsStateChange(rtc.RtcDtlsState dtlsState) {
    switch (dtlsState) {
      case rtc.RtcDtlsState.connecting:
        // Already in connecting state from ICE
        break;
      case rtc.RtcDtlsState.connected:
        _logMedia.fine('[$debugLabel] DTLS connected');
        _setState(TransportState.connected);
        break;
      case rtc.RtcDtlsState.failed:
        _setState(TransportState.failed);
        break;
      case rtc.RtcDtlsState.closed:
        _setState(TransportState.closed);
        break;
      case rtc.RtcDtlsState.new_:
        break;
    }
  }

  /// Start DTLS handshake after ICE connection is established
  Future<void> _startDtlsHandshake() async {
    if (_dtlsStarted) {
      _logMedia.fine('[$debugLabel] DTLS already started, skipping');
      return;
    }
    _dtlsStarted = true;

    try {
      // Start DTLS handshake (don't require remote fingerprints for backwards compat)
      await _dtlsTransport.start(requireRemoteFingerprints: false);
    } catch (e) {
      _logMedia.fine('[$debugLabel] DTLS handshake failed: $e');
      _setState(TransportState.failed);
      rethrow;
    }
  }

  /// Start SRTP decryption (for backwards compat - now handled internally by RtcDtlsTransport)
  void startSrtp() {
    // SRTP is now started automatically by RtcDtlsTransport after DTLS connects
    // This method is kept for API compatibility
    _dtlsTransport.startSrtp();
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
    await _dtlsStateSubscription?.cancel();
    await _rtpSubscription?.cancel();
    await _rtcpSubscription?.cancel();

    await _dtlsTransport.stop();

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

  /// Debug label for logging
  String debugLabel = '';

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
///
/// Internally uses RtcIceGatherer, RtcIceTransport, and RtcDtlsTransport wrappers
/// to align with werift-webrtc architecture.
class IntegratedTransport {
  /// Debug label
  final String debugLabel;

  // ============= Internal Transport Wrappers =============

  /// ICE Gatherer (wraps IceConnection for candidate gathering)
  late final RtcIceGatherer _iceGatherer;

  /// ICE Transport (manages ICE connectivity state)
  late final RtcIceTransport _iceTransport;

  /// DTLS Transport (manages DTLS handshake and SRTP)
  late final rtc.RtcDtlsTransport _dtlsTransport;

  // ============= SCTP/DataChannel Components =============

  /// SCTP association for reliable data transport (optional)
  SctpAssociation? sctpAssociation;

  /// DataChannel manager
  dcm.DataChannelManager? dataChannelManager;

  /// Effective DTLS role (after auto-detection)
  /// Used for DataChannel stream ID allocation per RFC 8832
  rtc.RtcDtlsRole? _effectiveDtlsRole;

  // ============= State and Event Streams =============

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

  /// Buffer for SCTP packets that arrive before SCTP association is ready
  final List<Uint8List> _sctpPacketBuffer = [];

  /// Pending data channels created before SCTP is ready
  final List<PendingDataChannelConfig> _pendingDataChannels = [];

  /// Subscriptions
  StreamSubscription<RtcIceConnectionState>? _iceStateSubscription;
  StreamSubscription<RtpPacket>? _rtpSubscription;
  StreamSubscription<dynamic>? _rtcpSubscription;
  StreamSubscription<rtc.RtcDtlsState>? _dtlsStateSubscription;

  /// Whether DTLS handshake has been started
  bool _dtlsStarted = false;

  IntegratedTransport({
    required IceConnection iceConnection,
    DtlsRole dtlsRole = DtlsRole.auto,
    CertificateKeyPair? serverCertificate,
    this.debugLabel = '',
  }) {
    // Create transport wrapper chain: IceGatherer -> IceTransport -> DtlsTransport
    _iceGatherer = RtcIceGatherer(iceConnection);
    _iceTransport = RtcIceTransport(_iceGatherer);

    // Map DtlsRole to RtcDtlsRole
    final rtcDtlsRole = switch (dtlsRole) {
      DtlsRole.auto => rtc.RtcDtlsRole.auto,
      DtlsRole.client => rtc.RtcDtlsRole.client,
      DtlsRole.server => rtc.RtcDtlsRole.server,
    };

    _dtlsTransport = rtc.RtcDtlsTransport(
      iceTransport: _iceTransport,
      localCertificate: serverCertificate,
      role: rtcDtlsRole,
    );
    _dtlsTransport.debugLabel = debugLabel;

    // Set up SCTP data receiver on DTLS transport
    _dtlsTransport.dataReceiver = _handleSctpData;

    // Subscribe to ICE transport state changes
    _iceStateSubscription =
        _iceTransport.onStateChange.listen(_handleIceStateChange);

    // Subscribe to DTLS transport state changes
    _dtlsStateSubscription =
        _dtlsTransport.onStateChange.listen(_handleDtlsStateChange);

    // Forward decrypted RTP packets from DTLS transport
    _rtpSubscription = _dtlsTransport.onRtp.listen((packet) {
      if (!_decryptedRtpController.isClosed) {
        _decryptedRtpController.add(packet);
      }
    });

    // Forward decrypted RTCP packets from DTLS transport (serialize to bytes)
    _rtcpSubscription = _dtlsTransport.onRtcp.listen((packet) {
      if (!_decryptedRtcpController.isClosed) {
        _decryptedRtcpController.add(packet.serialize());
      }
    });

    // Check current ICE state and handle it
    _handleIceStateChange(_mapIceState(iceConnection.state));
  }

  // ============= Public API (backwards compatible) =============

  /// ICE connection for network connectivity
  IceConnection get iceConnection => _iceTransport.connection;

  /// DTLS socket (client or server)
  DtlsSocket? get dtlsSocket => _dtlsTransport.dtls;

  /// DTLS role getter (client or server)
  DtlsRole get dtlsRole {
    final role = _dtlsTransport.role;
    return switch (role) {
      rtc.RtcDtlsRole.auto => DtlsRole.auto,
      rtc.RtcDtlsRole.client => DtlsRole.client,
      rtc.RtcDtlsRole.server => DtlsRole.server,
    };
  }

  /// DTLS role setter (must be set before connection is established)
  set dtlsRole(DtlsRole value) {
    final rtcRole = switch (value) {
      DtlsRole.auto => rtc.RtcDtlsRole.auto,
      DtlsRole.client => rtc.RtcDtlsRole.client,
      DtlsRole.server => rtc.RtcDtlsRole.server,
    };
    _dtlsTransport.role = rtcRole;
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
  SrtpSession? get srtpSession => _dtlsTransport.srtp;

  // ============= Internal State Handling =============

  /// Handle SCTP data from DTLS transport
  void _handleSctpData(Uint8List data) async {
    if (sctpAssociation != null) {
      await sctpAssociation!.handlePacket(data);
    } else {
      // SCTP not ready yet, buffer the packet
      _sctpPacketBuffer.add(data);
    }
  }

  /// Map internal IceState to RtcIceConnectionState
  RtcIceConnectionState _mapIceState(IceState state) {
    return switch (state) {
      IceState.newState => RtcIceConnectionState.new_,
      IceState.gathering => RtcIceConnectionState.checking,
      IceState.checking => RtcIceConnectionState.checking,
      IceState.connected => RtcIceConnectionState.connected,
      IceState.completed => RtcIceConnectionState.completed,
      IceState.disconnected => RtcIceConnectionState.disconnected,
      IceState.failed => RtcIceConnectionState.failed,
      IceState.closed => RtcIceConnectionState.closed,
    };
  }

  /// Handle ICE transport state changes
  void _handleIceStateChange(RtcIceConnectionState iceState) async {
    _log.fine('[INTEGRATED:$debugLabel] ICE state: $iceState');
    switch (iceState) {
      case RtcIceConnectionState.new_:
        _setState(TransportState.new_);
        break;
      case RtcIceConnectionState.checking:
        // Don't regress from connected back to connecting
        if (_state != TransportState.connected) {
          _setState(TransportState.connecting);
        }
        break;
      case RtcIceConnectionState.connected:
      case RtcIceConnectionState.completed:
        // Start DTLS handshake when ICE is connected
        _log.fine('[INTEGRATED:$debugLabel] Starting DTLS handshake');
        await _startDtlsHandshake();
        break;
      case RtcIceConnectionState.failed:
        _setState(TransportState.failed);
        break;
      case RtcIceConnectionState.disconnected:
        _setState(TransportState.disconnected);
        break;
      case RtcIceConnectionState.closed:
        _setState(TransportState.closed);
        break;
    }
  }

  /// Handle DTLS transport state changes
  void _handleDtlsStateChange(rtc.RtcDtlsState dtlsState) async {
    _log.fine('[INTEGRATED:$debugLabel] DTLS state: $dtlsState');
    switch (dtlsState) {
      case rtc.RtcDtlsState.connecting:
        // Already in connecting state from ICE
        break;
      case rtc.RtcDtlsState.connected:
        _log.fine('[$debugLabel] DTLS handshake complete');
        _setState(TransportState.connected);
        _effectiveDtlsRole = _dtlsTransport.effectiveRole;
        // Start SCTP for data channels (asynchronously)
        await _startSctp();
        break;
      case rtc.RtcDtlsState.failed:
        _setState(TransportState.failed);
        break;
      case rtc.RtcDtlsState.closed:
        _setState(TransportState.closed);
        break;
      case rtc.RtcDtlsState.new_:
        break;
    }
  }

  /// Start DTLS handshake after ICE connection is established
  Future<void> _startDtlsHandshake() async {
    if (_dtlsStarted) {
      _log.fine('[$debugLabel] DTLS already started, skipping');
      return;
    }
    _dtlsStarted = true;

    try {
      // Start DTLS handshake (don't require remote fingerprints for backwards compat)
      await _dtlsTransport.start(requireRemoteFingerprints: false);
    } catch (e) {
      _log.fine('[$debugLabel] DTLS handshake failed: $e');
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
          // Send SCTP packets through DTLS transport
          if (_dtlsTransport.state == rtc.RtcDtlsState.connected) {
            await _dtlsTransport.sendData(packet);
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
        isDtlsServer: _effectiveDtlsRole == rtc.RtcDtlsRole.server,
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
    } else if (_dtlsTransport.state == rtc.RtcDtlsState.connected) {
      // Send directly via DTLS if SCTP not established
      await _dtlsTransport.sendData(data);
    } else {
      throw StateError('Transport not connected');
    }
  }

  /// Start SRTP decryption (for backwards compat - now handled internally by RtcDtlsTransport)
  void startSrtp() {
    // SRTP is now started automatically by RtcDtlsTransport after DTLS connects
    // This method is kept for API compatibility
    _dtlsTransport.startSrtp();
  }

  /// Set transport state
  void _setState(TransportState newState) {
    if (_state != newState) {
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
    await _dtlsStateSubscription?.cancel();
    await _rtpSubscription?.cancel();
    await _rtcpSubscription?.cancel();

    await dataChannelManager?.close();
    await sctpAssociation?.close();
    await _dtlsTransport.stop();

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
