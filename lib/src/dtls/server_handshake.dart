import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/cipher/ecdh.dart';
import 'package:webrtc_dart/src/dtls/cipher/key_derivation.dart';
import 'package:webrtc_dart/src/dtls/context/cipher_context.dart';
import 'package:webrtc_dart/src/dtls/context/dtls_context.dart';
import 'package:webrtc_dart/src/dtls/flight/flight.dart';
import 'package:webrtc_dart/src/dtls/flight/server_flights.dart';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/client_hello.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/client_key_exchange.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/finished.dart';
import 'package:webrtc_dart/src/dtls/record/record_layer.dart';

/// Server handshake state
enum ServerHandshakeState {
  initial,
  waitingForClientHello,
  waitingForClientHelloWithCookie,
  waitingForClientKeyExchange,
  waitingForClientFinished,
  completed,
  failed,
}

/// Server handshake coordinator
/// Manages the DTLS server handshake flow
class ServerHandshakeCoordinator {
  final DtlsContext dtlsContext;
  final CipherContext cipherContext;
  final DtlsRecordLayer recordLayer;
  final FlightManager flightManager;
  final List<CipherSuite> cipherSuites;
  final List<NamedCurve> supportedCurves;
  final Uint8List? certificate;
  final dynamic privateKey;

  ServerHandshakeState _state = ServerHandshakeState.waitingForClientHello;

  ServerHandshakeCoordinator({
    required this.dtlsContext,
    required this.cipherContext,
    required this.recordLayer,
    required this.flightManager,
    required this.cipherSuites,
    required this.supportedCurves,
    this.certificate,
    this.privateKey,
  });

  ServerHandshakeState get state => _state;

  /// Process received handshake record
  Future<void> processHandshake(Uint8List data) async {
    // For now, assume data is just the message body without header
    // In production, we'd parse the handshake header first
  }

  /// Process handshake message with type
  /// [body] is the message body (without header)
  /// [fullMessage] is the complete message with header (for handshake buffer)
  Future<void> processHandshakeWithType(
    HandshakeType messageType,
    Uint8List body, {
    Uint8List? fullMessage,
  }) async {
    print('[SERVER] Processing $messageType in state $_state');
    switch (messageType) {
      case HandshakeType.clientHello:
        await _processClientHello(body, fullMessage: fullMessage);
        break;
      case HandshakeType.certificate:
        await _processCertificate(body, fullMessage: fullMessage);
        break;
      case HandshakeType.clientKeyExchange:
        await _processClientKeyExchange(body, fullMessage: fullMessage);
        break;
      case HandshakeType.certificateVerify:
        await _processCertificateVerify(body, fullMessage: fullMessage);
        break;
      case HandshakeType.finished:
        await _processFinished(body, fullMessage: fullMessage);
        break;
      default:
        // Ignore other message types for now
        break;
    }
  }

  /// Process ClientHello from client
  Future<void> _processClientHello(Uint8List data, {Uint8List? fullMessage}) async {
    // Parse ClientHello
    final clientHello = ClientHello.parse(data);
    dtlsContext.clientHello = clientHello;
    dtlsContext.remoteRandom = clientHello.random.bytes;

    // Check if client wants extended master secret
    dtlsContext.useExtendedMasterSecret = clientHello.hasExtendedMasterSecret;
    print('[SERVER] Processing ClientHello (cookie length: ${clientHello.cookie.length}, ems=${dtlsContext.useExtendedMasterSecret})');

    // Check if cookie is present
    if (clientHello.cookie.isEmpty) {
      // First ClientHello without cookie - send HelloVerifyRequest
      if (_state != ServerHandshakeState.waitingForClientHello) {
        throw StateError('Unexpected first ClientHello in state $_state');
      }

      // Send Flight 2 (HelloVerifyRequest)
      final flight2 = ServerFlight2(
        dtlsContext: dtlsContext,
        recordLayer: recordLayer,
      );

      final messages = await flight2.generateMessages();
      flightManager.addFlight(flight2, messages);

      _state = ServerHandshakeState.waitingForClientHelloWithCookie;
    } else {
      // Second ClientHello with cookie - verify and proceed
      print('[SERVER] Second ClientHello - verifying cookie');
      if (_state != ServerHandshakeState.waitingForClientHelloWithCookie) {
        throw StateError('Unexpected second ClientHello in state $_state');
      }

      // Verify cookie matches
      if (clientHello.cookie.length != dtlsContext.cookie?.length ||
          !_bytesEqual(clientHello.cookie, dtlsContext.cookie!)) {
        throw StateError('Cookie mismatch');
      }

      print('[SERVER] Cookie verified, generating key pair');

      // Add to handshake messages (use fullMessage if available, includes header)
      dtlsContext.addHandshakeMessage(fullMessage ?? data);

      // Mark Flight 2 as complete (received response)
      flightManager.moveToNextFlight();

      // Generate our ECDH key pair
      await _generateKeyPair();

      print('[SERVER] Key pair generated, creating Flight 4');

      // Send Flight 4 (ServerHello + Certificate + ServerKeyExchange + ServerHelloDone)
      final flight4 = ServerFlight4(
        dtlsContext: dtlsContext,
        cipherContext: cipherContext,
        recordLayer: recordLayer,
        cipherSuites: cipherSuites,
        certificate: certificate,
        privateKey: privateKey,
      );

      final messages = await flight4.generateMessages();
      print('[SERVER] Flight 4 has ${messages.length} messages');
      flightManager.addFlight(flight4, messages);

      _state = ServerHandshakeState.waitingForClientKeyExchange;
    }
  }

  /// Process Certificate from client (if client authentication is used)
  /// Note: Client certificate authentication is optional in WebRTC and rarely used.
  /// werift supports this via CertificateRequest (packages/dtls/src/flight/server/flight4.ts)
  /// but most browser implementations don't send client certificates.
  Future<void> _processCertificate(Uint8List data, {Uint8List? fullMessage}) async {
    // Parse and store client certificate (matching werift behavior)
    // In practice, browsers don't send certificates unless CertificateRequest was sent
    dtlsContext.addHandshakeMessage(fullMessage ?? data);
  }

  /// Process ClientKeyExchange from client
  Future<void> _processClientKeyExchange(Uint8List data, {Uint8List? fullMessage}) async {
    if (_state != ServerHandshakeState.waitingForClientKeyExchange) {
      throw StateError('Unexpected ClientKeyExchange in state $_state');
    }

    // Parse ClientKeyExchange
    final cke = ClientKeyExchange.parse(data);

    // Store client's public key
    cipherContext.remotePublicKey = cke.publicKey;

    // Add to handshake messages (use fullMessage if available, includes header)
    dtlsContext.addHandshakeMessage(fullMessage ?? data);

    // Mark Flight 4 as complete (client has received it and is responding)
    flightManager.moveToNextFlight();

    // Compute shared secret
    if (cipherContext.localKeyPair != null &&
        cipherContext.namedCurve != null) {
      final sharedSecret = await computePreMasterSecret(
        cipherContext.localKeyPair!,
        cke.publicKey,
        cipherContext.namedCurve!,
      );
      dtlsContext.preMasterSecret = sharedSecret;

      // Derive master secret from pre-master secret
      // Only use extended master secret if negotiated with client (RFC 7627)
      print('[SERVER] Deriving master secret (extended=${dtlsContext.useExtendedMasterSecret})');
      final masterSecret = KeyDerivation.deriveMasterSecret(
        dtlsContext,
        cipherContext,
        dtlsContext.useExtendedMasterSecret,
      );
      dtlsContext.masterSecret = masterSecret;

      // Derive encryption keys from master secret
      final encryptionKeys = KeyDerivation.deriveEncryptionKeys(
        dtlsContext,
        cipherContext,
      );
      cipherContext.encryptionKeys = encryptionKeys;

      // Initialize ciphers for encryption/decryption
      if (cipherContext.cipherSuite != null) {
        cipherContext.initializeCiphers(encryptionKeys, cipherContext.cipherSuite!);
      }
    }

    _state = ServerHandshakeState.waitingForClientFinished;
  }

  /// Process CertificateVerify from client (if client authentication is used)
  /// werift implements this in packages/dtls/src/handshake/message/client/certificateVerify.ts
  /// The message contains a signature over the handshake transcript.
  /// Only received if server sent CertificateRequest and client has a certificate.
  Future<void> _processCertificateVerify(Uint8List data, {Uint8List? fullMessage}) async {
    // Parse CertificateVerify: algorithm (uint16) + signature (length-prefixed)
    // In practice, browsers don't send this unless we request client authentication
    dtlsContext.addHandshakeMessage(fullMessage ?? data);
  }

  /// Process Finished from client
  Future<void> _processFinished(Uint8List data, {Uint8List? fullMessage}) async {
    if (_state != ServerHandshakeState.waitingForClientFinished) {
      throw StateError('Unexpected Finished in state $_state');
    }

    // Parse Finished message
    final finished = Finished.parse(data);

    // Verify the verify_data matches expected value
    final isValid = KeyDerivation.verifyFinishedMessage(
      dtlsContext,
      finished.verifyData,
      true, // isClient=true for verifying client's Finished
    );

    if (!isValid) {
      _state = ServerHandshakeState.failed;
      throw StateError('Finished message verification failed');
    }

    dtlsContext.addHandshakeMessage(fullMessage ?? data);

    // Send Flight 6 (ChangeCipherSpec + Finished)
    final flight6 = ServerFlight6(
      dtlsContext: dtlsContext,
      cipherContext: cipherContext,
      recordLayer: recordLayer,
    );

    final messages = await flight6.generateMessages();
    flightManager.addFlight(flight6, messages);

    dtlsContext.handshakeComplete = true;
    _state = ServerHandshakeState.completed;
  }

  /// Generate ECDH key pair for key exchange
  Future<void> _generateKeyPair() async {
    // Select a curve to use (prefer X25519, fall back to P-256)
    final curve = supportedCurves.contains(NamedCurve.x25519)
        ? NamedCurve.x25519
        : NamedCurve.secp256r1;

    cipherContext.namedCurve = curve;

    // Generate key pair
    final keyPair = await generateEcdhKeypair(curve);
    cipherContext.localKeyPair = keyPair;
    cipherContext.localPublicKey = await serializePublicKey(keyPair, curve);

    // Set signature scheme
    cipherContext.signatureScheme = SignatureScheme.ecdsaSecp256r1Sha256;
  }

  /// Compare two byte arrays for equality
  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Check if handshake is complete
  bool get isComplete => _state == ServerHandshakeState.completed;

  /// Check if handshake failed
  bool get isFailed => _state == ServerHandshakeState.failed;
}
