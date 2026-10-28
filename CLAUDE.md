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
  named `TYPE`s and `IMPORT FGL` only (no linking). Rules 11-12 (MVC separation and
  no cross-referencing) are **not yet applied**: the domain modules still mix
  model and controller code and import `LibAw`/`AwCalc`/`AwRepo`. Do not restructure
  them without the user's go-ahead. When asked, ask first about navigation from one
  feature to another; the rest is settled in rules 11 and 12: helpers
  (`<Role>Helper.4gl`), lookups (`<Feature>Lookup.4gl`), the entry point
  (`MainController.4gl`, `MainMenuController.4gl`), and each `SELECT` living with the
  module it supports (UI reads in the controller, validation and write-guard reads in
  the model).
- Locals use `VAR` under the standards, so the "`DEFINE` must be at top of
  FUNCTION/MAIN" note in the upstream block above only governs legacy `DEFINE`.

### Environment
- Database name: `adventureworks` (connect via `res/fglprofile.pgs`, driver `dbmpgs_9`).
- Schema file: `adventureworks.sch` in the project root — 68 lowercase tables.
  Set `FGLDBPATH` to the project root so `SCHEMA adventureworks` resolves when
  compiling modules and forms (the Makefiles do this).
- Build with `make build`; run with `make run` (GDC) — see README for GBC/GAS.
- Every compiler warning fails the build: `fglcomp -Wall -Werror` for modules and tests,
  `fglform -W all` (output-checked) for forms. Fix the code; do not relax `WARNFLAGS`.
- This app does **not** build or load the database (that is `fgl-adventureworks`).

### Architecture
- Modular per-domain: one `.4gl` + `.per` per entity (`Customers`, `SalesOrders`,
  `SalesPersons`, `Territories`, `SpecialOffers`), a shared `LibAw.4gl`, and
  `Main.4gl` for navigation. Each domain module exposes one `*Run()` entry
  (`customersRun()`, `salesOrdersRun()`, ...), called module-qualified from `Main`.
- Reuse `LibAw`: `awConnect()`, `awDisconnect()`, `awSqlError()`, `awConfirm()`,
  `awFillComboBox()`, `awCustomerLabel()`, `awSalesPersonLabel()`.
- Testable logic lives in two PUBLIC leaf libraries: `AwCalc.4gl` (pure
  derived-value math/labels) and `AwRepo.4gl` (read-only data-access). Domain
  modules call into these rather than reimplementing logic inline. Put new pure
  or data-access logic here (not in PRIVATE dialog functions) so it stays testable.

### Testing (fglunit)
- Suites are in `tests/`; run with `make test` (writes `bin/junit-*.xml`).
- A test program is a `.4gl` with a `MAIN` that does:
  `CALL CliArgs.parse()` (enables `--junit`/`--filter`/`-v`/`--fail-fast`),
  `CALL FglUnit.suite(...)`, one `FglUnit.register("name", FUNCTION name)` per
  test, then `EXIT PROGRAM FglUnit.run()`. Tests are PUBLIC, parameterless.
- fglunit can only call PUBLIC functions of an imported module — PRIVATE
  functions are untestable from outside (another reason to extract logic into
  `AwCalc`/`AwRepo`).
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
  double-quoted in SQL and mapped to safe record members (`groupName`, `offerType`).
- AdventureWorks computed columns were **dropped** in the PG port
  (`salesorderdetail.linetotal`, `salesorderheader.salesordernumber`/`totaldue`,
  `customer.accountnumber`) — compute them in 4GL, never SELECT them.
- `salesorderdetail` has a composite FK on `(specialofferid, productid)` into
  `specialofferproduct`: only sellable products may be ordered, and the offer must
  be valid for the product (resolved in `AwRepo.repoResolveOffer()`).
- Dialogs and `ui.ComboBox.forName()` address a form item by its **field name**
  (`FORMONLY.x` / `table.column`), never its layout tag: a tag gives `-8015` /
  `-1102` or a silently empty combobox.
- Static SQL qualifies every column with its table (`customer.customerid`):
  identifiers are case-insensitive, so an unqualified `status` or `productid` is
  compiled as a host variable when a variable of that name exists. Check with
  `fglcomp -S`.
