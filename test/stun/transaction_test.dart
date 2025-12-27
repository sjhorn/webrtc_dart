import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/stun/const.dart';
import 'package:webrtc_dart/src/stun/message.dart';
import 'package:webrtc_dart/src/stun/transaction.dart';

void main() {
  group('StunTransaction', () {
    late StunMessage request;
    late List<Uint8List> sentMessages;

    setUp(() {
      request = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.request,
      );
      sentMessages = [];
    });

    test('sends request immediately on run()', () async {
      final transaction = StunTransaction(
        request: request,
        sendCallback: (data) async {
          sentMessages.add(data);
        },
        maxRetransmissions: 0, // Only one attempt
      );

      // Start transaction but don't wait for it
      unawaited(transaction.run().catchError((_) {}));

      // Give it time to send
      await Future.delayed(Duration(milliseconds: 10));

      expect(sentMessages.length, equals(1));
      transaction.cancel();
    });

    test('returns success response', () async {
      final transaction = StunTransaction(
        request: request,
        sendCallback: (data) async {
          sentMessages.add(data);
        },
      );

      // Start transaction
      final responseFuture = transaction.run();

      // Wait a bit then simulate response
      await Future.delayed(Duration(milliseconds: 10));

      final response = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.successResponse,
        transactionId: request.transactionId,
      );

      final handled = transaction.responseReceived(response);
      expect(handled, isTrue);

      final result = await responseFuture;
      expect(result.messageClass, equals(StunClass.successResponse));
      expect(result.transactionIdHex, equals(request.transactionIdHex));
    });

    test('throws TransactionFailed on error response', () async {
      final transaction = StunTransaction(
        request: request,
        sendCallback: (data) async {
          sentMessages.add(data);
        },
      );

      // Start transaction
      final responseFuture = transaction.run();

      // Wait a bit then simulate error response
      await Future.delayed(Duration(milliseconds: 10));

      final errorResponse = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.errorResponse,
        transactionId: request.transactionId,
      );
      errorResponse.setAttribute(
        StunAttributeType.errorCode,
        (401, 'Unauthorized'),
      );

      final handled = transaction.responseReceived(errorResponse);
      expect(handled, isTrue);

      expect(
        () => responseFuture,
        throwsA(isA<TransactionFailed>()),
      );
    });

    test('throws TransactionTimeout after max retries', () async {
      final transaction = StunTransaction(
        request: request,
        sendCallback: (data) async {
          sentMessages.add(data);
        },
        maxRetransmissions: 1, // Only 2 attempts total (1 + 1)
      );

      expect(
        () => transaction.run(),
        throwsA(isA<TransactionTimeout>()),
      );

      // Should have sent twice: initial + 1 retry
      // Wait for retries to complete
      await Future.delayed(Duration(milliseconds: 200));
      expect(sentMessages.length, greaterThanOrEqualTo(2));
    }, timeout: Timeout(Duration(seconds: 2)));

    test('exponential backoff doubles timeout each retry', () async {
      var sendCount = 0;
      final sendTimes = <int>[];

      final transaction = StunTransaction(
        request: request,
        sendCallback: (data) async {
          sendTimes.add(DateTime.now().millisecondsSinceEpoch);
          sendCount++;
        },
        maxRetransmissions: 2, // 3 attempts total
      );

      expect(
        () => transaction.run(),
        throwsA(isA<TransactionTimeout>()),
      );

      // Wait for all retries
      await Future.delayed(Duration(milliseconds: 400));

      expect(sendCount, equals(3));

      // Check timing intervals (approximately)
      // First interval should be ~50ms (retryRto)
      // Second interval should be ~100ms (retryRto * 2)
      if (sendTimes.length >= 3) {
        final interval1 = sendTimes[1] - sendTimes[0];
        final interval2 = sendTimes[2] - sendTimes[1];

        // Allow some timing slack
        expect(interval1, greaterThanOrEqualTo(40));
        expect(interval1, lessThan(80));
        expect(interval2, greaterThanOrEqualTo(80));
        expect(interval2, lessThan(160));
      }
    }, timeout: Timeout(Duration(seconds: 2)));

    test('ignores response with wrong transaction ID', () async {
      final transaction = StunTransaction(
        request: request,
        sendCallback: (data) async {},
        maxRetransmissions: 0,
      );

      // Start transaction
      unawaited(transaction.run().catchError((_) {}));

      // Create response with different transaction ID
      final wrongResponse = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.successResponse,
        // Different transaction ID (auto-generated)
      );

      final handled = transaction.responseReceived(wrongResponse);
      expect(handled, isFalse);

      transaction.cancel();
    });

    test('cancel() stops retries', () async {
      var sendCount = 0;

      final transaction = StunTransaction(
        request: request,
        sendCallback: (data) async {
          sendCount++;
        },
        maxRetransmissions: 10, // Many retries
      );

      // Start transaction
      unawaited(transaction.run().catchError((_) {}));

      // Wait for first send
      await Future.delayed(Duration(milliseconds: 10));
      expect(sendCount, equals(1));

      // Cancel
      transaction.cancel();
      expect(transaction.ended, isTrue);

      // Wait to ensure no more sends
      await Future.delayed(Duration(milliseconds: 200));
      expect(sendCount, equals(1)); // Still just 1
    });

    test('transactionId matches request', () {
      final transaction = StunTransaction(
        request: request,
        sendCallback: (data) async {},
      );

      expect(transaction.transactionId, equals(request.transactionIdHex));
    });
  });

  group('TransactionManager', () {
    late TransactionManager manager;
    late StunMessage request;

    setUp(() {
      manager = TransactionManager();
      request = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.request,
      );
    });

    test('register adds transaction', () {
      final transaction = StunTransaction(
        request: request,
        sendCallback: (data) async {},
      );

      manager.register(transaction);
      expect(manager.pendingCount, equals(1));
    });

    test('unregister removes transaction', () {
      final transaction = StunTransaction(
        request: request,
        sendCallback: (data) async {},
      );

      manager.register(transaction);
      expect(manager.pendingCount, equals(1));

      manager.unregister(transaction);
      expect(manager.pendingCount, equals(0));
    });

    test('handleResponse matches and removes transaction', () async {
      final transaction = StunTransaction(
        request: request,
        sendCallback: (data) async {},
      );

      manager.register(transaction);

      // Start transaction
      final responseFuture = transaction.run();

      // Create matching response
      final response = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.successResponse,
        transactionId: request.transactionId,
      );

      final handled = manager.handleResponse(response);
      expect(handled, isTrue);
      expect(manager.pendingCount, equals(0));

      await responseFuture;
    });

    test('handleResponse returns false for unknown transaction', () {
      final unknownResponse = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.successResponse,
      );

      final handled = manager.handleResponse(unknownResponse);
      expect(handled, isFalse);
    });

    test('cancelAll cancels all transactions', () {
      final t1 = StunTransaction(
        request: request,
        sendCallback: (data) async {},
      );

      final request2 = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.request,
      );
      final t2 = StunTransaction(
        request: request2,
        sendCallback: (data) async {},
      );

      manager.register(t1);
      manager.register(t2);
      expect(manager.pendingCount, equals(2));

      manager.cancelAll();

      expect(manager.pendingCount, equals(0));
      expect(t1.ended, isTrue);
      expect(t2.ended, isTrue);
    });
  });

  group('TransactionTimeout', () {
    test('has default message', () {
      final timeout = TransactionTimeout();
      expect(timeout.message, contains('timed out'));
      expect(timeout.toString(), contains('TransactionTimeout'));
    });

    test('accepts custom message', () {
      final timeout = TransactionTimeout('Custom message');
      expect(timeout.message, equals('Custom message'));
    });
  });

  group('TransactionFailed', () {
    test('extracts error code from response', () {
      final response = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.errorResponse,
      );
      response.setAttribute(StunAttributeType.errorCode, (487, 'Role Conflict'));

      final failed = TransactionFailed(response);
      expect(failed.toString(), contains('487'));
      expect(failed.toString(), contains('Role Conflict'));
    });

    test('handles response without error code', () {
      final response = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.errorResponse,
      );

      final failed = TransactionFailed(response);
      expect(failed.toString(), contains('Error response'));
    });
  });
}
