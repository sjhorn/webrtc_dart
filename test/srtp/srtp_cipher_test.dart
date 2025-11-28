import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/srtp/srtp_cipher.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';

void main() {
  group('SrtpCipher', () {
    test('encrypts and decrypts RTP packet', () async {
      // Generate test keys
      final masterKey = Uint8List.fromList(List.generate(16, (i) => i));
      final masterSalt = Uint8List.fromList(List.generate(12, (i) => i + 16));

      final cipher = SrtpCipher(
        masterKey: masterKey,
        masterSalt: masterSalt,
      );

      // Create test RTP packet
      final payload = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final packet = RtpPacket(
        payloadType: 96,
        sequenceNumber: 100,
        timestamp: 1000,
        ssrc: 0x12345678,
        payload: payload,
      );

      // Encrypt
      final encrypted = await cipher.encrypt(packet);

      // Encrypted packet should be larger (includes auth tag)
      expect(encrypted.length, greaterThan(packet.serialize().length));

      // Decrypt
      final decrypted = await cipher.decrypt(encrypted);

      // Verify decrypted packet matches original
      expect(decrypted.payloadType, packet.payloadType);
      expect(decrypted.sequenceNumber, packet.sequenceNumber);
      expect(decrypted.timestamp, packet.timestamp);
      expect(decrypted.ssrc, packet.ssrc);
      expect(decrypted.payload, equals(payload));
    });

    test('detects replay attacks', () async {
      final masterKey = Uint8List.fromList(List.generate(16, (i) => i));
      final masterSalt = Uint8List.fromList(List.generate(12, (i) => i + 16));

      final cipher = SrtpCipher(
        masterKey: masterKey,
        masterSalt: masterSalt,
      );

      // Create and encrypt first packet
      final packet1 = RtpPacket(
        payloadType: 96,
        sequenceNumber: 100,
        timestamp: 1000,
        ssrc: 0x12345678,
        payload: Uint8List(10),
      );

      final encrypted1 = await cipher.encrypt(packet1);

      // Decrypt once - should succeed
      final decrypted1 = await cipher.decrypt(encrypted1);
      expect(decrypted1.sequenceNumber, 100);

      // Try to decrypt same packet again - should fail (replay)
      expect(
        () async => await cipher.decrypt(encrypted1),
        throwsA(isA<StateError>()),
      );
    });

    test('handles multiple SSRCs independently', () async {
      final masterKey = Uint8List.fromList(List.generate(16, (i) => i));
      final masterSalt = Uint8List.fromList(List.generate(12, (i) => i + 16));

      final cipher = SrtpCipher(
        masterKey: masterKey,
        masterSalt: masterSalt,
      );

      // Create packets with different SSRCs
      final packet1 = RtpPacket(
        payloadType: 96,
        sequenceNumber: 100,
        timestamp: 1000,
        ssrc: 0x11111111,
        payload: Uint8List.fromList([1, 2, 3]),
      );

      final packet2 = RtpPacket(
        payloadType: 96,
        sequenceNumber: 200,
        timestamp: 2000,
        ssrc: 0x22222222,
        payload: Uint8List.fromList([4, 5, 6]),
      );

      // Encrypt both
      final encrypted1 = await cipher.encrypt(packet1);
      final encrypted2 = await cipher.encrypt(packet2);

      // Decrypt both - should work independently
      final decrypted1 = await cipher.decrypt(encrypted1);
      final decrypted2 = await cipher.decrypt(encrypted2);

      expect(decrypted1.ssrc, 0x11111111);
      expect(decrypted2.ssrc, 0x22222222);
      expect(decrypted1.payload, equals([1, 2, 3]));
      expect(decrypted2.payload, equals([4, 5, 6]));
    });

    test('resets state correctly', () async {
      final masterKey = Uint8List.fromList(List.generate(16, (i) => i));
      final masterSalt = Uint8List.fromList(List.generate(12, (i) => i + 16));

      final cipher = SrtpCipher(
        masterKey: masterKey,
        masterSalt: masterSalt,
      );

      // Encrypt a packet
      final packet = RtpPacket(
        payloadType: 96,
        sequenceNumber: 100,
        timestamp: 1000,
        ssrc: 0x12345678,
        payload: Uint8List(10),
      );

      final encrypted = await cipher.encrypt(packet);
      await cipher.decrypt(encrypted);

      // Reset
      cipher.reset();

      // Should be able to decrypt same packet again after reset
      final decrypted = await cipher.decrypt(encrypted);
      expect(decrypted.sequenceNumber, 100);
    });

    test('handles packets with CSRCs', () async {
      final masterKey = Uint8List.fromList(List.generate(16, (i) => i));
      final masterSalt = Uint8List.fromList(List.generate(12, (i) => i + 16));

      final cipher = SrtpCipher(
        masterKey: masterKey,
        masterSalt: masterSalt,
      );

      // Create packet with CSRCs
      final packet = RtpPacket(
        payloadType: 96,
        sequenceNumber: 100,
        timestamp: 1000,
        ssrc: 0x12345678,
        csrcs: [0xAAAAAAAA, 0xBBBBBBBB],
        payload: Uint8List(20),
      );

      final encrypted = await cipher.encrypt(packet);
      final decrypted = await cipher.decrypt(encrypted);

      expect(decrypted.csrcs.length, 2);
      expect(decrypted.csrcs[0], 0xAAAAAAAA);
      expect(decrypted.csrcs[1], 0xBBBBBBBB);
    });
  });
}
