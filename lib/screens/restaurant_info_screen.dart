import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/restaurant_repository.dart';
import '../models/restaurant.dart';
import '../providers/auth_provider.dart';
import '../widgets/edit_action_bar.dart';
import '../widgets/logo_picker.dart';

/// Lets the Admin update this restaurant's category and address —
/// shown to customers at the top of their self-order screen once they
/// scan a table QR. The name itself is read-only here; only Super Admin
/// can rename a resto (via List Resto), since it's the resto's
/// identifying label across the whole platform.
///
/// Opens in view-only mode (all fields greyed out) — tap "Edit" to make
/// Kategori/Alamat editable, so nothing gets changed by accident just by
/// opening this screen.
class RestaurantInfoScreen extends StatefulWidget {
  const RestaurantInfoScreen({super.key});

  @override
  State<RestaurantInfoScreen> createState() => _RestaurantInfoScreenState();
}

class _RestaurantInfoScreenState extends State<RestaurantInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _repo = RestaurantRepository();
  bool _loading = true;
  bool _editing = false;
  /// Rates are Finance's to set (Mapping GL Account), not the Admin's —
  /// carried through unchanged so saving info here can't reset them.
  double _ppnPercent = 0;
  double _servicePercent = 0;

  bool _saving = false;

  /// Captured when Edit is tapped so Batal can restore it verbatim.
  Map<String, String?> _snapshot = const {};
  String? _selectedCategory;

  /// The logo is a single shared column — an Admin can replace or remove
  /// one uploaded by Super Admin, and vice versa.
  /// Carried through save untouched. Without it the upsert would default
  /// active back to true, letting an Admin silently reactivate a resto
  /// that Super Admin had switched off.
  bool _active = true;

  String? _existingLogo;
  File? _pickedLogo;
  bool _logoRemoved = false;
  File? _snapshotPickedLogo;
  String? _snapshotExistingLogo;
  bool _snapshotLogoRemoved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final restoId = context.read<AuthProvider>().restoId!;
    final resto = await _repo.getOnce(restoId);
    if (resto != null) {
      _nameCtrl.text = resto.name;
      _addressCtrl.text = resto.address;
      _ppnPercent = resto.ppnPercent;
      _servicePercent = resto.servicePercent;
      _phoneCtrl.text = resto.phone ?? '';
      _selectedCategory = resto.category;
      _existingLogo = resto.logoBase64;
      _active = resto.active;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _startEdit() {
    _snapshot = {
      'address': _addressCtrl.text,
      'phone': _phoneCtrl.text,
      'category': _selectedCategory,
    };
    _snapshotPickedLogo = _pickedLogo;
    _snapshotExistingLogo = _existingLogo;
    _snapshotLogoRemoved = _logoRemoved;
    setState(() => _editing = true);
  }

  void _cancelEdit() {
    _addressCtrl.text = _snapshot['address'] ?? '';
    _phoneCtrl.text = _snapshot['phone'] ?? '';
    _selectedCategory = _snapshot['category'];
    _pickedLogo = _snapshotPickedLogo;
    _existingLogo = _snapshotExistingLogo;
    _logoRemoved = _snapshotLogoRemoved;
    _formKey.currentState?.reset();
    setState(() => _editing = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final restoId = context.read<AuthProvider>().restoId!;
    setState(() => _saving = true);
    try {
      String? logoBase64 = _existingLogo;
      if (_pickedLogo != null) {
        logoBase64 = base64Encode(await _pickedLogo!.readAsBytes());
      } else if (_logoRemoved) {
        logoBase64 = null;
      }

      await _repo.update(Restaurant(
        id: restoId,
        name: _nameCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        ppnPercent: _ppnPercent,
        servicePercent: _servicePercent,
        category: _selectedCategory,
        logoBase64: logoBase64,
        active: _active,
      ));
      // Keep local state in step with what was just written, so a second
      // edit round doesn't re-upload or resurrect a removed logo.
      _existingLogo = logoBase64;
      _pickedLogo = null;
      _logoRemoved = false;
      if (!mounted) return;
      setState(() {
        _editing = false;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Info resto disimpan')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Info Resto'),
        actions: [
          if (!_loading && !_editing)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: _startEdit,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    TextFormField(
                      controller: _nameCtrl,
                      enabled: false,
                      decoration: const InputDecoration(
                        labelText: 'Nama Resto',
                        helperText: 'Cuma Super Admin yang bisa ubah nama resto',
                        filled: true,
                        fillColor: Color(0xFFEEEEEE),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedCategory,
                      decoration: InputDecoration(
                        labelText: 'Kategori Resto',
                        filled: !_editing,
                        fillColor: _editing ? null : const Color(0xFFEEEEEE),
                      ),
                      isExpanded: true,
                      items: kRestaurantCategories
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: _editing ? (value) => setState(() => _selectedCategory = value) : null,
                      validator: (v) => v == null ? 'Wajib dipilih' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _addressCtrl,
                      enabled: _editing,
                      decoration: InputDecoration(
                        labelText: 'Alamat',
                        filled: !_editing,
                        fillColor: _editing ? null : const Color(0xFFEEEEEE),
                      ),
                      maxLines: 2,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneCtrl,
                      enabled: _editing,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Nomor HP (opsional)',
                        helperText: 'Ditampilkan di struk',
                        filled: !_editing,
                        fillColor: _editing ? null : const Color(0xFFEEEEEE),
                      ),
                    ),
                    const SizedBox(height: 20),
                    LogoPicker(
                      existingBase64: _existingLogo,
                      picked: _pickedLogo,
                      removed: _logoRemoved,
                      enabled: _editing,
                      onChanged: ({File? picked, bool removed = false}) => setState(() {
                        _pickedLogo = picked;
                        _logoRemoved = removed;
                      }),
                    ),
                    const SizedBox(height: 24),
                    if (_editing)
                      EditActionBar(
                        onCancel: _cancelEdit,
                        onSave: _save,
                        saving: _saving,
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
