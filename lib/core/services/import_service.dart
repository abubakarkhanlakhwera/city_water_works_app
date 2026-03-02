import 'dart:io';
import 'package:excel/excel.dart';
import '../database/daos/schemes_dao.dart';
import '../database/daos/sets_dao.dart';
import '../database/daos/machinery_dao.dart';
import '../database/daos/billing_entries_dao.dart';
import '../models/scheme.dart';
import '../models/set_model.dart';
import '../models/machinery.dart';
import '../models/billing_entry.dart';
import 'dart:convert';

class ImportResult {
  final int schemesImported;
  final int setsImported;
  final int machineryImported;
  final int entriesImported;
  final List<String> errors;
  final List<String> warnings;

  ImportResult({
    this.schemesImported = 0,
    this.setsImported = 0,
    this.machineryImported = 0,
    this.entriesImported = 0,
    this.errors = const [],
    this.warnings = const [],
  });
}

/// Parsed data structures before committing to DB
class ParsedScheme {
  String schemeName;
  List<ParsedSet> sets;

  ParsedScheme({required this.schemeName, this.sets = const []});
}

class ParsedSet {
  int setNumber;
  String setLabel;
  List<ParsedMachinery> machineryList;

  ParsedSet({required this.setNumber, required this.setLabel, this.machineryList = const []});
}

class ParsedMachinery {
  String machineryType;
  String? brand;
  Map<String, String> specs;
  String displayLabel;
  List<ParsedEntry> entries;

  ParsedMachinery({
    required this.machineryType,
    this.brand,
    this.specs = const {},
    required this.displayLabel,
    this.entries = const [],
  });
}

class ParsedEntry {
  int serialNo;
  String date;
  int? voucherNo;
  double amount;
  String? regPageNo;
  String? error;
  int rowNumber;

  ParsedEntry({
    required this.serialNo,
    required this.date,
    this.voucherNo,
    required this.amount,
    this.regPageNo,
    this.error,
    this.rowNumber = 0,
  });
}

class ImportService {
  final SchemesDao _schemesDao = SchemesDao();
  final SetsDao _setsDao = SetsDao();
  final MachineryDao _machineryDao = MachineryDao();
  final BillingEntriesDao _entriesDao = BillingEntriesDao();

  // Regex patterns for parsing machinery labels
  static final motorRegex = RegExp(r'Motor\s*(\d+)\s*/?\s*HP\s+(.+)', caseSensitive: false);
  static final pumpRegex = RegExp(r'Pump\s*(\d+x\d+)', caseSensitive: false);
  static final transformerRegex = RegExp(r'Transformer\s*(\d+)\s*[Kk][Vv]', caseSensitive: false);

  // Sheet name to scheme name mapping
  static final Map<String, String> sheetNameMapping = {
    'Tanky 2': 'City Water Works Tanky No. 2',
    'Tanky 1': 'City Water Works Tanky No. 1',
    'Mehboob colony': 'Mehboob Colony Water Works',
    'Hussain Colony': 'Hussain Colony Water Works',
    '14G': '14G Water Works',
    '46F': '46F Water Works',
    'Sodha': 'Sodha Water Works',
  };

  /// Parse an Excel file and return structured data for preview
  Future<List<ParsedScheme>> parseExcelFile(String filePath) async {
    final bytes = File(filePath).readAsBytesSync();
    final excel = Excel.decodeBytes(bytes);
    final List<ParsedScheme> schemes = [];

    for (final sheetName in excel.tables.keys) {
      if (sheetName.toLowerCase() == 'list') continue; // Skip metadata sheets

      final sheet = excel.tables[sheetName]!;
      if (sheet.maxRows < 2) continue;

      final schemeName = sheetNameMapping[sheetName] ?? '$sheetName Water Works';
      final parsedScheme = ParsedScheme(schemeName: schemeName, sets: []);

      // Parse the sheet to find sets and machinery
      final parsedSets = _parseSheet(sheet);
      parsedScheme.sets = parsedSets;

      if (parsedSets.isNotEmpty) {
        schemes.add(parsedScheme);
      }
    }

    return schemes;
  }

  List<ParsedSet> _parseSheet(Sheet sheet) {
    final List<ParsedSet> sets = [];
    final rows = sheet.rows;
    if (rows.isEmpty) return sets;

    // Strategy: scan for set headers
    // Look for rows containing "Set No." pattern
    int currentRow = 0;

    while (currentRow < rows.length) {
      final row = rows[currentRow];
      // Check if this row contains a Set header
      int setStartCol = -1;
      String? setHeaderText;

      for (int col = 0; col < row.length; col++) {
        final cell = row[col];
        if (cell != null && cell.value != null) {
          final text = cell.value.toString().trim();
          if (text.toLowerCase().contains('set no')) {
            setStartCol = col;
            setHeaderText = text;
            break;
          }
        }
      }

      if (setHeaderText != null) {
        // Found a set header row — parse it
        final parsedSetsFromRow = _parseSetsFromRow(rows, currentRow);
        sets.addAll(parsedSetsFromRow);
        // Skip ahead past data rows
        currentRow += _findEndOfData(rows, currentRow + 1) + 1;
      } else {
        // Also check if row has machinery labels directly (alternate format)
        bool hasMachineryLabel = false;
        for (int col = 0; col < row.length; col++) {
          final cell = row[col];
          if (cell != null && cell.value != null) {
            final text = cell.value.toString().trim();
            if (motorRegex.hasMatch(text) || pumpRegex.hasMatch(text) || transformerRegex.hasMatch(text)) {
              hasMachineryLabel = true;
              break;
            }
          }
        }

        if (hasMachineryLabel && sets.isEmpty) {
          // Machinery labels without a set header — create a default set
          final parsedSets = _parseMachineryRow(rows, currentRow);
          sets.addAll(parsedSets);
          currentRow += _findEndOfData(rows, currentRow + 1) + 1;
        } else {
          currentRow++;
        }
      }
    }

    // If no sets found from structured parsing, try a simpler approach
    if (sets.isEmpty) {
      return _parseSimpleFormat(rows);
    }

    return sets;
  }

  List<ParsedSet> _parseSetsFromRow(List<List<Data?>> rows, int headerRow) {
    final List<ParsedSet> sets = [];
    final row = rows[headerRow];

    // Find all set header positions in this row
    final List<MapEntry<int, String>> setPositions = [];
    for (int col = 0; col < row.length; col++) {
      final cell = row[col];
      if (cell != null && cell.value != null) {
        final text = cell.value.toString().trim();
        if (text.toLowerCase().contains('set no')) {
          setPositions.add(MapEntry(col, text));
        }
      }
    }

    // For each set, find machinery in the next row
    for (int i = 0; i < setPositions.length; i++) {
      final startCol = setPositions[i].key;
      final endCol = i + 1 < setPositions.length ? setPositions[i + 1].key : row.length;
      final setHeader = setPositions[i].value;

      // Extract set number
      final setNumMatch = RegExp(r'Set\s*No\.?\s*(\d+)', caseSensitive: false).firstMatch(setHeader);
      final setNumber = setNumMatch != null ? int.tryParse(setNumMatch.group(1)!) ?? (i + 1) : (i + 1);

      final parsedSet = ParsedSet(
        setNumber: setNumber,
        setLabel: 'Set No. $setNumber',
        machineryList: [],
      );

      // Next row should have machinery labels
      if (headerRow + 1 < rows.length) {
        final machineryRow = rows[headerRow + 1];
        final machineryList = _parseMachineryInRange(machineryRow, startCol, endCol);

        // Find data start row (skip column headers row)
        int dataStartRow = headerRow + 3; // header -> machinery -> col headers -> data

        // Parse entries for each machinery
        for (final mach in machineryList) {
          final entries = _parseEntries(rows, dataStartRow, mach.startCol, mach.endCol);
          mach.machinery.entries = entries;
        }

        parsedSet.machineryList = machineryList.map((m) => m.machinery).toList();
      }

      sets.add(parsedSet);
    }

    return sets;
  }

  List<ParsedSet> _parseMachineryRow(List<List<Data?>> rows, int machineryRowIndex) {
    // The row has machinery labels without set headers
    final parsedSet = ParsedSet(setNumber: 1, setLabel: 'Set No. 1', machineryList: []);
    final row = rows[machineryRowIndex];
    final machineryList = _parseMachineryInRange(row, 0, row.length);

    int dataStartRow = machineryRowIndex + 2; // machinery -> col headers -> data

    for (final mach in machineryList) {
      final entries = _parseEntries(rows, dataStartRow, mach.startCol, mach.endCol);
      mach.machinery.entries = entries;
    }

    parsedSet.machineryList = machineryList.map((m) => m.machinery).toList();
    return [parsedSet];
  }

  List<_MachineryWithCols> _parseMachineryInRange(List<Data?> row, int startCol, int endCol) {
    final List<_MachineryWithCols> result = [];

    for (int col = startCol; col < endCol && col < row.length; col++) {
      final cell = row[col];
      if (cell == null || cell.value == null) continue;
      final text = cell.value.toString().trim();
      if (text.isEmpty) continue;

      final machinery = _parseMachineryLabel(text);
      if (machinery != null) {
        result.add(_MachineryWithCols(machinery: machinery, startCol: col, endCol: col + 4));
      }
    }

    // Adjust end columns
    for (int i = 0; i < result.length; i++) {
      if (i + 1 < result.length) {
        result[i].endCol = result[i + 1].startCol;
      } else {
        result[i].endCol = endCol;
      }
    }

    return result;
  }

  ParsedMachinery? _parseMachineryLabel(String text) {
    // Motor
    final motorMatch = motorRegex.firstMatch(text);
    if (motorMatch != null) {
      return ParsedMachinery(
        machineryType: 'Motor',
        brand: motorMatch.group(2)?.trim(),
        specs: {'hp': motorMatch.group(1)!},
        displayLabel: text,
        entries: [],
      );
    }

    // Pump
    final pumpMatch = pumpRegex.firstMatch(text);
    if (pumpMatch != null) {
      return ParsedMachinery(
        machineryType: 'Pump',
        specs: {'size': pumpMatch.group(1)!},
        displayLabel: text,
        entries: [],
      );
    }

    // Transformer
    final transMatch = transformerRegex.firstMatch(text);
    if (transMatch != null) {
      return ParsedMachinery(
        machineryType: 'Transformer',
        specs: {'kva': transMatch.group(1)!},
        displayLabel: text,
        entries: [],
      );
    }

    // Turbine or unknown
    if (text.toLowerCase().contains('turbine')) {
      return ParsedMachinery(
        machineryType: 'Turbine',
        specs: {},
        displayLabel: text,
        entries: [],
      );
    }

    return null;
  }

  List<ParsedEntry> _parseEntries(List<List<Data?>> rows, int startRow, int startCol, int endCol) {
    final List<ParsedEntry> entries = [];
    int emptyRowCount = 0;

    for (int r = startRow; r < rows.length; r++) {
      final row = rows[r];
      if (startCol >= row.length) {
        emptyRowCount++;
        if (emptyRowCount >= 3) break;
        continue;
      }

      // Try to read Sr.No, Date, Voucher No., Amount
      final snCell = startCol < row.length ? row[startCol] : null;
      final dateCell = startCol + 1 < row.length ? row[startCol + 1] : null;
      final voucherCell = startCol + 2 < row.length ? row[startCol + 2] : null;
      final amountCell = startCol + 3 < row.length ? row[startCol + 3] : null;

      if (snCell == null || snCell.value == null) {
        emptyRowCount++;
        if (emptyRowCount >= 3) break;
        continue;
      }

      emptyRowCount = 0;

      final sn = _parseInt(snCell.value);
      if (sn == null) continue;

      final date = _parseDate(dateCell?.value);
      final voucher = _parseInt(voucherCell?.value);
      final amount = _parseDouble(amountCell?.value);

      String? error;
      if (date == null) error = 'Invalid date';
      if (amount == null) error = (error != null ? '$error; ' : '') + 'Invalid amount';

      entries.add(ParsedEntry(
        serialNo: sn,
        date: date ?? '',
        voucherNo: voucher,
        amount: amount ?? 0.0,
        regPageNo: null,
        error: error,
        rowNumber: r + 1,
      ));
    }

    return entries;
  }

  int _findEndOfData(List<List<Data?>> rows, int startRow) {
    int emptyRowCount = 0;
    for (int r = startRow; r < rows.length; r++) {
      final row = rows[r];
      bool isEmpty = true;
      for (final cell in row) {
        if (cell != null && cell.value != null && cell.value.toString().trim().isNotEmpty) {
          isEmpty = false;
          break;
        }
      }
      if (isEmpty) {
        emptyRowCount++;
        if (emptyRowCount >= 3) return r - startRow;
      } else {
        emptyRowCount = 0;
      }
    }
    return rows.length - startRow;
  }

  List<ParsedSet> _parseSimpleFormat(List<List<Data?>> rows) {
    // Fallback: try to find machinery labels in any row
    final List<ParsedSet> sets = [];

    for (int r = 0; r < rows.length; r++) {
      final row = rows[r];
      List<_MachineryWithCols> foundMachinery = [];

      for (int col = 0; col < row.length; col++) {
        final cell = row[col];
        if (cell == null || cell.value == null) continue;
        final text = cell.value.toString().trim();
        final machinery = _parseMachineryLabel(text);
        if (machinery != null) {
          foundMachinery.add(_MachineryWithCols(machinery: machinery, startCol: col, endCol: col + 4));
        }
      }

      if (foundMachinery.isNotEmpty) {
        // Adjust end columns
        for (int i = 0; i < foundMachinery.length; i++) {
          if (i + 1 < foundMachinery.length) {
            foundMachinery[i].endCol = foundMachinery[i + 1].startCol;
          }
        }

        int dataStartRow = r + 2; // skip column headers
        for (final mach in foundMachinery) {
          final entries = _parseEntries(rows, dataStartRow, mach.startCol, mach.endCol);
          mach.machinery.entries = entries;
        }

        // Try to determine set number from context
        int setNum = sets.length + 1;
        // Check the row above for set header
        if (r > 0) {
          for (final cell in rows[r - 1]) {
            if (cell != null && cell.value != null) {
              final match = RegExp(r'Set\s*No\.?\s*(\d+)', caseSensitive: false).firstMatch(cell.value.toString());
              if (match != null) {
                setNum = int.tryParse(match.group(1)!) ?? setNum;
                break;
              }
            }
          }
        }

        sets.add(ParsedSet(
          setNumber: setNum,
          setLabel: 'Set No. $setNum',
          machineryList: foundMachinery.map((m) => m.machinery).toList(),
        ));
      }
    }

    return sets;
  }

  /// Parse date from various formats to DD-MM-YYYY
  String? _parseDate(dynamic value) {
    if (value == null) return null;

    if (value is DateTime) {
      return '${value.day.toString().padLeft(2, '0')}-${value.month.toString().padLeft(2, '0')}-${value.year}';
    }

    if (value is DateCellValue) {
      return '${value.day.toString().padLeft(2, '0')}-${value.month.toString().padLeft(2, '0')}-${value.year}';
    }

    final str = value.toString().trim();
    if (str.isEmpty) return null;

    // Try DD-MM-YYYY
    final dmy = RegExp(r'^(\d{1,2})-(\d{1,2})-(\d{4})$').firstMatch(str);
    if (dmy != null) {
      return '${dmy.group(1)!.padLeft(2, '0')}-${dmy.group(2)!.padLeft(2, '0')}-${dmy.group(3)}';
    }

    // Try DD-MM-YY
    final dmyShort = RegExp(r'^(\d{1,2})-(\d{1,2})-(\d{2})$').firstMatch(str);
    if (dmyShort != null) {
      final year = int.parse(dmyShort.group(3)!);
      final fullYear = year > 50 ? 1900 + year : 2000 + year;
      return '${dmyShort.group(1)!.padLeft(2, '0')}-${dmyShort.group(2)!.padLeft(2, '0')}-$fullYear';
    }

    // Try YYYY-MM-DD
    final ymd = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(str);
    if (ymd != null) {
      return '${ymd.group(3)!.padLeft(2, '0')}-${ymd.group(2)!.padLeft(2, '0')}-${ymd.group(1)}';
    }

    // Try DD/MM/YYYY
    final dmySlash = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(str);
    if (dmySlash != null) {
      return '${dmySlash.group(1)!.padLeft(2, '0')}-${dmySlash.group(2)!.padLeft(2, '0')}-${dmySlash.group(3)}';
    }

    // Excel numeric date (days since 1899-12-30)
    final numericDate = double.tryParse(str);
    if (numericDate != null && numericDate > 30000 && numericDate < 100000) {
      final date = DateTime(1899, 12, 30).add(Duration(days: numericDate.toInt()));
      return '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';
    }

    return null;
  }

  int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is IntCellValue) return value.value;
    if (value is double) return value.toInt();
    if (value is DoubleCellValue) return value.value.toInt();
    final str = value.toString().trim();
    return int.tryParse(str) ?? double.tryParse(str)?.toInt();
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is DoubleCellValue) return value.value;
    if (value is int) return value.toDouble();
    if (value is IntCellValue) return value.value.toDouble();
    final str = value.toString().trim().replaceAll(',', '').replaceAll('Rs.', '').replaceAll('Rs', '');
    return double.tryParse(str);
  }

  /// Commit parsed data to database
  Future<ImportResult> commitImport(List<ParsedScheme> parsedSchemes) async {
    int schemesCount = 0;
    int setsCount = 0;
    int machineryCount = 0;
    int entriesCount = 0;
    final List<String> errors = [];
    final List<String> warnings = [];

    for (final ps in parsedSchemes) {
      try {
        // Check if scheme already exists
        var existingScheme = await _schemesDao.getSchemeByName(ps.schemeName);
        int schemeId;

        if (existingScheme != null) {
          schemeId = existingScheme.schemeId!;
          warnings.add('Scheme "${ps.schemeName}" already exists — merging data.');
        } else {
          final now = DateTime.now();
          final nowStr = '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
          schemeId = await _schemesDao.insertScheme(Scheme(
            schemeName: ps.schemeName,
            createdAt: nowStr,
            updatedAt: nowStr,
          ));
          schemesCount++;
        }

        for (final pset in ps.sets) {
          final setId = await _setsDao.insertSet(SetModel(
            schemeId: schemeId,
            setNumber: pset.setNumber,
            setLabel: pset.setLabel,
          ));
          setsCount++;

          int sortOrder = 0;
          for (final pm in pset.machineryList) {
            final specs = jsonEncode(pm.specs);
            final machineryId = await _machineryDao.insertMachinery(Machinery(
              setId: setId,
              machineryType: pm.machineryType,
              brand: pm.brand,
              specs: pm.specs,
              displayLabel: pm.displayLabel,
              sortOrder: sortOrder++,
            ));
            machineryCount++;

            for (final pe in pm.entries) {
              if (pe.error != null) {
                errors.add('Row ${pe.rowNumber}: ${pe.error}');
                continue;
              }
              if (pe.date.isEmpty || pe.amount == 0.0) continue;

              final now = DateTime.now();
              final nowStr = '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
              await _entriesDao.insertEntry(BillingEntry(
                machineryId: machineryId,
                serialNo: pe.serialNo,
                entryDate: pe.date,
                voucherNo: pe.voucherNo,
                amount: pe.amount,
                regPageNo: pe.regPageNo,
                createdAt: nowStr,
                updatedAt: nowStr,
              ));
              entriesCount++;
            }
          }
        }
      } catch (e) {
        errors.add('Error importing "${ps.schemeName}": $e');
      }
    }

    return ImportResult(
      schemesImported: schemesCount,
      setsImported: setsCount,
      machineryImported: machineryCount,
      entriesImported: entriesCount,
      errors: errors,
      warnings: warnings,
    );
  }
}

class _MachineryWithCols {
  ParsedMachinery machinery;
  int startCol;
  int endCol;

  _MachineryWithCols({required this.machinery, required this.startCol, required this.endCol});
}
