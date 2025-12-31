import 'dart:async';
import 'dart:typed_data';

import 'package:webrtc_dart/src/common/logging.dart';
import 'package:webrtc_dart/src/dtls/cipher/prf.dart';
import 'package:webrtc_dart/src/dtls/context/cipher_context.dart';
import 'package:webrtc_dart/src/dtls/context/dtls_context.dart';
import 'package:webrtc_dart/src/dtls/context/srtp_context.dart';
import 'package:webrtc_dart/src/dtls/context/transport.dart';
import 'package:webrtc_dart/src/dtls/flight/flight.dart';

final _log = WebRtcLogging.dtls;

/// DTLS Socket States
enum DtlsSocketState {
  closed,
  connecting,
  connected,
  failed,
}

/// Base DTLS Socket class
/// Provides common functionality for client and server
abstract class DtlsSocket {
  /// Transport layer
  final DtlsTransport transport;

  /// DTLS context (protocol state)
  final DtlsContext dtlsContext;

  /// Cipher context (cryptographic state)
  final CipherContext cipherContext;

  /// SRTP context (SRTP keying material)
  final SrtpContext srtpContext;

  /// Flight manager for handshake
  final FlightManager flightManager;

  /// Current socket state
  DtlsSocketState _state;

  /// Stream controller for state changes
  final StreamController<DtlsSocketState> _stateController;

  /// Stream controller for received application data
  final StreamController<Uint8List> _dataController;

  /// Stream controller for errors
  final StreamController<Object> _errorController;

  /// Subscription to transport data
  StreamSubscription<Uint8List>? _transportSubscription;

  /// Expose data controller for subclasses
  StreamController<Uint8List> get dataController => _dataController;

  /// Expose error controller for subclasses
  StreamController<Object> get errorController => _errorController;

  DtlsSocket({
    required this.transport,
    DtlsContext? dtlsContext,
    CipherContext? cipherContext,
    SrtpContext? srtpContext,
    FlightManager? flightManager,
    DtlsSocketState initialState = DtlsSocketState.closed,
  })  : dtlsContext = dtlsContext ?? DtlsContext(),
        cipherContext = cipherContext ?? CipherContext(),
        srtpContext = srtpContext ?? SrtpContext(),
        flightManager = flightManager ?? FlightManager(),
        _state = initialState,
        _stateController = StreamController<DtlsSocketState>.broadcast(),
        _dataController = StreamController<Uint8List>.broadcast(),
        _errorController = StreamController<Object>.broadcast();

  /// Current socket state
  DtlsSocketState get state => _state;

  /// Stream of state changes
  Stream<DtlsSocketState> get onStateChange => _stateController.stream;

  /// Stream of received application data
  Stream<Uint8List> get onData => _dataController.stream;

  /// Stream of errors
  Stream<Object> get onError => _errorController.stream;

  /// Check if socket is connected
  bool get isConnected => _state == DtlsSocketState.connected;

  /// Check if socket is closed
  bool get isClosed => _state == DtlsSocketState.closed;

  /// Update socket state
  /// Protected method for subclasses
  void setState(DtlsSocketState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  /// Start the DTLS handshake
  Future<void> connect();

  /// Send application data (after handshake complete)
  /// Subclasses must implement this to use their record layer
  Future<void> send(Uint8List data);

  /// Handle received data from transport
  void _handleTransportData(Uint8List data) {
    try {
      // Parse DTLS records and process
      processReceivedData(data);
    } catch (e) {
      if (!isClosed && !_errorController.isClosed) {
        _errorController.add(e);
      }
    }
  }

  /// Process received DTLS records
  /// Subclasses must implement this to handle records
  void processReceivedData(Uint8List data);

  /// Close the socket
  Future<void> close() async {
    if (_state == DtlsSocketState.closed) {
      return;
    }

    setState(DtlsSocketState.closed);

    // Cancel transport subscription
    await _transportSubscription?.cancel();
    _transportSubscription = null;

    // Close transport
    await transport.close();

    // Close stream controllers
    await _stateController.close();
    await _dataController.close();
    await _errorController.close();

    // Clear flight manager
    flightManager.clear();
  }

  /// Initialize transport subscription
  /// Protected method for subclasses
  void initializeTransport() {
    _transportSubscription = transport.onData.listen(
      _handleTransportData,
      onError: (error) {
        if (!isClosed && !_errorController.isClosed) {
          _errorController.add(error);
        }
      },
    );
  }

  /// Export SRTP keying material
  /// RFC 5764 Section 4.2
  Future<void> exportSrtpKeys() async {
    if (dtlsContext.masterSecret == null) {
      throw StateError('Master secret not available');
    }

    if (srtpContext.profile == null) {
      // No SRTP profile negotiated - this is OK for data-only connections
      _log.fine('No SRTP profile negotiated, skipping key export');
      return;
    }

    if (dtlsContext.localRandom == null || dtlsContext.remoteRandom == null) {
      throw StateError('Random values not available');
    }

    // Export keying material using RFC 5705 PRF
    // Label is "EXTRACTOR-dtls_srtp" per RFC 5764 Section 4.2
    final keyingMaterial = exportKeyingMaterial(
      'EXTRACTOR-dtls_srtp',
      srtpContext.keyMaterialLength,
      dtlsContext.masterSecret!,
      dtlsContext.localRandom!,
      dtlsContext.remoteRandom!,
      cipherContext.isClient,
    );

    // Extract individual keys from keying material
    srtpContext.extractKeys(keyingMaterial, cipherContext.isClient);

    _log.fine('Exported SRTP keys for profile ${srtpContext.profile}');
    _log.fine(
        'Local key: ${srtpContext.localMasterKey?.length} bytes, salt: ${srtpContext.localMasterSalt?.length} bytes');
    _log.fine(
        'Remote key: ${srtpContext.remoteMasterKey?.length} bytes, salt: ${srtpContext.remoteMasterSalt?.length} bytes');
  }
}
