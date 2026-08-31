// lib/widgets/invoice_widget.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:drinks_calculator_fixed/models/drink_model.dart'; // Import Drink from models

class InvoiceWidget extends StatelessWidget {
  final List<Drink> drinks;
  final double total;

  const InvoiceWidget({
    Key? key,
    required this.drinks,
    required this.total,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'INVOICE',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Date: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),
          ...drinks.map((drink) => ListTile(
                title: Text(drink.name),
                trailing: Text('\$${drink.price.toStringAsFixed(2)}'),
              )),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TOTAL:',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '\$${total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
