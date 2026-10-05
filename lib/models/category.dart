import 'package:flutter/material.dart';

class CategoryInfo {
  const CategoryInfo(this.name, this.icon, this.color);

  final String name;
  final IconData icon;
  final Color color;
}

/// Every category the user can pick. Names must match [Categorizer].
const List<CategoryInfo> kCategories = [
  CategoryInfo('Food', Icons.restaurant, Color(0xFFE76F51)),
  CategoryInfo('Groceries', Icons.local_grocery_store, Color(0xFF2A9D8F)),
  CategoryInfo('Shopping', Icons.shopping_bag, Color(0xFF8E44AD)),
  CategoryInfo('Travel', Icons.directions_car, Color(0xFF3A86FF)),
  CategoryInfo('Fuel', Icons.local_gas_station, Color(0xFFF4A261)),
  CategoryInfo('Bills & Recharge', Icons.receipt_long, Color(0xFF457B9D)),
  CategoryInfo('Entertainment', Icons.movie, Color(0xFFD62828)),
  CategoryInfo('Health', Icons.local_hospital, Color(0xFF06A77D)),
  CategoryInfo('Education', Icons.school, Color(0xFF6A4C93)),
  CategoryInfo('Transfers', Icons.swap_horiz, Color(0xFF6C757D)),
  CategoryInfo('Income', Icons.account_balance_wallet, Color(0xFF2E7D32)),
  CategoryInfo('Others', Icons.category, Color(0xFF8D99AE)),
];

CategoryInfo categoryOf(String name) =>
    kCategories.firstWhere((c) => c.name == name, orElse: () => kCategories.last);
