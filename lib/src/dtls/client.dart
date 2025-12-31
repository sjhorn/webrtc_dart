import 'dart:typed_data';

import 'package:webrtc_dart/src/common/logging.dart';
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/cipher/key_derivation.dart';
import 'package:webrtc_dart/src/dtls/client_handshake.dart';
import 'package:webrtc_dart/src/dtls/context/cipher_context.dart';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/use_srtp.dart';
import 'package:webrtc_dart/src/dtls/handshake/handshake_header.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/alert.dart';
import 'package:webrtc_dart/src/dtls/record/const.dart';
import 'package:webrtc_dart/src/dtls/record/record_layer.dart';
import 'package:webrtc_dart/src/dtls/socket.dart';

final _log = WebRtcLogging.dtlsClient;

/// DTLS Client
/// Initiates DTLS handshake as the client
class DtlsClient extends DtlsSocket {
  /// Supported cipher suites
  final List<CipherSuite> cipherSuites;

  /// Supported elliptic curves
  final List<NamedCurve> supportedCurves;

  /// Supported SRTP profiles
  final List<SrtpProtectionProfile> srtpProfiles;

  /// Handshake coordinator
  late final ClientHandshakeCoordinator _handshakeCoordinator;

  /// Record layer
  late final DtlsRecordLayer _recordLayer;

  /// Processing lock to ensure sequential message processing
  Future<void>? _processingLock;

  /// Buffer for future-epoch records that arrive before CCS
  final List<Uint8List> _futureEpochBuffer = [];

  DtlsClient({
    required super.transport,
    super.dtlsContext,
    CipherContext? cipherContext,
    super.srtpContext,
    List<CipherSuite>? cipherSuites,
    List<NamedCurve>? supportedCurves,
    List<SrtpProtectionProfile>? srtpProfiles,
  })  : cipherSuites = cipherSuites ??
            [
              CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256,
              CipherSuite.tlsEcdheRsaWithAes128GcmSha256,
            ],
        supportedCurves =
            supportedCurves ?? [NamedCurve.x25519, NamedCurve.secp256r1],
        srtpProfiles = srtpProfiles ??
            [
              SrtpProtectionProfile.srtpAeadAes128Gcm,
              SrtpProtectionProfile.srtpAes128CmHmacSha1_80,
            ],
        super(
          cipherContext: cipherContext ?? CipherContext(isClient: true),
          initialState: DtlsSocketState.closed,
        ) {
    // Initialize record layer
    _recordLayer = DtlsRecordLayer(
      dtlsContext: dtlsContext,
      cipherContext: this.cipherContext,
    );

    // Initialize handshake coordinator
    _handshakeCoordinator = ClientHandshakeCoordinator(
      dtlsContext: dtlsContext,
      cipherContext: this.cipherContext,
      srtpContext: srtpContext,
      recordLayer: _recordLayer,
      flightManager: flightManager,
      cipherSuites: this.cipherSuites,
      supportedCurves: this.supportedCurves,
    );
  }

  @override
  Future<void> connect() async {
    if (state != DtlsSocketState.closed) {
      throw StateError('Client already connecting or connected');
    }

    initializeTransport();
    setState(DtlsSocketState.connecting);

    try {
      // Start handshake via coordinator
      await _handshakeCoordinator.start();

      // Send the initial ClientHello flight
      await _sendPendingFlights();
    } catch (e) {
      setState(DtlsSocketState.failed);
      rethrow;
    }
  }

  @override
  Future<void> send(Uint8List data) async {
    if (!isConnected) {
      throw StateError('Cannot send data: socket not connected');
    }

    // Create application data record
    final record = _recordLayer.wrapApplicationData(data);

    // Encrypt and send
    final encrypted = await _recordLayer.encryptRecord(record);
    await transport.send(encrypted);
  }

  @override
  void processReceivedData(Uint8List data) async {
    // Ensure sequential processing by chaining with previous processing
    _processingLock = (_processingLock ?? Future.value()).then((_) async {
      try {
        // Parse DTLS records - this returns records that match current readEpoch
        // Future-epoch records are returned with a special marker
        final records = await _recordLayer.processRecordsWithFutureEpoch(
          data,
          _futureEpochBuffer,
        );

        bool ccsReceived = false;
        for (final processed in records) {
          switch (processed.contentType) {
            case ContentType.handshake:
              await _processHandshakeRecord(processed.data);
              break;

            case ContentType.changeCipherSpec:
              // CCS received - increment read epoch for decryption
              _log.fine(
                'Received ChangeCipherSpec, incrementing readEpoch from ${dtlsContext.readEpoch} to ${dtlsContext.readEpoch + 1}',
              );
              dtlsContext.readEpoch++;
              ccsReceived = true;
              break;

            case ContentType.applicationData:
              // Application data received
              if (isConnected) {
                dataController.add(processed.data);
              }
              break;

            case ContentType.alert:
              // Alert received - handle error
              await _processAlert(processed.data);
              break;
          }
        }

        // If we received CCS, reprocess any buffered future-epoch records
        if (ccsReceived && _futureEpochBuffer.isNotEmpty) {
          _log.fine(
            'Reprocessing ${_futureEpochBuffer.length} buffered future-epoch records',
          );
          final bufferedData = List<Uint8List>.from(_futureEpochBuffer);
          _futureEpochBuffer.clear();
          for (final buffered in bufferedData) {
            await _processBufferedRecord(buffered);
          }
        }

        // Check if handshake is complete (but not if we're closed)
        if (_handshakeCoordinator.isComplete && !isConnected && !isClosed) {
          _onHandshakeComplete();
        }
      } catch (e) {
        if (!isClosed && !errorController.isClosed) {
          errorController.add(e);
          setState(DtlsSocketState.failed);
        }
      }
    });
  }

  /// Process a buffered record that was received before CCS
  Future<void> _processBufferedRecord(Uint8List data) async {
    try {
      final records = await _recordLayer.processRecords(data);
      for (final processed in records) {
        switch (processed.contentType) {
          case ContentType.handshake:
            await _processHandshakeRecord(processed.data);
            break;
          case ContentType.applicationData:
            if (isConnected) {
              dataController.add(processed.data);
            }
            break;
          case ContentType.alert:
            await _processAlert(processed.data);
            break;
          default:
            break;
        }
      }
    } catch (e) {
      _log.fine('Error processing buffered record: $e');
    }
  }

  /// Process handshake record
  /// Note: A single record may contain multiple handshake messages
  Future<void> _processHandshakeRecord(Uint8List data) async {
    // Parse all handshake messages from the record
    final messages = HandshakeMessage.parseMultiple(data);

    // Process each message via coordinator
    for (final handshakeMsg in messages) {
      // Pass the full message (header + body) for handshake buffer
      // The coordinator will add the full message to the handshake buffer
      // Use rawBytes if available to preserve original bytes for handshake hash
      final fullMessage = handshakeMsg.rawBytes ?? handshakeMsg.serialize();
      _log.fine(
        'Processing ${handshakeMsg.header.messageType}, rawBytes available: ${handshakeMsg.rawBytes != null}, fullMessage len: ${fullMessage.length}',
      );
      await _handshakeCoordinator.processHandshakeWithType(
        handshakeMsg.header.messageType,
        handshakeMsg.body,
        fullMessage: fullMessage,
      );
    }

    // Send any pending flights
    await _sendPendingFlights();
  }

  /// Send pending flights
  Future<void> _sendPendingFlights() async {
    final currentFlight = flightManager.currentFlight;
    if (currentFlight != null &&
        !currentFlight.sent &&
        currentFlight.messages.isNotEmpty) {
      _log.fine(
        'Sending flight ${currentFlight.flight.flightNumber} with ${currentFlight.messages.length} messages',
      );
      for (var i = 0; i < currentFlight.messages.length; i++) {
        final message = currentFlight.messages[i];
        _log.fine('  Message $i: ${message.length} bytes');
        await transport.send(message);
      }
      currentFlight.markSent();
    }
  }

  /// Called when handshake completes
  void _onHandshakeComplete() {
    _log.info('Handshake complete!');

    // Export SRTP keys if profile was negotiated
    if (srtpContext.profile != null) {
      final srtpKeyMaterial = KeyDerivation.exportSrtpKeys(
        dtlsContext,
        srtpContext.keyMaterialLength,
        true, // isClient
      );

      // Store raw material and extract individual keys
      srtpContext.keyMaterial = srtpKeyMaterial;
      srtpContext.extractKeys(srtpKeyMaterial, true);

      _log.fine('Exported SRTP keys for profile ${srtpContext.profile}');
      _log.fine(
          'Local key: ${srtpContext.localMasterKey?.length} bytes, salt: ${srtpContext.localMasterSalt?.length} bytes');
      _log.fine(
          'Remote key: ${srtpContext.remoteMasterKey?.length} bytes, salt: ${srtpContext.remoteMasterSalt?.length} bytes');
    } else {
      _log.fine('No SRTP profile negotiated, skipping key export');
    }

    // Mark as connected
    dtlsContext.handshakeComplete = true;
    setState(DtlsSocketState.connected);
  }

  /// Process alert message
  Future<void> _processAlert(Uint8List data) async {
    try {
      final alert = Alert.parse(data);
      _log.fine('Received alert: $alert');

      if (alert.isFatal) {
        _log.warning('Fatal alert received, closing connection');
        if (!isClosed && !errorController.isClosed) {
          errorController.add(Exception('Fatal alert: ${alert.description}'));
          setState(DtlsSocketState.failed);
        }
        await close();
      } else if (alert.description == AlertDescription.closeNotify) {
        _log.fine('Close notify received, closing connection');
        await close();
      } else {
        _log.warning('Alert: ${alert.description}');
      }
    } catch (e) {
      _log.warning('Error processing alert: $e');
      if (!isClosed && !errorController.isClosed) {
        errorController.add(e);
      }
    }
  }

  /// Send alert message
  Future<void> sendAlert(Alert alert) async {
    try {
      final alertRecord = _recordLayer.wrapAlert(alert);
      final serialized = await _recordLayer.encryptRecord(alertRecord);
      await transport.send(serialized);
      _log.fine('Sent alert: $alert');
    } catch (e) {
      _log.warning('Error sending alert: $e');
    }
  }
}
