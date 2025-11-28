import 'dart:async';
import 'dart:typed_data';

/// Transport abstraction for DTLS
/// Provides send/receive interface over UDP
abstract class DtlsTransport {
  /// Send data to remote endpoint
  Future<void> send(Uint8List data);

  /// Receive data stream from remote endpoint
  Stream<Uint8List> get onData;

  /// Close the transport
  Future<void> close();

  /// Check if transport is open
  bool get isOpen;
}

/// Simple transport implementation using StreamController
/// Can be used for testing or adapting to different transport layers
class StreamDtlsTransport implements DtlsTransport {
  final StreamController<Uint8List> _receiveController;
  final void Function(Uint8List data) _sendCallback;
  bool _isOpen;

  StreamDtlsTransport({
    required void Function(Uint8List data) sendCallback,
    StreamController<Uint8List>? receiveController,
  })  : _sendCallback = sendCallback,
        _receiveController = receiveController ?? StreamController<Uint8List>.broadcast(),
        _isOpen = true;

  @override
  Future<void> send(Uint8List data) async {
    if (!_isOpen) {
      throw StateError('Transport is closed');
    }
    _sendCallback(data);
  }

  @override
  Stream<Uint8List> get onData => _receiveController.stream;

  /// Inject received data into the transport
  void receive(Uint8List data) {
    if (_isOpen) {
      _receiveController.add(data);
    }
  }

  @override
  Future<void> close() async {
    if (_isOpen) {
      _isOpen = false;
      await _receiveController.close();
    }
  }

  @override
  bool get isOpen => _isOpen;
}

/// UDP-based transport implementation
/// Wraps a UDP socket for DTLS communication
class UdpDtlsTransport implements DtlsTransport {
  final StreamController<Uint8List> _receiveController;
  final Future<void> Function(Uint8List data, String address, int port) _sendCallback;
  final String _remoteAddress;
  final int _remotePort;
  bool _isOpen;

  UdpDtlsTransport({
    required Future<void> Function(Uint8List data, String address, int port) sendCallback,
    required String remoteAddress,
    required int remotePort,
    StreamController<Uint8List>? receiveController,
  })  : _sendCallback = sendCallback,
        _remoteAddress = remoteAddress,
        _remotePort = remotePort,
        _receiveController = receiveController ?? StreamController<Uint8List>.broadcast(),
        _isOpen = true;

  @override
  Future<void> send(Uint8List data) async {
    if (!_isOpen) {
      throw StateError('Transport is closed');
    }
    await _sendCallback(data, _remoteAddress, _remotePort);
  }

  @override
  Stream<Uint8List> get onData => _receiveController.stream;

  /// Inject received data into the transport
  void receive(Uint8List data) {
    if (_isOpen) {
      _receiveController.add(data);
    }
  }

  @override
  Future<void> close() async {
    if (_isOpen) {
      _isOpen = false;
      await _receiveController.close();
    }
  }

  @override
  bool get isOpen => _isOpen;

  String get remoteAddress => _remoteAddress;
  int get remotePort => _remotePort;
}
