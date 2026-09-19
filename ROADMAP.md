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

## Phase 2 — Predictive Analytics / Demand Forecasting ✅

**Value:** High · **Risk:** Medium · **Hardware:** none

### Delivered
- `lib/models/forecast_model.dart` — `ForecastItem`, `EventDay`, `ForecastResult`.
- `lib/utils/forecast_helper.dart` — `computeForecast()` (moving average + weekly seasonality + event multipliers).
- `lib/utils/holidays.dart` — static holiday calendar + `upcomingStaticEvents()`.
- `lib/screens/forecast_screen.dart` — forecast list, recommended orders, trend/confidence, custom events, optional AI summary (Groq).
- Drawer entry (`forecastMenu`) for Manager + Admin; EN/FR keys.

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

## Phase 3 — Receipt Printing / Sharing (thermal printer) ✅

**Value:** Medium · **Risk:** Medium (platform) · **Hardware:** thermal printer (optional)

### Delivered
- `lib/services/receipt_printer.dart` — self-contained ESC/POS generator + Bluetooth printing.
- `lib/screens/receipt_print_screen.dart` — 58/80mm preview, Bluetooth print, text share/save.
- `responsive_invoice.dart` — receipt (thermal) action wired from the invoice.
- `android/app/src/main/AndroidManifest.xml` — Bluetooth permissions.
- `print_bluetooth_thermal` dependency + EN/FR keys.

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

## Phase 5 — AR Scanning (barcode/QR MVP → full AR later) 🟡

**Value:** Medium · **Risk:** Medium → High (full AR) · **Hardware:** camera + printed codes

### Delivered (MVP)
- `mobile_scanner` dependency + `CAMERA` permission.
- `drink_model.dart` — added `barcode` field.
- `lib/services/barcode_service.dart` — scan → drink/inventory matching.
- `lib/screens/scanner_screen.dart` — camera preview, scan overlay, torch/camera toggle, detail sheet with quick restock.
- Drawer entry (`scanMenu`) for drink-managing roles; EN/FR keys.

### How the MVP works
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

---

## Phase 6 — Hardening, billing gate, alerts & reporting ✅

**Value:** High · **Risk:** Medium (touches login flow, security and exports)

Requested in one batch; shipped as nine independently validated changes.

### Delivered
1. **Drink batch dates actually persist** (`lib/services/supabase_service.dart`).
   `production_date`, `expiry_date` and `unit_kind` were never sent to
   `/api/data/drinks` and were dropped again when reading the rows back, so the
   dates looked lost. Payload building and row mapping are now pure, unit-tested
   helpers (`buildDrinkInsertPayload`, `buildDrinkUpdatePayload`, `mapDrinkRow`,
   `dateOnly`); the same fix stops `image_url` from being wiped on save/edit.
2. **`forecast_events` RLS** — created without row level security, so the anon
   key could read/forge company events. RLS + `REVOKE ALL … FROM anon,
   authenticated` is applied at boot and via `sql/rls_forecast_events.sql`
   (`scripts/apply_forecast_rls.js`); the lockdown scripts cover the newer tables.
3. **Notifications are device-only** — the `/api/data/notifications` routes, the
   table creation and every client sync path were removed; history lives in
   SharedPreferences. `sql/drop_notifications_table.sql` is the opt-in cleanup.
4. **Co-managers cannot edit the owner** — `PUT /api/auth/update-staff/:id` now
   refuses unless the caller is the owner or an Administrator, and the owner can
   never be demoted out of the Manager role. Rules live in
   `utils/staffPermissions.js` (backend) and `lib/utils/staff_permissions.dart`
   (UI), both unit tested.
5. **Subscription gate** — `PlanGate` resolves the plan right after login: an
   active plan goes straight through, free/none/expired plans open the
   subscription screen, and **Continue on Free** is remembered per company (a
   lapsed paid plan re-opens the gate). `lib/utils/plan_gate_logic.dart` holds the
   decision table.
6. **Pro staff barcode scanning** — the drawer exposes the (Pro) scanner to
   Staff, the scan sheet gained a quantity stepper plus *Send to calculator*
   (via `OrderBridge`), and stock-management actions stay manager/admin only.
7. **30-day expiry alerts joined with the demand forecast** —
   `computeExpiryAlerts()` pairs each batch date with its expected demand and
   suggested order; `ExpiryAlertService` raises the alert once per batch per day
   and the forecast screen shows an *Expiring soon* banner. The AI assistant and
   the forecast AI summary both receive the expiring-stock context and are told to
   push those batches first.
8. **Professional inventory export** — `lib/utils/inventory_report_files.dart`
   builds a presentation-ready PDF (company name, period, KPI boxes, two bar
   charts, stock/low-stock/expiry/movement tables, page numbers), a multi-sheet
   Excel workbook and a CSV. The export dialog offers a **checkbox per section**,
   the company name comes from `CompanyNameHelper`, and all labels are EN/FR.
9. **MouseTracker assertion tamed** — `FlutterAssertionGuard` drops only the
   known framework re-entrancy assertion
   (`mouse_tracker.dart … !_debugDuringDeviceUpdate`, flutter/flutter#137938) and
   counts it; a periodic rebuild storm in the connectivity banner was removed too.
   The same guard now prints a **one-per-location pointer** for real layout
   failures ("RenderBox was not laid out", `box.dart:2251`) so the offending
   `file:line` is visible instead of drowning in per-frame repeats.
10. **In-app drink pictures** — the image field in Drink Management has an upload
    button (camera/gallery) that stores the picture in the public Supabase Storage
    bucket `drink-images` and fills the URL automatically
    (`lib/services/drink_image_service.dart`, bucket + policies in
    `sql/storage_drink_images.sql`: 5 MB, images only, no overwrite/delete).
11. **AI assistant image + voice** — a captured photo is shown inside the
    conversation (Gemini-style) and survives a restart on native, spoken commands
    are persisted like typed ones (mic badge), and the pending-order button is
    labelled **Proceed**.
12. **Scan restock asks the quantity** — "Add stock" opens a dialog (quantity
    field with ±, +1/+pack shortcuts, validation, resulting total) instead of
    silently adding a whole pack.

### Validation
- `flutter analyze lib` → 0 errors
- `flutter test` → 110 passing (drink batch dates, staff permissions, plan gate,
  expiry alerts, inventory report builders, assertion guard)
- `npx jest` (backend) → 6 suites / 43 tests passing (schema hardening, staff
  permissions, orders staff-name, atomic inventory, payment mode, smoke)

