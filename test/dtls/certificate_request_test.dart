import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/certificate_request.dart';

void main() {
  group('CertificateRequest', () {
    test('round-trip serialize/parse', () {
      final original = CertificateRequest(
        certificateTypes: [
          ClientCertificateType.rsaSign,
          ClientCertificateType.ecdsaSign,
        ],
        signatureAlgorithms: [
          SignatureHashAlgorithm(
            hash: HashAlgorithm.sha256,
            signature: SignatureAlgorithm.ecdsa,
          ),
          SignatureHashAlgorithm(
            hash: HashAlgorithm.sha256,
            signature: SignatureAlgorithm.rsa,
          ),
        ],
        certificateAuthorities: [],
      );

      final serialized = original.serialize();
      final parsed = CertificateRequest.parse(serialized);

      expect(parsed.certificateTypes.length,
          equals(original.certificateTypes.length));
      expect(parsed.certificateTypes[0], equals(ClientCertificateType.rsaSign));
      expect(
          parsed.certificateTypes[1], equals(ClientCertificateType.ecdsaSign));
      expect(parsed.signatureAlgorithms.length,
          equals(original.signatureAlgorithms.length));
      expect(parsed.signatureAlgorithms[0].hash, equals(HashAlgorithm.sha256));
      expect(parsed.signatureAlgorithms[0].signature,
          equals(SignatureAlgorithm.ecdsa));
      expect(parsed.signatureAlgorithms[1].hash, equals(HashAlgorithm.sha256));
      expect(parsed.signatureAlgorithms[1].signature,
          equals(SignatureAlgorithm.rsa));
      expect(parsed.certificateAuthorities, isEmpty);
    });

    test('parse werift test vector', () {
      // Test vector from werift-webrtc/packages/dtls/tests/handshake/message/server/certificateRequest.test.ts
      // Raw: 0x02, 0x01, 0x40, 0x00, 0x0c, 0x04, 0x03, 0x04, 0x01, 0x05, 0x03, 0x05, 0x01, 0x06, 0x01, 0x02, 0x01, 0x00, 0x00
      final raw = Uint8List.fromList([
        0x02, 0x01, 0x40, // cert types: length=2, RSA_SIGN=1, ECDSA_SIGN=0x40
        0x00, 0x0c, // sig algos length = 12 (6 algorithms * 2 bytes)
        0x04, 0x03, // SHA256 + ECDSA
        0x04, 0x01, // SHA256 + RSA
        0x05, 0x03, // SHA384 + ECDSA
        0x05, 0x01, // SHA384 + RSA
        0x06, 0x01, // SHA512 + RSA
        0x02, 0x01, // SHA1 + RSA
        0x00, 0x00, // authorities length = 0
      ]);

      final parsed = CertificateRequest.parse(raw);

      // Verify certificate types
      expect(parsed.certificateTypes.length, equals(2));
      expect(parsed.certificateTypes[0], equals(ClientCertificateType.rsaSign));
      expect(
          parsed.certificateTypes[1], equals(ClientCertificateType.ecdsaSign));

      // Verify signature algorithms (6 algorithms)
      expect(parsed.signatureAlgorithms.length, equals(6));
      expect(parsed.signatureAlgorithms[0].hash, equals(HashAlgorithm.sha256));
      expect(parsed.signatureAlgorithms[0].signature,
          equals(SignatureAlgorithm.ecdsa));
      expect(parsed.signatureAlgorithms[1].hash, equals(HashAlgorithm.sha256));
      expect(parsed.signatureAlgorithms[1].signature,
          equals(SignatureAlgorithm.rsa));
      expect(parsed.signatureAlgorithms[2].hash, equals(HashAlgorithm.sha384));
      expect(parsed.signatureAlgorithms[2].signature,
          equals(SignatureAlgorithm.ecdsa));
      expect(parsed.signatureAlgorithms[3].hash, equals(HashAlgorithm.sha384));
      expect(parsed.signatureAlgorithms[3].signature,
          equals(SignatureAlgorithm.rsa));
      expect(parsed.signatureAlgorithms[4].hash, equals(HashAlgorithm.sha512));
      expect(parsed.signatureAlgorithms[4].signature,
          equals(SignatureAlgorithm.rsa));
      expect(parsed.signatureAlgorithms[5].hash, equals(HashAlgorithm.sha1));
      expect(parsed.signatureAlgorithms[5].signature,
          equals(SignatureAlgorithm.rsa));

      // Verify authorities
      expect(parsed.certificateAuthorities, isEmpty);

      // Round-trip: serialize and compare
      final reserialized = parsed.serialize();
      expect(reserialized, equals(raw));
    });

    test('createDefault matches werift defaults', () {
      final defaultReq = CertificateRequest.createDefault();

      // werift defaults from cipher/const.ts:
      // certificateTypes = [1, 64] (RSA_SIGN, ECDSA_SIGN)
      // signatures = [{hash: 4, sig: 1}, {hash: 4, sig: 3}] (SHA256+RSA, SHA256+ECDSA)
      expect(defaultReq.certificateTypes.length, equals(2));
      expect(defaultReq.certificateTypes[0],
          equals(ClientCertificateType.rsaSign));
      expect(defaultReq.certificateTypes[1],
          equals(ClientCertificateType.ecdsaSign));

      expect(defaultReq.signatureAlgorithms.length, equals(2));
      expect(
          defaultReq.signatureAlgorithms[0].hash, equals(HashAlgorithm.sha256));
      expect(defaultReq.signatureAlgorithms[0].signature,
          equals(SignatureAlgorithm.rsa));
      expect(
          defaultReq.signatureAlgorithms[1].hash, equals(HashAlgorithm.sha256));
      expect(defaultReq.signatureAlgorithms[1].signature,
          equals(SignatureAlgorithm.ecdsa));

      expect(defaultReq.certificateAuthorities, isEmpty);
    });

    test('serialize with certificate authorities', () {
      final authority1 = Uint8List.fromList([0x01, 0x02, 0x03]);
      final authority2 = Uint8List.fromList([0x04, 0x05, 0x06, 0x07]);

      final request = CertificateRequest(
        certificateTypes: [ClientCertificateType.rsaSign],
        signatureAlgorithms: [
          SignatureHashAlgorithm(
            hash: HashAlgorithm.sha256,
            signature: SignatureAlgorithm.rsa,
          ),
        ],
        certificateAuthorities: [authority1, authority2],
      );

      final serialized = request.serialize();
      final parsed = CertificateRequest.parse(serialized);

      expect(parsed.certificateTypes.length, equals(1));
      expect(parsed.signatureAlgorithms.length, equals(1));
      expect(parsed.certificateAuthorities.length, equals(2));
      expect(parsed.certificateAuthorities[0], equals(authority1));
      expect(parsed.certificateAuthorities[1], equals(authority2));
    });

    test('empty certificate types throws', () {
      expect(
        () => CertificateRequest.parse(Uint8List(0)),
        throwsFormatException,
      );
    });

    test('ClientCertificateType fromValue', () {
      expect(ClientCertificateType.fromValue(1),
          equals(ClientCertificateType.rsaSign));
      expect(ClientCertificateType.fromValue(64),
          equals(ClientCertificateType.ecdsaSign));
      expect(ClientCertificateType.fromValue(999), isNull);
    });

    test('SignatureHashAlgorithm equality', () {
      final a = SignatureHashAlgorithm(
        hash: HashAlgorithm.sha256,
        signature: SignatureAlgorithm.ecdsa,
      );
      final b = SignatureHashAlgorithm(
        hash: HashAlgorithm.sha256,
        signature: SignatureAlgorithm.ecdsa,
      );
      final c = SignatureHashAlgorithm(
        hash: HashAlgorithm.sha256,
        signature: SignatureAlgorithm.rsa,
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('CertificateRequest equality', () {
      final a = CertificateRequest.createDefault();
      final b = CertificateRequest.createDefault();

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('toString', () {
      final request = CertificateRequest.createDefault();
      final str = request.toString();

      expect(str, contains('CertificateRequest'));
      expect(str, contains('certificateTypes'));
      expect(str, contains('signatureAlgorithms'));
    });
  });
}
