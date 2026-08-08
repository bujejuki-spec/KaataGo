import 'package:flutter/material.dart';

import '../db/employee_repository.dart';
import '../db/restaurant_repository.dart';
import '../models/employee.dart';
import '../models/restaurant.dart';

const _roleLabels = {
  'super_admin': 'Super Admin',
  'admin': 'Admin',
  'kasir': 'Kasir',
  'chef': 'Chef',
  'finance': 'Finance',
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

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _employeeRepo.getAll(),
      _restaurantRepo.getAll(),
    ]);
    if (!mounted) return;
    setState(() {
      _employees = results[0] as List<Employee>;
      _restaurants = results[1] as List<Restaurant>;
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
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _employeeRepo.delete(e.email);
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
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _employees.length,
                    itemBuilder: (context, i) {
                      final e = _employees[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: e.active ? null : Colors.grey.shade300,
                          child: Icon(e.active ? Icons.person : Icons.person_off_outlined),
                        ),
                        title: Text(e.email),
                        subtitle: Text(
                          '${_roleLabels[e.role] ?? e.role} • ${_restoName(e.restoId)}'
                          '${e.active ? '' : ' • nonaktif'}',
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'edit') _openForm(existing: e);
                            if (v == 'delete') _delete(e);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(value: 'delete', child: Text('Hapus')),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _EmployeeFormDialog extends StatefulWidget {
  final Employee? existing;
  final List<Restaurant> restaurants;

  const _EmployeeFormDialog({this.existing, required this.restaurants});

  @override
  State<_EmployeeFormDialog> createState() => _EmployeeFormDialogState();
}

class _EmployeeFormDialogState extends State<_EmployeeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailCtrl;
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
    _role = e?.role ?? 'kasir';
    _restoId = e?.restoId;
    _active = e?.active ?? true;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // super_admin isn't scoped to a resto — every other role requires one.
    if (_role != 'super_admin' && _restoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih resto untuk role ini.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _repo.upsert(Employee(
        email: _emailCtrl.text.trim().toLowerCase(),
        role: _role,
        restoId: _role == 'super_admin' ? null : _restoId,
        active: _active,
      ));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan: $e')),
      );
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
                controller: _emailCtrl,
                enabled: !isEditing, // email is the primary key — can't rename
                decoration: const InputDecoration(labelText: 'Email Gmail'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Wajib diisi';
                  if (!v.contains('@')) return 'Email tidak valid';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: _roleLabels.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setState(() => _role = v!),
              ),
              const SizedBox(height: 12),
              if (_role != 'super_admin')
                DropdownButtonFormField<String>(
                  value: _restoId,
                  decoration: const InputDecoration(labelText: 'Resto'),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Simpan'),
        ),
      ],
    );
  }
}
