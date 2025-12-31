import 'dart:typed_data';

import 'package:webrtc_dart/src/common/logging.dart';
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/cipher/key_derivation.dart';
import 'package:webrtc_dart/src/dtls/context/cipher_context.dart';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/alert.dart';
import 'package:webrtc_dart/src/dtls/record/const.dart';
import 'package:webrtc_dart/src/dtls/record/fragment.dart';
import 'package:webrtc_dart/src/dtls/record/record_layer.dart';
import 'package:webrtc_dart/src/dtls/server_handshake.dart';
import 'package:webrtc_dart/src/dtls/socket.dart';

final _log = WebRtcLogging.dtlsServer;

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

  /// Buffer for handshake fragment reassembly
  /// Key: (messageSeq, messageType) -> list of fragments
  final Map<(int, int), List<FragmentedHandshake>> _fragmentBuffer = {};

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
      srtpContext: srtpContext,
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
    _log.fine(
        'DTLS send: data=${data.length} bytes, epoch=${record.epoch}, seq=${record.sequenceNumber}');

    // Encrypt and send
    final encrypted = await _recordLayer.encryptRecord(record);
    _log.fine('DTLS send encrypted: ${encrypted.length} bytes');
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
              _log.fine('Received ChangeCipherSpec');
              dtlsContext.readEpoch++;

              // Reprocess buffered future-epoch records
              if (_futureEpochBuffer.isNotEmpty) {
                _log.fine(
                  'Reprocessing ${_futureEpochBuffer.length} buffered records',
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
        _log.fine(
            'Checking handshake: isComplete=${_handshakeCoordinator.isComplete}, isConnected=$isConnected');
        if (_handshakeCoordinator.isComplete && !isConnected) {
          _onHandshakeComplete();
        }
      } catch (e) {
        _log.warning('Error processing data: $e');
        if (!isClosed && !errorController.isClosed) {
          errorController.add(e);
          setState(DtlsSocketState.failed);
        }
      }
    });
  }

  /// Process handshake record
  /// Note: A single record may contain multiple handshake messages
  /// Handles fragmented messages by buffering and reassembling
  Future<void> _processHandshakeRecord(Uint8List data) async {
    // Parse all handshake fragments from the record
    var offset = 0;
    while (offset < data.length) {
      if (data.length - offset < 12) break;

      final fragment = FragmentedHandshake.deserialize(data.sublist(offset));
      offset += 12 + fragment.fragmentLength;

      _log.fine(
          'Received fragment: type=${fragment.msgType}, seq=${fragment.messageSeq}, '
          'offset=${fragment.fragmentOffset}/${fragment.length}, fragLen=${fragment.fragmentLength}');

      // Check if this is a complete message (not fragmented)
      if (fragment.fragmentOffset == 0 &&
          fragment.fragmentLength == fragment.length) {
        // Complete message - process immediately
        await _processCompleteHandshake(fragment);
      } else {
        // Fragmented message - buffer and reassemble
        final key = (fragment.messageSeq, fragment.msgType);
        _fragmentBuffer.putIfAbsent(key, () => []);
        _fragmentBuffer[key]!.add(fragment);

        // Check if we have all fragments
        final fragments = _fragmentBuffer[key]!;
        final totalReceived =
            fragments.fold<int>(0, (sum, f) => sum + f.fragmentLength);

        if (totalReceived >= fragment.length) {
          // We have all fragments - reassemble
          _log.fine(
              'Reassembling ${fragments.length} fragments for message ${fragment.msgType}');
          final assembled = FragmentedHandshake.assemble(fragments);
          _fragmentBuffer.remove(key);
          await _processCompleteHandshake(assembled);
        }
      }
    }

    // Send any pending flights
    await _sendPendingFlights();
  }

  /// Process a complete (reassembled) handshake message
  Future<void> _processCompleteHandshake(FragmentedHandshake fragment) async {
    final messageType = HandshakeType.fromValue(fragment.msgType);
    if (messageType == null) {
      _log.warning('Unknown handshake type: ${fragment.msgType}');
      return;
    }

    // Create full message bytes for handshake hash (header + body)
    final fullMessage = FragmentedHandshake(
      msgType: fragment.msgType,
      length: fragment.length,
      messageSeq: fragment.messageSeq,
      fragmentOffset: 0,
      fragmentLength: fragment.length,
      fragment: fragment.fragment,
    ).serialize();

    await _handshakeCoordinator.processHandshakeWithType(
      messageType,
      fragment.fragment,
      fullMessage: fullMessage,
    );
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
      for (final message in currentFlight.messages) {
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
        false, // isClient
      );

      // Store raw material and extract individual keys
      srtpContext.keyMaterial = srtpKeyMaterial;
      srtpContext.extractKeys(srtpKeyMaterial, false);

      _log.fine('Exported SRTP keys for profile ${srtpContext.profile}');
      _log.fine(
          'Local key: ${srtpContext.localMasterKey?.length} bytes, salt: ${srtpContext.localMasterSalt?.length} bytes');
      _log.fine(
          'Remote key: ${srtpContext.remoteMasterKey?.length} bytes, salt: ${srtpContext.remoteMasterSalt?.length} bytes');
      // Debug: print actual keys
      final localKeyHex = srtpContext.localMasterKey
          ?.map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      final localSaltHex = srtpContext.localMasterSalt
          ?.map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      final remoteKeyHex = srtpContext.remoteMasterKey
          ?.map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      final remoteSaltHex = srtpContext.remoteMasterSalt
          ?.map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      _log.fine('localMasterKey: $localKeyHex');
      _log.fine('localMasterSalt: $localSaltHex');
      _log.fine('remoteMasterKey: $remoteKeyHex');
      _log.fine('remoteMasterSalt: $remoteSaltHex');
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
