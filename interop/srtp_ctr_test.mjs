// Test if Ring might be using CTR mode despite negotiating GCM
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

// SRTCP packet from Ring
const srtcpPacket = Buffer.from([
  0x80, 0xc9, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // header (8 bytes)
  0x43, 0x03, 0xf2, 0xf7, 0x3a, 0x4e, 0x7f, 0xa1, // encrypted + HMAC
  0x4a, 0xda, 0x9b, 0x49, 0x8d, 0x57, 0xec, 0xce,
  0x80, 0x00, 0x00, 0x01, // SRTCP index with E-flag (4 bytes)
]);

// Key derivation for CTR mode (same labels as GCM for SRTCP)
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
  return Buffer.concat([cipher.update(block), cipher.final()]).subarray(0, 14);
}

// CTR mode SRTCP format (RFC 3711):
// | header(8) | encrypted_payload | HMAC-SHA1-80(10) | index(4) |
// For minimal RR with 0 payload: total = 8 + 0 + 10 + 4 = 22 bytes
// But we have 28 bytes, which is GCM format: header(8) + tag(16) + index(4)

console.log('=== Packet Format Analysis ===');
console.log('Packet length:', srtcpPacket.length, 'bytes');
console.log('GCM format would be: header(8) + tag(16) + index(4) = 28 bytes');
console.log('CTR format would be: header(8) + payload(0) + HMAC(10) + index(4) = 22 bytes');
console.log('Our packet is 28 bytes, so it matches GCM format');

// Parse packet
const ssrc = srtcpPacket.readUInt32BE(4);
let srtcpIndex = srtcpPacket.readUInt32BE(srtcpPacket.length - 4);
srtcpIndex &= 0x7FFFFFFF;

console.log('\n=== Trying to verify HMAC-SHA1-80 anyway ===');
// Maybe Ring put HMAC at the wrong position? Let's try various positions

// Get authentication key (label 4 for SRTCP auth)
const authKey = generateSessionKey(remoteMasterKey, remoteMasterSalt, 0x04);
console.log('Auth key:', authKey.toString('hex'));

// Try HMAC over header + index (traditional CTR format)
const hmacInput1 = Buffer.concat([
  srtcpPacket.subarray(0, 8),  // header
  srtcpPacket.subarray(srtcpPacket.length - 4),  // index
]);
const hmac1 = crypto.createHmac('sha1', authKey).update(hmacInput1).digest().subarray(0, 10);
console.log('HMAC over header+index:', hmac1.toString('hex'));
console.log('Bytes 8-18 from packet:', srtcpPacket.subarray(8, 18).toString('hex'));
console.log('Match:', hmac1.equals(srtcpPacket.subarray(8, 18)));

// Try including full "encrypted" portion
const hmacInput2 = srtcpPacket.subarray(0, srtcpPacket.length - 4);  // Everything except index
const hmac2 = crypto.createHmac('sha1', authKey).update(hmacInput2).digest().subarray(0, 10);
console.log('\nHMAC over packet except index:', hmac2.toString('hex'));

// Check if any 10-byte window matches
console.log('\n=== Checking for HMAC match anywhere in packet ===');
for (let i = 8; i <= srtcpPacket.length - 10 - 4; i++) {
  const window = srtcpPacket.subarray(i, i + 10);
  if (hmac1.equals(window)) {
    console.log('HMAC match at offset', i);
  }
  if (hmac2.equals(window)) {
    console.log('HMAC2 match at offset', i);
  }
}

// Let's also try raw master key/salt (no derivation)
console.log('\n=== Trying with raw master keys (no KDF) ===');
const srtcpSalt = generateSessionSalt(remoteMasterKey, remoteMasterSalt, 0x05).subarray(0, 12);
const srtcpKey = generateSessionKey(remoteMasterKey, remoteMasterSalt, 0x03);

// Build IV
const iv = Buffer.alloc(12);
iv.writeUInt32BE(ssrc, 2);
iv.writeUInt32BE(srtcpIndex, 8);
for (let i = 0; i < 12; i++) {
  iv[i] ^= srtcpSalt[i];
}

// Try raw master key with GCM
console.log('Trying GCM with raw master key...');
try {
  const cipher = crypto.createDecipheriv('aes-128-gcm', remoteMasterKey, iv);
  cipher.setAuthTag(srtcpPacket.subarray(8, 24));
  cipher.setAAD(Buffer.concat([srtcpPacket.subarray(0, 8), srtcpPacket.subarray(24)]));
  const dec = cipher.update(Buffer.alloc(0));
  cipher.final();
  console.log('SUCCESS with raw master key!');
} catch (e) {
  console.log('FAILED:', e.message);
}

// Maybe the issue is that we're getting client/server keys swapped at the TLS exporter level?
// Let's compute what the keys would be if we swapped the randoms in the PRF
console.log('\n=== What if TLS random order is wrong? ===');
console.log('This would require access to the DTLS handshake parameters...');
console.log('But both client and server should compute the same keying material');
console.log('since they both have access to the same randoms.');

// Final check - verify the GCM auth tag is at least well-formed (16 bytes)
console.log('\n=== Auth Tag Analysis ===');
const authTag = srtcpPacket.subarray(8, 24);
console.log('Auth tag (16 bytes):', authTag.toString('hex'));
console.log('This should be a valid GCM authentication tag.');
console.log('If it were HMAC-SHA1-80, it would only be 10 bytes.');
