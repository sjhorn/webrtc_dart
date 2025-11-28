import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/cipher/key_derivation.dart';
import 'package:webrtc_dart/src/dtls/context/cipher_context.dart';
import 'package:webrtc_dart/src/dtls/context/dtls_context.dart';

void main() {
  group('KeyDerivation', () {
    test('deriveMasterSecret with standard mode', () {
      final dtlsContext = DtlsContext();
      dtlsContext.preMasterSecret = Uint8List.fromList(List.generate(32, (i) => i));
      dtlsContext.localRandom = Uint8List.fromList(List.generate(32, (i) => i + 10));
      dtlsContext.remoteRandom = Uint8List.fromList(List.generate(32, (i) => i + 20));

      final cipherContext = CipherContext(isClient: true);

      final masterSecret = KeyDerivation.deriveMasterSecret(
        dtlsContext,
        cipherContext,
        false, // standard mode
      );

      expect(masterSecret.length, 48);
      expect(dtlsContext.masterSecret, isNull); // deriveMasterSecret doesn't store it
    });

    test('deriveMasterSecret with extended master secret', () {
      final dtlsContext = DtlsContext();
      dtlsContext.preMasterSecret = Uint8List.fromList(List.generate(32, (i) => i));
      dtlsContext.localRandom = Uint8List.fromList(List.generate(32, (i) => i + 10));
      dtlsContext.remoteRandom = Uint8List.fromList(List.generate(32, (i) => i + 20));

      final cipherContext = CipherContext(isClient: true);

      // Add some handshake messages
      dtlsContext.addHandshakeMessage(Uint8List.fromList([1, 2, 3, 4]));
      dtlsContext.addHandshakeMessage(Uint8List.fromList([5, 6, 7, 8]));

      final masterSecret = KeyDerivation.deriveMasterSecret(
        dtlsContext,
        cipherContext,
        true, // extended mode
      );

      expect(masterSecret.length, 48);
    });

    test('deriveMasterSecret throws when pre-master secret is missing', () {
      final dtlsContext = DtlsContext();
      dtlsContext.localRandom = Uint8List(32);
      dtlsContext.remoteRandom = Uint8List(32);

      final cipherContext = CipherContext(isClient: true);

      expect(
        () => KeyDerivation.deriveMasterSecret(dtlsContext, cipherContext, false),
        throwsStateError,
      );
    });

    test('deriveMasterSecret throws when random values are missing', () {
      final dtlsContext = DtlsContext();
      dtlsContext.preMasterSecret = Uint8List(32);

      final cipherContext = CipherContext(isClient: true);

      expect(
        () => KeyDerivation.deriveMasterSecret(dtlsContext, cipherContext, false),
        throwsStateError,
      );
    });

    test('deriveEncryptionKeys for AES-128-GCM', () {
      final dtlsContext = DtlsContext();
      dtlsContext.masterSecret = Uint8List.fromList(List.generate(48, (i) => i));
      dtlsContext.localRandom = Uint8List.fromList(List.generate(32, (i) => i + 10));
      dtlsContext.remoteRandom = Uint8List.fromList(List.generate(32, (i) => i + 20));

      final cipherContext = CipherContext(isClient: true);
      cipherContext.cipherSuite = CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256;

      final keys = KeyDerivation.deriveEncryptionKeys(dtlsContext, cipherContext);

      expect(keys.clientWriteKey.length, 16); // AES-128 = 16 bytes
      expect(keys.serverWriteKey.length, 16);
      expect(keys.clientNonce.length, 4); // Implicit nonce = 4 bytes
      expect(keys.serverNonce.length, 4);
    });

    test('deriveEncryptionKeys for different cipher suite', () {
      final dtlsContext = DtlsContext();
      dtlsContext.masterSecret = Uint8List.fromList(List.generate(48, (i) => i));
      dtlsContext.localRandom = Uint8List.fromList(List.generate(32, (i) => i + 10));
      dtlsContext.remoteRandom = Uint8List.fromList(List.generate(32, (i) => i + 20));

      final cipherContext = CipherContext(isClient: false);
      cipherContext.cipherSuite = CipherSuite.tlsEcdheRsaWithAes128GcmSha256;

      final keys = KeyDerivation.deriveEncryptionKeys(dtlsContext, cipherContext);

      expect(keys.clientWriteKey.length, 16); // AES-128 = 16 bytes
      expect(keys.serverWriteKey.length, 16);
      expect(keys.clientNonce.length, 4);
      expect(keys.serverNonce.length, 4);
    });

    test('deriveEncryptionKeys throws when master secret is missing', () {
      final dtlsContext = DtlsContext();
      final cipherContext = CipherContext(isClient: true);
      cipherContext.cipherSuite = CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256;

      expect(
        () => KeyDerivation.deriveEncryptionKeys(dtlsContext, cipherContext),
        throwsStateError,
      );
    });

    test('deriveEncryptionKeys throws when cipher suite is missing', () {
      final dtlsContext = DtlsContext();
      dtlsContext.masterSecret = Uint8List(48);
      final cipherContext = CipherContext(isClient: true);

      expect(
        () => KeyDerivation.deriveEncryptionKeys(dtlsContext, cipherContext),
        throwsStateError,
      );
    });

    test('computeVerifyData for client', () {
      final dtlsContext = DtlsContext();
      dtlsContext.masterSecret = Uint8List.fromList(List.generate(48, (i) => i));

      // Add some handshake messages
      dtlsContext.addHandshakeMessage(Uint8List.fromList([1, 2, 3, 4]));
      dtlsContext.addHandshakeMessage(Uint8List.fromList([5, 6, 7, 8]));

      final verifyData = KeyDerivation.computeVerifyData(dtlsContext, true);

      expect(verifyData.length, 12); // verify_data is 12 bytes
    });

    test('computeVerifyData for server', () {
      final dtlsContext = DtlsContext();
      dtlsContext.masterSecret = Uint8List.fromList(List.generate(48, (i) => i));

      dtlsContext.addHandshakeMessage(Uint8List.fromList([1, 2, 3, 4]));
      dtlsContext.addHandshakeMessage(Uint8List.fromList([5, 6, 7, 8]));

      final verifyData = KeyDerivation.computeVerifyData(dtlsContext, false);

      expect(verifyData.length, 12);
    });

    test('computeVerifyData throws when master secret is missing', () {
      final dtlsContext = DtlsContext();
      dtlsContext.addHandshakeMessage(Uint8List.fromList([1, 2, 3, 4]));

      expect(
        () => KeyDerivation.computeVerifyData(dtlsContext, true),
        throwsStateError,
      );
    });

    test('verifyFinishedMessage with matching data', () {
      final dtlsContext = DtlsContext();
      dtlsContext.masterSecret = Uint8List.fromList(List.generate(48, (i) => i));

      dtlsContext.addHandshakeMessage(Uint8List.fromList([1, 2, 3, 4]));
      dtlsContext.addHandshakeMessage(Uint8List.fromList([5, 6, 7, 8]));

      // Compute expected verify data
      final expectedVerifyData = KeyDerivation.computeVerifyData(dtlsContext, true);

      // Verify it matches
      final isValid = KeyDerivation.verifyFinishedMessage(
        dtlsContext,
        expectedVerifyData,
        true,
      );

      expect(isValid, true);
    });

    test('verifyFinishedMessage with non-matching data', () {
      final dtlsContext = DtlsContext();
      dtlsContext.masterSecret = Uint8List.fromList(List.generate(48, (i) => i));

      dtlsContext.addHandshakeMessage(Uint8List.fromList([1, 2, 3, 4]));
      dtlsContext.addHandshakeMessage(Uint8List.fromList([5, 6, 7, 8]));

      // Use wrong verify data
      final wrongVerifyData = Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);

      final isValid = KeyDerivation.verifyFinishedMessage(
        dtlsContext,
        wrongVerifyData,
        true,
      );

      expect(isValid, false);
    });

    test('verifyFinishedMessage with wrong length', () {
      final dtlsContext = DtlsContext();
      dtlsContext.masterSecret = Uint8List.fromList(List.generate(48, (i) => i));

      dtlsContext.addHandshakeMessage(Uint8List.fromList([1, 2, 3, 4]));

      // Wrong length
      final wrongLengthData = Uint8List.fromList([0, 0, 0, 0]);

      final isValid = KeyDerivation.verifyFinishedMessage(
        dtlsContext,
        wrongLengthData,
        true,
      );

      expect(isValid, false);
    });

    test('exportSrtpKeys generates correct length', () {
      final dtlsContext = DtlsContext();
      dtlsContext.masterSecret = Uint8List.fromList(List.generate(48, (i) => i));
      dtlsContext.localRandom = Uint8List.fromList(List.generate(32, (i) => i + 10));
      dtlsContext.remoteRandom = Uint8List.fromList(List.generate(32, (i) => i + 20));

      // SRTP typically needs: client_key (16) + server_key (16) + client_salt (14) + server_salt (14) = 60 bytes
      final srtpKeys = KeyDerivation.exportSrtpKeys(dtlsContext, 60, true);

      expect(srtpKeys.length, 60);
    });

    test('exportSrtpKeys throws when master secret is missing', () {
      final dtlsContext = DtlsContext();
      dtlsContext.localRandom = Uint8List(32);
      dtlsContext.remoteRandom = Uint8List(32);

      expect(
        () => KeyDerivation.exportSrtpKeys(dtlsContext, 60, true),
        throwsStateError,
      );
    });
  });
}
