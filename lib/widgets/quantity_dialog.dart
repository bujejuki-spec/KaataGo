import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/level_option.dart';
import '../models/product.dart';
import '../utils/tax_calculator.dart';
import 'dialog_actions.dart';

/// What [QuantityDialog] hands back once "Tambah ke Keranjang" is tapped:
/// the quantity, one chosen option per the product's level group (e.g.
/// spice/sugar level), and an optional free-text note — used by
/// customer/kasir/admin alike when adding a line to the cart.
class QuantityDialogResult {
  final int quantity;
  final Map<String, String> selectedLevels;
  final String? notes;

  const QuantityDialogResult({
    required this.quantity,
    required this.selectedLevels,
    this.notes,
  });
}

/// Popup shown when a product card is tapped: lets the cashier/customer
/// type/adjust the quantity, pick a level per variant group (e.g. Level
/// Pedas, Level Gula) the product offers, add an optional note, and see
/// the computed subtotal (qty × unit price) live before it's added to
/// the cart.
class QuantityDialog extends StatefulWidget {
  final Product product;
  final int initialQuantity;
  final Map<String, String>? initialLevels;
  final String? initialNotes;

  /// Resto's PPN rate — figures here must match the menu prices the
  /// customer just tapped, which are shown inclusive of PPN.
  final double ppnPercent;

  /// True when reopened on a line already in the cart. Changes the
  /// confirm label from "Tambah" to "Simpan" and offers a delete, so
  /// removing something you added by mistake doesn't require fiddling
  /// the quantity down to zero.
  final bool editing;

  const QuantityDialog({
    super.key,
    required this.product,
    this.initialQuantity = 1,
    this.initialLevels,
    this.initialNotes,
    this.ppnPercent = 0,
    this.editing = false,
  });

  @override
  State<QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<QuantityDialog> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _notesCtrl;
  int _quantity = 1;
  late Map<String, String> _selectedLevels;

  @override
  void initState() {
    super.initState();
    _quantity = widget.initialQuantity < 1 ? 1 : widget.initialQuantity;
    _qtyCtrl = TextEditingController(text: '$_quantity');
    _notesCtrl = TextEditingController(text: widget.initialNotes ?? '');
    // Default every level group to its first option so a selection is
    // always present without the pemesan needing to touch each dropdown.
    _selectedLevels = {
      for (final group in widget.product.levelGroups)
        group: widget.initialLevels?[group] ?? kLevelGroups[group]!.first,
    };
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _setQuantity(int value) {
    final maxQty = widget.product.stock;
    final clamped = value.clamp(1, maxQty < 1 ? 1 : maxQty);
    setState(() {
      _quantity = clamped;
      _qtyCtrl.text = '$_quantity';
      _qtyCtrl.selection = TextSelection.collapsed(offset: _qtyCtrl.text.length);
    });
  }

  int _withPpn(int amount) => menuPrice(
        amount,
        ppnPercent: widget.ppnPercent,
        ppnExempt: widget.product.ppnExempt,
      );

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    // Extra price from whichever level options are currently selected
    // (e.g. "Ukuran: Large") — added on top of the base price per item.
    final priceDelta = _selectedLevels.entries.fold(
      0,
      (sum, e) => sum + widget.product.priceDeltaFor(e.key, e.value),
    );
    // Priced the way the customer sees it on the menu: original + PPN.
    // The pre-tax figures are what gets stored on the order; this is
    // display only, so the dialog can't quote a different number than
    // the grid card the customer tapped.
    // Rounded on the combined figure, exactly as the cart does it, so
    // the subtotal shown here can't be a rupiah off what gets added.
    final unitPrice = _withPpn(widget.product.price + priceDelta);
    final shownBase = _withPpn(widget.product.price);
    final shownDelta = unitPrice - shownBase;
    final subtotal = unitPrice * _quantity;

    return AlertDialog(
      title: Text(widget.product.name),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.product.photoBase64 != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  base64Decode(widget.product.photoBase64!),
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            if (widget.product.photoBase64 != null) const SizedBox(height: 12),
            Text(
              priceDelta == 0
                  ? '${currency.format(shownBase)} / item • Stok: ${widget.product.stock}'
                  : '${currency.format(unitPrice)} / item (dasar ${currency.format(shownBase)} + ${currency.format(shownDelta)}) • Stok: ${widget.product.stock}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            if (widget.product.description != null && widget.product.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                widget.product.description!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13),
              ),
            ],
            if (widget.product.levelGroups.isNotEmpty) ...[
              const SizedBox(height: 16),
              for (final group in widget.product.levelGroups) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(group,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  value: _selectedLevels[group],
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: kLevelGroups[group]!
                      .map((opt) => DropdownMenuItem(value: opt, child: Text(opt)))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedLevels[group] = value);
                  },
                ),
                const SizedBox(height: 10),
              ],
            ],
            const SizedBox(height: 6),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Catatan (opsional)',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Contoh: tanpa bawang, pisah kuah, dll',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  icon: const Icon(Icons.remove),
                  onPressed: () => _setQuantity(_quantity - 1),
                ),
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: _qtyCtrl,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(border: InputBorder.none),
                    onChanged: (v) {
                      final parsed = int.tryParse(v);
                      if (parsed != null) _setQuantity(parsed);
                    },
                  ),
                ),
                IconButton.filledTonal(
                  icon: const Icon(Icons.add),
                  onPressed: () => _setQuantity(_quantity + 1),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Subtotal', style: TextStyle(fontSize: 16)),
                Text(
                  currency.format(subtotal),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DialogActions(
              confirmLabel: widget.editing ? 'Simpan Perubahan' : 'Tambah ke Keranjang',
              onConfirm: () => Navigator.of(context).pop(QuantityDialogResult(
                quantity: _quantity,
                selectedLevels: _selectedLevels,
                notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
              )),
              onCancel: () => Navigator.of(context).pop(),
            ),
            if (widget.editing)
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Hapus dari keranjang'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => Navigator.of(context).pop(
                  const QuantityDialogResult(quantity: 0, selectedLevels: {}),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
