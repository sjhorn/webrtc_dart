import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/cipher/prf.dart';

void main() {
  group('PRF tests', () {
    // Test vector from RFC 5246 or other known source
    test('prfPHash basic test', () {
      // Test with a simple input to verify HMAC-SHA256 P_hash works
      final secret = Uint8List.fromList('secret'.codeUnits);
      final seed = Uint8List.fromList('seed'.codeUnits);

      // Just verify it runs without error and produces expected length
      final result = prfPHash(secret, seed, 48);
      expect(result.length, 48);

      // Print result for comparison
      print('P_hash result: ${result.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

      // Test vector from werift: 8e4d932530d765a0aae974c304735ecc1202a819f80adbd5ad09c1a34fc06918e3d07795214d94c6a1976caea5a0b644
      expect(result[0], 0x8e);
      expect(result[1], 0x4d);
      expect(result[2], 0x93);
      expect(result[3], 0x25);
    });

    test('verify_data computation test', () {
      // Create a test with known inputs
      // Master secret (48 bytes)
      final masterSecret = Uint8List.fromList([
        0xfb, 0x92, 0xd2, 0x2d, 0xab, 0xf6, 0xbf, 0xba,
        0x67, 0xbd, 0x7e, 0x94, 0xcd, 0x1a, 0x67, 0xa4,
        0xe1, 0xcd, 0x2c, 0xcd, 0x68, 0x67, 0x32, 0x8c,
        0xe5, 0x8f, 0x19, 0xf3, 0xe9, 0xaa, 0xbf, 0xc0,
        0xd3, 0xaa, 0x15, 0xea, 0xa3, 0x4a, 0xf9, 0x64,
        0xdf, 0x80, 0xd3, 0x8d, 0xc4, 0x02, 0xc4, 0x4d,
      ]);

      // Sample handshake messages (simplified)
      final handshakes = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);

      final verifyData = prfVerifyDataClient(masterSecret, handshakes);
      expect(verifyData.length, 12);
      print('verify_data: ${verifyData.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

      // Test vector from werift: efffcd22933a103d7e28841f
      expect(verifyData, equals(Uint8List.fromList([
        0xef, 0xff, 0xcd, 0x22, 0x93, 0x3a, 0x10, 0x3d, 0x7e, 0x28, 0x84, 0x1f
      ])));
    });

    test('extended master secret computation', () {
      // Pre-master secret (32 bytes for X25519)
      final preMasterSecret = Uint8List.fromList([
        0xab, 0x4b, 0xc4, 0xef, 0xa5, 0x7a, 0xfe, 0x66,
        0x31, 0xd4, 0xae, 0x39, 0x77, 0x75, 0x81, 0xd3,
        0xcc, 0x9e, 0xd2, 0xcf, 0x2b, 0xb2, 0xb9, 0x60,
        0x58, 0x2e, 0xa8, 0x00, 0x2c, 0xe3, 0xda, 0x08,
      ]);

      // Sample handshake messages
      final handshakes = Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0x05]);

      final masterSecret = prfExtendedMasterSecret(preMasterSecret, handshakes);
      expect(masterSecret.length, 48);
      print('master_secret: ${masterSecret.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

      // Test vector from werift: b9aace1a741cddae6f724eddd49d9f94f34e57ec2cbadb2e6403c47dec6c7bf2c5e4ba2902284a21d75754d80d3514e0
      expect(masterSecret[0], 0xb9);
      expect(masterSecret[1], 0xaa);
      expect(masterSecret[2], 0xce);
      expect(masterSecret[3], 0x1a);
    });

    test('verify_data with real handshake hash', () {
      // This test uses specific values from a captured session
      final realHandshakeHash = Uint8List.fromList([
        0x07, 0xa7, 0xbb, 0xa4, 0xc7, 0xbb, 0xff, 0x5d,
        0x0c, 0x0d, 0x0b, 0xd2, 0x80, 0x34, 0xb8, 0xb5,
        0xf7, 0x28, 0x9f, 0x3f, 0xc0, 0x87, 0x5b, 0xaf,
        0x1a, 0x44, 0xb2, 0xf1, 0xee, 0x72, 0x00, 0xd7,
      ]);
      final realMasterSecret = Uint8List.fromList([
        0x3c, 0xdf, 0x38, 0x04, 0xca, 0x4e, 0x1a, 0x00,
        0xd3, 0xd9, 0x4d, 0xd3, 0xa8, 0xd8, 0x70, 0x19,
        0x97, 0x0b, 0xbf, 0x81, 0xd9, 0xaa, 0x3e, 0x4c,
        0x77, 0x37, 0x15, 0x19, 0xdb, 0x40, 0x62, 0xa1,
        0x9a, 0xb9, 0x72, 0x06, 0x6f, 0xda, 0x06, 0x48,
        0xa6, 0x50, 0x59, 0x8e, 0xe6, 0xa6, 0x13, 0x51,
      ]);

      // Compute verify_data using PRF(master_secret, "client finished", handshake_hash)
      // Note: prfVerifyData hashes the handshakes first, but we already have the hash,
      // so we need to call prfPHash directly
      final label = Uint8List.fromList('client finished'.codeUnits);
      final seed = Uint8List(label.length + realHandshakeHash.length);
      seed.setRange(0, label.length, label);
      seed.setRange(label.length, seed.length, realHandshakeHash);

      final verifyData = prfPHash(realMasterSecret, seed, 12);
      print('verify_data: ${verifyData.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

      // Test vector from werift: 88e9f3b5e1e02873ae52643d
      expect(verifyData, equals(Uint8List.fromList([
        0x88, 0xe9, 0xf3, 0xb5, 0xe1, 0xe0, 0x28, 0x73, 0xae, 0x52, 0x64, 0x3d
      ])));
    });
  });
}
