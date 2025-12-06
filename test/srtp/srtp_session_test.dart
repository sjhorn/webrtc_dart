import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/use_srtp.dart';
import 'package:webrtc_dart/src/srtp/srtp_session.dart';

void main() {
  group('SrtpSession', () {
    // Test key material for AES-128 (16 byte key, 14 byte salt)
    final testClientKey = Uint8List.fromList([
      0x01,
      0x02,
      0x03,
      0x04,
      0x05,
      0x06,
      0x07,
      0x08,
      0x09,
      0x0A,
      0x0B,
      0x0C,
      0x0D,
      0x0E,
      0x0F,
      0x10,
    ]);
    final testClientSalt = Uint8List.fromList([
      0x11,
      0x12,
      0x13,
      0x14,
      0x15,
      0x16,
      0x17,
      0x18,
      0x19,
      0x1A,
      0x1B,
      0x1C,
      0x1D,
      0x1E,
    ]);
    final testServerKey = Uint8List.fromList([
      0x21,
      0x22,
      0x23,
      0x24,
      0x25,
      0x26,
      0x27,
      0x28,
      0x29,
      0x2A,
      0x2B,
      0x2C,
      0x2D,
      0x2E,
      0x2F,
      0x30,
    ]);
    final testServerSalt = Uint8List.fromList([
      0x31,
      0x32,
      0x33,
      0x34,
      0x35,
      0x36,
      0x37,
      0x38,
      0x39,
      0x3A,
      0x3B,
      0x3C,
      0x3D,
      0x3E,
    ]);

    test('construction with valid parameters', () {
      final session = SrtpSession(
        profile: SrtpProtectionProfile.srtpAes128CmHmacSha1_80,
        localMasterKey: testClientKey,
        localMasterSalt: testClientSalt,
        remoteMasterKey: testServerKey,
        remoteMasterSalt: testServerSalt,
      );

      expect(session.profile,
          equals(SrtpProtectionProfile.srtpAes128CmHmacSha1_80));
      expect(session.localMasterKey, equals(testClientKey));
      expect(session.localMasterSalt, equals(testClientSalt));
      expect(session.remoteMasterKey, equals(testServerKey));
      expect(session.remoteMasterSalt, equals(testServerSalt));
    });

    test('toString returns readable format', () {
      final session = SrtpSession(
        profile: SrtpProtectionProfile.srtpAes128CmHmacSha1_80,
        localMasterKey: testClientKey,
        localMasterSalt: testClientSalt,
        remoteMasterKey: testServerKey,
        remoteMasterSalt: testServerSalt,
      );

      final str = session.toString();
      expect(str, contains('SrtpSession'));
      expect(str, contains('srtpAes128CmHmacSha1_80'));
    });

    test('reset does not throw', () {
      final session = SrtpSession(
        profile: SrtpProtectionProfile.srtpAes128CmHmacSha1_80,
        localMasterKey: testClientKey,
        localMasterSalt: testClientSalt,
        remoteMasterKey: testServerKey,
        remoteMasterSalt: testServerSalt,
      );

      expect(() => session.reset(), returnsNormally);
    });
  });

  group('SrtpSession.fromKeyMaterial', () {
    test('creates session from keying material for client', () {
      // AES-128 HMAC-SHA1: 16 byte key, 14 byte salt
      // Total: 16 + 16 + 14 + 14 = 60 bytes
      final keyingMaterial = Uint8List.fromList([
        // Client key (16 bytes)
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
        // Server key (16 bytes)
        0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28,
        0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F, 0x30,
        // Client salt (14 bytes)
        0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
        0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E,
        // Server salt (14 bytes)
        0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37,
        0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E,
      ]);

      final session = SrtpSession.fromKeyMaterial(
        profile: SrtpProtectionProfile.srtpAes128CmHmacSha1_80,
        keyingMaterial: keyingMaterial,
        isClient: true,
      );

      // Client uses client key for local (outbound)
      expect(session.localMasterKey, equals(keyingMaterial.sublist(0, 16)));
      expect(session.localMasterSalt, equals(keyingMaterial.sublist(32, 46)));
      // Client uses server key for remote (inbound)
      expect(session.remoteMasterKey, equals(keyingMaterial.sublist(16, 32)));
      expect(session.remoteMasterSalt, equals(keyingMaterial.sublist(46, 60)));
    });

    test('creates session from keying material for server', () {
      // AES-128 HMAC-SHA1: 16 byte key, 14 byte salt
      final keyingMaterial = Uint8List.fromList([
        // Client key (16 bytes)
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
        // Server key (16 bytes)
        0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28,
        0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F, 0x30,
        // Client salt (14 bytes)
        0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
        0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E,
        // Server salt (14 bytes)
        0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37,
        0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E,
      ]);

      final session = SrtpSession.fromKeyMaterial(
        profile: SrtpProtectionProfile.srtpAes128CmHmacSha1_80,
        keyingMaterial: keyingMaterial,
        isClient: false,
      );

      // Server uses server key for local (outbound)
      expect(session.localMasterKey, equals(keyingMaterial.sublist(16, 32)));
      expect(session.localMasterSalt, equals(keyingMaterial.sublist(46, 60)));
      // Server uses client key for remote (inbound)
      expect(session.remoteMasterKey, equals(keyingMaterial.sublist(0, 16)));
      expect(session.remoteMasterSalt, equals(keyingMaterial.sublist(32, 46)));
    });

    test('throws on insufficient keying material', () {
      final shortMaterial = Uint8List(30); // Too short

      expect(
        () => SrtpSession.fromKeyMaterial(
          profile: SrtpProtectionProfile.srtpAes128CmHmacSha1_80,
          keyingMaterial: shortMaterial,
          isClient: true,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('handles AES-128 GCM profile (12-byte salt)', () {
      // AES-128 GCM: 16 byte key, 12 byte salt
      // Total: 16 + 16 + 12 + 12 = 56 bytes
      final keyingMaterial = Uint8List.fromList([
        // Client key (16 bytes)
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
        // Server key (16 bytes)
        0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28,
        0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F, 0x30,
        // Client salt (12 bytes)
        0x11, 0x12, 0x13, 0x14, 0x15, 0x16,
        0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C,
        // Server salt (12 bytes)
        0x31, 0x32, 0x33, 0x34, 0x35, 0x36,
        0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C,
      ]);

      final session = SrtpSession.fromKeyMaterial(
        profile: SrtpProtectionProfile.srtpAeadAes128Gcm,
        keyingMaterial: keyingMaterial,
        isClient: true,
      );

      expect(session.profile, equals(SrtpProtectionProfile.srtpAeadAes128Gcm));
      expect(session.localMasterKey.length, equals(16));
      expect(session.localMasterSalt.length, equals(12));
    });

    test('handles AES-256 GCM profile (32-byte key)', () {
      // AES-256 GCM: 32 byte key, 12 byte salt
      // Total: 32 + 32 + 12 + 12 = 88 bytes
      final keyingMaterial = Uint8List.fromList([
        // Client key (32 bytes)
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
        // Server key (32 bytes)
        0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28,
        0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F, 0x30,
        0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28,
        0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F, 0x30,
        // Client salt (12 bytes)
        0x11, 0x12, 0x13, 0x14, 0x15, 0x16,
        0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C,
        // Server salt (12 bytes)
        0x31, 0x32, 0x33, 0x34, 0x35, 0x36,
        0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C,
      ]);

      final session = SrtpSession.fromKeyMaterial(
        profile: SrtpProtectionProfile.srtpAeadAes256Gcm,
        keyingMaterial: keyingMaterial,
        isClient: true,
      );

      expect(session.profile, equals(SrtpProtectionProfile.srtpAeadAes256Gcm));
      expect(session.localMasterKey.length, equals(32));
      expect(session.localMasterSalt.length, equals(12));
    });

    test('handles srtpAes128CmHmacSha1_32 profile', () {
      // Same as SHA1_80 but with 32-bit auth tag
      final keyingMaterial = Uint8List(60); // 16+16+14+14

      final session = SrtpSession.fromKeyMaterial(
        profile: SrtpProtectionProfile.srtpAes128CmHmacSha1_32,
        keyingMaterial: keyingMaterial,
        isClient: true,
      );

      expect(session.profile,
          equals(SrtpProtectionProfile.srtpAes128CmHmacSha1_32));
    });
  });
}
