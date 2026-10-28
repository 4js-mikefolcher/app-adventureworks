################################################################################
# CustomersController.4gl - search and maintain customers.
#
# The list is query-by-example (CONSTRUCT) because there are ~19k customers. A
# customer is an individual (person) or a store, so the list SELECT resolves readable
# names by join. The controller owns the dialogs, the user flow and that SELECT; the
# territory reassignment and the delete go through CustomersModel, and the territory
# comboboxes are filled by TerritoriesLookup. The view record adds the type and name,
# so toDbCustomer converts to the database record.
#
# Public entry: customersRun()
################################################################################

IMPORT util

IMPORT FGL CustomersModel
IMPORT FGL DialogHelper
IMPORT FGL TerritoriesLookup

#+ Maximum customers loaded per search (keeps the list responsive).
PRIVATE CONSTANT cMaxRows = 500

#+ The view record: one customer row as shown in the list. The type and the name are
#+ resolved by join for display only; the JSON bridge ignores them.
PUBLIC TYPE tCustomerView RECORD
   customerId   INTEGER,
   customerType VARCHAR(20),
   customerName VARCHAR(120),
   territoryId  INTEGER
END RECORD

PRIVATE DEFINE customerList  DYNAMIC ARRAY OF tCustomerView
PRIVATE DEFINE searchWhere   STRING
PRIVATE DEFINE quitRequested BOOLEAN

#-------------------------------------------------------------------------------
#+ View record to database record. The JSON bridge copies every member whose name
#+ matches a column (customerId, territoryId), ignores the type and the name, and sets
#+ the columns the view does not carry to NULL, so the model's UPDATE names the columns
#+ it writes.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION toDbCustomer(viewRec tCustomerView) RETURNS CustomersModel.tCustomer
   VAR dbRec CustomersModel.tCustomer
   CALL util.JSONObject.fromFGL(viewRec).toFGL(dbRec)
   RETURN dbRec
END FUNCTION

#-------------------------------------------------------------------------------
#+ Open the customers window and run the search / browse loop.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION customersRun() RETURNS ()
   OPEN WINDOW wCustomers WITH FORM "Customers"
      ATTRIBUTES(TEXT = "Customers", STYLE = "dialog")
   CALL fillCustomerCombos()
   LET quitRequested = FALSE
   WHILE NOT quitRequested
      IF searchCustomers() THEN
         CALL loadCustomers()
         CALL browseCustomers()
      ELSE
         LET quitRequested = TRUE
      END IF
   END WHILE
   CLOSE WINDOW wCustomers
END FUNCTION

#-------------------------------------------------------------------------------
#+ Populate the territory comboboxes (search filter and inline editor). Both are
#+ addressed by form field name: customer.territoryid (search) and rTerr (row).
#-------------------------------------------------------------------------------
PRIVATE FUNCTION fillCustomerCombos() RETURNS ()
   CALL TerritoriesLookup.fillTerritories(ui.ComboBox.forName("customer.territoryid"))
   CALL TerritoriesLookup.fillTerritories(ui.ComboBox.forName("rTerr"))
END FUNCTION

#-------------------------------------------------------------------------------
#+ Query-by-example over the customer base columns. Returns TRUE if the user
#+ launched a search, FALSE if they cancelled (to leave the screen).
#-------------------------------------------------------------------------------
PRIVATE FUNCTION searchCustomers() RETURNS BOOLEAN
   CONSTRUCT BY NAME searchWhere ON customer.customerid, customer.territoryid
   RETURN (NOT int_flag)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Run the search and load up to cMaxRows rows, resolving names by join. The column
#+ list follows tCustomerView member for member. The SQL is dynamic because the WHERE
#+ clause comes from the CONSTRUCT, and it uses full table names (no aliases) so that
#+ clause matches.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION loadCustomers() RETURNS ()
   VAR rec tCustomerView
   VAR sqlText STRING
   LET sqlText =
      "SELECT customer.customerid,"
      || " CASE WHEN customer.storeid IS NOT NULL THEN 'Store' ELSE 'Individual' END,"
      || " CASE WHEN store.name IS NOT NULL THEN store.name"
      || "      ELSE TRIM(person.lastname) || ', ' || TRIM(person.firstname) END,"
      || " customer.territoryid"
      || " FROM customer"
      || " LEFT JOIN person ON person.businessentityid = customer.personid"
      || " LEFT JOIN store  ON store.businessentityid  = customer.storeid"
      || " WHERE " || searchWhere
      || " ORDER BY customer.customerid"
   CALL customerList.clear()
   DECLARE cursCustomers CURSOR FROM sqlText
   FOREACH cursCustomers INTO rec.*
      LET customerList[customerList.getLength() + 1] = rec
      IF customerList.getLength() >= cMaxRows THEN
         EXIT FOREACH
      END IF
   END FOREACH
   IF customerList.getLength() >= cMaxRows THEN
      MESSAGE SFMT("Showing the first %1 matches - refine the search to narrow the list.", cMaxRows)
   END IF
END FUNCTION

#-------------------------------------------------------------------------------
#+ Browse the result list. Inline-edit reassigns the territory; remove deletes
#+ the customer; new-search returns to the criteria; close leaves the screen.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION browseCustomers() RETURNS ()
   VAR rec tCustomerView
   DISPLAY ARRAY customerList TO srCustomers.* ATTRIBUTES(DOUBLECLICK = update, UNBUFFERED)

      ON UPDATE
         LET rec = customerList[arr_curr()]
         IF inputCustomerTerritory(scr_line(), rec) THEN
            IF saveCustomer(rec) THEN
               LET customerList[arr_curr()] = rec
            END IF
         END IF

      ON ACTION remove ATTRIBUTES(TEXT = "Delete", IMAGE = "fa-trash")
         IF customerList.getLength() > 0 THEN
            IF DialogHelper.confirm("Delete customer",
                  SFMT("Delete customer %1 (%2)?",
                     customerList[arr_curr()].customerId,
                     customerList[arr_curr()].customerName)) THEN
               IF removeCustomer(customerList[arr_curr()].customerId) THEN
                  CALL customerList.deleteElement(arr_curr())
               END IF
            END IF
         END IF

      ON ACTION newsearch ATTRIBUTES(TEXT = "New search", IMAGE = "fa-search")
         EXIT DISPLAY

      ON ACTION close
         LET quitRequested = TRUE
         EXIT DISPLAY

   END DISPLAY
END FUNCTION

#-------------------------------------------------------------------------------
#+ Inline edit of the territory of one row. Returns TRUE if the user accepted it.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION inputCustomerTerritory(line INTEGER, rec tCustomerView INOUT) RETURNS BOOLEAN
   LET int_flag = FALSE
   INPUT rec.territoryId FROM srCustomers[line].rTerr
      ATTRIBUTES(WITHOUT DEFAULTS)
   RETURN (NOT int_flag)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Persist a customer's territory through the model and show its error, if any.
#+ Returns TRUE on success.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION saveCustomer(rec tCustomerView INOUT) RETURNS BOOLEAN
   VAR saved BOOLEAN
   VAR messageText STRING
   CALL CustomersModel.updateCustomer(toDbCustomer(rec)) RETURNING saved, messageText
   IF NOT saved THEN
      ERROR messageText
   END IF
   RETURN saved
END FUNCTION

#-------------------------------------------------------------------------------
#+ Delete a customer through the model and show its message, if any. Returns TRUE
#+ when the row was removed.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION removeCustomer(customerId INTEGER) RETURNS BOOLEAN
   VAR removed BOOLEAN
   VAR messageText STRING
   CALL CustomersModel.deleteCustomer(customerId) RETURNING removed, messageText
   IF NOT removed THEN
      ERROR messageText
   END IF
   RETURN removed
END FUNCTION
