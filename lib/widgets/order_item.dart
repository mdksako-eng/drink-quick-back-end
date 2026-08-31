import 'package:flutter/material.dart';
import 'package:drinks_calculator_fixed/models/drink_model.dart';

class OrderItem extends StatelessWidget {
  final Drink drink;
  final int quantity;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onRemove;

  const OrderItem({
    Key? key,
    required this.drink,
    required this.quantity,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4), // Line 22
      child: ListTile(
        leading: const Icon(Icons.local_drink, color: Colors.blue), // Line 33
        title: Text(drink.name),
        subtitle: Text(
            'Quantity: $quantity • \$${drink.price.toStringAsFixed(2)} each'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '\$${(drink.price * quantity).toStringAsFixed(2)}',
              style: const TextStyle(
                // Line 38
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 16),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove, size: 20), // Line 53
                  onPressed: onDecrease,
                ),
                Text(
                  '$quantity',
                  style: const TextStyle(fontSize: 16),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 20), // Line 57
                  onPressed: onIncrease,
                ),
                IconButton(
                  icon: const Icon(Icons.delete,
                      color: Colors.red, size: 20), // Line 57 (second one)
                  onPressed: onRemove,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
