/// STUN Message Performance Regression Tests
///
/// Tests STUN message parse/serialize throughput.
/// STUN is used heavily during ICE connectivity checks.
///
/// Run: dart test test/performance/stun_perf_test.dart
@Tags(['performance'])
library;

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/stun/message.dart';
import 'package:webrtc_dart/src/stun/const.dart';

import 'perf_test_utils.dart';

void main() {
  group('STUN Message Performance', () {
    test('parse binding request meets threshold', () {
      const iterations = 50000;

      // Create a typical binding request with USERNAME, PRIORITY, etc.
      final message = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.request,
        transactionId: Uint8List.fromList(List.generate(12, (i) => i)),
      );
      message.setAttribute(
        StunAttributeType.username,
        'abcd1234:efgh5678',
      );
      message.setAttribute(
        StunAttributeType.priority,
        2130706431,
      );
      message.setAttribute(
        StunAttributeType.iceControlled,
        BigInt.from(123456789),
      );
      final serialized = message.toBytes();

      final result = runBenchmarkSync(
        name: 'STUN parse binding request',
        iterations: iterations,
        warmupIterations: 500,
        operation: () {
          parseStunMessage(serialized);
        },
        metadata: {'messageSize': serialized.length},
      );

      // Threshold: >200,000 parses/sec
      result.checkThreshold(PerfThreshold(
        name: 'STUN parse binding request',
        minOpsPerSecond: 200000,
      ));
    });

    test('serialize binding request meets threshold', () {
      const iterations = 50000;

      final message = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.request,
        transactionId: Uint8List.fromList(List.generate(12, (i) => i)),
      );
      message.setAttribute(
        StunAttributeType.username,
        'abcd1234:efgh5678',
      );
      message.setAttribute(
        StunAttributeType.priority,
        2130706431,
      );

      final result = runBenchmarkSync(
        name: 'STUN serialize binding request',
        iterations: iterations,
        warmupIterations: 500,
        operation: () {
          message.toBytes();
        },
      );

      // Threshold: >200,000 serializes/sec
      result.checkThreshold(PerfThreshold(
        name: 'STUN serialize binding request',
        minOpsPerSecond: 200000,
      ));
    });

    test('parse binding response with XOR-MAPPED-ADDRESS meets threshold', () {
      const iterations = 50000;

      final message = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.successResponse,
        transactionId: Uint8List.fromList(List.generate(12, (i) => i)),
      );
      message.setAttribute(
        StunAttributeType.xorMappedAddress,
        ('192.168.1.100', 54321),
      );
      message.setAttribute(
        StunAttributeType.mappedAddress,
        ('192.168.1.100', 54321),
      );
      final serialized = message.toBytes();

      final result = runBenchmarkSync(
        name: 'STUN parse binding response',
        iterations: iterations,
        warmupIterations: 500,
        operation: () {
          parseStunMessage(serialized);
        },
        metadata: {'messageSize': serialized.length},
      );

      // Threshold: >200,000 parses/sec
      result.checkThreshold(PerfThreshold(
        name: 'STUN parse binding response',
        minOpsPerSecond: 200000,
      ));
    });

    test('round-trip (serialize + parse) meets threshold', () {
      const iterations = 30000;

      final message = StunMessage(
        method: StunMethod.binding,
        messageClass: StunClass.request,
        transactionId: Uint8List.fromList(List.generate(12, (i) => i)),
      );
      message.setAttribute(
        StunAttributeType.username,
        'abcd1234:efgh5678',
      );
      message.setAttribute(
        StunAttributeType.priority,
        2130706431,
      );

      final result = runBenchmarkSync(
        name: 'STUN round-trip',
        iterations: iterations,
        warmupIterations: 300,
        operation: () {
          final serialized = message.toBytes();
          parseStunMessage(serialized);
        },
      );

      // Threshold: >100,000 round-trips/sec
      result.checkThreshold(PerfThreshold(
        name: 'STUN round-trip',
        minOpsPerSecond: 100000,
      ));
    });
  });
}
