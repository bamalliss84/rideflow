# Phase 2: dashboard final review, UI/UX refinement and functional completion

Date: 2026-10-24. Scope: the existing platform and operator portals (`apps/admin`).

This was a refinement, not a rebuild: routes, architecture, the BFF/session model and the business rules are unchanged. The approved reference image guided the visual direction:

- navy sidebar with a filled turquoise active item;
- white top bar;
- rounded cards;
- KPI tiles with tinted icon squares;
- light table headers and soft badges.

None of the reference's sample numbers, names or features were copied. All figures shown come from the existing authorized APIs.

## 1. Issues discovered

| # | Issue (where seen) | Severity |
|---|---|---|
| 1 | Small up/down scroll arrows at the top of the members table | High (visual defect) |
| 2 | Pages scrolled horizontally on phones (subscription plans, deposit accounts, audit log, members) | High |
| 3 | Grid columns could be widened by wide tables (cards had no shrink floor) | Medium |
| 4 | Mixed Arabic/Latin values concatenated into one string ("name · role · date"), reordered by the bidi algorithm. Seen in the dispute decision line and also in disputes list, ride timeline, deposit decisions, driver vehicles/availability, verification queue and tenant currency | High |
| 5 | Arabic dates and amounts wrapped in a forced-LTR class appeared scrambled, e.g. `212026/10/` | High (found during this review's own browser check) |
| 6 | Audit log showed raw English codes such as `Subscription receipt viewed`, `Auth login`, `Auth first factor ok` | Medium |
| 7 | Notifications had no read/unread state; "mark all" did not refresh; long feeds started at the oldest page | Medium |
| 8 | Reports chart: a 30-day range with one active day rendered as one full-height bar, and only active days were plotted | Medium |
| 9 | Policy settings: one very long stacked form, raw keys and JSON defaults shown to everyone, units mixed into labels, no unsaved-changes guard, provisional vs approved not explained | High (UX) |
| 10 | Organization page: narrow card with large unused space; hint wrongly implied the tenant slug is the sign-in workspace | Low |
| 11 | Ratings: no direction filter or sorting, cramped "name · role" text, plain empty state | Low |
| 12 | Filter selects announced their selected value instead of their label to screen readers | Low (a11y) |

## 2. Root causes

- **Tabs (#1).** Each tab used `-mb-px` to overlap the strip border. Inside an `overflow-x:auto` strip that 1px vertical overflow made the browser draw a vertical scrollbar, which shows as tiny arrows on Windows.
- **Phone overflow (#2).** Tables with an actions column have a visually hidden (`sr-only`, absolutely positioned) header label. The scroll box was not a containing block, so the label escaped the clip and widened the whole RTL page.
- **Grid blow-out (#3).** `Card` lacked `min-w-0`, so grid tracks took the table's minimum width.
- **Concatenated strings (#4).** Concatenating heterogeneous values into one string puts names, roles and dates into a single bidi run.
- **Scrambled dates (#5).** `Intl` output for `ar` contains RLM/LRM marks that assume the natural direction; forcing `direction:ltr` reorders it.
- **Audit codes (#6).** There was no presentation layer: `humanize(code)` was the only formatting.
- **Notifications (#7).** The backend feed did not expose `read_at`, and mark-read only supported "everything up to a cursor".
- **Report chart (#8).** The chart scaled bars to the data maximum. The daily report only returns days that had rides.
- **Policy page (#9).** It rendered the backend's technical groups 1:1.

## 3. Files and components changed

**Shared (fixed first):**

- `components/ui/Page.tsx`: tabs underline via inset shadow, toolbar alignment, filter label above control, `aria-label` on selects, range picker scrolls on small screens.
- `components/ui/DataTable.tsx`: `relative` scroll box (#2); optional expandable detail row; header and hover styling.
- `components/ui/Card.tsx`: `min-w-0`, `rounded-xl`, icon-tile `StatCard` (compact on phones), 4-column `KeyValues`, `SectionTitle`.
- `components/shell/AppShell.tsx`: filled teal active nav item, sidebar scrolls independently only when needed (`min-h-0`, `overscroll-contain`, thin scrollbar), context card, `min-w-0` content column, active state for the bell, wider max content width.
- `components/domain/Display.tsx`: `MetaLine` (isolated parts with separators) and `PersonRole`; `Stars` with an optional numeric value.
- `components/charts/BarChart.tsx`: rewritten as a multi-series grouped chart with:
  - one colour per status (requested/matched/completed/cancelled/no-show);
  - a fixed integer y-scale with four gridlines;
  - a left-to-right time axis;
  - tooltips;
  - `fillDays()` for honest zero days in the operator time zone.
- `lib/format.ts`: `shortDay` (plain DD/MM for axes) and `amount` (exact decimal for CSV).
- `lib/audit.ts` (new): audit action, domain, target and data-key labels.
- `components/domain/AuditLog.tsx`: rewritten (see §4).
- `app/globals.css`: thin scrollbar utilities, softer card shadow.
- `lib/i18n/ar.ts`, `lib/i18n/en.ts`: all new strings. Policy labels are now unit-free, with units shown beside inputs plus concise per-parameter explanations.

**Pages:**

- `operator/trust/ratings`
- `operator/reports`
- `operator/notifications`
- `operator/trust/disputes/[id]`
- `operator/audit`
- `operator/members`
- `operator/settings/policy`
- `operator/settings/organization`
- `operator` (dashboard chart and KPI grid)
- bidi fixes in `operator/drivers`, `drivers/[id]`, `drivers/verification`, `rides/[id]`, `trust/disputes`, `subscriptions/deposits/[id]`, `subscriptions/ledger`, `platform/(portal)` and `platform/(portal)/tenants/[id]`
- money cells in `riders/[id]`, `rides`, `subscriptions/deposits`, `subscriptions/plans`, `TrustSummary`

**Backend (smallest safe change, needed for real read/unread state):**

- `services/api/apps/notifications/services.py`: the feed item now carries `read` (from the existing `read_at` column).
- `services/api/apps/notifications/views.py`: `POST /notifications/read` accepts exactly one of `up_to` (existing behaviour) or `cursor` (one item). It stays scoped to the requesting user and tenant (RLS model).
- `packages/contracts/openapi.yaml` and `apps/admin/src/lib/api/schema.ts`: regenerated. The only diff is the notification change.
- `services/api/tests/test_mfa_and_portal_api.py`: new test.

No migration was needed: `read_at` already existed.

## 4. Routes reviewed

**Operator portal:**

- **Dashboard:** `/operator`
- **Drivers and riders:** `/drivers`, `/drivers/[id]`, `/drivers/verification`, `/riders`, `/riders/[id]`
- **Rides and geography:** `/rides`, `/rides/[id]`, `/live`, `/geo`
- **Subscriptions:** `/subscriptions/{deposits,deposits/[id],active,plans,accounts,ledger}`
- **Trust:** `/trust/{disputes,disputes/[id],violations,enforcement,appeals,scores,ratings}`
- **Insights:** `/reports`, `/notifications`, `/audit`
- **Administration:** `/members`, `/settings/policy`, `/settings/organization`, `/account`

**Platform portal:** `/platform`, `/platform/tenants`, `/platform/tenants/[id]`, `/platform/audit`, `/platform/account`, plus both login screens.

**Page-level results:**

- **Ratings:** direction filter (rider → driver / driver → rider, mapped to `ratee_role`), stars filter, sorting via the API's `ordering` (`created_at`, `stars`), from/to people as isolated name + role, stars with value, tags tinted for low ratings, comment clamp with full text on hover, permission-aware ride link, and distinct empty vs filtered-empty states. No fake ratings.
- **Reports:**
  - KPI totals are sums of the returned rows; completion share is labelled as "of requests".
  - Visible date range and time zone.
  - Zero-filled 3-series chart and an "N active days of M" note.
  - Newest-first table with empty state.
  - CSV with ISO day, plain decimal amount and a currency column; the file name carries the date range.
  - Subscription section shows status badges and empty states.
  - No new metrics or financial calculations.
- **Notifications:** All/Unread tabs with counts, type icons, unread highlight and "New" pill, absolute and relative time. Clicking marks that item read, then navigates. Links are built only from UUID-validated ids and only to routes the user's permissions allow; every target page re-reads through the tenant-scoped API. Mark-all reports success or failure, and the feed loads to the newest items.
- **Dispute detail:**
  - Separate **Decision** card: decision text, decision maker, decision time and status.
  - **Case details** grid: opened by, against, status, created, category, related ride.
  - Description in its own block; notes timeline with an isolated author, role and time.
  - Long text wraps.
  - Resolve and add-note workflows and permissions are unchanged.
- **Audit:**
  - Arabic/English action names for every code the backend emits, plus readable fallbacks for new ones; codes are kept.
  - Category filter (backend `action` prefix), period filter (`created_from`/`created_to`) and an advanced action-code search.
  - Actor shown with role labels; target type localized.
  - The expandable row shows labelled event data and technical details (code, target id, request id, copyable).
  - Read-only: records are never altered.
- **Members:** tab-strip arrows removed (shared fix). Role badge, account status and MFA status are separate columns; MFA shows "Not required" for drivers and riders. Empty states added. The confirm dialog shows the person and role as isolated parts. Backend role enforcement is untouched.
- **Policy:**
  - Eight business sections with a sticky section list (tab strip on smaller screens) and per-section explanations.
  - Status legend (approved / proposed awaiting approval / provisional, not approved).
  - Units beside inputs; minor-unit amounts previewed in currency; allowed range shown.
  - Client-side validation mirrors `validate_overrides` (range, integer, weights, tier ordering, document types). The server still decides, and its field errors are shown per parameter.
  - Weights and tier thresholds edited as labelled numeric fields; required documents as checkboxes.
  - Technical key, default and source hidden behind a "Technical details" switch.
  - Edited rows are highlighted; a sticky unsaved-changes bar offers discard and save; the browser warns before leaving.
  - Saving still uses the existing `POST admin/config` (a new version with a change note). The confirmation states that saving does not change approval status. Version history lists changed parameters by name.
  - No policy values or rules were changed.
- **Organization:** a header card with name and status, plus a responsive 4/2/1-column grid: workspace identifier (copyable), currency, minor units, time zone, default language, creation date. Read-only, with a platform-managed note.

## 5. Functional workflows verified (browser, local Docker stack, 2026-10-24)

The built-in browser was used against `http://localhost:3000` after `docker compose up -d --build admin`.

**Sign-in:**

- Operator: workspace, phone and development OTP, then the dashboard. The D033 dev bypass is active in the local stack.
- Platform: phone and password, then the platform overview.

**Operator workflows checked:**

- **Members:** the tab strip has no scroll arrows; dates are correct.
- **Policy:**
  - Entering 150 for "Estimate range" (allowed 0–100) shows an inline error, the "Edited" marker and the unsaved bar, and Save is disabled.
  - Discard restores 20. Nothing was saved.
- **Audit log:**
  - Rows show Arabic labels ("تسجيل الدخول", "عرض إيصال إيداع"…).
  - The expanded row shows labelled data and copyable technical ids.
  - The category filter sends `action=ride.`.
- **Notifications:**
  - Three unread items are listed.
  - Clicking "dispute opened" marked it read and opened `/operator/trust/disputes/<id>`.
- **Dispute detail:** decision, decider and timestamp render as separate elements.
- **Reports:**
  - 31-day axis with zero days; y-axis 0–4 for one ride; CSV button enabled.
  - Totals match the single returned row (1 requested, 1 matched).
- **Ratings:** empty state (no ratings exist; none fabricated).
- **Organization:** information grid renders.

**Language:** switched to English; `dir=ltr`, `lang=en`, the dispute page lays out LTR with no overflow. Switched back to Arabic.

**Responsive:** page-level horizontal overflow and unexpected nested vertical scroll areas inside `<main>` were measured by script on every operator route at 375px, and on selected routes at 768, 1280 and 1440px:

- **375px:** all 24 routes show 0 overflow after the fixes. Before the fixes, plans (105px), accounts (71px), audit (208px) and members (34px) overflowed.
- **Other widths:** 0 overflow on all checked routes.

**Security spot checks:**

- With a platform session, the deep link `/operator/members` redirects to `/platform`.
- `GET /api/proxy/admin/members` returns 403.

**Not covered:**

- Create/approve actions that would change demo data (inviting members, approving deposits, resolving disputes, saving a policy version) were not executed in the browser. Their code paths and API calls are unchanged; only presentation around them changed.
- Mark-all-as-read was not clicked in the browser (single-item mark-read was). The backend behaviour is covered by the new test.

## 6. RTL/LTR and responsive corrections

- Every mixed-value line now uses isolated elements (`MetaLine`, `PersonRole`, `<bdi>`); no concatenated bidi strings remain in the operator pages.
- Localized dates and money are isolated with their natural direction (`<bdi>`) instead of forced LTR. Phone numbers, codes and ids keep `ltr-nums`.
- Chart axes always run left → right with plain DD/MM labels; legends follow the page direction.
- Directional icons (breadcrumb chevrons, rating arrow, notification chevrons, policy before/after arrow) flip with `ltr:`/`rtl:` variants.
- Phones: KPI tiles use 2 columns with icons hidden under 400px; the range picker and tab strips scroll inside themselves; tables scroll inside their cards.
- Tablet: the policy section list becomes a tab strip.
- Desktop: a 3-column policy layout with sticky navigation.

## 7. Tests and results

| Check | Result |
|---|---|
| `tsc --noEmit` (apps/admin) | 0 errors |
| `eslint . --max-warnings=0` | 0 findings |
| Production build (`docker compose up -d --build admin`, runs `next build`) | Succeeded (rebuilt 5 times during the review; final build includes every change) |
| New backend test `test_notifications_report_read_state_and_mark_single_or_all` | Passed (covers read flag, single vs all, validation, cross-tenant cursor not marked) |
| Focused suites (`test_mfa_and_portal_api`, `test_realtime`, `test_platform_basics`) | 32 passed |
| Full backend suite | **126 passed** |
| `ruff check` / `ruff format --check` (changed files) | Clean |
| OpenAPI `spectacular --validate --fail-on-warn` | Passed; contract regenerated |

The admin app has no frontend unit-test runner. Frontend verification is the typecheck, lint, production build and the browser checks in §5.

## 8. Remaining limitations and backend dependencies

- **Members search:** the members API has no free-text search (`role`, `status` only). The UI offers role, status and group filters only; no search box was invented.
- **Notifications:** there is no unread-count endpoint, so the top-bar bell shows no badge. A badge would need a cheap count endpoint, which is a later backend addition. The feed reads up to 2,000 items (10 × 200) to start at the newest.
- **Audit search:** the free-text search is backend `action` startswith matching (code prefix), so it is labelled "advanced".
- **Policy approval:** the approval status of a parameter is defined in code (`apps/tenancy/policy.py`) and decided by the owner. The UI only displays it; saving never promotes it.
- **Reports:** the KPI completion share is `completed ÷ requested` over the returned rows. Fare totals are cash fares of completed rides as agreed in the app, not settled revenue.
- **Not exercised in the browser:** visual details of create/approve dialogs in demo data, the live map page with real moving drivers, and Arabic screen-reader output.
- **Not implemented:** global search and new widgets from the reference image, because no backend capability exists for them.

## 9. Commit

`0300cb0`

## 10. Local URLs for owner review

- Operator sign-in: http://localhost:3000/login. Workspace `demo-mukalla-admin`, phone `+967700000001`, development OTP.
- Platform sign-in: http://localhost:3000/platform/login (local demo platform admin).
- Ratings: http://localhost:3000/operator/trust/ratings
- Reports: http://localhost:3000/operator/reports
- Notifications: http://localhost:3000/operator/notifications
- Audit log: http://localhost:3000/operator/audit
- Members: http://localhost:3000/operator/members
- Policy settings: http://localhost:3000/operator/settings/policy
- Organization: http://localhost:3000/operator/settings/organization
- Disputes (open one for the detail view): http://localhost:3000/operator/trust/disputes
- API: http://127.0.0.1:8010

Restart command if the containers are not running the latest images:

```
docker compose up -d --build
```
