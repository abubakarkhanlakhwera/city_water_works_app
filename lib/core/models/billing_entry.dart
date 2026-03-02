class BillingEntry {
  final int? entryId;
  final int machineryId;
  final int serialNo;
  final String entryDate; // DD-MM-YYYY
  final int? voucherNo;
  final double amount;
  final String? regPageNo;
  final String? notes;
  final String createdAt;
  final String updatedAt;

  // Joined fields for display
  final String? schemeName;
  final String? setLabel;
  final String? machineryLabel;

  BillingEntry({
    this.entryId,
    required this.machineryId,
    required this.serialNo,
    required this.entryDate,
    this.voucherNo,
    required this.amount,
    this.regPageNo,
    this.notes,
    this.createdAt = '',
    this.updatedAt = '',
    this.schemeName,
    this.setLabel,
    this.machineryLabel,
  });

  Map<String, dynamic> toMap() {
    return {
      if (entryId != null) 'entry_id': entryId,
      'machinery_id': machineryId,
      'serial_no': serialNo,
      'entry_date': entryDate,
      'voucher_no': voucherNo,
      'amount': amount,
      'reg_page_no': regPageNo,
      'notes': notes,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory BillingEntry.fromMap(Map<String, dynamic> map) {
    return BillingEntry(
      entryId: map['entry_id'] as int?,
      machineryId: map['machinery_id'] as int,
      serialNo: map['serial_no'] as int,
      entryDate: map['entry_date'] as String,
      voucherNo: map['voucher_no'] as int?,
      amount: (map['amount'] as num).toDouble(),
      regPageNo: map['reg_page_no'] as String?,
      notes: map['notes'] as String?,
      createdAt: map['created_at'] as String? ?? '',
      updatedAt: map['updated_at'] as String? ?? '',
      schemeName: map['scheme_name'] as String?,
      setLabel: map['set_label'] as String?,
      machineryLabel: map['display_label'] as String?,
    );
  }

  BillingEntry copyWith({
    int? entryId,
    int? machineryId,
    int? serialNo,
    String? entryDate,
    int? voucherNo,
    double? amount,
    String? regPageNo,
    String? notes,
    String? createdAt,
    String? updatedAt,
  }) {
    return BillingEntry(
      entryId: entryId ?? this.entryId,
      machineryId: machineryId ?? this.machineryId,
      serialNo: serialNo ?? this.serialNo,
      entryDate: entryDate ?? this.entryDate,
      voucherNo: voucherNo ?? this.voucherNo,
      amount: amount ?? this.amount,
      regPageNo: regPageNo ?? this.regPageNo,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
