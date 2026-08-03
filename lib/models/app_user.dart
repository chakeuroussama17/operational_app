/// A registered person from the Users tab. The sheet is the authority on who
/// they are and whether they're still allowed in — Firebase only proves the
/// email is real.
class AppUser {
  const AppUser({
    required this.email,
    required this.name,
    required this.employeeId,
    required this.status,
  });

  final String email;
  final String name;
  final String employeeId;
  final String status;

  bool get isActive => status.toLowerCase() == 'active';

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    email: (json['email'] ?? '').toString().trim(),
    name: (json['name'] ?? '').toString().trim(),
    employeeId: (json['employeeId'] ?? '').toString().trim(),
    status: (json['status'] ?? '').toString().trim(),
  );
}
