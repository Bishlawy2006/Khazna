import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

class EmailService {
  static Future<bool> sendOtp({
    required String smtpHost,
    required int smtpPort,
    required String smtpEmail,
    required String smtpPassword,
    required String recipient,
    required String otpCode,
  }) async {
    try {
      final server = SmtpServer(
        smtpHost,
        port: smtpPort,
        username: smtpEmail,
        password: smtpPassword,
        ssl: smtpPort == 465,
        allowInsecure: false,
      );

      final message = Message()
        ..from = Address(smtpEmail, 'Khazna')
        ..recipients.add(recipient)
        ..subject = 'Khazna — Your login code: $otpCode'
        ..html = '''
<!DOCTYPE html>
<html>
<body style="margin:0;padding:32px;background:#F5F7FA;font-family:sans-serif;">
  <div style="max-width:400px;margin:auto;background:#fff;border-radius:16px;padding:32px;border:1px solid #E5E7EB;">
    <h2 style="color:#1A237E;margin:0 0 8px 0;">Khazna Login Code</h2>
    <p style="color:#6B7280;font-size:14px;margin:0 0 24px 0;">
      Use the code below to complete your sign-in.<br>
      It expires in <strong>10 minutes</strong>.
    </p>
    <div style="background:#F5F7FA;border-radius:12px;padding:20px;text-align:center;margin-bottom:24px;">
      <span style="font-size:38px;font-weight:bold;letter-spacing:12px;color:#1A237E;">$otpCode</span>
    </div>
    <p style="color:#9CA3AF;font-size:12px;margin:0;">
      If you didn't request this code, you can safely ignore this email.
    </p>
  </div>
</body>
</html>''';

      await send(message, server);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Sends a test email to verify SMTP credentials work.
  static Future<String?> testConnection({
    required String smtpHost,
    required int smtpPort,
    required String smtpEmail,
    required String smtpPassword,
    required String recipient,
  }) async {
    try {
      final server = SmtpServer(
        smtpHost,
        port: smtpPort,
        username: smtpEmail,
        password: smtpPassword,
        ssl: smtpPort == 465,
        allowInsecure: false,
      );

      final message = Message()
        ..from = Address(smtpEmail, 'Khazna')
        ..recipients.add(recipient)
        ..subject = 'Khazna — SMTP test successful'
        ..text =
            'Your email settings are working correctly. Khazna will use this address for login codes.';

      await send(message, server);
      return null; // null = success
    } on MailerException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }
}
