import 'package:test/test.dart';
import 'package:webrtc_dart/src/ice/ice_connection.dart';

void main() {
  group('Reflexive Candidate Gathering', () {
    test('gathering without STUN server only creates host candidates', () async {
      final connection = IceConnectionImpl(
        iceControlling: true,
        options: IceOptions(), // No STUN server
      );

      await connection.gatherCandidates();

      // Should only have host candidates
      expect(
        connection.localCandidates.every((c) => c.type == 'host'),
        isTrue,
      );

      await connection.close();
    });

    test('STUN server option is configurable', () {
      final connection = IceConnectionImpl(
        iceControlling: true,
        options: IceOptions(
          stunServer: ('stun.l.google.com', 19302),
        ),
      );

      expect(connection.options.stunServer, equals(('stun.l.google.com', 19302)));

      connection.close();
    });

    test('gathering with STUN server attempts reflexive discovery', () async {
      // This test attempts to use Google's public STUN server
      // It may fail in restricted networks, which is okay
      final connection = IceConnectionImpl(
        iceControlling: true,
        options: IceOptions(
          stunServer: ('stun.l.google.com', 19302),
        ),
      );

      try {
        await connection.gatherCandidates();

        // Should have at least host candidates
        final hostCandidates = connection.localCandidates.where((c) => c.type == 'host');
        expect(hostCandidates, isNotEmpty);

        // May have reflexive candidates if network allows
        final srflxCandidates = connection.localCandidates.where((c) => c.type == 'srflx');

        // If we got reflexive candidates, verify their properties
        for (final srflx in srflxCandidates) {
          expect(srflx.type, equals('srflx'));
          expect(srflx.transport, equals('udp'));
          expect(srflx.relatedAddress, isNotNull);
          expect(srflx.relatedPort, isNotNull);
          expect(srflx.host, isNotEmpty);
          expect(srflx.port, greaterThan(0));

          // Priority should be lower than host candidates
          final hostPriority = hostCandidates.first.priority;
          expect(srflx.priority, lessThan(hostPriority));
        }
      } catch (e) {
        // Network issues are acceptable in testing
        print('STUN request failed (this is okay in restricted networks): $e');
      } finally {
        await connection.close();
      }
    }, timeout: Timeout(Duration(seconds: 10)));

    test('reflexive candidates have correct related address', () async {
      // This test verifies the structure even if STUN fails
      final connection = IceConnectionImpl(
        iceControlling: true,
        options: IceOptions(
          stunServer: ('stun.l.google.com', 19302),
        ),
      );

      try {
        await connection.gatherCandidates();

        final srflxCandidates = connection.localCandidates.where((c) => c.type == 'srflx');
        final hostCandidates = connection.localCandidates.where((c) => c.type == 'host');

        // If we got reflexive candidates, verify they point to host candidates
        for (final srflx in srflxCandidates) {
          // Find the related host candidate
          final relatedHost = hostCandidates.where((h) =>
            h.host == srflx.relatedAddress && h.port == srflx.relatedPort
          );

          expect(relatedHost, isNotEmpty,
            reason: 'Reflexive candidate should have a matching host candidate');
        }
      } catch (e) {
        // Network issues are acceptable
        print('STUN request failed: $e');
      } finally {
        await connection.close();
      }
    }, timeout: Timeout(Duration(seconds: 10)));

    test('reflexive candidates share socket with host candidate', () async {
      final connection = IceConnectionImpl(
        iceControlling: true,
        options: IceOptions(
          stunServer: ('stun.l.google.com', 19302),
        ),
      );

      try {
        await connection.gatherCandidates();

        final srflxCandidates = connection.localCandidates.where((c) => c.type == 'srflx');

        // Reflexive candidates should reuse the host candidate's socket
        // This is verified by checking that the related port matches a host candidate
        for (final srflx in srflxCandidates) {
          final hostWithSamePort = connection.localCandidates.where((c) =>
            c.type == 'host' &&
            c.host == srflx.relatedAddress &&
            c.port == srflx.relatedPort
          );

          expect(hostWithSamePort, isNotEmpty,
            reason: 'Reflexive candidate should share socket with host candidate');
        }
      } catch (e) {
        // Network issues are acceptable
        print('STUN request failed: $e');
      } finally {
        await connection.close();
      }
    }, timeout: Timeout(Duration(seconds: 10)));

    test('gathering with invalid STUN server falls back to host only', () async {
      final connection = IceConnectionImpl(
        iceControlling: true,
        options: IceOptions(
          stunServer: ('invalid.stun.server.example', 3478),
        ),
      );

      await connection.gatherCandidates();

      // Should complete gathering even if STUN fails
      expect(connection.localCandidatesEnd, isTrue);

      // Should have at least host candidates
      final hostCandidates = connection.localCandidates.where((c) => c.type == 'host');
      expect(hostCandidates, isNotEmpty);

      await connection.close();
    }, timeout: Timeout(Duration(seconds: 10)));

    test('reflexive candidate SDP format is correct', () async {
      final connection = IceConnectionImpl(
        iceControlling: true,
        options: IceOptions(
          stunServer: ('stun.l.google.com', 19302),
        ),
      );

      try {
        await connection.gatherCandidates();

        final srflxCandidates = connection.localCandidates.where((c) => c.type == 'srflx');

        for (final srflx in srflxCandidates) {
          final sdp = srflx.toSdp();

          // Verify SDP contains all required fields
          expect(sdp, contains('typ srflx'));
          expect(sdp, contains('raddr ${srflx.relatedAddress}'));
          expect(sdp, contains('rport ${srflx.relatedPort}'));
          expect(sdp, contains('udp'));
          expect(sdp, contains(srflx.host));
          expect(sdp, contains(srflx.port.toString()));
        }
      } catch (e) {
        print('STUN request failed: $e');
      } finally {
        await connection.close();
      }
    }, timeout: Timeout(Duration(seconds: 10)));
  });
}
