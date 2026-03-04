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

// Integration tests for C2PA Sign-Read Roundtrip
//
// These tests verify end-to-end workflow: signing an asset then reading back the manifest.

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
  late Uint8List testImageBytes;

  setUpAll(() async {
    c2pa = C2pa();
    tempDir = await getTemporaryDirectory();

    testCert = await rootBundle.loadString('assets/test_certs/test_es256_cert.pem');
    testKey = await rootBundle.loadString('assets/test_certs/test_es256_key.pem');

    final byteData = await rootBundle.load('assets/test_images/test_unsigned.jpg');
    testImageBytes = byteData.buffer.asUint8List();
  });

  group('Basic Roundtrip', () {
    testWidgets('sign bytes then read manifest', (tester) async {
      // Create manifest with specific content
      final manifest = jsonEncode({
        'claim_generator': 'c2pa_flutter_roundtrip_test/1.0',
        'title': 'Roundtrip Test Image',
        'format': 'image/jpeg',
        'assertions': [
          {
            'label': 'c2pa.actions',
            'data': {
              'actions': [
                {
                  'action': 'c2pa.created',
                  'softwareAgent': 'c2pa_flutter_roundtrip_test/1.0',
                }
              ]
            }
          }
        ]
      });

      final signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem: testCert,
        privateKeyPem: testKey,
      );

      // Sign the image
      final signResult = await c2pa.signBytes(
        sourceData: testImageBytes,
        mimeType: 'image/jpeg',
        manifestJson: manifest,
        signer: signer,
      );

      expect(signResult.signedData.length, greaterThan(testImageBytes.length));

      // Read back the manifest
      final readResult = await c2pa.readBytes(signResult.signedData, 'image/jpeg');
      expect(readResult, isNotNull);

      // Verify the manifest contains expected data
      final manifestData = jsonDecode(readResult!) as Map<String, dynamic>;
      expect(manifestData['active_manifest'], isNotNull);
    });

    testWidgets('sign file then read file manifest', (tester) async {
      final sourceFile = File('${tempDir.path}/roundtrip_source.jpg');
      final signedFile = File('${tempDir.path}/roundtrip_signed.jpg');

      await sourceFile.writeAsBytes(testImageBytes);

      final manifest = jsonEncode({
        'claim_generator': 'c2pa_flutter_file_test/1.0',
        'title': 'File Roundtrip Test',
        'format': 'image/jpeg',
        'assertions': [
          {
            'label': 'c2pa.actions',
            'data': {
              'actions': [
                {'action': 'c2pa.created'}
              ]
            }
          }
        ]
      });

      final signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem: testCert,
        privateKeyPem: testKey,
      );

      // Sign the file
      await c2pa.signFile(
        sourcePath: sourceFile.path,
        destPath: signedFile.path,
        manifestJson: manifest,
        signer: signer,
      );

      expect(await signedFile.exists(), true);

      // Read back the manifest
      final readResult = await c2pa.readFile(signedFile.path);
      expect(readResult, isNotNull);

      // Cleanup
      await sourceFile.delete();
      await signedFile.delete();
    });
  });

  group('Manifest Store Info Roundtrip', () {
    testWidgets('sign then read as ManifestStoreInfo', (tester) async {
      final manifest = jsonEncode({
        'claim_generator': 'c2pa_flutter_store_test/1.0',
        'title': 'ManifestStoreInfo Test',
        'format': 'image/jpeg',
        'assertions': [
          {
            'label': 'c2pa.actions',
            'data': {
              'actions': [
                {
                  'action': 'c2pa.created',
                  'digitalSourceType': 'http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture',
                  'softwareAgent': 'c2pa_flutter_test/1.0',
                }
              ]
            }
          }
        ]
      });

      final signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem: testCert,
        privateKeyPem: testKey,
      );

      final signResult = await c2pa.signBytes(
        sourceData: testImageBytes,
        mimeType: 'image/jpeg',
        manifestJson: manifest,
        signer: signer,
      );

      // Read as structured data
      final storeInfo = await c2pa.readManifestFromBytes(
        signResult.signedData,
        'image/jpeg',
      );

      expect(storeInfo, isNotNull);
      expect(storeInfo!.activeManifest, isNotNull);
      expect(storeInfo.manifests.isNotEmpty, true);

      // Check active manifest
      final active = storeInfo.active;
      expect(active, isNotNull);
      expect(active!.claimGenerator, contains('c2pa_flutter'));
    });

    testWidgets('verify assertions are preserved', (tester) async {
      final manifest = jsonEncode({
        'claim_generator': 'c2pa_flutter_assertions_test/1.0',
        'title': 'Assertions Test',
        'format': 'image/jpeg',
        'assertions': [
          {
            'label': 'c2pa.actions',
            'data': {
              'actions': [
                {
                  'action': 'c2pa.created',
                  'softwareAgent': 'test_agent/1.0',
                }
              ]
            }
          },
          {
            'label': 'stds.schema-org.CreativeWork',
            'data': {
              '@context': 'https://schema.org',
              '@type': 'CreativeWork',
              'author': [
                {
                  '@type': 'Person',
                  'name': 'Integration Test Author'
                }
              ]
            }
          }
        ]
      });

      final signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem: testCert,
        privateKeyPem: testKey,
      );

      final signResult = await c2pa.signBytes(
        sourceData: testImageBytes,
        mimeType: 'image/jpeg',
        manifestJson: manifest,
        signer: signer,
      );

      final storeInfo = await c2pa.readManifestFromBytes(
        signResult.signedData,
        'image/jpeg',
      );

      expect(storeInfo, isNotNull);
      final active = storeInfo!.active;
      expect(active, isNotNull);

      // Check that assertions are present
      expect(active!.assertions.isNotEmpty, true);

      // Find the actions assertion
      final actionsAssertion = active.assertions.firstWhere(
        (a) => a.label == 'c2pa.actions',
        orElse: () => throw StateError('Actions assertion not found'),
      );
      expect(actionsAssertion.data['actions'], isNotNull);
    });
  });

  group('Builder Roundtrip', () {
    testWidgets('builder sign then read manifest', (tester) async {
      final manifest = jsonEncode({
        'claim_generator': 'c2pa_flutter_builder_test/1.0',
        'title': 'Builder Roundtrip Test',
        'format': 'image/jpeg',
      });

      final builder = await c2pa.createBuilder(manifest);
      builder.setIntent(ManifestIntent.create, DigitalSourceType.digitalCapture);

      builder.addAction(ActionConfig(
        action: 'c2pa.created',
        softwareAgent: 'c2pa_flutter_builder_test/1.0',
        digitalSourceType: DigitalSourceType.digitalCapture,
      ));

      final signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem: testCert,
        privateKeyPem: testKey,
      );

      final result = await builder.sign(
        sourceData: testImageBytes,
        mimeType: 'image/jpeg',
        signer: signer,
      );

      builder.dispose();

      // Verify we can read the manifest back
      final storeInfo = await c2pa.readManifestFromBytes(
        result.signedData,
        'image/jpeg',
      );

      expect(storeInfo, isNotNull);
      expect(storeInfo!.active, isNotNull);
    });

    testWidgets('builder archive roundtrip', (tester) async {
      final manifest = jsonEncode({
        'claim_generator': 'c2pa_flutter_archive_test/1.0',
        'title': 'Archive Test Image',
        'format': 'image/jpeg',
      });

      // Create initial builder and configure it
      final builder1 = await c2pa.createBuilder(manifest);
      builder1.setIntent(ManifestIntent.create, DigitalSourceType.digitalCapture);

      // Export to archive
      final archive = await builder1.toArchive();
      builder1.dispose();

      expect(archive.data.isNotEmpty, true);

      // Create new builder from archive
      final builder2 = await c2pa.createBuilderFromArchive(archive.data);

      final signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem: testCert,
        privateKeyPem: testKey,
      );

      final result = await builder2.sign(
        sourceData: testImageBytes,
        mimeType: 'image/jpeg',
        signer: signer,
      );

      builder2.dispose();

      expect(result.signedData.isNotEmpty, true);
      expect(result.signedData.length, greaterThan(testImageBytes.length));
    });
  });

  group('Multiple Signing', () {
    testWidgets('sign same image multiple times', (tester) async {
      final signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem: testCert,
        privateKeyPem: testKey,
      );

      // First sign
      final manifest1 = jsonEncode({
        'claim_generator': 'c2pa_flutter_multi_test/1.0',
        'title': 'First Sign',
        'format': 'image/jpeg',
        'assertions': [
          {
            'label': 'c2pa.actions',
            'data': {
              'actions': [
                {'action': 'c2pa.created'}
              ]
            }
          }
        ]
      });

      final result1 = await c2pa.signBytes(
        sourceData: testImageBytes,
        mimeType: 'image/jpeg',
        manifestJson: manifest1,
        signer: signer,
      );

      // Second sign (editing the first)
      final manifest2 = jsonEncode({
        'claim_generator': 'c2pa_flutter_multi_test/1.0',
        'title': 'Second Sign - Edited',
        'format': 'image/jpeg',
        'assertions': [
          {
            'label': 'c2pa.actions',
            'data': {
              'actions': [
                {
                  'action': 'c2pa.edited',
                  'softwareAgent': 'c2pa_flutter_multi_test/1.0',
                }
              ]
            }
          }
        ]
      });

      final result2 = await c2pa.signBytes(
        sourceData: result1.signedData,
        mimeType: 'image/jpeg',
        manifestJson: manifest2,
        signer: signer,
      );

      // Read the final manifest
      final storeInfo = await c2pa.readManifestFromBytes(
        result2.signedData,
        'image/jpeg',
      );

      expect(storeInfo, isNotNull);
      // Should have multiple manifests (original + edited)
      expect(storeInfo!.manifests.length, greaterThanOrEqualTo(1));
    });
  });
}
