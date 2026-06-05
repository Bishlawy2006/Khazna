class UserModel {
  final int? id;
  final String username;
  final String? email;
  final String passwordHash;
  final String salt;
  final int iterations;
  final bool twoFactorEnabled;
  final String? twoFactorMethod; // 'email' | 'totp'
  final String? totpSecret; // base32-encoded TOTP secret
  final String? smtpHost;
  final int? smtpPort;
  final String? smtpEmail;
  final String? smtpPassword;
  final String? smtpRecipient;
  final int failedLoginAttempts;
  final String? lockedUntil; // ISO 8601
  final String createdAt;

  const UserModel({
    this.id,
    required this.username,
    this.email,
    required this.passwordHash,
    required this.salt,
    this.iterations = 100000,
    this.twoFactorEnabled = false,
    this.twoFactorMethod,
    this.totpSecret,
    this.smtpHost,
    this.smtpPort,
    this.smtpEmail,
    this.smtpPassword,
    this.smtpRecipient,
    this.failedLoginAttempts = 0,
    this.lockedUntil,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'username': username,
        'email': email,
        'passwordHash': passwordHash,
        'salt': salt,
        'iterations': iterations,
        'twoFactorEnabled': twoFactorEnabled ? 1 : 0,
        'twoFactorMethod': twoFactorMethod,
        'totpSecret': totpSecret,
        'smtpHost': smtpHost,
        'smtpPort': smtpPort,
        'smtpEmail': smtpEmail,
        'smtpPassword': smtpPassword,
        'smtpRecipient': smtpRecipient,
        'failedLoginAttempts': failedLoginAttempts,
        'lockedUntil': lockedUntil,
        'createdAt': createdAt,
      };

  factory UserModel.fromMap(Map<String, dynamic> m) => UserModel(
        id: m['id'] as int?,
        username: m['username'] as String,
        email: m['email'] as String?,
        passwordHash: m['passwordHash'] as String,
        salt: m['salt'] as String,
        iterations: m['iterations'] as int? ?? 100000,
        twoFactorEnabled: (m['twoFactorEnabled'] as int? ?? 0) == 1,
        twoFactorMethod: m['twoFactorMethod'] as String?,
        totpSecret: m['totpSecret'] as String?,
        smtpHost: m['smtpHost'] as String?,
        smtpPort: m['smtpPort'] as int?,
        smtpEmail: m['smtpEmail'] as String?,
        smtpPassword: m['smtpPassword'] as String?,
        smtpRecipient: m['smtpRecipient'] as String?,
        failedLoginAttempts: m['failedLoginAttempts'] as int? ?? 0,
        lockedUntil: m['lockedUntil'] as String?,
        createdAt: m['createdAt'] as String,
      );

  UserModel copyWith({
    String? username,
    String? email,
    String? passwordHash,
    String? salt,
    int? iterations,
    bool? twoFactorEnabled,
    String? twoFactorMethod,
    bool clearTwoFactorMethod = false,
    String? totpSecret,
    bool clearTotpSecret = false,
    String? smtpHost,
    int? smtpPort,
    String? smtpEmail,
    String? smtpPassword,
    String? smtpRecipient,
    int? failedLoginAttempts,
    String? lockedUntil,
    bool clearLockedUntil = false,
  }) =>
      UserModel(
        id: id,
        username: username ?? this.username,
        email: email ?? this.email,
        passwordHash: passwordHash ?? this.passwordHash,
        salt: salt ?? this.salt,
        iterations: iterations ?? this.iterations,
        twoFactorEnabled: twoFactorEnabled ?? this.twoFactorEnabled,
        twoFactorMethod: clearTwoFactorMethod
            ? null
            : (twoFactorMethod ?? this.twoFactorMethod),
        totpSecret:
            clearTotpSecret ? null : (totpSecret ?? this.totpSecret),
        smtpHost: smtpHost ?? this.smtpHost,
        smtpPort: smtpPort ?? this.smtpPort,
        smtpEmail: smtpEmail ?? this.smtpEmail,
        smtpPassword: smtpPassword ?? this.smtpPassword,
        smtpRecipient: smtpRecipient ?? this.smtpRecipient,
        failedLoginAttempts: failedLoginAttempts ?? this.failedLoginAttempts,
        lockedUntil:
            clearLockedUntil ? null : (lockedUntil ?? this.lockedUntil),
        createdAt: createdAt,
      );
}
