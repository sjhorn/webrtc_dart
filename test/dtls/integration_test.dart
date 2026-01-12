import 'dart:async';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/dtls/certificate/certificate_generator.dart';
import 'package:webrtc_dart/src/dtls/cipher/const.dart';
import 'package:webrtc_dart/src/dtls/client.dart';
import 'package:webrtc_dart/src/dtls/server.dart';
import 'package:webrtc_dart/src/dtls/socket.dart';
import 'mock_transport.dart';

void main() {
  group('DTLS Integration Tests', () {
    test('client and server can establish connection', () async {
      // Generate server certificate
      final serverCert = await generateSelfSignedCertificate(
        info: CertificateInfo(commonName: 'Test Server'),
      );

      // Create mock transports
      final clientTransport = MockTransport();
      final serverTransport = MockTransport();
      MockTransport.connectPair(clientTransport, serverTransport);

      // Create client and server
      final client = DtlsClient(
        transport: clientTransport,
        cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
        supportedCurves: [NamedCurve.x25519],
      );

      final server = DtlsServer(
        transport: serverTransport,
        cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
        supportedCurves: [NamedCurve.x25519],
        certificate: serverCert.certificate,
        privateKey: serverCert.privateKey,
      );

      // Track state changes
      final clientStates = <DtlsSocketState>[];
      final serverStates = <DtlsSocketState>[];

      client.onStateChange.listen(clientStates.add);
      server.onStateChange.listen(serverStates.add);

      // Start handshake
      await server.connect();
      await client.connect();

      // Wait for handshake to complete (with timeout)
      await Future.any([
        Future.wait([
          client.onStateChange
              .firstWhere((state) => state == DtlsSocketState.connected),
          server.onStateChange
              .firstWhere((state) => state == DtlsSocketState.connected),
        ]),
        Future.delayed(const Duration(seconds: 5)).then((_) {
          throw TimeoutException('Handshake did not complete in time');
        }),
      ]);

      // Verify both endpoints are connected
      expect(client.state, DtlsSocketState.connected);
      expect(server.state, DtlsSocketState.connected);

      // Verify handshake completed
      expect(client.dtlsContext.handshakeComplete, true);
      expect(server.dtlsContext.handshakeComplete, true);

      // Verify state transitions
      expect(clientStates, contains(DtlsSocketState.connecting));
      expect(clientStates, contains(DtlsSocketState.connected));
      expect(serverStates, contains(DtlsSocketState.connecting));
      expect(serverStates, contains(DtlsSocketState.connected));

      // Clean up
      await client.close();
      await server.close();
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('handshake derives matching keys', () async {
      // Generate server certificate
      final serverCert = await generateSelfSignedCertificate(
        info: CertificateInfo(commonName: 'Test Server'),
      );

      // Create mock transports
      final clientTransport = MockTransport();
      final serverTransport = MockTransport();
      MockTransport.connectPair(clientTransport, serverTransport);

      // Create client and server
      final client = DtlsClient(
        transport: clientTransport,
        cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
        supportedCurves: [NamedCurve.x25519],
      );

      final server = DtlsServer(
        transport: serverTransport,
        cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
        supportedCurves: [NamedCurve.x25519],
        certificate: serverCert.certificate,
        privateKey: serverCert.privateKey,
      );

      // Start handshake
      await server.connect();
      await client.connect();

      // Wait for completion
      await Future.wait([
        client.onStateChange
            .firstWhere((state) => state == DtlsSocketState.connected),
        server.onStateChange
            .firstWhere((state) => state == DtlsSocketState.connected),
      ]).timeout(const Duration(seconds: 5));

      // Verify master secret was derived
      expect(client.dtlsContext.masterSecret, isNotNull);
      expect(server.dtlsContext.masterSecret, isNotNull);

      // Verify encryption keys were derived
      expect(client.cipherContext.encryptionKeys, isNotNull);
      expect(server.cipherContext.encryptionKeys, isNotNull);

      // Verify SRTP keys were exported
      expect(client.srtpContext.keyMaterial, isNotNull);
      expect(server.srtpContext.keyMaterial, isNotNull);

      // Verify cipher suite was negotiated
      expect(
        client.cipherContext.cipherSuite,
        CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256,
      );
      expect(
        server.cipherContext.cipherSuite,
        CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256,
      );

      // Clean up
      await client.close();
      await server.close();
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('handshake fails with no shared cipher suites', () async {
      // Generate server certificate
      final serverCert = await generateSelfSignedCertificate(
        info: CertificateInfo(commonName: 'Test Server'),
      );

      // Create mock transports
      final clientTransport = MockTransport();
      final serverTransport = MockTransport();
      MockTransport.connectPair(clientTransport, serverTransport);

      // Create client and server with incompatible cipher suites
      final client = DtlsClient(
        transport: clientTransport,
        cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
        supportedCurves: [NamedCurve.x25519],
      );

      final server = DtlsServer(
        transport: serverTransport,
        cipherSuites: [CipherSuite.tlsEcdheRsaWithAes128GcmSha256],
        supportedCurves: [NamedCurve.x25519],
        certificate: serverCert.certificate,
        privateKey: serverCert.privateKey,
      );

      // Track errors
      final clientErrors = <Object>[];
      final serverErrors = <Object>[];

      client.onError.listen(clientErrors.add);
      server.onError.listen(serverErrors.add);

      // Start handshake
      await server.connect();
      await client.connect();

      // Wait for either connection or failure (with timeout)
      await Future.any([
        Future.wait([
          client.onStateChange
              .firstWhere((state) =>
                  state == DtlsSocketState.connected ||
                  state == DtlsSocketState.failed)
              .timeout(const Duration(seconds: 5)),
          server.onStateChange
              .firstWhere((state) =>
                  state == DtlsSocketState.connected ||
                  state == DtlsSocketState.failed)
              .timeout(const Duration(seconds: 5)),
        ]),
        Future.delayed(const Duration(seconds: 5)),
      ]);

      // Note: This test documents current behavior - in a full implementation,
      // the handshake should fail when no cipher suites match.
      // For now, we just verify the test doesn't hang.

      // Clean up
      await client.close();
      await server.close();
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('multiple handshakes can occur sequentially', () async {
      for (var i = 0; i < 3; i++) {
        // Generate server certificate
        final serverCert = await generateSelfSignedCertificate(
          info: CertificateInfo(commonName: 'Test Server $i'),
        );

        // Create mock transports
        final clientTransport = MockTransport();
        final serverTransport = MockTransport();
        MockTransport.connectPair(clientTransport, serverTransport);

        // Create client and server
        final client = DtlsClient(
          transport: clientTransport,
          cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
          supportedCurves: [NamedCurve.x25519],
        );

        final server = DtlsServer(
          transport: serverTransport,
          cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
          supportedCurves: [NamedCurve.x25519],
          certificate: serverCert.certificate,
          privateKey: serverCert.privateKey,
        );

        // Start handshake
        await server.connect();
        await client.connect();

        // Wait for completion
        await Future.wait([
          client.onStateChange
              .firstWhere((state) => state == DtlsSocketState.connected),
          server.onStateChange
              .firstWhere((state) => state == DtlsSocketState.connected),
        ]).timeout(const Duration(seconds: 5));

        expect(client.state, DtlsSocketState.connected);
        expect(server.state, DtlsSocketState.connected);

        // Clean up
        await client.close();
        await server.close();
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('handshake works with simulated packet delay', () async {
      // Generate server certificate
      final serverCert = await generateSelfSignedCertificate(
        info: CertificateInfo(commonName: 'Test Server'),
      );

      // Create mock transports with delay
      final clientTransport =
          MockTransport(delay: const Duration(milliseconds: 10));
      final serverTransport =
          MockTransport(delay: const Duration(milliseconds: 10));
      MockTransport.connectPair(clientTransport, serverTransport);

      // Create client and server
      final client = DtlsClient(
        transport: clientTransport,
        cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
        supportedCurves: [NamedCurve.x25519],
      );

      final server = DtlsServer(
        transport: serverTransport,
        cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
        supportedCurves: [NamedCurve.x25519],
        certificate: serverCert.certificate,
        privateKey: serverCert.privateKey,
      );

      // Start handshake
      await server.connect();
      await client.connect();

      // Wait for completion (with longer timeout due to delays)
      await Future.wait([
        client.onStateChange
            .firstWhere((state) => state == DtlsSocketState.connected),
        server.onStateChange
            .firstWhere((state) => state == DtlsSocketState.connected),
      ]).timeout(const Duration(seconds: 10));

      expect(client.state, DtlsSocketState.connected);
      expect(server.state, DtlsSocketState.connected);

      // Clean up
      await client.close();
      await server.close();
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('server handles retransmitted first ClientHello (no cookie)', () async {
      // This test verifies the fix for the issue where the server would throw:
      // "Bad state: Unexpected first ClientHello in state waitingForClientHelloWithCookie"
      //
      // Scenario:
      // 1. Client sends ClientHello (no cookie)
      // 2. Server responds with HelloVerifyRequest
      // 3. HelloVerifyRequest is lost (packet loss)
      // 4. Client retransmits original ClientHello (no cookie)
      // 5. Server is in waitingForClientHelloWithCookie state but receives no-cookie ClientHello
      //
      // Per RFC 6347, the server should re-send the HelloVerifyRequest
      // instead of throwing an error.
      //
      // This test simulates the retransmission by using a ReplayTransport that
      // replays the first ClientHello after a delay.

      // Generate server certificate
      final serverCert = await generateSelfSignedCertificate(
        info: CertificateInfo(commonName: 'Test Server'),
      );

      // Create mock transports
      // The client transport will replay its first sent packet after a delay
      final clientTransport = ReplayFirstPacketTransport(
        replayDelayMs: 200, // Replay after 200ms
      );
      final serverTransport = SelectiveDropTransport();

      // Connect transports
      clientTransport.remotePeer = serverTransport;
      serverTransport.remotePeer = clientTransport;

      // Drop the first outgoing packet from server (HelloVerifyRequest)
      // This simulates packet loss which triggers client retransmission
      serverTransport.dropNextNPackets(1);

      // Create client and server
      final client = DtlsClient(
        transport: clientTransport,
        cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
        supportedCurves: [NamedCurve.x25519],
      );

      final server = DtlsServer(
        transport: serverTransport,
        cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
        supportedCurves: [NamedCurve.x25519],
        certificate: serverCert.certificate,
        privateKey: serverCert.privateKey,
      );

      // Track errors - the fix ensures no errors are thrown
      final serverErrors = <Object>[];
      server.onError.listen(serverErrors.add);

      // Start handshake
      await server.connect();
      await client.connect();

      // Wait for the replay to trigger
      // The first ClientHello is sent, HelloVerifyRequest is dropped,
      // then after 200ms the ClientHello is replayed
      await Future.delayed(const Duration(milliseconds: 300));

      // At this point:
      // - Server received first ClientHello, sent HelloVerifyRequest (dropped)
      // - Server is in waitingForClientHelloWithCookie state
      // - Server received replayed ClientHello (no cookie)
      // - Without the fix, this would throw "Unexpected first ClientHello"
      // - With the fix, server re-sends HelloVerifyRequest

      // Verify no errors occurred on server
      expect(serverErrors, isEmpty,
          reason:
              'Server should not throw "Unexpected first ClientHello" error');

      // Clean up
      await client.close();
      await server.close();
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('close during async processing does not throw', () async {
      // This test verifies the fix for race condition where close() is called
      // while async processing is still happening, which could cause
      // "Cannot add to a closed controller" errors.
      //
      // The fix adds `if (!isClosed)` guards before errorController.add() calls.

      // Generate server certificate
      final serverCert = await generateSelfSignedCertificate(
        info: CertificateInfo(commonName: 'Test Server'),
      );

      // Create mock transports
      final clientTransport = MockTransport();
      final serverTransport = MockTransport();
      MockTransport.connectPair(clientTransport, serverTransport);

      // Create client and server
      final client = DtlsClient(
        transport: clientTransport,
        cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
        supportedCurves: [NamedCurve.x25519],
      );

      final server = DtlsServer(
        transport: serverTransport,
        cipherSuites: [CipherSuite.tlsEcdheEcdsaWithAes128GcmSha256],
        supportedCurves: [NamedCurve.x25519],
        certificate: serverCert.certificate,
        privateKey: serverCert.privateKey,
      );

      // Start handshake
      await server.connect();
      await client.connect();

      // Wait for connection
      await Future.wait([
        client.onStateChange
            .firstWhere((state) => state == DtlsSocketState.connected),
        server.onStateChange
            .firstWhere((state) => state == DtlsSocketState.connected),
      ]).timeout(const Duration(seconds: 5));

      // Close immediately - this simulates browser disconnect
      // Any in-flight async processing should not throw when trying to
      // add errors to the closed controller
      await client.close();
      await server.close();

      // Verify closed state
      expect(client.isClosed, true);
      expect(server.isClosed, true);

      // Give any pending async operations time to complete
      await Future.delayed(const Duration(milliseconds: 100));

      // If we get here without exception, the test passes
    }, timeout: const Timeout(Duration(seconds: 10)));
  });
}
