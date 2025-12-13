/**
 * Generate SRTP/SRTCP test vectors using Node.js crypto
 * 
 * This replicates werift's key derivation and AES-GCM encryption
 * to generate test vectors for verifying our Dart implementation.
 */

import crypto from 'crypto';

// Test vector: known master key and salt
const masterKey = Buffer.from([
  0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
  0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f
]);

// GCM uses 12-byte salt (we'll pad to 14 for KDF)
const masterSalt = Buffer.from([
  0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5,
  0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab
]);

// Pad salt to 14 bytes (werift pads with zeros on the right)
const paddedSalt = Buffer.concat([masterSalt, Buffer.alloc(2)]);

console.log('=== SRTP AES-GCM Test Vectors ===');
console.log('');
console.log('Master Key:', masterKey.toString('hex'));
console.log('Master Salt (12 bytes):', masterSalt.toString('hex'));
console.log('Padded Salt (14 bytes):', paddedSalt.toString('hex'));
console.log('');

// Replicate werift's generateSessionKey
function generateSessionKey(masterKey, masterSalt, label) {
  const sessionKey = Buffer.from(masterSalt);
  
  // labelAndIndexOverKdr: [label, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
  const labelAndIndexOverKdr = Buffer.from([label, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
  
  // XOR from the end
  for (let i = labelAndIndexOverKdr.length - 1, j = sessionKey.length - 1; i >= 0; i--, j--) {
    sessionKey[j] = sessionKey[j] ^ labelAndIndexOverKdr[i];
  }
  
  // Pad to 16 bytes with [0x00, 0x00]
  const block = Buffer.concat([sessionKey, Buffer.from([0x00, 0x00])]);
  
  // Encrypt with AES-ECB (raw AES)
  const cipher = crypto.createCipheriv('aes-128-ecb', masterKey, null);
  cipher.setAutoPadding(false);
  return Buffer.concat([cipher.update(block), cipher.final()]);
}

// Replicate werift's generateSessionSalt
function generateSessionSalt(masterKey, masterSalt, label) {
  const sessionSalt = Buffer.from(masterSalt);
  
  const labelAndIndexOverKdr = Buffer.from([label, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
  
  // XOR from the end
  for (let i = labelAndIndexOverKdr.length - 1, j = sessionSalt.length - 1; i >= 0; i--, j--) {
    sessionSalt[j] = sessionSalt[j] ^ labelAndIndexOverKdr[i];
  }
  
  // Pad to 16 bytes
  const block = Buffer.concat([sessionSalt, Buffer.from([0x00, 0x00])]);
  
  // Encrypt with AES-ECB
  const cipher = crypto.createCipheriv('aes-128-ecb', masterKey, null);
  cipher.setAutoPadding(false);
  const output = Buffer.concat([cipher.update(block), cipher.final()]);
  
  // Return first 14 bytes
  return output.slice(0, 14);
}

// Labels from RFC 3711
const labelSrtpEncryption = 0x00;
const labelSrtpSalt = 0x02;
const labelSrtcpEncryption = 0x03;
const labelSrtcpSalt = 0x05;

// Derive session keys
const srtpSessionKey = generateSessionKey(masterKey, paddedSalt, labelSrtpEncryption);
const srtpSessionSalt = generateSessionSalt(masterKey, paddedSalt, labelSrtpSalt);
const srtcpSessionKey = generateSessionKey(masterKey, paddedSalt, labelSrtcpEncryption);
const srtcpSessionSalt = generateSessionSalt(masterKey, paddedSalt, labelSrtcpSalt);

console.log('=== Derived Keys ===');
console.log('SRTP Session Key:', srtpSessionKey.toString('hex'));
console.log('SRTP Session Salt:', srtpSessionSalt.toString('hex'));
console.log('SRTCP Session Key:', srtcpSessionKey.toString('hex'));
console.log('SRTCP Session Salt:', srtcpSessionSalt.toString('hex'));
console.log('');

// Create a simple RTCP Receiver Report packet
const rtcpPacket = Buffer.from([
  0x80, 0xc9, 0x00, 0x01,  // V=2, P=0, RC=0, PT=201, Length=1
  0xca, 0xfe, 0xba, 0xbe,  // SSRC
]);

console.log('=== RTCP Packet (plaintext) ===');
console.log('RTCP:', rtcpPacket.toString('hex'));
console.log('');

// Build IV for SRTCP (RFC 7714 Section 9.1)
// IV = 00 || SSRC || 0000 || SRTCP_index, XOR with salt
const ssrc = 0xcafebabe;
const srtcpIndex = 0;

function buildSrtcpNonce(salt, ssrc, index) {
  const nonce = Buffer.alloc(12);
  // First 2 bytes zero
  nonce[0] = 0;
  nonce[1] = 0;
  // SSRC at bytes 2-5
  nonce.writeUInt32BE(ssrc, 2);
  // 2 bytes zero padding
  nonce[6] = 0;
  nonce[7] = 0;
  // SRTCP index at bytes 8-11
  nonce.writeUInt32BE(index, 8);
  
  // XOR with first 12 bytes of salt
  for (let i = 0; i < 12; i++) {
    nonce[i] ^= salt[i];
  }
  return nonce;
}

// Build AAD for SRTCP
// AAD = RTCP Header (8 bytes) + SRTCP Index with E-flag (4 bytes)
function buildSrtcpAad(header, index) {
  const aad = Buffer.alloc(12);
  header.copy(aad, 0, 0, 8);
  // Set E-flag manually to avoid signed int issues
  aad[8] = 0x80 | ((index >> 24) & 0x7F);
  aad[9] = (index >> 16) & 0xFF;
  aad[10] = (index >> 8) & 0xFF;
  aad[11] = index & 0xFF;
  return aad;
}

const nonce = buildSrtcpNonce(srtcpSessionSalt, ssrc, srtcpIndex);
const aad = buildSrtcpAad(rtcpPacket, srtcpIndex);

console.log('=== SRTCP Encryption Parameters ===');
console.log('Nonce (12 bytes):', nonce.toString('hex'));
console.log('AAD (12 bytes):', aad.toString('hex'));
console.log('');

// Encrypt with AES-GCM
const header = rtcpPacket.slice(0, 8);
const plaintext = rtcpPacket.slice(8);  // Empty for this minimal packet

const cipher = crypto.createCipheriv('aes-128-gcm', srtcpSessionKey, nonce);
cipher.setAAD(aad);

let encrypted;
if (plaintext.length > 0) {
  encrypted = Buffer.concat([cipher.update(plaintext), cipher.final()]);
} else {
  cipher.update(Buffer.alloc(0));
  cipher.final();
  encrypted = Buffer.alloc(0);
}
const authTag = cipher.getAuthTag();

// Build final SRTCP packet: header + encrypted + tag + index
const indexBuf = Buffer.alloc(4);
// Set E-flag manually to avoid signed int issues
indexBuf[0] = 0x80 | ((srtcpIndex >> 24) & 0x7F);
indexBuf[1] = (srtcpIndex >> 16) & 0xFF;
indexBuf[2] = (srtcpIndex >> 8) & 0xFF;
indexBuf[3] = srtcpIndex & 0xFF;

const srtcpPacket = Buffer.concat([header, encrypted, authTag, indexBuf]);

console.log('=== Encrypted SRTCP ===');
console.log('Header:', header.toString('hex'));
console.log('Encrypted payload:', encrypted.toString('hex'));
console.log('Auth Tag:', authTag.toString('hex'));
console.log('SRTCP Index:', indexBuf.toString('hex'));
console.log('');
console.log('Full SRTCP packet:', srtcpPacket.toString('hex'));
console.log('Length:', srtcpPacket.length, 'bytes');
