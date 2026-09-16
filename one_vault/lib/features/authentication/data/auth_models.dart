class AuthUser {
  const AuthUser({
    required this.userId,
    required this.name,
    required this.email,
    this.phone,
  });

  final int userId;
  final String name;
  final String email;
  final String? phone;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final rawId = json['userId'] ?? json['user_id'] ?? json['id'];
    return AuthUser(
      userId: rawId is int ? rawId : int.parse(rawId.toString()),
      name: json['name'] as String,
      email: json['email'] as String,
      phone: json['phone'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'name': name,
      'email': email,
      if (phone != null) 'phone': phone,
    };
  }
}

class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
  });

  final String accessToken;
  final String refreshToken;

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
    );
  }
}

class AuthResult {
  const AuthResult({
    required this.user,
    required this.tokens,
  });

  final AuthUser user;
  final AuthTokens tokens;

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    return AuthResult(
      user: AuthUser.fromJson(data['user'] as Map<String, dynamic>),
      tokens: AuthTokens.fromJson(data['tokens'] as Map<String, dynamic>),
    );
  }
}

class AuthException implements Exception {
  const AuthException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
