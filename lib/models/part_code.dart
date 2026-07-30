/// One entry from the Parts master list (imported CSV), scoped to a module's
/// Department. Feeds the add-part dropdown: the user picks a [code]; [barcode]
/// (the CSV "Part number") and [name] are what the backend snapshots onto the
/// Config row and every logged data row.
class PartCode {
  const PartCode({required this.code, this.barcode, this.name});

  final String code;
  final String? barcode;
  final String? name;

  factory PartCode.fromJson(Map<String, dynamic> json) => PartCode(
    code: (json['code'] ?? '').toString().trim(),
    barcode: _clean(json['barcode']),
    name: _clean(json['name']),
  );

  static String? _clean(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty || s == 'null' ? null : s;
  }
}
