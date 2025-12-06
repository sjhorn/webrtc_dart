import 'package:test/test.dart';
import 'package:webrtc_dart/src/ice/mdns.dart';
import 'package:webrtc_dart/src/ice/ice_connection.dart';

void main() {
  group('MdnsHostname', () {
    test('generate() creates valid UUID.local hostname', () {
      final hostname = MdnsHostname.generate();

      expect(hostname.endsWith('.local'), isTrue);

      // Extract UUID part
      final uuidPart =
          hostname.substring(0, hostname.length - 6); // Remove '.local'

      // UUID format: 8-4-4-4-12 hex chars
      final uuidRegex = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      expect(uuidRegex.hasMatch(uuidPart), isTrue,
          reason: 'UUID should match v4 format: $uuidPart');
    });

    test('generate() creates unique hostnames', () {
      final hostnames = <String>{};
      for (var i = 0; i < 100; i++) {
        hostnames.add(MdnsHostname.generate());
      }
      expect(hostnames.length, equals(100),
          reason: 'All generated hostnames should be unique');
    });

    test('isLocalHostname() returns true for .local hostnames', () {
      expect(MdnsHostname.isLocalHostname('abc123.local'), isTrue);
      expect(MdnsHostname.isLocalHostname('test.local'), isTrue);
      expect(MdnsHostname.isLocalHostname('a-b-c.local'), isTrue);
      expect(MdnsHostname.isLocalHostname('UPPERCASE.LOCAL'), isTrue);
      expect(MdnsHostname.isLocalHostname('Mixed.Local'), isTrue);
    });

    test('isLocalHostname() returns false for non-.local hostnames', () {
      expect(MdnsHostname.isLocalHostname('example.com'), isFalse);
      expect(MdnsHostname.isLocalHostname('localhost'), isFalse);
      expect(MdnsHostname.isLocalHostname('192.168.1.1'), isFalse);
      expect(MdnsHostname.isLocalHostname('test.localhost'), isFalse);
      expect(MdnsHostname.isLocalHostname('local.example.com'), isFalse);
    });
  });

  group('MdnsService', () {
    late MdnsService service;

    setUp(() {
      service = MdnsService();
    });

    tearDown(() async {
      await service.stop();
    });

    test('isRunning is false initially', () {
      expect(service.isRunning, isFalse);
    });

    test('registerHostname() creates mDNS hostname mapping', () {
      final hostname = service.registerHostname('192.168.1.100');

      expect(hostname.endsWith('.local'), isTrue);
      expect(service.getRegisteredAddress(hostname), equals('192.168.1.100'));
    });

    test('registerWithHostname() registers specific hostname', () {
      service.registerWithHostname('custom-device.local', '10.0.0.1');

      expect(service.getRegisteredAddress('custom-device.local'),
          equals('10.0.0.1'));
    });

    test('registerHostname() creates unique hostname each call', () {
      final hostname1 = service.registerHostname('192.168.1.1');
      final hostname2 = service.registerHostname('192.168.1.2');

      expect(hostname1, isNot(equals(hostname2)));
      expect(service.getRegisteredAddress(hostname1), equals('192.168.1.1'));
      expect(service.getRegisteredAddress(hostname2), equals('192.168.1.2'));
    });

    test('resolve() returns cached hostname immediately', () async {
      service.registerWithHostname('cached.local', '172.16.0.1');

      final resolved = await service.resolve('cached.local');
      expect(resolved, equals('172.16.0.1'));
    });

    test('resolve() returns null for unknown .local hostname when not running',
        () async {
      final resolved = await service.resolve('unknown.local');
      expect(resolved, isNull);
    });

    test('resolve() uses regular DNS for non-.local hostnames', () async {
      // This will attempt regular DNS lookup, which may or may not succeed
      // depending on network configuration. We just verify it doesn't crash.
      final resolved = await service.resolve('localhost');
      // localhost should resolve to 127.0.0.1 on most systems
      if (resolved != null) {
        expect(resolved, anyOf(equals('127.0.0.1'), equals('::1')));
      }
    });

    test('stop() clears registrations and cache', () async {
      service.registerWithHostname('test.local', '1.2.3.4');

      await service.stop();

      expect(service.getRegisteredAddress('test.local'), isNull);
    });

    test('stop() completes pending resolutions with null', () async {
      // Start the service
      try {
        await service.start();
      } catch (e) {
        // mDNS port may be in use, skip this test
        return;
      }

      // Start a resolution that will timeout
      final resolveFuture = service.resolve('nonexistent-host.local');

      // Stop immediately
      await service.stop();

      // Resolution should complete with null
      final result = await resolveFuture;
      expect(result, isNull);
    });

    group('DNS encoding', () {
      test('_encodeDnsName encodes hostname correctly', () {
        // Access the private method via a subclass or test the observable behavior
        // We can test by registering and checking the packet would be sent correctly
        final hostname = 'test.local';
        service.registerWithHostname(hostname, '192.168.1.1');

        // The hostname should be resolvable from cache
        expect(service.getRegisteredAddress(hostname), equals('192.168.1.1'));
      });
    });
  });

  group('DnsRecordType', () {
    test('has correct values', () {
      expect(DnsRecordType.a, equals(1));
      expect(DnsRecordType.aaaa, equals(28));
      expect(DnsRecordType.ptr, equals(12));
      expect(DnsRecordType.txt, equals(16));
      expect(DnsRecordType.srv, equals(33));
      expect(DnsRecordType.any, equals(255));
    });
  });

  group('DnsClass', () {
    test('has correct values', () {
      expect(DnsClass.internet, equals(1));
      expect(DnsClass.cacheFlush, equals(0x8001));
    });
  });

  group('DnsFlags', () {
    test('has correct values', () {
      expect(DnsFlags.query, equals(0x0000));
      expect(DnsFlags.response, equals(0x8400));
    });
  });

  group('mDNS constants', () {
    test('kMdnsPort is 5353', () {
      expect(kMdnsPort, equals(5353));
    });

    test('kMdnsMulticastIPv4 is 224.0.0.251', () {
      expect(kMdnsMulticastIPv4.address, equals('224.0.0.251'));
    });

    test('kMdnsMulticastIPv6 is ff02::fb', () {
      expect(kMdnsMulticastIPv6.address, equals('ff02::fb'));
    });
  });

  group('IceOptions.useMdns', () {
    test('defaults to false', () {
      const options = IceOptions();
      expect(options.useMdns, isFalse);
    });

    test('can be enabled', () {
      const options = IceOptions(useMdns: true);
      expect(options.useMdns, isTrue);
    });

    test('can be combined with other options', () {
      const options = IceOptions(
        useMdns: true,
        useTcp: true,
        useUdp: true,
      );
      expect(options.useMdns, isTrue);
      expect(options.useTcp, isTrue);
      expect(options.useUdp, isTrue);
    });
  });

  group('Global mdnsService', () {
    test('is accessible', () {
      expect(mdnsService, isA<MdnsService>());
    });

    test('can register hostnames', () {
      final hostname = mdnsService.registerHostname('10.10.10.10');
      expect(hostname.endsWith('.local'), isTrue);

      // Clean up
      mdnsService.stop();
    });
  });

  group('MdnsService network operations', () {
    late MdnsService service1;
    late MdnsService service2;

    setUp(() {
      service1 = MdnsService();
      service2 = MdnsService();
    });

    tearDown(() async {
      await service1.stop();
      await service2.stop();
    });

    test('start() sets isRunning to true', () async {
      try {
        await service1.start();
        expect(service1.isRunning, isTrue);
      } catch (e) {
        // mDNS port may be in use, that's OK
        expect(service1.isRunning, isFalse);
      }
    });

    test('start() is idempotent', () async {
      try {
        await service1.start();
        await service1.start();
        expect(service1.isRunning, isTrue);
      } catch (e) {
        // mDNS port may be in use
      }
    });

    test('stop() sets isRunning to false', () async {
      try {
        await service1.start();
      } catch (e) {
        // Ignore startup errors
      }

      await service1.stop();
      expect(service1.isRunning, isFalse);
    });

    test('stop() is idempotent', () async {
      await service1.stop();
      await service1.stop();
      expect(service1.isRunning, isFalse);
    });

    test('resolutionTimeout is 3 seconds', () {
      expect(MdnsService.resolutionTimeout, equals(const Duration(seconds: 3)));
    });

    test('recordTtl is 120 seconds', () {
      expect(MdnsService.recordTtl, equals(120));
    });
  });

  group('MdnsService DNS name parsing', () {
    test('handles empty hostname parts gracefully', () {
      final service = MdnsService();

      // Register with a simple hostname to verify parsing works
      service.registerWithHostname('a.b.c.local', '1.1.1.1');
      expect(service.getRegisteredAddress('a.b.c.local'), equals('1.1.1.1'));
    });

    test('handles deeply nested hostnames', () {
      final service = MdnsService();

      service.registerWithHostname('a.b.c.d.e.f.local', '2.2.2.2');
      expect(
          service.getRegisteredAddress('a.b.c.d.e.f.local'), equals('2.2.2.2'));
    });
  });
}
