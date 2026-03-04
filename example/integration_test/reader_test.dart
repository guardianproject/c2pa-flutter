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

// Integration tests for C2PA Reader API
//
// These tests verify the reader functionality on actual platform implementations.

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

  setUpAll(() async {
    c2pa = C2pa();
    tempDir = await getTemporaryDirectory();
  });

  group('Version API', () {
    testWidgets('getPlatformVersion returns non-empty string', (tester) async {
      final version = await c2pa.getPlatformVersion();
      expect(version, isNotNull);
      expect(version!.isNotEmpty, true);
    });

    testWidgets('getVersion returns C2PA library version', (tester) async {
      final version = await c2pa.getVersion();
      expect(version, isNotNull);
      expect(version!.isNotEmpty, true);
      // Version should contain numbers and dots
      expect(version.contains(RegExp(r'[\d.]')), true);
    });
  });

  group('Supported MIME Types', () {
    testWidgets('getSupportedReadMimeTypes returns list', (tester) async {
      final mimeTypes = await c2pa.getSupportedReadMimeTypes();
      expect(mimeTypes, isA<List<String>>());
      expect(mimeTypes.isNotEmpty, true);
      // Should include common image types
      expect(mimeTypes.contains('image/jpeg'), true);
    });

    testWidgets('getSupportedSignMimeTypes returns list', (tester) async {
      final mimeTypes = await c2pa.getSupportedSignMimeTypes();
      expect(mimeTypes, isA<List<String>>());
      expect(mimeTypes.isNotEmpty, true);
      // Should include JPEG at minimum
      expect(mimeTypes.contains('image/jpeg'), true);
    });
  });

  group('Read from Bytes', () {
    testWidgets('readBytes returns null for unsigned image', (tester) async {
      // Load test unsigned image from assets
      final byteData = await rootBundle.load('assets/test_images/test_unsigned.jpg');
      final imageBytes = byteData.buffer.asUint8List();

      // Read should return null for unsigned image
      final manifestJson = await c2pa.readBytes(imageBytes, 'image/jpeg');
      expect(manifestJson, isNull);
    });

    testWidgets('readManifestFromBytes returns null for unsigned image', (tester) async {
      final byteData = await rootBundle.load('assets/test_images/test_unsigned.jpg');
      final imageBytes = byteData.buffer.asUint8List();

      final storeInfo = await c2pa.readManifestFromBytes(imageBytes, 'image/jpeg');
      expect(storeInfo, isNull);
    });

    testWidgets('readBytes handles PNG format', (tester) async {
      final byteData = await rootBundle.load('assets/test_images/test_unsigned.png');
      final imageBytes = byteData.buffer.asUint8List();

      // Should return null for unsigned PNG
      final manifestJson = await c2pa.readBytes(imageBytes, 'image/png');
      expect(manifestJson, isNull);
    });
  });

  group('Read from File', () {
    testWidgets('readFile returns null for unsigned image', (tester) async {
      // Copy test image to temp directory for file-based tests
      final byteData = await rootBundle.load('assets/test_images/test_unsigned.jpg');
      final imageBytes = byteData.buffer.asUint8List();
      final testFile = File('${tempDir.path}/test_unsigned.jpg');
      await testFile.writeAsBytes(imageBytes);

      final manifestJson = await c2pa.readFile(testFile.path);
      expect(manifestJson, isNull);

      // Cleanup
      await testFile.delete();
    });

    testWidgets('readManifestFromFile returns null for unsigned image', (tester) async {
      final byteData = await rootBundle.load('assets/test_images/test_unsigned.jpg');
      final imageBytes = byteData.buffer.asUint8List();
      final testFile = File('${tempDir.path}/test_unsigned_manifest.jpg');
      await testFile.writeAsBytes(imageBytes);

      final storeInfo = await c2pa.readManifestFromFile(testFile.path);
      expect(storeInfo, isNull);

      await testFile.delete();
    });

    testWidgets('readManifestFromFile with detailed option', (tester) async {
      final byteData = await rootBundle.load('assets/test_images/test_unsigned.jpg');
      final imageBytes = byteData.buffer.asUint8List();
      final testFile = File('${tempDir.path}/test_unsigned_detailed.jpg');
      await testFile.writeAsBytes(imageBytes);

      final storeInfo = await c2pa.readManifestFromFile(
        testFile.path,
        options: const ReaderOptions(detailed: true),
      );
      expect(storeInfo, isNull);

      await testFile.delete();
    });
  });

  group('Reader Options', () {
    testWidgets('ReaderOptions can be constructed with defaults', (tester) async {
      const options = ReaderOptions();
      expect(options.detailed, false);
      expect(options.dataDir, isNull);
    });

    testWidgets('ReaderOptions can specify dataDir', (tester) async {
      final options = ReaderOptions(dataDir: tempDir.path);
      expect(options.dataDir, tempDir.path);
    });

    testWidgets('ReaderOptions toMap produces correct map', (tester) async {
      final options = ReaderOptions(detailed: true, dataDir: tempDir.path);
      final map = options.toMap();
      expect(map['detailed'], true);
      expect(map['dataDir'], tempDir.path);
    });
  });
}
