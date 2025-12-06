import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/handshake/message/certificate.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/certificate_request.dart';
import 'package:webrtc_dart/src/common/crypto.dart';
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/cipher/key_derivation.dart';
import 'package:webrtc_dart/src/dtls/context/cipher_context.dart';
import 'package:pointycastle/export.dart';
import 'package:webrtc_dart/src/dtls/context/dtls_context.dart';
import 'package:webrtc_dart/src/dtls/flight/flight.dart';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/extended_master_secret.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/extension.dart';
import 'package:webrtc_dart/src/dtls/handshake/handshake_header.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/change_cipher_spec.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/finished.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/hello_verify_request.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/server_hello.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/server_hello_done.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/server_key_exchange.dart';
import 'package:webrtc_dart/src/dtls/record/const.dart';
import 'package:webrtc_dart/src/dtls/record/record_layer.dart';

/// Flight 2: HelloVerifyRequest (cookie exchange)
class ServerFlight2 extends Flight {
  final DtlsContext dtlsContext;
  final DtlsRecordLayer recordLayer;

  ServerFlight2({
    required this.dtlsContext,
    required this.recordLayer,
  });

  @override
  int get flightNumber => 2;

  @override
  bool get expectsResponse => true;

  @override
  Future<List<Uint8List>> generateMessages() async {
    // Generate random cookie
    final cookie = randomBytes(20);
    dtlsContext.cookie = cookie;

    // Create HelloVerifyRequest
    final helloVerifyRequest = HelloVerifyRequest.create(cookie);
    final messageBody = helloVerifyRequest.serialize();

    // Wrap with handshake header
    final handshakeMessage = wrapHandshakeMessage(
      HandshakeType.helloVerifyRequest,
      messageBody,
      messageSeq: 0,
    );

    // Wrap in record
    final record = recordLayer.wrapHandshake(handshakeMessage);
    return [record.serialize()];
  }

  @override
  Future<bool> processMessages(List<Uint8List> messages) async {
    // Process ClientHello with cookie
    return true;
  }
}

/// Flight 4: ServerHello + Certificate + ServerKeyExchange +
///           CertificateRequest (optional) + ServerHelloDone
class ServerFlight4 extends Flight {
  final DtlsContext dtlsContext;
  final CipherContext cipherContext;
  final DtlsRecordLayer recordLayer;
  final List<CipherSuite> cipherSuites;
  final Uint8List? certificate;
  final dynamic privateKey;
  final bool requireClientCert;

  ServerFlight4({
    required this.dtlsContext,
    required this.cipherContext,
    required this.recordLayer,
    required this.cipherSuites,
    this.certificate,
    this.privateKey,
    this.requireClientCert = false,
  });

  @override
  int get flightNumber => 4;

  @override
  bool get expectsResponse => true;

  @override
  Future<List<Uint8List>> generateMessages() async {
    final messages = <Uint8List>[];

    // 1. ServerHello
    // Echo extended_master_secret if client offered it
    final extensions = <Extension>[];
    if (dtlsContext.useExtendedMasterSecret) {
      extensions.add(ExtendedMasterSecretExtension());
    }

    final selectedCipher = _selectCipherSuite();
    final serverHello = ServerHello.create(
      sessionId: dtlsContext.sessionId ?? Uint8List(32),
      cipherSuite: selectedCipher,
      extensions: extensions,
    );
    dtlsContext.serverHello = serverHello;
    dtlsContext.localRandom = serverHello.random.bytes;
    cipherContext.cipherSuite = selectedCipher;

    final serverHelloBody = serverHello.serialize();
    final serverHelloMsg = wrapHandshakeMessage(
      HandshakeType.serverHello,
      serverHelloBody,
      messageSeq: 0,
    );
    // Add full message with header to handshake buffer
    dtlsContext.addHandshakeMessage(serverHelloMsg);
    messages.add(recordLayer.wrapHandshake(serverHelloMsg).serialize());

    // 2. Certificate
    final certData = certificate;
    if (certData != null) {
      final cert = Certificate.single(certData);
      final certBody = cert.serialize();
      final certMsg = wrapHandshakeMessage(
        HandshakeType.certificate,
        certBody,
        messageSeq: 0,
      );
      // Add full message with header to handshake buffer
      dtlsContext.addHandshakeMessage(certMsg);
      messages.add(recordLayer.wrapHandshake(certMsg).serialize());
    }

    // 3. ServerKeyExchange (for ECDHE cipher suites)
    if (cipherContext.localPublicKey != null &&
        cipherContext.namedCurve != null) {
      // Compute signature over ServerKeyExchange params
      final signature =
          (dtlsContext.remoteRandom != null && dtlsContext.localRandom != null)
              ? _signServerKeyExchange(
                  clientRandom: dtlsContext.remoteRandom!,
                  serverRandom: dtlsContext.localRandom!,
                  curve: cipherContext.namedCurve!,
                  publicKey: cipherContext.localPublicKey!,
                  privateKey: privateKey,
                )
              : Uint8List(64); // Placeholder signature if randoms not set

      final serverKeyExchange = ServerKeyExchange(
        curve: cipherContext.namedCurve!,
        publicKey: cipherContext.localPublicKey!,
        signatureScheme: cipherContext.signatureScheme ??
            SignatureScheme.ecdsaSecp256r1Sha256,
        signature: signature,
      );
      final skeBody = serverKeyExchange.serialize();
      final skeMsg = wrapHandshakeMessage(
        HandshakeType.serverKeyExchange,
        skeBody,
        messageSeq: 0,
      );
      // Add full message with header to handshake buffer
      dtlsContext.addHandshakeMessage(skeMsg);
      messages.add(recordLayer.wrapHandshake(skeMsg).serialize());
    }

    // 4. CertificateRequest (if requiring client authentication)
    // RFC 5246 Section 7.4.4 - sent between ServerKeyExchange and ServerHelloDone
    // Note: Browsers typically don't send client certificates in WebRTC.
    // This is here for completeness to match werift (flight4.ts).
    if (requireClientCert) {
      final certRequest = CertificateRequest.createDefault();
      final certReqBody = certRequest.serialize();
      final certReqMsg = wrapHandshakeMessage(
        HandshakeType.certificateRequest,
        certReqBody,
        messageSeq: 0,
      );
      dtlsContext.addHandshakeMessage(certReqMsg);
      messages.add(recordLayer.wrapHandshake(certReqMsg).serialize());
    }

    // 5. ServerHelloDone
    const serverHelloDone = ServerHelloDone();
    final shdBody = serverHelloDone.serialize();
    final shdMsg = wrapHandshakeMessage(
      HandshakeType.serverHelloDone,
      shdBody,
      messageSeq: 0,
    );
    // Add full message with header to handshake buffer
    dtlsContext.addHandshakeMessage(shdMsg);
    messages.add(recordLayer.wrapHandshake(shdMsg).serialize());

    return messages;
  }

  @override
  Future<bool> processMessages(List<Uint8List> messages) async {
    // Process client's Certificate, ClientKeyExchange, CertificateVerify,
    // ChangeCipherSpec, and Finished messages
    return true;
  }

  /// Select cipher suite from client's offered suites
  CipherSuite _selectCipherSuite() {
    if (dtlsContext.clientHello == null) {
      return cipherSuites.first;
    }

    // Find first match
    for (final offered in dtlsContext.clientHello!.cipherSuites) {
      if (cipherSuites.contains(offered)) {
        return offered;
      }
    }

    return cipherSuites.first;
  }
}

/// Flight 6: ChangeCipherSpec + Finished
class ServerFlight6 extends Flight {
  final DtlsContext dtlsContext;
  final CipherContext cipherContext;
  final DtlsRecordLayer recordLayer;

  ServerFlight6({
    required this.dtlsContext,
    required this.cipherContext,
    required this.recordLayer,
  });

  @override
  int get flightNumber => 6;

  @override
  bool get expectsResponse => false;

  @override
  Future<List<Uint8List>> generateMessages() async {
    final messages = <Uint8List>[];

    // 1. ChangeCipherSpec
    const changeCipherSpec = ChangeCipherSpec();
    final ccsMsg = changeCipherSpec.serialize();
    final ccsRecord = recordLayer.createRecord(
      contentType: ContentType.changeCipherSpec,
      data: ccsMsg,
    );
    messages.add(ccsRecord.serialize());

    // Increment epoch
    dtlsContext.incrementEpoch();

    // 2. Finished
    final verifyData = KeyDerivation.computeVerifyData(dtlsContext, false);
    final finished = Finished.create(verifyData);
    final finishedBody = finished.serialize();
    final finishedMsg = wrapHandshakeMessage(
      HandshakeType.finished,
      finishedBody,
      messageSeq: 0,
    );
    // Add full message with header to handshake buffer (AFTER computing verify_data)
    dtlsContext.addHandshakeMessage(finishedMsg);

    // Finished should be encrypted
    final finishedRecord = recordLayer.wrapHandshake(finishedMsg);
    final encryptedFinished = await recordLayer.encryptRecord(finishedRecord);
    messages.add(encryptedFinished);

    return messages;
  }

  @override
  Future<bool> processMessages(List<Uint8List> messages) async {
    return true;
  }
}

/// Sign ServerKeyExchange parameters
/// RFC 5246 Section 7.4.3
///
/// The hash is computed over:
///   client_random + server_random + server_params
Uint8List _signServerKeyExchange({
  required Uint8List clientRandom,
  required Uint8List serverRandom,
  required NamedCurve curve,
  required Uint8List publicKey,
  required dynamic privateKey,
}) {
  // If no private key, return empty signature
  if (privateKey == null) {
    return Uint8List(64);
  }

  // Build the data to sign: client_random + server_random + server_params
  final paramsLength = 1 +
      2 +
      1 +
      publicKey.length; // ECCurveType + NamedCurve + length + publicKey
  final dataToSign =
      Uint8List(clientRandom.length + serverRandom.length + paramsLength);
  var offset = 0;

  // Client random
  dataToSign.setRange(offset, offset + clientRandom.length, clientRandom);
  offset += clientRandom.length;

  // Server random
  dataToSign.setRange(offset, offset + serverRandom.length, serverRandom);
  offset += serverRandom.length;

  // Server params
  dataToSign[offset++] = 3; // ECCurveType: named_curve
  dataToSign[offset++] = (curve.value >> 8) & 0xFF;
  dataToSign[offset++] = curve.value & 0xFF;
  dataToSign[offset++] = publicKey.length;
  dataToSign.setRange(offset, offset + publicKey.length, publicKey);

  // Hash the data using SHA-256
  final digest = Digest('SHA-256');
  final hash = digest.process(dataToSign);

  // Sign the hash using ECDSA
  if (privateKey is ECPrivateKey) {
    final signer = ECDSASigner(null, HMac(digest, 64));
    signer.init(true, PrivateKeyParameter<ECPrivateKey>(privateKey));
    final ecSignature = signer.generateSignature(hash) as ECSignature;

    // Encode signature as DER SEQUENCE { r, s }
    return _encodeDerSignature(ecSignature);
  }

  // Unsupported key type
  return Uint8List(64);
}

/// Encode ECDSA signature in DER format
/// SEQUENCE { INTEGER r, INTEGER s }
Uint8List _encodeDerSignature(ECSignature signature) {
  final rBytes = _bigIntToBytes(signature.r);
  final sBytes = _bigIntToBytes(signature.s);

  final length = 2 + rBytes.length + 2 + sBytes.length;
  final result = Uint8List(2 + length);
  var offset = 0;

  // SEQUENCE tag
  result[offset++] = 0x30;
  result[offset++] = length;

  // INTEGER r
  result[offset++] = 0x02;
  result[offset++] = rBytes.length;
  result.setRange(offset, offset + rBytes.length, rBytes);
  offset += rBytes.length;

  // INTEGER s
  result[offset++] = 0x02;
  result[offset++] = sBytes.length;
  result.setRange(offset, offset + sBytes.length, sBytes);

  return result;
}

/// Convert BigInt to bytes (with proper padding for DER INTEGER)
Uint8List _bigIntToBytes(BigInt value) {
  var hex = value.toRadixString(16);
  if (hex.length % 2 != 0) {
    hex = '0$hex';
  }

  final bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }

  // Add padding byte if high bit is set (to avoid negative interpretation)
  if (bytes.isNotEmpty && bytes.first >= 0x80) {
    bytes.insert(0, 0x00);
  }

  return Uint8List.fromList(bytes);
}
