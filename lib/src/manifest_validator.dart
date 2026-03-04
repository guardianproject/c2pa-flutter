import 'dart:convert';

import 'manifest_types.dart';

/// Result of a validation operation
class ValidationResult {
  final List<String> errors;
  final List<String> warnings;

  const ValidationResult({this.errors = const [], this.warnings = const []});

  bool get hasErrors => errors.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;
  bool get isValid => !hasErrors;
}

/// Validates C2PA manifests for spec compliance.
///
/// Checks for compliance with C2PA 2.3 specification and CAWG requirements.
class ManifestValidator {
  /// Assertion labels that are deprecated in C2PA 2.x.
  static const Set<String> deprecatedAssertionLabels = {
    'stds.exif',
    'stds.iptc.photo-metadata',
    'stds.schema-org.CreativeWork',
    'c2pa.endorsement',
  };

  static const Map<String, String> _deprecatedReplacements = {
    'stds.exif':
        'Consider using c2pa.metadata or embedding EXIF in the asset directly.',
    'stds.iptc.photo-metadata': 'Consider using c2pa.metadata instead.',
    'stds.schema-org.CreativeWork': 'Consider using c2pa.metadata instead.',
    'c2pa.endorsement':
        'Endorsement assertions are no longer supported in C2PA 2.x.',
  };

  /// Recommended claim_version for C2PA 2.x manifests.
  static const int recommendedClaimVersion = 2;

  /// Validates a [ManifestDefinition] for C2PA 2.3 spec compliance.
  static ValidationResult validate(ManifestDefinition manifest) {
    final errors = <String>[];
    final warnings = <String>[];

    if (manifest.claimVersion != recommendedClaimVersion) {
      warnings.add(
        'claim_version is ${manifest.claimVersion}, but C2PA 2.x recommends '
        'version $recommendedClaimVersion. Version 1 claims use legacy '
        'assertion formats and do not support created/gathered assertion '
        'separation.',
      );
    }

    if (manifest.title.isEmpty) {
      errors.add('Manifest title is required');
    }

    if (manifest.claimGeneratorInfo.isEmpty) {
      errors.add('At least one claim_generator_info entry is required');
    }

    _checkDeprecatedAssertions(manifest.assertions, warnings);
    _checkDeprecatedAssertions(manifest.gatheredAssertions, warnings);

    for (final assertion in manifest.assertions) {
      if (assertion is CawgIdentityAssertion) {
        warnings.add(
          'CAWG identity assertion found in created assertions. '
          'Per CAWG spec, identity assertions MUST be in gathered_assertions '
          'rather than created assertions. Use ManifestDefinition.withCawgIdentity() '
          'or move to gatheredAssertions.',
        );
      }
      _validateAssertionLabel(assertion, warnings);
    }

    for (final assertion in manifest.gatheredAssertions) {
      _validateAssertionLabel(assertion, warnings);
    }

    for (final ingredient in manifest.ingredients) {
      if (ingredient.relationship == null) {
        warnings.add(
          "Ingredient '${ingredient.title ?? 'unnamed'}' has no relationship "
          'specified. Consider using parentOf, componentOf, or inputTo.',
        );
      }
    }

    return ValidationResult(errors: errors, warnings: warnings);
  }

  /// Validates a raw JSON manifest string.
  static ValidationResult validateJson(String manifestJson) {
    try {
      final map = jsonDecode(manifestJson) as Map<String, dynamic>;
      final manifest = ManifestDefinition.fromMap(map);
      return validate(manifest);
    } catch (e) {
      return ValidationResult(
        errors: ['Failed to parse manifest JSON: $e'],
      );
    }
  }

  /// Validates that gathered assertions are appropriate types.
  static ValidationResult validateGatheredAssertions(
    ManifestDefinition manifest,
  ) {
    final warnings = <String>[];

    for (final assertion in manifest.gatheredAssertions) {
      if (assertion is ActionsAssertion) {
        warnings.add(
          'Actions assertion found in gathered_assertions. '
          'Actions are typically created by the signer and should be in '
          'created assertions (assertions field) unless they come from '
          'a third-party workflow component.',
        );
      }
    }

    return ValidationResult(warnings: warnings);
  }

  /// Checks if CAWG identity assertions are properly placed in gathered
  /// assertions (not in created assertions).
  static bool isCawgIdentityProperlyPlaced(ManifestDefinition manifest) {
    return !manifest.assertions.any((a) => a is CawgIdentityAssertion);
  }

  /// Returns a list of CAWG-specific compliance issues.
  static List<String> validateCawgCompliance(ManifestDefinition manifest) {
    final issues = <String>[];

    for (final assertion in manifest.assertions) {
      if (assertion is CawgIdentityAssertion) {
        issues.add(
          'CAWG identity assertion in created_assertions violates CAWG spec. '
          'CAWG identity assertions MUST be gathered assertions.',
        );
      }
    }

    return issues;
  }

  static void _checkDeprecatedAssertions(
    List<AssertionDefinition> assertions,
    List<String> warnings,
  ) {
    for (final assertion in assertions) {
      final label = assertion.label;
      if (deprecatedAssertionLabels.contains(label)) {
        final replacement = _deprecatedReplacements[label] ??
            'Check the C2PA 2.3 specification for current alternatives.';
        warnings.add(
          "Assertion '$label' is deprecated in C2PA 2.x. $replacement",
        );
      }
    }
  }

  static void _validateAssertionLabel(
    AssertionDefinition assertion,
    List<String> warnings,
  ) {
    if (assertion is CustomAssertion) {
      final label = assertion.label;
      if (!label.contains('.') && !label.contains(':')) {
        warnings.add(
          "Custom assertion label '$label' should use namespaced format "
          "(e.g., 'com.example.custom' or vendor prefix).",
        );
      }
      const commonTypos = {
        'c2pa.action': 'c2pa.actions',
        'stds.iptc': 'stds.iptc.photo-metadata',
        'cawg.training': 'cawg.ai_training_and_data_mining',
      };
      final correct = commonTypos[label];
      if (correct != null) {
        warnings.add("Label '$label' may be a typo. Did you mean '$correct'?");
      }
    }
  }
}
