import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/transaction_repository.dart';
import '../models/transaction.dart';

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

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final dateFmt = DateFormat('dd MMM yyyy, HH:mm', 'id_ID');

    // Simple reconciliation summary: total per payment method.
    final byMethod = <PaymentMethod, int>{};
    for (final tx in _transactions) {
      byMethod[tx.paymentMethod] = (byMethod[tx.paymentMethod] ?? 0) + tx.total;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat Transaksi')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _transactions.isEmpty
              ? const Center(child: Text('Belum ada transaksi.'))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: byMethod.entries.map((e) {
                          return Chip(
                            label: Text(
                                '${_paymentLabel(e.key)}: ${currency.format(e.value)}'),
                          );
                        }).toList(),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _transactions.length,
                        itemBuilder: (context, index) {
                          final tx = _transactions[index];
                          return ListTile(
                            title: Text(currency.format(tx.total)),
                            subtitle: Text(
                              '${dateFmt.format(tx.createdAt)} • ${_paymentLabel(tx.paymentMethod)}',
                            ),
                            trailing: Text('${tx.items.length} item'),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
