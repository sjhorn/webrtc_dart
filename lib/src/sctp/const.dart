/// SCTP Constants
/// RFC 4960 - Stream Control Transmission Protocol
library;

/// SCTP Chunk Types
/// RFC 4960 Section 3.2
enum SctpChunkType {
  data(0),
  init(1),
  initAck(2),
  sack(3),
  heartbeat(4),
  heartbeatAck(5),
  abort(6),
  shutdown(7),
  shutdownAck(8),
  error(9),
  cookieEcho(10),
  cookieAck(11),
  shutdownComplete(12),
  // RFC 3758 - Partial Reliability Extension
  forwardTsn(192),
  // RFC 6525 - Stream Reconfiguration
  reconfig(130);

  final int value;
  const SctpChunkType(this.value);

  static SctpChunkType? fromValue(int value) {
    for (final type in values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// SCTP Cause Codes for ERROR and ABORT chunks
/// RFC 4960 Section 3.3.10
enum SctpCauseCode {
  invalidStreamIdentifier(1),
  missingMandatoryParameter(2),
  staleCookieError(3),
  outOfResource(4),
  unresolvableAddress(5),
  unrecognizedChunkType(6),
  invalidMandatoryParameter(7),
  unrecognizedParameters(8),
  noUserData(9),
  cookieReceivedWhileShuttingDown(10),
  restartWithNewAddresses(11),
  userInitiatedAbort(12),
  protocolViolation(13);

  final int value;
  const SctpCauseCode(this.value);

  static SctpCauseCode? fromValue(int value) {
    for (final code in values) {
      if (code.value == value) return code;
    }
    return null;
  }
}

/// SCTP Payload Protocol Identifiers (PPID)
/// For WebRTC Data Channels (RFC 8831)
enum SctpPpid {
  /// DCEP - Data Channel Establishment Protocol
  dcep(50),

  /// WebRTC String (UTF-8)
  webrtcString(51),

  /// WebRTC Binary
  webrtcBinary(53),

  /// WebRTC String Empty
  webrtcStringEmpty(56),

  /// WebRTC Binary Empty
  webrtcBinaryEmpty(57);

  final int value;
  const SctpPpid(this.value);

  static SctpPpid? fromValue(int value) {
    for (final ppid in values) {
      if (ppid.value == value) return ppid;
    }
    return null;
  }
}

/// SCTP Constants
class SctpConstants {
  /// SCTP common header size (12 bytes)
  static const int headerSize = 12;

  /// SCTP chunk header size (4 bytes)
  static const int chunkHeaderSize = 4;

  /// Default MTU for SCTP over DTLS
  static const int defaultMtu = 1200;

  /// Minimum SCTP packet size
  static const int minPacketSize = headerSize;

  /// Maximum stream identifier (16-bit)
  static const int maxStreamId = 65535;

  /// Default number of outbound streams
  static const int defaultOutboundStreams = 65535;

  /// Default number of inbound streams
  static const int defaultInboundStreams = 65535;

  /// Initial TSN (Transmission Sequence Number)
  /// Should be random for security
  static const int initialTsn = 0;

  /// SCTP port for DTLS encapsulation
  /// RFC 8261 - For SCTP over DTLS, port is typically 5000
  static const int dtlsPort = 5000;

  /// INIT chunk parameters
  static const int initChunkMinSize = 16;

  /// SACK chunk minimum size
  static const int sackChunkMinSize = 12;

  /// DATA chunk minimum size (16 bytes header)
  static const int dataChunkMinSize = 16;

  /// Cookie preservative parameter type
  static const int cookiePreservativeParam = 9;

  /// Supported address types parameter
  static const int supportedAddressTypesParam = 12;

  /// Forward TSN supported parameter
  static const int forwardTsnSupportedParam = 0xC000;

  /// Default RWND (Receive Window) size
  static const int defaultRwnd = 131072; // 128 KB

  /// Default a_rwnd (Advertised Receive Window)
  static const int defaultAdvertisedRwnd = 131072; // 128 KB

  /// Retransmission timeout (RTO) initial value (ms)
  static const int rtoInitial = 3000;

  /// Retransmission timeout (RTO) minimum value (ms)
  static const int rtoMin = 1000;

  /// Retransmission timeout (RTO) maximum value (ms)
  static const int rtoMax = 60000;

  /// Maximum retransmissions for INIT
  static const int maxInitRetransmits = 8;

  /// Maximum retransmissions for path
  static const int maxPathRetransmits = 5;

  /// Association maximum retransmissions
  static const int maxAssocRetransmits = 10;

  /// SACK timeout (delayed ACK timer) in milliseconds
  static const int sackTimeout = 200;

  /// Heartbeat interval in milliseconds
  static const int heartbeatInterval = 30000;

  /// Cookie lifetime in seconds
  static const int cookieLifetime = 60;

  SctpConstants._();
}

/// SCTP Chunk Flags

/// DATA chunk flags (RFC 4960 Section 3.3.1)
class SctpDataChunkFlags {
  /// End fragment flag
  static const int endFragment = 0x01;

  /// Beginning fragment flag
  static const int beginningFragment = 0x02;

  /// Unordered flag
  static const int unordered = 0x04;

  /// Immediate flag (I-bit) - RFC 7053
  static const int immediate = 0x08;

  SctpDataChunkFlags._();
}

/// SCTP Parameter Types
enum SctpParameterType {
  heartbeatInfo(1),
  ipv4Address(5),
  ipv6Address(6),
  stateCookie(7),
  unrecognizedParameters(8),
  cookiePreservative(9),
  hostNameAddress(11),
  supportedAddressTypes(12),
  outgoingStreamsRequest(13),
  incomingStreamsRequest(14),
  forwardTsnSupported(0xC000),
  adaptationLayerIndication(0xC006);

  final int value;
  const SctpParameterType(this.value);

  static SctpParameterType? fromValue(int value) {
    for (final type in values) {
      if (type.value == value) return type;
    }
    return null;
  }
}
