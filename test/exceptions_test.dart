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

import 'package:c2pa_flutter/c2pa.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

C2paException _map(String code, String message) =>
    C2paException.fromPlatformException(
      PlatformException(code: code, message: message),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('C2paException.fromPlatformException', () {
    test('maps the SDK messages for a missing manifest', () {
      for (final message in [
        'C2PA API error: ManifestNotFound: no JUMBF data found',
        'JumbfNotFound',
        'no JUMBF data found',
      ]) {
        expect(
          _map('C2PA_ERROR', message),
          isA<C2paManifestNotFoundException>(),
          reason: message,
        );
      }
    });

    test('maps cancellation', () {
      expect(
        _map('C2PA_ERROR', 'OperationCancelled'),
        isA<C2paCancelledException>(),
      );
    });

    test('maps other SDK errors', () {
      final e = _map('C2PA_ERROR', 'ClaimEncoding: bad claim');
      expect(e, isA<C2paSdkException>());
      expect(e.code, 'C2PA_ERROR');
      expect(e.message, 'ClaimEncoding: bad claim');
    });

    test('maps plugin codes', () {
      expect(
        _map('INVALID_ARGUMENT', 'x'),
        isA<C2paInvalidArgumentException>(),
      );
      expect(_map('INVALID_HANDLE', 'x'), isA<C2paInvalidArgumentException>());
      expect(_map('NOT_IMPLEMENTED_IOS', 'x'), isA<C2paUnsupportedException>());
      expect(
        _map('NOT_IMPLEMENTED_ANDROID', 'x'),
        isA<C2paUnsupportedException>(),
      );
      expect(_map('NOT_AVAILABLE', 'x'), isA<C2paUnsupportedException>());
      expect(_map('KEY_NOT_FOUND', 'x'), isA<C2paKeyException>());
      expect(_map('ENROLLMENT_ERROR', 'x'), isA<C2paKeyException>());
      expect(_map('ERROR', 'x'), isA<C2paPlatformException>());
    });

    test('falls back to the code when there is no message', () {
      final e = C2paException.fromPlatformException(
        PlatformException(code: 'ERROR'),
      );
      expect(e.message, 'ERROR');
    });
  });

  group('ManifestStoreInfo validation', () {
    test('uses validation_state when present', () {
      ValidationStatus statusOf(Map<String, dynamic> map) =>
          ManifestStoreInfo.fromMap(map).validationStatus;

      expect(
        statusOf({'validation_state': 'Trusted'}),
        ValidationStatus.trusted,
      );
      expect(statusOf({'validation_state': 'Valid'}), ValidationStatus.valid);
      expect(
        statusOf({'validation_state': 'Invalid'}),
        ValidationStatus.invalid,
      );
      expect(
        statusOf({
          'validation_state': 'Valid',
          'validation_status': [
            {'code': 'signingCredential.untrusted'},
          ],
        }),
        ValidationStatus.valid,
      );
    });

    test('falls back to validation_status without validation_state', () {
      expect(
        ManifestStoreInfo.fromMap({'validation_status': <Object>[]})
            .validationStatus,
        ValidationStatus.valid,
      );
      expect(
        ManifestStoreInfo.fromMap({
          'validation_status': [
            {'code': 'claimSignature.mismatch'},
          ],
        }).validationStatus,
        ValidationStatus.invalid,
      );
      expect(
        ManifestStoreInfo.fromMap(<String, dynamic>{}).validationStatus,
        ValidationStatus.unknown,
      );
    });

    test('an ingredient links to its manifest by label', () {
      final ingredient = IngredientInfo.fromMap({
        'title': 'parent.jpg',
        'relationship': 'parentOf',
        'active_manifest': 'urn:c2pa:parent',
        'manifest': 'urn:c2pa:parent',
      });
      expect(ingredient.activeManifest, 'urn:c2pa:parent');
      expect(ingredient.manifest, isNull);
      expect(ingredient.relationship, Relationship.parentOf);
    });

    test('the claim generator falls back to claim_generator_info', () {
      expect(
        ManifestInfo.fromMap({
          'claim_generator_info': [
            {'name': 'app', 'version': '1.0'},
            {'name': 'c2pa-rs'},
          ],
        }).claimGenerator,
        'app/1.0 c2pa-rs',
      );
      expect(
        ManifestInfo.fromMap({'claim_generator': 'legacy/2'}).claimGenerator,
        'legacy/2',
      );
      expect(ManifestInfo.fromMap(<String, dynamic>{}).claimGenerator, isNull);
    });

    test('an unknown signature algorithm parses as null', () {
      expect(
        SignatureInfo.fromMap({'alg': 'Es384'}).algorithm,
        SigningAlgorithm.es384,
      );
      expect(SignatureInfo.fromMap({'alg': 'rs256'}).algorithm, isNull);
    });
  });
}
