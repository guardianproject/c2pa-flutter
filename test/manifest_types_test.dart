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
  group('Enums', () {
    test('PredefinedAction has correct values', () {
      expect(PredefinedAction.created.value, 'c2pa.created');
      expect(PredefinedAction.edited.value, 'c2pa.edited');
      expect(PredefinedAction.aiGenerated.value, 'c2pa.ai_generated');
    });

    test('Relationship serializes correctly', () {
      expect(Relationship.parentOf.toJson(), 'parentOf');
      expect(Relationship.componentOf.toJson(), 'componentOf');
      expect(Relationship.inputTo.toJson(), 'inputTo');
    });

    test('Relationship deserializes correctly', () {
      expect(Relationship.fromJson('parentOf'), Relationship.parentOf);
      expect(Relationship.fromJson('componentOf'), Relationship.componentOf);
      expect(Relationship.fromJson('inputTo'), Relationship.inputTo);
      expect(Relationship.fromJson('unknown'), Relationship.componentOf);
    });

    test('DigitalSourceType has correct URLs', () {
      expect(
        DigitalSourceType.digitalCapture.url,
        'http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture',
      );
      expect(
        DigitalSourceType.trainedAlgorithmicMedia.url,
        'http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia',
      );
      expect(
        DigitalSourceType.empty.url,
        'http://c2pa.org/digitalsourcetype/empty',
      );
    });

    test('DigitalSourceType.fromUrl works', () {
      expect(
        DigitalSourceType.fromUrl(
          'http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture',
        ),
        DigitalSourceType.digitalCapture,
      );
      expect(DigitalSourceType.fromUrl(null), isNull);
      expect(DigitalSourceType.fromUrl('unknown'), isNull);
    });

    test('Role has correct values', () {
      expect(Role.edited.value, 'c2pa.edited');
      expect(Role.cropped.value, 'c2pa.cropped');
    });

    test('ImageRegionType has correct URLs', () {
      expect(
        ImageRegionType.crop.url,
        'http://cv.iptc.org/newscodes/imageregionrole/crop',
      );
    });
  });

  group('Coordinate', () {
    test('toJson and fromJson round-trip', () {
      final coord = Coordinate(x: 10.5, y: 20.3);
      final json = coord.toJson();
      final decoded = Coordinate.fromJson(json);

      expect(decoded.x, 10.5);
      expect(decoded.y, 20.3);
    });

    test('equality works', () {
      final a = Coordinate(x: 1, y: 2);
      final b = Coordinate(x: 1, y: 2);
      final c = Coordinate(x: 3, y: 4);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('Shape', () {
    test('rectangle factory creates correct shape', () {
      final shape = Shape.rectangle(
        origin: Coordinate(x: 0, y: 0),
        width: 100,
        height: 50,
        unit: UnitType.pixel,
      );

      expect(shape.type, ShapeType.rectangle);
      expect(shape.width, 100);
      expect(shape.height, 50);
    });

    test('circle factory creates correct shape', () {
      final shape = Shape.circle(origin: Coordinate(x: 50, y: 50), radius: 25);

      expect(shape.type, ShapeType.circle);
      expect(shape.radius, 25);
    });

    test('polygon factory creates correct shape', () {
      final shape = Shape.polygon(
        vertices: [
          Coordinate(x: 0, y: 0),
          Coordinate(x: 100, y: 0),
          Coordinate(x: 50, y: 100),
        ],
      );

      expect(shape.type, ShapeType.polygon);
      expect(shape.vertices?.length, 3);
    });

    test('toJson and fromJson round-trip', () {
      final shape = Shape.rectangle(
        origin: Coordinate(x: 10, y: 20),
        width: 100,
        height: 50,
        inside: true,
        unit: UnitType.percent,
      );

      final json = shape.toJson();
      final decoded = Shape.fromJson(json);

      expect(decoded.type, ShapeType.rectangle);
      expect(decoded.origin?.x, 10);
      expect(decoded.width, 100);
      expect(decoded.inside, true);
      expect(decoded.unit, UnitType.percent);
    });
  });

  group('RegionRange', () {
    test('SpatialRange serializes correctly', () {
      final range = SpatialRange(
        shape: Shape.rectangle(
          origin: Coordinate(x: 0, y: 0),
          width: 100,
          height: 100,
        ),
      );

      final json = range.toJson();
      expect(json.containsKey('shape'), true);
    });

    test('TemporalRange serializes correctly', () {
      final range = TemporalRange(
        time: Time(start: '0:00', end: '1:30'),
      );

      final json = range.toJson();
      expect(json.containsKey('time'), true);
    });

    test('FrameRange serializes correctly', () {
      final range = FrameRange(frame: Frame(start: 0, end: 100));

      final json = range.toJson();
      expect(json.containsKey('frame'), true);
    });

    test('RegionRange.fromJson detects type correctly', () {
      final spatial = RegionRange.fromJson({
        'shape': {'type': 'rectangle', 'width': 100, 'height': 100},
      });
      expect(spatial, isA<SpatialRange>());

      final temporal = RegionRange.fromJson({
        'time': {'start': '0:00', 'end': '1:00'},
      });
      expect(temporal, isA<TemporalRange>());

      final frame = RegionRange.fromJson({
        'frame': {'start': 0, 'end': 100},
      });
      expect(frame, isA<FrameRange>());
    });
  });

  group('RegionOfInterest', () {
    test('spatial factory creates correct region', () {
      final region = RegionOfInterest.spatial(
        shape: Shape.rectangle(
          origin: Coordinate(x: 0, y: 0),
          width: 100,
          height: 100,
        ),
        role: Role.edited,
        regionType: ImageRegionType.mainSubject,
      );

      expect(region.region.length, 1);
      expect(region.region.first, isA<SpatialRange>());
      expect(region.role, Role.edited);
    });

    test('toJson and fromJson round-trip', () {
      final region = RegionOfInterest(
        region: [
          SpatialRange(
            shape: Shape.rectangle(
              origin: Coordinate(x: 10, y: 20),
              width: 50,
              height: 50,
            ),
          ),
        ],
        description: 'Test region',
        name: 'Region 1',
        role: Role.areaOfInterest,
      );

      final json = region.toJson();
      final decoded = RegionOfInterest.fromJson(json);

      expect(decoded.description, 'Test region');
      expect(decoded.name, 'Region 1');
      expect(decoded.region.length, 1);
    });
  });

  group('Action', () {
    test('created factory sets correct values', () {
      final action = Action.created(
        sourceType: DigitalSourceType.digitalCapture,
        softwareAgent: 'TestApp/1.0',
      );

      expect(action.action, 'c2pa.created');
      expect(action.digitalSourceType, DigitalSourceType.digitalCapture.url);
      expect(action.softwareAgent, 'TestApp/1.0');
    });

    test('edited factory sets correct values', () {
      final action = Action.edited(
        softwareAgent: 'TestApp/1.0',
        changes: [
          RegionOfInterest.spatial(
            shape: Shape.rectangle(
              origin: Coordinate(x: 0, y: 0),
              width: 100,
              height: 100,
            ),
          ),
        ],
      );

      expect(action.action, 'c2pa.edited');
      expect(action.changes?.length, 1);
    });

    test('aiGenerated factory sets correct values', () {
      final action = Action.aiGenerated(
        sourceType: DigitalSourceType.trainedAlgorithmicMedia,
        softwareAgent: 'AI Model v1',
        parameters: {'model': 'test-model'},
      );

      expect(action.action, 'c2pa.ai_generated');
      expect(
        action.digitalSourceType,
        DigitalSourceType.trainedAlgorithmicMedia.url,
      );
      expect(action.parameters?['model'], 'test-model');
    });

    test('toJson and fromJson round-trip', () {
      final action = Action(
        action: 'c2pa.edited',
        softwareAgent: 'TestApp/1.0',
        when: '2024-01-15T10:30:00Z',
        parameters: {'key': 'value'},
      );

      final json = action.toJson();
      final decoded = Action.fromJson(json);

      expect(decoded.action, 'c2pa.edited');
      expect(decoded.softwareAgent, 'TestApp/1.0');
      expect(decoded.when, '2024-01-15T10:30:00Z');
      expect(decoded.parameters?['key'], 'value');
    });
  });

  group('Ingredient', () {
    test('parent factory sets correct relationship', () {
      final ingredient = Ingredient.parent(title: 'Parent Image');

      expect(ingredient.relationship, Relationship.parentOf);
      expect(ingredient.title, 'Parent Image');
    });

    test('component factory sets correct relationship', () {
      final ingredient = Ingredient.component(title: 'Component');

      expect(ingredient.relationship, Relationship.componentOf);
    });

    test('toJson and fromJson round-trip', () {
      final ingredient = Ingredient(
        title: 'Test Ingredient',
        format: 'image/jpeg',
        relationship: Relationship.parentOf,
        documentId: 'doc-123',
        instanceId: 'inst-456',
      );

      final json = ingredient.toJson();
      final decoded = Ingredient.fromJson(json);

      expect(decoded.title, 'Test Ingredient');
      expect(decoded.format, 'image/jpeg');
      expect(decoded.relationship, Relationship.parentOf);
      expect(decoded.documentId, 'doc-123');
    });
  });

  group('ClaimGeneratorInfo', () {
    test('claimGeneratorString formats correctly', () {
      final info = ClaimGeneratorInfo(name: 'TestApp', version: '1.0.0');
      expect(info.claimGeneratorString, 'TestApp/1.0.0');

      final infoNoVersion = ClaimGeneratorInfo(name: 'TestApp');
      expect(infoNoVersion.claimGeneratorString, 'TestApp');
    });

    test('toJson and fromJson round-trip', () {
      final info = ClaimGeneratorInfo(
        name: 'TestApp',
        version: '2.0',
        icon: {'format': 'image/png', 'identifier': 'icon.png'},
      );

      final json = info.toJson();
      final decoded = ClaimGeneratorInfo.fromJson(json);

      expect(decoded.name, 'TestApp');
      expect(decoded.version, '2.0');
      expect(decoded.icon?['format'], 'image/png');
    });
  });

  group('TrainingMiningEntry', () {
    test('dataMining factory creates correct entry', () {
      final entry = TrainingMiningEntry.dataMining(
        permission: TrainingMiningPermission.notAllowed,
      );

      expect(entry.use, 'dataMining');
      expect(entry.permission, TrainingMiningPermission.notAllowed);
    });

    test('aiTraining factory creates correct entry', () {
      final entry = TrainingMiningEntry.aiTraining(
        permission: TrainingMiningPermission.constrained,
        constraintInfo: 'Only for research',
      );

      expect(entry.use, 'aiTraining');
      expect(entry.permission, TrainingMiningPermission.constrained);
      expect(entry.constraintInfo, 'Only for research');
    });

    test('toJson serializes permission correctly', () {
      final entry = TrainingMiningEntry(
        use: 'aiInference',
        permission: TrainingMiningPermission.allowed,
      );

      final json = entry.toJson();
      expect(json['use'], 'aiInference');
      expect(json['allowed'], true);
    });
  });

  group('Assertions', () {
    test('ActionsAssertion serializes correctly', () {
      final assertion = ActionsAssertion(
        actions: [Action.created(sourceType: DigitalSourceType.digitalCapture)],
      );

      final json = assertion.toJson();
      expect(json['label'], 'c2pa.actions');
      expect((json['data'] as Map)['actions'], isA<List>());
    });

    test('CreativeWorkAssertion serializes correctly', () {
      final assertion = CreativeWorkAssertion(
        author: 'John Doe',
        copyrightNotice: '2024 John Doe',
      );

      final json = assertion.toJson();
      expect(json['label'], 'stds.schema-org.CreativeWork');
      expect((json['data'] as Map)['author'], 'John Doe');
      expect((json['data'] as Map)['@context'], 'https://schema.org/');
    });

    test('TrainingMiningAssertion serializes correctly', () {
      final assertion = TrainingMiningAssertion(
        entries: [
          TrainingMiningEntry.aiTraining(
            permission: TrainingMiningPermission.notAllowed,
          ),
        ],
      );

      final json = assertion.toJson();
      expect(json['label'], 'c2pa.training-mining');
    });

    test('CustomAssertion allows arbitrary data', () {
      final assertion = CustomAssertion(
        label: 'custom.my-assertion',
        data: {'key': 'value', 'number': 42},
      );

      final json = assertion.toJson();
      expect(json['label'], 'custom.my-assertion');
      expect((json['data'] as Map)['key'], 'value');
    });

    test('AssertionDefinition.fromJson parses actions assertion', () {
      final json = {
        'label': 'c2pa.actions',
        'data': {
          'actions': [
            {'action': 'c2pa.created'},
          ],
        },
      };

      final assertion = AssertionDefinition.fromJson(json);
      expect(assertion, isA<ActionsAssertion>());
      expect((assertion as ActionsAssertion).actions.length, 1);
    });
  });

  group('ManifestDefinition', () {
    test('created factory generates correct manifest', () {
      final manifest = ManifestDefinition.created(
        title: 'My Photo',
        claimGenerator: ClaimGeneratorInfo(name: 'TestApp', version: '1.0'),
        sourceType: DigitalSourceType.digitalCapture,
      );

      expect(manifest.title, 'My Photo');
      expect(manifest.claimGeneratorInfo.length, 1);
      expect(manifest.assertions.length, 1);
      expect(manifest.assertions.first, isA<ActionsAssertion>());
    });

    test('aiGenerated factory generates correct manifest', () {
      final manifest = ManifestDefinition.aiGenerated(
        title: 'AI Image',
        claimGenerator: ClaimGeneratorInfo(name: 'AIApp', version: '2.0'),
        trainingMining: TrainingMiningAssertion(
          entries: [
            TrainingMiningEntry.aiTraining(
              permission: TrainingMiningPermission.notAllowed,
            ),
          ],
        ),
      );

      expect(manifest.title, 'AI Image');
      expect(manifest.assertions.length, 2);
    });

    test('toJsonString produces valid JSON', () {
      final manifest = ManifestDefinition(
        title: 'Test Image',
        claimGeneratorInfo: [ClaimGeneratorInfo(name: 'Test', version: '1.0')],
        assertions: [
          ActionsAssertion(actions: [Action.created()]),
        ],
      );

      final jsonStr = manifest.toJsonString();
      expect(() => jsonDecode(jsonStr), returnsNormally);

      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(decoded['title'], 'Test Image');
      expect(decoded['claim_generator'], 'Test/1.0');
    });

    test('fromJson and toJson round-trip', () {
      final original = ManifestDefinition(
        title: 'Round Trip Test',
        claimGeneratorInfo: [
          ClaimGeneratorInfo(name: 'TestApp', version: '1.0'),
        ],
        assertions: [
          ActionsAssertion(
            actions: [
              Action.created(sourceType: DigitalSourceType.digitalCapture),
            ],
          ),
          CreativeWorkAssertion(author: 'Test Author'),
        ],
        ingredients: [Ingredient.parent(title: 'Parent Image')],
        vendor: 'test-vendor',
        format: 'image/jpeg',
      );

      final jsonStr = original.toJsonString();
      final decoded = ManifestDefinition.fromJson(jsonStr);

      expect(decoded.title, 'Round Trip Test');
      expect(decoded.claimGeneratorInfo.length, 1);
      expect(decoded.assertions.length, 2);
      expect(decoded.ingredients.length, 1);
      expect(decoded.vendor, 'test-vendor');
      expect(decoded.format, 'image/jpeg');
    });

    test('toJson includes claim_generator for compatibility', () {
      final manifest = ManifestDefinition(
        title: 'Test',
        claimGeneratorInfo: [ClaimGeneratorInfo(name: 'App', version: '1.0')],
      );

      final json = manifest.toJson();
      expect(json['claim_generator'], 'App/1.0');
      expect(json['claim_generator_info'], isA<List>());
    });
  });

  group('ResourceRef', () {
    test('toJson and fromJson round-trip', () {
      final ref = ResourceRef(
        identifier: 'self#jumbf=/c2pa/thumbnail.jpg',
        format: 'image/jpeg',
      );

      final json = ref.toJson();
      final decoded = ResourceRef.fromJson(json);

      expect(decoded.identifier, ref.identifier);
      expect(decoded.format, 'image/jpeg');
    });
  });

  group('HashedUri', () {
    test('toJson and fromJson round-trip', () {
      final uri = HashedUri(
        url: 'https://example.com/cert',
        alg: 'sha256',
        hash: 'abc123',
      );

      final json = uri.toJson();
      final decoded = HashedUri.fromJson(json);

      expect(decoded.url, uri.url);
      expect(decoded.alg, 'sha256');
      expect(decoded.hash, 'abc123');
    });
  });

  group('ValidationResults', () {
    test('toJson and fromJson round-trip', () {
      final results = ValidationResults(
        errors: [ValidationStatusEntry(code: 'ERR01', explanation: 'Error')],
        warnings: [ValidationStatusEntry(code: 'WARN01')],
        informational: [],
      );

      final json = results.toJson();
      final decoded = ValidationResults.fromJson(json);

      expect(decoded.errors.length, 1);
      expect(decoded.warnings.length, 1);
      expect(decoded.errors.first.code, 'ERR01');
    });
  });

  group('Metadata', () {
    test('toJson and fromJson round-trip', () {
      final metadata = Metadata(
        dateTime: DateTime(2024, 1, 15, 10, 30),
        reference: 'ref-123',
        dataSource: DataSource(type: 'localProvider'),
      );

      final json = metadata.toJson();
      final decoded = Metadata.fromJson(json);

      expect(decoded.dateTime?.year, 2024);
      expect(decoded.reference, 'ref-123');
      expect(decoded.dataSource?.type, 'localProvider');
    });
  });

  group('ValidationStatusCode', () {
    test('fromCode with valid success code returns correct enum', () {
      final result = ValidationStatusCode.fromCode('claimSignature.validated');
      expect(result, ValidationStatusCode.claimSignatureValidated);
    });

    test('fromCode with valid failure code returns correct enum', () {
      final result = ValidationStatusCode.fromCode(
        'assertion.dataHash.mismatch',
      );
      expect(result, ValidationStatusCode.assertionDataHashMismatch);
    });

    test('fromCode with unknown code returns null', () {
      final result = ValidationStatusCode.fromCode('unknown.code.here');
      expect(result, isNull);
    });

    test('all codes have non-empty string values', () {
      for (final code in ValidationStatusCode.values) {
        expect(code.code, isNotEmpty);
      }
    });

    test('code property matches expected string', () {
      expect(
        ValidationStatusCode.claimSignatureValidated.code,
        'claimSignature.validated',
      );
      expect(ValidationStatusCode.generalError.code, 'general.error');
      expect(ValidationStatusCode.timestampTrusted.code, 'timeStamp.trusted');
    });
  });

  group('CawgIdentityAssertion', () {
    test('has correct label', () {
      final assertion = CawgIdentityAssertion(data: {'key': 'value'});
      expect(assertion.label, 'cawg.identity');
    });

    test('toJson includes label and data', () {
      final assertion = CawgIdentityAssertion(data: {'signer': 'test-signer'});

      final json = assertion.toJson();
      expect(json['label'], 'cawg.identity');
      expect((json['data'] as Map)['signer'], 'test-signer');
    });

    test('fromData round-trip works', () {
      final original = CawgIdentityAssertion(
        data: {'signer': 'test-signer', 'method': 'x509'},
      );

      final json = original.toJson();
      final decoded = CawgIdentityAssertion.fromData(
        json['data'] as Map<String, dynamic>,
      );

      expect(decoded.label, 'cawg.identity');
      expect(decoded.data['signer'], 'test-signer');
      expect(decoded.data['method'], 'x509');
    });
  });

  group('CawgTrainingMiningAssertion', () {
    test('has correct label', () {
      final assertion = CawgTrainingMiningAssertion(entries: []);
      expect(assertion.label, 'cawg.ai_training_and_data_mining');
    });

    test('toJson serializes entries correctly', () {
      final assertion = CawgTrainingMiningAssertion(
        entries: [
          CawgTrainingMiningEntry(
            use: 'aiTraining',
            permission: TrainingMiningPermission.notAllowed,
          ),
        ],
      );

      final json = assertion.toJson();
      expect(json['label'], 'cawg.ai_training_and_data_mining');
      final entries = (json['data'] as Map)['entries'] as List;
      expect(entries.length, 1);
      expect((entries.first as Map)['use'], 'aiTraining');
    });

    test('fromData round-trip works with entries containing extra fields', () {
      final original = CawgTrainingMiningAssertion(
        entries: [
          CawgTrainingMiningEntry(
            use: 'aiTraining',
            permission: TrainingMiningPermission.allowed,
            aiModelLearningType: 'supervised',
            aiMiningType: 'text',
          ),
        ],
      );

      final json = original.toJson();
      final decoded = CawgTrainingMiningAssertion.fromData(
        json['data'] as Map<String, dynamic>,
      );

      expect(decoded.entries.length, 1);
      expect(decoded.entries.first.use, 'aiTraining');
      expect(
        decoded.entries.first.permission,
        TrainingMiningPermission.allowed,
      );
      expect(decoded.entries.first.aiModelLearningType, 'supervised');
      expect(decoded.entries.first.aiMiningType, 'text');
    });
  });

  group('CawgTrainingMiningEntry', () {
    test('toJson serializes permission correctly', () {
      final entry = CawgTrainingMiningEntry(
        use: 'aiTraining',
        permission: TrainingMiningPermission.allowed,
      );

      final json = entry.toJson();
      expect(json['use'], 'aiTraining');
      expect(json['allowed'], true);
    });

    test('fromJson parses allowed permission', () {
      final json = {'use': 'dataMining', 'allowed': true};
      final entry = CawgTrainingMiningEntry.fromJson(json);

      expect(entry.use, 'dataMining');
      expect(entry.permission, TrainingMiningPermission.allowed);
    });

    test(
      'extra fields aiModelLearningType and aiMiningType are serialized',
      () {
        final entry = CawgTrainingMiningEntry(
          use: 'aiTraining',
          permission: TrainingMiningPermission.constrained,
          aiModelLearningType: 'reinforcement',
          aiMiningType: 'image',
        );

        final json = entry.toJson();
        expect(json['ai_model_learning_type'], 'reinforcement');
        expect(json['ai_mining_type'], 'image');
      },
    );
  });

  group('AssertionDefinition.fromJson CAWG labels', () {
    test('parses cawg.identity label to CawgIdentityAssertion', () {
      final json = {
        'label': 'cawg.identity',
        'data': {'signer': 'test'},
      };

      final assertion = AssertionDefinition.fromJson(json);
      expect(assertion, isA<CawgIdentityAssertion>());
      expect((assertion as CawgIdentityAssertion).data['signer'], 'test');
    });

    test(
      'parses cawg.ai_training_and_data_mining label to CawgTrainingMiningAssertion',
      () {
        final json = {
          'label': 'cawg.ai_training_and_data_mining',
          'data': {
            'entries': [
              {'use': 'aiTraining', 'notAllowed': true},
            ],
          },
        };

        final assertion = AssertionDefinition.fromJson(json);
        expect(assertion, isA<CawgTrainingMiningAssertion>());
        expect((assertion as CawgTrainingMiningAssertion).entries.length, 1);
      },
    );

    test('unknown label produces CustomAssertion', () {
      final json = {
        'label': 'com.example.unknown',
        'data': {'foo': 'bar'},
      };

      final assertion = AssertionDefinition.fromJson(json);
      expect(assertion, isA<CustomAssertion>());
      expect((assertion as CustomAssertion).label, 'com.example.unknown');
    });
  });

  group('ManifestDefinition - gathered assertions', () {
    test('default gatheredAssertions is empty list', () {
      final manifest = ManifestDefinition(
        title: 'Test',
        claimGeneratorInfo: [ClaimGeneratorInfo(name: 'App', version: '1.0')],
      );

      expect(manifest.gatheredAssertions, isEmpty);
    });

    test('default claimVersion is 2', () {
      final manifest = ManifestDefinition(
        title: 'Test',
        claimGeneratorInfo: [ClaimGeneratorInfo(name: 'App', version: '1.0')],
      );

      expect(manifest.claimVersion, 2);
    });

    test('toJson includes gathered_assertions when non-empty', () {
      final manifest = ManifestDefinition(
        title: 'Test',
        claimGeneratorInfo: [ClaimGeneratorInfo(name: 'App', version: '1.0')],
        gatheredAssertions: [
          CawgIdentityAssertion(data: {'signer': 'test'}),
        ],
      );

      final json = manifest.toJson();
      expect(json.containsKey('gathered_assertions'), true);
      expect((json['gathered_assertions'] as List).length, 1);
    });

    test('toJson omits claim_version when it is 2', () {
      final manifest = ManifestDefinition(
        title: 'Test',
        claimGeneratorInfo: [ClaimGeneratorInfo(name: 'App', version: '1.0')],
      );

      final json = manifest.toJson();
      expect(json.containsKey('claim_version'), false);
    });

    test('toJson includes claim_version when non-default', () {
      final manifest = ManifestDefinition(
        title: 'Test',
        claimGeneratorInfo: [ClaimGeneratorInfo(name: 'App', version: '1.0')],
        claimVersion: 1,
      );

      final json = manifest.toJson();
      expect(json['claim_version'], 1);
    });

    test('fromJson round-trip preserves gatheredAssertions', () {
      final original = ManifestDefinition(
        title: 'Test',
        claimGeneratorInfo: [ClaimGeneratorInfo(name: 'App', version: '1.0')],
        gatheredAssertions: [
          CawgIdentityAssertion(data: {'signer': 'test'}),
        ],
      );

      final jsonStr = original.toJsonString();
      final decoded = ManifestDefinition.fromJson(jsonStr);

      expect(decoded.gatheredAssertions.length, 1);
      expect(decoded.gatheredAssertions.first, isA<CawgIdentityAssertion>());
    });
  });

  group('ManifestDefinition.withAssertions', () {
    test('separates created and gathered assertions correctly', () {
      final manifest = ManifestDefinition.withAssertions(
        title: 'Test',
        claimGenerator: ClaimGeneratorInfo(name: 'App', version: '1.0'),
        createdAssertions: [
          ActionsAssertion(actions: [Action.created()]),
        ],
        gatheredAssertions: [
          CawgIdentityAssertion(data: {'signer': 'test'}),
        ],
      );

      expect(manifest.assertions.length, 1);
      expect(manifest.assertions.first, isA<ActionsAssertion>());
      expect(manifest.gatheredAssertions.length, 1);
      expect(manifest.gatheredAssertions.first, isA<CawgIdentityAssertion>());
    });

    test('factory properly assigns both lists', () {
      final created = [
        ActionsAssertion(actions: [Action.created()]),
        CreativeWorkAssertion(author: 'Author'),
      ];
      final gathered = [
        CawgIdentityAssertion(data: {'method': 'x509'}),
      ];

      final manifest = ManifestDefinition.withAssertions(
        title: 'Test',
        claimGenerator: ClaimGeneratorInfo(name: 'App', version: '1.0'),
        createdAssertions: created,
        gatheredAssertions: gathered,
      );

      expect(manifest.assertions.length, 2);
      expect(manifest.gatheredAssertions.length, 1);
    });
  });

  group('ManifestDefinition.withCawgIdentity', () {
    test('places identity assertions in gatheredAssertions', () {
      final manifest = ManifestDefinition.withCawgIdentity(
        title: 'Test',
        claimGenerator: ClaimGeneratorInfo(name: 'App', version: '1.0'),
        identityAssertions: [
          CawgIdentityAssertion(data: {'signer': 'test'}),
        ],
      );

      expect(manifest.gatheredAssertions.length, 1);
      expect(manifest.gatheredAssertions.first, isA<CawgIdentityAssertion>());
    });

    test('created assertions are set from parameter', () {
      final manifest = ManifestDefinition.withCawgIdentity(
        title: 'Test',
        claimGenerator: ClaimGeneratorInfo(name: 'App', version: '1.0'),
        identityAssertions: [
          CawgIdentityAssertion(data: {'signer': 'test'}),
        ],
        createdAssertions: [
          ActionsAssertion(actions: [Action.created()]),
        ],
      );

      expect(manifest.assertions.length, 1);
      expect(manifest.assertions.first, isA<ActionsAssertion>());
      expect(manifest.gatheredAssertions.length, 1);
    });
  });

  group('StandardAssertionLabel', () {
    test('cawgIdentity has value cawg.identity', () {
      expect(StandardAssertionLabel.cawgIdentity.value, 'cawg.identity');
    });

    test('cawgTrainingMining has value cawg.ai_training_and_data_mining', () {
      expect(
        StandardAssertionLabel.cawgTrainingMining.value,
        'cawg.ai_training_and_data_mining',
      );
    });
  });
}
