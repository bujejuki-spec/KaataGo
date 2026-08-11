/// Dari mana uang petty cash datang.
///
/// [incomeWithdrawal] dulu berarti "dari seluruh penghasilan", waktu
/// tunai dan non-tunai belum dibedakan. Baris lama dibiarkan apa adanya
/// dan sekarang dibaca sebagai Non Cash — menulis ulang riwayat justru
/// akan mengaku tahu sesuatu yang saat itu memang tidak tercatat.
enum PettyCashSource { manual, incomeWithdrawal, cashWithdrawal }

const _sourceDbValues = {
  PettyCashSource.manual: 'manual',
  PettyCashSource.incomeWithdrawal: 'income_withdrawal',
  PettyCashSource.cashWithdrawal: 'cash_withdrawal',
};

const kPettyCashSourceLabels = {
  PettyCashSource.manual: 'Top Up Manual',
  PettyCashSource.incomeWithdrawal: 'Withdraw dari Saldo Non Cash',
  PettyCashSource.cashWithdrawal: 'Withdraw dari Saldo Cash',
};

extension PettyCashSourceDb on PettyCashSource {
  String get dbValue => _sourceDbValues[this]!;

  static PettyCashSource fromDb(String? value) {
    return _sourceDbValues.entries
        .firstWhere((e) => e.value == value, orElse: () => const MapEntry(PettyCashSource.manual, ''))
        .key;
  }
}

/// A single top-up into the Petty Cash float — either a manual entry
/// (day-one cash before any income has come in) or a withdrawal moving
/// money out of Saldo Penghasilan. Never negative: there's no "usage"
/// entry yet, only funding — spending petty cash is still tracked the
/// same way as any other expense (see [Expense]).
class PettyCashEntry {
  final String id;
  final String restoId;
  final int amount;
  final PettyCashSource source;
  final String? description;
  final String createdBy;
  final DateTime createdAt;

  PettyCashEntry({
    required this.id,
    required this.restoId,
    required this.amount,
    required this.source,
    this.description,
    required this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'resto_id': restoId,
        'amount': amount,
        'source': source.dbValue,
        if (description != null) 'description': description,
        'created_by': createdBy,
      };

  factory PettyCashEntry.fromMap(Map<String, dynamic> map) {
    return PettyCashEntry(
      id: map['id'] as String,
      restoId: map['resto_id'] as String,
      amount: (map['amount'] as num).toInt(),
      source: PettyCashSourceDb.fromDb(map['source'] as String?),
      description: map['description'] as String?,
      createdBy: map['created_by'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
