# Drink Quick Cal — Feature Roadmap (5 Features)

A phased plan for the requested features, ordered by value-vs-risk.

> Status legend: ✅ done · ⬜ planned

---

## Phase 1 — Manager Dashboard Analytics (charts, popular items, peak hours) ✅

**Value:** High · **Risk:** Low · **Hardware:** none

Everything is computed client-side from data already in memory (`OrderProvider.orderHistory`).

### Delivered
- `lib/models/analytics_model.dart` — `AnalyticsSnapshot`, `PopularItem`, `CategorySlice`.
- `lib/utils/analytics_helper.dart` — `computeAnalytics(orders, startDate, endDate)`.
- `lib/widgets/charts.dart` — dependency-free chart widgets:
  - `HourlyBarChart` (24h vertical bars — peak hours)
  - `RevenueLineChart` (CustomPaint line/area — revenue trend)
  - `DonutChart` (donut + legend — sales by category)
- `lib/screens/manager_dashboard.dart` — KPI cards (revenue, orders, items sold, avg order), popular items (ranked bars), peak hours, revenue trend, category mix, 7/30/90-day range selector.
- Drawer entry (`analyticsMenu`) for Manager + Admin roles.
- EN/FR keys added to `i18n.dart`.

### Validation
- `flutter analyze lib` → 0 errors
- EN/FR key parity check → equal, no missing

---

## Phase 2 — Predictive Analytics / Demand Forecasting ⬜

**Value:** High · **Risk:** Medium · **Hardware:** none

### Approach
1. **Deterministic engine (offline, no AI cost):**
   - Moving average + weekly seasonality per drink from `InventoryProvider.transactions` / `OrderProvider.orderHistory`.
   - Holiday/event calendar with demand multipliers (static holiday table + user-defined events).
   - Output: forecasted demand per drink → recommended order quantity vs `minStockLevel`.
2. **Optional AI layer:** feed the historical summary + upcoming events to the existing `GroqService` (`/api/ai/chat`) for a natural-language forecast.

### Files (planned)
- `lib/models/forecast_model.dart` — `ForecastItem { drinkName, forecastQty, recommendedOrder, confidence, trend }`.
- `lib/utils/forecast_helper.dart` — `computeForecast(...)`.
- `lib/utils/holidays.dart` — holiday table + event CRUD (SharedPreferences).
- `lib/screens/forecast_screen.dart` — forecast list, order recommendations, AI summary.
- Drawer entry + `i18n.dart` keys.

### Notes
- Keep the forecast local/offline first; add `/api/analytics/forecast` only if server-side aggregation is desired.

---

## Phase 3 — Receipt Printing / Sharing (thermal printer) ⬜

**Value:** Medium · **Risk:** Medium (platform) · **Hardware:** thermal printer (optional)

### Approach
1. **Sharing** — already done via `share_plus` (PDF). Add "share as text" fallback.
2. **Thermal (ESC/POS)** — new native packages:
   - `esc_pos_utils` (byte encoding, 58mm/80mm)
   - `print_bluetooth_thermal` (Bluetooth discovery/printing; Android/iOS)
   - `permission_handler` (already present) for Bluetooth runtime permission.
3. Render a monochrome receipt from `Order` data (same source as `responsive_invoice.dart`).
4. Fall back to the existing PDF `printing` flow on Windows/web where thermal isn't supported.

### Files (planned)
- `lib/services/receipt_printer.dart` — ESC/POS builder + printer discovery + print/save.
- `lib/screens/receipt_print_screen.dart` — printer list + preview + print button.
- Wiring into `responsive_invoice.dart` (new "Thermal" button).
- `android/app/src/main/AndroidManifest.xml` — Bluetooth permissions.
- `i18n.dart` keys.

### Notes
- Android requires runtime Bluetooth + (API 31+) `BLUETOOTH_CONNECT`/`BLUETOOTH_SCAN`.
- iOS supports AirPrint natively via `printing`; dedicated thermal apps use Bluetooth (MFi/LAN) printers.

---

## Phase 4 — Real-time IoT Sensor Integration (automated replenishment) ⬜

**Value:** Medium · **Risk:** High (hardware + backend) · **Hardware:** ESP32/Arduino + weight/load-cell sensor

### Approach (3 layers)
1. **Firmware (separate repo):** ESP32 reads load cell → reports weight over WiFi (MQTT or HTTP POST).
2. **Backend:**
   - `POST /api/sensors/reading` (device-authenticated) → upsert `sensor_readings`.
   - Publish change to **Supabase Realtime**.
3. **App:**
   - Subscribe to Realtime (`SupabaseService` already has Realtime infra + an `inventory` channel pattern).
   - Map sensor → `InventoryItem` via a `device_id`/`drink_id` mapping.
   - Live-update quantity + trigger existing `NotificationService.showLowStock/OutOfStock`.

### Files (planned)
- Backend: `routes/sensors.js` (or inline in `server.js`), `sql/sensor_tables.sql`.
- App: `lib/models/sensor_model.dart`, `lib/services/sensor_service.dart`, Realtime channel in `SupabaseService`, mapping UI in `inventory_screen.dart` / `storage_settings_screen.dart`.
- `ApiConfig` endpoints.

### Notes
- Requires real hardware for end-to-end testing; the app + backend integration layer can be built and unit-tested independently.
- Recommend MQTT (Mosquitto/EMQX) if scaling to many devices; HTTP is fine for a pilot.

---

## Phase 5 — AR Scanning (barcode/QR MVP → full AR later) ⬜

**Value:** Medium · **Risk:** Medium → High (full AR) · **Hardware:** camera + printed codes

### MVP (recommended first step)
1. **Barcode/QR scan → item detail:**
   - Add `mobile_scanner` package + camera permission (`permission_handler` already present).
   - Scan a label → match SKU/barcode to a `Drink`/`InventoryItem` → open live stock detail + restock/count actions.
2. **Print labels:** generate QR/barcode labels from the app (ties into Phase 3 printing).

### Full AR (later, high effort)
- `arcore_flutter_plugin` / `arkit_flutter_plugin` + custom object-detection ML models per product (e.g. `tflite_flutter`).
- Research-level effort; only pursue after the barcode MVP validates demand.

### Files (planned)
- `lib/screens/scanner_screen.dart` (camera + scan + result sheet).
- `lib/services/barcode_service.dart`.
- `drink_model.dart` — add `barcode` field.
- `i18n.dart` keys, `pubspec.yaml` deps, Android/iOS permissions.

---

## Suggested sequencing
1 → 2 → 3 → 4 → 5 (each phase independently shippable).
