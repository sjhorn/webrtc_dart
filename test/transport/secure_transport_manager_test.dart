import 'dart:async';

import 'package:test/test.dart';
import 'package:webrtc_dart/src/ice/ice_connection.dart';
import 'package:webrtc_dart/src/peer_connection.dart';
import 'package:webrtc_dart/src/transport/ice_gatherer.dart';
import 'package:webrtc_dart/src/transport/secure_transport_manager.dart';
import 'package:webrtc_dart/src/transport/transport.dart';

void main() {
  group('SecureTransportManager state properties', () {
    late SecureTransportManager manager;

    setUp(() {
      manager = SecureTransportManager();
    });

    tearDown(() async {
      await manager.close();
    });

    test('initial connectionState is new', () {
      expect(manager.connectionState, PeerConnectionState.new_);
    });

    test('initial iceConnectionState is new', () {
      expect(manager.iceConnectionState, IceConnectionState.new_);
    });

    test('initial iceGatheringState is new', () {
      expect(manager.iceGatheringState, IceGatheringState.new_);
    });
  });

  group('SecureTransportManager setConnectionState', () {
    late SecureTransportManager manager;

    setUp(() {
      manager = SecureTransportManager();
    });

    tearDown(() async {
      await manager.close();
    });

    test('sets connection state', () {
      manager.setConnectionState(PeerConnectionState.connecting);
      expect(manager.connectionState, PeerConnectionState.connecting);
    });

    test('emits state change event', () async {
      final states = <PeerConnectionState>[];
      manager.onConnectionStateChange.listen(states.add);

      manager.setConnectionState(PeerConnectionState.connecting);

      await Future.delayed(Duration(milliseconds: 10));
      expect(states, contains(PeerConnectionState.connecting));
    });

    test('does not emit for same state', () async {
      final states = <PeerConnectionState>[];
      manager.onConnectionStateChange.listen(states.add);

      manager.setConnectionState(PeerConnectionState.new_);
      manager.setConnectionState(PeerConnectionState.new_);

      await Future.delayed(Duration(milliseconds: 10));
      expect(states, isEmpty); // Already new_, no change
    });
  });

  group('SecureTransportManager setIceConnectionState', () {
    late SecureTransportManager manager;

    setUp(() {
      manager = SecureTransportManager();
    });

    tearDown(() async {
      await manager.close();
    });

    test('sets ICE connection state', () {
      manager.setIceConnectionState(IceConnectionState.checking);
      expect(manager.iceConnectionState, IceConnectionState.checking);
    });

    test('emits state change event', () async {
      final states = <IceConnectionState>[];
      manager.onIceConnectionStateChange.listen(states.add);

      manager.setIceConnectionState(IceConnectionState.connected);

      await Future.delayed(Duration(milliseconds: 10));
      expect(states, contains(IceConnectionState.connected));
    });
  });

  group('SecureTransportManager setIceGatheringState', () {
    late SecureTransportManager manager;

    setUp(() {
      manager = SecureTransportManager();
    });

    tearDown(() async {
      await manager.close();
    });

    test('sets ICE gathering state', () {
      manager.setIceGatheringState(IceGatheringState.gathering);
      expect(manager.iceGatheringState, IceGatheringState.gathering);
    });

    test('emits state change event', () async {
      final states = <IceGatheringState>[];
      manager.onIceGatheringStateChange.listen(states.add);

      manager.setIceGatheringState(IceGatheringState.complete);

      await Future.delayed(Duration(milliseconds: 10));
      expect(states, contains(IceGatheringState.complete));
    });
  });

  group('SecureTransportManager updateIceGatheringState', () {
    late SecureTransportManager manager;

    setUp(() {
      manager = SecureTransportManager();
    });

    tearDown(() async {
      await manager.close();
    });

    test('empty list does not change state', () {
      manager.updateIceGatheringState([]);
      expect(manager.iceGatheringState, IceGatheringState.new_);
    });

    test('all complete -> complete', () {
      manager.updateIceGatheringState([
        IceGathererState.complete,
        IceGathererState.complete,
      ]);
      expect(manager.iceGatheringState, IceGatheringState.complete);
    });

    test('any gathering -> gathering', () {
      manager.updateIceGatheringState([
        IceGathererState.complete,
        IceGathererState.gathering,
      ]);
      expect(manager.iceGatheringState, IceGatheringState.gathering);
    });

    test('all new -> new', () {
      manager.updateIceGatheringState([
        IceGathererState.new_,
        IceGathererState.new_,
      ]);
      expect(manager.iceGatheringState, IceGatheringState.new_);
    });
  });

  group('SecureTransportManager updateIceConnectionState', () {
    late SecureTransportManager manager;

    setUp(() {
      manager = SecureTransportManager();
    });

    tearDown(() async {
      await manager.close();
    });

    test('empty list does not change state', () {
      manager.updateIceConnectionState([]);
      expect(manager.iceConnectionState, IceConnectionState.new_);
    });

    test('any failed -> failed', () {
      manager.updateIceConnectionState([
        IceState.connected,
        IceState.failed,
      ]);
      expect(manager.iceConnectionState, IceConnectionState.failed);
    });

    test('any disconnected -> disconnected', () {
      manager.updateIceConnectionState([
        IceState.connected,
        IceState.disconnected,
      ]);
      expect(manager.iceConnectionState, IceConnectionState.disconnected);
    });

    test('all connected/completed/closed -> connected', () {
      manager.updateIceConnectionState([
        IceState.connected,
        IceState.completed,
      ]);
      expect(manager.iceConnectionState, IceConnectionState.connected);
    });

    test('all completed/closed -> completed', () {
      manager.updateIceConnectionState([
        IceState.completed,
        IceState.closed,
      ]);
      expect(manager.iceConnectionState, IceConnectionState.completed);
    });

    test('any checking -> checking', () {
      manager.updateIceConnectionState([
        IceState.newState,
        IceState.checking,
      ]);
      expect(manager.iceConnectionState, IceConnectionState.checking);
    });

    test('all new/closed -> new', () {
      manager.updateIceConnectionState([
        IceState.newState,
        IceState.closed,
      ]);
      expect(manager.iceConnectionState, IceConnectionState.new_);
    });

    test('respects closed connection state', () {
      // First close the connection
      manager.setConnectionState(PeerConnectionState.closed);

      // Then update ICE state
      manager.updateIceConnectionState([IceState.connected]);

      // Should be closed
      expect(manager.iceConnectionState, IceConnectionState.closed);
    });
  });

  group('SecureTransportManager updateConnectionState', () {
    late SecureTransportManager manager;

    setUp(() {
      manager = SecureTransportManager();
    });

    tearDown(() async {
      await manager.close();
    });

    test('empty list does not change state', () {
      manager.updateConnectionState([]);
      expect(manager.connectionState, PeerConnectionState.new_);
    });

    test('any failed -> failed', () {
      manager.updateConnectionState([
        TransportState.connected,
        TransportState.failed,
      ]);
      expect(manager.connectionState, PeerConnectionState.failed);
    });

    test('any disconnected -> disconnected', () {
      manager.updateConnectionState([
        TransportState.connected,
        TransportState.disconnected,
      ]);
      expect(manager.connectionState, PeerConnectionState.disconnected);
    });

    test('any connected -> connected', () {
      manager.updateConnectionState([
        TransportState.connecting,
        TransportState.connected,
      ]);
      expect(manager.connectionState, PeerConnectionState.connected);
    });

    test('any connecting -> connecting', () {
      manager.updateConnectionState([
        TransportState.new_,
        TransportState.connecting,
      ]);
      expect(manager.connectionState, PeerConnectionState.connecting);
    });

    test('all closed -> closed', () {
      manager.updateConnectionState([
        TransportState.closed,
        TransportState.closed,
      ]);
      expect(manager.connectionState, PeerConnectionState.closed);
    });

    test('all new -> new', () {
      manager.updateConnectionState([
        TransportState.new_,
        TransportState.new_,
      ]);
      expect(manager.connectionState, PeerConnectionState.new_);
    });
  });

  group('SecureTransportManager close', () {
    test('sets connection state to closed', () async {
      final manager = SecureTransportManager();

      await manager.close();

      expect(manager.connectionState, PeerConnectionState.closed);
    });

    test('clears SRTP sessions', () async {
      final manager = SecureTransportManager();

      await manager.close();

      expect(manager.srtpSession, isNull);
    });

    test('can be called multiple times', () async {
      final manager = SecureTransportManager();

      await manager.close();
      await manager.close(); // Should not throw

      expect(manager.connectionState, PeerConnectionState.closed);
    });
  });

  group('SecureTransportManager SRTP session management', () {
    late SecureTransportManager manager;

    setUp(() {
      manager = SecureTransportManager();
    });

    tearDown(() async {
      await manager.close();
    });

    test('srtpSession is initially null', () {
      expect(manager.srtpSession, isNull);
    });

    test('getSrtpSessionForMid returns null when no sessions', () {
      expect(manager.getSrtpSessionForMid('0'), isNull);
    });

    test('hasSrtpSessionForMid returns false when no per-mid session', () {
      expect(manager.hasSrtpSessionForMid('0'), false);
    });
  });
}
