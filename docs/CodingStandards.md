# Genero BDL Coding Standards

Team coding standards for Genero BDL code in this repository. Claude Code loads this file through the project `CLAUDE.md`; developers follow it too.

**Scope:** Genero BDL source: `.4gl` modules, plus `.per`, `.str`, `.4st`, `.4ad`, `.4tb` and `.4tm` resource files. Ignore this document for any other language.

**How to apply:** All new code, and every line you modify, follows these rules. Do not reformat or rename untouched code, and do not rename files, unless the user asks for a migration. If a project instruction conflicts with a rule below, tell the user instead of choosing silently.

## The standards

1. **Indent 3 spaces per nesting level** in `.4gl` files, never tabs. This covers function and `MAIN` bodies, dialog blocks (`DIALOG`, `INPUT`, `DISPLAY ARRAY`, `MENU`) and their control blocks (`ON ACTION`, `BEFORE ROW`, ...), and flow control (`IF`, `CASE`, `FOR`, `WHILE`, `FOREACH`, `TRY`/`CATCH`). `ELSE`, `WHEN` and `CATCH` align one level inside their parent.
2. **Capitalize all keywords, and write every other Genero symbol in its actual case.** Keywords are capitalized: statements, data types (`INTEGER`, `STRING`, `DYNAMIC ARRAY OF`), literals (`TRUE`, `FALSE`, `NULL`), keyword-like operators that the compiler accepts in any case (`SFMT`, `TODAY`, `MDY`, `CURRENT`, `SQLERRMESSAGE`), and SQL keywords inside SQL text. Every other built-in symbol keeps the exact case it is defined with, and is never capitalized because it looks like a keyword: functions (`length`, `arr_curr()`, `scr_line()`, `downshift()`, `fgl_getenv()`), registers (`status`, `int_flag`, `sqlca.sqlcode`), classes and methods (`ui.ComboBox.forName()`, `util.JSON.stringify()`, `getLength()`, `clear()`), and table and column names. `fglcomp -Wall` enforces it: a wrong case is warning `-8440 Case considerations, expecting <name>`, which also names the actual case, so a build must show no `-8440` warnings (verified: `LENGTH(...)` warns expecting `length`, `ARR_CURR()` expecting `arr_curr`).
3. **Variable, parameter and function names are camelCase:** lower-case first letter, capital on each later word (`customerId`, `loadOrders`).
4. **No underscores** in variable, function or file names, and **no prefixes except these roles**, each followed by a camelCase name: `t` for types (`tOrder`), `c` for constants (`cMaxRows`), `curs` for cursors (`cursOrders`), `stmt` for prepared statements (`stmtDetailInsert`), `w` for windows (`wOrders`) and `sr` for screen records (`srOrders`). Nothing else takes a prefix: no scope or role prefixes (`m_`, `l_`, `p_`, `g_`, `_helper`) on variables, parameters or functions.
5. **File names are Title Case:** every word capitalized and joined (`SalesOrders.4gl`, `SalesOrders.per`). The file name, the `IMPORT FGL` module name and the form name in `OPEN WINDOW ... WITH FORM` must match exactly. Tool-mandated names (`Makefile`, `README.md`, `CLAUDE.md`, `LICENSE`, `fglpkg.json`, the `.sch` named after its database) are exempt.
6. **Every function has a complete signature:** every parameter has a data type, and every function has a `RETURNS` clause. A function that returns nothing writes `RETURNS ()`. Never use the legacy untyped `FUNCTION f(a, b)` + `DEFINE` form.
7. **No global variables.** Never use `GLOBALS`. Shared state is a module-level `PUBLIC DEFINE` or `PRIVATE DEFINE`; expose private state to other modules through functions.
8. **Local variables use `VAR`, never `DEFINE`.** Declare each one before its first use, normally at the top of the function. `DEFINE` appears only at module level.
9. **Every record has a named `TYPE` declared at module level.** No anonymous `RECORD ... END RECORD` in a variable, parameter or array declaration: declare `TYPE tOrder RECORD ... END RECORD` (or `RECORD LIKE table.*`), then use `tOrder` everywhere.
10. **The build uses `IMPORT FGL`, never linking.** No `fgl2p`, no `fgllink`, no `.42r` link step, no `GLOBALS "file"`. Compile each module with `fglcomp -M -Wall -Werror` and each form with `fglform -M -W all`, so that any warning fails the build (`fglform` has no error switch and still writes the form when it only warns, so the build must check its output and delete the form). Output goes to one directory that is on `FGLLDPATH`, libraries before the modules that import them, and you run `fglrun Main.42m`.

11. **MVC: separate concerns into view, model and controller.** Every feature is split into three kinds of file:
    - **View**: the `.per` form, plus its presentation resources (`.4st`, `.4ad`, `.4tb`, `.4tm`, `.str`). Layout and field attributes only, no business logic.
    - **Model**: a `.4gl` data model. It owns the data changes (`INSERT`, `UPDATE`, `DELETE`) with their transactions, the validation, the derived-value rules, and the public `TYPE` of its database record. It also owns every `SELECT` that serves its own writes and validation: that a referenced row exists, that a value is unique, that the row has not changed since the user loaded it, or a key the write itself must resolve. Those reads run in the model, inside the write's transaction when there is one. It has no UI: no `DISPLAY`, `MESSAGE`, `ERROR`, `MENU`, `PROMPT`, `OPEN WINDOW` or `ui.*`. It reports success or failure through return values, and the controller shows them.
    - **Controller**: a `.4gl` holding the dialogs (`INPUT`, `DISPLAY ARRAY`, `CONSTRUCT`, `DIALOG`, `MENU`) and the user flow (windows, navigation, confirmations, messages), plus the `TYPE` of the view record it displays and the conversion between that and the database record (rule 13). It calls the model for every write and validation. It owns the `SELECT` statements that serve the user interface: finding the records the user will view, change or delete (lists, search results built from `CONSTRUCT`, reloading a row for display), because those reads are driven by the dialog. Combobox contents that come from another feature's data are filled by that feature's lookup module (rule 12). Each `SELECT` is written for the specific view record it fills: an explicit column list in that record's member order, read `INTO rec.*`, never `SELECT *` and never a generic reader shared by different record shapes. The controller contains no `INSERT`, `UPDATE`, `DELETE` or transaction.

    Name them `<Feature>Model.4gl`, `<Feature>Controller.4gl` and `<Feature>.per`. **A `SELECT` belongs to the module it supports:** a read that lets the user find a record to view, change or delete is the controller's, and a read that validates data or checks that it was not changed is the model's. New code follows MVC from the start; existing files that mix concerns are restructured only when the user asks for a migration. **If something does not clearly belong to the view, model or controller, stop and ask the user before placing it.** Do not guess; the answer becomes a refinement of this standard.
12. **No cross-referencing between modules; keep them loosely coupled.** A controller imports its own model and nothing else, except helpers and lookups. A model imports no other module of the application, except helpers that contain no UI. No module imports a sibling feature's controller or model. **Helper modules are the first sanctioned exception:** code shared by several features lives in a module named `<Role>Helper.4gl` (for example `DialogHelper.4gl`). A helper is a leaf: it imports no application module and knows nothing about any feature. Controllers may import helpers; a model may import only a helper that contains no UI (rule 11). (Genero base packages such as `security`, `util`, `os` and `fgldialog` are not application modules and may be imported; a test suite imports the module under test.) **Lookup modules are the second sanctioned exception.** The contents of a combobox that come from another feature's data, such as the salespeople or territories a form offers, are filled by a module named `<Feature>Lookup.4gl`, grouped by the feature that owns the data (`CustomersLookup.4gl`, `SalesPersonsLookup.4gl`). Each lookup function takes the combobox as a parameter and fills it, replacing what it held (`fillSalesPersons(comboBox ui.ComboBox) RETURNS ()`); the controller finds the combobox by its field name and passes it in. The `SELECT` inside is written for the record it reads (rule 11), and its cursor is declared lazily, on the first call. That cursor lives as long as the database connection and fails with `-404` after a reconnect, so the program connects once at startup. A lookup need not be backed by a table: a fixed list of items is a lookup too. A lookup is a leaf that imports no application module, and it is a controller helper only: any controller may import a lookup, its own feature's or another's, and a model never does (it runs its own `SELECT`s for validation, rule 11). **The program entry point is the third sanctioned exception.** In a single-program application the entry module is `MainController.4gl`, never `Main.4gl`, so that the module name cannot be confused with the `MAIN` block (`Main.MAIN`). It holds `MAIN` and does startup only: the database connection, logging, initializers, styles and the like, with no feature logic and no data access. It then hands over to the application menu, `MainMenuController.4gl`, which is the one controller that may import other features' controllers, and only to call their entry functions. A system made of several `fglrun` programs works differently: `MainMenuController.4gl` is the launcher and starts the other programs as separate processes without importing them, and each of those programs has a `<Feature>Controller.4gl` that holds its own `MAIN` block and the usual controller content. Startup code shared by several programs lives in a helper. Registry or plug-in schemes, where features register themselves, are not part of this standard. Any other need that would require another reference is outside these definitions, so stop and ask the user how to structure it instead of adding an import. Typical case: navigation from one feature to another.

13. **The controller converts between the view record and the database record with the JSON bridge.** The view record (what the screen or list shows; it may blend several tables and differ from the columns in names and types) and the database record (what the model reads and writes) are separate `TYPE`s. The controller owns one conversion function per direction, `toDb<Name>` and `toView<Name>`, which copies the matching members through `util.JSONObject`:

    ```4gl
    CALL util.JSONObject.fromFGL(viewRec).toFGL(dbRec)
    ```

    The bridge is the default, not the whole function: add the extra logic a special case needs after the bridge call (see the verified behavior below). Make conversion functions `PUBLIC` so fglunit can test them.

14. **Reset `int_flag` before every dialog.** Write `LET int_flag = FALSE` immediately before every dialog statement (`INPUT`, `INPUT ARRAY`, `CONSTRUCT`, `DISPLAY ARRAY`, `DIALOG`, `MENU`), in the function that runs it, including a dialog whose result you do not read. The runtime only ever sets `int_flag` to TRUE (when a singular dialog is cancelled or closed) and never clears it, not even when a later dialog is accepted, so a stale TRUE left by any earlier dialog makes `RETURN (NOT int_flag)` report a cancel for a search or an input the user accepted. Verified in the running app: after closing the Territories list, pressing Accept on the Sales Orders search closed the window and went back to the menu, and so did the Customers search. The manual gives the same advice (User interruption handling): "`int_flag` is not reset to `FALSE` when the automatic 'accept' action is fired. Therefore, it is good practice to initialize `int_flag` to `FALSE`, before starting a singular dialog." Test `int_flag` straight after the dialog it belongs to. (`MENU` never touches `int_flag` and a multiple `DIALOG` sets it only through `CANCEL DIALOG`; the `DISPLAY ARRAY` triggers `ON INSERT`, `ON APPEND`, `ON UPDATE` and `ON DELETE` use it as their verdict and reset it before running; a singular dialog with an explicit `ON ACTION close` handler does not set it on close. The rule still applies to all of them, so that it holds for every dialog and can be checked by reading.)
15. **Never use `PROMPT`.** It is in Genero only for Informix-4GL compatibility. To ask the user for a value, open a small window on a form (a `.per` view, rule 11) and run an `INPUT` on it, so the dialog is laid out, styled and cancelled like every other screen: `OPEN WINDOW wNewOrder WITH FORM "NewOrder" ATTRIBUTES(TEXT = "New order", STYLE = "dialog")`, then `INPUT customerId FROM customerId`, then `CLOSE WINDOW wNewOrder`.

## Supporting rules (needed to make the standards safe)

- **`VAR` details.** It needs a type or an initial value: `VAR x` is `-6609` and `VAR x = NULL` is `-8422`. Inference copies the exact type and size, so write the type when a value can grow (`VAR name STRING = getName()`). Scope ends at the `END` of the enclosing block, so declare at function level anything used after a block. Redeclaring a name in a nested block is `-4319`. An unused `VAR` is a compile error even without `-Wall`. `VAR` is rejected at module level. Never name a variable after a BDL keyword: `RETURN label` fails to parse (`-6609`) because `LABEL` is a keyword.
- **Identifiers are case-insensitive, so camelCase can collide with column names.** `customerId` is the same identifier as column `customerid`, and in static SQL an unqualified match compiles into a host variable. Verified: `WHERE customerid = customerId` became `WHERE ? = ?`. Always qualify columns with their table in static SQL (`customer.customerid = customerId`), never give a variable the same name as a column used in that statement, and check with `fglcomp -S`.
- **Read the SQL error before `ROLLBACK WORK`.** A successful rollback resets `sqlca.sqlcode` to 0 and `SQLERRMESSAGE` to empty. Capture them first (`LET errorText = SQLERRMESSAGE`, as the worked example does) and test the captured code, never `sqlca.sqlcode` after the rollback. Verified: for a blocked `DELETE` the code was `-691` before the rollback and `0` after, so a test of the code placed after it can never match.
- **A reserved-word column such as `salesterritory."group"` needs `dblquotes = false`.** By default the database interface turns every double quote in SQL, dynamic SQL included, into a single quote (FGLPROFILE `dbi.database.<name>.ifxemul.dblquotes`, default true). `"group"` then becomes the string `'group'`: a `SELECT` returns that text instead of the column, and an `INSERT` or `UPDATE` fails with `-201`. Set `dbi.database.<name>.ifxemul.dblquotes = false` and write string literals in SQL with single quotes. Verified on PostgreSQL: with the setting, `"group"` reads and writes the column. `RECORD LIKE salesterritory.*` still names the member `group`, and `rec.group` compiles; a view member with another name maps to it with `ATTRIBUTES(json_name = "group")`.
- **Declare visibility explicitly** on every module-level `TYPE`, `CONSTANT`, `DEFINE` and `FUNCTION`; the bare defaults differ (functions are public, the rest private).
- **Qualify calls to imported modules** (`SalesOrders.ordersRun()`), so a same-named helper in another module cannot become ambiguous.
- **Declaration order:** `IMPORT FGL`, then `SCHEMA`, then module-level `CONSTANT`/`TYPE`/`DEFINE`, then `MAIN`, then functions.
- **Reference form fields by field name, never by layout tag.** A form item has a layout tag (the identifier on the left in `ATTRIBUTES`, e.g. `EDIT cBonus = ...`) and a field name (`FORMONLY.name` or `table.column`). Dialog statements and `ui.*` lookups need the field name: `ON CHANGE`, `NEXT FIELD`, `INPUT ... FROM sr[line].field` and `ui.ComboBox.forName()`. Verified against a running app: a tag in `ON CHANGE` stops the program with `-8015`, a tag in `FROM sr[line].x` with `-1102`, and `forName("tag")` silently returns NULL so the combobox stays empty. Table-bound fields use `table.column` (`forName("customer.territoryid")`).
- **Continuation lines also indent in 3-space steps.** Clauses (`INTO`, `FROM`, `WHERE`, `SET`, `ATTRIBUTES`) go one level deeper than their statement, and wrapped list items go two levels deeper. Do not align to a column of the previous line.
- **JSON bridge: matching is by name, case-insensitive.** A camelCase view member fills a lowercase column (`shipDate` fills `shipdate`). A member whose column has a different name takes `ATTRIBUTES(json_name = "column")`, for example `statusCode INTEGER ATTRIBUTES(json_name = "status")`. Members with no counterpart, such as a name blended in from another table, are ignored without error.
- **JSON bridge: `toFGL` replaces the whole target record.** Every target member the view does not carry is set to NULL, even when the target already held a loaded row. Never convert onto a loaded record to merge changes, and have the model's `UPDATE` name the columns it owns (`SET shipdate = ..., comment = ...`) instead of writing the whole record. A NULL view member writes NULL.
- **JSON bridge: mismatched types become NULL silently.** There is no error and `TRY`/`CATCH` does not see one: a `STRING` holding "abc" into an `INTEGER`, a `BIGINT` that overflows an `INTEGER`, and `DATE` to `DATETIME` or back. Declare a crossing member with exactly the column's type, or assign it directly after the bridge.
- **JSON bridge: decimals travel as binary64,** exact to about 15 significant digits. Verified: `1234567890123456.7891` came back as `1234567890123456.8`. Assign a decimal that can be wider than that directly after the bridge.
- **JSON bridge: verified lossless** for all 24 columns of a real `salesorderheader` row (INTEGER, BOOLEAN, CHAR(36), DATETIME with fraction, floating DECIMAL), for quotes, backslashes, newlines, tabs and CJK text, and for DATETIME with fractional seconds. An empty string becomes NULL (the BDL rule). 10,000 conversions take about 0.04 seconds.
- **JSON bridge: special cases are expected.** Handle them in the conversion function after the bridge call: type bridging (DATE and DATETIME), wide decimals, computed or audit columns (`modifieddate`), defaults for columns the view lacks, and any merge onto a loaded row.
- **Test every conversion function** with a record whose every crossing member is populated, and assert that none came back NULL, because the failure is silent. Verified: removing the DATE special case from the worked example makes such a test fail. Assert each member is not NULL before comparing its value: a comparison with NULL is NULL, and `assertTrue(NULL)` does not fail (verified: a test that only compared the converted dates still passed with the DATE special case removed).

## Worked example (four files; compiles clean with `fglcomp -M -Wall` and `fglform -M`)

**Model**, `OrdersModel.4gl`: the database record, data changes, transactions and validation, including the `SELECT` that serves the validation; no UI.

```4gl
SCHEMA adventureworks

#+ The database record: one row of salesorderheader, as the model reads and writes it.
PUBLIC TYPE tOrder RECORD LIKE salesorderheader.*

#+ Business-rule validation. Returns TRUE, or FALSE with a message for the user.
#+ The SELECT serves this validation, so it belongs to the model: the stored status is
#+ read here, and a cancelled order (status 6) cannot be changed.
PUBLIC FUNCTION validateOrder(rec tOrder) RETURNS (BOOLEAN, STRING)
   VAR currentStatus SMALLINT
   IF rec.shipdate IS NOT NULL AND rec.shipdate < rec.orderdate THEN
      RETURN FALSE, "Ship date cannot be before the order date."
   END IF
   SELECT salesorderheader.status INTO currentStatus FROM salesorderheader
      WHERE salesorderheader.salesorderid = rec.salesorderid
   IF currentStatus = 6 THEN
      RETURN FALSE, "A cancelled order cannot be changed."
   END IF
   RETURN TRUE, NULL
END FUNCTION

#+ Persist one order in its own transaction. Returns TRUE, or FALSE with the SQL message.
#+ The UPDATE names the columns this model owns; it never writes the whole record,
#+ because a record converted from a view has every other column set to NULL.
PUBLIC FUNCTION saveOrder(rec tOrder) RETURNS (BOOLEAN, STRING)
   VAR errorText STRING
   BEGIN WORK
   TRY
      UPDATE salesorderheader
         SET shipdate = rec.shipdate, comment = rec.comment
         WHERE salesorderheader.salesorderid = rec.salesorderid
      COMMIT WORK
   CATCH
      LET errorText = SQLERRMESSAGE
      ROLLBACK WORK
      RETURN FALSE, errorText
   END TRY
   RETURN TRUE, NULL
END FUNCTION
```

**Controller**, `OrdersController.4gl`: the view record, the conversion function (JSON bridge plus a special case), dialogs, flow and the `SELECT` that blends several tables; no writes. It imports only its own model.

```4gl
IMPORT util

IMPORT FGL OrdersModel

PRIVATE CONSTANT cMaxRows = 500

#+ The view record: what the screen shows. It blends salesorderheader columns with a
#+ name from customer / store / person, and holds the dates as DATE for the screen.
PUBLIC TYPE tOrderView RECORD
   salesOrderId INTEGER,
   customerName VARCHAR(120),
   orderDate    DATE,
   shipDate     DATE,
   comment      VARCHAR(128)
END RECORD

PRIVATE DEFINE orderList DYNAMIC ARRAY OF tOrderView

#+ View record to database record. The JSON bridge copies every member whose name
#+ matches a column (case-insensitive) and ignores the rest (customerName). It also
#+ sets every column the view does not carry to NULL. Special cases follow the bridge.
PUBLIC FUNCTION toDbOrder(viewRec tOrderView) RETURNS OrdersModel.tOrder
   VAR dbRec OrdersModel.tOrder
   CALL util.JSONObject.fromFGL(viewRec).toFGL(dbRec)
   # Special case: the screen holds DATEs but the columns are DATETIMEs, and the bridge
   # turns that mismatch into NULL without an error, so assign these members directly.
   LET dbRec.orderdate = viewRec.orderDate
   LET dbRec.shipdate = viewRec.shipDate
   RETURN dbRec
END FUNCTION

PUBLIC FUNCTION ordersRun(customerId INTEGER) RETURNS ()
   OPEN WINDOW wOrders WITH FORM "Orders"
      ATTRIBUTES(TEXT = "Orders", STYLE = "dialog")
   IF loadOrders(customerId) = 0 THEN
      MESSAGE "This customer has no orders."
   END IF
   CALL browseOrders()
   CLOSE WINDOW wOrders
END FUNCTION

#+ The read stays in the controller: it finds the orders the user will view and change. It is
#+ written for tOrderView: the column list follows the members of that record one for one,
#+ in order, and blends several tables.
PRIVATE FUNCTION loadOrders(customerId INTEGER) RETURNS INTEGER
   VAR rec tOrderView
   CALL orderList.clear()
   DECLARE cursOrders CURSOR FOR
      SELECT salesorderheader.salesorderid, COALESCE(store.name, person.lastname),
            salesorderheader.orderdate, salesorderheader.shipdate, salesorderheader.comment
         FROM salesorderheader
         INNER JOIN customer ON customer.customerid = salesorderheader.customerid
         LEFT JOIN person ON person.businessentityid = customer.personid
         LEFT JOIN store ON store.businessentityid = customer.storeid
         WHERE salesorderheader.customerid = customerId
   FOREACH cursOrders INTO rec.*
      LET orderList[orderList.getLength() + 1] = rec
      IF orderList.getLength() >= cMaxRows THEN
         EXIT FOREACH
      END IF
   END FOREACH
   RETURN orderList.getLength()
END FUNCTION

PRIVATE FUNCTION browseOrders() RETURNS ()
   VAR rec tOrderView
   LET int_flag = FALSE
   DISPLAY ARRAY orderList TO srOrders.* ATTRIBUTES(DOUBLECLICK = update, UNBUFFERED)
      ON UPDATE
         LET rec = orderList[arr_curr()]
         IF inputOrder(scr_line(), rec) THEN
            LET orderList[arr_curr()] = rec
         END IF
      ON ACTION close
         EXIT DISPLAY
   END DISPLAY
END FUNCTION

PRIVATE FUNCTION inputOrder(line INTEGER, rec tOrderView INOUT) RETURNS BOOLEAN
   VAR valid BOOLEAN
   VAR errorText STRING
   LET int_flag = FALSE
   INPUT rec.shipDate, rec.comment
      FROM srOrders[line].shipDate, srOrders[line].comment
      ATTRIBUTES(WITHOUT DEFAULTS)
      AFTER INPUT
         IF NOT int_flag THEN
            CALL OrdersModel.validateOrder(toDbOrder(rec)) RETURNING valid, errorText
            IF NOT valid THEN
               ERROR errorText
               NEXT FIELD shipDate
            END IF
         END IF
   END INPUT
   IF int_flag THEN
      RETURN FALSE
   END IF
   CALL OrdersModel.saveOrder(toDbOrder(rec)) RETURNING valid, errorText
   IF NOT valid THEN
      ERROR errorText
      RETURN FALSE
   END IF
   RETURN TRUE
END FUNCTION
```

**View**, `Orders.per`: layout only.

```per
LAYOUT (TEXT = "Orders")
  VBOX
    TABLE
    {
     ID        Customer           Order date   Ship date    Comment
    [cId      |cCustomer        |cOrderDate |cShipDate   |cComment                 ]
    }
    END
  END
END

ATTRIBUTES
  EDIT     cId        = FORMONLY.salesOrderId TYPE INTEGER, NOENTRY;
  EDIT     cCustomer  = FORMONLY.customerName TYPE VARCHAR, NOENTRY;
  DATEEDIT cOrderDate = FORMONLY.orderDate    TYPE DATE,    NOENTRY;
  DATEEDIT cShipDate  = FORMONLY.shipDate     TYPE DATE;
  EDIT     cComment   = FORMONLY.comment      TYPE VARCHAR;
END

INSTRUCTIONS
  SCREEN RECORD srOrders(salesOrderId, customerName, orderDate, shipDate, comment);
END
```

**Lookup**, `SalesPersonsLookup.4gl`: fills a combobox with data that belongs to another feature. A controller calls it with the combobox found by its field name, `CALL SalesPersonsLookup.fillSalesPersons(ui.ComboBox.forName("salesPersonId"))`. The cursor is declared on the first call and reused afterwards.

```4gl
SCHEMA adventureworks

#+ One combobox entry: the value the field stores and the text the user sees.
PRIVATE TYPE tSalesPersonItem RECORD
   salesPersonId INTEGER,
   fullName      STRING
END RECORD

PRIVATE DEFINE declared BOOLEAN

#+ Fill a combobox with the salespeople, replacing what it held. The controller finds the
#+ combobox by its field name and passes it in. The cursor is declared on the first call
#+ and reused afterwards.
PUBLIC FUNCTION fillSalesPersons(comboBox ui.ComboBox) RETURNS ()
   VAR item tSalesPersonItem
   IF NOT declared THEN
      DECLARE cursSalesPersons CURSOR FOR
         SELECT salesperson.businessentityid,
               TRIM(person.lastname) || ', ' || TRIM(person.firstname)
            FROM salesperson
            INNER JOIN person ON person.businessentityid = salesperson.businessentityid
            ORDER BY person.lastname, person.firstname
      LET declared = TRUE
   END IF
   CALL comboBox.clear()
   FOREACH cursSalesPersons INTO item.*
      CALL comboBox.addItem(item.salesPersonId, item.fullName)
   END FOREACH
END FUNCTION
```

## Interpretations (decisions made where the original standard was silent; change here if the team disagrees)

- "Camel-case" means lowerCamelCase; "title case" files means UpperCamelCase with no separators, applied to Genero source and resource files only. Confirmed by the user.
- Indentation (rule 1) is specified for `.4gl` code; `.per` layout is not covered.
- "Actual case of the symbol" is read as the case `fglcomp -Wall` expects (warning `-8440`). Keyword-like operators the compiler accepts in any case are capitalized under rule 2; for a symbol the compiler does not check, use the case the manual gives.
- Form identifiers follow the naming rules too: layout tags and `FORMONLY` field names are camelCase without underscores. Action names (`ON ACTION newsearch`) are protocol identifiers and are left as written. Form identifiers camelCase: confirmed by the user.
- Module-level variables carry no scope prefix; `PRIVATE`/`PUBLIC` states scope. Name them for what they hold.
- The view is the form file and its presentation resources. Field-level presentation attributes (`NOENTRY`, `UPSHIFT`, formats) stay in the view; business-rule validation (ranges, cross-field and referential checks) lives in the model.
- A `SELECT` belongs to the module it supports (rule 11). Reads that let the user find a record to view, change or delete (list loading, `CONSTRUCT` results, reloading a row for display) are the controller's, because the dialog drives them. Reads that validate data or guard a write (existence, uniqueness, whether the row was changed since it was loaded, a key the write must resolve) are the model's, and run in the write's transaction when there is one. The model also owns insert, update, delete, validation, the pure derived-value calculations and the database-record `TYPE`. Confirmed by the user, including that the controller calls a public model function for a screen default that needs the same `SELECT`, so it is not written twice.
- The file naming `<Feature>Model.4gl` / `<Feature>Controller.4gl` / `<Feature>.per` is a convention chosen where the standard gave none. Confirmed by the user.
- "No cross-referencing" is read as: the only allowed application imports are a controller to its own model, helpers, lookups and the entry-point imports of rule 12. The `<Role>Helper.4gl` naming is confirmed by the user; who may import a helper (controllers; models only if the helper has no UI) is my reading. The program entry point is settled in rule 12: `MainController.4gl` for startup only, and the single-program versus several-program shapes, are confirmed by the user, as is leaving the registry pattern out until a project needs it. That the application menu is a separate `MainMenuController.4gl` (with a `MainMenu.per` view and no model) that imports the feature controllers is my reading of "startup only". Navigation between features (one feature opening another's screen) is deliberately left unresolved, to be settled with the user case by case (rule 11 and 12 say to ask).
- Lookup modules, named `<Feature>Lookup.4gl` and grouped by the feature that owns the data, fill comboboxes with data from another feature (rule 12). Confirmed by the user: the function takes the combobox as a parameter and fills it; the cursor is declared lazily on the first call; a lookup is a leaf and a controller helper only (a model imports none and keeps its own validation `SELECT`s); a lookup may exist for data with no feature of its own (such as products) or with no table behind it (a fixed list); and a controller's own list `SELECT` may still join other tables to fill its own view record, without a lookup. Verified: a lazily declared cursor lives as long as the database connection, so after `DISCONNECT` and `CONNECT` it fails with `-404`; connect once at startup and keep that connection. My reading: a single display value, such as a customer's name for an id, is not a lookup, because the controller's own `SELECT` joins it in.
- Conversion functions are named `toDb<Name>` and `toView<Name>`, and are `PUBLIC` in the controller so fglunit can reach them; a test suite importing a controller is the exception rule 12 already allows. Confirmed by the user.
- The controller owns the view record `TYPE`; the model owns the database record `TYPE` (for example `RECORD LIKE salesorderheader.*`). A controller that reads straight into its view record with its own `SELECT` needs no conversion on the way in; the bridge is used where a view record must become a database record, or the reverse. Confirmed by the user.
- Rule 14 applies to every dialog statement, including `MENU` and the multiple `DIALOG`, which do not set `int_flag` themselves, apart from `CANCEL DIALOG` (documented runtime behavior). It is taken from the instruction "before each dialog": one rule with no exceptions is easier to check by reading than a list of them.
- Rule 15 bans `PROMPT` outright (the user's reason: it exists only for Informix-4GL compatibility). The one `PROMPT` in the AdventureWorks app, the customer id of a new order, became an `INPUT` on its own small form, `NewOrder.per`.
