import 'dart:typed_data';
import 'package:pointycastle/export.dart' as pc;
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/cipher/key_derivation.dart';
import 'package:webrtc_dart/src/dtls/context/cipher_context.dart';
import 'package:webrtc_dart/src/dtls/context/dtls_context.dart';
import 'package:webrtc_dart/src/dtls/flight/flight.dart';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/ec_point_formats.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/elliptic_curves.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/extended_master_secret.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/extension.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/signature_algorithms.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/use_srtp.dart';
import 'package:webrtc_dart/src/dtls/handshake/handshake_header.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/certificate.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/certificate_verify.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/change_cipher_spec.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/client_hello.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/client_key_exchange.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/finished.dart';
import 'package:webrtc_dart/src/dtls/record/const.dart';
import 'package:webrtc_dart/src/dtls/record/record_layer.dart';

/// Flight 1: Initial ClientHello (without cookie)
class ClientFlight1 extends Flight {
  final DtlsContext dtlsContext;
  final CipherContext cipherContext;
  final DtlsRecordLayer recordLayer;
  final List<CipherSuite> cipherSuites;
  final List<NamedCurve> supportedCurves;
  final List<SrtpProtectionProfile> srtpProfiles;

  ClientFlight1({
    required this.dtlsContext,
    required this.cipherContext,
    required this.recordLayer,
    required this.cipherSuites,
    required this.supportedCurves,
    List<SrtpProtectionProfile>? srtpProfiles,
  }) : srtpProfiles = srtpProfiles ??
            [
              SrtpProtectionProfile.srtpAes128CmHmacSha1_80,
              SrtpProtectionProfile.srtpAeadAes128Gcm,
            ];

  @override
  int get flightNumber => 1;

  @override
  bool get expectsResponse => true;

  /// Build the list of extensions for ClientHello
  List<Extension> _buildExtensions() {
    return [
      // Supported groups (elliptic curves)
      EllipticCurvesExtension(supportedCurves),
      // EC point formats
      ECPointFormatsExtension([ECPointFormat.uncompressed]),
      // Signature algorithms
      SignatureAlgorithmsExtension([
        SignatureScheme.ecdsaSecp256r1Sha256,
        SignatureScheme.rsaPkcs1Sha256,
      ]),
      // use_srtp for WebRTC
      UseSrtpExtension(profiles: srtpProfiles),
      // Extended master secret for better security
      ExtendedMasterSecretExtension(),
    ];
  }

  @override
  Future<List<Uint8List>> generateMessages() async {
    // Create ClientHello without cookie but with extensions
    final clientHello = ClientHello.create(
      sessionId: dtlsContext.sessionId ?? Uint8List(0),
      cookie: Uint8List(0), // No cookie in initial flight
      cipherSuites: cipherSuites,
      extensions: _buildExtensions(),
    );

    // Store in context
    dtlsContext.clientHello = clientHello;
    dtlsContext.localRandom = clientHello.random.bytes;

    // Serialize message body
    final messageBody = clientHello.serialize();

    // Wrap with handshake header
    final handshakeMessage = wrapHandshakeMessage(
      HandshakeType.clientHello,
      messageBody,
      messageSeq: dtlsContext.getNextHandshakeMessageSeq(),
    );
    // Add full message with header to handshake buffer for verify_data computation
    dtlsContext.addHandshakeMessage(handshakeMessage);

    // Wrap in record
    final record = recordLayer.wrapHandshake(handshakeMessage);
    final serialized = record.serialize();

    return [serialized];
  }

  @override
  Future<bool> processMessages(List<Uint8List> messages) async {
    // Process HelloVerifyRequest from server
    // This flight expects a HelloVerifyRequest in response
    return true; // Move to next flight after receiving response
  }
}

/// Flight 3: ClientHello (with cookie) + Certificate + ClientKeyExchange +
///           CertificateVerify + ChangeCipherSpec + Finished
class ClientFlight3 extends Flight {
  final DtlsContext dtlsContext;
  final CipherContext cipherContext;
  final DtlsRecordLayer recordLayer;
  final List<CipherSuite> cipherSuites;
  final List<NamedCurve> supportedCurves;
  final List<SrtpProtectionProfile> srtpProfiles;
  final Uint8List? certificate;
  final bool includeClientHello;
  final bool sendEmptyCertificate;

  ClientFlight3({
    required this.dtlsContext,
    required this.cipherContext,
    required this.recordLayer,
    required this.cipherSuites,
    List<NamedCurve>? supportedCurves,
    List<SrtpProtectionProfile>? srtpProfiles,
    this.certificate,
    this.includeClientHello = true,
    this.sendEmptyCertificate = false,
  })  : supportedCurves = supportedCurves ??
            [
              NamedCurve.x25519,
              NamedCurve.secp256r1,
            ],
        srtpProfiles = srtpProfiles ??
            [
              SrtpProtectionProfile.srtpAes128CmHmacSha1_80,
              SrtpProtectionProfile.srtpAeadAes128Gcm,
            ];

  @override
  int get flightNumber => 3;

  @override
  bool get expectsResponse => true;

  /// Build the list of extensions for ClientHello
  List<Extension> _buildExtensions() {
    return [
      // Supported groups (elliptic curves)
      EllipticCurvesExtension(supportedCurves),
      // EC point formats
      ECPointFormatsExtension([ECPointFormat.uncompressed]),
      // Signature algorithms
      SignatureAlgorithmsExtension([
        SignatureScheme.ecdsaSecp256r1Sha256,
        SignatureScheme.rsaPkcs1Sha256,
      ]),
      // use_srtp for WebRTC
      UseSrtpExtension(profiles: srtpProfiles),
      // Extended master secret for better security
      ExtendedMasterSecretExtension(),
    ];
  }

  @override
  Future<List<Uint8List>> generateMessages() async {
    final messages = <Uint8List>[];

    // 1. ClientHello with cookie (only if requested)
    if (includeClientHello) {
      if (dtlsContext.cookie == null) {
        throw StateError('Cookie must be set before generating Flight 3');
      }

      final clientHello = ClientHello.create(
        sessionId: dtlsContext.sessionId ?? Uint8List(0),
        cookie: dtlsContext.cookie!,
        cipherSuites: cipherSuites,
        extensions: _buildExtensions(),
      );
      dtlsContext.clientHello = clientHello;
      dtlsContext.localRandom = clientHello.random.bytes;

      final clientHelloBody = clientHello.serialize();
      final clientHelloMsg = wrapHandshakeMessage(
        HandshakeType.clientHello,
        clientHelloBody,
        messageSeq: 0,
      );
      // Add full message with header to handshake buffer
      dtlsContext.addHandshakeMessage(clientHelloMsg);
      messages.add(recordLayer.wrapHandshake(clientHelloMsg).serialize());

      // Only send the rest of the flight if we have a master secret
      // (meaning key exchange has been completed)
      if (dtlsContext.masterSecret == null) {
        return messages;
      }
    }

    // 2. Certificate (if server requested it)
    // In WebRTC, we MUST send our certificate for mutual authentication
    final bool shouldSendCertificate = sendEmptyCertificate || certificate != null;
    if (shouldSendCertificate) {
      // Use local certificate from cipher context if available
      final certToSend = cipherContext.localCertificate ?? certificate;

      Uint8List certBody;
      if (certToSend != null) {
        // Send actual certificate
        final certMessage = Certificate.single(certToSend);
        certBody = certMessage.serialize();
        print('[CLIENT] Sending Certificate with ${certToSend.length} bytes');
      } else {
        // Fallback to empty certificate (should not happen in WebRTC)
        certBody = Uint8List(3); // 3 zero bytes = empty certificate list
        print('[CLIENT] Warning: Sending empty Certificate message');
      }

      final certSeq = dtlsContext.getNextHandshakeMessageSeq();
      final certMsg = wrapHandshakeMessage(
        HandshakeType.certificate,
        certBody,
        messageSeq: certSeq,
      );
      // Add full message with header to handshake buffer
      dtlsContext.addHandshakeMessage(certMsg);
      messages.add(recordLayer.wrapHandshake(certMsg).serialize());
      print('[CLIENT] Sent Certificate message (seq=$certSeq)');
    }

    // 3. ClientKeyExchange
    if (cipherContext.localPublicKey != null) {
      final clientKeyExchange = ClientKeyExchange.fromPublicKey(
        cipherContext.localPublicKey!,
      );
      final ckeBody = clientKeyExchange.serialize();
      final ckeSeq = dtlsContext.getNextHandshakeMessageSeq();
      final ckeMsg = wrapHandshakeMessage(
        HandshakeType.clientKeyExchange,
        ckeBody,
        messageSeq: ckeSeq,
      );
      // Add full message with header to handshake buffer
      dtlsContext.addHandshakeMessage(ckeMsg);
      messages.add(recordLayer.wrapHandshake(ckeMsg).serialize());
      print('[CLIENT] Sent ClientKeyExchange (seq=$ckeSeq)');
    }

    // 4. Derive master secret and initialize ciphers
    // This must happen AFTER Certificate and ClientKeyExchange are in the buffer
    // (required for extended master secret per RFC 7627)
    if (dtlsContext.masterSecret == null) {
      print('[CLIENT] Deriving master secret (extended=${dtlsContext.useExtendedMasterSecret})');
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

    // 5. CertificateVerify (if client has certificate)
    // The signature is over all handshake messages so far (before CertificateVerify)
    if (shouldSendCertificate && cipherContext.localCertificate != null && cipherContext.localSigningKey != null) {
      // Get all handshake messages concatenated for signing
      final handshakeData = dtlsContext.getAllHandshakeMessages();
      print('[CLIENT] CertificateVerify: signing ${handshakeData.length} bytes of handshake data');
      print('[CLIENT] Handshake messages count: ${dtlsContext.handshakeMessages.length}');
      for (var i = 0; i < dtlsContext.handshakeMessages.length; i++) {
        final msg = dtlsContext.handshakeMessages[i];
        final msgType = msg.isNotEmpty ? msg[0] : -1;
        print('[CLIENT]   Message $i: type=$msgType, length=${msg.length}');
      }

      // Sign the handshake hash with our private key
      final signature = _signHandshakeHash(handshakeData, cipherContext.localSigningKey!);

      // Use ECDSA with SHA-256 (matching our certificate)
      final certVerify = CertificateVerify.create(
        SignatureScheme.ecdsaSecp256r1Sha256,
        signature,
      );
      final certVerifyBody = certVerify.serialize();
      final certVerifySeq = dtlsContext.getNextHandshakeMessageSeq();
      final certVerifyMsg = wrapHandshakeMessage(
        HandshakeType.certificateVerify,
        certVerifyBody,
        messageSeq: certVerifySeq,
      );
      // Add to handshake buffer (needed for Finished calculation)
      dtlsContext.addHandshakeMessage(certVerifyMsg);
      messages.add(recordLayer.wrapHandshake(certVerifyMsg).serialize());
      print('[CLIENT] Sent CertificateVerify (seq=$certVerifySeq, signature=${signature.length} bytes)');
    }

    // 6. ChangeCipherSpec
    const changeCipherSpec = ChangeCipherSpec();
    final ccsMsg = changeCipherSpec.serialize();
    // Note: CCS is NOT a handshake message, so don't add to handshake buffer
    final ccsRecord = recordLayer.createRecord(
      contentType: ContentType.changeCipherSpec,
      data: ccsMsg,
    );
    messages.add(ccsRecord.serialize());

    // After CCS, increment epoch
    dtlsContext.incrementEpoch();

    // 8. Finished
    // Compute verify_data from all handshake messages (BEFORE adding Finished itself)
    final verifyData = KeyDerivation.computeVerifyData(dtlsContext, true);
    final finished = Finished.create(verifyData);
    final finishedBody = finished.serialize();
    final finishedSeq = dtlsContext.getNextHandshakeMessageSeq();
    final finishedMsg = wrapHandshakeMessage(
      HandshakeType.finished,
      finishedBody,
      messageSeq: finishedSeq,
    );
    // Add full message with header to handshake buffer (AFTER computing verify_data)
    dtlsContext.addHandshakeMessage(finishedMsg);
    print('[CLIENT] Sending Finished (seq=$finishedSeq, verify_data=${verifyData.length} bytes)');

    // Finished message should be encrypted
    final finishedRecord = recordLayer.wrapHandshake(finishedMsg);
    final encryptedFinished = await recordLayer.encryptRecord(finishedRecord);
    messages.add(encryptedFinished);

    return messages;
  }

  @override
  Future<bool> processMessages(List<Uint8List> messages) async {
    // Process server's Finished message
    // Verify the server's verify_data
    return true;
  }
}

/// Flight 5: (Abbreviated handshake) ChangeCipherSpec + Finished
class ClientFlight5 extends Flight {
  final DtlsContext dtlsContext;
  final CipherContext cipherContext;
  final DtlsRecordLayer recordLayer;

  ClientFlight5({
    required this.dtlsContext,
    required this.cipherContext,
    required this.recordLayer,
  });

  @override
  int get flightNumber => 5;

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
    final verifyData = KeyDerivation.computeVerifyData(dtlsContext, true);
    final finished = Finished.create(verifyData);
    final finishedBody = finished.serialize();
    dtlsContext.addHandshakeMessage(finishedBody);
    final finishedMsg = wrapHandshakeMessage(
      HandshakeType.finished,
      finishedBody,
      messageSeq: dtlsContext.getNextHandshakeMessageSeq(),
    );

    final finishedRecord = recordLayer.wrapHandshake(finishedMsg);
    messages.add(finishedRecord.serialize());

    return messages;
  }

  @override
  Future<bool> processMessages(List<Uint8List> messages) async {
    return true;
  }
}

/// Sign handshake messages hash with ECDSA private key
/// Returns DER-encoded signature
Uint8List _signHandshakeHash(Uint8List handshakeData, pc.ECPrivateKey privateKey) {
  // Hash the handshake messages with SHA-256
  final digest = pc.Digest('SHA-256');
  final hash = digest.process(handshakeData);

  // Sign the hash using ECDSA
  final signer = pc.ECDSASigner(null, pc.HMac(digest, 64));
  signer.init(true, pc.PrivateKeyParameter<pc.ECPrivateKey>(privateKey));
  final signature = signer.generateSignature(hash) as pc.ECSignature;

  // Encode signature as DER SEQUENCE of two INTEGERs
  return _encodeDerSignature(signature.r, signature.s);
}

/// Encode ECDSA signature as DER
Uint8List _encodeDerSignature(BigInt r, BigInt s) {
  final rBytes = _bigIntToBytes(r);
  final sBytes = _bigIntToBytes(s);

  // DER encoding: SEQUENCE { INTEGER r, INTEGER s }
  final rLen = rBytes.length;
  final sLen = sBytes.length;
  final seqLen = 2 + rLen + 2 + sLen; // 2 bytes header for each INTEGER

  final result = Uint8List(2 + seqLen);
  var offset = 0;

  // SEQUENCE tag and length
  result[offset++] = 0x30;
  result[offset++] = seqLen;

  // INTEGER r
  result[offset++] = 0x02;
  result[offset++] = rLen;
  result.setRange(offset, offset + rLen, rBytes);
  offset += rLen;

  // INTEGER s
  result[offset++] = 0x02;
  result[offset++] = sLen;
  result.setRange(offset, offset + sLen, sBytes);

  return result;
}

/// Convert BigInt to bytes with proper DER integer encoding
/// (adds leading 0x00 if high bit is set to ensure positive number)
Uint8List _bigIntToBytes(BigInt value) {
  var hex = value.toRadixString(16);
  if (hex.length % 2 != 0) {
    hex = '0$hex';
  }

  final bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }

  // Add leading zero if high bit is set (to indicate positive number in DER)
  if (bytes.isNotEmpty && (bytes[0] & 0x80) != 0) {
    bytes.insert(0, 0);
  }

  return Uint8List.fromList(bytes);
}
