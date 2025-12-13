import 'dart:math' as math;
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:webrtc_dart/src/common/logging.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:webrtc_dart/src/dtls/cipher/const.dart';

final _log = WebRtcLogging.dtlsEcdh;

/// ECDH key exchange for DTLS
/// Supports Curve25519 (X25519) and secp256r1 (P-256)
///
/// - X25519: Uses cryptography package (pure Dart, fast, recommended)
/// - P-256: Uses pointycastle package (pure Dart, required for WebRTC certificate compatibility)

/// Generate an ECDH keypair for the specified curve
Future<KeyPair> generateEcdhKeypair(NamedCurve curve) async {
  switch (curve) {
    case NamedCurve.x25519:
      final algorithm = X25519();
      return await algorithm.newKeyPair();

    case NamedCurve.secp256r1:
      // Use pointycastle for P-256 key generation
      return _generateP256KeyPair();
  }
}

/// Generate P-256 keypair using pointycastle
KeyPair _generateP256KeyPair() {
  final secureRandom = pc.FortunaRandom();

  // Seed the random number generator
  final seedSource = math.Random.secure();
  final seeds = List<int>.generate(32, (_) => seedSource.nextInt(256));
  secureRandom.seed(pc.KeyParameter(Uint8List.fromList(seeds)));

  // Generate key pair
  final keyGen = pc.KeyGenerator('EC');
  final params = pc.ECKeyGeneratorParameters(pc.ECCurve_secp256r1());
  keyGen.init(pc.ParametersWithRandom(params, secureRandom));

  final pair = keyGen.generateKeyPair();
  final privateKey = pair.privateKey as pc.ECPrivateKey;
  final publicKey = pair.publicKey as pc.ECPublicKey;

  // Extract private key bytes (32 bytes for P-256)
  final d = privateKey.d!;
  final privateBytes = _bigIntToBytes(d, 32);

  // Extract public key bytes (64 bytes: 32 bytes X + 32 bytes Y)
  final qx = publicKey.Q!.x!.toBigInteger()!;
  final qy = publicKey.Q!.y!.toBigInteger()!;
  final publicBytes = Uint8List(64);
  publicBytes.setRange(0, 32, _bigIntToBytes(qx, 32));
  publicBytes.setRange(32, 64, _bigIntToBytes(qy, 32));

  // Return as cryptography package KeyPair
  return SimpleKeyPairData(
    privateBytes,
    publicKey: SimplePublicKey(publicBytes.toList(), type: KeyPairType.p256),
    type: KeyPairType.p256,
  );
}

/// Convert BigInt to fixed-length byte array
Uint8List _bigIntToBytes(BigInt value, int length) {
  final bytes = Uint8List(length);
  var v = value;
  for (var i = length - 1; i >= 0; i--) {
    bytes[i] = (v & BigInt.from(0xff)).toInt();
    v = v >> 8;
  }
  return bytes;
}

/// Compute pre-master secret from ECDH key exchange
Future<Uint8List> computePreMasterSecret(
  KeyPair localKeyPair,
  Uint8List remotePublicKeyBytes,
  NamedCurve curve,
) async {
  _log.fine('computePreMasterSecret: curve=$curve');
  _log.fine(
      'remotePublicKey (${remotePublicKeyBytes.length} bytes): ${remotePublicKeyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

  // Extract and print local private key
  final localKeyPairData = await localKeyPair.extract();
  if (localKeyPairData is SimpleKeyPairData) {
    final privateBytes = Uint8List.fromList(localKeyPairData.bytes);
    _log.fine(
        'localPrivateKey (${privateBytes.length} bytes): ${privateBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
  }

  // Extract and print local public key
  final localPublicKey = await localKeyPair.extractPublicKey();
  if (localPublicKey is SimplePublicKey) {
    _log.fine(
        'localPublicKey (${localPublicKey.bytes.length} bytes): ${localPublicKey.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
  }

  final remotePublicKey = SimplePublicKey(
    remotePublicKeyBytes.toList(),
    type: _getKeyPairType(curve),
  );

  final sharedSecret = await _computeSharedSecret(
    localKeyPair,
    remotePublicKey,
    curve,
  );

  // Extract bytes from SecretKey
  final bytes = await sharedSecret.extractBytes();
  _log.fine(
      'sharedSecret (${bytes.length} bytes): ${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
  return Uint8List.fromList(bytes);
}

/// Get KeyPairType for the curve
KeyPairType _getKeyPairType(NamedCurve curve) {
  switch (curve) {
    case NamedCurve.x25519:
      return KeyPairType.x25519;
    case NamedCurve.secp256r1:
      return KeyPairType.p256;
  }
}

/// Compute shared secret using ECDH
Future<SecretKey> _computeSharedSecret(
  KeyPair localKeyPair,
  SimplePublicKey remotePublicKey,
  NamedCurve curve,
) async {
  switch (curve) {
    case NamedCurve.x25519:
      final algorithm = X25519();
      return await algorithm.sharedSecretKey(
        keyPair: localKeyPair,
        remotePublicKey: remotePublicKey,
      );

    case NamedCurve.secp256r1:
      // Use pointycastle for P-256 key agreement
      return _computeP256SharedSecret(localKeyPair, remotePublicKey);
  }
}

/// Compute P-256 shared secret using pointycastle
Future<SecretKey> _computeP256SharedSecret(
  KeyPair localKeyPair,
  SimplePublicKey remotePublicKey,
) async {
  // Extract local private key
  final privateKeyData = await localKeyPair.extract();
  // For SimpleKeyPairData, the bytes are the private key
  final privateBytes = (privateKeyData as SimpleKeyPairData).bytes;

  // Convert to BigInt
  final d = _bytesToBigInt(Uint8List.fromList(privateBytes));

  // Reconstruct pointycastle private key
  final domainParams = pc.ECDomainParameters('secp256r1');
  final pcPrivateKey = pc.ECPrivateKey(d, domainParams);

  // Parse remote public key (64 bytes: X + Y coordinates)
  final remoteBytes = Uint8List.fromList(remotePublicKey.bytes);
  final qx = _bytesToBigInt(remoteBytes.sublist(0, 32));
  final qy = _bytesToBigInt(remoteBytes.sublist(32, 64));

  // Reconstruct pointycastle public key
  final q = domainParams.curve.createPoint(qx, qy);
  final pcPublicKey = pc.ECPublicKey(q, domainParams);

  // Compute shared secret using ECDH
  final agreement = pc.ECDHBasicAgreement();
  agreement.init(pcPrivateKey);
  final sharedSecret = agreement.calculateAgreement(pcPublicKey);

  // Convert to 32-byte array
  final sharedBytes = _bigIntToBytes(sharedSecret, 32);

  return SecretKey(sharedBytes.toList());
}

/// Convert byte array to BigInt
BigInt _bytesToBigInt(Uint8List bytes) {
  var result = BigInt.zero;
  for (var i = 0; i < bytes.length; i++) {
    result = (result << 8) | BigInt.from(bytes[i]);
  }
  return result;
}

/// Serialize public key for transmission
/// Returns the public key bytes in the appropriate format for the curve
Future<Uint8List> serializePublicKey(
  KeyPair keyPair,
  NamedCurve curve,
) async {
  final publicKey = await keyPair.extractPublicKey();

  // Extract bytes from PublicKey - handle both SimplePublicKey and other types
  final List<int> bytes;
  if (publicKey is SimplePublicKey) {
    bytes = publicKey.bytes;
  } else {
    // For other public key types, try to convert
    throw UnsupportedError(
        'Unsupported public key type: ${publicKey.runtimeType}');
  }

  switch (curve) {
    case NamedCurve.x25519:
      // X25519 public keys are 32 bytes
      return Uint8List.fromList(bytes);

    case NamedCurve.secp256r1:
      // P-256 public keys need to be in uncompressed format (0x04 + X + Y)
      // The cryptography package returns the raw bytes
      if (bytes.length == 64) {
        // Raw X and Y coordinates - add uncompressed point prefix
        final result = Uint8List(65);
        result[0] = 0x04; // Uncompressed point format
        result.setRange(1, 65, bytes);
        return result;
      } else if (bytes.length == 65 && bytes[0] == 0x04) {
        // Already in uncompressed format
        return Uint8List.fromList(bytes);
      } else {
        throw ArgumentError(
          'Unexpected P-256 public key format: ${bytes.length} bytes',
        );
      }
  }
}

/// Parse public key from received bytes
/// Returns a SimplePublicKey for the specified curve
SimplePublicKey parsePublicKey(Uint8List bytes, NamedCurve curve) {
  switch (curve) {
    case NamedCurve.x25519:
      // X25519 public keys are 32 bytes
      if (bytes.length != 32) {
        throw ArgumentError(
          'Invalid X25519 public key length: expected 32, got ${bytes.length}',
        );
      }
      return SimplePublicKey(bytes.toList(), type: KeyPairType.x25519);

    case NamedCurve.secp256r1:
      // P-256 public keys should be in uncompressed format (0x04 + X + Y)
      if (bytes.length == 65 && bytes[0] == 0x04) {
        // Remove the 0x04 prefix for the cryptography package
        final keyBytes = bytes.sublist(1);
        return SimplePublicKey(keyBytes.toList(), type: KeyPairType.p256);
      } else if (bytes.length == 64) {
        // Already without prefix
        return SimplePublicKey(bytes.toList(), type: KeyPairType.p256);
      } else {
        throw ArgumentError(
          'Invalid P-256 public key format: ${bytes.length} bytes, '
          'first byte: 0x${bytes.isNotEmpty ? bytes[0].toRadixString(16) : "empty"}',
        );
      }
  }
}
