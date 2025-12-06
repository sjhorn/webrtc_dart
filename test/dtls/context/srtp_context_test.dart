import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/context/srtp_context.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/use_srtp.dart';

void main() {
  group('SrtpContext', () {
    test('construction with default values', () {
      final context = SrtpContext();

      expect(context.profile, isNull);
      expect(context.localMasterKey, isNull);
      expect(context.localMasterSalt, isNull);
      expect(context.remoteMasterKey, isNull);
      expect(context.remoteMasterSalt, isNull);
      expect(context.mki, isNull);
    });

    test('construction with profile', () {
      final context = SrtpContext(
        profile: SrtpProtectionProfile.srtpAes128CmHmacSha1_80,
      );

      expect(context.profile,
          equals(SrtpProtectionProfile.srtpAes128CmHmacSha1_80));
    });

    test('hasKeys returns false when keys not set', () {
      final context = SrtpContext();
      expect(context.hasKeys, isFalse);
    });

    test('hasKeys returns true when all keys set', () {
      final context = SrtpContext(
        localMasterKey: Uint8List(16),
        localMasterSalt: Uint8List(14),
        remoteMasterKey: Uint8List(16),
        remoteMasterSalt: Uint8List(14),
      );

      expect(context.hasKeys, isTrue);
    });

    test('keyMaterial getter returns empty list when not set', () {
      final context = SrtpContext();
      expect(context.keyMaterial.isEmpty, isTrue);
    });

    test('keyMaterial setter and getter', () {
      final context = SrtpContext();
      final material = Uint8List.fromList([1, 2, 3, 4]);

      context.keyMaterial = material;

      expect(context.keyMaterial, equals(material));
    });

    test('keyMaterialLength for AES-128 HMAC-SHA1-80', () {
      final context = SrtpContext(
        profile: SrtpProtectionProfile.srtpAes128CmHmacSha1_80,
      );

      // 16 + 16 + 14 + 14 = 60
      expect(context.keyMaterialLength, equals(60));
    });

    test('keyMaterialLength for AES-128 HMAC-SHA1-32', () {
      final context = SrtpContext(
        profile: SrtpProtectionProfile.srtpAes128CmHmacSha1_32,
      );

      expect(context.keyMaterialLength, equals(60));
    });

    test('keyMaterialLength for AEAD-AES-128-GCM', () {
      final context = SrtpContext(
        profile: SrtpProtectionProfile.srtpAeadAes128Gcm,
      );

      // 16 + 16 + 12 + 12 = 56
      expect(context.keyMaterialLength, equals(56));
    });

    test('keyMaterialLength for AEAD-AES-256-GCM', () {
      final context = SrtpContext(
        profile: SrtpProtectionProfile.srtpAeadAes256Gcm,
      );

      // 32 + 32 + 12 + 12 = 88
      expect(context.keyMaterialLength, equals(88));
    });

    test('keyMaterialLength returns 0 when profile is null', () {
      final context = SrtpContext();
      expect(context.keyMaterialLength, equals(0));
    });

    test('keyLength for AES-128 profiles', () {
      var context = SrtpContext(
        profile: SrtpProtectionProfile.srtpAes128CmHmacSha1_80,
      );
      expect(context.keyLength, equals(16));

      context = SrtpContext(
        profile: SrtpProtectionProfile.srtpAes128CmHmacSha1_32,
      );
      expect(context.keyLength, equals(16));

      context = SrtpContext(
        profile: SrtpProtectionProfile.srtpAeadAes128Gcm,
      );
      expect(context.keyLength, equals(16));
    });

    test('keyLength for AES-256 GCM', () {
      final context = SrtpContext(
        profile: SrtpProtectionProfile.srtpAeadAes256Gcm,
      );
      expect(context.keyLength, equals(32));
    });

    test('keyLength returns 0 when profile is null', () {
      final context = SrtpContext();
      expect(context.keyLength, equals(0));
    });

    test('saltLength for HMAC-SHA1 profiles', () {
      var context = SrtpContext(
        profile: SrtpProtectionProfile.srtpAes128CmHmacSha1_80,
      );
      expect(context.saltLength, equals(14));

      context = SrtpContext(
        profile: SrtpProtectionProfile.srtpAes128CmHmacSha1_32,
      );
      expect(context.saltLength, equals(14));
    });

    test('saltLength for GCM profiles', () {
      var context = SrtpContext(
        profile: SrtpProtectionProfile.srtpAeadAes128Gcm,
      );
      expect(context.saltLength, equals(12));

      context = SrtpContext(
        profile: SrtpProtectionProfile.srtpAeadAes256Gcm,
      );
      expect(context.saltLength, equals(12));
    });

    test('saltLength returns 0 when profile is null', () {
      final context = SrtpContext();
      expect(context.saltLength, equals(0));
    });

    test('reset clears all fields', () {
      final context = SrtpContext(
        profile: SrtpProtectionProfile.srtpAes128CmHmacSha1_80,
        localMasterKey: Uint8List(16),
        localMasterSalt: Uint8List(14),
        remoteMasterKey: Uint8List(16),
        remoteMasterSalt: Uint8List(14),
        mki: Uint8List(4),
      );

      expect(context.hasKeys, isTrue);

      context.reset();

      expect(context.profile, isNull);
      expect(context.hasKeys, isFalse);
      expect(context.mki, isNull);
    });

    test('toString returns readable format', () {
      final context = SrtpContext(
        profile: SrtpProtectionProfile.srtpAes128CmHmacSha1_80,
      );

      final str = context.toString();
      expect(str, contains('SrtpContext'));
      expect(str, contains('srtpAes128CmHmacSha1_80'));
    });
  });

  group('SrtpContext.extractKeys', () {
    test('extracts keys for client', () {
      final context = SrtpContext(
        profile: SrtpProtectionProfile.srtpAes128CmHmacSha1_80,
      );

      // 60 bytes: 16 + 16 + 14 + 14
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

      context.extractKeys(keyingMaterial, true);

      // Client uses client key for local
      expect(context.localMasterKey, equals(keyingMaterial.sublist(0, 16)));
      expect(context.remoteMasterKey, equals(keyingMaterial.sublist(16, 32)));
      expect(context.localMasterSalt, equals(keyingMaterial.sublist(32, 46)));
      expect(context.remoteMasterSalt, equals(keyingMaterial.sublist(46, 60)));
      expect(context.hasKeys, isTrue);
    });

    test('extracts keys for server', () {
      final context = SrtpContext(
        profile: SrtpProtectionProfile.srtpAes128CmHmacSha1_80,
      );

      final keyingMaterial = Uint8List(60);

      context.extractKeys(keyingMaterial, false);

      // Server uses server key for local (bytes 16-32)
      expect(context.localMasterKey, equals(keyingMaterial.sublist(16, 32)));
      expect(context.remoteMasterKey, equals(keyingMaterial.sublist(0, 16)));
      expect(context.hasKeys, isTrue);
    });

    test('throws on no profile selected', () {
      final context = SrtpContext();

      expect(
        () => context.extractKeys(Uint8List(60), true),
        throwsA(isA<StateError>()),
      );
    });

    test('throws on insufficient keying material', () {
      final context = SrtpContext(
        profile: SrtpProtectionProfile.srtpAes128CmHmacSha1_80,
      );

      expect(
        () => context.extractKeys(Uint8List(30), true),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
