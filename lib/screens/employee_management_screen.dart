import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme.dart';

import '../db/employee_repository.dart';
import '../db/restaurant_repository.dart';
import '../models/employee.dart';
import '../models/restaurant.dart';
import '../providers/auth_provider.dart';
import '../widgets/dialog_actions.dart';
import '../widgets/kotak_cari.dart';
import '../utils/field_rules.dart';
import '../widgets/app_toast.dart';
import '../widgets/responsive.dart';
import '../widgets/required_label.dart';

const _roleLabels = {
  'super_admin': 'KaataGo Admin',
  'owner': 'Owner',
  'admin': 'Admin',
  'kasir': 'Kasir',
  'chef': 'Chef',
  'finance': 'Finance',
};

const _roleColors = {
  'super_admin': Color(0xFF7C3AED),
  'owner': Color(0xFFD97706),
  'admin': Color(0xFF6366F1),
  'kasir': Color(0xFF0EA5E9),
  'chef': Color(0xFFF97316),
  'finance': Color(0xFF10B981),
};

/// Super Admin only: lists every employee across every restaurant, and
/// lets you add/edit/deactivate/remove any of them — this is the "insert
/// data employee" screen the app previously had no UI for at all (only
/// possible via the Supabase Dashboard directly).
class EmployeeManagementScreen extends StatefulWidget {
  const EmployeeManagementScreen({super.key});

  @override
  State<EmployeeManagementScreen> createState() => _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState extends State<EmployeeManagementScreen> {
  final _employeeRepo = EmployeeRepository();
  final _restaurantRepo = RestaurantRepository();
  List<Employee> _employees = [];
  List<Restaurant> _restaurants = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Merchant yang boleh dikelola orang yang sedang masuk.
  ///
  /// KaataGo Admin memegang semuanya. Owner dan Admin merchant hanya
  /// yang dipetakan ke mereka — dan itu bukan sekadar tampilan: RLS
  /// menegakkan hal yang sama lewat is_resto_employee, jadi menambah
  /// karyawan di resto orang lain ditolak server meskipun layarnya
  /// dipaksa menampilkannya.
  ///
  /// Disaring di sini juga supaya yang tidak berhak tidak pernah melihat
  /// pilihan yang pasti gagal. Menawarkan tombol yang selalu ditolak
  /// adalah cara memberi tahu orang bahwa aplikasinya rusak.
  bool _semuaMerchant = false;
  Set<String> _restoSaya = const {};

  Future<void> _load() async {
    setState(() => _loading = true);

    final auth = context.read<AuthProvider>();
    _semuaMerchant = auth.isSuperAdmin;
    _restoSaya = {
      ...auth.restoIds,
      if (auth.restoId != null) auth.restoId!,
    };

    final results = await Future.wait([
      _employeeRepo.getAll(),
      _restaurantRepo.getAll(),
    ]);
    if (!mounted) return;

    final semuaResto = results[1] as List<Restaurant>;
    final semuaKaryawan = results[0] as List<Employee>;

    setState(() {
      _restaurants = _semuaMerchant
          ? semuaResto
          : [for (final r in semuaResto) if (_restoSaya.contains(r.id)) r];
      _employees = _semuaMerchant
          ? semuaKaryawan
          : [
              for (final e in semuaKaryawan)
                // KaataGo Admin (restoId null) tidak pernah tampil di
                // sisi merchant: ia bukan karyawan resto mana pun, dan
                // tidak ada satu pun tindakan di sini yang berlaku
                // padanya.
                if (e.restoId != null && _restoSaya.contains(e.restoId)) e
            ];
      _loading = false;
    });
  }

  String _restoName(String? id) {
    if (id == null) return '—';
    final match = _restaurants.where((r) => r.id == id);
    return match.isEmpty ? id : match.first.name;
  }

  Future<void> _openForm({Employee? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EmployeeFormDialog(
        existing: existing,
        restaurants: _restaurants,
        bolehSuperAdmin: _semuaMerchant,
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(Employee e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus karyawan?'),
        content: Text('${e.email} akan kehilangan akses staff sepenuhnya.'),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          DialogActions(
            confirmLabel: 'Hapus',
            destructive: true,
            onConfirm: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _employeeRepo.delete(e.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kelola Karyawan')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Tambah Karyawan'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _employees.isEmpty
              ? const Center(child: Text('Belum ada karyawan.'))
              : Column(
                children: [
                  KotakCari(
                    controller: _cariCtrl,
                    petunjuk: 'Cari nama, email, NIP, peran, atau merchant',
                    onUbah: (v) => setState(() => _cari = v),
                  ),
                  if (_groupByResto().isEmpty)
                    Expanded(
                      child: Center(
                        child: Text(
                            'Tidak ada karyawan yang cocok dengan "$_cari".'),
                      ),
                    )
                  else
                  Expanded(
                  child: RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, kFabSafeBottom),
                    children: _groupByResto().entries.map((group) {
                      // Dibuka sendiri saat sedang mencari: yang
                      // mengetikkan sebuah nama ingin melihat orangnya,
                      // bukan nama kelompok yang harus diketuk dulu.
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        clipBehavior: Clip.antiAlias,
                        child: ExpansionTile(
                          key: PageStorageKey(
                              '${group.key}|${_cari.isEmpty}'),
                          initiallyExpanded: _cari.isNotEmpty,
                          leading: const Icon(Icons.storefront_outlined),
                          title: Text(group.key,
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${group.value.length} karyawan'),
                          children: group.value.map((e) => _EmployeeRow(
                                employee: e,
                                restoName: _restoName(e.restoId),
                                onEdit: () => _openForm(existing: e),
                                onDelete: () => _delete(e),
                              )).toList(),
                        ),
                      );
                    }).toList(),
                  ),
                  ),
                  ),
                ],
              ),
    );
  }

  /// Groups employees by restaurant name (Super Admins — no resto — get
  /// their own "Super Admin" group), each group sorted alphabetically by
  /// resto name with "Super Admin" pinned first.
  final _cariCtrl = TextEditingController();
  String _cari = '';

  @override
  void dispose() {
    _cariCtrl.dispose();
    super.dispose();
  }

  Map<String, List<Employee>> _groupByResto() {
    final byResto = <String, List<Employee>>{};
    for (final e in _employees) {
      // Nama, email, NIP, peran, dan nama restonya sekaligus. Yang
      // mencari seorang karyawan kadang cuma ingat emailnya, kadang cuma
      // ingat dia kasir di cabang mana.
      if (!cocokCari(_cari, [
        e.name,
        e.email,
        e.nip,
        _roleLabels[e.role] ?? e.role,
        _restoName(e.restoId),
      ])) {
        continue;
      }
      final key = e.restoId == null ? 'KaataGo Admin' : _restoName(e.restoId);
      byResto.putIfAbsent(key, () => []).add(e);
    }
    final sortedKeys = byResto.keys.toList()
      ..sort((a, b) {
        if (a == 'KaataGo Admin') return -1;
        if (b == 'KaataGo Admin') return 1;
        return a.compareTo(b);
      });
    return {for (final k in sortedKeys) k: byResto[k]!};
  }
}

class _EmployeeRow extends StatelessWidget {
  final Employee employee;
  final String restoName;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EmployeeRow({
    required this.employee,
    required this.restoName,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final e = employee;
    final color = _roleColors[e.role] ?? Colors.grey;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: e.active ? color : KaataTheme.borderOf(context),
        child: Icon(e.active ? Icons.person : Icons.person_off_outlined, color: Colors.white),
      ),
      title: Text(
        e.name.isEmpty ? e.email : e.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (e.name.isNotEmpty) Text(e.email, style: const TextStyle(fontSize: 12)),
            if (e.nip != null && e.nip!.isNotEmpty)
              Text('NIP: ${e.nip}', style: TextStyle(fontSize: 12, color: KaataTheme.mutedOf(context))),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _roleLabels[e.role] ?? e.role,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
                if (!e.active)
                  Text('nonaktif', style: TextStyle(color: Colors.red.shade400, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
      isThreeLine: e.name.isNotEmpty,
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'edit') onEdit();
          if (v == 'delete') onDelete();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(value: 'delete', child: Text('Hapus')),
        ],
      ),
    );
  }
}

class _EmployeeFormDialog extends StatefulWidget {
  final Employee? existing;
  final List<Restaurant> restaurants;

  /// Hanya KaataGo Admin yang boleh mengangkat KaataGo Admin baru.
  ///
  /// Peran itu tidak terikat merchant mana pun, jadi memberikannya
  /// berarti memberi akses ke seluruh merchant — dan tidak ada Owner
  /// yang berhak memutuskan itu untuk merchant orang lain.
  final bool bolehSuperAdmin;

  const _EmployeeFormDialog({
    this.existing,
    required this.restaurants,
    required this.bolehSuperAdmin,
  });

  @override
  State<_EmployeeFormDialog> createState() => _EmployeeFormDialogState();
}

class _EmployeeFormDialogState extends State<_EmployeeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _nipCtrl;
  late String _role;
  String? _restoId;
  late bool _active;
  final _repo = EmployeeRepository();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _emailCtrl = TextEditingController(text: e?.email ?? '');
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _nipCtrl = TextEditingController(text: e?.nip ?? '');
    _role = e?.role ?? 'kasir';
    _restoId = e?.restoId;
    // Satu merchant berarti tidak ada yang perlu dipilih. Dropdown
    // berisi satu pilihan yang wajib diisi cuma satu ketukan tambahan
    // yang jawabannya sudah pasti.
    if (_restoId == null && widget.restaurants.length == 1) {
      _restoId = widget.restaurants.first.id;
    }
    _active = e?.active ?? true;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    _nipCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // super_admin isn't scoped to a resto — every other role requires one.
    if (_role != 'super_admin' && _restoId == null) {
      showAppToast(context, 'Pilih merchant untuk role ini.');
      return;
    }

    setState(() => _saving = true);
    try {
      await _repo.upsert(Employee(
        // Baris yang sudah ada dikenali dari id-nya, jadi emailnya boleh
        // ikut berubah tanpa membuat orang baru.
        id: widget.existing?.id ?? '',
        email: _emailCtrl.text.trim().toLowerCase(),
        name: _nameCtrl.text.trim(),
        nip: _nipCtrl.text.trim().isEmpty ? null : _nipCtrl.text.trim(),
        role: _role,
        restoId: _role == 'super_admin' ? null : _restoId,
        active: _active,
      ));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Gagal menyimpan: $e', isError: true);
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return AlertDialog(
      title: Text(isEditing ? 'Edit Karyawan' : 'Tambah Karyawan'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(label: requiredLabel('Nama')),
                inputFormatters: nameFormatters,
                textCapitalization: TextCapitalization.words,
                validator: (v) => validateName(v, label: 'Nama'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nipCtrl,
                decoration: const InputDecoration(labelText: 'NIP (opsional)'),
                keyboardType: TextInputType.number,
                inputFormatters: nipFormatters,
                validator: validateNip,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                decoration: InputDecoration(
                  label: requiredLabel('Email Gmail'),
                  helperText: isEditing
                      ? 'Mengubahnya juga mengubah akun yang bisa login'
                      : 'Harus @gmail.com — login aplikasi lewat Google',
                ),
                keyboardType: TextInputType.emailAddress,
                inputFormatters: emailFormatters,
                validator: (v) => validateGmail(v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _role,
                decoration: InputDecoration(label: requiredLabel('Role')),
                items: _roleLabels.entries
                    .where((e) =>
                        widget.bolehSuperAdmin || e.key != 'super_admin')
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setState(() => _role = v!),
              ),
              const SizedBox(height: 12),
              if (_role != 'super_admin')
                DropdownButtonFormField<String>(
                  value: _restoId,
                  decoration: InputDecoration(label: requiredLabel('Merchant')),
                  items: widget.restaurants
                      .map((r) => DropdownMenuItem(value: r.id, child: Text(r.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _restoId = v),
                ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Aktif'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        DialogActions(
          confirmLabel: 'Simpan',
          busy: _saving,
          onConfirm: _save,
          onCancel: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}
