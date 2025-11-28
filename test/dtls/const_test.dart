import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/record/const.dart' as record;
import 'package:webrtc_dart/src/dtls/handshake/const.dart' as handshake;
import 'package:webrtc_dart/src/dtls/cipher/const.dart' as cipher;

void main() {
  group('Record Layer Constants', () {
    test('ContentType values match RFC 5246', () {
      expect(record.ContentType.changeCipherSpec.value, 20);
      expect(record.ContentType.alert.value, 21);
      expect(record.ContentType.handshake.value, 22);
      expect(record.ContentType.applicationData.value, 23);
    });

    test('ContentType.fromValue() works correctly', () {
      expect(record.ContentType.fromValue(20), record.ContentType.changeCipherSpec);
      expect(record.ContentType.fromValue(21), record.ContentType.alert);
      expect(record.ContentType.fromValue(22), record.ContentType.handshake);
      expect(record.ContentType.fromValue(23), record.ContentType.applicationData);
      expect(record.ContentType.fromValue(99), isNull);
    });

    test('AlertDesc values match RFC 5246', () {
      expect(record.AlertDesc.closeNotify.value, 0);
      expect(record.AlertDesc.unexpectedMessage.value, 10);
      expect(record.AlertDesc.badRecordMac.value, 20);
      expect(record.AlertDesc.decryptionFailed.value, 21);
      expect(record.AlertDesc.recordOverflow.value, 22);
      expect(record.AlertDesc.decompressionFailure.value, 30);
      expect(record.AlertDesc.handshakeFailure.value, 40);
      expect(record.AlertDesc.noCertificate.value, 41);
      expect(record.AlertDesc.badCertificate.value, 42);
      expect(record.AlertDesc.unsupportedCertificate.value, 43);
      expect(record.AlertDesc.certificateRevoked.value, 44);
      expect(record.AlertDesc.certificateExpired.value, 45);
      expect(record.AlertDesc.certificateUnknown.value, 46);
      expect(record.AlertDesc.illegalParameter.value, 47);
      expect(record.AlertDesc.unknownCa.value, 48);
      expect(record.AlertDesc.accessDenied.value, 49);
      expect(record.AlertDesc.decodeError.value, 50);
      expect(record.AlertDesc.decryptError.value, 51);
      expect(record.AlertDesc.exportRestriction.value, 60);
      expect(record.AlertDesc.protocolVersion.value, 70);
      expect(record.AlertDesc.insufficientSecurity.value, 71);
      expect(record.AlertDesc.internalError.value, 80);
      expect(record.AlertDesc.userCanceled.value, 90);
      expect(record.AlertDesc.noRenegotiation.value, 100);
      expect(record.AlertDesc.unsupportedExtension.value, 110);
    });

    test('AlertDesc.fromValue() works correctly', () {
      expect(record.AlertDesc.fromValue(0), record.AlertDesc.closeNotify);
      expect(record.AlertDesc.fromValue(40), record.AlertDesc.handshakeFailure);
      expect(record.AlertDesc.fromValue(80), record.AlertDesc.internalError);
      expect(record.AlertDesc.fromValue(999), isNull);
    });

    test('AlertLevel values match RFC 5246', () {
      expect(handshake.AlertLevel.warning.value, 1);
      expect(handshake.AlertLevel.fatal.value, 2);
    });

    test('AlertLevel.fromValue() works correctly', () {
      expect(handshake.AlertLevel.fromValue(1), handshake.AlertLevel.warning);
      expect(handshake.AlertLevel.fromValue(2), handshake.AlertLevel.fatal);
      expect(handshake.AlertLevel.fromValue(3), isNull);
    });

    test('ProtocolVersion constants match DTLS spec', () {
      // DTLS 1.0 is encoded as 254.255 (inverted from TLS 1.1)
      expect(record.ProtocolVersion.dtls10.major, 254);
      expect(record.ProtocolVersion.dtls10.minor, 255);

      // DTLS 1.2 is encoded as 254.253 (inverted from TLS 1.3)
      expect(record.ProtocolVersion.dtls12.major, 254);
      expect(record.ProtocolVersion.dtls12.minor, 253);
    });

    test('ProtocolVersion equality works', () {
      const v1 = record.ProtocolVersion(254, 253);
      const v2 = record.ProtocolVersion(254, 253);
      const v3 = record.ProtocolVersion(254, 255);

      expect(v1, equals(v2));
      expect(v1, isNot(equals(v3)));
      expect(v1.hashCode, equals(v2.hashCode));
    });

    test('Record layer constants match RFC 6347', () {
      expect(record.dtlsRecordHeaderLength, 13);
      expect(record.dtlsMaxRecordLength, 16384); // 2^14
      expect(record.dtlsMaxFragmentLength, 16384);
      expect(record.dtlsMinRecordSize, 14); // header + 1 byte
    });
  });

  group('Handshake Constants', () {
    test('HandshakeType values match RFC 6347', () {
      expect(handshake.HandshakeType.helloRequest.value, 0);
      expect(handshake.HandshakeType.clientHello.value, 1);
      expect(handshake.HandshakeType.serverHello.value, 2);
      expect(handshake.HandshakeType.helloVerifyRequest.value, 3);
      expect(handshake.HandshakeType.certificate.value, 11);
      expect(handshake.HandshakeType.serverKeyExchange.value, 12);
      expect(handshake.HandshakeType.certificateRequest.value, 13);
      expect(handshake.HandshakeType.serverHelloDone.value, 14);
      expect(handshake.HandshakeType.certificateVerify.value, 15);
      expect(handshake.HandshakeType.clientKeyExchange.value, 16);
      expect(handshake.HandshakeType.finished.value, 20);
    });

    test('HandshakeType.fromValue() works correctly', () {
      expect(handshake.HandshakeType.fromValue(1), handshake.HandshakeType.clientHello);
      expect(handshake.HandshakeType.fromValue(2), handshake.HandshakeType.serverHello);
      expect(handshake.HandshakeType.fromValue(20), handshake.HandshakeType.finished);
      expect(handshake.HandshakeType.fromValue(99), isNull);
    });

    test('CompressionMethod values match RFC 5246', () {
      expect(handshake.CompressionMethod.none.value, 0);
    });

    test('ExtensionType values match RFC specs', () {
      expect(handshake.ExtensionType.serverName.value, 0);
      expect(handshake.ExtensionType.maxFragmentLength.value, 1);
      expect(handshake.ExtensionType.ellipticCurves.value, 10);
      expect(handshake.ExtensionType.ecPointFormats.value, 11);
      expect(handshake.ExtensionType.signatureAlgorithms.value, 13);
      expect(handshake.ExtensionType.useSrtp.value, 14);
      expect(handshake.ExtensionType.heartbeat.value, 15);
      expect(handshake.ExtensionType.extendedMasterSecret.value, 23);
      expect(handshake.ExtensionType.sessionTicket.value, 35);
      expect(handshake.ExtensionType.renegotiationInfo.value, 65281); // 0xFF01
    });

    test('ExtensionType.fromValue() works correctly', () {
      expect(handshake.ExtensionType.fromValue(0), handshake.ExtensionType.serverName);
      expect(handshake.ExtensionType.fromValue(14), handshake.ExtensionType.useSrtp);
      expect(handshake.ExtensionType.fromValue(65281), handshake.ExtensionType.renegotiationInfo);
      expect(handshake.ExtensionType.fromValue(99999), isNull);
    });

    test('HashAlgorithm values match RFC 5246', () {
      expect(handshake.HashAlgorithm.none.value, 0);
      expect(handshake.HashAlgorithm.md5.value, 1);
      expect(handshake.HashAlgorithm.sha1.value, 2);
      expect(handshake.HashAlgorithm.sha224.value, 3);
      expect(handshake.HashAlgorithm.sha256.value, 4);
      expect(handshake.HashAlgorithm.sha384.value, 5);
      expect(handshake.HashAlgorithm.sha512.value, 6);
    });

    test('SignatureAlgorithm values match RFC 5246', () {
      expect(handshake.SignatureAlgorithm.anonymous.value, 0);
      expect(handshake.SignatureAlgorithm.rsa.value, 1);
      expect(handshake.SignatureAlgorithm.dsa.value, 2);
      expect(handshake.SignatureAlgorithm.ecdsa.value, 3);
    });

    test('ECPointFormat values match RFC 4492', () {
      expect(handshake.ECPointFormat.uncompressed.value, 0);
      expect(handshake.ECPointFormat.ansix962CompressedPrime.value, 1);
      expect(handshake.ECPointFormat.ansix962CompressedChar2.value, 2);
    });

    test('Handshake header constants match DTLS spec', () {
      expect(handshake.dtlsHandshakeHeaderLength, 12);
      expect(handshake.dtlsFinishedVerifyDataLength, 12);
    });
  });

  group('Cipher Suite Constants', () {
    test('CipherSuite values match RFC 5289', () {
      // TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
      expect(cipher.CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256.value, 0xC02B);
      // TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
      expect(cipher.CipherSuite.tlsEcdheRsaWithAes128GcmSha256.value, 0xC02F);
    });

    test('CipherSuite.fromValue() works correctly', () {
      expect(
        cipher.CipherSuite.fromValue(0xC02B),
        cipher.CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256,
      );
      expect(
        cipher.CipherSuite.fromValue(0xC02F),
        cipher.CipherSuite.tlsEcdheRsaWithAes128GcmSha256,
      );
      expect(cipher.CipherSuite.fromValue(0x0000), isNull);
    });

    test('NamedCurve values match RFC 8422', () {
      expect(cipher.NamedCurve.x25519.value, 29);
      expect(cipher.NamedCurve.secp256r1.value, 23); // NIST P-256
    });

    test('NamedCurve.fromValue() works correctly', () {
      expect(cipher.NamedCurve.fromValue(29), cipher.NamedCurve.x25519);
      expect(cipher.NamedCurve.fromValue(23), cipher.NamedCurve.secp256r1);
      expect(cipher.NamedCurve.fromValue(999), isNull);
    });

    test('CurveType values match RFC 4492', () {
      expect(cipher.CurveType.namedCurve.value, 3);
    });

    test('SignatureScheme values match RFC 8446', () {
      expect(handshake.SignatureScheme.rsaPkcs1Sha256.value, 0x0401);
      expect(handshake.SignatureScheme.ecdsaSecp256r1Sha256.value, 0x0403);
    });

    test('SignatureScheme.fromValue() works correctly', () {
      expect(
        handshake.SignatureScheme.fromValue(0x0401),
        handshake.SignatureScheme.rsaPkcs1Sha256,
      );
      expect(
        handshake.SignatureScheme.fromValue(0x0403),
        handshake.SignatureScheme.ecdsaSecp256r1Sha256,
      );
      expect(handshake.SignatureScheme.fromValue(0x0000), isNull);
    });

    test('supportedCertificateTypes match RFC 5246', () {
      expect(cipher.supportedCertificateTypes, [1, 64]);
      expect(cipher.supportedCertificateTypes[0], 1); // RSA sign
      expect(cipher.supportedCertificateTypes[1], 64); // ECDSA sign
    });

    test('SignatureHash equality and hashCode work', () {
      const sh1 = cipher.SignatureHash(hash: 4, signature: 1);
      const sh2 = cipher.SignatureHash(hash: 4, signature: 1);
      const sh3 = cipher.SignatureHash(hash: 4, signature: 3);

      expect(sh1, equals(sh2));
      expect(sh1, isNot(equals(sh3)));
      expect(sh1.hashCode, equals(sh2.hashCode));
    });

    test('SignatureHash.toScheme() converts correctly', () {
      const rsaSha256 = cipher.SignatureHash(hash: 4, signature: 1);
      expect(rsaSha256.toScheme(), handshake.SignatureScheme.rsaPkcs1Sha256);

      const ecdsaSha256 = cipher.SignatureHash(hash: 4, signature: 3);
      expect(ecdsaSha256.toScheme(), handshake.SignatureScheme.ecdsaSecp256r1Sha256);

      const unknown = cipher.SignatureHash(hash: 5, signature: 1);
      expect(unknown.toScheme(), isNull);
    });

    test('SignatureHash.fromScheme() converts correctly', () {
      final rsaSh = cipher.SignatureHash.fromScheme(
        handshake.SignatureScheme.rsaPkcs1Sha256,
      );
      expect(rsaSh.hash, 4);
      expect(rsaSh.signature, 1);

      final ecdsaSh = cipher.SignatureHash.fromScheme(
        handshake.SignatureScheme.ecdsaSecp256r1Sha256,
      );
      expect(ecdsaSh.hash, 4);
      expect(ecdsaSh.signature, 3);
    });

    test('supportedSignatureAlgorithms contains expected values', () {
      expect(cipher.supportedSignatureAlgorithms.length, 2);
      expect(
        cipher.supportedSignatureAlgorithms,
        contains(const cipher.SignatureHash(hash: 4, signature: 1)), // SHA256 + RSA
      );
      expect(
        cipher.supportedSignatureAlgorithms,
        contains(const cipher.SignatureHash(hash: 4, signature: 3)), // SHA256 + ECDSA
      );
    });

    test('getKeyExchangeAlgorithm returns correct values', () {
      expect(
        cipher.getKeyExchangeAlgorithm(
          cipher.CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256,
        ),
        cipher.KeyExchangeAlgorithm.ecdhe,
      );
      expect(
        cipher.getKeyExchangeAlgorithm(
          cipher.CipherSuite.tlsEcdheRsaWithAes128GcmSha256,
        ),
        cipher.KeyExchangeAlgorithm.ecdhe,
      );
    });

    test('getBulkCipherAlgorithm returns correct values', () {
      expect(
        cipher.getBulkCipherAlgorithm(
          cipher.CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256,
        ),
        cipher.BulkCipherAlgorithm.aes128Gcm,
      );
      expect(
        cipher.getBulkCipherAlgorithm(
          cipher.CipherSuite.tlsEcdheRsaWithAes128GcmSha256,
        ),
        cipher.BulkCipherAlgorithm.aes128Gcm,
      );
    });

    test('getMacAlgorithm returns correct values', () {
      expect(
        cipher.getMacAlgorithm(
          cipher.CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256,
        ),
        cipher.MacAlgorithm.sha256,
      );
      expect(
        cipher.getMacAlgorithm(
          cipher.CipherSuite.tlsEcdheRsaWithAes128GcmSha256,
        ),
        cipher.MacAlgorithm.sha256,
      );
    });

    test('Cipher constants match TLS spec', () {
      expect(cipher.masterSecretLength, 48);
      expect(cipher.premasterSecretLength, 48);
      expect(cipher.verifyDataLength, 12);
      expect(cipher.randomLength, 32);
      expect(cipher.sessionIdMaxLength, 32);
    });

    test('supportedCipherSuites contains all cipher suites', () {
      expect(cipher.supportedCipherSuites.length, 2);
      expect(
        cipher.supportedCipherSuites,
        contains(cipher.CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256),
      );
      expect(
        cipher.supportedCipherSuites,
        contains(cipher.CipherSuite.tlsEcdheRsaWithAes128GcmSha256),
      );
    });

    test('supportedNamedCurves contains all curves', () {
      expect(cipher.supportedNamedCurves.length, 2);
      expect(cipher.supportedNamedCurves, contains(cipher.NamedCurve.x25519));
      expect(cipher.supportedNamedCurves, contains(cipher.NamedCurve.secp256r1));
    });
  });
}
