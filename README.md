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
src/
  Makefile                compiles lib first, then domain modules, then main; then forms
  lib_aw.4gl              shared: connect, SQL-error reporting, confirm, combobox fill, name lookups
  main.4gl / main.per     entry point + navigation menu
  territories.4gl/.per    \
  specialoffers.4gl/.per   |  one module + form per domain
  customers.4gl/.per       |  (modular per-domain architecture)
  salespersons.4gl/.per    |
  salesorders.4gl + salesorders.per + salesorders_list.per   master-detail centerpiece
  aw_calc.4gl             pure derived-value logic (line/order totals, status label, order no.)
  aw_repo.4gl             read-only data-access helpers (offer resolution, list price, existence)
tests/
  test_aw_calc.4gl        fglunit suite for aw_calc (pure, no DB)
  test_data.4gl           fglunit suite for aw_repo + lib_aw (live DB; skips if unavailable)
```

All compiled artifacts are written to `bin/` (via `fglcomp -o` / `fglform -o`).
The runtime finds them through `FGLLDPATH`/`FGLRESOURCEPATH` (set by the Makefile).

## Build & run

```bash
make build      # compile all .4gl and .per (zero errors/warnings expected)
make run        # launch under the desktop client (GDC must be running)
make run-tui    # headless terminal run (connect smoke test; complex forms need a real client)
make clean      # remove compiled .42m / .42f
```

Connection details live in `res/fglprofile.pgs` (host `localhost:5432`, database
`adventureworks`). The app connects at runtime with `CONNECT TO "adventureworks"`.
`res/fglprofile.pgs` is git-ignored because it holds credentials: copy
`res/fglprofile.pgs.example` to `res/fglprofile.pgs` and set the password for your database.

## Tests

Unit tests use **fglunit** (xUnit for Genero BDL; installed via `fglpkg install fglunit`).
Testable logic was extracted into two PUBLIC library modules so it can be exercised
directly: `aw_calc` (pure) and `aw_repo` (data-access).

```bash
make test     # compile + run both suites; writes bin/junit-*.xml
```

- **test_aw_calc** — 16 pure tests (line/order totals incl. NULL handling, status
  labels, order-number format, date-range validation). No database.
- **test_data** — 12 tests over `aw_repo` and `lib_aw` name resolution against the
  live database (name formats, fallbacks, the `(specialofferid, productid)` FK
  resolution, product price, existence). Connects once in `setUpSuite`; if the DB
  is unreachable every test **skips** (the suite stays green), so it's CI-safe.

Each suite is a standalone program — run one directly with the documented flags:

```bash
eval "$(fglpkg env)" && export FGLLDPATH="$PWD/bin:$FGLLDPATH"
fglrun bin/test_aw_calc.42m -v
fglrun bin/test_data.42m --filter resolve_offer --junit out.xml
```

### Running under GBC
GBC rendering requires the Genero Application Server (GAS). Point a GAS
application configuration at `src/main.42m` (with `FGLDBPATH`/`FGLRESOURCEPATH`
as in the Makefile), or launch the app through Genero Studio's embedded GAS.
`make run` / GDC is the quickest path for local functional testing.

## Conventions

- Authoritative Genero guidance comes from the **Genero MCP skills** (see
  `CLAUDE.md`), not from model memory.
- Static SQL where possible; parameterised dynamic SQL otherwise; all writes in
  short `BEGIN/COMMIT WORK` transactions with `TRY/CATCH` error handling.
- Reserved-word columns (`salesterritory."group"`, `specialoffer."type"`) are
  mapped to safe record members and quoted in SQL.
- Foreign-key/constraint violations surface as friendly messages via
  `lib_aw.aw_sql_error()`.

## Notes & limitations

- **Customers / Sales Persons** do not offer *Add*: a row there must reference an
  existing person/store/employee, which is outside the Sales scope.
- **Order lines** are restricted to products that are for sale (present in
  `specialofferproduct`); the `(specialofferid, productid)` composite FK is
  enforced and a valid offer is resolved at save time.
- Order line items are saved with a delete-all + insert-all strategy
  (`salesorderdetail` is a leaf table) inside one transaction.
