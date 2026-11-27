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

// Public API for the c2pa-swift 0.1 / c2pa-android 0.1 capabilities,
// exercised against the mock platform.

import 'package:c2pa_flutter/c2pa.dart';
import 'package:c2pa_flutter/c2pa_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mocks/mock_c2pa_platform.dart';

void main() {
  late MockC2paPlatform mock;
  late C2pa c2pa;

  const pem = PemSigner(
    algorithm: SigningAlgorithm.es256,
    certificatePem: 'CERT',
    privateKeyPem: 'KEY',
  );

  setUp(() {
    mock = MockC2paPlatform();
    C2paPlatform.instance = mock;
    c2pa = C2pa();
  });

  MockMethodCall last(String method) =>
      mock.methodCalls.lastWhere((c) => c.method == method);

  group('C2paContext', () {
    test('create forwards settings, signer, progress and resolver', () async {
      final settings = await C2paSettings.create();
      void onProgress(C2paProgress p) {}
      final context = await C2paContext.create(
        settings: settings,
        signer: pem,
        onProgress: onProgress,
        httpResolver: const NativeHttpResolver(),
      );
      final args = last('createContext').arguments!;
      expect(args['settingsHandle'], settings.handle);
      expect(args['signerType'], 'PemSigner');
      expect(args['progress'], true);
      expect(args['httpResolver'], 'NativeHttpResolver');
      expect(mock.contexts[context.handle]!.onProgress, same(onProgress));
    });

    test('create rejects disposed settings', () async {
      final settings = await C2paSettings.create();
      await settings.dispose();
      expect(() => C2paContext.create(settings: settings), throwsStateError);
    });

    test('cancel reaches the platform', () async {
      final context = await C2paContext.create();
      await context.cancel();
      expect(mock.contexts[context.handle]!.cancelled, isTrue);
    });

    test('a disposed context can no longer be used', () async {
      final context = await C2paContext.create();
      await context.dispose();
      expect(() => context.handle, throwsStateError);
      expect(context.cancel, throwsStateError);
    });
  });

  group('Reader additions', () {
    test('readCrJsonFromFile and readCrJsonFromBytes', () async {
      final context = await C2paContext.create();
      expect(
        await c2pa.readCrJsonFromFile('/a.jpg', context: context),
        mock.mockCrJson,
      );
      expect(last('readCrJson').arguments!['path'], '/a.jpg');
      expect(last('readCrJson').arguments!['contextHandle'], context.handle);

      await c2pa.readCrJsonFromBytes(Uint8List(4), 'image/png');
      expect(last('readCrJson').arguments!['mimeType'], 'image/png');
    });

    test('readFileWithManifest and readBytesWithManifest', () async {
      final store = await c2pa.readFileWithManifest(
        '/a.jpg',
        Uint8List(10),
        options: const ReaderOptions(detailed: true),
      );
      expect(store.activeManifest, isNotNull);
      expect(last('readWithManifest').arguments!['path'], '/a.jpg');
      expect(last('readWithManifest').arguments!['detailed'], true);

      await c2pa.readBytesWithManifest(
        Uint8List(3),
        'image/jpeg',
        Uint8List(5),
      );
      expect(last('readWithManifest').arguments!['manifestDataLength'], 5);
    });

    test('readFragment', () async {
      final store = await c2pa.readFragment(
        initPath: '/init.mp4',
        fragmentPath: '/seg1.m4s',
      );
      expect(store.activeManifest, isNotNull);
      expect(last('readFragment').arguments!['fragmentPath'], '/seg1.m4s');
    });

    test('extractResource passes the context', () async {
      final context = await C2paContext.create();
      await c2pa.extractResource(
        Uint8List(4),
        'image/jpeg',
        'self#jumbf=thumb',
        context: context,
      );
      expect(
        last('extractResource').arguments!['contextHandle'],
        context.handle,
      );
    });
  });

  group('Builder additions', () {
    test('createBuilderFromArchive accepts a context', () async {
      final context = await C2paContext.create();
      await c2pa.createBuilderFromArchive(Uint8List(4), context: context);
      expect(
        last('createBuilderFromArchive').arguments!['contextHandle'],
        context.handle,
      );
    });

    test('embeddable workflow round trip through the builder', () async {
      final context = await C2paContext.create(signer: pem);
      final builder = await c2pa.createBuilderFromContext(context, '{}');

      expect(await builder.needsPlaceholder('image/jpeg'), isTrue);
      final placeholder = await builder.placeholder('image/jpeg');
      await builder.setDataHashExclusions([
        DataHashExclusion(start: 2, length: placeholder.length),
      ]);
      await builder.updateHashFromBytes('image/jpeg', Uint8List(100));
      final signed = await builder.signEmbeddable('image/jpeg');
      expect(signed.length, placeholder.length);

      expect(last('builderSetDataHashExclusions').arguments!['exclusions'], [
        [2, placeholder.length],
      ]);
    });

    test('sign without a signer uses the context signer', () async {
      final context = await C2paContext.create(signer: pem);
      final builder = await c2pa.createBuilderFromContext(context, '{}');
      await builder.sign(sourceData: Uint8List(4), mimeType: 'image/jpeg');
      expect(last('builderSign').arguments!['signerType'], isNull);
    });

    test('ingredient archives', () async {
      final builder = await c2pa.createBuilder('{}');
      final archive = await builder.writeIngredientArchive('ing-1');
      await builder.addIngredientFromArchive(archive);
      expect(
        last('builderWriteIngredientArchive').arguments!['ingredientId'],
        'ing-1',
      );
      expect(
        last('builderAddIngredientFromArchive').arguments!['archiveLength'],
        archive.length,
      );
    });
  });

  group('Types', () {
    test('CawgIdentitySigner serializes both signers', () {
      const signer = CawgIdentitySigner(
        claimSigner: pem,
        identitySigner: pem,
        referencedAssertions: ['c2pa.actions'],
        roles: ['cawg.creator'],
      );
      final map = signer.toMap();
      expect(map['type'], 'cawgIdentity');
      expect((map['claimSigner'] as Map)['type'], 'pem');
      expect(map['roles'], ['cawg.creator']);
      expect(signer.algorithm, SigningAlgorithm.es256);
    });

    test('C2paHashType.fromName rejects unknown names', () {
      expect(C2paHashType.fromName('boxHash'), C2paHashType.boxHash);
      expect(() => C2paHashType.fromName('nope'), throwsArgumentError);
    });

    test('C2paHttpRequest.fromMap defaults', () {
      final request = C2paHttpRequest.fromMap({'url': 'https://x'});
      expect(request.method, 'GET');
      expect(request.headers, isEmpty);
      expect(request.body, isNull);
    });

    test('DataHashExclusion equality', () {
      expect(
        const DataHashExclusion(start: 1, length: 2),
        const DataHashExclusion(start: 1, length: 2),
      );
    });
  });
}
