import 'package:test/test.dart';
import 'package:webrtc_dart/src/ice/candidate.dart';

void main() {
  group('Candidate', () {
    test('creates candidate with all properties', () {
      final candidate = Candidate(
        foundation: '1234567890',
        component: 1,
        transport: 'udp',
        priority: 2130706431,
        host: '192.168.1.100',
        port: 54321,
        type: 'host',
      );

      expect(candidate.foundation, equals('1234567890'));
      expect(candidate.component, equals(1));
      expect(candidate.transport, equals('udp'));
      expect(candidate.priority, equals(2130706431));
      expect(candidate.host, equals('192.168.1.100'));
      expect(candidate.port, equals(54321));
      expect(candidate.type, equals('host'));
    });

    test('parses candidate from SDP', () {
      final sdp = '6815297761 1 udp 2130706431 192.168.1.1 54321 typ host';
      final candidate = Candidate.fromSdp(sdp);

      expect(candidate.foundation, equals('6815297761'));
      expect(candidate.component, equals(1));
      expect(candidate.transport, equals('udp'));
      expect(candidate.priority, equals(2130706431));
      expect(candidate.host, equals('192.168.1.1'));
      expect(candidate.port, equals(54321));
      expect(candidate.type, equals('host'));
    });

    test('parses candidate with candidate: prefix', () {
      final sdp =
          'candidate:6815297761 1 udp 2130706431 192.168.1.1 54321 typ host';
      final candidate = Candidate.fromSdp(sdp);

      expect(candidate.foundation, equals('6815297761'));
      expect(candidate.component, equals(1));
      expect(candidate.transport, equals('udp'));
      expect(candidate.priority, equals(2130706431));
      expect(candidate.host, equals('192.168.1.1'));
      expect(candidate.port, equals(54321));
      expect(candidate.type, equals('host'));
    });

    test('parses candidate with a=candidate: prefix', () {
      final sdp =
          'a=candidate:6815297761 1 udp 2130706431 192.168.1.1 54321 typ host';
      final candidate = Candidate.fromSdp(sdp);

      expect(candidate.foundation, equals('6815297761'));
      expect(candidate.component, equals(1));
      expect(candidate.host, equals('192.168.1.1'));
      expect(candidate.type, equals('host'));
    });

    test('parses candidate with optional attributes', () {
      final sdp = '6815297761 1 udp 1694498815 10.0.0.1 54321 typ srflx '
          'raddr 192.168.1.1 rport 54321 generation 0 ufrag test';
      final candidate = Candidate.fromSdp(sdp);

      expect(candidate.type, equals('srflx'));
      expect(candidate.relatedAddress, equals('192.168.1.1'));
      expect(candidate.relatedPort, equals(54321));
      expect(candidate.generation, equals(0));
      expect(candidate.ufrag, equals('test'));
    });

    test('throws on invalid SDP', () {
      final invalidSdp = '1 2 3'; // Too few parts
      expect(() => Candidate.fromSdp(invalidSdp), throwsArgumentError);
    });

    test('converts candidate to SDP', () {
      final candidate = Candidate(
        foundation: '6815297761',
        component: 1,
        transport: 'udp',
        priority: 2130706431,
        host: '192.168.1.1',
        port: 54321,
        type: 'host',
      );

      final sdp = candidate.toSdp();
      expect(sdp,
          equals('6815297761 1 udp 2130706431 192.168.1.1 54321 typ host'));
    });

    test('converts candidate with optional attributes to SDP', () {
      final candidate = Candidate(
        foundation: '6815297761',
        component: 1,
        transport: 'udp',
        priority: 1694498815,
        host: '10.0.0.1',
        port: 54321,
        type: 'srflx',
        relatedAddress: '192.168.1.1',
        relatedPort: 54321,
        generation: 0,
        ufrag: 'test',
      );

      final sdp = candidate.toSdp();
      expect(sdp, contains('typ srflx'));
      expect(sdp, contains('raddr 192.168.1.1'));
      expect(sdp, contains('rport 54321'));
      expect(sdp, contains('generation 0'));
      expect(sdp, contains('ufrag test'));
    });

    test('round-trips SDP parsing and generation', () {
      final originalSdp =
          '6815297761 1 udp 2130706431 192.168.1.1 54321 typ host '
          'generation 0 ufrag test';
      final candidate = Candidate.fromSdp(originalSdp);
      final regeneratedSdp = candidate.toSdp();
      final reparsed = Candidate.fromSdp(regeneratedSdp);

      expect(reparsed.foundation, equals(candidate.foundation));
      expect(reparsed.component, equals(candidate.component));
      expect(reparsed.transport, equals(candidate.transport));
      expect(reparsed.priority, equals(candidate.priority));
      expect(reparsed.host, equals(candidate.host));
      expect(reparsed.port, equals(candidate.port));
      expect(reparsed.type, equals(candidate.type));
      expect(reparsed.generation, equals(candidate.generation));
      expect(reparsed.ufrag, equals(candidate.ufrag));
    });

    group('canPairWith', () {
      test('can pair with same component and IP version', () {
        final local = Candidate(
          foundation: '1',
          component: 1,
          transport: 'udp',
          priority: 100,
          host: '192.168.1.1',
          port: 1234,
          type: 'host',
        );

        final remote = Candidate(
          foundation: '2',
          component: 1,
          transport: 'udp',
          priority: 100,
          host: '10.0.0.1',
          port: 5678,
          type: 'host',
        );

        expect(local.canPairWith(remote), isTrue);
      });

      test('cannot pair with different component', () {
        final local = Candidate(
          foundation: '1',
          component: 1,
          transport: 'udp',
          priority: 100,
          host: '192.168.1.1',
          port: 1234,
          type: 'host',
        );

        final remote = Candidate(
          foundation: '2',
          component: 2,
          transport: 'udp',
          priority: 100,
          host: '10.0.0.1',
          port: 5678,
          type: 'host',
        );

        expect(local.canPairWith(remote), isFalse);
      });

      test('cannot pair with different IP version', () {
        final local = Candidate(
          foundation: '1',
          component: 1,
          transport: 'udp',
          priority: 100,
          host: '192.168.1.1', // IPv4
          port: 1234,
          type: 'host',
        );

        final remote = Candidate(
          foundation: '2',
          component: 1,
          transport: 'udp',
          priority: 100,
          host: '::1', // IPv6
          port: 5678,
          type: 'host',
        );

        expect(local.canPairWith(remote), isFalse);
      });

      test('can pair IPv6 candidates', () {
        final local = Candidate(
          foundation: '1',
          component: 1,
          transport: 'udp',
          priority: 100,
          host: '2001:db8::1',
          port: 1234,
          type: 'host',
        );

        final remote = Candidate(
          foundation: '2',
          component: 1,
          transport: 'udp',
          priority: 100,
          host: '2001:db8::2',
          port: 5678,
          type: 'host',
        );

        expect(local.canPairWith(remote), isTrue);
      });
    });

    test('equality comparison', () {
      final c1 = Candidate(
        foundation: '1',
        component: 1,
        transport: 'udp',
        priority: 100,
        host: '192.168.1.1',
        port: 1234,
        type: 'host',
      );

      final c2 = Candidate(
        foundation: '1',
        component: 1,
        transport: 'udp',
        priority: 100,
        host: '192.168.1.1',
        port: 1234,
        type: 'host',
      );

      final c3 = Candidate(
        foundation: '1',
        component: 1,
        transport: 'udp',
        priority: 200, // Different priority
        host: '192.168.1.1',
        port: 1234,
        type: 'host',
      );

      expect(c1, equals(c2));
      expect(c1.hashCode, equals(c2.hashCode));
      expect(c1 == c3, isTrue); // Equality doesn't check priority
    });
  });

  group('candidateFoundation', () {
    test('computes foundation from type, transport, and base', () {
      final foundation = candidateFoundation('host', 'udp', '192.168.1.1');

      expect(foundation, isNotEmpty);
      expect(foundation.length, equals(25)); // MD5 hash substring
    });

    test('same inputs produce same foundation', () {
      final f1 = candidateFoundation('host', 'udp', '192.168.1.1');
      final f2 = candidateFoundation('host', 'udp', '192.168.1.1');

      expect(f1, equals(f2));
    });

    test('different inputs produce different foundations', () {
      final f1 = candidateFoundation('host', 'udp', '192.168.1.1');
      final f2 = candidateFoundation('srflx', 'udp', '192.168.1.1');
      final f3 = candidateFoundation('host', 'tcp', '192.168.1.1');
      final f4 = candidateFoundation('host', 'udp', '10.0.0.1');

      expect(f1, isNot(equals(f2)));
      expect(f1, isNot(equals(f3)));
      expect(f1, isNot(equals(f4)));
    });
  });

  group('candidatePriority', () {
    test('computes priority for host candidate', () {
      final priority = candidatePriority('host');

      // host type has typePref=126
      // Formula: (2^24)*126 + (2^8)*65535 + (256-1)
      expect(priority, equals(2130706431));
    });

    test('computes priority for srflx candidate', () {
      final priority = candidatePriority('srflx');

      // srflx type has typePref=100
      // Formula: (2^24)*100 + (2^8)*65535 + (256-1)
      expect(priority, equals(1694498815));
    });

    test('computes priority for prflx candidate', () {
      final priority = candidatePriority('prflx');

      // prflx type has typePref=110
      // Formula: (2^24)*110 + (2^8)*65535 + (256-1)
      // = 16777216*110 + 256*65535 + 255
      // = 1845493760 + 16776960 + 255 = 1862270975
      expect(priority, equals(1862270975));
    });

    test('computes priority for relay candidate', () {
      final priority = candidatePriority('relay');

      // relay type has typePref=0
      // Formula: (2^24)*0 + (2^8)*65535 + (256-1)
      expect(priority, equals(16777215));
    });

    test('respects localPref parameter', () {
      final p1 = candidatePriority('host', localPref: 65535);
      final p2 = candidatePriority('host', localPref: 32767);

      expect(p2, lessThan(p1));
    });

    test('host candidates have highest priority', () {
      final host = candidatePriority('host');
      final prflx = candidatePriority('prflx');
      final srflx = candidatePriority('srflx');
      final relay = candidatePriority('relay');

      expect(host, greaterThan(prflx));
      expect(prflx, greaterThan(srflx));
      expect(srflx, greaterThan(relay));
    });
  });
}
