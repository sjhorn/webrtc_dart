import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/cipher/prf.dart';
import 'package:webrtc_dart/src/dtls/cipher/ecdh.dart';
import 'package:webrtc_dart/src/dtls/cipher/suites/aead.dart';
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/record/const.dart';
import 'package:webrtc_dart/src/dtls/record/header.dart';

void main() {
  group('PRF (Pseudo-Random Function)', () {
    test('prfPHash generates correct length output', () {
      final secret = Uint8List.fromList([1, 2, 3, 4]);
      final seed = Uint8List.fromList([5, 6, 7, 8]);

      final output = prfPHash(secret, seed, 32);
      expect(output.length, 32);
    });

    test('prfPHash is deterministic', () {
      final secret = Uint8List.fromList([1, 2, 3, 4]);
      final seed = Uint8List.fromList([5, 6, 7, 8]);

      final output1 = prfPHash(secret, seed, 48);
      final output2 = prfPHash(secret, seed, 48);

      expect(output1, equals(output2));
    });

    test('prfPHash with different secrets produces different output', () {
      final secret1 = Uint8List.fromList([1, 2, 3, 4]);
      final secret2 = Uint8List.fromList([5, 6, 7, 8]);
      final seed = Uint8List.fromList([9, 10, 11, 12]);

      final output1 = prfPHash(secret1, seed, 32);
      final output2 = prfPHash(secret2, seed, 32);

      expect(output1, isNot(equals(output2)));
    });

    test('prfMasterSecret generates 48 bytes', () {
      final preMasterSecret = Uint8List(48);
      final clientRandom = Uint8List(32);
      final serverRandom = Uint8List(32);

      for (var i = 0; i < preMasterSecret.length; i++) {
        preMasterSecret[i] = i & 0xFF;
      }
      for (var i = 0; i < clientRandom.length; i++) {
        clientRandom[i] = (i + 10) & 0xFF;
      }
      for (var i = 0; i < serverRandom.length; i++) {
        serverRandom[i] = (i + 20) & 0xFF;
      }

      final masterSecret = prfMasterSecret(
        preMasterSecret,
        clientRandom,
        serverRandom,
      );

      expect(masterSecret.length, 48);
    });

    test('prfExtendedMasterSecret generates 48 bytes', () {
      final preMasterSecret = Uint8List(48);
      final handshakes = Uint8List(100);

      for (var i = 0; i < preMasterSecret.length; i++) {
        preMasterSecret[i] = i & 0xFF;
      }
      for (var i = 0; i < handshakes.length; i++) {
        handshakes[i] = (i * 2) & 0xFF;
      }

      final masterSecret = prfExtendedMasterSecret(
        preMasterSecret,
        handshakes,
      );

      expect(masterSecret.length, 48);
    });

    test('exportKeyingMaterial generates correct length', () {
      final masterSecret = Uint8List(48);
      final clientRandom = Uint8List(32);
      final serverRandom = Uint8List(32);

      for (var i = 0; i < masterSecret.length; i++) {
        masterSecret[i] = i & 0xFF;
      }

      final exported = exportKeyingMaterial(
        'EXTRACTOR-dtls_srtp',
        60,
        masterSecret,
        clientRandom,
        serverRandom,
        true,
      );

      expect(exported.length, 60);
    });

    test('exportKeyingMaterial differs for client and server', () {
      final masterSecret = Uint8List(48);
      final clientRandom = Uint8List(32);
      final serverRandom = Uint8List(32);

      // Make randoms different so client/server exports differ
      for (var i = 0; i < 32; i++) {
        clientRandom[i] = i & 0xFF;
        serverRandom[i] = (i + 100) & 0xFF;
      }

      final clientExport = exportKeyingMaterial(
        'test',
        32,
        masterSecret,
        clientRandom,
        serverRandom,
        true,
      );

      final serverExport = exportKeyingMaterial(
        'test',
        32,
        masterSecret,
        clientRandom,
        serverRandom,
        false,
      );

      expect(clientExport, isNot(equals(serverExport)));
    });

    test('prfVerifyDataClient generates 12 bytes', () {
      final masterSecret = Uint8List(48);
      final handshakes = Uint8List(200);

      for (var i = 0; i < masterSecret.length; i++) {
        masterSecret[i] = i & 0xFF;
      }

      final verifyData = prfVerifyDataClient(masterSecret, handshakes);
      expect(verifyData.length, 12);
    });

    test('prfVerifyDataServer generates 12 bytes', () {
      final masterSecret = Uint8List(48);
      final handshakes = Uint8List(200);

      final verifyData = prfVerifyDataServer(masterSecret, handshakes);
      expect(verifyData.length, 12);
    });

    test('client and server verify data differ', () {
      final masterSecret = Uint8List(48);
      final handshakes = Uint8List(200);

      final clientData = prfVerifyDataClient(masterSecret, handshakes);
      final serverData = prfVerifyDataServer(masterSecret, handshakes);

      expect(clientData, isNot(equals(serverData)));
    });

    test('prfEncryptionKeys generates correct key material', () {
      final masterSecret = Uint8List(48);
      final clientRandom = Uint8List(32);
      final serverRandom = Uint8List(32);

      for (var i = 0; i < masterSecret.length; i++) {
        masterSecret[i] = i & 0xFF;
      }

      final keys = prfEncryptionKeys(
        masterSecret,
        clientRandom,
        serverRandom,
        16, // AES-128 key length
        4, // GCM implicit nonce length
        12, // GCM full nonce length
      );

      expect(keys.clientWriteKey.length, 16);
      expect(keys.serverWriteKey.length, 16);
      // Nonces should be only the implicit part (4 bytes for GCM)
      expect(keys.clientNonce.length, 4);
      expect(keys.serverNonce.length, 4);
    });

    test('encryption keys are unique', () {
      final masterSecret = Uint8List(48);
      final clientRandom = Uint8List(32);
      final serverRandom = Uint8List(32);

      final keys = prfEncryptionKeys(
        masterSecret,
        clientRandom,
        serverRandom,
        16,
        4,
        12,
      );

      expect(keys.clientWriteKey, isNot(equals(keys.serverWriteKey)));
      expect(keys.clientNonce, isNot(equals(keys.serverNonce)));
    });
  });

  group('ECDH Key Exchange', () {
    test('generates X25519 keypair', () async {
      final keyPair = await generateEcdhKeypair(NamedCurve.x25519);
      final publicKey = await serializePublicKey(keyPair, NamedCurve.x25519);

      expect(publicKey.length, 32); // X25519 public keys are 32 bytes
    });

    test('generates P-256 keypair', () async {
      final keyPair = await generateEcdhKeypair(NamedCurve.secp256r1);
      final publicKey = await serializePublicKey(keyPair, NamedCurve.secp256r1);

      // P-256 public key should be 65 bytes (0x04 + 32 bytes X + 32 bytes Y)
      expect(publicKey.length, 65);
      expect(publicKey[0], 0x04); // Uncompressed point format
    });

    test('X25519 key exchange produces shared secret', () async {
      // Generate Alice's keypair
      final aliceKeyPair = await generateEcdhKeypair(NamedCurve.x25519);
      final alicePublicKey = await serializePublicKey(
        aliceKeyPair,
        NamedCurve.x25519,
      );

      // Generate Bob's keypair
      final bobKeyPair = await generateEcdhKeypair(NamedCurve.x25519);
      final bobPublicKey = await serializePublicKey(
        bobKeyPair,
        NamedCurve.x25519,
      );

      // Compute shared secrets
      final aliceShared = await computePreMasterSecret(
        aliceKeyPair,
        bobPublicKey,
        NamedCurve.x25519,
      );

      final bobShared = await computePreMasterSecret(
        bobKeyPair,
        alicePublicKey,
        NamedCurve.x25519,
      );

      // Both should compute the same shared secret
      expect(aliceShared, equals(bobShared));
      expect(aliceShared.length, 32);
    });

    test('P-256 key exchange produces shared secret', () async {
      // Generate Alice's keypair
      final aliceKeyPair = await generateEcdhKeypair(NamedCurve.secp256r1);
      final alicePublicKey = await serializePublicKey(
        aliceKeyPair,
        NamedCurve.secp256r1,
      );

      // Generate Bob's keypair
      final bobKeyPair = await generateEcdhKeypair(NamedCurve.secp256r1);
      final bobPublicKey = await serializePublicKey(
        bobKeyPair,
        NamedCurve.secp256r1,
      );

      // Remove 0x04 prefix from public keys for key agreement
      final alicePublicKeyBytes = alicePublicKey.sublist(1);
      final bobPublicKeyBytes = bobPublicKey.sublist(1);

      // Compute shared secrets
      final aliceShared = await computePreMasterSecret(
        aliceKeyPair,
        bobPublicKeyBytes,
        NamedCurve.secp256r1,
      );

      final bobShared = await computePreMasterSecret(
        bobKeyPair,
        alicePublicKeyBytes,
        NamedCurve.secp256r1,
      );

      // Both should compute the same shared secret
      expect(aliceShared, equals(bobShared));
      expect(aliceShared.length, 32);
    });

    test('parsePublicKey handles X25519 keys', () {
      final publicKeyBytes = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        publicKeyBytes[i] = i & 0xFF;
      }

      final publicKey = parsePublicKey(publicKeyBytes, NamedCurve.x25519);
      expect(publicKey.bytes.length, 32);
    });

    test('parsePublicKey handles P-256 uncompressed keys', () {
      final publicKeyBytes = Uint8List(65);
      publicKeyBytes[0] = 0x04; // Uncompressed format
      for (var i = 1; i < 65; i++) {
        publicKeyBytes[i] = i & 0xFF;
      }

      final publicKey = parsePublicKey(publicKeyBytes, NamedCurve.secp256r1);
      expect(publicKey.bytes.length, 64); // Without 0x04 prefix
    });

    test('parsePublicKey throws on invalid X25519 length', () {
      final publicKeyBytes = Uint8List(30); // Wrong length

      expect(
        () => parsePublicKey(publicKeyBytes, NamedCurve.x25519),
        throwsArgumentError,
      );
    });

    test('parsePublicKey throws on invalid P-256 format', () {
      final publicKeyBytes = Uint8List(64); // Missing 0x04 prefix or wrong size

      // This should work (64 bytes without prefix)
      expect(
        () => parsePublicKey(publicKeyBytes, NamedCurve.secp256r1),
        returnsNormally,
      );

      // Wrong length should fail
      final wrongLength = Uint8List(60);
      expect(
        () => parsePublicKey(wrongLength, NamedCurve.secp256r1),
        throwsArgumentError,
      );
    });
  });

  group('AEAD Cipher Suite', () {
    test('encrypts and decrypts data correctly', () async {
      // Generate keys
      final masterSecret = Uint8List(48);
      final clientRandom = Uint8List(32);
      final serverRandom = Uint8List(32);

      for (var i = 0; i < masterSecret.length; i++) {
        masterSecret[i] = i & 0xFF;
      }

      final keys = prfEncryptionKeys(
        masterSecret,
        clientRandom,
        serverRandom,
        16,
        4,
        12,
      );

      // Create cipher suite for client sending (uses clientWriteKey)
      final clientSendSuite = AEADCipherSuite.fromKeys(
        CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256,
        keys,
        true, // isClient
      );

      // Create cipher suite for server receiving client data (uses clientWriteKey)
      final serverReceiveSuite = AEADCipherSuite(
        suite: CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256,
        writeKey: keys
            .clientWriteKey, // Server uses client's write key to decrypt client's messages
        writeNonce: keys.clientNonce,
      );

      // Create a record header
      final header = RecordHeader(
        contentType: ContentType.applicationData.value,
        protocolVersion: ProtocolVersion.dtls12,
        epoch: 1,
        sequenceNumber: 100,
        contentLen: 0, // Will be updated
      );

      // Original plaintext
      final plaintext = Uint8List.fromList('Hello, DTLS!'.codeUnits);

      // Client encrypts
      final encrypted = await clientSendSuite.encrypt(plaintext, header);

      // Encrypted should be longer (explicit nonce + ciphertext + tag)
      expect(encrypted.length, greaterThan(plaintext.length));

      // Update header with encrypted length
      final decryptHeader = RecordHeader(
        contentType: header.contentType,
        protocolVersion: header.protocolVersion,
        epoch: header.epoch,
        sequenceNumber: header.sequenceNumber,
        contentLen:
            encrypted.length - 8 - 16, // Subtract explicit nonce and tag
      );

      // Server decrypts
      final decrypted =
          await serverReceiveSuite.decrypt(encrypted, decryptHeader);

      // Should match original
      expect(decrypted, equals(plaintext));
    });

    test('encrypted data includes explicit nonce', () async {
      final keys = prfEncryptionKeys(
        Uint8List(48),
        Uint8List(32),
        Uint8List(32),
        16,
        4,
        12,
      );

      final suite = AEADCipherSuite.fromKeys(
        CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256,
        keys,
        true,
      );

      final header = RecordHeader(
        contentType: ContentType.handshake.value,
        protocolVersion: ProtocolVersion.dtls12,
        epoch: 0,
        sequenceNumber: 5,
        contentLen: 0,
      );

      final plaintext = Uint8List(50);
      final encrypted = await suite.encrypt(plaintext, header);

      // First 8 bytes should be explicit nonce (sequence number)
      expect(encrypted.length, greaterThanOrEqualTo(8));
    });

    test('decrypt throws on too short data', () async {
      final keys = prfEncryptionKeys(
        Uint8List(48),
        Uint8List(32),
        Uint8List(32),
        16,
        4,
        12,
      );

      final suite = AEADCipherSuite.fromKeys(
        CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256,
        keys,
        true,
      );

      final header = RecordHeader(
        contentType: ContentType.applicationData.value,
        protocolVersion: ProtocolVersion.dtls12,
        epoch: 1,
        sequenceNumber: 100,
        contentLen: 0,
      );

      // Too short data (less than 8 + 16 bytes)
      final tooShort = Uint8List(20);

      expect(
        () async => await suite.decrypt(tooShort, header),
        throwsArgumentError,
      );
    });

    test('verifyData generates correct length for client', () async {
      final keys = prfEncryptionKeys(
        Uint8List(48),
        Uint8List(32),
        Uint8List(32),
        16,
        4,
        12,
      );

      final suite = AEADCipherSuite.fromKeys(
        CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256,
        keys,
        true,
      );

      final masterSecret = Uint8List(48);
      final handshakes = Uint8List(200);

      final verifyData = await suite.verifyData(
        masterSecret,
        handshakes,
        true, // isClient
      );

      expect(verifyData.length, 12);
    });

    test('verifyData generates correct length for server', () async {
      final keys = prfEncryptionKeys(
        Uint8List(48),
        Uint8List(32),
        Uint8List(32),
        16,
        4,
        12,
      );

      final suite = AEADCipherSuite.fromKeys(
        CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256,
        keys,
        false,
      );

      final masterSecret = Uint8List(48);
      final handshakes = Uint8List(200);

      final verifyData = await suite.verifyData(
        masterSecret,
        handshakes,
        false, // isServer
      );

      expect(verifyData.length, 12);
    });

    test('CipherSuiteLengths returns correct values for AES-128-GCM', () {
      final lengths = CipherSuiteLengths.forSuite(
        CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256,
      );

      expect(lengths.keyLen, 16); // AES-128
      expect(lengths.ivLen, 4); // GCM implicit nonce
      expect(lengths.nonceLen, 12); // GCM full nonce
    });

    test('different epochs produce different encrypted output', () async {
      final keys = prfEncryptionKeys(
        Uint8List(48),
        Uint8List(32),
        Uint8List(32),
        16,
        4,
        12,
      );

      final suite = AEADCipherSuite.fromKeys(
        CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256,
        keys,
        true,
      );

      final plaintext = Uint8List.fromList('test data'.codeUnits);

      final header1 = RecordHeader(
        contentType: ContentType.applicationData.value,
        protocolVersion: ProtocolVersion.dtls12,
        epoch: 0,
        sequenceNumber: 1,
        contentLen: 0,
      );

      final header2 = RecordHeader(
        contentType: ContentType.applicationData.value,
        protocolVersion: ProtocolVersion.dtls12,
        epoch: 1,
        sequenceNumber: 1,
        contentLen: 0,
      );

      final encrypted1 = await suite.encrypt(plaintext, header1);
      final encrypted2 = await suite.encrypt(plaintext, header2);

      // Different epochs should produce different ciphertext
      expect(encrypted1, isNot(equals(encrypted2)));
    });
  });
}
