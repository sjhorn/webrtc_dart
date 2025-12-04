/// ICE TCP Transport Layer
///
/// Implements TCP transport for ICE candidates per RFC 6544.
/// TCP candidates use STUN over TCP with 2-byte length framing (RFC 5389 Section 7.1).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// TCP connection state
enum TcpConnectionState {
  /// Connection not started
  idle,

  /// Connection in progress
  connecting,

  /// Connection established
  connected,

  /// Connection failed
  failed,

  /// Connection closed
  closed,
}

/// TCP type for ICE candidates (RFC 6544)
enum IceTcpType {
  /// Active: peer initiates connection
  active,

  /// Passive: peer accepts connections
  passive,

  /// Simultaneous open (RFC 6544 Section 5.2)
  so,
}

/// Extension to convert TcpType to string
extension IceTcpTypeExtension on IceTcpType {
  String get value {
    switch (this) {
      case IceTcpType.active:
        return 'active';
      case IceTcpType.passive:
        return 'passive';
      case IceTcpType.so:
        return 'so';
    }
  }

  static IceTcpType? fromString(String? value) {
    if (value == null) return null;
    switch (value.toLowerCase()) {
      case 'active':
        return IceTcpType.active;
      case 'passive':
        return IceTcpType.passive;
      case 'so':
        return IceTcpType.so;
      default:
        return null;
    }
  }
}

/// TCP connection for ICE
///
/// Manages a single TCP connection with STUN framing.
class IceTcpConnection {
  /// Remote address
  final InternetAddress remoteAddress;

  /// Remote port
  final int remotePort;

  /// Local TCP type (determines connection direction)
  final IceTcpType localTcpType;

  /// Connection state
  TcpConnectionState _state = TcpConnectionState.idle;

  /// Underlying socket
  Socket? _socket;

  /// Server socket (for passive mode)
  ServerSocket? _serverSocket;

  /// Local port (assigned when bound/connected)
  int? _localPort;

  /// Receive buffer for incomplete messages
  final List<int> _receiveBuffer = [];

  /// Controller for incoming STUN messages
  final _messageController = StreamController<Uint8List>.broadcast();

  /// Controller for state changes
  final _stateController = StreamController<TcpConnectionState>.broadcast();

  /// Connection timeout
  static const connectionTimeout = Duration(seconds: 10);

  IceTcpConnection({
    required this.remoteAddress,
    required this.remotePort,
    required this.localTcpType,
  });

  /// Current connection state
  TcpConnectionState get state => _state;

  /// Stream of incoming STUN messages
  Stream<Uint8List> get onMessage => _messageController.stream;

  /// Stream of state changes
  Stream<TcpConnectionState> get onStateChange => _stateController.stream;

  /// Local port (available after connect/bind)
  int? get localPort => _localPort;

  /// Whether connection is established
  bool get isConnected => _state == TcpConnectionState.connected;

  /// Connect (for active mode)
  ///
  /// Initiates outgoing TCP connection to remote peer.
  Future<void> connect() async {
    if (localTcpType != IceTcpType.active) {
      throw StateError('connect() only valid for active TCP type');
    }

    if (_state != TcpConnectionState.idle) {
      throw StateError('Already connecting or connected');
    }

    _setState(TcpConnectionState.connecting);

    try {
      _socket = await Socket.connect(
        remoteAddress,
        remotePort,
        timeout: connectionTimeout,
      );

      _localPort = _socket!.port;
      _setupSocketListener(_socket!);
      _setState(TcpConnectionState.connected);
    } catch (e) {
      _setState(TcpConnectionState.failed);
      rethrow;
    }
  }

  /// Bind (for passive mode)
  ///
  /// Creates a listening socket for incoming connections.
  Future<void> bind(InternetAddress localAddress, [int port = 0]) async {
    if (localTcpType != IceTcpType.passive) {
      throw StateError('bind() only valid for passive TCP type');
    }

    if (_state != TcpConnectionState.idle) {
      throw StateError('Already bound');
    }

    try {
      _serverSocket = await ServerSocket.bind(localAddress, port);
      _localPort = _serverSocket!.port;

      // Wait for incoming connection
      _serverSocket!.listen((socket) {
        // Check if connection is from expected peer
        if (socket.remoteAddress.address == remoteAddress.address &&
            socket.remotePort == remotePort) {
          _socket = socket;
          _setupSocketListener(socket);
          _setState(TcpConnectionState.connected);
        } else {
          // Connection from unexpected peer, close it
          socket.close();
        }
      });
    } catch (e) {
      _setState(TcpConnectionState.failed);
      rethrow;
    }
  }

  /// Accept an existing socket (for passive mode with external server)
  void acceptSocket(Socket socket) {
    if (_state == TcpConnectionState.connected) {
      throw StateError('Already connected');
    }

    _socket = socket;
    _localPort = socket.port;
    _setupSocketListener(socket);
    _setState(TcpConnectionState.connected);
  }

  /// Send a STUN message
  ///
  /// Adds 2-byte length prefix per RFC 5389 Section 7.1.
  Future<void> send(Uint8List data) async {
    if (_state != TcpConnectionState.connected || _socket == null) {
      throw StateError('Not connected');
    }

    // Create framed message: 2-byte big-endian length + data
    final framed = Uint8List(2 + data.length);
    final view = ByteData.view(framed.buffer);
    view.setUint16(0, data.length, Endian.big);
    framed.setRange(2, framed.length, data);

    _socket!.add(framed);
    await _socket!.flush();
  }

  /// Close the connection
  Future<void> close() async {
    if (_state == TcpConnectionState.closed) return;

    _setState(TcpConnectionState.closed);

    await _socket?.close();
    _socket = null;

    await _serverSocket?.close();
    _serverSocket = null;

    _receiveBuffer.clear();
    await _messageController.close();
    await _stateController.close();
  }

  void _setState(TcpConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      if (!_stateController.isClosed) {
        _stateController.add(newState);
      }
    }
  }

  void _setupSocketListener(Socket socket) {
    socket.listen(
      (data) {
        _receiveBuffer.addAll(data);
        _processReceiveBuffer();
      },
      onError: (error) {
        _setState(TcpConnectionState.failed);
      },
      onDone: () {
        if (_state == TcpConnectionState.connected) {
          _setState(TcpConnectionState.closed);
        }
      },
    );
  }

  /// Process received data, extracting complete STUN messages
  void _processReceiveBuffer() {
    while (_receiveBuffer.length >= 2) {
      // Read 2-byte length prefix
      final lengthBytes = Uint8List.fromList(_receiveBuffer.sublist(0, 2));
      final length = ByteData.view(lengthBytes.buffer).getUint16(0, Endian.big);

      // Check if we have complete message
      if (_receiveBuffer.length < 2 + length) {
        break; // Wait for more data
      }

      // Extract message
      final message = Uint8List.fromList(_receiveBuffer.sublist(2, 2 + length));
      _receiveBuffer.removeRange(0, 2 + length);

      // Emit message
      if (!_messageController.isClosed) {
        _messageController.add(message);
      }
    }
  }
}

/// TCP server for passive ICE candidates
///
/// Listens for incoming TCP connections from remote peers.
class IceTcpServer {
  /// Local address
  final InternetAddress localAddress;

  /// Local port (0 = any available)
  final int requestedPort;

  /// Server socket
  ServerSocket? _serverSocket;

  /// Actual bound port
  int? _boundPort;

  /// Active connections by remote endpoint
  final Map<String, IceTcpConnection> _connections = {};

  /// Controller for new connections
  final _connectionController =
      StreamController<IceTcpConnection>.broadcast();

  IceTcpServer({
    required this.localAddress,
    this.requestedPort = 0,
  });

  /// Bound port (available after start())
  int? get port => _boundPort;

  /// Stream of new connections
  Stream<IceTcpConnection> get onConnection => _connectionController.stream;

  /// Start listening
  Future<void> start() async {
    if (_serverSocket != null) return;

    _serverSocket = await ServerSocket.bind(localAddress, requestedPort);
    _boundPort = _serverSocket!.port;

    _serverSocket!.listen(_handleConnection);
  }

  /// Stop listening and close all connections
  Future<void> stop() async {
    await _serverSocket?.close();
    _serverSocket = null;

    // Copy connections to avoid concurrent modification
    final connList = _connections.values.toList();
    _connections.clear();

    for (final conn in connList) {
      await conn.close();
    }

    await _connectionController.close();
  }

  /// Get connection for remote endpoint
  IceTcpConnection? getConnection(String remoteAddress, int remotePort) {
    final key = '$remoteAddress:$remotePort';
    return _connections[key];
  }

  void _handleConnection(Socket socket) {
    final remoteKey = '${socket.remoteAddress.address}:${socket.remotePort}';

    // Create connection wrapper
    final connection = IceTcpConnection(
      remoteAddress: socket.remoteAddress,
      remotePort: socket.remotePort,
      localTcpType: IceTcpType.passive,
    );

    connection.acceptSocket(socket);
    _connections[remoteKey] = connection;

    if (!_connectionController.isClosed) {
      _connectionController.add(connection);
    }

    // Clean up when closed
    connection.onStateChange.listen((state) {
      if (state == TcpConnectionState.closed ||
          state == TcpConnectionState.failed) {
        _connections.remove(remoteKey);
      }
    });
  }
}

/// TCP candidate gatherer
///
/// Creates TCP host candidates (passive mode).
class TcpCandidateGatherer {
  /// Gathered TCP servers by address
  final Map<String, IceTcpServer> _servers = {};

  /// Start gathering TCP candidates on given addresses
  Future<List<({String address, int port})>> gatherHostCandidates(
    List<String> addresses,
  ) async {
    final results = <({String address, int port})>[];

    for (final address in addresses) {
      try {
        final addr = InternetAddress(address);
        final server = IceTcpServer(localAddress: addr);
        await server.start();

        _servers[address] = server;
        results.add((address: address, port: server.port!));
      } catch (e) {
        // Failed to bind to this address, skip it
        continue;
      }
    }

    return results;
  }

  /// Get server for address
  IceTcpServer? getServer(String address) => _servers[address];

  /// Get connection for remote endpoint
  IceTcpConnection? getConnection(
    String localAddress,
    String remoteAddress,
    int remotePort,
  ) {
    final server = _servers[localAddress];
    return server?.getConnection(remoteAddress, remotePort);
  }

  /// Close all servers
  Future<void> close() async {
    for (final server in _servers.values) {
      await server.stop();
    }
    _servers.clear();
  }
}
