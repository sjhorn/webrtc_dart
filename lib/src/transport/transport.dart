import 'dart:async';
import 'dart:typed_data';
import 'package:webrtc_dart/src/ice/ice_connection.dart';
import 'package:webrtc_dart/src/dtls/dtls_transport.dart';
import 'package:webrtc_dart/src/dtls/client.dart';
import 'package:webrtc_dart/src/dtls/server.dart';
import 'package:webrtc_dart/src/dtls/socket.dart';
import 'package:webrtc_dart/src/dtls/context/transport.dart' as dtls_ctx;
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/certificate/certificate_generator.dart';
import 'package:webrtc_dart/src/sctp/association.dart';
import 'package:webrtc_dart/src/datachannel/data_channel.dart';
import 'package:webrtc_dart/src/datachannel/data_channel_manager.dart' as dcm;

/// Transport state
enum TransportState {
  new_,
  connecting,
  connected,
  disconnected,
  failed,
  closed,
}

/// Adapter that bridges ICE connection to DTLS transport interface
class IceToDtlsAdapter implements dtls_ctx.DtlsTransport {
  final IceConnection iceConnection;
  final StreamController<Uint8List> _receiveController =
      StreamController<Uint8List>.broadcast();
  bool _isOpen = true;
  StreamSubscription? _iceDataSubscription;

  IceToDtlsAdapter(this.iceConnection) {
    // Forward non-STUN data from ICE to DTLS
    _iceDataSubscription = iceConnection.onData.listen((data) {
      if (_isOpen) {
        _receiveController.add(data);
      }
    });
  }

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
  final DtlsRole dtlsRole;

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

  /// RTP/RTCP data stream (for media packets)
  final _rtpDataController = StreamController<Uint8List>.broadcast();

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

  /// Stream of RTP/RTCP packets (for media)
  Stream<Uint8List> get onRtpData => _rtpDataController.stream;

  /// Handle ICE state changes
  void _handleIceStateChange(IceState iceState) async {
    switch (iceState) {
      case IceState.newState:
        _setState(TransportState.new_);
        break;
      case IceState.checking:
      case IceState.gathering:
        _setState(TransportState.connecting);
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
      return; // Already started
    }

    try {
      // Determine DTLS role
      DtlsRole effectiveRole = dtlsRole;
      if (dtlsRole == DtlsRole.auto) {
        // Convention: ICE controlling agent acts as DTLS client
        effectiveRole = iceConnection.iceControlling ? DtlsRole.client : DtlsRole.server;
      }

      // Create DTLS socket based on role
      if (effectiveRole == DtlsRole.client) {
        dtlsSocket = DtlsClient(
          transport: _dtlsAdapter!,
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
          // Don't mark as connected yet - wait for SCTP
          // Start SCTP after DTLS is connected
          await _startSctp();
        } else if (dtlsState == DtlsSocketState.failed) {
          _setState(TransportState.failed);
        }
      });

      // Listen for decrypted application data from DTLS
      // Demux between SCTP (DataChannels) and RTP/RTCP (media)
      dtlsSocket!.onData.listen((data) async {
        if (data.length >= 2) {
          // Demux using first byte according to RFC 5761 and RFC 7983
          // STUN:       0-3
          // DTLS:       20-63
          // RTP/RTCP:   128-191 (version bits 10 in first 2 bits)
          // SCTP:       Other values
          final firstByte = data[0];

          if (firstByte >= 128 && firstByte <= 191) {
            // RTP or RTCP packet
            // Further distinguish using second byte:
            // RTCP payload types are 192-223
            final secondByte = data[1];
            if (secondByte >= 192 && secondByte <= 223) {
              // RTCP packet
              _rtpDataController.add(data);
            } else {
              // RTP packet
              _rtpDataController.add(data);
            }
          } else {
            // SCTP packet - feed to association
            if (sctpAssociation != null) {
              await sctpAssociation!.handlePacket(data);
            } else {
              // SCTP not ready yet, buffer the packet
              _sctpPacketBuffer.add(data);
            }
          }
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
          if (dtlsSocket != null && dtlsSocket!.state == DtlsSocketState.connected) {
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
      sctpAssociation!.onStateChange.listen((sctpState) {
        if (sctpState == SctpAssociationState.established) {
          _setState(TransportState.connected);

          // Initialize any pending data channels NOW that SCTP is established
          _initializePendingDataChannels();
        }
      });

      // Create DataChannel manager
      dataChannelManager = dcm.DataChannelManager(association: sctpAssociation!);

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
      // Determine if we're client or server based on ICE role
      if (iceConnection.iceControlling) {
        // Controlling side initiates SCTP
        await sctpAssociation!.connect();
      }
      // Controlled side waits for INIT from remote
    } catch (e) {
      // SCTP setup failed, but don't fail the whole transport
      // DataChannels may not be used
    }
  }

  /// Initialize pending data channels after SCTP is established
  void _initializePendingDataChannels() {
    if (_pendingDataChannels.isEmpty || dataChannelManager == null) {
      return;
    }

    for (final config in _pendingDataChannels) {
      // Create the real channel now that SCTP is ready
      final realChannel = dataChannelManager!.createDataChannel(
        label: config.label,
        protocol: config.protocol,
        ordered: config.ordered,
        maxRetransmits: config.maxRetransmits,
        maxPacketLifeTime: config.maxPacketLifeTime,
        priority: config.priority,
      );
      // Wire up the proxy to the real channel
      config.proxy.initializeWithChannel(realChannel);
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
    } else if (dtlsSocket != null && dtlsSocket!.state == DtlsSocketState.connected) {
      // Send directly via DTLS if SCTP not established
      await dtlsSocket!.send(data);
    } else {
      throw StateError('Transport not connected');
    }
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
  }

  @override
  String toString() {
    return 'IntegratedTransport(state=$_state, ice=${iceConnection.state})';
  }
}
