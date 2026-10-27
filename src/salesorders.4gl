################################################################################
# salesorders.4gl - the centerpiece: browse, view and edit sales orders with
# their line items (salesorderdetail) as a master-detail screen.
#
# AdventureWorks' computed columns were dropped in the PostgreSQL port, so the
# derived values are recomputed here in 4GL:
#   * line total      = orderqty * unitprice * (1 - unitpricediscount)
#   * subtotal        = sum of line totals
#   * total due       = subtotal + taxamt + freight
#   * sales order no.  = 'SO' || salesorderid
#
# Line items are persisted with a delete-all + insert-all strategy inside one
# transaction (salesorderdetail is a leaf table, so this is safe and avoids
# per-row diff tracking).
#
# Public entry: salesorders_run()
################################################################################

IMPORT security

IMPORT FGL lib_aw
IMPORT FGL aw_calc
IMPORT FGL aw_repo

PRIVATE CONSTANT MAX_ROWS = 500
#+ specialofferid 1 is the standard "No Discount" offer in AdventureWorks.
PRIVATE CONSTANT NO_DISCOUNT_OFFER = 1

#+ Order summary row for the list.
TYPE t_order RECORD
    salesorderid INTEGER,
    o_num        VARCHAR(25),
    o_date       DATE,
    o_cust       VARCHAR(120),
    o_status     VARCHAR(20),
    o_total      DECIMAL(20,4)
END RECORD

#+ Editable header fields (member names match the sr_hdr form fields).
TYPE t_hdr RECORD
    salesordernumber VARCHAR(25),
    orderdate        DATE,
    custname         VARCHAR(120),
    status           INTEGER,
    shipdate         DATE,
    salespersonid    INTEGER,
    territoryid      INTEGER,
    comment          VARCHAR(128),
    subtotal         DECIMAL(20,4),
    taxamt           DECIMAL(20,4),
    freight          DECIMAL(20,4),
    totaldue         DECIMAL(20,4)
END RECORD

#+ Editable line item (member names match the sr_lines form fields).
TYPE t_line RECORD
    productid         INTEGER,
    specialofferid    INTEGER,
    orderqty          INTEGER,
    unitprice         DECIMAL(20,4),
    unitpricediscount DECIMAL(10,4),
    linetotal         DECIMAL(20,4)
END RECORD

PRIVATE DEFINE m_orders DYNAMIC ARRAY OF t_order
PRIVATE DEFINE m_owc    STRING
PRIVATE DEFINE m_oquit  BOOLEAN

PRIVATE DEFINE m_hdr    t_hdr
PRIVATE DEFINE m_lines  DYNAMIC ARRAY OF t_line
PRIVATE DEFINE m_soid   INTEGER
PRIVATE DEFINE m_custid INTEGER

################################################################################
# List / search
################################################################################

#-------------------------------------------------------------------------------
#+ Open the orders list window and run the search / browse loop.
#-------------------------------------------------------------------------------
FUNCTION salesorders_run()
    OPEN WINDOW w_olist WITH FORM "salesorders_list"
        ATTRIBUTES(TEXT = "Sales Orders", STYLE = "dialog")
    LET m_oquit = FALSE
    WHILE NOT m_oquit
        IF so_search() THEN
            CALL so_load_list()
            CALL so_list_browse()
        ELSE
            LET m_oquit = TRUE
        END IF
    END WHILE
    CLOSE WINDOW w_olist
END FUNCTION

#-------------------------------------------------------------------------------
#+ Query-by-example over the order base columns. Returns FALSE if cancelled.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION so_search() RETURNS BOOLEAN
    CONSTRUCT BY NAME m_owc ON salesorderheader.salesorderid, salesorderheader.customerid
    RETURN (NOT int_flag)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Run the search, loading up to MAX_ROWS order summaries with a computed total.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION so_load_list()
    DEFINE r t_order
    DEFINE l_status INTEGER
    DEFINE l_custid INTEGER
    DEFINE l_sql STRING
    LET l_sql =
        "SELECT salesorderheader.salesorderid, salesorderheader.orderdate,"
        || " salesorderheader.status, salesorderheader.customerid,"
        || " (salesorderheader.subtotal + salesorderheader.taxamt + salesorderheader.freight)"
        || " FROM salesorderheader"
        || " WHERE " || m_owc
        || " ORDER BY salesorderheader.salesorderid DESC"
    CALL m_orders.clear()
    DECLARE c_olist CURSOR FROM l_sql
    FOREACH c_olist INTO r.salesorderid, r.o_date, l_status, l_custid, r.o_total
        LET r.o_num = aw_calc.aw_order_number(r.salesorderid)
        LET r.o_status = aw_calc.aw_status_label(l_status)
        LET r.o_cust = aw_customer_label(l_custid)
        LET m_orders[m_orders.getLength() + 1] = r
        IF m_orders.getLength() >= MAX_ROWS THEN
            EXIT FOREACH
        END IF
    END FOREACH
    IF m_orders.getLength() >= MAX_ROWS THEN
        MESSAGE SFMT("Showing the first %1 matches - refine the search to narrow the list.", MAX_ROWS)
    END IF
END FUNCTION

#-------------------------------------------------------------------------------
#+ Browse the order list. Open edits the selected order; new creates one.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION so_list_browse()
    DEFINE l_newid INTEGER
    DISPLAY ARRAY m_orders TO sr_orders.* ATTRIBUTES(DOUBLECLICK = open)

        ON ACTION open ATTRIBUTES(TEXT = "Open", IMAGE = "fa-folder-open")
            IF m_orders.getLength() > 0 THEN
                CALL so_edit(m_orders[arr_curr()].salesorderid)
                CALL so_load_list()
            END IF

        ON ACTION new ATTRIBUTES(TEXT = "New order", IMAGE = "fa-plus")
            LET l_newid = so_new()
            IF l_newid > 0 THEN
                CALL so_edit(l_newid)
                CALL so_load_list()
            END IF

        ON ACTION newsearch ATTRIBUTES(TEXT = "New search", IMAGE = "fa-search")
            EXIT DISPLAY

        ON ACTION close
            LET m_oquit = TRUE
            EXIT DISPLAY

    END DISPLAY
END FUNCTION

################################################################################
# Master-detail edit
################################################################################

#-------------------------------------------------------------------------------
#+ Open the master-detail editor for one order.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION so_edit(p_soid INTEGER)
    LET m_soid = p_soid
    OPEN WINDOW w_oedit WITH FORM "salesorders"
        ATTRIBUTES(TEXT = "Sales Order", STYLE = "dialog")
    CALL so_fill_combos()
    CALL so_load_header()
    CALL so_load_lines()
    CALL so_recompute()
    CALL so_dialog()
    CLOSE WINDOW w_oedit
END FUNCTION

#-------------------------------------------------------------------------------
#+ Populate the header and line comboboxes once for the editor.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION so_fill_combos()
    DEFINE l_cb ui.ComboBox
    CALL so_fill_status()
    CALL aw_fill_combobox("f_sp",
        "SELECT salesperson.businessentityid,"
        || " TRIM(person.lastname) || ', ' || TRIM(person.firstname)"
        || " FROM salesperson"
        || " LEFT JOIN person ON person.businessentityid = salesperson.businessentityid"
        || " ORDER BY 2")
    CALL aw_fill_combobox("f_terr", "SELECT territoryid, name FROM salesterritory ORDER BY name")
    # Only products that are actually for sale (present in specialofferproduct) can
    # appear on an order line - salesorderdetail has a composite FK on
    # (specialofferid, productid) into specialofferproduct.
    CALL aw_fill_combobox("l_prod",
        "SELECT DISTINCT product.productid, product.name"
        || " FROM product"
        || " JOIN specialofferproduct ON specialofferproduct.productid = product.productid"
        || " ORDER BY product.name")
    CALL aw_fill_combobox("l_offer",
        "SELECT specialofferid, description FROM specialoffer ORDER BY specialofferid")
    # salesperson and territory are optional on an order
    LET l_cb = ui.ComboBox.forName("f_sp")
    IF l_cb IS NOT NULL THEN CALL l_cb.addItem(NULL, "(none)") END IF
    LET l_cb = ui.ComboBox.forName("f_terr")
    IF l_cb IS NOT NULL THEN CALL l_cb.addItem(NULL, "(none)") END IF
END FUNCTION

#-------------------------------------------------------------------------------
#+ Fill the order-status combobox with its code/label pairs.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION so_fill_status()
    DEFINE l_cb ui.ComboBox
    LET l_cb = ui.ComboBox.forName("f_status")
    IF l_cb IS NULL THEN RETURN END IF
    CALL l_cb.clear()
    CALL l_cb.addItem(1, "1 - In process")
    CALL l_cb.addItem(2, "2 - Approved")
    CALL l_cb.addItem(3, "3 - Backordered")
    CALL l_cb.addItem(4, "4 - Rejected")
    CALL l_cb.addItem(5, "5 - Shipped")
    CALL l_cb.addItem(6, "6 - Cancelled")
END FUNCTION

#-------------------------------------------------------------------------------
#+ Load the editable header fields plus the context needed for save.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION so_load_header()
    SELECT orderdate, status, shipdate, salespersonid, territoryid, comment,
           subtotal, taxamt, freight, customerid
      INTO m_hdr.orderdate, m_hdr.status, m_hdr.shipdate, m_hdr.salespersonid,
           m_hdr.territoryid, m_hdr.comment, m_hdr.subtotal, m_hdr.taxamt,
           m_hdr.freight, m_custid
      FROM salesorderheader
     WHERE salesorderid = m_soid
    LET m_hdr.salesordernumber = aw_calc.aw_order_number(m_soid)
    LET m_hdr.custname = aw_customer_label(m_custid)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Load the order's line items.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION so_load_lines()
    DEFINE r t_line
    CALL m_lines.clear()
    DECLARE c_lines CURSOR FROM
        "SELECT productid, specialofferid, orderqty, unitprice, unitpricediscount"
        || " FROM salesorderdetail WHERE salesorderid = ? ORDER BY salesorderdetailid"
    FOREACH c_lines USING m_soid INTO r.productid, r.specialofferid, r.orderqty,
                                       r.unitprice, r.unitpricediscount
        LET m_lines[m_lines.getLength() + 1] = r
    END FOREACH
END FUNCTION

#-------------------------------------------------------------------------------
#+ The master-detail dialog: header INPUT + editable line-item grid.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION so_dialog()
    DIALOG ATTRIBUTES(UNBUFFERED)

        INPUT BY NAME m_hdr.* ATTRIBUTES(WITHOUT DEFAULTS)
        END INPUT

        INPUT ARRAY m_lines FROM sr_lines.*
            ATTRIBUTES(WITHOUT DEFAULTS, APPEND ROW = TRUE, DELETE ROW = TRUE, INSERT ROW = FALSE)

            AFTER INSERT
                LET m_lines[arr_curr()].specialofferid = NO_DISCOUNT_OFFER
                IF m_lines[arr_curr()].orderqty IS NULL THEN
                    LET m_lines[arr_curr()].orderqty = 1
                END IF
                IF m_lines[arr_curr()].unitpricediscount IS NULL THEN
                    LET m_lines[arr_curr()].unitpricediscount = 0
                END IF
                CALL so_recompute()

            ON CHANGE l_prod
                CALL so_set_price(arr_curr())
                CALL so_recompute()

            ON CHANGE l_qty
                CALL so_recompute()

            ON CHANGE l_price
                CALL so_recompute()

            ON CHANGE l_disc
                CALL so_recompute()

            AFTER DELETE
                CALL so_recompute()

        END INPUT

        ON ACTION accept ATTRIBUTES(TEXT = "Save", IMAGE = "fa-save")
            IF so_validate() THEN
                IF so_save() THEN
                    MESSAGE "Order saved."
                    EXIT DIALOG
                END IF
            END IF

        ON ACTION cancel
            EXIT DIALOG

    END DIALOG
END FUNCTION

#-------------------------------------------------------------------------------
#+ Default a line's unit price from the chosen product's list price.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION so_set_price(p_row INTEGER)
    DEFINE l_price DECIMAL(20,4)
    IF m_lines[p_row].productid IS NULL THEN RETURN END IF
    LET l_price = aw_repo.repo_product_list_price(m_lines[p_row].productid)
    IF l_price IS NOT NULL THEN
        LET m_lines[p_row].unitprice = l_price
    END IF
    # Reflect a valid offer for the chosen product (keeps the display honest;
    # the same rule is enforced at save time).
    LET m_lines[p_row].specialofferid =
        aw_repo.repo_resolve_offer(m_lines[p_row].productid, m_lines[p_row].specialofferid)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Recompute every line total, the subtotal and the total due, and reflect the
#+ header totals on screen. The arithmetic lives in aw_calc (pure + tested).
#-------------------------------------------------------------------------------
PRIVATE FUNCTION so_recompute()
    DEFINE i INTEGER
    DEFINE l_sub DECIMAL(20,4)
    LET l_sub = 0
    FOR i = 1 TO m_lines.getLength()
        IF m_lines[i].orderqty IS NULL THEN LET m_lines[i].orderqty = 0 END IF
        IF m_lines[i].unitprice IS NULL THEN LET m_lines[i].unitprice = 0 END IF
        IF m_lines[i].unitpricediscount IS NULL THEN LET m_lines[i].unitpricediscount = 0 END IF
        LET m_lines[i].linetotal = aw_calc.aw_line_total(m_lines[i].orderqty,
                                       m_lines[i].unitprice, m_lines[i].unitpricediscount)
        LET l_sub = l_sub + m_lines[i].linetotal
    END FOR
    LET m_hdr.subtotal = l_sub
    LET m_hdr.totaldue = aw_calc.aw_order_total(m_hdr.subtotal, m_hdr.taxamt, m_hdr.freight)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Validate the order before saving.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION so_validate() RETURNS BOOLEAN
    DEFINE i INTEGER
    IF m_lines.getLength() = 0 THEN
        ERROR "An order must have at least one line item."
        RETURN FALSE
    END IF
    FOR i = 1 TO m_lines.getLength()
        IF m_lines[i].productid IS NULL THEN
            ERROR SFMT("Line %1: a product is required.", i)
            RETURN FALSE
        END IF
        IF m_lines[i].orderqty IS NULL OR m_lines[i].orderqty <= 0 THEN
            ERROR SFMT("Line %1: quantity must be greater than zero.", i)
            RETURN FALSE
        END IF
        IF m_lines[i].unitprice IS NULL OR m_lines[i].unitprice < 0 THEN
            ERROR SFMT("Line %1: unit price must not be negative.", i)
            RETURN FALSE
        END IF
    END FOR
    RETURN TRUE
END FUNCTION

#-------------------------------------------------------------------------------
#+ Persist header changes and rewrite the line items in one transaction.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION so_save() RETURNS BOOLEAN
    DEFINE i INTEGER
    DEFINE l_now DATETIME YEAR TO SECOND
    DEFINE l_uuid VARCHAR(36)
    LET l_now = CURRENT YEAR TO SECOND
    BEGIN WORK
    TRY
        UPDATE salesorderheader
           SET status = m_hdr.status, shipdate = m_hdr.shipdate,
               salespersonid = m_hdr.salespersonid, territoryid = m_hdr.territoryid,
               comment = m_hdr.comment, subtotal = m_hdr.subtotal,
               modifieddate = l_now
         WHERE salesorderid = m_soid

        DELETE FROM salesorderdetail WHERE salesorderid = m_soid

        PREPARE p_det_ins FROM
            "INSERT INTO salesorderdetail"
            || " (salesorderid, orderqty, productid, specialofferid, unitprice,"
            || "  unitpricediscount, rowguid, modifieddate)"
            || " VALUES (?,?,?,?,?,?,?,?)"
        FOR i = 1 TO m_lines.getLength()
            # Ensure the (specialofferid, productid) pair satisfies the composite FK
            # into specialofferproduct; fall back to a valid offer for the product.
            LET m_lines[i].specialofferid =
                aw_repo.repo_resolve_offer(m_lines[i].productid, m_lines[i].specialofferid)
            IF m_lines[i].specialofferid IS NULL THEN
                ROLLBACK WORK
                ERROR SFMT("Line %1: that product is not available for sale.", i)
                RETURN FALSE
            END IF
            LET l_uuid = security.RandomGenerator.CreateUUIDString()
            EXECUTE p_det_ins USING m_soid, m_lines[i].orderqty, m_lines[i].productid,
                                    m_lines[i].specialofferid, m_lines[i].unitprice,
                                    m_lines[i].unitpricediscount, l_uuid, l_now
        END FOR

        COMMIT WORK
    CATCH
        ROLLBACK WORK
        CALL aw_sql_error("Saving order")
        RETURN FALSE
    END TRY
    RETURN TRUE
END FUNCTION

################################################################################
# New order
################################################################################

#-------------------------------------------------------------------------------
#+ Create a new (empty) order for a chosen customer, deriving the required FK
#+ values (bill/ship address, ship method) from the customer. Returns the new
#+ salesorderid, or 0 if the user cancelled or the order could not be created.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION so_new() RETURNS INTEGER
    DEFINE l_custid  INTEGER
    DEFINE l_beid    INTEGER
    DEFINE l_addr    INTEGER
    DEFINE l_ship    INTEGER
    DEFINE l_newid   INTEGER
    DEFINE l_uuid    VARCHAR(36)
    DEFINE l_now     DATETIME YEAR TO SECOND

    LET l_custid = NULL
    PROMPT "Customer ID for the new order: " FOR l_custid
    IF int_flag THEN
        RETURN 0
    END IF
    IF l_custid IS NULL THEN
        RETURN 0
    END IF

    IF NOT aw_repo.repo_customer_exists(l_custid) THEN
        ERROR SFMT("No customer with id %1.", l_custid)
        RETURN 0
    END IF

    SELECT COALESCE(personid, storeid) INTO l_beid FROM customer WHERE customerid = l_custid
    IF l_beid IS NULL THEN
        ERROR "This customer is not linked to a person or store; cannot derive an address."
        RETURN 0
    END IF
    SELECT MIN(addressid) INTO l_addr FROM businessentityaddress WHERE businessentityid = l_beid
    IF l_addr IS NULL THEN
        ERROR "This customer has no address on file; cannot create an order."
        RETURN 0
    END IF
    SELECT MIN(shipmethodid) INTO l_ship FROM shipmethod
    IF l_ship IS NULL THEN
        ERROR "No shipping methods are defined."
        RETURN 0
    END IF

    LET l_now = CURRENT YEAR TO SECOND
    LET l_uuid = security.RandomGenerator.CreateUUIDString()
    BEGIN WORK
    TRY
        EXECUTE IMMEDIATE
            "INSERT INTO salesorderheader"
            || " (revisionnumber, orderdate, duedate, status, onlineorderflag,"
            || "  customerid, billtoaddressid, shiptoaddressid, shipmethodid,"
            || "  subtotal, taxamt, freight, rowguid, modifieddate)"
            || " VALUES (1, '" || TODAY || "', '" || (TODAY + 7) || "', 1, FALSE, "
            || l_custid || ", " || l_addr || ", " || l_addr || ", " || l_ship
            || ", 0, 0, 0, '" || l_uuid || "', '" || l_now || "')"
        LET l_newid = sqlca.sqlerrd[2]
        COMMIT WORK
    CATCH
        ROLLBACK WORK
        CALL aw_sql_error("Creating order")
        RETURN 0
    END TRY
    RETURN l_newid
END FUNCTION
