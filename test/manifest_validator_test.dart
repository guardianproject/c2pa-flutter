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

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:c2pa_flutter/c2pa.dart';

void main() {
  // =============================================================================
  // Helpers
  // =============================================================================

  ClaimGeneratorInfo testGenerator() =>
      ClaimGeneratorInfo(name: 'TestApp', version: '1.0');

  ManifestDefinition validManifest({
    String title = 'Test Image',
    List<ClaimGeneratorInfo>? generators,
    List<AssertionDefinition> assertions = const [],
    List<AssertionDefinition> gatheredAssertions = const [],
    List<Ingredient> ingredients = const [],
    int claimVersion = 2,
  }) {
    return ManifestDefinition(
      title: title,
      claimGeneratorInfo: generators ?? [testGenerator()],
      assertions: assertions,
      gatheredAssertions: gatheredAssertions,
      ingredients: ingredients,
      claimVersion: claimVersion,
    );
  }

  // =============================================================================
  // ValidationResult
  // =============================================================================

  group('ValidationResult', () {
    test('default constructor has empty lists', () {
      const result = ValidationResult();
      expect(result.errors, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('isValid is true when no errors', () {
      const result = ValidationResult();
      expect(result.isValid, isTrue);
    });

    test('isValid is false when has errors', () {
      const result = ValidationResult(errors: ['something went wrong']);
      expect(result.isValid, isFalse);
    });

    test('hasErrors returns true when errors list is non-empty', () {
      const result = ValidationResult(errors: ['err']);
      expect(result.hasErrors, isTrue);
    });

    test('hasErrors returns false when errors list is empty', () {
      const result = ValidationResult();
      expect(result.hasErrors, isFalse);
    });

    test('hasWarnings returns true when warnings list is non-empty', () {
      const result = ValidationResult(warnings: ['warn']);
      expect(result.hasWarnings, isTrue);
    });

    test('hasWarnings returns false when warnings list is empty', () {
      const result = ValidationResult();
      expect(result.hasWarnings, isFalse);
    });
  });

  // =============================================================================
  // ManifestValidator.validate()
  // =============================================================================

  group('ManifestValidator.validate()', () {
    test('valid manifest with all required fields passes', () {
      final manifest = validManifest();
      final result = ManifestValidator.validate(manifest);
      expect(result.isValid, isTrue);
      expect(result.hasErrors, isFalse);
    });

    test('empty title produces error', () {
      final manifest = validManifest(title: '');
      final result = ManifestValidator.validate(manifest);
      expect(result.hasErrors, isTrue);
      expect(result.errors, contains('Manifest title is required'));
    });

    test('empty claimGeneratorInfo produces error', () {
      final manifest = validManifest(generators: []);
      final result = ManifestValidator.validate(manifest);
      expect(result.hasErrors, isTrue);
      expect(
        result.errors,
        contains('At least one claim_generator_info entry is required'),
      );
    });

    test('both empty title and empty claimGeneratorInfo produce errors', () {
      final manifest = validManifest(title: '', generators: []);
      final result = ManifestValidator.validate(manifest);
      expect(result.errors.length, equals(2));
      expect(result.errors, contains('Manifest title is required'));
      expect(
        result.errors,
        contains('At least one claim_generator_info entry is required'),
      );
    });

    test('non-v2 claimVersion produces warning', () {
      final manifest = validManifest(claimVersion: 1);
      final result = ManifestValidator.validate(manifest);
      expect(result.hasWarnings, isTrue);
      expect(
        result.warnings.any((w) => w.contains('claim_version is 1')),
        isTrue,
      );
    });

    test('v2 claimVersion produces no warning', () {
      final manifest = validManifest(claimVersion: 2);
      final result = ManifestValidator.validate(manifest);
      expect(result.warnings.any((w) => w.contains('claim_version')), isFalse);
    });

    test(
      'deprecated assertion stds.exif in assertions produces warning with correct message',
      () {
        final manifest = validManifest(
          assertions: [
            ExifAssertion(data: {'key': 'value'}),
          ],
        );
        final result = ManifestValidator.validate(manifest);
        expect(result.hasWarnings, isTrue);
        expect(
          result.warnings.any(
            (w) =>
                w.contains("'stds.exif'") &&
                w.contains('deprecated') &&
                w.contains('c2pa.metadata'),
          ),
          isTrue,
        );
      },
    );

    test('deprecated assertion stds.iptc.photo-metadata produces warning', () {
      final manifest = validManifest(
        assertions: [
          IptcPhotoMetadataAssertion(data: {'key': 'value'}),
        ],
      );
      final result = ManifestValidator.validate(manifest);
      expect(result.hasWarnings, isTrue);
      expect(
        result.warnings.any(
          (w) =>
              w.contains("'stds.iptc.photo-metadata'") &&
              w.contains('deprecated'),
        ),
        isTrue,
      );
    });

    test(
      'deprecated assertion stds.schema-org.CreativeWork produces warning',
      () {
        final manifest = validManifest(
          assertions: [CreativeWorkAssertion(author: 'Test')],
        );
        final result = ManifestValidator.validate(manifest);
        expect(result.hasWarnings, isTrue);
        expect(
          result.warnings.any(
            (w) =>
                w.contains("'stds.schema-org.CreativeWork'") &&
                w.contains('deprecated'),
          ),
          isTrue,
        );
      },
    );

    test('deprecated assertion c2pa.endorsement produces warning', () {
      final manifest = validManifest(
        assertions: [
          CustomAssertion(label: 'c2pa.endorsement', data: {'key': 'val'}),
        ],
      );
      final result = ManifestValidator.validate(manifest);
      expect(result.hasWarnings, isTrue);
      expect(
        result.warnings.any(
          (w) => w.contains("'c2pa.endorsement'") && w.contains('deprecated'),
        ),
        isTrue,
      );
    });

    test(
      'deprecated assertion in gatheredAssertions also produces warning',
      () {
        final manifest = validManifest(
          gatheredAssertions: [
            ExifAssertion(data: {'key': 'value'}),
          ],
        );
        final result = ManifestValidator.validate(manifest);
        expect(result.hasWarnings, isTrue);
        expect(
          result.warnings.any(
            (w) => w.contains("'stds.exif'") && w.contains('deprecated'),
          ),
          isTrue,
        );
      },
    );

    test('CawgIdentityAssertion in assertions (created) produces warning', () {
      final manifest = validManifest(
        assertions: [
          CawgIdentityAssertion(data: {'sig_type': 'cawg.x509.cose'}),
        ],
      );
      final result = ManifestValidator.validate(manifest);
      expect(result.hasWarnings, isTrue);
      expect(
        result.warnings.any(
          (w) =>
              w.contains('CAWG identity assertion') &&
              w.contains('created assertions') &&
              w.contains('gathered_assertions'),
        ),
        isTrue,
      );
    });

    test(
      'CawgIdentityAssertion in gatheredAssertions does NOT produce warning about placement',
      () {
        final manifest = validManifest(
          gatheredAssertions: [
            CawgIdentityAssertion(data: {'sig_type': 'cawg.x509.cose'}),
          ],
        );
        final result = ManifestValidator.validate(manifest);
        expect(
          result.warnings.any(
            (w) =>
                w.contains('CAWG identity assertion') &&
                w.contains('created assertions'),
          ),
          isFalse,
        );
      },
    );

    test('ingredient without relationship produces warning', () {
      final manifest = validManifest(
        ingredients: [const Ingredient(title: 'Source Image')],
      );
      final result = ManifestValidator.validate(manifest);
      expect(result.hasWarnings, isTrue);
      expect(
        result.warnings.any(
          (w) => w.contains('Source Image') && w.contains('no relationship'),
        ),
        isTrue,
      );
    });

    test('ingredient with relationship produces no warning', () {
      final manifest = validManifest(
        ingredients: [Ingredient.parent(title: 'Source Image')],
      );
      final result = ManifestValidator.validate(manifest);
      expect(
        result.warnings.any((w) => w.contains('no relationship')),
        isFalse,
      );
    });

    test('unnamed ingredient warning contains unnamed', () {
      final manifest = validManifest(ingredients: [const Ingredient()]);
      final result = ManifestValidator.validate(manifest);
      expect(result.hasWarnings, isTrue);
      expect(result.warnings.any((w) => w.contains('unnamed')), isTrue);
    });

    test('multiple issues combine correctly', () {
      final manifest = ManifestDefinition(
        title: '',
        claimGeneratorInfo: [],
        claimVersion: 1,
        assertions: [
          CawgIdentityAssertion(data: {'sig_type': 'cawg.x509.cose'}),
          ExifAssertion(data: {'key': 'val'}),
        ],
        ingredients: [const Ingredient()],
      );
      final result = ManifestValidator.validate(manifest);

      // Should have 2 errors: empty title, empty claimGeneratorInfo
      expect(result.errors.length, equals(2));

      // Should have warnings for: claim_version, deprecated exif,
      // CAWG identity placement, ingredient without relationship
      expect(result.warnings.length, greaterThanOrEqualTo(4));
      expect(result.isValid, isFalse);
    });
  });

  // =============================================================================
  // ManifestValidator.validateJson()
  // =============================================================================

  group('ManifestValidator.validateJson()', () {
    test('valid JSON produces valid result', () {
      final map = {
        'title': 'Test',
        'claim_generator_info': [
          {'name': 'TestApp', 'version': '1.0'},
        ],
      };
      final json = jsonEncode(map);
      final result = ManifestValidator.validateJson(json);
      expect(result.isValid, isTrue);
      expect(result.hasErrors, isFalse);
    });

    test('invalid JSON produces error', () {
      final result = ManifestValidator.validateJson('not valid json{{{');
      expect(result.hasErrors, isTrue);
      expect(
        result.errors.any((e) => e.contains('Failed to parse manifest JSON')),
        isTrue,
      );
    });

    test('JSON that parses to valid manifest is valid', () {
      final manifest = validManifest();
      final json = manifest.toJsonString();
      final result = ManifestValidator.validateJson(json);
      expect(result.isValid, isTrue);
    });
  });

  // =============================================================================
  // ManifestValidator.validateGatheredAssertions()
  // =============================================================================

  group('ManifestValidator.validateGatheredAssertions()', () {
    test('ActionsAssertion in gathered produces warning', () {
      final manifest = validManifest(
        gatheredAssertions: [
          ActionsAssertion(actions: [Action.created()]),
        ],
      );
      final result = ManifestValidator.validateGatheredAssertions(manifest);
      expect(result.hasWarnings, isTrue);
      expect(
        result.warnings.any(
          (w) =>
              w.contains('Actions assertion') &&
              w.contains('gathered_assertions'),
        ),
        isTrue,
      );
    });

    test('CawgIdentityAssertion in gathered is OK (no warning)', () {
      final manifest = validManifest(
        gatheredAssertions: [
          CawgIdentityAssertion(data: {'sig_type': 'cawg.x509.cose'}),
        ],
      );
      final result = ManifestValidator.validateGatheredAssertions(manifest);
      expect(result.hasWarnings, isFalse);
    });

    test('empty gathered produces no warnings', () {
      final manifest = validManifest();
      final result = ManifestValidator.validateGatheredAssertions(manifest);
      expect(result.hasWarnings, isFalse);
      expect(result.warnings, isEmpty);
    });
  });

  // =============================================================================
  // ManifestValidator.isCawgIdentityProperlyPlaced()
  // =============================================================================

  group('ManifestValidator.isCawgIdentityProperlyPlaced()', () {
    test('returns true when no CAWG identity in created assertions', () {
      final manifest = validManifest();
      expect(ManifestValidator.isCawgIdentityProperlyPlaced(manifest), isTrue);
    });

    test('returns false when CAWG identity in created assertions', () {
      final manifest = validManifest(
        assertions: [
          CawgIdentityAssertion(data: {'sig_type': 'cawg.x509.cose'}),
        ],
      );
      expect(ManifestValidator.isCawgIdentityProperlyPlaced(manifest), isFalse);
    });

    test('returns true when CAWG identity only in gathered assertions', () {
      final manifest = validManifest(
        gatheredAssertions: [
          CawgIdentityAssertion(data: {'sig_type': 'cawg.x509.cose'}),
        ],
      );
      expect(ManifestValidator.isCawgIdentityProperlyPlaced(manifest), isTrue);
    });
  });

  // =============================================================================
  // ManifestValidator.validateCawgCompliance()
  // =============================================================================

  group('ManifestValidator.validateCawgCompliance()', () {
    test('returns empty list when compliant', () {
      final manifest = validManifest(
        gatheredAssertions: [
          CawgIdentityAssertion(data: {'sig_type': 'cawg.x509.cose'}),
        ],
      );
      final issues = ManifestValidator.validateCawgCompliance(manifest);
      expect(issues, isEmpty);
    });

    test('returns issue when CAWG identity in created assertions', () {
      final manifest = validManifest(
        assertions: [
          CawgIdentityAssertion(data: {'sig_type': 'cawg.x509.cose'}),
        ],
      );
      final issues = ManifestValidator.validateCawgCompliance(manifest);
      expect(issues, isNotEmpty);
      expect(issues.length, equals(1));
      expect(
        issues.first,
        contains('CAWG identity assertion in created_assertions'),
      );
    });
  });
}
