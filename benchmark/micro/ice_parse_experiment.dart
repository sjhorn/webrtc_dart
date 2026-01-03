/// ICE Candidate Parsing Experiment
///
/// Compares different parsing approaches:
/// 1. Current: indexOf + substring
/// 2. Byte-level: work with codeUnits directly
///
/// Run: dart run benchmark/micro/ice_parse_experiment.dart

import 'dart:typed_data';

const testSdp =
    '6815297761 1 udp 2130706431 192.168.1.100 31102 typ host generation 0 ufrag b7l3';

const iterations = 500000;
const warmup = 10000;

void main() {
  print('ICE Candidate Parsing Experiment');
  print('=' * 60);
  print('Input: $testSdp');
  print('Iterations: $iterations\n');

  // Warm up both approaches
  for (var i = 0; i < warmup; i++) {
    parseWithIndexOf(testSdp);
    parseWithCodeUnits(testSdp);
  }

  // Benchmark indexOf approach (current)
  var sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    parseWithIndexOf(testSdp);
  }
  sw.stop();
  final indexOfTime = sw.elapsedMicroseconds;
  final indexOfOps = (iterations / indexOfTime * 1000000).round();
  print('indexOf + substring:');
  print('  ${indexOfOps} ops/sec');
  print('  ${(indexOfTime / iterations).toStringAsFixed(2)} µs/op\n');

  // Benchmark codeUnits approach
  sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    parseWithCodeUnits(testSdp);
  }
  sw.stop();
  final codeUnitsTime = sw.elapsedMicroseconds;
  final codeUnitsOps = (iterations / codeUnitsTime * 1000000).round();
  print('codeUnits byte-level:');
  print('  ${codeUnitsOps} ops/sec');
  print('  ${(codeUnitsTime / iterations).toStringAsFixed(2)} µs/op\n');

  // Benchmark codeUnits with pre-encoded input
  final preEncoded = Uint16List.fromList(testSdp.codeUnits);
  sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    parseWithPreEncodedCodeUnits(preEncoded);
  }
  sw.stop();
  final preEncodedTime = sw.elapsedMicroseconds;
  final preEncodedOps = (iterations / preEncodedTime * 1000000).round();
  print('Pre-encoded codeUnits:');
  print('  ${preEncodedOps} ops/sec');
  print('  ${(preEncodedTime / iterations).toStringAsFixed(2)} µs/op\n');

  print('=' * 60);
  print('Comparison:');
  print(
      '  codeUnits vs indexOf: ${(codeUnitsOps / indexOfOps).toStringAsFixed(2)}x');
  print(
      '  pre-encoded vs indexOf: ${(preEncodedOps / indexOfOps).toStringAsFixed(2)}x');

  // Verify correctness
  print('\nVerifying correctness...');
  final r1 = parseWithIndexOf(testSdp);
  final r2 = parseWithCodeUnits(testSdp);
  final r3 = parseWithPreEncodedCodeUnits(preEncoded);

  if (r1.foundation == r2.foundation &&
      r2.foundation == r3.foundation &&
      r1.component == r2.component &&
      r2.component == r3.component &&
      r1.priority == r2.priority &&
      r2.priority == r3.priority &&
      r1.host == r2.host &&
      r2.host == r3.host &&
      r1.port == r2.port &&
      r2.port == r3.port &&
      r1.type == r2.type &&
      r2.type == r3.type) {
    print('✓ All approaches produce identical results');
  } else {
    print('✗ Results differ!');
    print('  indexOf: $r1');
    print('  codeUnits: $r2');
    print('  preEncoded: $r3');
  }
}

/// Simple result class to hold parsed values
class ParseResult {
  final String foundation;
  final int component;
  final String transport;
  final int priority;
  final String host;
  final int port;
  final String type;
  final String? generation;
  final String? ufrag;

  ParseResult({
    required this.foundation,
    required this.component,
    required this.transport,
    required this.priority,
    required this.host,
    required this.port,
    required this.type,
    this.generation,
    this.ufrag,
  });

  @override
  String toString() =>
      'ParseResult($foundation, $component, $transport, $priority, $host, $port, $type)';
}

/// Current approach: indexOf + substring
ParseResult parseWithIndexOf(String sdp) {
  int nextSpace(int from) {
    final idx = sdp.indexOf(' ', from);
    return idx == -1 ? sdp.length : idx;
  }

  var pos = 0;
  var spacePos = nextSpace(pos);
  final foundation = sdp.substring(pos, spacePos);

  pos = spacePos + 1;
  spacePos = nextSpace(pos);
  final component = int.parse(sdp.substring(pos, spacePos));

  pos = spacePos + 1;
  spacePos = nextSpace(pos);
  final transport = sdp.substring(pos, spacePos);

  pos = spacePos + 1;
  spacePos = nextSpace(pos);
  final priority = int.parse(sdp.substring(pos, spacePos));

  pos = spacePos + 1;
  spacePos = nextSpace(pos);
  final host = sdp.substring(pos, spacePos);

  pos = spacePos + 1;
  spacePos = nextSpace(pos);
  final port = int.parse(sdp.substring(pos, spacePos));

  // Skip "typ"
  pos = spacePos + 1;
  spacePos = nextSpace(pos);

  pos = spacePos + 1;
  spacePos = nextSpace(pos);
  final type = sdp.substring(pos, spacePos);

  // Parse optional attributes
  String? generation;
  String? ufrag;

  pos = spacePos + 1;
  while (pos < sdp.length) {
    spacePos = nextSpace(pos);
    final key = sdp.substring(pos, spacePos);

    pos = spacePos + 1;
    if (pos >= sdp.length) break;

    spacePos = nextSpace(pos);
    final value = sdp.substring(pos, spacePos);

    if (key == 'generation') {
      generation = value;
    } else if (key == 'ufrag') {
      ufrag = value;
    }

    pos = spacePos + 1;
  }

  return ParseResult(
    foundation: foundation,
    component: component,
    transport: transport,
    priority: priority,
    host: host,
    port: port,
    type: type,
    generation: generation,
    ufrag: ufrag,
  );
}

/// Byte-level approach: work with codeUnits
ParseResult parseWithCodeUnits(String sdp) {
  final units = sdp.codeUnits;
  final len = units.length;
  const space = 0x20; // ' '

  int nextSpace(int from) {
    for (var i = from; i < len; i++) {
      if (units[i] == space) return i;
    }
    return len;
  }

  // Parse integer from code units without creating substring
  int parseInt(int start, int end) {
    var result = 0;
    for (var i = start; i < end; i++) {
      result = result * 10 + (units[i] - 0x30); // '0' = 0x30
    }
    return result;
  }

  var pos = 0;
  var spacePos = nextSpace(pos);
  final foundation = String.fromCharCodes(units, pos, spacePos);

  pos = spacePos + 1;
  spacePos = nextSpace(pos);
  final component = parseInt(pos, spacePos);

  pos = spacePos + 1;
  spacePos = nextSpace(pos);
  final transport = String.fromCharCodes(units, pos, spacePos);

  pos = spacePos + 1;
  spacePos = nextSpace(pos);
  final priority = parseInt(pos, spacePos);

  pos = spacePos + 1;
  spacePos = nextSpace(pos);
  final host = String.fromCharCodes(units, pos, spacePos);

  pos = spacePos + 1;
  spacePos = nextSpace(pos);
  final port = parseInt(pos, spacePos);

  // Skip "typ"
  pos = spacePos + 1;
  spacePos = nextSpace(pos);

  pos = spacePos + 1;
  spacePos = nextSpace(pos);
  final type = String.fromCharCodes(units, pos, spacePos);

  // Parse optional attributes
  String? generation;
  String? ufrag;

  pos = spacePos + 1;
  while (pos < len) {
    spacePos = nextSpace(pos);

    // Check first char for fast dispatch
    final firstChar = units[pos];

    pos = spacePos + 1;
    if (pos >= len) break;

    spacePos = nextSpace(pos);

    if (firstChar == 0x67) {
      // 'g' - generation
      generation = String.fromCharCodes(units, pos, spacePos);
    } else if (firstChar == 0x75) {
      // 'u' - ufrag
      ufrag = String.fromCharCodes(units, pos, spacePos);
    }

    pos = spacePos + 1;
  }

  return ParseResult(
    foundation: foundation,
    component: component,
    transport: transport,
    priority: priority,
    host: host,
    port: port,
    type: type,
    generation: generation,
    ufrag: ufrag,
  );
}

/// Pre-encoded approach: work with Uint16List directly
ParseResult parseWithPreEncodedCodeUnits(Uint16List units) {
  final len = units.length;
  const space = 0x20; // ' '

  int nextSpace(int from) {
    for (var i = from; i < len; i++) {
      if (units[i] == space) return i;
    }
    return len;
  }

  // Parse integer from code units without creating substring
  int parseInt(int start, int end) {
    var result = 0;
    for (var i = start; i < end; i++) {
      result = result * 10 + (units[i] - 0x30); // '0' = 0x30
    }
    return result;
  }

  var pos = 0;
  var spacePos = nextSpace(pos);
  final foundation = String.fromCharCodes(units, pos, spacePos);

  pos = spacePos + 1;
  spacePos = nextSpace(pos);
  final component = parseInt(pos, spacePos);

  pos = spacePos + 1;
  spacePos = nextSpace(pos);
  final transport = String.fromCharCodes(units, pos, spacePos);

  pos = spacePos + 1;
  spacePos = nextSpace(pos);
  final priority = parseInt(pos, spacePos);

  pos = spacePos + 1;
  spacePos = nextSpace(pos);
  final host = String.fromCharCodes(units, pos, spacePos);

  pos = spacePos + 1;
  spacePos = nextSpace(pos);
  final port = parseInt(pos, spacePos);

  // Skip "typ"
  pos = spacePos + 1;
  spacePos = nextSpace(pos);

  pos = spacePos + 1;
  spacePos = nextSpace(pos);
  final type = String.fromCharCodes(units, pos, spacePos);

  // Parse optional attributes
  String? generation;
  String? ufrag;

  pos = spacePos + 1;
  while (pos < len) {
    spacePos = nextSpace(pos);

    // Check first char for fast dispatch
    final firstChar = units[pos];

    pos = spacePos + 1;
    if (pos >= len) break;

    spacePos = nextSpace(pos);

    if (firstChar == 0x67) {
      // 'g' - generation
      generation = String.fromCharCodes(units, pos, spacePos);
    } else if (firstChar == 0x75) {
      // 'u' - ufrag
      ufrag = String.fromCharCodes(units, pos, spacePos);
    }

    pos = spacePos + 1;
  }

  return ParseResult(
    foundation: foundation,
    component: component,
    transport: transport,
    priority: priority,
    host: host,
    port: port,
    type: type,
    generation: generation,
    ufrag: ufrag,
  );
}
