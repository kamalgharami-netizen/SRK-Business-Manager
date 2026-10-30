import 'package:flutter/material.dart';

import '../../data/local/app_database.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  List<Map<String, Object?>> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('products', orderBy: 'name COLLATE NOCASE');
    if (!mounted) return;
    setState(() {
      _products = rows;
      _loading = false;
    });
  }

  Future<void> _showProductForm({Map<String, Object?>? product}) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController(text: product?['name'] as String? ?? '');
    final sku = TextEditingController(text: product?['sku'] as String? ?? '');
    final unit = TextEditingController(text: product?['unit'] as String? ?? 'pcs');
    final hsnSac = TextEditingController(text: product?['hsn_sac'] as String? ?? '');
    final purchasePrice = TextEditingController(text: product == null ? '' : product['purchase_price'].toString());
    final salePrice = TextEditingController(text: product == null ? '' : product['sale_price'].toString());
    final stock = TextEditingController(text: product == null ? '0' : product['current_stock'].toString());
    final gstRate = TextEditingController(text: product == null ? '0' : product['gst_rate'].toString());

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(product == null ? 'Add product' : 'Edit product'),
        content: SizedBox(
          width: 440,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Product name *'),
                    validator: (value) => value == null || value.trim().isEmpty ? 'Enter a product name' : null,
                  ),
                  TextFormField(controller: sku, decoration: const InputDecoration(labelText: 'SKU / Code')),
                  TextFormField(controller: hsnSac, decoration: const InputDecoration(labelText: 'HSN / SAC Code'), textCapitalization: TextCapitalization.characters),
                  TextFormField(
                    controller: unit,
                    decoration: const InputDecoration(labelText: 'Unit (pcs, kg, litre...)'),
                    validator: (value) => value == null || value.trim().isEmpty ? 'Enter a unit' : null,
                  ),
                  TextFormField(controller: purchasePrice, decoration: const InputDecoration(labelText: 'Purchase price'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: _nonNegativeNumber),
                  TextFormField(controller: salePrice, decoration: const InputDecoration(labelText: 'Sale price'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: _nonNegativeNumber),
                  TextFormField(controller: stock, decoration: const InputDecoration(labelText: 'Opening / current stock'), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: _nonNegativeNumber),
                  TextFormField(
                    controller: gstRate,
                    decoration: const InputDecoration(labelText: 'GST rate (%)'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      final parsed = double.tryParse(value ?? '');
                      if (parsed == null || parsed < 0 || parsed > 100) return 'Enter a GST rate between 0 and 100';
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(dialogContext, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == true) {
      final db = await AppDatabase.instance.database;
      final quantity = double.parse(stock.text.trim());
      final values = <String, Object?>{
        'name': name.text.trim(),
        'sku': sku.text.trim(),
        'unit': unit.text.trim(),
        'hsn_sac': hsnSac.text.trim().toUpperCase(),
        'purchase_price': double.parse(purchasePrice.text.trim().isEmpty ? '0' : purchasePrice.text.trim()),
        'sale_price': double.parse(salePrice.text.trim().isEmpty ? '0' : salePrice.text.trim()),
        'current_stock': quantity,
        'opening_stock': product == null ? quantity : (product['opening_stock'] as num).toDouble(),
        'gst_rate': double.parse(gstRate.text.trim()),
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (product == null) {
        await db.insert('products', values);
      } else {
        await db.update('products', values, where: 'id = ?', whereArgs: [product['id']]);
      }
      await _loadProducts();
    }

    name.dispose();
    sku.dispose();
    unit.dispose();
    hsnSac.dispose();
    purchasePrice.dispose();
    salePrice.dispose();
    stock.dispose();
    gstRate.dispose();
  }

  String? _nonNegativeNumber(String? value) {
    final parsed = double.tryParse(value ?? '');
    if (parsed == null || parsed < 0) return 'Enter a valid non-negative number';
    return null;
  }

  Future<void> _deleteProduct(Map<String, Object?> product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('Delete ${product['name']} from this device?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = await AppDatabase.instance.database;
    await db.delete('products', where: 'id = ?', whereArgs: [product['id']]);
    await _loadProducts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventory & Stock')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showProductForm,
        icon: const Icon(Icons.add_box_outlined),
        label: const Text('Add product'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _products.isEmpty
              ? const Center(child: Text('No products added yet. Tap Add product to begin.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  itemCount: _products.length,
                  separatorBuilder: (_, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final product = _products[index];
                    final quantity = (product['current_stock'] as num).toString();
                    final price = (product['sale_price'] as num).toStringAsFixed(2);
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
                      title: Text(product['name'] as String),
                      subtitle: Text('Stock: $quantity ${product['unit']} • Sale: ₹$price • HSN/SAC: ${product['hsn_sac'] ?? '—'}'),
                      onTap: () => _showProductForm(product: product),
                      trailing: IconButton(
                        tooltip: 'Delete product',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteProduct(product),
                      ),
                    );
                  },
                ),
    );
  }
}
