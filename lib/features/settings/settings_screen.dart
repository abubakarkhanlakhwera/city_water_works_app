import 'package:flutter/material.dart';
import '../../core/database/daos/settings_dao.dart';
import '../../core/database/daos/machinery_types_dao.dart';
import '../../core/models/machinery_type.dart';
import '../../core/services/backup_service.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/app_text_field.dart';
import '../backup/backup_screen.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onThemeChanged;

  const SettingsScreen({super.key, this.onThemeChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settingsDao = SettingsDao();
  final _typesDao = MachineryTypesDao();
  final _backupService = BackupService();

  bool _isDarkMode = false;
  bool _autoBackup = false;
  List<MachineryType> _types = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final darkMode = await _settingsDao.getSetting('dark_mode');
      final autoBackup = await _settingsDao.getSetting('auto_backup');
      final types = await _typesDao.getAllTypes();

      if (mounted) {
        setState(() {
          _isDarkMode = darkMode == 'true';
          _autoBackup = autoBackup == 'true';
          _types = types;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleDarkMode(bool value) async {
    setState(() => _isDarkMode = value);
    await _settingsDao.setSetting('dark_mode', value.toString());
    widget.onThemeChanged?.call();
  }

  Future<void> _toggleAutoBackup(bool value) async {
    setState(() => _autoBackup = value);
    await _settingsDao.setSetting('auto_backup', value.toString());
  }

  Future<void> _addMachineryType() async {
    final nameCtrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Machinery Type'),
        content: AppTextField(
          controller: nameCtrl,
          label: 'Type Name',
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await _typesDao.insertType(MachineryType(
        typeName: result,
        attributes: [],
      ));
      _loadSettings();
    }
  }

  Future<void> _deleteMachineryType(MachineryType type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Type'),
        content: Text('Delete machinery type "${type.typeName}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _typesDao.deleteType(type.typeId!);
      _loadSettings();
    }
  }

  Future<void> _deleteAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete All Data'),
        content: const Text(
          'This will permanently delete all schemes, sets, machinery, and billing entries.\n\n'
          'This action cannot be undone. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _backupService.deleteAllData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All data deleted successfully')),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Appearance
                Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: SwitchListTile(
                    title: const Text('Dark Mode'),
                    subtitle: const Text('Switch between light and dark theme'),
                    secondary: Icon(
                      _isDarkMode ? Icons.dark_mode : Icons.light_mode,
                      color: AppColors.primary,
                    ),
                    value: _isDarkMode,
                    onChanged: _toggleDarkMode,
                  ),
                ),
                const SizedBox(height: 20),

                // Data Management
                Text('Data Management', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Auto Backup'),
                        subtitle: const Text('Automatically backup data weekly'),
                        secondary: const Icon(Icons.backup, color: AppColors.primary),
                        value: _autoBackup,
                        onChanged: _toggleAutoBackup,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.restore, color: AppColors.primary),
                        title: const Text('Backup & Restore'),
                        subtitle: const Text('Manage your data backups'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const BackupScreen()),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.delete_forever, color: AppColors.error),
                        title: const Text('Delete All Data',
                            style: TextStyle(color: AppColors.error)),
                        subtitle: const Text('Permanently remove all records'),
                        onTap: _deleteAllData,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Machinery Types
                Row(
                  children: [
                    Expanded(
                      child: Text('Machinery Types',
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: AppColors.primary),
                      onPressed: _addMachineryType,
                      tooltip: 'Add Type',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: _types
                        .map((t) => ListTile(
                              leading: const Icon(Icons.precision_manufacturing),
                              title: Text(t.typeName),
                              subtitle: Text('${t.attributes.length} attributes'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, size: 20),
                                onPressed: () => _deleteMachineryType(t),
                              ),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 20),

                // About
                Text('About', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.water_drop, color: AppColors.primary),
                        title: const Text('City Water Works'),
                        subtitle: const Text('Machinery Billing & Record Management'),
                      ),
                      const Divider(height: 1),
                      const ListTile(
                        leading: Icon(Icons.info_outline),
                        title: Text('Version'),
                        subtitle: Text('1.0.0'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
