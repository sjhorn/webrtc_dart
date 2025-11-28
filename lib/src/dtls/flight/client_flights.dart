import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/cipher/key_derivation.dart';
import 'package:webrtc_dart/src/dtls/context/cipher_context.dart';
import 'package:webrtc_dart/src/dtls/context/dtls_context.dart';
import 'package:webrtc_dart/src/dtls/flight/flight.dart';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/handshake_header.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/change_cipher_spec.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/client_hello.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/client_key_exchange.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/finished.dart';
import 'package:webrtc_dart/src/dtls/record/const.dart';
import 'package:webrtc_dart/src/dtls/record/record.dart';
import 'package:webrtc_dart/src/dtls/record/record_layer.dart';

/// Flight 1: Initial ClientHello (without cookie)
class ClientFlight1 extends Flight {
  final DtlsContext dtlsContext;
  final CipherContext cipherContext;
  final DtlsRecordLayer recordLayer;
  final List<CipherSuite> cipherSuites;
  final List<NamedCurve> supportedCurves;

  ClientFlight1({
    required this.dtlsContext,
    required this.cipherContext,
    required this.recordLayer,
    required this.cipherSuites,
    required this.supportedCurves,
  });

  @override
  int get flightNumber => 1;

  @override
  bool get expectsResponse => true;

  @override
  Future<List<Uint8List>> generateMessages() async {
    // Create ClientHello without cookie
    final clientHello = ClientHello.create(
      sessionId: dtlsContext.sessionId ?? Uint8List(0),
      cookie: Uint8List(0), // No cookie in initial flight
      cipherSuites: cipherSuites,
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
      messageSeq: 0,
    );
    dtlsContext.addHandshakeMessage(messageBody);

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
  final Uint8List? certificate;
  final bool includeClientHello;

  ClientFlight3({
    required this.dtlsContext,
    required this.cipherContext,
    required this.recordLayer,
    required this.cipherSuites,
    this.certificate,
    this.includeClientHello = true,
  });

  @override
  int get flightNumber => 3;

  @override
  bool get expectsResponse => true;

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
      );
      dtlsContext.clientHello = clientHello;
      dtlsContext.localRandom = clientHello.random.bytes;

      final clientHelloBody = clientHello.serialize();
      dtlsContext.addHandshakeMessage(clientHelloBody);
      final clientHelloMsg = wrapHandshakeMessage(
        HandshakeType.clientHello,
        clientHelloBody,
        messageSeq: 0,
      );
      messages.add(recordLayer.wrapHandshake(clientHelloMsg).serialize());

      // Only send the rest of the flight if we have a master secret
      // (meaning key exchange has been completed)
      if (dtlsContext.masterSecret == null) {
        return messages;
      }
    }

    // 2. Certificate (if client auth is required)
    if (certificate != null) {
      // TODO: Implement Certificate message
      // final certBody = cert.serialize();
      // dtlsContext.addHandshakeMessage(certBody);
      // final certMsg = wrapHandshakeMessage(HandshakeType.certificate, certBody);
      // messages.add(recordLayer.wrapHandshake(certMsg).serialize());
    }

    // 3. ClientKeyExchange
    if (cipherContext.localPublicKey != null) {
      final clientKeyExchange = ClientKeyExchange.fromPublicKey(
        cipherContext.localPublicKey!,
      );
      final ckeBody = clientKeyExchange.serialize();
      // NOTE: Don't add to handshake buffer here - coordinator already did it before deriving master secret
      // dtlsContext.addHandshakeMessage(ckeBody);
      final ckeMsg = wrapHandshakeMessage(
        HandshakeType.clientKeyExchange,
        ckeBody,
        messageSeq: 0,
      );
      messages.add(recordLayer.wrapHandshake(ckeMsg).serialize());
    }

    // 4. CertificateVerify (if client has certificate)
    // TODO: Implement CertificateVerify message

    // 5. ChangeCipherSpec
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

    // 6. Finished
    // Compute verify_data from all handshake messages
    final verifyData = KeyDerivation.computeVerifyData(dtlsContext, true);
    final finished = Finished.create(verifyData);
    final finishedBody = finished.serialize();
    dtlsContext.addHandshakeMessage(finishedBody);
    final finishedMsg = wrapHandshakeMessage(
      HandshakeType.finished,
      finishedBody,
      messageSeq: 0,
    );

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
      messageSeq: 0,
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
