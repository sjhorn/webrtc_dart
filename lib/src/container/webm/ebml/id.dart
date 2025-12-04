import 'dart:typed_data';

/// EBML Element IDs for Matroska/WebM containers
/// See: https://www.matroska.org/technical/specs/index.html
class EbmlId {
  // EBML Header
  static final ebml = Uint8List.fromList([0x1a, 0x45, 0xdf, 0xa3]);
  static final ebmlVersion = Uint8List.fromList([0x42, 0x86]);
  static final ebmlReadVersion = Uint8List.fromList([0x42, 0xf7]);
  static final ebmlMaxIdLength = Uint8List.fromList([0x42, 0xf2]);
  static final ebmlMaxSizeLength = Uint8List.fromList([0x42, 0xf3]);
  static final docType = Uint8List.fromList([0x42, 0x82]);
  static final docTypeVersion = Uint8List.fromList([0x42, 0x87]);
  static final docTypeReadVersion = Uint8List.fromList([0x42, 0x85]);

  // Global Elements
  static final voidElement = Uint8List.fromList([0xec]);
  static final crc32 = Uint8List.fromList([0xbf]);

  // Segment
  static final segment = Uint8List.fromList([0x18, 0x53, 0x80, 0x67]);

  // Seek Head
  static final seekHead = Uint8List.fromList([0x11, 0x4d, 0x9b, 0x74]);
  static final seek = Uint8List.fromList([0x4d, 0xbb]);
  static final seekId = Uint8List.fromList([0x53, 0xab]);
  static final seekPosition = Uint8List.fromList([0x53, 0xac]);

  // Segment Info
  static final info = Uint8List.fromList([0x15, 0x49, 0xa9, 0x66]);
  static final segmentUid = Uint8List.fromList([0x73, 0xa4]);
  static final segmentFilename = Uint8List.fromList([0x73, 0x84]);
  static final prevUid = Uint8List.fromList([0x3c, 0xb9, 0x23]);
  static final prevFilename = Uint8List.fromList([0x3c, 0x83, 0xab]);
  static final nextUid = Uint8List.fromList([0x3e, 0xb9, 0x23]);
  static final nextFilename = Uint8List.fromList([0x3e, 0x83, 0xbb]);
  static final segmentFamily = Uint8List.fromList([0x44, 0x44]);
  static final timecodeScale = Uint8List.fromList([0x2a, 0xd7, 0xb1]);
  static final duration = Uint8List.fromList([0x44, 0x89]);
  static final dateUtc = Uint8List.fromList([0x44, 0x61]);
  static final title = Uint8List.fromList([0x7b, 0xa9]);
  static final muxingApp = Uint8List.fromList([0x4d, 0x80]);
  static final writingApp = Uint8List.fromList([0x57, 0x41]);

  // Cluster
  static final cluster = Uint8List.fromList([0x1f, 0x43, 0xb6, 0x75]);
  static final timecode = Uint8List.fromList([0xe7]);
  static final silentTracks = Uint8List.fromList([0x58, 0x54]);
  static final silentTrackNumber = Uint8List.fromList([0x58, 0xd7]);
  static final position = Uint8List.fromList([0xa7]);
  static final prevSize = Uint8List.fromList([0xab]);

  // Block
  static final simpleBlock = Uint8List.fromList([0xa3]);
  static final blockGroup = Uint8List.fromList([0xa0]);
  static final block = Uint8List.fromList([0xa1]);
  static final blockAdditions = Uint8List.fromList([0x75, 0xa1]);
  static final blockMore = Uint8List.fromList([0xa6]);
  static final blockAddId = Uint8List.fromList([0xee]);
  static final blockAdditional = Uint8List.fromList([0xa5]);
  static final blockDuration = Uint8List.fromList([0x9b]);
  static final referencePriority = Uint8List.fromList([0xfa]);
  static final referenceBlock = Uint8List.fromList([0xfb]);
  static final codecState = Uint8List.fromList([0xa4]);
  static final discardPadding = Uint8List.fromList([0x75, 0xa2]);
  static final slices = Uint8List.fromList([0x8e]);
  static final timeSlice = Uint8List.fromList([0xe8]);
  static final laceNumber = Uint8List.fromList([0xcc]);

  // Tracks
  static final tracks = Uint8List.fromList([0x16, 0x54, 0xae, 0x6b]);
  static final trackEntry = Uint8List.fromList([0xae]);
  static final trackNumber = Uint8List.fromList([0xd7]);
  static final trackUid = Uint8List.fromList([0x73, 0xc5]);
  static final trackType = Uint8List.fromList([0x83]);
  static final flagEnabled = Uint8List.fromList([0xb9]);
  static final flagDefault = Uint8List.fromList([0x88]);
  static final flagForced = Uint8List.fromList([0x55, 0xaa]);
  static final flagLacing = Uint8List.fromList([0x9c]);
  static final minCache = Uint8List.fromList([0x6d, 0xe7]);
  static final maxCache = Uint8List.fromList([0x6d, 0xf8]);
  static final defaultDuration = Uint8List.fromList([0x23, 0xe3, 0x83]);
  static final defaultDecodedFieldDuration =
      Uint8List.fromList([0x23, 0x4e, 0x7a]);
  static final maxBlockAdditionId = Uint8List.fromList([0x55, 0xee]);
  static final name = Uint8List.fromList([0x53, 0x6e]);
  static final language = Uint8List.fromList([0x22, 0xb5, 0x9c]);
  static final codecId = Uint8List.fromList([0x86]);
  static final codecPrivate = Uint8List.fromList([0x63, 0xa2]);
  static final codecName = Uint8List.fromList([0x25, 0x86, 0x88]);
  static final attachmentLink = Uint8List.fromList([0x74, 0x46]);
  static final codecDecodeAll = Uint8List.fromList([0xaa]);
  static final trackOverlay = Uint8List.fromList([0x6f, 0xab]);
  static final codecDelay = Uint8List.fromList([0x56, 0xaa]);
  static final seekPreRoll = Uint8List.fromList([0x56, 0xbb]);

  // Video
  static final video = Uint8List.fromList([0xe0]);
  static final flagInterlaced = Uint8List.fromList([0x9a]);
  static final fieldOrder = Uint8List.fromList([0x9d]);
  static final stereoMode = Uint8List.fromList([0x53, 0xb8]);
  static final alphaMode = Uint8List.fromList([0x53, 0xc0]);
  static final pixelWidth = Uint8List.fromList([0xb0]);
  static final pixelHeight = Uint8List.fromList([0xba]);
  static final pixelCropBottom = Uint8List.fromList([0x54, 0xaa]);
  static final pixelCropTop = Uint8List.fromList([0x54, 0xbb]);
  static final pixelCropLeft = Uint8List.fromList([0x54, 0xcc]);
  static final pixelCropRight = Uint8List.fromList([0x54, 0xdd]);
  static final displayWidth = Uint8List.fromList([0x54, 0xb0]);
  static final displayHeight = Uint8List.fromList([0x54, 0xba]);
  static final displayUnit = Uint8List.fromList([0x54, 0xb2]);
  static final aspectRatioType = Uint8List.fromList([0x54, 0xb3]);
  static final colourSpace = Uint8List.fromList([0x2e, 0xb5, 0x24]);

  // Colour
  static final colour = Uint8List.fromList([0x55, 0xb0]);
  static final matrixCoefficients = Uint8List.fromList([0x55, 0xb1]);
  static final bitsPerChannel = Uint8List.fromList([0x55, 0xb2]);
  static final chromaSubsamplingHorz = Uint8List.fromList([0x55, 0xb3]);
  static final chromaSubsamplingVert = Uint8List.fromList([0x55, 0xb4]);
  static final cbSubsamplingHorz = Uint8List.fromList([0x55, 0xb5]);
  static final cbSubsamplingVert = Uint8List.fromList([0x55, 0xb6]);
  static final chromaSitingHorz = Uint8List.fromList([0x55, 0xb7]);
  static final chromaSitingVert = Uint8List.fromList([0x55, 0xb8]);
  static final range = Uint8List.fromList([0x55, 0xb9]);
  static final transferCharacteristics = Uint8List.fromList([0x55, 0xba]);
  static final primaries = Uint8List.fromList([0x55, 0xbb]);
  static final maxCll = Uint8List.fromList([0x55, 0xbc]);
  static final maxFall = Uint8List.fromList([0x55, 0xbd]);

  // Mastering Metadata
  static final masteringMetadata = Uint8List.fromList([0x55, 0xd0]);
  static final primaryRChromaticityX = Uint8List.fromList([0x55, 0xd1]);
  static final primaryRChromaticityY = Uint8List.fromList([0x55, 0xd2]);
  static final primaryGChromaticityX = Uint8List.fromList([0x55, 0xd3]);
  static final primaryGChromaticityY = Uint8List.fromList([0x55, 0xd4]);
  static final primaryBChromaticityX = Uint8List.fromList([0x55, 0xd5]);
  static final primaryBChromaticityY = Uint8List.fromList([0x55, 0xd6]);
  static final whitePointChromaticityX = Uint8List.fromList([0x55, 0xd7]);
  static final whitePointChromaticityY = Uint8List.fromList([0x55, 0xd8]);
  static final luminanceMax = Uint8List.fromList([0x55, 0xd9]);
  static final luminanceMin = Uint8List.fromList([0x55, 0xda]);

  // Audio
  static final audio = Uint8List.fromList([0xe1]);
  static final samplingFrequency = Uint8List.fromList([0xb5]);
  static final outputSamplingFrequency = Uint8List.fromList([0x78, 0xb5]);
  static final channels = Uint8List.fromList([0x9f]);
  static final bitDepth = Uint8List.fromList([0x62, 0x64]);

  // Content Encoding
  static final contentEncodings = Uint8List.fromList([0x6d, 0x80]);
  static final contentEncoding = Uint8List.fromList([0x62, 0x40]);
  static final contentEncodingOrder = Uint8List.fromList([0x50, 0x31]);
  static final contentEncodingScope = Uint8List.fromList([0x50, 0x32]);
  static final contentEncodingType = Uint8List.fromList([0x50, 0x33]);
  static final contentCompression = Uint8List.fromList([0x50, 0x34]);
  static final contentCompAlgo = Uint8List.fromList([0x42, 0x54]);
  static final contentCompSettings = Uint8List.fromList([0x42, 0x55]);
  static final contentEncryption = Uint8List.fromList([0x50, 0x35]);
  static final contentEncAlgo = Uint8List.fromList([0x47, 0xe1]);
  static final contentEncKeyId = Uint8List.fromList([0x47, 0xe2]);
  static final contentEncAesSettings = Uint8List.fromList([0x47, 0xe7]);
  static final aesSettingsCipherMode = Uint8List.fromList([0x47, 0xe8]);

  // Cues
  static final cues = Uint8List.fromList([0x1c, 0x53, 0xbb, 0x6b]);
  static final cuePoint = Uint8List.fromList([0xbb]);
  static final cueTime = Uint8List.fromList([0xb3]);
  static final cueTrackPositions = Uint8List.fromList([0xb7]);
  static final cueTrack = Uint8List.fromList([0xf7]);
  static final cueClusterPosition = Uint8List.fromList([0xf1]);
  static final cueRelativePosition = Uint8List.fromList([0xf0]);
  static final cueDuration = Uint8List.fromList([0xb2]);
  static final cueBlockNumber = Uint8List.fromList([0x53, 0x78]);
  static final cueCodecState = Uint8List.fromList([0xea]);
  static final cueReference = Uint8List.fromList([0xdb]);
  static final cueRefTime = Uint8List.fromList([0x96]);

  // Attachments
  static final attachments = Uint8List.fromList([0x19, 0x41, 0xa4, 0x69]);
  static final attachedFile = Uint8List.fromList([0x61, 0xa7]);
  static final fileDescription = Uint8List.fromList([0x46, 0x7e]);
  static final fileName = Uint8List.fromList([0x46, 0x6e]);
  static final fileMimeType = Uint8List.fromList([0x46, 0x60]);
  static final fileData = Uint8List.fromList([0x46, 0x5c]);
  static final fileUid = Uint8List.fromList([0x46, 0xae]);

  // Chapters
  static final chapters = Uint8List.fromList([0x10, 0x43, 0xa7, 0x70]);
  static final editionEntry = Uint8List.fromList([0x45, 0xb9]);
  static final editionUid = Uint8List.fromList([0x45, 0xbc]);
  static final editionFlagHidden = Uint8List.fromList([0x45, 0xbd]);
  static final editionFlagDefault = Uint8List.fromList([0x45, 0xdb]);
  static final editionFlagOrdered = Uint8List.fromList([0x45, 0xdd]);
  static final chapterAtom = Uint8List.fromList([0xb6]);
  static final chapterUid = Uint8List.fromList([0x73, 0xc4]);
  static final chapterStringUid = Uint8List.fromList([0x56, 0x54]);
  static final chapterTimeStart = Uint8List.fromList([0x91]);
  static final chapterTimeEnd = Uint8List.fromList([0x92]);
  static final chapterFlagHidden = Uint8List.fromList([0x98]);
  static final chapterFlagEnabled = Uint8List.fromList([0x45, 0x98]);
  static final chapterDisplay = Uint8List.fromList([0x80]);
  static final chapString = Uint8List.fromList([0x85]);
  static final chapLanguage = Uint8List.fromList([0x43, 0x7c]);

  // Tags
  static final tags = Uint8List.fromList([0x12, 0x54, 0xc3, 0x67]);
  static final tag = Uint8List.fromList([0x73, 0x73]);
  static final targets = Uint8List.fromList([0x63, 0xc0]);
  static final targetTypeValue = Uint8List.fromList([0x68, 0xca]);
  static final targetType = Uint8List.fromList([0x63, 0xca]);
  static final tagTrackUid = Uint8List.fromList([0x63, 0xc5]);
  static final tagEditionUid = Uint8List.fromList([0x63, 0xc9]);
  static final tagChapterUid = Uint8List.fromList([0x63, 0xc4]);
  static final tagAttachmentUid = Uint8List.fromList([0x63, 0xc6]);
  static final simpleTag = Uint8List.fromList([0x67, 0xc8]);
  static final tagName = Uint8List.fromList([0x45, 0xa3]);
  static final tagLanguage = Uint8List.fromList([0x44, 0x7a]);
  static final tagDefault = Uint8List.fromList([0x44, 0x84]);
  static final tagString = Uint8List.fromList([0x44, 0x87]);
  static final tagBinary = Uint8List.fromList([0x44, 0x85]);

  // Projection (360 video)
  static final projection = Uint8List.fromList([0x76, 0x70]);
  static final projectionType = Uint8List.fromList([0x76, 0x71]);
  static final projectionPrivate = Uint8List.fromList([0x76, 0x72]);
  static final projectionPoseYaw = Uint8List.fromList([0x76, 0x73]);
  static final projectionPosePitch = Uint8List.fromList([0x76, 0x74]);
  static final projectionPoseRoll = Uint8List.fromList([0x76, 0x75]);
}

/// Matroska track types
class MatroskaTrackType {
  static const int video = 1;
  static const int audio = 2;
  static const int complex = 3;
  static const int logo = 0x10;
  static const int subtitle = 0x11;
  static const int buttons = 0x12;
  static const int control = 0x20;
}
