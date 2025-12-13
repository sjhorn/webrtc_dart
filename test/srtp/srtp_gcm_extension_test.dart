import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/srtp/srtp_cipher.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';

/// Regression tests for AES-GCM SRTP with RTP extension headers
///
/// Bug discovered: December 11, 2025 during Ring camera integration
///
/// Root cause: The GCM cipher's _serializeHeader() wasn't including RTP
/// extension headers in the AAD (Additional Authenticated Data). This caused
/// GCM authentication to fail on the receiver side because:
/// - Sender AAD = header without extension
/// - Receiver AAD = header with extension (from packet bytes)
/// - Auth tag mismatch -> silent decryption failure
///
/// The fix was to use packet.serializeHeader() which correctly includes
/// extension headers in the AAD.
///
/// This test ensures we don't regress on this behavior.
void main() {
  group('SrtpCipher AES-GCM with RTP extensions', () {
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

    group('RTP extension header handling (Ring camera regression)', () {
      test('encrypts and decrypts packet with one-byte extension header',
          () async {
        // This simulates Ring camera packets which have transport-cc extension
        // Extension format: 0xBEDE profile (one-byte header)
        final cipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        // Create extension data in one-byte header format (0xBEDE profile)
        // Format: (id << 4) | (len-1), followed by payload bytes
        // Example: transport-cc with id=1, 2-byte payload
        final extensionData = Uint8List.fromList([
          0x11, // id=1, len=2 (len-1=1)
          0xAB, 0xCD, // 2-byte transport-cc sequence number
          0x00, // padding to 4-byte boundary
        ]);

        final packet = RtpPacket(
          payloadType: 96,
          sequenceNumber: 12345,
          timestamp: 0xDECAFBAD,
          ssrc: 0xCAFEBABE,
          extension: true,
          extensionHeader: RtpExtension(
            profile: 0xBEDE, // One-byte header extension profile
            data: extensionData,
          ),
          payload: Uint8List.fromList([
            0x7c, 0x81, // H264 FU-A start fragment
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
          ]),
        );

        // Verify packet has extension
        expect(packet.extension, isTrue);
        expect(packet.extensionHeader, isNotNull);
        expect(packet.extensionHeader!.profile, equals(0xBEDE));

        // Encrypt
        final encrypted = await cipher.encrypt(packet);

        // Encrypted size: header (12) + ext header (4) + ext data (4) + payload (10) + auth (16)
        expect(encrypted.length, equals(12 + 4 + 4 + 10 + 16));

        // Verify extension bit is set in encrypted packet
        expect(encrypted[0] & 0x10, equals(0x10),
            reason: 'Extension bit should be set');

        // Decrypt with fresh cipher
        final decryptCipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final decrypted = await decryptCipher.decrypt(encrypted);

        // Verify all fields match
        expect(decrypted.payloadType, equals(96));
        expect(decrypted.sequenceNumber, equals(12345));
        expect(decrypted.timestamp, equals(0xDECAFBAD));
        expect(decrypted.ssrc, equals(0xCAFEBABE));
        expect(decrypted.extension, isTrue);
        expect(decrypted.extensionHeader, isNotNull);
        expect(decrypted.extensionHeader!.profile, equals(0xBEDE));
        expect(decrypted.extensionHeader!.data, equals(extensionData));
        expect(decrypted.payload, equals(packet.payload));
      });

      test('encrypts and decrypts packet with mid extension', () async {
        // This simulates browser-bound packets with mid extension
        // Mid extension: id=1, value="1" (ASCII 0x31)
        final cipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        // Mid extension: (1 << 4) | 0 = 0x10, followed by "1" (0x31)
        final midExtensionData = Uint8List.fromList([
          0x10, // id=1, len=1
          0x31, // "1" in ASCII
          0x00, 0x00, // padding
        ]);

        final packet = RtpPacket(
          payloadType: 96,
          sequenceNumber: 100,
          timestamp: 90000,
          ssrc: 0x12345678,
          marker: true,
          extension: true,
          extensionHeader: RtpExtension(
            profile: 0xBEDE,
            data: midExtensionData,
          ),
          payload: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        );

        final encrypted = await cipher.encrypt(packet);

        // Verify marker bit preserved
        expect(encrypted[1] & 0x80, equals(0x80),
            reason: 'Marker bit should be set');

        final decryptCipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final decrypted = await decryptCipher.decrypt(encrypted);

        expect(decrypted.marker, isTrue);
        expect(decrypted.extension, isTrue);
        expect(decrypted.extensionHeader!.data, equals(midExtensionData));
      });

      test('different extension data produces different ciphertext', () async {
        // Verifies that extension data is actually included in AAD
        final cipher1 =
            SrtpCipher(masterKey: masterKey, masterSalt: masterSalt);
        final cipher2 =
            SrtpCipher(masterKey: masterKey, masterSalt: masterSalt);

        final basePacket = RtpPacket(
          payloadType: 96,
          sequenceNumber: 1,
          timestamp: 1000,
          ssrc: 0xAABBCCDD,
          extension: true,
          extensionHeader: RtpExtension(
            profile: 0xBEDE,
            data: Uint8List.fromList([0x10, 0x31, 0x00, 0x00]),
          ),
          payload: Uint8List.fromList([1, 2, 3, 4]),
        );

        final modifiedPacket = RtpPacket(
          payloadType: 96,
          sequenceNumber: 1,
          timestamp: 1000,
          ssrc: 0xAABBCCDD,
          extension: true,
          extensionHeader: RtpExtension(
            profile: 0xBEDE,
            data: Uint8List.fromList(
                [0x10, 0x32, 0x00, 0x00]), // Different: "2" vs "1"
          ),
          payload: Uint8List.fromList([1, 2, 3, 4]),
        );

        final encrypted1 = await cipher1.encrypt(basePacket);
        final encrypted2 = await cipher2.encrypt(modifiedPacket);

        // Different extension data should produce different ciphertext
        // because extension is part of AAD
        expect(encrypted1, isNot(equals(encrypted2)));
      });

      test('tampered extension causes decryption failure', () async {
        // This is the critical test - if extension is not in AAD,
        // tampering won't be detected
        final encryptCipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final packet = RtpPacket(
          payloadType: 96,
          sequenceNumber: 1,
          timestamp: 1000,
          ssrc: 0x12345678,
          extension: true,
          extensionHeader: RtpExtension(
            profile: 0xBEDE,
            data: Uint8List.fromList([0x10, 0x31, 0x00, 0x00]),
          ),
          payload: Uint8List.fromList([1, 2, 3, 4]),
        );

        final encrypted = await encryptCipher.encrypt(packet);

        // Tamper with extension data (byte 17 is extension data[1])
        // Header (12) + ext profile (2) + ext len (2) + ext data starts at 16
        final tampered = Uint8List.fromList(encrypted);
        tampered[17] = 0xFF; // Change extension data

        final decryptCipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        // Decryption should fail due to auth tag mismatch
        expect(
          () async => await decryptCipher.decrypt(tampered),
          throwsA(anything),
          reason: 'Tampered extension should cause auth failure',
        );
      });

      test('handles two-byte extension profile (0x1000)', () async {
        // Two-byte header extension profile
        final cipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        // Two-byte extension format: id (1 byte) + len (1 byte) + data
        final extensionData = Uint8List.fromList([
          0x01, // id=1
          0x02, // len=2
          0xAA, 0xBB, // data
        ]);

        final packet = RtpPacket(
          payloadType: 96,
          sequenceNumber: 500,
          timestamp: 45000,
          ssrc: 0xDEADBEEF,
          extension: true,
          extensionHeader: RtpExtension(
            profile: 0x1000, // Two-byte header profile
            data: extensionData,
          ),
          payload: Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]),
        );

        final encrypted = await cipher.encrypt(packet);

        final decryptCipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final decrypted = await decryptCipher.decrypt(encrypted);

        expect(decrypted.extension, isTrue);
        expect(decrypted.extensionHeader!.profile, equals(0x1000));
        expect(decrypted.extensionHeader!.data, equals(extensionData));
      });

      test('packet without extension still works', () async {
        // Ensure we didn't break non-extension packets
        final cipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final packet = RtpPacket(
          payloadType: 96,
          sequenceNumber: 1,
          timestamp: 1000,
          ssrc: 0x11111111,
          extension: false, // No extension
          payload: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        );

        expect(packet.extension, isFalse);

        final encrypted = await cipher.encrypt(packet);

        // No extension bit
        expect(encrypted[0] & 0x10, equals(0));

        final decryptCipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final decrypted = await decryptCipher.decrypt(encrypted);

        expect(decrypted.extension, isFalse);
        expect(decrypted.extensionHeader, isNull);
        expect(decrypted.payload, equals(packet.payload));
      });
    });

    group('RTP forwarding scenario (Ring → Browser)', () {
      test('simulates Ring packet forwarding with extension replacement',
          () async {
        // Simulates the Ring video forwarding scenario:
        // 1. Receive packet from Ring with transport-cc extension
        // 2. Replace extension with mid extension
        // 3. Encrypt with GCM for browser
        // 4. Browser decrypts successfully

        // Ring's original extension (transport-cc)
        final ringExtension = Uint8List.fromList([
          0x11, 0xAB, 0xCD, 0x00, // transport-cc id=1, seq=0xABCD
        ]);

        // Our mid extension to add
        final midExtension = Uint8List.fromList([
          0x10, 0x31, 0x00, 0x00, // mid id=1, value="1"
        ]);

        // Simulate Ring packet (incoming)
        final ringPacket = RtpPacket(
          payloadType: 96,
          sequenceNumber: 29692,
          timestamp: 837175688,
          ssrc: 0x89E390AF, // Ring's SSRC
          marker: false,
          extension: true,
          extensionHeader: RtpExtension(profile: 0xBEDE, data: ringExtension),
          payload: Uint8List.fromList([
            0x7c, 0x81, // H264 FU-A
            0x9a, 0x1c, 0x1c, 0x64, 0x9f, 0xbd,
          ]),
        );

        // Create browser-bound packet (replace extension, change SSRC)
        final browserPacket = RtpPacket(
          version: ringPacket.version,
          padding: ringPacket.padding,
          marker: ringPacket.marker,
          payloadType: 96,
          sequenceNumber: ringPacket.sequenceNumber,
          timestamp: ringPacket.timestamp,
          ssrc: 0x6420FA28, // Browser's SSRC from SDP
          csrcs: ringPacket.csrcs,
          extension: true,
          extensionHeader: RtpExtension(profile: 0xBEDE, data: midExtension),
          payload: ringPacket.payload,
        );

        // Encrypt for browser (GCM)
        final encryptCipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final encrypted = await encryptCipher.encrypt(browserPacket);

        // Verify structure
        expect(encrypted[0] & 0x10, equals(0x10), reason: 'Extension bit set');
        expect(encrypted[1] & 0x7F, equals(96),
            reason: 'Payload type preserved');

        // Browser decrypts
        final decryptCipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final decrypted = await decryptCipher.decrypt(encrypted);

        // Verify browser receives correct data
        expect(decrypted.ssrc, equals(0x6420FA28));
        expect(decrypted.sequenceNumber, equals(29692));
        expect(decrypted.extension, isTrue);
        expect(decrypted.extensionHeader!.data, equals(midExtension));
        expect(decrypted.payload, equals(ringPacket.payload));
      });

      test('multiple packets maintain sequence continuity', () async {
        final cipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final decryptCipher = SrtpCipher(
          masterKey: masterKey,
          masterSalt: masterSalt,
        );

        final midExtension = Uint8List.fromList([0x10, 0x31, 0x00, 0x00]);

        // Simulate forwarding multiple packets
        for (var seq = 0; seq < 10; seq++) {
          final packet = RtpPacket(
            payloadType: 96,
            sequenceNumber: seq,
            timestamp: seq * 3000,
            ssrc: 0x12345678,
            marker: seq % 3 == 2, // Marker every 3rd packet (frame boundary)
            extension: true,
            extensionHeader: RtpExtension(profile: 0xBEDE, data: midExtension),
            payload: Uint8List.fromList([seq, seq + 1, seq + 2, seq + 3]),
          );

          final encrypted = await cipher.encrypt(packet);
          final decrypted = await decryptCipher.decrypt(encrypted);

          expect(decrypted.sequenceNumber, equals(seq));
          expect(decrypted.marker, equals(seq % 3 == 2));
          expect(decrypted.payload[0], equals(seq));
        }
      });
    });
  });
}
