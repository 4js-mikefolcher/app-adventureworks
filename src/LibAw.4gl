################################################################################
# LibAw.4gl - shared services for the AdventureWorks Sales application.
#
# Reused by the domain modules not yet split into model and controller (Customers,
# SalesOrders, SalesPersons, SpecialOffers); it is dissolved into helpers as each
# one migrates. Provides:
#   * connection / disconnection to the "adventureworks" database
#   * a single SQL-error reporting point
#   * a yes/no confirmation dialog
#   * a generic COMBOBOX populator (value/label SQL -> form combobox)
#   * customer / salesperson display-name resolution (the base tables hold only
#     ids; readable names live in person / store)
#
# No MAIN: this is a library module, imported by its callers with IMPORT FGL LibAw.
################################################################################

#+ Database source name. Matches the FGLPROFILE entry in res/fglprofile.pgs and
#+ the schema file adventureworks.sch.
PUBLIC CONSTANT cAwDbName = "adventureworks"

#-------------------------------------------------------------------------------
#+ Connect to the AdventureWorks database. Credentials come from FGLPROFILE
#+ (res/fglprofile.pgs). Returns TRUE on success; on failure reports the error
#+ and returns FALSE so the caller can abort.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION awConnect() RETURNS BOOLEAN
   TRY
      CONNECT TO cAwDbName
   CATCH
      CALL awSqlError(SFMT("Connection to '%1' failed", cAwDbName))
      RETURN FALSE
   END TRY
   RETURN TRUE
END FUNCTION

#-------------------------------------------------------------------------------
#+ Close the current database connection (best-effort).
#-------------------------------------------------------------------------------
PUBLIC FUNCTION awDisconnect() RETURNS ()
   WHENEVER ANY ERROR CONTINUE
   DISCONNECT CURRENT
   WHENEVER ANY ERROR STOP
END FUNCTION

#-------------------------------------------------------------------------------
#+ Report an SQL error to the user, prefixed with a caller-supplied context.
#+ Reads sqlca.sqlcode and the last SQL error message; safe to call right after
#+ a CATCH.
#+
#+ @param operation human description of the operation that failed
#-------------------------------------------------------------------------------
PUBLIC FUNCTION awSqlError(operation STRING) RETURNS ()
   VAR code INTEGER = sqlca.sqlcode
   ERROR SFMT("%1: SQL error %2 - %3", operation, code, SQLERRMESSAGE)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Modal yes/no confirmation. Returns TRUE only if the user picks "Yes".
#+
#+ @param dialogTitle dialog title
#+ @param question    confirmation question shown in the dialog body
#-------------------------------------------------------------------------------
PUBLIC FUNCTION awConfirm(dialogTitle STRING, question STRING) RETURNS BOOLEAN
   VAR confirmed BOOLEAN = FALSE
   MENU dialogTitle ATTRIBUTES(STYLE = "dialog", COMMENT = question, IMAGE = "fa-question-circle")
      COMMAND "No"
         LET confirmed = FALSE
      COMMAND "Yes"
         LET confirmed = TRUE
   END MENU
   RETURN confirmed
END FUNCTION

#-------------------------------------------------------------------------------
#+ Populate a form COMBOBOX from a query returning two columns: (value, label).
#+ The combobox is cleared first. Use full table names (no aliases) in the SQL.
#+ The combobox is addressed by its form FIELD NAME (the FORMONLY name or
#+ table.column), never by its layout tag.
#+
#+ @param fieldName combobox field name as declared in the form
#+ @param sqlText   SELECT returning exactly (value, label)
#-------------------------------------------------------------------------------
PUBLIC FUNCTION awFillComboBox(fieldName STRING, sqlText STRING) RETURNS ()
   VAR cb ui.ComboBox
   VAR itemValue STRING
   VAR itemLabel STRING
   LET cb = ui.ComboBox.forName(fieldName)
   IF cb IS NULL THEN
      RETURN
   END IF
   CALL cb.clear()
   DECLARE cursFillCombo CURSOR FROM sqlText
   FOREACH cursFillCombo INTO itemValue, itemLabel
      CALL cb.addItem(itemValue, itemLabel)
   END FOREACH
END FUNCTION

#-------------------------------------------------------------------------------
#+ Resolve a readable customer name. A customer is either an individual (joined
#+ to person via personid) or a store (joined to store via storeid). Returns a
#+ best-effort label; never NULL.
#+
#+ @param customerId the customer.customerid
#-------------------------------------------------------------------------------
PUBLIC FUNCTION awCustomerLabel(customerId INTEGER) RETURNS STRING
   VAR labelText STRING
   LET labelText = NULL
   SELECT
         CASE
            WHEN store.name IS NOT NULL THEN store.name
            ELSE TRIM(person.lastname) || ', ' || TRIM(person.firstname)
         END
      INTO labelText
      FROM customer
      LEFT JOIN person ON person.businessentityid = customer.personid
      LEFT JOIN store  ON store.businessentityid  = customer.storeid
      WHERE customer.customerid = customerId
   IF labelText IS NULL THEN
      LET labelText = SFMT("Customer %1", customerId)
   END IF
   RETURN labelText
END FUNCTION

#-------------------------------------------------------------------------------
#+ Resolve a salesperson's name from the person table.
#+
#+ @param entityId the salesperson.businessentityid
#-------------------------------------------------------------------------------
PUBLIC FUNCTION awSalesPersonLabel(entityId INTEGER) RETURNS STRING
   VAR labelText STRING
   LET labelText = NULL
   SELECT TRIM(person.lastname) || ', ' || TRIM(person.firstname)
      INTO labelText
      FROM person
      WHERE person.businessentityid = entityId
   IF labelText IS NULL THEN
      LET labelText = SFMT("Salesperson %1", entityId)
   END IF
   RETURN labelText
END FUNCTION
