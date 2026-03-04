/* 
This file is licensed to you under the Apache License, Version 2.0
(http://www.apache.org/licenses/LICENSE-2.0) or the MIT license
(http://opensource.org/licenses/MIT), at your option.

Unless required by applicable law or agreed to in writing, this software is
distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS OF
ANY KIND, either express or implied. See the LICENSE-MIT and LICENSE-APACHE
files for the specific language governing permissions and limitations under
each license.
*/

/// Type-safe manifest building types for C2PA Flutter
///
/// This file contains all the Dart types needed to construct C2PA manifests
/// in a type-safe manner instead of using raw JSON.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

// =============================================================================
// Enums
// =============================================================================

/// Standard C2PA action identifiers
///
/// These represent the predefined actions in the C2PA specification.
/// Use [value] to get the string representation for JSON serialization.
enum PredefinedAction {
  created('c2pa.created'),
  edited('c2pa.edited'),
  converted('c2pa.converted'),
  compressed('c2pa.compressed'),
  cropped('c2pa.cropped'),
  drawing('c2pa.drawing'),
  filtered('c2pa.filtered'),
  opened('c2pa.opened'),
  orientation('c2pa.orientation'),
  placed('c2pa.placed'),
  published('c2pa.published'),
  redacted('c2pa.redacted'),
  removed('c2pa.removed'),
  repackaged('c2pa.repackaged'),
  resized('c2pa.resized'),
  transcoded('c2pa.transcoded'),
  translated('c2pa.translated'),
  watermarked('c2pa.watermarked'),
  aiGenerated('c2pa.ai_generated'),
  aiTrained('c2pa.ai_trained'),
  derivedFrom('c2pa.derived_from'),
  color('c2pa.color'),
  combined('c2pa.combined'),
  compositeUsed('c2pa.composite_used'),
  contentSummary('c2pa.content_summary'),
  adjustments('c2pa.adjustments');

  const PredefinedAction(this.value);
  final String value;

  static PredefinedAction? fromValue(String? value) {
    if (value == null) return null;
    return PredefinedAction.values.cast<PredefinedAction?>().firstWhere(
      (e) => e?.value == value,
      orElse: () => null,
    );
  }
}

/// Relationship type for ingredients
enum Relationship {
  parentOf,
  componentOf,
  inputTo;

  String toJson() => name;

  static Relationship fromJson(String value) {
    return Relationship.values.firstWhere(
      (e) => e.name == value,
      orElse: () => Relationship.componentOf,
    );
  }
}

/// Role of a region of interest
enum Role {
  areaOfInterest('c2pa.areaOfInterest'),
  edited('c2pa.edited'),
  placed('c2pa.placed'),
  cropped('c2pa.cropped'),
  deleted('c2pa.deleted'),
  invisible('c2pa.invisible');

  const Role(this.value);
  final String value;

  String toJson() => value;

  static Role? fromJson(String? value) {
    if (value == null) return null;
    return Role.values.cast<Role?>().firstWhere(
      (e) => e?.value == value,
      orElse: () => null,
    );
  }
}

/// Shape type for spatial regions
enum ShapeType {
  rectangle,
  circle,
  polygon;

  String toJson() => name;

  static ShapeType fromJson(String value) {
    return ShapeType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ShapeType.rectangle,
    );
  }
}

/// Unit type for coordinates
enum UnitType {
  pixel,
  percent;

  String toJson() => name;

  static UnitType fromJson(String value) {
    return UnitType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => UnitType.pixel,
    );
  }
}

/// Range type for regions of interest
enum RangeType {
  spatial,
  temporal,
  frame,
  textual,
  identified;

  String toJson() => name;

  static RangeType fromJson(String value) {
    return RangeType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => RangeType.spatial,
    );
  }
}

/// Time type for temporal ranges
enum TimeType {
  npt;

  String toJson() => name;
}

/// IPTC image region types
///
/// These are standard region type URLs from the IPTC Photo Metadata standard.
enum ImageRegionType {
  crop('http://cv.iptc.org/newscodes/imageregionrole/crop'),
  composite('http://cv.iptc.org/newscodes/imageregionrole/composite'),
  artwork('http://cv.iptc.org/newscodes/imageregionrole/artwork'),
  border('http://cv.iptc.org/newscodes/imageregionrole/border'),
  businessArea('http://cv.iptc.org/newscodes/imageregionrole/businessArea'),
  graphics('http://cv.iptc.org/newscodes/imageregionrole/graphics'),
  headline('http://cv.iptc.org/newscodes/imageregionrole/headline'),
  mainSubject('http://cv.iptc.org/newscodes/imageregionrole/mainSubject'),
  landscapeScenery(
    'http://cv.iptc.org/newscodes/imageregionrole/landscapeScenery',
  ),
  logo('http://cv.iptc.org/newscodes/imageregionrole/logo'),
  mark('http://cv.iptc.org/newscodes/imageregionrole/mark'),
  organisationInImage(
    'http://cv.iptc.org/newscodes/imageregionrole/organisationInImage',
  ),
  personInImage('http://cv.iptc.org/newscodes/imageregionrole/personInImage'),
  photoCaption('http://cv.iptc.org/newscodes/imageregionrole/photoCaption'),
  product('http://cv.iptc.org/newscodes/imageregionrole/product'),
  safeZone('http://cv.iptc.org/newscodes/imageregionrole/safeZone'),
  subjectArea('http://cv.iptc.org/newscodes/imageregionrole/subjectArea'),
  subjectSubArea('http://cv.iptc.org/newscodes/imageregionrole/subjectSubArea'),
  text('http://cv.iptc.org/newscodes/imageregionrole/text'),
  titleArea('http://cv.iptc.org/newscodes/imageregionrole/titleArea'),
  vehicleInImage('http://cv.iptc.org/newscodes/imageregionrole/vehicleInImage'),
  watermark('http://cv.iptc.org/newscodes/imageregionrole/watermark');

  const ImageRegionType(this.url);
  final String url;

  static ImageRegionType? fromUrl(String? url) {
    if (url == null) return null;
    return ImageRegionType.values.cast<ImageRegionType?>().firstWhere(
      (e) => e?.url == url,
      orElse: () => null,
    );
  }
}

/// Standard assertion labels
enum StandardAssertionLabel {
  actions('c2pa.actions'),
  creativeWork('stds.schema-org.CreativeWork'),
  exif('stds.exif'),
  iptcPhotoMetadata('stds.iptc.photo-metadata'),
  trainingMining('c2pa.training-mining'),
  cawgIdentity('cawg.identity'),
  cawgTrainingMining('cawg.ai_training_and_data_mining');

  const StandardAssertionLabel(this.value);
  final String value;
}

/// Digital source types as defined by C2PA/IPTC
enum DigitalSourceType {
  empty('http://c2pa.org/digitalsourcetype/empty'),
  trainedAlgorithmicData(
    'http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicData',
  ),
  digitalCapture(
    'http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture',
  ),
  computationalCapture(
    'http://cv.iptc.org/newscodes/digitalsourcetype/computationalCapture',
  ),
  negativeFilm('http://cv.iptc.org/newscodes/digitalsourcetype/negativeFilm'),
  positiveFilm('http://cv.iptc.org/newscodes/digitalsourcetype/positiveFilm'),
  print('http://cv.iptc.org/newscodes/digitalsourcetype/print'),
  humanEdits('http://cv.iptc.org/newscodes/digitalsourcetype/humanEdits'),
  compositeWithTrainedAlgorithmicMedia(
    'http://cv.iptc.org/newscodes/digitalsourcetype/compositeWithTrainedAlgorithmicMedia',
  ),
  algorithmicallyEnhanced(
    'http://cv.iptc.org/newscodes/digitalsourcetype/algorithmicallyEnhanced',
  ),
  digitalCreation(
    'http://cv.iptc.org/newscodes/digitalsourcetype/digitalCreation',
  ),
  dataDrivenMedia(
    'http://cv.iptc.org/newscodes/digitalsourcetype/dataDrivenMedia',
  ),
  trainedAlgorithmicMedia(
    'http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia',
  ),
  algorithmicMedia(
    'http://cv.iptc.org/newscodes/digitalsourcetype/algorithmicMedia',
  ),
  screenCapture('http://cv.iptc.org/newscodes/digitalsourcetype/screenCapture'),
  virtualRecording(
    'http://cv.iptc.org/newscodes/digitalsourcetype/virtualRecording',
  ),
  composite('http://cv.iptc.org/newscodes/digitalsourcetype/composite'),
  compositeCapture(
    'http://cv.iptc.org/newscodes/digitalsourcetype/compositeCapture',
  ),
  compositeSynthetic(
    'http://cv.iptc.org/newscodes/digitalsourcetype/compositeSynthetic',
  );

  const DigitalSourceType(this.url);
  final String url;

  static DigitalSourceType? fromUrl(String? url) {
    if (url == null) return null;
    return DigitalSourceType.values.cast<DigitalSourceType?>().firstWhere(
      (e) => e?.url == url,
      orElse: () => null,
    );
  }
}

/// Training/mining permission values
enum TrainingMiningPermission {
  notAllowed('notAllowed'),
  constrained('constrained'),
  allowed('allowed');

  const TrainingMiningPermission(this.value);
  final String value;

  String toJson() => value;

  static TrainingMiningPermission fromJson(String value) {
    return TrainingMiningPermission.values.firstWhere(
      (e) => e.value == value,
      orElse: () => TrainingMiningPermission.notAllowed,
    );
  }
}

// =============================================================================
// Core Types
// =============================================================================

/// 2D coordinate
@immutable
class Coordinate {
  final double x;
  final double y;

  const Coordinate({required this.x, required this.y});

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory Coordinate.fromJson(Map<String, dynamic> json) {
    return Coordinate(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Coordinate &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode => x.hashCode ^ y.hashCode;
}

/// Spatial shape definition
@immutable
class Shape {
  final ShapeType type;
  final Coordinate? origin;
  final double? width;
  final double? height;
  final double? radius;
  final List<Coordinate>? vertices;
  final bool? inside;
  final UnitType? unit;

  const Shape._({
    required this.type,
    this.origin,
    this.width,
    this.height,
    this.radius,
    this.vertices,
    this.inside,
    this.unit,
  });

  /// Create a rectangle shape
  factory Shape.rectangle({
    required Coordinate origin,
    required double width,
    required double height,
    bool? inside,
    UnitType? unit,
  }) {
    return Shape._(
      type: ShapeType.rectangle,
      origin: origin,
      width: width,
      height: height,
      inside: inside,
      unit: unit,
    );
  }

  /// Create a circle shape
  factory Shape.circle({
    required Coordinate origin,
    required double radius,
    bool? inside,
    UnitType? unit,
  }) {
    return Shape._(
      type: ShapeType.circle,
      origin: origin,
      radius: radius,
      inside: inside,
      unit: unit,
    );
  }

  /// Create a polygon shape
  factory Shape.polygon({
    required List<Coordinate> vertices,
    bool? inside,
    UnitType? unit,
  }) {
    return Shape._(
      type: ShapeType.polygon,
      vertices: vertices,
      inside: inside,
      unit: unit,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'type': type.toJson()};
    if (origin != null) map['origin'] = origin!.toJson();
    if (width != null) map['width'] = width;
    if (height != null) map['height'] = height;
    if (radius != null) map['radius'] = radius;
    if (vertices != null) {
      map['vertices'] = vertices!.map((v) => v.toJson()).toList();
    }
    if (inside != null) map['inside'] = inside;
    if (unit != null) map['unit'] = unit!.toJson();
    return map;
  }

  factory Shape.fromJson(Map<String, dynamic> json) {
    final type = ShapeType.fromJson(json['type'] as String);
    return Shape._(
      type: type,
      origin: json['origin'] != null
          ? Coordinate.fromJson(json['origin'] as Map<String, dynamic>)
          : null,
      width: (json['width'] as num?)?.toDouble(),
      height: (json['height'] as num?)?.toDouble(),
      radius: (json['radius'] as num?)?.toDouble(),
      vertices: (json['vertices'] as List<dynamic>?)
          ?.map((v) => Coordinate.fromJson(v as Map<String, dynamic>))
          .toList(),
      inside: json['inside'] as bool?,
      unit: json['unit'] != null ? UnitType.fromJson(json['unit']) : null,
    );
  }
}

/// Frame range for video content
@immutable
class Frame {
  final int start;
  final int? end;

  const Frame({required this.start, this.end});

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'start': start};
    if (end != null) map['end'] = end;
    return map;
  }

  factory Frame.fromJson(Map<String, dynamic> json) {
    return Frame(start: json['start'] as int, end: json['end'] as int?);
  }
}

/// Time range for temporal regions
@immutable
class Time {
  final TimeType type;
  final String start;
  final String? end;

  const Time({this.type = TimeType.npt, required this.start, this.end});

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'type': type.toJson(), 'start': start};
    if (end != null) map['end'] = end;
    return map;
  }

  factory Time.fromJson(Map<String, dynamic> json) {
    return Time(
      type: TimeType.npt,
      start: json['start'] as String,
      end: json['end'] as String?,
    );
  }
}

/// Text selector for textual regions
@immutable
class TextSelector {
  final String fragment;
  final int? start;
  final int? end;

  const TextSelector({required this.fragment, this.start, this.end});

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'fragment': fragment};
    if (start != null) map['start'] = start;
    if (end != null) map['end'] = end;
    return map;
  }

  factory TextSelector.fromJson(Map<String, dynamic> json) {
    return TextSelector(
      fragment: json['fragment'] as String,
      start: json['start'] as int?,
      end: json['end'] as int?,
    );
  }
}

/// Range definition for regions of interest
@immutable
sealed class RegionRange {
  const RegionRange();

  Map<String, dynamic> toJson();

  static RegionRange fromJson(Map<String, dynamic> json) {
    if (json.containsKey('shape')) {
      return SpatialRange.fromJson(json);
    } else if (json.containsKey('time')) {
      return TemporalRange.fromJson(json);
    } else if (json.containsKey('frame')) {
      return FrameRange.fromJson(json);
    } else if (json.containsKey('text')) {
      return TextualRange.fromJson(json);
    } else if (json.containsKey('id')) {
      return IdentifiedRange.fromJson(json);
    }
    throw ArgumentError('Unknown region range type');
  }
}

/// Spatial region range
@immutable
class SpatialRange extends RegionRange {
  final Shape shape;

  const SpatialRange({required this.shape});

  @override
  Map<String, dynamic> toJson() => {'shape': shape.toJson()};

  factory SpatialRange.fromJson(Map<String, dynamic> json) {
    return SpatialRange(
      shape: Shape.fromJson(json['shape'] as Map<String, dynamic>),
    );
  }
}

/// Temporal region range
@immutable
class TemporalRange extends RegionRange {
  final Time time;

  const TemporalRange({required this.time});

  @override
  Map<String, dynamic> toJson() => {'time': time.toJson()};

  factory TemporalRange.fromJson(Map<String, dynamic> json) {
    return TemporalRange(
      time: Time.fromJson(json['time'] as Map<String, dynamic>),
    );
  }
}

/// Frame-based region range
@immutable
class FrameRange extends RegionRange {
  final Frame frame;

  const FrameRange({required this.frame});

  @override
  Map<String, dynamic> toJson() => {'frame': frame.toJson()};

  factory FrameRange.fromJson(Map<String, dynamic> json) {
    return FrameRange(
      frame: Frame.fromJson(json['frame'] as Map<String, dynamic>),
    );
  }
}

/// Text-based region range
@immutable
class TextualRange extends RegionRange {
  final TextSelector text;

  const TextualRange({required this.text});

  @override
  Map<String, dynamic> toJson() => {'text': text.toJson()};

  factory TextualRange.fromJson(Map<String, dynamic> json) {
    return TextualRange(
      text: TextSelector.fromJson(json['text'] as Map<String, dynamic>),
    );
  }
}

/// Identified region range (by reference ID)
@immutable
class IdentifiedRange extends RegionRange {
  final String id;

  const IdentifiedRange({required this.id});

  @override
  Map<String, dynamic> toJson() => {'id': id};

  factory IdentifiedRange.fromJson(Map<String, dynamic> json) {
    return IdentifiedRange(id: json['id'] as String);
  }
}

/// Region of interest in content
@immutable
class RegionOfInterest {
  final List<RegionRange> region;
  final String? description;
  final String? name;
  final String? identifier;
  final Role? role;
  final String? regionType;

  const RegionOfInterest({
    required this.region,
    this.description,
    this.name,
    this.identifier,
    this.role,
    this.regionType,
  });

  /// Create a spatial region of interest
  factory RegionOfInterest.spatial({
    required Shape shape,
    String? description,
    String? name,
    String? identifier,
    Role? role,
    ImageRegionType? regionType,
  }) {
    return RegionOfInterest(
      region: [SpatialRange(shape: shape)],
      description: description,
      name: name,
      identifier: identifier,
      role: role,
      regionType: regionType?.url,
    );
  }

  /// Create a temporal region of interest
  factory RegionOfInterest.temporal({
    required Time time,
    String? description,
    String? name,
    String? identifier,
    Role? role,
  }) {
    return RegionOfInterest(
      region: [TemporalRange(time: time)],
      description: description,
      name: name,
      identifier: identifier,
      role: role,
    );
  }

  /// Create a frame-based region of interest
  factory RegionOfInterest.frame({
    required Frame frame,
    String? description,
    String? name,
    String? identifier,
    Role? role,
  }) {
    return RegionOfInterest(
      region: [FrameRange(frame: frame)],
      description: description,
      name: name,
      identifier: identifier,
      role: role,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'region': region.map((r) => r.toJson()).toList(),
    };
    if (description != null) map['description'] = description;
    if (name != null) map['name'] = name;
    if (identifier != null) map['identifier'] = identifier;
    if (role != null) map['role'] = role!.value;
    if (regionType != null) map['type'] = regionType;
    return map;
  }

  factory RegionOfInterest.fromJson(Map<String, dynamic> json) {
    return RegionOfInterest(
      region: (json['region'] as List<dynamic>)
          .map((r) => RegionRange.fromJson(r as Map<String, dynamic>))
          .toList(),
      description: json['description'] as String?,
      name: json['name'] as String?,
      identifier: json['identifier'] as String?,
      role: Role.fromJson(json['role'] as String?),
      regionType: json['type'] as String?,
    );
  }
}

/// Hashed URI reference
@immutable
class HashedUri {
  final String url;
  final String? alg;
  final String? hash;

  const HashedUri({required this.url, this.alg, this.hash});

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'url': url};
    if (alg != null) map['alg'] = alg;
    if (hash != null) map['hash'] = hash;
    return map;
  }

  factory HashedUri.fromJson(Map<String, dynamic> json) {
    return HashedUri(
      url: json['url'] as String,
      alg: json['alg'] as String?,
      hash: json['hash'] as String?,
    );
  }
}

/// Resource reference for manifest resources
@immutable
class ResourceRef {
  final String identifier;
  final String? format;

  const ResourceRef({required this.identifier, this.format});

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'identifier': identifier};
    if (format != null) map['format'] = format;
    return map;
  }

  factory ResourceRef.fromJson(Map<String, dynamic> json) {
    return ResourceRef(
      identifier: json['identifier'] as String,
      format: json['format'] as String?,
    );
  }
}

/// Resource data for adding resources to a manifest
@immutable
class ResourceData {
  final String identifier;
  final Uint8List data;
  final String? format;

  const ResourceData({
    required this.identifier,
    required this.data,
    this.format,
  });
}

/// Asset type information
@immutable
class AssetType {
  final String type;

  const AssetType({required this.type});

  Map<String, dynamic> toJson() => {'type': type};

  factory AssetType.fromJson(Map<String, dynamic> json) {
    return AssetType(type: json['type'] as String);
  }
}

/// Data source information
@immutable
class DataSource {
  final String type;
  final String? details;
  final List<HashedUri>? actors;

  const DataSource({required this.type, this.details, this.actors});

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'type': type};
    if (details != null) map['details'] = details;
    if (actors != null) {
      map['actors'] = actors!.map((a) => a.toJson()).toList();
    }
    return map;
  }

  factory DataSource.fromJson(Map<String, dynamic> json) {
    return DataSource(
      type: json['type'] as String,
      details: json['details'] as String?,
      actors: (json['actors'] as List<dynamic>?)
          ?.map((a) => HashedUri.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Validation status entry
@immutable
class ValidationStatusEntry {
  final String code;
  final String? url;
  final String? explanation;

  const ValidationStatusEntry({required this.code, this.url, this.explanation});

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'code': code};
    if (url != null) map['url'] = url;
    if (explanation != null) map['explanation'] = explanation;
    return map;
  }

  factory ValidationStatusEntry.fromJson(Map<String, dynamic> json) {
    return ValidationStatusEntry(
      code: json['code'] as String,
      url: json['url'] as String?,
      explanation: json['explanation'] as String?,
    );
  }
}

/// Detailed validation results
@immutable
class ValidationResults {
  final List<ValidationStatusEntry> errors;
  final List<ValidationStatusEntry> warnings;
  final List<ValidationStatusEntry> informational;

  const ValidationResults({
    this.errors = const [],
    this.warnings = const [],
    this.informational = const [],
  });

  Map<String, dynamic> toJson() => {
    'errors': errors.map((e) => e.toJson()).toList(),
    'warnings': warnings.map((w) => w.toJson()).toList(),
    'informational': informational.map((i) => i.toJson()).toList(),
  };

  factory ValidationResults.fromJson(Map<String, dynamic> json) {
    return ValidationResults(
      errors:
          (json['errors'] as List<dynamic>?)
              ?.map(
                (e) =>
                    ValidationStatusEntry.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      warnings:
          (json['warnings'] as List<dynamic>?)
              ?.map(
                (w) =>
                    ValidationStatusEntry.fromJson(w as Map<String, dynamic>),
              )
              .toList() ??
          [],
      informational:
          (json['informational'] as List<dynamic>?)
              ?.map(
                (i) =>
                    ValidationStatusEntry.fromJson(i as Map<String, dynamic>),
              )
              .toList() ??
          [],
    );
  }
}

/// C2PA validation status codes as defined in the specification
enum ValidationStatusCode {
  // Success codes
  claimSignatureValidated('claimSignature.validated'),
  signingCredentialTrusted('signingCredential.trusted'),
  timestampTrusted('timeStamp.trusted'),
  assertionDataHashMatch('assertion.dataHash.match'),
  assertionBmffHashMatch('assertion.bmffHash.match'),
  assertionBoxesHashMatch('assertion.boxesHash.match'),
  assertionCollectionHashMatch('assertion.collectionHash.match'),
  assertionHashedUriMatch('assertion.hashedURI.match'),
  assertionIngredientMatch('assertion.ingredientMatch'),
  assertionAccessible('assertion.accessible'),

  // Failure codes
  assertionDataHashMismatch('assertion.dataHash.mismatch'),
  assertionBmffHashMismatch('assertion.bmffHash.mismatch'),
  assertionBoxesHashMismatch('assertion.boxesHash.mismatch'),
  assertionCollectionHashMismatch('assertion.collectionHash.mismatch'),
  assertionHashedUriMismatch('assertion.hashedURI.mismatch'),
  assertionMissing('assertion.missing'),
  assertionMultipleHardBindings('assertion.multipleHardBindings'),
  assertionUndeclaredHashedUri('assertion.undeclaredHashedURI'),
  assertionRequiredMissing('assertion.requiredMissing'),
  assertionInaccessible('assertion.inaccessible'),
  assertionCloudDataHardBinding('assertion.cloudData.hardBinding'),
  assertionCloudDataActions('assertion.cloudData.actions'),
  assertionCloudDataMismatch('assertion.cloudData.mismatch'),
  assertionJsonInvalid('assertion.json.invalid'),
  assertionCborInvalid('assertion.cbor.invalid'),
  assertionActionIngredientMismatch('assertion.action.ingredientMismatch'),
  assertionActionMissing('assertion.action.missing'),
  assertionActionRedactionMissing('assertion.action.redactionMissing'),
  assertionSelfRedacted('assertion.selfRedacted'),
  assertionRedactedUriMismatch('assertion.redactedUriMismatch'),
  assertionNotRedactable('assertion.notRedactable'),
  claimMissing('claim.missing'),
  claimMultiple('claim.multiple'),
  claimHardBindingsMissing('claim.hardBindings.missing'),
  claimRequiredMissing('claim.required.missing'),
  claimCborInvalid('claim.cbor.invalid'),
  claimSignatureMismatch('claimSignature.mismatch'),
  claimSignatureMissing('claimSignature.missing'),
  manifestMissing('manifest.missing'),
  manifestMultipleParents('manifest.multipleParents'),
  manifestUpdateWrongParents('manifest.updateWrongParents'),
  manifestInaccessible('manifest.inaccessible'),
  ingredientHashedUriMismatch('ingredient.hashedURI.mismatch'),
  signingCredentialUntrusted('signingCredential.untrusted'),
  signingCredentialInvalid('signingCredential.invalid'),
  signingCredentialRevoked('signingCredential.revoked'),
  signingCredentialExpired('signingCredential.expired'),
  timestampMismatch('timeStamp.mismatch'),
  timestampUntrusted('timeStamp.untrusted'),
  timestampOutsideValidity('timeStamp.outsideValidity'),
  algorithmUnsupported('algorithm.unsupported'),
  generalError('general.error');

  const ValidationStatusCode(this.code);
  final String code;

  static ValidationStatusCode? fromCode(String code) {
    return ValidationStatusCode.values.cast<ValidationStatusCode?>().firstWhere(
      (e) => e?.code == code,
      orElse: () => null,
    );
  }
}

/// Assertion metadata
@immutable
class Metadata {
  final DateTime? dateTime;
  final String? reviewRatings;
  final DataSource? dataSource;
  final String? reference;

  const Metadata({
    this.dateTime,
    this.reviewRatings,
    this.dataSource,
    this.reference,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (dateTime != null) map['dateTime'] = dateTime!.toIso8601String();
    if (reviewRatings != null) map['reviewRatings'] = reviewRatings;
    if (dataSource != null) map['dataSource'] = dataSource!.toJson();
    if (reference != null) map['reference'] = reference;
    return map;
  }

  factory Metadata.fromJson(Map<String, dynamic> json) {
    return Metadata(
      dateTime: json['dateTime'] != null
          ? DateTime.tryParse(json['dateTime'] as String)
          : null,
      reviewRatings: json['reviewRatings'] as String?,
      dataSource: json['dataSource'] != null
          ? DataSource.fromJson(json['dataSource'] as Map<String, dynamic>)
          : null,
      reference: json['reference'] as String?,
    );
  }
}

// =============================================================================
// Action
// =============================================================================

/// An action performed on content
@immutable
class Action {
  /// The action identifier (use PredefinedAction.value or custom string)
  final String action;

  /// Digital source type URL
  final String? digitalSourceType;

  /// Software that performed the action
  final String? softwareAgent;

  /// Additional parameters
  final Map<String, String>? parameters;

  /// When the action was performed (ISO 8601)
  final String? when;

  /// Regions changed by this action
  final List<RegionOfInterest>? changes;

  /// Related ingredient labels
  final List<String>? related;

  /// Reason for the action
  final String? reason;

  const Action({
    required this.action,
    this.digitalSourceType,
    this.softwareAgent,
    this.parameters,
    this.when,
    this.changes,
    this.related,
    this.reason,
  });

  /// Create a "created" action
  factory Action.created({
    DigitalSourceType? sourceType,
    String? softwareAgent,
    String? when,
  }) {
    return Action(
      action: PredefinedAction.created.value,
      digitalSourceType: sourceType?.url,
      softwareAgent: softwareAgent,
      when: when,
    );
  }

  /// Create an "edited" action
  factory Action.edited({
    String? softwareAgent,
    List<RegionOfInterest>? changes,
    String? when,
  }) {
    return Action(
      action: PredefinedAction.edited.value,
      softwareAgent: softwareAgent,
      changes: changes,
      when: when,
    );
  }

  /// Create a "cropped" action
  factory Action.cropped({
    String? softwareAgent,
    List<RegionOfInterest>? changes,
    String? when,
  }) {
    return Action(
      action: PredefinedAction.cropped.value,
      softwareAgent: softwareAgent,
      changes: changes,
      when: when,
    );
  }

  /// Create a "filtered" action
  factory Action.filtered({
    String? softwareAgent,
    Map<String, String>? parameters,
    String? when,
  }) {
    return Action(
      action: PredefinedAction.filtered.value,
      softwareAgent: softwareAgent,
      parameters: parameters,
      when: when,
    );
  }

  /// Create a "resized" action
  factory Action.resized({
    String? softwareAgent,
    Map<String, String>? parameters,
    String? when,
  }) {
    return Action(
      action: PredefinedAction.resized.value,
      softwareAgent: softwareAgent,
      parameters: parameters,
      when: when,
    );
  }

  /// Create an "opened" action
  factory Action.opened({
    String? softwareAgent,
    List<String>? related,
    String? when,
  }) {
    return Action(
      action: PredefinedAction.opened.value,
      softwareAgent: softwareAgent,
      related: related,
      when: when,
    );
  }

  /// Create a "placed" action (for compositing)
  factory Action.placed({
    String? softwareAgent,
    List<RegionOfInterest>? changes,
    List<String>? related,
    String? when,
  }) {
    return Action(
      action: PredefinedAction.placed.value,
      softwareAgent: softwareAgent,
      changes: changes,
      related: related,
      when: when,
    );
  }

  /// Create an "AI generated" action
  factory Action.aiGenerated({
    DigitalSourceType? sourceType,
    String? softwareAgent,
    Map<String, String>? parameters,
    String? when,
  }) {
    return Action(
      action: PredefinedAction.aiGenerated.value,
      digitalSourceType: sourceType?.url,
      softwareAgent: softwareAgent,
      parameters: parameters,
      when: when,
    );
  }

  /// Create a "converted" action
  factory Action.converted({
    String? softwareAgent,
    Map<String, String>? parameters,
    String? when,
  }) {
    return Action(
      action: PredefinedAction.converted.value,
      softwareAgent: softwareAgent,
      parameters: parameters,
      when: when,
    );
  }

  /// Create a custom action
  factory Action.custom({
    required String action,
    String? digitalSourceType,
    String? softwareAgent,
    Map<String, String>? parameters,
    String? when,
    List<RegionOfInterest>? changes,
    List<String>? related,
    String? reason,
  }) {
    return Action(
      action: action,
      digitalSourceType: digitalSourceType,
      softwareAgent: softwareAgent,
      parameters: parameters,
      when: when,
      changes: changes,
      related: related,
      reason: reason,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'action': action};
    if (digitalSourceType != null) map['digitalSourceType'] = digitalSourceType;
    if (softwareAgent != null) map['softwareAgent'] = softwareAgent;
    if (parameters != null) map['parameters'] = parameters;
    if (when != null) map['when'] = when;
    if (changes != null) {
      map['changes'] = changes!.map((c) => c.toJson()).toList();
    }
    if (related != null) map['related'] = related;
    if (reason != null) map['reason'] = reason;
    return map;
  }

  factory Action.fromJson(Map<String, dynamic> json) {
    return Action(
      action: json['action'] as String,
      digitalSourceType: json['digitalSourceType'] as String?,
      softwareAgent: json['softwareAgent'] as String?,
      parameters: (json['parameters'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v as String),
      ),
      when: json['when'] as String?,
      changes: (json['changes'] as List<dynamic>?)
          ?.map((c) => RegionOfInterest.fromJson(c as Map<String, dynamic>))
          .toList(),
      related: (json['related'] as List<dynamic>?)
          ?.map((r) => r as String)
          .toList(),
      reason: json['reason'] as String?,
    );
  }
}

// =============================================================================
// Ingredient
// =============================================================================

/// An ingredient (source material) in a manifest
@immutable
class Ingredient {
  final String? title;
  final String? format;
  final Relationship? relationship;
  final ResourceRef? data;
  final ResourceRef? thumbnail;
  final ResourceRef? manifestData;
  final String? activeManifest;
  final String? hash;
  final String? description;
  final String? label;
  final List<AssetType>? dataTypes;
  final List<ValidationStatusEntry>? validationStatus;
  final ValidationResults? validationResults;
  final Metadata? metadata;
  final String? documentId;
  final String? instanceId;
  final String? provenance;
  final String? informationalUri;

  const Ingredient({
    this.title,
    this.format,
    this.relationship,
    this.data,
    this.thumbnail,
    this.manifestData,
    this.activeManifest,
    this.hash,
    this.description,
    this.label,
    this.dataTypes,
    this.validationStatus,
    this.validationResults,
    this.metadata,
    this.documentId,
    this.instanceId,
    this.provenance,
    this.informationalUri,
  });

  /// Create a parent ingredient
  factory Ingredient.parent({String? title, String? format}) {
    return Ingredient(
      title: title,
      format: format,
      relationship: Relationship.parentOf,
    );
  }

  /// Create a component ingredient
  factory Ingredient.component({String? title, String? format}) {
    return Ingredient(
      title: title,
      format: format,
      relationship: Relationship.componentOf,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (title != null) map['title'] = title;
    if (format != null) map['format'] = format;
    if (relationship != null) map['relationship'] = relationship!.toJson();
    if (data != null) map['data'] = data!.toJson();
    if (thumbnail != null) map['thumbnail'] = thumbnail!.toJson();
    if (manifestData != null) map['manifest_data'] = manifestData!.toJson();
    if (activeManifest != null) map['active_manifest'] = activeManifest;
    if (hash != null) map['hash'] = hash;
    if (description != null) map['description'] = description;
    if (label != null) map['label'] = label;
    if (dataTypes != null) {
      map['data_types'] = dataTypes!.map((t) => t.toJson()).toList();
    }
    if (validationStatus != null) {
      map['validation_status'] = validationStatus!
          .map((s) => s.toJson())
          .toList();
    }
    if (validationResults != null) {
      map['validation_results'] = validationResults!.toJson();
    }
    if (metadata != null) map['metadata'] = metadata!.toJson();
    if (documentId != null) map['document_id'] = documentId;
    if (instanceId != null) map['instance_id'] = instanceId;
    if (provenance != null) map['provenance'] = provenance;
    if (informationalUri != null) map['informational_uri'] = informationalUri;
    return map;
  }

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    return Ingredient(
      title: json['title'] as String?,
      format: json['format'] as String?,
      relationship: json['relationship'] != null
          ? Relationship.fromJson(json['relationship'] as String)
          : null,
      data: json['data'] != null
          ? ResourceRef.fromJson(json['data'] as Map<String, dynamic>)
          : null,
      thumbnail: json['thumbnail'] != null
          ? ResourceRef.fromJson(json['thumbnail'] as Map<String, dynamic>)
          : null,
      manifestData: json['manifest_data'] != null
          ? ResourceRef.fromJson(json['manifest_data'] as Map<String, dynamic>)
          : null,
      activeManifest: json['active_manifest'] as String?,
      hash: json['hash'] as String?,
      description: json['description'] as String?,
      label: json['label'] as String?,
      dataTypes: (json['data_types'] as List<dynamic>?)
          ?.map((t) => AssetType.fromJson(t as Map<String, dynamic>))
          .toList(),
      validationStatus: (json['validation_status'] as List<dynamic>?)
          ?.map(
            (s) => ValidationStatusEntry.fromJson(s as Map<String, dynamic>),
          )
          .toList(),
      validationResults: json['validation_results'] != null
          ? ValidationResults.fromJson(
              json['validation_results'] as Map<String, dynamic>,
            )
          : null,
      metadata: json['metadata'] != null
          ? Metadata.fromJson(json['metadata'] as Map<String, dynamic>)
          : null,
      documentId: json['document_id'] as String?,
      instanceId: json['instance_id'] as String?,
      provenance: json['provenance'] as String?,
      informationalUri: json['informational_uri'] as String?,
    );
  }
}

// =============================================================================
// Claim Generator Info
// =============================================================================

/// Information about the software that created the manifest
@immutable
class ClaimGeneratorInfo {
  final String name;
  final String? version;
  final Map<String, String>? icon;

  const ClaimGeneratorInfo({required this.name, this.version, this.icon});

  /// Format as claim generator string (name/version or just name)
  String get claimGeneratorString => version != null ? '$name/$version' : name;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'name': name};
    if (version != null) map['version'] = version;
    if (icon != null) map['icon'] = icon;
    return map;
  }

  factory ClaimGeneratorInfo.fromJson(Map<String, dynamic> json) {
    return ClaimGeneratorInfo(
      name: json['name'] as String,
      version: json['version'] as String?,
      icon: (json['icon'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v as String),
      ),
    );
  }
}

// =============================================================================
// Training/Mining Entry
// =============================================================================

/// Entry for AI training/mining permissions
@immutable
class TrainingMiningEntry {
  final String use;
  final TrainingMiningPermission permission;
  final String? constraintInfo;

  const TrainingMiningEntry({
    required this.use,
    required this.permission,
    this.constraintInfo,
  });

  /// Create an entry for data mining permission
  factory TrainingMiningEntry.dataMining({
    required TrainingMiningPermission permission,
    String? constraintInfo,
  }) {
    return TrainingMiningEntry(
      use: 'dataMining',
      permission: permission,
      constraintInfo: constraintInfo,
    );
  }

  /// Create an entry for AI/ML inference permission
  factory TrainingMiningEntry.aiInference({
    required TrainingMiningPermission permission,
    String? constraintInfo,
  }) {
    return TrainingMiningEntry(
      use: 'aiInference',
      permission: permission,
      constraintInfo: constraintInfo,
    );
  }

  /// Create an entry for AI/ML training permission
  factory TrainingMiningEntry.aiTraining({
    required TrainingMiningPermission permission,
    String? constraintInfo,
  }) {
    return TrainingMiningEntry(
      use: 'aiTraining',
      permission: permission,
      constraintInfo: constraintInfo,
    );
  }

  /// Create an entry for AI generative training permission
  factory TrainingMiningEntry.aiGenerativeTraining({
    required TrainingMiningPermission permission,
    String? constraintInfo,
  }) {
    return TrainingMiningEntry(
      use: 'aiGenerativeTraining',
      permission: permission,
      constraintInfo: constraintInfo,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'use': use, permission.value: true};
    if (constraintInfo != null) map['constraint_info'] = constraintInfo;
    return map;
  }

  factory TrainingMiningEntry.fromJson(Map<String, dynamic> json) {
    TrainingMiningPermission permission;
    if (json['allowed'] == true) {
      permission = TrainingMiningPermission.allowed;
    } else if (json['constrained'] == true) {
      permission = TrainingMiningPermission.constrained;
    } else {
      permission = TrainingMiningPermission.notAllowed;
    }

    return TrainingMiningEntry(
      use: json['use'] as String,
      permission: permission,
      constraintInfo: json['constraint_info'] as String?,
    );
  }
}

// =============================================================================
// Assertions
// =============================================================================

/// Base class for assertion definitions
@immutable
sealed class AssertionDefinition {
  const AssertionDefinition();

  /// The assertion label
  String get label;

  Map<String, dynamic> toJson();

  static AssertionDefinition fromJson(Map<String, dynamic> json) {
    final label = json['label'] as String;
    final data = json['data'] as Map<String, dynamic>;

    if (label == StandardAssertionLabel.actions.value) {
      return ActionsAssertion.fromData(data);
    } else if (label == StandardAssertionLabel.creativeWork.value) {
      return CreativeWorkAssertion.fromData(data);
    } else if (label == StandardAssertionLabel.exif.value) {
      return ExifAssertion.fromData(data);
    } else if (label == StandardAssertionLabel.iptcPhotoMetadata.value) {
      return IptcPhotoMetadataAssertion.fromData(data);
    } else if (label == StandardAssertionLabel.trainingMining.value) {
      return TrainingMiningAssertion.fromData(data);
    } else if (label == StandardAssertionLabel.cawgIdentity.value) {
      return CawgIdentityAssertion.fromData(data);
    } else if (label == StandardAssertionLabel.cawgTrainingMining.value) {
      return CawgTrainingMiningAssertion.fromData(data);
    } else {
      return CustomAssertion(label: label, data: data);
    }
  }
}

/// Actions assertion
@immutable
class ActionsAssertion extends AssertionDefinition {
  @override
  String get label => StandardAssertionLabel.actions.value;

  final List<Action> actions;
  final Metadata? metadata;

  const ActionsAssertion({required this.actions, this.metadata});

  @override
  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'data': {
        'actions': actions.map((a) => a.toJson()).toList(),
        if (metadata != null) 'metadata': metadata!.toJson(),
      },
    };
  }

  factory ActionsAssertion.fromData(Map<String, dynamic> data) {
    return ActionsAssertion(
      actions: (data['actions'] as List<dynamic>)
          .map((a) => Action.fromJson(a as Map<String, dynamic>))
          .toList(),
      metadata: data['metadata'] != null
          ? Metadata.fromJson(data['metadata'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Creative work assertion (schema.org)
@immutable
class CreativeWorkAssertion extends AssertionDefinition {
  @override
  String get label => StandardAssertionLabel.creativeWork.value;

  final String? context;
  final String? type;
  final String? author;
  final String? copyrightNotice;
  final String? creator;
  final String? license;
  final Map<String, dynamic>? additionalData;

  const CreativeWorkAssertion({
    this.context = 'https://schema.org/',
    this.type = 'CreativeWork',
    this.author,
    this.copyrightNotice,
    this.creator,
    this.license,
    this.additionalData,
  });

  @override
  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
      '@context': context ?? 'https://schema.org/',
      '@type': type ?? 'CreativeWork',
    };
    if (author != null) data['author'] = author;
    if (copyrightNotice != null) data['copyrightNotice'] = copyrightNotice;
    if (creator != null) data['creator'] = creator;
    if (license != null) data['license'] = license;
    if (additionalData != null) data.addAll(additionalData!);
    return {'label': label, 'data': data};
  }

  factory CreativeWorkAssertion.fromData(Map<String, dynamic> data) {
    final knownKeys = {
      '@context',
      '@type',
      'author',
      'copyrightNotice',
      'creator',
      'license',
    };
    final additional = Map<String, dynamic>.from(data)
      ..removeWhere((k, _) => knownKeys.contains(k));

    return CreativeWorkAssertion(
      context: data['@context'] as String?,
      type: data['@type'] as String?,
      author: data['author'] as String?,
      copyrightNotice: data['copyrightNotice'] as String?,
      creator: data['creator'] as String?,
      license: data['license'] as String?,
      additionalData: additional.isEmpty ? null : additional,
    );
  }
}

/// EXIF metadata assertion
@immutable
class ExifAssertion extends AssertionDefinition {
  @override
  String get label => StandardAssertionLabel.exif.value;

  final Map<String, dynamic> data;

  const ExifAssertion({required this.data});

  @override
  Map<String, dynamic> toJson() => {'label': label, 'data': data};

  factory ExifAssertion.fromData(Map<String, dynamic> data) {
    return ExifAssertion(data: data);
  }
}

/// IPTC Photo Metadata assertion
@immutable
class IptcPhotoMetadataAssertion extends AssertionDefinition {
  @override
  String get label => StandardAssertionLabel.iptcPhotoMetadata.value;

  final Map<String, dynamic> data;

  const IptcPhotoMetadataAssertion({required this.data});

  @override
  Map<String, dynamic> toJson() => {'label': label, 'data': data};

  factory IptcPhotoMetadataAssertion.fromData(Map<String, dynamic> data) {
    return IptcPhotoMetadataAssertion(data: data);
  }
}

/// Training/mining permission assertion
@immutable
class TrainingMiningAssertion extends AssertionDefinition {
  @override
  String get label => StandardAssertionLabel.trainingMining.value;

  final List<TrainingMiningEntry> entries;
  final Metadata? metadata;

  const TrainingMiningAssertion({required this.entries, this.metadata});

  @override
  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'data': {
        'entries': entries.map((e) => e.toJson()).toList(),
        if (metadata != null) 'metadata': metadata!.toJson(),
      },
    };
  }

  factory TrainingMiningAssertion.fromData(Map<String, dynamic> data) {
    return TrainingMiningAssertion(
      entries: (data['entries'] as List<dynamic>)
          .map((e) => TrainingMiningEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      metadata: data['metadata'] != null
          ? Metadata.fromJson(data['metadata'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Custom assertion with arbitrary data
@immutable
class CustomAssertion extends AssertionDefinition {
  @override
  final String label;

  final Map<String, dynamic> data;

  const CustomAssertion({required this.label, required this.data});

  @override
  Map<String, dynamic> toJson() => {'label': label, 'data': data};
}

/// CAWG identity assertion
///
/// Per the CAWG specification, identity assertions MUST be placed in
/// [ManifestDefinition.gatheredAssertions], not in [ManifestDefinition.assertions].
@immutable
class CawgIdentityAssertion extends AssertionDefinition {
  @override
  String get label => StandardAssertionLabel.cawgIdentity.value;

  final Map<String, dynamic> data;

  const CawgIdentityAssertion({required this.data});

  @override
  Map<String, dynamic> toJson() => {'label': label, 'data': data};

  factory CawgIdentityAssertion.fromData(Map<String, dynamic> data) {
    return CawgIdentityAssertion(data: data);
  }
}

/// CAWG AI training and data mining assertion
@immutable
class CawgTrainingMiningAssertion extends AssertionDefinition {
  @override
  String get label => StandardAssertionLabel.cawgTrainingMining.value;

  final List<CawgTrainingMiningEntry> entries;
  final Metadata? metadata;

  const CawgTrainingMiningAssertion({required this.entries, this.metadata});

  @override
  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'data': {
        'entries': entries.map((e) => e.toJson()).toList(),
        if (metadata != null) 'metadata': metadata!.toJson(),
      },
    };
  }

  factory CawgTrainingMiningAssertion.fromData(Map<String, dynamic> data) {
    return CawgTrainingMiningAssertion(
      entries: (data['entries'] as List<dynamic>)
          .map(
            (e) =>
                CawgTrainingMiningEntry.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      metadata: data['metadata'] != null
          ? Metadata.fromJson(data['metadata'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Entry for CAWG AI training and data mining permissions
@immutable
class CawgTrainingMiningEntry {
  final String use;
  final TrainingMiningPermission permission;
  final String? constraintInfo;
  final String? aiModelLearningType;
  final String? aiMiningType;

  const CawgTrainingMiningEntry({
    required this.use,
    required this.permission,
    this.constraintInfo,
    this.aiModelLearningType,
    this.aiMiningType,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'use': use, permission.value: true};
    if (constraintInfo != null) map['constraint_info'] = constraintInfo;
    if (aiModelLearningType != null) {
      map['ai_model_learning_type'] = aiModelLearningType;
    }
    if (aiMiningType != null) map['ai_mining_type'] = aiMiningType;
    return map;
  }

  factory CawgTrainingMiningEntry.fromJson(Map<String, dynamic> json) {
    TrainingMiningPermission permission;
    if (json['allowed'] == true) {
      permission = TrainingMiningPermission.allowed;
    } else if (json['constrained'] == true) {
      permission = TrainingMiningPermission.constrained;
    } else {
      permission = TrainingMiningPermission.notAllowed;
    }

    return CawgTrainingMiningEntry(
      use: json['use'] as String,
      permission: permission,
      constraintInfo: json['constraint_info'] as String?,
      aiModelLearningType: json['ai_model_learning_type'] as String?,
      aiMiningType: json['ai_mining_type'] as String?,
    );
  }
}

// =============================================================================
// Manifest Definition
// =============================================================================

/// Complete manifest definition for building C2PA manifests
@immutable
class ManifestDefinition {
  final String title;
  final List<ClaimGeneratorInfo> claimGeneratorInfo;
  final List<AssertionDefinition> assertions;
  final List<AssertionDefinition> gatheredAssertions;
  final List<Ingredient> ingredients;
  final ResourceRef? thumbnail;
  final String? format;
  final String? vendor;
  final String? label;
  final String? instanceId;
  final List<String>? redactions;
  final int claimVersion;

  const ManifestDefinition({
    required this.title,
    required this.claimGeneratorInfo,
    this.assertions = const [],
    this.gatheredAssertions = const [],
    this.ingredients = const [],
    this.thumbnail,
    this.format,
    this.vendor,
    this.label,
    this.instanceId,
    this.redactions,
    this.claimVersion = 2,
  });

  /// Create a manifest for new content creation
  factory ManifestDefinition.created({
    required String title,
    required ClaimGeneratorInfo claimGenerator,
    required DigitalSourceType sourceType,
    String? softwareAgent,
    List<AssertionDefinition>? additionalAssertions,
  }) {
    final actions = [
      Action.created(
        sourceType: sourceType,
        softwareAgent: softwareAgent ?? claimGenerator.claimGeneratorString,
        when: DateTime.now().toUtc().toIso8601String(),
      ),
    ];

    return ManifestDefinition(
      title: title,
      claimGeneratorInfo: [claimGenerator],
      assertions: [
        ActionsAssertion(actions: actions),
        if (additionalAssertions != null) ...additionalAssertions,
      ],
    );
  }

  /// Create a manifest for edited content
  factory ManifestDefinition.edited({
    required String title,
    required ClaimGeneratorInfo claimGenerator,
    List<Action>? actions,
    List<AssertionDefinition>? additionalAssertions,
  }) {
    final editActions =
        actions ??
        [
          Action.edited(
            softwareAgent: claimGenerator.claimGeneratorString,
            when: DateTime.now().toUtc().toIso8601String(),
          ),
        ];

    return ManifestDefinition(
      title: title,
      claimGeneratorInfo: [claimGenerator],
      assertions: [
        ActionsAssertion(actions: editActions),
        if (additionalAssertions != null) ...additionalAssertions,
      ],
    );
  }

  /// Create a manifest for AI-generated content
  factory ManifestDefinition.aiGenerated({
    required String title,
    required ClaimGeneratorInfo claimGenerator,
    DigitalSourceType sourceType = DigitalSourceType.trainedAlgorithmicMedia,
    Map<String, String>? parameters,
    TrainingMiningAssertion? trainingMining,
    List<AssertionDefinition>? additionalAssertions,
  }) {
    return ManifestDefinition(
      title: title,
      claimGeneratorInfo: [claimGenerator],
      assertions: [
        ActionsAssertion(
          actions: [
            Action.aiGenerated(
              sourceType: sourceType,
              softwareAgent: claimGenerator.claimGeneratorString,
              parameters: parameters,
              when: DateTime.now().toUtc().toIso8601String(),
            ),
          ],
        ),
        if (trainingMining != null) trainingMining,
        if (additionalAssertions != null) ...additionalAssertions,
      ],
    );
  }

  /// Create a manifest with explicit created and gathered assertion separation
  factory ManifestDefinition.withAssertions({
    required String title,
    required ClaimGeneratorInfo claimGenerator,
    List<AssertionDefinition> createdAssertions = const [],
    List<AssertionDefinition> gatheredAssertions = const [],
    List<Ingredient> ingredients = const [],
  }) {
    return ManifestDefinition(
      title: title,
      claimGeneratorInfo: [claimGenerator],
      assertions: createdAssertions,
      gatheredAssertions: gatheredAssertions,
      ingredients: ingredients,
    );
  }

  /// Create a manifest with CAWG identity assertions in gathered assertions
  factory ManifestDefinition.withCawgIdentity({
    required String title,
    required ClaimGeneratorInfo claimGenerator,
    required List<AssertionDefinition> identityAssertions,
    List<AssertionDefinition>? createdAssertions,
    List<Ingredient> ingredients = const [],
  }) {
    return ManifestDefinition(
      title: title,
      claimGeneratorInfo: [claimGenerator],
      assertions: createdAssertions ?? const [],
      gatheredAssertions: identityAssertions,
      ingredients: ingredients,
    );
  }

  /// Convert to JSON string for the platform API
  String toJsonString() => jsonEncode(toJson());

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'title': title,
      'claim_generator_info': claimGeneratorInfo
          .map((c) => c.toJson())
          .toList(),
    };

    // Add claim_generator string for compatibility
    if (claimGeneratorInfo.isNotEmpty) {
      map['claim_generator'] = claimGeneratorInfo.first.claimGeneratorString;
    }

    if (assertions.isNotEmpty) {
      map['assertions'] = assertions.map((a) => a.toJson()).toList();
    }

    if (gatheredAssertions.isNotEmpty) {
      map['gathered_assertions'] =
          gatheredAssertions.map((a) => a.toJson()).toList();
    }

    if (ingredients.isNotEmpty) {
      map['ingredients'] = ingredients.map((i) => i.toJson()).toList();
    }

    if (thumbnail != null) map['thumbnail'] = thumbnail!.toJson();
    if (format != null) map['format'] = format;
    if (vendor != null) map['vendor'] = vendor;
    if (label != null) map['label'] = label;
    if (instanceId != null) map['instance_id'] = instanceId;
    if (redactions != null) map['redactions'] = redactions;
    if (claimVersion != 2) map['claim_version'] = claimVersion;

    return map;
  }

  factory ManifestDefinition.fromJson(String json) {
    return ManifestDefinition.fromMap(jsonDecode(json) as Map<String, dynamic>);
  }

  factory ManifestDefinition.fromMap(Map<String, dynamic> map) {
    return ManifestDefinition(
      title: map['title'] as String,
      claimGeneratorInfo:
          (map['claim_generator_info'] as List<dynamic>?)
              ?.map(
                (c) => ClaimGeneratorInfo.fromJson(c as Map<String, dynamic>),
              )
              .toList() ??
          [],
      assertions:
          (map['assertions'] as List<dynamic>?)
              ?.map(
                (a) => AssertionDefinition.fromJson(a as Map<String, dynamic>),
              )
              .toList() ??
          [],
      gatheredAssertions:
          (map['gathered_assertions'] as List<dynamic>?)
              ?.map(
                (a) => AssertionDefinition.fromJson(a as Map<String, dynamic>),
              )
              .toList() ??
          [],
      ingredients:
          (map['ingredients'] as List<dynamic>?)
              ?.map((i) => Ingredient.fromJson(i as Map<String, dynamic>))
              .toList() ??
          [],
      thumbnail: map['thumbnail'] != null
          ? ResourceRef.fromJson(map['thumbnail'] as Map<String, dynamic>)
          : null,
      format: map['format'] as String?,
      vendor: map['vendor'] as String?,
      label: map['label'] as String?,
      instanceId: map['instance_id'] as String?,
      redactions: (map['redactions'] as List<dynamic>?)
          ?.cast<String>()
          .toList(),
      claimVersion: map['claim_version'] as int? ?? 2,
    );
  }
}
