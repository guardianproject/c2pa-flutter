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

// Test PEM certificate chain (from test fixtures)
const testCert = '-----BEGIN CERTIFICATE-----\n'
    'MIIChzCCAi6gAwIBAgIUcCTmJHYF8dZfG0d1UdT6/LXtkeYwCgYIKoZIzj0EAwIw\n'
    'gYwxCzAJBgNVBAYTAlVTMQswCQYDVQQIDAJDQTESMBAGA1UEBwwJU29tZXdoZXJl\n'
    'MScwJQYDVQQKDB5DMlBBIFRlc3QgSW50ZXJtZWRpYXRlIFJvb3QgQ0ExGTAXBgNV\n'
    'BAsMEEZPUiBURVNUSU5HX09OTFkxGDAWBgNVBAMMD0ludGVybWVkaWF0ZSBDQTAe\n'
    'Fw0yMjA2MTAxODQ2NDBaFw0zMDA4MjYxODQ2NDBaMIGAMQswCQYDVQQGEwJVUzEL\n'
    '-----END CERTIFICATE-----';

const testKey = '-----BEGIN PRIVATE KEY-----\n'
    'MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgfNJBsaRLSeHizv0m\n'
    'GL+gcn78QmtfLSm+n+qG9veC2W2hRANCAAQPaL6RkAkYkKU4+IryBSYxJM3h77sF\n'
    'iMrbvbI8fG7w2Bbl9otNG/cch3DAw5rGAPV7NWkyl3QGuV/wt0MrAPDo\n'
    '-----END PRIVATE KEY-----';

const invalidPem = 'NOT A VALID PEM STRING';

/// Convenience: build a settings map, encode to JSON, and validate.
ValidationResult validateSettings(Map<String, dynamic> settings) {
  return SettingsValidator.validate(jsonEncode(settings));
}

void main() {
  // =============================================================================
  // SettingsValidator.validate()
  // =============================================================================

  group('SettingsValidator.validate()', () {
    // ===========================================================================
    // Version validation
    // ===========================================================================
    group('version validation', () {
      test('missing version produces error', () {
        final result = validateSettings({});
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains('version')),
        );
      });

      test('non-integer version produces error', () {
        final result = validateSettings({'version': '1'});
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains("'version' must be an integer")),
        );
      });

      test('wrong version number produces error', () {
        final result = validateSettings({'version': 2});
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains("'version' must be 1, got 2")),
        );
      });

      test('correct version (1) passes', () {
        final result = validateSettings({'version': 1});
        expect(result.isValid, isTrue);
        expect(result.errors, isEmpty);
      });
    });

    // ===========================================================================
    // Top-level keys
    // ===========================================================================
    group('top-level keys', () {
      test('unknown top-level key produces warning', () {
        final result = validateSettings({
          'version': 1,
          'bogus_key': 'whatever',
        });
        expect(result.isValid, isTrue);
        expect(result.hasWarnings, isTrue);
        expect(
          result.warnings,
          contains(contains('Unknown top-level key')),
        );
      });

      test('all known keys are accepted without warnings', () {
        // Provide minimal valid structures so that each section does not
        // itself produce warnings.
        final result = validateSettings({
          'version': 1,
          'trust': <String, dynamic>{},
          'cawg_trust': <String, dynamic>{},
          'core': 'placeholder',
          'verify': <String, dynamic>{},
          'builder': <String, dynamic>{},
          'signer': {
            'local': {
              'alg': 'es256',
              'sign_cert': testCert,
              'private_key': testKey,
            },
          },
          'cawg_x509_signer': {
            'local': {
              'alg': 'es256',
              'sign_cert': testCert,
              'private_key': testKey,
            },
          },
        });
        expect(
          result.warnings.where((w) => w.contains('Unknown top-level key')),
          isEmpty,
        );
      });
    });

    // ===========================================================================
    // Trust section
    // ===========================================================================
    group('trust section', () {
      test('valid trust section passes', () {
        final result = validateSettings({
          'version': 1,
          'trust': {
            'user_anchors': testCert,
            'trust_anchors': testCert,
          },
        });
        expect(result.isValid, isTrue);
        expect(
          result.errors.where((e) => e.contains('trust')),
          isEmpty,
        );
      });

      test('invalid PEM in user_anchors produces error', () {
        final result = validateSettings({
          'version': 1,
          'trust': {
            'user_anchors': invalidPem,
          },
        });
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains('trust.user_anchors')),
        );
      });

      test('invalid PEM in trust_anchors produces error', () {
        final result = validateSettings({
          'version': 1,
          'trust': {
            'trust_anchors': invalidPem,
          },
        });
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains('trust.trust_anchors')),
        );
      });

      test('unknown key in trust section produces warning', () {
        final result = validateSettings({
          'version': 1,
          'trust': {
            'unknown_field': 'value',
          },
        });
        expect(result.hasWarnings, isTrue);
        expect(
          result.warnings,
          contains(contains("Unknown key in trust")),
        );
      });

      test('cawg_trust section validates same as trust', () {
        // Invalid PEM in cawg_trust should produce an error with the
        // cawg_trust prefix.
        final result = validateSettings({
          'version': 1,
          'cawg_trust': {
            'user_anchors': invalidPem,
          },
        });
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains('cawg_trust.user_anchors')),
        );
      });
    });

    // ===========================================================================
    // Verify section
    // ===========================================================================
    group('verify section', () {
      test('valid verify section with booleans passes', () {
        final result = validateSettings({
          'version': 1,
          'verify': {
            'verify_after_reading': true,
            'verify_trust': true,
            'verify_timestamp_trust': true,
            'verify_after_sign': true,
            'ocsp_fetch': false,
          },
        });
        expect(result.isValid, isTrue);
        // No errors related to verify
        expect(
          result.errors.where((e) => e.contains('verify')),
          isEmpty,
        );
      });

      test('non-boolean value in verify produces error', () {
        final result = validateSettings({
          'version': 1,
          'verify': {
            'verify_trust': 'yes',
          },
        });
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains('verify.verify_trust must be a boolean')),
        );
      });

      test('verify_trust=false produces security warning', () {
        final result = validateSettings({
          'version': 1,
          'verify': {
            'verify_trust': false,
          },
        });
        expect(result.hasWarnings, isTrue);
        expect(
          result.warnings,
          contains(contains('verify.verify_trust is set to false')),
        );
      });

      test('verify_timestamp_trust=false produces security warning', () {
        final result = validateSettings({
          'version': 1,
          'verify': {
            'verify_timestamp_trust': false,
          },
        });
        expect(result.hasWarnings, isTrue);
        expect(
          result.warnings,
          contains(contains('verify.verify_timestamp_trust is set to false')),
        );
      });

      test('verify_after_sign=false produces security warning', () {
        final result = validateSettings({
          'version': 1,
          'verify': {
            'verify_after_sign': false,
          },
        });
        expect(result.hasWarnings, isTrue);
        expect(
          result.warnings,
          contains(contains('verify.verify_after_sign is set to false')),
        );
      });

      test('unknown key in verify produces warning', () {
        final result = validateSettings({
          'version': 1,
          'verify': {
            'not_a_real_key': true,
          },
        });
        expect(result.hasWarnings, isTrue);
        expect(
          result.warnings,
          contains(contains("Unknown key in verify")),
        );
      });
    });

    // ===========================================================================
    // Builder section
    // ===========================================================================
    group('builder section', () {
      test('valid builder section passes', () {
        final result = validateSettings({
          'version': 1,
          'builder': {
            'claim_generator_info': [
              {'name': 'TestApp', 'version': '1.0'},
            ],
            'intent': 'Edit',
          },
        });
        expect(result.isValid, isTrue);
        expect(
          result.errors.where((e) => e.contains('builder')),
          isEmpty,
        );
      });

      test('unknown key in builder produces warning', () {
        final result = validateSettings({
          'version': 1,
          'builder': {
            'fake_option': 42,
          },
        });
        expect(result.hasWarnings, isTrue);
        expect(
          result.warnings,
          contains(contains("Unknown key in builder")),
        );
      });

      test("valid intent string 'Edit' passes", () {
        final result = validateSettings({
          'version': 1,
          'builder': {
            'intent': 'Edit',
          },
        });
        expect(result.isValid, isTrue);
        expect(
          result.errors.where((e) => e.contains('intent')),
          isEmpty,
        );
      });

      test("valid intent string 'Update' passes", () {
        final result = validateSettings({
          'version': 1,
          'builder': {
            'intent': 'Update',
          },
        });
        expect(result.isValid, isTrue);
        expect(
          result.errors.where((e) => e.contains('intent')),
          isEmpty,
        );
      });

      test('invalid intent string produces error', () {
        final result = validateSettings({
          'version': 1,
          'builder': {
            'intent': 'Delete',
          },
        });
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains('builder.intent string must be one of')),
        );
      });

      test('intent as object with Create key and valid source type passes',
          () {
        final result = validateSettings({
          'version': 1,
          'builder': {
            'intent': {'Create': 'digitalCapture'},
          },
        });
        expect(result.isValid, isTrue);
        expect(
          result.errors.where((e) => e.contains('intent')),
          isEmpty,
        );
      });

      test('intent as object with invalid source type produces error', () {
        final result = validateSettings({
          'version': 1,
          'builder': {
            'intent': {'Create': 'invalidSource'},
          },
        });
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains('builder.intent Create source type must be one of')),
        );
      });

      test('intent as object without Create key produces error', () {
        final result = validateSettings({
          'version': 1,
          'builder': {
            'intent': {'Edit': 'digitalCapture'},
          },
        });
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains("builder.intent object must have 'Create' key")),
        );
      });

      test('invalid intent type (not string or map) produces error', () {
        final result = validateSettings({
          'version': 1,
          'builder': {
            'intent': 42,
          },
        });
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains('builder.intent must be a string')),
        );
      });
    });

    // ===========================================================================
    // Thumbnail validation
    // ===========================================================================
    group('thumbnail validation', () {
      test('valid thumbnail format passes', () {
        final result = validateSettings({
          'version': 1,
          'builder': {
            'thumbnail': {'format': 'jpeg'},
          },
        });
        expect(result.isValid, isTrue);
        expect(
          result.errors.where((e) => e.contains('thumbnail')),
          isEmpty,
        );
      });

      test('invalid format produces error', () {
        final result = validateSettings({
          'version': 1,
          'builder': {
            'thumbnail': {'format': 'bmp'},
          },
        });
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains('builder.thumbnail.format must be one of')),
        );
      });

      test('valid quality passes', () {
        final result = validateSettings({
          'version': 1,
          'builder': {
            'thumbnail': {'quality': 'medium'},
          },
        });
        expect(result.isValid, isTrue);
        expect(
          result.errors.where((e) => e.contains('thumbnail')),
          isEmpty,
        );
      });

      test('invalid quality produces error', () {
        final result = validateSettings({
          'version': 1,
          'builder': {
            'thumbnail': {'quality': 'ultra'},
          },
        });
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains('builder.thumbnail.quality must be one of')),
        );
      });

      test('unknown thumbnail key produces warning', () {
        final result = validateSettings({
          'version': 1,
          'builder': {
            'thumbnail': {'made_up_key': true},
          },
        });
        expect(result.hasWarnings, isTrue);
        expect(
          result.warnings,
          contains(contains('Unknown key in builder.thumbnail')),
        );
      });
    });

    // ===========================================================================
    // Signer section (local)
    // ===========================================================================
    group('signer section (local)', () {
      Map<String, dynamic> localSignerSettings({
        Map<String, dynamic>? localOverrides,
      }) {
        final local = <String, dynamic>{
          'alg': 'es256',
          'sign_cert': testCert,
          'private_key': testKey,
          ...?localOverrides,
        };
        return {
          'version': 1,
          'signer': {'local': local},
        };
      }

      test('valid local signer passes', () {
        final result = validateSettings(localSignerSettings());
        expect(result.isValid, isTrue);
        expect(
          result.errors.where((e) => e.contains('signer')),
          isEmpty,
        );
      });

      test('missing alg produces error', () {
        final settings = localSignerSettings();
        (settings['signer'] as Map)['local'].remove('alg');
        final result = validateSettings(settings);
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains('signer.local.alg is required')),
        );
      });

      test('missing sign_cert produces error', () {
        final settings = localSignerSettings();
        (settings['signer'] as Map)['local'].remove('sign_cert');
        final result = validateSettings(settings);
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains('signer.local.sign_cert is required')),
        );
      });

      test('missing private_key produces error', () {
        final settings = localSignerSettings();
        (settings['signer'] as Map)['local'].remove('private_key');
        final result = validateSettings(settings);
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains('signer.local.private_key is required')),
        );
      });

      test('invalid algorithm produces error', () {
        final result = validateSettings(localSignerSettings(
          localOverrides: {'alg': 'rsa1024'},
        ));
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains('signer.local.alg must be one of')),
        );
      });

      test('invalid PEM cert produces error', () {
        final result = validateSettings(localSignerSettings(
          localOverrides: {'sign_cert': invalidPem},
        ));
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains('signer.local.sign_cert must be valid PEM')),
        );
      });

      test('invalid PEM key produces error', () {
        final result = validateSettings(localSignerSettings(
          localOverrides: {'private_key': invalidPem},
        ));
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains('signer.local.private_key must be valid PEM')),
        );
      });

      test('invalid tsa_url produces error', () {
        final result = validateSettings(localSignerSettings(
          localOverrides: {'tsa_url': 'not-a-url'},
        ));
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains('signer.local.tsa_url must be a valid URL')),
        );
      });

      test('valid tsa_url passes', () {
        final result = validateSettings(localSignerSettings(
          localOverrides: {'tsa_url': 'http://timestamp.example.com'},
        ));
        expect(result.isValid, isTrue);
        expect(
          result.errors.where((e) => e.contains('tsa_url')),
          isEmpty,
        );
      });

      test('unknown key produces warning', () {
        final result = validateSettings(localSignerSettings(
          localOverrides: {'extra_field': 'surprise'},
        ));
        expect(result.hasWarnings, isTrue);
        expect(
          result.warnings,
          contains(contains("Unknown key in signer.local")),
        );
      });
    });

    // ===========================================================================
    // Signer section (remote)
    // ===========================================================================
    group('signer section (remote)', () {
      Map<String, dynamic> remoteSignerSettings({
        Map<String, dynamic>? remoteOverrides,
      }) {
        final remote = <String, dynamic>{
          'url': 'https://signer.example.com/sign',
          'alg': 'ps256',
          'sign_cert': testCert,
          ...?remoteOverrides,
        };
        return {
          'version': 1,
          'signer': {'remote': remote},
        };
      }

      test('valid remote signer passes', () {
        final result = validateSettings(remoteSignerSettings());
        expect(result.isValid, isTrue);
        expect(
          result.errors.where((e) => e.contains('signer')),
          isEmpty,
        );
      });

      test('missing url produces error', () {
        final settings = remoteSignerSettings();
        (settings['signer'] as Map)['remote'].remove('url');
        final result = validateSettings(settings);
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains('signer.remote.url is required')),
        );
      });

      test('missing alg produces error', () {
        final settings = remoteSignerSettings();
        (settings['signer'] as Map)['remote'].remove('alg');
        final result = validateSettings(settings);
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains('signer.remote.alg is required')),
        );
      });

      test('missing sign_cert produces error', () {
        final settings = remoteSignerSettings();
        (settings['signer'] as Map)['remote'].remove('sign_cert');
        final result = validateSettings(settings);
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains('signer.remote.sign_cert is required')),
        );
      });

      test('invalid url produces error', () {
        final result = validateSettings(remoteSignerSettings(
          remoteOverrides: {'url': 'ftp://bad-scheme.example.com'},
        ));
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains('signer.remote.url must be a valid URL')),
        );
      });

      test('invalid algorithm produces error', () {
        final result = validateSettings(remoteSignerSettings(
          remoteOverrides: {'alg': 'sha1'},
        ));
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains('signer.remote.alg must be one of')),
        );
      });
    });

    // ===========================================================================
    // Combined signer
    // ===========================================================================
    group('combined signer', () {
      test('having both local and remote produces error', () {
        final result = validateSettings({
          'version': 1,
          'signer': {
            'local': {
              'alg': 'es256',
              'sign_cert': testCert,
              'private_key': testKey,
            },
            'remote': {
              'url': 'https://signer.example.com/sign',
              'alg': 'ps256',
              'sign_cert': testCert,
            },
          },
        });
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains("cannot have both 'local' and 'remote'")),
        );
      });

      test('having neither local nor remote produces error', () {
        final result = validateSettings({
          'version': 1,
          'signer': <String, dynamic>{},
        });
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains("must have either 'local' or 'remote'")),
        );
      });

      test('cawg_x509_signer validates same as signer', () {
        // Neither local nor remote in cawg_x509_signer should produce an
        // error using the cawg_x509_signer prefix.
        final result = validateSettings({
          'version': 1,
          'cawg_x509_signer': <String, dynamic>{},
        });
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(
            contains("cawg_x509_signer must have either 'local' or 'remote'"),
          ),
        );
      });
    });

    // ===========================================================================
    // Full settings
    // ===========================================================================
    group('full settings', () {
      test('minimal valid settings (version only) passes', () {
        final result = validateSettings({'version': 1});
        expect(result.isValid, isTrue);
        expect(result.errors, isEmpty);
      });

      test('complete valid settings passes', () {
        final result = validateSettings({
          'version': 1,
          'trust': {
            'user_anchors': testCert,
            'trust_anchors': testCert,
          },
          'verify': {
            'verify_after_reading': true,
            'verify_trust': true,
            'verify_timestamp_trust': true,
            'verify_after_sign': true,
          },
          'builder': {
            'claim_generator_info': [
              {'name': 'TestApp', 'version': '1.0'},
            ],
            'intent': 'Edit',
            'thumbnail': {
              'format': 'jpeg',
              'quality': 'high',
              'enabled': true,
            },
          },
          'signer': {
            'local': {
              'alg': 'es256',
              'sign_cert': testCert,
              'private_key': testKey,
              'tsa_url': 'https://timestamp.example.com',
            },
          },
        });
        expect(result.isValid, isTrue);
        expect(result.errors, isEmpty);
        expect(result.hasWarnings, isFalse);
      });

      test('invalid JSON produces error', () {
        final result = SettingsValidator.validate('{ this is not valid JSON }');
        expect(result.hasErrors, isTrue);
        expect(
          result.errors,
          contains(contains('Failed to parse settings JSON')),
        );
      });
    });
  });
}
