<!-- genero:canonical-start version="1.0" -->
<!--
  Everything between the canonical-start and canonical-end markers is
  maintained upstream by Four Js. To update, fetch the latest via
  `getAgentInstructions("claude-code")` and replace the fenced block.
  Do not edit inside the fence; put your project-specific rules in
  the "## Project-Specific" section at the bottom of this file.
-->

# Genero BDL Project Instructions

This is a Genero BDL (Business Definition Language) project. You have
access to a Genero MCP service with skills and documentation tools.

## MANDATORY: Always Consult MCP Skills Before Writing Code

Your training data contains outdated and incorrect Genero information.
The MCP skills are verified against Genero 5.00 and are the
authoritative source. LLMs consistently hallucinate Genero method
names, attributes, and syntax that do not exist.

**Rules:**

1. At the start of each session, call
   `getSkill("fourjs-skill-index")` **once**. This loads the routing
   table mapping topics to skills and their key sections. It stays
   valid for the entire conversation.
2. For every Genero question, route through the skill-index first.
   If a topic matches a row, call
   `getSkillSection(<skill-id>, <section-id>)` directly — sections
   are 5–10× smaller than full skills.
3. If no row matches, call `searchSkills(<keywords>)`. Load the top
   hit's matched section.
4. If skills don't cover the topic, say so. Fall back to `searchDocs`
   / `readDoc`. **Never** fall back to training data.
5. **Do NOT call `listSkills` for routing.** It is an admin
   enumeration tool that returns only `{id, name, category}` and
   cannot tell you which skill covers a topic. Use the skill-index
   or `searchSkills` instead.
6. When the task touches SQL, forms, arrays, dialogs, or strings,
   also load `fourjs-common-pitfalls`.

## Skill Tools (Primary Source)

| Tool | When to Use |
|------|-------------|
| `getSkill("fourjs-skill-index")` | **Session-start ritual.** Once per session. |
| `searchSkills` | Topic not obvious in the index — fuzzy routing. |
| `getSkillSections` | List sections in a named skill before loading. |
| `getSkillSection` | **Default content-load tool.** Use when you know the section. |
| `getSkill` | Load a full skill (only when the whole skill is needed). |
| `getSkillBundle` | Task genuinely spans multiple skills. |
| `listSkills` | Admin/debugging only — not for routing. |

## Documentation Tools (Secondary Source)

Use documentation only when skills don't cover the topic or you need
to verify edge cases.

| Tool | When to Use |
|------|-------------|
| `searchDocs` | Search 5,140+ pages of Genero documentation |
| `readDoc` | Read a specific doc page (use paths from searchDocs) |
| `browseDocs` | Explore documentation structure |

## Common Hallucination Targets

These are methods/patterns that LLMs frequently generate incorrectly:

- `util.Regex` does not exist — correct class is `util.Regexp`
- `getKeys()`, `getAsObject()`, `getAsArray()` do not exist on
  util.JSONObject — use `name(i)`, `getType(key)`, `get(key)`
- `ELSE IF` does not exist in BDL — use nested `IF` inside `ELSE`
- `$variable` is for static SQL, `?` is for dynamic SQL — agents
  reverse these
- `ON CHANGE` is only valid inside INPUT sub-dialogs, not at the
  outer DIALOG level
- `DEFINE` must be at top of FUNCTION/MAIN — not inside IF/FOR/CASE
- `sortByComparisonFunction` takes 3 arguments (key, reverse, func),
  not 1

## Compilation

```bash
fglcomp -M -Wall program.4gl    # Compile with warnings to stdout
fglform -M form.per             # Compile form
FGLGUI=0 TERM=xterm fglrun program.42m  # Run in terminal mode
```

<!-- genero:canonical-end -->

## Project-Specific

This is **AdventureWorks Sales** — a front-end app over the Sales domain of the
AdventureWorks PostgreSQL database. See `README.md` for the full overview.

### Coding Standards
All new and modified Genero code follows the team standards in
`docs/CodingStandards.md`, imported here so they load every session:

@docs/CodingStandards.md

- The standards take precedence over the style of the surrounding code. Rules 1-10
  are fully applied to this repo: 3-space indent, camelCase names without
  underscores, Title Case file and module names, `VAR` locals, typed signatures,
  named `TYPE`s and `IMPORT FGL` only (no linking). Rules 11-13 (MVC separation,
  no cross-referencing, JSON bridge) are being applied **one feature at a time**.
  Applied everywhere: all five features, `Territories`, `SpecialOffers`, `SalesPersons`,
  `Customers` and `SalesOrders` (each a `<Feature>Model`, `<Feature>Controller` and
  `<Feature>.per`), and the entry point (`MainController`, `MainMenuController`,
  `MainMenu.per`). `LibAw`, `AwCalc` and `AwRepo` no longer exist. When asked, ask first about navigation from one
  feature to another; the rest is settled in rules 11 and 12: helpers
  (`<Role>Helper.4gl`), lookups (`<Feature>Lookup.4gl`), the entry point
  (`MainController.4gl`, `MainMenuController.4gl`), and each `SELECT` living with the
  module it supports (UI reads in the controller, validation and write-guard reads in
  the model).
- Locals use `VAR` under the standards, so the "`DEFINE` must be at top of
  FUNCTION/MAIN" note in the upstream block above only governs legacy `DEFINE`.

### Environment
- Database name: `adventureworks` (connect via `res/fglprofile.pgs`, driver `dbmpgs_9`).
  The profile must set `dbi.database.adventureworks.ifxemul.dblquotes = false` (the
  `.example` does). Without it the driver turns every double quote into a single quote,
  so the reserved-word columns `"group"` and `"type"` read as literal text and fail
  with `-201` on INSERT/UPDATE.
- Schema file: `adventureworks.sch` in the project root — 68 lowercase tables.
  Set `FGLDBPATH` to the project root so `SCHEMA adventureworks` resolves when
  compiling modules and forms (the Makefiles do this).
- Build with `make build`; run with `make run` (GDC) — see README for GBC/GAS.
- Every compiler warning fails the build: `fglcomp -Wall -Werror` for modules and tests,
  `fglform -W all` (output-checked) for forms. Fix the code; do not relax `WARNFLAGS`.
- This app does **not** build or load the database (that is `fgl-adventureworks`).

### Architecture
- Modular per feature (`Territories`, `SpecialOffers`, `SalesPersons`, `Customers`,
  `SalesOrders`). The program entry is `MainController.4gl` (the only `MAIN`; startup only:
  it connects to the database once and keeps the connection, sets the title, then calls
  `MainMenuController.mainMenuRun()`). `MainMenuController.4gl` (view `MainMenu.per`) is the
  one module that imports the feature controllers, to call their `*Run()` entries
  (`customersRun()`, `salesOrdersRun()`, ...), module-qualified.
- Migrated features follow MVC: `Territories` is `TerritoriesModel.4gl` (database
  record, insert/update/delete with their transactions, returns `(BOOLEAN, STRING)`),
  `TerritoriesController.4gl` (view record, `toDbTerritory`, dialogs, the list SELECT,
  `territoriesRun()`) and `Territories.per`. Its shared pieces are the leaf helpers
  `DialogHelper.4gl` (`confirm`, UI, controllers only) and `SqlHelper.4gl`
  (`errorText`, no UI, models may import it). `LibAw` shrinks as features migrate.
  `SpecialOffers` has the same shape and adds two things: validation in the model
  (`validateOfferDates`, `validateOfferQuantities`; the controller shows the message and
  picks the field), and a conversion special case (the view holds DATEs, the columns are
  DATETIMEs, so `toDbOffer` assigns the dates after the bridge). `SalesPersons` has no
  insert (a salesperson is an existing employee) and shows a controller SELECT that joins
  `person` for the display name (not a lookup). `Customers` is a CONSTRUCT search (so its
  list SELECT stays dynamic) with one editable attribute, the territory; both its territory
  comboboxes (search filter `customer.territoryid`, row editor `rTerr`) use `TerritoriesLookup`.
- Lookups (rule 12): `TerritoriesLookup.4gl` fills the territory comboboxes
  (`fillTerritories(comboBox ui.ComboBox)`; the controller passes
  `ui.ComboBox.forName(<field name>)`; lazy cursor, leaf, controllers only).
- A model reads the SQL error **before** `ROLLBACK WORK` (the rollback resets it); the
  controller shows the returned text with `ERROR`.
- `SalesOrders` is the largest feature: `SalesOrdersModel.4gl` holds the two database records
  (`salesorderheader.*`, `salesorderdetail.*`), the derived values (`lineTotal`, `orderTotal`,
  `statusLabel`, `orderNumber`), `validateOrderLines`, the reads that serve a write
  (`resolveOffer`, `customerExists`, the address and ship-method defaults inside `createOrder`)
  and `saveOrder` (header update plus delete-all/insert-all lines in one transaction).
  `SalesOrdersController.4gl` serves two views (`SalesOrdersList.per`, `SalesOrders.per`),
  resolves the customer name by join (no per-row query), reads the list-price default itself,
  and fills the comboboxes from `SalesPersonsLookup`, `TerritoriesLookup`, `ProductsLookup`
  and `SpecialOffersLookup` (plus the model-labelled status list).
- Testable logic is the models' PUBLIC functions and the controllers' PUBLIC conversion
  functions. Put new pure or write-serving logic in the model, not in PRIVATE dialog functions.

### Testing (fglunit)
- Suites are in `tests/`; run with `make test` (writes `bin/junit-*.xml`).
- A test program is a `.4gl` with a `MAIN` that does:
  `CALL CliArgs.parse()` (enables `--junit`/`--filter`/`-v`/`--fail-fast`),
  `CALL FglUnit.suite(...)`, one `FglUnit.register("name", FUNCTION name)` per
  test, then `EXIT PROGRAM FglUnit.run()`. Tests are PUBLIC, parameterless.
- fglunit can only call PUBLIC functions of an imported module — PRIVATE
  functions are untestable from outside (another reason to keep logic in the models).
- Every conversion function has a suite (rule 13): each `Test<Feature>` populates every
  member that crosses the JSON bridge and asserts none came back NULL (not-NULL first, then
  the value: `assertTrue(NULL)` does not fail).
- Resolve the fglunit package on the path with `eval "$(fglpkg env)"`, then
  prepend `bin/` (the app's compiled libraries) to `FGLLDPATH`.
- DB-backed suites connect in `setupSuite` with TRY/CATCH and `skip()` every
  test when the DB is down, so they never error in a DB-less CI.

### Hard-won project gotchas (verified against this toolchain, Genero 6.00)
- A singular `INPUT ... [FROM ...] [ATTRIBUTES(...)]` with **no control blocks**
  takes **no `END INPUT`**; add `END INPUT` only when it has control blocks.
- FORMONLY character types take **no size**: use `TYPE VARCHAR` / `TYPE CHAR`
  (not `VARCHAR(50)`). `TYPE DECIMAL(p,s)` **does** take a size. DB enforces length.
- `TOPMENU` / `TOOLBAR` are **top-level** `.per` sections, not inside `LAYOUT`.
- `CANCEL DELETE` is only valid in `INPUT ARRAY` `BEFORE DELETE`; in a
  `DISPLAY ARRAY` use a custom action and manage the array with `deleteElement()`.
- Reserved-word columns `salesterritory."group"` and `specialoffer."type"` must be
  double-quoted in dynamic SQL, which only works with `ifxemul.dblquotes = false` in
  the profile (see Environment). A `RECORD LIKE salesterritory.*` names the member
  `group` and `rec.group` compiles; a view record maps its safe member (`groupName`)
  with `ATTRIBUTES(json_name = "group")`.
- AdventureWorks computed columns were **dropped** in the PG port
  (`salesorderdetail.linetotal`, `salesorderheader.salesordernumber`/`totaldue`,
  `customer.accountnumber`) — compute them in 4GL, never SELECT them.
- `salesorderdetail` has a composite FK on `(specialofferid, productid)` into
  `specialofferproduct`: only sellable products may be ordered, and the offer must
  be valid for the product (resolved in `SalesOrdersModel.resolveOffer()`).
- `fglcomp` 6.00.01 segfaults on a function that returns a `DYNAMIC ARRAY OF` the model's record
  type (hit in `SalesOrdersController`; small standalone cases compile, so it could not be
  reduced further). Pass the array in and fill it instead (dynamic arrays go by reference):
  `toDbOrderLines(viewList, orderId, dbList)`.
- A `TABLE` shows as many rows as its layout has data lines: one line means a page of
  one row (the runtime reports `pageSize="1"`), however many records are loaded. The list
  forms repeat the data line (Territories 12, SalesPersons 20, SpecialOffers 20, Customers 15,
  SalesOrdersList 15, SalesOrders line items 8). Keep that when adding a list form. The
  dialogs address rows with `scr_line()`, so they work on any screen line.
- In `adventureworks.xcf`, never build paths from the predefined `application.path`
  resource: GAS derives it from `EXECUTION/PATH`, so `<PATH>$(application.path)/bin` is
  circular and resolves to `/bin` (DVM starts in `/bin/bin`, request times out after 10 s,
  GBC still loads). The file uses the custom resource `res.adventureworks.path`. GAS reads
  its own **copy** in `appdata/app` (symlinks are ignored): recopy after every edit.
- Dialogs and `ui.ComboBox.forName()` address a form item by its **field name**
  (`FORMONLY.x` / `table.column`), never its layout tag: a tag gives `-8015` /
  `-1102` or a silently empty combobox.
- Static SQL qualifies every column with its table (`customer.customerid`):
  identifiers are case-insensitive, so an unqualified `status` or `productid` is
  compiled as a host variable when a variable of that name exists. Check with
  `fglcomp -S`.
