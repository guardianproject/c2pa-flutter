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
// These tests read unsigned assets and an asset signed by a third party
// (adobe_20220124_ci.jpg, from the upstream SDK fixtures) on the device.

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
  late Uint8List unsignedJpeg;
  late Uint8List unsignedPng;
  late Uint8List adobeJpeg;
  late String adobePath;

  Future<Uint8List> asset(String name) async =>
      (await rootBundle.load('assets/test_images/$name')).buffer.asUint8List();

  setUpAll(() async {
    c2pa = C2pa();
    tempDir = await getTemporaryDirectory();
    unsignedJpeg = await asset('test_unsigned.jpg');
    unsignedPng = await asset('test_unsigned.png');
    adobeJpeg = await asset('adobe_20220124_ci.jpg');
    adobePath = '${tempDir.path}/adobe_20220124_ci.jpg';
    await File(adobePath).writeAsBytes(adobeJpeg);
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
      expect(version!, contains(RegExp(r'\d+\.\d+')));
    });
  });

  group('Supported MIME Types', () {
    testWidgets('read and sign lists include the common formats', (
      tester,
    ) async {
      final read = await c2pa.getSupportedReadMimeTypes();
      final sign = await c2pa.getSupportedSignMimeTypes();
      expect(read, containsAll(['image/jpeg', 'image/png', 'video/mp4']));
      expect(sign, containsAll(['image/jpeg', 'image/png', 'video/mp4']));
    });
  });

  group('Assets without a manifest', () {
    testWidgets('every read of an unsigned JPEG throws manifest not found', (
      tester,
    ) async {
      final path = '${tempDir.path}/test_unsigned.jpg';
      await File(path).writeAsBytes(unsignedJpeg);
      final notFound = throwsA(isA<C2paManifestNotFoundException>());

      await expectLater(c2pa.readFile(path), notFound);
      await expectLater(c2pa.readBytes(unsignedJpeg, 'image/jpeg'), notFound);
      await expectLater(c2pa.readManifestFromFile(path), notFound);
      await expectLater(
        c2pa.readManifestFromBytes(
          unsignedJpeg,
          'image/jpeg',
          options: const ReaderOptions(detailed: true),
        ),
        notFound,
      );
      await expectLater(c2pa.isManifestEmbedded(path), notFound);
    });

    testWidgets('an unsigned PNG throws manifest not found', (tester) async {
      await expectLater(
        c2pa.readBytes(unsignedPng, 'image/png'),
        throwsA(isA<C2paManifestNotFoundException>()),
      );
    });
  });

  group('Asset signed by a third party', () {
    testWidgets('reads the manifest store from a file and from bytes', (
      tester,
    ) async {
      final fromFile = await c2pa.readManifestFromFile(adobePath);
      final fromBytes = await c2pa.readManifestFromBytes(
        adobeJpeg,
        'image/jpeg',
      );

      expect(fromFile.activeManifest, isNotNull);
      expect(fromBytes.activeManifest, fromFile.activeManifest);
      final active = fromFile.active!;
      expect(active.claimGenerator ?? '', isNotEmpty);
      expect(active.ingredients, isNotEmpty);
      expect(active.signature?.issuer, isNotNull);
    });

    testWidgets('the raw JSON matches the parsed store', (tester) async {
      final json = jsonDecode(await c2pa.readFile(adobePath))
          as Map<String, dynamic>;
      final store = await c2pa.readManifestFromFile(adobePath);
      expect(json['active_manifest'], store.activeManifest);
      expect((json['manifests'] as Map).length, store.manifests.length);
    });

    testWidgets('extracts the thumbnail the manifest references', (
      tester,
    ) async {
      final store = await c2pa.readManifestFromFile(adobePath);
      final uri = store.active!.thumbnailUri;
      expect(uri, isNotNull);

      final thumbnail = await c2pa.extractResource(
        adobeJpeg,
        'image/jpeg',
        uri!,
      );
      // A JPEG thumbnail starts with the SOI marker.
      expect(thumbnail.length, greaterThan(100));
      expect(thumbnail.sublist(0, 2), [0xFF, 0xD8]);
    });

    testWidgets('reports an embedded manifest with no remote URL', (
      tester,
    ) async {
      expect(await c2pa.isManifestEmbedded(adobePath), isTrue);
      expect(await c2pa.getRemoteUrl(adobePath), isNull);
    });

    testWidgets('reads as crJSON', (tester) async {
      final crJson = jsonDecode(await c2pa.readCrJsonFromFile(adobePath));
      expect(crJson, isA<Map<String, dynamic>>());
      expect(crJson as Map<String, dynamic>, isNotEmpty);
    });
  });

  group('Reader Options', () {
    testWidgets('ReaderOptions can be constructed with defaults', (
      tester,
    ) async {
      const options = ReaderOptions();
      expect(options.detailed, false);
      expect(options.context, isNull);
    });
  });
}
