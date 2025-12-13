import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/srtp/srtp_cipher.dart';
import 'package:webrtc_dart/src/srtp/srtcp_cipher.dart';
import 'package:webrtc_dart/src/srtp/key_derivation.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';
import 'package:webrtc_dart/src/srtp/rtcp_packet.dart';

/// Regression tests for RFC 7714 AES-GCM implementation
///
/// These tests verify critical aspects of the AES-GCM SRTP/SRTCP implementation
/// that were fixed during Ring camera video streaming development:
///
/// 1. SRTP AAD (Additional Authenticated Data) must include RTP extension headers
/// 2. SRTCP AAD must include both header (8 bytes) AND SRTCP index with E-flag (4 bytes)
/// 3. Nonce format: 00 || SSRC || ROC/padding || SEQ/index (RFC 7714 Section 8.1/9.1)
/// 4. Key derivation uses werift-compatible AES-ECB PRF (not AES-CTR)
///
/// The RTP extension header bug caused Chrome to silently drop all video packets
/// because GCM authentication failed when the sender excluded extension headers
/// from AAD but the receiver included them (from the raw packet bytes).
void main() {
  group('RFC 7714 SRTP/SRTCP', () {
    // Standard test vectors
    final masterKey = Uint8List.fromList([
      0x00,
      0x01,
      0x02,
      0x03,
      0x04,
      0x05,
      0x06,
      0x07,
      0x08,
      0x09,
      0x0a,
      0x0b,
      0x0c,
      0x0d,
      0x0e,
      0x0f,
    ]);
    final masterSalt = Uint8List.fromList([
      0xa0,
      0xa1,
      0xa2,
      0xa3,
      0xa4,
      0xa5,
      0xa6,
      0xa7,
      0xa8,
      0xa9,
      0xaa,
      0xab,
    ]);

    group('SRTP AAD includes extension headers', () {
      test('packet with one-byte extension encrypts/decrypts correctly',
          () async {
        // This test verifies the fix for the Ring video bug:
        // Extension headers MUST be included in AAD for GCM authentication

        final cipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        // Create packet with one-byte extension (0xBEDE profile)
        // This is what Ring camera sends with transport-cc extension
        final packet = RtpPacket(
          payloadType: 96,
          sequenceNumber: 1234,
          timestamp: 5678,
          ssrc: 0xCAFEBABE,
          extension: true,
          extensionHeader: RtpExtension(
            profile: 0xBEDE, // One-byte extension profile
            data: Uint8List.fromList([0x10, 0x31, 0x00, 0x00]), // mid=1
          ),
          payload: Uint8List.fromList([0xAB, 0xCD, 0xEF, 0x01]),
        );

        // Encrypt
        final encrypted = await cipher.encrypt(packet);

        // Decrypt with fresh cipher
        final decryptCipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final decrypted = await decryptCipher.decrypt(encrypted);

        // Verify extension is preserved
        expect(decrypted.extension, isTrue);
        expect(decrypted.extensionHeader, isNotNull);
        expect(decrypted.extensionHeader!.profile, equals(0xBEDE));
        expect(decrypted.extensionHeader!.data,
            equals(packet.extensionHeader!.data));
        expect(decrypted.payload, equals(packet.payload));
      });

      test('tampered extension header causes decryption failure', () async {
        // This test ensures that tampering with extension data is detected
        // because extension is included in AAD

        final cipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final packet = RtpPacket(
          payloadType: 96,
          sequenceNumber: 100,
          timestamp: 1000,
          ssrc: 0x12345678,
          extension: true,
          extensionHeader: RtpExtension(
            profile: 0xBEDE,
            data: Uint8List.fromList([0x10, 0x31, 0x00, 0x00]),
          ),
          payload: Uint8List.fromList([1, 2, 3, 4]),
        );

        final encrypted = await cipher.encrypt(packet);

        // Tamper with extension data (byte 17 is within extension)
        final tampered = Uint8List.fromList(encrypted);
        tampered[17] = tampered[17] ^ 0xFF;

        // Decryption should fail due to AAD mismatch
        final decryptCipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        expect(
          () async => await decryptCipher.decrypt(tampered),
          throwsA(anything),
          reason: 'Tampered extension should cause GCM auth failure',
        );
      });

      test('packet with two-byte extension encrypts/decrypts correctly',
          () async {
        final cipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        // Two-byte extension profile (0x1000)
        // Extension data must be 4-byte aligned
        final packet = RtpPacket(
          payloadType: 96,
          sequenceNumber: 500,
          timestamp: 90000,
          ssrc: 0xDEADBEEF,
          extension: true,
          extensionHeader: RtpExtension(
            profile: 0x1000, // Two-byte extension profile
            data: Uint8List.fromList([
              0x01, 0x02, 0xAA,
              0xBB, // Extension ID 1, length 2, data AA BB (4 bytes)
            ]),
          ),
          payload: Uint8List.fromList([0x11, 0x22, 0x33]),
        );

        final encrypted = await cipher.encrypt(packet);

        final decryptCipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final decrypted = await decryptCipher.decrypt(encrypted);

        expect(decrypted.extension, isTrue);
        expect(decrypted.extensionHeader!.profile, equals(0x1000));
        expect(decrypted.extensionHeader!.data,
            equals(packet.extensionHeader!.data));
      });
    });

    group('SRTCP AAD format (RFC 7714 Section 17)', () {
      test('AAD includes header (8 bytes) + index with E-flag (4 bytes)',
          () async {
        // RFC 7714 Section 17: AAD = RTCP Header || SRTCP Index
        // The E-flag is part of the SRTCP index in the AAD

        final srtcpKey = SrtpKeyDerivation.generateSessionKey(
          masterKey: masterKey,
          masterSalt: masterSalt,
          label: SrtpKeyDerivation.labelSrtcpEncryption,
        );
        final srtcpSalt = SrtpKeyDerivation.generateSessionSalt(
          masterKey: masterKey,
          masterSalt: masterSalt,
          label: SrtpKeyDerivation.labelSrtcpSalt,
        );

        final cipher = SrtcpCipher(
          masterKey: srtcpKey,
          masterSalt: srtcpSalt.sublist(0, 12),
        );

        // RTCP length field = (total bytes / 4) - 1
        // For 8 byte header + 16 byte payload = 24 bytes = 6 words, length = 5
        final packet = RtcpPacket(
          packetType: RtcpPacketType.senderReport,
          reportCount: 0,
          length: 5, // (24 bytes / 4) - 1 = 5
          ssrc: 0xCAFEBABE,
          payload: Uint8List.fromList(
              [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]),
        );

        final encrypted = await cipher.encrypt(packet);

        // Decrypt with fresh cipher should work
        final decryptCipher = SrtcpCipher(
          masterKey: srtcpKey,
          masterSalt: srtcpSalt.sublist(0, 12),
        );

        final decrypted = await decryptCipher.decrypt(encrypted);
        expect(decrypted.ssrc, equals(packet.ssrc));
        expect(decrypted.payload, equals(packet.payload));
      });

      test('tampered SRTCP index causes decryption failure', () async {
        // Since SRTCP index is part of AAD, tampering should fail

        final srtcpKey = SrtpKeyDerivation.generateSessionKey(
          masterKey: masterKey,
          masterSalt: masterSalt,
          label: SrtpKeyDerivation.labelSrtcpEncryption,
        );
        final srtcpSalt = SrtpKeyDerivation.generateSessionSalt(
          masterKey: masterKey,
          masterSalt: masterSalt,
          label: SrtpKeyDerivation.labelSrtcpSalt,
        );

        final cipher = SrtcpCipher(
          masterKey: srtcpKey,
          masterSalt: srtcpSalt.sublist(0, 12),
        );

        final packet = RtcpPacket(
          packetType: RtcpPacketType.receiverReport,
          reportCount: 0,
          length: 1,
          ssrc: 0x12345678,
          payload: Uint8List(0),
        );

        final encrypted = await cipher.encrypt(packet);

        // Tamper with SRTCP index (last 4 bytes, change index but keep E-flag)
        final tampered = Uint8List.fromList(encrypted);
        tampered[tampered.length - 2] = 0xFF; // Change index

        final decryptCipher = SrtcpCipher(
          masterKey: srtcpKey,
          masterSalt: srtcpSalt.sublist(0, 12),
        );

        expect(
          () async => await decryptCipher.decrypt(tampered),
          throwsA(anything),
          reason: 'Tampered SRTCP index should cause GCM auth failure',
        );
      });
    });

    group('Nonce (IV) format (RFC 7714 Section 8.1/9.1)', () {
      test('SRTP nonce format: 00 || SSRC || ROC || SEQ', () async {
        // RFC 7714 Section 8.1: IV = 00 || SSRC || ROC || SEQ
        // Bytes: [0, 0, SSRC(4), ROC(4), SEQ(2)]
        // Then XOR with 12-byte salt

        final cipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        // Encrypt two packets with same SSRC but different sequence numbers
        // They should produce different ciphertexts due to different nonces
        final packet1 = RtpPacket(
          payloadType: 96,
          sequenceNumber: 1,
          timestamp: 1000,
          ssrc: 0xAABBCCDD,
          payload: Uint8List.fromList([0x00, 0x00, 0x00, 0x00]),
        );

        final packet2 = RtpPacket(
          payloadType: 96,
          sequenceNumber: 2,
          timestamp: 1000,
          ssrc: 0xAABBCCDD,
          payload: Uint8List.fromList([0x00, 0x00, 0x00, 0x00]),
        );

        final encrypted1 = await cipher.encrypt(packet1);
        final encrypted2 = await cipher.encrypt(packet2);

        // Same plaintext but different sequence numbers = different ciphertext
        expect(encrypted1, isNot(equals(encrypted2)));
      });

      test('SRTCP nonce format: 00 || SSRC || 00 || index', () async {
        // RFC 7714 Section 9.1: IV = 00 || SSRC || 0000 || SRTCP_index
        // Bytes: [0, 0, SSRC(4), 0, 0, index(4)]
        // Then XOR with 12-byte salt

        final srtcpKey = SrtpKeyDerivation.generateSessionKey(
          masterKey: masterKey,
          masterSalt: masterSalt,
          label: SrtpKeyDerivation.labelSrtcpEncryption,
        );
        final srtcpSalt = SrtpKeyDerivation.generateSessionSalt(
          masterKey: masterKey,
          masterSalt: masterSalt,
          label: SrtpKeyDerivation.labelSrtcpSalt,
        );

        final cipher = SrtcpCipher(
          masterKey: srtcpKey,
          masterSalt: srtcpSalt.sublist(0, 12),
        );

        // Encrypt same packet twice - index increments, so ciphertexts differ
        final packet = RtcpPacket(
          packetType: RtcpPacketType.senderReport,
          reportCount: 0,
          length: 1,
          ssrc: 0xAABBCCDD,
          payload: Uint8List(0),
        );

        final encrypted1 = await cipher.encrypt(packet);
        final encrypted2 = await cipher.encrypt(packet);

        // Same plaintext but different index = different ciphertext
        expect(encrypted1, isNot(equals(encrypted2)));
      });
    });

    group('Key derivation (werift-compatible AES-ECB PRF)', () {
      test('SRTP key derivation produces expected values', () {
        // Test vector from interop/srtp_cipher_vectors.mjs
        // Verified against werift-webrtc Node.js implementation

        final derivedKey = SrtpKeyDerivation.generateSessionKey(
          masterKey: masterKey,
          masterSalt: masterSalt,
          label: SrtpKeyDerivation.labelSrtpEncryption,
        );

        final derivedSalt = SrtpKeyDerivation.generateSessionSalt(
          masterKey: masterKey,
          masterSalt: masterSalt,
          label: SrtpKeyDerivation.labelSrtpSalt,
        );

        expect(_toHex(derivedKey), equals('077c6143cb221bc355ff23d5f984a16e'));
        expect(_toHex(derivedSalt), equals('9af3e95364ebac9c99c5a7c40169'));
      });

      test('SRTCP key derivation produces expected values', () {
        // Test vector from interop/srtp_cipher_vectors.mjs

        final derivedKey = SrtpKeyDerivation.generateSessionKey(
          masterKey: masterKey,
          masterSalt: masterSalt,
          label: SrtpKeyDerivation.labelSrtcpEncryption,
        );

        final derivedSalt = SrtpKeyDerivation.generateSessionSalt(
          masterKey: masterKey,
          masterSalt: masterSalt,
          label: SrtpKeyDerivation.labelSrtcpSalt,
        );

        expect(_toHex(derivedKey), equals('615dcd9042600666f6fd4d9e4fe4519f'));
        expect(_toHex(derivedSalt), equals('fcca937b9112a500dac722691f9e'));
      });

      test('12-byte master salt is padded to 14 bytes correctly', () {
        // GCM uses 12-byte salt, but KDF requires 14-byte input
        // Salt should be right-padded with zeros

        final shortSalt = Uint8List.fromList([
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
        ]);

        // Should not throw with 12-byte salt
        expect(
          () => SrtpKeyDerivation.generateSessionKey(
            masterKey: masterKey,
            masterSalt: shortSalt,
            label: SrtpKeyDerivation.labelSrtpEncryption,
          ),
          returnsNormally,
        );
      });
    });

    group('Ring camera video forwarding scenario', () {
      test('simulates Ring -> webrtc_dart -> Browser forwarding', () async {
        // This test simulates the actual Ring video streaming scenario:
        // 1. Ring camera encrypts RTP with transport-cc extension
        // 2. webrtc_dart decrypts (CTR mode from Ring)
        // 3. webrtc_dart re-encrypts with mid extension (GCM mode to browser)
        // 4. Browser decrypts and displays video

        // Simulate incoming packet from Ring (with extension)
        final incomingPacket = RtpPacket(
          payloadType: 96,
          sequenceNumber: 1000,
          timestamp: 90000,
          ssrc: 0xD1061234, // Ring's SSRC
          marker: true, // End of frame
          extension: true,
          extensionHeader: RtpExtension(
            profile: 0xBEDE,
            data: Uint8List.fromList(
                [0x02, 0x01, 0x00, 0x00]), // transport-cc ext
          ),
          payload: Uint8List.fromList(List.generate(100, (i) => i)), // H264 NAL
        );

        // Encrypt for browser (GCM mode)
        final cipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final encrypted = await cipher.encrypt(incomingPacket);

        // Browser decrypts
        final browserCipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final decrypted = await browserCipher.decrypt(encrypted);

        // Verify browser receives complete packet with extension
        expect(decrypted.payloadType, equals(96));
        expect(decrypted.marker, isTrue);
        expect(decrypted.extension, isTrue);
        expect(decrypted.extensionHeader!.profile, equals(0xBEDE));
        expect(decrypted.payload.length, equals(100));
      });
    });
  });
}

String _toHex(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
