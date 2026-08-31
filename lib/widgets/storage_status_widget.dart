// lib/widgets/storage_status_widget.dart
import 'package:flutter/material.dart';
import 'package:drinks_calculator_fixed/services/storage_service.dart';

class StorageStatusWidget extends StatelessWidget {
  final VoidCallback onBackup;
  final VoidCallback onRestore;
  final VoidCallback onClear;

  const StorageStatusWidget({
    Key? key,
    required this.onBackup,
    required this.onRestore,
    required this.onClear,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final stats = StorageService.getStorageStats();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Storage Status',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            _buildStatItem('Custom Drinks', '${stats['drinksCount']}'),
            _buildStatItem('Order History', '${stats['ordersCount']}'),
            _buildStatItem(
                'Storage Used', '${stats['totalSize'].toStringAsFixed(2)} KB'),
            _buildStatItem('Last Backup', stats['lastBackup'] ?? 'Never'),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(
                  icon: Icons.backup,
                  label: 'Backup',
                  onPressed: onBackup,
                  color: Colors.blue,
                ),
                _buildActionButton(
                  icon: Icons.restore,
                  label: 'Restore',
                  onPressed: onRestore,
                  color: Colors.green,
                ),
                _buildActionButton(
                  icon: Icons.delete_sweep,
                  label: 'Clear',
                  onPressed: onClear,
                  color: Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.grey),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return Column(
      children: [
        IconButton(
          icon: Icon(icon),
          color: color,
          onPressed: onPressed,
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: color),
        ),
      ],
    );
  }
}
