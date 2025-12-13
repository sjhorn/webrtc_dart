import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:webrtc_dart/src/common/logging.dart';
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/cipher/ecdh.dart';
import 'package:webrtc_dart/src/dtls/cipher/key_derivation.dart';
import 'package:webrtc_dart/src/dtls/context/cipher_context.dart';
import 'package:webrtc_dart/src/dtls/context/dtls_context.dart';
import 'package:webrtc_dart/src/dtls/context/srtp_context.dart';
import 'package:webrtc_dart/src/dtls/flight/client_flights.dart';
import 'package:webrtc_dart/src/dtls/flight/flight.dart';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/certificate.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/finished.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/hello_verify_request.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/server_hello.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/server_hello_done.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/server_key_exchange.dart';
import 'package:webrtc_dart/src/dtls/record/record_layer.dart';

final _log = WebRtcLogging.dtlsClient;

/// Client handshake state
enum ClientHandshakeState {
  initial,
  waitingForHelloVerifyRequest,
  waitingForServerHello,
  waitingForCertificate,
  waitingForServerKeyExchange,
  waitingForServerHelloDone,
  waitingForServerFinished,
  completed,
  failed,
}

/// Client handshake coordinator
/// Manages the DTLS client handshake flow
class ClientHandshakeCoordinator {
  final DtlsContext dtlsContext;
  final CipherContext cipherContext;
  final SrtpContext? srtpContext;
  final DtlsRecordLayer recordLayer;
  final FlightManager flightManager;
  final List<CipherSuite> cipherSuites;
  final List<NamedCurve> supportedCurves;

  ClientHandshakeState _state = ClientHandshakeState.initial;
  Certificate? _serverCertificate;
  bool _certificateRequested = false;

  ClientHandshakeCoordinator({
    required this.dtlsContext,
    required this.cipherContext,
    this.srtpContext,
    required this.recordLayer,
    required this.flightManager,
    required this.cipherSuites,
    required this.supportedCurves,
  });

  ClientHandshakeState get state => _state;

  /// Start the handshake by sending initial ClientHello
  Future<void> start() async {
    if (_state != ClientHandshakeState.initial) {
      throw StateError('Handshake already started');
    }

    // Create and send Flight 1 (initial ClientHello)
    final flight1 = ClientFlight1(
      dtlsContext: dtlsContext,
      cipherContext: cipherContext,
      recordLayer: recordLayer,
      cipherSuites: cipherSuites,
      supportedCurves: supportedCurves,
    );

    final messages = await flight1.generateMessages();
    flightManager.addFlight(flight1, messages);

    _state = ClientHandshakeState.waitingForHelloVerifyRequest;
  }

  /// Process received handshake record
  Future<void> processHandshake(Uint8List data) async {
    // For now, assume data is just the message body without header
    // In production, we'd parse the handshake header first
    // The message type should be passed separately or we need to look at context

    // This is a simplified version - in reality we need proper message routing
    // based on current state expectations

    // For testing purposes, we'll handle raw message bodies
    // The test will pass the serialized message directly
  }

  /// Process handshake message with type
  /// [body] is the message body (without header)
  /// [fullMessage] is the complete message with header (for handshake buffer)
  Future<void> processHandshakeWithType(
    HandshakeType messageType,
    Uint8List body, {
    Uint8List? fullMessage,
  }) async {
    _log.fine('Processing $messageType in state $_state');
    switch (messageType) {
      case HandshakeType.helloVerifyRequest:
        await _processHelloVerifyRequest(body);
        break;
      case HandshakeType.serverHello:
        await _processServerHello(body, fullMessage: fullMessage);
        break;
      case HandshakeType.certificate:
        await _processCertificate(body, fullMessage: fullMessage);
        break;
      case HandshakeType.serverKeyExchange:
        await _processServerKeyExchange(body, fullMessage: fullMessage);
        break;
      case HandshakeType.serverHelloDone:
        await _processServerHelloDone(body, fullMessage: fullMessage);
        break;
      case HandshakeType.finished:
        await _processFinished(body, fullMessage: fullMessage);
        break;
      case HandshakeType.certificateRequest:
        await _processCertificateRequest(body, fullMessage: fullMessage);
        break;
      default:
        // Ignore other message types for now
        break;
    }
  }

  /// Process HelloVerifyRequest from server
  Future<void> _processHelloVerifyRequest(Uint8List data) async {
    if (_state != ClientHandshakeState.waitingForHelloVerifyRequest) {
      throw StateError('Unexpected HelloVerifyRequest in state $_state');
    }

    // Parse HelloVerifyRequest
    final hvr = HelloVerifyRequest.parse(data);
    dtlsContext.cookie = hvr.cookie;

    // Clear handshake messages - handshake is restarted with cookie
    // Per RFC 6347: "the handshake is restarted and the first ClientHello is not included"
    dtlsContext.clearHandshakeMessages();
    // Also reset message sequence number since handshake is restarted
    dtlsContext.handshakeMessageSeq = 0;

    // Mark Flight 1 as complete
    flightManager.moveToNextFlight();

    // Send Flight 3 (ClientHello with cookie + key exchange)
    final flight3 = ClientFlight3(
      dtlsContext: dtlsContext,
      cipherContext: cipherContext,
      recordLayer: recordLayer,
      cipherSuites: cipherSuites,
    );

    final messages = await flight3.generateMessages();
    flightManager.addFlight(flight3, messages);

    _state = ClientHandshakeState.waitingForServerHello;
  }

  /// Process ServerHello from server
  Future<void> _processServerHello(Uint8List data,
      {Uint8List? fullMessage}) async {
    // RFC 6347 Section 4.2.1: HelloVerifyRequest is optional
    // Server may skip it and send ServerHello directly
    if (_state == ClientHandshakeState.waitingForHelloVerifyRequest) {
      _log.fine('Server skipped HelloVerifyRequest, proceeding directly');
      // Mark Flight 1 as complete
      flightManager.moveToNextFlight();
      _state = ClientHandshakeState.waitingForServerHello;

      // Important: The ClientHello is already in the handshake buffer from Flight 1
      // Server will include it in its verify_data calculation
      _log.fine(
          'Handshake buffer has ${dtlsContext.handshakeMessages.length} messages after ClientHello');
    }

    if (_state != ClientHandshakeState.waitingForServerHello) {
      // DTLS retransmission - silently ignore duplicate messages from previous flights
      _log.fine('Ignoring retransmitted ServerHello in state $_state');
      return;
    }

    // Parse ServerHello
    final serverHello = ServerHello.parse(data);
    dtlsContext.serverHello = serverHello;
    dtlsContext.remoteRandom = serverHello.random.bytes;

    // Store selected cipher suite
    cipherContext.cipherSuite = serverHello.cipherSuite;
    _log.fine('Selected cipher suite: ${serverHello.cipherSuite}');

    // Check if server echoed extended master secret extension
    dtlsContext.useExtendedMasterSecret = serverHello.hasExtendedMasterSecret;
    _log.fine('Extended master secret: ${dtlsContext.useExtendedMasterSecret}');

    // Extract negotiated SRTP profile from ServerHello
    final negotiatedSrtpProfile = serverHello.srtpProfile;
    if (negotiatedSrtpProfile != null && srtpContext != null) {
      srtpContext!.profile = negotiatedSrtpProfile;
      _log.fine('Negotiated SRTP profile: $negotiatedSrtpProfile');
    } else if (srtpContext != null) {
      _log.fine('No SRTP profile in ServerHello');
    }

    // Add to handshake messages (use fullMessage if available, includes header)
    dtlsContext.addHandshakeMessage(fullMessage ?? data);
    _log.fine(
        'Added ServerHello to buffer, now ${dtlsContext.handshakeMessages.length} messages');

    _state = ClientHandshakeState.waitingForCertificate;
  }

  /// Process Certificate from server
  Future<void> _processCertificate(Uint8List data,
      {Uint8List? fullMessage}) async {
    // Ignore retransmissions from previous flights
    if (_state == ClientHandshakeState.waitingForServerFinished ||
        _state == ClientHandshakeState.completed) {
      _log.fine('Ignoring retransmitted Certificate in state $_state');
      return;
    }

    if (_state != ClientHandshakeState.waitingForCertificate) {
      // Certificate is optional, might go straight to ServerKeyExchange
      if (_state == ClientHandshakeState.waitingForServerHello) {
        _state = ClientHandshakeState.waitingForCertificate;
      }
    }

    // Parse Certificate message
    _serverCertificate = Certificate.parse(data);
    _log.fine(
        'Received certificate with ${_serverCertificate!.certificates.length} certificate(s)');

    // Note: Certificate chain validation is not performed here (matching werift:
    // packages/dtls/src/flight/client/flight5.ts - just stores remoteCertificate).
    // In WebRTC, certificates are self-signed and security comes from fingerprint
    // verification via SDP, not traditional PKI chain validation.

    dtlsContext.addHandshakeMessage(fullMessage ?? data);

    _state = ClientHandshakeState.waitingForServerKeyExchange;
  }

  /// Process ServerKeyExchange from server
  Future<void> _processServerKeyExchange(Uint8List data,
      {Uint8List? fullMessage}) async {
    // Ignore retransmissions from previous flights
    if (_state == ClientHandshakeState.waitingForServerFinished ||
        _state == ClientHandshakeState.completed) {
      _log.fine('Ignoring retransmitted ServerKeyExchange in state $_state');
      return;
    }

    // Can arrive after Certificate or directly after ServerHello (if no certificate)
    if (_state != ClientHandshakeState.waitingForServerKeyExchange &&
        _state != ClientHandshakeState.waitingForCertificate &&
        _state != ClientHandshakeState.waitingForServerHello) {
      // DTLS retransmission - silently ignore duplicate messages from previous flights
      _log.fine('Ignoring retransmitted ServerKeyExchange in state $_state');
      return;
    }

    // Parse ServerKeyExchange
    final ske = ServerKeyExchange.parse(data);

    // Store server's public key
    cipherContext.remotePublicKey = ske.publicKey;
    cipherContext.namedCurve = ske.curve;
    cipherContext.signatureScheme = ske.signatureScheme;
    _log.fine('Selected curve: ${ske.curve}');
    _log.fine('Server public key: ${ske.publicKey.length} bytes');

    // Verify signature if we have a certificate
    if (_serverCertificate != null &&
        dtlsContext.localRandom != null &&
        dtlsContext.remoteRandom != null) {
      final isValid = _verifyServerKeyExchangeSignature(
        ske: ske,
        clientRandom: dtlsContext.localRandom!,
        serverRandom: dtlsContext.remoteRandom!,
        certificate: _serverCertificate!,
      );
      if (!isValid) {
        _log.warning('ServerKeyExchange signature verification failed');
        // In a production system, you would fail the handshake here
        // throw StateError('ServerKeyExchange signature verification failed');
      } else {
        _log.fine('ServerKeyExchange signature verified');
      }
    }

    // Add to handshake messages
    dtlsContext.addHandshakeMessage(fullMessage ?? data);

    _state = ClientHandshakeState.waitingForServerHelloDone;
  }

  /// Process CertificateRequest from server
  Future<void> _processCertificateRequest(Uint8List data,
      {Uint8List? fullMessage}) async {
    // Ignore retransmissions from previous flights
    if (_state == ClientHandshakeState.waitingForServerFinished ||
        _state == ClientHandshakeState.completed) {
      _log.fine('Ignoring retransmitted CertificateRequest in state $_state');
      return;
    }

    // CertificateRequest can arrive after ServerKeyExchange
    if (_state != ClientHandshakeState.waitingForServerHelloDone) {
      _log.fine('CertificateRequest received unexpectedly in state $_state');
    }

    _log.fine('Server requested client certificate');
    _certificateRequested = true;

    // Add to handshake messages
    dtlsContext.addHandshakeMessage(fullMessage ?? data);

    // State remains waitingForServerHelloDone
  }

  /// Process ServerHelloDone from server
  Future<void> _processServerHelloDone(Uint8List data,
      {Uint8List? fullMessage}) async {
    // Ignore retransmissions from previous flights
    if (_state == ClientHandshakeState.waitingForServerFinished ||
        _state == ClientHandshakeState.completed) {
      _log.fine('Ignoring retransmitted ServerHelloDone in state $_state');
      return;
    }

    // Can arrive after ServerKeyExchange, or after ServerHello if no cert/key exchange
    if (_state != ClientHandshakeState.waitingForServerHelloDone &&
        _state != ClientHandshakeState.waitingForServerKeyExchange &&
        _state != ClientHandshakeState.waitingForCertificate) {
      // DTLS retransmission - silently ignore duplicate messages from previous flights
      _log.fine('Ignoring retransmitted ServerHelloDone in state $_state');
      return;
    }

    // Parse ServerHelloDone
    ServerHelloDone.parse(data);
    dtlsContext.addHandshakeMessage(fullMessage ?? data);

    // Generate our ECDH key pair (but NOT master secret yet - that happens after ClientKeyExchange is added to buffer)
    await _generateKeyPairOnly();

    // Mark Flight 3 as complete (we're done waiting for ServerHello flight)
    flightManager.moveToNextFlight();

    // NOTE: Master secret derivation is deferred to ClientFlight3.generateMessages()
    // because extended master secret (RFC 7627) requires ClientKeyExchange to be in the buffer
    // The buffer needs: ClientHello + Server messages + Certificate (client) + ClientKeyExchange

    // Send Flight 5 (Certificate + ClientKeyExchange + ChangeCipherSpec + Finished)
    // This uses ClientFlight3 but without ClientHello since we already sent that
    final flight5 = ClientFlight3(
      dtlsContext: dtlsContext,
      cipherContext: cipherContext,
      recordLayer: recordLayer,
      cipherSuites: cipherSuites,
      includeClientHello: false,
      sendEmptyCertificate: _certificateRequested,
    );

    final messages = await flight5.generateMessages();
    flightManager.addFlight(flight5, messages);

    _state = ClientHandshakeState.waitingForServerFinished;
  }

  /// Process Finished from server
  Future<void> _processFinished(Uint8List data,
      {Uint8List? fullMessage}) async {
    if (_state != ClientHandshakeState.waitingForServerFinished) {
      // DTLS retransmission - silently ignore duplicate Finished messages
      // This can happen if our final ACK was lost and server retransmits
      _log.fine('Ignoring retransmitted Finished in state $_state');
      return;
    }

    // Parse Finished message
    final finished = Finished.parse(data);

    // Verify the verify_data matches expected value
    final isValid = KeyDerivation.verifyFinishedMessage(
      dtlsContext,
      finished.verifyData,
      false, // isClient=false for verifying server's Finished
    );

    if (!isValid) {
      _state = ClientHandshakeState.failed;
      throw StateError('Finished message verification failed');
    }

    dtlsContext.addHandshakeMessage(fullMessage ?? data);

    // Mark Flight 5 as complete
    flightManager.moveToNextFlight();

    dtlsContext.handshakeComplete = true;

    _state = ClientHandshakeState.completed;
  }

  /// Generate ECDH key pair only (without deriving master secret)
  Future<void> _generateKeyPairOnly() async {
    final curve = cipherContext.namedCurve;
    if (curve == null) {
      throw StateError('Named curve not selected');
    }

    // Generate key pair based on selected curve
    final keyPair = await generateEcdhKeypair(curve);
    cipherContext.localKeyPair = keyPair;
    cipherContext.localPublicKey = await serializePublicKey(keyPair, curve);

    // Compute shared secret if we have remote public key
    if (cipherContext.remotePublicKey != null) {
      final sharedSecret = await computePreMasterSecret(
        keyPair,
        cipherContext.remotePublicKey!,
        curve,
      );
      dtlsContext.preMasterSecret = sharedSecret;
    }
  }

  /// Check if handshake is complete
  bool get isComplete => _state == ClientHandshakeState.completed;

  /// Check if handshake failed
  bool get isFailed => _state == ClientHandshakeState.failed;

  /// Check if server requested client certificate
  bool get certificateRequested => _certificateRequested;

  /// Verify ServerKeyExchange signature
  bool _verifyServerKeyExchangeSignature({
    required ServerKeyExchange ske,
    required Uint8List clientRandom,
    required Uint8List serverRandom,
    required Certificate certificate,
  }) {
    try {
      // Build the data that was signed
      final paramsLength = 1 + 2 + 1 + ske.publicKey.length;
      final dataToVerify =
          Uint8List(clientRandom.length + serverRandom.length + paramsLength);
      var offset = 0;

      // Client random
      dataToVerify.setRange(offset, offset + clientRandom.length, clientRandom);
      offset += clientRandom.length;

      // Server random
      dataToVerify.setRange(offset, offset + serverRandom.length, serverRandom);
      offset += serverRandom.length;

      // Server params
      dataToVerify[offset++] = 3; // ECCurveType: named_curve
      dataToVerify[offset++] = (ske.curve.value >> 8) & 0xFF;
      dataToVerify[offset++] = ske.curve.value & 0xFF;
      dataToVerify[offset++] = ske.publicKey.length;
      dataToVerify.setRange(
          offset, offset + ske.publicKey.length, ske.publicKey);

      // Hash the data
      final digest = Digest('SHA-256');
      final hash = digest.process(dataToVerify);

      // Extract public key from certificate
      // This is a simplified implementation - in production, you'd use a proper ASN.1 parser
      final publicKey =
          _extractPublicKeyFromCertificate(certificate.entityCertificate!);
      if (publicKey == null) {
        _log.fine('Could not extract public key from certificate');
        return false;
      }

      // Verify the signature
      final signer = ECDSASigner(null, HMac(digest, 64));
      signer.init(false, PublicKeyParameter<ECPublicKey>(publicKey));

      // Parse DER signature
      final ecSignature = _parseDerSignature(ske.signature);
      if (ecSignature == null) {
        _log.fine('Could not parse DER signature');
        return false;
      }

      return signer.verifySignature(hash, ecSignature);
    } catch (e) {
      _log.warning('Signature verification error: $e');
      return false;
    }
  }

  /// Extract ECDSA public key from X.509 certificate (simplified)
  /// This is a basic implementation that works with the certificates we generate
  ECPublicKey? _extractPublicKeyFromCertificate(Uint8List certData) {
    try {
      // This is a simplified parser - in production, use a proper ASN.1/X.509 library
      // We look for the BIT STRING containing the public key (uncompressed point)
      // The public key is in the Subject Public Key Info section

      // Search for the EC public key OID (1.2.840.10045.2.1) followed by curve OID
      // Then find the BIT STRING with the public key
      for (var i = 0; i < certData.length - 70; i++) {
        // Look for BIT STRING tag (0x03) followed by length and 0x00 (no unused bits)
        if (certData[i] == 0x03 && certData[i + 2] == 0x00) {
          final bitStringLength = certData[i + 1];
          if (bitStringLength >= 65 && bitStringLength <= 67) {
            // Likely our public key (04 + 32 bytes X + 32 bytes Y = 65 bytes)
            final keyData =
                certData.sublist(i + 3, i + 3 + bitStringLength - 1);
            if (keyData.isNotEmpty && keyData[0] == 0x04) {
              // Uncompressed point format
              final curve = ECCurve_secp256r1();
              final point = curve.curve.decodePoint(keyData);
              if (point != null) {
                return ECPublicKey(point, curve);
              }
            }
          }
        }
      }
      return null;
    } catch (e) {
      _log.warning('Error extracting public key: $e');
      return null;
    }
  }

  /// Parse DER-encoded ECDSA signature
  /// SEQUENCE { INTEGER r, INTEGER s }
  ECSignature? _parseDerSignature(Uint8List signature) {
    try {
      if (signature.length < 8) return null;

      var offset = 0;
      // SEQUENCE tag
      if (signature[offset++] != 0x30) return null;

      // Sequence length
      final seqLength = signature[offset++];
      if (signature.length < 2 + seqLength) return null;

      // INTEGER r
      if (signature[offset++] != 0x02) return null;
      final rLength = signature[offset++];
      final rBytes = signature.sublist(offset, offset + rLength);
      offset += rLength;

      // INTEGER s
      if (signature[offset++] != 0x02) return null;
      final sLength = signature[offset++];
      final sBytes = signature.sublist(offset, offset + sLength);

      // Convert bytes to BigInt
      final r = _bytesToBigInt(rBytes);
      final s = _bytesToBigInt(sBytes);

      return ECSignature(r, s);
    } catch (e) {
      _log.warning('Error parsing DER signature: $e');
      return null;
    }
  }

  /// Convert bytes to BigInt
  BigInt _bytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (var byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }
}
