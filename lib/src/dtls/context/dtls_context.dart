import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/handshake/message/client_hello.dart';
import 'package:webrtc_dart/src/dtls/handshake/message/server_hello.dart';
import 'package:webrtc_dart/src/dtls/record/const.dart';

/// DTLS connection state and configuration
/// Tracks protocol state, epoch, sequence numbers, and handshake messages
class DtlsContext {
  /// Protocol version being used
  ProtocolVersion version;

  /// Current epoch (incremented when cipher changes)
  int epoch;

  /// Sequence number for sending records
  int sequenceNumber;

  /// Message sequence number for handshake messages (increments per message)
  int handshakeMessageSeq;

  /// Remote endpoint address and port (for identification)
  String? remoteAddress;
  int? remotePort;

  /// Session ID for resumption
  Uint8List? sessionId;

  /// Cookie for DTLS handshake (DoS protection)
  Uint8List? cookie;

  /// Buffer of all handshake messages for verify_data computation
  /// Used to compute the Finished message
  final List<Uint8List> handshakeMessages;

  /// ClientHello message (for reference during handshake)
  ClientHello? clientHello;

  /// ServerHello message (for reference during handshake)
  ServerHello? serverHello;

  /// Local random value (from ClientHello or ServerHello)
  Uint8List? localRandom;

  /// Remote random value (from ClientHello or ServerHello)
  Uint8List? remoteRandom;

  /// Master secret (computed after key exchange)
  Uint8List? masterSecret;

  /// Pre-master secret (computed during key exchange)
  Uint8List? preMasterSecret;

  /// Whether extended master secret is being used (RFC 7627)
  bool useExtendedMasterSecret;

  /// Whether the handshake is complete
  bool handshakeComplete;

  /// Whether we've sent ChangeCipherSpec
  bool sentChangeCipherSpec;

  /// Whether we've received ChangeCipherSpec
  bool receivedChangeCipherSpec;

  /// Maximum transmission unit for fragmentation
  int mtu;

  DtlsContext({
    this.version = ProtocolVersion.dtls12,
    this.epoch = 0,
    this.sequenceNumber = 0,
    this.handshakeMessageSeq = 0,
    this.remoteAddress,
    this.remotePort,
    this.sessionId,
    this.cookie,
    List<Uint8List>? handshakeMessages,
    this.clientHello,
    this.serverHello,
    this.localRandom,
    this.remoteRandom,
    this.masterSecret,
    this.preMasterSecret,
    this.useExtendedMasterSecret = false,
    this.handshakeComplete = false,
    this.sentChangeCipherSpec = false,
    this.receivedChangeCipherSpec = false,
    this.mtu = 1200,
  }) : handshakeMessages = handshakeMessages ?? [];

  /// Add a handshake message to the buffer
  /// Used for computing Finished verify_data
  void addHandshakeMessage(Uint8List message) {
    handshakeMessages.add(Uint8List.fromList(message));
  }

  /// Get the next handshake message sequence number and increment it
  int getNextHandshakeMessageSeq() {
    return handshakeMessageSeq++;
  }

  /// Get all handshake messages concatenated for hash computation
  /// Used for PRF verify_data computation
  Uint8List getAllHandshakeMessages() {
    final totalLength =
        handshakeMessages.fold<int>(0, (sum, msg) => sum + msg.length);
    final result = Uint8List(totalLength);
    var offset = 0;

    for (final message in handshakeMessages) {
      result.setRange(offset, offset + message.length, message);
      offset += message.length;
    }

    return result;
  }

  /// Clear handshake messages buffer
  void clearHandshakeMessages() {
    handshakeMessages.clear();
  }

  /// Increment epoch (when cipher changes)
  void incrementEpoch() {
    epoch++;
    sequenceNumber = 0; // Reset sequence number on epoch change
  }

  /// Get next sequence number and increment
  int getNextSequenceNumber() {
    return sequenceNumber++;
  }

  /// Get current write epoch
  int get writeEpoch => epoch;

  /// Get current read epoch
  int readEpoch = 0;

  /// Get next write sequence number
  int getNextWriteSequence() {
    return getNextSequenceNumber();
  }

  /// Reset context for new handshake
  void reset() {
    epoch = 0;
    sequenceNumber = 0;
    sessionId = null;
    cookie = null;
    handshakeMessages.clear();
    clientHello = null;
    serverHello = null;
    localRandom = null;
    remoteRandom = null;
    masterSecret = null;
    preMasterSecret = null;
    useExtendedMasterSecret = false;
    handshakeComplete = false;
    sentChangeCipherSpec = false;
    receivedChangeCipherSpec = false;
  }

  @override
  String toString() {
    return 'DtlsContext(version=$version, epoch=$epoch, seq=$sequenceNumber, '
        'handshakeComplete=$handshakeComplete)';
  }
}
