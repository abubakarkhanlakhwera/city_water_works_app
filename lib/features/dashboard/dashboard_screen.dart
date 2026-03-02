import 'package:flutter/material.dart';
import '../../core/database/daos/schemes_dao.dart';
import '../../core/database/daos/sets_dao.dart';
import '../../core/database/daos/billing_entries_dao.dart';
import '../../core/models/billing_entry.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/utils/currency_utils.dart';
import 'widgets/summary_card.dart';
import 'widgets/recent_entries_list.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onNavigateToSchemes;
  final VoidCallback? onNavigateToImport;
  final VoidCallback? onNavigateToExport;
  final Function(int)? onNavigateToScheme;

  const DashboardScreen({
    super.key,
    this.onNavigateToSchemes,
    this.onNavigateToImport,
    this.onNavigateToExport,
    this.onNavigateToScheme,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _schemesDao = SchemesDao();
  final _setsDao = SetsDao();
  final _entriesDao = BillingEntriesDao();

  int _schemeCount = 0;
  int _setCount = 0;
  int _entriesThisMonth = 0;
  double _amountThisMonth = 0.0;
  List<BillingEntry> _recentEntries = [];
  List<BillingEntry> _searchResults = [];
  bool _isLoading = true;
  bool _isSearching = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final schemeCount = await _schemesDao.getSchemeCount();
      final setCount = await _setsDao.getSetCount();
      final entriesThisMonth = await _entriesDao.getEntryCountThisMonth();
      final amountThisMonth = await _entriesDao.getTotalAmountThisMonth();
      final recentEntries = await _entriesDao.getRecentEntries(limit: 10);

      if (mounted) {
        setState(() {
          _schemeCount = schemeCount;
          _setCount = setCount;
          _entriesThisMonth = entriesThisMonth;
          _amountThisMonth = amountThisMonth;
          _recentEntries = recentEntries;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      return;
    }

    setState(() => _isSearching = true);
    try {
      final results = await _entriesDao.searchEntries(query);
      if (mounted) {
        setState(() => _searchResults = results);
      }
    } catch (e) {
      // Ignore search errors
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width < 600 ? 2 : width < 1200 ? 3 : 4;

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // Search bar
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search schemes, vouchers, amounts...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _isSearching
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  _performSearch('');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      onChanged: _performSearch,
                    ),
                  ),
                ),

                // Show search results if searching
                if (_isSearching) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Search Results (${_searchResults.length})',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: RecentEntriesList(entries: _searchResults),
                  ),
                ] else ...[
                  // Summary cards
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: 1.5,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      delegate: SliverChildListDelegate([
                        SummaryCard(
                          title: 'Total Schemes',
                          value: _schemeCount.toString(),
                          icon: Icons.water_drop,
                          color: AppColors.primary,
                          onTap: widget.onNavigateToSchemes ?? () {},
                        ),
                        SummaryCard(
                          title: 'Total Sets',
                          value: _setCount.toString(),
                          icon: Icons.settings,
                          color: const Color(0xFF2D8CFF),
                        ),
                        SummaryCard(
                          title: 'Entries This Month',
                          value: _entriesThisMonth.toString(),
                          icon: Icons.receipt_long,
                          color: AppColors.success,
                        ),
                        SummaryCard(
                          title: 'Amount This Month',
                          value: CurrencyUtils.formatAmountShort(_amountThisMonth),
                          icon: Icons.currency_rupee,
                          color: AppColors.accent,
                        ),
                      ]),
                    ),
                  ),

                  // Quick actions
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Quick Actions', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _QuickActionChip(
                                label: 'Add Scheme',
                                icon: Icons.add_circle_outline,
                                onTap: widget.onNavigateToSchemes ?? () {},
                              ),
                              _QuickActionChip(
                                label: 'Import Excel/CSV',
                                icon: Icons.upload_file,
                                onTap: widget.onNavigateToImport ?? () {},
                              ),
                              _QuickActionChip(
                                label: 'Export',
                                icon: Icons.download,
                                onTap: widget.onNavigateToExport ?? () {},
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Recent entries
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Recent Entries', style: Theme.of(context).textTheme.titleLarge),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _recentEntries.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(32),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(Icons.inbox_outlined, size: 64, color: AppColors.textHint),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No entries yet.\nImport an Excel file or add entries manually.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : RecentEntriesList(entries: _recentEntries),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              ],
            ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

class _QuickActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18, color: AppColors.primary),
      label: Text(label),
      onPressed: onTap,
      backgroundColor: Colors.white,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}
