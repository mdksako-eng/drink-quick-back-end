// models/AppUser_model.dart
class AppUser {
  String username;
  String email;
  String password;
  String role;
  DateTime createdAt;
  Map<String, String> securityQuestions;

  AppUser({
    required this.username,
    required this.email,
    required this.password,
    required this.role,
    required this.createdAt,
    required this.securityQuestions,
  });

  Map<String, dynamic> toJson() => {
        'username': username,
        'email': email,
        'password': password,
        'role': role,
        'createdAt': createdAt.toIso8601String(),
        'securityQuestions': securityQuestions,
      };

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        username: json['username'],
        email: json['email'],
        password: json['password'],
        role: json['role'],
        createdAt: DateTime.parse(json['createdAt']),
        securityQuestions: Map<String, String>.from(json['securityQuestions']),
      );
}
