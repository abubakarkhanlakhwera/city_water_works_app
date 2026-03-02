import 'package:flutter/material.dart';
import '../../core/database/daos/machinery_dao.dart';
import '../../core/database/daos/machinery_types_dao.dart';
import '../../core/models/machinery.dart';
import '../../core/models/machinery_type.dart';
import '../../shared/widgets/app_text_field.dart';

class MachineryForm extends StatefulWidget {
  final int setId;
  final Machinery? machinery; // null for add, non-null for edit

  const MachineryForm({super.key, required this.setId, this.machinery});

  @override
  State<MachineryForm> createState() => _MachineryFormState();
}

class _MachineryFormState extends State<MachineryForm> {
  static const String _defaultMotorBrand = 'Siemns';
  static const List<String> _defaultPumpSizes = ['4x5', '3x5'];

  final _formKey = GlobalKey<FormState>();
  final _dao = MachineryDao();
  final _typesDao = MachineryTypesDao();

  List<MachineryType> _types = [];
  MachineryType? _selectedType;
  final _brandCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();
  final Map<String, TextEditingController> _specControllers = {};

  bool _isSaving = false;
  bool _isLoading = true;
  bool get _isEdit => widget.machinery != null;

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    var types = await _typesDao.getAllTypes();

    final existing = types.map((t) => t.typeName.toLowerCase()).toSet();
    final defaults = <MachineryType>[
      MachineryType(
        typeName: 'Motor',
        attributes: [
          MachineryAttribute(name: 'Horsepower', inputType: 'dropdown', options: ['20HP', '25HP', '30HP', '40HP'], required: true),
          MachineryAttribute(name: 'Brand', inputType: 'text', required: false),
          MachineryAttribute(name: 'Phase', inputType: 'dropdown', options: ['Single', 'Three'], required: false),
        ],
      ),
      MachineryType(
        typeName: 'Pump',
        attributes: [
          MachineryAttribute(name: 'Size', inputType: 'dropdown', options: ['4x5', '3x5'], required: true),
          MachineryAttribute(name: 'Type', inputType: 'dropdown', options: ['Centrifugal', 'Submersible'], required: false),
        ],
      ),
      MachineryType(
        typeName: 'Transformer',
        attributes: [
          MachineryAttribute(name: 'kVA Rating', inputType: 'dropdown', options: ['25Kv', '50Kv', '100Kv', '200Kv'], required: true),
          MachineryAttribute(name: 'Brand', inputType: 'text', required: false),
        ],
      ),
      MachineryType(
        typeName: 'Turbine',
        attributes: [
          MachineryAttribute(name: 'Model', inputType: 'text', required: false),
          MachineryAttribute(name: 'Flow Rate', inputType: 'number', required: false),
        ],
      ),
      MachineryType(
        typeName: 'Miscellaneous',
        attributes: [
          MachineryAttribute(name: 'Particular', inputType: 'text', required: false),
        ],
      ),
    ];

    final missing = defaults.where((t) => !existing.contains(t.typeName.toLowerCase())).toList();
    if (missing.isNotEmpty) {
      for (final type in missing) {
        await _typesDao.insertType(type);
      }
      types = await _typesDao.getAllTypes();
    }

    if (mounted) {
      setState(() {
        _types = types;
        _isLoading = false;
      });

      if (_isEdit) {
        final m = widget.machinery!;
        _brandCtrl.text = m.brand ?? '';
        _labelCtrl.text = m.displayLabel;
        // Find matching type
        for (final t in types) {
          if (t.typeName.toLowerCase() == m.machineryType.toLowerCase()) {
            _selectedType = t;
            break;
          }
        }
        // Populate spec controllers
        for (final entry in m.specs.entries) {
          _specControllers[entry.key] = TextEditingController(text: entry.value);
        }
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _brandCtrl.dispose();
    _labelCtrl.dispose();
    for (final ctrl in _specControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _onTypeChanged(MachineryType? type) {
    setState(() {
      _selectedType = type;
      // Clear old spec controllers
      for (final ctrl in _specControllers.values) {
        ctrl.dispose();
      }
      _specControllers.clear();

      // Create new spec controllers based on the type's attributes
      if (type != null) {
        for (final attr in type.attributes) {
          _specControllers[attr.name] = TextEditingController();
        }

        if (type.typeName.toLowerCase() == 'motor') {
          if (_brandCtrl.text.trim().isEmpty) {
            _brandCtrl.text = _defaultMotorBrand;
          }

          final brandSpecCtrl = _specControllers['Brand'];
          if (brandSpecCtrl != null && brandSpecCtrl.text.trim().isEmpty) {
            brandSpecCtrl.text = _defaultMotorBrand;
          }
        }

        if (type.typeName.toLowerCase() == 'pump') {
          final sizeCtrl = _specControllers['Size'];
          if (sizeCtrl != null && sizeCtrl.text.trim().isEmpty) {
            sizeCtrl.text = _defaultPumpSizes.first;
          }
        }

        // Auto-generate display label
        _updateLabel();
      }
    });
  }

  bool _isPumpSizeAttribute(MachineryAttribute attr) {
    return _selectedType?.typeName.toLowerCase() == 'pump' &&
        attr.name.toLowerCase() == 'size';
  }

  bool _shouldUseDropdown(MachineryAttribute attr) {
    if (attr.inputType == 'dropdown') return true;
    return _isPumpSizeAttribute(attr);
  }

  List<String> _getAttributeOptions(MachineryAttribute attr) {
    final options = List<String>.from(attr.options);
    if (_isPumpSizeAttribute(attr)) {
      for (final size in _defaultPumpSizes) {
        if (!options.contains(size)) {
          options.add(size);
        }
      }
    }
    return options;
  }

  Future<void> _addDropdownOption(MachineryAttribute attr) async {
    final optionCtrl = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add ${attr.name}'),
        content: AppTextField(
          controller: optionCtrl,
          label: '${attr.name} value',
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, optionCtrl.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (value == null || value.isEmpty || _selectedType == null) return;

    final normalized = value.toLowerCase();
    final existing = _getAttributeOptions(attr).map((e) => e.toLowerCase()).toSet();
    if (existing.contains(normalized)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This option already exists')),
      );
      return;
    }

    final updatedAttributes = _selectedType!.attributes.map((a) {
      if (a.name != attr.name) return a;
      return MachineryAttribute(
        name: a.name,
        inputType: 'dropdown',
        options: [..._getAttributeOptions(a), value],
        required: a.required,
      );
    }).toList();

    final updatedType = MachineryType(
      typeId: _selectedType!.typeId,
      typeName: _selectedType!.typeName,
      attributes: updatedAttributes,
      createdAt: _selectedType!.createdAt,
    );

    if (updatedType.typeId != null) {
      await _typesDao.updateType(updatedType);
    }

    final currentCtrl = _specControllers[attr.name];
    if (currentCtrl != null) {
      currentCtrl.text = value;
    }

    setState(() {
      _selectedType = updatedType;
      final idx = _types.indexWhere((t) => t.typeId == updatedType.typeId);
      if (idx != -1) {
        _types[idx] = updatedType;
      }
    });
  }

  void _updateLabel() {
    if (_selectedType == null) return;
    final brand = _brandCtrl.text.trim();
    final typeName = _selectedType!.typeName;
    if (brand.isNotEmpty) {
      _labelCtrl.text = '$typeName - $brand';
    } else {
      _labelCtrl.text = typeName;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a machinery type')),
      );
      return;
    }

    final selectedType = _selectedType!.typeName.trim().toLowerCase();
    if (selectedType == 'pump' || selectedType == 'turbine') {
      final existingMachinery = await _dao.getMachineryForSet(widget.setId);
      final conflictingType = selectedType == 'pump' ? 'turbine' : 'pump';
      final hasConflict = existingMachinery.any((m) {
        if (_isEdit && m.machineryId == widget.machinery?.machineryId) return false;
        return m.machineryType.trim().toLowerCase() == conflictingType;
      });

      if (hasConflict) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('A set cannot have both Pump and Turbine.')),
          );
        }
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      final specs = <String, String>{};
      for (final entry in _specControllers.entries) {
        if (entry.value.text.trim().isNotEmpty) {
          specs[entry.key] = entry.value.text.trim();
        }
      }

      if (_isEdit) {
        await _dao.updateMachinery(widget.machinery!.copyWith(
          machineryType: _selectedType!.typeName,
          brand: _brandCtrl.text.trim().isEmpty ? null : _brandCtrl.text.trim(),
          specs: specs,
          displayLabel: _labelCtrl.text.trim(),
        ));
      } else {
        final sortOrder = await _dao.getNextSortOrder(widget.setId);
        await _dao.insertMachinery(Machinery(
          setId: widget.setId,
          machineryType: _selectedType!.typeName,
          brand: _brandCtrl.text.trim().isEmpty ? null : _brandCtrl.text.trim(),
          specs: specs,
          displayLabel: _labelCtrl.text.trim(),
          sortOrder: sortOrder,
        ));
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _isEdit ? 'Edit Machinery' : 'Add Machinery',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else ...[
                // Type selector
                DropdownButtonFormField<MachineryType>(
                  value: _selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Machinery Type *',
                    border: OutlineInputBorder(),
                  ),
                  items: _types
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(t.typeName),
                          ))
                      .toList(),
                  onChanged: _onTypeChanged,
                  validator: (v) => v == null ? 'Select a type' : null,
                ),
                const SizedBox(height: 12),

                // Brand
                AppTextField(
                  controller: _brandCtrl,
                  label: 'Brand / Make (optional)',
                  onChanged: (_) => _updateLabel(),
                ),
                const SizedBox(height: 12),

                // Dynamic attributes from machinery type
                if (_selectedType != null)
                  ..._selectedType!.attributes.map((attr) {
                    final ctrl = _specControllers[attr.name];
                    if (ctrl == null) return const SizedBox.shrink();
                    final useDropdown = _shouldUseDropdown(attr);
                    final options = _getAttributeOptions(attr);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: useDropdown && options.isNotEmpty
                          ? DropdownButtonFormField<String>(
                              value: ctrl.text.isEmpty ? null : ctrl.text,
                              decoration: InputDecoration(
                                labelText: '${attr.name}${attr.required ? ' *' : ''}',
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  tooltip: 'Add ${attr.name}',
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () => _addDropdownOption(attr),
                                ),
                              ),
                              items: options
                                  .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                                  .toList(),
                              onChanged: (v) => ctrl.text = v ?? '',
                              validator: attr.required ? (v) => v == null ? 'Required' : null : null,
                            )
                          : AppTextField(
                              controller: ctrl,
                              label: '${attr.name}${attr.required ? ' *' : ''}',
                              keyboardType:
                                  attr.inputType == 'number' ? TextInputType.number : TextInputType.text,
                              validator: attr.required
                                  ? (v) => (v == null || v.isEmpty) ? 'Required' : null
                                  : null,
                            ),
                    );
                  }),

                // Display label
                AppTextField(
                  controller: _labelCtrl,
                  label: 'Display Label *',
                  validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 20),

                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_isEdit ? 'Update' : 'Add Machinery'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
