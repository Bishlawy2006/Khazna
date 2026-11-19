import 'package:flutter_test/flutter_test.dart';
import 'package:khazna/models/bank_model.dart';
import 'package:khazna/services/bank_identifier.dart';
import 'package:khazna/services/notification_parser.dart';

// Real SMS formats (names, account digits sanitised).
const nbePurchase =
    'تم خصم 109 EGP  من بطاقة الخصم المباشر رقم ....  باستخدام Mobile Payment '
    'عند GUC - COPY MENSA 9  يوم 14/11/26  الساعه 12:26  المتاح 54.82EGP  '
    'للمزيد إتصل ب ١٩٦٢٣';

const mashreqCard =
    'Your Card ending with .... has been used at CIRCLE K TRED MORE for EGP 88.00';

const ipnSent =
    'قمت بتحويل لحظي من 6..5 بمبلغ 225.50 جم عبر IPN يوم 12-11-2026 '
    'الساعة 21:01 رقم المعاملة ebca3042 للمساعدة www.mashreq.com/mashreqipn';

const ipnReceived =
    'لقد استقبلت تحويل لحظي على  6..5 بمبلغ 1,250.00 جم عبر IPN من اسم المرسل '
    'يوم  11-11-2026 الساعة  20:19 رقم المعاملة 1727e69b '
    'للمساعدة www.mashreq.com/mashreqipn';

// Telda push alert (as shown by the app) and the sentence the Wallet
// "Transaction" automation rebuilds from Merchant + Amount.
const teldaPush =
    'You spent EGP 89 at German University in Cairo\nBalance: EGP 184.01';
const teldaWallet = 'Telda: You spent EGP EGP 89.00 at Guc - Copy Mensa 11';

void main() {
  group('NotificationParser', () {
    test('El Ahly card purchase', () {
      final tx = NotificationParser.parse(nbePurchase, accountId: 1)!;
      expect(tx.amount, 109);
      expect(tx.type, 'expense');
      expect(tx.category, 'Card Payment');
      expect(tx.date, '2026-11-14');
      expect(tx.note, 'GUC - COPY MENSA 9');
      expect(tx.time, '12:26');
      expect(tx.source, 'auto');
      expect(tx.rawNotification, 'nbe|109.0|2026-11-14|12:26|GUC - COPY MENSA 9');
    });

    test('Mashreq card purchase uses the receive time as date', () {
      final tx = NotificationParser.parse(mashreqCard,
          accountId: 2, receivedAt: DateTime(2026, 11, 15, 9, 30))!;
      expect(tx.amount, 88);
      expect(tx.type, 'expense');
      expect(tx.date, '2026-11-15');
      expect(tx.note, 'CIRCLE K TRED MORE');
      expect(tx.rawNotification, isNull); // no reference → never deduplicated
    });

    test('Instapay sent', () {
      final tx = NotificationParser.parse(ipnSent, accountId: 2)!;
      expect(tx.amount, 225.50);
      expect(tx.type, 'expense');
      expect(tx.category, 'Transfer');
      expect(tx.date, '2026-11-12');
      expect(tx.time, '21:01');
      expect(tx.rawNotification, 'ipn|ebca3042');
    });

    test('Instapay received (thousands separator, sender name)', () {
      final tx = NotificationParser.parse(ipnReceived, accountId: 2)!;
      expect(tx.amount, 1250.00);
      expect(tx.type, 'income');
      expect(tx.date, '2026-11-11');
      expect(tx.note, 'Instapay from اسم المرسل');
      expect(tx.rawNotification, 'ipn|1727e69b');
    });

    test('Telda push alert: amount, place, date and time', () {
      final tx = NotificationParser.parse(teldaPush,
          accountId: 4, receivedAt: DateTime(2026, 11, 19, 14, 16))!;
      expect(tx.amount, 89);
      expect(tx.type, 'expense');
      expect(tx.category, 'Card Payment');
      expect(tx.note, 'German University in Cairo');
      expect(tx.date, '2026-11-19');
      expect(tx.time, '14:16');
      expect(tx.source, 'auto');
      expect(tx.rawNotification,
          'telda|89.0|2026-11-19|14:16|German University in Cairo');
    });

    test('Telda sentence rebuilt by the Wallet automation', () {
      final tx = NotificationParser.parse(teldaWallet,
          accountId: 4, receivedAt: DateTime(2026, 11, 19, 14, 16))!;
      expect(tx.amount, 89);
      expect(tx.note, 'Guc - Copy Mensa 11');
      expect(tx.type, 'expense');
    });

    test('Telda: declined and foreign-currency alerts are rejected', () {
      expect(NotificationParser.parse('Declined • EGP 89.00', accountId: 4),
          isNull);
      expect(
          NotificationParser.parse(
              'Telda: Declined. You spent EGP 89 at GUC', accountId: 4),
          isNull);
      expect(NotificationParser.parse('You spent USD 5 at Amazon', accountId: 4),
          isNull);
    });

    test('Arabic-Indic digits and invisible bidi marks are handled', () {
      final tx = NotificationParser.parse(
        '‏تم خصم ١٠٩ EGP من بطاقة عند GUC يوم ١٤/١١/٢٦ الساعه ١٢:٢٦',
        accountId: 1,
      )!;
      expect(tx.amount, 109);
      expect(tx.date, '2026-11-14');
    });

    test('direction: paid vs received is never mixed up', () {
      // Money OUT
      for (final sms in [nbePurchase, mashreqCard, ipnSent, teldaPush]) {
        expect(NotificationParser.parse(sms, accountId: 1)!.type, 'expense',
            reason: sms);
      }
      // Money IN
      expect(NotificationParser.parse(ipnReceived, accountId: 1)!.type,
          'income');
    });

    test('a message that reads as both paid and received is rejected', () {
      expect(
          NotificationParser.parse('$ipnSent $ipnReceived', accountId: 1),
          isNull);
    });

    test('unrecognised or risky messages are rejected, not guessed', () {
      expect(NotificationParser.parse('EGP', accountId: 1), isNull);
      // foreign currency card purchase
      expect(
          NotificationParser.parse(
              'Your Card ending with 1234 has been used at SHOP for USD 88.00',
              accountId: 1),
          isNull);
      // fee message without a merchant
      expect(
          NotificationParser.parse(
              'تم خصم 5 EGP رسوم خدمة يوم 14/11/26 الساعه 12:26',
              accountId: 1),
          isNull);
      // impossible date
      expect(
          NotificationParser.parse(
              'قمت بتحويل لحظي من 6..5 بمبلغ 5.00 جم عبر IPN يوم 31-02-2026 '
              'الساعة 21:01 رقم المعاملة abc',
              accountId: 1),
          isNull);
    });
  });

  group('BankIdentifier', () {
    final banks = [
      BankModel(id: 1, name: 'El Ahly'),
      BankModel(id: 2, name: 'El Mashreq'),
      BankModel(id: 3, name: 'CIB'),
      BankModel(id: 4, name: 'Telda'),
    ];

    test('recognises each sample without a bank name in it', () {
      expect(BankIdentifier.matchBank(nbePurchase, banks)?.id, 1);
      expect(BankIdentifier.matchBank(mashreqCard, banks)?.id, 2);
      expect(BankIdentifier.matchBank(ipnSent, banks)?.id, 2);
      expect(BankIdentifier.matchBank(ipnReceived, banks)?.id, 2);
      expect(BankIdentifier.matchBank(teldaPush, banks)?.id, 4);
      expect(BankIdentifier.matchBank(teldaWallet, banks)?.id, 4);
    });

    test('tolerates different names the user may have typed', () {
      final alt = [BankModel(id: 7, name: 'NBE'), BankModel(id: 8, name: 'Mashreq')];
      expect(BankIdentifier.matchBank(nbePurchase, alt)?.id, 7);
      expect(BankIdentifier.matchBank(ipnSent, alt)?.id, 8);
    });

    test('does not match unrelated text or a hotline inside an amount', () {
      expect(BankIdentifier.matchBank('EGP', banks), isNull);
      expect(BankIdentifier.matchBank('Balance 119623.50 EGP', banks), isNull);
    });
  });
}
