/// RtpStream - Stream-based RTP processing
///
/// Provides a stream interface for RTP packet processing,
/// filtering by payload type.
///
/// Ported from werift-webrtc rtpStream.ts
library;

import 'dart:async';
import 'dart:typed_data';

import '../../srtp/rtp_packet.dart';

/// RTP output wrapper
class RtpOutput {
  /// RTP packet
  final RtpPacket? rtp;

  /// End of life signal
  final bool eol;

  RtpOutput({this.rtp, this.eol = false});
}

/// RTP source stream options
class RtpSourceStreamOptions {
  /// Expected payload type (optional filter)
  final int? payloadType;

  /// Whether to clear invalid PT packets
  final bool clearInvalidPtPacket;

  const RtpSourceStreamOptions({
    this.payloadType,
    this.clearInvalidPtPacket = true,
  });
}

/// RTP source stream
///
/// Provides a [Stream] interface for receiving RTP packets,
/// with optional payload type filtering.
class RtpSourceStream {
  /// Stream options
  final RtpSourceStreamOptions options;

  /// Stream controller
  final StreamController<RtpOutput> _controller;

  /// The readable stream
  Stream<RtpOutput> get stream => _controller.stream;

  /// Whether the stream is closed
  bool _closed = false;

  RtpSourceStream({
    this.options = const RtpSourceStreamOptions(),
  }) : _controller = StreamController<RtpOutput>.broadcast();

  /// Push an RTP packet into the stream
  ///
  /// Can accept either raw bytes or an [RtpPacket].
  void push(dynamic packet) {
    if (_closed) return;

    final RtpPacket rtp;
    if (packet is Uint8List) {
      rtp = RtpPacket.parse(packet);
    } else if (packet is RtpPacket) {
      rtp = packet;
    } else {
      throw ArgumentError('Expected Uint8List or RtpPacket');
    }

    // Filter by payload type if specified
    if (options.payloadType != null && options.payloadType != rtp.payloadType) {
      // Optionally clear the packet
      if (options.clearInvalidPtPacket) {
        // In Dart we just don't emit it
        return;
      }
      return;
    }

    _controller.add(RtpOutput(rtp: rtp));
  }

  /// Stop the stream
  void stop() {
    if (_closed) return;
    _closed = true;
    _controller.add(RtpOutput(eol: true));
    _controller.close();
  }

  /// Whether the stream is closed
  bool get isClosed => _closed;
}

/// RTP sink stream for writing RTP packets
class RtpSinkStream {
  /// Callback for when RTP data is available
  final void Function(Uint8List data)? onData;

  /// Stream subscription
  StreamSubscription<RtpOutput>? _subscription;

  RtpSinkStream({this.onData});

  /// Connect to an RTP source stream
  void connect(RtpSourceStream source) {
    _subscription = source.stream.listen((output) {
      if (output.rtp != null && onData != null) {
        onData!(output.rtp!.serialize());
      }
    });
  }

  /// Disconnect from the source
  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}

/// RTP transform stream for processing RTP packets
class RtpTransformStream {
  /// Transform function
  final RtpPacket? Function(RtpPacket rtp) transform;

  /// Input stream
  final RtpSourceStream _input;

  /// Output stream
  final RtpSourceStream _output;

  /// Subscription
  StreamSubscription<RtpOutput>? _subscription;

  /// Get the output stream
  Stream<RtpOutput> get stream => _output.stream;

  RtpTransformStream({
    required this.transform,
    required RtpSourceStream input,
  })  : _input = input,
        _output = RtpSourceStream() {
    _subscription = _input.stream.listen((output) {
      if (output.eol) {
        _output.stop();
        return;
      }
      if (output.rtp != null) {
        final transformed = transform(output.rtp!);
        if (transformed != null) {
          _output.push(transformed);
        }
      }
    });
  }

  /// Stop the transform stream
  Future<void> stop() async {
    await _subscription?.cancel();
    _output.stop();
  }
}
