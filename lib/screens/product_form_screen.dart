import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/level_option.dart';
import '../models/product.dart';
import '../providers/category_provider.dart';
import '../widgets/edit_action_bar.dart';
import '../providers/product_provider.dart';
import 'category_management_screen.dart';
import '../utils/rupiah_input.dart';
import '../utils/tax_calculator.dart';
import '../theme.dart';
import '../db/restaurant_repository.dart';
import '../providers/auth_provider.dart';
import '../utils/field_rules.dart';
import '../widgets/app_toast.dart';
import '../widgets/required_label.dart';

class ProductFormScreen extends StatefulWidget {
  final Product? existing;

  const ProductFormScreen({super.key, this.existing});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _stockCtrl;
  final _picker = ImagePicker();
  String? _selectedCategory;
  String? _existingPhotoBase64;
  File? _pickedPhoto;
  bool _photoRemoved = false;
  late Set<String> _selectedLevelGroups;
  /// Resto's PPN rate, loaded once so the form can preview the selling
  /// price. Nothing is stored with the product — only the original price
  /// is persisted, and PPN is applied wherever the price is shown.
  double _ppnPercent = 0;

  late bool _ppnExempt;
  late bool _serviceExempt;

  /// Adding a brand-new product has nothing to accidentally overwrite,
  /// so it starts directly editable. Editing an existing one opens
  /// view-only (all fields greyed) until "Edit" is tapped.
  late bool _editing;
  bool _saving = false;

  /// Everything Batal has to put back. Only populated for an existing
  /// product — for a new one, Batal just abandons the screen instead.
  Map<String, dynamic> _snapshot = const {};

  /// One price-delta controller per (group, option) — e.g. "Ukuran" →
  /// "Large" → "5000" means picking Large adds Rp 5.000 on top of the
  /// base price. Pre-built for every known option so toggling a group's
  /// chip on/off never loses what was typed.
  final Map<String, Map<String, TextEditingController>> _priceDeltaCtrls = {};

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _descriptionCtrl = TextEditingController(text: p?.description ?? '');
    _priceCtrl = TextEditingController(text: formatRupiahInput(p?.price));
    _stockCtrl = TextEditingController(text: p?.stock.toString() ?? '');
    _selectedCategory = p?.category;
    _existingPhotoBase64 = p?.photoBase64;
    _selectedLevelGroups = (p?.levelGroups ?? const []).toSet();
    _ppnExempt = p?.ppnExempt ?? false;
    _serviceExempt = p?.serviceExempt ?? false;
    _editing = widget.existing == null;
    for (final entry in kLevelGroups.entries) {
      _priceDeltaCtrls[entry.key] = {
        for (final option in entry.value)
          option: TextEditingController(
            text: formatRupiahInput(p?.priceDeltaFor(entry.key, option) ?? 0),
          ),
      };
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPpnRate());
  }

  Future<void> _loadPpnRate() async {
    final restoId = context.read<AuthProvider>().restoId;
    if (restoId == null) return;
    try {
      final resto = await RestaurantRepository().getOnce(restoId);
      if (!mounted || resto == null) return;
      setState(() => _ppnPercent = resto.ppnPercent);
    } catch (_) {
      // Offline — the preview just mirrors the original price.
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    for (final group in _priceDeltaCtrls.values) {
      for (final ctrl in group.values) {
        ctrl.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    // Kept small (max 500px wide, 70% JPEG quality) so the base64 string
    // stays a reasonable size in both local SQLite and Firestore.
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 500,
      imageQuality: 70,
    );
    if (picked == null) return;
    setState(() {
      _pickedPhoto = File(picked.path);
      _photoRemoved = false;
    });
  }

  void _removePhoto() {
    setState(() {
      _pickedPhoto = null;
      _existingPhotoBase64 = null;
      _photoRemoved = true;
    });
  }

  bool get _isEditingExisting => widget.existing != null;

  void _startEdit() {
    _snapshot = {
      'name': _nameCtrl.text,
      'description': _descriptionCtrl.text,
      'price': _priceCtrl.text,
      'stock': _stockCtrl.text,
      'category': _selectedCategory,
      'levelGroups': {..._selectedLevelGroups},
      'ppnExempt': _ppnExempt,
      'serviceExempt': _serviceExempt,
      'existingPhoto': _existingPhotoBase64,
      'pickedPhoto': _pickedPhoto,
      'photoRemoved': _photoRemoved,
      'deltas': {
        for (final g in _priceDeltaCtrls.entries)
          g.key: {for (final o in g.value.entries) o.key: o.value.text},
      },
    };
    setState(() => _editing = true);
  }

  void _cancelEdit() {
    // Creating a new product has no previous state to return to, so
    // cancelling means leaving the form entirely.
    if (!_isEditingExisting) {
      Navigator.of(context).pop();
      return;
    }

    _nameCtrl.text = _snapshot['name'] as String? ?? '';
    _descriptionCtrl.text = _snapshot['description'] as String? ?? '';
    _priceCtrl.text = _snapshot['price'] as String? ?? '';
    _stockCtrl.text = _snapshot['stock'] as String? ?? '';
    _selectedCategory = _snapshot['category'] as String?;
    _selectedLevelGroups = {...(_snapshot['levelGroups'] as Set<String>? ?? const {})};
    _ppnExempt = _snapshot['ppnExempt'] as bool? ?? false;
    _serviceExempt = _snapshot['serviceExempt'] as bool? ?? false;
    _existingPhotoBase64 = _snapshot['existingPhoto'] as String?;
    _pickedPhoto = _snapshot['pickedPhoto'] as File?;
    _photoRemoved = _snapshot['photoRemoved'] as bool? ?? false;
    final deltas = _snapshot['deltas'] as Map<String, Map<String, String>>? ?? const {};
    for (final g in _priceDeltaCtrls.entries) {
      for (final o in g.value.entries) {
        o.value.text = deltas[g.key]?[o.key] ?? '';
      }
    }
    _formKey.currentState?.reset();
    setState(() => _editing = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final provider = context.read<ProductProvider>();
    final name = _nameCtrl.text.trim();
    final description = _descriptionCtrl.text.trim();
    final category = _selectedCategory!;
    final price = parseRupiah(_priceCtrl.text)!;
    final stock = int.parse(_stockCtrl.text.trim());

    String? photoBase64 = _existingPhotoBase64;
    if (_pickedPhoto != null) {
      final bytes = await _pickedPhoto!.readAsBytes();
      photoBase64 = base64Encode(bytes);
    } else if (_photoRemoved) {
      photoBase64 = null;
    }

    final levelPrices = <String, Map<String, int>>{
      for (final group in _selectedLevelGroups)
        group: {
          for (final entry in _priceDeltaCtrls[group]!.entries)
            entry.key: parseRupiah(entry.value.text) ?? 0,
        },
    };

    if (widget.existing == null) {
      await provider.addProduct(
        name: name,
        category: category,
        price: price,
        stock: stock,
        description: description.isEmpty ? null : description,
        photoBase64: photoBase64,
        levelGroups: _selectedLevelGroups.toList(),
        levelPrices: levelPrices,
        ppnExempt: _ppnExempt,
        serviceExempt: _serviceExempt,
      );
    } else {
      await provider.updateProduct(widget.existing!.copyWith(
        name: name,
        category: category,
        price: price,
        stock: stock,
        description: description.isEmpty ? null : description,
        photoBase64: photoBase64,
        levelGroups: _selectedLevelGroups.toList(),
        levelPrices: levelPrices,
        ppnExempt: _ppnExempt,
        serviceExempt: _serviceExempt,
      ));
    }

    if (!mounted) return;
    if (widget.existing != null) {
      setState(() {
        _editing = false;
        _saving = false;
      });
      showAppToast(context, 'Produk disimpan');
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    final categories = context.watch<CategoryProvider>().categories;

    // If editing a product whose category was since deleted, keep it
    // selectable so saving without changing it doesn't silently fail.
    final categoryNames = categories.map((c) => c.name).toSet();
    if (_selectedCategory != null && !categoryNames.contains(_selectedCategory)) {
      categoryNames.add(_selectedCategory!);
    }

    ImageProvider? photoPreview;
    if (_pickedPhoto != null) {
      photoPreview = FileImage(_pickedPhoto!);
    } else if (_existingPhotoBase64 != null) {
      photoPreview = MemoryImage(base64Decode(_existingPhotoBase64!));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Produk' : 'Tambah Produk'),
        actions: [
          if (isEditing && !_editing)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: _startEdit,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Stack(
                children: [
                  GestureDetector(
                    onTap: _editing ? _pickPhoto : null,
                    child: Container(
                      height: 160,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                        image: photoPreview != null
                            ? DecorationImage(image: photoPreview, fit: BoxFit.cover)
                            : null,
                      ),
                      child: photoPreview == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_a_photo_outlined,
                                    size: 36, color: Colors.grey.shade500),
                                const SizedBox(height: 6),
                                Text('Tambah Foto Produk',
                                    style: TextStyle(color: Colors.grey.shade600)),
                              ],
                            )
                          : Align(
                              alignment: Alignment.bottomRight,
                              child: Container(
                                margin: const EdgeInsets.all(8),
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.edit, size: 16, color: Colors.white),
                              ),
                            ),
                    ),
                  ),
                  if (photoPreview != null && _editing)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: _removePhoto,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                value: !_ppnExempt,
                onChanged: _editing ? (v) => setState(() => _ppnExempt = !v) : null,
                title: const Text('Kena PPN'),
                subtitle: const Text('Matikan kalau produk ini dibebaskan PPN',
                    style: TextStyle(fontSize: 12)),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              SwitchListTile(
                value: !_serviceExempt,
                onChanged: _editing ? (v) => setState(() => _serviceExempt = !v) : null,
                title: const Text('Kena Biaya Service'),
                subtitle: const Text('Hanya berlaku untuk pesanan Dine In',
                    style: TextStyle(fontSize: 12)),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameCtrl,
                enabled: _editing,
                decoration: InputDecoration(
                  label: requiredLabel('Nama produk'),
                  filled: !_editing,
                  fillColor: _editing ? null : const Color(0xFFEEEEEE),
                ),
                inputFormatters: nameFormatters,
                textCapitalization: TextCapitalization.words,
                validator: (v) => validateName(v, label: 'Nama produk'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionCtrl,
                enabled: _editing,
                decoration: InputDecoration(
                  labelText: 'Deskripsi (opsional)',
                  alignLabelWithHint: true,
                  filled: !_editing,
                  fillColor: _editing ? null : const Color(0xFFEEEEEE),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              if (categoryNames.isEmpty)
                Card(
                  color: Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Belum ada kategori.'),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const CategoryManagementScreen()),
                          ),
                          child: const Text('Tambah Kategori Dulu'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  decoration: InputDecoration(
                    label: requiredLabel('Kategori'),
                    filled: !_editing,
                    fillColor: _editing ? null : const Color(0xFFEEEEEE),
                  ),
                  items: categoryNames
                      .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                      .toList(),
                  onChanged: _editing ? (value) => setState(() => _selectedCategory = value) : null,
                  validator: (v) => v == null ? 'Wajib dipilih' : null,
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _priceCtrl,
                enabled: _editing,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  label: requiredLabel('Harga Original (Rp)'),
                  helperText: 'Harga bersih, belum termasuk PPN',
                  filled: !_editing,
                  fillColor: _editing ? null : const Color(0xFFEEEEEE),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsInputFormatter()],
                validator: (v) {
                  if (parseRupiah(v ?? '') == null) return 'Wajib diisi, angka';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _SellingPricePreview(
                basePrice: parseRupiah(_priceCtrl.text) ?? 0,
                ppnPercent: _ppnPercent,
                ppnExempt: _ppnExempt,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _stockCtrl,
                enabled: _editing,
                decoration: InputDecoration(
                  label: requiredLabel('Stok'),
                  filled: !_editing,
                  fillColor: _editing ? null : const Color(0xFFEEEEEE),
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Wajib diisi';
                  if (int.tryParse(v.trim()) == null) return 'Harus angka';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              const Text('Level / Varian (opsional)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'Pilih level yang tersedia untuk produk ini — pemesan akan diminta memilih salah satu opsi per level.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: kLevelGroups.keys.map((group) {
                  final selected = _selectedLevelGroups.contains(group);
                  return FilterChip(
                    label: Text(group),
                    selected: selected,
                    onSelected: !_editing
                        ? null
                        : (value) => setState(() {
                              if (value) {
                                _selectedLevelGroups.add(group);
                              } else {
                                _selectedLevelGroups.remove(group);
                              }
                            }),
                  );
                }).toList(),
              ),
              for (final group in _selectedLevelGroups) ...[
                const SizedBox(height: 12),
                Card(
                  color: Colors.grey.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tambahan harga — $group',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                          'Kosongkan/0 kalau opsi itu tidak menambah harga dari harga dasar.',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                        ),
                        const SizedBox(height: 8),
                        for (final option in kLevelGroups[group]!)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(child: Text(option)),
                                SizedBox(
                                  width: 110,
                                  child: TextFormField(
                                    controller: _priceDeltaCtrls[group]![option],
                                    enabled: _editing,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [ThousandsInputFormatter()],
                                    decoration: InputDecoration(
                                      isDense: true,
                                      prefixText: 'Rp ',
                                      border: const OutlineInputBorder(),
                                      contentPadding:
                                          const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      filled: !_editing,
                                      fillColor: _editing ? null : const Color(0xFFEEEEEE),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              if (_editing)
                EditActionBar(
                  onCancel: _cancelEdit,
                  onSave: categoryNames.isEmpty ? null : _save,
                  saving: _saving,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The second price: what the customer actually sees on the menu.
///
/// Read-only on purpose — it's derived from the original price and the
/// resto's PPN rate, so letting it be edited would just create two
/// sources of truth that drift apart.
class _SellingPricePreview extends StatelessWidget {
  final int basePrice;
  final double ppnPercent;
  final bool ppnExempt;

  const _SellingPricePreview({
    required this.basePrice,
    required this.ppnPercent,
    required this.ppnExempt,
  });

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final selling = menuPrice(basePrice, ppnPercent: ppnPercent, ppnExempt: ppnExempt);
    final ppn = selling - basePrice;

    final String note;
    if (ppnExempt) {
      note = 'Produk ini dibebaskan PPN';
    } else if (ppnPercent <= 0) {
      note = 'Resto belum mengatur PPN';
    } else {
      note = 'Termasuk PPN ${formatPercent(ppnPercent)} (${currency.format(ppn)})';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: KaataTheme.brand.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KaataTheme.brand.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Harga Jual ke Customer',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              Text(
                currency.format(selling),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: KaataTheme.brandDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(note, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
          const SizedBox(height: 2),
          Text(
            'Biaya service ditambahkan saat checkout untuk pesanan Dine In.',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}
