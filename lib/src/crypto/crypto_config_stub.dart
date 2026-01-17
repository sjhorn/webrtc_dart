/// Stub implementation for platforms without dart:ffi (e.g., Flutter web)
///
/// This file is used when dart:ffi is not available.
library;

import 'aes_gcm.dart';

/// Check if native crypto is available (always false on web)
bool isNativeCryptoAvailable() => false;

/// Find OpenSSL path (not available on web)
String? findOpenSSL() => null;

/// Create an AES-GCM cipher (always returns Dart implementation on web)
AesGcmCipher createNativeCipher() {
  throw UnsupportedError('Native crypto not available on this platform');
}

/// Check environment variable (not available on web)
bool checkNativeEnvVar() => false;
