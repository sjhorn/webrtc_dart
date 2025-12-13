import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// Test SRTCP decryption with various key configurations
/// to debug Ring camera interop issue
// From fresh debug output:
// Remote master key: 20 a2 70 36 1f 60 1e 94 b5 1f 17 1e 50 c2 a3 0b
// Remote master salt: 65 ed f6 00 d4 c4 df 83 47 cf 57 68
// Derived remoteSrtcpKey: 8b 5e b7 dc 53 ff 10 54 0f 28 14 1f de 44 93 e9
// Derived remoteSrtcpSalt (12): 76 49 58 12 15 f9 dd 02 45 84 48 2f
// SRTCP packet: 80 c9 00 01 00 00 00 01 f3 07 fd da 68 d2 ae d9 13 8f 47 d3 64 b6 38 65 80 00 00 01

void main() async {
  // Master keys (from DTLS export)
  final masterKey = Uint8List.fromList([
    0x20,
    0xa2,
    0x70,
    0x36,
    0x1f,
    0x60,
    0x1e,
    0x94,
    0xb5,
    0x1f,
    0x17,
    0x1e,
    0x50,
    0xc2,
    0xa3,
    0x0b,
  ]);
  final masterSalt = Uint8List.fromList([
    0x65,
    0xed,
    0xf6,
    0x00,
    0xd4,
    0xc4,
    0xdf,
    0x83,
    0x47,
    0xcf,
    0x57,
    0x68,
  ]);

  // Derived keys
  final derivedKey = Uint8List.fromList([
    0x8b,
    0x5e,
    0xb7,
    0xdc,
    0x53,
    0xff,
    0x10,
    0x54,
    0x0f,
    0x28,
    0x14,
    0x1f,
    0xde,
    0x44,
    0x93,
    0xe9,
  ]);
  final derivedSalt = Uint8List.fromList([
    0x76,
    0x49,
    0x58,
    0x12,
    0x15,
    0xf9,
    0xdd,
    0x02,
    0x45,
    0x84,
    0x48,
    0x2f,
  ]);

  // SRTCP packet from Ring
  final srtcpPacket = Uint8List.fromList([
    0x80, 0xc9, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // header
    0xf3, 0x07, 0xfd, 0xda, 0x68, 0xd2, 0xae, 0xd9, // auth tag part 1
    0x13, 0x8f, 0x47, 0xd3, 0x64, 0xb6, 0x38, 0x65, // auth tag part 2
    0x80, 0x00, 0x00, 0x01, // SRTCP index with E-flag
  ]);

  // Parse packet
  final header = srtcpPacket.sublist(0, 8);
  final headerBuffer = ByteData.sublistView(header);
  final ssrc = headerBuffer.getUint32(4);

  final indexStart = srtcpPacket.length - 4;
  final indexBuffer = ByteData.sublistView(srtcpPacket, indexStart);
  final indexWithEFlag = indexBuffer.getUint32(0);
  final index = indexWithEFlag & 0x7FFFFFFF;

  // Encrypted data + auth tag
  final encryptedData = srtcpPacket.sublist(8, indexStart);

  print('=== SRTCP Packet Analysis ===');
  print('SSRC: 0x${ssrc.toRadixString(16)}');
  print('Index: $index (with E-flag: 0x${indexWithEFlag.toRadixString(16)})');
  print('Header: ${_hex(header)}');
  print(
      'Encrypted data (${encryptedData.length} bytes): ${_hex(encryptedData)}');
  print('');

  // Try decryption with different key configurations
  print('=== Test 1: Derived keys (current implementation) ===');
  await _tryDecrypt(derivedKey, derivedSalt, ssrc, index, header, encryptedData,
      indexWithEFlag);

  print('');
  print('=== Test 2: Master keys directly (no KDF) ===');
  await _tryDecrypt(masterKey, masterSalt, ssrc, index, header, encryptedData,
      indexWithEFlag);

  print('');
  print('=== Test 3: Master key + derived salt ===');
  await _tryDecrypt(masterKey, derivedSalt, ssrc, index, header, encryptedData,
      indexWithEFlag);

  print('');
  print('=== Test 4: Derived key + master salt ===');
  await _tryDecrypt(derivedKey, masterSalt, ssrc, index, header, encryptedData,
      indexWithEFlag);

  print('');
  print('=== Test 5: Index = 0 instead of 1 (derived keys) ===');
  await _tryDecrypt(
      derivedKey, derivedSalt, ssrc, 0, header, encryptedData, 0x80000000);

  print('');
  print('=== Test 6: Index = 0 (master keys directly) ===');
  await _tryDecrypt(
      masterKey, masterSalt, ssrc, 0, header, encryptedData, 0x80000000);

  // Additional tests: Try swapped keys (maybe we're using client vs server wrong?)
  // From the debug output, the LOCAL keys are:
  // localMasterKey: 9a c8 62 98 d0 08 34 b5 1b 02 c4 db 41 f3 78 3d
  // localMasterSalt: 89 10 99 1e 23 e4 23 9b d2 14 c3 8e
  final localKey = Uint8List.fromList([
    0x9a,
    0xc8,
    0x62,
    0x98,
    0xd0,
    0x08,
    0x34,
    0xb5,
    0x1b,
    0x02,
    0xc4,
    0xdb,
    0x41,
    0xf3,
    0x78,
    0x3d,
  ]);
  final localSalt = Uint8List.fromList([
    0x89,
    0x10,
    0x99,
    0x1e,
    0x23,
    0xe4,
    0x23,
    0x9b,
    0xd2,
    0x14,
    0xc3,
    0x8e,
  ]);

  print('');
  print('=== Test 7: LOCAL keys (swapped direction?) ===');
  await _tryDecrypt(
      localKey, localSalt, ssrc, index, header, encryptedData, indexWithEFlag);

  print('');
  print('=== Test 8: LOCAL keys, index=0 ===');
  await _tryDecrypt(
      localKey, localSalt, ssrc, 0, header, encryptedData, 0x80000000);

  // Try deriving SRTCP keys from local master keys
  print('');
  print('=== Test 9: Derive SRTCP from LOCAL master ===');
  final localDerivedKey =
      _deriveSessionKey(localKey, localSalt, 0x03); // labelSrtcpEncryption
  final localDerivedSalt =
      _deriveSessionSalt(localKey, localSalt, 0x05); // labelSrtcpSalt
  print(
      'Derived from local: key=${_hex(localDerivedKey)}, salt=${_hex(localDerivedSalt)}');
  await _tryDecrypt(localDerivedKey, localDerivedSalt.sublist(0, 12), ssrc,
      index, header, encryptedData, indexWithEFlag);
}

// Key derivation functions matching our implementation
Uint8List _deriveSessionKey(
    Uint8List masterKey, Uint8List masterSalt, int label) {
  final paddedSalt = _padSaltTo14Bytes(masterSalt);
  final sessionKey = Uint8List.fromList(paddedSalt);

  final labelAndIndexOverKdr =
      Uint8List.fromList([label, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);

  var i = labelAndIndexOverKdr.length - 1;
  var j = sessionKey.length - 1;
  while (i >= 0) {
    sessionKey[j] = sessionKey[j] ^ labelAndIndexOverKdr[i];
    i--;
    j--;
  }

  final block = Uint8List(16);
  block.setRange(0, 14, sessionKey);
  block[14] = 0x00;
  block[15] = 0x00;

  final aes = AESEngine();
  aes.init(true, KeyParameter(masterKey));
  final output = Uint8List(16);
  aes.processBlock(block, 0, output, 0);

  return output;
}

Uint8List _deriveSessionSalt(
    Uint8List masterKey, Uint8List masterSalt, int label) {
  final paddedSalt = _padSaltTo14Bytes(masterSalt);
  final sessionSalt = Uint8List.fromList(paddedSalt);

  final labelAndIndexOverKdr =
      Uint8List.fromList([label, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);

  var i = labelAndIndexOverKdr.length - 1;
  var j = sessionSalt.length - 1;
  while (i >= 0) {
    sessionSalt[j] = sessionSalt[j] ^ labelAndIndexOverKdr[i];
    i--;
    j--;
  }

  final block = Uint8List(16);
  block.setRange(0, 14, sessionSalt);
  block[14] = 0x00;
  block[15] = 0x00;

  final aes = AESEngine();
  aes.init(true, KeyParameter(masterKey));
  final output = Uint8List(16);
  aes.processBlock(block, 0, output, 0);

  return output.sublist(0, 14);
}

Uint8List _padSaltTo14Bytes(Uint8List salt) {
  if (salt.length >= 14) {
    return salt.sublist(0, 14);
  }
  final padded = Uint8List(14);
  padded.setRange(0, salt.length, salt);
  return padded;
}

Future<void> _tryDecrypt(
  Uint8List key,
  Uint8List salt,
  int ssrc,
  int index,
  Uint8List header,
  Uint8List encryptedData,
  int indexWithEFlag,
) async {
  final nonce = _buildNonce(salt, ssrc, index);
  final aad = _buildAad(header, indexWithEFlag);

  print('Key: ${_hex(key)}');
  print('Salt: ${_hex(salt)}');
  print('Nonce: ${_hex(nonce)}');
  print('AAD: ${_hex(aad)}');

  try {
    final gcm = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(key),
      128,
      nonce,
      aad,
    );

    gcm.init(false, params);

    final outputLength = encryptedData.length - 16;
    if (outputLength < 0) {
      print('Result: FAIL - encrypted data too short');
      return;
    }

    final plaintext = Uint8List(outputLength);
    var outOff =
        gcm.processBytes(encryptedData, 0, encryptedData.length, plaintext, 0);
    gcm.doFinal(plaintext, outOff);

    print('Result: SUCCESS! Decrypted ${plaintext.length} bytes');
    if (plaintext.isNotEmpty) {
      print('Plaintext: ${_hex(plaintext)}');
    } else {
      print('(empty payload - valid for minimal RTCP RR)');
    }
  } catch (e) {
    print('Result: FAIL - $e');
  }

  // Also try CTR mode decryption in case Ring is using CTR despite GCM negotiation
  print('Trying CTR mode (AES-CM):');
  try {
    await _tryCtrDecrypt(key, salt, ssrc, encryptedData);
  } catch (e) {
    print('CTR Result: FAIL - $e');
  }
}

Future<void> _tryCtrDecrypt(
  Uint8List key,
  Uint8List salt,
  int ssrc,
  Uint8List encryptedData,
) async {
  // In CTR mode, the packet format is different:
  // header(8) + encrypted_payload + HMAC(10) + index(4)
  // For a minimal RR, there's no payload, so it would be:
  // header(8) + HMAC(10) + index(4) = 22 bytes
  // But our packet is 28 bytes, which matches GCM (header(8) + tag(16) + index(4))

  // Let's assume it's CTR and the 16 bytes after header are:
  // encrypted_payload(6) + HMAC(10) or encrypted_payload(0) + ?

  // Actually CTR mode for RTCP:
  // | header(8) | encrypted_payload | HMAC-SHA1-80(10) | index(4) |
  // If payload is 0, total = 8 + 0 + 10 + 4 = 22 bytes
  // But we have 28 bytes, so there's 6 extra bytes somewhere...

  // Unless this is truly CTR with some payload?
  // 28 - 8 - 10 - 4 = 6 bytes of encrypted payload

  print('  (CTR mode format doesn\'t match 28-byte packet with GCM)');
}

Uint8List _buildNonce(Uint8List salt, int ssrc, int index) {
  final nonce = Uint8List(12);

  // First 2 bytes are zero
  nonce[0] = 0;
  nonce[1] = 0;

  // SSRC at bytes 2-5
  nonce[2] = (ssrc >> 24) & 0xFF;
  nonce[3] = (ssrc >> 16) & 0xFF;
  nonce[4] = (ssrc >> 8) & 0xFF;
  nonce[5] = ssrc & 0xFF;

  // 2 bytes zero at bytes 6-7
  nonce[6] = 0;
  nonce[7] = 0;

  // Index at bytes 8-11
  nonce[8] = (index >> 24) & 0xFF;
  nonce[9] = (index >> 16) & 0xFF;
  nonce[10] = (index >> 8) & 0xFF;
  nonce[11] = index & 0xFF;

  // XOR with salt
  for (var i = 0; i < 12; i++) {
    nonce[i] ^= salt[i];
  }

  return nonce;
}

Uint8List _buildAad(Uint8List header, int indexWithEFlag) {
  final aad = Uint8List(12);
  aad.setRange(0, 8, header);
  aad[8] = (indexWithEFlag >> 24) & 0xFF;
  aad[9] = (indexWithEFlag >> 16) & 0xFF;
  aad[10] = (indexWithEFlag >> 8) & 0xFF;
  aad[11] = indexWithEFlag & 0xFF;
  return aad;
}

String _hex(List<int> bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}
