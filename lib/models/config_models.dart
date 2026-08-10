/// Data types for the admin "manage groups/parts/operations" API shared by
/// all three modules. A "group" is a DCM (Casting), Station (Secondary) or
/// Customer (Machining); Machining also has a flat, global list of operations.
library;

/// Snapshot of one module's configured groups, their parts, and (Machining
/// only) the global operation list.
class ConfigSnapshot {
  const ConfigSnapshot({
    required this.groups,
    required this.partsByGroup,
    this.operations = const [],
  });

  final List<String> groups;
  final Map<String, List<String>> partsByGroup;

  /// Machining only; empty for Casting/Secondary.
  final List<String> operations;

  factory ConfigSnapshot.fromJson(Map<String, dynamic> json) {
    final groups = (json['groups'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
    final rawParts = json['partsByGroup'] as Map<String, dynamic>? ?? const {};
    final partsByGroup = <String, List<String>>{
      for (final entry in rawParts.entries)
        entry.key: (entry.value as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
    };
    final operations = (json['operations'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
    return ConfigSnapshot(
      groups: groups,
      partsByGroup: partsByGroup,
      operations: operations,
    );
  }
}
