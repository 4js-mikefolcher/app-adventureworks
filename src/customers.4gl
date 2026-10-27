################################################################################
# customers.4gl - search and maintain customers (customer).
#
# A customer is either an individual (joined to person via personid) or a store
# (joined to store via storeid); the base table holds only ids, so readable
# names are resolved by join. The list is query-by-example (CONSTRUCT) because
# there are ~19k customers. Editable attribute: territory assignment. Add is not
# offered here - a customer must reference an existing person or store, which is
# outside the Sales scope. Delete is supported.
#
# Public entry: customers_run()
################################################################################

IMPORT FGL lib_aw

#+ Maximum customers loaded per search (keeps the list responsive).
PRIVATE CONSTANT MAX_ROWS = 500

TYPE t_cust RECORD
    customerid  INTEGER,
    custtype    VARCHAR(20),
    custname    VARCHAR(120),
    territoryid INTEGER
END RECORD

PRIVATE DEFINE m_cust DYNAMIC ARRAY OF t_cust
PRIVATE DEFINE m_wc   STRING
PRIVATE DEFINE m_quit BOOLEAN

#-------------------------------------------------------------------------------
#+ Open the customers window and run the search / browse loop.
#-------------------------------------------------------------------------------
FUNCTION customers_run()
    OPEN WINDOW w_cust WITH FORM "customers"
        ATTRIBUTES(TEXT = "Customers", STYLE = "dialog")
    CALL cust_fill_combos()
    LET m_quit = FALSE
    WHILE NOT m_quit
        IF cust_search() THEN
            CALL cust_load()
            CALL cust_browse()
        ELSE
            LET m_quit = TRUE
        END IF
    END WHILE
    CLOSE WINDOW w_cust
END FUNCTION

#-------------------------------------------------------------------------------
#+ Populate the territory comboboxes (search filter and inline editor).
#-------------------------------------------------------------------------------
PRIVATE FUNCTION cust_fill_combos()
    DEFINE l_sql STRING
    LET l_sql = "SELECT territoryid, name FROM salesterritory ORDER BY name"
    CALL aw_fill_combobox("f_terr", l_sql)
    CALL aw_fill_combobox("r_terr", l_sql)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Query-by-example over the customer base columns. Returns TRUE if the user
#+ launched a search, FALSE if they cancelled (to leave the screen).
#-------------------------------------------------------------------------------
PRIVATE FUNCTION cust_search() RETURNS BOOLEAN
    CONSTRUCT BY NAME m_wc ON customer.customerid, customer.territoryid
    RETURN (NOT int_flag)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Run the search and load up to MAX_ROWS rows, resolving names by join. Uses
#+ full table names (no aliases) so the CONSTRUCT WHERE clause matches.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION cust_load()
    DEFINE r t_cust
    DEFINE l_sql STRING
    LET l_sql =
        "SELECT customer.customerid,"
        || " CASE WHEN customer.storeid IS NOT NULL THEN 'Store' ELSE 'Individual' END,"
        || " CASE WHEN store.name IS NOT NULL THEN store.name"
        || "      ELSE TRIM(person.lastname) || ', ' || TRIM(person.firstname) END,"
        || " customer.territoryid"
        || " FROM customer"
        || " LEFT JOIN person ON person.businessentityid = customer.personid"
        || " LEFT JOIN store  ON store.businessentityid  = customer.storeid"
        || " WHERE " || m_wc
        || " ORDER BY customer.customerid"
    CALL m_cust.clear()
    DECLARE c_cust CURSOR FROM l_sql
    FOREACH c_cust INTO r.*
        LET m_cust[m_cust.getLength() + 1] = r
        IF m_cust.getLength() >= MAX_ROWS THEN
            EXIT FOREACH
        END IF
    END FOREACH
    IF m_cust.getLength() >= MAX_ROWS THEN
        MESSAGE SFMT("Showing the first %1 matches - refine the search to narrow the list.", MAX_ROWS)
    END IF
END FUNCTION

#-------------------------------------------------------------------------------
#+ Browse the result list. Inline-edit reassigns the territory; remove deletes
#+ the customer; new-search returns to the criteria; close leaves the screen.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION cust_browse()
    DEFINE rec t_cust
    DISPLAY ARRAY m_cust TO sr_cust.* ATTRIBUTES(DOUBLECLICK = update, UNBUFFERED)

        ON UPDATE
            LET rec = m_cust[arr_curr()]
            LET int_flag = FALSE
            INPUT rec.territoryid FROM sr_cust[scr_line()].r_terr
                ATTRIBUTES(WITHOUT DEFAULTS)
            IF NOT int_flag THEN
                IF cust_save_territory(rec) THEN
                    LET m_cust[arr_curr()] = rec
                END IF
            END IF

        ON ACTION remove ATTRIBUTES(TEXT = "Delete", IMAGE = "fa-trash")
            IF m_cust.getLength() > 0 THEN
                IF aw_confirm("Delete customer",
                              SFMT("Delete customer %1 (%2)?",
                                   m_cust[arr_curr()].customerid, m_cust[arr_curr()].custname)) THEN
                    IF cust_delete(m_cust[arr_curr()].customerid) THEN
                        CALL m_cust.deleteElement(arr_curr())
                    END IF
                END IF
            END IF

        ON ACTION newsearch ATTRIBUTES(TEXT = "New search", IMAGE = "fa-search")
            EXIT DISPLAY

        ON ACTION close
            LET m_quit = TRUE
            EXIT DISPLAY

    END DISPLAY
END FUNCTION

#-------------------------------------------------------------------------------
#+ Update a customer's territory assignment.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION cust_save_territory(rec t_cust INOUT) RETURNS BOOLEAN
    DEFINE l_now DATETIME YEAR TO SECOND
    LET l_now = CURRENT YEAR TO SECOND
    BEGIN WORK
    TRY
        UPDATE customer
           SET territoryid = rec.territoryid, modifieddate = l_now
         WHERE customerid = rec.customerid
        COMMIT WORK
    CATCH
        ROLLBACK WORK
        CALL aw_sql_error("Updating customer territory")
        RETURN FALSE
    END TRY
    RETURN TRUE
END FUNCTION

#-------------------------------------------------------------------------------
#+ Delete a customer. Customers referenced by orders cannot be removed.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION cust_delete(p_id INTEGER) RETURNS BOOLEAN
    BEGIN WORK
    TRY
        DELETE FROM customer WHERE customerid = p_id
        COMMIT WORK
    CATCH
        ROLLBACK WORK
        IF sqlca.sqlcode = -692 OR sqlca.sqlcode = -691 THEN
            ERROR "Cannot delete: this customer still has orders or other references."
        ELSE
            CALL aw_sql_error("Deleting customer")
        END IF
        RETURN FALSE
    END TRY
    RETURN TRUE
END FUNCTION
