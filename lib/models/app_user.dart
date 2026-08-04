import '../config/constants.dart';

/// A registered person from the Users tab. The sheet is the authority on who
/// they are, which department they belong to, and whether they're still
/// allowed in — Firebase only proves the email.
class AppUser {
  const AppUser({
    required this.email,
    required this.name,
    required this.employeeId,
    required this.department,
    required this.status,
  });

  final String email;
  final String name;
  final String employeeId;

  /// "Casting" | "Secondary" | "Machining", or "All" for the admin. Blank on
  /// rows written before departments existed — those people are sent back to
  /// finish registering rather than being shown everything.
  final String department;
  final String status;

  bool get isActive => status.toLowerCase() == 'active';

  bool get isAdmin => email.trim().toLowerCase() == adminEmail;

  /// True once this account is confined to (or, for the admin, granted) a
  /// department. A blank one means registration never finished.
  bool get hasDepartment => isAdmin || department.trim().isNotEmpty;

  /// Whether this person may see and log a module ('casting', 'secondary',
  /// 'machining').
  bool canAccess(String module) {
    if (isAdmin) return true;
    final own = department.trim().toLowerCase();
    if (own == 'all') return true;
    return own.isNotEmpty && own == module.trim().toLowerCase();
  }

  /// The modules this person may work in, in display order.
  List<String> get allowedModules => [
    for (final department in departments)
      if (canAccess(department.toLowerCase())) department.toLowerCase(),
  ];

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    email: (json['email'] ?? '').toString().trim(),
    name: (json['name'] ?? '').toString().trim(),
    employeeId: (json['employeeId'] ?? '').toString().trim(),
    department: (json['department'] ?? '').toString().trim(),
    status: (json['status'] ?? '').toString().trim(),
  );
}
