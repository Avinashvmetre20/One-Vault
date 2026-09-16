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
    this.isFavorite = false,
  });

  final String id;
  final String title;
  final String username;
  final String password;
  final String website;
  final PasswordCategory category;
  final String notes;
  final List<String> tags;
  final DateTime updatedAt;
  final bool isFavorite;

  PasswordItem copyWith({
    String? title,
    String? username,
    String? password,
    String? website,
    PasswordCategory? category,
    String? notes,
    List<String>? tags,
    DateTime? updatedAt,
    bool? isFavorite,
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
      updatedAt: updatedAt ?? this.updatedAt,
      isFavorite: isFavorite ?? this.isFavorite,
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

class TodoItem {
  TodoItem({
    required this.id,
    required this.title,
    required this.description,
    required this.priority,
    required this.category,
    this.dueDate,
    this.completed = false,
  });

  final String id;
  final String title;
  final String description;
  final TodoPriority priority;
  final String category;
  final DateTime? dueDate;
  final bool completed;

  TodoItem copyWith({bool? completed}) {
    return TodoItem(
      id: id,
      title: title,
      description: description,
      priority: priority,
      category: category,
      dueDate: dueDate,
      completed: completed ?? this.completed,
    );
  }
}

class NoteItem {
  NoteItem({
    required this.id,
    required this.title,
    required this.content,
    required this.tags,
    required this.updatedAt,
    this.isPinned = false,
    this.isFavorite = false,
  });

  final String id;
  final String title;
  final String content;
  final List<String> tags;
  final DateTime updatedAt;
  final bool isPinned;
  final bool isFavorite;
}

class ReminderItem {
  ReminderItem({
    required this.id,
    required this.title,
    required this.dateTime,
    required this.recurrence,
    this.linkedTo,
    this.completed = false,
  });

  final String id;
  final String title;
  final DateTime dateTime;
  final ReminderRecurrence recurrence;
  final String? linkedTo;
  final bool completed;
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
