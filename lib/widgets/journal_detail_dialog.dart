import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/gl_journal_repository.dart';
import '../models/gl_journal_entry.dart';
import '../theme.dart';
import '../utils/id_time.dart';

/// Menampilkan seluruh baris jurnal GL yang lahir dari satu catatan.
///
/// Angka saldo yang berubah tanpa bisa ditelusuri adalah keluhan yang
/// paling sulit dijawab: yang terlihat cuma "petty cash berkurang", tanpa
/// akun mana yang didebit dan mana yang dikredit. Dialog ini membuka
/// pembukuan di balik satu baris, di tempat orangnya sedang melihat baris
/// itu — bukan menyuruhnya pindah ke layar Jurnal GL dan mencari sendiri.
Future<void> showJournalDetail(
  BuildContext context, {
  required String restoId,
  required String referenceId,
  required String title,
  String? subtitle,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _JournalDetailDialog(
      restoId: restoId,
      referenceId: referenceId,
      title: title,
      subtitle: subtitle,
    ),
  );
}

class _JournalDetailDialog extends StatefulWidget {
  final String restoId;
  final String referenceId;
  final String title;
  final String? subtitle;

  const _JournalDetailDialog({
    required this.restoId,
    required this.referenceId,
    required this.title,
    this.subtitle,
  });

  @override
  State<_JournalDetailDialog> createState() => _JournalDetailDialogState();
}

class _JournalDetailDialogState extends State<_JournalDetailDialog> {
  List<GlJournalEntry> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await GlJournalRepository().getForResto(widget.restoId);
      if (!mounted) return;
      setState(() {
        _entries = all.where((e) => e.referenceId == widget.referenceId).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final dateFmt = DateFormat('d MMM yyyy, HH:mm', 'id_ID');

    final debit = _entries
        .where((e) => e.entryType == JournalEntryType.debit)
        .fold<int>(0, (sum, e) => sum + e.amount);
    final credit = _entries
        .where((e) => e.entryType == JournalEntryType.credit)
        .fold<int>(0, (sum, e) => sum + e.amount);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: KaataTheme.brand.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.menu_book_outlined, color: KaataTheme.brand, size: 20),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5)),
                      if (widget.subtitle != null)
                        Text(widget.subtitle!,
                            style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text('Gagal memuat jurnal.\n$_error',
                    style: TextStyle(color: KaataTheme.mutedOf(context), fontSize: 13)),
              )
            else if (_entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Belum ada jurnal untuk catatan ini.\n'
                  'Biasanya karena akun GL-nya belum dipetakan di Mapping GL Account.',
                  style: TextStyle(color: KaataTheme.mutedOf(context), fontSize: 13),
                ),
              )
            else ...[
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [for (final e in _entries) _row(e, currency, dateFmt)],
                  ),
                ),
              ),
              const Divider(height: 20),
              Row(
                children: [
                  Expanded(child: _totalBox('Debit', debit, const Color(0xFF4F46E5), currency)),
                  const SizedBox(width: 8),
                  Expanded(child: _totalBox('Kredit', credit, const Color(0xFF10B981), currency)),
                ],
              ),
              if (debit != credit) ...[
                const SizedBox(height: 8),
                Text(
                  'Debit dan kredit belum seimbang — biasanya ada akun GL yang '
                  'belum dipetakan.',
                  style: TextStyle(fontSize: 11.5, color: Colors.orange.shade800),
                ),
              ],
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tutup'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(GlJournalEntry e, NumberFormat currency, DateFormat dateFmt) {
    final isDebit = e.entryType == JournalEntryType.debit;
    final color = isDebit ? const Color(0xFF4F46E5) : const Color(0xFF10B981);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: KaataTheme.softFillOf(context),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: KaataTheme.softFillOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              isDebit ? 'D' : 'K',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${e.glCode}${e.glName != null && e.glName!.isNotEmpty ? ' — ${e.glName}' : ''}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                if (e.description != null && e.description!.isNotEmpty)
                  Text(e.description!,
                      style: TextStyle(fontSize: 11.5, color: KaataTheme.mutedOf(context))),
                Text(dateFmt.format(e.createdAt.toWib()),
                    style: TextStyle(fontSize: 10.5, color: KaataTheme.mutedOf(context))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            currency.format(e.amount),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
              decoration: e.isReversal ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalBox(String label, int value, Color color, NumberFormat currency) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          Text(currency.format(value),
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
