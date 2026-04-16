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

/// Type-safe C2PA settings definition.
///
/// Mirrors the `C2PASettingsDefinition` type exposed by c2pa-ios and
/// c2pa-android v0.0.9. Serializes to the same JSON shape both native SDKs
/// accept (snake_case keys). Use with [C2paSettings.updateFromDefinition]
/// to apply typed settings to a settings handle.
library;

import 'dart:convert';

import 'package:meta/meta.dart';

// =============================================================================
// Top-level settings container
// =============================================================================

/// A type-safe representation of the C2PA settings JSON schema.
///
/// All fields are optional. Only set the values you need — unset fields are
/// omitted from the encoded JSON.
///
/// ## Example
///
/// ```dart
/// final definition = C2paSettingsDefinition(
///   version: 1,
///   signer: SignerSettings.local(LocalSignerSettings(
///     alg: 'es256',
///     signCert: certPem,
///     privateKey: keyPem,
///     tsaUrl: 'http://timestamp.digicert.com',
///   )),
/// );
///
/// final settings = await C2paSettings.create();
/// await settings.updateFromDefinition(definition);
/// ```
@immutable
class C2paSettingsDefinition {
  /// The settings schema version. Currently `1`.
  final int? version;

  /// Trust configuration for manifest verification.
  final TrustSettings? trust;

  /// CAWG-specific trust configuration.
  final TrustSettings? cawgTrust;

  /// Core library settings.
  final CoreSettings? core;

  /// Verification behavior settings.
  final VerifySettings? verify;

  /// Builder configuration.
  final BuilderSettingsDefinition? builder;

  /// Signer configuration (local or remote).
  final SignerSettings? signer;

  /// CAWG X.509 signer configuration.
  final SignerSettings? cawgX509Signer;

  const C2paSettingsDefinition({
    this.version,
    this.trust,
    this.cawgTrust,
    this.core,
    this.verify,
    this.builder,
    this.signer,
    this.cawgX509Signer,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (version != null) map['version'] = version;
    if (trust != null) map['trust'] = trust!.toJson();
    if (cawgTrust != null) map['cawg_trust'] = cawgTrust!.toJson();
    if (core != null) map['core'] = core!.toJson();
    if (verify != null) map['verify'] = verify!.toJson();
    if (builder != null) map['builder'] = builder!.toJson();
    if (signer != null) map['signer'] = signer!.toJson();
    if (cawgX509Signer != null) {
      map['cawg_x509_signer'] = cawgX509Signer!.toJson();
    }
    return map;
  }

  /// Encodes this definition to a compact JSON string.
  String toJsonString() => jsonEncode(toJson());
}

// =============================================================================
// Trust settings
// =============================================================================

/// Trust configuration for manifest verification.
@immutable
class TrustSettings {
  /// Whether to verify against the trust list.
  final bool? verifyTrustList;

  /// User-provided trust anchors in PEM format.
  final String? userAnchors;

  /// Trust anchors in PEM format.
  final String? trustAnchors;

  /// Trust configuration JSON.
  final String? trustConfig;

  /// Allowed list of signing credentials.
  final String? allowedList;

  const TrustSettings({
    this.verifyTrustList,
    this.userAnchors,
    this.trustAnchors,
    this.trustConfig,
    this.allowedList,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (verifyTrustList != null) map['verify_trust_list'] = verifyTrustList;
    if (userAnchors != null) map['user_anchors'] = userAnchors;
    if (trustAnchors != null) map['trust_anchors'] = trustAnchors;
    if (trustConfig != null) map['trust_config'] = trustConfig;
    if (allowedList != null) map['allowed_list'] = allowedList;
    return map;
  }
}

// =============================================================================
// Core settings
// =============================================================================

/// Core library configuration.
@immutable
class CoreSettings {
  /// Chunk size for Merkle tree hashing, in kilobytes.
  final int? merkleTreeChunkSizeInKb;

  /// Maximum number of Merkle tree proofs.
  final int? merkleTreeMaxProofs;

  /// Memory threshold before switching to disk-backed storage, in megabytes.
  final int? backingStoreMemoryThresholdInMb;

  /// Whether to decode identity assertions.
  final bool? decodeIdentityAssertions;

  /// List of allowed network hosts for remote operations.
  final List<String>? allowedNetworkHosts;

  const CoreSettings({
    this.merkleTreeChunkSizeInKb,
    this.merkleTreeMaxProofs,
    this.backingStoreMemoryThresholdInMb,
    this.decodeIdentityAssertions,
    this.allowedNetworkHosts,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (merkleTreeChunkSizeInKb != null) {
      map['merkle_tree_chunk_size_in_kb'] = merkleTreeChunkSizeInKb;
    }
    if (merkleTreeMaxProofs != null) {
      map['merkle_tree_max_proofs'] = merkleTreeMaxProofs;
    }
    if (backingStoreMemoryThresholdInMb != null) {
      map['backing_store_memory_threshold_in_mb'] =
          backingStoreMemoryThresholdInMb;
    }
    if (decodeIdentityAssertions != null) {
      map['decode_identity_assertions'] = decodeIdentityAssertions;
    }
    if (allowedNetworkHosts != null) {
      map['allowed_network_hosts'] = allowedNetworkHosts;
    }
    return map;
  }
}

// =============================================================================
// Verify settings
// =============================================================================

/// Verification behavior configuration.
@immutable
class VerifySettings {
  /// Whether to verify manifests after reading.
  final bool? verifyAfterReading;

  /// Whether to verify manifests after signing.
  final bool? verifyAfterSign;

  /// Whether to verify trust chains.
  final bool? verifyTrust;

  /// Whether to verify timestamp trust.
  final bool? verifyTimestampTrust;

  /// Whether to fetch OCSP responses.
  final bool? ocspFetch;

  /// Whether to fetch remote manifests.
  final bool? remoteManifestFetch;

  /// Whether to skip ingredient conflict resolution.
  final bool? skipIngredientConflictResolution;

  /// Whether to use strict v1 validation rules.
  final bool? strictV1Validation;

  const VerifySettings({
    this.verifyAfterReading,
    this.verifyAfterSign,
    this.verifyTrust,
    this.verifyTimestampTrust,
    this.ocspFetch,
    this.remoteManifestFetch,
    this.skipIngredientConflictResolution,
    this.strictV1Validation,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (verifyAfterReading != null) {
      map['verify_after_reading'] = verifyAfterReading;
    }
    if (verifyAfterSign != null) map['verify_after_sign'] = verifyAfterSign;
    if (verifyTrust != null) map['verify_trust'] = verifyTrust;
    if (verifyTimestampTrust != null) {
      map['verify_timestamp_trust'] = verifyTimestampTrust;
    }
    if (ocspFetch != null) map['ocsp_fetch'] = ocspFetch;
    if (remoteManifestFetch != null) {
      map['remote_manifest_fetch'] = remoteManifestFetch;
    }
    if (skipIngredientConflictResolution != null) {
      map['skip_ingredient_conflict_resolution'] =
          skipIngredientConflictResolution;
    }
    if (strictV1Validation != null) {
      map['strict_v1_validation'] = strictV1Validation;
    }
    return map;
  }
}

// =============================================================================
// Builder settings
// =============================================================================

/// Builder configuration within settings.
@immutable
class BuilderSettingsDefinition {
  /// Vendor prefix for manifest labels.
  final String? vendor;

  /// Claim generator information.
  final ClaimGeneratorInfoSettings? claimGeneratorInfo;

  /// Thumbnail generation settings.
  final ThumbnailSettings? thumbnail;

  /// Actions configuration.
  final ActionsSettings? actions;

  /// Scope for fetching certificate status (OCSP).
  final OcspFetchScope? certificateStatusFetch;

  /// Whether certificate status should override existing status.
  final bool? certificateStatusShouldOverride;

  /// The intent for building manifests.
  final SettingsIntent? intent;

  /// Labels of assertions considered "created" by the builder.
  final List<String>? createdAssertionLabels;

  /// Whether to prefer box hash for large assets.
  final bool? preferBoxHash;

  /// Whether to generate a C2PA archive.
  final bool? generateC2paArchive;

  /// Automatic timestamp assertion settings.
  final TimeStampSettings? autoTimestampAssertion;

  const BuilderSettingsDefinition({
    this.vendor,
    this.claimGeneratorInfo,
    this.thumbnail,
    this.actions,
    this.certificateStatusFetch,
    this.certificateStatusShouldOverride,
    this.intent,
    this.createdAssertionLabels,
    this.preferBoxHash,
    this.generateC2paArchive,
    this.autoTimestampAssertion,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (vendor != null) map['vendor'] = vendor;
    if (claimGeneratorInfo != null) {
      map['claim_generator_info'] = claimGeneratorInfo!.toJson();
    }
    if (thumbnail != null) map['thumbnail'] = thumbnail!.toJson();
    if (actions != null) map['actions'] = actions!.toJson();
    if (certificateStatusFetch != null) {
      map['certificate_status_fetch'] = certificateStatusFetch!.value;
    }
    if (certificateStatusShouldOverride != null) {
      map['certificate_status_should_override'] =
          certificateStatusShouldOverride;
    }
    if (intent != null) map['intent'] = intent!.toJson();
    if (createdAssertionLabels != null) {
      map['created_assertion_labels'] = createdAssertionLabels;
    }
    if (preferBoxHash != null) map['prefer_box_hash'] = preferBoxHash;
    if (generateC2paArchive != null) {
      map['generate_c2pa_archive'] = generateC2paArchive;
    }
    if (autoTimestampAssertion != null) {
      map['auto_timestamp_assertion'] = autoTimestampAssertion!.toJson();
    }
    return map;
  }
}

// =============================================================================
// Claim generator info settings
// =============================================================================

/// Claim generator information for settings.
@immutable
class ClaimGeneratorInfoSettings {
  /// The name of the claim generator.
  final String name;

  /// The version of the claim generator.
  final String? version;

  /// The operating system the claim generator runs on.
  final String? operatingSystem;

  const ClaimGeneratorInfoSettings({
    required this.name,
    this.version,
    this.operatingSystem,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'name': name};
    if (version != null) map['version'] = version;
    if (operatingSystem != null) map['operating_system'] = operatingSystem;
    return map;
  }
}

// =============================================================================
// Thumbnail settings
// =============================================================================

/// Thumbnail generation configuration.
@immutable
class ThumbnailSettings {
  /// Whether thumbnail generation is enabled.
  final bool? enabled;

  /// Whether to ignore errors during thumbnail generation.
  final bool? ignoreErrors;

  /// The long edge dimension in pixels.
  final int? longEdge;

  /// The image format for generated thumbnails.
  final ThumbnailFormat? format;

  /// Whether to prefer the smallest format.
  final bool? preferSmallestFormat;

  /// The quality level for generated thumbnails.
  final ThumbnailQuality? quality;

  const ThumbnailSettings({
    this.enabled,
    this.ignoreErrors,
    this.longEdge,
    this.format,
    this.preferSmallestFormat,
    this.quality,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (enabled != null) map['enabled'] = enabled;
    if (ignoreErrors != null) map['ignore_errors'] = ignoreErrors;
    if (longEdge != null) map['long_edge'] = longEdge;
    if (format != null) map['format'] = format!.value;
    if (preferSmallestFormat != null) {
      map['prefer_smallest_format'] = preferSmallestFormat;
    }
    if (quality != null) map['quality'] = quality!.value;
    return map;
  }
}

/// Thumbnail image format.
enum ThumbnailFormat {
  png('png'),
  jpeg('jpeg'),
  gif('gif'),
  webp('webp'),
  tiff('tiff');

  const ThumbnailFormat(this.value);
  final String value;
}

/// Thumbnail quality level.
enum ThumbnailQuality {
  low('low'),
  medium('medium'),
  high('high');

  const ThumbnailQuality(this.value);
  final String value;
}

// =============================================================================
// Actions settings
// =============================================================================

/// Actions configuration for the builder.
@immutable
class ActionsSettings {
  /// Whether all actions are included.
  final bool? allActionsIncluded;

  /// Action templates.
  final List<ActionTemplateSettings>? templates;

  /// Auto-created action settings.
  final AutoActionSettings? autoCreatedAction;

  /// Auto-opened action settings.
  final AutoActionSettings? autoOpenedAction;

  /// Auto-placed action settings.
  final AutoActionSettings? autoPlacedAction;

  const ActionsSettings({
    this.allActionsIncluded,
    this.templates,
    this.autoCreatedAction,
    this.autoOpenedAction,
    this.autoPlacedAction,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (allActionsIncluded != null) {
      map['all_actions_included'] = allActionsIncluded;
    }
    if (templates != null) {
      map['templates'] = templates!.map((t) => t.toJson()).toList();
    }
    if (autoCreatedAction != null) {
      map['auto_created_action'] = autoCreatedAction!.toJson();
    }
    if (autoOpenedAction != null) {
      map['auto_opened_action'] = autoOpenedAction!.toJson();
    }
    if (autoPlacedAction != null) {
      map['auto_placed_action'] = autoPlacedAction!.toJson();
    }
    return map;
  }
}

/// A template for an action assertion.
@immutable
class ActionTemplateSettings {
  /// The action identifier.
  final String action;

  /// Software agent information for this action.
  final ClaimGeneratorInfoSettings? softwareAgent;

  /// Index of the software agent in the claim generator info list.
  final int? softwareAgentIndex;

  /// The digital source type URL for this action.
  final String? sourceType;

  /// A human-readable description of the action.
  final String? description;

  const ActionTemplateSettings({
    required this.action,
    this.softwareAgent,
    this.softwareAgentIndex,
    this.sourceType,
    this.description,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'action': action};
    if (softwareAgent != null) {
      map['software_agent'] = softwareAgent!.toJson();
    }
    if (softwareAgentIndex != null) {
      map['software_agent_index'] = softwareAgentIndex;
    }
    if (sourceType != null) map['source_type'] = sourceType;
    if (description != null) map['description'] = description;
    return map;
  }
}

/// Settings for automatic action generation.
@immutable
class AutoActionSettings {
  /// Whether the automatic action is enabled.
  final bool enabled;

  /// The digital source type URL for the automatic action.
  final String? sourceType;

  const AutoActionSettings({required this.enabled, this.sourceType});

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'enabled': enabled};
    if (sourceType != null) map['source_type'] = sourceType;
    return map;
  }
}

// =============================================================================
// Timestamp settings
// =============================================================================

/// Timestamp assertion configuration.
@immutable
class TimeStampSettings {
  /// Whether automatic timestamping is enabled.
  final bool? enabled;

  /// Whether to skip timestamping if a timestamp already exists.
  final bool? skipExisting;

  /// The scope for fetching timestamps.
  final TimeStampFetchScope? fetchScope;

  const TimeStampSettings({
    this.enabled,
    this.skipExisting,
    this.fetchScope,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (enabled != null) map['enabled'] = enabled;
    if (skipExisting != null) map['skip_existing'] = skipExisting;
    if (fetchScope != null) map['fetch_scope'] = fetchScope!.value;
    return map;
  }
}

/// Scope for fetching timestamps.
enum TimeStampFetchScope {
  parent('parent'),
  all('all');

  const TimeStampFetchScope(this.value);
  final String value;
}

/// Scope for fetching OCSP certificate status.
enum OcspFetchScope {
  all('all'),
  active('active');

  const OcspFetchScope(this.value);
  final String value;
}

// =============================================================================
// Settings intent (sealed)
// =============================================================================

/// The intent for building manifests, specified in settings.
///
/// Encodes as:
/// - `"Edit"` (string) for [SettingsIntent.edit]
/// - `"Update"` (string) for [SettingsIntent.update]
/// - `{"Create": {"digital_source_type": "<url>"}}` for [SettingsIntent.create]
sealed class SettingsIntent {
  const SettingsIntent();

  /// A new digital creation with the specified digital source type URI.
  const factory SettingsIntent.create(String digitalSourceType) =
      _SettingsIntentCreate;

  /// An edit of a pre-existing parent asset.
  static const SettingsIntent edit = _SettingsIntentEdit();

  /// A restricted version of edit for non-editorial changes.
  static const SettingsIntent update = _SettingsIntentUpdate();

  /// Returns the JSON value for this intent — may be a String ("Edit"/"Update")
  /// or a Map (`{"Create": {...}}`). The caller should accept `dynamic`.
  dynamic toJson();
}

class _SettingsIntentCreate extends SettingsIntent {
  final String digitalSourceType;
  const _SettingsIntentCreate(this.digitalSourceType);

  @override
  Map<String, dynamic> toJson() => {
    'Create': {'digital_source_type': digitalSourceType},
  };
}

class _SettingsIntentEdit extends SettingsIntent {
  const _SettingsIntentEdit();

  @override
  String toJson() => 'Edit';
}

class _SettingsIntentUpdate extends SettingsIntent {
  const _SettingsIntentUpdate();

  @override
  String toJson() => 'Update';
}

// =============================================================================
// Signer settings (sealed)
// =============================================================================

/// Signer configuration, either local or remote.
///
/// Encodes as `{"local": {...}}` or `{"remote": {...}}` depending on variant.
sealed class SignerSettings {
  const SignerSettings();

  /// A local signer with credentials stored on-device.
  const factory SignerSettings.local(LocalSignerSettings settings) =
      _SignerSettingsLocal;

  /// A remote signer that delegates to a signing service.
  const factory SignerSettings.remote(RemoteSignerSettings settings) =
      _SignerSettingsRemote;

  Map<String, dynamic> toJson();
}

class _SignerSettingsLocal extends SignerSettings {
  final LocalSignerSettings settings;
  const _SignerSettingsLocal(this.settings);

  @override
  Map<String, dynamic> toJson() => {'local': settings.toJson()};
}

class _SignerSettingsRemote extends SignerSettings {
  final RemoteSignerSettings settings;
  const _SignerSettingsRemote(this.settings);

  @override
  Map<String, dynamic> toJson() => {'remote': settings.toJson()};
}

/// Local signer credentials and configuration.
@immutable
class LocalSignerSettings {
  /// The signing algorithm identifier (e.g., `"es256"`).
  final String alg;

  /// The certificate chain in PEM format.
  final String signCert;

  /// The private key in PEM format.
  final String privateKey;

  /// Optional URL of a timestamp authority.
  final String? tsaUrl;

  /// Assertion labels referenced by the signer.
  final List<String>? referencedAssertions;

  /// Signer roles.
  final List<String>? roles;

  const LocalSignerSettings({
    required this.alg,
    required this.signCert,
    required this.privateKey,
    this.tsaUrl,
    this.referencedAssertions,
    this.roles,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'alg': alg,
      'sign_cert': signCert,
      'private_key': privateKey,
    };
    if (tsaUrl != null) map['tsa_url'] = tsaUrl;
    if (referencedAssertions != null) {
      map['referenced_assertions'] = referencedAssertions;
    }
    if (roles != null) map['roles'] = roles;
    return map;
  }
}

/// Remote signer configuration.
@immutable
class RemoteSignerSettings {
  /// The URL of the remote signing service.
  final String url;

  /// The signing algorithm identifier.
  final String alg;

  /// The certificate chain in PEM format.
  final String signCert;

  /// Optional URL of a timestamp authority.
  final String? tsaUrl;

  /// Assertion labels referenced by the signer.
  final List<String>? referencedAssertions;

  /// Signer roles.
  final List<String>? roles;

  const RemoteSignerSettings({
    required this.url,
    required this.alg,
    required this.signCert,
    this.tsaUrl,
    this.referencedAssertions,
    this.roles,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'url': url,
      'alg': alg,
      'sign_cert': signCert,
    };
    if (tsaUrl != null) map['tsa_url'] = tsaUrl;
    if (referencedAssertions != null) {
      map['referenced_assertions'] = referencedAssertions;
    }
    if (roles != null) map['roles'] = roles;
    return map;
  }
}
