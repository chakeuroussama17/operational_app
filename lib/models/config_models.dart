/// Data types for the admin "manage groups/parts/lines" API shared by all
/// three modules. A "group" is a DCM (Casting), Station (Secondary) or
/// Customer (Machining); Machining also has a flat, global list of Lines.
library;

/// Snapshot of one module's configured groups, their parts, and (Machining
/// only) the global line list.
class ConfigSnapshot {
  const ConfigSnapshot({
    required this.groups,
    required this.partsByGroup,
    this.lines = const [],
  });

  final List<String> groups;
  final Map<String, List<String>> partsByGroup;

  /// Machining only; empty for Casting/Secondary.
  final List<String> lines;

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
    final lines = (json['lines'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
    return ConfigSnapshot(
      groups: groups,
      partsByGroup: partsByGroup,
      lines: lines,
    );
  }
}
