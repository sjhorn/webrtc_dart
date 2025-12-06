import 'dart:typed_data';
import 'package:webrtc_dart/src/common/crypto.dart';
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/cipher/prf.dart';
import 'package:webrtc_dart/src/dtls/record/header.dart';

/// AEAD cipher suite for DTLS (AES-GCM)
/// RFC 5288 - AES Galois Counter Mode (GCM) Cipher Suites for TLS
class AEADCipherSuite {
  final CipherSuite suite;
  final Uint8List writeKey;
  final Uint8List writeNonce;
  final int nonceLength;
  final int tagLength;

  const AEADCipherSuite({
    required this.suite,
    required this.writeKey,
    required this.writeNonce,
    this.nonceLength = 12,
    this.tagLength = 16,
  });

  /// Create cipher suite from encryption keys
  factory AEADCipherSuite.fromKeys(
    CipherSuite suite,
    EncryptionKeys keys,
    bool isClient,
  ) {
    final writeKey = isClient ? keys.clientWriteKey : keys.serverWriteKey;
    final writeNonce = isClient ? keys.clientNonce : keys.serverNonce;

    return AEADCipherSuite(
      suite: suite,
      writeKey: writeKey,
      writeNonce: writeNonce,
    );
  }

  /// Encrypt a DTLS record using AES-GCM
  /// Returns encrypted data with authentication tag appended
  Future<Uint8List> encrypt(
    Uint8List plaintext,
    RecordHeader header,
  ) async {
    // Construct nonce: implicit part (4 bytes) + explicit part (8 bytes)
    final nonce = _constructNonce(header.epoch, header.sequenceNumber);

    // Construct additional authenticated data (AAD) - always uses plaintext length
    final aad = _constructAAD(header, plaintext.length);

    print('[AEAD] encrypt: epoch=${header.epoch} seq=${header.sequenceNumber}');
    print(
        '[AEAD] plaintext (${plaintext.length} bytes): ${plaintext.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    print(
        '[AEAD] writeKey: ${writeKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    print(
        '[AEAD] nonce: ${nonce.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    print(
        '[AEAD] aad: ${aad.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

    // Encrypt with AES-GCM
    final ciphertext = await aesGcmEncrypt(
      key: writeKey,
      nonce: nonce,
      plaintext: plaintext,
      additionalData: aad,
    );

    // Prepend explicit nonce (epoch + sequence number) to ciphertext
    // Format: explicit_nonce (8 bytes) + ciphertext + tag (16 bytes)
    final explicitNonce =
        _encodeExplicitNonce(header.epoch, header.sequenceNumber);
    final result = Uint8List(explicitNonce.length + ciphertext.length);
    result.setRange(0, explicitNonce.length, explicitNonce);
    result.setRange(explicitNonce.length, result.length, ciphertext);

    print(
        '[AEAD] result (${result.length} bytes): ${result.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

    return result;
  }

  /// Decrypt a DTLS record using AES-GCM
  /// Expects format: explicit_nonce (8 bytes) + ciphertext + tag (16 bytes)
  Future<Uint8List> decrypt(
    Uint8List encrypted,
    RecordHeader header,
  ) async {
    if (encrypted.length < 8 + tagLength) {
      throw ArgumentError(
        'Encrypted data too short: ${encrypted.length} bytes '
        '(min ${8 + tagLength})',
      );
    }

    // Extract explicit nonce (first 8 bytes)
    final explicitNonce = encrypted.sublist(0, 8);
    final ciphertext = encrypted.sublist(8);

    // Reconstruct full nonce: implicit part + explicit part
    final nonce = Uint8List(nonceLength);
    nonce.setRange(0, writeNonce.length, writeNonce);
    nonce.setRange(writeNonce.length, nonceLength, explicitNonce);

    // Construct additional authenticated data (AAD) - always uses plaintext length
    // (ciphertext.length - tagLength gives us the plaintext length)
    final plaintextLength = ciphertext.length - tagLength;
    final aad = _constructAAD(header, plaintextLength);

    // Decrypt with AES-GCM
    final plaintext = await aesGcmDecrypt(
      key: writeKey,
      nonce: nonce,
      ciphertext: ciphertext,
      additionalData: aad,
    );

    return plaintext;
  }

  /// Construct nonce from epoch and sequence number
  /// Format: implicit nonce (4 bytes) + epoch (2 bytes) + seq_num (6 bytes)
  Uint8List _constructNonce(int epoch, int sequenceNumber) {
    final nonce = Uint8List(nonceLength);

    // Copy implicit nonce (first 4 bytes from writeNonce)
    nonce.setRange(0, writeNonce.length, writeNonce);

    // Add explicit part: epoch (2 bytes) + sequence number (6 bytes)
    final buffer = ByteData.sublistView(nonce);
    buffer.setUint16(4, epoch);

    // Write 48-bit sequence number
    final seqHigh = (sequenceNumber >> 32) & 0xFFFF;
    final seqLow = sequenceNumber & 0xFFFFFFFF;
    buffer.setUint16(6, seqHigh);
    buffer.setUint32(8, seqLow);

    return nonce;
  }

  /// Encode explicit nonce for transmission
  /// Format: epoch (2 bytes) + sequence number (6 bytes) = 8 bytes
  /// This matches bytes 4-11 of the full 12-byte GCM nonce
  Uint8List _encodeExplicitNonce(int epoch, int sequenceNumber) {
    final result = Uint8List(8);
    final buffer = ByteData.sublistView(result);

    // Write epoch (2 bytes)
    buffer.setUint16(0, epoch);

    // Write 48-bit sequence number (6 bytes)
    final seqHigh = (sequenceNumber >> 32) & 0xFFFF;
    final seqLow = sequenceNumber & 0xFFFFFFFF;
    buffer.setUint16(2, seqHigh);
    buffer.setUint32(4, seqLow);

    return result;
  }

  /// Construct Additional Authenticated Data (AAD) for AEAD
  /// Format: epoch (2) + seq_num (6) + type (1) + version (2) + length (2) = 13 bytes
  /// The length field should ALWAYS be the plaintext length (RFC 5246 Section 6.2.3.3)
  Uint8List _constructAAD(RecordHeader header, int plaintextLength) {
    final result = Uint8List(13);
    final buffer = ByteData.sublistView(result);

    // Epoch (2 bytes)
    buffer.setUint16(0, header.epoch);

    // Sequence number (6 bytes)
    final seqHigh = (header.sequenceNumber >> 32) & 0xFFFF;
    final seqLow = header.sequenceNumber & 0xFFFFFFFF;
    buffer.setUint16(2, seqHigh);
    buffer.setUint32(4, seqLow);

    // Content type (1 byte)
    buffer.setUint8(8, header.contentType);

    // Protocol version (2 bytes)
    buffer.setUint8(9, header.protocolVersion.major);
    buffer.setUint8(10, header.protocolVersion.minor);

    // Payload length (2 bytes) - this is ALWAYS the plaintext length
    buffer.setUint16(11, plaintextLength);

    return result;
  }

  /// Compute verify data for Finished message
  Future<Uint8List> verifyData(
    Uint8List masterSecret,
    Uint8List handshakes,
    bool isClient,
  ) async {
    if (isClient) {
      return prfVerifyDataClient(masterSecret, handshakes);
    } else {
      return prfVerifyDataServer(masterSecret, handshakes);
    }
  }

  @override
  String toString() {
    return 'AEADCipherSuite(suite=$suite, keyLen=${writeKey.length}, '
        'nonceLen=$nonceLength, tagLen=$tagLength)';
  }
}

/// Get key lengths for a cipher suite
class CipherSuiteLengths {
  final int keyLen;
  final int ivLen;
  final int nonceLen;

  const CipherSuiteLengths({
    required this.keyLen,
    required this.ivLen,
    required this.nonceLen,
  });

  /// Get lengths for a specific cipher suite
  factory CipherSuiteLengths.forSuite(CipherSuite suite) {
    switch (suite) {
      case CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256:
      case CipherSuite.tlsEcdheRsaWithAes128GcmSha256:
        return const CipherSuiteLengths(
          keyLen: 16, // AES-128
          ivLen: 4, // GCM implicit nonce
          nonceLen: 12, // GCM full nonce
        );
    }
  }
}
