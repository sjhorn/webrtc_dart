import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/certificate_verify.dart';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';

void main() {
  group('CertificateVerify', () {
    test('construction with signature scheme and signature', () {
      final signature = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final cv = CertificateVerify(
        signatureScheme: SignatureScheme.ecdsaSecp256r1Sha256,
        signature: signature,
      );

      expect(cv.signatureScheme, equals(SignatureScheme.ecdsaSecp256r1Sha256));
      expect(cv.signature, equals(signature));
    });

    test('factory constructor create', () {
      final signature = Uint8List.fromList([10, 20, 30, 40]);
      final cv = CertificateVerify.create(
        SignatureScheme.rsaPkcs1Sha256,
        signature,
      );

      expect(cv.signatureScheme, equals(SignatureScheme.rsaPkcs1Sha256));
      expect(cv.signature, equals(signature));
    });

    test('serialize creates valid bytes', () {
      final signature = Uint8List.fromList([0xAB, 0xCD, 0xEF, 0x12]);
      final cv = CertificateVerify(
        signatureScheme: SignatureScheme.ecdsaSecp256r1Sha256,
        signature: signature,
      );

      final bytes = cv.serialize();

      // 2 bytes signature scheme + 2 bytes length + 4 bytes signature = 8 bytes
      expect(bytes.length, equals(8));

      // Check signature scheme (0x0403 for ecdsaSecp256r1Sha256)
      expect(bytes[0], equals(0x04));
      expect(bytes[1], equals(0x03));

      // Check signature length (4)
      expect(bytes[2], equals(0x00));
      expect(bytes[3], equals(0x04));

      // Check signature data
      expect(bytes.sublist(4), equals(signature));
    });

    test('parse creates valid CertificateVerify', () {
      // Create valid bytes: scheme (0x0403) + length (4) + signature
      final bytes = Uint8List.fromList([
        0x04, 0x03, // ecdsaSecp256r1Sha256
        0x00, 0x04, // length = 4
        0x11, 0x22, 0x33, 0x44, // signature
      ]);

      final cv = CertificateVerify.parse(bytes);

      expect(cv.signatureScheme, equals(SignatureScheme.ecdsaSecp256r1Sha256));
      expect(cv.signature, equals(Uint8List.fromList([0x11, 0x22, 0x33, 0x44])));
    });

    test('parse throws on too short data', () {
      final bytes = Uint8List.fromList([0x04, 0x03]); // Only 2 bytes

      expect(
        () => CertificateVerify.parse(bytes),
        throwsA(isA<FormatException>()),
      );
    });

    test('parse throws on unknown signature scheme', () {
      final bytes = Uint8List.fromList([
        0xFF, 0xFF, // Unknown scheme
        0x00, 0x04,
        0x11, 0x22, 0x33, 0x44,
      ]);

      expect(
        () => CertificateVerify.parse(bytes),
        throwsA(isA<FormatException>()),
      );
    });

    test('parse throws on truncated signature', () {
      final bytes = Uint8List.fromList([
        0x04, 0x03,
        0x00, 0x10, // length = 16 but only 4 bytes follow
        0x11, 0x22, 0x33, 0x44,
      ]);

      expect(
        () => CertificateVerify.parse(bytes),
        throwsA(isA<FormatException>()),
      );
    });

    test('roundtrip serialize/parse', () {
      final original = CertificateVerify(
        signatureScheme: SignatureScheme.rsaPkcs1Sha256,
        signature: Uint8List.fromList(List.generate(64, (i) => i)),
      );

      final bytes = original.serialize();
      final parsed = CertificateVerify.parse(bytes);

      expect(parsed.signatureScheme, equals(original.signatureScheme));
      expect(parsed.signature, equals(original.signature));
    });

    test('toString returns readable format', () {
      final cv = CertificateVerify(
        signatureScheme: SignatureScheme.ecdsaSecp256r1Sha256,
        signature: Uint8List(64),
      );

      final str = cv.toString();
      expect(str, contains('CertificateVerify'));
      expect(str, contains('64 bytes'));
    });

    test('different signature schemes serialize correctly', () {
      // Test RSA PKCS#1 SHA-256
      final rsa = CertificateVerify(
        signatureScheme: SignatureScheme.rsaPkcs1Sha256,
        signature: Uint8List(256),
      );
      final rsaBytes = rsa.serialize();
      expect(rsaBytes[0], equals(0x04));
      expect(rsaBytes[1], equals(0x01));

      // Test ECDSA P-384
      final ecdsa384 = CertificateVerify(
        signatureScheme: SignatureScheme.ecdsaSecp384r1Sha384,
        signature: Uint8List(96),
      );
      final ecdsa384Bytes = ecdsa384.serialize();
      expect(ecdsa384Bytes[0], equals(0x05));
      expect(ecdsa384Bytes[1], equals(0x03));
    });
  });
}
