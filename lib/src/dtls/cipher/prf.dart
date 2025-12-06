import 'dart:typed_data';
import 'package:webrtc_dart/src/common/crypto.dart';

/// TLS Pseudo-Random Function (PRF)
/// Based on RFC 5246 Section 5

/// P_hash function from TLS PRF
/// Expands a secret and seed into arbitrary-length output
Uint8List prfPHash(
  Uint8List secret,
  Uint8List seed,
  int requestedLength, {
  String algorithm = 'sha256',
}) {
  final bufs = <Uint8List>[];
  var totalLength = 0;
  var ai = seed; // A(0) = seed

  while (totalLength < requestedLength) {
    // A(i) = HMAC(secret, A(i-1))
    ai = hmac(algorithm, secret, ai);

    // P_hash(secret, seed) = HMAC(secret, A(1) + seed) +
    //                         HMAC(secret, A(2) + seed) +
    //                         HMAC(secret, A(3) + seed) + ...
    final combined = Uint8List(ai.length + seed.length);
    combined.setRange(0, ai.length, ai);
    combined.setRange(ai.length, combined.length, seed);

    final output = hmac(algorithm, secret, combined);
    bufs.add(output);
    totalLength += output.length;
  }

  // Concatenate and truncate to exact length
  final result = Uint8List(requestedLength);
  var offset = 0;
  for (final buf in bufs) {
    final remaining = requestedLength - offset;
    final copyLen = remaining < buf.length ? remaining : buf.length;
    result.setRange(offset, offset + copyLen, buf);
    offset += copyLen;
    if (offset >= requestedLength) break;
  }

  return result;
}

/// Generate master secret from pre-master secret
/// RFC 5246 Section 8.1
Uint8List prfMasterSecret(
  Uint8List preMasterSecret,
  Uint8List clientRandom,
  Uint8List serverRandom,
) {
  final label = Uint8List.fromList('master secret'.codeUnits);
  final seed =
      Uint8List(label.length + clientRandom.length + serverRandom.length);
  seed.setRange(0, label.length, label);
  seed.setRange(label.length, label.length + clientRandom.length, clientRandom);
  seed.setRange(
    label.length + clientRandom.length,
    seed.length,
    serverRandom,
  );

  return prfPHash(preMasterSecret, seed, 48);
}

/// Generate extended master secret from pre-master secret
/// RFC 7627
Uint8List prfExtendedMasterSecret(
  Uint8List preMasterSecret,
  Uint8List handshakes,
) {
  final sessionHash = hash('sha256', handshakes);
  final label = Uint8List.fromList('extended master secret'.codeUnits);
  final seed = Uint8List(label.length + sessionHash.length);
  seed.setRange(0, label.length, label);
  seed.setRange(label.length, seed.length, sessionHash);

  return prfPHash(preMasterSecret, seed, 48);
}

/// Export keying material for SRTP
/// RFC 5705
Uint8List exportKeyingMaterial(
  String label,
  int length,
  Uint8List masterSecret,
  Uint8List localRandom,
  Uint8List remoteRandom,
  bool isClient,
) {
  final clientRandom = isClient ? localRandom : remoteRandom;
  final serverRandom = isClient ? remoteRandom : localRandom;

  final labelBytes = Uint8List.fromList(label.codeUnits);
  final seed = Uint8List(
    labelBytes.length + clientRandom.length + serverRandom.length,
  );
  seed.setRange(0, labelBytes.length, labelBytes);
  seed.setRange(
    labelBytes.length,
    labelBytes.length + clientRandom.length,
    clientRandom,
  );
  seed.setRange(
    labelBytes.length + clientRandom.length,
    seed.length,
    serverRandom,
  );

  return prfPHash(masterSecret, seed, length);
}

/// Generate verify data for Finished message
/// RFC 5246 Section 7.4.9
Uint8List prfVerifyData(
  Uint8List masterSecret,
  Uint8List handshakes,
  String label, {
  int size = 12,
}) {
  final handshakeHash = hash('sha256', handshakes);
  final labelBytes = Uint8List.fromList(label.codeUnits);
  final seed = Uint8List(labelBytes.length + handshakeHash.length);
  seed.setRange(0, labelBytes.length, labelBytes);
  seed.setRange(labelBytes.length, seed.length, handshakeHash);

  return prfPHash(masterSecret, seed, size);
}

/// Generate client verify data for Finished message
Uint8List prfVerifyDataClient(Uint8List masterSecret, Uint8List handshakes) {
  return prfVerifyData(masterSecret, handshakes, 'client finished');
}

/// Generate server verify data for Finished message
Uint8List prfVerifyDataServer(Uint8List masterSecret, Uint8List handshakes) {
  return prfVerifyData(masterSecret, handshakes, 'server finished');
}

/// Encryption keys for cipher suite
class EncryptionKeys {
  final Uint8List clientWriteKey;
  final Uint8List serverWriteKey;
  final Uint8List clientNonce;
  final Uint8List serverNonce;

  const EncryptionKeys({
    required this.clientWriteKey,
    required this.serverWriteKey,
    required this.clientNonce,
    required this.serverNonce,
  });
}

/// Generate encryption keys from master secret
/// RFC 5246 Section 6.3
EncryptionKeys prfEncryptionKeys(
  Uint8List masterSecret,
  Uint8List clientRandom,
  Uint8List serverRandom,
  int prfKeyLen,
  int prfIvLen,
  int prfNonceLen, {
  String algorithm = 'sha256',
}) {
  final size = prfKeyLen * 2 + prfIvLen * 2;
  final label = Uint8List.fromList('key expansion'.codeUnits);
  final seed = Uint8List(
    label.length + serverRandom.length + clientRandom.length,
  );
  seed.setRange(0, label.length, label);
  seed.setRange(label.length, label.length + serverRandom.length, serverRandom);
  seed.setRange(
    label.length + serverRandom.length,
    seed.length,
    clientRandom,
  );

  final keyBlock = prfPHash(masterSecret, seed, size, algorithm: algorithm);

  // Extract keys from key block
  var offset = 0;

  final clientWriteKey = Uint8List(prfKeyLen);
  clientWriteKey.setRange(0, prfKeyLen, keyBlock, offset);
  offset += prfKeyLen;

  final serverWriteKey = Uint8List(prfKeyLen);
  serverWriteKey.setRange(0, prfKeyLen, keyBlock, offset);
  offset += prfKeyLen;

  final clientNonceImplicit = Uint8List(prfIvLen);
  clientNonceImplicit.setRange(0, prfIvLen, keyBlock, offset);
  offset += prfIvLen;

  final serverNonceImplicit = Uint8List(prfIvLen);
  serverNonceImplicit.setRange(0, prfIvLen, keyBlock, offset);

  // Return only the implicit nonce part (prfIvLen bytes)
  // The explicit nonce (epoch + sequence number) will be added by the cipher suite
  return EncryptionKeys(
    clientWriteKey: clientWriteKey,
    serverWriteKey: serverWriteKey,
    clientNonce: clientNonceImplicit,
    serverNonce: serverNonceImplicit,
  );
}
