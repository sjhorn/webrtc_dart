// Compare werift GCM cipher with Ring camera packet data
// Updated with fresh captured values from real connection
import crypto from 'crypto';

// Fresh capture - Remote master keys (these are what Ring sent us)
const remoteMasterKey = Buffer.from([
  0x76, 0xa7, 0xf2, 0x6f, 0x80, 0xda, 0x77, 0x65,
  0x7b, 0x8f, 0xcd, 0xdc, 0x59, 0xda, 0x87, 0x3f,
]);
const remoteMasterSalt = Buffer.from([
  0xd7, 0xeb, 0xaf, 0xd2, 0x30, 0xc5, 0xf4, 0x6c,
  0x67, 0x8c, 0x14, 0x01,
]);

// Derived keys (from our key derivation)
const derivedSrtcpKey = Buffer.from([
  0x21, 0xdb, 0x6d, 0xd7, 0x97, 0x12, 0x32, 0x28,
  0x5e, 0x16, 0xd4, 0x58, 0x44, 0x48, 0xca, 0x4f,
]);
const derivedSrtcpSalt12 = Buffer.from([
  0x91, 0x72, 0xf0, 0x11, 0x4b, 0x66, 0xf2, 0x69,
  0xdc, 0x5e, 0x6b, 0xfd,
]);

// SRTCP packet from Ring
const srtcpPacket = Buffer.from([
  0x80, 0xc9, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // header
  0x52, 0xf8, 0xa9, 0xf5, 0x24, 0x63, 0x52, 0x34, // encrypted + tag
  0x43, 0x9f, 0xd6, 0x48, 0x49, 0x3d, 0xb8, 0xbb,
  0x80, 0x00, 0x00, 0x01, // SRTCP index with E-flag
]);

// Key derivation (matching werift approach)
function generateSessionKey(masterKey, masterSalt, label) {
  // Pad salt to 14 bytes
  const paddedSalt = Buffer.alloc(14);
  masterSalt.copy(paddedSalt, 0, 0, Math.min(masterSalt.length, 14));

  const sessionKey = Buffer.from(paddedSalt);

  // labelAndIndexOverKdr
  const labelAndIndexOverKdr = Buffer.from([label, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);

  // XOR from end
  let i = labelAndIndexOverKdr.length - 1;
  let j = sessionKey.length - 1;
  while (i >= 0) {
    sessionKey[j] ^= labelAndIndexOverKdr[i];
    i--;
    j--;
  }

  // Pad to 16 bytes
  const block = Buffer.alloc(16);
  sessionKey.copy(block, 0, 0, 14);
  block[14] = 0x00;
  block[15] = 0x00;

  // AES-ECB encrypt
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
  block[14] = 0x00;
  block[15] = 0x00;

  const cipher = crypto.createCipheriv('aes-128-ecb', masterKey, null);
  cipher.setAutoPadding(false);
  return Buffer.concat([cipher.update(block), cipher.final()]).subarray(0, 14);
}

// Verify key derivation matches what Dart computed
console.log('=== Key Derivation Verification ===');
const nodeDerivedKey = generateSessionKey(remoteMasterKey, remoteMasterSalt, 0x03);
const nodeDerivedSalt = generateSessionSalt(remoteMasterKey, remoteMasterSalt, 0x05);
console.log('Node derived SRTCP key:', nodeDerivedKey.toString('hex').match(/.{2}/g).join(' '));
console.log('Dart derived SRTCP key:', derivedSrtcpKey.toString('hex').match(/.{2}/g).join(' '));
console.log('Key match:', nodeDerivedKey.equals(derivedSrtcpKey));
console.log('Node derived SRTCP salt (12):', nodeDerivedSalt.subarray(0, 12).toString('hex').match(/.{2}/g).join(' '));
console.log('Dart derived SRTCP salt (12):', derivedSrtcpSalt12.toString('hex').match(/.{2}/g).join(' '));
console.log('Salt match:', nodeDerivedSalt.subarray(0, 12).equals(derivedSrtcpSalt12));

// Parse SRTCP packet
const header = srtcpPacket.subarray(0, 8);
const ssrc = srtcpPacket.readUInt32BE(4);
const indexWithEFlag = srtcpPacket.readUInt32BE(srtcpPacket.length - 4);
const index = indexWithEFlag & 0x7FFFFFFF;
const encryptedWithTag = srtcpPacket.subarray(8, srtcpPacket.length - 4);

console.log('\n=== SRTCP Packet ===');
console.log('Header:', header.toString('hex').match(/.{2}/g).join(' '));
console.log('SSRC:', ssrc.toString(16));
console.log('Index:', index, '(with E-flag: 0x' + indexWithEFlag.toString(16) + ')');
console.log('Encrypted+Tag:', encryptedWithTag.toString('hex').match(/.{2}/g).join(' '));

// Build nonce (matching werift's rtcpIvWriter: [2, 4, 2, 4])
const nonce = Buffer.alloc(12);
// [0, 0] - 2 bytes
nonce.writeUInt16BE(0, 0);
// [SSRC] - 4 bytes
nonce.writeUInt32BE(ssrc, 2);
// [0, 0] - 2 bytes
nonce.writeUInt16BE(0, 6);
// [index] - 4 bytes
nonce.writeUInt32BE(index, 8);

// XOR with salt (only first 12 bytes)
for (let i = 0; i < 12; i++) {
  nonce[i] ^= derivedSrtcpSalt12[i];
}

console.log('\n=== GCM Parameters ===');
console.log('Key:', derivedSrtcpKey.toString('hex').match(/.{2}/g).join(' '));
console.log('Nonce (before XOR):', Buffer.from([
  0, 0,
  (ssrc >> 24) & 0xff, (ssrc >> 16) & 0xff, (ssrc >> 8) & 0xff, ssrc & 0xff,
  0, 0,
  (index >> 24) & 0xff, (index >> 16) & 0xff, (index >> 8) & 0xff, index & 0xff
]).toString('hex').match(/.{2}/g).join(' '));
console.log('Nonce (after XOR):', nonce.toString('hex').match(/.{2}/g).join(' '));

// Build AAD (header + index with E-flag)
const aad = Buffer.alloc(12);
header.copy(aad, 0, 0, 8);
// Write index WITH E-flag
aad.writeUInt32BE(indexWithEFlag, 8);

console.log('AAD:', aad.toString('hex').match(/.{2}/g).join(' '));

// Try decryption with derived keys
console.log('\n=== Decryption Attempt (Derived Keys) ===');
try {
  const authTagLen = 16;
  const ciphertext = encryptedWithTag.subarray(0, encryptedWithTag.length - authTagLen);
  const authTag = encryptedWithTag.subarray(encryptedWithTag.length - authTagLen);

  console.log('Ciphertext (', ciphertext.length, 'bytes):', ciphertext.length > 0 ? ciphertext.toString('hex') : '(empty)');
  console.log('Auth tag:', authTag.toString('hex').match(/.{2}/g).join(' '));

  const decipher = crypto.createDecipheriv('aes-128-gcm', derivedSrtcpKey, nonce);
  decipher.setAuthTag(authTag);
  decipher.setAAD(aad);

  let plaintext = decipher.update(ciphertext);
  plaintext = Buffer.concat([plaintext, decipher.final()]);

  console.log('SUCCESS! Decrypted', plaintext.length, 'bytes');
  if (plaintext.length > 0) {
    console.log('Plaintext:', plaintext.toString('hex'));
  }
} catch (e) {
  console.log('FAILED:', e.message);
}

// Try with different AAD construction (maybe without E-flag)
console.log('\n=== Try AAD without E-flag ===');
try {
  const authTagLen = 16;
  const ciphertext = encryptedWithTag.subarray(0, encryptedWithTag.length - authTagLen);
  const authTag = encryptedWithTag.subarray(encryptedWithTag.length - authTagLen);

  // AAD with index WITHOUT E-flag first, then OR E-flag
  const aad2 = Buffer.alloc(12);
  header.copy(aad2, 0, 0, 8);
  aad2.writeUInt32BE(index, 8);
  aad2[8] |= 0x80;  // OR in E-flag

  console.log('AAD (alt):', aad2.toString('hex').match(/.{2}/g).join(' '));

  const nonce2 = Buffer.alloc(12);
  nonce2.writeUInt16BE(0, 0);
  nonce2.writeUInt32BE(ssrc, 2);
  nonce2.writeUInt16BE(0, 6);
  nonce2.writeUInt32BE(index, 8);
  for (let i = 0; i < 12; i++) {
    nonce2[i] ^= derivedSrtcpSalt12[i];
  }

  const decipher = crypto.createDecipheriv('aes-128-gcm', derivedSrtcpKey, nonce2);
  decipher.setAuthTag(authTag);
  decipher.setAAD(aad2);

  let plaintext = decipher.update(ciphertext);
  plaintext = Buffer.concat([plaintext, decipher.final()]);

  console.log('SUCCESS! Decrypted', plaintext.length, 'bytes');
} catch (e) {
  console.log('FAILED:', e.message);
}

// Try master keys directly (no KDF) in case Ring skips key derivation
console.log('\n=== Try Master Keys (no KDF) ===');
try {
  const masterSalt12 = remoteMasterSalt.subarray(0, 12);
  const nonce3 = Buffer.alloc(12);
  nonce3.writeUInt16BE(0, 0);
  nonce3.writeUInt32BE(ssrc, 2);
  nonce3.writeUInt16BE(0, 6);
  nonce3.writeUInt32BE(index, 8);
  for (let i = 0; i < 12; i++) {
    nonce3[i] ^= masterSalt12[i];
  }

  const authTagLen = 16;
  const ciphertext = encryptedWithTag.subarray(0, encryptedWithTag.length - authTagLen);
  const authTag = encryptedWithTag.subarray(encryptedWithTag.length - authTagLen);

  const decipher = crypto.createDecipheriv('aes-128-gcm', remoteMasterKey, nonce3);
  decipher.setAuthTag(authTag);
  decipher.setAAD(aad);

  let plaintext = decipher.update(ciphertext);
  plaintext = Buffer.concat([plaintext, decipher.final()]);

  console.log('SUCCESS! Decrypted', plaintext.length, 'bytes');
} catch (e) {
  console.log('FAILED:', e.message);
}

// Try with index = 0 in nonce (some implementations use 0 for first packet)
console.log('\n=== Try with Index = 0 in nonce ===');
try {
  const nonce4 = Buffer.alloc(12);
  nonce4.writeUInt16BE(0, 0);
  nonce4.writeUInt32BE(ssrc, 2);
  nonce4.writeUInt16BE(0, 6);
  nonce4.writeUInt32BE(0, 8);  // index = 0
  for (let i = 0; i < 12; i++) {
    nonce4[i] ^= derivedSrtcpSalt12[i];
  }

  console.log('Nonce (index=0):', nonce4.toString('hex').match(/.{2}/g).join(' '));

  const authTagLen = 16;
  const ciphertext = encryptedWithTag.subarray(0, encryptedWithTag.length - authTagLen);
  const authTag = encryptedWithTag.subarray(encryptedWithTag.length - authTagLen);

  const decipher = crypto.createDecipheriv('aes-128-gcm', derivedSrtcpKey, nonce4);
  decipher.setAuthTag(authTag);
  decipher.setAAD(aad);

  let plaintext = decipher.update(ciphertext);
  plaintext = Buffer.concat([plaintext, decipher.final()]);

  console.log('SUCCESS! Decrypted', plaintext.length, 'bytes');
} catch (e) {
  console.log('FAILED:', e.message);
}

// Try with SRTP keys (label 0 and 2 instead of SRTCP label 3 and 5)
console.log('\n=== Try SRTP Keys (label 0/2) instead of SRTCP (label 3/5) ===');
try {
  const srtpKey = generateSessionKey(remoteMasterKey, remoteMasterSalt, 0x00);
  const srtpSalt = generateSessionSalt(remoteMasterKey, remoteMasterSalt, 0x02);

  console.log('SRTP key:', srtpKey.toString('hex').match(/.{2}/g).join(' '));
  console.log('SRTP salt (12):', srtpSalt.subarray(0, 12).toString('hex').match(/.{2}/g).join(' '));

  const nonce5 = Buffer.alloc(12);
  nonce5.writeUInt16BE(0, 0);
  nonce5.writeUInt32BE(ssrc, 2);
  nonce5.writeUInt16BE(0, 6);
  nonce5.writeUInt32BE(index, 8);
  for (let i = 0; i < 12; i++) {
    nonce5[i] ^= srtpSalt[i];
  }

  const authTagLen = 16;
  const ciphertext = encryptedWithTag.subarray(0, encryptedWithTag.length - authTagLen);
  const authTag = encryptedWithTag.subarray(encryptedWithTag.length - authTagLen);

  const decipher = crypto.createDecipheriv('aes-128-gcm', srtpKey, nonce5);
  decipher.setAuthTag(authTag);
  decipher.setAAD(aad);

  let plaintext = decipher.update(ciphertext);
  plaintext = Buffer.concat([plaintext, decipher.final()]);

  console.log('SUCCESS! Decrypted', plaintext.length, 'bytes');
} catch (e) {
  console.log('FAILED:', e.message);
}

// Try swapping client/server keys (maybe the key export is swapped?)
console.log('\n=== Try LOCAL Keys (swapped direction) ===');
// Local master keys from the debug output
const localMasterKey = Buffer.from([
  0xba, 0x3f, 0xd4, 0x6b, 0x0b, 0xaa, 0xdd, 0x21,
  0x03, 0x6d, 0x96, 0x08, 0xc1, 0x61, 0xee, 0x22,
]);
const localMasterSalt = Buffer.from([
  0x27, 0x67, 0x39, 0x74, 0xcb, 0xad, 0xf9, 0x1b,
  0x26, 0x21, 0xf4, 0xae,
]);

try {
  const localSrtcpKey = generateSessionKey(localMasterKey, localMasterSalt, 0x03);
  const localSrtcpSalt = generateSessionSalt(localMasterKey, localMasterSalt, 0x05);

  console.log('Local SRTCP key:', localSrtcpKey.toString('hex').match(/.{2}/g).join(' '));
  console.log('Local SRTCP salt (12):', localSrtcpSalt.subarray(0, 12).toString('hex').match(/.{2}/g).join(' '));

  const nonce6 = Buffer.alloc(12);
  nonce6.writeUInt16BE(0, 0);
  nonce6.writeUInt32BE(ssrc, 2);
  nonce6.writeUInt16BE(0, 6);
  nonce6.writeUInt32BE(index, 8);
  for (let i = 0; i < 12; i++) {
    nonce6[i] ^= localSrtcpSalt[i];
  }

  const authTagLen = 16;
  const ciphertext = encryptedWithTag.subarray(0, encryptedWithTag.length - authTagLen);
  const authTag = encryptedWithTag.subarray(encryptedWithTag.length - authTagLen);

  const decipher = crypto.createDecipheriv('aes-128-gcm', localSrtcpKey, nonce6);
  decipher.setAuthTag(authTag);
  decipher.setAAD(aad);

  let plaintext = decipher.update(ciphertext);
  plaintext = Buffer.concat([plaintext, decipher.final()]);

  console.log('SUCCESS! Decrypted', plaintext.length, 'bytes');
} catch (e) {
  console.log('FAILED:', e.message);
}
