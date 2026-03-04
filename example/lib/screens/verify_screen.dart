import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:c2pa_flutter/c2pa.dart';
import '../services/c2pa_manager.dart';

class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  final C2paManager _manager = C2paManager();
  ManifestStoreInfo? _storeInfo;
  String? _rawJson;
  bool _isLoading = false;
  String? _error;
  String? _imagePath;

  Future<void> _pickAndVerify() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      await _verifyFile(image.path);
    }
  }

  Future<void> _verifySavedImages() async {
    final directory = await getApplicationDocumentsDirectory();
    final files = directory.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.jpg') || f.path.endsWith('.jpeg'),
    ).toList();

    if (files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No signed images found')),
        );
      }
      return;
    }

    await _verifyFile(files.last.path);
  }

  Future<void> _verifyFile(String path) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _storeInfo = null;
      _rawJson = null;
      _imagePath = path;
    });

    try {
      // Try enhanced reader for structured data
      final storeInfo = await _manager.readManifestEnhanced(path);
      if (storeInfo != null && storeInfo.active != null) {
        setState(() {
          _storeInfo = storeInfo;
          _isLoading = false;
        });
        return;
      }

      // Fall back to raw JSON reader
      final rawJson = await _manager.readManifest(path);
      if (rawJson != null) {
        // Try parsing raw JSON into structured data
        try {
          final parsed = ManifestStoreInfo.fromJson(rawJson);
          if (parsed.active != null) {
            setState(() {
              _storeInfo = parsed;
              _isLoading = false;
            });
            return;
          }
        } catch (_) {
          // Parsing failed, show raw JSON
        }
      }

      setState(() {
        _rawJson = rawJson;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Image'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickAndVerify,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Pick Image'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _verifySavedImages,
                    icon: const Icon(Icons.history),
                    label: const Text('Last Signed'),
                  ),
                ),
              ],
            ),
          ),
          if (_isLoading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_storeInfo != null)
            Expanded(child: _buildStructuredView())
          else if (_rawJson != null)
            Expanded(child: _buildRawJsonView())
          else
            const Expanded(
              child: Center(
                child: Text('Select an image to verify its C2PA manifest'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStructuredView() {
    final store = _storeInfo!;
    final active = store.active;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_imagePath != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(_imagePath!),
              height: 200,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Validation status card
        _buildValidationStatusCard(store),
        const SizedBox(height: 12),

        // Active manifest card
        if (active != null) ...[
          _buildManifestCard(active),
          const SizedBox(height: 12),
        ],

        // Signature info
        if (active?.signature != null) ...[
          _buildSignatureCard(active!.signature!),
          const SizedBox(height: 12),
        ],

        // Assertions
        if (active != null && active.assertions.isNotEmpty) ...[
          _buildAssertionsCard(active.assertions),
          const SizedBox(height: 12),
        ],

        // Ingredients
        if (active != null && active.ingredients.isNotEmpty) ...[
          _buildIngredientsCard(active.ingredients),
          const SizedBox(height: 12),
        ],

        // Validation errors
        if (store.validationErrors.isNotEmpty) ...[
          _buildValidationErrorsCard(store.validationErrors),
          const SizedBox(height: 12),
        ],

        // Manifests count
        if (store.manifests.length > 1)
          Card(
            child: ListTile(
              leading: const Icon(Icons.layers),
              title: const Text('Manifest Store'),
              subtitle: Text('${store.manifests.length} manifests in chain'),
            ),
          ),
      ],
    );
  }

  Widget _buildValidationStatusCard(ManifestStoreInfo store) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (store.validationStatus) {
      case ValidationStatus.valid:
        statusColor = Colors.green;
        statusIcon = Icons.verified;
        statusText = 'Valid C2PA Manifest';
      case ValidationStatus.invalid:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        statusText = 'Validation Issues Found';
      case ValidationStatus.unknown:
        statusColor = Colors.orange;
        statusIcon = Icons.help;
        statusText = 'C2PA Manifest Found';
    }

    return Card(
      color: statusColor.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(statusIcon, color: statusColor, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                  if (store.activeManifest != null)
                    Text(
                      'Active: ${store.activeManifest}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManifestCard(ManifestInfo manifest) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Manifest Details',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            if (manifest.title != null)
              _buildInfoRow('Title', manifest.title!),
            if (manifest.format != null)
              _buildInfoRow('Format', manifest.format!),
            if (manifest.claimGenerator != null)
              _buildInfoRow('Claim Generator', manifest.claimGenerator!),
            if (manifest.instanceId != null)
              _buildInfoRow('Instance ID', manifest.instanceId!),
          ],
        ),
      ),
    );
  }

  Widget _buildSignatureCard(SignatureInfo sig) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock, size: 20, color: Colors.blue[700]),
                const SizedBox(width: 8),
                const Text(
                  'Signature',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            if (sig.issuer != null) _buildInfoRow('Issuer', sig.issuer!),
            if (sig.signedAt != null)
              _buildInfoRow('Signed At', sig.signedAt!.toIso8601String()),
            if (sig.expiresAt != null)
              _buildInfoRow('Expires', sig.expiresAt!.toIso8601String()),
            if (sig.algorithm != null)
              _buildInfoRow('Algorithm', sig.algorithm!.name),
            if (sig.serialNumber != null)
              _buildInfoRow('Serial Number', sig.serialNumber!),
          ],
        ),
      ),
    );
  }

  Widget _buildAssertionsCard(List<AssertionInfo> assertions) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Assertions (${assertions.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            ...assertions.map((a) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  a.label,
                  style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
                ),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      const JsonEncoder.withIndent('  ').convert(a.data),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildIngredientsCard(List<IngredientInfo> ingredients) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ingredients (${ingredients.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            ...ingredients.map((i) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.input, size: 20),
              title: Text(i.title ?? 'Unnamed'),
              subtitle: Text(
                'Relationship: ${i.relationship.toJson()}'
                '${i.format != null ? ' | Format: ${i.format}' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: _buildValidationBadge(i.validationStatus),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildValidationErrorsCard(List<ValidationError> errors) {
    return Card(
      color: Colors.red.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning, size: 20, color: Colors.red[700]),
                const SizedBox(width: 8),
                Text(
                  'Validation Issues (${errors.length})',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red[700],
                  ),
                ),
              ],
            ),
            const Divider(),
            ...errors.map((e) {
              final code = ValidationStatusCode.fromCode(e.code);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      code != null ? _iconForStatusCode(code) : Icons.error_outline,
                      size: 16,
                      color: code != null ? _colorForStatusCode(code) : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.code,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            e.message,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildValidationBadge(ValidationStatus status) {
    switch (status) {
      case ValidationStatus.valid:
        return Icon(Icons.check_circle, color: Colors.green[600], size: 20);
      case ValidationStatus.invalid:
        return Icon(Icons.error, color: Colors.red[600], size: 20);
      case ValidationStatus.unknown:
        return Icon(Icons.help_outline, color: Colors.grey[400], size: 20);
    }
  }

  Color _colorForStatusCode(ValidationStatusCode code) {
    final name = code.name;
    if (name.contains('Validated') || name.contains('Match')) {
      return Colors.green;
    }
    if (name.contains('Mismatch') || name.contains('Missing') || name.contains('Revoked')) {
      return Colors.red;
    }
    return Colors.orange;
  }

  IconData _iconForStatusCode(ValidationStatusCode code) {
    final name = code.name;
    if (name.contains('Validated') || name.contains('Match')) {
      return Icons.check_circle;
    }
    if (name.contains('Mismatch') || name.contains('Missing') || name.contains('Revoked')) {
      return Icons.error;
    }
    return Icons.info;
  }

  Widget _buildRawJsonView() {
    Map<String, dynamic>? manifest;
    try {
      manifest = jsonDecode(_rawJson!);
    } catch (e) {
      return Center(child: Text('Error parsing manifest: $e'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_imagePath != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(_imagePath!),
              height: 200,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 16),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.verified, color: Colors.green),
                    SizedBox(width: 8),
                    Text(
                      'C2PA Manifest Found',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Divider(),
                _buildInfoRow('Active Manifest', manifest?['active_manifest'] ?? 'N/A'),
                if (manifest?['manifests'] != null)
                  _buildInfoRow(
                    'Manifests Count',
                    (manifest!['manifests'] as Map).length.toString(),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          title: const Text('Raw Manifest JSON'),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(manifest),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}
