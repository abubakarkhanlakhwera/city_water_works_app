class Scheme {
  final int? schemeId;
  final String schemeName;
  final String? description;
  final String createdAt;
  final String updatedAt;

  // Computed fields (not stored in DB)
  final int setCount;
  final double totalAmount;

  Scheme({
    this.schemeId,
    required this.schemeName,
    this.description,
    required this.createdAt,
    required this.updatedAt,
    this.setCount = 0,
    this.totalAmount = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      if (schemeId != null) 'scheme_id': schemeId,
      'scheme_name': schemeName,
      'description': description,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory Scheme.fromMap(Map<String, dynamic> map) {
    return Scheme(
      schemeId: map['scheme_id'] as int?,
      schemeName: map['scheme_name'] as String,
      description: map['description'] as String?,
      createdAt: map['created_at'] as String? ?? '',
      updatedAt: map['updated_at'] as String? ?? '',
      setCount: map['set_count'] as int? ?? 0,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Scheme copyWith({
    int? schemeId,
    String? schemeName,
    String? description,
    String? createdAt,
    String? updatedAt,
    int? setCount,
    double? totalAmount,
  }) {
    return Scheme(
      schemeId: schemeId ?? this.schemeId,
      schemeName: schemeName ?? this.schemeName,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      setCount: setCount ?? this.setCount,
      totalAmount: totalAmount ?? this.totalAmount,
    );
  }
}
