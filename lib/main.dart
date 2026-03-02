import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'core/database/app_database.dart';
import 'core/database/daos/settings_dao.dart';
import 'shared/theme/app_theme.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/schemes/schemes_list_screen.dart';
import 'features/import/import_screen.dart';
import 'features/export/export_screen.dart';
import 'features/settings/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await AppDatabase.instance.database;

  final settingsDao = SettingsDao();
  final darkModePref = await settingsDao.getSetting('dark_mode');
  final isDarkMode = darkModePref == 'true';

  runApp(CityWaterWorksApp(isDarkMode: isDarkMode));
}

class CityWaterWorksApp extends StatefulWidget {
  final bool isDarkMode;
  const CityWaterWorksApp({super.key, this.isDarkMode = false});

  static _CityWaterWorksAppState? of(BuildContext context) {
    return context.findAncestorStateOfType<_CityWaterWorksAppState>();
  }

  @override
  State<CityWaterWorksApp> createState() => _CityWaterWorksAppState();
}

class _CityWaterWorksAppState extends State<CityWaterWorksApp> {
  late bool _isDarkMode;

  @override
  void initState() {
    super.initState();
    _isDarkMode = widget.isDarkMode;
  }

  void toggleTheme() async {
    final settingsDao = SettingsDao();
    final pref = await settingsDao.getSetting('dark_mode');
    setState(() => _isDarkMode = pref == 'true');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'City Water Works',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  final List<_NavItem> _navItems = [
    _NavItem(icon: Icons.dashboard, label: 'Dashboard'),
    _NavItem(icon: Icons.business, label: 'Schemes'),
    _NavItem(icon: Icons.upload_file, label: 'Import'),
    _NavItem(icon: Icons.download, label: 'Export'),
    _NavItem(icon: Icons.settings, label: 'Settings'),
  ];

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return const DashboardScreen();
      case 1:
        return const SchemesListScreen();
      case 2:
        return const ImportScreen();
      case 3:
        return const ExportScreen();
      case 4:
        return SettingsScreen(
          onThemeChanged: () => CityWaterWorksApp.of(context)?.toggleTheme(),
        );
      default:
        return const DashboardScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    // Desktop: persistent side navigation drawer
    if (width >= 1200) {
      return Scaffold(
        body: Row(
          children: [
            NavigationDrawer(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (i) => setState(() => _selectedIndex = i),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 16),
                  child: Row(
                    children: [
                      Icon(Icons.water_drop, size: 32, color: Color(0xFF1E3A5F)),
                      SizedBox(width: 12),
                      Text('City Water Works',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F))),
                    ],
                  ),
                ),
                const Divider(),
                ..._navItems.map((item) => NavigationDrawerDestination(
                  icon: Icon(item.icon), label: Text(item.label))),
              ],
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: _buildPage(_selectedIndex)),
          ],
        ),
      );
    }

    // Tablet: navigation rail
    if (width >= 600) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (i) => setState(() => _selectedIndex = i),
              labelType: NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Icon(Icons.water_drop, size: 32, color: Color(0xFF1E3A5F)),
              ),
              destinations: _navItems.map((item) => NavigationRailDestination(
                icon: Icon(item.icon), label: Text(item.label))).toList(),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: _buildPage(_selectedIndex)),
          ],
        ),
      );
    }

    // Mobile: bottom navigation bar
    return Scaffold(
      body: _buildPage(_selectedIndex),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: _navItems.map((item) => NavigationDestination(
          icon: Icon(item.icon), label: item.label)).toList(),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  _NavItem({required this.icon, required this.label});
}
