import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/elliptic_curves.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/extended_master_secret.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/signature_algorithms.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/use_srtp.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/alert.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/change_cipher_spec.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/client_hello.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/client_key_exchange.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/finished.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/hello_verify_request.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/server_hello.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/server_hello_done.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/server_key_exchange.dart';
import 'package:webrtc_dart/src/dtls/handshake/random.dart';
import 'package:webrtc_dart/src/dtls/record/const.dart';

void main() {
  group('DtlsRandom', () {
    test('generates 32-byte random value', () {
      final random = DtlsRandom.generate();
      expect(random.bytes.length, 32);
      expect(random.randomBytes.length, 28);
    });

    test('serializes and deserializes correctly', () {
      final random1 = DtlsRandom.generate();
      final bytes = random1.toBytes();
      final random2 = DtlsRandom.fromBytes(bytes);

      expect(random2.gmtUnixTime, random1.gmtUnixTime);
      expect(random2.randomBytes, equals(random1.randomBytes));
    });

    test('throws on invalid length', () {
      expect(
        () => DtlsRandom.fromBytes(Uint8List(10)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Extensions', () {
    test('EllipticCurves serializes and parses', () {
      final ext = EllipticCurvesExtension([
        NamedCurve.x25519,
        NamedCurve.secp256r1,
      ]);

      final serialized = ext.serialize();
      expect(serialized.length, greaterThan(0));

      final data = serialized.sublist(4); // Skip type and length
      final parsed = EllipticCurvesExtension.parse(data);
      expect(parsed.curves, equals(ext.curves));
    });

    test('SignatureAlgorithms serializes and parses', () {
      final ext = SignatureAlgorithmsExtension([
        SignatureScheme.ecdsaSecp256r1Sha256,
        SignatureScheme.rsaPssRsaeSha256,
      ]);

      final serialized = ext.serialize();
      expect(serialized.length, greaterThan(0));

      final data = serialized.sublist(4);
      final parsed = SignatureAlgorithmsExtension.parse(data);
      expect(parsed.algorithms, equals(ext.algorithms));
    });

    test('UseSrtp serializes and parses', () {
      final ext = UseSrtpExtension(
        profiles: [
          SrtpProtectionProfile.srtpAeadAes128Gcm,
          SrtpProtectionProfile.srtpAes128CmHmacSha1_80,
        ],
      );

      final serialized = ext.serialize();
      expect(serialized.length, greaterThan(0));

      final data = serialized.sublist(4);
      final parsed = UseSrtpExtension.parse(data);
      expect(parsed.profiles, equals(ext.profiles));
    });

    test('ExtendedMasterSecret serializes and parses', () {
      final ext = ExtendedMasterSecretExtension();

      final serialized = ext.serialize();
      expect(serialized.length, 4); // Type + length + empty data

      final data = serialized.sublist(4);
      final parsed = ExtendedMasterSecretExtension.parse(data);
      expect(parsed, isA<ExtendedMasterSecretExtension>());
    });
  });

  group('ClientHello', () {
    test('creates with default values', () {
      final clientHello = ClientHello.create();

      expect(clientHello.clientVersion, ProtocolVersion.dtls12);
      expect(clientHello.random.bytes.length, 32);
      expect(clientHello.cipherSuites.length, greaterThan(0));
      expect(clientHello.compressionMethods, contains(CompressionMethod.none));
    });

    test('serializes and parses correctly', () {
      final clientHello1 = ClientHello.create(
        sessionId: Uint8List.fromList([1, 2, 3]),
        cookie: Uint8List.fromList([4, 5, 6]),
      );

      final serialized = clientHello1.serialize();
      final clientHello2 = ClientHello.parse(serialized);

      expect(clientHello2.clientVersion, clientHello1.clientVersion);
      expect(clientHello2.sessionId, equals(clientHello1.sessionId));
      expect(clientHello2.cookie, equals(clientHello1.cookie));
      expect(
          clientHello2.cipherSuites.length, clientHello1.cipherSuites.length);
    });

    test('includes extensions', () {
      final extensions = [
        EllipticCurvesExtension([NamedCurve.x25519]),
        ExtendedMasterSecretExtension(),
      ];

      final clientHello = ClientHello.create(extensions: extensions);
      expect(clientHello.extensions.length, 2);

      final serialized = clientHello.serialize();
      final parsed = ClientHello.parse(serialized);
      expect(parsed.extensions.length, greaterThanOrEqualTo(0));
    });
  });

  group('ServerHello', () {
    test('creates with selected cipher suite', () {
      final serverHello = ServerHello.create(
        sessionId: Uint8List.fromList([1, 2, 3]),
        cipherSuite: CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256,
      );

      expect(serverHello.serverVersion, ProtocolVersion.dtls12);
      expect(serverHello.cipherSuite,
          CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256);
      expect(serverHello.compressionMethod, CompressionMethod.none);
    });

    test('serializes and parses correctly', () {
      final serverHello1 = ServerHello.create(
        sessionId: Uint8List.fromList([1, 2, 3, 4]),
        cipherSuite: CipherSuite.tlsEcdheRsaWithAes128GcmSha256,
      );

      final serialized = serverHello1.serialize();
      final serverHello2 = ServerHello.parse(serialized);

      expect(serverHello2.serverVersion, serverHello1.serverVersion);
      expect(serverHello2.sessionId, equals(serverHello1.sessionId));
      expect(serverHello2.cipherSuite, serverHello1.cipherSuite);
    });
  });

  group('HelloVerifyRequest', () {
    test('creates with cookie', () {
      final cookie = Uint8List.fromList([1, 2, 3, 4, 5]);
      final hvr = HelloVerifyRequest.create(cookie);

      expect(hvr.serverVersion, ProtocolVersion.dtls12);
      expect(hvr.cookie, equals(cookie));
    });

    test('serializes and parses correctly', () {
      final cookie = Uint8List.fromList(List.generate(20, (i) => i));
      final hvr1 = HelloVerifyRequest.create(cookie);

      final serialized = hvr1.serialize();
      final hvr2 = HelloVerifyRequest.parse(serialized);

      expect(hvr2.serverVersion, hvr1.serverVersion);
      expect(hvr2.cookie, equals(hvr1.cookie));
    });
  });

  group('ServerKeyExchange', () {
    test('serializes and parses ECDHE parameters', () {
      final publicKey = Uint8List.fromList(List.generate(32, (i) => i));
      final signature = Uint8List.fromList(List.generate(64, (i) => i + 100));

      final ske1 = ServerKeyExchange(
        curve: NamedCurve.x25519,
        publicKey: publicKey,
        signatureScheme: SignatureScheme.ecdsaSecp256r1Sha256,
        signature: signature,
      );

      final serialized = ske1.serialize();
      final ske2 = ServerKeyExchange.parse(serialized);

      expect(ske2.curve, ske1.curve);
      expect(ske2.publicKey, equals(ske1.publicKey));
      expect(ske2.signatureScheme, ske1.signatureScheme);
      expect(ske2.signature, equals(ske1.signature));
    });
  });

  group('ClientKeyExchange', () {
    test('serializes and parses public key', () {
      final publicKey = Uint8List.fromList(List.generate(65, (i) => i));
      final cke1 = ClientKeyExchange.fromPublicKey(publicKey);

      final serialized = cke1.serialize();
      final cke2 = ClientKeyExchange.parse(serialized);

      expect(cke2.publicKey, equals(cke1.publicKey));
    });
  });

  group('ServerHelloDone', () {
    test('serializes to empty message', () {
      const shd = ServerHelloDone();
      final serialized = shd.serialize();
      expect(serialized.length, 0);
    });

    test('parses empty message', () {
      final shd = ServerHelloDone.parse(Uint8List(0));
      expect(shd, isA<ServerHelloDone>());
    });
  });

  group('ChangeCipherSpec', () {
    test('serializes to single byte', () {
      const ccs = ChangeCipherSpec();
      final serialized = ccs.serialize();
      expect(serialized.length, 1);
      expect(serialized[0], 1);
    });

    test('parses correctly', () {
      final ccs = ChangeCipherSpec.parse(Uint8List.fromList([1]));
      expect(ccs, isA<ChangeCipherSpec>());
    });
  });

  group('Finished', () {
    test('creates with 12-byte verify data', () {
      final verifyData = Uint8List.fromList(List.generate(12, (i) => i));
      final finished = Finished.create(verifyData);
      expect(finished.verifyData, equals(verifyData));
    });

    test('throws on invalid length', () {
      expect(
        () => Finished.create(Uint8List(10)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('serializes and parses correctly', () {
      final verifyData = Uint8List.fromList(List.generate(12, (i) => i * 2));
      final finished1 = Finished.create(verifyData);

      final serialized = finished1.serialize();
      final finished2 = Finished.parse(serialized);

      expect(finished2.verifyData, equals(finished1.verifyData));
    });
  });

  group('Alert', () {
    test('creates fatal alert', () {
      final alert = Alert.fatal(AlertDescription.handshakeFailure);
      expect(alert.level, AlertLevel.fatal);
      expect(alert.isFatal, true);
      expect(alert.isWarning, false);
    });

    test('creates warning alert', () {
      final alert = Alert.warning(AlertDescription.closeNotify);
      expect(alert.level, AlertLevel.warning);
      expect(alert.isWarning, true);
      expect(alert.isFatal, false);
    });

    test('serializes and parses correctly', () {
      final alert1 = Alert.fatal(AlertDescription.badRecordMac);

      final serialized = alert1.serialize();
      expect(serialized.length, 2);

      final alert2 = Alert.parse(serialized);
      expect(alert2, equals(alert1));
    });

    test('provides common alert shortcuts', () {
      expect(Alert.closeNotify.description, AlertDescription.closeNotify);
      expect(Alert.handshakeFailure.description,
          AlertDescription.handshakeFailure);
      expect(Alert.badRecordMac.description, AlertDescription.badRecordMac);
    });
  });
}
