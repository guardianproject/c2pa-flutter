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

import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Phase of a C2PA operation reported through a context's progress callback.
enum C2paProgressPhase {
  reading,
  verifyingManifest,
  verifyingSignature,
  verifyingIngredient,
  verifyingAssetHash,
  addingIngredient,
  thumbnail,
  hashing,
  signing,
  embedding,
  fetchingRemoteManifest,
  writing,
  fetchingOcsp,
  fetchingTimestamp,

  /// A phase the native SDK reported that this version does not know.
  unknown;

  /// Parses the phase name sent by the native side.
  static C2paProgressPhase fromName(String? name) {
    for (final phase in values) {
      if (phase.name == name) return phase;
    }
    return unknown;
  }
}

/// A progress report from a C2PA operation running on a `C2paContext`.
///
/// [step] counts up from 1 within a phase. [total] is 0 when the amount of
/// work is unknown, 1 for a single-shot phase, and the number of steps
/// otherwise, in which case `step / total` is the fraction complete.
@immutable
class C2paProgress {
  final C2paProgressPhase phase;
  final int step;
  final int total;

  const C2paProgress({
    required this.phase,
    required this.step,
    required this.total,
  });

  /// Fraction complete in [0, 1], or null when [total] does not allow one.
  double? get fraction =>
      total > 1 ? (step / total).clamp(0, 1).toDouble() : null;

  factory C2paProgress.fromMap(Map<dynamic, dynamic> map) {
    return C2paProgress(
      phase: C2paProgressPhase.fromName(map['phase'] as String?),
      step: (map['step'] as num?)?.toInt() ?? 0,
      total: (map['total'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  String toString() => 'C2paProgress(${phase.name}, $step/$total)';
}

/// An HTTP request the C2PA SDK needs answered: a remote manifest fetch, an
/// OCSP query or a timestamp request.
@immutable
class C2paHttpRequest {
  final String url;
  final String method;
  final Map<String, String> headers;
  final Uint8List? body;

  const C2paHttpRequest({
    required this.url,
    required this.method,
    this.headers = const {},
    this.body,
  });

  factory C2paHttpRequest.fromMap(Map<dynamic, dynamic> map) {
    final rawHeaders = map['headers'] as Map<dynamic, dynamic>? ?? const {};
    return C2paHttpRequest(
      url: map['url'] as String,
      method: map['method'] as String? ?? 'GET',
      headers: rawHeaders.map((k, v) => MapEntry(k.toString(), v.toString())),
      body: map['body'] as Uint8List?,
    );
  }
}

/// The answer to a [C2paHttpRequest].
@immutable
class C2paHttpResponse {
  final int status;
  final Uint8List? body;

  const C2paHttpResponse({required this.status, this.body});

  Map<String, dynamic> toMap() => {'status': status, 'body': body};
}

/// How a `C2paContext` performs the HTTP requests the SDK makes.
sealed class C2paHttpResolver {
  const C2paHttpResolver();
}

/// Uses the platform HTTP client: `URLSession` on iOS, OkHttp on Android.
class NativeHttpResolver extends C2paHttpResolver {
  const NativeHttpResolver();
}

/// Routes every SDK HTTP request through a Dart callback, for example to add
/// authentication, use an app-wide client, or serve requests offline.
///
/// The SDK waits for the callback, so it must always complete. Throwing fails
/// the request (and usually the operation that made it).
class CallbackHttpResolver extends C2paHttpResolver {
  final Future<C2paHttpResponse> Function(C2paHttpRequest request) resolve;

  const CallbackHttpResolver(this.resolve);
}

/// How a format binds the manifest to the asset's bytes.
enum C2paHashType {
  /// Placeholder, exclusions, hash, sign (JPEG, PNG and similar).
  dataHash,

  /// Placeholder, hash, sign (MP4, AVIF, HEIF/HEIC).
  bmffHash,

  /// Hash and sign with no placeholder.
  boxHash;

  static C2paHashType fromName(String name) {
    for (final type in values) {
      if (type.name == name) return type;
    }
    throw ArgumentError.value(name, 'name', 'Unknown hash type');
  }
}

/// A byte range of the asset left out of the data hash, normally the range
/// the placeholder manifest occupies.
@immutable
class DataHashExclusion {
  final int start;
  final int length;

  const DataHashExclusion({required this.start, required this.length});

  List<int> toList() => [start, length];

  @override
  bool operator ==(Object other) =>
      other is DataHashExclusion &&
      other.start == start &&
      other.length == length;

  @override
  int get hashCode => Object.hash(start, length);

  @override
  String toString() => 'DataHashExclusion($start, $length)';
}
