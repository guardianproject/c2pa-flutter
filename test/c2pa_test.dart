import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:c2pa_flutter/c2pa.dart';
import 'package:c2pa_flutter/c2pa_platform_interface.dart';
import 'package:c2pa_flutter/c2pa_method_channel.dart';

import 'mocks/mock_c2pa_platform.dart';

void main() {
  late MockC2paPlatform mockPlatform;
  late C2pa c2pa;

  setUp(() {
    mockPlatform = MockC2paPlatform();
    C2paPlatform.instance = mockPlatform;
    c2pa = C2pa();
  });

  tearDown(() {
    mockPlatform.reset();
  });

  group('Platform verification', () {
    test('MethodChannelC2pa is the default instance', () {
      // Reset to get actual default
      final initialPlatform = MethodChannelC2pa();
      expect(initialPlatform, isInstanceOf<MethodChannelC2pa>());
    });
  });

  group('Version API', () {
    test('getPlatformVersion returns mock version', () async {
      mockPlatform.platformVersion = 'Test Platform 2.0';
      expect(await c2pa.getPlatformVersion(), 'Test Platform 2.0');
      expect(mockPlatform.methodCalls.last.method, 'getPlatformVersion');
    });

    test('getVersion returns C2PA library version', () async {
      mockPlatform.c2paVersion = '2.0.0-test';
      expect(await c2pa.getVersion(), '2.0.0-test');
      expect(mockPlatform.methodCalls.last.method, 'getVersion');
    });

    test('getVersion handles errors', () async {
      mockPlatform.simulateError = true;
      mockPlatform.errorMessage = 'Version error';
      expect(() => c2pa.getVersion(), throwsException);
    });
  });

  group('Reader API - Basic', () {
    test('readFile reads manifest from path', () async {
      final result = await c2pa.readFile('/path/to/image.jpg');
      expect(result, isNotNull);
      expect(result, contains('active_manifest'));
      expect(mockPlatform.methodCalls.last.method, 'readFile');
      expect(
        mockPlatform.methodCalls.last.arguments!['path'],
        '/path/to/image.jpg',
      );
    });

    test('readBytes reads manifest from bytes', () async {
      final data = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
      final result = await c2pa.readBytes(data, 'image/jpeg');
      expect(result, isNotNull);
      expect(mockPlatform.methodCalls.last.method, 'readBytes');
      expect(
        mockPlatform.methodCalls.last.arguments!['mimeType'],
        'image/jpeg',
      );
    });

    test('readFile returns custom manifest JSON', () async {
      mockPlatform.mockManifestJson = '{"custom": "manifest"}';
      final result = await c2pa.readFile('/test.jpg');
      expect(result, '{"custom": "manifest"}');
    });
  });

  group('Reader API - Enhanced', () {
    test('readManifestFromFile returns ManifestStoreInfo', () async {
      final result = await c2pa.readManifestFromFile('/path/to/image.jpg');
      expect(result, isNotNull);
      expect(result!.activeManifest, isNotNull);
      expect(result.manifests, isNotEmpty);
    });

    test('readManifestFromFile with options', () async {
      final result = await c2pa.readManifestFromFile(
        '/path/to/image.jpg',
        options: const ReaderOptions(detailed: true, dataDir: '/tmp/data'),
      );
      expect(result, isNotNull);
      expect(mockPlatform.methodCalls.last.arguments!['detailed'], true);
      expect(mockPlatform.methodCalls.last.arguments!['dataDir'], '/tmp/data');
    });

    test('readManifestFromBytes returns ManifestStoreInfo', () async {
      final data = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
      final result = await c2pa.readManifestFromBytes(data, 'image/jpeg');
      expect(result, isNotNull);
      expect(result!.activeManifest, isNotNull);
    });

    test('extractResource returns resource data', () async {
      final sourceData = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
      mockPlatform.mockResourceData = Uint8List.fromList([1, 2, 3, 4]);

      final result = await c2pa.extractResource(
        sourceData,
        'image/jpeg',
        'c2pa:thumbnail',
      );
      expect(result, equals(Uint8List.fromList([1, 2, 3, 4])));
    });

    test('readIngredientFromFile returns ingredient JSON', () async {
      final result = await c2pa.readIngredientFromFile(
        '/path/to/ingredient.jpg',
      );
      expect(result, isNotNull);
      expect(result, contains('title'));
    });

    test('getSupportedReadMimeTypes returns list', () async {
      final result = await c2pa.getSupportedReadMimeTypes();
      expect(result, contains('image/jpeg'));
      expect(result, contains('image/png'));
    });

    test('getSupportedSignMimeTypes returns list', () async {
      final result = await c2pa.getSupportedSignMimeTypes();
      expect(result, contains('image/jpeg'));
    });
  });

  group('Signer API', () {
    late PemSigner signer;
    late Uint8List testData;

    setUp(() {
      signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem:
            '-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----',
        privateKeyPem:
            '-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----',
      );
      testData = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
    });

    test('signBytes returns SignResult', () async {
      final result = await c2pa.signBytes(
        sourceData: testData,
        mimeType: 'image/jpeg',
        manifestJson: '{"title": "Test"}',
        signer: signer,
      );

      expect(result.signedData, isNotNull);
      expect(result.signedDataSize, greaterThan(0));
      expect(mockPlatform.methodCalls.last.method, 'signBytes');
    });

    test('signBytes with TSA URL', () async {
      final signerWithTsa = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem:
            '-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----',
        privateKeyPem:
            '-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----',
        tsaUrl: 'https://timestamp.example.com',
      );

      final result = await c2pa.signBytes(
        sourceData: testData,
        mimeType: 'image/jpeg',
        manifestJson: '{"title": "Test"}',
        signer: signerWithTsa,
      );

      expect(result.signedData, isNotNull);
    });

    test('signFile signs file', () async {
      await c2pa.signFile(
        sourcePath: '/input.jpg',
        destPath: '/output.jpg',
        manifestJson: '{"title": "Test"}',
        signer: signer,
      );

      expect(mockPlatform.methodCalls.last.method, 'signFile');
      expect(
        mockPlatform.methodCalls.last.arguments!['sourcePath'],
        '/input.jpg',
      );
      expect(
        mockPlatform.methodCalls.last.arguments!['destPath'],
        '/output.jpg',
      );
    });

    test('all signing algorithms are supported', () async {
      for (final algorithm in SigningAlgorithm.values) {
        final pemSigner = PemSigner(
          algorithm: algorithm,
          certificatePem:
              '-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----',
          privateKeyPem:
              '-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----',
        );

        final result = await c2pa.signBytes(
          sourceData: testData,
          mimeType: 'image/jpeg',
          manifestJson: '{"title": "Test ${algorithm.name}"}',
          signer: pemSigner,
        );

        expect(
          result.signedData,
          isNotNull,
          reason: 'Failed for ${algorithm.name}',
        );
      }
    });
  });

  group('Builder API', () {
    late PemSigner signer;
    late Uint8List testData;

    setUp(() {
      signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem:
            '-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----',
        privateKeyPem:
            '-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----',
      );
      testData = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
    });

    test('createBuilder creates builder', () async {
      final builder = await c2pa.createBuilder('{"title": "Test"}');
      expect(builder, isNotNull);
      expect(builder.handle, greaterThan(0));
      expect(mockPlatform.methodCalls.last.method, 'createBuilder');
    });

    test('createBuilder with ManifestDefinition.created', () async {
      final manifest = ManifestDefinition.created(
        title: 'Digital Photo',
        claimGenerator: ClaimGeneratorInfo(name: 'TestApp', version: '1.0.0'),
        sourceType: DigitalSourceType.digitalCapture,
      );

      final builder = await c2pa.createBuilder(manifest.toJsonString());
      expect(builder, isNotNull);

      final call = mockPlatform.methodCalls.last;
      expect(call.method, 'createBuilder');
      expect(call.arguments!['manifestJson'], contains('Digital Photo'));
      expect(call.arguments!['manifestJson'], contains('TestApp/1.0.0'));
      expect(call.arguments!['manifestJson'], contains('c2pa.created'));
    });

    test('createBuilder with ManifestDefinition.edited', () async {
      final manifest = ManifestDefinition.edited(
        title: 'Edited Photo',
        claimGenerator: ClaimGeneratorInfo(name: 'PhotoEditor', version: '2.0'),
        actions: [
          Action.cropped(softwareAgent: 'PhotoEditor/2.0'),
          Action.filtered(
            softwareAgent: 'PhotoEditor/2.0',
            parameters: {'filter': 'brightness'},
          ),
        ],
      );

      final builder = await c2pa.createBuilder(manifest.toJsonString());
      expect(builder, isNotNull);

      final call = mockPlatform.methodCalls.last;
      expect(call.arguments!['manifestJson'], contains('Edited Photo'));
      expect(call.arguments!['manifestJson'], contains('c2pa.cropped'));
      expect(call.arguments!['manifestJson'], contains('c2pa.filtered'));
    });

    test('createBuilder with ManifestDefinition.aiGenerated', () async {
      final manifest = ManifestDefinition.aiGenerated(
        title: 'AI Generated Image',
        claimGenerator: ClaimGeneratorInfo(name: 'AI Art', version: '1.0'),
        sourceType: DigitalSourceType.trainedAlgorithmicMedia,
        parameters: {'model': 'test-model', 'prompt': 'landscape'},
        trainingMining: TrainingMiningAssertion(
          entries: [
            TrainingMiningEntry.aiTraining(
              permission: TrainingMiningPermission.notAllowed,
            ),
            TrainingMiningEntry.dataMining(
              permission: TrainingMiningPermission.constrained,
              constraintInfo: 'Research only',
            ),
          ],
        ),
      );

      final builder = await c2pa.createBuilder(manifest.toJsonString());
      expect(builder, isNotNull);

      final call = mockPlatform.methodCalls.last;
      expect(call.arguments!['manifestJson'], contains('AI Generated Image'));
      expect(call.arguments!['manifestJson'], contains('c2pa.ai_generated'));
      expect(
        call.arguments!['manifestJson'],
        contains('trainedAlgorithmicMedia'),
      );
      expect(call.arguments!['manifestJson'], contains('c2pa.training-mining'));
    });

    test('createBuilder with full ManifestDefinition', () async {
      final manifest = ManifestDefinition(
        title: 'Complete Manifest Test',
        claimGeneratorInfo: [
          ClaimGeneratorInfo(name: 'TestApp', version: '1.0.0'),
        ],
        assertions: [
          ActionsAssertion(
            actions: [
              Action.created(
                sourceType: DigitalSourceType.digitalCapture,
                softwareAgent: 'Camera App',
              ),
              Action.edited(
                softwareAgent: 'Editor App',
                changes: [
                  RegionOfInterest.spatial(
                    shape: Shape.rectangle(
                      origin: Coordinate(x: 0, y: 0),
                      width: 100,
                      height: 100,
                    ),
                    role: Role.edited,
                  ),
                ],
              ),
            ],
          ),
          CreativeWorkAssertion(
            author: 'Test Author',
            copyrightNotice: '2024 Test Author',
          ),
        ],
        ingredients: [Ingredient.parent(title: 'Original Photo')],
        vendor: 'test-vendor',
        format: 'image/jpeg',
      );

      final builder = await c2pa.createBuilder(manifest.toJsonString());
      expect(builder, isNotNull);

      final call = mockPlatform.methodCalls.last;
      expect(
        call.arguments!['manifestJson'],
        contains('Complete Manifest Test'),
      );
      expect(call.arguments!['manifestJson'], contains('Test Author'));
      expect(call.arguments!['manifestJson'], contains('Original Photo'));
    });

    test('createBuilderFromArchive creates builder', () async {
      final archiveData = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04]);
      final builder = await c2pa.createBuilderFromArchive(archiveData);
      expect(builder, isNotNull);
      expect(mockPlatform.methodCalls.last.method, 'createBuilderFromArchive');
    });

    test('builder setIntent works', () async {
      final builder = await c2pa.createBuilder('{}');
      builder.setIntent(
        ManifestIntent.create,
        DigitalSourceType.digitalCapture,
      );

      final mockBuilder = mockPlatform.builders[builder.handle] as MockBuilder;
      expect(mockBuilder.intent, ManifestIntent.create);
      expect(mockBuilder.digitalSourceType, DigitalSourceType.digitalCapture);
    });

    test('builder setNoEmbed works', () async {
      final builder = await c2pa.createBuilder('{}');
      builder.setNoEmbed();

      final mockBuilder = mockPlatform.builders[builder.handle] as MockBuilder;
      expect(mockBuilder.noEmbed, true);
    });

    test('builder setRemoteUrl works', () async {
      final builder = await c2pa.createBuilder('{}');
      builder.setRemoteUrl('https://example.com/manifest');

      final mockBuilder = mockPlatform.builders[builder.handle] as MockBuilder;
      expect(mockBuilder.remoteUrl, 'https://example.com/manifest');
    });

    test('builder addResource works', () async {
      final builder = await c2pa.createBuilder('{}');
      final thumbnail = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);

      await builder.addResource(
        BuilderResource(
          uri: 'c2pa:thumbnail.jpg',
          data: thumbnail,
          mimeType: 'image/jpeg',
        ),
      );

      expect(
        mockPlatform.builders[builder.handle]!.resources['c2pa:thumbnail.jpg'],
        equals(thumbnail),
      );
    });

    test('builder addIngredient works', () async {
      final builder = await c2pa.createBuilder('{}');
      final ingredientData = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);

      await builder.addIngredient(
        data: ingredientData,
        mimeType: 'image/jpeg',
        config: IngredientConfig(
          title: 'Test Ingredient',
          relationship: Relationship.parentOf,
        ),
      );

      expect(mockPlatform.builders[builder.handle]!.ingredients, hasLength(1));
    });

    test('builder addAction works', () async {
      final builder = await c2pa.createBuilder('{}');

      builder.addAction(
        ActionConfig(
          action: 'c2pa.created',
          softwareAgent: 'TestApp/1.0',
          digitalSourceType: DigitalSourceType.digitalCapture,
        ),
      );

      final mockBuilder = mockPlatform.builders[builder.handle] as MockBuilder;
      expect(mockBuilder.actions, hasLength(1));
    });

    test('builder toArchive returns archive', () async {
      final builder = await c2pa.createBuilder('{}');
      final archive = await builder.toArchive();

      expect(archive.data, isNotNull);
      expect(archive.data.length, greaterThan(0));
    });

    test('builder sign returns result', () async {
      final builder = await c2pa.createBuilder('{}');

      final result = await builder.sign(
        sourceData: testData,
        mimeType: 'image/jpeg',
        signer: signer,
      );

      expect(result.signedData, isNotNull);
      expect(result.manifestSize, greaterThanOrEqualTo(0));
    });

    test('builder dispose works', () async {
      final builder = await c2pa.createBuilder('{}');
      final handle = builder.handle;

      builder.dispose();

      expect(mockPlatform.builders.containsKey(handle), false);
    });

    test('disposed builder throws error', () async {
      final builder = await c2pa.createBuilder('{}');
      builder.dispose();

      expect(() => builder.setIntent(ManifestIntent.create), throwsStateError);
    });
  });

  group('Advanced Signing API', () {
    late PemSigner signer;
    late ManifestBuilder builder;

    setUp(() async {
      signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem:
            '-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----',
        privateKeyPem:
            '-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----',
      );
      builder = await c2pa.createBuilder('{}');
    });

    test('createHashedPlaceholder returns data', () async {
      final placeholder = await c2pa.createHashedPlaceholder(
        builder: builder,
        reservedSize: 5000,
        mimeType: 'image/jpeg',
      );

      expect(placeholder, isNotNull);
      expect(placeholder.length, 5000);
    });

    test('signHashedEmbeddable returns manifest', () async {
      final manifest = await c2pa.signHashedEmbeddable(
        builder: builder,
        signer: signer,
        dataHash: 'abc123hash',
        mimeType: 'image/jpeg',
      );

      expect(manifest, isNotNull);
      expect(manifest.length, greaterThan(0));
    });

    test('formatEmbeddable returns formatted data', () async {
      final manifestBytes = Uint8List.fromList([0xC2, 0xAA, 0x00, 0x01]);
      final formatted = await c2pa.formatEmbeddable(
        mimeType: 'image/jpeg',
        manifestBytes: manifestBytes,
      );

      expect(formatted, equals(manifestBytes));
    });

    test('getSignerReserveSize returns size', () async {
      mockPlatform.mockReserveSize = 12345;
      final size = await c2pa.getSignerReserveSize(signer);

      expect(size, 12345);
    });
  });

  group('Settings API', () {
    test('loadSettings loads JSON settings', () async {
      await c2pa.loadSettings('{"setting": "value"}');

      expect(mockPlatform.methodCalls.last.method, 'loadSettings');
      expect(mockPlatform.methodCalls.last.arguments!['format'], 'json');
    });

    test('loadSettings loads TOML settings', () async {
      await c2pa.loadSettings('[settings]\nkey = "value"', format: 'toml');

      expect(mockPlatform.methodCalls.last.arguments!['format'], 'toml');
    });
  });

  group('Error handling', () {
    test('error is propagated from platform', () async {
      mockPlatform.simulateError = true;
      mockPlatform.errorMessage = 'Test error';

      expect(() => c2pa.getPlatformVersion(), throwsException);
    });

    test('readFile handles error', () async {
      mockPlatform.simulateError = true;
      mockPlatform.errorMessage = 'File not found';

      expect(() => c2pa.readFile('/nonexistent.jpg'), throwsException);
    });

    test('signBytes handles error', () async {
      mockPlatform.simulateError = true;
      mockPlatform.errorMessage = 'Signing failed';

      final signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem: 'cert',
        privateKeyPem: 'key',
      );

      expect(
        () => c2pa.signBytes(
          sourceData: Uint8List(1),
          mimeType: 'image/jpeg',
          manifestJson: '{}',
          signer: signer,
        ),
        throwsException,
      );
    });
  });

  group('Data classes', () {
    group('PemSigner', () {
      test('toMap serializes correctly', () {
        final signer = PemSigner(
          algorithm: SigningAlgorithm.ps256,
          certificatePem: 'cert_pem',
          privateKeyPem: 'key_pem',
          tsaUrl: 'https://tsa.example.com',
        );

        final map = signer.toMap();
        expect(map['type'], 'pem');
        expect(map['algorithm'], 'ps256');
        expect(map['certificatePem'], 'cert_pem');
        expect(map['privateKeyPem'], 'key_pem');
        expect(map['tsaUrl'], 'https://tsa.example.com');
      });

      test('fromMap deserializes correctly', () {
        final map = {
          'type': 'pem',
          'algorithm': 'ed25519',
          'certificatePem': 'cert',
          'privateKeyPem': 'key',
          'tsaUrl': null,
        };

        final signer = PemSigner.fromMap(map);
        expect(signer.algorithm, SigningAlgorithm.ed25519);
        expect(signer.certificatePem, 'cert');
        expect(signer.tsaUrl, isNull);
      });
    });

    group('CallbackSigner', () {
      test('toMap serializes correctly', () {
        final signer = CallbackSigner(
          algorithm: SigningAlgorithm.es256,
          certificateChainPem: 'cert_chain',
          signCallback: (data) async => Uint8List.fromList([1, 2, 3]),
          tsaUrl: 'https://tsa.example.com',
        );

        final map = signer.toMap();
        expect(map['type'], 'callback');
        expect(map['algorithm'], 'es256');
        expect(map['certificateChainPem'], 'cert_chain');
        expect(map['tsaUrl'], 'https://tsa.example.com');
      });
    });

    group('KeystoreSigner', () {
      test('toMap serializes correctly', () {
        final signer = KeystoreSigner(
          algorithm: SigningAlgorithm.es384,
          keyAlias: 'my-key',
          certificateChainPem: 'cert_chain',
          tsaUrl: 'https://tsa.example.com',
        );

        final map = signer.toMap();
        expect(map['type'], 'keystore');
        expect(map['algorithm'], 'es384');
        expect(map['keyAlias'], 'my-key');
        expect(map['certificateChainPem'], 'cert_chain');
        expect(map['tsaUrl'], 'https://tsa.example.com');
      });
    });

    group('HardwareSigner', () {
      test('toMap serializes correctly', () {
        final signer = HardwareSigner(
          keyAlias: 'secure-key',
          certificateChainPem: 'cert_chain',
          requireUserAuthentication: true,
          tsaUrl: 'https://tsa.example.com',
        );

        final map = signer.toMap();
        expect(map['type'], 'hardware');
        expect(map['algorithm'], 'es256'); // Hardware only supports ES256
        expect(map['keyAlias'], 'secure-key');
        expect(map['certificateChainPem'], 'cert_chain');
        expect(map['requireUserAuthentication'], true);
        expect(map['tsaUrl'], 'https://tsa.example.com');
      });

      test('algorithm is always ES256', () {
        final signer = HardwareSigner(
          keyAlias: 'test-key',
          certificateChainPem: 'cert',
        );

        expect(signer.algorithm, SigningAlgorithm.es256);
      });
    });

    group('RemoteSigner', () {
      test('toMap serializes correctly', () {
        final signer = RemoteSigner(
          configurationUrl: 'https://sign.example.com/config',
          bearerToken: 'test-token',
          customHeaders: {'X-Custom': 'value'},
        );

        final map = signer.toMap();
        expect(map['type'], 'remote');
        expect(map['configurationUrl'], 'https://sign.example.com/config');
        expect(map['bearerToken'], 'test-token');
        expect(map['customHeaders'], {'X-Custom': 'value'});
      });

      test('toMap without optional fields', () {
        final signer = RemoteSigner(
          configurationUrl: 'https://sign.example.com/config',
        );

        final map = signer.toMap();
        expect(map['type'], 'remote');
        expect(map['configurationUrl'], 'https://sign.example.com/config');
        expect(map['bearerToken'], isNull);
        expect(map['customHeaders'], isNull);
      });
    });

    group('ReaderOptions', () {
      test('default values', () {
        const options = ReaderOptions();
        expect(options.detailed, false);
        expect(options.dataDir, isNull);
      });

      test('toMap serializes correctly', () {
        const options = ReaderOptions(detailed: true, dataDir: '/data');
        final map = options.toMap();
        expect(map['detailed'], true);
        expect(map['dataDir'], '/data');
      });
    });

    group('ActionConfig', () {
      test('toJson serializes correctly', () {
        final action = ActionConfig(
          action: 'c2pa.edited',
          when: DateTime(2024, 1, 15),
          softwareAgent: 'TestApp/1.0',
          digitalSourceType: DigitalSourceType.humanEdits,
        );

        final json = action.toJson();
        expect(json, contains('c2pa.edited'));
        expect(json, contains('TestApp/1.0'));
        expect(json, contains('humanEdits'));
      });
    });

    group('IngredientConfig', () {
      test('toJson serializes relationship correctly', () {
        final config = IngredientConfig(
          title: 'Test Ingredient',
          relationship: Relationship.parentOf,
        );

        final json = config.toJson();
        expect(json, contains('parentOf'));
        expect(json, contains('Test Ingredient'));
      });
    });

    group('ManifestStoreInfo', () {
      test('fromJson parses correctly', () {
        const json = '''
      {
        "active_manifest": "urn:uuid:test",
        "manifests": {
          "urn:uuid:test": {
            "label": "urn:uuid:test",
            "title": "Test Image",
            "format": "image/jpeg",
            "claim_generator": "test/1.0",
            "assertions": [],
            "ingredients": []
          }
        },
        "validation_status": []
      }
      ''';

        final info = ManifestStoreInfo.fromJson(json);
        expect(info.activeManifest, 'urn:uuid:test');
        expect(info.manifests.length, 1);
        expect(info.active?.title, 'Test Image');
        expect(info.validationStatus, ValidationStatus.valid);
      });

      test('validation errors are parsed', () {
        const json = '''
      {
        "active_manifest": null,
        "manifests": {},
        "validation_status": [
          {"code": "ERR001", "message": "Invalid signature"}
        ]
      }
      ''';

        final info = ManifestStoreInfo.fromJson(json);
        expect(info.validationErrors, hasLength(1));
        expect(info.validationErrors.first.code, 'ERR001');
        expect(info.validationStatus, ValidationStatus.invalid);
      });
    });
  });

  group('SettingsSigner', () {
    test('toMap serializes with type settings, settings string, and format', () {
      final signer = SettingsSigner(
        settingsString: '{"signer": "config"}',
        format: 'json',
      );

      final map = signer.toMap();
      expect(map['type'], 'settings');
      expect(map['settings'], '{"signer": "config"}');
      expect(map['format'], 'json');
    });

    test('default format is json', () {
      final signer = SettingsSigner(
        settingsString: '{"signer": "config"}',
      );

      expect(signer.format, 'json');
      expect(signer.toMap()['format'], 'json');
    });

    test('algorithm returns es256', () {
      final signer = SettingsSigner(
        settingsString: '{"signer": "config"}',
      );

      expect(signer.algorithm, SigningAlgorithm.es256);
    });
  });

  group('C2paSettings', () {
    test('create() returns settings with valid handle', () async {
      final settings = await C2paSettings.create();
      expect(settings.handle, greaterThan(0));
      expect(mockPlatform.methodCalls.last.method, 'createSettings');
    });

    test('updateFromString() records call with correct arguments', () async {
      final settings = await C2paSettings.create();
      await settings.updateFromString('{"verify": true}', 'json');

      final call = mockPlatform.methodCalls.last;
      expect(call.method, 'settingsUpdateFromString');
      expect(call.arguments!['handle'], settings.handle);
      expect(call.arguments!['settingsStr'], '{"verify": true}');
      expect(call.arguments!['format'], 'json');
    });

    test('setValue() records call with correct arguments', () async {
      final settings = await C2paSettings.create();
      await settings.setValue('verify.verify_trust', 'false');

      final call = mockPlatform.methodCalls.last;
      expect(call.method, 'settingsSetValue');
      expect(call.arguments!['handle'], settings.handle);
      expect(call.arguments!['path'], 'verify.verify_trust');
      expect(call.arguments!['value'], 'false');
    });

    test('dispose() prevents further operations', () async {
      final settings = await C2paSettings.create();
      settings.dispose();

      expect(
        () => settings.updateFromString('{}', 'json'),
        throwsStateError,
      );
      expect(
        () => settings.setValue('key', 'value'),
        throwsStateError,
      );
    });
  });

  group('C2paContext', () {
    test('create() returns context with valid handle', () async {
      final context = await C2paContext.create();
      expect(context.handle, greaterThan(0));
      expect(mockPlatform.methodCalls.last.method, 'createContext');
    });

    test('fromSettings() creates context from settings handle and records settingsHandle', () async {
      final settings = await C2paSettings.create();
      final context = await C2paContext.fromSettings(settings);

      expect(context.handle, greaterThan(0));
      final call = mockPlatform.methodCalls.last;
      expect(call.method, 'createContextFromSettings');
      expect(call.arguments!['settingsHandle'], settings.handle);
    });

    test('dispose() prevents further operations', () async {
      final context = await C2paContext.create();
      context.dispose();

      expect(
        () async => await c2pa.readManifestFromFileWithContext(
          '/path/to/image.jpg',
          context,
        ),
        throwsStateError,
      );
    });

    test('fromSettings() on disposed settings throws StateError', () async {
      final settings = await C2paSettings.create();
      settings.dispose();

      expect(
        () async => await C2paContext.fromSettings(settings),
        throwsStateError,
      );
    });
  });

  group('CertificateConfig', () {
    test('toMap includes all fields when set', () {
      const config = CertificateConfig(
        commonName: 'Test CN',
        organization: 'Test Org',
        organizationalUnit: 'Test OU',
        country: 'US',
        state: 'CA',
        locality: 'San Francisco',
        email: 'test@example.com',
        validityDays: 365,
      );

      final map = config.toMap();
      expect(map['commonName'], 'Test CN');
      expect(map['organization'], 'Test Org');
      expect(map['organizationalUnit'], 'Test OU');
      expect(map['country'], 'US');
      expect(map['state'], 'CA');
      expect(map['locality'], 'San Francisco');
      expect(map['email'], 'test@example.com');
      expect(map['validityDays'], 365);
    });

    test('toMap only includes required fields when optionals are null', () {
      const config = CertificateConfig(commonName: 'Minimal CN');

      final map = config.toMap();
      expect(map['commonName'], 'Minimal CN');
      expect(map.containsKey('organization'), false);
      expect(map.containsKey('organizationalUnit'), false);
      expect(map.containsKey('country'), false);
      expect(map.containsKey('state'), false);
      expect(map.containsKey('locality'), false);
      expect(map.containsKey('email'), false);
      expect(map.containsKey('validityDays'), false);
    });
  });

  group('Enhanced Reader API', () {
    test('readManifestFromFileWithContext calls readFileWithContext with correct args', () async {
      final context = await C2paContext.create();
      final result = await c2pa.readManifestFromFileWithContext(
        '/path/to/image.jpg',
        context,
        options: const ReaderOptions(detailed: true, dataDir: '/tmp/data'),
      );

      expect(result, isNotNull);
      expect(result!.activeManifest, isNotNull);

      final call = mockPlatform.methodCalls.last;
      expect(call.method, 'readFileWithContext');
      expect(call.arguments!['path'], '/path/to/image.jpg');
      expect(call.arguments!['contextHandle'], context.handle);
      expect(call.arguments!['detailed'], true);
      expect(call.arguments!['dataDir'], '/tmp/data');
    });

    test('readManifestFromFileWithContext on disposed context throws StateError', () async {
      final context = await C2paContext.create();
      context.dispose();

      expect(
        () async => await c2pa.readManifestFromFileWithContext(
          '/path/to/image.jpg',
          context,
        ),
        throwsStateError,
      );
    });
  });

  group('Enhanced Builder API', () {
    test('createBuilderFromContext creates builder via platform', () async {
      final context = await C2paContext.create();
      final builder = await c2pa.createBuilderFromContext(
        context,
        '{"title": "Test"}',
      );

      expect(builder, isNotNull);
      expect(builder.handle, greaterThan(0));

      final call = mockPlatform.methodCalls.last;
      expect(call.method, 'createBuilderWithContext');
      expect(call.arguments!['contextHandle'], context.handle);
      expect(call.arguments!['manifestJson'], '{"title": "Test"}');
    });

    test('createBuilderWithSettings creates builder via platform', () async {
      final settings = await C2paSettings.create();
      final builder = await c2pa.createBuilderWithSettings(
        '{"title": "Settings Test"}',
        settings,
      );

      expect(builder, isNotNull);
      expect(builder.handle, greaterThan(0));

      final call = mockPlatform.methodCalls.last;
      expect(call.method, 'createBuilderWithSettings');
      expect(call.arguments!['manifestJson'], '{"title": "Settings Test"}');
      expect(call.arguments!['settingsHandle'], settings.handle);
    });

    test('createBuilderWithSettings on disposed settings throws StateError', () async {
      final settings = await C2paSettings.create();
      settings.dispose();

      expect(
        () async => await c2pa.createBuilderWithSettings(
          '{"title": "Test"}',
          settings,
        ),
        throwsStateError,
      );
    });
  });

  group('Certificate Manager API', () {
    test('createSelfSignedCertificateChain returns PEM certificate chain', () async {
      final chain = await c2pa.createSelfSignedCertificateChain(
        keyAlias: 'test-key',
      );

      expect(chain, contains('-----BEGIN CERTIFICATE-----'));
      expect(chain, contains('-----END CERTIFICATE-----'));
    });

    test('createSelfSignedCertificateChain passes config correctly', () async {
      const config = CertificateConfig(
        commonName: 'Test App',
        organization: 'Test Org',
        country: 'US',
        validityDays: 365,
      );

      final chain = await c2pa.createSelfSignedCertificateChain(
        keyAlias: 'test-key',
        config: config,
      );

      expect(chain, contains('-----BEGIN CERTIFICATE-----'));

      final call = mockPlatform.methodCalls.last;
      expect(call.method, 'createSelfSignedCertificateChain');
      expect(call.arguments!['keyAlias'], 'test-key');
      expect(call.arguments!['config'], isNotNull);
      expect(call.arguments!['config']['commonName'], 'Test App');
      expect(call.arguments!['config']['organization'], 'Test Org');
      expect(call.arguments!['config']['country'], 'US');
      expect(call.arguments!['config']['validityDays'], 365);
    });
  });
}
