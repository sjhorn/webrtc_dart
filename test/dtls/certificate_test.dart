import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/certificate/certificate_generator.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/certificate.dart';

void main() {
  group('CertificateGenerator', () {
    test('generates self-signed certificate', () async {
      final certKeyPair = await generateSelfSignedCertificate();

      expect(certKeyPair.certificate, isNotEmpty);
      expect(certKeyPair.privateKey, isNotNull);
      expect(certKeyPair.publicKey, isNotNull);
    });

    test('generates certificate with custom info', () async {
      final info = CertificateInfo(
        commonName: 'Test Certificate',
        notBefore: DateTime(2024, 1, 1),
        notAfter: DateTime(2025, 1, 1),
      );

      final certKeyPair = await generateSelfSignedCertificate(info: info);

      expect(certKeyPair.certificate, isNotEmpty);
      expect(certKeyPair.privateKey, isNotNull);
      expect(certKeyPair.publicKey, isNotNull);
    });

    test('generated certificate is DER encoded', () async {
      final certKeyPair = await generateSelfSignedCertificate();

      // DER-encoded certificates start with SEQUENCE tag (0x30)
      expect(certKeyPair.certificate[0], 0x30);
    });
  });

  group('Certificate Message', () {
    test('creates empty certificate', () {
      final cert = Certificate(certificates: []);

      expect(cert.isEmpty, true);
      expect(cert.entityCertificate, isNull);
    });

    test('creates single certificate', () {
      final certData = Uint8List.fromList([1, 2, 3, 4, 5]);
      final cert = Certificate.single(certData);

      expect(cert.certificates.length, 1);
      expect(cert.entityCertificate, equals(certData));
      expect(cert.isEmpty, false);
    });

    test('creates certificate chain', () {
      final cert1 = Uint8List.fromList([1, 2, 3]);
      final cert2 = Uint8List.fromList([4, 5, 6]);
      final cert = Certificate.chain([cert1, cert2]);

      expect(cert.certificates.length, 2);
      expect(cert.entityCertificate, equals(cert1));
    });

    test('serializes and parses empty certificate', () {
      final original = Certificate(certificates: []);
      final serialized = original.serialize();
      final parsed = Certificate.parse(serialized);

      expect(parsed.certificates.length, 0);
      expect(parsed.isEmpty, true);
    });

    test('serializes and parses single certificate', () {
      final certData = Uint8List.fromList(List.generate(100, (i) => i));
      final original = Certificate.single(certData);
      final serialized = original.serialize();
      final parsed = Certificate.parse(serialized);

      expect(parsed.certificates.length, 1);
      expect(parsed.entityCertificate, equals(certData));
    });

    test('serializes and parses certificate chain', () {
      final cert1 = Uint8List.fromList(List.generate(50, (i) => i));
      final cert2 = Uint8List.fromList(List.generate(75, (i) => i + 100));
      final cert3 = Uint8List.fromList(List.generate(100, (i) => i + 200));

      final original = Certificate.chain([cert1, cert2, cert3]);
      final serialized = original.serialize();
      final parsed = Certificate.parse(serialized);

      expect(parsed.certificates.length, 3);
      expect(parsed.certificates[0], equals(cert1));
      expect(parsed.certificates[1], equals(cert2));
      expect(parsed.certificates[2], equals(cert3));
    });

    test('serializes certificate correctly', () {
      final certData = Uint8List.fromList([1, 2, 3, 4, 5]);
      final cert = Certificate.single(certData);
      final serialized = cert.serialize();

      // Check structure:
      // 3 bytes: certificate list length
      // 3 bytes: certificate length
      // N bytes: certificate data

      expect(serialized.length, 3 + 3 + 5);

      // Certificate list length should be 8 (3 + 5)
      expect(serialized[0], 0);
      expect(serialized[1], 0);
      expect(serialized[2], 8);

      // Certificate length should be 5
      expect(serialized[3], 0);
      expect(serialized[4], 0);
      expect(serialized[5], 5);

      // Certificate data
      expect(serialized.sublist(6), equals(certData));
    });

    test('parses correctly handles truncated data', () {
      // Too short for header
      expect(
        () => Certificate.parse(Uint8List.fromList([0, 0])),
        throwsFormatException,
      );

      // Truncated certificate list
      final truncated = Uint8List.fromList([
        0, 0, 10, // certificate list length = 10
        0, 0, 5, // certificate length = 5
        1, 2, 3, // only 3 bytes instead of 5
      ]);
      expect(() => Certificate.parse(truncated), throwsFormatException);
    });

    test('handles large certificates', () {
      // Create a large certificate (e.g., 2000 bytes)
      final largeCert = Uint8List.fromList(List.generate(2000, (i) => i % 256));
      final cert = Certificate.single(largeCert);
      final serialized = cert.serialize();
      final parsed = Certificate.parse(serialized);

      expect(parsed.entityCertificate, equals(largeCert));
    });
  });

  group('Certificate Integration', () {
    test('generated certificate can be serialized in Certificate message', () async {
      final certKeyPair = await generateSelfSignedCertificate();
      final certMessage = Certificate.single(certKeyPair.certificate);
      final serialized = certMessage.serialize();
      final parsed = Certificate.parse(serialized);

      expect(parsed.entityCertificate, equals(certKeyPair.certificate));
    });
  });
}
