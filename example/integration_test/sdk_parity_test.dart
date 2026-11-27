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

// Scenarios ported from the c2pa-swift and c2pa-android test suites, run
// against the real SDKs through the plugin: every signing algorithm, real
// callback signatures, BMFF Merkle hashing, embeddable error paths,
// cancellation, HTTP resolver failures, key management, settings, reserve
// sizes, remote signer failures, CAWG with a callback claim signer and
// concurrent signing.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart' as asn1;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart' as pc;

import 'package:c2pa_flutter/c2pa.dart';
import 'package:c2pa_flutter/c2pa_platform_interface.dart';

/// The P-256 private scalar of a PKCS#8 PEM key.
BigInt _p256PrivateScalar(String pem) {
  final body = pem.split('\n').where((l) => !l.startsWith('-----')).join();
  final pkcs8 =
      asn1.ASN1Parser(base64.decode(body)).nextObject() as asn1.ASN1Sequence;
  final ecKey =
      asn1.ASN1Parser(
            (pkcs8.elements[2] as asn1.ASN1OctetString).contentBytes(),
          ).nextObject()
          as asn1.ASN1Sequence;
  final d = (ecKey.elements[1] as asn1.ASN1OctetString).contentBytes();
  return d.fold<BigInt>(BigInt.zero, (v, b) => (v << 8) | BigInt.from(b));
}

Uint8List _unsigned(BigInt value, int length) {
  final out = Uint8List(length);
  var v = value;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v = v >> 8;
  }
  return out;
}

Uint8List _derInteger(BigInt value) {
  var bytes = _unsigned(value, 33);
  var start = 0;
  while (start < bytes.length - 1 &&
      bytes[start] == 0 &&
      bytes[start + 1] < 0x80) {
    start++;
  }
  bytes = bytes.sublist(start);
  return Uint8List.fromList([0x02, bytes.length, ...bytes]);
}

/// Signs [data] with ES256 (deterministic ECDSA over SHA-256). Returns the
/// raw r||s form c2pa-android's signers produce, or DER when [der] is true,
/// the form c2pa-swift's keychain signer produces.
Uint8List _es256Sign(Uint8List data, BigInt d, {bool der = false}) {
  final signer = pc.ECDSASigner(pc.SHA256Digest(), pc.HMac(pc.SHA256Digest(), 64))
    ..init(
      true,
      pc.PrivateKeyParameter<pc.ECPrivateKey>(
        pc.ECPrivateKey(d, pc.ECDomainParameters('secp256r1')),
      ),
    );
  final signature = signer.generateSignature(data) as pc.ECSignature;
  if (!der) {
    return Uint8List.fromList([
      ..._unsigned(signature.r, 32),
      ..._unsigned(signature.s, 32),
    ]);
  }
  final r = _derInteger(signature.r);
  final s = _derInteger(signature.s);
  return Uint8List.fromList([0x30, r.length + s.length, ...r, ...s]);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late C2pa c2pa;
  late Directory tempDir;
  late String cert;
  late String key;
  late BigInt privateScalar;
  late Uint8List jpeg;
  late Uint8List video;

  String manifest({String title = 'SDK parity test'}) => jsonEncode({
    'title': title,
    'claim_generator_info': [
      {'name': 'c2pa_flutter_sdk_parity_test', 'version': '1.0'},
    ],
  });

  PemSigner pemSigner({String? tsaUrl}) => PemSigner(
    algorithm: SigningAlgorithm.es256,
    certificatePem: cert,
    privateKeyPem: key,
    tsaUrl: tsaUrl,
  );

  CallbackSigner callbackSigner({bool der = false, void Function()? onSign}) =>
      CallbackSigner(
        algorithm: SigningAlgorithm.es256,
        certificateChainPem: cert,
        signCallback: (data) async {
          onSign?.call();
          return _es256Sign(data, privateScalar, der: der);
        },
      );

  Map<String, dynamic> localSigner() => {
    'local': {'alg': 'es256', 'sign_cert': cert, 'private_key': key},
  };

  Future<ManifestBuilder> createBuilder({C2paContext? context}) async {
    final builder = context == null
        ? await c2pa.createBuilder(manifest())
        : await c2pa.createBuilderFromContext(context, manifest());
    await builder.setIntent(
      ManifestIntent.create,
      DigitalSourceType.digitalCapture,
    );
    return builder;
  }

  /// Validation codes that mean the signature itself failed to verify.
  List<String> signatureFailures(ManifestStoreInfo store) => store
      .validationErrors
      .map((e) => e.code)
      .where((c) => c.startsWith('claimSignature') || c.contains('mismatch'))
      .toList();

  setUpAll(() async {
    c2pa = C2pa();
    tempDir = await getTemporaryDirectory();
    cert = await rootBundle.loadString('assets/test_certs/test_es256_cert.pem');
    key = await rootBundle.loadString('assets/test_certs/test_es256_key.pem');
    privateScalar = _p256PrivateScalar(key);
    jpeg = (await rootBundle.load(
      'assets/test_images/test_unsigned.jpg',
    )).buffer.asUint8List();
    video = (await rootBundle.load(
      'assets/test_images/video1.mp4',
    )).buffer.asUint8List();
  });

  group('Signing algorithms', () {
    for (final algorithm in SigningAlgorithm.values) {
      testWidgets('signs and reads back with ${algorithm.name}', (
        tester,
      ) async {
        final String chain;
        final String privateKey;
        if (algorithm == SigningAlgorithm.es256) {
          chain = cert;
          privateKey = key;
        } else {
          chain = await rootBundle.loadString(
            'assets/test_certs/${algorithm.name}_certs.pem',
          );
          privateKey = await rootBundle.loadString(
            'assets/test_certs/${algorithm.name}_private.key',
          );
        }
        final builder = await createBuilder();
        try {
          final result = await builder.sign(
            sourceData: jpeg,
            mimeType: 'image/jpeg',
            signer: PemSigner(
              algorithm: algorithm,
              certificatePem: chain,
              privateKeyPem: privateKey,
            ),
          );
          final store = await c2pa.readManifestFromBytes(
            result.signedData,
            'image/jpeg',
          );
          expect(store.active!.signature?.algorithm, algorithm);
          expect(signatureFailures(store), isEmpty);
        } finally {
          await builder.dispose();
        }
      });
    }
  });

  group('Callback signer', () {
    for (final der in [false, true]) {
      testWidgets(
        'a ${der ? 'DER' : 'raw'} ES256 signature from Dart verifies',
        (tester) async {
          var calls = 0;
          final builder = await createBuilder();
          try {
            final result = await builder.sign(
              sourceData: jpeg,
              mimeType: 'image/jpeg',
              signer: callbackSigner(der: der, onSign: () => calls++),
            );
            expect(calls, 1);
            final store = await c2pa.readManifestFromBytes(
              result.signedData,
              'image/jpeg',
            );
            expect(store.active!.signature?.algorithm, SigningAlgorithm.es256);
            expect(signatureFailures(store), isEmpty);
          } finally {
            await builder.dispose();
          }
        },
      );
    }

    testWidgets('an exception in the callback fails the sign', (tester) async {
      final builder = await createBuilder();
      try {
        await expectLater(
          builder.sign(
            sourceData: jpeg,
            mimeType: 'image/jpeg',
            signer: CallbackSigner(
              algorithm: SigningAlgorithm.es256,
              certificateChainPem: cert,
              signCallback: (data) async => throw StateError('HSM offline'),
            ),
          ),
          throwsA(isA<C2paException>()),
        );
      } finally {
        await builder.dispose();
      }
    });

    testWidgets('concurrent signs share one context callback signer', (
      tester,
    ) async {
      var calls = 0;
      final context = await C2paContext.create(
        signer: callbackSigner(onSign: () => calls++),
      );
      final builders = [
        await createBuilder(context: context),
        await createBuilder(context: context),
      ];
      try {
        final results = await Future.wait(
          builders.map((b) => b.sign(sourceData: jpeg, mimeType: 'image/jpeg')),
        );
        expect(calls, 2);
        for (final result in results) {
          final store = await c2pa.readManifestFromBytes(
            result.signedData,
            'image/jpeg',
          );
          expect(signatureFailures(store), isEmpty);
        }
      } finally {
        for (final b in builders) {
          await b.dispose();
        }
        await context.dispose();
      }
    });
  });

  group('Reserve size', () {
    testWidgets('signers report a reserve size', (tester) async {
      final pem = await c2pa.getSignerReserveSize(pemSigner());
      final withTsa = await c2pa.getSignerReserveSize(
        pemSigner(tsaUrl: 'http://timestamp.digicert.com'),
      );
      final callback = await c2pa.getSignerReserveSize(callbackSigner());
      expect(pem, greaterThan(0));
      expect(withTsa, greaterThanOrEqualTo(pem));
      expect(callback, greaterThan(0));
    });
  });

  group('BMFF', () {
    testWidgets('MP4 uses a BMFF hash and JPEG a data hash', (tester) async {
      final context = await C2paContext.create(signer: pemSigner());
      final builder = await createBuilder(context: context);
      try {
        expect(await builder.hashType('video/mp4'), C2paHashType.bmffHash);
        expect(await builder.hashType('image/jpeg'), C2paHashType.dataHash);
      } finally {
        await builder.dispose();
        await context.dispose();
      }
    });

    testWidgets('signs an MP4 file and reads it back', (tester) async {
      final source = File('${tempDir.path}/parity_video.mp4');
      final dest = File('${tempDir.path}/parity_video_signed.mp4');
      await source.writeAsBytes(video);
      final builder = await createBuilder();
      try {
        final result = await builder.signFile(
          sourcePath: source.path,
          destPath: dest.path,
          signer: pemSigner(),
        );
        expect(result.manifestSize, greaterThan(0));
        final store = await c2pa.readManifestFromFile(dest.path);
        expect(store.activeManifest, isNotNull);
        expect(signatureFailures(store), isEmpty);
      } finally {
        await builder.dispose();
      }
    });

    testWidgets('fragmented BMFF Merkle flow produces a manifest', (
      tester,
    ) async {
      // Mirrors the upstream testBmffMerkleHashing: a placeholder creates the
      // Merkle slots, 1 KB leaves split the mdat, and a dummy mdat leaf
      // exercises the path (the asset itself will not validate).
      final settings = await C2paSettings.create();
      await settings.updateFromString(
        '{"version": 1, "builder": '
            '{"created_assertion_labels": ["c2pa.actions"]}}',
        'json',
      );
      final context = await C2paContext.create(
        settings: settings,
        signer: pemSigner(),
      );
      final builder = await createBuilder(context: context);
      try {
        await builder.placeholder('video/mp4');
        await builder.setFixedSizeMerkle(1);
        await builder.hashMdatBytes(
          mdatId: 0,
          data: Uint8List(4096)..fillRange(0, 4096, 0xAB),
          largeSize: true,
        );
        await builder.updateHashFromBytes('video/mp4', video);
        final embeddable = await builder.signEmbeddable('video/mp4');
        expect(embeddable, isNotEmpty);
      } finally {
        await builder.dispose();
        await context.dispose();
        await settings.dispose();
      }
    });
  });

  group('Embeddable error paths', () {
    final fails = throwsA(isA<C2paException>());

    testWidgets('placeholder needs a context signer', (tester) async {
      final builder = await createBuilder();
      try {
        await expectLater(builder.placeholder('image/jpeg'), fails);
      } finally {
        await builder.dispose();
      }
    });

    testWidgets('signEmbeddable needs a context signer', (tester) async {
      final builder = await createBuilder();
      try {
        await expectLater(builder.signEmbeddable('image/jpeg'), fails);
      } finally {
        await builder.dispose();
      }
    });

    testWidgets('exclusions need a placeholder first', (tester) async {
      final builder = await createBuilder();
      try {
        await expectLater(
          builder.setDataHashExclusions(const [
            DataHashExclusion(start: 0, length: 2),
          ]),
          fails,
        );
      } finally {
        await builder.dispose();
      }
    });

    testWidgets('composeManifest rejects an unsupported format', (
      tester,
    ) async {
      await expectLater(
        c2pa.composeManifest(
          manifestBytes: Uint8List.fromList([1, 2, 3]),
          mimeType: 'application/x-unsupported',
        ),
        fails,
      );
    });
  });

  group('Cancellation', () {
    testWidgets('cancelling the context stops a sign in progress', (
      tester,
    ) async {
      late C2paContext context;
      context = await C2paContext.create(
        signer: CallbackSigner(
          algorithm: SigningAlgorithm.es256,
          certificateChainPem: cert,
          signCallback: (data) async {
            // The native operation is blocked waiting for this signature.
            await context.cancel();
            return _es256Sign(data, privateScalar);
          },
        ),
      );
      final builder = await createBuilder(context: context);
      try {
        await expectLater(
          builder.sign(sourceData: video, mimeType: 'video/mp4'),
          throwsA(isA<C2paCancelledException>()),
        );
      } finally {
        await builder.dispose();
        await context.dispose();
      }
    });

    testWidgets('disposing a context mid-sign lets the sign finish', (
      tester,
    ) async {
      final context = await C2paContext.create(signer: pemSigner());
      final builder = await createBuilder(context: context);
      try {
        final signing = builder.sign(sourceData: jpeg, mimeType: 'image/jpeg');
        await context.dispose();
        final result = await signing;
        expect(result.signedData, isNotEmpty);
      } finally {
        await builder.dispose();
      }
    });
  });

  group('HTTP resolver failures', () {
    const remoteUrl = 'https://example.invalid/manifests/parity.c2pa';

    Future<Uint8List> remoteOnlyAsset() async {
      final builder = await createBuilder();
      try {
        await builder.setNoEmbed();
        await builder.setRemoteUrl(remoteUrl);
        final result = await builder.sign(
          sourceData: jpeg,
          mimeType: 'image/jpeg',
          signer: pemSigner(),
        );
        return result.signedData;
      } finally {
        await builder.dispose();
      }
    }

    Future<void> expectReadFails(C2paHttpResolver resolver) async {
      final asset = await remoteOnlyAsset();
      final settings = await C2paSettings.create();
      await settings.setValue('verify.remote_manifest_fetch', true);
      final context = await C2paContext.create(
        settings: settings,
        httpResolver: resolver,
      );
      try {
        await expectLater(
          c2pa.readManifestFromBytes(
            asset,
            'image/jpeg',
            options: ReaderOptions(context: context),
          ),
          throwsA(isA<C2paException>()),
        );
      } finally {
        await context.dispose();
        await settings.dispose();
      }
    }

    testWidgets('a Dart resolver that throws fails the read', (tester) async {
      await expectReadFails(
        CallbackHttpResolver((request) async => throw StateError('offline')),
      );
    });

    testWidgets('a 404 from a Dart resolver fails the read', (tester) async {
      await expectReadFails(
        CallbackHttpResolver(
          (request) async => C2paHttpResponse(status: 404, body: Uint8List(0)),
        ),
      );
    });

    testWidgets('the native resolver reports an unreachable host', (
      tester,
    ) async {
      await expectReadFails(const NativeHttpResolver());
    });
  });

  group('Settings', () {
    testWidgets('setValue takes JSON scalars alongside a settings signer', (
      tester,
    ) async {
      final settings = await C2paSettings.create();
      await settings.updateFromString(
        jsonEncode({'version': 1, 'signer': localSigner()}),
        'json',
      );
      await settings.setValue('verify.verify_after_sign', false);
      await settings.setValue('builder.thumbnail.enabled', false);
      final context = await C2paContext.create(settings: settings);
      final builder = await createBuilder(context: context);
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
        await settings.dispose();
      }
    });

    testWidgets('TOML settings carry a signer', (tester) async {
      String toml(String pem) => "'''\n$pem'''";
      final settings = await C2paSettings.create();
      await settings.updateFromString(
        'version = 1\n'
            '[signer.local]\n'
            'alg = "es256"\n'
            'sign_cert = ${toml(cert)}\n'
            'private_key = ${toml(key)}\n',
        'toml',
      );
      final builder = await c2pa.createBuilderWithSettings(
        manifest(),
        settings,
      );
      try {
        await builder.setIntent(
          ManifestIntent.create,
          DigitalSourceType.digitalCapture,
        );
        final result = await builder.sign(
          sourceData: jpeg,
          mimeType: 'image/jpeg',
        );
        expect(result.signedData, isNotEmpty);
      } finally {
        await builder.dispose();
        await settings.dispose();
      }
    });

    testWidgets('builders without a context record actions as created', (
      tester,
    ) async {
      // Both platforms apply c2pa-android's default created_assertion_labels.
      final builder = await createBuilder();
      try {
        final result = await builder.sign(
          sourceData: jpeg,
          mimeType: 'image/jpeg',
          signer: pemSigner(),
        );
        final detailed =
            jsonDecode(
                  await C2paPlatform.instance.readBytesDetailed(
                    result.signedData,
                    'image/jpeg',
                    true,
                  ),
                )
                as Map<String, dynamic>;
        final label = detailed['active_manifest'] as String;
        final claim =
            ((detailed['manifests'] as Map<String, dynamic>)[label]
                    as Map<String, dynamic>)['claim']
                as Map<String, dynamic>;
        final created = jsonEncode(claim['created_assertions'] ?? const []);
        expect(created, contains('c2pa.actions'));
      } finally {
        await builder.dispose();
      }
    });
  });

  group('Key management', () {
    testWidgets('import, export, CSR, keystore signing and delete', (
      tester,
    ) async {
      const alias = 'c2pa_flutter_parity_import';
      await c2pa.deleteKey(alias);
      await c2pa.importKey(
        keyAlias: alias,
        privateKeyPem: key,
        certificateChainPem: cert,
      );
      try {
        expect(await c2pa.keyExists(alias), isTrue);
        expect(
          await c2pa.exportPublicKey(alias),
          startsWith('-----BEGIN PUBLIC KEY-----'),
        );
        expect(
          await c2pa.createCSR(keyAlias: alias, commonName: 'Parity Test'),
          contains('CERTIFICATE REQUEST-----'),
        );

        final builder = await createBuilder();
        try {
          final result = await builder.sign(
            sourceData: jpeg,
            mimeType: 'image/jpeg',
            signer: KeystoreSigner(
              algorithm: SigningAlgorithm.es256,
              certificateChainPem: cert,
              keyAlias: alias,
            ),
          );
          final store = await c2pa.readManifestFromBytes(
            result.signedData,
            'image/jpeg',
          );
          expect(signatureFailures(store), isEmpty);
        } finally {
          await builder.dispose();
        }
      } finally {
        expect(await c2pa.deleteKey(alias), isTrue);
      }
      expect(await c2pa.keyExists(alias), isFalse);
    });

    testWidgets('createKey makes a key on the requested curve', (
      tester,
    ) async {
      // DER SubjectPublicKeyInfo sizes for uncompressed EC points.
      const spkiBytes = {
        SigningAlgorithm.es256: 91,
        SigningAlgorithm.es384: 120,
        SigningAlgorithm.es512: 158,
      };
      for (final entry in spkiBytes.entries) {
        final alias = 'c2pa_flutter_parity_${entry.key.name}';
        await c2pa.deleteKey(alias);
        await c2pa.createKey(keyAlias: alias, algorithm: entry.key);
        try {
          final pem = await c2pa.exportPublicKey(alias);
          final body = pem
              .split('\n')
              .where((l) => l.isNotEmpty && !l.startsWith('-----'))
              .join();
          expect(
            base64.decode(body).length,
            entry.value,
            reason: entry.key.name,
          );
        } finally {
          await c2pa.deleteKey(alias);
        }
      }
    });

    testWidgets('createKey rejects algorithms it cannot honour', (
      tester,
    ) async {
      await expectLater(
        c2pa.createKey(
          keyAlias: 'c2pa_flutter_parity_rsa',
          algorithm: SigningAlgorithm.ps256,
        ),
        throwsA(isA<C2paInvalidArgumentException>()),
      );
      await expectLater(
        c2pa.createKey(
          keyAlias: 'c2pa_flutter_parity_hw384',
          algorithm: SigningAlgorithm.es384,
          useHardware: true,
        ),
        throwsA(isA<C2paInvalidArgumentException>()),
      );
    });
  });

  group('Remote signer', () {
    testWidgets('an unreachable configuration endpoint fails the sign', (
      tester,
    ) async {
      final builder = await createBuilder();
      try {
        await expectLater(
          builder.sign(
            sourceData: jpeg,
            mimeType: 'image/jpeg',
            signer: const RemoteSigner(
              configurationUrl: 'https://example.invalid/signer/config',
            ),
          ),
          throwsA(isA<C2paException>()),
        );
      } finally {
        await builder.dispose();
      }
    });
  });

  group('CAWG identity', () {
    testWidgets('a callback claim signer combines with a PEM identity', (
      tester,
    ) async {
      final builder = await createBuilder();
      try {
        final result = await builder.sign(
          sourceData: jpeg,
          mimeType: 'image/jpeg',
          signer: CawgIdentitySigner(
            claimSigner: callbackSigner(),
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
}
