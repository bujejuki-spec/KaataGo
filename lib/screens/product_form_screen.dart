import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/level_option.dart';
import '../models/product.dart';
import '../providers/category_provider.dart';
import '../providers/product_provider.dart';
import 'category_management_screen.dart';

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
    _priceCtrl = TextEditingController(text: p?.price.toString() ?? '');
    _stockCtrl = TextEditingController(text: p?.stock.toString() ?? '');
    _selectedCategory = p?.category;
    _existingPhotoBase64 = p?.photoBase64;
    _selectedLevelGroups = (p?.levelGroups ?? const []).toSet();
    for (final entry in kLevelGroups.entries) {
      _priceDeltaCtrls[entry.key] = {
        for (final option in entry.value)
          option: TextEditingController(
            text: '${p?.priceDeltaFor(entry.key, option) ?? 0}',
          ),
      };
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<ProductProvider>();
    final name = _nameCtrl.text.trim();
    final description = _descriptionCtrl.text.trim();
    final category = _selectedCategory!;
    final price = int.parse(_priceCtrl.text.trim());
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
            entry.key: int.tryParse(entry.value.text.trim()) ?? 0,
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
      ));
    }

    if (mounted) Navigator.of(context).pop();
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
      appBar: AppBar(title: Text(isEditing ? 'Edit Produk' : 'Tambah Produk')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Stack(
                children: [
                  GestureDetector(
                    onTap: _pickPhoto,
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
                  if (photoPreview != null)
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
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nama produk'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Deskripsi (opsional)',
                  alignLabelWithHint: true,
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
                  decoration: const InputDecoration(labelText: 'Kategori'),
                  items: categoryNames
                      .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                      .toList(),
                  onChanged: (value) => setState(() => _selectedCategory = value),
                  validator: (v) => v == null ? 'Wajib dipilih' : null,
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _priceCtrl,
                decoration: const InputDecoration(labelText: 'Harga (Rp)'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Wajib diisi';
                  if (int.tryParse(v.trim()) == null) return 'Harus angka';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _stockCtrl,
                decoration: const InputDecoration(labelText: 'Stok'),
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
                    onSelected: (value) => setState(() {
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
                                    keyboardType: const TextInputType.numberWithOptions(signed: true),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      prefixText: 'Rp ',
                                      border: OutlineInputBorder(),
                                      contentPadding:
                                          EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
              FilledButton(
                onPressed: categoryNames.isEmpty ? null : _save,
                child: const Text('Simpan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
