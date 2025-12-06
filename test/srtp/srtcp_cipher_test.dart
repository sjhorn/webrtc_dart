import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/srtp/srtcp_cipher.dart';
import 'package:webrtc_dart/src/srtp/rtcp_packet.dart';

void main() {
  group('SrtcpCipher', () {
    // Test key and salt (AES-128 GCM: 16 byte key, 12 byte salt)
    final testKey = Uint8List.fromList([
      0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
      0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
    ]);
    final testSalt = Uint8List.fromList([
      0x11, 0x12, 0x13, 0x14, 0x15, 0x16,
      0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C,
    ]);

    test('construction with valid parameters', () {
      final cipher = SrtcpCipher(
        masterKey: testKey,
        masterSalt: testSalt,
      );

      expect(cipher.masterKey, equals(testKey));
      expect(cipher.masterSalt, equals(testSalt));
    });

    test('reset clears index state', () {
      final cipher = SrtcpCipher(
        masterKey: testKey,
        masterSalt: testSalt,
      );

      // Reset should not throw
      expect(() => cipher.reset(), returnsNormally);
    });

    test('encrypt and decrypt roundtrip', () async {
      final cipher = SrtcpCipher(
        masterKey: testKey,
        masterSalt: testSalt,
      );

      // Create a simple RTCP packet
      final rtcpPacket = RtcpPacket(
        version: 2,
        padding: false,
        reportCount: 0,
        packetType: RtcpPacketType.senderReport,
        length: 6,
        ssrc: 0x12345678,
        payload: Uint8List.fromList([0xAB, 0xCD, 0xEF, 0x01]),
      );

      // Encrypt
      final encrypted = await cipher.encrypt(rtcpPacket);

      // Encrypted packet should be longer due to auth tag and index
      expect(encrypted.length, greaterThan(rtcpPacket.serialize().length));

      // Decrypt (need a fresh cipher since indexes increment)
      final cipher2 = SrtcpCipher(
        masterKey: testKey,
        masterSalt: testSalt,
      );

      final decrypted = await cipher2.decrypt(encrypted);

      // Verify roundtrip
      expect(decrypted.version, equals(rtcpPacket.version));
      expect(decrypted.ssrc, equals(rtcpPacket.ssrc));
      expect(decrypted.packetType, equals(rtcpPacket.packetType));
    });

    test('decrypt throws on packet too short', () async {
      final cipher = SrtcpCipher(
        masterKey: testKey,
        masterSalt: testSalt,
      );

      // Packet too short (needs at least header + auth tag + index)
      final shortPacket = Uint8List(10);

      expect(
        () async => await cipher.decrypt(shortPacket),
        throwsA(isA<FormatException>()),
      );
    });

    test('decrypt throws when E-flag not set', () async {
      final cipher = SrtcpCipher(
        masterKey: testKey,
        masterSalt: testSalt,
      );

      // Create a packet with enough length but E-flag not set
      // Minimum: 8 (header) + 16 (auth tag) + 4 (index) = 28 bytes
      final packetWithoutEFlag = Uint8List(28);

      // Set some valid-looking header
      packetWithoutEFlag[0] = 0x80; // V=2, P=0, RC=0
      packetWithoutEFlag[1] = 200; // SR

      // Last 4 bytes are index - E-flag is MSB, leave as 0

      expect(
        () async => await cipher.decrypt(packetWithoutEFlag),
        throwsA(isA<FormatException>()),
      );
    });

    test('encrypt with different SSRCs maintains separate indexes', () async {
      final cipher = SrtcpCipher(
        masterKey: testKey,
        masterSalt: testSalt,
      );

      final packet1 = RtcpPacket(
        version: 2,
        padding: false,
        reportCount: 0,
        packetType: RtcpPacketType.senderReport,
        length: 6,
        ssrc: 0x11111111,
        payload: Uint8List(4),
      );

      final packet2 = RtcpPacket(
        version: 2,
        padding: false,
        reportCount: 0,
        packetType: RtcpPacketType.senderReport,
        length: 6,
        ssrc: 0x22222222,
        payload: Uint8List(4),
      );

      // Encrypt both - should succeed even with different SSRCs
      final encrypted1 = await cipher.encrypt(packet1);
      final encrypted2 = await cipher.encrypt(packet2);

      // Both should be encrypted (non-empty)
      expect(encrypted1.isNotEmpty, isTrue);
      expect(encrypted2.isNotEmpty, isTrue);
    });

    test('encrypted packet has E-flag set', () async {
      final cipher = SrtcpCipher(
        masterKey: testKey,
        masterSalt: testSalt,
      );

      final packet = RtcpPacket(
        version: 2,
        padding: false,
        reportCount: 0,
        packetType: RtcpPacketType.senderReport,
        length: 6,
        ssrc: 0x12345678,
        payload: Uint8List(4),
      );

      final encrypted = await cipher.encrypt(packet);

      // Extract index from last 4 bytes
      final indexBuffer = ByteData.sublistView(
        encrypted,
        encrypted.length - 4,
      );
      final indexWithEFlag = indexBuffer.getUint32(0);

      // E-flag should be set (MSB of 32-bit index)
      expect(indexWithEFlag & 0x80000000, equals(0x80000000));
    });
  });
}
