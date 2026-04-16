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

import 'package:c2pa_flutter/c2pa.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('C2paSettingsDefinition', () {
    test('empty definition serializes to empty object', () {
      const def = C2paSettingsDefinition();
      expect(def.toJson(), <String, dynamic>{});
      expect(def.toJsonString(), '{}');
    });

    test('version-only definition serializes correctly', () {
      const def = C2paSettingsDefinition(version: 1);
      expect(def.toJson(), {'version': 1});
    });

    test('CAWG-keyed fields use snake_case wire names', () {
      const def = C2paSettingsDefinition(
        version: 1,
        cawgTrust: TrustSettings(verifyTrustList: true),
        cawgX509Signer: SignerSettings.local(
          LocalSignerSettings(alg: 'es256', signCert: 'c', privateKey: 'k'),
        ),
      );
      final json = def.toJson();
      expect(json.containsKey('cawg_trust'), true);
      expect(json.containsKey('cawg_x509_signer'), true);
      expect(json.containsKey('cawgTrust'), false);
    });

    test('trust settings serialize snake_case', () {
      const trust = TrustSettings(
        verifyTrustList: true,
        userAnchors: '---user---',
        trustAnchors: '---trust---',
        trustConfig: '{"foo":"bar"}',
        allowedList: 'allowed',
      );
      expect(trust.toJson(), {
        'verify_trust_list': true,
        'user_anchors': '---user---',
        'trust_anchors': '---trust---',
        'trust_config': '{"foo":"bar"}',
        'allowed_list': 'allowed',
      });
    });

    test('core settings serialize snake_case', () {
      const core = CoreSettings(
        merkleTreeChunkSizeInKb: 256,
        merkleTreeMaxProofs: 1024,
        backingStoreMemoryThresholdInMb: 64,
        decodeIdentityAssertions: true,
        allowedNetworkHosts: ['timestamp.digicert.com'],
      );
      expect(core.toJson(), {
        'merkle_tree_chunk_size_in_kb': 256,
        'merkle_tree_max_proofs': 1024,
        'backing_store_memory_threshold_in_mb': 64,
        'decode_identity_assertions': true,
        'allowed_network_hosts': ['timestamp.digicert.com'],
      });
    });

    test('verify settings include every known flag', () {
      const verify = VerifySettings(
        verifyAfterReading: true,
        verifyAfterSign: false,
        verifyTrust: true,
        verifyTimestampTrust: false,
        ocspFetch: true,
        remoteManifestFetch: false,
        skipIngredientConflictResolution: true,
        strictV1Validation: false,
      );
      final json = verify.toJson();
      expect(json['verify_after_reading'], true);
      expect(json['verify_after_sign'], false);
      expect(json['verify_trust'], true);
      expect(json['verify_timestamp_trust'], false);
      expect(json['ocsp_fetch'], true);
      expect(json['remote_manifest_fetch'], false);
      expect(json['skip_ingredient_conflict_resolution'], true);
      expect(json['strict_v1_validation'], false);
    });

    test('builder settings encode nested thumbnail and actions', () {
      const builder = BuilderSettingsDefinition(
        vendor: 'ACME',
        claimGeneratorInfo: ClaimGeneratorInfoSettings(
          name: 'ACME Editor',
          version: '1.0',
          operatingSystem: 'iOS 18',
        ),
        thumbnail: ThumbnailSettings(
          enabled: true,
          format: ThumbnailFormat.webp,
          quality: ThumbnailQuality.high,
          longEdge: 512,
        ),
        actions: ActionsSettings(
          allActionsIncluded: true,
          autoCreatedAction: AutoActionSettings(enabled: true),
        ),
        certificateStatusFetch: OcspFetchScope.active,
        createdAssertionLabels: ['c2pa.actions'],
        preferBoxHash: false,
      );
      final json = builder.toJson();
      expect(json['vendor'], 'ACME');
      expect(json['claim_generator_info'], {
        'name': 'ACME Editor',
        'version': '1.0',
        'operating_system': 'iOS 18',
      });
      expect(json['thumbnail'], {
        'enabled': true,
        'long_edge': 512,
        'format': 'webp',
        'quality': 'high',
      });
      expect(json['actions'], {
        'all_actions_included': true,
        'auto_created_action': {'enabled': true},
      });
      expect(json['certificate_status_fetch'], 'active');
      expect(json['created_assertion_labels'], ['c2pa.actions']);
      expect(json['prefer_box_hash'], false);
    });

    test('SettingsIntent.create encodes with digital_source_type', () {
      const intent = SettingsIntent.create(
        'http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture',
      );
      expect(intent.toJson(), {
        'Create': {
          'digital_source_type':
              'http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture',
        },
      });
    });

    test('SettingsIntent.edit and .update encode as strings', () {
      expect(SettingsIntent.edit.toJson(), 'Edit');
      expect(SettingsIntent.update.toJson(), 'Update');
    });

    test('SignerSettings.local encodes under "local"', () {
      const signer = SignerSettings.local(
        LocalSignerSettings(
          alg: 'es256',
          signCert: '---CERT---',
          privateKey: '---KEY---',
          tsaUrl: 'http://timestamp.digicert.com',
          referencedAssertions: ['c2pa.actions'],
        ),
      );
      expect(signer.toJson(), {
        'local': {
          'alg': 'es256',
          'sign_cert': '---CERT---',
          'private_key': '---KEY---',
          'tsa_url': 'http://timestamp.digicert.com',
          'referenced_assertions': ['c2pa.actions'],
        },
      });
    });

    test('SignerSettings.remote encodes under "remote"', () {
      const signer = SignerSettings.remote(
        RemoteSignerSettings(
          url: 'https://signing.example.com/sign',
          alg: 'ps256',
          signCert: '---CERT---',
        ),
      );
      expect(signer.toJson(), {
        'remote': {
          'url': 'https://signing.example.com/sign',
          'alg': 'ps256',
          'sign_cert': '---CERT---',
        },
      });
    });

    test('timestamp settings and fetch scope', () {
      const ts = TimeStampSettings(
        enabled: true,
        skipExisting: false,
        fetchScope: TimeStampFetchScope.all,
      );
      expect(ts.toJson(), {
        'enabled': true,
        'skip_existing': false,
        'fetch_scope': 'all',
      });
    });

    test('full round-trip through JSON string is deterministic', () {
      const def = C2paSettingsDefinition(
        version: 1,
        verify: VerifySettings(verifyTrust: false),
        signer: SignerSettings.local(
          LocalSignerSettings(
            alg: 'es256',
            signCert: 'c',
            privateKey: 'k',
            tsaUrl: 'http://tsa.example',
          ),
        ),
      );
      final serialized = def.toJsonString();
      final parsed = jsonDecode(serialized) as Map<String, dynamic>;
      expect(parsed['version'], 1);
      expect(parsed['verify'], {'verify_trust': false});
      expect(parsed['signer'], {
        'local': {
          'alg': 'es256',
          'sign_cert': 'c',
          'private_key': 'k',
          'tsa_url': 'http://tsa.example',
        },
      });
    });
  });
}
