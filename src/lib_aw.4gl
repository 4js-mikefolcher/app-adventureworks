################################################################################
# lib_aw.4gl - shared services for the AdventureWorks Sales application.
#
# Reused by every domain module (customers, salesorders, salespersons,
# territories, specialoffers). Provides:
#   * connection / disconnection to the "adventureworks" database
#   * a single SQL-error reporting point
#   * a yes/no confirmation dialog
#   * a generic COMBOBOX populator (value/label SQL -> form combobox)
#   * customer / salesperson display-name resolution (the base tables hold only
#     ids; readable names live in person / store)
#
# No MAIN: this is a library module, linked into main via IMPORT FGL lib_aw.
################################################################################

#+ Database source name. Matches the FGLPROFILE entry in res/fglprofile.pgs and
#+ the schema file adventureworks.sch.
PUBLIC CONSTANT AW_DBNAME = "adventureworks"

#-------------------------------------------------------------------------------
#+ Connect to the AdventureWorks database. Credentials come from FGLPROFILE
#+ (res/fglprofile.pgs). Returns TRUE on success; on failure reports the error
#+ and returns FALSE so the caller can abort.
#-------------------------------------------------------------------------------
FUNCTION aw_connect() RETURNS BOOLEAN
    TRY
        CONNECT TO AW_DBNAME
    CATCH
        CALL aw_sql_error(SFMT("Connection to '%1' failed", AW_DBNAME))
        RETURN FALSE
    END TRY
    RETURN TRUE
END FUNCTION

#-------------------------------------------------------------------------------
#+ Close the current database connection (best-effort).
#-------------------------------------------------------------------------------
FUNCTION aw_disconnect()
    WHENEVER ANY ERROR CONTINUE
    DISCONNECT CURRENT
    WHENEVER ANY ERROR STOP
END FUNCTION

#-------------------------------------------------------------------------------
#+ Report an SQL error to the user, prefixed with a caller-supplied context.
#+ Reads sqlca.sqlcode and the last SQL error message; safe to call right after
#+ a CATCH.
#+
#+ @param p_context human description of the operation that failed
#-------------------------------------------------------------------------------
FUNCTION aw_sql_error(p_context STRING)
    DEFINE l_code INTEGER
    LET l_code = sqlca.sqlcode
    ERROR SFMT("%1: SQL error %2 - %3", p_context, l_code, SQLERRMESSAGE)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Modal yes/no confirmation. Returns TRUE only if the user picks "Yes".
#+
#+ @param p_title  dialog title
#+ @param p_msg    confirmation question shown in the dialog body
#-------------------------------------------------------------------------------
FUNCTION aw_confirm(p_title STRING, p_msg STRING) RETURNS BOOLEAN
    DEFINE l_result BOOLEAN
    LET l_result = FALSE
    MENU p_title ATTRIBUTES(STYLE = "dialog", COMMENT = p_msg, IMAGE = "fa-question-circle")
        COMMAND "No"
            LET l_result = FALSE
        COMMAND "Yes"
            LET l_result = TRUE
    END MENU
    RETURN l_result
END FUNCTION

#-------------------------------------------------------------------------------
#+ Populate a form COMBOBOX from a query returning two columns: (value, label).
#+ The combobox is cleared first. Use full table names (no aliases) in the SQL.
#+
#+ @param p_field combobox field name as declared in the form
#+ @param p_sql   SELECT returning exactly (value, label)
#-------------------------------------------------------------------------------
FUNCTION aw_fill_combobox(p_field STRING, p_sql STRING)
    DEFINE l_cb ui.ComboBox
    DEFINE l_value STRING
    DEFINE l_label STRING
    LET l_cb = ui.ComboBox.forName(p_field)
    IF l_cb IS NULL THEN
        RETURN
    END IF
    CALL l_cb.clear()
    DECLARE c_fillcb CURSOR FROM p_sql
    FOREACH c_fillcb INTO l_value, l_label
        CALL l_cb.addItem(l_value, l_label)
    END FOREACH
END FUNCTION

#-------------------------------------------------------------------------------
#+ Resolve a readable customer name. A customer is either an individual (joined
#+ to person via personid) or a store (joined to store via storeid). Returns a
#+ best-effort label; never NULL.
#+
#+ @param p_customerid the customer.customerid
#-------------------------------------------------------------------------------
FUNCTION aw_customer_label(p_customerid INTEGER) RETURNS STRING
    DEFINE l_name STRING
    LET l_name = NULL
    SELECT CASE
              WHEN store.name IS NOT NULL THEN store.name
              ELSE TRIM(person.lastname) || ', ' || TRIM(person.firstname)
           END
      INTO l_name
      FROM customer
      LEFT JOIN person ON person.businessentityid = customer.personid
      LEFT JOIN store  ON store.businessentityid  = customer.storeid
     WHERE customer.customerid = p_customerid
    IF l_name IS NULL THEN
        LET l_name = SFMT("Customer %1", p_customerid)
    END IF
    RETURN l_name
END FUNCTION

#-------------------------------------------------------------------------------
#+ Resolve a salesperson's name from the person table.
#+
#+ @param p_beid the salesperson.businessentityid
#-------------------------------------------------------------------------------
FUNCTION aw_salesperson_label(p_beid INTEGER) RETURNS STRING
    DEFINE l_name STRING
    LET l_name = NULL
    SELECT TRIM(person.lastname) || ', ' || TRIM(person.firstname)
      INTO l_name
      FROM person
     WHERE person.businessentityid = p_beid
    IF l_name IS NULL THEN
        LET l_name = SFMT("Salesperson %1", p_beid)
    END IF
    RETURN l_name
END FUNCTION
