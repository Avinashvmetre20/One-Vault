import '../enums/enums.dart';

class PasswordItem {
  PasswordItem({
    required this.id,
    required this.title,
    required this.username,
    required this.password,
    required this.website,
    required this.category,
    required this.notes,
    required this.tags,
    required this.updatedAt,
    DateTime? createdAt,
    this.isFavorite = false,
    this.version = 1,
    this.recoveryEmail = '',
    this.recoveryPhone = '',
    this.twoFactorMethod = '',
    this.backupCodes = '',
    this.securityNotes = '',
    this.domain = '',
    this.deletedAt,
  }) : createdAt = createdAt ?? updatedAt;

  final String id;
  final String title;
  final String username;
  final String password;
  final String website;
  final PasswordCategory category;
  final String notes;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isFavorite;
  final int version;
  final String recoveryEmail;
  final String recoveryPhone;
  final String twoFactorMethod;
  final String backupCodes;
  final String securityNotes;
  final String domain;
  final DateTime? deletedAt;

  PasswordItem copyWith({
    String? title,
    String? username,
    String? password,
    String? website,
    PasswordCategory? category,
    String? notes,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isFavorite,
    int? version,
    String? recoveryEmail,
    String? recoveryPhone,
    String? twoFactorMethod,
    String? backupCodes,
    String? securityNotes,
    String? domain,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return PasswordItem(
      id: id,
      title: title ?? this.title,
      username: username ?? this.username,
      password: password ?? this.password,
      website: website ?? this.website,
      category: category ?? this.category,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      version: version ?? this.version,
      recoveryEmail: recoveryEmail ?? this.recoveryEmail,
      recoveryPhone: recoveryPhone ?? this.recoveryPhone,
      twoFactorMethod: twoFactorMethod ?? this.twoFactorMethod,
      backupCodes: backupCodes ?? this.backupCodes,
      securityNotes: securityNotes ?? this.securityNotes,
      domain: domain ?? this.domain,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }

  Map<String, dynamic> toPayload() {
    return {
      'id': id,
      'title': title,
      'username': username,
      'password': password,
      'website': website,
      'category': category.name,
      'notes': notes,
      'tags': tags,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isFavorite': isFavorite,
      'version': version,
      'recoveryEmail': recoveryEmail,
      'recoveryPhone': recoveryPhone,
      'twoFactorMethod': twoFactorMethod,
      'backupCodes': backupCodes,
      'securityNotes': securityNotes,
      'domain': domain,
    };
  }

  factory PasswordItem.fromPayload(Map<String, dynamic> json) {
    final categoryName = json['category'] as String? ?? 'other';
    return PasswordItem(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      website: json['website'] as String? ?? '',
      category: PasswordCategory.values.firstWhere(
        (item) => item.name == categoryName,
        orElse: () => PasswordCategory.other,
      ),
      notes: json['notes'] as String? ?? '',
      tags: (json['tags'] as List?)?.map((item) => item.toString()).toList() ?? const [],
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      isFavorite: json['isFavorite'] == true,
      version: json['version'] is int ? json['version'] as int : 1,
      recoveryEmail: json['recoveryEmail'] as String? ?? '',
      recoveryPhone: json['recoveryPhone'] as String? ?? '',
      twoFactorMethod: json['twoFactorMethod'] as String? ?? '',
      backupCodes: json['backupCodes'] as String? ?? '',
      securityNotes: json['securityNotes'] as String? ?? '',
      domain: json['domain'] as String? ?? '',
    );
  }
}

class DocumentItem {
  DocumentItem({
    required this.id,
    required this.name,
    required this.category,
    required this.fileType,
    required this.sizeLabel,
    required this.createdAt,
    required this.tags,
    this.expiryDate,
    this.isFavorite = false,
  });

  final String id;
  final String name;
  final DocumentCategory category;
  final String fileType;
  final String sizeLabel;
  final DateTime createdAt;
  final DateTime? expiryDate;
  final List<String> tags;
  final bool isFavorite;
}

class PhotoItem {
  PhotoItem({
    required this.id,
    required this.name,
    required this.album,
    required this.createdAt,
    required this.sizeLabel,
    this.isFavorite = false,
    this.isPrivate = false,
  });

  final String id;
  final String name;
  final String album;
  final DateTime createdAt;
  final String sizeLabel;
  final bool isFavorite;
  final bool isPrivate;
}

class FileItem {
  FileItem({
    required this.id,
    required this.name,
    required this.folder,
    required this.fileType,
    required this.sizeLabel,
    required this.createdAt,
    this.isFavorite = false,
  });

  final String id;
  final String name;
  final String folder;
  final String fileType;
  final String sizeLabel;
  final DateTime createdAt;
  final bool isFavorite;
}

class AccountItem {
  AccountItem({
    required this.id,
    required this.name,
    required this.type,
    required this.balance,
  });

  final String id;
  final String name;
  final AccountType type;
  final double balance;
}

class TransactionItem {
  TransactionItem({
    required this.id,
    required this.amount,
    required this.date,
    required this.accountId,
    required this.category,
    required this.description,
    required this.type,
    required this.paymentMethod,
    required this.merchant,
  });

  final String id;
  final double amount;
  final DateTime date;
  final String accountId;
  final String category;
  final String description;
  final TransactionType type;
  final String paymentMethod;
  final String merchant;
}

class PersonalInfo {
  PersonalInfo({
    required this.name,
    required this.dateOfBirth,
    required this.phone,
    required this.email,
    required this.address,
    required this.emergencyContact,
    required this.bloodGroup,
    required this.nationality,
    required this.pan,
    required this.aadhaar,
    required this.passport,
    required this.drivingLicense,
    required this.company,
    required this.employeeId,
    required this.designation,
  });

  final String name;
  final DateTime dateOfBirth;
  final String phone;
  final String email;
  final String address;
  final String emergencyContact;
  final String bloodGroup;
  final String nationality;
  final String pan;
  final String aadhaar;
  final String passport;
  final String drivingLicense;
  final String company;
  final String employeeId;
  final String designation;

  PersonalInfo copyWith({
    String? name,
    DateTime? dateOfBirth,
    String? phone,
    String? email,
    String? address,
    String? emergencyContact,
    String? bloodGroup,
    String? nationality,
    String? pan,
    String? aadhaar,
    String? passport,
    String? drivingLicense,
    String? company,
    String? employeeId,
    String? designation,
  }) {
    return PersonalInfo(
      name: name ?? this.name,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      bloodGroup: bloodGroup ?? this.bloodGroup,
      nationality: nationality ?? this.nationality,
      pan: pan ?? this.pan,
      aadhaar: aadhaar ?? this.aadhaar,
      passport: passport ?? this.passport,
      drivingLicense: drivingLicense ?? this.drivingLicense,
      company: company ?? this.company,
      employeeId: employeeId ?? this.employeeId,
      designation: designation ?? this.designation,
    );
  }
}

class SecuritySettings {
  SecuritySettings({
    this.pinEnabled = false,
    this.pin = '',
    this.hideSensitiveData = true,
  });

  final bool pinEnabled;
  final String pin;
  final bool hideSensitiveData;

  SecuritySettings copyWith({
    bool? pinEnabled,
    String? pin,
    bool? hideSensitiveData,
  }) {
    return SecuritySettings(
      pinEnabled: pinEnabled ?? this.pinEnabled,
      pin: pin ?? this.pin,
      hideSensitiveData: hideSensitiveData ?? this.hideSensitiveData,
    );
  }
}
