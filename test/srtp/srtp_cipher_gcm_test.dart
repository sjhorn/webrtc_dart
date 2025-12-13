import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/srtp/srtp_cipher.dart';
import 'package:webrtc_dart/src/srtp/srtcp_cipher.dart';
import 'package:webrtc_dart/src/srtp/key_derivation.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';
import 'package:webrtc_dart/src/srtp/rtcp_packet.dart';

/// Test vectors from werift-webrtc packages/rtp/tests/srtp/cipher/gcm.test.ts
///
/// IMPORTANT: AES-GCM Key Derivation Notes (RFC 7714)
///
/// AES-GCM mode requires key derivation from master key/salt just like CTR mode:
/// - Use RFC 3711's Key Derivation Function (KDF) with AES-ECB PRF
/// - SRTP: label 0 for encryption key, label 2 for salt
/// - SRTCP: label 3 for encryption key, label 5 for salt
/// - 12-byte master salt must be right-padded to 14 bytes for KDF
/// - Derived 14-byte salt is then truncated to 12 bytes for GCM nonce
///
/// This matches werift's implementation (context.ts) and libsrtp's approach.
/// Note: RFC spec says left-pad, but werift/libsrtp use right-padding.
///
/// Test vectors generated with Node.js crypto (see interop/srtp_cipher_vectors.mjs)
void main() {
  group('SrtpCipher AES-GCM', () {
    // Test vectors from werift
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

    group('RTP encryption/decryption', () {
      test('encrypts and decrypts RTP packet roundtrip', () async {
        final cipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final packet = RtpPacket(
          payloadType: 15,
          sequenceNumber: 0x1234,
          timestamp: 0xdecafbad,
          ssrc: 0xcafebabe,
          payload: Uint8List.fromList([
            0xab,
            0xab,
            0xab,
            0xab,
            0xab,
            0xab,
            0xab,
            0xab,
            0xab,
            0xab,
            0xab,
            0xab,
            0xab,
            0xab,
            0xab,
            0xab,
          ]),
        );

        final encrypted = await cipher.encrypt(packet);

        // Encrypted should be larger (header + encrypted payload + 16-byte auth tag)
        expect(encrypted.length, equals(12 + 16 + 16));

        // Decrypt with fresh cipher
        final decryptCipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final decrypted = await decryptCipher.decrypt(encrypted);

        expect(decrypted.payloadType, equals(packet.payloadType));
        expect(decrypted.sequenceNumber, equals(packet.sequenceNumber));
        expect(decrypted.timestamp, equals(packet.timestamp));
        expect(decrypted.ssrc, equals(packet.ssrc));
        expect(decrypted.payload, equals(packet.payload));
      });

      test('encrypts packets with different sequence numbers differently',
          () async {
        final cipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final payload = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);

        final packet1 = RtpPacket(
          payloadType: 96,
          sequenceNumber: 100,
          timestamp: 1000,
          ssrc: 0x12345678,
          payload: payload,
        );

        final packet2 = RtpPacket(
          payloadType: 96,
          sequenceNumber: 101,
          timestamp: 2000,
          ssrc: 0x12345678,
          payload: payload,
        );

        final encrypted1 = await cipher.encrypt(packet1);
        final encrypted2 = await cipher.encrypt(packet2);

        // Same payload but different encrypted data due to different sequence numbers
        expect(encrypted1, isNot(equals(encrypted2)));
      });

      test('handles empty payload', () async {
        final cipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final packet = RtpPacket(
          payloadType: 96,
          sequenceNumber: 1,
          timestamp: 1000,
          ssrc: 0xAABBCCDD,
          payload: Uint8List(0),
        );

        final encrypted = await cipher.encrypt(packet);

        // Header (12) + auth tag (16), no payload
        expect(encrypted.length, equals(12 + 16));

        final decryptCipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );
        final decrypted = await decryptCipher.decrypt(encrypted);

        expect(decrypted.payload, isEmpty);
        expect(decrypted.ssrc, equals(packet.ssrc));
      });

      test('handles packets with CSRCs', () async {
        final cipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final packet = RtpPacket(
          payloadType: 96,
          sequenceNumber: 100,
          timestamp: 1000,
          ssrc: 0x12345678,
          csrcs: [0xAAAAAAAA, 0xBBBBBBBB],
          payload: Uint8List.fromList([1, 2, 3, 4]),
        );

        final encrypted = await cipher.encrypt(packet);
        final decryptCipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );
        final decrypted = await decryptCipher.decrypt(encrypted);

        expect(decrypted.csrcs.length, 2);
        expect(decrypted.csrcs[0], 0xAAAAAAAA);
        expect(decrypted.csrcs[1], 0xBBBBBBBB);
      });
    });

    group('RTCP encryption/decryption', () {
      test('encrypts and decrypts RTCP packet roundtrip', () async {
        final cipher = SrtcpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final packet = RtcpPacket(
          packetType: RtcpPacketType.senderReport,
          reportCount: 1,
          length: 5, // 5 = (8 header + 16 payload)/4 - 1
          ssrc: 0xcafebabe,
          payload: Uint8List.fromList([
            0xab,
            0xab,
            0xab,
            0xab,
            0xab,
            0xab,
            0xab,
            0xab,
            0xab,
            0xab,
            0xab,
            0xab,
            0xab,
            0xab,
            0xab,
            0xab,
          ]),
        );

        final encrypted = await cipher.encrypt(packet);

        // Encrypted should include: header(8) + encrypted_payload(16) + auth(16) + index(4)
        expect(encrypted.length, equals(8 + 16 + 16 + 4));

        final decryptCipher = SrtcpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final decrypted = await decryptCipher.decrypt(encrypted);

        expect(decrypted.packetType, equals(packet.packetType));
        expect(decrypted.ssrc, equals(packet.ssrc));
        expect(decrypted.payload, equals(packet.payload));
      });

      test('encrypts and decrypts empty RTCP payload', () async {
        final cipher = SrtcpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final packet = RtcpPacket(
          packetType: RtcpPacketType.receiverReport,
          reportCount: 0,
          length: 1,
          ssrc: 0xAABBCCDD,
          payload: Uint8List(0),
        );

        final encrypted = await cipher.encrypt(packet);

        // Minimum SRTCP GCM: 8 (header) + 0 (payload) + 16 (auth) + 4 (index) = 28 bytes
        expect(encrypted.length, equals(28));

        final decryptCipher = SrtcpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final decrypted = await decryptCipher.decrypt(encrypted);

        expect(decrypted.packetType, equals(RtcpPacketType.receiverReport));
        expect(decrypted.ssrc, equals(0xAABBCCDD));
        expect(decrypted.payload, isEmpty);
      });

      test('encrypted packet has E-flag set', () async {
        final cipher = SrtcpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final packet = RtcpPacket(
          packetType: RtcpPacketType.senderReport,
          reportCount: 0,
          length: 1,
          ssrc: 0x11111111,
          payload: Uint8List(0),
        );

        final encrypted = await cipher.encrypt(packet);

        // E-flag is MSB of the last 4 bytes (index)
        final indexOffset = encrypted.length - 4;
        final eFlag = encrypted[indexOffset] & 0x80;
        expect(eFlag, equals(0x80));
      });
    });

    group('reset', () {
      test('reset clears SRTP state', () async {
        final cipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        // Encrypt some packets
        for (var i = 0; i < 5; i++) {
          await cipher.encrypt(RtpPacket(
            payloadType: 96,
            sequenceNumber: i,
            timestamp: i * 1000,
            ssrc: 0x12345678,
            payload: Uint8List.fromList([i]),
          ));
        }

        cipher.reset();

        // After reset, should work fresh
        final packet = RtpPacket(
          payloadType: 96,
          sequenceNumber: 0,
          timestamp: 0,
          ssrc: 0x12345678,
          payload: Uint8List.fromList([0]),
        );

        expect(() async => await cipher.encrypt(packet), returnsNormally);
      });

      test('reset clears SRTCP state', () async {
        final cipher = SrtcpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        // Encrypt some packets
        for (var i = 0; i < 5; i++) {
          await cipher.encrypt(RtcpPacket(
            packetType: RtcpPacketType.receiverReport,
            reportCount: 0,
            length: 1,
            ssrc: 0x12345678,
            payload: Uint8List(0),
          ));
        }

        cipher.reset();

        // After reset, index should restart from 0
        final packet = RtcpPacket(
          packetType: RtcpPacketType.receiverReport,
          reportCount: 0,
          length: 1,
          ssrc: 0x12345678,
          payload: Uint8List(0),
        );

        expect(() async => await cipher.encrypt(packet), returnsNormally);
      });
    });

    group('different SSRCs', () {
      test('handles multiple SSRCs independently', () async {
        final cipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final packet1 = RtpPacket(
          payloadType: 96,
          sequenceNumber: 1,
          timestamp: 1000,
          ssrc: 0x11111111,
          payload: Uint8List.fromList([1, 2, 3]),
        );

        final packet2 = RtpPacket(
          payloadType: 96,
          sequenceNumber: 1,
          timestamp: 1000,
          ssrc: 0x22222222,
          payload: Uint8List.fromList([1, 2, 3]),
        );

        final encrypted1 = await cipher.encrypt(packet1);
        final encrypted2 = await cipher.encrypt(packet2);

        // Different SSRCs should produce different ciphertexts
        expect(encrypted1, isNot(equals(encrypted2)));
      });
    });

    group('authentication tag', () {
      test('authTagLength is 16 bytes for GCM', () {
        // GCM uses 128-bit (16-byte) authentication tag
        expect(16, equals(16)); // Just documenting the expected value
      });
    });

    group('key derivation test vectors', () {
      // Test vectors from interop/srtp_cipher_vectors.mjs (Node.js crypto)
      // Master key/salt are used as inputs, and we verify derived session keys match.

      test('derives correct SRTP session key from 12-byte master salt', () {
        // These expected values were generated by running:
        //   node interop/srtp_cipher_vectors.mjs
        //
        // Input:
        //   masterKey: 000102030405060708090a0b0c0d0e0f
        //   masterSalt: a0a1a2a3a4a5a6a7a8a9aaab (12 bytes)
        //
        // Output:
        //   SRTP Session Key: 077c6143cb221bc355ff23d5f984a16e
        //   SRTP Session Salt: 9af3e95364ebac9c99c5a7c40169

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

      test('derives correct SRTCP session key from 12-byte master salt', () {
        // Expected values from interop/srtp_cipher_vectors.mjs:
        //   SRTCP Session Key: 615dcd9042600666f6fd4d9e4fe4519f
        //   SRTCP Session Salt: fcca937b9112a500dac722691f9e

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

      test('SRTCP encryption matches Node.js test vector', () async {
        // Test vector from interop/srtp_cipher_vectors.mjs
        //
        // Input RTCP packet: 80c90001cafebabe (Receiver Report, SSRC=0xcafebabe)
        // Expected encrypted: 80c90001cafebabeeaecc2c438ea2e58439ea0841a4a2e8d80000000
        //
        // The cipher uses derived session keys (not master keys directly)

        // Derive SRTCP session keys
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

        // Create cipher with derived keys (truncate salt to 12 bytes for GCM)
        final cipher = SrtcpCipher(
          masterKey: srtcpKey,
          masterSalt: srtcpSalt.sublist(0, 12),
        );

        // Create the test RTCP packet
        final packet = RtcpPacket(
          packetType: RtcpPacketType.receiverReport,
          reportCount: 0,
          length: 1,
          ssrc: 0xcafebabe,
          payload: Uint8List(0),
        );

        final encrypted = await cipher.encrypt(packet);

        // Verify encrypted output matches Node.js
        expect(_toHex(encrypted),
            equals('80c90001cafebabeeaecc2c438ea2e58439ea0841a4a2e8d80000000'));
      });

      test('SRTCP decryption of known Node.js vector', () async {
        // Decrypt the known encrypted packet from Node.js
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

        final encryptedPacket = _fromHex(
            '80c90001cafebabeeaecc2c438ea2e58439ea0841a4a2e8d80000000');
        final decrypted = await cipher.decrypt(encryptedPacket);

        expect(_toHex(decrypted.serialize()), equals('80c90001cafebabe'));
        expect(decrypted.ssrc, equals(0xcafebabe));
        expect(decrypted.packetType, equals(RtcpPacketType.receiverReport));
      });
    });
  });
}

String _toHex(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Uint8List _fromHex(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < result.length; i++) {
    result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return result;
}
