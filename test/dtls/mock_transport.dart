import 'dart:async';
import 'dart:typed_data';
import 'package:webrtc_dart/src/dtls/context/transport.dart';

/// Mock transport for testing DTLS
/// Connects two endpoints in memory without actual network I/O
class MockTransport implements DtlsTransport {
  final StreamController<Uint8List> _dataController =
      StreamController<Uint8List>.broadcast();

  /// The remote transport to send data to
  MockTransport? remotePeer;

  /// Whether the transport is closed
  bool _closed = false;

  @override
  bool get isOpen => !_closed;

  /// Optional packet loss rate (0.0 - 1.0)
  final double packetLossRate;

  /// Optional delay for packets (simulates network latency)
  final Duration? delay;

  MockTransport({
    this.packetLossRate = 0.0,
    this.delay,
  });

  @override
  Stream<Uint8List> get onData => _dataController.stream;

  @override
  Future<void> send(Uint8List data) async {
    if (_closed) {
      throw StateError('Transport is closed');
    }

    if (remotePeer == null) {
      throw StateError('No remote peer connected');
    }

    // Simulate packet loss
    if (packetLossRate > 0 &&
        (DateTime.now().microsecondsSinceEpoch % 100) <
            (packetLossRate * 100)) {
      return; // Drop packet
    }

    // Simulate network delay
    if (delay != null) {
      await Future.delayed(delay!);
    }

    // Deliver to remote peer
    if (!remotePeer!._closed) {
      remotePeer!._dataController.add(data);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _dataController.close();
  }

  /// Connect two mock transports together
  static void connectPair(MockTransport transport1, MockTransport transport2) {
    transport1.remotePeer = transport2;
    transport2.remotePeer = transport1;
  }
}
