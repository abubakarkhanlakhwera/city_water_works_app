import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/database/daos/schemes_dao.dart';
import '../../core/database/daos/sets_dao.dart';
import '../../core/models/scheme.dart';
import '../../core/models/set_model.dart';
import '../../core/services/export_service.dart';
import '../../shared/theme/app_colors.dart';

class ExportScreen extends StatefulWidget {
  final int? schemeId;
  final int? setId;

  const ExportScreen({super.key, this.schemeId, this.setId});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  final _schemesDao = SchemesDao();
  final _setsDao = SetsDao();
  final _exportService = ExportService();

  List<Scheme> _schemes = [];
  List<SetModel> _sets = [];
  Scheme? _selectedScheme;
  SetModel? _selectedSet;
  String _exportFormat = 'pdf';
  String _exportScope = 'scheme';

  bool _isLoading = true;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final schemes = await _schemesDao.getAllSchemes();
      setState(() {
        _schemes = schemes;
        _isLoading = false;
      });

      if (widget.schemeId != null) {
        final scheme = schemes.where((s) => s.schemeId == widget.schemeId).firstOrNull;
        if (scheme != null) {
          _selectedScheme = scheme;
          _exportScope = widget.setId != null ? 'set' : 'scheme';
          await _loadSets(scheme.schemeId!);
          if (widget.setId != null) {
            _selectedSet = _sets.where((s) => s.setId == widget.setId).firstOrNull;
          }
          setState(() {});
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSets(int schemeId) async {
    final sets = await _setsDao.getSetsForScheme(schemeId);
    setState(() => _sets = sets);
  }

  Future<void> _export() async {
    if (_selectedScheme == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a scheme')),
      );
      return;
    }
    if (_exportScope == 'set' && _selectedSet == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a set')),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      String? filePath;
      String? suggestedFileName;

      if (_exportFormat == 'pdf') {
        Uint8List pdfBytes;
        String filename;
        if (_exportScope == 'set' && _selectedSet != null) {
          pdfBytes = await _exportService.exportSetToPdf(_selectedSet!.setId!);
          filename = _buildSuggestedFileName(extension: 'pdf');
        } else {
          pdfBytes = await _exportService.exportSchemeToPdf(_selectedScheme!.schemeId!);
          filename = _buildSuggestedFileName(extension: 'pdf');
        }
        suggestedFileName = filename;
        filePath = await _exportService.savePdf(pdfBytes, filename);
      } else if (_exportFormat == 'excel') {
        suggestedFileName = _buildSuggestedFileName(extension: 'xlsx');
        filePath = await _exportService.exportSchemeToExcel(_selectedScheme!.schemeId!);
      } else if (_exportFormat == 'csv') {
        suggestedFileName = _buildSuggestedFileName(extension: 'csv');
        filePath = await _exportService.exportSchemeToCsv(_selectedScheme!.schemeId!);
      }

      if (filePath != null && mounted) {
        _showExportSuccess(filePath, suggestedFileName: suggestedFileName);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportAllMachineryPdf() async {
    setState(() => _isExporting = true);

    try {
      final pdfBytes = await _exportService.exportAllMachineryToPdf();
      final now = DateTime.now();
      final filename =
          'WaterSupplySchemeHistory_AllMachinery_${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.pdf';
      final filePath = await _exportService.savePdfToDownloads(pdfBytes, filename);

      if (mounted) {
        _showExportSuccess(filePath, suggestedFileName: filename);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  String _buildSuggestedFileName({required String extension}) {
    final rawBaseName = _exportScope == 'set' && _selectedSet != null
        ? '${_selectedSet!.setLabel}_Export'
        : '${_selectedScheme?.schemeName ?? 'Export'}_Export';

    final safeBaseName = rawBaseName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    return '$safeBaseName.$extension';
  }

  Future<String> _saveAsAndMoveExport(String generatedPath, [String? preferredFileName]) async {
    final defaultName = preferredFileName?.trim().isNotEmpty == true
        ? preferredFileName!
        : p.basename(generatedPath);
    final pickedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Export File',
      fileName: defaultName,
    );

    if (pickedPath == null || pickedPath.trim().isEmpty) {
      return generatedPath;
    }

    final sourceFile = File(generatedPath);
    final destinationFile = File(pickedPath);

    if (await destinationFile.exists()) {
      await destinationFile.delete();
    }

    await sourceFile.copy(pickedPath);
    return pickedPath;
  }

  void _showExportSuccess(String path, {String? suggestedFileName}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export Complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 48),
            const SizedBox(height: 12),
            Text('File saved to:\n$path', style: const TextStyle(fontSize: 13)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final savedPath = await _saveAsAndMoveExport(path, suggestedFileName);
              if (!mounted) return;
              Navigator.pop(ctx);
              _showExportSuccess(savedPath, suggestedFileName: suggestedFileName);
            },
            icon: const Icon(Icons.save_alt),
            label: const Text('Save As'),
          ),
          TextButton.icon(
            onPressed: () async {
              if (Platform.isWindows) {
                await Process.run('explorer.exe', ['/select,', path]);
              } else {
                final folder = p.dirname(path);
                await Process.run('xdg-open', [folder]);
              }
            },
            icon: const Icon(Icons.folder_open),
            label: const Text('Open Folder'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              Share.shareXFiles([XFile(path)]);
            },
            icon: const Icon(Icons.share),
            label: const Text('Share'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Scope selection
                Text('Export Scope', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'set', label: Text('Single Set'), icon: Icon(Icons.folder)),
                    ButtonSegment(
                        value: 'scheme', label: Text('Entire Scheme'), icon: Icon(Icons.business)),
                  ],
                  selected: {_exportScope},
                  onSelectionChanged: (v) => setState(() {
                    _exportScope = v.first;
                    _selectedSet = null;
                  }),
                ),
                const SizedBox(height: 20),

                // Scheme selector
                DropdownButtonFormField<Scheme>(
                  value: _selectedScheme,
                  decoration: const InputDecoration(
                    labelText: 'Select Scheme',
                    border: OutlineInputBorder(),
                  ),
                  items: _schemes
                      .map((s) => DropdownMenuItem(value: s, child: Text(s.schemeName)))
                      .toList(),
                  onChanged: (s) async {
                    setState(() {
                      _selectedScheme = s;
                      _selectedSet = null;
                      _sets = [];
                    });
                    if (s != null) await _loadSets(s.schemeId!);
                  },
                ),
                const SizedBox(height: 16),

                // Set selector (only if scope is 'set')
                if (_exportScope == 'set') ...[
                  DropdownButtonFormField<SetModel>(
                    value: _selectedSet,
                    decoration: const InputDecoration(
                      labelText: 'Select Set',
                      border: OutlineInputBorder(),
                    ),
                    items: _sets
                        .map((s) => DropdownMenuItem(value: s, child: Text(s.setLabel)))
                        .toList(),
                    onChanged: (s) => setState(() => _selectedSet = s),
                  ),
                  const SizedBox(height: 20),
                ],

                // Format selection
                Text('Export Format', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _buildFormatTile('pdf', 'PDF Document', Icons.picture_as_pdf, Colors.red),
                _buildFormatTile('excel', 'Excel Spreadsheet', Icons.table_chart, Colors.green),
                _buildFormatTile('csv', 'CSV File', Icons.text_snippet, Colors.blue),
                const SizedBox(height: 24),

                // Export button
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _isExporting ? null : _export,
                    icon: _isExporting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.download),
                    label: Text(_isExporting ? 'Exporting...' : 'Export'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _isExporting ? null : _exportAllMachineryPdf,
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Export All Machinery (Single PDF)'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildFormatTile(String value, String label, IconData icon, Color color) {
    return RadioListTile<String>(
      value: value,
      groupValue: _exportFormat,
      onChanged: (v) => setState(() => _exportFormat = v!),
      title: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }
}
