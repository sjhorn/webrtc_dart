import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/handshake/const.dart';
import 'package:webrtc_dart/src/dtls/handshake/extensions/extension.dart';

/// SRTP Protection Profiles
/// RFC 5764 Section 4.1.2
enum SrtpProtectionProfile {
  srtpAes128CmHmacSha1_80(0x0001),
  srtpAes128CmHmacSha1_32(0x0002),
  srtpAeadAes128Gcm(0x0007),
  srtpAeadAes256Gcm(0x0008);

  final int value;
  const SrtpProtectionProfile(this.value);

  static SrtpProtectionProfile? fromValue(int value) {
    for (final profile in SrtpProtectionProfile.values) {
      if (profile.value == value) return profile;
    }
    return null;
  }
}

/// use_srtp Extension
/// RFC 5764 Section 4.1.1
///
/// Used to negotiate SRTP protection profiles for WebRTC
class UseSrtpExtension extends Extension {
  final List<SrtpProtectionProfile> profiles;
  final Uint8List mki; // Master Key Identifier (optional)

  UseSrtpExtension({
    required this.profiles,
    Uint8List? mki,
  }) : mki = mki ?? Uint8List(0);

  @override
  ExtensionType get type => ExtensionType.useSrtp;

  @override
  Uint8List serializeData() {
    final result = Uint8List(2 + profiles.length * 2 + 1 + mki.length);
    final buffer = ByteData.sublistView(result);

    // Protection profiles length (2 bytes)
    buffer.setUint16(0, profiles.length * 2);

    // Write each profile (2 bytes each)
    var offset = 2;
    for (final profile in profiles) {
      buffer.setUint16(offset, profile.value);
      offset += 2;
    }

    // MKI length (1 byte)
    buffer.setUint8(offset, mki.length);
    offset++;

    // MKI data
    if (mki.isNotEmpty) {
      result.setRange(offset, offset + mki.length, mki);
    }

    return result;
  }

  /// Parse from extension data
  static UseSrtpExtension parse(Uint8List data) {
    if (data.length < 3) {
      throw FormatException('use_srtp extension too short');
    }

    final buffer = ByteData.sublistView(data);
    final profilesLength = buffer.getUint16(0);

    if (data.length < 2 + profilesLength + 1) {
      throw FormatException('Incomplete use_srtp data');
    }

    final profiles = <SrtpProtectionProfile>[];
    var offset = 2;

    while (offset < 2 + profilesLength) {
      final profileValue = buffer.getUint16(offset);
      final profile = SrtpProtectionProfile.fromValue(profileValue);
      if (profile != null) {
        profiles.add(profile);
      }
      offset += 2;
    }

    // Read MKI
    final mkiLength = buffer.getUint8(offset);
    offset++;

    final mki = mkiLength > 0 ? data.sublist(offset, offset + mkiLength) : Uint8List(0);

    return UseSrtpExtension(profiles: profiles, mki: mki);
  }

  @override
  String toString() {
    return 'UseSrtpExtension(profiles=$profiles, mki=${mki.length} bytes)';
  }
}
