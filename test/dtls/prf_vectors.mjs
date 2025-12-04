// Generate PRF test vectors using werift's implementation
import { createHash, createHmac } from "crypto";

// Copied from werift's prf.ts
function hmac(algorithm, secret, data) {
  const hash = createHmac(algorithm, secret);
  hash.update(data);
  return hash.digest();
}

function prfPHash(secret, seed, requestedLength, algorithm = "sha256") {
  const totalLength = requestedLength;
  const bufs = [];
  let Ai = seed;

  do {
    Ai = hmac(algorithm, secret, Ai);
    const output = hmac(algorithm, secret, Buffer.concat([Ai, seed]));
    bufs.push(output);
    requestedLength -= output.length;
  } while (requestedLength > 0);

  return Buffer.concat(bufs, totalLength);
}

function hash(algorithm, data) {
  return createHash(algorithm).update(data).digest();
}

function prfVerifyData(masterSecret, handshakes, label, size = 12) {
  const bytes = hash("sha256", handshakes);
  return prfPHash(
    masterSecret,
    Buffer.concat([Buffer.from(label), bytes]),
    size
  );
}

function prfVerifyDataClient(masterSecret, handshakes) {
  return prfVerifyData(masterSecret, handshakes, "client finished");
}

function prfExtendedMasterSecret(preMasterSecret, handshakes) {
  const sessionHash = hash("sha256", handshakes);
  const label = "extended master secret";
  return prfPHash(
    preMasterSecret,
    Buffer.concat([Buffer.from(label), sessionHash]),
    48
  );
}

// Test 1: Simple P_hash
console.log("=== Test 1: P_hash ===");
const secret1 = Buffer.from("secret");
const seed1 = Buffer.from("seed");
const phash1 = prfPHash(secret1, seed1, 48);
console.log("P_hash result:", phash1.toString("hex"));

// Test 2: verify_data with known master secret
console.log("\n=== Test 2: verify_data ===");
const masterSecret = Buffer.from([
  0xfb, 0x92, 0xd2, 0x2d, 0xab, 0xf6, 0xbf, 0xba,
  0x67, 0xbd, 0x7e, 0x94, 0xcd, 0x1a, 0x67, 0xa4,
  0xe1, 0xcd, 0x2c, 0xcd, 0x68, 0x67, 0x32, 0x8c,
  0xe5, 0x8f, 0x19, 0xf3, 0xe9, 0xaa, 0xbf, 0xc0,
  0xd3, 0xaa, 0x15, 0xea, 0xa3, 0x4a, 0xf9, 0x64,
  0xdf, 0x80, 0xd3, 0x8d, 0xc4, 0x02, 0xc4, 0x4d,
]);
const handshakes1 = Buffer.from([0x01, 0x02, 0x03, 0x04]);
const verifyData1 = prfVerifyDataClient(masterSecret, handshakes1);
console.log("verify_data:", verifyData1.toString("hex"));

// Test 3: Extended master secret
console.log("\n=== Test 3: Extended master secret ===");
const preMasterSecret = Buffer.from([
  0xab, 0x4b, 0xc4, 0xef, 0xa5, 0x7a, 0xfe, 0x66,
  0x31, 0xd4, 0xae, 0x39, 0x77, 0x75, 0x81, 0xd3,
  0xcc, 0x9e, 0xd2, 0xcf, 0x2b, 0xb2, 0xb9, 0x60,
  0x58, 0x2e, 0xa8, 0x00, 0x2c, 0xe3, 0xda, 0x08,
]);
const handshakes2 = Buffer.from([0x01, 0x02, 0x03, 0x04, 0x05]);
const extMasterSecret = prfExtendedMasterSecret(preMasterSecret, handshakes2);
console.log("master_secret:", extMasterSecret.toString("hex"));

// Test 4: Handshake hash
console.log("\n=== Test 4: Handshake hash ===");
const handshakeHash = hash("sha256", handshakes1);
console.log("handshake_hash:", handshakeHash.toString("hex"));

// Test 5: Real-world verify_data with specific hash
console.log("\n=== Test 5: Real verify_data with handshake hash ===");
// This is the actual handshake hash from a Chrome session:
const realHandshakeHash = Buffer.from([
  0x07, 0xa7, 0xbb, 0xa4, 0xc7, 0xbb, 0xff, 0x5d,
  0x0c, 0x0d, 0x0b, 0xd2, 0x80, 0x34, 0xb8, 0xb5,
  0xf7, 0x28, 0x9f, 0x3f, 0xc0, 0x87, 0x5b, 0xaf,
  0x1a, 0x44, 0xb2, 0xf1, 0xee, 0x72, 0x00, 0xd7,
]);
const realMasterSecret = Buffer.from([
  0x3c, 0xdf, 0x38, 0x04, 0xca, 0x4e, 0x1a, 0x00,
  0xd3, 0xd9, 0x4d, 0xd3, 0xa8, 0xd8, 0x70, 0x19,
  0x97, 0x0b, 0xbf, 0x81, 0xd9, 0xaa, 0x3e, 0x4c,
  0x77, 0x37, 0x15, 0x19, 0xdb, 0x40, 0x62, 0xa1,
  0x9a, 0xb9, 0x72, 0x06, 0x6f, 0xda, 0x06, 0x48,
  0xa6, 0x50, 0x59, 0x8e, 0xe6, 0xa6, 0x13, 0x51,
]);
// Compute verify_data using PRF(master_secret, "client finished", handshake_hash)
const realVerifyData = prfPHash(
  realMasterSecret,
  Buffer.concat([Buffer.from("client finished"), realHandshakeHash]),
  12
);
console.log("verify_data:", realVerifyData.toString("hex"));
