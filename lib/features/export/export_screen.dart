import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/database/daos/schemes_dao.dart';
import '../../core/database/daos/sets_dao.dart';
import '../../core/database/daos/machinery_dao.dart';
import '../../core/database/daos/miscellaneous_dao.dart';
import '../../core/models/machinery.dart';
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
  final _machineryDao = MachineryDao();
  final _miscDao = MiscellaneousDao();
  final _exportService = ExportService();

  List<Scheme> _schemes = [];
  List<SetModel> _sets = [];
  List<Machinery> _machineryForSet = [];
  Scheme? _selectedScheme;
  SetModel? _selectedSet;
  Machinery? _selectedMachinery;
  List<Map<String, String>> _miscRecords = [];
  String _miscExportMode = 'complete';
  String? _selectedMiscRecordId;
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
            if (_selectedSet != null) {
              await _loadMachinery(_selectedSet!.setId!);
            }
          }
          setState(() {});
        }
      }

      await _loadMiscRecords();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMiscRecords() async {
    final recordsRaw = await _miscDao.getAllRecords();
    final records = recordsRaw
        .map((map) => {
              'id': (map['id'] ?? '').toString(),
              'title': (map['title'] ?? 'Untitled').toString(),
            })
        .where((entry) => (entry['id'] ?? '').isNotEmpty)
        .toList();

    if (!mounted) return;
    setState(() {
      _miscRecords = records;
      if (_selectedMiscRecordId != null && !_miscRecords.any((r) => r['id'] == _selectedMiscRecordId)) {
        _selectedMiscRecordId = null;
      }
    });
  }

  Future<void> _loadSets(int schemeId) async {
    final sets = await _setsDao.getSetsForScheme(schemeId);
    if (!mounted) return;
    setState(() {
      _sets = sets;
      _machineryForSet = [];
      _selectedMachinery = null;
    });
  }

  Future<void> _loadMachinery(int setId) async {
    final machinery = await _machineryDao.getMachineryForSet(setId);
    if (!mounted) return;
    setState(() {
      _machineryForSet = machinery;
      _selectedMachinery = null;
    });
  }

  Future<void> _export() async {
    if (_exportScope != 'miscellaneous' && _selectedScheme == null) {
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
    if (_exportScope == 'miscellaneous' && _miscExportMode == 'single' && _selectedMiscRecordId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a miscellaneous item')),
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
        if (_exportScope == 'miscellaneous') {
          pdfBytes = await _exportService.exportMiscellaneousToPdf(
            recordId: _miscExportMode == 'single' ? _selectedMiscRecordId : null,
          );
          filename = _buildSuggestedFileName(extension: 'pdf');
        } else if (_exportScope == 'set' && _selectedSet != null && _selectedMachinery != null) {
          pdfBytes = await _exportService.exportSingleMachineryToPdf(
            _selectedSet!.setId!,
            _selectedMachinery!.machineryId!,
          );
          filename = _buildSuggestedFileName(extension: 'pdf');
        } else if (_exportScope == 'set' && _selectedSet != null) {
          pdfBytes = await _exportService.exportSetToPdf(_selectedSet!.setId!);
          filename = _buildSuggestedFileName(extension: 'pdf');
        } else {
          pdfBytes = await _exportService.exportSchemeToPdf(_selectedScheme!.schemeId!);
          filename = _buildSuggestedFileName(extension: 'pdf');
        }
        suggestedFileName = filename;
        filePath = await _savePdfWithPathChoice(pdfBytes, filename);
      } else if (_exportFormat == 'excel') {
        suggestedFileName = _buildSuggestedFileName(extension: 'xlsx');
        if (_exportScope == 'miscellaneous') {
          filePath = await _exportService.exportMiscellaneousToExcel(
            recordId: _miscExportMode == 'single' ? _selectedMiscRecordId : null,
          );
        } else if (_exportScope == 'set' && _selectedSet != null) {
          if (_selectedMachinery != null) {
            filePath = await _exportService.exportSingleMachineryToExcel(
              _selectedSet!.setId!,
              _selectedMachinery!.machineryId!,
            );
          } else {
            filePath = await _exportService.exportSetToExcel(_selectedSet!.setId!);
          }
        } else {
          filePath = await _exportService.exportSchemeToExcel(_selectedScheme!.schemeId!);
        }
      } else if (_exportFormat == 'csv') {
        suggestedFileName = _buildSuggestedFileName(extension: 'csv');
        if (_exportScope == 'miscellaneous') {
          filePath = await _exportService.exportMiscellaneousToCsv(
            recordId: _miscExportMode == 'single' ? _selectedMiscRecordId : null,
          );
        } else if (_exportScope == 'set' && _selectedSet != null) {
          if (_selectedMachinery != null) {
            filePath = await _exportService.exportSingleMachineryToCsv(
              _selectedSet!.setId!,
              _selectedMachinery!.machineryId!,
            );
          } else {
            filePath = await _exportService.exportSetToCsv(_selectedSet!.setId!);
          }
        } else {
          filePath = await _exportService.exportSchemeToCsv(_selectedScheme!.schemeId!);
        }
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
      final filePath = await _savePdfWithPathChoice(pdfBytes, filename);

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
    if (_exportScope == 'miscellaneous') {
      if (_miscExportMode == 'single' && _selectedMiscRecordId != null) {
        final item = _miscRecords.where((r) => r['id'] == _selectedMiscRecordId).firstOrNull;
        final title = (item?['title'] ?? 'Miscellaneous').replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
        return '${title}_Miscellaneous_Export.$extension';
      }
      return 'Miscellaneous_Export.$extension';
    }

    final machineryTypeForName = (_selectedMachinery?.machineryType.trim().isNotEmpty ?? false)
        ? _selectedMachinery!.machineryType.trim()
        : 'Machinery';

    final rawBaseName = _exportScope == 'set' && _selectedSet != null
      ? _selectedMachinery != null
        ? '${_selectedSet!.setLabel}_${machineryTypeForName}_Export'
        : '${_selectedSet!.setLabel}_Export'
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

  Future<String> _savePdfWithPathChoice(Uint8List bytes, String filename) async {
    final pickedPath = await _pickExportPath(filename, const ['pdf']);
    if (pickedPath == null || pickedPath.trim().isEmpty) {
      return _exportService.savePdf(bytes, filename);
    }

    final destinationFile = File(pickedPath);
    if (!await destinationFile.parent.exists()) {
      await destinationFile.parent.create(recursive: true);
    }
    if (await destinationFile.exists()) {
      await destinationFile.delete();
    }

    await destinationFile.writeAsBytes(bytes);
    return destinationFile.path;
  }

  Future<String?> _pickExportPath(String defaultName, List<String> extensions) async {
    String? pickedPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Choose where to save export',
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: extensions,
    );

    if (pickedPath == null || pickedPath.trim().isEmpty) {
      final directory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select folder for export file',
      );
      if (directory != null && directory.trim().isNotEmpty) {
        pickedPath = p.join(directory, defaultName);
      }
    }

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
              if (!mounted || !ctx.mounted) return;
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
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              Share.shareXFiles([XFile(path)], text: 'City Water Works — Export File');
            },
            icon: const Icon(Icons.chat),
            label: const Text('WhatsApp Share'),
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
    final isCompact = MediaQuery.of(context).size.width < 600;
    return Scaffold(
      appBar: AppBar(title: const Text('Export')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.all(isCompact ? 12 : 16),
              children: [
                // Scope selection
                Text('Export Scope', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'set', label: Text('Single Set'), icon: Icon(Icons.folder)),
                    ButtonSegment(
                        value: 'scheme', label: Text('Entire Scheme'), icon: Icon(Icons.business)),
                    ButtonSegment(
                        value: 'miscellaneous',
                        label: Text('Miscellaneous'),
                        icon: Icon(Icons.category_outlined)),
                  ],
                  selected: {_exportScope},
                  onSelectionChanged: (v) => setState(() {
                    _exportScope = v.first;
                    _selectedSet = null;
                    _selectedMachinery = null;
                    _machineryForSet = [];
                    if (_exportScope == 'miscellaneous') {
                      _miscExportMode = 'complete';
                      _selectedMiscRecordId = null;
                    }
                  }),
                ),
                const SizedBox(height: 20),

                // Scheme selector
                if (_exportScope != 'miscellaneous') ...[
                  DropdownButtonFormField<Scheme>(
                    initialValue: _selectedScheme,
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
                        _selectedMachinery = null;
                        _machineryForSet = [];
                        _sets = [];
                      });
                      if (s != null) await _loadSets(s.schemeId!);
                    },
                  ),
                  const SizedBox(height: 16),
                ] else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text('Miscellaneous Mode', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'single', label: Text('Single Item'), icon: Icon(Icons.filter_1)),
                          ButtonSegment(value: 'complete', label: Text('Complete'), icon: Icon(Icons.list_alt)),
                        ],
                        selected: {_miscExportMode},
                        onSelectionChanged: (v) => setState(() {
                          _miscExportMode = v.first;
                          if (_miscExportMode == 'complete') {
                            _selectedMiscRecordId = null;
                          }
                        }),
                      ),
                      const SizedBox(height: 12),
                      if (_miscExportMode == 'single')
                        DropdownButtonFormField<String>(
                          initialValue: _selectedMiscRecordId,
                          decoration: const InputDecoration(
                            labelText: 'Select Miscellaneous Item',
                            border: OutlineInputBorder(),
                          ),
                          items: _miscRecords
                              .map((r) => DropdownMenuItem(
                                    value: r['id'],
                                    child: Text(r['title'] ?? 'Untitled'),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedMiscRecordId = v),
                        )
                      else
                        const ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.info_outline),
                          title: Text('Complete Miscellaneous Export'),
                          subtitle: Text('Exports all miscellaneous items and expenditures.'),
                        ),
                      const SizedBox(height: 16),
                    ],
                  ),

                // Set selector (only if scope is 'set')
                if (_exportScope == 'set') ...[
                  DropdownButtonFormField<SetModel>(
                    initialValue: _selectedSet,
                    decoration: const InputDecoration(
                      labelText: 'Select Set',
                      border: OutlineInputBorder(),
                    ),
                    items: _sets
                        .map((s) => DropdownMenuItem(value: s, child: Text(s.setLabel)))
                        .toList(),
                    onChanged: (s) async {
                      setState(() {
                        _selectedSet = s;
                        _selectedMachinery = null;
                        _machineryForSet = [];
                      });
                      if (s != null) {
                        await _loadMachinery(s.setId!);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<Machinery?>(
                    initialValue: _selectedMachinery,
                    decoration: const InputDecoration(
                      labelText: 'Select Machinery',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<Machinery?>(
                        value: null,
                        child: Text('All Machinery in this Set'),
                      ),
                      ..._machineryForSet.map(
                        (m) => DropdownMenuItem<Machinery?>(
                          value: m,
                          child: Text(m.displayLabel),
                        ),
                      ),
                    ],
                    onChanged: (m) => setState(() => _selectedMachinery = m),
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
                    onPressed: (_isExporting || _exportScope == 'miscellaneous')
                        ? null
                        : _exportAllMachineryPdf,
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
