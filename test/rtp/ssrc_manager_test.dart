import 'dart:math';
import 'package:test/test.dart';
import 'package:webrtc_dart/src/rtp/ssrc_manager.dart';

void main() {
  group('SsrcManager', () {
    test('generates non-zero random SSRC', () {
      final manager = SsrcManager();
      expect(manager.localSsrc, isNot(0));
      expect(manager.localSsrc, greaterThan(0));
      expect(manager.localSsrc, lessThanOrEqualTo(0xFFFFFFFF));
    });

    test('accepts initial SSRC value', () {
      final manager = SsrcManager(initialSsrc: 0x12345678);
      expect(manager.localSsrc, 0x12345678);
    });

    test('tracks remote SSRCs', () {
      final manager = SsrcManager();

      manager.addRemoteSsrc(0x11111111);
      manager.addRemoteSsrc(0x22222222);

      expect(manager.isRemoteSsrc(0x11111111), true);
      expect(manager.isRemoteSsrc(0x22222222), true);
      expect(manager.isRemoteSsrc(0x33333333), false);
      expect(manager.remoteSSRCCount, 2);
    });

    test('removes remote SSRCs', () {
      final manager = SsrcManager();

      manager.addRemoteSsrc(0x11111111);
      manager.addRemoteSsrc(0x22222222);

      expect(manager.remoteSSRCCount, 2);

      manager.removeRemoteSsrc(0x11111111);

      expect(manager.isRemoteSsrc(0x11111111), false);
      expect(manager.isRemoteSsrc(0x22222222), true);
      expect(manager.remoteSSRCCount, 1);
    });

    test('detects SSRC collision', () {
      final manager = SsrcManager(initialSsrc: 0x12345678);
      final originalSsrc = manager.localSsrc;

      // No collision with different SSRC
      final collision1 = manager.checkCollision(
        receivedSsrc: 0xAABBCCDD,
        sourceAddress: '192.168.1.100',
        sourcePort: 5000,
      );
      expect(collision1, false);
      expect(manager.localSsrc, originalSsrc);

      // Collision detected with same SSRC
      final collision2 = manager.checkCollision(
        receivedSsrc: 0x12345678,
        sourceAddress: '192.168.1.100',
        sourcePort: 5000,
      );
      expect(collision2, true);

      // SSRC should have changed
      expect(manager.localSsrc, isNot(originalSsrc));
      expect(manager.collisionCount, 1);
    });

    test('generates new SSRC on collision', () {
      final manager = SsrcManager(initialSsrc: 0x12345678);

      // Add some remote SSRCs
      manager.addRemoteSsrc(0x11111111);
      manager.addRemoteSsrc(0x22222222);

      final originalSsrc = manager.localSsrc;

      // Trigger collision
      manager.checkCollision(
        receivedSsrc: 0x12345678,
        sourceAddress: '192.168.1.100',
        sourcePort: 5000,
      );

      // New SSRC should not conflict with remote SSRCs
      expect(manager.localSsrc, isNot(originalSsrc));
      expect(manager.localSsrc, isNot(0x11111111));
      expect(manager.localSsrc, isNot(0x22222222));
    });

    test('handles multiple collisions', () {
      final manager = SsrcManager(initialSsrc: 0x12345678);

      // Trigger multiple collisions
      for (var i = 0; i < 5; i++) {
        manager.checkCollision(
          receivedSsrc: manager.localSsrc,
          sourceAddress: '192.168.1.$i',
          sourcePort: 5000 + i,
        );
      }

      expect(manager.collisionCount, 5);
      expect(manager.localSsrc, isNot(0x12345678));
    });

    test('detects loop (receiving own packets)', () {
      final manager = SsrcManager(initialSsrc: 0x12345678);

      // Not a loop - different address
      final loop1 = manager.checkLoop(
        receivedSsrc: 0x12345678,
        localAddress: '192.168.1.1',
        localPort: 5000,
        sourceAddress: '192.168.1.2',
        sourcePort: 5000,
      );
      expect(loop1, false);

      // Loop detected - same address and SSRC
      final loop2 = manager.checkLoop(
        receivedSsrc: 0x12345678,
        localAddress: '192.168.1.1',
        localPort: 5000,
        sourceAddress: '192.168.1.1',
        sourcePort: 5000,
      );
      expect(loop2, true);
    });

    test('resets collision statistics', () {
      final manager = SsrcManager(initialSsrc: 0x12345678);

      // Trigger collision
      manager.checkCollision(
        receivedSsrc: 0x12345678,
        sourceAddress: '192.168.1.100',
        sourcePort: 5000,
      );

      expect(manager.collisionCount, 1);
      expect(manager.timeSinceLastCollision(), isNotNull);

      // Reset
      manager.resetCollisionStats();

      expect(manager.collisionCount, 0);
      expect(manager.timeSinceLastCollision(), isNull);
    });

    test('clears remote SSRCs', () {
      final manager = SsrcManager();

      manager.addRemoteSsrc(0x11111111);
      manager.addRemoteSsrc(0x22222222);
      manager.addRemoteSsrc(0x33333333);

      expect(manager.remoteSSRCCount, 3);

      manager.clearRemoteSSRCs();

      expect(manager.remoteSSRCCount, 0);
      expect(manager.isRemoteSsrc(0x11111111), false);
    });

    test('generates unique SSRCs with deterministic random', () {
      final manager1 = SsrcManager(random: Random(12345));
      final manager2 = SsrcManager(random: Random(12345));

      // Same seed should produce same SSRC
      expect(manager1.localSsrc, manager2.localSsrc);

      // Different seeds should produce different SSRCs
      final manager3 = SsrcManager(random: Random(54321));
      expect(manager3.localSsrc, isNot(manager1.localSsrc));
    });

    test('tracks time since last collision', () async {
      final manager = SsrcManager(initialSsrc: 0x12345678);

      expect(manager.timeSinceLastCollision(), isNull);

      // Trigger collision
      manager.checkCollision(
        receivedSsrc: 0x12345678,
        sourceAddress: '192.168.1.100',
        sourcePort: 5000,
      );

      // Should have recent collision time
      final timeSince1 = manager.timeSinceLastCollision();
      expect(timeSince1, isNotNull);
      expect(timeSince1!.inMilliseconds, lessThan(100));

      // Wait and check again
      await Future.delayed(Duration(milliseconds: 50));

      final timeSince2 = manager.timeSinceLastCollision();
      expect(timeSince2!.inMilliseconds, greaterThanOrEqualTo(50));
    });

    test('returns unmodifiable set of remote SSRCs', () {
      final manager = SsrcManager();

      manager.addRemoteSsrc(0x11111111);
      manager.addRemoteSsrc(0x22222222);

      final remoteSSRCs = manager.remoteSSRCs;

      expect(remoteSSRCs.length, 2);
      expect(remoteSSRCs.contains(0x11111111), true);
      expect(remoteSSRCs.contains(0x22222222), true);

      // Verify it's unmodifiable
      expect(() => remoteSSRCs.add(0x33333333), throwsUnsupportedError);
    });
  });
}
