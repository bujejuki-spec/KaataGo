import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/transaction_repository.dart';
import '../models/transaction.dart';

/// One day's worth of transactions plus the totals used for the
/// per-day summary header (overall total + a breakdown per payment
/// method, e.g. how much was Tunai vs QRIS vs Transfer that day).
class _DayGroup {
  final DateTime day;
  final List<PosTransaction> transactions;
  final int total;
  final Map<PaymentMethod, int> byMethod;

  _DayGroup(this.day, this.transactions)
      : total = transactions.fold(0, (sum, tx) => sum + tx.total),
        byMethod = {
          for (final m in PaymentMethod.values)
            m: transactions.where((tx) => tx.paymentMethod == m).fold(0, (s, tx) => s + tx.total),
        };
}

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  final _repo = TransactionRepository();
  List<PosTransaction> _transactions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final txs = await _repo.getAll();
    setState(() {
      _transactions = txs;
      _loading = false;
    });
  }

  String _paymentLabel(PaymentMethod m) {
    switch (m) {
      case PaymentMethod.cash:
        return 'Tunai';
      case PaymentMethod.qris:
        return 'QRIS';
      case PaymentMethod.transfer:
        return 'Transfer';
    }
  }

  List<_DayGroup> _groupByDay(List<PosTransaction> txs) {
    final byDay = <DateTime, List<PosTransaction>>{};
    for (final tx in txs) {
      final day = DateTime(tx.createdAt.year, tx.createdAt.month, tx.createdAt.day);
      byDay.putIfAbsent(day, () => []).add(tx);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a)); // newest first
    return days.map((d) => _DayGroup(d, byDay[d]!)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final dayFmt = DateFormat('EEEE, dd MMM yyyy', 'id_ID');
    final timeFmt = DateFormat('HH:mm', 'id_ID');
    final groups = _groupByDay(_transactions);

    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat Transaksi')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _transactions.isEmpty
              ? const Center(child: Text('Belum ada transaksi.'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: groups.length,
                  itemBuilder: (context, i) {
                    final group = groups[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      clipBehavior: Clip.antiAlias,
                      child: ExpansionTile(
                        initiallyExpanded: i == 0,
                        title: Text(
                          dayFmt.format(group.day),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total: ${currency.format(group.total)}',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: PaymentMethod.values.where((m) => group.byMethod[m]! > 0).map((m) {
                                  return Chip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text(
                                      '${_paymentLabel(m)}: ${currency.format(group.byMethod[m])}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                        childrenPadding: const EdgeInsets.only(bottom: 8),
                        children: group.transactions.map((tx) {
                          return ListTile(
                            dense: true,
                            title: Text(currency.format(tx.total)),
                            subtitle: Text(
                              '${timeFmt.format(tx.createdAt)} • ${_paymentLabel(tx.paymentMethod)}',
                            ),
                            trailing: Text('${tx.items.length} item'),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
    );
  }
}
