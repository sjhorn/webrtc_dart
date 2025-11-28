import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/client_handshake.dart';
import 'package:webrtc_dart/src/dtls/context/cipher_context.dart';
import 'package:webrtc_dart/src/dtls/context/dtls_context.dart';
import 'package:webrtc_dart/src/dtls/flight/flight.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/client_hello.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/hello_verify_request.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/server_hello.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/server_hello_done.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/server_key_exchange.dart';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';
import 'package:webrtc_dart/src/dtls/record/record_layer.dart';
import 'package:webrtc_dart/src/dtls/server_handshake.dart';

void main() {
  group('ClientHandshakeCoordinator', () {
    test('starts in initial state', () {
      final dtlsContext = DtlsContext();
      final cipherContext = CipherContext(isClient: true);
      final recordLayer = DtlsRecordLayer(
        dtlsContext: dtlsContext,
        cipherContext: cipherContext,
      );
      final flightManager = FlightManager();

      final coordinator = ClientHandshakeCoordinator(
        dtlsContext: dtlsContext,
        cipherContext: cipherContext,
        recordLayer: recordLayer,
        flightManager: flightManager,
        cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
        supportedCurves: [NamedCurve.x25519],
      );

      expect(coordinator.state, ClientHandshakeState.initial);
      expect(coordinator.isComplete, false);
      expect(coordinator.isFailed, false);
    });

    test('transitions to waitingForHelloVerifyRequest after start', () async {
      final dtlsContext = DtlsContext();
      final cipherContext = CipherContext(isClient: true);
      final recordLayer = DtlsRecordLayer(
        dtlsContext: dtlsContext,
        cipherContext: cipherContext,
      );
      final flightManager = FlightManager();

      final coordinator = ClientHandshakeCoordinator(
        dtlsContext: dtlsContext,
        cipherContext: cipherContext,
        recordLayer: recordLayer,
        flightManager: flightManager,
        cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
        supportedCurves: [NamedCurve.x25519],
      );

      await coordinator.start();

      expect(coordinator.state, ClientHandshakeState.waitingForHelloVerifyRequest);
      expect(dtlsContext.clientHello, isNotNull);
      expect(flightManager.currentFlight, isNotNull);
    });

    test('processes HelloVerifyRequest and transitions state', () async {
      final dtlsContext = DtlsContext();
      final cipherContext = CipherContext(isClient: true);
      final recordLayer = DtlsRecordLayer(
        dtlsContext: dtlsContext,
        cipherContext: cipherContext,
      );
      final flightManager = FlightManager();

      final coordinator = ClientHandshakeCoordinator(
        dtlsContext: dtlsContext,
        cipherContext: cipherContext,
        recordLayer: recordLayer,
        flightManager: flightManager,
        cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
        supportedCurves: [NamedCurve.x25519],
      );

      await coordinator.start();

      // Create HelloVerifyRequest
      final cookie = Uint8List.fromList(List.generate(20, (i) => i));
      final hvr = HelloVerifyRequest.create(cookie);
      final hvrData = hvr.serialize();

      await coordinator.processHandshakeWithType(
        HandshakeType.helloVerifyRequest,
        hvrData,
      );

      expect(coordinator.state, ClientHandshakeState.waitingForServerHello);
      expect(dtlsContext.cookie, equals(cookie));
    });

    test('processes ServerHello and stores context', () async {
      final dtlsContext = DtlsContext();
      final cipherContext = CipherContext(isClient: true);
      final recordLayer = DtlsRecordLayer(
        dtlsContext: dtlsContext,
        cipherContext: cipherContext,
      );
      final flightManager = FlightManager();

      final coordinator = ClientHandshakeCoordinator(
        dtlsContext: dtlsContext,
        cipherContext: cipherContext,
        recordLayer: recordLayer,
        flightManager: flightManager,
        cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
        supportedCurves: [NamedCurve.x25519],
      );

      // Fast-forward to waitingForServerHello state
      await coordinator.start();
      final hvr = HelloVerifyRequest.create(Uint8List(20));
      await coordinator.processHandshakeWithType(
        HandshakeType.helloVerifyRequest,
        hvr.serialize(),
      );

      // Create ServerHello
      final serverHello = ServerHello.create(
        sessionId: Uint8List(32),
        cipherSuite: CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256,
      );
      final shData = serverHello.serialize();

      await coordinator.processHandshakeWithType(
        HandshakeType.serverHello,
        shData,
      );

      expect(coordinator.state, ClientHandshakeState.waitingForCertificate);
      expect(dtlsContext.serverHello, isNotNull);
      expect(dtlsContext.remoteRandom, isNotNull);
      expect(cipherContext.cipherSuite, CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256);
    });
  });

  group('ServerHandshakeCoordinator', () {
    test('starts in waitingForClientHello state', () {
      final dtlsContext = DtlsContext();
      final cipherContext = CipherContext(isClient: false);
      final recordLayer = DtlsRecordLayer(
        dtlsContext: dtlsContext,
        cipherContext: cipherContext,
      );
      final flightManager = FlightManager();

      final coordinator = ServerHandshakeCoordinator(
        dtlsContext: dtlsContext,
        cipherContext: cipherContext,
        recordLayer: recordLayer,
        flightManager: flightManager,
        cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
        supportedCurves: [NamedCurve.x25519],
      );

      expect(coordinator.state, ServerHandshakeState.waitingForClientHello);
      expect(coordinator.isComplete, false);
      expect(coordinator.isFailed, false);
    });

    test('processes first ClientHello without cookie', () async {
      final dtlsContext = DtlsContext();
      final cipherContext = CipherContext(isClient: false);
      final recordLayer = DtlsRecordLayer(
        dtlsContext: dtlsContext,
        cipherContext: cipherContext,
      );
      final flightManager = FlightManager();

      final coordinator = ServerHandshakeCoordinator(
        dtlsContext: dtlsContext,
        cipherContext: cipherContext,
        recordLayer: recordLayer,
        flightManager: flightManager,
        cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
        supportedCurves: [NamedCurve.x25519],
      );

      // Create ClientHello without cookie
      final clientHello = ClientHello.create(
        sessionId: Uint8List(0),
        cookie: Uint8List(0),
        cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
      );
      final chData = clientHello.serialize();

      await coordinator.processHandshakeWithType(
        HandshakeType.clientHello,
        chData,
      );

      expect(
        coordinator.state,
        ServerHandshakeState.waitingForClientHelloWithCookie,
      );
      expect(dtlsContext.cookie, isNotNull);
      expect(dtlsContext.cookie!.length, 20);
    });
  });
}
