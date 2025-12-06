import 'dart:io';

/// Check if an address is a link-local address
/// Link-local addresses:
/// - IPv4: 169.254.0.0/16
/// - IPv6: fe80::/10
bool isLinkLocalAddress(InternetAddress address) {
  if (address.type == InternetAddressType.IPv4) {
    return address.address.startsWith('169.254.');
  } else if (address.type == InternetAddressType.IPv6) {
    return address.address.startsWith('fe80:');
  }
  return false;
}

/// Get local host addresses from network interfaces
/// Based on Chromium's network selection logic
Future<List<String>> getHostAddresses({
  bool useIpv4 = true,
  bool useIpv6 = true,
  bool useLinkLocalAddress = false,
}) async {
  // Networks to avoid (from Chromium's WebRTC implementation)
  const costlyNetworks = ['ipsec', 'tun', 'utun', 'tap'];
  const banNetworks = ['vmnet', 'veth', 'docker', 'vbox'];

  final addresses = <String>[];

  try {
    // Get all network interfaces
    final interfaces = await NetworkInterface.list();

    // Sort by name for consistent ordering (eth0 before eth1, etc.)
    interfaces.sort((a, b) => a.name.compareTo(b.name));

    for (final interface in interfaces) {
      // Skip costly and banned networks
      var skip = false;
      for (final network in [...costlyNetworks, ...banNetworks]) {
        if (interface.name.startsWith(network)) {
          skip = true;
          break;
        }
      }
      if (skip) continue;

      for (final addr in interface.addresses) {
        // Skip loopback addresses
        if (addr.isLoopback) continue;

        // Check IP version
        if (addr.type == InternetAddressType.IPv4 && !useIpv4) continue;
        if (addr.type == InternetAddressType.IPv6 && !useIpv6) continue;

        // Check link-local
        if (!useLinkLocalAddress && isLinkLocalAddress(addr)) continue;

        addresses.add(addr.address);
      }
    }
  } catch (e) {
    // If we can't list interfaces, fall back to localhost
    if (useIpv4) {
      addresses.add('127.0.0.1');
    }
    if (useIpv6) {
      addresses.add('::1');
    }
  }

  return addresses;
}

/// Parse URL string to address tuple
/// Example: "stun.example.com:3478" -> ("stun.example.com", 3478)
(String, int)? parseAddress(String? url) {
  if (url == null || url.isEmpty) return null;

  final parts = url.split(':');
  if (parts.length != 2) return null;

  final host = parts[0];
  final port = int.tryParse(parts[1]);
  if (port == null) return null;

  return (host, port);
}

/// Get the default route interface address
/// This is the address that would be used for outbound connections
Future<String?> getDefaultAddress({bool ipv6 = false}) async {
  try {
    // Create a temporary UDP socket and connect to a public address
    // This doesn't actually send data, but tells us which local address would be used
    final socket = await RawDatagramSocket.bind(
      ipv6 ? InternetAddress.anyIPv6 : InternetAddress.anyIPv4,
      0,
    );

    try {
      // Connect to Google's DNS (doesn't send packets, just determines route)
      socket.send(
        [],
        ipv6
            ? InternetAddress('2001:4860:4860::8888')
            : InternetAddress('8.8.8.8'),
        53,
      );

      // Get the local address that was selected
      return socket.address.address;
    } finally {
      socket.close();
    }
  } catch (e) {
    return null;
  }
}

/// Check if an address is private (RFC 1918)
/// - 10.0.0.0/8
/// - 172.16.0.0/12
/// - 192.168.0.0/16
bool isPrivateAddress(String address) {
  try {
    final addr = InternetAddress(address);
    if (addr.type != InternetAddressType.IPv4) {
      return false; // Only check IPv4 for now
    }

    final parts = address.split('.').map(int.parse).toList();
    if (parts.length != 4) return false;

    // 10.0.0.0/8
    if (parts[0] == 10) return true;

    // 172.16.0.0/12
    if (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) return true;

    // 192.168.0.0/16
    if (parts[0] == 192 && parts[1] == 168) return true;

    return false;
  } catch (e) {
    return false;
  }
}
