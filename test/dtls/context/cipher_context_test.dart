import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/context/cipher_context.dart';
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';

void main() {
  group('CipherContext', () {
    test('construction with default values', () {
      final context = CipherContext();

      expect(context.cipherSuite, isNull);
      expect(context.localKeyPair, isNull);
      expect(context.localPublicKey, isNull);
      expect(context.remotePublicKey, isNull);
      expect(context.namedCurve, isNull);
      expect(context.signatureScheme, isNull);
      expect(context.localCertificate, isNull);
      expect(context.remoteCertificate, isNull);
      expect(context.isClient, isTrue);
    });

    test('construction with isClient false', () {
      final context = CipherContext(isClient: false);
      expect(context.isClient, isFalse);
    });

    test('canEncrypt returns false when localCipher is null', () {
      final context = CipherContext();
      expect(context.canEncrypt, isFalse);
    });

    test('canDecrypt returns false when remoteCipher is null', () {
      final context = CipherContext();
      expect(context.canDecrypt, isFalse);
    });

    test('isEncryptionReady is alias for canEncrypt', () {
      final context = CipherContext();
      expect(context.isEncryptionReady, equals(context.canEncrypt));
    });

    test('isDecryptionReady is alias for canDecrypt', () {
      final context = CipherContext();
      expect(context.isDecryptionReady, equals(context.canDecrypt));
    });

    test('hasKeyPair returns false when localKeyPair is null', () {
      final context = CipherContext();
      expect(context.hasKeyPair, isFalse);
    });

    test('hasRemotePublicKey returns false when remotePublicKey is null', () {
      final context = CipherContext();
      expect(context.hasRemotePublicKey, isFalse);
    });

    test('hasRemotePublicKey returns true when remotePublicKey is set', () {
      final context = CipherContext(
        remotePublicKey: Uint8List.fromList([1, 2, 3]),
      );
      expect(context.hasRemotePublicKey, isTrue);
    });

    test('reset clears all fields', () {
      final context = CipherContext(
        cipherSuite: CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256,
        namedCurve: NamedCurve.x25519,
        signatureScheme: SignatureScheme.ecdsaSecp256r1Sha256,
        localPublicKey: Uint8List(32),
        remotePublicKey: Uint8List(32),
        localCertificate: Uint8List(100),
        remoteCertificate: Uint8List(100),
        localFingerprint: 'AA:BB:CC',
        remoteFingerprint: 'DD:EE:FF',
        isClient: false,
      );

      context.reset();

      expect(context.cipherSuite, isNull);
      expect(context.namedCurve, isNull);
      expect(context.signatureScheme, isNull);
      expect(context.localPublicKey, isNull);
      expect(context.remotePublicKey, isNull);
      expect(context.localCertificate, isNull);
      expect(context.remoteCertificate, isNull);
      expect(context.localFingerprint, isNull);
      expect(context.remoteFingerprint, isNull);
      expect(context.encryptionKeys, isNull);
      expect(context.localCipher, isNull);
      expect(context.remoteCipher, isNull);
    });

    test('toString returns readable format', () {
      final context = CipherContext(
        cipherSuite: CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256,
        namedCurve: NamedCurve.x25519,
      );

      final str = context.toString();
      expect(str, contains('CipherContext'));
      expect(str, contains('canEncrypt'));
      expect(str, contains('canDecrypt'));
    });

    test('clientWriteIV returns null when encryptionKeys is null', () {
      final context = CipherContext();
      expect(context.clientWriteIV, isNull);
    });

    test('serverWriteIV returns null when encryptionKeys is null', () {
      final context = CipherContext();
      expect(context.serverWriteIV, isNull);
    });

    test('clientWriteCipher returns correctly based on isClient', () {
      final context = CipherContext(isClient: true);
      // When isClient is true, clientWriteCipher should be localCipher
      // Both are null so they should be equal
      expect(context.clientWriteCipher, isNull);

      final serverContext = CipherContext(isClient: false);
      // When isClient is false, clientWriteCipher should be remoteCipher
      expect(serverContext.clientWriteCipher, isNull);
    });

    test('serverWriteCipher returns correctly based on isClient', () {
      final context = CipherContext(isClient: true);
      // When isClient is true, serverWriteCipher should be remoteCipher
      expect(context.serverWriteCipher, isNull);

      final serverContext = CipherContext(isClient: false);
      // When isClient is false, serverWriteCipher should be localCipher
      expect(serverContext.serverWriteCipher, isNull);
    });
  });
}
