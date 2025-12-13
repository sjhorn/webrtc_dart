import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/srtp/srtp_cipher_ctr.dart';
import 'package:webrtc_dart/src/srtp/key_derivation.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';
import 'package:webrtc_dart/src/srtp/rtcp_packet.dart';

// Helper functions for test vectors
Uint8List fromHex(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < result.length; i++) {
    result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return result;
}

String toHex(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

void main() {
  group('SrtpCipherCtr', () {
    late Uint8List masterKey;
    late Uint8List masterSalt;

    setUp(() {
      // 16-byte master key for AES-128
      masterKey = Uint8List.fromList([
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

      // 14-byte master salt for HMAC-SHA1
      masterSalt = Uint8List.fromList([
        0x10,
        0x11,
        0x12,
        0x13,
        0x14,
        0x15,
        0x16,
        0x17,
        0x18,
        0x19,
        0x1a,
        0x1b,
        0x1c,
        0x1d,
      ]);
    });

    test('construction from master key', () {
      final cipher = SrtpCipherCtr.fromMasterKey(
        masterKey: masterKey,
        masterSalt: masterSalt,
      );

      expect(cipher.srtpSessionKey, isNotEmpty);
      expect(cipher.srtpSessionSalt, isNotEmpty);
      expect(cipher.srtpSessionAuthKey, isNotEmpty);
      expect(cipher.srtcpSessionKey, isNotEmpty);
      expect(cipher.srtcpSessionSalt, isNotEmpty);
      expect(cipher.srtcpSessionAuthKey, isNotEmpty);
    });

    test('authTagLength is 10 bytes (HMAC-SHA1-80)', () {
      expect(SrtpCipherCtr.authTagLength, equals(10));
    });

    test('srtcpIndexLength is 4 bytes', () {
      expect(SrtpCipherCtr.srtcpIndexLength, equals(4));
    });

    group('SRTP encryption/decryption', () {
      test('encrypts and decrypts RTP packet roundtrip', () {
        final cipher = SrtpCipherCtr.fromMasterKey(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final packet = RtpPacket(
          payloadType: 96,
          sequenceNumber: 1234,
          timestamp: 567890,
          ssrc: 0x12345678,
          payload: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        );

        final encrypted = cipher.encryptRtp(packet);

        // Encrypted packet should be larger (auth tag added)
        expect(encrypted.length, equals(packet.serialize().length + 10));

        // Create a second cipher for decryption (simulating remote peer)
        final decryptCipher = SrtpCipherCtr.fromMasterKey(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final decrypted = decryptCipher.decryptSrtp(encrypted);

        expect(decrypted.payloadType, equals(packet.payloadType));
        expect(decrypted.sequenceNumber, equals(packet.sequenceNumber));
        expect(decrypted.timestamp, equals(packet.timestamp));
        expect(decrypted.ssrc, equals(packet.ssrc));
        expect(decrypted.payload, equals(packet.payload));
      });

      test('encrypts and decrypts packet with empty payload', () {
        final cipher = SrtpCipherCtr.fromMasterKey(
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

        final encrypted = cipher.encryptRtp(packet);

        final decryptCipher = SrtpCipherCtr.fromMasterKey(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );
        final decrypted = decryptCipher.decryptSrtp(encrypted);

        expect(decrypted.payload, isEmpty);
        expect(decrypted.ssrc, equals(packet.ssrc));
      });

      test('encrypts packets with different sequence numbers', () {
        final cipher = SrtpCipherCtr.fromMasterKey(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final payload = Uint8List.fromList([0xAA, 0xBB, 0xCC]);

        final packet1 = RtpPacket(
          payloadType: 96,
          sequenceNumber: 100,
          timestamp: 1000,
          ssrc: 0x11111111,
          payload: payload,
        );

        final packet2 = RtpPacket(
          payloadType: 96,
          sequenceNumber: 101,
          timestamp: 2000,
          ssrc: 0x11111111,
          payload: payload,
        );

        final encrypted1 = cipher.encryptRtp(packet1);
        final encrypted2 = cipher.encryptRtp(packet2);

        // Same payload but different encrypted data due to different sequence numbers
        expect(encrypted1, isNot(equals(encrypted2)));
      });

      test('throws on packet too short for decryption', () {
        final cipher = SrtpCipherCtr.fromMasterKey(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        // Less than 12 (header) + 10 (auth tag) = 22 bytes
        final shortPacket = Uint8List(20);
        shortPacket[0] = 0x80; // RTP version 2

        expect(
          () => cipher.decryptSrtp(shortPacket),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('SRTCP encryption/decryption', () {
      test('encrypts and decrypts RTCP packet roundtrip', () {
        final cipher = SrtpCipherCtr.fromMasterKey(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final payload = Uint8List.fromList([1, 2, 3, 4]);
        final packet = RtcpPacket(
          packetType: RtcpPacketType.receiverReport,
          reportCount: 0,
          length: 1 + (payload.length ~/ 4), // header words + payload words
          ssrc: 0x12345678,
          payload: payload,
        );

        final encrypted = cipher.encryptRtcp(packet);

        // Encrypted should include: header(8) + encrypted_payload + index(4) + auth(10)
        expect(encrypted.length, equals(8 + 4 + 4 + 10));

        final decryptCipher = SrtpCipherCtr.fromMasterKey(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final decrypted = decryptCipher.decryptSrtcp(encrypted);

        expect(decrypted.packetType, equals(packet.packetType));
        expect(decrypted.ssrc, equals(packet.ssrc));
        expect(decrypted.payload, equals(packet.payload));
      });

      test('encrypts and decrypts empty RTCP (22-byte minimum)', () {
        final cipher = SrtpCipherCtr.fromMasterKey(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        // Empty Receiver Report - this is what browsers send
        final packet = RtcpPacket(
          packetType: RtcpPacketType.receiverReport,
          reportCount: 0,
          length: 1, // Just SSRC, no report blocks
          ssrc: 0xAABBCCDD,
          payload: Uint8List(0),
        );

        final encrypted = cipher.encryptRtcp(packet);

        // Minimum SRTCP: 8 (header) + 0 (payload) + 4 (index) + 10 (auth) = 22 bytes
        expect(encrypted.length, equals(22));

        final decryptCipher = SrtpCipherCtr.fromMasterKey(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final decrypted = decryptCipher.decryptSrtcp(encrypted);

        expect(decrypted.packetType, equals(RtcpPacketType.receiverReport));
        expect(decrypted.ssrc, equals(0xAABBCCDD));
        expect(decrypted.payload, isEmpty);
      });

      test('decrypts 22-byte SRTCP packet (browser minimum)', () {
        final cipher = SrtpCipherCtr.fromMasterKey(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        // Create and encrypt an empty RR
        final packet = RtcpPacket(
          packetType: RtcpPacketType.receiverReport,
          reportCount: 0,
          length: 1,
          ssrc: 0x12345678,
          payload: Uint8List(0),
        );

        final encrypted = cipher.encryptRtcp(packet);
        expect(encrypted.length, equals(22));

        // Verify it can be decrypted
        final decryptCipher = SrtpCipherCtr.fromMasterKey(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        expect(() => decryptCipher.decryptSrtcp(encrypted), returnsNormally);
      });

      test('throws on SRTCP packet shorter than 22 bytes', () {
        final cipher = SrtpCipherCtr.fromMasterKey(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        // 21 bytes - one less than minimum
        final shortPacket = Uint8List(21);
        shortPacket[0] = 0x80; // RTP version 2
        shortPacket[1] = 201; // RR type

        expect(
          () => cipher.decryptSrtcp(shortPacket),
          throwsA(isA<FormatException>()),
        );
      });

      test('encrypted packet has E-flag set', () {
        final cipher = SrtpCipherCtr.fromMasterKey(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final payload = Uint8List(20);
        final packet = RtcpPacket(
          packetType: RtcpPacketType.senderReport,
          reportCount: 0,
          length: 1 + (payload.length ~/ 4),
          ssrc: 0x11111111,
          payload: payload,
        );

        final encrypted = cipher.encryptRtcp(packet);

        // E-flag is MSB of the 4-byte index before auth tag
        final indexOffset = encrypted.length - 14; // 4 index + 10 auth
        final eFlag = encrypted[indexOffset] & 0x80;
        expect(eFlag, equals(0x80));
      });
    });

    group('reset', () {
      test('reset clears internal state', () {
        final cipher = SrtpCipherCtr.fromMasterKey(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        // Encrypt some packets to advance state
        for (var i = 0; i < 10; i++) {
          cipher.encryptRtp(RtpPacket(
            payloadType: 96,
            sequenceNumber: i,
            timestamp: i * 1000,
            ssrc: 0x12345678,
            payload: Uint8List.fromList([i]),
          ));
        }

        // Reset
        cipher.reset();

        // After reset, should be able to start fresh
        final packet = RtpPacket(
          payloadType: 96,
          sequenceNumber: 0,
          timestamp: 0,
          ssrc: 0x12345678,
          payload: Uint8List.fromList([0]),
        );

        expect(() => cipher.encryptRtp(packet), returnsNormally);
      });
    });

    group('different SSRCs', () {
      test('handles multiple SSRCs independently', () {
        final cipher = SrtpCipherCtr.fromMasterKey(
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

        final encrypted1 = cipher.encryptRtp(packet1);
        final encrypted2 = cipher.encryptRtp(packet2);

        // Different SSRCs should produce different ciphertexts
        expect(encrypted1, isNot(equals(encrypted2)));
      });
    });

    group('sequence number rollover', () {
      test('handles sequence number wrap-around', () {
        final cipher = SrtpCipherCtr.fromMasterKey(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        // Simulate near wrap-around
        final packet1 = RtpPacket(
          payloadType: 96,
          sequenceNumber: 65534,
          timestamp: 1000,
          ssrc: 0x12345678,
          payload: Uint8List.fromList([1]),
        );

        final packet2 = RtpPacket(
          payloadType: 96,
          sequenceNumber: 65535,
          timestamp: 2000,
          ssrc: 0x12345678,
          payload: Uint8List.fromList([2]),
        );

        final packet3 = RtpPacket(
          payloadType: 96,
          sequenceNumber: 0, // Wrapped around
          timestamp: 3000,
          ssrc: 0x12345678,
          payload: Uint8List.fromList([3]),
        );

        // All should encrypt successfully
        expect(() => cipher.encryptRtp(packet1), returnsNormally);
        expect(() => cipher.encryptRtp(packet2), returnsNormally);
        expect(() => cipher.encryptRtp(packet3), returnsNormally);
      });
    });

    group('werift test vectors', () {
      // Test vectors from werift-webrtc
      // These ensure byte-for-byte compatibility with TypeScript implementation
      final weriftMasterKey = fromHex('000102030405060708090a0b0c0d0e0f');
      final weriftMasterSalt = fromHex('101112131415161718191a1b1c1d');

      test('key derivation matches werift', () {
        final srtpKeys = SrtpKeyDerivation.deriveSrtpKeys(
          masterKey: weriftMasterKey,
          masterSalt: weriftMasterSalt,
          ssrc: 0,
          index: 0,
        );

        final srtcpKeys = SrtpKeyDerivation.deriveSrtcpKeys(
          masterKey: weriftMasterKey,
          masterSalt: weriftMasterSalt,
          ssrc: 0,
          index: 0,
        );

        // Expected values from werift
        expect(toHex(srtpKeys.encryptionKey),
            equals('7e52987945787ea107d93f0d54631a6f'));
        expect(
            toHex(srtpKeys.saltingKey), equals('117507eab2655d2c31d1b1b3c454'));
        expect(toHex(srtpKeys.authenticationKey),
            equals('d407ce49f85990a04c3fb0b59c3e86dc951517aa'));

        expect(toHex(srtcpKeys.encryptionKey),
            equals('f8ac41338c7ab44cdc8cb12b20e86b02'));
        expect(toHex(srtcpKeys.saltingKey),
            equals('be6407ed97368d97c7db5058a77a'));
        expect(toHex(srtcpKeys.authenticationKey),
            equals('97b9c69bc7f4482d8e1c4bd2379e5659f20783a8'));
      });

      test('RTP encryption matches werift', () {
        final cipher = SrtpCipherCtr.fromMasterKey(
          masterKey: weriftMasterKey,
          masterSalt: weriftMasterSalt,
        );

        // RTP packet from werift test
        final packet = RtpPacket(
          payloadType: 15,
          sequenceNumber: 0x1234,
          timestamp: 0xdecafbad,
          ssrc: 0xcafebabe,
          payload: fromHex('abababababababababababababababab'),
        );

        final encrypted = cipher.encryptRtp(packet);
        final expectedEncrypted =
            '800f1234decafbadcafebabec8f5e0214236e5fde9cbd62d47b0a0914abc4786f3c58a32060f';

        expect(toHex(encrypted), equals(expectedEncrypted));
      });

      test('RTCP encryption matches werift', () {
        final cipher = SrtpCipherCtr.fromMasterKey(
          masterKey: weriftMasterKey,
          masterSalt: weriftMasterSalt,
        );

        // RTCP Sender Report from werift test
        final packet = RtcpPacket(
          packetType: RtcpPacketType.senderReport,
          reportCount: 1,
          length: 5,
          ssrc: 0xcafebabe,
          payload: fromHex('abababababababababababababababab'),
        );

        final encrypted = cipher.encryptRtcp(packet);
        final expectedEncrypted =
            '81c80005cafebabe2dcbd1a0f763810879d398df743f4f7d80000001ddc57f60c3485f92e761';

        expect(toHex(encrypted), equals(expectedEncrypted));
      });

      test('decryption roundtrip matches werift', () {
        final encryptCipher = SrtpCipherCtr.fromMasterKey(
          masterKey: weriftMasterKey,
          masterSalt: weriftMasterSalt,
        );

        final decryptCipher = SrtpCipherCtr.fromMasterKey(
          masterKey: weriftMasterKey,
          masterSalt: weriftMasterSalt,
        );

        // RTP roundtrip
        final rtpPacket = RtpPacket(
          payloadType: 15,
          sequenceNumber: 0x1234,
          timestamp: 0xdecafbad,
          ssrc: 0xcafebabe,
          payload: fromHex('abababababababababababababababab'),
        );

        final encryptedRtp = encryptCipher.encryptRtp(rtpPacket);
        final decryptedRtp = decryptCipher.decryptSrtp(encryptedRtp);

        expect(toHex(decryptedRtp.payload), equals(toHex(rtpPacket.payload)));
      });
    });
  });
}
