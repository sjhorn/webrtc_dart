import 'package:test/test.dart';
import 'package:webrtc_dart/src/srtp/replay_protection.dart';

void main() {
  group('ReplayProtection', () {
    test('accepts first packet', () {
      final rp = ReplayProtection(windowSize: 64);

      expect(rp.check(100), true);
      expect(rp.highestSequence, 100);
    });

    test('accepts increasing sequence numbers', () {
      final rp = ReplayProtection(windowSize: 64);

      expect(rp.check(100), true);
      expect(rp.check(101), true);
      expect(rp.check(102), true);
      expect(rp.check(103), true);

      expect(rp.highestSequence, 103);
    });

    test('rejects duplicate sequence numbers', () {
      final rp = ReplayProtection(windowSize: 64);

      expect(rp.check(100), true);
      expect(rp.check(101), true);
      expect(rp.check(101), false); // Duplicate
      expect(rp.check(100), false); // Duplicate
    });

    test('accepts out-of-order packets within window', () {
      final rp = ReplayProtection(windowSize: 64);

      expect(rp.check(100), true);
      expect(rp.check(105), true);
      expect(rp.check(102), true); // Out of order but within window
      expect(rp.check(103), true);
      expect(rp.check(101), true);
    });

    test('rejects packets outside window', () {
      final rp = ReplayProtection(windowSize: 64);

      expect(rp.check(100), true);
      expect(rp.check(200), true); // Jump forward
      expect(rp.check(100), false); // Too old, outside window
    });

    test('handles sequence number wraparound', () {
      final rp = ReplayProtection(windowSize: 64);

      // Start near max sequence number
      expect(rp.check(65530), true);
      expect(rp.check(65531), true);
      expect(rp.check(65535), true);

      // Wraparound to 0
      expect(rp.check(0), true);
      expect(rp.check(1), true);
      expect(rp.check(2), true);

      expect(rp.highestSequence, 2);
    });

    test('rejects old packets after wraparound', () {
      final rp = ReplayProtection(windowSize: 64);

      expect(rp.check(65530), true);
      expect(rp.check(0), true); // Wraparound
      expect(rp.check(10), true);

      // Try to replay old packet from before wraparound
      expect(rp.check(65530), false); // Should be rejected
    });

    test('sliding window moves forward', () {
      final rp = ReplayProtection(windowSize: 64);

      expect(rp.check(1000), true);
      expect(rp.check(1010), true);

      // These are within window
      expect(rp.check(1005), true);
      expect(rp.check(1008), true);

      // Jump far ahead
      expect(rp.check(2000), true);

      // Now 1010 is too old
      expect(rp.check(1010), false);
    });

    test('reset clears state', () {
      final rp = ReplayProtection(windowSize: 64);

      expect(rp.check(100), true);
      expect(rp.check(101), true);

      rp.reset();

      expect(rp.isInitialized, false);
      expect(rp.check(100), true); // Accepts again after reset
      expect(rp.isInitialized, true);
    });

    test('handles small gaps correctly', () {
      final rp = ReplayProtection(windowSize: 64);

      expect(rp.check(100), true);
      expect(rp.check(102), true); // Skip 101
      expect(rp.check(101), true); // Fill the gap
      expect(rp.check(101), false); // Duplicate
    });

    test('handles large jumps correctly', () {
      final rp = ReplayProtection(windowSize: 64);

      expect(rp.check(100), true);
      expect(rp.check(200), true); // Large jump

      // 150 is within window (200 - 150 = 50 < 64), so it's accepted
      expect(rp.check(150), true);

      // But 100 is now too old (200 - 100 = 100 > 64)
      expect(rp.check(100), false);
    });
  });
}
