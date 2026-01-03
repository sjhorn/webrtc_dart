import 'dart:typed_data';

import 'package:webrtc_dart/src/crypto/aes_gcm.dart';
import 'package:webrtc_dart/src/crypto/crypto_config.dart';
import 'package:webrtc_dart/src/srtp/const.dart';
import 'package:webrtc_dart/src/srtp/rtcp_packet.dart';

/// SRTCP Cipher for AES-GCM encryption/decryption
/// RFC 7714 - AES-GCM Authenticated Encryption in SRTCP
///
/// SRTCP packet format (RFC 7714 Section 9):
/// | RTCP Header (8 bytes) | Encrypted Payload | Auth Tag (16 bytes) | SRTCP Index (4 bytes) |
///
/// The SRTCP index has the E-flag (encryption flag) in the MSB.
/// AAD (Additional Authenticated Data) = RTCP Header (8 bytes) + SRTCP Index with E-flag (4 bytes)
///
/// Uses [CryptoConfig] to select between pure Dart and native FFI implementations.
/// Key derivation should be done by SrtpSession before passing to this cipher.
class SrtcpCipher {
  /// Session encryption key (derived from master key)
  final Uint8List masterKey;

  /// Session salt (derived from master salt, 14 bytes - only first 12 used for GCM IV)
  final Uint8List masterSalt;

  /// SRTCP index for each SSRC (packet counter)
  final Map<int, int> _indexMap = {};

  /// AES-GCM cipher instance (reused across packets)
  late final AesGcmCipher _cipher;

  SrtcpCipher({
    required this.masterKey,
    required this.masterSalt,
  }) {
    _cipher = CryptoConfig.createAesGcm();
  }

  /// Encrypt RTCP packet
  /// Returns encrypted SRTCP packet bytes
  Future<Uint8List> encrypt(RtcpPacket packet) async {
    return encryptBytes(packet.serialize());
  }

  /// Encrypt compound RTCP packet (pre-serialized bytes)
  /// Used for RTCP compound packets (SR/RR + SDES) per RFC 3550
  Future<Uint8List> encryptBytes(Uint8List fullRtcp) async {
    // Extract SSRC from header (bytes 4-7)
    final ssrc = ByteData.sublistView(fullRtcp, 4, 8).getUint32(0);

    // Get and increment SRTCP index for this SSRC
    final index = _getAndIncrementIndex(ssrc);

    // Build nonce (IV) for SRTCP
    final nonce = _buildNonce(masterSalt, ssrc, index);

    // Extract header (first 8 bytes) and payload
    final header = fullRtcp.sublist(0, RtcpPacket.headerSize);
    final plaintext = fullRtcp.sublist(RtcpPacket.headerSize);

    // SRTCP Index with E-flag (encryption flag set)
    final indexWithEFlag = index | srtcpEFlagBit;

    // Build AAD: RTCP Header (8 bytes) + SRTCP Index with E-flag (4 bytes)
    // Per RFC 7714 Section 17
    final aad = _buildAad(header, indexWithEFlag);

    // Encrypt payload using AES-GCM (returns ciphertext + tag)
    final encrypted = await _cipher.encrypt(
      key: masterKey,
      nonce: nonce,
      plaintext: plaintext,
      aad: aad,
    );

    // Build SRTCP packet: header + encrypted_payload + auth_tag + index
    final result =
        Uint8List(header.length + encrypted.length + srtcpIndexLength);
    var offset = 0;

    // Copy header
    result.setRange(offset, offset + header.length, header);
    offset += header.length;

    // Copy encrypted payload + auth tag
    result.setRange(offset, offset + encrypted.length, encrypted);
    offset += encrypted.length;

    // Append SRTCP index with E-flag
    final indexBuffer = ByteData(srtcpIndexLength);
    indexBuffer.setUint32(0, indexWithEFlag);
    result.setRange(
        offset, offset + srtcpIndexLength, indexBuffer.buffer.asUint8List());

    return result;
  }

  /// Decrypt SRTCP packet
  /// Returns decrypted RTCP packet
  Future<RtcpPacket> decrypt(Uint8List srtcpPacket) async {
    if (srtcpPacket.length <
        RtcpPacket.headerSize + SrtpAuthTagSize.tag128 + srtcpIndexLength) {
      throw FormatException(
          'SRTCP packet too short: ${srtcpPacket.length} bytes');
    }

    // Extract SRTCP index from end of packet
    final indexStart = srtcpPacket.length - srtcpIndexLength;
    final indexBuffer = ByteData.sublistView(srtcpPacket, indexStart);
    final indexWithEFlag = indexBuffer.getUint32(0);

    // Check E-flag
    final encrypted = (indexWithEFlag & srtcpEFlagBit) != 0;
    if (!encrypted) {
      throw FormatException('SRTCP packet is not encrypted (E-flag not set)');
    }

    // Extract index (clear E-flag)
    final index = indexWithEFlag & ~srtcpEFlagBit;

    // Extract header (first 8 bytes)
    final header = srtcpPacket.sublist(0, RtcpPacket.headerSize);

    // Parse SSRC from header
    final headerBuffer = ByteData.sublistView(header);
    final ssrc = headerBuffer.getUint32(4);

    // Extract encrypted data + auth tag (everything between header and index)
    final encryptedEnd = indexStart;
    final encryptedData =
        srtcpPacket.sublist(RtcpPacket.headerSize, encryptedEnd);

    // Build nonce (IV)
    final nonce = _buildNonce(masterSalt, ssrc, index);

    // Build AAD: RTCP Header (8 bytes) + SRTCP Index with E-flag (4 bytes)
    // Per RFC 7714 Section 17
    final aad = _buildAad(header, indexWithEFlag);

    // Decrypt using AES-GCM
    try {
      final plaintext = await _cipher.decrypt(
        key: masterKey,
        nonce: nonce,
        ciphertext: encryptedData,
        aad: aad,
      );

      // Reconstruct full RTCP packet
      final fullPacket = Uint8List(header.length + plaintext.length);
      fullPacket.setRange(0, header.length, header);
      fullPacket.setRange(header.length, fullPacket.length, plaintext);

      return RtcpPacket.parse(fullPacket);
    } catch (e) {
      throw StateError('SRTCP decryption failed: $e');
    }
  }

  /// Build AAD (Additional Authenticated Data) for SRTCP
  /// RFC 7714 Section 17: AAD = RTCP Header (8 bytes) + SRTCP Index (4 bytes)
  Uint8List _buildAad(Uint8List header, int indexWithEFlag) {
    final aad = Uint8List(RtcpPacket.headerSize + srtcpIndexLength);

    // Copy header (8 bytes)
    aad.setRange(0, RtcpPacket.headerSize, header);

    // Append index with E-flag (4 bytes, big-endian)
    aad[8] = (indexWithEFlag >> 24) & 0xFF;
    aad[9] = (indexWithEFlag >> 16) & 0xFF;
    aad[10] = (indexWithEFlag >> 8) & 0xFF;
    aad[11] = indexWithEFlag & 0xFF;

    return aad;
  }

  /// Get and increment SRTCP index for an SSRC
  int _getAndIncrementIndex(int ssrc) {
    final current = _indexMap[ssrc] ?? 0;
    _indexMap[ssrc] =
        (current + 1) & 0x7FFFFFFF; // Keep 31 bits (E-flag is separate)
    return current;
  }

  /// Build nonce (IV) for AES-GCM
  /// RFC 7714 Section 9.1
  ///
  /// For SRTCP: IV = 00 || SSRC || 0000 || SRTCP_index, XOR with salt
  /// Bytes: [0, 0, SSRC(4 bytes), 0, 0, index(4 bytes)]
  Uint8List _buildNonce(Uint8List salt, int ssrc, int index) {
    final nonce = Uint8List(12);

    // First 2 bytes are zero
    nonce[0] = 0;
    nonce[1] = 0;

    // SSRC (32-bit) at bytes 2-5
    nonce[2] = (ssrc >> 24) & 0xFF;
    nonce[3] = (ssrc >> 16) & 0xFF;
    nonce[4] = (ssrc >> 8) & 0xFF;
    nonce[5] = ssrc & 0xFF;

    // 2 bytes zero padding at bytes 6-7
    nonce[6] = 0;
    nonce[7] = 0;

    // SRTCP index (32-bit) at bytes 8-11
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

  /// Reset cipher state
  void reset() {
    _indexMap.clear();
  }

  /// Dispose of cipher resources
  void dispose() {
    _cipher.dispose();
  }
}
