// screens/scanner_screen.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../models/drink_model.dart';
import '../models/inventory_model.dart';
import '../providers/drink_provider.dart';
import '../providers/inventory_provider.dart';
import '../services/barcode_service.dart';
import '../utils/currency_helper.dart';
import '../utils/helpers.dart';
import '../utils/i18n.dart';
import 'inventory_screen.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({Key? key}) : super(key: key);

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _torchOn = false;
  bool _handling = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleCode(String raw) async {
    if (_handling) return;
    _handling = true;
    final drinkProvider = Provider.of<DrinkProvider>(context, listen: false);
    final inventoryProvider =
        Provider.of<InventoryProvider>(context, listen: false);
    final match = BarcodeService.resolve(
      raw,
      drinks: drinkProvider.allDrinks,
      inventory: inventoryProvider.inventoryItems,
    );

    if (match != null) {
      await _showMatchSheet(match.drink, match.item);
    } else {
      if (mounted) Helpers.showToast(t('scanNotFound'));
      await Future.delayed(const Duration(seconds: 1));
    }
    _handling = false;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(t('scanTitle')),
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (BarcodeCapture capture) {
              for (final b in capture.barcodes) {
                final raw = b.rawValue ?? b.displayValue;
                if (raw != null && raw.isNotEmpty) {
                  _handleCode(raw);
                  break;
                }
              }
            },
            errorBuilder: (context, error) => _cameraError(error),
          ),
          _buildScanOverlay(primary),
        ],
      ),
    );
  }

  Widget _buildScanOverlay(Color primary) {
    return Stack(
      children: [
        Center(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: primary, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 40,
          child: Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(t('scanHint'),
                  style: const TextStyle(color: Colors.white)),
            ),
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Column(children: [
            _circleButton(
                _torchOn ? Icons.flash_off : Icons.flash_on, _toggleTorch),
            const SizedBox(height: 12),
            _circleButton(Icons.cameraswitch, _controller.switchCamera),
          ]),
        ),
      ],
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.black.withValues(alpha: 0.5),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }

  Future<void> _toggleTorch() async {
    await _controller.toggleTorch();
    if (mounted) setState(() => _torchOn = !_torchOn);
  }

  Widget _cameraError(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.no_photography, size: 60, color: Colors.grey),
          const SizedBox(height: 12),
          Text(t('scanCameraError'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
        ]),
      ),
    );
  }

  Future<void> _showMatchSheet(Drink drink, InventoryItem? item) async {
    await _controller.stop();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _buildDetailSheet(ctx, drink, item),
    );
    if (mounted) await _controller.start();
  }

  Widget _buildDetailSheet(
      BuildContext ctx, Drink drink, InventoryItem? item) {
    final inventoryProvider = Provider.of<InventoryProvider>(ctx, listen: false);
    final qty = item?.quantity ?? drink.currentStock;
    final minLevel = item?.minStockLevel ?? drink.minimumLevel;
    final low = qty <= minLevel;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const CircleAvatar(child: Icon(Icons.local_drink)),
            const SizedBox(width: 12),
            Expanded(
                child: Text(drink.name,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 8),
          Text(drink.category, style: TextStyle(color: Colors.grey[600])),
          Text(CurrencyHelper.format(drink.price),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: low
                  ? Colors.orange.withValues(alpha: 0.12)
                  : Colors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              Icon(low ? Icons.warning : Icons.check_circle,
                  color: low ? Colors.orange : Colors.green),
              const SizedBox(width: 8),
              Text('${t('stock')}: $qty',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: low ? Colors.orange : Colors.green)),
              const Spacer(),
              Text('${t('scanMinLevel')}: $minLevel',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ]),
          ),
          if (low)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(t('scanLowStock'),
                  style: const TextStyle(
                      color: Colors.orange, fontWeight: FontWeight.bold)),
            ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _restock(ctx, inventoryProvider, drink),
                icon: const Icon(Icons.add),
                label: Text(t('scanRestock')),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const InventoryScreen()));
                },
                icon: const Icon(Icons.inventory),
                label: Text(t('scanManage')),
              ),
            ),
          ]),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _restock(BuildContext ctx, InventoryProvider provider,
      Drink drink) async {
    await provider.addStock(
      drinkId: drink.id,
      drinkName: drink.name,
      quantity: 1,
    );
    if (!ctx.mounted) return;
    Navigator.pop(ctx);
    if (mounted) Helpers.showToast('${drink.name} +1');
  }
}

