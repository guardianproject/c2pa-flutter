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

  Future<Uint8List> unsignedJpeg() async =>
      (await rootBundle.load('assets/test_images/test_unsigned.jpg')).buffer
          .asUint8List();

  PemSigner validSigner() => PemSigner(
    algorithm: SigningAlgorithm.es256,
    certificatePem: testCert,
    privateKeyPem: testKey,
  );

  final manifest = jsonEncode({
    'claim_generator_info': [
          {'name': 'test', 'version': '1.0'},
        ],
    'title': 'Test',
    'format': 'image/jpeg',
  });

  group('Invalid Input - Reader', () {
    testWidgets('readFile with a missing path is an invalid argument', (
      tester,
    ) async {
      await expectLater(
        c2pa.readFile('/non/existent/path/image.jpg'),
        throwsA(isA<C2paInvalidArgumentException>()),
      );
    });

    testWidgets('readBytes with empty data throws', (tester) async {
      await expectLater(
        c2pa.readBytes(Uint8List(0), 'image/jpeg'),
        throwsA(isA<C2paException>()),
      );
    });

    testWidgets('readBytes with bytes that are not an image throws', (
      tester,
    ) async {
      final randomBytes = Uint8List.fromList(
        List.generate(100, (i) => i % 256),
      );
      await expectLater(
        c2pa.readBytes(randomBytes, 'image/jpeg'),
        throwsA(isA<C2paException>()),
      );
    });

    testWidgets('readBytes with an unsupported MIME type throws', (
      tester,
    ) async {
      await expectLater(
        c2pa.readBytes(await unsignedJpeg(), 'application/x-unsupported'),
        throwsA(isA<C2paException>()),
      );
    });
  });

  group('Invalid Input - Signer', () {
    Future<void> expectSignFails(PemSigner signer, {String? json}) async {
      await expectLater(
        c2pa.signBytes(
          sourceData: await unsignedJpeg(),
          mimeType: 'image/jpeg',
          manifestJson: json ?? manifest,
          signer: signer,
        ),
        throwsA(isA<C2paException>()),
      );
    }

    testWidgets('signBytes with an invalid certificate throws', (
      tester,
    ) async {
      await expectSignFails(
        PemSigner(
          algorithm: SigningAlgorithm.es256,
          certificatePem: 'INVALID_CERTIFICATE',
          privateKeyPem: testKey,
        ),
      );
    });

    testWidgets('signBytes with an invalid private key throws', (
      tester,
    ) async {
      await expectSignFails(
        PemSigner(
          algorithm: SigningAlgorithm.es256,
          certificatePem: testCert,
          privateKeyPem: 'INVALID_PRIVATE_KEY',
        ),
      );
    });

    testWidgets('signBytes with a key of another algorithm throws', (
      tester,
    ) async {
      // An ES256 key declared as ES384.
      await expectSignFails(
        PemSigner(
          algorithm: SigningAlgorithm.es384,
          certificatePem: testCert,
          privateKeyPem: testKey,
        ),
      );
    });

    testWidgets('signBytes with invalid manifest JSON throws', (tester) async {
      await expectSignFails(validSigner(), json: 'NOT_VALID_JSON{{{');
    });

    testWidgets('signBytes with empty source data throws', (tester) async {
      await expectLater(
        c2pa.signBytes(
          sourceData: Uint8List(0),
          mimeType: 'image/jpeg',
          manifestJson: manifest,
          signer: validSigner(),
        ),
        throwsA(isA<C2paException>()),
      );
    });

    testWidgets('signBytes with an unsupported MIME type throws', (
      tester,
    ) async {
      await expectLater(
        c2pa.signBytes(
          sourceData: await unsignedJpeg(),
          mimeType: 'application/x-unsupported',
          manifestJson: manifest,
          signer: validSigner(),
        ),
        throwsA(isA<C2paException>()),
      );
    });

    testWidgets('signFile with a missing source is an invalid argument', (
      tester,
    ) async {
      final dest = File('${tempDir.path}/missing_source_output.jpg');
      if (dest.existsSync()) dest.deleteSync();
      await expectLater(
        c2pa.signFile(
          sourcePath: '/non/existent/path.jpg',
          destPath: dest.path,
          manifestJson: manifest,
          signer: validSigner(),
        ),
        throwsA(isA<C2paInvalidArgumentException>()),
      );
      expect(dest.existsSync(), isFalse);
    });
  });

  group('Invalid Input - Builder', () {
    testWidgets('createBuilder with invalid JSON throws', (tester) async {
      await expectLater(
        c2pa.createBuilder('NOT_VALID_JSON{{{'),
        throwsA(isA<C2paException>()),
      );
    });

    testWidgets('createBuilderFromArchive with invalid data throws', (
      tester,
    ) async {
      await expectLater(
        c2pa.createBuilderFromArchive(Uint8List.fromList([1, 2, 3, 4])),
        throwsA(isA<C2paException>()),
      );
    });

    testWidgets('builder sign with an invalid signer throws', (tester) async {
      final builder = await c2pa.createBuilder(manifest);
      try {
        await expectLater(
          builder.sign(
            sourceData: await unsignedJpeg(),
            mimeType: 'image/jpeg',
            signer: const PemSigner(
              algorithm: SigningAlgorithm.es256,
              certificatePem: 'INVALID',
              privateKeyPem: 'INVALID',
            ),
          ),
          throwsA(isA<C2paException>()),
        );
      } finally {
        await builder.dispose();
      }
    });

    testWidgets('a disposed builder rejects further calls', (tester) async {
      final builder = await c2pa.createBuilder(manifest);
      await builder.dispose();
      expect(() => builder.setNoEmbed(), throwsStateError);
      expect(builder.toArchive, throwsStateError);
      // A second dispose does nothing.
      await builder.dispose();
    });

    testWidgets('dispose waits for a sign already in flight', (tester) async {
      final builder = await c2pa.createBuilder(manifest);
      await builder.setIntent(
        ManifestIntent.create,
        DigitalSourceType.digitalCapture,
      );
      final signing = builder.sign(
        sourceData: await unsignedJpeg(),
        mimeType: 'image/jpeg',
        signer: validSigner(),
      );
      final disposing = builder.dispose();
      final result = await signing;
      await disposing;
      expect(result.signedData, isNotEmpty);
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

      await expectLater(
        c2pa.readBytes(minimalJpeg, 'image/jpeg'),
        throwsA(isA<C2paException>()),
      );
    });

    testWidgets('a manifest without a created action is rejected', (
      tester,
    ) async {
      final byteData = await rootBundle.load('assets/test_images/test_unsigned.jpg');
      final imageBytes = byteData.buffer.asUint8List();

      final manifest = jsonEncode({
        'claim_generator_info': [
          {'name': 'test', 'version': '1.0'},
        ],
        'title': 'Empty Assertions Test',
        'format': 'image/jpeg',
        'assertions': [],
      });

      final signer = PemSigner(
        algorithm: SigningAlgorithm.es256,
        certificatePem: testCert,
        privateKeyPem: testKey,
      );

      // c2pa-rs requires the first action to be c2pa.created or c2pa.opened.
      await expectLater(
        c2pa.signBytes(
          sourceData: imageBytes,
          mimeType: 'image/jpeg',
          manifestJson: manifest,
          signer: signer,
        ),
        throwsA(isA<C2paSdkException>()),
      );
    });

    testWidgets('manifest with special characters in title', (tester) async {
      final byteData = await rootBundle.load('assets/test_images/test_unsigned.jpg');
      final imageBytes = byteData.buffer.asUint8List();

      final manifest = jsonEncode({
        'claim_generator_info': [
          {'name': 'test', 'version': '1.0'},
        ],
        'title': 'Test with special chars: !@#\$%^&*()_+-=[]{}|;\':",.<>?/',
        'format': 'image/jpeg',
        'assertions': [
          {
            'label': 'c2pa.actions',
            'data': {
              'actions': [
                {
                  'action': 'c2pa.created',
                  'digitalSourceType': 'http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture',
                }
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
      final store = await c2pa.readManifestFromBytes(
        result.signedData,
        'image/jpeg',
      );
      expect(
        store.active!.title,
        (jsonDecode(manifest) as Map<String, dynamic>)['title'],
      );
    });

    testWidgets('manifest with unicode in title', (tester) async {
      final byteData = await rootBundle.load('assets/test_images/test_unsigned.jpg');
      final imageBytes = byteData.buffer.asUint8List();

      final manifest = jsonEncode({
        'claim_generator_info': [
          {'name': 'test', 'version': '1.0'},
        ],
        'title': 'Unicode test: caf\u00e9, \u0395\u03bb\u03bb\u03b7\u03bd\u03b9\u03ba\u03ac, \u65e5\u672c\u8a9e',
        'format': 'image/jpeg',
        'assertions': [
          {
            'label': 'c2pa.actions',
            'data': {
              'actions': [
                {
                  'action': 'c2pa.created',
                  'digitalSourceType': 'http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture',
                }
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
      final store = await c2pa.readManifestFromBytes(
        result.signedData,
        'image/jpeg',
      );
      expect(
        store.active!.title,
        (jsonDecode(manifest) as Map<String, dynamic>)['title'],
      );
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
