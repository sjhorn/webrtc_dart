import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

/// Generate cryptographically secure random bytes
Uint8List randomBytes(int length) {
  final random = math.Random.secure();
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return bytes;
}

/// Calculate HMAC using provided hash algorithm
Uint8List hmac(String algorithm, Uint8List secret, Uint8List data) {
  late crypto.Hash hashAlgorithm;

  switch (algorithm) {
    case 'sha1':
      hashAlgorithm = crypto.sha1;
      break;
    case 'sha256':
      hashAlgorithm = crypto.sha256;
      break;
    case 'sha384':
      hashAlgorithm = crypto.sha384;
      break;
    case 'sha512':
      hashAlgorithm = crypto.sha512;
      break;
    case 'md5':
      hashAlgorithm = crypto.md5;
      break;
    default:
      throw ArgumentError('Unsupported hash algorithm: $algorithm');
  }

  final hmacAlgorithm = crypto.Hmac(hashAlgorithm, secret);
  final digest = hmacAlgorithm.convert(data);
  return Uint8List.fromList(digest.bytes);
}

/// A data expansion function for PRF (Pseudo-Random Function)
/// Used in TLS/DTLS key derivation
Uint8List pHash(
  int bytes,
  String algorithm,
  Uint8List secret,
  Uint8List seed,
) {
  final totalLength = bytes;
  final bufs = <Uint8List>[];
  var ai = seed; // A(0) = seed

  var remainingBytes = bytes;
  while (remainingBytes > 0) {
    ai = hmac(algorithm, secret, ai); // A(i) = HMAC(secret, A(i-1))

    // Concatenate A(i) and seed
    final combined = Uint8List(ai.length + seed.length);
    combined.setAll(0, ai);
    combined.setAll(ai.length, seed);

    final output = hmac(algorithm, secret, combined);
    bufs.add(output);
    remainingBytes -= output.length;
  }

  // Concatenate all outputs and trim to exact length
  final result = Uint8List(totalLength);
  var offset = 0;
  for (final buf in bufs) {
    final copyLength = math.min(buf.length, totalLength - offset);
    result.setRange(offset, offset + copyLength, buf);
    offset += copyLength;
  }

  return result;
}

/// AES-GCM encryption (supports 128-bit and 256-bit keys)
Future<Uint8List> aesGcmEncrypt({
  required Uint8List key,
  required Uint8List nonce,
  required Uint8List plaintext,
  required Uint8List additionalData,
}) async {
  // Select algorithm based on key length
  final algorithm =
      key.length == 16 ? AesGcm.with128bits() : AesGcm.with256bits();

  final secretKey = SecretKey(key);
  final secretBox = await algorithm.encrypt(
    plaintext,
    secretKey: secretKey,
    nonce: nonce,
    aad: additionalData,
  );

  // Concatenate ciphertext and MAC
  final result =
      Uint8List(secretBox.cipherText.length + secretBox.mac.bytes.length);
  result.setAll(0, secretBox.cipherText);
  result.setAll(secretBox.cipherText.length, secretBox.mac.bytes);

  return result;
}

/// AES-GCM decryption
Future<Uint8List> aesGcmDecrypt({
  required Uint8List key,
  required Uint8List nonce,
  required Uint8List ciphertext,
  required Uint8List additionalData,
  int macLength = 16,
}) async {
  if (ciphertext.length < macLength) {
    throw ArgumentError('Ciphertext too short');
  }

  // Select algorithm based on key length
  final algorithm =
      key.length == 16 ? AesGcm.with128bits() : AesGcm.with256bits();

  // Split ciphertext and MAC
  final actualCiphertext = ciphertext.sublist(0, ciphertext.length - macLength);
  final mac = ciphertext.sublist(ciphertext.length - macLength);

  final secretKey = SecretKey(key);
  final secretBox = SecretBox(
    actualCiphertext,
    nonce: nonce,
    mac: Mac(mac),
  );

  final plaintext = await algorithm.decrypt(
    secretBox,
    secretKey: secretKey,
    aad: additionalData,
  );

  return Uint8List.fromList(plaintext);
}

/// AES-128-CBC encryption
Future<Uint8List> aesCbcEncrypt({
  required Uint8List key,
  required Uint8List iv,
  required Uint8List plaintext,
}) async {
  final algorithm = AesCbc.with128bits(macAlgorithm: MacAlgorithm.empty);

  final secretKey = SecretKey(key);
  final secretBox = await algorithm.encrypt(
    plaintext,
    secretKey: secretKey,
    nonce: iv,
  );

  return Uint8List.fromList(secretBox.cipherText);
}

/// AES-128-CBC decryption
Future<Uint8List> aesCbcDecrypt({
  required Uint8List key,
  required Uint8List iv,
  required Uint8List ciphertext,
}) async {
  final algorithm = AesCbc.with128bits(macAlgorithm: MacAlgorithm.empty);

  final secretKey = SecretKey(key);
  final secretBox = SecretBox(ciphertext, nonce: iv, mac: Mac.empty);

  final plaintext = await algorithm.decrypt(
    secretBox,
    secretKey: secretKey,
  );

  return Uint8List.fromList(plaintext);
}

/// Calculate hash digest
Uint8List hash(String algorithm, Uint8List data) {
  late crypto.Hash hashAlgorithm;

  switch (algorithm) {
    case 'sha1':
      hashAlgorithm = crypto.sha1;
      break;
    case 'sha256':
      hashAlgorithm = crypto.sha256;
      break;
    case 'sha384':
      hashAlgorithm = crypto.sha384;
      break;
    case 'sha512':
      hashAlgorithm = crypto.sha512;
      break;
    case 'md5':
      hashAlgorithm = crypto.md5;
      break;
    default:
      throw ArgumentError('Unsupported hash algorithm: $algorithm');
  }

  final digest = hashAlgorithm.convert(data);
  return Uint8List.fromList(digest.bytes);
}

/// Calculate MD5 hash
Uint8List md5Hash(Uint8List data) {
  return hash('md5', data);
}

/// ChaCha20-Poly1305 encryption (RFC 7905)
/// Key: 32 bytes, Nonce: 12 bytes, Tag: 16 bytes
Future<Uint8List> chacha20Poly1305Encrypt({
  required Uint8List key,
  required Uint8List nonce,
  required Uint8List plaintext,
  required Uint8List additionalData,
}) async {
  final algorithm = Chacha20.poly1305Aead();

  final secretKey = SecretKey(key);
  final secretBox = await algorithm.encrypt(
    plaintext,
    secretKey: secretKey,
    nonce: nonce,
    aad: additionalData,
  );

  // Concatenate ciphertext and MAC (same format as AES-GCM)
  final result =
      Uint8List(secretBox.cipherText.length + secretBox.mac.bytes.length);
  result.setAll(0, secretBox.cipherText);
  result.setAll(secretBox.cipherText.length, secretBox.mac.bytes);

  return result;
}

/// ChaCha20-Poly1305 decryption (RFC 7905)
Future<Uint8List> chacha20Poly1305Decrypt({
  required Uint8List key,
  required Uint8List nonce,
  required Uint8List ciphertext,
  required Uint8List additionalData,
  int macLength = 16,
}) async {
  if (ciphertext.length < macLength) {
    throw ArgumentError('Ciphertext too short');
  }

  final algorithm = Chacha20.poly1305Aead();

  // Split ciphertext and MAC
  final actualCiphertext = ciphertext.sublist(0, ciphertext.length - macLength);
  final mac = ciphertext.sublist(ciphertext.length - macLength);

  final secretKey = SecretKey(key);
  final secretBox = SecretBox(
    actualCiphertext,
    nonce: nonce,
    mac: Mac(mac),
  );

  final plaintext = await algorithm.decrypt(
    secretBox,
    secretKey: secretKey,
    aad: additionalData,
  );

  return Uint8List.fromList(plaintext);
}

/// AES-128-CTR encryption for WebM encryption
/// Key: 16 bytes, IV: 16 bytes
/// This is a simple stream cipher without authentication
Future<Uint8List> aesCtrEncrypt({
  required Uint8List key,
  required Uint8List iv,
  required Uint8List plaintext,
}) async {
  final algorithm = AesCtr.with128bits(macAlgorithm: MacAlgorithm.empty);

  final secretKey = SecretKey(key);
  final secretBox = await algorithm.encrypt(
    plaintext,
    secretKey: secretKey,
    nonce: iv,
  );

  return Uint8List.fromList(secretBox.cipherText);
}

/// AES-128-CTR decryption for WebM encryption
Future<Uint8List> aesCtrDecrypt({
  required Uint8List key,
  required Uint8List iv,
  required Uint8List ciphertext,
}) async {
  final algorithm = AesCtr.with128bits(macAlgorithm: MacAlgorithm.empty);

  final secretKey = SecretKey(key);
  final secretBox = SecretBox(ciphertext, nonce: iv, mac: Mac.empty);

  final plaintext = await algorithm.decrypt(
    secretBox,
    secretKey: secretKey,
  );

  return Uint8List.fromList(plaintext);
}
