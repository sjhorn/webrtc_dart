import 'dart:async';
import 'package:webrtc_dart/src/media/media_stream_track.dart';

/// Media Stream
/// Represents a collection of media tracks (audio and/or video)
/// Based on W3C MediaStream API
class MediaStream {
  /// Unique identifier
  final String id;

  /// Tracks in this stream
  final List<MediaStreamTrack> _tracks = [];

  /// Track added event stream
  final _trackAddedController = StreamController<MediaStreamTrack>.broadcast();

  /// Track removed event stream
  final _trackRemovedController =
      StreamController<MediaStreamTrack>.broadcast();

  /// Active state change stream
  final _activeController = StreamController<bool>.broadcast();

  MediaStream({String? id}) : id = id ?? _generateId();

  /// Create stream from tracks
  MediaStream.fromTracks(List<MediaStreamTrack> tracks, {String? id})
      : id = id ?? _generateId() {
    for (final track in tracks) {
      addTrack(track);
    }
  }

  /// Get all tracks
  List<MediaStreamTrack> getTracks() {
    return List.unmodifiable(_tracks);
  }

  /// Get audio tracks
  List<AudioStreamTrack> getAudioTracks() {
    return _tracks.whereType<AudioStreamTrack>().toList();
  }

  /// Get video tracks
  List<VideoStreamTrack> getVideoTracks() {
    return _tracks.whereType<VideoStreamTrack>().toList();
  }

  /// Get track by ID
  MediaStreamTrack? getTrackById(String trackId) {
    try {
      return _tracks.firstWhere((t) => t.id == trackId);
    } catch (_) {
      return null;
    }
  }

  /// Add track to stream
  void addTrack(MediaStreamTrack track) {
    if (!_tracks.contains(track)) {
      _tracks.add(track);
      _trackAddedController.add(track);
      _updateActiveState();
    }
  }

  /// Remove track from stream
  void removeTrack(MediaStreamTrack track) {
    if (_tracks.remove(track)) {
      _trackRemovedController.add(track);
      _updateActiveState();
    }
  }

  /// Check if stream is active (has at least one live track)
  bool get active {
    return _tracks.any((track) => track.state == MediaStreamTrackState.live);
  }

  /// Stream of track added events
  Stream<MediaStreamTrack> get onAddTrack => _trackAddedController.stream;

  /// Stream of track removed events
  Stream<MediaStreamTrack> get onRemoveTrack => _trackRemovedController.stream;

  /// Stream of active state changes
  Stream<bool> get onActiveChange => _activeController.stream;

  /// Clone the stream
  MediaStream clone() {
    final clonedTracks = _tracks.map((track) => track.clone()).toList();
    return MediaStream.fromTracks(clonedTracks);
  }

  /// Update active state and emit event if changed
  void _updateActiveState() {
    final newActive = active;
    _activeController.add(newActive);
  }

  /// Dispose resources
  void dispose() {
    for (final track in _tracks) {
      track.dispose();
    }
    _tracks.clear();
    _trackAddedController.close();
    _trackRemovedController.close();
    _activeController.close();
  }

  /// Generate unique stream ID
  static String _generateId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final random = timestamp.hashCode;
    return '{${random.toRadixString(16).padLeft(8, '0')}-stream}';
  }

  @override
  String toString() {
    final audioCount = getAudioTracks().length;
    final videoCount = getVideoTracks().length;
    return 'MediaStream(id=$id, audio=$audioCount, video=$videoCount, active=$active)';
  }
}
