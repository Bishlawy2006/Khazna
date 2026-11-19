import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/transaction_model.dart';
import '../theme/app_theme.dart';
import '../widgets/analysis_charts.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  final _db = DatabaseHelper.instance;
  List<TransactionModel> _allTx = [];
  Map<String, double> _budgets = {}; // category → monthly limit
  bool _loading = true;

  // Month navigator: offset from current month (0 = this month, -1 = last, etc.)
  int _monthOffset = 0;

  // Chart option: 0 = Daily histogram, 1 = Trends (6 months + pace).
  int _chartView = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tx = await _db.getAllTransactions();
    final budgetList = await _db.getBudgets();
    if (mounted) {
      setState(() {
        _allTx = tx;
        _budgets = {for (final b in budgetList) b.category: b.monthlyLimit};
        _loading = false;
      });
    }
  }

  DateTime get _selectedMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month + _monthOffset);
  }

  List<TransactionModel> get _monthTx {
    final m = _selectedMonth;
    return _allTx.where((tx) {
      final d = DateTime.parse(tx.date);
      return d.year == m.year && d.month == m.month;
    }).toList();
  }

  List<TransactionModel> get _prevMonthTx {
    final m = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    return _allTx.where((tx) {
      final d = DateTime.parse(tx.date);
      return d.year == m.year && d.month == m.month;
    }).toList();
  }

  double get _totalIncome =>
      _monthTx.where((t) => t.type == 'income').fold(0.0, (s, t) => s + t.amount);

  double get _totalExpense =>
      _monthTx.where((t) => t.type == 'expense').fold(0.0, (s, t) => s + t.amount);

  double get _prevTotalExpense =>
      _prevMonthTx.where((t) => t.type == 'expense').fold(0.0, (s, t) => s + t.amount);

  Map<String, double> get _expenseByCategory {
    final map = <String, double>{};
    for (final tx in _monthTx.where((t) => t.type == 'expense')) {
      map[tx.category] = (map[tx.category] ?? 0) + tx.amount;
    }
    final sorted = Map.fromEntries(
      map.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
    return sorted;
  }

  Map<String, double> get _incomeByCategory {
    final map = <String, double>{};
    for (final tx in _monthTx.where((t) => t.type == 'income')) {
      map[tx.category] = (map[tx.category] ?? 0) + tx.amount;
    }
    final sorted = Map.fromEntries(
      map.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
    return sorted;
  }

  // ─── Chart data ────────────────────────────────────────

  static const _mon = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  int _daysIn(DateTime m) => DateTime(m.year, m.month + 1, 0).day;

  /// Expense per day for [m]; index 0 = day 1.
  List<double> _dailyExpenses(DateTime m) {
    final out = List<double>.filled(_daysIn(m), 0);
    for (final tx in _allTx) {
      if (tx.type != 'expense') continue;
      final d = DateTime.parse(tx.date);
      if (d.year == m.year && d.month == m.month) out[d.day - 1] += tx.amount;
    }
    return out;
  }

  /// Last day of [m] that has already happened.
  int _lastDay(DateTime m) {
    final now = DateTime.now();
    final isCurrent = m.year == now.year && m.month == now.month;
    return isCurrent ? now.day : _daysIn(m);
  }

  List<double> _cumulative(List<double> daily, int upTo) {
    final out = <double>[];
    var run = 0.0;
    for (var i = 0; i < upTo && i < daily.length; i++) {
      run += daily[i];
      out.add(run);
    }
    return out;
  }

  /// Income / expense totals for the six months ending at the selected one.
  List<MonthTotals> _lastSixMonths() {
    final sel = _selectedMonth;
    final result = <MonthTotals>[];
    for (var i = 5; i >= 0; i--) {
      final m = DateTime(sel.year, sel.month - i);
      var inc = 0.0, exp = 0.0;
      for (final tx in _allTx) {
        final d = DateTime.parse(tx.date);
        if (d.year != m.year || d.month != m.month) continue;
        if (tx.type == 'income') {
          inc += tx.amount;
        } else {
          exp += tx.amount;
        }
      }
      result.add(MonthTotals(_mon[m.month], inc, exp));
    }
    return result;
  }

  String _monthLabel(DateTime dt) {
    const months = ['', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'];
    return '${months[dt.month]} ${dt.year}';
  }

  String _shortMonth(DateTime dt) {
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Analysis', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  _buildMonthNavigator(),
                  _buildSummaryRow(),
                  if (_monthTx.isEmpty)
                    _buildEmpty()
                  else ...[
                    _buildVsLastMonth(),
                    _buildChartSection(),
                    if (_monthOffset == 0 && _budgets.isNotEmpty)
                      _buildBudgetOverview(),
                    _buildCategoryBreakdown('Expenses', _expenseByCategory, _totalExpense, AppColors.error, budgets: _budgets),
                    _buildCategoryBreakdown('Income Sources', _incomeByCategory, _totalIncome, AppColors.success),
                    _buildTopTransactions(),
                  ],
                ],
              ),
            ),
    );
  }

  // ─── Charts (option switch: Daily | Trends) ────────────

  Widget _buildChartSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: 0,
                icon: Icon(Icons.bar_chart_rounded, size: 18),
                label: Text('Daily'),
              ),
              ButtonSegment(
                value: 1,
                icon: Icon(Icons.show_chart_rounded, size: 18),
                label: Text('Trends'),
              ),
            ],
            selected: {_chartView},
            onSelectionChanged: (v) => setState(() => _chartView = v.first),
            style: SegmentedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.textSecondary,
              selectedBackgroundColor: AppColors.primary,
              selectedForegroundColor: Colors.white,
              minimumSize: const Size(0, 44),
            ),
          ),
          const SizedBox(height: 10),
          if (_chartView == 0) _buildDailyCard() else ..._buildTrendCards(),
        ],
      ),
    );
  }

  Widget _chartCard({
    required String title,
    required String subtitle,
    required Widget chart,
    Widget? legend,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: AppTextStyles.sectionTitle)),
              Text(subtitle, style: AppTextStyles.secondary),
            ],
          ),
          if (legend != null) ...[
            const SizedBox(height: 8),
            legend,
          ],
          const SizedBox(height: 10),
          chart,
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color color, {bool line = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: line ? 16 : 10,
          height: line ? 3 : 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(line ? 2 : 3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: AppTextStyles.secondary.copyWith(fontSize: 12)),
      ],
    );
  }

  Widget _buildDailyCard() {
    final m = _selectedMonth;
    final daily = _dailyExpenses(m);
    final last = _lastDay(m);
    var peak = 0.0;
    var peakDay = 0;
    for (var i = 0; i < last && i < daily.length; i++) {
      if (daily[i] > peak) {
        peak = daily[i];
        peakDay = i + 1;
      }
    }
    return _chartCard(
      title: 'Daily spending',
      subtitle: '${_mon[m.month]}, EGP',
      chart: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DailySpendChart(daily: daily, lastDay: last),
          if (peak > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Biggest day: $peakDay ${_mon[m.month]}, EGP ${_fmt(peak)}',
              style: AppTextStyles.secondary.copyWith(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildTrendCards() {
    final m = _selectedMonth;
    final prev = DateTime(m.year, m.month - 1);
    final curDaily = _dailyExpenses(m);
    final prevDaily = _dailyExpenses(prev);
    final cur = _cumulative(curDaily, _lastDay(m));
    final prv = _cumulative(prevDaily, prevDaily.length);

    return [
      _chartCard(
        title: 'Income vs spending',
        subtitle: 'Last 6 months, EGP',
        legend: Row(
          children: [
            _legendItem('Income', ChartColors.primary),
            const SizedBox(width: 16),
            _legendItem('Spending', ChartColors.secondary),
          ],
        ),
        chart: MonthlyBarsChart(months: _lastSixMonths()),
      ),
      _chartCard(
        title: 'Pace this month',
        subtitle: 'Cumulative, EGP',
        legend: Row(
          children: [
            _legendItem(_mon[m.month], ChartColors.primary, line: true),
            const SizedBox(width: 16),
            _legendItem(_mon[prev.month], ChartColors.previous, line: true),
          ],
        ),
        chart: PaceChart(
          current: cur,
          previous: prv,
          monthDays: curDaily.length,
          currentLabel: _mon[m.month],
          previousLabel: _mon[prev.month],
        ),
      ),
    ];
  }

  Widget _buildMonthNavigator() {
    final isCurrentMonth = _monthOffset == 0;
    return Container(
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white70),
            onPressed: () => setState(() => _monthOffset--),
          ),
          const SizedBox(width: 8),
          Text(
            _monthLabel(_selectedMonth),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.chevron_right,
                color: isCurrentMonth ? Colors.white24 : Colors.white70),
            onPressed: isCurrentMonth ? null : () => setState(() => _monthOffset++),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow() {
    final net = _totalIncome - _totalExpense;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _summaryCard('Income', _totalIncome, AppColors.success, Icons.arrow_downward_rounded),
          const SizedBox(width: 8),
          _summaryCard('Expenses', _totalExpense, AppColors.error, Icons.arrow_upward_rounded),
          const SizedBox(width: 8),
          _summaryCard('Net', net, net >= 0 ? AppColors.success : AppColors.error,
              net >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, double amount, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 14),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'EGP ${_fmt(amount)}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVsLastMonth() {
    final prev = _prevTotalExpense;
    final curr = _totalExpense;
    final prevMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);

    if (prev == 0 && curr == 0) return const SizedBox.shrink();

    final double change;
    final String changeText;
    if (prev == 0) {
      change = 1.0;
      changeText = 'No data for ${_shortMonth(prevMonth)}';
    } else {
      change = (curr - prev) / prev;
      final pct = (change.abs() * 100).toStringAsFixed(0);
      changeText = change >= 0
          ? 'Spending up $pct% vs ${_shortMonth(prevMonth)}'
          : 'Spending down $pct% vs ${_shortMonth(prevMonth)}';
    }

    final isUp = curr >= prev;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            Icon(
              isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              color: isUp ? AppColors.error : AppColors.success,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                changeText,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isUp ? AppColors.error : AppColors.success,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBudgetOverview() {
    int onTrack = 0, near = 0, over = 0;
    double totalBudget = 0, totalSpent = 0;

    for (final entry in _budgets.entries) {
      final spent = _expenseByCategory[entry.key] ?? 0;
      final pct = spent / entry.value;
      totalBudget += entry.value;
      totalSpent += spent;
      if (pct > 1.0) { over++; }
      else if (pct > 0.75) { near++; }
      else { onTrack++; }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: AppShadows.card,
          border: over > 0
              ? Border.all(color: AppColors.error.withValues(alpha: 0.3))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Budget Overview', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (over > 0)
                  _statusChip('$over over', AppColors.error),
                if (near > 0) ...[
                  const SizedBox(width: 6),
                  _statusChip('$near near', AppColors.warning),
                ],
                if (onTrack > 0) ...[
                  const SizedBox(width: 6),
                  _statusChip('$onTrack ok', AppColors.success),
                ],
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: totalBudget > 0
                    ? (totalSpent / totalBudget).clamp(0.0, 1.0)
                    : 0,
                minHeight: 8,
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation<Color>(
                  totalSpent > totalBudget
                      ? AppColors.error
                      : totalSpent / totalBudget > 0.75
                          ? AppColors.warning
                          : AppColors.success,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('EGP ${_fmt(totalSpent)} spent',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text('of EGP ${_fmt(totalBudget)} total budget',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _buildCategoryBreakdown(
      String title, Map<String, double> data, double total, Color color,
      {Map<String, double> budgets = const {}}) {
    if (data.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.sectionTitle),
            const SizedBox(height: 12),
            ...data.entries.map((e) {
              final pctOfTotal = total > 0 ? e.value / total : 0.0;

              // Budget awareness (expenses only)
              final limit = budgets[e.key];
              final hasLimit = limit != null && limit > 0;
              final pctOfLimit = hasLimit ? e.value / limit : null;
              final isOver = pctOfLimit != null && pctOfLimit > 1.0;
              final isNear = pctOfLimit != null && pctOfLimit > 0.75 && !isOver;
              final barColor = isOver
                  ? AppColors.error
                  : isNear
                      ? AppColors.warning
                      : hasLimit
                          ? AppColors.success
                          : color;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Text(e.key,
                                  style: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w500)),
                              if (isOver) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.warning_amber_rounded,
                                    size: 14, color: AppColors.error),
                              ],
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'EGP ${_fmt(e.value)}',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: barColor),
                            ),
                            if (hasLimit)
                              Text(
                                'of EGP ${_fmt(limit)}',
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textSecondary),
                              ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 34,
                          child: Text(
                            '${(pctOfTotal * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: hasLimit
                            ? (pctOfLimit!).clamp(0.0, 1.0)
                            : pctOfTotal,
                        minHeight: 6,
                        backgroundColor: barColor.withValues(alpha: 0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(barColor),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTopTransactions() {
    final expenses = _monthTx.where((t) => t.type == 'expense').toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    final top = expenses.take(5).toList();
    if (top.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Top Expenses', style: AppTextStyles.sectionTitle),
            const SizedBox(height: 8),
            ...top.map((tx) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.arrow_upward_rounded,
                        color: AppColors.error, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tx.category,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        if (tx.note != null && tx.note!.isNotEmpty)
                          Text(tx.note!,
                              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Text('EGP ${_fmt(tx.amount)}',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.error)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Column(
        children: [
          Icon(Icons.bar_chart_rounded, size: 64,
              color: AppColors.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('No transactions in ${_monthLabel(_selectedMonth)}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text('Add some transactions to see your spending analysis.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13,
                  color: AppColors.textSecondary.withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  String _fmt(double v) => v.toStringAsFixed(2);
}
