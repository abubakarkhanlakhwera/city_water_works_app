import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io' show Platform;
import '../../core/services/import_service.dart';
import '../../shared/theme/app_colors.dart';
import 'import_preview_screen.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  bool _isParsing = false;
  String? _selectedFilePath;
  String? _errorMessage;

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFilePath = result.files.single.path;
          _errorMessage = null;
        });
        _parseFile();
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error picking file: $e');
    }
  }

  Future<void> _parseFile() async {
    if (_selectedFilePath == null) return;

    setState(() {
      _isParsing = true;
      _errorMessage = null;
    });

    try {
      final importService = ImportService();
      final parsedSchemes = await importService.parseExcelFile(_selectedFilePath!);

      if (parsedSchemes.isEmpty) {
        setState(() {
          _isParsing = false;
          _errorMessage = 'No data found in the Excel file. Make sure it follows the expected format.';
        });
        return;
      }

      if (mounted) {
        setState(() => _isParsing = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ImportPreviewScreen(
              parsedSchemes: parsedSchemes,
              fileName: _selectedFilePath!.split(Platform.pathSeparator).last,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isParsing = false;
        _errorMessage = 'Error parsing file: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import from Excel')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Instructions card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text('Import Instructions',
                            style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Select an Excel (.xlsx) file to import billing records.\n\n'
                      'Expected format:\n'
                      '• Each sheet represents a Set (e.g., "Tanky 2")\n'
                      '• Sheets contain machinery sub-heads (Motor, Pump, Transformer, etc.)\n'
                      '• Columns: Sr.No, Date, Voucher No., Amount, Reg. Page No.\n\n'
                      'The system will parse and preview the data before importing.',
                      style: TextStyle(fontSize: 14, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // File picker area
            InkWell(
              onTap: _isParsing ? null : _pickFile,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.primary, width: 2, style: BorderStyle.solid),
                  borderRadius: BorderRadius.circular(12),
                  color: AppColors.primary.withOpacity(0.03),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.upload_file,
                      size: 64,
                      color: _isParsing ? AppColors.textHint : AppColors.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isParsing
                          ? 'Parsing...'
                          : _selectedFilePath != null
                              ? _selectedFilePath!.split(Platform.pathSeparator).last
                              : 'Tap to select Excel file (.xlsx)',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: _isParsing ? AppColors.textHint : AppColors.primary,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    if (_isParsing) ...[
                      const SizedBox(height: 16),
                      const CircularProgressIndicator(),
                    ],
                  ],
                ),
              ),
            ),

            // Error
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Card(
                color: AppColors.error.withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.error, color: AppColors.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_errorMessage!,
                            style: const TextStyle(color: AppColors.error)),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const Spacer(),

            // Info footer
            Text(
              'Supported format: .xlsx (Microsoft Excel)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
