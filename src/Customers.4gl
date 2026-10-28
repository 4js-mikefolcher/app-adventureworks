################################################################################
# Customers.4gl - search and maintain customers (customer).
#
# A customer is either an individual (joined to person via personid) or a store
# (joined to store via storeid); the base table holds only ids, so readable
# names are resolved by join. The list is query-by-example (CONSTRUCT) because
# there are ~19k customers. Editable attribute: territory assignment. Add is not
# offered here - a customer must reference an existing person or store, which is
# outside the Sales scope. Delete is supported.
#
# Public entry: customersRun()
################################################################################

IMPORT FGL LibAw

#+ Maximum customers loaded per search (keeps the list responsive).
PRIVATE CONSTANT cMaxRows = 500

PRIVATE TYPE tCustomer RECORD
   customerId   INTEGER,
   customerType VARCHAR(20),
   customerName VARCHAR(120),
   territoryId  INTEGER
END RECORD

PRIVATE DEFINE customerList  DYNAMIC ARRAY OF tCustomer
PRIVATE DEFINE searchWhere   STRING
PRIVATE DEFINE quitRequested BOOLEAN

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
   VAR sqlText STRING
   LET sqlText = "SELECT territoryid, name FROM salesterritory ORDER BY name"
   CALL LibAw.awFillComboBox("customer.territoryid", sqlText)
   CALL LibAw.awFillComboBox("rTerr", sqlText)
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
#+ Run the search and load up to cMaxRows rows, resolving names by join. Uses
#+ full table names (no aliases) so the CONSTRUCT WHERE clause matches.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION loadCustomers() RETURNS ()
   VAR rec tCustomer
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
   VAR rec tCustomer
   DISPLAY ARRAY customerList TO srCustomers.* ATTRIBUTES(DOUBLECLICK = update, UNBUFFERED)

      ON UPDATE
         LET rec = customerList[arr_curr()]
         LET int_flag = FALSE
         INPUT rec.territoryId FROM srCustomers[scr_line()].rTerr
            ATTRIBUTES(WITHOUT DEFAULTS)
         IF NOT int_flag THEN
            IF saveCustomerTerritory(rec) THEN
               LET customerList[arr_curr()] = rec
            END IF
         END IF

      ON ACTION remove ATTRIBUTES(TEXT = "Delete", IMAGE = "fa-trash")
         IF customerList.getLength() > 0 THEN
            IF LibAw.awConfirm("Delete customer",
                  SFMT("Delete customer %1 (%2)?",
                     customerList[arr_curr()].customerId,
                     customerList[arr_curr()].customerName)) THEN
               IF deleteCustomer(customerList[arr_curr()].customerId) THEN
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
#+ Update a customer's territory assignment.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION saveCustomerTerritory(rec tCustomer INOUT) RETURNS BOOLEAN
   VAR modifiedAt DATETIME YEAR TO SECOND
   LET modifiedAt = CURRENT YEAR TO SECOND
   BEGIN WORK
   TRY
      UPDATE customer
         SET territoryid = rec.territoryId, modifieddate = modifiedAt
         WHERE customer.customerid = rec.customerId
      COMMIT WORK
   CATCH
      ROLLBACK WORK
      CALL LibAw.awSqlError("Updating customer territory")
      RETURN FALSE
   END TRY
   RETURN TRUE
END FUNCTION

#-------------------------------------------------------------------------------
#+ Delete a customer. Customers referenced by orders cannot be removed.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION deleteCustomer(customerId INTEGER) RETURNS BOOLEAN
   BEGIN WORK
   TRY
      DELETE FROM customer WHERE customer.customerid = customerId
      COMMIT WORK
   CATCH
      ROLLBACK WORK
      IF sqlca.sqlcode = -692 OR sqlca.sqlcode = -691 THEN
         ERROR "Cannot delete: this customer still has orders or other references."
      ELSE
         CALL LibAw.awSqlError("Deleting customer")
      END IF
      RETURN FALSE
   END TRY
   RETURN TRUE
END FUNCTION
