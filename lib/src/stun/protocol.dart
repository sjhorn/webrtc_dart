import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'const.dart';
import 'message.dart';

/// STUN Protocol Client
class StunProtocol {
  final RawDatagramSocket socket;
  final InternetAddress serverAddress;
  final int serverPort;

  final _responseController = StreamController<StunMessage>.broadcast();
  final _pendingRequests = <String, Completer<StunMessage>>{};

  StunProtocol({
    required this.socket,
    required this.serverAddress,
    required this.serverPort,
  }) {
    _startListening();
  }

  /// Stream of received STUN messages
  Stream<StunMessage> get onMessage => _responseController.stream;

  /// Start a new STUN protocol instance
  static Future<StunProtocol> create({
    required String serverAddress,
    required int serverPort,
    InternetAddress? bindAddress,
    int bindPort = 0,
  }) async {
    final socket = await RawDatagramSocket.bind(
      bindAddress ?? InternetAddress.anyIPv4,
      bindPort,
    );

    return StunProtocol(
      socket: socket,
      serverAddress: InternetAddress(serverAddress),
      serverPort: serverPort,
    );
  }

  void _startListening() {
    socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket.receive();
        if (datagram != null) {
          _handleIncomingData(datagram.data);
        }
      }
    });
  }

  void _handleIncomingData(Uint8List data) {
    final message = parseStunMessage(data);
    if (message == null) {
      return; // Invalid message
    }

    // Notify stream listeners
    _responseController.add(message);

    // Complete pending request if this is a response
    final tid = message.transactionIdHex;
    final completer = _pendingRequests.remove(tid);
    if (completer != null && !completer.isCompleted) {
      completer.complete(message);
    }
  }

  /// Send a STUN binding request and wait for response
  Future<StunMessage> sendBindingRequest({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final request = StunMessage(
      method: StunMethod.binding,
      messageClass: StunClass.request,
    );

    return sendRequest(request, timeout: timeout);
  }

  /// Send a STUN request and wait for response
  Future<StunMessage> sendRequest(
    StunMessage request, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final tid = request.transactionIdHex;
    final completer = Completer<StunMessage>();
    _pendingRequests[tid] = completer;

    // Send the request
    final bytes = request.toBytes();
    socket.send(bytes, serverAddress, serverPort);

    // Wait for response with timeout
    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          _pendingRequests.remove(tid);
          throw TimeoutException('STUN request timed out', timeout);
        },
      );
    } catch (e) {
      _pendingRequests.remove(tid);
      rethrow;
    }
  }

  /// Send a STUN message without waiting for response
  void sendMessage(StunMessage message) {
    final bytes = message.toBytes();
    socket.send(bytes, serverAddress, serverPort);
  }

  /// Close the protocol and cleanup
  Future<void> close() async {
    socket.close();
    await _responseController.close();
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('STUN protocol closed'));
      }
    }
    _pendingRequests.clear();
  }

  /// Get the local address and port
  InternetAddress get localAddress => socket.address;
  int get localPort => socket.port;
}

/// Simple STUN client for connectivity checks
class StunClient {
  final String serverHost;
  final int serverPort;

  StunClient({
    required this.serverHost,
    this.serverPort = 3478, // Default STUN port
  });

  /// Perform a STUN binding request
  Future<StunBindingResult> performBindingRequest({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final protocol = await StunProtocol.create(
      serverAddress: serverHost,
      serverPort: serverPort,
    );

    try {
      final response = await protocol.sendBindingRequest(timeout: timeout);

      if (response.messageClass == StunClass.successResponse) {
        // Extract XOR-MAPPED-ADDRESS or MAPPED-ADDRESS
        final xorMapped =
            response.getAttribute(StunAttributeType.xorMappedAddress);
        final mapped = response.getAttribute(StunAttributeType.mappedAddress);

        final address = xorMapped ?? mapped;
        if (address != null) {
          final (host, port) = address as (String, int);
          return StunBindingResult(
            success: true,
            mappedAddress: host,
            mappedPort: port,
            localAddress: protocol.localAddress.address,
            localPort: protocol.localPort,
          );
        }
      }

      // Error response
      if (response.messageClass == StunClass.errorResponse) {
        final errorCode = response.getAttribute(StunAttributeType.errorCode);
        if (errorCode != null) {
          final (code, reason) = errorCode as (int, String);
          return StunBindingResult(
            success: false,
            errorCode: code,
            errorReason: reason,
          );
        }
      }

      return StunBindingResult(
        success: false,
        errorReason: 'Unknown response type',
      );
    } finally {
      await protocol.close();
    }
  }
}

/// Result of a STUN binding request
class StunBindingResult {
  final bool success;
  final String? mappedAddress;
  final int? mappedPort;
  final String? localAddress;
  final int? localPort;
  final int? errorCode;
  final String? errorReason;

  StunBindingResult({
    required this.success,
    this.mappedAddress,
    this.mappedPort,
    this.localAddress,
    this.localPort,
    this.errorCode,
    this.errorReason,
  });

  @override
  String toString() {
    if (success) {
      return 'StunBindingResult(success: true, '
          'mapped: $mappedAddress:$mappedPort, '
          'local: $localAddress:$localPort)';
    } else {
      return 'StunBindingResult(success: false, '
          'error: $errorCode - $errorReason)';
    }
  }
}
