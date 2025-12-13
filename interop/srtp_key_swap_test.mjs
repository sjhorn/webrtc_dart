// Test if keys need to be swapped for Ring camera SRTCP decryption
import crypto from 'crypto';

// Latest captured values from Ring connection
// From server.dart debug output:
// [SERVER] localMasterKey: ...
// [SERVER] remoteMasterKey: ...
//
// We are DTLS server (Ring is DTLS client)
// In RFC 5764:
// - Client write key = what client uses to encrypt (Ring → us)
// - Server write key = what server uses to encrypt (us → Ring)
//
// So for DECRYPTING Ring's SRTCP packets, we need:
// - The CLIENT's write key (Ring's encryption key)
// - Which should be our "remoteMasterKey"

// Fresh capture - what our server printed:
// These are from server.dart _onHandshakeComplete()
const remoteMasterKey = Buffer.from([
  0x76, 0xa7, 0xf2, 0x6f, 0x80, 0xda, 0x77, 0x65,
  0x7b, 0x8f, 0xcd, 0xdc, 0x59, 0xda, 0x87, 0x3f,
]);
const remoteMasterSalt = Buffer.from([
  0xd7, 0xeb, 0xaf, 0xd2, 0x30, 0xc5, 0xf4, 0x6c,
  0x67, 0x8c, 0x14, 0x01,
]);

// Our local keys (server write keys)
const localMasterKey = Buffer.from([
  0x9d, 0x46, 0xaf, 0x45, 0xe3, 0x72, 0xa2, 0x5e,
  0xbf, 0x3b, 0x94, 0x64, 0xa4, 0x7a, 0xd6, 0x96,
]);
const localMasterSalt = Buffer.from([
  0xe9, 0x29, 0xf5, 0x42, 0x22, 0x42, 0x18, 0x5c,
  0xa9, 0x39, 0x23, 0x55,
]);

// SRTCP packet from Ring (DTLS client)
const srtcpPacket = Buffer.from([
  0x80, 0xc9, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // header
  0x52, 0xf8, 0xa9, 0xf5, 0x24, 0x63, 0x52, 0x34, // encrypted + tag
  0x43, 0x9f, 0xd6, 0x48, 0x49, 0x3d, 0xb8, 0xbb,
  0x80, 0x00, 0x00, 0x01, // SRTCP index with E-flag
]);

// Key derivation
function generateSessionKey(masterKey, masterSalt, label) {
  const paddedSalt = Buffer.alloc(14);
  masterSalt.copy(paddedSalt, 0, 0, Math.min(masterSalt.length, 14));
  const sessionKey = Buffer.from(paddedSalt);
  const labelAndIndexOverKdr = Buffer.from([label, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
  let i = labelAndIndexOverKdr.length - 1;
  let j = sessionKey.length - 1;
  while (i >= 0) {
    sessionKey[j] ^= labelAndIndexOverKdr[i];
    i--;
    j--;
  }
  const block = Buffer.alloc(16);
  sessionKey.copy(block, 0, 0, 14);
  const cipher = crypto.createCipheriv('aes-128-ecb', masterKey, null);
  cipher.setAutoPadding(false);
  return Buffer.concat([cipher.update(block), cipher.final()]);
}

function generateSessionSalt(masterKey, masterSalt, label) {
  const paddedSalt = Buffer.alloc(14);
  masterSalt.copy(paddedSalt, 0, 0, Math.min(masterSalt.length, 14));
  const sessionSalt = Buffer.from(paddedSalt);
  const labelAndIndexOverKdr = Buffer.from([label, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
  let i = labelAndIndexOverKdr.length - 1;
  let j = sessionSalt.length - 1;
  while (i >= 0) {
    sessionSalt[j] ^= labelAndIndexOverKdr[i];
    i--;
    j--;
  }
  const block = Buffer.alloc(16);
  sessionSalt.copy(block, 0, 0, 14);
  const cipher = crypto.createCipheriv('aes-128-ecb', masterKey, null);
  cipher.setAutoPadding(false);
  return Buffer.concat([cipher.update(block), cipher.final()]).subarray(0, 12);
}

function tryDecrypt(keyLabel, srtcpKey, srtcpSalt) {
  console.log(`\n=== Test: ${keyLabel} ===`);
  console.log('SRTCP key:', srtcpKey.toString('hex'));
  console.log('SRTCP salt:', srtcpSalt.toString('hex'));

  // Parse packet
  const encrypted = srtcpPacket;
  const ssrc = encrypted.readUInt32BE(4);
  let srtcpIndex = encrypted.readUInt32BE(encrypted.length - 4);
  srtcpIndex &= ~(0x80 << 24);
  const aadPos = encrypted.length - 4;

  console.log('SSRC:', ssrc, 'index:', srtcpIndex);

  // Build IV for SRTCP
  const iv = Buffer.alloc(12);
  iv.writeUInt32BE(ssrc, 2);
  iv.writeUInt32BE(srtcpIndex, 8);
  for (let i = 0; i < 12; i++) {
    iv[i] ^= srtcpSalt[i];
  }
  console.log('IV:', iv.toString('hex'));

  // Build AAD
  const aad = Buffer.alloc(12);
  encrypted.copy(aad, 0, 0, 8);
  aad.writeUInt32BE((srtcpIndex | 0x80000000) >>> 0, 8);
  console.log('AAD:', aad.toString('hex'));

  // For minimal RTCP RR, encrypted payload is 0 bytes
  // So the "encrypted" part (indices 8-24) is just the 16-byte auth tag
  const aeadAuthTagLen = 16;
  const ciphertext = encrypted.slice(8, aadPos - aeadAuthTagLen);
  const authTag = encrypted.slice(aadPos - aeadAuthTagLen, aadPos);

  console.log('Ciphertext length:', ciphertext.length, 'bytes');
  console.log('Auth tag:', authTag.toString('hex'));

  try {
    const cipher = crypto.createDecipheriv('aes-128-gcm', srtcpKey, iv);
    cipher.setAuthTag(authTag);
    cipher.setAAD(aad);
    const dec = cipher.update(ciphertext);
    cipher.final();  // Verify auth tag
    console.log('SUCCESS! Decrypted:', dec.toString('hex'), `(${dec.length} bytes)`);
    return true;
  } catch (e) {
    console.log('FAILED:', e.message);
    return false;
  }
}

// Test with "remote" keys (what we receive from Ring = client write keys)
const remoteSrtcpKey = generateSessionKey(remoteMasterKey, remoteMasterSalt, 0x03);
const remoteSrtcpSalt = generateSessionSalt(remoteMasterKey, remoteMasterSalt, 0x05);

// Test with "local" keys (what we use to send = server write keys)
const localSrtcpKey = generateSessionKey(localMasterKey, localMasterSalt, 0x03);
const localSrtcpSalt = generateSessionSalt(localMasterKey, localMasterSalt, 0x05);

console.log('=== RFC 5764 Key Extraction Test ===');
console.log('We are DTLS SERVER, Ring is DTLS CLIENT');
console.log('Ring sends SRTCP encrypted with CLIENT write keys');
console.log('We should decrypt with remoteMasterKey (= client write key)');

tryDecrypt('Remote/Client keys (expected)', remoteSrtcpKey, remoteSrtcpSalt);
tryDecrypt('Local/Server keys (swapped)', localSrtcpKey, localSrtcpSalt);

// What if the keying material is in the wrong order?
// RFC 5764 says: client_write_SRTP_master_key + server_write_SRTP_master_key + salts
// But what if we extracted them in server order?
console.log('\n=== Checking raw keying material order ===');
console.log('If we got the order wrong, try deriving from swapped master keys');

// Try deriving SRTCP keys from local master but treating it as client's key
const swapped1Key = generateSessionKey(localMasterKey, localMasterSalt, 0x03);
const swapped1Salt = generateSessionSalt(localMasterKey, localMasterSalt, 0x05);
tryDecrypt('Derive from LOCAL master (maybe Ring encrypted with this?)', swapped1Key, swapped1Salt);

// For RTCP specifically, try index 0 as well
console.log('\n=== Alternative: Try SRTCP index = 0 ===');
// Modify packet to test with index 0
const packet0 = Buffer.from(srtcpPacket);
packet0.writeUInt32BE(0x80000000, packet0.length - 4);

const iv0 = Buffer.alloc(12);
iv0.writeUInt32BE(1, 2);  // SSRC = 1
// index 0 → no change
for (let i = 0; i < 12; i++) {
  iv0[i] ^= remoteSrtcpSalt[i];
}

const aad0 = Buffer.alloc(12);
packet0.copy(aad0, 0, 0, 8);
aad0.writeUInt32BE(0x80000000, 8);

console.log('IV (index=0):', iv0.toString('hex'));
console.log('AAD (index=0):', aad0.toString('hex'));

// The auth tag should still be at the same position
const authTag0 = packet0.slice(8, 24);
try {
  const cipher = crypto.createDecipheriv('aes-128-gcm', remoteSrtcpKey, iv0);
  cipher.setAuthTag(authTag0);
  cipher.setAAD(aad0);
  const dec = cipher.update(Buffer.alloc(0));  // No ciphertext
  cipher.final();
  console.log('SUCCESS with index=0! Decrypted:', dec.toString('hex'));
} catch (e) {
  console.log('FAILED with index=0:', e.message);
}
