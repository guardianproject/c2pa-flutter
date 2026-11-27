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

import 'package:flutter/services.dart';

/// An error reported by the C2PA plugin or the native C2PA SDK.
///
/// Every failure of a plugin call arrives as one of the subclasses, so
/// callers can match on the case they care about:
///
/// ```dart
/// try {
///   final store = await c2pa.readManifestFromFile(path);
/// } on C2paManifestNotFoundException {
///   // The asset carries no content credentials.
/// } on C2paException catch (e) {
///   print('C2PA failed: ${e.message}');
/// }
/// ```
///
/// Misuse of the Dart API itself (a disposed builder, conflicting arguments)
/// throws an [Error] such as [StateError] or [ArgumentError] instead.
sealed class C2paException implements Exception {
  const C2paException(this.code, this.message);

  /// The code the native plugin reported, for example `C2PA_ERROR` or
  /// `INVALID_ARGUMENT`.
  final String code;

  /// The error message from the plugin or the native SDK.
  final String message;

  /// Maps a [PlatformException] from the platform channel to the matching
  /// [C2paException].
  factory C2paException.fromPlatformException(PlatformException e) {
    final code = e.code;
    final message = e.message ?? code;
    switch (code) {
      case 'C2PA_ERROR':
        if (_isManifestNotFound(message)) {
          return C2paManifestNotFoundException(message);
        }
        if (_isCancelled(message)) return C2paCancelledException(message);
        return C2paSdkException(message);
      case 'INVALID_ARGUMENT':
      case 'INVALID_HANDLE':
        return C2paInvalidArgumentException(code, message);
      case 'NOT_IMPLEMENTED_IOS':
      case 'NOT_IMPLEMENTED_ANDROID':
      case 'NOT_AVAILABLE':
        return C2paUnsupportedException(code, message);
      case 'KEY_NOT_FOUND':
      case 'ENROLLMENT_ERROR':
        return C2paKeyException(code, message);
      default:
        return C2paPlatformException(code, message);
    }
  }

  static bool _isManifestNotFound(String message) =>
      message.contains('ManifestNotFound') ||
      message.contains('JumbfNotFound') ||
      message.contains('no JUMBF data found');

  static bool _isCancelled(String message) =>
      message.contains('OperationCancelled') ||
      message.toLowerCase().contains('cancelled');

  @override
  String toString() => '$runtimeType($code): $message';
}

/// The asset has no C2PA manifest: nothing is embedded and no remote
/// manifest is referenced.
final class C2paManifestNotFoundException extends C2paException {
  const C2paManifestNotFoundException(String message)
    : super('C2PA_ERROR', message);
}

/// The operation was stopped by `C2paContext.cancel`.
final class C2paCancelledException extends C2paException {
  const C2paCancelledException(String message) : super('C2PA_ERROR', message);
}

/// Any other error from the native C2PA SDK: an invalid manifest, a
/// certificate the SDK rejects, an unsupported format, and so on.
final class C2paSdkException extends C2paException {
  const C2paSdkException(String message) : super('C2PA_ERROR', message);
}

/// The plugin rejected an argument, for example a missing file or a handle
/// that has already been released.
final class C2paInvalidArgumentException extends C2paException {
  const C2paInvalidArgumentException(super.code, super.message);
}

/// The operation is not available on this platform or device. [code] is
/// `NOT_IMPLEMENTED_IOS`, `NOT_IMPLEMENTED_ANDROID` or `NOT_AVAILABLE`.
final class C2paUnsupportedException extends C2paException {
  const C2paUnsupportedException(super.code, super.message);
}

/// A key-management operation failed: the key does not exist
/// (`KEY_NOT_FOUND`) or certificate enrollment was refused
/// (`ENROLLMENT_ERROR`).
final class C2paKeyException extends C2paException {
  const C2paKeyException(super.code, super.message);
}

/// Any other failure inside the plugin or the platform.
final class C2paPlatformException extends C2paException {
  const C2paPlatformException(super.code, super.message);
}
