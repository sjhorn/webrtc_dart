import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/context/cipher_context.dart';
import 'package:webrtc_dart/src/dtls/context/dtls_context.dart';
import 'package:webrtc_dart/src/dtls/flight/client_flights.dart';
import 'package:webrtc_dart/src/dtls/flight/server_flights.dart';
import 'package:webrtc_dart/src/dtls/record/record_layer.dart';

void main() {
  group('ClientFlight1', () {
    test('generates initial ClientHello without cookie', () async {
      final dtlsContext = DtlsContext();
      final cipherContext = CipherContext(isClient: true);
      final recordLayer = DtlsRecordLayer(
        dtlsContext: dtlsContext,
        cipherContext: cipherContext,
      );

      final flight = ClientFlight1(
        dtlsContext: dtlsContext,
        cipherContext: cipherContext,
        recordLayer: recordLayer,
        cipherSuites: [
          CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256,
        ],
        supportedCurves: [
          NamedCurve.x25519,
        ],
      );

      expect(flight.flightNumber, 1);
      expect(flight.expectsResponse, true);

      final messages = await flight.generateMessages();
      expect(messages.length, 1);
      expect(dtlsContext.clientHello, isNotNull);
      expect(dtlsContext.localRandom, isNotNull);
    });
  });

  group('ClientFlight3', () {
    test('generates ClientHello with cookie and key exchange', () async {
      final dtlsContext = DtlsContext();
      dtlsContext.cookie = Uint8List.fromList([1, 2, 3, 4]);

      // Set up master secret for verify_data computation
      dtlsContext.masterSecret =
          Uint8List.fromList(List.generate(48, (i) => i));
      dtlsContext.addHandshakeMessage(Uint8List.fromList([1, 2, 3, 4]));

      final cipherContext = CipherContext(isClient: true);
      cipherContext.localPublicKey =
          Uint8List.fromList(List.generate(32, (i) => i));

      final recordLayer = DtlsRecordLayer(
        dtlsContext: dtlsContext,
        cipherContext: cipherContext,
      );

      final flight = ClientFlight3(
        dtlsContext: dtlsContext,
        cipherContext: cipherContext,
        recordLayer: recordLayer,
        cipherSuites: [
          CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256,
        ],
      );

      expect(flight.flightNumber, 3);
      expect(flight.expectsResponse, true);

      final messages = await flight.generateMessages();
      // Should have: ClientHello, ClientKeyExchange, CCS, Finished
      expect(messages.length, greaterThan(2));
      expect(dtlsContext.epoch, 1); // Epoch incremented after CCS
    });
  });

  group('ServerFlight2', () {
    test('generates HelloVerifyRequest with cookie', () async {
      final dtlsContext = DtlsContext();
      final cipherContext = CipherContext(isClient: false);
      final recordLayer = DtlsRecordLayer(
        dtlsContext: dtlsContext,
        cipherContext: cipherContext,
      );

      final flight = ServerFlight2(
        dtlsContext: dtlsContext,
        recordLayer: recordLayer,
      );

      expect(flight.flightNumber, 2);
      expect(flight.expectsResponse, true);

      final messages = await flight.generateMessages();
      expect(messages.length, 1);
      expect(dtlsContext.cookie, isNotNull);
      expect(dtlsContext.cookie!.length, 20);
    });
  });

  group('ServerFlight4', () {
    test('generates ServerHello and key exchange messages', () async {
      final dtlsContext = DtlsContext();
      final cipherContext = CipherContext(isClient: false);
      cipherContext.localPublicKey =
          Uint8List.fromList(List.generate(32, (i) => i));
      cipherContext.namedCurve = NamedCurve.x25519;

      final recordLayer = DtlsRecordLayer(
        dtlsContext: dtlsContext,
        cipherContext: cipherContext,
      );

      final flight = ServerFlight4(
        dtlsContext: dtlsContext,
        cipherContext: cipherContext,
        recordLayer: recordLayer,
        cipherSuites: [
          CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256,
        ],
      );

      expect(flight.flightNumber, 4);
      expect(flight.expectsResponse, true);

      final messages = await flight.generateMessages();
      // Should have: ServerHello, ServerKeyExchange, ServerHelloDone
      expect(messages.length, greaterThanOrEqualTo(3));
      expect(dtlsContext.serverHello, isNotNull);
    });
  });

  group('ServerFlight6', () {
    test('generates ChangeCipherSpec and Finished', () async {
      final dtlsContext = DtlsContext();

      // Set up master secret for verify_data computation
      dtlsContext.masterSecret =
          Uint8List.fromList(List.generate(48, (i) => i));
      dtlsContext.addHandshakeMessage(Uint8List.fromList([1, 2, 3, 4]));

      final cipherContext = CipherContext(isClient: false);
      final recordLayer = DtlsRecordLayer(
        dtlsContext: dtlsContext,
        cipherContext: cipherContext,
      );

      final flight = ServerFlight6(
        dtlsContext: dtlsContext,
        cipherContext: cipherContext,
        recordLayer: recordLayer,
      );

      expect(flight.flightNumber, 6);
      expect(flight.expectsResponse, false);

      final initialEpoch = dtlsContext.epoch;
      final messages = await flight.generateMessages();

      expect(messages.length, 2); // CCS + Finished
      expect(dtlsContext.epoch, initialEpoch + 1); // Epoch incremented
    });
  });
}
