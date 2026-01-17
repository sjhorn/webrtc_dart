/// Native implementation for platforms with dart:ffi support
///
/// This file is used when dart:ffi is available (native platforms).
library;

import 'dart:io';

import 'aes_gcm.dart';
import 'aes_gcm_ffi.dart' as ffi;

/// Check if native crypto is available
bool isNativeCryptoAvailable() => ffi.isNativeCryptoAvailable();

/// Find OpenSSL path
String? findOpenSSL() => ffi.findOpenSSL();

/// Create a native AES-GCM cipher
AesGcmCipher createNativeCipher() => ffi.FfiAesGcmCipher();

/// Check environment variable for native crypto setting
bool checkNativeEnvVar() {
  try {
    final env = Platform.environment['WEBRTC_NATIVE_CRYPTO'];
    // Default is true (use native). Only disable if explicitly set to 0/false.
    if (env == '0' || env == 'false') {
      return false;
    }
    return true;
  } catch (_) {
    // Platform.environment not available
    return true;
  }
}
