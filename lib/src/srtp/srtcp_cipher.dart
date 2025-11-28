import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:webrtc_dart/src/srtp/const.dart';
import 'package:webrtc_dart/src/srtp/rtcp_packet.dart';

/// SRTCP Cipher for AES-GCM encryption/decryption
/// RFC 3711 Section 3.4 - SRTCP
///
/// SRTCP adds an index and E-flag to encrypted RTCP packets:
/// | Encrypted RTCP | SRTCP Index (31 bits) + E-flag (1 bit) | Auth Tag |
class SrtcpCipher {
  /// Master key
  final Uint8List masterKey;

  /// Master salt
  final Uint8List masterSalt;

  /// SRTCP index for each SSRC (packet counter)
  final Map<int, int> _indexMap = {};

  SrtcpCipher({
    required this.masterKey,
    required this.masterSalt,
  });

  /// Encrypt RTCP packet
  /// Returns encrypted SRTCP packet bytes
  Future<Uint8List> encrypt(RtcpPacket packet) async {
    // Get and increment SRTCP index for this SSRC
    final index = _getAndIncrementIndex(packet.ssrc);

    // Derive session keys
    final sessionKey = _deriveSessionKey(packet.ssrc, index);
    final sessionSalt = _deriveSessionSalt(packet.ssrc, index);

    // Build nonce (IV) for SRTCP
    final nonce = _buildNonce(sessionSalt, packet.ssrc, index);

    // Serialize RTCP header (first 8 bytes - authenticated but not encrypted)
    final header = packet.serialize().sublist(0, RtcpPacket.headerSize);

    // Get payload (everything after header - will be encrypted)
    final plaintext = packet.serialize().sublist(RtcpPacket.headerSize);

    // Encrypt payload using AES-GCM
    final gcm = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(sessionKey),
      128, // 128-bit auth tag
      nonce,
      header, // Additional authenticated data (RTCP header)
    );

    gcm.init(true, params);

    // Allocate output buffer (encrypted payload + auth tag)
    final outputLength = plaintext.length + SrtpAuthTagSize.tag128;
    final encrypted = Uint8List(outputLength);

    // Encrypt
    var outOff = gcm.processBytes(plaintext, 0, plaintext.length, encrypted, 0);
    outOff += gcm.doFinal(encrypted, outOff);

    // Build SRTCP packet: header + encrypted_payload + auth_tag + index
    // Index includes E-flag in MSB
    final indexWithEFlag = index | srtcpEFlagBit; // Set E-flag (encrypted)

    final result = Uint8List(header.length + encrypted.length + srtcpIndexLength);
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
    result.setRange(offset, offset + srtcpIndexLength, indexBuffer.buffer.asUint8List());

    return result;
  }

  /// Decrypt SRTCP packet
  /// Returns decrypted RTCP packet
  Future<RtcpPacket> decrypt(Uint8List srtcpPacket) async {
    if (srtcpPacket.length < RtcpPacket.headerSize + SrtpAuthTagSize.tag128 + srtcpIndexLength) {
      throw FormatException('SRTCP packet too short: ${srtcpPacket.length} bytes');
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

    // Extract encrypted data (everything between header and index, including auth tag)
    final encryptedEnd = indexStart;
    final encryptedData = srtcpPacket.sublist(RtcpPacket.headerSize, encryptedEnd);

    // Derive session keys
    final sessionKey = _deriveSessionKey(ssrc, index);
    final sessionSalt = _deriveSessionSalt(ssrc, index);

    // Build nonce (IV)
    final nonce = _buildNonce(sessionSalt, ssrc, index);

    // Decrypt using AES-GCM
    final gcm = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(sessionKey),
      128, // 128-bit auth tag
      nonce,
      header, // Additional authenticated data
    );

    gcm.init(false, params);

    // Allocate output buffer (plaintext payload)
    final outputLength = encryptedData.length - SrtpAuthTagSize.tag128;
    final plaintext = Uint8List(outputLength);

    // Decrypt
    try {
      var outOff = gcm.processBytes(encryptedData, 0, encryptedData.length, plaintext, 0);
      outOff += gcm.doFinal(plaintext, outOff);

      // Reconstruct full RTCP packet
      final fullPacket = Uint8List(header.length + plaintext.length);
      fullPacket.setRange(0, header.length, header);
      fullPacket.setRange(header.length, fullPacket.length, plaintext);

      return RtcpPacket.parse(fullPacket);
    } catch (e) {
      throw StateError('SRTCP decryption failed: $e');
    }
  }

  /// Get and increment SRTCP index for an SSRC
  int _getAndIncrementIndex(int ssrc) {
    final current = _indexMap[ssrc] ?? 0;
    _indexMap[ssrc] = (current + 1) & 0x7FFFFFFF; // Keep 31 bits (E-flag is separate)
    return current;
  }

  /// Derive session key from master key
  /// RFC 3711 Section 4.3
  Uint8List _deriveSessionKey(int ssrc, int index) {
    // Simplified: In full implementation, use proper key derivation with label
    // For now, use master key directly
    return masterKey;
  }

  /// Derive session salt from master salt
  /// RFC 3711 Section 4.3
  Uint8List _deriveSessionSalt(int ssrc, int index) {
    // Simplified: In full implementation, use proper salt derivation
    // For now, use master salt directly
    return masterSalt;
  }

  /// Build nonce (IV) for AES-GCM
  /// RFC 3711 Section 4.1.1
  ///
  /// For SRTCP: Nonce = (SSRC || index) XOR salt
  Uint8List _buildNonce(Uint8List salt, int ssrc, int index) {
    final nonce = Uint8List(12);

    // SSRC (32-bit) at bytes 0-3
    nonce[0] = (ssrc >> 24) & 0xFF;
    nonce[1] = (ssrc >> 16) & 0xFF;
    nonce[2] = (ssrc >> 8) & 0xFF;
    nonce[3] = ssrc & 0xFF;

    // Index (31-bit) at bytes 4-7, pad bytes 8-11
    nonce[4] = (index >> 24) & 0xFF;
    nonce[5] = (index >> 16) & 0xFF;
    nonce[6] = (index >> 8) & 0xFF;
    nonce[7] = index & 0xFF;
    nonce[8] = 0;
    nonce[9] = 0;
    nonce[10] = 0;
    nonce[11] = 0;

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
}
