import 'dart:io';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/ice/utils.dart';

void main() {
  group('isLinkLocalAddress', () {
    test('identifies IPv4 link-local addresses', () {
      final addr1 = InternetAddress('169.254.0.1');
      final addr2 = InternetAddress('169.254.255.255');

      expect(isLinkLocalAddress(addr1), isTrue);
      expect(isLinkLocalAddress(addr2), isTrue);
    });

    test('identifies non-link-local IPv4 addresses', () {
      final addr1 = InternetAddress('192.168.1.1');
      final addr2 = InternetAddress('10.0.0.1');
      final addr3 = InternetAddress('8.8.8.8');

      expect(isLinkLocalAddress(addr1), isFalse);
      expect(isLinkLocalAddress(addr2), isFalse);
      expect(isLinkLocalAddress(addr3), isFalse);
    });

    test('identifies IPv6 link-local addresses', () {
      final addr1 = InternetAddress('fe80::1');
      final addr2 = InternetAddress('fe80::abcd:1234');

      expect(isLinkLocalAddress(addr1), isTrue);
      expect(isLinkLocalAddress(addr2), isTrue);
    });

    test('identifies non-link-local IPv6 addresses', () {
      final addr1 = InternetAddress('2001:db8::1');
      final addr2 = InternetAddress('::1');

      expect(isLinkLocalAddress(addr1), isFalse);
      expect(isLinkLocalAddress(addr2), isFalse);
    });
  });

  group('getHostAddresses', () {
    test('returns addresses', () async {
      final addresses = await getHostAddresses();

      expect(addresses, isNotEmpty);
      // Should have at least localhost
      expect(addresses.length, greaterThanOrEqualTo(0));
    });

    test('filters by IPv4', () async {
      final addresses = await getHostAddresses(useIpv4: true, useIpv6: false);

      for (final address in addresses) {
        final addr = InternetAddress(address);
        expect(addr.type, equals(InternetAddressType.IPv4));
      }
    });

    test('filters by IPv6', () async {
      final addresses = await getHostAddresses(useIpv4: false, useIpv6: true);

      for (final address in addresses) {
        final addr = InternetAddress(address);
        expect(addr.type, equals(InternetAddressType.IPv6));
      }
    });

    test('excludes link-local by default', () async {
      final addresses = await getHostAddresses(useLinkLocalAddress: false);

      for (final address in addresses) {
        final addr = InternetAddress(address);
        expect(isLinkLocalAddress(addr), isFalse);
      }
    });

    test('includes link-local when requested', () async {
      final addresses = await getHostAddresses(useLinkLocalAddress: true);

      // Can't guarantee link-local addresses exist, just check it doesn't crash
      expect(addresses, isA<List<String>>());
    });
  });

  group('parseAddress', () {
    test('parses valid address', () {
      final result = parseAddress('stun.example.com:3478');

      expect(result, isNotNull);
      expect(result!.$1, equals('stun.example.com'));
      expect(result.$2, equals(3478));
    });

    test('parses IP address with port', () {
      final result = parseAddress('192.168.1.1:8080');

      expect(result, isNotNull);
      expect(result!.$1, equals('192.168.1.1'));
      expect(result.$2, equals(8080));
    });

    test('returns null for null input', () {
      expect(parseAddress(null), isNull);
    });

    test('returns null for empty string', () {
      expect(parseAddress(''), isNull);
    });

    test('returns null for invalid format', () {
      expect(parseAddress('example.com'), isNull);
      expect(parseAddress('example.com:abc'), isNull);
      expect(parseAddress('example.com:3478:extra'), isNull);
    });
  });

  group('getDefaultAddress', () {
    test('returns an address', () async {
      final address = await getDefaultAddress();

      // Should return some address (or null if network unavailable)
      expect(address, anyOf(isNull, isA<String>()));
    });

    test('returns IPv4 by default', () async {
      final address = await getDefaultAddress(ipv6: false);

      if (address != null) {
        final addr = InternetAddress(address);
        expect(addr.type, equals(InternetAddressType.IPv4));
      }
    });
  });

  group('isPrivateAddress', () {
    test('identifies 10.0.0.0/8 as private', () {
      expect(isPrivateAddress('10.0.0.1'), isTrue);
      expect(isPrivateAddress('10.255.255.255'), isTrue);
      expect(isPrivateAddress('10.123.45.67'), isTrue);
    });

    test('identifies 172.16.0.0/12 as private', () {
      expect(isPrivateAddress('172.16.0.1'), isTrue);
      expect(isPrivateAddress('172.31.255.255'), isTrue);
      expect(isPrivateAddress('172.20.1.1'), isTrue);
    });

    test('identifies 192.168.0.0/16 as private', () {
      expect(isPrivateAddress('192.168.0.1'), isTrue);
      expect(isPrivateAddress('192.168.255.255'), isTrue);
      expect(isPrivateAddress('192.168.1.100'), isTrue);
    });

    test('identifies public addresses as non-private', () {
      expect(isPrivateAddress('8.8.8.8'), isFalse);
      expect(isPrivateAddress('1.1.1.1'), isFalse);
      expect(isPrivateAddress('172.15.0.1'), isFalse);
      expect(isPrivateAddress('172.32.0.1'), isFalse);
      expect(isPrivateAddress('11.0.0.1'), isFalse);
      expect(isPrivateAddress('192.167.1.1'), isFalse);
      expect(isPrivateAddress('193.168.1.1'), isFalse);
    });

    test('handles invalid addresses', () {
      expect(isPrivateAddress('not-an-ip'), isFalse);
      expect(isPrivateAddress(''), isFalse);
    });
  });
}
