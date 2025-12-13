// Test werift's exact GCM decryption approach (no auth tag verification)
import crypto from 'crypto';

// Fresh capture - Remote master keys
const remoteMasterKey = Buffer.from([
  0x76, 0xa7, 0xf2, 0x6f, 0x80, 0xda, 0x77, 0x65,
  0x7b, 0x8f, 0xcd, 0xdc, 0x59, 0xda, 0x87, 0x3f,
]);
const remoteMasterSalt = Buffer.from([
  0xd7, 0xeb, 0xaf, 0xd2, 0x30, 0xc5, 0xf4, 0x6c,
  0x67, 0x8c, 0x14, 0x01,
]);

// SRTCP packet from Ring
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
  return Buffer.concat([cipher.update(block), cipher.final()]).subarray(0, 14);
}

// werift buffer writer helper
function createBufferWriter(sizes, bigEndian) {
  return function(values) {
    const totalSize = sizes.reduce((a, b) => a + b, 0);
    const buf = Buffer.alloc(totalSize);
    let offset = 0;
    for (let i = 0; i < sizes.length; i++) {
      const size = sizes[i];
      const value = values[i];
      if (size === 2) {
        buf.writeUInt16BE(value, offset);
      } else if (size === 4) {
        buf.writeUInt32BE(value, offset);
      }
      offset += size;
    }
    return buf;
  };
}

// Derive keys
const srtcpSessionKey = generateSessionKey(remoteMasterKey, remoteMasterSalt, 0x03);
const srtcpSessionSalt = generateSessionSalt(remoteMasterKey, remoteMasterSalt, 0x05).subarray(0, 12);

console.log('=== Keys ===');
console.log('SRTCP key:', srtcpSessionKey.toString('hex'));
console.log('SRTCP salt:', srtcpSessionSalt.toString('hex'));

// werift-style IV writer
const rtcpIvWriter = createBufferWriter([2, 4, 2, 4], true);
const aadWriter = createBufferWriter([4], true);

// Parse packet
const encrypted = srtcpPacket;
const srtcpIndexSize = 4;
const rtcpEncryptionFlag = 0x80;
const aeadAuthTagLen = 16;

const aadPos = encrypted.length - srtcpIndexSize;
const ssrc = encrypted.readUInt32BE(4);
let srtcpIndex = encrypted.readUInt32BE(encrypted.length - 4);
srtcpIndex &= ~(rtcpEncryptionFlag << 24);

console.log('\n=== Packet Info ===');
console.log('SSRC:', ssrc);
console.log('srtcpIndex (without E-flag):', srtcpIndex);
console.log('aadPos:', aadPos);
console.log('encrypted.slice(8, aadPos):', encrypted.slice(8, aadPos).toString('hex'));

// Build IV exactly like werift
const iv = rtcpIvWriter([0, ssrc, 0, srtcpIndex]);
for (let i = 0; i < iv.length; i++) {
  iv[i] ^= srtcpSessionSalt[i];
}

console.log('\n=== IV ===');
console.log('IV:', iv.toString('hex'));

// Build AAD exactly like werift
const aad = Buffer.concat([
  encrypted.subarray(0, 8),
  aadWriter([srtcpIndex]),
]);
aad[8] |= rtcpEncryptionFlag;

console.log('AAD:', aad.toString('hex'));

// Try werift-style decryption (NO auth tag verification!)
console.log('\n=== werift-style Decryption (no auth verification) ===');
try {
  const cipher = crypto.createDecipheriv('aes-128-gcm', srtcpSessionKey, iv);
  cipher.setAAD(aad);
  // werift passes the full encrypted payload including the auth tag to update()
  const dec = cipher.update(encrypted.slice(8, aadPos));
  // werift does NOT call cipher.final() - it skips auth verification!
  console.log('Decrypted (werift-style, unverified):', dec.toString('hex'));
  console.log('Length:', dec.length, 'bytes');
} catch (e) {
  console.log('FAILED:', e.message);
}

// Try proper GCM decryption with auth tag
console.log('\n=== Proper GCM Decryption (with auth verification) ===');
try {
  const ciphertext = encrypted.slice(8, aadPos - aeadAuthTagLen);
  const authTag = encrypted.slice(aadPos - aeadAuthTagLen, aadPos);

  console.log('Ciphertext length:', ciphertext.length);
  console.log('Auth tag:', authTag.toString('hex'));

  const cipher = crypto.createDecipheriv('aes-128-gcm', srtcpSessionKey, iv);
  cipher.setAuthTag(authTag);
  cipher.setAAD(aad);
  const dec = cipher.update(ciphertext);
  cipher.final();  // This verifies the auth tag
  console.log('SUCCESS! Decrypted:', dec.toString('hex'));
} catch (e) {
  console.log('FAILED:', e.message);
}

// The issue: for a minimal RTCP RR with no payload:
// header(8) + auth_tag(16) + srtcp_index(4) = 28 bytes
// werift's approach: encrypted.slice(8, 24) = 16 bytes (the auth tag itself!)
// It treats the auth tag as ciphertext and "decrypts" it without verification

console.log('\n=== Analysis ===');
console.log('For a minimal RTCP packet (28 bytes):');
console.log('- header: 8 bytes (indices 0-7)');
console.log('- auth_tag: 16 bytes (indices 8-23)');
console.log('- srtcp_index: 4 bytes (indices 24-27)');
console.log('werift slices [8, 24) = just the auth tag, treating it as ciphertext');
console.log('This works because werift never calls cipher.final() to verify!');
