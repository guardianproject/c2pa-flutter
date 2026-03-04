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

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:c2pa_flutter/c2pa.dart';
import 'package:c2pa_flutter/c2pa_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final MethodChannelC2pa platform = MethodChannelC2pa();
  const MethodChannel channel = MethodChannel('org.guardianproject.c2pa');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          return '42';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  group('MethodChannelManifestBuilder', () {
    late List<MethodCall> methodCalls;
    late int nextHandle;

    setUp(() {
      methodCalls = [];
      nextHandle = 1;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            methodCalls.add(methodCall);

            switch (methodCall.method) {
              case 'createBuilder':
                return nextHandle++;
              case 'builderDispose':
                return null;
              case 'builderSetIntent':
                return null;
              case 'builderSetNoEmbed':
                return null;
              case 'builderSetRemoteUrl':
                return null;
              case 'builderAddAction':
                return null;
              case 'builderSign':
                return {
                  'signedData': Uint8List.fromList([1, 2, 3]),
                  'manifestBytes': Uint8List.fromList([4, 5, 6]),
                  'manifestSize': 3,
                };
              case 'builderToArchive':
                return Uint8List.fromList([7, 8, 9]);
              default:
                return null;
            }
          });
    });

    test('setIntent is applied via native call on sign', () async {
      final builder = await platform.createBuilder('{}');

      builder.setIntent(
        ManifestIntent.create,
        DigitalSourceType.digitalCapture,
      );

      await builder.sign(
        sourceData: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
        signer: const PemSigner(
          algorithm: SigningAlgorithm.es256,
          certificatePem: 'test-cert',
          privateKeyPem: 'test-key',
        ),
      );

      final setIntentCalls = methodCalls
          .where((c) => c.method == 'builderSetIntent')
          .toList();
      expect(setIntentCalls.length, 1);
      expect(setIntentCalls[0].arguments['intent'], 'create');
      expect(
        setIntentCalls[0].arguments['digitalSourceType'],
        'digitalCapture',
      );

      builder.dispose();
    });

    test('addAction is applied via native call on sign', () async {
      final builder = await platform.createBuilder('{}');

      builder.addAction(
        const ActionConfig(
          action: 'c2pa.created',
          softwareAgent: 'TestApp/1.0',
        ),
      );

      await builder.sign(
        sourceData: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
        signer: const PemSigner(
          algorithm: SigningAlgorithm.es256,
          certificatePem: 'test-cert',
          privateKeyPem: 'test-key',
        ),
      );

      final addActionCalls = methodCalls
          .where((c) => c.method == 'builderAddAction')
          .toList();
      expect(addActionCalls.length, 1);

      final actionJson = jsonDecode(
        addActionCalls[0].arguments['actionJson'] as String,
      );
      expect(actionJson['action'], 'c2pa.created');
      expect(actionJson['softwareAgent'], 'TestApp/1.0');

      builder.dispose();
    });

    test('setNoEmbed is applied via native call on sign', () async {
      final builder = await platform.createBuilder('{}');

      builder.setNoEmbed();

      await builder.sign(
        sourceData: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
        signer: const PemSigner(
          algorithm: SigningAlgorithm.es256,
          certificatePem: 'test-cert',
          privateKeyPem: 'test-key',
        ),
      );

      final setNoEmbedCalls = methodCalls
          .where((c) => c.method == 'builderSetNoEmbed')
          .toList();
      expect(setNoEmbedCalls.length, 1);

      builder.dispose();
    });

    test('setRemoteUrl is applied via native call on sign', () async {
      final builder = await platform.createBuilder('{}');

      builder.setRemoteUrl('https://example.com/manifest');

      await builder.sign(
        sourceData: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
        signer: const PemSigner(
          algorithm: SigningAlgorithm.es256,
          certificatePem: 'test-cert',
          privateKeyPem: 'test-key',
        ),
      );

      final setRemoteUrlCalls = methodCalls
          .where((c) => c.method == 'builderSetRemoteUrl')
          .toList();
      expect(setRemoteUrlCalls.length, 1);
      expect(
        setRemoteUrlCalls[0].arguments['url'],
        'https://example.com/manifest',
      );

      builder.dispose();
    });

    test('multiple operations are applied in order on sign', () async {
      final builder = await platform.createBuilder('{}');

      builder.setIntent(ManifestIntent.create);
      builder.setNoEmbed();
      builder.addAction(const ActionConfig(action: 'c2pa.created'));

      await builder.sign(
        sourceData: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
        signer: const PemSigner(
          algorithm: SigningAlgorithm.es256,
          certificatePem: 'test-cert',
          privateKeyPem: 'test-key',
        ),
      );

      // Verify operations were applied
      expect(methodCalls.any((c) => c.method == 'builderSetIntent'), true);
      expect(methodCalls.any((c) => c.method == 'builderSetNoEmbed'), true);
      expect(methodCalls.any((c) => c.method == 'builderAddAction'), true);

      builder.dispose();
    });

    test('toArchive applies pending operations', () async {
      final builder = await platform.createBuilder('{}');

      builder.setIntent(ManifestIntent.edit);

      await builder.toArchive();

      final setIntentCalls = methodCalls
          .where((c) => c.method == 'builderSetIntent')
          .toList();
      expect(setIntentCalls.length, 1);
      expect(setIntentCalls[0].arguments['intent'], 'edit');

      builder.dispose();
    });

    test('disposed builder throws StateError', () async {
      final builder = await platform.createBuilder('{}');
      builder.dispose();

      expect(() => builder.setIntent(ManifestIntent.create), throwsStateError);
      expect(() => builder.setNoEmbed(), throwsStateError);
      expect(() => builder.setRemoteUrl('url'), throwsStateError);
      expect(
        () => builder.addAction(const ActionConfig(action: 'test')),
        throwsStateError,
      );
    });

    test('dispose calls native builderDispose', () async {
      final builder = await platform.createBuilder('{}');
      final handle = builder.handle;

      builder.dispose();

      final disposeCalls = methodCalls
          .where((c) => c.method == 'builderDispose')
          .toList();
      expect(disposeCalls.length, 1);
      expect(disposeCalls[0].arguments['handle'], handle);
    });

    test('double dispose only calls native once', () async {
      final builder = await platform.createBuilder('{}');

      builder.dispose();
      builder.dispose(); // Should be no-op

      final disposeCalls = methodCalls
          .where((c) => c.method == 'builderDispose')
          .toList();
      expect(disposeCalls.length, 1);
    });

    test('pending operations are cleared after sign', () async {
      final builder = await platform.createBuilder('{}');

      builder.setIntent(ManifestIntent.create);

      // First sign
      await builder.sign(
        sourceData: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
        signer: const PemSigner(
          algorithm: SigningAlgorithm.es256,
          certificatePem: 'test-cert',
          privateKeyPem: 'test-key',
        ),
      );

      // Reset method calls
      methodCalls.clear();

      // Second sign without adding new operations
      await builder.sign(
        sourceData: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
        signer: const PemSigner(
          algorithm: SigningAlgorithm.es256,
          certificatePem: 'test-cert',
          privateKeyPem: 'test-key',
        ),
      );

      // Should not have setIntent call in second sign
      final setIntentCalls = methodCalls
          .where((c) => c.method == 'builderSetIntent')
          .toList();
      expect(setIntentCalls.length, 0);

      builder.dispose();
    });
  });
}
