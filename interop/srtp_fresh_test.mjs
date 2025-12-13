// Fresh test with data captured from the same Ring session
import crypto from 'crypto';

// Fresh capture from Ring session
const remoteMasterKey = Buffer.from([
  0x5c, 0x08, 0xd9, 0x1c, 0xd5, 0x17, 0x12, 0xb6,
  0x93, 0x29, 0xc1, 0x5c, 0x2c, 0x48, 0xd0, 0x29,
]);
const remoteMasterSalt = Buffer.from([
  0xa6, 0x5d, 0x74, 0xf3, 0xaa, 0x51, 0xa6, 0xf9,
  0x2a, 0x94, 0xf9, 0x58,
]);

// Dart-derived keys (to verify our derivation matches)
const expectedSrtcpKey = Buffer.from([
  0xc6, 0x09, 0x70, 0xfe, 0xea, 0x68, 0x61, 0xa0,
  0x01, 0xe7, 0x3d, 0xd9, 0x4e, 0xb0, 0x2d, 0x02,
]);
const expectedSrtcpSalt = Buffer.from([
  0x81, 0x92, 0x73, 0x0b, 0x64, 0xe1, 0x2a, 0x48,
  0xdc, 0xd2, 0xdf, 0xa3,
]);

// SRTCP packet from Ring in the SAME session
const srtcpPacket = Buffer.from([
  0x80, 0xc9, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // header (8 bytes)
  0x43, 0x03, 0xf2, 0xf7, 0x3a, 0x4e, 0x7f, 0xa1, // auth tag (16 bytes)
  0x4a, 0xda, 0x9b, 0x49, 0x8d, 0x57, 0xec, 0xce,
  0x80, 0x00, 0x00, 0x01, // SRTCP index with E-flag (4 bytes)
]);

// Key derivation functions
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

// Derive SRTCP keys (label 3 for encryption, label 5 for salt)
const srtcpKey = generateSessionKey(remoteMasterKey, remoteMasterSalt, 0x03);
const srtcpSalt = generateSessionSalt(remoteMasterKey, remoteMasterSalt, 0x05);

console.log('=== Key Derivation Verification ===');
console.log('Derived key:', srtcpKey.toString('hex'));
console.log('Expected key:', expectedSrtcpKey.toString('hex'));
console.log('Keys match:', srtcpKey.equals(expectedSrtcpKey));
console.log('');
console.log('Derived salt:', srtcpSalt.toString('hex'));
console.log('Expected salt:', expectedSrtcpSalt.toString('hex'));
console.log('Salts match:', srtcpSalt.equals(expectedSrtcpSalt));

// Parse packet
const ssrc = srtcpPacket.readUInt32BE(4);
let srtcpIndex = srtcpPacket.readUInt32BE(srtcpPacket.length - 4);
const hasEFlag = (srtcpIndex & 0x80000000) !== 0;
srtcpIndex &= 0x7FFFFFFF;  // Clear E-flag to get actual index

console.log('\n=== Packet Info ===');
console.log('SSRC:', ssrc, `(0x${ssrc.toString(16)})`);
console.log('Index:', srtcpIndex);
console.log('E-flag set:', hasEFlag);
console.log('Packet length:', srtcpPacket.length, 'bytes');

// Build IV for SRTCP: [00 00, SSRC(4), 00 00, index(4)] XOR salt
const iv = Buffer.alloc(12);
iv.writeUInt32BE(ssrc, 2);
iv.writeUInt32BE(srtcpIndex, 8);
for (let i = 0; i < 12; i++) {
  iv[i] ^= srtcpSalt[i];
}
console.log('IV:', iv.toString('hex'));

// Build AAD: header (8 bytes) + index with E-flag (4 bytes)
const aad = Buffer.alloc(12);
srtcpPacket.copy(aad, 0, 0, 8);  // Copy header
aad.writeUInt32BE((srtcpIndex | 0x80000000) >>> 0, 8);  // Index with E-flag
console.log('AAD:', aad.toString('hex'));

// For minimal RTCP RR (28 bytes total):
// header(8) + tag(16) + index(4) = 28
// So encrypted payload is 0 bytes, the 16 bytes after header are pure auth tag
const authTag = srtcpPacket.subarray(8, 24);  // 16-byte auth tag
const ciphertext = Buffer.alloc(0);  // No ciphertext for minimal RR

console.log('Auth tag:', authTag.toString('hex'));
console.log('Ciphertext length:', ciphertext.length);

console.log('\n=== GCM Decryption (proper, with auth verification) ===');
try {
  const cipher = crypto.createDecipheriv('aes-128-gcm', srtcpKey, iv);
  cipher.setAuthTag(authTag);
  cipher.setAAD(aad);
  const dec = cipher.update(ciphertext);
  cipher.final();  // This verifies the auth tag
  console.log('SUCCESS! Decrypted:', dec.toString('hex'));
} catch (e) {
  console.log('FAILED:', e.message);
}

// Try werift-style (no auth verification)
console.log('\n=== werift-style Decryption (NO auth verification) ===');
try {
  const cipher = crypto.createDecipheriv('aes-128-gcm', srtcpKey, iv);
  cipher.setAAD(aad);
  // werift passes the entire encrypted portion (including tag) to update()
  const encryptedPortion = srtcpPacket.subarray(8, 24);  // 16 bytes
  const dec = cipher.update(encryptedPortion);
  // werift does NOT call cipher.final() - skips verification
  console.log('Output:', dec.toString('hex'));
  console.log('Length:', dec.length, 'bytes');
} catch (e) {
  console.log('FAILED:', e.message);
}

// Let's also try different AAD constructions
console.log('\n=== Testing alternative AAD constructions ===');

// Alternative 1: Only header (no index)
console.log('\n--- Alt 1: AAD = header only (8 bytes) ---');
try {
  const aadAlt1 = srtcpPacket.subarray(0, 8);
  const cipher = crypto.createDecipheriv('aes-128-gcm', srtcpKey, iv);
  cipher.setAuthTag(authTag);
  cipher.setAAD(aadAlt1);
  const dec = cipher.update(ciphertext);
  cipher.final();
  console.log('SUCCESS with AAD = header only');
} catch (e) {
  console.log('FAILED:', e.message);
}

// Alternative 2: Full packet minus auth tag as AAD
console.log('\n--- Alt 2: AAD = header + index (without E-flag) ---');
try {
  const aadAlt2 = Buffer.alloc(12);
  srtcpPacket.copy(aadAlt2, 0, 0, 8);
  aadAlt2.writeUInt32BE(srtcpIndex, 8);  // Index WITHOUT E-flag
  const cipher = crypto.createDecipheriv('aes-128-gcm', srtcpKey, iv);
  cipher.setAuthTag(authTag);
  cipher.setAAD(aadAlt2);
  const dec = cipher.update(ciphertext);
  cipher.final();
  console.log('SUCCESS with AAD = header + index (no E-flag)');
} catch (e) {
  console.log('FAILED:', e.message);
}

// Alternative 3: Using SRTP keys instead of SRTCP keys
console.log('\n--- Alt 3: Using SRTP keys (label 0/2) instead of SRTCP (label 3/5) ---');
const srtpKey = generateSessionKey(remoteMasterKey, remoteMasterSalt, 0x00);
const srtpSalt = generateSessionSalt(remoteMasterKey, remoteMasterSalt, 0x02);
console.log('SRTP key:', srtpKey.toString('hex'));
console.log('SRTP salt:', srtpSalt.toString('hex'));

const ivSrtp = Buffer.alloc(12);
ivSrtp.writeUInt32BE(ssrc, 2);
ivSrtp.writeUInt32BE(srtcpIndex, 8);
for (let i = 0; i < 12; i++) {
  ivSrtp[i] ^= srtpSalt[i];
}

try {
  const cipher = crypto.createDecipheriv('aes-128-gcm', srtpKey, ivSrtp);
  cipher.setAuthTag(authTag);
  cipher.setAAD(aad);
  const dec = cipher.update(ciphertext);
  cipher.final();
  console.log('SUCCESS with SRTP keys!');
} catch (e) {
  console.log('FAILED:', e.message);
}
