import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../db/customer_profile_repository.dart';
import '../models/customer_profile.dart';

/// Customer's profile — shown once, right after their first successful
/// email login (name required, phone optional, email locked), and
/// reachable anytime afterward via "Profil Saya" to view/edit, including
/// the profile photo.
class CustomerProfileScreen extends StatefulWidget {
  final String email;

  const CustomerProfileScreen({super.key, required this.email});

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  final _repo = CustomerProfileRepository();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _picker = ImagePicker();

  bool _loading = true;
  bool _saving = false;
  String? _existingPhotoBase64;
  File? _pickedPhoto;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    final existing = await _repo.getOnce(widget.email);
    if (existing != null) {
      _nameCtrl.text = existing.name;
      _phoneCtrl.text = existing.phone ?? '';
      _existingPhotoBase64 = existing.photoBase64;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  bool get _canSave => _nameCtrl.text.trim().isNotEmpty && !_saving;

  Future<void> _pickPhoto() async {
    // Kept small (max 400px wide, 70% JPEG quality) so the base64 string
    // comfortably fits inside a single Firestore document (1MB limit).
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 400,
      imageQuality: 70,
    );
    if (picked == null) return;
    setState(() => _pickedPhoto = File(picked.path));
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);

    String? photoBase64 = _existingPhotoBase64;
    if (_pickedPhoto != null) {
      final bytes = await _pickedPhoto!.readAsBytes();
      photoBase64 = base64Encode(bytes);
    }

    await _repo.save(CustomerProfile(
      email: widget.email,
      name: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      photoBase64: photoBase64,
    ));
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Lengkapi Profil')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    ImageProvider? avatarImage;
    if (_pickedPhoto != null) {
      avatarImage = FileImage(_pickedPhoto!);
    } else if (_existingPhotoBase64 != null) {
      avatarImage = MemoryImage(base64Decode(_existingPhotoBase64!));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Lengkapi Profil')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickPhoto,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: Colors.indigo.shade50,
                      backgroundImage: avatarImage,
                      child: avatarImage == null
                          ? const Icon(Icons.person, size: 48, color: Colors.indigo)
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.indigo,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text('Ketuk untuk ubah foto', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
            const SizedBox(height: 24),
            const Text(
              'Isi data diri kamu supaya pesanan lebih mudah dikenali.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nama',
                hintText: 'Nama lengkap kamu',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              enabled: false,
              controller: TextEditingController(text: widget.email),
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
                filled: true,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'No. Telepon (opsional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canSave ? _save : null,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Simpan'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
