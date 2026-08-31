// widgets/drink_card.dart
import 'package:flutter/material.dart';
import 'package:drinks_calculator_fixed/models/drink_model.dart';
import 'package:drinks_calculator_fixed/utils/currency_helper.dart';

class DrinkCard extends StatelessWidget {
  final Drink drink;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;
  final bool isBuiltIn;
  final bool isMobile;

  const DrinkCard({
    Key? key,
    required this.drink,
    required this.onTap,
    this.onEdit,
    required this.onDelete,
    required this.isBuiltIn,
    this.isMobile = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drink Image
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                  image: DecorationImage(
                    image: NetworkImage(drink.imageUrl),
                    fit: BoxFit.cover,
                    onError: (exception, stackTrace) {
                      // Handle image load error
                    },
                  ),
                ),
                child: Stack(
                  children: [
                    // Built-in Badge
                    if (isBuiltIn)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color.fromRGBO(66, 133, 244, 0.9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Built-in',
                            style: TextStyle(
                              fontSize: isMobile ? 9 : 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                    // Category Badge
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color.fromRGBO(0, 0, 0, 0.54),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          drink.category,
                          style: TextStyle(
                            fontSize: isMobile ? 9 : 10,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Drink Info
            Padding(
              padding: EdgeInsets.all(isMobile ? 8 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    drink.name,
                    style: TextStyle(
                      fontSize: isMobile ? 14 : 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF2C3E50),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: isMobile ? 4 : 6),
                  Text(
                    CurrencyHelper.format(drink.price),
                    style: TextStyle(
                      fontSize: isMobile ? 13 : 15,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF667EEA),
                    ),
                  ),
                ],
              ),
            ),

            // Action Buttons
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 8 : 12,
                vertical: isMobile ? 6 : 8,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFFF8F9FA),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Edit Button
                  IconButton(
                    onPressed: onEdit,
                    icon: Icon(
                      Icons.edit,
                      size: isMobile ? 18 : 20,
                      color: isBuiltIn ? Colors.grey : const Color(0xFF667EEA),
                    ),
                    tooltip: isBuiltIn ? 'Built-in drink cannot be edited' : 'Edit',
                  ),
                  // Delete Button
                  IconButton(
                    onPressed: onDelete,
                    icon: Icon(
                      Icons.delete,
                      size: isMobile ? 18 : 20,
                      color: const Color(0xFFFF6B6B),
                    ),
                    tooltip: isBuiltIn ? 'Hide from list' : 'Delete',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}