import 'package:flutter/material.dart';

class BankCardWidget extends StatelessWidget {
  final String bankName;
  final String accountName;
  final double balance;

  const BankCardWidget({
    super.key,
    required this.bankName,
    required this.accountName,
    required this.balance,
  });

  String? get _cardImagePath {
    final lower = bankName.toLowerCase();
    if (lower.contains('ahly') ||
        lower.contains('national bank') ||
        lower.contains('nbe')) {
      return 'assets/images/cards/nbe_card.png';
    } else if (lower.contains('cib')) {
      return 'assets/images/cards/cib_card.png';
    } else if (lower.contains('telda')) {
      return 'assets/images/cards/telda_card.png';
    } else if (lower.contains('mashreq')) {
      return 'assets/images/cards/elmashreq_card.png';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = _cardImagePath;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: AspectRatio(
        aspectRatio: 1.586,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                // Background — card image or gradient fallback
                Positioned.fill(
                  child: imagePath != null
                      ? Image.asset(imagePath, fit: BoxFit.cover)
                      : Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF1A237E), Color(0xFF4A148C)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        ),
                ),
                // Dark gradient overlay so text is always readable
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.52),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.4, 1.0],
                      ),
                    ),
                  ),
                ),
                // Bank name top-right (only for generic gradient cards)
                if (imagePath == null)
                  Positioned(
                    top: 20,
                    right: 20,
                    child: Text(
                      bankName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                // Balance and account name — bottom-left
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        accountName,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'EGP ${balance.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
