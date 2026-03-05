import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/database/daos/settings_dao.dart';
import '../../core/database/daos/miscellaneous_dao.dart';
import '../../shared/theme/app_colors.dart';

class MiscellaneousScreen extends StatefulWidget {
  const MiscellaneousScreen({super.key});

  @override
  State<MiscellaneousScreen> createState() => _MiscellaneousScreenState();
}

class _MiscellaneousScreenState extends State<MiscellaneousScreen> {
  final _settingsDao = SettingsDao();
  final _miscDao = MiscellaneousDao();

  List<String> _miscTypes = [];
  List<_MiscRecord> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final miscItemsRaw = await _settingsDao.getSetting('misc_items_json');

    var miscTypes = <String>['Leakage', 'Starter', 'Pipes', 'Electrical'];
    if (miscItemsRaw != null && miscItemsRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(miscItemsRaw);
        if (decoded is List) {
          final loaded = decoded
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList();
          if (loaded.isNotEmpty) {
            miscTypes = loaded;
          }
        }
      } catch (_) {}
    }

    final dbRecordsRaw = await _miscDao.getAllRecords();
    final records = dbRecordsRaw
        .map((e) => _MiscRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    for (final record in records) {
      if (!miscTypes.any((t) => t.toLowerCase() == record.category.toLowerCase())) {
        miscTypes.add(record.category);
      }
    }

    if (!mounted) return;
    setState(() {
      _miscTypes = miscTypes;
      _records = records;
      _isLoading = false;
    });
  }

  Future<void> _persistRecords() async {
    await _miscDao.replaceAllRecords(_records.map((r) => r.toJson()).toList());

    final groupedTitles = <String, List<String>>{};
    for (final record in _records) {
      final list = groupedTitles.putIfAbsent(record.category, () => []);
      if (!list.any((v) => v.toLowerCase() == record.title.toLowerCase())) {
        list.add(record.title);
      }
    }
    await _settingsDao.setSetting('misc_custom_values_json', jsonEncode(groupedTitles));
  }

  Future<void> _addRecord() async {
    await _showRecordDialog();
  }

  Future<void> _showRecordDialog({_MiscRecord? existing}) async {
    final titleCtrl = TextEditingController();
    titleCtrl.text = existing?.title ?? '';
    var selectedCategory = existing?.category ?? (_miscTypes.isNotEmpty ? _miscTypes.first : 'Miscellaneous');

    final created = await showDialog<_MiscRecord>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(existing == null ? 'Add Miscellaneous Item' : 'Edit Miscellaneous Item'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'e.g., Tubewell Main Leakage',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedCategory,
                decoration: const InputDecoration(labelText: 'Category'),
                items: _miscTypes
                    .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setLocalState(() => selectedCategory = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                Navigator.pop(
                  ctx,
                  _MiscRecord(
                    id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
                    title: title,
                    category: selectedCategory,
                    entries: existing?.entries ?? [],
                  ),
                );
              },
              child: Text(existing == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );

    if (created == null) return;

    final index = _records.indexWhere((r) => r.id == created.id);
    setState(() {
      if (index == -1) {
        _records.add(created);
      } else {
        _records[index] = created;
      }
    });
    await _persistRecords();
  }

  Future<void> _deleteRecord(_MiscRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text('Delete "${record.title}" and all expenditures?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() {
      _records.removeWhere((r) => r.id == record.id);
    });
    await _persistRecords();
  }

  Future<void> _openRecord(_MiscRecord record) async {
    final updated = await Navigator.push<_MiscRecord>(
      context,
      MaterialPageRoute(
        builder: (_) => _MiscRecordDetailScreen(
          record: record,
          categoryOptions: _miscTypes,
        ),
      ),
    );

    if (updated == null) return;

    final index = _records.indexWhere((r) => r.id == updated.id);
    if (index == -1) return;

    setState(() {
      _records[index] = updated;
    });
    await _persistRecords();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Miscellaneous')),
      floatingActionButton: FloatingActionButton(
        onPressed: _addRecord,
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'No miscellaneous items yet.\nTap + to add title, category, and expenditures.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _records.length,
                    itemBuilder: (context, index) {
                      final record = _records[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          onTap: () => _openRecord(record),
                          leading: const CircleAvatar(child: Icon(Icons.category_outlined)),
                          title: Text(record.title),
                          subtitle: Text(
                            '${record.category} • ${record.entries.length} entries • Rs. ${record.totalAmount.toStringAsFixed(0)}',
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') {
                                _showRecordDialog(existing: record);
                              }
                              if (value == 'delete') {
                                _deleteRecord(record);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _MiscRecordDetailScreen extends StatefulWidget {
  final _MiscRecord record;
  final List<String> categoryOptions;

  const _MiscRecordDetailScreen({required this.record, required this.categoryOptions});

  @override
  State<_MiscRecordDetailScreen> createState() => _MiscRecordDetailScreenState();
}

class _MiscRecordDetailScreenState extends State<_MiscRecordDetailScreen> {
  late _MiscRecord _record;

  @override
  void initState() {
    super.initState();
    _record = widget.record.copyWith(
      entries: widget.record.entries.map((e) => e.copyWith()).toList(),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';
  }

  DateTime _parseDate(String value) {
    final parts = value.split('-');
    if (parts.length != 3) return DateTime.now();
    final day = int.tryParse(parts[0]) ?? 1;
    final month = int.tryParse(parts[1]) ?? 1;
    final year = int.tryParse(parts[2]) ?? DateTime.now().year;
    return DateTime(year, month, day);
  }

  Future<void> _showEntryDialog({_MiscEntry? existing}) async {
    final formKey = GlobalKey<FormState>();
    final serialNoCtrl = TextEditingController();
    final dateCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final sizeCtrl = TextEditingController();
    final voucherCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final regPageCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    var category = existing?.category ?? _record.category;
    var selectedDate = existing != null ? _parseDate(existing.entryDate) : DateTime.now();
    final nextSerialNo = existing?.serialNo ?? (_record.entries.length + 1);

    serialNoCtrl.text = nextSerialNo.toString();
    dateCtrl.text = existing?.entryDate ?? _formatDate(selectedDate);
    locationCtrl.text = existing?.location ?? '';
    sizeCtrl.text = existing?.size ?? '';
    voucherCtrl.text = existing?.voucherNo ?? '';
    amountCtrl.text = existing != null ? existing.amount.toStringAsFixed(0) : '';
    regPageCtrl.text = existing?.regPageNo ?? '';
    noteCtrl.text = existing?.notes ?? '';

    final entry = await showDialog<_MiscEntry>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocalState) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              existing == null ? 'Add Expenditure' : 'Edit Expenditure',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Row: Sr. No. + Date
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: TextFormField(
                              controller: serialNoCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Sr. No.'),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Required';
                                if (int.tryParse(v) == null) return 'Invalid';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              readOnly: true,
                              controller: dateCtrl,
                              decoration: InputDecoration(
                                labelText: 'Date (DD-MM-YYYY)',
                                prefixIcon: const Icon(Icons.calendar_today),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.date_range),
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: selectedDate,
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime(2100),
                                    );
                                    if (picked == null) return;
                                    setLocalState(() {
                                      selectedDate = picked;
                                      dateCtrl.text = _formatDate(picked);
                                    });
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Location
                      TextFormField(
                        controller: locationCtrl,
                        decoration: const InputDecoration(labelText: 'Location'),
                      ),
                      const SizedBox(height: 12),

                      // Category
                      DropdownButtonFormField<String>(
                        value: category,
                        decoration: const InputDecoration(labelText: 'Category'),
                        items: widget.categoryOptions
                            .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setLocalState(() => category = v);
                        },
                      ),
                      const SizedBox(height: 12),

                      // Size
                      TextFormField(
                        controller: sizeCtrl,
                        decoration: const InputDecoration(labelText: 'Size (optional)'),
                      ),
                      const SizedBox(height: 12),

                      // Row: Voucher No. + Amount
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: voucherCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Voucher No.'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: amountCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Amount (PKR)',
                                prefixText: 'Rs. ',
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Required';
                                if (double.tryParse(v) == null) return 'Invalid';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Register Page No.
                      TextFormField(
                        controller: regPageCtrl,
                        decoration: const InputDecoration(labelText: 'Register Page No.'),
                      ),
                      const SizedBox(height: 12),

                      // Notes
                      TextFormField(
                        controller: noteCtrl,
                        decoration: const InputDecoration(labelText: 'Notes (optional)'),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 20),

                      // Full-width submit button
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            if (!formKey.currentState!.validate()) return;
                            final amount = double.tryParse(amountCtrl.text.trim());
                            if (amount == null || amount <= 0) return;
                            Navigator.pop(
                              ctx,
                              _MiscEntry(
                                id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
                                serialNo: int.tryParse(serialNoCtrl.text.trim()) ?? nextSerialNo,
                                category: category,
                                entryDate: dateCtrl.text.trim().isEmpty ? _formatDate(selectedDate) : dateCtrl.text.trim(),
                                location: locationCtrl.text.trim().isEmpty ? null : locationCtrl.text.trim(),
                                size: sizeCtrl.text.trim().isEmpty ? null : sizeCtrl.text.trim(),
                                voucherNo: voucherCtrl.text.trim().isEmpty ? null : voucherCtrl.text.trim(),
                                amount: amount,
                                regPageNo: regPageCtrl.text.trim().isEmpty ? null : regPageCtrl.text.trim(),
                                notes: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                              ),
                            );
                          },
                          child: Text(existing == null ? 'Add Entry' : 'Save'),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (entry == null) return;
    setState(() {
      final idx = _record.entries.indexWhere((e) => e.id == entry.id);
      final updatedEntries = List<_MiscEntry>.from(_record.entries);
      if (idx == -1) {
        updatedEntries.add(entry);
      } else {
        updatedEntries[idx] = entry;
      }
      _record = _record.copyWith(entries: updatedEntries);
    });
  }

  void _deleteEntry(String entryId) {
    setState(() {
      _record = _record.copyWith(
        entries: _record.entries.where((e) => e.id != entryId).toList(),
      );
    });
  }

  void _saveAndClose() {
    Navigator.pop(context, _record);
  }

  Future<bool> _onWillPop() async {
    _saveAndClose();
    return false;
  }

  Widget _getCategoryIcon(String category) {
    IconData icon;
    Color color;
    switch (category.toLowerCase()) {
      case 'starter':
        icon = Icons.electric_bolt;
        color = Colors.amber;
        break;
      case 'leakage':
        icon = Icons.water_drop;
        color = Colors.blue;
        break;
      case 'pipes':
        icon = Icons.plumbing;
        color = Colors.teal;
        break;
      case 'electrical':
        icon = Icons.electrical_services;
        color = Colors.orange;
        break;
      default:
        icon = Icons.build_circle;
        color = AppColors.primary;
    }
    return CircleAvatar(
      backgroundColor: color.withOpacity(0.15),
      child: Icon(icon, color: color, size: 20),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _saveAndClose,
          ),
          title: Text(_record.title),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: ExpansionTile(
                initiallyExpanded: true,
                leading: _getCategoryIcon(_record.category),
                title: Text(
                  _record.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${_record.entries.length} entries · Total: Rs. ${_record.totalAmount.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                children: [
                  if (_record.entries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No expenditures yet. Tap + to add.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columnSpacing: 16,
                        headingRowColor: WidgetStateProperty.all(AppColors.primary.withOpacity(0.05)),
                        columns: const [
                          DataColumn(label: Text('Sr.No', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Location', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Category', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Size', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Voucher No.', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Amount (PKR)', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                          DataColumn(label: Text('Reg. Page No.', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: _record.entries.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final row = entry.value;
                          return DataRow(
                            cells: [
                              DataCell(Text('${row.serialNo > 0 ? row.serialNo : idx + 1}')),
                              DataCell(Text(row.entryDate)),
                              DataCell(Text(row.location ?? '-')),
                              DataCell(Text(row.category)),
                              DataCell(Text(row.size ?? '-')),
                              DataCell(Text(row.voucherNo ?? '-')),
                              DataCell(Text('Rs. ${row.amount.toStringAsFixed(0)}')),
                              DataCell(Text(row.regPageNo ?? '-')),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 18, color: AppColors.primary),
                                      onPressed: () => _showEntryDialog(existing: row),
                                      tooltip: 'Edit',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.delete, size: 18, color: AppColors.error),
                                      onPressed: () => _deleteEntry(row.id),
                                      tooltip: 'Delete',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  // Add Entry button — centered, matching scheme page style
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: OutlinedButton.icon(
                      onPressed: () => _showEntryDialog(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Entry'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class _MiscRecord {
  final String id;
  final String title;
  final String category;
  final List<_MiscEntry> entries;

  _MiscRecord({
    required this.id,
    required this.title,
    required this.category,
    required this.entries,
  });

  double get totalAmount => entries.fold<double>(0, (sum, e) => sum + e.amount);

  _MiscRecord copyWith({
    String? id,
    String? title,
    String? category,
    List<_MiscEntry>? entries,
  }) {
    return _MiscRecord(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      entries: entries ?? this.entries,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'entries': entries.map((e) => e.toJson()).toList(),
      };

  factory _MiscRecord.fromJson(Map<String, dynamic> json) {
    return _MiscRecord(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      category: (json['category'] ?? 'Miscellaneous').toString(),
      entries: (json['entries'] is List)
          ? (json['entries'] as List)
              .whereType<Map>()
              .map((e) => _MiscEntry.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : <_MiscEntry>[],
    );
  }
}

class _MiscEntry {
  final String id;
  final int serialNo;
  final String category;
  final String entryDate;
  final String? location;
  final String? size;
  final String? voucherNo;
  final double amount;
  final String? regPageNo;
  final String? notes;

  _MiscEntry({
    required this.id,
    required this.serialNo,
    required this.category,
    required this.entryDate,
    this.location,
    this.size,
    this.voucherNo,
    required this.amount,
    this.regPageNo,
    this.notes,
  });

  _MiscEntry copyWith({
    String? id,
    int? serialNo,
    String? category,
    String? entryDate,
    String? location,
    String? size,
    String? voucherNo,
    double? amount,
    String? regPageNo,
    String? notes,
  }) {
    return _MiscEntry(
      id: id ?? this.id,
      serialNo: serialNo ?? this.serialNo,
      category: category ?? this.category,
      entryDate: entryDate ?? this.entryDate,
      location: location ?? this.location,
      size: size ?? this.size,
      voucherNo: voucherNo ?? this.voucherNo,
      amount: amount ?? this.amount,
      regPageNo: regPageNo ?? this.regPageNo,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'serialNo': serialNo,
        'category': category,
        'entryDate': entryDate,
        'location': location,
        'size': size,
        'voucherNo': voucherNo,
        'amount': amount,
        'regPageNo': regPageNo,
        'notes': notes,
      };

  factory _MiscEntry.fromJson(Map<String, dynamic> json) {
    return _MiscEntry(
      id: (json['id'] ?? '').toString(),
      serialNo: int.tryParse((json['serialNo'] ?? 0).toString()) ?? 0,
      category: (json['category'] ?? 'Miscellaneous').toString(),
      entryDate: (json['entryDate'] ?? '').toString(),
      location: json['location']?.toString(),
      size: json['size']?.toString(),
      voucherNo: json['voucherNo']?.toString(),
      amount: double.tryParse((json['amount'] ?? 0).toString()) ?? 0,
      regPageNo: json['regPageNo']?.toString(),
      notes: json['notes']?.toString(),
    );
  }
}
