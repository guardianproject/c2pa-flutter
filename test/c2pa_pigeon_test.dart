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

// The contract between PigeonC2pa and the generated host API: call
// ordering, signer messages and callback lifetimes, the native-to-Dart
// callbacks for signing, progress and HTTP resolution, argument forwarding
// and error mapping.

import 'dart:async';

import 'package:c2pa_flutter/c2pa.dart';
import 'package:c2pa_flutter/c2pa_pigeon.dart';
import 'package:c2pa_flutter/src/c2pa_api.g.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [C2paHostApi] that records every call. A method answers with the
/// future its entry in [responses] returns, or a completed `Future<void>`.
class FakeHostApi implements C2paHostApi {
  final List<Invocation> calls = [];
  final Map<Symbol, Future<Object?> Function(List<Object?> args)> responses =
      {};

  /// The positional arguments of the last call to [method].
  List<Object?> argsOf(Symbol method) =>
      calls.lastWhere((c) => c.memberName == method).positionalArguments;

  List<String> get names => [
    for (final c in calls)
      c.memberName.toString().replaceAll('Symbol("', '').replaceAll('")', ''),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    final respond = responses[invocation.memberName];
    if (respond == null) return Future<void>.value();
    return respond(invocation.positionalArguments);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHostApi api;
  late PigeonC2pa platform;
  var nextHandle = 1;

  const pem = PemSigner(
    algorithm: SigningAlgorithm.es256,
    certificatePem: 'CERT',
    privateKeyPem: 'KEY',
  );

  SignResultMessage signResult() => SignResultMessage(
    signedData: Uint8List.fromList([1, 2, 3]),
    manifestBytes: Uint8List.fromList([4]),
    manifestSize: 1,
  );

  setUp(() {
    api = FakeHostApi();
    platform = PigeonC2pa(hostApi: api);
    nextHandle = 1;
    Future<int> handle(List<Object?> _) => Future<int>.value(nextHandle++);
    api.responses.addAll({
      #createBuilder: handle,
      #createContext: handle,
      #builderSign: (_) => Future<SignResultMessage>.value(signResult()),
      #builderSignFile: (_) => Future<SignResultMessage>.value(signResult()),
      #builderToArchive: (_) =>
          Future<Uint8List>.value(Uint8List.fromList([7, 8, 9])),
      #builderPlaceholder: (_) => Future<Uint8List>.value(Uint8List(4)),
      #builderHashType: (_) =>
          Future<HashTypeMessage>.value(HashTypeMessage.bmffHash),
      #composeManifest: (_) =>
          Future<Uint8List>.value(Uint8List.fromList([0xFF, 0xEB])),
      #readFile: (_) => Future<String>.value('{}'),
      #readBytes: (_) => Future<String>.value('{}'),
      #readWithManifest: (_) => Future<String>.value('{}'),
      #readFragment: (_) => Future<String>.value('{}'),
      #getPlatformVersion: (_) => Future<String>.value('Test 1'),
    });
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), 'Test 1');
  });

  group('builder call ordering', () {
    test('awaited calls reach the host in order', () async {
      final builder = await platform.createBuilder('{}');
      await builder.setIntent(
        ManifestIntent.create,
        DigitalSourceType.digitalCapture,
      );
      await builder.addAction(
        const ActionConfig(action: 'c2pa.color_adjustments'),
      );
      await builder.placeholder('image/jpeg');

      expect(api.names, [
        'createBuilder',
        'builderSetIntent',
        'builderAddAction',
        'builderPlaceholder',
      ]);
      final intent = api.argsOf(#builderSetIntent);
      expect(intent[1], ManifestIntentMessage.create);
      expect(intent[2], 'digitalCapture');
    });

    test('un-awaited calls run one after another in call order', () async {
      final ingredient = Completer<void>();
      api.responses[#builderAddIngredient] = (_) => ingredient.future;
      final builder = await platform.createBuilder('{}');

      unawaited(
        builder.addIngredient(data: Uint8List(1), mimeType: 'image/jpeg'),
      );
      unawaited(builder.setIntent(ManifestIntent.edit));
      final signing = builder.sign(
        sourceData: Uint8List(1),
        mimeType: 'image/jpeg',
        signer: pem,
      );
      await pumpEventQueue();
      // Nothing after the ingredient starts until it finishes.
      expect(api.names.last, 'builderAddIngredient');

      ingredient.complete();
      await signing;
      await builder.dispose();
      expect(api.names, [
        'createBuilder',
        'builderAddIngredient',
        'builderSetIntent',
        'builderSign',
        'builderDispose',
      ]);
    });

    test('a failed call does not stop later calls', () async {
      api.responses[#builderAddAction] = (_) => Future<Never>.error(
        PlatformException(code: 'C2PA_ERROR', message: 'invalid action'),
      );
      final builder = await platform.createBuilder('{}');

      final failed = builder.addAction(const ActionConfig(action: 'bad'));
      final archive = builder.toArchive();

      await expectLater(failed, throwsA(isA<C2paSdkException>()));
      expect((await archive).data, [7, 8, 9]);
    });

    test('a disposed builder rejects calls and disposes once', () async {
      final builder = await platform.createBuilder('{}');
      await builder.dispose();
      await builder.dispose();

      expect(() => builder.setIntent(ManifestIntent.create), throwsStateError);
      expect(() => builder.setNoEmbed(), throwsStateError);
      expect(() => builder.handle, throwsStateError);
      expect(api.names.where((n) => n == 'builderDispose'), hasLength(1));
    });

    test('addIngredientFromFile forwards the path and config', () async {
      final builder = await platform.createBuilder('{}');
      await builder.addIngredientFromFile(
        path: '/tmp/in.jpg',
        config: const IngredientConfig(title: 'in.jpg'),
      );
      final args = api.argsOf(#builderAddIngredientFromFile);
      expect(args[1], '/tmp/in.jpg');
      expect(args[2], isNull);
      expect(args[3], contains('in.jpg'));
    });
  });

  group('embeddable workflow arguments', () {
    test('exclusions become exclusion messages', () async {
      final builder = await platform.createBuilder('{}');
      await builder.setDataHashExclusions(const [
        DataHashExclusion(start: 2, length: 100),
        DataHashExclusion(start: 500, length: 10),
      ]);
      final sent =
          api.argsOf(#builderSetDataHashExclusions)[1]!
              as List<DataHashExclusionMessage>;
      expect(
        [for (final e in sent) (e.start, e.length)],
        [(2, 100), (500, 10)],
      );
    });

    test('hashType maps the host enum', () async {
      final builder = await platform.createBuilder('{}');
      expect(await builder.hashType('video/mp4'), C2paHashType.bmffHash);
    });

    test('hashMdatBytes forwards all fields', () async {
      final builder = await platform.createBuilder('{}');
      await builder.hashMdatBytes(
        mdatId: 3,
        data: Uint8List(4),
        largeSize: true,
      );
      final args = api.argsOf(#builderHashMdatBytes);
      expect(args[1], 3);
      expect(args[3], true);
    });

    test('composeManifest forwards bytes and type', () async {
      final result = await platform.composeManifest(
        manifestBytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
      );
      expect(result, [0xFF, 0xEB]);
      expect(api.argsOf(#composeManifest)[1], 'image/jpeg');
    });
  });

  group('signers', () {
    test('sign without a signer sends a null signer', () async {
      final builder = await platform.createBuilder('{}');
      await builder.sign(sourceData: Uint8List(1), mimeType: 'image/jpeg');
      expect(api.argsOf(#builderSign)[3], isNull);
    });

    test('a PEM signer becomes a PEM signer message', () async {
      final builder = await platform.createBuilder('{}');
      await builder.signFile(
        sourcePath: '/a.jpg',
        destPath: '/b.jpg',
        signer: const PemSigner(
          algorithm: SigningAlgorithm.ps384,
          certificatePem: 'CERT',
          privateKeyPem: 'KEY',
          tsaUrl: 'http://tsa.example',
        ),
      );
      final message = api.argsOf(#builderSignFile)[4]! as PemSignerMessage;
      expect(message.algorithm, SigningAlgorithmMessage.ps384);
      expect(message.certificatePem, 'CERT');
      expect(message.tsaUrl, 'http://tsa.example');
    });

    test('CawgIdentitySigner nests both signers with a callback id', () async {
      Future<SignResultMessage> signWithCallback(List<Object?> args) async {
        final cawg = args[3]! as CawgIdentitySignerMessage;
        final identity = cawg.identitySigner as CallbackSignerMessage;
        // Native would call back into Dart for the identity signature.
        final signature = await platform.sign(
          identity.callbackId,
          Uint8List.fromList([1]),
        );
        return SignResultMessage(signedData: signature, manifestSize: 0);
      }

      api.responses[#builderSign] = signWithCallback;
      final builder = await platform.createBuilder('{}');
      final result = await builder.sign(
        sourceData: Uint8List(1),
        mimeType: 'image/jpeg',
        signer: CawgIdentitySigner(
          claimSigner: pem,
          identitySigner: CallbackSigner(
            algorithm: SigningAlgorithm.es256,
            certificateChainPem: 'CHAIN',
            signCallback: (data) async => Uint8List.fromList([7, 7]),
          ),
          referencedAssertions: const ['c2pa.actions'],
        ),
      );
      expect(result.signedData, [7, 7]);

      final cawg = api.argsOf(#builderSign)[3]! as CawgIdentitySignerMessage;
      expect(cawg.claimSigner, isA<PemSignerMessage>());
      expect(cawg.referencedAssertions, ['c2pa.actions']);
    });

    test('a one-shot callback signer is released after the call', () async {
      final builder = await platform.createBuilder('{}');
      await builder.sign(
        sourceData: Uint8List(1),
        mimeType: 'image/jpeg',
        signer: CallbackSigner(
          algorithm: SigningAlgorithm.es256,
          certificateChainPem: 'CHAIN',
          signCallback: (data) async => data,
        ),
      );
      final id =
          (api.argsOf(#builderSign)[3]! as CallbackSignerMessage).callbackId;
      expect(
        () => platform.sign(id, Uint8List(1)),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'CALLBACK_NOT_FOUND',
          ),
        ),
      );
    });
  });

  group('contexts', () {
    test(
      'createContext sends settings, signer, progress and resolver',
      () async {
        await platform.createContext(
          settingsHandle: 7,
          signer: pem,
          onProgress: (_) {},
          httpResolver: const NativeHttpResolver(),
        );
        final args = api.argsOf(#createContext);
        expect(args[0], 7);
        expect(args[1], isA<PemSignerMessage>());
        expect(args[2], true);
        expect(args[3], HttpResolverModeMessage.native);
      },
    );

    test('progress reaches the context callback', () async {
      final updates = <C2paProgress>[];
      final handle = await platform.createContext(onProgress: updates.add);
      await platform.progress(handle, 'signing', 2, 4);
      expect(updates.single.phase, C2paProgressPhase.signing);
      expect(updates.single.fraction, 0.5);
    });

    test('unknown progress phases map to unknown', () async {
      final updates = <C2paProgress>[];
      final handle = await platform.createContext(onProgress: updates.add);
      await platform.progress(handle, 'somethingNew', 1, 0);
      expect(updates.single.phase, C2paProgressPhase.unknown);
      expect(updates.single.fraction, isNull);
    });

    test('resolveHttp is answered by the Dart resolver', () async {
      final handle = await platform.createContext(
        httpResolver: CallbackHttpResolver((request) async {
          expect(request.url, 'https://example.com/m.c2pa');
          expect(request.headers['Accept'], 'application/c2pa');
          return C2paHttpResponse(status: 200, body: Uint8List.fromList([5]));
        }),
      );
      expect(api.argsOf(#createContext)[3], HttpResolverModeMessage.callback);

      final response = await platform.resolveHttp(
        handle,
        HttpRequestMessage(
          url: 'https://example.com/m.c2pa',
          method: 'GET',
          headers: {'Accept': 'application/c2pa'},
        ),
      );
      expect(response.status, 200);
      expect(response.body, [5]);
    });

    test('resolveHttp without a Dart resolver fails', () async {
      final handle = await platform.createContext();
      await expectLater(
        platform.resolveHttp(
          handle,
          HttpRequestMessage(url: 'https://x', method: 'GET', headers: {}),
        ),
        throwsA(isA<PlatformException>()),
      );
    });

    test(
      'a context signer callback lives until the context is disposed',
      () async {
        final handle = await platform.createContext(
          signer: CallbackSigner(
            algorithm: SigningAlgorithm.es256,
            certificateChainPem: 'CHAIN',
            signCallback: (data) async => Uint8List.fromList([3]),
          ),
        );
        final id = (api.argsOf(#createContext)[1]! as CallbackSignerMessage)
            .callbackId;

        for (var i = 0; i < 2; i++) {
          expect(await platform.sign(id, Uint8List(1)), [3]);
        }

        await platform.contextDispose(handle);
        expect(
          () => platform.sign(id, Uint8List(1)),
          throwsA(isA<PlatformException>()),
        );
      },
    );

    test('a failed createContext releases its signer callbacks', () async {
      api.responses[#createContext] = (_) => Future<Never>.error(
        PlatformException(code: 'INVALID_HANDLE', message: 'settings'),
      );
      await expectLater(
        platform.createContext(
          settingsHandle: 99,
          signer: CallbackSigner(
            algorithm: SigningAlgorithm.es256,
            certificateChainPem: 'CHAIN',
            signCallback: (data) async => data,
          ),
        ),
        throwsA(isA<C2paInvalidArgumentException>()),
      );
      final id =
          (api.argsOf(#createContext)[1]! as CallbackSignerMessage).callbackId;
      expect(
        () => platform.sign(id, Uint8List(1)),
        throwsA(isA<PlatformException>()),
      );
    });

    test('contextCancel targets the handle', () async {
      await platform.contextCancel(4);
      expect(api.argsOf(#contextCancel), [4]);
    });
  });

  group('reader', () {
    test('plain and detailed reads choose the format', () async {
      await platform.readFile('/a.jpg');
      expect(api.argsOf(#readFile), [
        '/a.jpg',
        null,
        ReadFormatMessage.json,
        null,
      ]);

      await platform.readBytesDetailed(
        Uint8List(1),
        'image/png',
        true,
        contextHandle: 3,
      );
      final args = api.argsOf(#readBytes);
      expect(args[1], 'image/png');
      expect(args[2], ReadFormatMessage.detailed);
      expect(args[3], 3);
    });

    test('readCrJson reads bytes or a path as crJSON', () async {
      await platform.readCrJson(data: Uint8List(1), mimeType: 'image/jpeg');
      expect(api.argsOf(#readBytes)[2], ReadFormatMessage.crJson);

      await platform.readCrJson(path: '/a.jpg');
      expect(api.argsOf(#readFile)[2], ReadFormatMessage.crJson);
    });

    test('readCrJson needs exactly one of path or data', () {
      expect(() => platform.readCrJson(), throwsArgumentError);
      expect(
        () => platform.readCrJson(path: '/a', data: Uint8List(1)),
        throwsArgumentError,
      );
    });

    test('readWithManifest forwards the manifest', () async {
      await platform.readWithManifest(
        data: Uint8List(2),
        mimeType: 'image/jpeg',
        manifestData: Uint8List(3),
        contextHandle: 9,
      );
      final args = api.argsOf(#readWithManifest);
      expect((args[3]! as Uint8List).length, 3);
      expect(args[5], 9);
    });

    test('readFragment forwards both paths', () async {
      await platform.readFragment(
        initPath: '/init.mp4',
        fragmentPath: '/f1.m4s',
      );
      final args = api.argsOf(#readFragment);
      expect(args[0], '/init.mp4');
      expect(args[1], '/f1.m4s');
    });
  });

  group('errors and values', () {
    test('host failures arrive as C2paException', () async {
      api.responses[#readFile] = (_) => Future<Never>.error(
        PlatformException(
          code: 'C2PA_ERROR',
          message: 'ManifestNotFound: no JUMBF data found',
        ),
      );
      await expectLater(
        platform.readFile('/unsigned.jpg'),
        throwsA(isA<C2paManifestNotFoundException>()),
      );
    });

    test('settings values are sent JSON-encoded', () async {
      await platform.settingsSetValue(1, 'verify.verify_trust', false);
      expect(api.argsOf(#settingsSetValue)[2], 'false');
      await platform.settingsSetValue(1, 'signer.local.alg', 'es256');
      expect(api.argsOf(#settingsSetValue)[2], '"es256"');
      await platform.settingsSetValue(1, 'builder.labels', ['a', 'b']);
      expect(api.argsOf(#settingsSetValue)[2], '["a","b"]');
    });

    test('certificate configs keep the email address', () async {
      api.responses[#createSelfSignedCertificateChain] = (_) =>
          Future<String>.value('CHAIN');
      await platform.createSelfSignedCertificateChain(
        keyAlias: 'k',
        config: const CertificateConfig(
          commonName: 'CN',
          email: 'a@example.com',
          validityDays: 30,
        ),
      );
      final config =
          api.argsOf(#createSelfSignedCertificateChain)[1]!
              as CertificateConfigMessage;
      expect(config.emailAddress, 'a@example.com');
      expect(config.validityDays, 30);
    });

    test('enrollHardwareKey returns the typed enrollment', () async {
      api.responses[#enrollHardwareKey] = (_) =>
          Future<HardwareKeyEnrollmentMessage>.value(
            HardwareKeyEnrollmentMessage(
              keyAlias: 'hw',
              certificateChainPem: 'CHAIN',
            ),
          );
      final enrollment = await platform.enrollHardwareKey(
        keyAlias: 'hw',
        signingServerUrl: 'https://signer.example',
      );
      expect(enrollment.keyAlias, 'hw');
      expect(enrollment.certificateChainPem, 'CHAIN');
    });
  });
}
