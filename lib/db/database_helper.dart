import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/bank_model.dart';
import '../models/account_model.dart';
import '../models/certificate_model.dart';
import '../models/transaction_model.dart';
import '../models/activity_log_model.dart';
import '../models/budget_model.dart';
import '../models/essential_model.dart';
import '../models/user_model.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('khazna.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 6,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE banks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bankId INTEGER NOT NULL,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        balance REAL NOT NULL,
        FOREIGN KEY (bankId) REFERENCES banks(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE certificates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        accountId INTEGER NOT NULL,
        depositAccountId INTEGER NOT NULL,
        principal REAL NOT NULL,
        interestRate REAL NOT NULL,
        openedDate TEXT NOT NULL,
        maturityDate TEXT NOT NULL,
        nextInterestDate TEXT NOT NULL,
        frequencyMonths INTEGER NOT NULL,
        isMatured INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (accountId) REFERENCES accounts(id),
        FOREIGN KEY (depositAccountId) REFERENCES accounts(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        accountId INTEGER NOT NULL,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        category TEXT NOT NULL,
        date TEXT NOT NULL,
        note TEXT,
        source TEXT NOT NULL DEFAULT 'manual',
        rawNotification TEXT,
        FOREIGN KEY (accountId) REFERENCES accounts(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE activity_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        title TEXT NOT NULL,
        message TEXT NOT NULL,
        amount REAL,
        bankName TEXT,
        accountName TEXT,
        category TEXT,
        dateTime TEXT NOT NULL,
        type TEXT NOT NULL,
        isRead INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL,
        email TEXT,
        passwordHash TEXT NOT NULL,
        salt TEXT NOT NULL,
        iterations INTEGER NOT NULL DEFAULT 100000,
        twoFactorEnabled INTEGER NOT NULL DEFAULT 0,
        twoFactorMethod TEXT,
        totpSecret TEXT,
        smtpHost TEXT,
        smtpPort INTEGER,
        smtpEmail TEXT,
        smtpPassword TEXT,
        smtpRecipient TEXT,
        failedLoginAttempts INTEGER NOT NULL DEFAULT 0,
        lockedUntil TEXT,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE essentials (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        amount REAL NOT NULL,
        paidMonth TEXT,
        paidAccountId INTEGER,
        paidTransactionId INTEGER,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE budgets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL UNIQUE,
        monthlyLimit REAL NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE otp_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId INTEGER NOT NULL,
        codeHash TEXT NOT NULL,
        expiresAt TEXT NOT NULL,
        failedAttempts INTEGER NOT NULL DEFAULT 0,
        used INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (userId) REFERENCES users(id)
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          "ALTER TABLE transactions ADD COLUMN source TEXT NOT NULL DEFAULT 'manual'");
      await db.execute(
          "ALTER TABLE transactions ADD COLUMN rawNotification TEXT");
      await db.execute('''
        CREATE TABLE activity_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          action TEXT NOT NULL,
          title TEXT NOT NULL,
          message TEXT NOT NULL,
          amount REAL,
          bankName TEXT,
          accountName TEXT,
          category TEXT,
          dateTime TEXT NOT NULL,
          type TEXT NOT NULL,
          isRead INTEGER NOT NULL DEFAULT 0
        )
      ''');
    }
    if (oldVersion < 6) {
      await db.execute(
          'ALTER TABLE essentials ADD COLUMN paidAccountId INTEGER');
      await db.execute(
          'ALTER TABLE essentials ADD COLUMN paidTransactionId INTEGER');
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS essentials (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          amount REAL NOT NULL,
          paidMonth TEXT,
          paidAccountId INTEGER,
          paidTransactionId INTEGER,
          createdAt TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS budgets (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          category TEXT NOT NULL UNIQUE,
          monthlyLimit REAL NOT NULL,
          createdAt TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          username TEXT NOT NULL,
          email TEXT,
          passwordHash TEXT NOT NULL,
          salt TEXT NOT NULL,
          iterations INTEGER NOT NULL DEFAULT 100000,
          twoFactorEnabled INTEGER NOT NULL DEFAULT 0,
          twoFactorMethod TEXT,
          totpSecret TEXT,
          smtpHost TEXT,
          smtpPort INTEGER,
          smtpEmail TEXT,
          smtpPassword TEXT,
          smtpRecipient TEXT,
          failedLoginAttempts INTEGER NOT NULL DEFAULT 0,
          lockedUntil TEXT,
          createdAt TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE otp_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          userId INTEGER NOT NULL,
          codeHash TEXT NOT NULL,
          expiresAt TEXT NOT NULL,
          failedAttempts INTEGER NOT NULL DEFAULT 0,
          used INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (userId) REFERENCES users(id)
        )
      ''');
    }
  }

  // ─── Banks ────────────────────────────────────────────

  Future<int> insertBank(BankModel bank) async {
    final db = await database;
    return await db.insert('banks', bank.toMap());
  }

  Future<List<BankModel>> getAllBanks() async {
    final db = await database;
    final result = await db.query('banks');
    return result.map((m) => BankModel.fromMap(m)).toList();
  }

  // ─── Accounts ─────────────────────────────────────────

  Future<int> insertAccount(AccountModel account) async {
    final db = await database;
    return await db.insert('accounts', account.toMap());
  }

  Future<List<AccountModel>> getAccountsForBank(int bankId) async {
    final db = await database;
    final result = await db.query(
      'accounts',
      where: 'bankId = ?',
      whereArgs: [bankId],
    );
    return result.map((m) => AccountModel.fromMap(m)).toList();
  }

  Future<AccountModel?> getAccountById(int id) async {
    final db = await database;
    final result =
        await db.query('accounts', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return AccountModel.fromMap(result.first);
  }

  Future<int> updateAccountBalance(int id, double newBalance) async {
    final db = await database;
    return await db.update(
      'accounts',
      {'balance': newBalance},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ─── Certificates ─────────────────────────────────────

  Future<int> insertCertificate(CertificateModel cert) async {
    final db = await database;
    return await db.insert('certificates', cert.toMap());
  }

  Future<List<CertificateModel>> getAllCertificates() async {
    final db = await database;
    final result =
        await db.query('certificates', where: 'isMatured = ?', whereArgs: [0]);
    return result.map((m) => CertificateModel.fromMap(m)).toList();
  }

  Future<CertificateModel?> getCertificateByAccountId(int accountId) async {
    final db = await database;
    final result = await db.query(
      'certificates',
      where: 'accountId = ?',
      whereArgs: [accountId],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return CertificateModel.fromMap(result.first);
  }

  Future<int> updateCertificate(CertificateModel cert) async {
    final db = await database;
    return await db.update(
      'certificates',
      cert.toMap(),
      where: 'id = ?',
      whereArgs: [cert.id],
    );
  }

  // ─── Transactions ─────────────────────────────────────

  Future<int> insertTransaction(TransactionModel tx) async {
    final db = await database;
    final account = await getAccountById(tx.accountId);
    if (account != null) {
      final newBalance = tx.type == 'income'
          ? account.balance + tx.amount
          : account.balance - tx.amount;
      await updateAccountBalance(tx.accountId, newBalance);
    }
    return await db.insert('transactions', tx.toMap());
  }

  /// True if an auto-parsed transaction with this fingerprint already exists.
  /// (Auto-parsed rows store a fingerprint in rawNotification, never the SMS.)
  Future<bool> transactionFingerprintExists(String fingerprint) async {
    final db = await database;
    final rows = await db.query(
      'transactions',
      columns: ['id'],
      where: 'rawNotification = ?',
      whereArgs: [fingerprint],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<List<TransactionModel>> getTransactionsForAccount(
      int accountId) async {
    final db = await database;
    final result = await db.query(
      'transactions',
      where: 'accountId = ?',
      whereArgs: [accountId],
      orderBy: 'date DESC',
    );
    return result.map((m) => TransactionModel.fromMap(m)).toList();
  }

  // ─── Auto Interest ─────────────────────────────────────

  Future<void> processAllCertificateInterest() async {
    final certificates = await getAllCertificates(); // fetch all active certs
    final today = DateTime.now();

    for (final cert in certificates) {
      await _processCertificate(cert, today);
    }
  }

  Future<void> _processCertificate(
      CertificateModel cert, DateTime today) async {
    DateTime nextDate = DateTime.parse(cert.nextInterestDate);
    final maturityDate = DateTime.parse(cert.maturityDate);

    final bool isCompounding = cert.depositAccountId == cert.accountId;

    while (!nextDate.isAfter(today)) {
      if (nextDate.isAfter(maturityDate)) break;

      final double interest = cert.monthlyInterest;
      final String dateStr = nextDate.toIso8601String().substring(0, 10);

      if (isCompounding) {
        // El Mashreq: add interest directly to certificate balance
        // Do NOT use insertTransaction here because that would double-count.
        // We manually update the balance and just log the transaction row.
        final currentBalance = await _getAccountBalance(cert.accountId);
        await updateAccountBalance(cert.accountId, currentBalance + interest);

        final db = await database;
        await db.insert('transactions', {
          'accountId': cert.accountId,
          'amount': interest,
          'type': 'income',
          'category': 'Interest',
          'date': dateStr,
          'note':
              'Auto: Certificate interest (${(cert.interestRate * 100).toStringAsFixed(0)}%) — compounded',
        });
      } else {
        // El Ahly: deposit into linked current account via insertTransaction
        // insertTransaction handles the balance update automatically
        await insertTransaction(TransactionModel(
          accountId: cert.depositAccountId,
          amount: interest,
          type: 'income',
          category: 'Interest',
          date: dateStr,
          note:
              'Auto: Certificate interest (${(cert.interestRate * 100).toStringAsFixed(0)}%)',
        ));
      }

      // Advance to next interest date
      nextDate = DateTime(
        nextDate.year,
        nextDate.month + cert.frequencyMonths,
        nextDate.day,
      );
    }

    // Update certificate with new nextInterestDate and maturity status
    final isNowMatured = nextDate.isAfter(maturityDate);
    final updated = CertificateModel(
      id: cert.id,
      accountId: cert.accountId,
      depositAccountId: cert.depositAccountId,
      principal: cert.principal,
      interestRate: cert.interestRate,
      openedDate: cert.openedDate,
      maturityDate: cert.maturityDate,
      nextInterestDate: nextDate.toIso8601String().substring(0, 10),
      frequencyMonths: cert.frequencyMonths,
      isMatured: isNowMatured,
    );
    await updateCertificate(updated);
  }

  Future<double> _getAccountBalance(int accountId) async {
    final db = await database;
    final result = await db.query(
      'accounts',
      columns: ['balance'],
      where: 'id = ?',
      whereArgs: [accountId],
    );
    if (result.isEmpty) return 0.0;
    return result.first['balance'] as double;
  }

  // ─── Bank / Account management ────────────────────────

  Future<void> updateBankName(int id, String newName) async {
    final db = await database;
    await db.update('banks', {'name': newName},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteBank(int bankId) async {
    final db = await database;
    final accounts = await getAccountsForBank(bankId);
    for (final account in accounts) {
      await db.delete('transactions',
          where: 'accountId = ?', whereArgs: [account.id]);
      await db.delete('certificates',
          where: 'accountId = ?', whereArgs: [account.id]);
    }
    await db.delete('accounts',
        where: 'bankId = ?', whereArgs: [bankId]);
    await db.delete('banks', where: 'id = ?', whereArgs: [bankId]);
  }

  Future<void> deleteAccount(int accountId) async {
    final db = await database;
    await db.delete('transactions',
        where: 'accountId = ?', whereArgs: [accountId]);
    await db.delete('certificates',
        where: 'accountId = ?', whereArgs: [accountId]);
    await db.delete('accounts',
        where: 'id = ?', whereArgs: [accountId]);
  }

  // ─── Transaction Editing ───────────────────────────────

  Future<void> updateTransaction(
      TransactionModel oldTx, TransactionModel newTx) async {
    final db = await database;

    // Reverse old transaction's balance impact
    final oldAccount = await getAccountById(oldTx.accountId);
    if (oldAccount != null) {
      final restored = oldTx.type == 'income'
          ? oldAccount.balance - oldTx.amount
          : oldAccount.balance + oldTx.amount;
      await updateAccountBalance(oldTx.accountId, restored);
    }

    // Apply new transaction's balance impact
    final newAccount = await getAccountById(newTx.accountId);
    if (newAccount != null) {
      final applied = newTx.type == 'income'
          ? newAccount.balance + newTx.amount
          : newAccount.balance - newTx.amount;
      await updateAccountBalance(newTx.accountId, applied);
    }

    await db.update(
      'transactions',
      {
        'accountId': newTx.accountId,
        'amount': newTx.amount,
        'type': newTx.type,
        'category': newTx.category,
        'date': newTx.date,
        'note': newTx.note,
      },
      where: 'id = ?',
      whereArgs: [oldTx.id],
    );
  }

  Future<void> deleteTransaction(TransactionModel tx) async {
    final db = await database;

    final account = await getAccountById(tx.accountId);
    if (account != null) {
      final restored = tx.type == 'income'
          ? account.balance - tx.amount
          : account.balance + tx.amount;
      await updateAccountBalance(tx.accountId, restored);
    }

    await db.delete('transactions', where: 'id = ?', whereArgs: [tx.id]);
  }

  Future<TransactionModel?> getTransactionById(int id) async {
    final db = await database;
    final result =
        await db.query('transactions', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return TransactionModel.fromMap(result.first);
  }

  Future<List<TransactionModel>> getAllTransactions() async {
    final db = await database;
    final result = await db.query('transactions', orderBy: 'date DESC');
    return result.map((m) => TransactionModel.fromMap(m)).toList();
  }

  // ─── Activity Logs ────────────────────────────────────

  Future<int> logActivity(ActivityLogModel log) async {
    final db = await database;
    return await db.insert('activity_logs', log.toMap());
  }

  Future<List<ActivityLogModel>> getActivityLogs() async {
    final db = await database;
    final result =
        await db.query('activity_logs', orderBy: 'dateTime DESC');
    return result.map((m) => ActivityLogModel.fromMap(m)).toList();
  }

  Future<int> getUnreadActivityCount() async {
    final db = await database;
    final result = await db.query(
      'activity_logs',
      columns: ['COUNT(*) as count'],
      where: 'isRead = ?',
      whereArgs: [0],
    );
    if (result.isEmpty) return 0;
    return (result.first['count'] as int?) ?? 0;
  }

  Future<void> markAllActivityRead() async {
    final db = await database;
    await db.update('activity_logs', {'isRead': 1});
  }

  Future<void> clearActivityLogs() async {
    final db = await database;
    await db.delete('activity_logs');
  }

  // ─── Banks (extended) ─────────────────────────────────

  Future<BankModel?> getBankById(int id) async {
    final db = await database;
    final result =
        await db.query('banks', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return BankModel.fromMap(result.first);
  }

  // ─── Cash Account ──────────────────────────────────────

  // ─── Essentials ───────────────────────────────────────

  Future<List<EssentialModel>> getEssentials() async {
    final db = await database;
    final result = await db.query('essentials', orderBy: 'createdAt ASC');
    return result.map((m) => EssentialModel.fromMap(m)).toList();
  }

  Future<int> insertEssential(EssentialModel e) async {
    final db = await database;
    return await db.insert('essentials', e.toMap());
  }

  Future<void> updateEssential(EssentialModel e) async {
    final db = await database;
    await db.update('essentials', e.toMap(), where: 'id = ?', whereArgs: [e.id]);
  }

  Future<void> deleteEssential(int id) async {
    final db = await database;
    await db.delete('essentials', where: 'id = ?', whereArgs: [id]);
  }

  // ─── App Settings ──────────────────────────────────────

  Future<String?> getSetting(String key) async {
    final db = await database;
    final result = await db.query('app_settings', where: 'key = ?', whereArgs: [key]);
    if (result.isEmpty) return null;
    return result.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('app_settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ─── All account balances (for Essentials screen) ─────

  Future<double> getTotalBalance() async {
    final db = await database;
    final result = await db.rawQuery(
        "SELECT SUM(balance) as total FROM accounts WHERE type = 'current'");
    if (result.isEmpty) return 0.0;
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  // ─── Budgets ──────────────────────────────────────────

  Future<List<BudgetModel>> getBudgets() async {
    final db = await database;
    final result = await db.query('budgets', orderBy: 'category ASC');
    return result.map((m) => BudgetModel.fromMap(m)).toList();
  }

  Future<void> upsertBudget(BudgetModel budget) async {
    final db = await database;
    await db.insert('budgets', budget.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteBudget(int id) async {
    final db = await database;
    await db.delete('budgets', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Backup / Restore ─────────────────────────────────

  Future<Map<String, dynamic>> exportAllData() async {
    final db = await database;
    return {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'users': await db.query('users'),
      'banks': await db.query('banks'),
      'accounts': await db.query('accounts'),
      'certificates': await db.query('certificates'),
      'transactions': await db.query('transactions'),
      'activity_logs': await db.query('activity_logs'),
      'essentials': await db.query('essentials'),
      'budgets': await db.query('budgets'),
      'app_settings': await db.query('app_settings'),
    };
  }

  Future<void> importAllData(Map<String, dynamic> data) async {
    final db = await database;
    await db.transaction((txn) async {
      // Delete in FK-safe order
      await txn.delete('otp_sessions');
      await txn.delete('transactions');
      await txn.delete('certificates');
      await txn.delete('accounts');
      await txn.delete('banks');
      await txn.delete('users');
      await txn.delete('activity_logs');
      await txn.delete('essentials');
      await txn.delete('budgets');
      await txn.delete('app_settings');

      // Re-insert in FK-safe order, preserving original IDs
      for (final row in _rows(data, 'users')) {
        await txn.insert('users', row);
      }
      for (final row in _rows(data, 'banks')) {
        await txn.insert('banks', row);
      }
      for (final row in _rows(data, 'accounts')) {
        await txn.insert('accounts', row);
      }
      for (final row in _rows(data, 'certificates')) {
        await txn.insert('certificates', row);
      }
      for (final row in _rows(data, 'transactions')) {
        await txn.insert('transactions', row);
      }
      for (final row in _rows(data, 'activity_logs')) {
        await txn.insert('activity_logs', row);
      }
      for (final row in _rows(data, 'essentials')) {
        await txn.insert('essentials', row);
      }
      for (final row in _rows(data, 'budgets')) {
        await txn.insert('budgets', row);
      }
      for (final row in _rows(data, 'app_settings')) {
        await txn.insert('app_settings', row);
      }
    });
  }

  List<Map<String, dynamic>> _rows(Map<String, dynamic> data, String table) {
    final raw = data[table];
    if (raw == null) return [];
    return (raw as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // ─── Users ────────────────────────────────────────────

  Future<int> insertUser(UserModel user) async {
    final db = await database;
    return await db.insert('users', user.toMap());
  }

  Future<UserModel?> getUser() async {
    final db = await database;
    final result = await db.query('users', limit: 1);
    if (result.isEmpty) return null;
    return UserModel.fromMap(result.first);
  }

  Future<void> updateUser(UserModel user) async {
    final db = await database;
    await db.update('users', user.toMap(),
        where: 'id = ?', whereArgs: [user.id]);
  }

  // ─── OTP Sessions ─────────────────────────────────────

  Future<int> createOtpSession(int userId, String codeHash) async {
    final db = await database;
    final expiresAt = DateTime.now()
        .add(const Duration(minutes: 10))
        .toIso8601String();
    return await db.insert('otp_sessions', {
      'userId': userId,
      'codeHash': codeHash,
      'expiresAt': expiresAt,
      'failedAttempts': 0,
      'used': 0,
    });
  }

  Future<Map<String, dynamic>?> getActiveOtpSession(int userId) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final result = await db.query(
      'otp_sessions',
      where: 'userId = ? AND used = 0 AND expiresAt > ?',
      whereArgs: [userId, now],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (result.isEmpty) return null;
    return result.first;
  }

  Future<void> markOtpUsed(int sessionId) async {
    final db = await database;
    await db.update('otp_sessions', {'used': 1},
        where: 'id = ?', whereArgs: [sessionId]);
  }

  Future<void> incrementOtpFailedAttempts(int sessionId) async {
    final db = await database;
    await db.rawUpdate(
        'UPDATE otp_sessions SET failedAttempts = failedAttempts + 1 WHERE id = ?',
        [sessionId]);
  }

  Future<void> expireAllOtpSessions(int userId) async {
    final db = await database;
    await db.update('otp_sessions', {'used': 1},
        where: 'userId = ?', whereArgs: [userId]);
  }

  Future<AccountModel> ensureCashAccountExists() async {
    final db = await database;

    // Find or create Cash bank
    final bankRows =
        await db.query('banks', where: 'name = ?', whereArgs: ['Cash']);
    final int cashBankId;
    if (bankRows.isEmpty) {
      cashBankId = await insertBank(BankModel(name: 'Cash'));
    } else {
      cashBankId = bankRows.first['id'] as int;
    }

    // Find or create Cash Wallet account
    final accRows = await db.query(
      'accounts',
      where: 'bankId = ? AND name = ?',
      whereArgs: [cashBankId, 'Cash Wallet'],
    );
    if (accRows.isEmpty) {
      final id = await insertAccount(AccountModel(
        bankId: cashBankId,
        name: 'Cash Wallet',
        type: 'cash',
        balance: 0,
      ));
      return (await getAccountById(id))!;
    } else {
      return AccountModel.fromMap(accRows.first);
    }
  }
}