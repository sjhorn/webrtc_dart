import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';

void main() {
  group('X25519 test vectors', () {
    test('RFC 7748 test vector', () async {
      // Test vector from RFC 7748 Section 6.1
      // Alice's private key (scalar)
      final alicePrivate = Uint8List.fromList([
        0x77, 0x07, 0x6d, 0x0a, 0x73, 0x18, 0xa5, 0x7d,
        0x3c, 0x16, 0xc1, 0x72, 0x51, 0xb2, 0x66, 0x45,
        0xdf, 0x4c, 0x2f, 0x87, 0xeb, 0xc0, 0x99, 0x2a,
        0xb1, 0x77, 0xfb, 0xa5, 0x1d, 0xb9, 0x2c, 0x2a,
      ]);

      // Bob's public key (u-coordinate)
      final bobPublic = Uint8List.fromList([
        0xde, 0x9e, 0xdb, 0x7d, 0x7b, 0x7d, 0xc1, 0xb4,
        0xd3, 0x5b, 0x61, 0xc2, 0xec, 0xe4, 0x35, 0x37,
        0x3f, 0x83, 0x43, 0xc8, 0x5b, 0x78, 0x67, 0x4d,
        0xad, 0xfc, 0x7e, 0x14, 0x6f, 0x88, 0x2b, 0x4f,
      ]);

      // Expected shared secret
      final expectedShared = Uint8List.fromList([
        0x4a, 0x5d, 0x9d, 0x5b, 0xa4, 0xce, 0x2d, 0xe1,
        0x72, 0x8e, 0x3b, 0xf4, 0x80, 0x35, 0x0f, 0x25,
        0xe0, 0x7e, 0x21, 0xc9, 0x47, 0xd1, 0x9e, 0x33,
        0x76, 0xf0, 0x9b, 0x3c, 0x1e, 0x16, 0x17, 0x42,
      ]);

      // Use cryptography package to compute shared secret
      final algorithm = X25519();

      // Create key pair from private key bytes
      final keyPair = await algorithm.newKeyPairFromSeed(alicePrivate);

      // Create remote public key
      final remotePublicKey = SimplePublicKey(
        bobPublic.toList(),
        type: KeyPairType.x25519,
      );

      // Compute shared secret
      final sharedSecret = await algorithm.sharedSecretKey(
        keyPair: keyPair,
        remotePublicKey: remotePublicKey,
      );

      final sharedBytes = await sharedSecret.extractBytes();

      print('Expected:  ${expectedShared.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      print('Computed:  ${sharedBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

      expect(Uint8List.fromList(sharedBytes), equals(expectedShared));
    });
  });
}
