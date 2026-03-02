import 'package:flutter/material.dart';
import '../utils/date_utils.dart';
import '../theme/app_colors.dart';

class DDMMYYYYDatePicker extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;

  const DDMMYYYYDatePicker({
    super.key,
    required this.controller,
    this.label = 'Date (DD-MM-YYYY)',
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'DD-MM-YYYY',
        prefixIcon: const Icon(Icons.calendar_today),
        suffixIcon: IconButton(
          icon: const Icon(Icons.date_range),
          onPressed: () => _pickDate(context),
        ),
      ),
      readOnly: true,
      onTap: () => _pickDate(context),
      validator: validator ?? (value) {
        if (value == null || value.isEmpty) return 'Date is required';
        if (!DateUtils2.isValidDate(value)) return 'Invalid date format';
        return null;
      },
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    DateTime initialDate = DateTime.now();
    if (controller.text.isNotEmpty) {
      final parsed = DateUtils2.parseDate(controller.text);
      if (parsed != null) initialDate = parsed;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      controller.text = DateUtils2.formatDate(picked);
    }
  }
}
