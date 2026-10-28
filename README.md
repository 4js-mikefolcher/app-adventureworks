# AdventureWorks Sales — Genero BDL application

A modular Genero BDL (FGL) application for managing the **Sales domain** of the
AdventureWorks sample database on PostgreSQL. Built for the Genero Browser
Client (GBC); the same source also runs under the Genero Desktop Client (GDC).

> This app is a **front end only**. It does not create or load the database.
> The `adventureworks` database must already exist and be populated by the
> separate [`fgl-adventureworks`](https://github.com/4js-mikefolcher/fgl-adventureworks)
> schema/data builder.

## What it manages

| Module | Tables | Capabilities |
|--------|--------|--------------|
| **Sales Orders** (centerpiece) | `salesorderheader` + `salesorderdetail` | Search, open, master-detail edit of header + line items, live totals, create new order |
| **Customers** | `customer` (+ `person`/`store`) | Query-by-example search, name resolution, territory reassignment, delete |
| **Sales Persons** | `salesperson` (+ `person`) | Browse, edit territory/quota/bonus/commission, delete |
| **Territories** | `salesterritory` | Full CRUD |
| **Special Offers** | `specialoffer` | Full CRUD |

### Derived values computed in 4GL
The PostgreSQL port drops AdventureWorks' computed columns, so the app
recomputes them: line total = `qty × price × (1 − discount)`, subtotal =
Σ line totals, total due = `subtotal + tax + freight`, order number = `'SO' || id`.

## Project layout

```
adventureworks.sch        Genero schema (68 tables, lowercase) — used at compile time
res/fglprofile.pgs        PostgreSQL connection profile (database name: adventureworks)
Makefile                  build / run / clean (sets FGLDBPATH, FGLLDPATH, FGLRESOURCEPATH)
bin/                      compiled output: all *.42m and *.42f (generated; git-ignore)
docs/
  CodingStandards.md      team coding standards (also imported by CLAUDE.md)
src/
  Makefile                compiles libs and helpers first, then each model before its controller, then main; then forms
  LibAw.4gl               shared: connect, SQL-error reporting, confirm, combobox fill, name lookups
  DialogHelper.4gl        helper: yes/no confirmation dialog (controllers only)
  SqlHelper.4gl           helper: SQL error text (no UI, models may use it)
  Main.4gl / Main.per     entry point + navigation menu
  TerritoriesModel.4gl       \  MVC feature: database record + writes,
  TerritoriesController.4gl   |  dialogs + list SELECT + conversion,
  Territories.per            /   and the form
  SpecialOffersModel.4gl       \  MVC feature, same shape as Territories plus the
  SpecialOffersController.4gl   |  validation in the model
  SpecialOffers.per            /
  Customers.4gl/.per       \  one module + form per domain
  SalesPersons.4gl/.per    /  (not yet split into model and controller)
  SalesOrders.4gl + SalesOrders.per + SalesOrdersList.per   master-detail centerpiece
  AwCalc.4gl              pure derived-value logic (line/order totals, status label, order no.)
  AwRepo.4gl              read-only data-access helpers (offer resolution, list price, existence)
tests/
  TestAwCalc.4gl          fglunit suite for AwCalc (pure, no DB)
  TestTerritories.4gl     fglunit suite for the Territories view-to-database conversion (no DB)
  TestSpecialOffers.4gl   fglunit suite for the SpecialOffers conversion and validation (no DB)
  TestData.4gl            fglunit suite for AwRepo + LibAw (live DB; skips if unavailable)
```

All compiled artifacts are written to `bin/` (via `fglcomp -o` / `fglform -o`).
The runtime finds them through `FGLLDPATH`/`FGLRESOURCEPATH` (set by the Makefile).

## Build & run

```bash
make build      # compile all .4gl and .per; any compiler warning fails the build
make run        # launch under the desktop client (GDC must be running)
make run-tui    # headless terminal run (connect smoke test; complex forms need a real client)
make clean      # remove compiled .42m / .42f
```

Connection details live in `res/fglprofile.pgs` (host `localhost:5432`, database
`adventureworks`). The app connects at runtime with `CONNECT TO "adventureworks"`.
`res/fglprofile.pgs` is git-ignored because it holds credentials: copy
`res/fglprofile.pgs.example` to `res/fglprofile.pgs` and set the password for your database.
Keep its `ifxemul.dblquotes = false` line: it lets the reserved-word columns
`salesterritory."group"` and `specialoffer."type"` be double-quoted in SQL. Without it the
driver sends them as string literals, so they read as the column's name and fail on write.

## Tests

Unit tests use **fglunit** (xUnit for Genero BDL; installed via `fglpkg install fglunit`).
Testable logic was extracted into two PUBLIC library modules so it can be exercised
directly: `AwCalc` (pure) and `AwRepo` (data-access).

```bash
make test     # compile + run all suites; writes bin/junit-*.xml
```

- **TestAwCalc** — 11 pure tests (line/order totals incl. NULL handling, status
  labels, order-number format). No database.
- **TestTerritories** — 3 tests of the JSON-bridge conversion from the view record to
  the database record (every crossing member populated and asserted not NULL). No database.
- **TestSpecialOffers** — 14 tests: the same conversion check, including the DATE to
  DATETIME special case, plus the date-range and quantity-range validation. No database.
- **TestData** — 12 tests over `AwRepo` and `LibAw` name resolution against the
  live database (name formats, fallbacks, the `(specialofferid, productid)` FK
  resolution, product price, existence). Connects once in `setupSuite`; if the DB
  is unreachable every test **skips** (the suite stays green), so it's CI-safe.

Each suite is a standalone program — run one directly with the documented flags:

```bash
eval "$(fglpkg env)" && export FGLLDPATH="$PWD/bin:$FGLLDPATH"
fglrun bin/TestAwCalc.42m -v
fglrun bin/TestData.42m --filter ResolveOffer --junit out.xml
```

### Running under GBC
GBC rendering requires the Genero Application Server (GAS). Point a GAS
application configuration at `bin/Main.42m` (with `FGLDBPATH`/`FGLRESOURCEPATH`
as in the Makefile), or launch the app through Genero Studio's embedded GAS.
`make run` / GDC is the quickest path for local functional testing.

## Conventions

- Authoritative Genero guidance comes from the **Genero MCP skills** (see
  `CLAUDE.md`), not from model memory.
- Genero code follows the team [coding standards](docs/CodingStandards.md)
  (3-space indent, camelCase, `VAR` locals, typed signatures, `IMPORT FGL`).
- Static SQL where possible; parameterised dynamic SQL otherwise; all writes in
  short `BEGIN/COMMIT WORK` transactions with `TRY/CATCH` error handling.
- Reserved-word columns (`salesterritory."group"`, `specialoffer."type"`) are
  mapped to safe record members and quoted in SQL.
- Foreign-key/constraint violations surface as friendly messages via
  `LibAw.awSqlError()`.

## Notes & limitations

- **Customers / Sales Persons** do not offer *Add*: a row there must reference an
  existing person/store/employee, which is outside the Sales scope.
- **Order lines** are restricted to products that are for sale (present in
  `specialofferproduct`); the `(specialofferid, productid)` composite FK is
  enforced and a valid offer is resolved at save time.
- Order line items are saved with a delete-all + insert-all strategy
  (`salesorderdetail` is a leaf table) inside one transaction.
