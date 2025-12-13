import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/context/cipher_context.dart';
import 'package:webrtc_dart/src/dtls/context/dtls_context.dart';
import 'package:webrtc_dart/src/dtls/context/srtp_context.dart';
import 'package:webrtc_dart/src/dtls/flight/flight.dart';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/extended_master_secret.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/use_srtp.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/client_hello.dart';
import 'package:webrtc_dart/src/dtls/record/record_layer.dart';
import 'package:webrtc_dart/src/dtls/server_handshake.dart';

void main() {
  group('ServerHandshakeCoordinator', () {
    group('SRTP negotiation', () {
      test('negotiates SRTP profile from ClientHello', () async {
        final dtlsContext = DtlsContext();
        final cipherContext = CipherContext(isClient: false);
        final srtpContext = SrtpContext();
        final recordLayer = DtlsRecordLayer(
          dtlsContext: dtlsContext,
          cipherContext: cipherContext,
        );
        final flightManager = FlightManager();

        final coordinator = ServerHandshakeCoordinator(
          dtlsContext: dtlsContext,
          cipherContext: cipherContext,
          srtpContext: srtpContext,
          recordLayer: recordLayer,
          flightManager: flightManager,
          cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
          supportedCurves: [NamedCurve.x25519],
        );

        // Create ClientHello with SRTP profiles
        final clientHello = ClientHello.create(
          sessionId: Uint8List(0),
          extensions: [
            UseSrtpExtension(profiles: [
              SrtpProtectionProfile.srtpAes128CmHmacSha1_80,
              SrtpProtectionProfile.srtpAes128CmHmacSha1_32,
            ]),
          ],
        );

        // Process first ClientHello
        await coordinator.processHandshakeWithType(
          HandshakeType.clientHello,
          clientHello.serialize(),
        );

        // Verify SRTP profile was negotiated
        expect(
            srtpContext.profile, SrtpProtectionProfile.srtpAes128CmHmacSha1_80);
      });

      test('selects first matching SRTP profile (server preference)', () async {
        final dtlsContext = DtlsContext();
        final cipherContext = CipherContext(isClient: false);
        final srtpContext = SrtpContext();
        final recordLayer = DtlsRecordLayer(
          dtlsContext: dtlsContext,
          cipherContext: cipherContext,
        );
        final flightManager = FlightManager();

        final coordinator = ServerHandshakeCoordinator(
          dtlsContext: dtlsContext,
          cipherContext: cipherContext,
          srtpContext: srtpContext,
          recordLayer: recordLayer,
          flightManager: flightManager,
          cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
          supportedCurves: [NamedCurve.x25519],
        );

        // ClientHello with 32-bit profile first (but server prefers 80-bit)
        final clientHello = ClientHello.create(
          sessionId: Uint8List(0),
          extensions: [
            UseSrtpExtension(profiles: [
              SrtpProtectionProfile
                  .srtpAes128CmHmacSha1_32, // Client's first choice
              SrtpProtectionProfile
                  .srtpAes128CmHmacSha1_80, // Server's first choice
            ]),
          ],
        );

        await coordinator.processHandshakeWithType(
          HandshakeType.clientHello,
          clientHello.serialize(),
        );

        // Server should select its preferred profile (80-bit) since both are offered
        expect(
            srtpContext.profile, SrtpProtectionProfile.srtpAes128CmHmacSha1_80);
      });

      test('leaves SRTP profile null when client offers none', () async {
        final dtlsContext = DtlsContext();
        final cipherContext = CipherContext(isClient: false);
        final srtpContext = SrtpContext();
        final recordLayer = DtlsRecordLayer(
          dtlsContext: dtlsContext,
          cipherContext: cipherContext,
        );
        final flightManager = FlightManager();

        final coordinator = ServerHandshakeCoordinator(
          dtlsContext: dtlsContext,
          cipherContext: cipherContext,
          srtpContext: srtpContext,
          recordLayer: recordLayer,
          flightManager: flightManager,
          cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
          supportedCurves: [NamedCurve.x25519],
        );

        // ClientHello without SRTP extension
        final clientHello = ClientHello.create(
          sessionId: Uint8List(0),
        );

        await coordinator.processHandshakeWithType(
          HandshakeType.clientHello,
          clientHello.serialize(),
        );

        // No SRTP profile should be selected
        expect(srtpContext.profile, isNull);
      });
    });

    group('Retransmission handling', () {
      test(
          'handles retransmitted ClientHello in waitingForClientKeyExchange state',
          () async {
        final dtlsContext = DtlsContext();
        final cipherContext = CipherContext(isClient: false);
        final srtpContext = SrtpContext();
        final recordLayer = DtlsRecordLayer(
          dtlsContext: dtlsContext,
          cipherContext: cipherContext,
        );
        final flightManager = FlightManager();

        final coordinator = ServerHandshakeCoordinator(
          dtlsContext: dtlsContext,
          cipherContext: cipherContext,
          srtpContext: srtpContext,
          recordLayer: recordLayer,
          flightManager: flightManager,
          cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
          supportedCurves: [NamedCurve.x25519],
        );

        // First ClientHello without cookie
        final clientHello1 = ClientHello.create(sessionId: Uint8List(0));
        await coordinator.processHandshakeWithType(
          HandshakeType.clientHello,
          clientHello1.serialize(),
        );

        expect(coordinator.state,
            ServerHandshakeState.waitingForClientHelloWithCookie);
        expect(dtlsContext.cookie, isNotNull);

        // Second ClientHello with cookie
        final clientHello2 = ClientHello.create(
          sessionId: Uint8List(0),
          cookie: dtlsContext.cookie,
        );
        final fullMessage = clientHello2.serialize();
        await coordinator.processHandshakeWithType(
          HandshakeType.clientHello,
          fullMessage,
          fullMessage: fullMessage,
        );

        expect(coordinator.state,
            ServerHandshakeState.waitingForClientKeyExchange);

        // Simulate retransmitted ClientHello - should not throw
        // (This tests the fix for "Unexpected second ClientHello" error)
        await coordinator.processHandshakeWithType(
          HandshakeType.clientHello,
          fullMessage,
          fullMessage: fullMessage,
        );

        // Should still be in same state, not failed
        expect(coordinator.state,
            ServerHandshakeState.waitingForClientKeyExchange);
        expect(coordinator.isFailed, false);
      });

      test('marks flight for retransmission on retransmitted ClientHello',
          () async {
        final dtlsContext = DtlsContext();
        final cipherContext = CipherContext(isClient: false);
        final srtpContext = SrtpContext();
        final recordLayer = DtlsRecordLayer(
          dtlsContext: dtlsContext,
          cipherContext: cipherContext,
        );
        final flightManager = FlightManager();

        final coordinator = ServerHandshakeCoordinator(
          dtlsContext: dtlsContext,
          cipherContext: cipherContext,
          srtpContext: srtpContext,
          recordLayer: recordLayer,
          flightManager: flightManager,
          cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
          supportedCurves: [NamedCurve.x25519],
        );

        // Setup: First ClientHello -> HelloVerifyRequest
        final clientHello1 = ClientHello.create(sessionId: Uint8List(0));
        await coordinator.processHandshakeWithType(
          HandshakeType.clientHello,
          clientHello1.serialize(),
        );

        // Second ClientHello with cookie -> Flight 4
        final clientHello2 = ClientHello.create(
          sessionId: Uint8List(0),
          cookie: dtlsContext.cookie,
        );
        final fullMessage = clientHello2.serialize();
        await coordinator.processHandshakeWithType(
          HandshakeType.clientHello,
          fullMessage,
          fullMessage: fullMessage,
        );

        // Mark flight as sent
        final currentFlight = flightManager.currentFlight;
        expect(currentFlight, isNotNull);
        currentFlight!.markSent();
        expect(currentFlight.sent, true);

        // Retransmitted ClientHello should mark flight as not sent
        await coordinator.processHandshakeWithType(
          HandshakeType.clientHello,
          fullMessage,
          fullMessage: fullMessage,
        );

        expect(currentFlight.sent, false);
      });
    });

    group('Extended master secret', () {
      test('negotiates extended master secret when offered by client',
          () async {
        final dtlsContext = DtlsContext();
        final cipherContext = CipherContext(isClient: false);
        final srtpContext = SrtpContext();
        final recordLayer = DtlsRecordLayer(
          dtlsContext: dtlsContext,
          cipherContext: cipherContext,
        );
        final flightManager = FlightManager();

        final coordinator = ServerHandshakeCoordinator(
          dtlsContext: dtlsContext,
          cipherContext: cipherContext,
          srtpContext: srtpContext,
          recordLayer: recordLayer,
          flightManager: flightManager,
          cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
          supportedCurves: [NamedCurve.x25519],
        );

        // ClientHello with extended master secret extension
        final clientHello = ClientHello.create(
          sessionId: Uint8List(0),
          extensions: [
            ExtendedMasterSecretExtension(),
          ],
        );

        await coordinator.processHandshakeWithType(
          HandshakeType.clientHello,
          clientHello.serialize(),
        );

        expect(dtlsContext.useExtendedMasterSecret, true);
      });

      test('does not use extended master secret when not offered', () async {
        final dtlsContext = DtlsContext();
        final cipherContext = CipherContext(isClient: false);
        final srtpContext = SrtpContext();
        final recordLayer = DtlsRecordLayer(
          dtlsContext: dtlsContext,
          cipherContext: cipherContext,
        );
        final flightManager = FlightManager();

        final coordinator = ServerHandshakeCoordinator(
          dtlsContext: dtlsContext,
          cipherContext: cipherContext,
          srtpContext: srtpContext,
          recordLayer: recordLayer,
          flightManager: flightManager,
          cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
          supportedCurves: [NamedCurve.x25519],
        );

        // ClientHello without extended master secret
        final clientHello = ClientHello.create(sessionId: Uint8List(0));

        await coordinator.processHandshakeWithType(
          HandshakeType.clientHello,
          clientHello.serialize(),
        );

        expect(dtlsContext.useExtendedMasterSecret, false);
      });
    });
  });

  group('ClientHello', () {
    test('srtpProfiles returns profiles from use_srtp extension', () {
      final clientHello = ClientHello.create(
        sessionId: Uint8List(0),
        extensions: [
          UseSrtpExtension(profiles: [
            SrtpProtectionProfile.srtpAes128CmHmacSha1_80,
            SrtpProtectionProfile.srtpAeadAes128Gcm,
          ]),
        ],
      );

      final profiles = clientHello.srtpProfiles;
      expect(profiles, hasLength(2));
      expect(profiles[0], SrtpProtectionProfile.srtpAes128CmHmacSha1_80);
      expect(profiles[1], SrtpProtectionProfile.srtpAeadAes128Gcm);
    });

    test('srtpProfiles returns empty list when no extension', () {
      final clientHello = ClientHello.create(sessionId: Uint8List(0));

      expect(clientHello.srtpProfiles, isEmpty);
    });
  });

  group('FlightState', () {
    test('markNotSent sets sent to false', () {
      final flightManager = FlightManager();
      // Create a simple mock flight
      final flight = _MockFlight(4);
      flightManager.addFlight(flight, [Uint8List(10)]);

      final flightState = flightManager.currentFlight!;
      flightState.markSent();
      expect(flightState.sent, true);

      flightState.markNotSent();
      expect(flightState.sent, false);
    });

    test('markNotSent allows flight to be resent', () {
      final flightManager = FlightManager();
      final flight = _MockFlight(4);
      flightManager.addFlight(flight, [Uint8List(10)]);

      final flightState = flightManager.currentFlight!;

      // Simulate first send
      flightState.markSent();
      expect(flightState.sent, true);

      // Simulate retransmission trigger
      flightState.markNotSent();
      expect(flightState.sent, false);

      // Can be sent again
      flightState.markSent();
      expect(flightState.sent, true);
    });
  });
}

/// Simple mock flight for testing
class _MockFlight extends Flight {
  @override
  final int flightNumber;

  _MockFlight(this.flightNumber);

  @override
  bool get expectsResponse => true;

  @override
  Future<List<Uint8List>> generateMessages() async => [];

  @override
  Future<bool> processMessages(List<Uint8List> messages) async => true;
}
