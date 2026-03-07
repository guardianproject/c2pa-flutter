// Integration test: OOM regression for large file signing (ByteArrayStream→FileStream)
//
// Production crashlytics: 30 OOM crashes in handleSignFile on Android.
// Root cause: readBytes() + ByteArrayStream loads entire file into JVM heap.
// In production, files are only 7-16MB but the JVM heap is nearly full
// (~240/256MB) after video record→edit flow.
//
// We reproduce this by filling the JVM heap via a test helper method channel,
// then signing a realistic 15MB MP4. This matches production conditions exactly.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:c2pa_flutter/c2pa.dart';

const _testHelper = MethodChannel('c2pa_test_helper');

/// Fills the JVM heap leaving approximately [targetFreeBytes] free.
/// Returns memory stats for logging.
Future<Map<String, dynamic>> fillJvmHeap({int targetFreeBytes = 20 * 1024 * 1024}) async {
  final result = await _testHelper.invokeMethod('fillHeap', {
    'targetFreeBytes': targetFreeBytes,
  });
  return Map<String, dynamic>.from(result as Map);
}

/// Releases all JVM heap ballast.
Future<void> releaseJvmHeap() async {
  await _testHelper.invokeMethod('releaseHeap');
}

/// Creates a minimal valid MP4 file padded to [targetSize].
Future<void> createMp4(File file, int targetSize) async {
  final sink = file.openWrite();

  // ftyp box: 20 bytes
  final ftyp = ByteData(20);
  ftyp.setUint32(0, 20);
  ftyp.setUint8(4, 0x66); ftyp.setUint8(5, 0x74); // ft
  ftyp.setUint8(6, 0x79); ftyp.setUint8(7, 0x70); // yp
  ftyp.setUint8(8, 0x69); ftyp.setUint8(9, 0x73); // is
  ftyp.setUint8(10, 0x6F); ftyp.setUint8(11, 0x6D); // om
  ftyp.setUint32(12, 0);
  ftyp.setUint8(16, 0x69); ftyp.setUint8(17, 0x73); // is
  ftyp.setUint8(18, 0x6F); ftyp.setUint8(19, 0x6D); // om
  sink.add(ftyp.buffer.asUint8List());

  // mdat box: remaining space
  final mdatSize = targetSize - 20;
  final mdatHeader = ByteData(8);
  mdatHeader.setUint32(0, mdatSize);
  mdatHeader.setUint8(4, 0x6D); mdatHeader.setUint8(5, 0x64); // md
  mdatHeader.setUint8(6, 0x61); mdatHeader.setUint8(7, 0x74); // at
  sink.add(mdatHeader.buffer.asUint8List());

  final remaining = mdatSize - 8;
  final chunk = Uint8List(1024 * 1024);
  for (var i = 0; i < remaining ~/ chunk.length; i++) {
    sink.add(chunk);
  }
  final tail = remaining % chunk.length;
  if (tail > 0) sink.add(Uint8List(tail));

  await sink.flush();
  await sink.close();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late C2pa c2pa;
  late Directory tempDir;
  late String testCert;

  setUpAll(() async {
    c2pa = C2pa();
    tempDir = await getTemporaryDirectory();
    testCert = await rootBundle.loadString('assets/test_certs/test_es256_cert.pem');
  });

  tearDown(() async {
    await releaseJvmHeap();
  });

  testWidgets('signFile under memory pressure does not OOM', (tester) async {
    // Step 1: Fill JVM heap to simulate post-camera memory state.
    // Leave ~15MB free, matching crashlytics data (devices had 7-16MB free).
    final memStats = await fillJvmHeap(targetFreeBytes: 15 * 1024 * 1024);
    final freeMB = (memStats['freeMemory'] as int) / (1024 * 1024);
    final maxMB = (memStats['maxMemory'] as int) / (1024 * 1024);
    // ignore: avoid_print
    print('Heap state: ${freeMB.toStringAsFixed(1)}MB free of ${maxMB.toStringAsFixed(1)}MB');

    // Step 2: Create a realistic 15MB MP4 (typical 6-second video)
    final videoFile = File('${tempDir.path}/oom_test.mp4');
    final destFile = File('${tempDir.path}/oom_test_signed.mp4');
    await createMp4(videoFile, 15 * 1024 * 1024);

    final manifest = jsonEncode({
      'claim_generator': 'c2pa_flutter_oom_test/1.0',
      'title': 'OOM Test',
      'format': 'video/mp4',
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

    // CallbackSigner hits the non-PEM code path that had readBytes().
    final signer = CallbackSigner(
      algorithm: SigningAlgorithm.es256,
      certificateChainPem: testCert,
      signCallback: (data) async => Uint8List(64),
    );

    // Before fix: readBytes() tries to allocate 15MB contiguously on a
    // heap with only 15MB free → OOM → process killed
    // After fix: FileStream reads from disk → zero JVM heap pressure
    try {
      await c2pa.signFile(
        sourcePath: videoFile.path,
        destPath: destFile.path,
        manifestJson: manifest,
        signer: signer,
      );
    } on PlatformException catch (e) {
      // C2PA error is fine — means plugin survived without crashing
      expect(e.code, anyOf('C2PA_ERROR', 'ERROR'));
    }

    // Cleanup
    if (await videoFile.exists()) await videoFile.delete();
    if (await destFile.exists()) await destFile.delete();
  });
}
