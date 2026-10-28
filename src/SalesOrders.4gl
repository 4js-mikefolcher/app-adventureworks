################################################################################
# SalesOrders.4gl - the centerpiece: browse, view and edit sales orders with
# their line items (salesorderdetail) as a master-detail screen.
#
# AdventureWorks' computed columns were dropped in the PostgreSQL port, so the
# derived values are recomputed here in 4GL:
#   * line total      = orderQty * unitPrice * (1 - unitPriceDiscount)
#   * subtotal        = sum of line totals
#   * total due       = subtotal + taxAmt + freight
#   * sales order no. = 'SO' || salesorderid
#
# Line items are persisted with a delete-all + insert-all strategy inside one
# transaction (salesorderdetail is a leaf table, so this is safe and avoids
# per-row diff tracking).
#
# Static SQL always qualifies columns with their table name; identifiers are
# case-insensitive, so an unqualified column such as status or salesorderid
# would be compiled as a host variable whenever a variable of that name exists.
#
# Public entry: salesOrdersRun()
################################################################################

IMPORT security

IMPORT FGL LibAw
IMPORT FGL AwCalc
IMPORT FGL AwRepo

PRIVATE CONSTANT cMaxRows = 500
#+ specialofferid 1 is the standard "No Discount" offer in AdventureWorks.
PRIVATE CONSTANT cNoDiscountOffer = 1

#+ Order summary row for the list.
PRIVATE TYPE tOrder RECORD
   salesOrderId  INTEGER,
   orderNumber   VARCHAR(25),
   orderDate     DATE,
   customerName  VARCHAR(120),
   statusLabel   VARCHAR(20),
   totalDue      DECIMAL(20,4)
END RECORD

#+ Editable header fields (member names match the srHeader form fields).
PRIVATE TYPE tHeader RECORD
   salesOrderNumber VARCHAR(25),
   orderDate        DATE,
   customerName     VARCHAR(120),
   statusCode       INTEGER,
   shipDate         DATE,
   salesPersonId    INTEGER,
   territoryId      INTEGER,
   comment          VARCHAR(128),
   subtotal         DECIMAL(20,4),
   taxAmt           DECIMAL(20,4),
   freight          DECIMAL(20,4),
   totalDue         DECIMAL(20,4)
END RECORD

#+ Editable line item (member names match the srLines form fields).
PRIVATE TYPE tLine RECORD
   productId         INTEGER,
   specialOfferId    INTEGER,
   orderQty          INTEGER,
   unitPrice         DECIMAL(20,4),
   unitPriceDiscount DECIMAL(10,4),
   lineTotal         DECIMAL(20,4)
END RECORD

PRIVATE DEFINE orderList         DYNAMIC ARRAY OF tOrder
PRIVATE DEFINE orderWhere        STRING
PRIVATE DEFINE quitRequested     BOOLEAN

PRIVATE DEFINE orderHeader       tHeader
PRIVATE DEFINE lineList          DYNAMIC ARRAY OF tLine
PRIVATE DEFINE currentOrderId    INTEGER
PRIVATE DEFINE currentCustomerId INTEGER

################################################################################
# List / search
################################################################################

#-------------------------------------------------------------------------------
#+ Open the orders list window and run the search / browse loop.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION salesOrdersRun() RETURNS ()
   OPEN WINDOW wOrderList WITH FORM "SalesOrdersList"
      ATTRIBUTES(TEXT = "Sales Orders", STYLE = "dialog")
   LET quitRequested = FALSE
   WHILE NOT quitRequested
      IF searchOrders() THEN
         CALL loadOrderList()
         CALL browseOrderList()
      ELSE
         LET quitRequested = TRUE
      END IF
   END WHILE
   CLOSE WINDOW wOrderList
END FUNCTION

#-------------------------------------------------------------------------------
#+ Query-by-example over the order base columns. Returns FALSE if cancelled.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION searchOrders() RETURNS BOOLEAN
   CONSTRUCT BY NAME orderWhere ON salesorderheader.salesorderid, salesorderheader.customerid
   RETURN (NOT int_flag)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Run the search, loading up to cMaxRows order summaries with a computed total.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION loadOrderList() RETURNS ()
   VAR rec tOrder
   VAR statusCode INTEGER
   VAR customerId INTEGER
   VAR sqlText STRING
   LET sqlText =
      "SELECT salesorderheader.salesorderid, salesorderheader.orderdate,"
      || " salesorderheader.status, salesorderheader.customerid,"
      || " (salesorderheader.subtotal + salesorderheader.taxamt + salesorderheader.freight)"
      || " FROM salesorderheader"
      || " WHERE " || orderWhere
      || " ORDER BY salesorderheader.salesorderid DESC"
   CALL orderList.clear()
   DECLARE cursOrders CURSOR FROM sqlText
   FOREACH cursOrders INTO rec.salesOrderId, rec.orderDate, statusCode, customerId, rec.totalDue
      LET rec.orderNumber = AwCalc.awOrderNumber(rec.salesOrderId)
      LET rec.statusLabel = AwCalc.awStatusLabel(statusCode)
      LET rec.customerName = LibAw.awCustomerLabel(customerId)
      LET orderList[orderList.getLength() + 1] = rec
      IF orderList.getLength() >= cMaxRows THEN
         EXIT FOREACH
      END IF
   END FOREACH
   IF orderList.getLength() >= cMaxRows THEN
      MESSAGE SFMT("Showing the first %1 matches - refine the search to narrow the list.", cMaxRows)
   END IF
END FUNCTION

#-------------------------------------------------------------------------------
#+ Browse the order list. Open edits the selected order; new creates one.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION browseOrderList() RETURNS ()
   VAR newId INTEGER
   DISPLAY ARRAY orderList TO srOrders.* ATTRIBUTES(DOUBLECLICK = open)

      ON ACTION open ATTRIBUTES(TEXT = "Open", IMAGE = "fa-folder-open")
         IF orderList.getLength() > 0 THEN
            CALL editOrder(orderList[arr_curr()].salesOrderId)
            CALL loadOrderList()
         END IF

      ON ACTION new ATTRIBUTES(TEXT = "New order", IMAGE = "fa-plus")
         LET newId = newOrder()
         IF newId > 0 THEN
            CALL editOrder(newId)
            CALL loadOrderList()
         END IF

      ON ACTION newsearch ATTRIBUTES(TEXT = "New search", IMAGE = "fa-search")
         EXIT DISPLAY

      ON ACTION close
         LET quitRequested = TRUE
         EXIT DISPLAY

   END DISPLAY
END FUNCTION

################################################################################
# Master-detail edit
################################################################################

#-------------------------------------------------------------------------------
#+ Open the master-detail editor for one order.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION editOrder(orderId INTEGER) RETURNS ()
   LET currentOrderId = orderId
   OPEN WINDOW wOrderEdit WITH FORM "SalesOrders"
      ATTRIBUTES(TEXT = "Sales Order", STYLE = "dialog")
   CALL fillOrderCombos()
   CALL loadOrderHeader()
   CALL loadOrderLines()
   CALL recomputeTotals()
   CALL runOrderDialog()
   CLOSE WINDOW wOrderEdit
END FUNCTION

#-------------------------------------------------------------------------------
#+ Populate the header and line comboboxes once for the editor. Every combobox is
#+ addressed by its form field name (see the SalesOrders form).
#-------------------------------------------------------------------------------
PRIVATE FUNCTION fillOrderCombos() RETURNS ()
   VAR cb ui.ComboBox
   CALL fillStatusCombo()
   CALL LibAw.awFillComboBox("salesPersonId",
      "SELECT salesperson.businessentityid,"
      || " TRIM(person.lastname) || ', ' || TRIM(person.firstname)"
      || " FROM salesperson"
      || " LEFT JOIN person ON person.businessentityid = salesperson.businessentityid"
      || " ORDER BY 2")
   CALL LibAw.awFillComboBox("territoryId",
      "SELECT territoryid, name FROM salesterritory ORDER BY name")
   # Only products that are actually for sale (present in specialofferproduct) can
   # appear on an order line - salesorderdetail has a composite FK on
   # (specialofferid, productid) into specialofferproduct.
   CALL LibAw.awFillComboBox("productId",
      "SELECT DISTINCT product.productid, product.name"
      || " FROM product"
      || " JOIN specialofferproduct ON specialofferproduct.productid = product.productid"
      || " ORDER BY product.name")
   CALL LibAw.awFillComboBox("specialOfferId",
      "SELECT specialofferid, description FROM specialoffer ORDER BY specialofferid")
   # salesperson and territory are optional on an order
   LET cb = ui.ComboBox.forName("salesPersonId")
   IF cb IS NOT NULL THEN
      CALL cb.addItem(NULL, "(none)")
   END IF
   LET cb = ui.ComboBox.forName("territoryId")
   IF cb IS NOT NULL THEN
      CALL cb.addItem(NULL, "(none)")
   END IF
END FUNCTION

#-------------------------------------------------------------------------------
#+ Fill the order-status combobox with its code/label pairs.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION fillStatusCombo() RETURNS ()
   VAR cb ui.ComboBox
   LET cb = ui.ComboBox.forName("statusCode")
   IF cb IS NULL THEN
      RETURN
   END IF
   CALL cb.clear()
   CALL cb.addItem(1, "1 - In process")
   CALL cb.addItem(2, "2 - Approved")
   CALL cb.addItem(3, "3 - Backordered")
   CALL cb.addItem(4, "4 - Rejected")
   CALL cb.addItem(5, "5 - Shipped")
   CALL cb.addItem(6, "6 - Cancelled")
END FUNCTION

#-------------------------------------------------------------------------------
#+ Load the editable header fields plus the context needed for save.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION loadOrderHeader() RETURNS ()
   SELECT salesorderheader.orderdate, salesorderheader.status, salesorderheader.shipdate,
         salesorderheader.salespersonid, salesorderheader.territoryid,
         salesorderheader.comment, salesorderheader.subtotal, salesorderheader.taxamt,
         salesorderheader.freight, salesorderheader.customerid
      INTO orderHeader.orderDate, orderHeader.statusCode, orderHeader.shipDate,
         orderHeader.salesPersonId, orderHeader.territoryId, orderHeader.comment,
         orderHeader.subtotal, orderHeader.taxAmt, orderHeader.freight, currentCustomerId
      FROM salesorderheader
      WHERE salesorderheader.salesorderid = currentOrderId
   LET orderHeader.salesOrderNumber = AwCalc.awOrderNumber(currentOrderId)
   LET orderHeader.customerName = LibAw.awCustomerLabel(currentCustomerId)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Load the order's line items.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION loadOrderLines() RETURNS ()
   VAR rec tLine
   CALL lineList.clear()
   DECLARE cursLines CURSOR FROM
      "SELECT productid, specialofferid, orderqty, unitprice, unitpricediscount"
      || " FROM salesorderdetail WHERE salesorderid = ? ORDER BY salesorderdetailid"
   FOREACH cursLines USING currentOrderId INTO rec.productId, rec.specialOfferId, rec.orderQty,
         rec.unitPrice, rec.unitPriceDiscount
      LET lineList[lineList.getLength() + 1] = rec
   END FOREACH
END FUNCTION

#-------------------------------------------------------------------------------
#+ The master-detail dialog: header INPUT + editable line-item grid.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION runOrderDialog() RETURNS ()
   DIALOG ATTRIBUTES(UNBUFFERED)

      INPUT BY NAME orderHeader.* ATTRIBUTES(WITHOUT DEFAULTS)
      END INPUT

      INPUT ARRAY lineList FROM srLines.*
         ATTRIBUTES(WITHOUT DEFAULTS, APPEND ROW = TRUE, DELETE ROW = TRUE, INSERT ROW = FALSE)

         AFTER INSERT
            LET lineList[arr_curr()].specialOfferId = cNoDiscountOffer
            IF lineList[arr_curr()].orderQty IS NULL THEN
               LET lineList[arr_curr()].orderQty = 1
            END IF
            IF lineList[arr_curr()].unitPriceDiscount IS NULL THEN
               LET lineList[arr_curr()].unitPriceDiscount = 0
            END IF
            CALL recomputeTotals()

         ON CHANGE productId
            CALL setLinePrice(arr_curr())
            CALL recomputeTotals()

         ON CHANGE orderQty
            CALL recomputeTotals()

         ON CHANGE unitPrice
            CALL recomputeTotals()

         ON CHANGE unitPriceDiscount
            CALL recomputeTotals()

         AFTER DELETE
            CALL recomputeTotals()

      END INPUT

      ON ACTION accept ATTRIBUTES(TEXT = "Save", IMAGE = "fa-save")
         IF validateOrder() THEN
            IF saveOrder() THEN
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
PRIVATE FUNCTION setLinePrice(rowIndex INTEGER) RETURNS ()
   VAR price DECIMAL(20,4)
   IF lineList[rowIndex].productId IS NULL THEN
      RETURN
   END IF
   LET price = AwRepo.repoProductListPrice(lineList[rowIndex].productId)
   IF price IS NOT NULL THEN
      LET lineList[rowIndex].unitPrice = price
   END IF
   # Reflect a valid offer for the chosen product (keeps the display honest;
   # the same rule is enforced at save time).
   LET lineList[rowIndex].specialOfferId =
      AwRepo.repoResolveOffer(lineList[rowIndex].productId, lineList[rowIndex].specialOfferId)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Recompute every line total, the subtotal and the total due, and reflect the
#+ header totals on screen. The arithmetic lives in AwCalc (pure + tested).
#-------------------------------------------------------------------------------
PRIVATE FUNCTION recomputeTotals() RETURNS ()
   VAR i INTEGER
   VAR runningTotal DECIMAL(20,4)
   LET runningTotal = 0
   FOR i = 1 TO lineList.getLength()
      IF lineList[i].orderQty IS NULL THEN
         LET lineList[i].orderQty = 0
      END IF
      IF lineList[i].unitPrice IS NULL THEN
         LET lineList[i].unitPrice = 0
      END IF
      IF lineList[i].unitPriceDiscount IS NULL THEN
         LET lineList[i].unitPriceDiscount = 0
      END IF
      LET lineList[i].lineTotal = AwCalc.awLineTotal(lineList[i].orderQty,
         lineList[i].unitPrice, lineList[i].unitPriceDiscount)
      LET runningTotal = runningTotal + lineList[i].lineTotal
   END FOR
   LET orderHeader.subtotal = runningTotal
   LET orderHeader.totalDue = AwCalc.awOrderTotal(orderHeader.subtotal, orderHeader.taxAmt,
      orderHeader.freight)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Validate the order before saving.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION validateOrder() RETURNS BOOLEAN
   VAR i INTEGER
   IF lineList.getLength() = 0 THEN
      ERROR "An order must have at least one line item."
      RETURN FALSE
   END IF
   FOR i = 1 TO lineList.getLength()
      IF lineList[i].productId IS NULL THEN
         ERROR SFMT("Line %1: a product is required.", i)
         RETURN FALSE
      END IF
      IF lineList[i].orderQty IS NULL OR lineList[i].orderQty <= 0 THEN
         ERROR SFMT("Line %1: quantity must be greater than zero.", i)
         RETURN FALSE
      END IF
      IF lineList[i].unitPrice IS NULL OR lineList[i].unitPrice < 0 THEN
         ERROR SFMT("Line %1: unit price must not be negative.", i)
         RETURN FALSE
      END IF
   END FOR
   RETURN TRUE
END FUNCTION

#-------------------------------------------------------------------------------
#+ Persist header changes and rewrite the line items in one transaction.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION saveOrder() RETURNS BOOLEAN
   VAR i INTEGER
   VAR modifiedAt DATETIME YEAR TO SECOND
   VAR rowGuid VARCHAR(36)
   LET modifiedAt = CURRENT YEAR TO SECOND
   BEGIN WORK
   TRY
      UPDATE salesorderheader
         SET status = orderHeader.statusCode, shipdate = orderHeader.shipDate,
            salespersonid = orderHeader.salesPersonId, territoryid = orderHeader.territoryId,
            comment = orderHeader.comment, subtotal = orderHeader.subtotal,
            modifieddate = modifiedAt
         WHERE salesorderheader.salesorderid = currentOrderId

      DELETE FROM salesorderdetail WHERE salesorderdetail.salesorderid = currentOrderId

      PREPARE stmtDetailInsert FROM
         "INSERT INTO salesorderdetail"
         || " (salesorderid, orderqty, productid, specialofferid, unitprice,"
         || "  unitpricediscount, rowguid, modifieddate)"
         || " VALUES (?,?,?,?,?,?,?,?)"
      FOR i = 1 TO lineList.getLength()
         # Ensure the (specialofferid, productid) pair satisfies the composite FK
         # into specialofferproduct; fall back to a valid offer for the product.
         LET lineList[i].specialOfferId =
            AwRepo.repoResolveOffer(lineList[i].productId, lineList[i].specialOfferId)
         IF lineList[i].specialOfferId IS NULL THEN
            ROLLBACK WORK
            ERROR SFMT("Line %1: that product is not available for sale.", i)
            RETURN FALSE
         END IF
         LET rowGuid = security.RandomGenerator.CreateUUIDString()
         EXECUTE stmtDetailInsert USING currentOrderId, lineList[i].orderQty, lineList[i].productId,
               lineList[i].specialOfferId, lineList[i].unitPrice,
               lineList[i].unitPriceDiscount, rowGuid, modifiedAt
      END FOR

      COMMIT WORK
   CATCH
      ROLLBACK WORK
      CALL LibAw.awSqlError("Saving order")
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
PRIVATE FUNCTION newOrder() RETURNS INTEGER
   VAR customerId   INTEGER
   VAR entityId     INTEGER
   VAR addressId    INTEGER
   VAR shipMethodId INTEGER
   VAR newOrderId   INTEGER
   VAR rowGuid      VARCHAR(36)
   VAR modifiedAt   DATETIME YEAR TO SECOND

   LET customerId = NULL
   PROMPT "Customer ID for the new order: " FOR customerId
   IF int_flag THEN
      RETURN 0
   END IF
   IF customerId IS NULL THEN
      RETURN 0
   END IF

   IF NOT AwRepo.repoCustomerExists(customerId) THEN
      ERROR SFMT("No customer with id %1.", customerId)
      RETURN 0
   END IF

   SELECT COALESCE(customer.personid, customer.storeid) INTO entityId
      FROM customer WHERE customer.customerid = customerId
   IF entityId IS NULL THEN
      ERROR "This customer is not linked to a person or store; cannot derive an address."
      RETURN 0
   END IF
   SELECT MIN(businessentityaddress.addressid) INTO addressId
      FROM businessentityaddress WHERE businessentityaddress.businessentityid = entityId
   IF addressId IS NULL THEN
      ERROR "This customer has no address on file; cannot create an order."
      RETURN 0
   END IF
   SELECT MIN(shipmethod.shipmethodid) INTO shipMethodId FROM shipmethod
   IF shipMethodId IS NULL THEN
      ERROR "No shipping methods are defined."
      RETURN 0
   END IF

   LET modifiedAt = CURRENT YEAR TO SECOND
   LET rowGuid = security.RandomGenerator.CreateUUIDString()
   BEGIN WORK
   TRY
      EXECUTE IMMEDIATE
         "INSERT INTO salesorderheader"
         || " (revisionnumber, orderdate, duedate, status, onlineorderflag,"
         || "  customerid, billtoaddressid, shiptoaddressid, shipmethodid,"
         || "  subtotal, taxamt, freight, rowguid, modifieddate)"
         || " VALUES (1, '" || TODAY || "', '" || (TODAY + 7) || "', 1, FALSE, "
         || customerId || ", " || addressId || ", " || addressId || ", " || shipMethodId
         || ", 0, 0, 0, '" || rowGuid || "', '" || modifiedAt || "')"
      LET newOrderId = sqlca.sqlerrd[2]
      COMMIT WORK
   CATCH
      ROLLBACK WORK
      CALL LibAw.awSqlError("Creating order")
      RETURN 0
   END TRY
   RETURN newOrderId
END FUNCTION
