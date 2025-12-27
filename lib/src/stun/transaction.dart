/// STUN Transaction with exponential backoff retry
/// Based on RFC 5389 Section 7.2.1
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import 'const.dart';
import 'message.dart';

final _log = Logger('StunTransaction');

/// Exception thrown when a STUN transaction times out after max retries
class TransactionTimeout implements Exception {
  final String message;
  TransactionTimeout([this.message = 'STUN transaction timed out']);

  @override
  String toString() => 'TransactionTimeout: $message';
}

/// Exception thrown when a STUN transaction receives an error response
class TransactionFailed implements Exception {
  final StunMessage response;
  final String? address;
  final int? port;

  TransactionFailed(this.response, [this.address, this.port]);

  @override
  String toString() {
    final errorCode = response.getAttribute(StunAttributeType.errorCode);
    if (errorCode != null) {
      final (code, reason) = errorCode as (int, String);
      return 'TransactionFailed: $code $reason';
    }
    return 'TransactionFailed: Error response received';
  }
}

/// Callback type for sending STUN messages
typedef StunSendCallback = Future<void> Function(Uint8List data);

/// STUN Transaction manages request/response with exponential backoff retry
///
/// Usage:
/// ```dart
/// final transaction = StunTransaction(
///   request: stunMessage,
///   sendCallback: (data) async => socket.send(data, addr, port),
///   maxRetransmissions: 6, // optional, defaults to retryMax
/// );
///
/// try {
///   final response = await transaction.run();
///   // Handle success response
/// } on TransactionTimeout {
///   // Handle timeout
/// } on TransactionFailed catch (e) {
///   // Handle error response
/// }
/// ```
class StunTransaction {
  final StunMessage request;
  final StunSendCallback sendCallback;
  final int maxRetransmissions;

  int _timeoutDelay;
  bool _ended = false;
  int _tries = 0;
  final int _triesMax;

  final Completer<StunMessage> _responseCompleter = Completer<StunMessage>();

  /// Create a new STUN transaction
  ///
  /// [request] - The STUN request message to send
  /// [sendCallback] - Callback to send the serialized message
  /// [maxRetransmissions] - Maximum number of retries (default: retryMax = 6)
  StunTransaction({
    required this.request,
    required this.sendCallback,
    this.maxRetransmissions = retryMax,
  })  : _timeoutDelay = retryRto,
        _triesMax = 1 + maxRetransmissions;

  /// Get the transaction ID for matching responses
  String get transactionId => request.transactionIdHex;

  /// Check if transaction has ended (completed, failed, or cancelled)
  bool get ended => _ended;

  /// Call this when a STUN response is received
  ///
  /// Returns true if the response was handled by this transaction
  bool responseReceived(StunMessage message) {
    if (_ended || _responseCompleter.isCompleted) {
      return false;
    }

    // Check if this response matches our transaction
    if (message.transactionIdHex != transactionId) {
      return false;
    }

    if (message.messageClass == StunClass.successResponse) {
      _responseCompleter.complete(message);
      return true;
    } else if (message.messageClass == StunClass.errorResponse) {
      _responseCompleter.completeError(TransactionFailed(message));
      return true;
    }

    return false;
  }

  /// Run the transaction with exponential backoff retry
  ///
  /// Returns the success response, or throws [TransactionTimeout] or [TransactionFailed]
  Future<StunMessage> run() async {
    // Start the retry loop in background
    _retryLoop();

    try {
      final response = await _responseCompleter.future;
      return response;
    } finally {
      cancel();
    }
  }

  /// Retry loop with exponential backoff
  Future<void> _retryLoop() async {
    while (_tries < _triesMax && !_ended) {
      try {
        final requestBytes = request.toBytes();
        await sendCallback(requestBytes);
        _log.fine(
            '[Transaction] Sent request ${transactionId.substring(0, 8)}... '
            '(attempt ${_tries + 1}/$_triesMax, timeout: ${_timeoutDelay}ms)');
      } catch (e) {
        _log.fine('[Transaction] Send failed: $e');
      }

      // Wait for timeout or response
      await Future.delayed(Duration(milliseconds: _timeoutDelay));

      if (_ended || _responseCompleter.isCompleted) {
        break;
      }

      // Exponential backoff
      _timeoutDelay *= 2;
      _tries++;
    }

    // If we exhausted all retries without a response
    if (_tries >= _triesMax && !_responseCompleter.isCompleted) {
      _log.fine(
          '[Transaction] Timeout after $_tries attempts for ${transactionId.substring(0, 8)}...');
      _responseCompleter.completeError(
        TransactionTimeout('Max retries ($_triesMax) exceeded'),
      );
    }
  }

  /// Cancel the transaction
  void cancel() {
    _ended = true;
  }
}

/// Transaction manager for tracking multiple concurrent STUN transactions
class TransactionManager {
  final Map<String, StunTransaction> _transactions = {};

  /// Register a transaction for response matching
  void register(StunTransaction transaction) {
    _transactions[transaction.transactionId] = transaction;
  }

  /// Unregister a transaction
  void unregister(StunTransaction transaction) {
    _transactions.remove(transaction.transactionId);
  }

  /// Handle an incoming STUN response by matching to a pending transaction
  ///
  /// Returns true if the response was handled
  bool handleResponse(StunMessage response) {
    final transactionId = response.transactionIdHex;
    final transaction = _transactions[transactionId];

    if (transaction != null) {
      final handled = transaction.responseReceived(response);
      if (handled) {
        _transactions.remove(transactionId);
      }
      return handled;
    }

    return false;
  }

  /// Cancel all pending transactions
  void cancelAll() {
    for (final transaction in _transactions.values) {
      transaction.cancel();
    }
    _transactions.clear();
  }

  /// Get the number of pending transactions
  int get pendingCount => _transactions.length;
}
