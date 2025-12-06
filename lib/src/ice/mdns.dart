/// mDNS Candidate Obfuscation
///
/// Implements local IP address obfuscation using mDNS (multicast DNS).
/// This provides privacy by replacing local IP addresses in ICE candidates
/// with random `.local` hostnames that can only be resolved on the local network.
///
/// See: https://datatracker.ietf.org/doc/html/rfc8828 (WebRTC IP Address Handling)
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// mDNS port (RFC 6762)
const int kMdnsPort = 5353;

/// mDNS multicast address for IPv4
final InternetAddress kMdnsMulticastIPv4 = InternetAddress('224.0.0.251');

/// mDNS multicast address for IPv6
final InternetAddress kMdnsMulticastIPv6 = InternetAddress('ff02::fb');

/// DNS record types
class DnsRecordType {
  static const int a = 1; // IPv4 address
  static const int aaaa = 28; // IPv6 address
  static const int ptr = 12; // Domain name pointer
  static const int txt = 16; // Text record
  static const int srv = 33; // Service record
  static const int any = 255; // Any record
}

/// DNS class
class DnsClass {
  static const int internet = 1;
  static const int cacheFlush = 0x8001; // Class IN with cache flush bit
}

/// DNS flags
class DnsFlags {
  static const int query = 0x0000;
  static const int response = 0x8400; // Response with AA (authoritative) bit
}

/// mDNS hostname generator
///
/// Generates RFC 6762 compliant `.local` hostnames using UUIDs.
class MdnsHostname {
  /// Generate a random mDNS hostname
  ///
  /// Format: `{uuid}.local` where uuid is a random v4 UUID
  static String generate() {
    final uuid = _generateUuid();
    return '$uuid.local';
  }

  /// Check if a hostname is an mDNS `.local` hostname
  static bool isLocalHostname(String hostname) {
    return hostname.toLowerCase().endsWith('.local');
  }

  /// Generate a v4 UUID
  static String _generateUuid() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));

    // Set version to 4
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    // Set variant to RFC 4122
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    // Format as UUID string
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

/// mDNS service for registering and resolving `.local` hostnames
///
/// This provides the ability to:
/// - Register a hostname -> IP mapping on the local network
/// - Resolve `.local` hostnames to IP addresses
class MdnsService {
  /// Registered hostnames (hostname -> IP address)
  final Map<String, String> _registrations = {};

  /// Pending resolutions (hostname -> completers)
  final Map<String, List<Completer<String?>>> _pendingResolutions = {};

  /// mDNS socket
  RawDatagramSocket? _socket;

  /// Whether the service is running
  bool _running = false;

  /// Cached resolutions (hostname -> IP address)
  final Map<String, String> _cache = {};

  /// Resolution timeout
  static const resolutionTimeout = Duration(seconds: 3);

  /// TTL for mDNS records (in seconds)
  static const int recordTtl = 120;

  /// Start the mDNS service
  Future<void> start() async {
    if (_running) return;

    try {
      // Bind to mDNS multicast address
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kMdnsPort,
        reuseAddress: true,
        reusePort: true,
      );

      // Join multicast group
      _socket!.joinMulticast(kMdnsMulticastIPv4);

      // Listen for mDNS packets
      _socket!.listen(_handlePacket);

      _running = true;
    } catch (e) {
      // mDNS binding may fail if port is in use or no multicast support
      _running = false;
    }
  }

  /// Stop the mDNS service
  Future<void> stop() async {
    _socket?.close();
    _socket = null;
    _running = false;

    // Always clear registrations and cache
    _registrations.clear();
    _cache.clear();

    // Complete any pending resolutions with null
    for (final completers in _pendingResolutions.values) {
      for (final completer in completers) {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      }
    }
    _pendingResolutions.clear();
  }

  /// Whether the service is running
  bool get isRunning => _running;

  /// Register a hostname for a local IP address
  ///
  /// Returns the generated mDNS hostname (e.g., `abc123.local`)
  String registerHostname(String ipAddress) {
    final hostname = MdnsHostname.generate();
    _registrations[hostname] = ipAddress;
    _cache[hostname] = ipAddress;

    // Announce the hostname
    if (_running) {
      _announceHostname(hostname, ipAddress);
    }

    return hostname;
  }

  /// Register a specific hostname for an IP address
  void registerWithHostname(String hostname, String ipAddress) {
    _registrations[hostname] = ipAddress;
    _cache[hostname] = ipAddress;

    if (_running) {
      _announceHostname(hostname, ipAddress);
    }
  }

  /// Resolve an mDNS hostname to an IP address
  ///
  /// Returns null if resolution fails or times out.
  Future<String?> resolve(String hostname) async {
    if (!MdnsHostname.isLocalHostname(hostname)) {
      // Not an mDNS hostname, try regular DNS
      try {
        final addresses = await InternetAddress.lookup(hostname);
        if (addresses.isNotEmpty) {
          return addresses.first.address;
        }
      } catch (e) {
        // DNS lookup failed
      }
      return null;
    }

    // Check cache first
    if (_cache.containsKey(hostname)) {
      return _cache[hostname];
    }

    // Check if we have it registered locally
    if (_registrations.containsKey(hostname)) {
      return _registrations[hostname];
    }

    if (!_running) {
      return null;
    }

    // Send mDNS query
    final completer = Completer<String?>();
    _pendingResolutions.putIfAbsent(hostname, () => []).add(completer);

    _sendQuery(hostname);

    // Wait for response with timeout
    try {
      return await completer.future.timeout(resolutionTimeout);
    } on TimeoutException {
      _pendingResolutions[hostname]?.remove(completer);
      return null;
    }
  }

  /// Get the IP address for a registered hostname
  String? getRegisteredAddress(String hostname) {
    return _registrations[hostname];
  }

  /// Handle incoming mDNS packet
  void _handlePacket(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;

    final datagram = _socket?.receive();
    if (datagram == null) return;

    try {
      _parseMdnsPacket(datagram.data);
    } catch (e) {
      // Malformed mDNS packet, ignore
    }
  }

  /// Parse an mDNS packet
  void _parseMdnsPacket(Uint8List data) {
    if (data.length < 12) return; // Minimum DNS header size

    final view = ByteData.view(data.buffer);

    // Parse DNS header
    // final id = view.getUint16(0, Endian.big);
    final flags = view.getUint16(2, Endian.big);
    final qdCount = view.getUint16(4, Endian.big);
    final anCount = view.getUint16(6, Endian.big);
    // final nsCount = view.getUint16(8, Endian.big);
    // final arCount = view.getUint16(10, Endian.big);

    final isResponse = (flags & 0x8000) != 0;

    var offset = 12;

    // Parse questions
    for (var i = 0; i < qdCount && offset < data.length; i++) {
      final (name, newOffset) = _parseDnsName(data, offset);
      if (newOffset + 4 > data.length) break;

      final qtype = view.getUint16(newOffset, Endian.big);
      // final qclass = view.getUint16(newOffset + 2, Endian.big);
      offset = newOffset + 4;

      // If this is a query for one of our registered hostnames, respond
      if (!isResponse && _registrations.containsKey(name)) {
        final ip = _registrations[name]!;
        if (qtype == DnsRecordType.a || qtype == DnsRecordType.any) {
          _sendResponse(name, ip);
        }
      }
    }

    // Parse answers
    for (var i = 0; i < anCount && offset < data.length; i++) {
      final (name, newOffset) = _parseDnsName(data, offset);
      if (newOffset + 10 > data.length) break;

      final rtype = view.getUint16(newOffset, Endian.big);
      // final rclass = view.getUint16(newOffset + 2, Endian.big);
      // final ttl = view.getUint32(newOffset + 4, Endian.big);
      final rdlength = view.getUint16(newOffset + 8, Endian.big);
      offset = newOffset + 10;

      if (offset + rdlength > data.length) break;

      // Parse A record (IPv4)
      if (rtype == DnsRecordType.a && rdlength == 4) {
        final ip =
            '${data[offset]}.${data[offset + 1]}.${data[offset + 2]}.${data[offset + 3]}';
        _cache[name] = ip;

        // Complete pending resolutions
        final completers = _pendingResolutions.remove(name);
        if (completers != null) {
          for (final completer in completers) {
            if (!completer.isCompleted) {
              completer.complete(ip);
            }
          }
        }
      }

      // Parse AAAA record (IPv6)
      if (rtype == DnsRecordType.aaaa && rdlength == 16) {
        final parts = <String>[];
        for (var j = 0; j < 16; j += 2) {
          final val = (data[offset + j] << 8) | data[offset + j + 1];
          parts.add(val.toRadixString(16));
        }
        final ip = parts.join(':');
        _cache[name] = ip;

        // Complete pending resolutions
        final completers = _pendingResolutions.remove(name);
        if (completers != null) {
          for (final completer in completers) {
            if (!completer.isCompleted) {
              completer.complete(ip);
            }
          }
        }
      }

      offset += rdlength;
    }
  }

  /// Parse a DNS name from packet
  (String, int) _parseDnsName(Uint8List data, int offset) {
    final parts = <String>[];
    var currentOffset = offset;
    var jumped = false;
    var finalOffset = offset;

    while (currentOffset < data.length) {
      final length = data[currentOffset];

      if (length == 0) {
        if (!jumped) finalOffset = currentOffset + 1;
        break;
      }

      // Check for pointer (compression)
      if ((length & 0xC0) == 0xC0) {
        if (currentOffset + 1 >= data.length) break;
        final pointer = ((length & 0x3F) << 8) | data[currentOffset + 1];
        if (!jumped) finalOffset = currentOffset + 2;
        currentOffset = pointer;
        jumped = true;
        continue;
      }

      currentOffset++;
      if (currentOffset + length > data.length) break;

      final part = String.fromCharCodes(
          data.sublist(currentOffset, currentOffset + length));
      parts.add(part);
      currentOffset += length;
    }

    return (parts.join('.'), finalOffset);
  }

  /// Encode a DNS name
  Uint8List _encodeDnsName(String name) {
    final parts = name.split('.');
    final bytes = <int>[];

    for (final part in parts) {
      bytes.add(part.length);
      bytes.addAll(part.codeUnits);
    }
    bytes.add(0); // Null terminator

    return Uint8List.fromList(bytes);
  }

  /// Send an mDNS query
  void _sendQuery(String hostname) {
    if (_socket == null) return;

    final nameBytes = _encodeDnsName(hostname);
    final packet = Uint8List(12 + nameBytes.length + 4);
    final view = ByteData.view(packet.buffer);

    // DNS header
    view.setUint16(0, 0, Endian.big); // ID
    view.setUint16(2, DnsFlags.query, Endian.big); // Flags
    view.setUint16(4, 1, Endian.big); // QDCOUNT
    view.setUint16(6, 0, Endian.big); // ANCOUNT
    view.setUint16(8, 0, Endian.big); // NSCOUNT
    view.setUint16(10, 0, Endian.big); // ARCOUNT

    // Question
    packet.setRange(12, 12 + nameBytes.length, nameBytes);
    final qOffset = 12 + nameBytes.length;
    view.setUint16(qOffset, DnsRecordType.a, Endian.big); // QTYPE
    view.setUint16(qOffset + 2, DnsClass.internet, Endian.big); // QCLASS

    _socket!.send(packet, kMdnsMulticastIPv4, kMdnsPort);
  }

  /// Announce a hostname via mDNS
  void _announceHostname(String hostname, String ipAddress) {
    _sendResponse(hostname, ipAddress);
  }

  /// Send an mDNS response
  void _sendResponse(String hostname, String ipAddress) {
    if (_socket == null) return;

    final nameBytes = _encodeDnsName(hostname);
    final ipParts = ipAddress.split('.');
    if (ipParts.length != 4) return; // Only IPv4 for now

    final packet = Uint8List(12 + nameBytes.length + 10 + 4);
    final view = ByteData.view(packet.buffer);

    // DNS header
    view.setUint16(0, 0, Endian.big); // ID
    view.setUint16(2, DnsFlags.response, Endian.big); // Flags
    view.setUint16(4, 0, Endian.big); // QDCOUNT
    view.setUint16(6, 1, Endian.big); // ANCOUNT
    view.setUint16(8, 0, Endian.big); // NSCOUNT
    view.setUint16(10, 0, Endian.big); // ARCOUNT

    // Answer
    packet.setRange(12, 12 + nameBytes.length, nameBytes);
    var offset = 12 + nameBytes.length;
    view.setUint16(offset, DnsRecordType.a, Endian.big); // TYPE
    view.setUint16(offset + 2, DnsClass.cacheFlush, Endian.big); // CLASS
    view.setUint32(offset + 4, recordTtl, Endian.big); // TTL
    view.setUint16(offset + 8, 4, Endian.big); // RDLENGTH
    offset += 10;

    // RDATA (IPv4 address)
    for (var i = 0; i < 4; i++) {
      packet[offset + i] = int.parse(ipParts[i]);
    }

    _socket!.send(packet, kMdnsMulticastIPv4, kMdnsPort);
  }
}

/// Global mDNS service instance
final mdnsService = MdnsService();
