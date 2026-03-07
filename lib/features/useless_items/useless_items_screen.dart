import 'package:flutter/material.dart';

import '../schemes/schemes_list_screen.dart';

class UselessItemsScreen extends StatelessWidget {
  const UselessItemsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SchemesListScreen(
      title: 'Useless Items',
      schemeCategory: 'useless_item',
      emptyStateTitle: 'No useless items yet',
      emptyStateSubtitle: 'Add a useless item scheme and then create sets and items inside it',
      addButtonLabel: 'Add Useless Item',
    );
  }
}
