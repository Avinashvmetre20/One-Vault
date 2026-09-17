class EncryptedCredential {
  const EncryptedCredential({
    required this.id,
    required this.nonce,
    required this.encryptedPayload,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String nonce;
  final String encryptedPayload;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nonce': nonce,
      'encryptedPayload': encryptedPayload,
      'version': version,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'deletedAt': deletedAt?.toIso8601String(),
    };
  }

  factory EncryptedCredential.fromJson(Map<String, dynamic> json) {
    return EncryptedCredential(
      id: (json['id'] ?? json['credentialId'] ?? json['credential_id']).toString(),
      nonce: json['nonce'] as String,
      encryptedPayload:
          (json['encryptedPayload'] ?? json['encrypted_payload']) as String,
      version: json['version'] is int ? json['version'] as int : 1,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
    );
  }
}

class VaultMeta {
  const VaultMeta({
    required this.salt,
    required this.wrappedDek,
    required this.wrappedDekNonce,
    this.kdf = 'argon2id',
    this.kdfMemory = 8192,
    this.kdfIterations = 3,
    this.kdfParallelism = 1,
  });

  final String salt;
  final String wrappedDek;
  final String wrappedDekNonce;
  final String kdf;
  final int kdfMemory;
  final int kdfIterations;
  final int kdfParallelism;

  Map<String, dynamic> toJson() {
    return {
      'kdf': kdf,
      'kdfMemory': kdfMemory,
      'kdfIterations': kdfIterations,
      'kdfParallelism': kdfParallelism,
      'salt': salt,
      'wrappedDek': wrappedDek,
      'wrappedDekNonce': wrappedDekNonce,
    };
  }

  factory VaultMeta.fromJson(Map<String, dynamic> json) {
    return VaultMeta(
      kdf: json['kdf'] as String? ?? 'argon2id',
      kdfMemory: json['kdfMemory'] is int ? json['kdfMemory'] as int : 8192,
      kdfIterations: json['kdfIterations'] is int ? json['kdfIterations'] as int : 3,
      kdfParallelism: json['kdfParallelism'] is int ? json['kdfParallelism'] as int : 1,
      salt: json['salt'] as String,
      wrappedDek: (json['wrappedDek'] ?? json['wrapped_dek']) as String,
      wrappedDekNonce: (json['wrappedDekNonce'] ?? json['wrapped_dek_nonce']) as String,
    );
  }
}

class VaultSnapshot {
  const VaultSnapshot({this.meta, this.credentials = const []});

  final VaultMeta? meta;
  final List<EncryptedCredential> credentials;

  Map<String, dynamic> toJson() {
    return {
      'meta': meta?.toJson(),
      'credentials': credentials.map((item) => item.toJson()).toList(),
    };
  }

  factory VaultSnapshot.fromJson(Map<String, dynamic> json) {
    final metaJson = json['meta'];
    return VaultSnapshot(
      meta: metaJson is Map<String, dynamic> ? VaultMeta.fromJson(metaJson) : null,
      credentials: (json['credentials'] as List? ?? [])
          .whereType<Map>()
          .map((item) => EncryptedCredential.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }
}
