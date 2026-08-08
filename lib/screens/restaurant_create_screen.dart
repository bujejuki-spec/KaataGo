import 'package:flutter/material.dart';

import '../db/restaurant_repository.dart';
import '../models/restaurant.dart';

/// Super Admin only: creates a brand-new restaurant row (a new tenant),
/// or — when [existing] is passed — edits one (from the "List Resto"
/// screen). Regular Admins can edit their own resto's info
/// (RestaurantInfoScreen) but can't create new ones or edit others —
/// only Super Admin has that RLS privilege.
class RestaurantCreateScreen extends StatefulWidget {
  final Restaurant? existing;

  const RestaurantCreateScreen({super.key, this.existing});

  @override
  State<RestaurantCreateScreen> createState() => _RestaurantCreateScreenState();
}

class _RestaurantCreateScreenState extends State<RestaurantCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _idCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;
  String? _category;
  final _repo = RestaurantRepository();
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _idCtrl = TextEditingController(text: r?.id ?? '');
    _nameCtrl = TextEditingController(text: r?.name ?? '');
    _addressCtrl = TextEditingController(text: r?.address ?? '');
    _category = r?.category;
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  String? _slugify(String name) {
    final slug = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'(^-+)|(-+$)'), '');
    return slug.isEmpty ? null : slug;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final id = _idCtrl.text.trim();

    setState(() => _saving = true);
    try {
      if (!_isEditing) {
        final existing = await _repo.getOnce(id);
        if (existing != null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ID "$id" sudah dipakai resto lain, pakai ID lain.')),
          );
          setState(() => _saving = false);
          return;
        }
      }

      await _repo.save(Restaurant(
        id: id,
        name: _nameCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        category: _category,
        // Preserve the existing active/inactive status when editing —
        // that's managed separately via the switch on List Resto, not
        // this form.
        active: widget.existing?.active ?? true,
      ));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isEditing ? 'Resto "$id" diperbarui.' : 'Resto "$id" berhasil dibuat.')),
      );
      Navigator.of(context).pop();
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
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Resto' : 'Buat Resto Baru')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nama resto'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                onChanged: (v) {
                  if (_isEditing) return; // don't reshuffle an existing id
                  // Auto-fill a slug id from the name, but let the user
                  // still hand-edit it (e.g. if they want it shorter).
                  final auto = _slugify(v);
                  if (auto != null) _idCtrl.text = auto;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _idCtrl,
                enabled: !_isEditing, // id is the primary key — can't change once created
                decoration: const InputDecoration(
                  labelText: 'ID resto (unik, dipakai internal)',
                  helperText: 'Huruf kecil, angka, dan strip saja — misal: warung-bu-siti',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Wajib diisi';
                  if (!RegExp(r'^[a-z0-9][a-z0-9-]*$').hasMatch(v.trim())) {
                    return 'Cuma huruf kecil, angka, dan strip';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(labelText: 'Alamat'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Kategori (opsional)'),
                items: kRestaurantCategories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _category = v),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isEditing ? 'Simpan Perubahan' : 'Buat Resto'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
