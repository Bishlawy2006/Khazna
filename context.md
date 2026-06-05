import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/bank_model.dart';
import '../models/account_model.dart';
import '../models/certificate_model.dart';
import '../models/transaction_model.dart';

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
    return await openDatabase(path, version: 1, onCreate: _createDB);
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
        FOREIGN KEY (accountId) REFERENCES accounts(id)
      )
    ''');
  }

  // ─── Banks ───────────────────────────────────────────

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
    // After calculating monthly interest...
  final double interest = cert.monthlyInterest;

  if (cert.depositAccountId == cert.accountId) {
    // El Mashreq style: compound into the certificate itself
    final currentBalance = await _getAccountBalance(cert.accountId);
    await updateAccountBalance(cert.accountId, currentBalance + interest);
  } else {
    // El Ahly style: deposit into the linked current account
    final currentBalance = await _getAccountBalance(cert.depositAccountId);
    await updateAccountBalance(cert.depositAccountId, currentBalance + interest);
  }

  // Log the transaction regardless
  await insertTransaction(TransactionModel(
    accountId: cert.depositAccountId,
    amount: interest,
    type: 'income',
    category: 'Interest',
    date: today,
    note: 'Auto interest from certificate',
  ));
    }


    Future<double> _getAccountBalance(int accountId) async {
    final db = await database;
    final result = await db.query('accounts',
        columns: ['balance'], where: 'id = ?', whereArgs: [accountId]);
    if (result.isEmpty) return 0.0;
    return result.first['balance'] as double;
  }

  Future<void> _processCertificate(
      CertificateModel cert, DateTime today) async {
    DateTime nextDate = DateTime.parse(cert.nextInterestDate);
    final maturityDate = DateTime.parse(cert.maturityDate);

    // Process all missed or due interest payments
    while (!nextDate.isAfter(today)) {
      if (nextDate.isAfter(maturityDate)) break;

      // Log interest as income on the deposit (current) account
      final tx = TransactionModel(
        accountId: cert.depositAccountId,
        amount: cert.monthlyInterest,
        type: 'income',
        category: 'Interest',
        date: nextDate.toIso8601String().substring(0, 10),
        note:
            'Auto: Certificate interest (${(cert.interestRate * 100).toStringAsFixed(0)}%)',
      );
      await insertTransaction(tx);

      // Advance to next interest date
      nextDate = DateTime(
        nextDate.year,
        nextDate.month + cert.frequencyMonths,
        nextDate.day,
      );
    }

    // Update certificate with new next interest date
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

    

}