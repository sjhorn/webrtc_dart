import 'dart:typed_data';

import 'package:webrtc_dart/src/sctp/chunk.dart';
import 'package:webrtc_dart/src/sctp/const.dart';
import 'package:webrtc_dart/src/sctp/inbound_stream.dart';

export 'package:webrtc_dart/src/sctp/inbound_stream.dart';

/// Create an InboundStream for testing
InboundStream createInboundStream() => InboundStream();

/// Create a DATA chunk for testing fragment reassembly
SctpDataChunk createDataChunk({
  required int tsn,
  required int streamId,
  required int streamSeq,
  required int ppid,
  required Uint8List userData,
  required bool beginningFragment,
  required bool endFragment,
  bool unordered = false,
}) {
  var flags = 0;
  if (endFragment) flags |= SctpDataChunkFlags.endFragment;
  if (beginningFragment) flags |= SctpDataChunkFlags.beginningFragment;
  if (unordered) flags |= SctpDataChunkFlags.unordered;

  return SctpDataChunk(
    tsn: tsn,
    streamId: streamId,
    streamSeq: streamSeq,
    ppid: ppid,
    userData: userData,
    flags: flags,
  );
}
