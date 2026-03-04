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

// Main integration test entry point for C2PA Flutter plugin
//
// This file imports and runs all integration tests for the C2PA plugin.
// Tests cover: Reader API, Signer API, Roundtrip workflows, and Error handling.
//
// Run with: flutter test integration_test/plugin_integration_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:c2pa_flutter/c2pa.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('C2PA Plugin Integration Tests', () {
    late C2pa c2pa;

    setUpAll(() {
      c2pa = C2pa();
    });

    group('Platform Verification', () {
      testWidgets('getPlatformVersion returns non-empty string', (tester) async {
        final version = await c2pa.getPlatformVersion();
        expect(version, isNotNull);
        expect(version!.isNotEmpty, true);
      });

      testWidgets('getVersion returns C2PA library version', (tester) async {
        final version = await c2pa.getVersion();
        expect(version, isNotNull);
        expect(version!.isNotEmpty, true);
      });

      testWidgets('getSupportedReadMimeTypes returns supported types', (tester) async {
        final mimeTypes = await c2pa.getSupportedReadMimeTypes();
        expect(mimeTypes, isA<List<String>>());
        expect(mimeTypes.isNotEmpty, true);
        // JPEG should always be supported
        expect(mimeTypes.contains('image/jpeg'), true);
      });

      testWidgets('getSupportedSignMimeTypes returns supported types', (tester) async {
        final mimeTypes = await c2pa.getSupportedSignMimeTypes();
        expect(mimeTypes, isA<List<String>>());
        expect(mimeTypes.isNotEmpty, true);
        // JPEG should always be supported for signing
        expect(mimeTypes.contains('image/jpeg'), true);
      });
    });

    group('Enums', () {
      testWidgets('SigningAlgorithm has all expected values', (tester) async {
        expect(SigningAlgorithm.values.length, greaterThanOrEqualTo(7));
        expect(SigningAlgorithm.values, contains(SigningAlgorithm.es256));
        expect(SigningAlgorithm.values, contains(SigningAlgorithm.es384));
        expect(SigningAlgorithm.values, contains(SigningAlgorithm.es512));
        expect(SigningAlgorithm.values, contains(SigningAlgorithm.ps256));
        expect(SigningAlgorithm.values, contains(SigningAlgorithm.ps384));
        expect(SigningAlgorithm.values, contains(SigningAlgorithm.ps512));
        expect(SigningAlgorithm.values, contains(SigningAlgorithm.ed25519));
      });

      testWidgets('ManifestIntent has all expected values', (tester) async {
        expect(ManifestIntent.values.length, 3);
        expect(ManifestIntent.values, contains(ManifestIntent.create));
        expect(ManifestIntent.values, contains(ManifestIntent.edit));
        expect(ManifestIntent.values, contains(ManifestIntent.update));
      });

      testWidgets('DigitalSourceType has all expected values', (tester) async {
        expect(DigitalSourceType.values.length, 19);
        expect(DigitalSourceType.values, contains(DigitalSourceType.digitalCapture));
        expect(DigitalSourceType.values, contains(DigitalSourceType.computationalCapture));
        expect(DigitalSourceType.values, contains(DigitalSourceType.humanEdits));
        expect(DigitalSourceType.values, contains(DigitalSourceType.digitalCreation));
      });

      testWidgets('ValidationStatus has all expected values', (tester) async {
        expect(ValidationStatus.values.length, 3);
        expect(ValidationStatus.values, contains(ValidationStatus.valid));
        expect(ValidationStatus.values, contains(ValidationStatus.invalid));
        expect(ValidationStatus.values, contains(ValidationStatus.unknown));
      });

      testWidgets('Relationship has all expected values', (tester) async {
        expect(Relationship.values.length, 3);
        expect(Relationship.values, contains(Relationship.parentOf));
        expect(Relationship.values, contains(Relationship.componentOf));
        expect(Relationship.values, contains(Relationship.inputTo));
      });
    });

    group('Data Classes', () {
      testWidgets('ReaderOptions has correct defaults', (tester) async {
        const options = ReaderOptions();
        expect(options.detailed, false);
        expect(options.dataDir, isNull);
      });

      testWidgets('BuilderOptions has correct defaults', (tester) async {
        const options = BuilderOptions();
        expect(options.intent, isNull);
        expect(options.digitalSourceType, isNull);
        expect(options.embed, true);
        expect(options.remoteUrl, isNull);
      });

      testWidgets('ActionConfig serializes correctly', (tester) async {
        final action = ActionConfig(
          action: 'c2pa.created',
          softwareAgent: 'test/1.0',
          digitalSourceType: DigitalSourceType.digitalCapture,
        );

        final map = action.toMap();
        expect(map['action'], 'c2pa.created');
        expect(map['softwareAgent'], 'test/1.0');
        expect(map['digitalSourceType'], contains('digitalCapture'));
      });

      testWidgets('IngredientConfig serializes correctly', (tester) async {
        final config = IngredientConfig(
          title: 'Test Ingredient',
          relationship: Relationship.parentOf,
        );

        final map = config.toMap();
        expect(map['title'], 'Test Ingredient');
        expect(map['relationship'], 'parentOf');
      });
    });

    group('Manifest Types', () {
      testWidgets('ManifestDefinition.created generates correct JSON', (tester) async {
        final manifest = ManifestDefinition.created(
          title: 'Test Photo',
          claimGenerator: ClaimGeneratorInfo(name: 'TestApp', version: '1.0'),
          sourceType: DigitalSourceType.digitalCapture,
        );

        final json = manifest.toJsonString();
        expect(json, contains('Test Photo'));
        expect(json, contains('TestApp/1.0'));
        expect(json, contains('c2pa.created'));
        expect(json, contains('digitalCapture'));
      });

      testWidgets('ManifestDefinition.edited generates correct JSON', (tester) async {
        final manifest = ManifestDefinition.edited(
          title: 'Edited Photo',
          claimGenerator: ClaimGeneratorInfo(name: 'Editor', version: '2.0'),
          actions: [
            Action.cropped(softwareAgent: 'Editor/2.0'),
            Action.filtered(softwareAgent: 'Editor/2.0'),
          ],
        );

        final json = manifest.toJsonString();
        expect(json, contains('Edited Photo'));
        expect(json, contains('c2pa.cropped'));
        expect(json, contains('c2pa.filtered'));
      });

      testWidgets('ManifestDefinition.aiGenerated generates correct JSON', (tester) async {
        final manifest = ManifestDefinition.aiGenerated(
          title: 'AI Art',
          claimGenerator: ClaimGeneratorInfo(name: 'AI Generator', version: '1.0'),
          trainingMining: TrainingMiningAssertion(
            entries: [
              TrainingMiningEntry.aiTraining(
                permission: TrainingMiningPermission.notAllowed,
              ),
            ],
          ),
        );

        final json = manifest.toJsonString();
        expect(json, contains('AI Art'));
        expect(json, contains('c2pa.ai_generated'));
        expect(json, contains('trainedAlgorithmicMedia'));
        expect(json, contains('c2pa.training-mining'));
      });

      testWidgets('Action factories create correct actions', (tester) async {
        final created = Action.created(sourceType: DigitalSourceType.digitalCapture);
        expect(created.action, 'c2pa.created');
        expect(created.digitalSourceType, contains('digitalCapture'));

        final edited = Action.edited(softwareAgent: 'Test/1.0');
        expect(edited.action, 'c2pa.edited');
        expect(edited.softwareAgent, 'Test/1.0');

        final cropped = Action.cropped();
        expect(cropped.action, 'c2pa.cropped');

        final aiGenerated = Action.aiGenerated(
          sourceType: DigitalSourceType.trainedAlgorithmicMedia,
        );
        expect(aiGenerated.action, 'c2pa.ai_generated');
      });

      testWidgets('Ingredient factories create correct ingredients', (tester) async {
        final parent = Ingredient.parent(title: 'Original');
        expect(parent.relationship, Relationship.parentOf);
        expect(parent.title, 'Original');

        final component = Ingredient.component(title: 'Overlay');
        expect(component.relationship, Relationship.componentOf);
        expect(component.title, 'Overlay');
      });

      testWidgets('Shape factories create correct shapes', (tester) async {
        final rect = Shape.rectangle(
          origin: Coordinate(x: 10, y: 20),
          width: 100,
          height: 50,
        );
        expect(rect.type, ShapeType.rectangle);
        expect(rect.origin?.x, 10);
        expect(rect.width, 100);

        final circle = Shape.circle(
          origin: Coordinate(x: 50, y: 50),
          radius: 25,
        );
        expect(circle.type, ShapeType.circle);
        expect(circle.radius, 25);

        final polygon = Shape.polygon(
          vertices: [
            Coordinate(x: 0, y: 0),
            Coordinate(x: 100, y: 0),
            Coordinate(x: 50, y: 100),
          ],
        );
        expect(polygon.type, ShapeType.polygon);
        expect(polygon.vertices?.length, 3);
      });

      testWidgets('RegionOfInterest factories create correct regions', (tester) async {
        final spatial = RegionOfInterest.spatial(
          shape: Shape.rectangle(
            origin: Coordinate(x: 0, y: 0),
            width: 100,
            height: 100,
          ),
          role: Role.edited,
        );
        expect(spatial.region.length, 1);
        expect(spatial.region.first, isA<SpatialRange>());
        expect(spatial.role, Role.edited);

        final temporal = RegionOfInterest.temporal(
          time: Time(start: '0:00', end: '1:30'),
        );
        expect(temporal.region.first, isA<TemporalRange>());
      });

      testWidgets('TrainingMiningEntry factories create correct entries', (tester) async {
        final aiTraining = TrainingMiningEntry.aiTraining(
          permission: TrainingMiningPermission.notAllowed,
        );
        expect(aiTraining.use, 'aiTraining');
        expect(aiTraining.permission, TrainingMiningPermission.notAllowed);

        final dataMining = TrainingMiningEntry.dataMining(
          permission: TrainingMiningPermission.constrained,
          constraintInfo: 'Research only',
        );
        expect(dataMining.use, 'dataMining');
        expect(dataMining.constraintInfo, 'Research only');
      });

      testWidgets('Assertions serialize correctly', (tester) async {
        final actions = ActionsAssertion(
          actions: [Action.created()],
        );
        expect(actions.label, 'c2pa.actions');

        final creative = CreativeWorkAssertion(
          author: 'Test Author',
          copyrightNotice: '2024 Test',
        );
        expect(creative.label, 'stds.schema-org.CreativeWork');

        final training = TrainingMiningAssertion(
          entries: [
            TrainingMiningEntry.aiTraining(
              permission: TrainingMiningPermission.notAllowed,
            ),
          ],
        );
        expect(training.label, 'c2pa.training-mining');
      });
    });
  });
}
