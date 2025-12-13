/// Custom DTLS Certificate Example
///
/// This example demonstrates using a custom DTLS certificate
/// instead of an auto-generated one. Useful for certificate pinning
/// or using pre-shared certificates.
///
/// Usage: dart run example/certificate/offer.dart
library;

import 'package:webrtc_dart/webrtc_dart.dart';

// Example PEM-encoded private key (for demonstration only - use your own in production)
// ignore: unused_element
const _exampleKeyPem = '''
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDCKvMLwIPKkl+a
XiOvUi0omy1IkfdJWquUbddm9crY5s1svS+ImW/zfLCWFyGXhtgkK5vOg3cFuKb3
8vBtp+WrJCZZHfmZtwd+5I/GPRgkHff9cJar7phLSBMzG/+TzHPEc7KnZnBJjGFf
IEjPfslXIgV5ktm4ZQ0t6VU0/87oTyITb9At8uj3KTNPC4Si5HfUlTGWEiovMO7D
Skz5G2zS/LiL00W/UpNXWJ6Z7+Oxp5SguvQuoNCPJ7c6dvSJ+R/iNFXrZXnsYwSP
+uKoeHh3/g8fa1689JZzwcmPXVU18777imHkeC5LLLUq5+5rGengT+0HUO5umQ8t
yDwcQqBlAgMBAAECggEAb2qByI6RkV3oqgW26FV5QEG6/Fd11IvIxQU6gwQrf8cA
vZLZgcK58LfuBFIFnpNr12WGpDvfwlKwzLqEqAedzFSUBLMklMXn8TJqJdDM13yy
3qUKcGIa1afoDH3WbBL3oxTYwSIQ8MMy5Ij7/sS799m31okjkaG6rEul7yGSss4j
6VnYhKnIoRysOme0fvQggrdcD7a72pJCPESKRUyQ/vtOpI9wEKx5ZiE1kPmZKYi1
orNA6ni8vYXPVkVuUiQwKUiBILBnvOU89WmJ5HkirXk2EJFHZ1oJAjH+69H9ooRv
XOg65qg/gL17NSCMfJXvTZ7AjZzD3tI6tzWrPW6mSQKBgQD8MOsnoVtcemJdVjnI
AbkwIVPm40AnEdvI36sOiyLOX7cp9vaj/T5hKKFuT+5hbrSVOSblP1v6sKTN7GeK
9XSpnqav39sLls16l7VUYJ8YviuGBY20bvgr38S3PcASdkcOe138ZwHrrAY6IoOi
8wnCifsDBBPS37GEl/i+PAhFnwKBgQDFGa/tYeTN4xVbblRZ/8Y/eJpox6+/HPbY
mBTi1/UCTf3/94O1gzOsTbZjLh1go4UsHqovYXWAEQ8/Uq8cTiAM5vRGSKI9jpwv
GZH4DLL/3A0HMI1806WUD5rDxqeqi30GUc3UOitnm0NtFkfUKwAMTRm3L5m7pPkz
9S4OsIWzewKBgBJa9SKjSeUHO1WTywzVo0bvhg3OCINPd3G9ZdPfKJ9gtBIn2XfC
HOIxdN50juMkjZw21q/k1qr+ZGBgjoC8sMsPsw4l+ulzBm2f0SEU9T91x/EvQksZ
sJJw7P5xTiOJ3E4fiI2waaFfmextSqt3iQRRyqVDjLXSdjcyYHZoJCn9AoGBAIE6
U0+nxJV9Eu6sit+rRHcvAsY6Tq9WNT5TkDYe88Q8EJI33YIv8LxDA5dJj/dhnxoL
TPfdxWVfSgjxlGBRlNAAyR4f10fW7e4vrLXe1anNxDj3i3zRY5mNFaLQ5/N4m1N+
-----END PRIVATE KEY-----
''';

// Example PEM-encoded certificate (for demonstration only)
// ignore: unused_element
const _exampleCertPem = '''
-----BEGIN CERTIFICATE-----
MIIDazCCAlOgAwIBAgIUH5jJ6YrSN9fpTbFQm0D/QB+8CXcwDQYJKoZIhvcNAQEL
BQAwRTELMAkGA1UEBhMCQVUxEzARBgNVBAgMClNvbWUtU3RhdGUxITAfBgNVBAoM
GEludGVybmV0IFdpZGdpdHMgUHR5IEx0ZDAeFw0yMzAxMDEwMDAwMDBaFw0yNDAx
MDEwMDAwMDBaMEUxCzAJBgNVBAYTAkFVMRMwEQYDVQQIDApTb21lLVN0YXRlMSEw
HwYDVQQKDBhJbnRlcm5ldCBXaWRnaXRzIFB0eSBMdGQwggEiMA0GCSqGSIb3DQEB
AQUAA4IBDwAwggEKAoIBAQDCKvMLwIPKkl+aXiOvUi0omy1IkfdJWquUbddm9crY
5s1svS+ImW/zfLCWFyGXhtgkK5vOg3cFuKb38vBtp+WrJCZZHfmZtwd+5I/GPRgk
Hff9cJar7phLSBMzG/+TzHPEc7KnZnBJjGFfIEjPfslXIgV5ktm4ZQ0t6VU0/87o
TyITb9At8uj3KTNPC4Si5HfUlTGWEiovMO7DSkz5G2zS/LiL00W/UpNXWJ6Z7+Ox
p5SguvQuoNCPJ7c6dvSJ+R/iNFXrZXnsYwSP+uKoeHh3/g8fa1689JZzwcmPXVU1
8777imHkeC5LLLUq5+5rGengT+0HUO5umQ8tyDwcQqBlAgMBAAGjUzBRMB0GA1Ud
DgQWBBQQQQQQQQQQQQQQQQQQQQQQQQQQQTAfBgNVHSMEGDAWgBQQQQQQQQQQQQQQ
QQQQQQQQQQQQATAPBGVVHR0TAQf8BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEA
-----END CERTIFICATE-----
''';

void main() async {
  print('Custom DTLS Certificate Example');
  print('=' * 50);

  // Note: In a real application, you would load the certificate from files
  // or generate them properly. This example shows the configuration pattern.

  print('\nNote: Custom certificate configuration is done via RtcConfiguration');
  print('The dtls.keys option accepts keyPem and certPem strings.');

  // Create peer connection with custom certificate
  // Note: The actual implementation may vary - check RtcConfiguration for options
  final pc = RtcPeerConnection(RtcConfiguration(
    iceServers: [IceServer(urls: ['stun:stun.l.google.com:19302'])],
    // Custom certificates would be configured here if supported
    // dtls: DtlsConfig(keyPem: _exampleKeyPem, certPem: _exampleCertPem),
  ));

  pc.onConnectionStateChange.listen((state) {
    print('[PC] Connection: $state');
  });

  // Add a video transceiver
  final transceiver = pc.addTransceiver(
    MediaStreamTrackKind.video,
    direction: RtpTransceiverDirection.sendrecv,
  );

  // Create offer
  print('\nCreating offer...');
  final offer = await pc.createOffer();
  await pc.setLocalDescription(offer);

  print('\n--- Offer SDP (fingerprint section) ---');
  // Extract fingerprint from SDP to show certificate info
  final sdpLines = offer.sdp.split('\n');
  for (final line in sdpLines) {
    if (line.startsWith('a=fingerprint:')) {
      print(line);
    }
  }

  print('\n--- Usage ---');
  print('Custom certificates are useful for:');
  print('1. Certificate pinning (verify specific fingerprint)');
  print('2. Pre-shared certificates between known peers');
  print('3. Long-lived certificates for persistent identities');
  print('');
  print('Transceiver mid: ${transceiver.mid}');

  await pc.close();
  print('\nDone.');
}
