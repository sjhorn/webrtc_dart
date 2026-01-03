import 'dart:io';

import 'aes_gcm.dart';
import 'aes_gcm_ffi.dart';

/// Global configuration for cryptographic implementations.
///
/// By default, webrtc_dart automatically uses native OpenSSL/BoringSSL if
/// available on the system (~16x faster SRTP). Falls back to pure Dart
/// if no native crypto library is found.
///
/// ## Usage
///
/// ```dart
/// // Check what crypto is being used
/// print(CryptoConfig.description);  // e.g., "Native (OpenSSL)" or "Dart (pure)"
///
/// // Disable native crypto (force pure Dart)
/// CryptoConfig.useNative = false;
///
/// // Or use environment variable to disable:
/// // WEBRTC_NATIVE_CRYPTO=0 dart run your_app.dart
/// ```
class CryptoConfig {
  /// Whether to use native crypto (OpenSSL/BoringSSL FFI) when available.
  ///
  /// Default: true (try native, fall back to Dart if unavailable)
  /// Set to false to force pure Dart implementation.
  static bool _useNative = _checkEnvVar();

  /// Check if the environment variable disables native crypto
  static bool _checkEnvVar() {
    final env = Platform.environment['WEBRTC_NATIVE_CRYPTO'];
    // Default is true (use native). Only disable if explicitly set to 0/false.
    if (env == '0' || env == 'false') {
      return false;
    }
    return true;
  }

  /// Get whether native crypto is enabled.
  static bool get useNative => _useNative;

  /// Set whether to use native crypto.
  ///
  /// Should be called before creating any RTCPeerConnection instances.
  static set useNative(bool value) {
    _useNative = value;
  }

  /// Cached check for native availability (computed once)
  static bool? _nativeAvailable;

  /// Check if native crypto (OpenSSL FFI) is available.
  ///
  /// Returns true if OpenSSL can be loaded via FFI.
  static bool get isNativeAvailable {
    return _nativeAvailable ??= isNativeCryptoAvailable();
  }

  /// Cached cipher instance for reuse
  static AesGcmCipher? _cachedCipher;

  /// Create an AES-GCM cipher based on current configuration.
  ///
  /// If [useNative] is true and OpenSSL is available, returns [FfiAesGcmCipher].
  /// Otherwise returns [DartAesGcmCipher].
  static AesGcmCipher createAesGcm() {
    if (useNative && isNativeAvailable) {
      return FfiAesGcmCipher();
    }
    return DartAesGcmCipher();
  }

  /// Get or create a shared AES-GCM cipher instance.
  ///
  /// This is useful when you want to reuse the same cipher across
  /// multiple operations to avoid FFI setup overhead.
  static AesGcmCipher getSharedCipher() {
    if (_cachedCipher == null) {
      _cachedCipher = createAesGcm();
    }
    return _cachedCipher!;
  }

  /// Reset the shared cipher instance.
  ///
  /// Call this after changing [useNative] to ensure the new setting takes effect.
  static void resetSharedCipher() {
    _cachedCipher?.dispose();
    _cachedCipher = null;
  }

  /// Get a description of the current crypto configuration.
  static String get description {
    if (useNative && isNativeAvailable) {
      final path = findOpenSSL();
      return 'Native (OpenSSL: $path)';
    } else if (!useNative) {
      return 'Dart (native disabled)';
    } else {
      return 'Dart (pure)';
    }
  }
}
