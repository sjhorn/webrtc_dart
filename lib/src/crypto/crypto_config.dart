/// Global configuration for cryptographic implementations.
///
/// By default, webrtc_dart automatically uses native OpenSSL/BoringSSL if
/// available on the system (~16x faster SRTP). Falls back to pure Dart
/// if no native crypto library is found or on platforms without FFI support
/// (e.g., Flutter web).
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
/// // Or use environment variable to disable (native platforms only):
/// // WEBRTC_NATIVE_CRYPTO=0 dart run your_app.dart
/// ```
library;

import 'aes_gcm.dart';

// Conditional import: use native implementation when dart:ffi is available,
// otherwise fall back to stub that always uses pure Dart
import 'crypto_config_stub.dart'
    if (dart.library.ffi) 'crypto_config_native.dart' as platform;

class CryptoConfig {
  static bool _initUseNative() {
    try {
      return platform.checkNativeEnvVar();
    } catch (_) {
      return true; // Default to trying native
    }
  }

  /// Whether to use native crypto (OpenSSL/BoringSSL FFI) when available.
  ///
  /// Default: true (try native, fall back to Dart if unavailable)
  /// Set to false to force pure Dart implementation.
  /// Should be set before creating any RTCPeerConnection instances.
  static bool useNative = _initUseNative();

  /// Cached check for native availability (computed once)
  static bool? _nativeAvailable;

  /// Check if native crypto (OpenSSL FFI) is available.
  ///
  /// Returns true if OpenSSL can be loaded via FFI.
  /// Always returns false on platforms without FFI support (e.g., web).
  static bool get isNativeAvailable {
    if (_nativeAvailable != null) return _nativeAvailable!;
    try {
      _nativeAvailable = platform.isNativeCryptoAvailable();
    } catch (_) {
      _nativeAvailable = false;
    }
    return _nativeAvailable!;
  }

  /// Cached cipher instance for reuse
  static AesGcmCipher? _cachedCipher;

  /// Create an AES-GCM cipher based on current configuration.
  ///
  /// If [useNative] is true and OpenSSL is available, returns native cipher.
  /// Otherwise returns pure Dart implementation.
  static AesGcmCipher createAesGcm() {
    if (useNative && isNativeAvailable) {
      try {
        return platform.createNativeCipher();
      } catch (_) {
        // Fall back to Dart if native cipher creation fails
      }
    }
    return DartAesGcmCipher();
  }

  /// Get or create a shared AES-GCM cipher instance.
  ///
  /// This is useful when you want to reuse the same cipher across
  /// multiple operations to avoid FFI setup overhead.
  static AesGcmCipher getSharedCipher() {
    _cachedCipher ??= createAesGcm();
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
      try {
        final path = platform.findOpenSSL();
        return 'Native (OpenSSL: $path)';
      } catch (_) {
        return 'Dart (native error)';
      }
    } else if (!useNative) {
      return 'Dart (native disabled)';
    } else {
      return 'Dart (pure)';
    }
  }
}
