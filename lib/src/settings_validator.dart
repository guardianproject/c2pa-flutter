import 'dart:convert';

import 'manifest_validator.dart';

/// Validates C2PA settings JSON for schema compliance.
///
/// Checks settings against the C2PA settings schema documented at:
/// https://opensource.contentauthenticity.org/docs/c2pa-rs/settings
class SettingsValidator {
  static const int supportedVersion = 1;

  static const Set<String> _validAlgorithms = {
    'es256',
    'es384',
    'es512',
    'ps256',
    'ps384',
    'ps512',
    'ed25519',
  };

  static const Set<String> _validThumbnailFormats = {'jpeg', 'png', 'webp'};
  static const Set<String> _validThumbnailQualities = {'low', 'medium', 'high'};
  static const Set<String> _validIntentStrings = {'Edit', 'Update'};

  static const Set<String> _validSourceTypes = {
    'empty',
    'digitalCapture',
    'negativeFilm',
    'positiveFilm',
    'print',
    'minorHumanEdits',
    'compositeCapture',
    'algorithmicallyEnhanced',
    'dataDrivenMedia',
    'digitalArt',
    'compositeWithTrainedAlgorithmicMedia',
    'compositeSynthetic',
    'trainedAlgorithmicMedia',
    'algorithmicMedia',
    'virtualRecording',
    'composite',
    'softwareRendered',
    'generatedByAI',
  };

  static const _knownTopLevelKeys = {
    'version',
    'trust',
    'cawg_trust',
    'core',
    'verify',
    'builder',
    'signer',
    'cawg_x509_signer',
  };

  /// Validates a settings JSON string.
  static ValidationResult validate(String settingsJson) {
    final errors = <String>[];
    final warnings = <String>[];

    try {
      final json = jsonDecode(settingsJson) as Map<String, dynamic>;
      _validateSettingsObject(json, errors, warnings);
    } catch (e) {
      if (errors.isEmpty) {
        errors.add('Failed to parse settings JSON: $e');
      }
    }

    return ValidationResult(errors: errors, warnings: warnings);
  }

  static void _validateSettingsObject(
    Map<String, dynamic> settings,
    List<String> errors,
    List<String> warnings,
  ) {
    for (final key in settings.keys) {
      if (!_knownTopLevelKeys.contains(key)) {
        warnings.add("Unknown top-level key: '$key'");
      }
    }

    _validateVersion(settings, errors);

    if (settings['trust'] is Map<String, dynamic>) {
      _validateTrustSection(
        settings['trust'] as Map<String, dynamic>,
        'trust',
        errors,
        warnings,
      );
    }
    if (settings['cawg_trust'] is Map<String, dynamic>) {
      _validateTrustSection(
        settings['cawg_trust'] as Map<String, dynamic>,
        'cawg_trust',
        errors,
        warnings,
      );
    }
    if (settings['verify'] is Map<String, dynamic>) {
      _validateVerifySection(
        settings['verify'] as Map<String, dynamic>,
        errors,
        warnings,
      );
    }
    if (settings['builder'] is Map<String, dynamic>) {
      _validateBuilderSection(
        settings['builder'] as Map<String, dynamic>,
        errors,
        warnings,
      );
    }
    if (settings['signer'] is Map<String, dynamic>) {
      _validateSignerSection(
        settings['signer'] as Map<String, dynamic>,
        'signer',
        errors,
        warnings,
      );
    }
    if (settings['cawg_x509_signer'] is Map<String, dynamic>) {
      _validateSignerSection(
        settings['cawg_x509_signer'] as Map<String, dynamic>,
        'cawg_x509_signer',
        errors,
        warnings,
      );
    }
  }

  static void _validateVersion(
    Map<String, dynamic> settings,
    List<String> errors,
  ) {
    final version = settings['version'];
    if (version == null) {
      errors.add("'version' is required and must be an integer");
    } else if (version is! int) {
      errors.add("'version' must be an integer");
    } else if (version != supportedVersion) {
      errors.add("'version' must be $supportedVersion, got $version");
    }
  }

  static void _validateTrustSection(
    Map<String, dynamic> trust,
    String sectionName,
    List<String> errors,
    List<String> warnings,
  ) {
    const validKeys = {
      'user_anchors',
      'trust_anchors',
      'trust_config',
      'allowed_list',
      'verify_trust_list',
    };

    for (final key in trust.keys) {
      if (!validKeys.contains(key)) {
        warnings.add("Unknown key in $sectionName: '$key'");
      }
    }

    for (final field in ['user_anchors', 'trust_anchors', 'allowed_list']) {
      final value = trust[field];
      if (value is String && !_isValidPEM(value, 'CERTIFICATE')) {
        errors.add(
          '$sectionName.$field must be valid PEM-formatted certificate(s)',
        );
      }
    }
  }

  static void _validateVerifySection(
    Map<String, dynamic> verify,
    List<String> errors,
    List<String> warnings,
  ) {
    const validKeys = {
      'verify_after_reading',
      'verify_after_sign',
      'verify_trust',
      'verify_timestamp_trust',
      'ocsp_fetch',
      'remote_manifest_fetch',
      'skip_ingredient_conflict_resolution',
      'strict_v1_validation',
    };

    for (final key in verify.keys) {
      if (!validKeys.contains(key)) {
        warnings.add("Unknown key in verify: '$key'");
      }
    }

    for (final field in validKeys) {
      final value = verify[field];
      if (value != null && value is! bool) {
        errors.add('verify.$field must be a boolean');
      }
    }

    for (final field in [
      'verify_trust',
      'verify_timestamp_trust',
      'verify_after_sign',
    ]) {
      if (verify[field] == false) {
        warnings.add(
          'verify.$field is set to false. This may result in verification '
          'behavior that is not fully compliant with the C2PA specification.',
        );
      }
    }
  }

  static void _validateBuilderSection(
    Map<String, dynamic> builder,
    List<String> errors,
    List<String> warnings,
  ) {
    const validKeys = {
      'claim_generator_info',
      'certificate_status_fetch',
      'certificate_status_should_override',
      'intent',
      'created_assertion_labels',
      'generate_c2pa_archive',
      'actions',
      'thumbnail',
    };

    for (final key in builder.keys) {
      if (!validKeys.contains(key)) {
        warnings.add("Unknown key in builder: '$key'");
      }
    }

    if (builder['intent'] != null) {
      _validateIntent(builder['intent'], errors);
    }

    if (builder['thumbnail'] is Map<String, dynamic>) {
      _validateThumbnailSection(
        builder['thumbnail'] as Map<String, dynamic>,
        errors,
        warnings,
      );
    }
  }

  static void _validateIntent(dynamic intent, List<String> errors) {
    if (intent is String) {
      if (!_validIntentStrings.contains(intent)) {
        errors.add(
          "builder.intent string must be one of: ${_validIntentStrings.join(', ')}, "
          "got '$intent'",
        );
      }
    } else if (intent is Map<String, dynamic>) {
      final createValue = intent['Create'];
      if (createValue == null) {
        errors.add(
          "builder.intent object must have 'Create' key with source type value",
        );
      } else if (createValue is String &&
          !_validSourceTypes.contains(createValue)) {
        errors.add(
          "builder.intent Create source type must be one of: ${_validSourceTypes.join(', ')}, "
          "got '$createValue'",
        );
      }
    } else {
      errors.add(
        "builder.intent must be a string ('Edit', 'Update') or object "
        '({"Create": "sourceType"})',
      );
    }
  }

  static void _validateThumbnailSection(
    Map<String, dynamic> thumbnail,
    List<String> errors,
    List<String> warnings,
  ) {
    const validKeys = {
      'enabled',
      'ignore_errors',
      'long_edge',
      'format',
      'prefer_smallest_format',
      'quality',
    };

    for (final key in thumbnail.keys) {
      if (!validKeys.contains(key)) {
        warnings.add("Unknown key in builder.thumbnail: '$key'");
      }
    }

    final format = thumbnail['format'];
    if (format is String && !_validThumbnailFormats.contains(format)) {
      errors.add(
        "builder.thumbnail.format must be one of: ${_validThumbnailFormats.join(', ')}, "
        "got '$format'",
      );
    }

    final quality = thumbnail['quality'];
    if (quality is String && !_validThumbnailQualities.contains(quality)) {
      errors.add(
        "builder.thumbnail.quality must be one of: ${_validThumbnailQualities.join(', ')}, "
        "got '$quality'",
      );
    }
  }

  static void _validateSignerSection(
    Map<String, dynamic> signer,
    String sectionName,
    List<String> errors,
    List<String> warnings,
  ) {
    final hasLocal = signer['local'] != null;
    final hasRemote = signer['remote'] != null;

    if (hasLocal && hasRemote) {
      errors.add(
        "$sectionName cannot have both 'local' and 'remote' configurations",
      );
    }

    if (!hasLocal && !hasRemote) {
      errors.add(
        "$sectionName must have either 'local' or 'remote' configuration",
      );
    }

    if (signer['local'] is Map<String, dynamic>) {
      _validateLocalSigner(
        signer['local'] as Map<String, dynamic>,
        '$sectionName.local',
        errors,
        warnings,
      );
    }

    if (signer['remote'] is Map<String, dynamic>) {
      _validateRemoteSigner(
        signer['remote'] as Map<String, dynamic>,
        '$sectionName.remote',
        errors,
        warnings,
      );
    }
  }

  static void _validateLocalSigner(
    Map<String, dynamic> local,
    String path,
    List<String> errors,
    List<String> warnings,
  ) {
    const validKeys = {'alg', 'sign_cert', 'private_key', 'tsa_url'};

    for (final key in local.keys) {
      if (!validKeys.contains(key)) {
        warnings.add("Unknown key in $path: '$key'");
      }
    }

    if (local['alg'] == null) errors.add('$path.alg is required');
    if (local['sign_cert'] == null) errors.add('$path.sign_cert is required');
    if (local['private_key'] == null) {
      errors.add('$path.private_key is required');
    }

    final alg = local['alg'];
    if (alg is String && !_validAlgorithms.contains(alg.toLowerCase())) {
      errors.add(
        "$path.alg must be one of: ${_validAlgorithms.join(', ')}, got '$alg'",
      );
    }

    final cert = local['sign_cert'];
    if (cert is String && !_isValidPEM(cert, 'CERTIFICATE')) {
      errors.add(
        '$path.sign_cert must be valid PEM-formatted certificate(s)',
      );
    }

    final key = local['private_key'];
    if (key is String &&
        !_isValidPEM(key, 'PRIVATE KEY') &&
        !_isValidPEM(key, 'RSA PRIVATE KEY') &&
        !_isValidPEM(key, 'EC PRIVATE KEY')) {
      errors.add('$path.private_key must be valid PEM-formatted private key');
    }

    final tsaUrl = local['tsa_url'];
    if (tsaUrl is String && !_isValidUrl(tsaUrl)) {
      errors.add('$path.tsa_url must be a valid URL');
    }
  }

  static void _validateRemoteSigner(
    Map<String, dynamic> remote,
    String path,
    List<String> errors,
    List<String> warnings,
  ) {
    const validKeys = {'url', 'alg', 'sign_cert', 'tsa_url'};

    for (final key in remote.keys) {
      if (!validKeys.contains(key)) {
        warnings.add("Unknown key in $path: '$key'");
      }
    }

    if (remote['url'] == null) errors.add('$path.url is required');
    if (remote['alg'] == null) errors.add('$path.alg is required');
    if (remote['sign_cert'] == null) errors.add('$path.sign_cert is required');

    final url = remote['url'];
    if (url is String && !_isValidUrl(url)) {
      errors.add('$path.url must be a valid URL');
    }

    final alg = remote['alg'];
    if (alg is String && !_validAlgorithms.contains(alg.toLowerCase())) {
      errors.add(
        "$path.alg must be one of: ${_validAlgorithms.join(', ')}, got '$alg'",
      );
    }

    final cert = remote['sign_cert'];
    if (cert is String && !_isValidPEM(cert, 'CERTIFICATE')) {
      errors.add(
        '$path.sign_cert must be valid PEM-formatted certificate(s)',
      );
    }

    final tsaUrl = remote['tsa_url'];
    if (tsaUrl is String && !_isValidUrl(tsaUrl)) {
      errors.add('$path.tsa_url must be a valid URL');
    }
  }

  static bool _isValidPEM(String pemString, String expectedType) {
    final beginMarker = '-----BEGIN $expectedType-----';
    final endMarker = '-----END $expectedType-----';
    return pemString.contains(beginMarker) && pemString.contains(endMarker);
  }

  static bool _isValidUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }
}
