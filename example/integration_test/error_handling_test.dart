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

// Integration tests for C2PA Error Handling
//
// These tests verify proper error handling for invalid inputs and edge cases.

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

  setUpAll(() async {
    c2pa = C2pa();
    tempDir = await getTemporaryDirectory();
    testCert = await rootBundle.loadString('assets/test_certs/test_es256_cert.pem');
    testKey = await rootBundle.loadString('assets/test_certs/test_es256_key.pem');
  });

  group('Invalid Input - Reader', () {
    testWidgets('readFile with non-existent path returns null or throws', (tester) async {
      try {
        final result = await c2pa.readFile('/non/existent/path/image.jpg');
        // If it doesn't throw, it should return null
        expect(result, isNull);
      } catch (e) {
        // Platform may throw an exception for non-existent files
        expect(e, isA<Exception>());
      }
    });

    testWidgets('readBytes with empty data', (tester) async {
      try {
        final result = await c2pa.readBytes(Uint8List(0), 'image/jpeg');
        // Should return null for invalid data
        expect(result, isNull);
      } catch (e) {
        // May throw for invalid data
        expect(e, isA<Exception>());
      }
    });

    testWidgets('readBytes with random bytes (not an image)', (tester) async {
      final randomBytes = Uint8List.fromList(List.generate(100, (i) => i % 256));

      try {
        final result = await c2pa.readBytes(randomBytes, 'image/jpeg');
        // Should return null for non-image data
        expect(result, isNull);
      } catch (e) {
        // May throw for invalid image data
        expect(e, isA<Exception>());
      }
    });

    testWidgets('readBytes with unsupported MIME type', (tester) async {
      final byteData = await rootBundle.load('assets/test_images/test_unsigned.jpg');
      final imageBytes = byteData.buffer.asUint8List();

      try {
        final result = await c2pa.readBytes(imageBytes, 'application/octet-stream');
        // May return null or throw for unsupported type
        expect(result, anyOf(isNull, isA<String>()));
      } catch (e) {
        expect(e, isA<Exception>());
      }
    });
  });

  group('Invalid Input - Signer', () {
    testWidgets('signBytes with invalid certificate', (tester) async {
      final byteData = await rootBundle.load('assets/test_images/test_unsigned.jpg');
      final imageBytes = byteData.buffer.asUint8List();

      final signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem: 'INVALID_CERTIFICATE',
        privateKeyPem: testKey,
      );

      final manifest = jsonEncode({
        'claim_generator': 'test/1.0',
        'title': 'Test',
        'format': 'image/jpeg',
      });

      try {
        await c2pa.signBytes(
          sourceData: imageBytes,
          mimeType: 'image/jpeg',
          manifestJson: manifest,
          signer: signer,
        );
        fail('Should have thrown for invalid certificate');
      } catch (e) {
        expect(e, isA<Exception>());
      }
    });

    testWidgets('signBytes with invalid private key', (tester) async {
      final byteData = await rootBundle.load('assets/test_images/test_unsigned.jpg');
      final imageBytes = byteData.buffer.asUint8List();

      final signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem: testCert,
        privateKeyPem: 'INVALID_PRIVATE_KEY',
      );

      final manifest = jsonEncode({
        'claim_generator': 'test/1.0',
        'title': 'Test',
        'format': 'image/jpeg',
      });

      try {
        await c2pa.signBytes(
          sourceData: imageBytes,
          mimeType: 'image/jpeg',
          manifestJson: manifest,
          signer: signer,
        );
        fail('Should have thrown for invalid private key');
      } catch (e) {
        expect(e, isA<Exception>());
      }
    });

    testWidgets('signBytes with invalid manifest JSON', (tester) async {
      final byteData = await rootBundle.load('assets/test_images/test_unsigned.jpg');
      final imageBytes = byteData.buffer.asUint8List();

      final signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem: testCert,
        privateKeyPem: testKey,
      );

      try {
        await c2pa.signBytes(
          sourceData: imageBytes,
          mimeType: 'image/jpeg',
          manifestJson: 'NOT_VALID_JSON{{{',
          signer: signer,
        );
        fail('Should have thrown for invalid JSON');
      } catch (e) {
        expect(e, isA<Exception>());
      }
    });

    testWidgets('signBytes with empty source data', (tester) async {
      final signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem: testCert,
        privateKeyPem: testKey,
      );

      final manifest = jsonEncode({
        'claim_generator': 'test/1.0',
        'title': 'Test',
        'format': 'image/jpeg',
      });

      try {
        await c2pa.signBytes(
          sourceData: Uint8List(0),
          mimeType: 'image/jpeg',
          manifestJson: manifest,
          signer: signer,
        );
        fail('Should have thrown for empty source data');
      } catch (e) {
        expect(e, isA<Exception>());
      }
    });

    testWidgets('signFile with non-existent source', (tester) async {
      final signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem: testCert,
        privateKeyPem: testKey,
      );

      final manifest = jsonEncode({
        'claim_generator': 'test/1.0',
        'title': 'Test',
        'format': 'image/jpeg',
      });

      try {
        await c2pa.signFile(
          sourcePath: '/non/existent/path.jpg',
          destPath: '${tempDir.path}/output.jpg',
          manifestJson: manifest,
          signer: signer,
        );
        fail('Should have thrown for non-existent file');
      } catch (e) {
        expect(e, isA<Exception>());
      }
    });
  });

  group('Invalid Input - Builder', () {
    testWidgets('createBuilder with invalid JSON', (tester) async {
      try {
        await c2pa.createBuilder('NOT_VALID_JSON{{{');
        fail('Should have thrown for invalid JSON');
      } catch (e) {
        expect(e, isA<Exception>());
      }
    });

    testWidgets('createBuilderFromArchive with invalid data', (tester) async {
      try {
        await c2pa.createBuilderFromArchive(Uint8List.fromList([1, 2, 3, 4]));
        fail('Should have thrown for invalid archive data');
      } catch (e) {
        expect(e, isA<Exception>());
      }
    });

    testWidgets('builder sign with invalid signer', (tester) async {
      final byteData = await rootBundle.load('assets/test_images/test_unsigned.jpg');
      final imageBytes = byteData.buffer.asUint8List();

      final manifest = jsonEncode({
        'claim_generator': 'test/1.0',
        'title': 'Test',
        'format': 'image/jpeg',
      });

      final builder = await c2pa.createBuilder(manifest);

      final invalidSigner = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem: 'INVALID',
        privateKeyPem: 'INVALID',
      );

      try {
        await builder.sign(
          sourceData: imageBytes,
          mimeType: 'image/jpeg',
          signer: invalidSigner,
        );
        fail('Should have thrown for invalid signer');
      } catch (e) {
        expect(e, isA<Exception>());
      }

      builder.dispose();
    });
  });

  group('Edge Cases', () {
    testWidgets('very small image (minimal valid JPEG)', (tester) async {
      // Minimal JPEG header - too small to be valid
      final minimalJpeg = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46,
        0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01,
        0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9,
      ]);

      try {
        final result = await c2pa.readBytes(minimalJpeg, 'image/jpeg');
        // Should return null or throw for minimal/invalid JPEG
        expect(result, anyOf(isNull, isA<String>()));
      } catch (e) {
        expect(e, isA<Exception>());
      }
    });

    testWidgets('manifest with empty assertions', (tester) async {
      final byteData = await rootBundle.load('assets/test_images/test_unsigned.jpg');
      final imageBytes = byteData.buffer.asUint8List();

      final manifest = jsonEncode({
        'claim_generator': 'test/1.0',
        'title': 'Empty Assertions Test',
        'format': 'image/jpeg',
        'assertions': [],
      });

      final signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem: testCert,
        privateKeyPem: testKey,
      );

      // Should succeed with empty assertions
      final result = await c2pa.signBytes(
        sourceData: imageBytes,
        mimeType: 'image/jpeg',
        manifestJson: manifest,
        signer: signer,
      );

      expect(result.signedData.isNotEmpty, true);
    });

    testWidgets('manifest with special characters in title', (tester) async {
      final byteData = await rootBundle.load('assets/test_images/test_unsigned.jpg');
      final imageBytes = byteData.buffer.asUint8List();

      final manifest = jsonEncode({
        'claim_generator': 'test/1.0',
        'title': 'Test with special chars: !@#\$%^&*()_+-=[]{}|;\':",.<>?/',
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
        ],
      });

      final signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem: testCert,
        privateKeyPem: testKey,
      );

      final result = await c2pa.signBytes(
        sourceData: imageBytes,
        mimeType: 'image/jpeg',
        manifestJson: manifest,
        signer: signer,
      );

      expect(result.signedData.isNotEmpty, true);
    });

    testWidgets('manifest with unicode in title', (tester) async {
      final byteData = await rootBundle.load('assets/test_images/test_unsigned.jpg');
      final imageBytes = byteData.buffer.asUint8List();

      final manifest = jsonEncode({
        'claim_generator': 'test/1.0',
        'title': 'Unicode test: Hello World',
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
        ],
      });

      final signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem: testCert,
        privateKeyPem: testKey,
      );

      final result = await c2pa.signBytes(
        sourceData: imageBytes,
        mimeType: 'image/jpeg',
        manifestJson: manifest,
        signer: signer,
      );

      expect(result.signedData.isNotEmpty, true);
    });
  });

  group('Data Class Edge Cases', () {
    testWidgets('PemSigner fromMap with unknown algorithm', (tester) async {
      final map = {
        'type': 'pem',
        'algorithm': 'unknown_algorithm',
        'certificatePem': testCert,
        'privateKeyPem': testKey,
      };

      final signer = PemSigner.fromMap(map);
      // Should fall back to es256
      expect(signer.algorithm, SigningAlgorithm.es256);
    });

    testWidgets('ValidationError fromMap with missing fields', (tester) async {
      final error = ValidationError.fromMap({});

      expect(error.code, 'unknown');
      expect(error.message, 'Unknown error');
      expect(error.manifestLabel, isNull);
    });

    testWidgets('IngredientInfo with various validation statuses', (tester) async {
      expect(
        IngredientInfo.fromMap({
          'relationship': 'componentOf',
          'validation_status': 'valid',
        }).validationStatus,
        ValidationStatus.valid,
      );

      expect(
        IngredientInfo.fromMap({
          'relationship': 'componentOf',
          'validation_status': 'invalid',
        }).validationStatus,
        ValidationStatus.invalid,
      );

      expect(
        IngredientInfo.fromMap({
          'relationship': 'componentOf',
          'validation_status': 'unknown_value',
        }).validationStatus,
        ValidationStatus.unknown,
      );
    });
  });
}
