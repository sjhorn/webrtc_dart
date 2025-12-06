import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/cipher/key_derivation.dart';
import 'package:webrtc_dart/src/dtls/context/cipher_context.dart';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/handshake_header.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/alert.dart';
import 'package:webrtc_dart/src/dtls/record/const.dart';
import 'package:webrtc_dart/src/dtls/record/record_layer.dart';
import 'package:webrtc_dart/src/dtls/server_handshake.dart';
import 'package:webrtc_dart/src/dtls/socket.dart';

/// DTLS Server
/// Responds to DTLS handshake as the server
class DtlsServer extends DtlsSocket {
  /// Supported cipher suites
  final List<CipherSuite> cipherSuites;

  /// Supported elliptic curves
  final List<NamedCurve> supportedCurves;

  /// Server certificate (X.509 DER encoded)
  final Uint8List? certificate;

  /// Server private key
  final dynamic privateKey;

  /// Handshake coordinator
  late final ServerHandshakeCoordinator _handshakeCoordinator;

  /// Record layer
  late final DtlsRecordLayer _recordLayer;

  /// Processing lock to ensure sequential message processing
  Future<void>? _processingLock;

  /// Buffer for future-epoch records
  final List<Uint8List> _futureEpochBuffer = [];

  DtlsServer({
    required super.transport,
    super.dtlsContext,
    CipherContext? cipherContext,
    super.srtpContext,
    List<CipherSuite>? cipherSuites,
    List<NamedCurve>? supportedCurves,
    this.certificate,
    this.privateKey,
  })  : cipherSuites = cipherSuites ??
            [
              CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256,
              CipherSuite.tlsEcdheRsaWithAes128GcmSha256,
            ],
        supportedCurves =
            supportedCurves ?? [NamedCurve.x25519, NamedCurve.secp256r1],
        super(
          cipherContext: cipherContext ?? CipherContext(isClient: false),
          initialState: DtlsSocketState.closed,
        ) {
    // Initialize record layer
    _recordLayer = DtlsRecordLayer(
      dtlsContext: dtlsContext,
      cipherContext: this.cipherContext,
    );

    // Initialize handshake coordinator
    _handshakeCoordinator = ServerHandshakeCoordinator(
      dtlsContext: dtlsContext,
      cipherContext: this.cipherContext,
      recordLayer: _recordLayer,
      flightManager: flightManager,
      cipherSuites: this.cipherSuites,
      supportedCurves: this.supportedCurves,
      certificate: certificate,
      privateKey: privateKey,
    );
  }

  @override
  Future<void> connect() async {
    if (state != DtlsSocketState.closed) {
      throw StateError('Server already connecting or connected');
    }

    initializeTransport();
    setState(DtlsSocketState.connecting);

    // Server waits for ClientHello
    // Connection starts when we receive first ClientHello
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
        // Parse DTLS records
        final records = await _recordLayer.processRecords(data);

        // If no records processed, might be future epoch - buffer it
        if (records.isEmpty) {
          _futureEpochBuffer.add(data);
        }

        for (final processed in records) {
          switch (processed.contentType) {
            case ContentType.handshake:
              await _processHandshakeRecord(processed.data);
              break;

            case ContentType.changeCipherSpec:
              // CCS received - increment read epoch for decryption
              print('[SERVER] Received ChangeCipherSpec');
              dtlsContext.readEpoch++;

              // Reprocess buffered future-epoch records
              if (_futureEpochBuffer.isNotEmpty) {
                print(
                  '[SERVER] Reprocessing ${_futureEpochBuffer.length} buffered records',
                );
                final buffered = List<Uint8List>.from(_futureEpochBuffer);
                _futureEpochBuffer.clear();
                for (final bufferedData in buffered) {
                  // Process the buffered data with new epoch
                  final bufferedRecords = await _recordLayer.processRecords(
                    bufferedData,
                  );
                  for (final bufferedProcessed in bufferedRecords) {
                    if (bufferedProcessed.contentType ==
                        ContentType.handshake) {
                      await _processHandshakeRecord(bufferedProcessed.data);
                    }
                  }
                }
              }
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

        // Check if handshake is complete
        if (_handshakeCoordinator.isComplete && !isConnected) {
          _onHandshakeComplete();
        }
      } catch (e) {
        print('[SERVER] Error processing data: $e');
        errorController.add(e);
        setState(DtlsSocketState.failed);
      }
    });
  }

  /// Process handshake record
  /// Note: A single record may contain multiple handshake messages
  Future<void> _processHandshakeRecord(Uint8List data) async {
    // Parse all handshake messages from the record
    final messages = HandshakeMessage.parseMultiple(data);

    // Process each message via coordinator
    for (final handshakeMsg in messages) {
      // Pass the full message (header + body) for handshake buffer
      // Use rawBytes if available to preserve original bytes for handshake hash
      await _handshakeCoordinator.processHandshakeWithType(
        handshakeMsg.header.messageType,
        handshakeMsg.body,
        fullMessage: handshakeMsg.rawBytes ?? handshakeMsg.serialize(),
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
      print(
        '[SERVER] Sending flight ${currentFlight.flight.flightNumber} with ${currentFlight.messages.length} messages',
      );
      for (final message in currentFlight.messages) {
        await transport.send(message);
      }
      currentFlight.markSent();
    }
  }

  /// Called when handshake completes
  void _onHandshakeComplete() {
    print('[SERVER] Handshake complete!');

    // Export SRTP keys
    final srtpKeyMaterial = KeyDerivation.exportSrtpKeys(
      dtlsContext,
      60, // Standard SRTP key material length
      false, // isClient
    );

    // Store in SRTP context
    srtpContext.keyMaterial = srtpKeyMaterial;

    // Mark as connected
    dtlsContext.handshakeComplete = true;
    setState(DtlsSocketState.connected);
  }

  /// Process alert message
  Future<void> _processAlert(Uint8List data) async {
    try {
      final alert = Alert.parse(data);
      print('[SERVER] Received alert: $alert');

      if (alert.isFatal) {
        print('[SERVER] Fatal alert received, closing connection');
        errorController.add(Exception('Fatal alert: ${alert.description}'));
        setState(DtlsSocketState.failed);
        await close();
      } else if (alert.description == AlertDescription.closeNotify) {
        print('[SERVER] Close notify received, closing connection');
        await close();
      } else {
        print('[SERVER] Warning alert: ${alert.description}');
      }
    } catch (e) {
      print('[SERVER] Error processing alert: $e');
      errorController.add(e);
    }
  }

  /// Send alert message
  Future<void> sendAlert(Alert alert) async {
    try {
      final alertRecord = _recordLayer.wrapAlert(alert);
      final serialized = await _recordLayer.encryptRecord(alertRecord);
      await transport.send(serialized);
      print('[SERVER] Sent alert: $alert');
    } catch (e) {
      print('[SERVER] Error sending alert: $e');
    }
  }
}
