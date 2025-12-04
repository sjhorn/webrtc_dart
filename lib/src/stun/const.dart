/// STUN constants and enums
/// Based on RFC 5389 and RFC 5766 (TURN)
library;

// Magic cookie value (0x2112A442)
const int stunCookie = 0x2112A442;

// STUN header is 20 bytes
const int stunHeaderLength = 20;

// Attribute lengths
const int fingerprintLength = 8;
const int integrityLength = 24;

// XOR value for fingerprint calculation
const int fingerprintXor = 0x5354554E; // "STUN" in ASCII

// IP protocol constants
const int ipv4Protocol = 1;
const int ipv6Protocol = 2;

// Retry constants
const int retryMax = 6;
const int retryRto = 50; // milliseconds

/// STUN message classes
enum StunClass {
  request(0x000),
  indication(0x010),
  successResponse(0x100),
  errorResponse(0x110);

  const StunClass(this.value);
  final int value;
}

/// STUN message methods
enum StunMethod {
  binding(0x001),
  sharedSecret(0x002),
  allocate(0x003),
  refresh(0x004),
  send(0x006),
  data(0x007),
  createPermission(0x008),
  channelBind(0x009);

  const StunMethod(this.value);
  final int value;
}

/// STUN attribute types
enum StunAttributeType {
  mappedAddress(0x0001),
  changeRequest(0x0003),
  sourceAddress(0x0004),
  changedAddress(0x0005),
  username(0x0006),
  messageIntegrity(0x0008),
  errorCode(0x0009),
  channelNumber(0x000C),
  lifetime(0x000D),
  xorPeerAddress(0x0012),
  data(0x0013),
  realm(0x0014),
  nonce(0x0015),
  xorRelayedAddress(0x0016),
  requestedTransport(0x0019),
  xorMappedAddress(0x0020),
  priority(0x0024),
  useCandidate(0x0025),
  software(0x8022),
  fingerprint(0x8028),
  iceControlled(0x8029),
  iceControlling(0x802A),
  responseOrigin(0x802B),
  otherAddress(0x802C);

  const StunAttributeType(this.value);
  final int value;

  static StunAttributeType? fromValue(int value) {
    for (final type in StunAttributeType.values) {
      if (type.value == value) {
        return type;
      }
    }
    return null;
  }
}
