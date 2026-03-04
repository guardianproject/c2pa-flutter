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

// Integration tests for C2PA Signer API
//
// These tests verify the signing functionality on actual platform implementations.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:c2pa_flutter/c2pa.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late C2pa c2pa;
  late Directory tempDir;
  late String testCert;
  late String testKey;
  late String basicManifest;

  setUpAll(() async {
    c2pa = C2pa();
    tempDir = await getTemporaryDirectory();

    // Load test certificates and manifests
    testCert = await rootBundle.loadString('assets/test_certs/test_es256_cert.pem');
    testKey = await rootBundle.loadString('assets/test_certs/test_es256_key.pem');
    basicManifest = await rootBundle.loadString('assets/test_manifests/basic_manifest.json');
  });

  group('PemSigner', () {
    testWidgets('PemSigner construction with ES256', (tester) async {
      final signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem: testCert,
        privateKeyPem: testKey,
      );

      expect(signer.algorithm, SigningAlgorithm.es256);
      expect(signer.certificatePem, testCert);
      expect(signer.privateKeyPem, testKey);
      expect(signer.tsaUrl, isNull);
    });

    testWidgets('PemSigner with TSA URL', (tester) async {
      final signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem: testCert,
        privateKeyPem: testKey,
        tsaUrl: 'http://timestamp.example.com',
      );

      expect(signer.tsaUrl, 'http://timestamp.example.com');
    });

    testWidgets('PemSigner toMap produces correct map', (tester) async {
      final signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem: testCert,
        privateKeyPem: testKey,
        tsaUrl: 'http://timestamp.example.com',
      );

      final map = signer.toMap();
      expect(map['algorithm'], 'es256');
      expect(map['certificatePem'], testCert);
      expect(map['privateKeyPem'], testKey);
      expect(map['tsaUrl'], 'http://timestamp.example.com');
    });

    testWidgets('PemSigner fromMap round-trip', (tester) async {
      final original = PemSigner(
        algorithm: SigningAlgorithm.ps256,
        certificatePem: testCert,
        privateKeyPem: testKey,
      );

      final map = original.toMap();
      final restored = PemSigner.fromMap(map);

      expect(restored.algorithm, original.algorithm);
      expect(restored.certificatePem, original.certificatePem);
      expect(restored.privateKeyPem, original.privateKeyPem);
    });
  });

  group('Sign Bytes', () {
    testWidgets('signBytes signs JPEG image', (tester) async {
      final byteData = await rootBundle.load('assets/test_images/test_unsigned.jpg');
      final imageBytes = byteData.buffer.asUint8List();

      final signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem: testCert,
        privateKeyPem: testKey,
      );

      final result = await c2pa.signBytes(
        sourceData: imageBytes,
        mimeType: 'image/jpeg',
        manifestJson: basicManifest,
        signer: signer,
      );

      expect(result.signedData, isNotNull);
      expect(result.signedData.length, greaterThan(imageBytes.length));
    });

    testWidgets('signBytes produces SignResult with correct properties', (tester) async {
      final byteData = await rootBundle.load('assets/test_images/test_unsigned.jpg');
      final imageBytes = byteData.buffer.asUint8List();

      final signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem: testCert,
        privateKeyPem: testKey,
      );

      final result = await c2pa.signBytes(
        sourceData: imageBytes,
        mimeType: 'image/jpeg',
        manifestJson: basicManifest,
        signer: signer,
      );

      expect(result.signedDataSize, greaterThan(0));
      // The signed data should be larger due to embedded manifest
      expect(result.signedDataSize, greaterThan(imageBytes.length));
    });
  });

  group('Sign File', () {
    testWidgets('signFile creates signed output file', (tester) async {
      final byteData = await rootBundle.load('assets/test_images/test_unsigned.jpg');
      final imageBytes = byteData.buffer.asUint8List();

      final sourceFile = File('${tempDir.path}/source_to_sign.jpg');
      final destFile = File('${tempDir.path}/signed_output.jpg');

      await sourceFile.writeAsBytes(imageBytes);

      final signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem: testCert,
        privateKeyPem: testKey,
      );

      await c2pa.signFile(
        sourcePath: sourceFile.path,
        destPath: destFile.path,
        manifestJson: basicManifest,
        signer: signer,
      );

      expect(await destFile.exists(), true);
      final signedBytes = await destFile.readAsBytes();
      expect(signedBytes.length, greaterThan(imageBytes.length));

      // Cleanup
      await sourceFile.delete();
      await destFile.delete();
    });
  });

  group('Builder API', () {
    testWidgets('createBuilder creates ManifestBuilder', (tester) async {
      final builder = await c2pa.createBuilder(basicManifest);

      expect(builder, isNotNull);
      expect(builder.handle, greaterThan(0));

      builder.dispose();
    });

    testWidgets('ManifestBuilder can set intent', (tester) async {
      final builder = await c2pa.createBuilder(basicManifest);

      // Should not throw
      builder.setIntent(ManifestIntent.create, DigitalSourceType.digitalCapture);
      builder.setIntent(ManifestIntent.edit);

      builder.dispose();
    });

    testWidgets('ManifestBuilder can add actions', (tester) async {
      final builder = await c2pa.createBuilder(basicManifest);

      builder.addAction(ActionConfig(
        action: 'c2pa.created',
        softwareAgent: 'c2pa_flutter_test',
        digitalSourceType: DigitalSourceType.digitalCapture,
      ));

      builder.addAction(ActionConfig(
        action: 'c2pa.edited',
        when: DateTime.now(),
        softwareAgent: 'c2pa_flutter_test',
      ));

      builder.dispose();
    });

    testWidgets('ManifestBuilder sign produces result', (tester) async {
      final byteData = await rootBundle.load('assets/test_images/test_unsigned.jpg');
      final imageBytes = byteData.buffer.asUint8List();

      final builder = await c2pa.createBuilder(basicManifest);
      builder.setIntent(ManifestIntent.create, DigitalSourceType.digitalCapture);

      final signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem: testCert,
        privateKeyPem: testKey,
      );

      final result = await builder.sign(
        sourceData: imageBytes,
        mimeType: 'image/jpeg',
        signer: signer,
      );

      expect(result.signedData, isNotNull);
      expect(result.signedData.length, greaterThan(imageBytes.length));
      expect(result.manifestSize, greaterThan(0));

      builder.dispose();
    });

    testWidgets('ManifestBuilder toArchive produces archive', (tester) async {
      final builder = await c2pa.createBuilder(basicManifest);
      builder.setIntent(ManifestIntent.create, DigitalSourceType.digitalCapture);

      final archive = await builder.toArchive();

      expect(archive.data, isNotNull);
      expect(archive.data.length, greaterThan(0));

      builder.dispose();
    });
  });

  group('ActionConfig', () {
    testWidgets('ActionConfig toMap produces correct structure', (tester) async {
      final action = ActionConfig(
        action: 'c2pa.created',
        when: DateTime(2024, 1, 15, 10, 30),
        softwareAgent: 'test_agent/1.0',
        digitalSourceType: DigitalSourceType.digitalCapture,
      );

      final map = action.toMap();
      expect(map['action'], 'c2pa.created');
      expect(map['softwareAgent'], 'test_agent/1.0');
      expect(map['when'], contains('2024-01-15'));
      expect(map['digitalSourceType'], contains('digitalCapture'));
    });

    testWidgets('ActionConfig toJson produces valid JSON', (tester) async {
      final action = ActionConfig(
        action: 'c2pa.edited',
        softwareAgent: 'test_agent',
      );

      final jsonStr = action.toJson();
      expect(() => jsonDecode(jsonStr), returnsNormally);

      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(decoded['action'], 'c2pa.edited');
    });
  });

  group('IngredientConfig', () {
    testWidgets('IngredientConfig with defaults', (tester) async {
      final config = IngredientConfig();
      final map = config.toMap();

      expect(map['relationship'], 'componentOf');
    });

    testWidgets('IngredientConfig as parentOf', (tester) async {
      final config = IngredientConfig(
        title: 'Parent Asset',
        relationship: Relationship.parentOf,
      );

      final map = config.toMap();
      expect(map['title'], 'Parent Asset');
      expect(map['relationship'], 'parentOf');
    });

    testWidgets('IngredientConfig toJson produces valid JSON', (tester) async {
      final config = IngredientConfig(
        title: 'Test Ingredient',
        relationship: Relationship.componentOf,
      );

      final jsonStr = config.toJson();
      expect(() => jsonDecode(jsonStr), returnsNormally);
    });
  });
}
