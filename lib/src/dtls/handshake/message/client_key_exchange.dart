import 'dart:typed_data';

/// ClientKeyExchange message for ECDHE
/// RFC 4492 Section 5.7
///
/// struct {
///   select (KeyExchangeAlgorithm) {
///     case ec_diffie_hellman:
///       ClientECDiffieHellmanPublic;
///   } exchange_keys;
/// } ClientKeyExchange;
///
/// struct {
///   opaque point <1..2^8-1>;
/// } ClientECDiffieHellmanPublic;
class ClientKeyExchange {
  final Uint8List publicKey;

  const ClientKeyExchange({required this.publicKey});

  /// Create from ECDH public key
  factory ClientKeyExchange.fromPublicKey(Uint8List publicKey) {
    return ClientKeyExchange(publicKey: publicKey);
  }

  /// Serialize to bytes
  Uint8List serialize() {
    final result = Uint8List(1 + publicKey.length);
    final buffer = ByteData.sublistView(result);

    // Public key length (1 byte)
    buffer.setUint8(0, publicKey.length);

    // Public key data
    result.setRange(1, 1 + publicKey.length, publicKey);

    return result;
  }

  /// Parse from bytes
  static ClientKeyExchange parse(Uint8List data) {
    if (data.isEmpty) {
      throw FormatException('ClientKeyExchange too short: ${data.length} bytes');
    }

    final buffer = ByteData.sublistView(data);

    // Public key length (1 byte)
    final publicKeyLength = buffer.getUint8(0);

    if (data.length < 1 + publicKeyLength) {
      throw FormatException('Incomplete ClientKeyExchange public key');
    }

    // Public key data
    final publicKey = data.sublist(1, 1 + publicKeyLength);

    return ClientKeyExchange(publicKey: publicKey);
  }

  @override
  String toString() {
    return 'ClientKeyExchange(publicKey=${publicKey.length} bytes)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ClientKeyExchange) return false;

    if (publicKey.length != other.publicKey.length) return false;
    for (var i = 0; i < publicKey.length; i++) {
      if (publicKey[i] != other.publicKey[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(publicKey);
}
