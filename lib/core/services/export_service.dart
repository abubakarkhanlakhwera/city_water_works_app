import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' as xl;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../database/daos/schemes_dao.dart';
import '../database/daos/sets_dao.dart';
import '../database/daos/machinery_dao.dart';
import '../database/daos/billing_entries_dao.dart';
import '../models/machinery.dart';

class ExportService {
  final SchemesDao _schemesDao = SchemesDao();
  final SetsDao _setsDao = SetsDao();
  final MachineryDao _machineryDao = MachineryDao();
  final BillingEntriesDao _entriesDao = BillingEntriesDao();

  String _formatAmount(double amount) {
    final f = NumberFormat('#,##0', 'en_US');
    return 'Rs. ${f.format(amount)}';
  }

  String _nowFormatted() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
  }

  // ─────────────────── PDF Export ───────────────────

  Future<Uint8List> exportSetToPdf(int setId) async {
    final setModel = await _setsDao.getSetById(setId);
    if (setModel == null) throw Exception('Set not found');

    final scheme = await _schemesDao.getSchemeById(setModel.schemeId);
    final machineryList = await _machineryDao.getMachineryForSet(setId);
    final entries = await _entriesDao.getEntriesForSet(setId);
    final totalAmount = entries.fold(0.0, (sum, e) => sum + e.amount);

    final entriesByMachinery = <int, List<dynamic>>{};
    int maxRows = 1;
    for (final machinery in machineryList) {
      final machineryEntries = entries
          .where((entry) => entry.machineryId == machinery.machineryId)
          .toList()
        ..sort((a, b) => a.serialNo.compareTo(b.serialNo));
      entriesByMachinery[machinery.machineryId!] = machineryEntries;
      if (machineryEntries.length > maxRows) {
        maxRows = machineryEntries.length;
      }
    }
    maxRows = math.max(maxRows, 2);

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        header: (context) => pw.Column(
          children: [
            pw.Text(
              '${scheme?.schemeName ?? 'Unknown Scheme'} ${setModel.setLabel}',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
          ],
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Prepared by City Water Works',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
        build: (context) => [
          pw.Column(
            children: [
              pw.Row(
                children: [
                  ...machineryList.asMap().entries.map((entry) {
                    final index = entry.key;
                    final machinery = entry.value;
                    return _pdfCell(
                      _machineryHeaderLabel(machinery),
                      width: index == 0 ? 250 : 210,
                      bold: true,
                      align: pw.TextAlign.center,
                    );
                  }),
                ],
              ),
              pw.Row(
                children: [
                  _pdfCell('Sr.No', width: 40, bold: true, align: pw.TextAlign.center),
                  ...machineryList.expand((_) => [
                        _pdfCell('Date', width: 70, bold: true),
                        _pdfCell('Voucher No.', width: 70, bold: true),
                        _pdfCell('Amount', width: 70, bold: true),
                      ]),
                ],
              ),
              ...List.generate(maxRows, (rowIndex) {
                return pw.Row(
                  children: [
                    _pdfCell('${rowIndex + 1}', width: 40, align: pw.TextAlign.center),
                    ...machineryList.expand((machinery) {
                      final mEntries = entriesByMachinery[machinery.machineryId!] ?? [];
                      final entry = rowIndex < mEntries.length ? mEntries[rowIndex] : null;
                      return [
                        _pdfCell(entry?.entryDate ?? '-', width: 70),
                        _pdfCell(entry?.voucherNo?.toString() ?? '-', width: 70, align: pw.TextAlign.center),
                        _pdfCell(entry != null ? _formatAmount(entry.amount) : '-', width: 70, align: pw.TextAlign.right),
                      ];
                    }),
                  ],
                );
              }),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Container(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Total: ${_formatAmount(totalAmount)}',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  String _machineryHeaderLabel(Machinery machinery) {
    final type = machinery.machineryType;
    final specs = machinery.specs;
    final lowerType = type.toLowerCase();

    String? keySpec;
    if (lowerType == 'motor') {
      keySpec = specs['Horsepower'];
    } else if (lowerType == 'pump') {
      keySpec = specs['Size'];
    } else if (lowerType == 'transformer') {
      keySpec = specs['kVA Rating'];
    }

    final parts = <String>[type];
    if (keySpec != null && keySpec.trim().isNotEmpty) {
      parts.add(keySpec.trim());
    }
    if (machinery.brand != null && machinery.brand!.trim().isNotEmpty) {
      parts.add(machinery.brand!.trim());
    }

    return parts.join(' ');
  }

  pw.Widget _pdfCell(
    String text, {
    required double width,
    bool bold = false,
    PdfColor? background,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Container(
      width: width,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      decoration: pw.BoxDecoration(
        color: background,
        border: pw.Border.all(width: 0.4, color: PdfColors.black),
      ),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 9,
          color: background != null ? PdfColors.white : PdfColors.black,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  Future<Uint8List> exportSchemeToPdf(int schemeId) async {
    final scheme = await _schemesDao.getSchemeById(schemeId);
    if (scheme == null) throw Exception('Scheme not found');

    final sets = await _setsDao.getSetsForScheme(schemeId);
    final pdf = pw.Document();
    final headerColor = PdfColor.fromHex('#1E3A5F');

    for (final setModel in sets) {
      final machineryList = await _machineryDao.getMachineryForSet(setModel.setId!);

      for (final machinery in machineryList) {
        final entries = await _entriesDao.getEntriesForMachinery(machinery.machineryId!);
        final totalAmount = entries.fold(0.0, (sum, e) => sum + e.amount);

        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4.landscape,
            header: (context) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(scheme.schemeName,
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('${setModel.setLabel} — ${machinery.displayLabel}',
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Date: ${_nowFormatted()}', style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
                pw.Divider(),
              ],
            ),
            footer: (context) => pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Prepared by City Water Works',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                    style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
            build: (context) => [
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
                headerDecoration: pw.BoxDecoration(color: headerColor),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellAlignment: pw.Alignment.centerLeft,
                headerAlignment: pw.Alignment.centerLeft,
                headers: ['Sr. No.', 'Date', 'Voucher No.', 'Amount (Rs.)', 'Reg. Page No.'],
                data: entries.map((e) => [
                  e.serialNo.toString(),
                  e.entryDate,
                  e.voucherNo?.toString() ?? '',
                  _formatAmount(e.amount),
                  e.regPageNo ?? '',
                ]).toList(),
              ),
              pw.SizedBox(height: 10),
              pw.Container(
                alignment: pw.Alignment.centerRight,
                child: pw.Text('Total: ${_formatAmount(totalAmount)}',
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    }

    return pdf.save();
  }

  Future<String> savePdf(Uint8List bytes, String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  // ─────────────────── Excel Export ───────────────────

  Future<String> exportSchemeToExcel(int schemeId) async {
    final scheme = await _schemesDao.getSchemeById(schemeId);
    if (scheme == null) throw Exception('Scheme not found');

    final sets = await _setsDao.getSetsForScheme(schemeId);
    final excel = xl.Excel.createExcel();

    final sheetName = scheme.schemeName.length > 31
        ? scheme.schemeName.substring(0, 31)
        : scheme.schemeName;
    final sheet = excel[sheetName];

    int colOffset = 0;
    for (final setModel in sets) {
      final machineryList = await _machineryDao.getMachineryForSet(setModel.setId!);

      // Row 0: Set header
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colOffset, rowIndex: 0)).value =
          xl.TextCellValue('${scheme.schemeName} ${setModel.setLabel}');

      int machColOffset = colOffset;
      for (final machinery in machineryList) {
        // Row 1: Machinery label
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: machColOffset, rowIndex: 1)).value =
            xl.TextCellValue(machinery.displayLabel);

        // Row 2: Column headers
        final headers = ['Sr.No', 'Date', 'Voucher No.', 'Amount', 'Reg. Page No.'];
        for (int h = 0; h < headers.length; h++) {
          final cell = sheet.cell(xl.CellIndex.indexByColumnRow(
              columnIndex: machColOffset + h, rowIndex: 2));
          cell.value = xl.TextCellValue(headers[h]);
          cell.cellStyle = xl.CellStyle(
            bold: true,
            backgroundColorHex: xl.ExcelColor.fromHexString('#1E3A5F'),
            fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
          );
        }

        // Data rows
        final entries = await _entriesDao.getEntriesForMachinery(machinery.machineryId!);
        for (int i = 0; i < entries.length; i++) {
          final e = entries[i];
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: machColOffset, rowIndex: 3 + i)).value =
              xl.IntCellValue(e.serialNo);
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: machColOffset + 1, rowIndex: 3 + i)).value =
              xl.TextCellValue(e.entryDate);
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: machColOffset + 2, rowIndex: 3 + i)).value =
              e.voucherNo != null ? xl.IntCellValue(e.voucherNo!) : xl.TextCellValue('');
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: machColOffset + 3, rowIndex: 3 + i)).value =
              xl.DoubleCellValue(e.amount);
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: machColOffset + 4, rowIndex: 3 + i)).value =
              xl.TextCellValue(e.regPageNo ?? '');
        }

        machColOffset += 6; // 5 columns + 1 gap
      }
      colOffset = machColOffset + 1; // gap between sets
    }

    // Remove default Sheet1 if exists
    if (excel.tables.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final dir = await getApplicationDocumentsDirectory();
    final filename = '${scheme.schemeName.replaceAll(RegExp(r'[^\w\s]'), '_')}_Export.xlsx';
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(excel.encode()!);
    return file.path;
  }

  // ─────────────────── CSV Export ───────────────────

  Future<String> exportSchemeToCsv(int schemeId) async {
    final scheme = await _schemesDao.getSchemeById(schemeId);
    if (scheme == null) throw Exception('Scheme not found');

    final sets = await _setsDao.getSetsForScheme(schemeId);

    final buffer = StringBuffer();
    // BOM for Excel UTF-8 compatibility
    buffer.write('\uFEFF');
    buffer.writeln('Scheme,Set,Machinery Type,Specs,Sr.No,Date,Voucher No.,Amount,Reg. Page No.,Notes');

    for (final setModel in sets) {
      final machineryList = await _machineryDao.getMachineryForSet(setModel.setId!);

      for (final machinery in machineryList) {
        final entries = await _entriesDao.getEntriesForMachinery(machinery.machineryId!);

        for (final e in entries) {
          buffer.writeln(
            '"${scheme.schemeName}","${setModel.setLabel}","${machinery.machineryType}","${machinery.displayLabel}",${e.serialNo},"${e.entryDate}",${e.voucherNo ?? ''},${e.amount},"${e.regPageNo ?? ''}","${e.notes ?? ''}"',
          );
        }
      }
    }

    final dir = await getApplicationDocumentsDirectory();
    final filename = '${scheme.schemeName.replaceAll(RegExp(r'[^\w\s]'), '_')}_Export.csv';
    final file = File('${dir.path}/$filename');
    await file.writeAsString(buffer.toString());
    return file.path;
  }
}
