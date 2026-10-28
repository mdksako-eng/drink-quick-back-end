// utils/json_num.dart

/// Tolerant number read for JSON that came out of Postgres.
///
/// NUMERIC/DECIMAL columns reach the app as **strings** — "0.00", "800.00",
/// "1.25" — because node-postgres returns them that way to avoid losing
/// precision, while integer and double columns arrive as numbers. Calling
/// `.toDouble()` on the string throws `NoSuchMethodError`.
///
/// That matters more than it sounds: parsing is done per row inside a loop, so
/// ONE unreadable field silently drops the whole load. This has now happened
/// three times in this codebase:
///   - `inventory.purchase_price` (and the price-at-sale columns),
///   - `forecast_events.multiplier`,
///   - `orders.tab_amount` NUMERIC(12,2) — which wiped all 128 orders on load
///     ("Found 128 orders in Supabase" then "Loaded 0 orders").
///
/// Read every number/money field through this instead of `.toDouble()`, and
/// keep the fallback explicit at the call site (`?? 0`).
double? asDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is bool) return null;
  return double.tryParse(value.toString().trim());
}
