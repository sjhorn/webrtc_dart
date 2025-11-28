import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/handshake/extensions/use_srtp.dart';
import 'package:webrtc_dart/src/srtp/srtp_cipher.dart';
import 'package:webrtc_dart/src/srtp/srtcp_cipher.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';
import 'package:webrtc_dart/src/srtp/rtcp_packet.dart';
import 'package:webrtc_dart/src/srtp/key_derivation.dart';

/// SRTP Session
/// Manages SRTP/SRTCP encryption and decryption for a media session
class SrtpSession {
  /// SRTP protection profile
  final SrtpProtectionProfile profile;

  /// Local master key
  final Uint8List localMasterKey;

  /// Local master salt
  final Uint8List localMasterSalt;

  /// Remote master key
  final Uint8List remoteMasterKey;

  /// Remote master salt
  final Uint8List remoteMasterSalt;

  /// SRTP cipher for outgoing packets
  late final SrtpCipher _srtpOutbound;

  /// SRTP cipher for incoming packets
  late final SrtpCipher _srtpInbound;

  /// SRTCP cipher for outgoing packets
  late final SrtcpCipher _srtcpOutbound;

  /// SRTCP cipher for incoming packets
  late final SrtcpCipher _srtcpInbound;

  SrtpSession({
    required this.profile,
    required this.localMasterKey,
    required this.localMasterSalt,
    required this.remoteMasterKey,
    required this.remoteMasterSalt,
  }) {
    // Initialize ciphers
    _srtpOutbound = SrtpCipher(
      masterKey: localMasterKey,
      masterSalt: localMasterSalt,
    );

    _srtpInbound = SrtpCipher(
      masterKey: remoteMasterKey,
      masterSalt: remoteMasterSalt,
    );

    _srtcpOutbound = SrtcpCipher(
      masterKey: localMasterKey,
      masterSalt: localMasterSalt,
    );

    _srtcpInbound = SrtcpCipher(
      masterKey: remoteMasterKey,
      masterSalt: remoteMasterSalt,
    );
  }

  /// Create SRTP session from DTLS-exported keying material
  factory SrtpSession.fromKeyMaterial({
    required SrtpProtectionProfile profile,
    required Uint8List keyingMaterial,
    required bool isClient,
  }) {
    // Extract keys based on profile
    final keyLen = _getKeyLength(profile);
    final saltLen = _getSaltLength(profile);

    if (keyingMaterial.length < keyLen * 2 + saltLen * 2) {
      throw ArgumentError('Insufficient keying material');
    }

    var offset = 0;

    // Client write key
    final clientKey = keyingMaterial.sublist(offset, offset + keyLen);
    offset += keyLen;

    // Server write key
    final serverKey = keyingMaterial.sublist(offset, offset + keyLen);
    offset += keyLen;

    // Client write salt
    final clientSalt = keyingMaterial.sublist(offset, offset + saltLen);
    offset += saltLen;

    // Server write salt
    final serverSalt = keyingMaterial.sublist(offset, offset + saltLen);

    // Assign based on role
    if (isClient) {
      return SrtpSession(
        profile: profile,
        localMasterKey: clientKey,
        localMasterSalt: clientSalt,
        remoteMasterKey: serverKey,
        remoteMasterSalt: serverSalt,
      );
    } else {
      return SrtpSession(
        profile: profile,
        localMasterKey: serverKey,
        localMasterSalt: serverSalt,
        remoteMasterKey: clientKey,
        remoteMasterSalt: clientSalt,
      );
    }
  }

  /// Encrypt outgoing RTP packet
  Future<Uint8List> encryptRtp(RtpPacket packet) async {
    return await _srtpOutbound.encrypt(packet);
  }

  /// Decrypt incoming SRTP packet
  Future<RtpPacket> decryptSrtp(Uint8List srtpPacket) async {
    return await _srtpInbound.decrypt(srtpPacket);
  }

  /// Encrypt outgoing RTCP packet
  Future<Uint8List> encryptRtcp(RtcpPacket packet) async {
    return await _srtcpOutbound.encrypt(packet);
  }

  /// Decrypt incoming SRTCP packet
  Future<RtcpPacket> decryptSrtcp(Uint8List srtcpPacket) async {
    return await _srtcpInbound.decrypt(srtcpPacket);
  }

  /// Reset session state
  void reset() {
    _srtpOutbound.reset();
    _srtpInbound.reset();
    _srtcpOutbound.reset();
    _srtcpInbound.reset();
  }

  /// Get key length for profile
  static int _getKeyLength(SrtpProtectionProfile profile) {
    switch (profile) {
      case SrtpProtectionProfile.srtpAes128CmHmacSha1_80:
      case SrtpProtectionProfile.srtpAes128CmHmacSha1_32:
      case SrtpProtectionProfile.srtpAeadAes128Gcm:
        return 16; // AES-128
      case SrtpProtectionProfile.srtpAeadAes256Gcm:
        return 32; // AES-256
    }
  }

  /// Get salt length for profile
  static int _getSaltLength(SrtpProtectionProfile profile) {
    switch (profile) {
      case SrtpProtectionProfile.srtpAes128CmHmacSha1_80:
      case SrtpProtectionProfile.srtpAes128CmHmacSha1_32:
        return 14; // HMAC-SHA1 uses 14-byte salt
      case SrtpProtectionProfile.srtpAeadAes128Gcm:
      case SrtpProtectionProfile.srtpAeadAes256Gcm:
        return 12; // GCM uses 12-byte salt
    }
  }

  @override
  String toString() {
    return 'SrtpSession(profile=$profile)';
  }
}
