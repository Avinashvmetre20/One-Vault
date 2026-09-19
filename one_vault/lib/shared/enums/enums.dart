enum PasswordCategory {
  banking,
  email,
  socialMedia,
  shopping,
  work,
  development,
  servers,
  wifi,
  entertainment,
  other,
}

enum DocumentCategory {
  identity,
  employment,
  salary,
  tax,
  banking,
  insurance,
  education,
  property,
  vehicle,
  travel,
  legal,
  certificates,
  personal,
  other,
}

extension PasswordCategoryLabel on PasswordCategory {
  String get label => switch (this) {
    PasswordCategory.banking => 'Banking',
    PasswordCategory.email => 'Email',
    PasswordCategory.socialMedia => 'Social Media',
    PasswordCategory.shopping => 'Shopping',
    PasswordCategory.work => 'Work',
    PasswordCategory.development => 'Development',
    PasswordCategory.servers => 'Servers',
    PasswordCategory.wifi => 'Wi-Fi',
    PasswordCategory.entertainment => 'Entertainment',
    PasswordCategory.other => 'Other',
  };
}

extension DocumentCategoryLabel on DocumentCategory {
  String get label => switch (this) {
    DocumentCategory.identity => 'Identity',
    DocumentCategory.employment => 'Employment',
    DocumentCategory.salary => 'Salary',
    DocumentCategory.tax => 'Tax',
    DocumentCategory.banking => 'Banking',
    DocumentCategory.insurance => 'Insurance',
    DocumentCategory.education => 'Education',
    DocumentCategory.property => 'Property',
    DocumentCategory.vehicle => 'Vehicle',
    DocumentCategory.travel => 'Travel',
    DocumentCategory.legal => 'Legal',
    DocumentCategory.certificates => 'Certificates',
    DocumentCategory.personal => 'Personal',
    DocumentCategory.other => 'Other',
  };
}
