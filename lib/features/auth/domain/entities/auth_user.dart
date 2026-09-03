import 'package:equatable/equatable.dart';

enum AuthProvider { guest, google, apple }

class AuthUser extends Equatable {
  final String id;
  final String? displayName;
  final String? email;
  final String? photoUrl;
  final AuthProvider provider;

  const AuthUser({
    required this.id,
    required this.provider,
    this.displayName,
    this.email,
    this.photoUrl,
  });

  bool get isGuest => provider == AuthProvider.guest;

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'email': email,
    'photoUrl': photoUrl,
    'provider': provider.name,
  };

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final providerName = (json['provider'] as String?) ?? 'guest';
    final provider = AuthProvider.values.firstWhere(
      (p) => p.name == providerName,
      orElse: () => AuthProvider.guest,
    );
    return AuthUser(
      id: json['id'] as String,
      displayName: json['displayName'] as String?,
      email: json['email'] as String?,
      photoUrl: json['photoUrl'] as String?,
      provider: provider,
    );
  }

  @override
  List<Object?> get props => [id, displayName, email, photoUrl, provider];
}
