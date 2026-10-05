# Drink Quick Cal — Administrator Manual

*For owners, managers and platform administrators — the people who control access, money, stock and the subscription. Version 2.0 — 27 September 2026.*

This manual covers what the user manual does not: **who may do what, how to change it, and what you must supervise**. For the day-to-day screens (selling, printing, counting), read `docs/USER_MANUAL.md` first.

---

## 1. Roles and what each one can do

Drink Quick Cal is a multi-tenant system: every record belongs to exactly one company, and a company can never see another company's data. Access is checked on the server from the signed-in session — never from anything the app sends — so changing a role in the app only works if the backend allows it.

| Role | Typical holder | Can do | Cannot do |
|---|---|---|---|
| **Owner** (one per company, `companies.owner_id`) | Proprietor / director | Everything: company settings and **logo**, staff, prices, subscription and payment, reports, exports, voids | — |
| **Manager** | Bar manager / supervisor | Sell, discount within limits, **void and restore orders with a reason**, approve staff actions, receive stock, run counts, close shifts, view reports, manage non-owner staff | Change the owner's account, change company ownership, buy or extend the subscription on the owner's behalf without agreement |
| **Staff** (cashier / bartender) | Serving staff | Sell, take payment, print, open and close their shift, view stock levels, add customers, settle tabs | Void orders, apply discounts beyond their limit, see cost prices where hidden, edit drinks or prices, see company settings, manage users |
| **Platform administrator** | You, the publisher / support team | Cross-company support: help a company reset access, inspect a problem, correct data with a documented reason | Business decisions inside a customer's company; administrator actions are also logged |

**The owner row is protected.** In the staff list the owner's own account is marked, and a co-manager cannot edit or delete it — only the owner themselves or a platform administrator may. That rule is enforced in the app *and* in the API, so it cannot be bypassed from a modified client.

## 2. Staff accounts

Open **Menu → Manager → Staff management**.

1. **Create an account** — choose a username, a temporary password, the role (manager or staff) and, where the company uses them, the branch/shift. Give the password to the person **in person**; never send it in a group chat.
2. **The person changes the password** on first sign-in, and the app asks them to set a **device PIN**.
3. **Edit** a staff user to correct the name, role or status. Promoting someone to manager gives them the money controls listed in §1 — do it deliberately and tell them so.
4. **Deactivate** (do not delete) an account when someone leaves: the history of their sales must stay readable, but they must not sign in again. Deactivated users cannot open a session, and their open shift should be closed first.
5. **Reset a password** for a user who lost theirs — the manager sets a new temporary password and the user changes it.
6. **Never share accounts.** If two people use one login, every void, discount and cash difference is attributed to the same person and the audit trail becomes useless.

**Login approvals** — where the company has switched approvals on, a new or unusual sign-in appears under *Manager → Login approvals* for a manager to confirm before that device is trusted.

**Owner contact details:** keep the owner's email and phone current in company settings. It is the only channel we use for subscription, security and legal notices.

## 3. Voiding an order with a trace (money control #1)

A recorded sale is **never edited**. It is voided, and the void is itself a record:

1. Open **Invoice History**, find the ticket, open it.
2. Tap **Void**, then type the **reason** — this is mandatory. Write something that a third person can understand next month: "wrong drink entered, corrected as invoice 000412", "customer left without paying and management agreed to write off", "double tap on a busy ticket".
3. Confirm with your credentials. Only managers and owners can void.
4. What happens automatically:
   - the order is marked voided, with **who** voided it, **when**, and **why**;
   - the **stock is put back** through an inventory movement, so the count stays honest;
   - the order is **excluded from the day's takings**, and the **Z report shows the number and value of voids** as a separate line;
   - the Sale/Invoice History shows it greyed out with the reason, so it can never be re-used as a "missing" ticket.
5. **Restore** is the reverse, also manager-only and also logged, for the case where a void was itself a mistake.

**Supervision habit.** Every week, read the voids for the period. A void list that is long, unexplained, or concentrated at the busiest hours or on the most expensive drinks is the classic signature of a drawer being emptied through the till. Ask for the reason; the app already recorded it.

## 4. Discounts and approvals (money control #2)

- A **discount** reduces the amount collected, so it must always be attributable: the app records who applied it and how much.
- Set a **staff discount limit**. Above that limit the app blocks staff and asks for **manager approval** — the manager's own password confirms the action, and the approval is logged.
- The same approval mechanism covers other sensitive actions the company has switched on (for example price edits or a credit above a customer's limit).
- **Never** approve a discount you do not understand. Approving is an authorisation, not a favour: the discount is on your record.
- Discounts, voids and credit notes all reduce the takings on the Z report, so they are the three lines to reconcile against reality every day.
## 5. Stock and variance control

Stock is where money quietly disappears, so treat every movement as an entry in the books.

- **Receipts** — record deliveries with supplier, quantity and unit cost. Never adjust a quantity to match a delivery that was not entered; the receipt *is* the entry.
- **Adjustments** — spillage, breakage, staff consumption, a gift, a transfer between bars: each needs a **reason**. An unexplained adjustment is a red flag, whoever made it.
- **Expiry** — capture expiry dates on receipt so the app can warn you in time, and pull short-dated stock to the front of the shelf.
- **Variance count** (Menu → Variance) — count physically, enter what you find, and give a reason where it differs. The app values the gap **at cost**, which is the honest number: it is what you paid for what you no longer have.
- **Cadence** — count high-value spirits weekly, beer and soft drinks daily or every two days, and always before a delivery. Do the count with a second person present and sign it off.
- **Read it as a trend.** A single 2 % gap on beer is noise; the same gap every week is a procedure problem or a theft. Compare variance to the voids in the same period: unrecorded sales often show up as a stock gap *and* an unexplained void pattern.

## 6. Cash-up discipline

1. **One shift, one drawer, one responsible person.** The app warns if a shift is already open — do not start a second one to hide the first.
2. The shift records the **float** at the start, cash sales, mobile money, card, and **credit given** separately.
3. At closing, the person **counts the cash physically** and enters the counted amount. The app computes **expected cash** and the **difference**.
4. A note explaining the difference is required to close. Accept no unexplained difference, however small: the habit is what protects the bar.
5. The **Z report** for that shift becomes the day's control document: sales by payment type, discounts, credit given, voids (count and value) listed separately, and the cash difference.
6. Keep the shift history. If a figure is ever disputed, the Z report plus the invoice list settle it, because both come from the same recorded sales.

**Mobile money and card are not cash.** Reconcile them against the operator's statement/wallet: the app shows what was *recorded* as received, and the operator statement shows what actually arrived. Differences there are usually a mistyped amount or a payment confirmed without checking the phone.

## 7. Credit control (customer tabs)

Credit is a loan you grant on trust, so it needs rules:

- **Set a credit limit** for each customer. The app warns before a sale pushes them past it, and staff cannot "just this once" without an approval.
- **One customer, one record.** Do not let staff put several people's debts under one name — the ledger becomes unenforceable.
- **Follow up weekly**, not once a year: the Customers screen shows the balance, the last activity and the full ledger, and the **WhatsApp** button sends a polite reminder with the exact amount.
- **All repayments are recorded** (cash, mobile money, card), so the balance always equals the ledger. If a customer disputes a figure, open the ledger and read it line by line.
- **Writing off a debt** is a manager decision and must be recorded as an adjustment **with a reason**, never by deleting entries. Treat writes-off as a monthly report line: a bar that writes off a lot is either granting credit too freely or losing it through the till.
- A customer who never pays is a business decision, not a technical one: stop extending credit and use the ledger as your evidence.

## 8. Prices, margins and what staff can see

- Maintain **cost (buying) price** and **selling price** for every drink: margin, stock valuation and forecast all depend on the cost price being right.
- Update prices when the supplier price moves — an out-of-date cost makes your variance report and margins lie.
- Where the company uses **two price levels** (for example retail and wholesale/happy hour), keep both prices clean, and check that staff use the right one.
- **Hide cost prices and margin views** from staff roles that do not need them; your managers should see them, your cashiers should not.
- **Archiving** a drink hides it from the Calculator without touching history — the correct way to stop selling an item you no longer stock. Never delete a drink that has sales.

## 9. Company settings and the logo

Open **Menu → Settings** (or Profile) with the **owner** account to change:

- **Company name, address, phone and tax details** — these print on receipts and invoices, so they must be right.
- **Company logo** — the owner uploads it; it appears on receipts and invoices. Logo changes are owner-only and are checked on the server, so a manager account will be refused even from a modified app. If the logo refuses to change, confirm you are signed in as the owner (see the troubleshooting note in §13).
- **Currency and formats** — set once, so every report and receipt reads the same way.
- **Branches / locations** — where the company runs more than one bar, keep each sale attached to the right location so reports make sense.
- **Default language** — the language new users see; each person can change their own afterwards.

**One company per user (today).** A user account belongs to one company; if you operate two separate businesses, they need their own accounts. Data between companies is isolated at the database level, and that isolation is a feature you should never try to work around inside one company.
## 10. Subscription and payment administration

Plans are **Free**, **Starter** and **Pro**; a paid plan runs for the period purchased and then returns the company to Free (records are kept — only plan-gated features switch off). A first sign-in on a company without an active plan sees the plans screen, and each user may choose **Continue on Free** to work immediately.

**How activation really works (important):**

- A plan is activated **only** when the payment provider confirms the transaction **and** the notification (webhook) is verified by its signature. A user tapping "I have paid" does not activate anything.
- If the notification reports a **smaller amount** than the price, the plan is not granted (underpayment guard). The payment is recorded and can be reconciled manually.
- A transaction shown as *pending verification* in the app is normal for a minute or two. If it stays pending for hours, ask the customer for the **transaction reference** and the exact phone number used.

**Administrator checklist for a disputed payment**

1. Get the **company name**, the **transaction reference**, the **amount**, the paying number and the **time**.
2. Check the provider dashboard for that reference: paid, pending or failed?
3. If the provider shows paid but the app shows Free, the notification may have been lost: re-send it from the provider dashboard or activate the period with a written note in the ticket.
4. Never activate a plan on a customer's word alone, and never publish your provider keys anywhere.

**Test mode vs live mode.** The payment integration can run in test mode (simulated payments — used for training and demos) or live mode (real money). The app shows a **test-mode banner** and the health endpoint below reports the current mode, so always check before telling a customer to pay.

**Prices and changes** are announced in the app at least 14 days before they apply to a renewal, and never retroactively (see the Terms of Service).

**Health check for administrators**

```
GET https://drink-quick-cal-kja1.onrender.com/health
```

It returns the running **release** and the payment **mode** (`test` or `live`). If the release is not the one you expect, the deployment has not finished. Do not announce a feature or take payments in live mode until this endpoint reports what you expect.

## 11. Security operations

- **Passwords** are stored only as strong one-way hashes (bcrypt). If an old account still holds a legacy password, it is upgraded silently on the next successful sign-in. Never create a second, weaker path for passwords.
- **Sessions** are server-side and revocable, and they expire. When someone leaves, deactivate the account — that is what actually ends their access.
- **Device PIN / lock screen**: enforce the habit. On a shared till the lock screen is what stops the next person acting as the previous user.
- **Log out pending sync first**: tell staff never to sign out of a device holding unsynchronised sales.
- **Roles, not favours**: give manager rights only to people accountable for cash, and review that list every month.
- **Audit trails** — two records exist for money-risk actions: the **void/restore** trail (who, when, why) and the **inventory movement** trail (every stock in, out and adjustment with its author). Review both at least weekly.
- **Rate limiting and abuse**: the API is protected on the most sensitive endpoints and by session checks on the rest. Keep the load low and sensible; if you ever see sustained failed sign-ins or unusual traffic for one company, treat it as an incident, rotate anything it could have exposed, and record what you found.
- **Secrets** (database URL, payment keys, session secret) live only in the server environment, never in the app, in a chat, or in a document. If a key leaks, rotate it **first**, then investigate.
- **Personal data on devices**: a lost phone with an active session is the realistic risk. Deactivate the account, ask staff to report losses immediately, and rely on device lock (PIN/pattern) plus the in-app PIN.

## 12. Data protection and retention duties

You are the **data controller** for your own company's records, including your customers' names, phones and tabs; we host and process them for you. That means the shop side must:

- **Tell your own customers** what you record (name, phone, address, purchases, credit balance) and why, and who to ask for a copy or a deletion.
- **Tell your staff** that you keep their account, role and the actions they take (voids, discounts, shifts) for control and audit reasons.
- **Use data only for business purposes** — no selling, no marketing to customers without their agreement.
- **Honour requests**: a customer asking for their data or its deletion should be handled by the company first. Export or delete what you can; if you cannot, write to us and we will assist.
- **Respect retention**: keep business records for the period your accountant and the law require; when a customer leaves, you do not have to keep their tab history forever.
- **Sub-processors** used to run the service: managed PostgreSQL database (Supabase), hosting (Render) and the payment operators (for example Notch Pay with MTN/Orange/card rails). Give notice to your customers if a sub-processor changes.

Full commitments, including retention periods and rights, are in the Privacy Policy shipped in the app (`/privacy.html`, French: `/privacy.fr.html`) and in the Terms of Service (`/terms.html`, `/terms.fr.html`).
## 13. Troubleshooting for administrators

| Symptom | Likely cause and action |
|---|---|
| **"Not authorized" when changing the company logo** | The account is not the company owner. Logo changes are owner-only and are checked on the server. Sign in with the owner account (or have a platform administrator do it). If it still fails *as the owner*, sign out and in again so the app refreshes your profile, then retry. |
| A user sees another company's data | Treat as a **serious incident**: stop, capture the user, company and time, and report it immediately. Tenant isolation is enforced server-side, so a report of this kind is a bug you must know about. |
| A staff member can void or discount | Their role is manager, or an approval was granted. Check their role in Staff management, and review the void/approval trail for who allowed it. |
| A payment was made but the plan is Free | Check the provider reference (see §10). Do not activate on trust; reconcile and document. |
| A plan expired during a busy service | Paid features switched off but **no data was lost**. Renew from the Subscription screen; the paid features return immediately. |
| Stock levels look impossible | Read **Inventory → Movements** for that drink: a receipt, an adjustment or a void explains it. Then run a **Variance** count with a reason. |
| Two devices show different totals | One device is behind on sync. Let it finish (indicator turns Synced) before comparing, then compare in **Invoice History** filtered by the day. |
| Shift cannot be closed | A note is required when there is a difference, and the counted amount must be entered. If a shift is genuinely stuck, close it and document the reason in the note. |
| Printer not working on a new phone | Pair it in *Settings → Printing*; make sure Bluetooth is on and the printer is not already connected to another phone. |
| The app shows a **test-mode** payment banner | Live payment keys are not configured. Do not let customers pay; report it to the platform administrator. |

**Escalation.** When you contact support, always include: **company name**, **user account**, **date and time**, **invoice number or transaction reference**, and what you expected to happen. A screenshot of the screen helps; never send passwords, keys or customer personal data in a support message.

## 14. Exports and business continuity

- **Export regularly.** Analytics, inventory and reports all export to **PDF**, **Excel** and **CSV**. Export at least monthly and at every period close, and keep the files somewhere other than the same phone: email to yourself, a laptop, or a USB drive kept in the office.
- Those files are also your answer to an audit, a tax inspection or an insurance claim, and the practical recovery path if a device is lost or stolen.
- **Offline resilience**: the app keeps recording sales without the network, so a cut connection is not an immediate business stop — but no device should stay offline for days: the longer the gap, the harder the reconciliation.
- **Never clear app data** on a device that still shows pending (not synced) records.
- **Training is continuity too**: teach each new user the shift routine, the void rule and the offline indicator before their first solo service. Use `docs/USER_MANUAL.md` as the checklist, and the test payment mode for training — never a live payment.
- **Record your routines**: stock count day, cash-up time, credit follow-up day, export day. Discipline, not software, is what closes the gap between the till and the bank.
## 15. Platform administration

The platform administrator account is for running the service across companies — support, not business decisions:

1. **Look up a company** before acting: name, owner, plan, status, last activity.
2. **Support a locked-out owner**: reset access or correct a company setting, and state in the ticket why you did it. Every administrative action is attributable.
3. **Never edit a customer's business figures** (sales, stock, balances) to "fix" a report: the correct tool is the one the shop already has — a void, an adjustment, or a correction entry with a reason.
4. **Watch `GET /health`** after every deployment: the reported release must match what you deployed, and the payment mode must be the intended one.
5. **Multi-tenant housekeeping**: deactivating a company stops its access while keeping the records for the retention period; deleting data is done on the owner's written request, against a documented trail.
6. **Keep the legal pages current**: `/privacy.html`, `/privacy.fr.html`, `/terms.html` and `/terms.fr.html` are served by the backend and linked from the app. Update the version and date whenever the text changes.

---

### Résumé en français (pour les gérants et propriétaires)

- **Rôles** : le **propriétaire** (un seul) peut tout ; le **gérant** vend, remise, **annule une commande avec motif**, valide les actions et gère le personnel non-propriétaire ; le **personnel** vend et encaisse mais n'annule pas ; l'**administrateur de la plateforme** intervient pour l'assistance, de façon journalisée.
- **Compte du propriétaire protégé** : un cogérant ne peut pas le modifier — seul le propriétaire ou un administrateur de la plateforme.
- **Personnel** : créez les comptes, transmettez le mot de passe de vive voix, **désactivez** au départ (ne supprimez pas), jamais de compte partagé.
- **Annulation** : on ne modifie jamais une vente. On annule avec un motif obligatoire ; le stock est remis en place et l'annulation est exclue du chiffre d'affaires mais comptée dans le rapport Z.
- **Remises** : au-delà du plafond autorisé, l'application demande l'approbation d'un gérant, et cette approbation est enregistrée.
- **Stock** : réception, ajustement motivé, dates d'expiration, comptage **Variance** valorisé au prix d'achat ; comparez l'écart aux annulations de la période.
- **Caisse** : un service, une caisse, une personne responsable ; comptez physiquement, justifiez l'écart dans la note, conservez le rapport Z.
- **Crédits** : plafond par client, un client = une fiche, relance hebdomadaire par WhatsApp, toute remise de dette enregistrée avec motif.
- **Logo et paramètres d'entreprise** : réservés au propriétaire.
- **Abonnements** : activation uniquement après confirmation du prestataire **et** notification vérifiée ; comparez la référence de transaction en cas de litige ; vérifiez le mode test/live (endpoint `/health`) avant tout paiement réel.
- **Sécurité** : mots de passe hachés, sessions révocables côté serveur, code PIN de l'appareil, revue hebdomadaire des annulations et des mouvements de stock, rotation immédiate des clés en cas de fuite.
- **Données** : l'Établissement répond de l'information de ses clients et de son personnel ; exports réguliers en PDF/Excel/CSV ; conservation selon la loi et la comptabilité.
- **Assistance** : mdksako@gmail.com · mbundaderick@gmail.com — avec le nom de l'entreprise, le compte, la date, le numéro de facture ou la référence de transaction.




