import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/handshake/extensions/use_srtp.dart';
import 'package:webrtc_dart/src/srtp/srtp_cipher.dart';
import 'package:webrtc_dart/src/srtp/srtcp_cipher.dart';
import 'package:webrtc_dart/src/srtp/srtp_cipher_ctr.dart';
import 'package:webrtc_dart/src/srtp/rtp_packet.dart';
import 'package:webrtc_dart/src/srtp/rtcp_packet.dart';
import 'package:webrtc_dart/src/srtp/key_derivation.dart';

/// SRTP Session
/// Manages SRTP/SRTCP encryption and decryption for a media session
///
/// Supports multiple cipher profiles:
/// - AES-128-CM-HMAC-SHA1-80/32: Counter mode with HMAC authentication
/// - AES-GCM-128/256: Authenticated encryption with associated data
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

  /// Whether to use CTR mode (true) or GCM mode (false)
  final bool _useCtrMode;

  /// CTR cipher for outgoing packets (AES-CM-HMAC-SHA1)
  SrtpCipherCtr? _ctrOutbound;

  /// CTR cipher for incoming packets (AES-CM-HMAC-SHA1)
  SrtpCipherCtr? _ctrInbound;

  /// GCM cipher for outgoing RTP (AES-GCM)
  SrtpCipher? _srtpOutbound;

  /// GCM cipher for incoming RTP (AES-GCM)
  SrtpCipher? _srtpInbound;

  /// GCM cipher for outgoing RTCP (AES-GCM)
  SrtcpCipher? _srtcpOutbound;

  /// GCM cipher for incoming RTCP (AES-GCM)
  SrtcpCipher? _srtcpInbound;

  SrtpSession({
    required this.profile,
    required this.localMasterKey,
    required this.localMasterSalt,
    required this.remoteMasterKey,
    required this.remoteMasterSalt,
  }) : _useCtrMode = _isCtrProfile(profile) {
    // Initialize ciphers based on profile
    if (_useCtrMode) {
      // AES-128-CM-HMAC-SHA1-80/32 (CTR mode + HMAC)
      _ctrOutbound = SrtpCipherCtr.fromMasterKey(
        masterKey: localMasterKey,
        masterSalt: localMasterSalt,
      );

      _ctrInbound = SrtpCipherCtr.fromMasterKey(
        masterKey: remoteMasterKey,
        masterSalt: remoteMasterSalt,
      );
    } else {
      // AES-GCM (AEAD) - RFC 7714 requires key derivation
      // Key derivation uses the AES_CM PRF from RFC 3711
      // The 96-bit (12-byte) master salt must be padded to 112 bits (14 bytes)
      // for use with the KDF, then the derived 14-byte salt is truncated to 12 bytes
      //
      // Per werift and RFC 7714:
      // - SRTP uses label 0 for key, label 2 for salt
      // - SRTCP uses label 3 for key, label 5 for salt

      // Derive outbound (local) SRTP keys
      final localSrtpKey = SrtpKeyDerivation.generateSessionKey(
        masterKey: localMasterKey,
        masterSalt: localMasterSalt,
        label: SrtpKeyDerivation.labelSrtpEncryption,
      );
      final localSrtpSalt = SrtpKeyDerivation.generateSessionSalt(
        masterKey: localMasterKey,
        masterSalt: localMasterSalt,
        label: SrtpKeyDerivation.labelSrtpSalt,
      );

      // Derive inbound (remote) SRTP keys
      final remoteSrtpKey = SrtpKeyDerivation.generateSessionKey(
        masterKey: remoteMasterKey,
        masterSalt: remoteMasterSalt,
        label: SrtpKeyDerivation.labelSrtpEncryption,
      );
      final remoteSrtpSalt = SrtpKeyDerivation.generateSessionSalt(
        masterKey: remoteMasterKey,
        masterSalt: remoteMasterSalt,
        label: SrtpKeyDerivation.labelSrtpSalt,
      );

      // Derive outbound (local) SRTCP keys
      final localSrtcpKey = SrtpKeyDerivation.generateSessionKey(
        masterKey: localMasterKey,
        masterSalt: localMasterSalt,
        label: SrtpKeyDerivation.labelSrtcpEncryption,
      );
      final localSrtcpSalt = SrtpKeyDerivation.generateSessionSalt(
        masterKey: localMasterKey,
        masterSalt: localMasterSalt,
        label: SrtpKeyDerivation.labelSrtcpSalt,
      );

      // Derive inbound (remote) SRTCP keys
      final remoteSrtcpKey = SrtpKeyDerivation.generateSessionKey(
        masterKey: remoteMasterKey,
        masterSalt: remoteMasterSalt,
        label: SrtpKeyDerivation.labelSrtcpEncryption,
      );
      final remoteSrtcpSalt = SrtpKeyDerivation.generateSessionSalt(
        masterKey: remoteMasterKey,
        masterSalt: remoteMasterSalt,
        label: SrtpKeyDerivation.labelSrtcpSalt,
      );

      // GCM uses 12-byte salt (derived salt is 14 bytes, truncate to 12)
      _srtpOutbound = SrtpCipher(
        masterKey: localSrtpKey,
        masterSalt: localSrtpSalt.sublist(0, 12),
      );

      _srtpInbound = SrtpCipher(
        masterKey: remoteSrtpKey,
        masterSalt: remoteSrtpSalt.sublist(0, 12),
      );

      _srtcpOutbound = SrtcpCipher(
        masterKey: localSrtcpKey,
        masterSalt: localSrtcpSalt.sublist(0, 12),
      );

      _srtcpInbound = SrtcpCipher(
        masterKey: remoteSrtcpKey,
        masterSalt: remoteSrtcpSalt.sublist(0, 12),
      );
    }
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
    if (_useCtrMode) {
      return _ctrOutbound!.encryptRtp(packet);
    } else {
      return await _srtpOutbound!.encrypt(packet);
    }
  }

  /// Decrypt incoming SRTP packet
  Future<RtpPacket> decryptSrtp(Uint8List srtpPacket) async {
    if (_useCtrMode) {
      return _ctrInbound!.decryptSrtp(srtpPacket);
    } else {
      return await _srtpInbound!.decrypt(srtpPacket);
    }
  }

  /// Encrypt outgoing RTCP packet
  Future<Uint8List> encryptRtcp(RtcpPacket packet) async {
    if (_useCtrMode) {
      return _ctrOutbound!.encryptRtcp(packet);
    } else {
      return await _srtcpOutbound!.encrypt(packet);
    }
  }

  /// Decrypt incoming SRTCP packet
  Future<RtcpPacket> decryptSrtcp(Uint8List srtcpPacket) async {
    if (_useCtrMode) {
      return _ctrInbound!.decryptSrtcp(srtcpPacket);
    } else {
      return await _srtcpInbound!.decrypt(srtcpPacket);
    }
  }

  /// Reset session state
  void reset() {
    if (_useCtrMode) {
      _ctrOutbound?.reset();
      _ctrInbound?.reset();
    } else {
      _srtpOutbound?.reset();
      _srtpInbound?.reset();
      _srtcpOutbound?.reset();
      _srtcpInbound?.reset();
    }
  }

  /// Check if profile uses CTR mode
  static bool _isCtrProfile(SrtpProtectionProfile profile) {
    switch (profile) {
      case SrtpProtectionProfile.srtpAes128CmHmacSha1_80:
      case SrtpProtectionProfile.srtpAes128CmHmacSha1_32:
        return true;
      case SrtpProtectionProfile.srtpAeadAes128Gcm:
      case SrtpProtectionProfile.srtpAeadAes256Gcm:
        return false;
    }
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
