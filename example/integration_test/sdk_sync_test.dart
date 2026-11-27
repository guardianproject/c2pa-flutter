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

// Integration tests for the capabilities adopted from c2pa-swift 0.1.x and
// c2pa-android 0.1.x: context signers, progress, cancellation, HTTP
// resolvers, embeddable manifests, ingredient archives, crJSON, external
// manifests, CAWG identity signing and file-based builder signing.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:c2pa_flutter/c2pa.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late C2pa c2pa;
  late Directory tempDir;
  late String cert;
  late String key;
  late Uint8List jpeg;

  PemSigner pemSigner() => PemSigner(
    algorithm: SigningAlgorithm.es256,
    certificatePem: cert,
    privateKeyPem: key,
  );

  String manifest({String title = 'SDK sync test'}) => jsonEncode({
    'title': title,
    'claim_generator_info': [
      {'name': 'c2pa_flutter_sdk_sync_test', 'version': '1.0'},
    ],
  });

  String localSignerSettings({Map<String, dynamic> extra = const {}}) =>
      jsonEncode({
        'version': 1,
        'signer': {
          'local': {'alg': 'es256', 'sign_cert': cert, 'private_key': key},
        },
        ...extra,
      });

  Future<ManifestBuilder> contextBuilder(C2paContext context) async {
    final builder = await c2pa.createBuilderFromContext(context, manifest());
    await builder.setIntent(ManifestIntent.create, DigitalSourceType.digitalCapture);
    return builder;
  }

  setUpAll(() async {
    c2pa = C2pa();
    tempDir = await getTemporaryDirectory();
    cert = await rootBundle.loadString('assets/test_certs/test_es256_cert.pem');
    key = await rootBundle.loadString('assets/test_certs/test_es256_key.pem');
    final data = await rootBundle.load('assets/test_images/test_unsigned.jpg');
    jpeg = data.buffer.asUint8List();
  });

  group('SDK-provided MIME types', () {
    testWidgets('read and sign lists come from the SDK', (tester) async {
      final read = await c2pa.getSupportedReadMimeTypes();
      final sign = await c2pa.getSupportedSignMimeTypes();
      expect(read, contains('image/jpeg'));
      expect(sign, contains('image/jpeg'));
    });
  });

  group('Context signer', () {
    testWidgets('builder signs with the context signer', (tester) async {
      final context = await C2paContext.create(signer: pemSigner());
      final builder = await contextBuilder(context);
      try {
        final result = await builder.sign(
          sourceData: jpeg,
          mimeType: 'image/jpeg',
        );
        final store = await c2pa.readManifestFromBytes(
          result.signedData,
          'image/jpeg',
        );
        expect(store.activeManifest, isNotNull);
      } finally {
        await builder.dispose();
        await context.dispose();
      }
    });

    testWidgets('a signer defined in settings signs through the context', (
      tester,
    ) async {
      final settings = await C2paSettings.create();
      await settings.updateFromString(localSignerSettings(), 'json');
      final context = await C2paContext.create(settings: settings);
      final builder = await contextBuilder(context);
      try {
        final result = await builder.sign(
          sourceData: jpeg,
          mimeType: 'image/jpeg',
        );
        expect(result.signedData.length, greaterThan(jpeg.length));
      } finally {
        await builder.dispose();
        await context.dispose();
        await settings.dispose();
      }
    });

    testWidgets('SettingsSigner works for one-shot signBytes', (tester) async {
      final result = await c2pa.signBytes(
        sourceData: jpeg,
        mimeType: 'image/jpeg',
        manifestJson: jsonEncode({
          'title': 'Settings signer',
          'assertions': [
            {
              'label': 'c2pa.actions',
              'data': {
                'actions': [
                  {
                    'action': 'c2pa.created',
                    'digitalSourceType': DigitalSourceType.digitalCapture.url,
                  },
                ],
              },
            },
          ],
        }),
        signer: SettingsSigner(settingsString: localSignerSettings()),
      );
      expect(result.signedData.length, greaterThan(jpeg.length));
    });

    testWidgets('SettingsSigner passed to builder.sign is rejected', (
      tester,
    ) async {
      final builder = await c2pa.createBuilder(manifest());
      await builder.setIntent(
        ManifestIntent.create,
        DigitalSourceType.digitalCapture,
      );
      try {
        await expectLater(
          builder.sign(
            sourceData: jpeg,
            mimeType: 'image/jpeg',
            signer: SettingsSigner(settingsString: localSignerSettings()),
          ),
          throwsA(isA<C2paInvalidArgumentException>()),
        );
      } finally {
        await builder.dispose();
      }
    });

    testWidgets('signing without any signer fails cleanly', (tester) async {
      final context = await C2paContext.create();
      final builder = await contextBuilder(context);
      try {
        await expectLater(
          builder.sign(sourceData: jpeg, mimeType: 'image/jpeg'),
          throwsA(isA<C2paSdkException>()),
        );
      } finally {
        await builder.dispose();
        await context.dispose();
      }
    });

    testWidgets('a callback signer on a context outlives the first sign', (
      tester,
    ) async {
      // The dummy signature may fail verification; what matters is that the
      // Dart callback is still registered for the second sign.
      var calls = 0;
      final context = await C2paContext.create(
        signer: CallbackSigner(
          algorithm: SigningAlgorithm.es256,
          certificateChainPem: cert,
          signCallback: (data) async {
            calls++;
            return Uint8List(64);
          },
        ),
      );
      try {
        for (var i = 0; i < 2; i++) {
          final builder = await contextBuilder(context);
          try {
            await builder.sign(sourceData: jpeg, mimeType: 'image/jpeg');
          } on C2paException {
            // Expected when the dummy signature is verified.
          } finally {
            await builder.dispose();
          }
        }
        expect(calls, 2);
      } finally {
        await context.dispose();
      }
    });
  });

  group('Progress and cancellation', () {
    testWidgets('signing reports progress', (tester) async {
      final updates = <C2paProgress>[];
      final context = await C2paContext.create(
        signer: pemSigner(),
        onProgress: updates.add,
      );
      final builder = await contextBuilder(context);
      try {
        await builder.sign(sourceData: jpeg, mimeType: 'image/jpeg');
        // Progress events are posted asynchronously; let them drain.
        await tester.pump(const Duration(milliseconds: 200));
        expect(updates, isNotEmpty);
        expect(
          updates.map((u) => u.phase),
          anyOf(
            contains(C2paProgressPhase.signing),
            contains(C2paProgressPhase.hashing),
          ),
        );
      } finally {
        await builder.dispose();
        await context.dispose();
      }
    });

    testWidgets('cancel on an idle context is harmless', (tester) async {
      final context = await C2paContext.create();
      await context.cancel();
      await context.dispose();
    });
  });

  group('Embeddable manifests', () {
    testWidgets('JPEG uses a data hash and needs a placeholder', (
      tester,
    ) async {
      final context = await C2paContext.create(signer: pemSigner());
      final builder = await contextBuilder(context);
      try {
        expect(await builder.hashType('image/jpeg'), C2paHashType.dataHash);
        expect(await builder.needsPlaceholder('image/jpeg'), isTrue);
      } finally {
        await builder.dispose();
        await context.dispose();
      }
    });

    testWidgets('placeholder, exclusions, hash and signEmbeddable round trip', (
      tester,
    ) async {
      final context = await C2paContext.create(signer: pemSigner());
      final builder = await contextBuilder(context);
      try {
        final placeholder = await builder.placeholder('image/jpeg');
        expect(placeholder, isNotEmpty);

        // Insert the placeholder right after the JPEG SOI marker.
        const offset = 2;
        final asset = Uint8List.fromList([
          ...jpeg.sublist(0, offset),
          ...placeholder,
          ...jpeg.sublist(offset),
        ]);
        await builder.setDataHashExclusions([
          DataHashExclusion(start: offset, length: placeholder.length),
        ]);
        await builder.updateHashFromBytes('image/jpeg', asset);
        final signed = await builder.signEmbeddable('image/jpeg');
        expect(signed.length, placeholder.length);

        asset.setRange(offset, offset + signed.length, signed);
        final store = await c2pa.readManifestFromBytes(
          asset,
          'image/jpeg',
          options: const ReaderOptions(detailed: true),
        );
        expect(store.activeManifest, isNotNull);
      } finally {
        await builder.dispose();
        await context.dispose();
      }
    });

    testWidgets('composeManifest frames raw manifest bytes for JPEG', (
      tester,
    ) async {
      final builder = await c2pa.createBuilder(manifest());
      await builder.setIntent(
        ManifestIntent.create,
        DigitalSourceType.digitalCapture,
      );
      await builder.setNoEmbed();
      try {
        final result = await builder.sign(
          sourceData: jpeg,
          mimeType: 'image/jpeg',
          signer: pemSigner(),
        );
        final raw = result.manifestBytes;
        expect(raw, isNotNull);
        final composed = await c2pa.composeManifest(
          manifestBytes: raw!,
          mimeType: 'image/jpeg',
        );
        expect(composed.length, greaterThan(raw.length));
        // JPEG embeds C2PA in APP11 segments.
        expect(composed[0], 0xFF);
        expect(composed[1], 0xEB);
      } finally {
        await builder.dispose();
      }
    });
  });

  group('External manifests', () {
    testWidgets('readBytesWithManifest validates a sidecar manifest', (
      tester,
    ) async {
      final builder = await c2pa.createBuilder(manifest());
      await builder.setIntent(
        ManifestIntent.create,
        DigitalSourceType.digitalCapture,
      );
      await builder.setNoEmbed();
      try {
        final result = await builder.sign(
          sourceData: jpeg,
          mimeType: 'image/jpeg',
          signer: pemSigner(),
        );
        final store = await c2pa.readBytesWithManifest(
          result.signedData,
          'image/jpeg',
          result.manifestBytes!,
        );
        expect(store.activeManifest, isNotNull);
      } finally {
        await builder.dispose();
      }
    });

    testWidgets('a Dart HTTP resolver serves a remote manifest', (
      tester,
    ) async {
      const remoteUrl = 'https://example.invalid/manifests/test.c2pa';
      final builder = await c2pa.createBuilder(manifest());
      await builder.setIntent(
        ManifestIntent.create,
        DigitalSourceType.digitalCapture,
      );
      await builder.setNoEmbed();
      await builder.setRemoteUrl(remoteUrl);
      final signed = await builder.sign(
        sourceData: jpeg,
        mimeType: 'image/jpeg',
        signer: pemSigner(),
      );
      await builder.dispose();

      final requests = <C2paHttpRequest>[];
      final settings = await C2paSettings.create();
      await settings.updateFromString(
        '{"version": 1, "verify": {"remote_manifest_fetch": true}}',
        'json',
      );
      final context = await C2paContext.create(
        settings: settings,
        httpResolver: CallbackHttpResolver((request) async {
          requests.add(request);
          return C2paHttpResponse(status: 200, body: signed.manifestBytes);
        }),
      );
      try {
        final store = await c2pa.readManifestFromBytes(
          signed.signedData,
          'image/jpeg',
          options: ReaderOptions(context: context),
        );
        expect(requests.map((r) => r.url), contains(remoteUrl));
        expect(store.activeManifest, isNotNull);
      } finally {
        await context.dispose();
        await settings.dispose();
      }
    });
  });

  group('Ingredient archives', () {
    testWidgets(
      'an ingredient exported from one builder imports into another',
      (tester) async {
        final settings = await C2paSettings.create();
        await settings.updateFromString(
          '{"version": 1, "builder": {"generate_c2pa_archive": true}}',
          'json',
        );
        final context = await C2paContext.create(
          settings: settings,
          signer: pemSigner(),
        );
        final exporter = await contextBuilder(context);
        final importer = await contextBuilder(context);
        try {
          await exporter.addIngredient(
            data: jpeg,
            mimeType: 'image/jpeg',
            config: const IngredientConfig(
              title: 'archived.jpg',
              relationship: Relationship.componentOf,
              additionalData: {'label': 'archived-ingredient'},
            ),
          );
          final archive = await exporter.writeIngredientArchive(
            'archived-ingredient',
          );
          expect(archive, isNotEmpty);

          await importer.addIngredientFromArchive(archive);
          final result = await importer.sign(
            sourceData: jpeg,
            mimeType: 'image/jpeg',
          );
          final json = await c2pa.readBytes(result.signedData, 'image/jpeg');
          expect(json, contains('archived.jpg'));
        } finally {
          await exporter.dispose();
          await importer.dispose();
          await context.dispose();
          await settings.dispose();
        }
      },
    );
  });

  group('crJSON', () {
    testWidgets('reads a signed asset as crJSON', (tester) async {
      final builder = await c2pa.createBuilder(manifest());
      await builder.setIntent(
        ManifestIntent.create,
        DigitalSourceType.digitalCapture,
      );
      try {
        final result = await builder.sign(
          sourceData: jpeg,
          mimeType: 'image/jpeg',
          signer: pemSigner(),
        );
        final crJson = await c2pa.readCrJsonFromBytes(
          result.signedData,
          'image/jpeg',
        );
        expect(() => jsonDecode(crJson), returnsNormally);
      } finally {
        await builder.dispose();
      }
    });
  });

  group('CAWG identity signer', () {
    testWidgets('signing emits a cawg.identity assertion', (tester) async {
      final builder = await c2pa.createBuilder(manifest());
      await builder.setIntent(
        ManifestIntent.create,
        DigitalSourceType.digitalCapture,
      );
      try {
        final result = await builder.sign(
          sourceData: jpeg,
          mimeType: 'image/jpeg',
          signer: CawgIdentitySigner(
            claimSigner: pemSigner(),
            identitySigner: pemSigner(),
            referencedAssertions: const ['c2pa.actions'],
          ),
        );
        final json = await c2pa.readBytes(result.signedData, 'image/jpeg');
        expect(json, contains('cawg.identity'));
      } finally {
        await builder.dispose();
      }
    });
  });

  group('File-based builder signing', () {
    testWidgets('signFile replaces a larger existing destination', (
      tester,
    ) async {
      final source = File('${tempDir.path}/sdk_sync_source.jpg');
      await source.writeAsBytes(jpeg);
      final dest = File('${tempDir.path}/sdk_sync_dest.jpg');
      // A leftover file far larger than any signed output of the fixture.
      const leftoverSize = 1024 * 1024;
      await dest.writeAsBytes(Uint8List(leftoverSize));

      final builder = await c2pa.createBuilder(manifest());
      await builder.setIntent(
        ManifestIntent.create,
        DigitalSourceType.digitalCapture,
      );
      try {
        final result = await builder.signFile(
          sourcePath: source.path,
          destPath: dest.path,
          signer: pemSigner(),
        );
        expect(result.manifestSize, greaterThan(0));
        expect(await dest.length(), lessThan(leftoverSize));
        final store = await c2pa.readManifestFromFile(dest.path);
        expect(store.activeManifest, isNotNull);
      } finally {
        await builder.dispose();
      }
    });

    testWidgets('a missing ingredient file throws and creates nothing', (
      tester,
    ) async {
      final missing = '${tempDir.path}/sdk_sync_missing_ingredient.jpg';
      final builder = await c2pa.createBuilder(manifest());
      try {
        await expectLater(
          builder.addIngredientFromFile(path: missing),
          throwsA(isA<C2paInvalidArgumentException>()),
        );
        expect(File(missing).existsSync(), isFalse);
      } finally {
        await builder.dispose();
      }
    });
  });

  group('Digital source types', () {
    testWidgets('computationalCapture is recorded on both platforms', (
      tester,
    ) async {
      final builder = await c2pa.createBuilder(manifest());
      await builder.setIntent(
        ManifestIntent.create,
        DigitalSourceType.computationalCapture,
      );
      try {
        final result = await builder.sign(
          sourceData: jpeg,
          mimeType: 'image/jpeg',
          signer: pemSigner(),
        );
        final json = await c2pa.readBytes(result.signedData, 'image/jpeg');
        expect(json, contains('computationalCapture'));
      } finally {
        await builder.dispose();
      }
    });
  });
}
