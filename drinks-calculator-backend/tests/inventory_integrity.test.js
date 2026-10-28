/**
 * Inventory integrity guards - no database required.
 *
 * inventory.drink_id is a text column with no foreign key, and two defects used
 * to leave stock rows pointing at a drink that no longer exists:
 *   1. DELETE /data/drinks/:id removed the drink but not its stock row;
 *   2. the app's "delete inventory item" called deleteDrink(), so it deleted the
 *      DRINK and left the stock row behind.
 * Live symptom: company 42, drink_id 1792870970398 ("music"), quantity 0.
 *
 * These are source guards: they lock the shape of the fix so a refactor cannot
 * silently reintroduce either one. Run with: npm test
 */
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8');
// The Flutter app lives beside the backend in the same repository.
const readApp = (rel) => fs.readFileSync(path.join(root, '..', 'lib', rel), 'utf8');

describe('deleting a drink takes its stock line with it', () => {
  test('DELETE /drinks/:id removes the inventory row, and does it first', () => {
    const routes = read('routes/data.routes.js');
    const start = routes.indexOf("router.delete('/drinks/:id'");
    expect(start).toBeGreaterThan(-1);
    const block = routes.slice(start, start + 1200);

    expect(block).toContain('DELETE FROM inventory WHERE drink_id = $1 AND company_id = $2');
    expect(block).toContain('DELETE FROM drinks WHERE id = $1 AND company_id = $2');
    // Inventory first: a leftover stock row is the bug; a drink with no stock row
    // is tolerated by the app (it falls back to drinks.current_stock).
    expect(block.indexOf('DELETE FROM inventory')).toBeLessThan(
      block.indexOf('DELETE FROM drinks')
    );
  });

  test('a route exists that deletes a stock line without the drink', () => {
    const routes = read('routes/data.routes.js');
    const start = routes.indexOf("router.delete('/inventory/:drinkId'");
    expect(start).toBeGreaterThan(-1);
    const block = routes.slice(start, start + 700);
    expect(block).toContain('DELETE FROM inventory WHERE drink_id = $1 AND company_id = $2');
    // It must never touch the drinks table.
    expect(block).not.toContain('DELETE FROM drinks');
  });
});

describe('the app deletes the stock line, not the drink', () => {
  test('inventory_provider calls deleteInventoryItem and never deleteDrink', () => {
    const provider = readApp('providers/inventory_provider.dart');
    const start = provider.indexOf('Future<void> deleteInventoryItem(');
    expect(start).toBeGreaterThan(-1);
    const block = provider.slice(start, start + 600);

    expect(block).toContain('SupabaseService.deleteInventoryItem(drinkId)');
    expect(block).not.toContain('SupabaseService.deleteDrink(');
  });

  test('SupabaseService.deleteInventoryItem points at the inventory route', () => {
    const service = readApp('services/supabase_service.dart');
    const start = service.indexOf('deleteInventoryItem(String drinkId)');
    expect(start).toBeGreaterThan(-1);
    expect(service.slice(start, start + 600)).toContain(
      'ApiConfig.dataInventoryDelete(drinkId)'
    );
  });
});

describe('the invariant is enforced in the database', () => {
  test('a script cleans the orphans and adds the cascade foreign key', () => {
    const sql = read('sql/inventory_drink_fk.sql');
    expect(sql).toContain('references public.drinks (id) on delete cascade');
    expect(sql.toLowerCase()).toContain('delete from public.inventory');
    // Re-runnable: the constraint is added inside an existence check.
    expect(sql).toContain('pg_constraint');
  });
});
