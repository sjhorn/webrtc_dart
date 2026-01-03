/// ICE Performance Regression Tests
///
/// Tests ICE candidate parsing - called for every trickle candidate.
///
/// Run: dart test test/performance/ice_perf_test.dart
@Tags(['performance'])
library;

import 'package:test/test.dart';
import 'package:webrtc_dart/src/ice/rtc_ice_candidate.dart';

import 'perf_test_utils.dart';

void main() {
  group('ICE Candidate Performance', () {
    test('parse host candidate meets threshold', () {
      const iterations = 200000;

      const sdp =
          '6815297761 1 udp 2130706431 192.168.1.100 31102 typ host generation 0 ufrag b7l3';

      final result = runBenchmarkSync(
        name: 'ICE parse host candidate',
        iterations: iterations,
        warmupIterations: 1000,
        operation: () {
          RTCIceCandidate.fromSdp(sdp);
        },
      );

      // Threshold: >500,000 ops/sec
      result.checkThreshold(PerfThreshold(
        name: 'ICE parse host candidate',
        minOpsPerSecond: 500000,
      ));
    });

    test('parse srflx candidate meets threshold', () {
      const iterations = 200000;

      const sdp =
          '842163049 1 udp 1694498815 203.0.113.50 54321 typ srflx raddr 192.168.1.100 rport 31102 generation 0 ufrag b7l3';

      final result = runBenchmarkSync(
        name: 'ICE parse srflx candidate',
        iterations: iterations,
        warmupIterations: 1000,
        operation: () {
          RTCIceCandidate.fromSdp(sdp);
        },
      );

      // Threshold: >400,000 ops/sec (slightly slower due to raddr/rport)
      result.checkThreshold(PerfThreshold(
        name: 'ICE parse srflx candidate',
        minOpsPerSecond: 400000,
      ));
    });

    test('parse relay candidate meets threshold', () {
      const iterations = 200000;

      const sdp =
          '3745641921 1 udp 41885439 203.0.113.100 54322 typ relay raddr 203.0.113.50 rport 54321 generation 0 ufrag b7l3';

      final result = runBenchmarkSync(
        name: 'ICE parse relay candidate',
        iterations: iterations,
        warmupIterations: 1000,
        operation: () {
          RTCIceCandidate.fromSdp(sdp);
        },
      );

      // Threshold: >400,000 ops/sec
      result.checkThreshold(PerfThreshold(
        name: 'ICE parse relay candidate',
        minOpsPerSecond: 400000,
      ));
    });

    test('parse TCP candidate meets threshold', () {
      const iterations = 200000;

      const sdp =
          '1234567890 1 tcp 2105458943 192.168.1.100 9 typ host tcptype passive generation 0';

      final result = runBenchmarkSync(
        name: 'ICE parse TCP candidate',
        iterations: iterations,
        warmupIterations: 1000,
        operation: () {
          RTCIceCandidate.fromSdp(sdp);
        },
      );

      // Threshold: >400,000 ops/sec
      result.checkThreshold(PerfThreshold(
        name: 'ICE parse TCP candidate',
        minOpsPerSecond: 400000,
      ));
    });

    test('serialize candidate meets threshold', () {
      const iterations = 200000;

      final candidate = RTCIceCandidate(
        foundation: '6815297761',
        component: 1,
        transport: 'udp',
        priority: 2130706431,
        host: '192.168.1.100',
        port: 31102,
        type: 'host',
        generation: 0,
        ufrag: 'b7l3',
      );

      final result = runBenchmarkSync(
        name: 'ICE serialize candidate',
        iterations: iterations,
        warmupIterations: 1000,
        operation: () {
          candidate.toSdp();
        },
      );

      // Threshold: >500,000 ops/sec
      result.checkThreshold(PerfThreshold(
        name: 'ICE serialize candidate',
        minOpsPerSecond: 500000,
      ));
    });

    test('round-trip (parse + serialize) meets threshold', () {
      const iterations = 100000;

      const sdp =
          '6815297761 1 udp 2130706431 192.168.1.100 31102 typ host generation 0 ufrag b7l3';

      final result = runBenchmarkSync(
        name: 'ICE round-trip',
        iterations: iterations,
        warmupIterations: 500,
        operation: () {
          final candidate = RTCIceCandidate.fromSdp(sdp);
          candidate.toSdp();
        },
      );

      // Threshold: >200,000 round-trips/sec
      result.checkThreshold(PerfThreshold(
        name: 'ICE round-trip',
        minOpsPerSecond: 200000,
      ));
    });
  });
}
