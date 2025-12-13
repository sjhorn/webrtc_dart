// SRTP Cipher Comparison Tool
// Compares Dart SRTP cipher output against werift test vectors
//
// Run: dart run interop/srtp_cipher_compare.dart
//
// GCM Test Vectors from Node.js (srtp_cipher_vectors.mjs):
// - SRTP Session Key: 077c6143cb221bc355ff23d5f984a16e
// - SRTP Session Salt: 9af3e95364ebac9c99c5a7c40169
// - SRTCP Session Key: 615dcd9042600666f6fd4d9e4fe4519f
// - SRTCP Session Salt: fcca937b9112a500dac722691f9e
// - Encrypted SRTCP: 80c90001cafebabeeaecc2c438ea2e58439ea0841a4a2e8d80000000

import 'dart:typed_data';
import 'package:webrtc_dart/src/srtp/srtp_cipher_ctr.dart';
import 'package:webrtc_dart/src/srtp/srtcp_cipher.dart';
import 'package:webrtc_dart/src/srtp/key_derivation.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';
import 'package:webrtc_dart/src/srtp/rtcp_packet.dart';

// Helper to convert hex string to Uint8List
Uint8List fromHex(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < result.length; i++) {
    result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return result;
}

// Helper to convert Uint8List to hex string
String toHex(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Future<void> main() async {
  print('=== SRTP Cipher Comparison: Dart vs werift ===\n');

  // CTR Mode Test Vectors from werift
  const masterKeyHex = '000102030405060708090a0b0c0d0e0f';
  const masterSaltHex = '101112131415161718191a1b1c1d';

  // Session keys derived by werift
  const expectedSrtpKey = '7e52987945787ea107d93f0d54631a6f';
  const expectedSrtpSalt = '117507eab2655d2c31d1b1b3c454';
  const expectedSrtpAuth = 'd407ce49f85990a04c3fb0b59c3e86dc951517aa';
  const expectedSrtcpKey = 'f8ac41338c7ab44cdc8cb12b20e86b02';
  const expectedSrtcpSalt = 'be6407ed97368d97c7db5058a77a';
  const expectedSrtcpAuth = '97b9c69bc7f4482d8e1c4bd2379e5659f20783a8';

  // RTP test vectors
  const rtpPlaintextHex =
      '800f1234decafbadcafebabeabababababababababababababababab';
  const expectedRtpEncrypted =
      '800f1234decafbadcafebabec8f5e0214236e5fde9cbd62d47b0a0914abc4786f3c58a32060f';

  // RTCP test vectors
  const rtcpPlaintextHex = '81c80005cafebabeabababababababababababababababab';
  const expectedRtcpEncrypted =
      '81c80005cafebabe2dcbd1a0f763810879d398df743f4f7d80000001ddc57f60c3485f92e761';

  print('--- CTR Mode (AES-128-CM-HMAC-SHA1-80) ---\n');

  final masterKey = fromHex(masterKeyHex);
  final masterSalt = fromHex(masterSaltHex);

  print('Input:');
  print('  masterKey: $masterKeyHex');
  print('  masterSalt: $masterSaltHex');
  print('');

  // Test key derivation
  print('Key Derivation Comparison:');

  final srtpKeys = SrtpKeyDerivation.deriveSrtpKeys(
    masterKey: masterKey,
    masterSalt: masterSalt,
    ssrc: 0,
    index: 0,
  );

  final srtcpKeys = SrtpKeyDerivation.deriveSrtcpKeys(
    masterKey: masterKey,
    masterSalt: masterSalt,
    ssrc: 0,
    index: 0,
  );

  final actualSrtpKey = toHex(srtpKeys.encryptionKey);
  print('  srtpSessionKey:');
  print('    expected: $expectedSrtpKey');
  print('    actual:   $actualSrtpKey');
  print('    match: ${expectedSrtpKey == actualSrtpKey ? '✓' : '✗'}');

  final actualSrtpSalt = toHex(srtpKeys.saltingKey);
  print('  srtpSessionSalt:');
  print('    expected: $expectedSrtpSalt');
  print('    actual:   $actualSrtpSalt');
  print('    match: ${expectedSrtpSalt == actualSrtpSalt ? '✓' : '✗'}');

  final actualSrtpAuth = toHex(srtpKeys.authenticationKey);
  print('  srtpSessionAuthTag:');
  print('    expected: $expectedSrtpAuth');
  print('    actual:   $actualSrtpAuth');
  print('    match: ${expectedSrtpAuth == actualSrtpAuth ? '✓' : '✗'}');

  final actualSrtcpKey = toHex(srtcpKeys.encryptionKey);
  print('  srtcpSessionKey:');
  print('    expected: $expectedSrtcpKey');
  print('    actual:   $actualSrtcpKey');
  print('    match: ${expectedSrtcpKey == actualSrtcpKey ? '✓' : '✗'}');

  final actualSrtcpSalt = toHex(srtcpKeys.saltingKey);
  print('  srtcpSessionSalt:');
  print('    expected: $expectedSrtcpSalt');
  print('    actual:   $actualSrtcpSalt');
  print('    match: ${expectedSrtcpSalt == actualSrtcpSalt ? '✓' : '✗'}');

  final actualSrtcpAuth = toHex(srtcpKeys.authenticationKey);
  print('  srtcpSessionAuthTag:');
  print('    expected: $expectedSrtcpAuth');
  print('    actual:   $actualSrtcpAuth');
  print('    match: ${expectedSrtcpAuth == actualSrtcpAuth ? '✓' : '✗'}');
  print('');

  // Test RTP encryption with SrtpCipherCtr
  print('RTP Encryption Comparison (CTR):');

  final cipher = SrtpCipherCtr.fromMasterKey(
    masterKey: masterKey,
    masterSalt: masterSalt,
  );

  // Parse the plaintext RTP packet
  final rtpPlaintext = fromHex(rtpPlaintextHex);
  final rtpPacket = RtpPacket.parse(rtpPlaintext);

  print('  RTP Packet:');
  print('    payloadType: ${rtpPacket.payloadType}');
  print('    sequenceNumber: ${rtpPacket.sequenceNumber}');
  print('    timestamp: ${rtpPacket.timestamp}');
  print('    ssrc: 0x${rtpPacket.ssrc.toRadixString(16)}');
  print('    payload: ${toHex(rtpPacket.payload)}');
  print('');

  final encryptedRtp = cipher.encryptRtp(rtpPacket);

  final actualRtpEncrypted = toHex(encryptedRtp);
  print('  encrypted:');
  print('    expected: $expectedRtpEncrypted');
  print('    actual:   $actualRtpEncrypted');
  print('    match: ${expectedRtpEncrypted == actualRtpEncrypted ? '✓' : '✗'}');
  print('    expected length: ${expectedRtpEncrypted.length ~/ 2}');
  print('    actual length: ${encryptedRtp.length}');
  print('');

  // Test RTCP encryption
  print('RTCP Encryption Comparison (CTR):');

  final cipher2 = SrtpCipherCtr.fromMasterKey(
    masterKey: masterKey,
    masterSalt: masterSalt,
  );

  // Parse the plaintext RTCP packet
  final rtcpPlaintext = fromHex(rtcpPlaintextHex);
  final rtcpPacket = RtcpPacket.parse(rtcpPlaintext);

  print('  RTCP Packet:');
  print('    packetType: ${rtcpPacket.packetType}');
  print('    reportCount: ${rtcpPacket.reportCount}');
  print('    ssrc: 0x${rtcpPacket.ssrc.toRadixString(16)}');
  print('    payload: ${toHex(rtcpPacket.payload)}');
  print('');

  final encryptedRtcp = cipher2.encryptRtcp(rtcpPacket);

  final actualRtcpEncrypted = toHex(encryptedRtcp);
  print('  encrypted:');
  print('    expected: $expectedRtcpEncrypted');
  print('    actual:   $actualRtcpEncrypted');
  print(
      '    match: ${expectedRtcpEncrypted == actualRtcpEncrypted ? '✓' : '✗'}');
  print('    expected length: ${expectedRtcpEncrypted.length ~/ 2}');
  print('    actual length: ${encryptedRtcp.length}');
  print('');

  // Test decryption roundtrip
  print('Decryption Roundtrip Test:');

  final cipher3 = SrtpCipherCtr.fromMasterKey(
    masterKey: masterKey,
    masterSalt: masterSalt,
  );

  final decryptedRtp = cipher3.decryptSrtp(encryptedRtp);
  print('  RTP roundtrip:');
  print('    original payload: ${toHex(rtpPacket.payload)}');
  print('    decrypted payload: ${toHex(decryptedRtp.payload)}');
  print(
      '    match: ${toHex(rtpPacket.payload) == toHex(decryptedRtp.payload) ? '✓' : '✗'}');

  final cipher4 = SrtpCipherCtr.fromMasterKey(
    masterKey: masterKey,
    masterSalt: masterSalt,
  );

  final decryptedRtcp = cipher4.decryptSrtcp(encryptedRtcp);
  print('  RTCP roundtrip:');
  print('    original payload: ${toHex(rtcpPacket.payload)}');
  print('    decrypted payload: ${toHex(decryptedRtcp.payload)}');
  print(
      '    match: ${toHex(rtcpPacket.payload) == toHex(decryptedRtcp.payload) ? '✓' : '✗'}');
  print('');

  // Summary
  print('=== Summary ===');

  final keyDerivationMatch = expectedSrtpKey == actualSrtpKey &&
      expectedSrtpSalt == actualSrtpSalt &&
      expectedSrtpAuth == actualSrtpAuth &&
      expectedSrtcpKey == actualSrtcpKey &&
      expectedSrtcpSalt == actualSrtcpSalt &&
      expectedSrtcpAuth == actualSrtcpAuth;

  final rtpEncryptionMatch = expectedRtpEncrypted == actualRtpEncrypted;
  final rtcpEncryptionMatch = expectedRtcpEncrypted == actualRtcpEncrypted;

  print('Key Derivation: ${keyDerivationMatch ? '✓ PASS' : '✗ FAIL'}');
  print('RTP Encryption: ${rtpEncryptionMatch ? '✓ PASS' : '✗ FAIL'}');
  print('RTCP Encryption: ${rtcpEncryptionMatch ? '✓ PASS' : '✗ FAIL'}');
  print('');

  if (keyDerivationMatch && rtpEncryptionMatch && rtcpEncryptionMatch) {
    print('All CTR cipher tests PASSED! ✓');
  } else {
    print('Some tests FAILED! ✗');
    if (!keyDerivationMatch) {
      print('  - Key derivation does not match werift');
    }
    if (!rtpEncryptionMatch) {
      print('  - RTP encryption does not match werift');
    }
    if (!rtcpEncryptionMatch) {
      print('  - RTCP encryption does not match werift');
    }
  }

  // Run GCM tests
  await testGcmCipher();
}

/// Test AES-GCM key derivation and encryption against werift/Node.js
Future<void> testGcmCipher() async {
  print('\n');
  print('--- GCM Mode (AES-128-GCM) ---\n');

  // GCM test vectors from srtp_cipher_vectors.mjs
  // 12-byte master salt (GCM uses 12 bytes, padded to 14 for KDF)
  const gcmMasterKeyHex = '000102030405060708090a0b0c0d0e0f';
  const gcmMasterSaltHex = 'a0a1a2a3a4a5a6a7a8a9aaab';

  // Expected values from Node.js (srtp_cipher_vectors.mjs)
  const expectedGcmSrtpKey = '077c6143cb221bc355ff23d5f984a16e';
  const expectedGcmSrtpSalt = '9af3e95364ebac9c99c5a7c40169';
  const expectedGcmSrtcpKey = '615dcd9042600666f6fd4d9e4fe4519f';
  const expectedGcmSrtcpSalt = 'fcca937b9112a500dac722691f9e';
  const expectedGcmSrtcp =
      '80c90001cafebabeeaecc2c438ea2e58439ea0841a4a2e8d80000000';

  final gcmMasterKey = fromHex(gcmMasterKeyHex);
  final gcmMasterSalt = fromHex(gcmMasterSaltHex);

  print('Input:');
  print('  masterKey: $gcmMasterKeyHex');
  print('  masterSalt (12 bytes): $gcmMasterSaltHex');
  print('');

  // Test key derivation for GCM
  print('GCM Key Derivation Comparison:');

  final gcmSrtpKey = SrtpKeyDerivation.generateSessionKey(
    masterKey: gcmMasterKey,
    masterSalt: gcmMasterSalt,
    label: SrtpKeyDerivation.labelSrtpEncryption,
  );
  final gcmSrtpSalt = SrtpKeyDerivation.generateSessionSalt(
    masterKey: gcmMasterKey,
    masterSalt: gcmMasterSalt,
    label: SrtpKeyDerivation.labelSrtpSalt,
  );
  final gcmSrtcpKey = SrtpKeyDerivation.generateSessionKey(
    masterKey: gcmMasterKey,
    masterSalt: gcmMasterSalt,
    label: SrtpKeyDerivation.labelSrtcpEncryption,
  );
  final gcmSrtcpSalt = SrtpKeyDerivation.generateSessionSalt(
    masterKey: gcmMasterKey,
    masterSalt: gcmMasterSalt,
    label: SrtpKeyDerivation.labelSrtcpSalt,
  );

  final actualGcmSrtpKey = toHex(gcmSrtpKey);
  print('  srtpSessionKey:');
  print('    expected: $expectedGcmSrtpKey');
  print('    actual:   $actualGcmSrtpKey');
  print('    match: ${expectedGcmSrtpKey == actualGcmSrtpKey ? '✓' : '✗'}');

  final actualGcmSrtpSalt = toHex(gcmSrtpSalt);
  print('  srtpSessionSalt:');
  print('    expected: $expectedGcmSrtpSalt');
  print('    actual:   $actualGcmSrtpSalt');
  print('    match: ${expectedGcmSrtpSalt == actualGcmSrtpSalt ? '✓' : '✗'}');

  final actualGcmSrtcpKey = toHex(gcmSrtcpKey);
  print('  srtcpSessionKey:');
  print('    expected: $expectedGcmSrtcpKey');
  print('    actual:   $actualGcmSrtcpKey');
  print('    match: ${expectedGcmSrtcpKey == actualGcmSrtcpKey ? '✓' : '✗'}');

  final actualGcmSrtcpSalt = toHex(gcmSrtcpSalt);
  print('  srtcpSessionSalt:');
  print('    expected: $expectedGcmSrtcpSalt');
  print('    actual:   $actualGcmSrtcpSalt');
  print('    match: ${expectedGcmSrtcpSalt == actualGcmSrtcpSalt ? '✓' : '✗'}');
  print('');

  // Test SRTCP encryption with GCM
  print('SRTCP Encryption Comparison (GCM):');

  // Create RTCP packet: 80c90001cafebabe
  final gcmRtcpPacket = RtcpPacket(
    version: 2,
    padding: false,
    reportCount: 0,
    packetType: RtcpPacketType.receiverReport, // 201
    length: 1,
    ssrc: 0xcafebabe,
    payload: Uint8List(0),
  );

  print('  RTCP Packet: ${toHex(gcmRtcpPacket.serialize())}');

  // Create SRTCP cipher with derived keys (truncate salt to 12 bytes for GCM)
  final gcmCipher = SrtcpCipher(
    masterKey: gcmSrtcpKey,
    masterSalt: gcmSrtcpSalt.sublist(0, 12),
  );

  final encryptedGcmRtcp = await gcmCipher.encrypt(gcmRtcpPacket);
  final actualGcmSrtcp = toHex(encryptedGcmRtcp);

  print('  encrypted:');
  print('    expected: $expectedGcmSrtcp');
  print('    actual:   $actualGcmSrtcp');
  print('    match: ${expectedGcmSrtcp == actualGcmSrtcp ? '✓' : '✗'}');
  print('');

  // Test SRTCP decryption
  print('SRTCP Decryption Test (GCM):');

  final decryptCipher = SrtcpCipher(
    masterKey: gcmSrtcpKey,
    masterSalt: gcmSrtcpSalt.sublist(0, 12),
  );

  try {
    final knownEncrypted = fromHex(expectedGcmSrtcp);
    final decryptedRtcp = await decryptCipher.decrypt(knownEncrypted);
    final decryptedHex = toHex(decryptedRtcp.serialize());
    print('  decrypted: $decryptedHex');
    print('  expected:  80c90001cafebabe');
    print('  match: ${decryptedHex == '80c90001cafebabe' ? '✓' : '✗'}');
  } catch (e) {
    print('  decryption failed: $e');
  }
  print('');

  // Summary
  print('=== GCM Summary ===');
  final gcmKeyMatch = expectedGcmSrtpKey == actualGcmSrtpKey &&
      expectedGcmSrtpSalt == actualGcmSrtpSalt &&
      expectedGcmSrtcpKey == actualGcmSrtcpKey &&
      expectedGcmSrtcpSalt == actualGcmSrtcpSalt;
  final gcmEncryptMatch = expectedGcmSrtcp == actualGcmSrtcp;

  print('Key Derivation: ${gcmKeyMatch ? '✓ PASS' : '✗ FAIL'}');
  print('SRTCP Encryption: ${gcmEncryptMatch ? '✓ PASS' : '✗ FAIL'}');
  print('');

  if (gcmKeyMatch && gcmEncryptMatch) {
    print('All GCM cipher tests PASSED! ✓');
  } else {
    print('Some GCM tests FAILED! ✗');
    if (!gcmKeyMatch) {
      print('  - GCM key derivation does not match werift/Node.js');
    }
    if (!gcmEncryptMatch) {
      print('  - GCM encryption does not match werift/Node.js');
    }
  }
}
