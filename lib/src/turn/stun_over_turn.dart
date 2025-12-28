import 'dart:async';
import 'dart:typed_data';

import 'package:webrtc_dart/src/stun/attributes.dart';
import 'package:webrtc_dart/src/stun/const.dart';
import 'package:webrtc_dart/src/stun/message.dart';

import 'turn_client.dart';

/// StunOverTurnProtocol wraps a TurnClient to enable STUN connectivity checks
/// through TURN relay.
///
/// This is used when ICE needs to perform connectivity checks on relay candidates.
/// STUN binding requests/responses are relayed through the TURN server.
///
/// Usage:
/// ```dart
/// final turnClient = TurnClient(...);
/// await turnClient.connect();
/// final stunOverTurn = StunOverTurnProtocol(turnClient);
///
/// // Send STUN binding request through TURN
/// final response = await stunOverTurn.request(request, peerAddress, integrityKey);
/// ```
class StunOverTurnProtocol {
  /// The underlying TURN client
  final TurnClient turn;

  /// Active transactions (transaction ID -> completer)
  final Map<String, Completer<(StunMessage, Address)>> _transactions = {};

  /// Callback for incoming STUN requests
  void Function(StunMessage message, Address address, Uint8List data)?
      onRequestReceived;

  /// Callback for incoming non-STUN data
  void Function(Uint8List data)? onDataReceived;

  /// Subscription to TURN client data
  StreamSubscription<(Address, Uint8List)>? _subscription;

  StunOverTurnProtocol(this.turn) {
    _subscription = turn.onReceive.listen(_handleData);
  }

  /// Handle incoming data from TURN relay
  void _handleData((Address, Uint8List) event) {
    final (addr, data) = event;

    try {
      final message = parseStunMessage(data);
      if (message == null) {
        // Not a STUN message, pass through
        onDataReceived?.call(data);
        return;
      }

      if (message.messageClass == StunClass.successResponse ||
          message.messageClass == StunClass.errorResponse) {
        // Response to our request
        final transaction = _transactions.remove(message.transactionIdHex);
        if (transaction != null && !transaction.isCompleted) {
          transaction.complete((message, addr));
        }
      } else if (message.messageClass == StunClass.request) {
        // Incoming request (ICE connectivity check from peer)
        onRequestReceived?.call(message, addr, data);
      }
    } catch (e) {
      // Failed to parse, treat as non-STUN data
      onDataReceived?.call(data);
    }
  }

  /// Send a STUN request through TURN and wait for response
  ///
  /// [request] - The STUN message to send
  /// [addr] - The peer address to send to (through TURN)
  /// [integrityKey] - Optional message integrity key for ICE credentials
  Future<(StunMessage, Address)> request(
    StunMessage request,
    Address addr, {
    Uint8List? integrityKey,
  }) async {
    if (_transactions.containsKey(request.transactionIdHex)) {
      throw StateError('Transaction already exists');
    }

    // Add integrity and fingerprint if key provided
    if (integrityKey != null) {
      request.addMessageIntegrity(integrityKey);
      request.addFingerprint();
    }

    final completer = Completer<(StunMessage, Address)>();
    _transactions[request.transactionIdHex] = completer;

    try {
      // Send through TURN relay
      await turn.sendData(addr, request.toBytes());

      // Wait for response with timeout (3 seconds default)
      final result = await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          _transactions.remove(request.transactionIdHex);
          throw TimeoutException('STUN request timed out');
        },
      );

      return result;
    } catch (e) {
      _transactions.remove(request.transactionIdHex);
      rethrow;
    }
  }

  /// Send raw data through TURN
  Future<void> sendData(Uint8List data, Address addr) async {
    await turn.sendData(addr, data);
  }

  /// Send a STUN message through TURN (no response expected)
  Future<void> sendStun(StunMessage message, Address addr) async {
    await turn.sendData(addr, message.toBytes());
  }

  /// Get the relayed address from the TURN allocation
  Address? get relayedAddress => turn.allocation?.relayedAddress;

  /// Get the mapped address from the TURN allocation
  Address? get mappedAddress => turn.allocation?.mappedAddress;

  /// Close the protocol (also closes the underlying TURN client)
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    _transactions.clear();
    await turn.close();
  }
}

/// Factory function to create a STUN-over-TURN client
///
/// This handles the full setup: creating TURN client, connecting,
/// and wrapping with StunOverTurnProtocol.
Future<StunOverTurnProtocol> createStunOverTurnClient({
  required Address address,
  required String username,
  required String password,
  TurnTransport transport = TurnTransport.udp,
  int lifetime = 600,
}) async {
  final turn = TurnClient(
    serverAddress: address,
    username: username,
    password: password,
    transport: transport,
    lifetime: lifetime,
  );

  await turn.connect();
  return StunOverTurnProtocol(turn);
}
