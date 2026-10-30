################################################################################
# SalesOrdersController.4gl - the centerpiece: browse, view and edit sales orders
# with their line items as a master-detail screen.
#
# Three views: SalesOrdersList (query-by-example search and the result list), SalesOrders
# (the header and the editable line-item grid) and NewOrder (the customer id asked for
# before an order is created). The controller owns the dialogs, the user flow and the
# SELECTs that fill the screens: the order list, the header and the lines, the customer
# name and the list-price default of a line. Validation, the derived values (line total,
# total due, order number, status label) and every write go through SalesOrdersModel.
# The comboboxes come from the lookups. The view records differ from the database records
# (DATE on the screen, DATETIME in the table, display-only members), so toDbOrderHeader
# and toDbOrderLines convert to them.
#
# Public entry: salesOrdersRun()
################################################################################

IMPORT util

IMPORT FGL ProductsLookup
IMPORT FGL SalesOrdersModel
IMPORT FGL SalesPersonsLookup
IMPORT FGL SpecialOffersLookup
IMPORT FGL TerritoriesLookup

PRIVATE CONSTANT cMaxRows = 1000

#+ Order summary row for the list. The order number and the status label are derived
#+ by the model after the read; the customer name comes from customerLabel.
PRIVATE TYPE tOrderRow RECORD
   salesOrderId  INTEGER,
   orderNumber   VARCHAR(25),
   orderDate     DATE,
   customerName  VARCHAR(120),
   statusLabel   VARCHAR(20),
   totalDue      DECIMAL(20,4)
END RECORD

#+ The header view record: member names match the srHeader form fields. The order
#+ number, the customer name and the total due are display-only (they have no column),
#+ "statusCode" is the column "status" (json_name), and the dates are DATEs on the
#+ screen while the columns are DATETIMEs.
PUBLIC TYPE tHeaderView RECORD
   salesOrderNumber VARCHAR(25),
   orderDate        DATE,
   customerName     VARCHAR(120),
   statusCode       INTEGER ATTRIBUTES(json_name = "status"),
   shipDate         DATE,
   salesPersonId    INTEGER,
   territoryId      INTEGER,
   comment          VARCHAR(128),
   subtotal         DECIMAL(20,4),
   taxAmt           DECIMAL(20,4),
   freight          DECIMAL(20,4),
   totalDue         DECIMAL(20,4)
END RECORD

#+ The line-item view record: member names match the srLines form fields. The line
#+ total is display-only: it has no column, the model derives it.
PUBLIC TYPE tLineView RECORD
   productId         INTEGER,
   specialOfferId    INTEGER,
   orderQty          INTEGER,
   unitPrice         DECIMAL(20,4),
   unitPriceDiscount DECIMAL(10,4),
   lineTotal         DECIMAL(20,4)
END RECORD

PRIVATE DEFINE orderList      DYNAMIC ARRAY OF tOrderRow
PRIVATE DEFINE orderWhere     STRING
PRIVATE DEFINE quitRequested  BOOLEAN

PRIVATE DEFINE orderHeader    tHeaderView
PRIVATE DEFINE lineList       DYNAMIC ARRAY OF tLineView
PRIVATE DEFINE currentOrderId INTEGER

################################################################################
# View record to database record
################################################################################

#-------------------------------------------------------------------------------
#+ Header view record to database record. The JSON bridge copies every member whose
#+ name matches a column (statusCode through its json_name), ignores the display-only
#+ ones, and sets the columns the view does not carry to NULL, so the model's UPDATE
#+ names the columns it writes. Special cases follow the bridge: the order id (the view
#+ does not hold it) and the two dates, because the bridge turns a DATE going into a
#+ DATETIME into NULL without an error.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION toDbOrderHeader(viewRec tHeaderView, orderId INTEGER)
      RETURNS SalesOrdersModel.tOrderHeader
   VAR dbRec SalesOrdersModel.tOrderHeader
   CALL util.JSONObject.fromFGL(viewRec).toFGL(dbRec)
   LET dbRec.salesorderid = orderId
   LET dbRec.orderdate = viewRec.orderDate
   LET dbRec.shipdate = viewRec.shipDate
   RETURN dbRec
END FUNCTION

#-------------------------------------------------------------------------------
#+ Line view record to database record. The JSON bridge copies the members that match
#+ a column and ignores the display-only line total; the order id is added after it.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION toDbOrderLine(viewRec tLineView, orderId INTEGER)
      RETURNS SalesOrdersModel.tOrderLine
   VAR dbRec SalesOrdersModel.tOrderLine
   CALL util.JSONObject.fromFGL(viewRec).toFGL(dbRec)
   LET dbRec.salesorderid = orderId
   RETURN dbRec
END FUNCTION

#-------------------------------------------------------------------------------
#+ Every line view record to a database record, in order, into the array the caller
#+ passes in (a dynamic array is passed by reference, so the caller sees the result).
#+ The array is a parameter and not a return value because fglcomp 6.00.01 crashes
#+ (segmentation fault) on a function returning a DYNAMIC ARRAY of the model's record
#+ type in this module.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION toDbOrderLines(viewList DYNAMIC ARRAY OF tLineView, orderId INTEGER,
      dbList DYNAMIC ARRAY OF SalesOrdersModel.tOrderLine) RETURNS ()
   VAR i INTEGER
   CALL dbList.clear()
   FOR i = 1 TO viewList.getLength()
      LET dbList[i] = toDbOrderLine(viewList[i], orderId)
   END FOR
END FUNCTION

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
   LET int_flag = FALSE
   CONSTRUCT BY NAME orderWhere ON salesorderheader.salesorderid, salesorderheader.customerid
   RETURN (NOT int_flag)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Run the search, loading up to cMaxRows order summaries. The customer name comes
#+ from customerLabel; the order number and the status label are derived by the model
#+ after each read. The SQL is dynamic because the WHERE clause comes from the CONSTRUCT.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION loadOrderList() RETURNS ()
   VAR rec tOrderRow
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
   FOREACH cursOrders INTO rec.salesOrderId, rec.orderDate, statusCode, customerId,
         rec.totalDue
      LET rec.orderNumber = SalesOrdersModel.orderNumber(rec.salesOrderId)
      LET rec.statusLabel = SalesOrdersModel.statusLabel(statusCode)
      LET rec.customerName = customerLabel(customerId)
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
#+ The display name of a customer: the store name, else "last, first" of the person,
#+ else "Customer <id>".
#-------------------------------------------------------------------------------
PRIVATE FUNCTION customerLabel(customerId INTEGER) RETURNS STRING
   VAR customerText STRING
   SELECT CASE WHEN store.name IS NOT NULL THEN store.name
         ELSE TRIM(person.lastname) || ', ' || TRIM(person.firstname) END
      INTO customerText
      FROM customer
      LEFT JOIN person ON person.businessentityid = customer.personid
      LEFT JOIN store ON store.businessentityid = customer.storeid
      WHERE customer.customerid = customerId
   IF customerText IS NULL THEN
      LET customerText = SFMT("Customer %1", customerId)
   END IF
   RETURN customerText
END FUNCTION

#-------------------------------------------------------------------------------
#+ Browse the order list. Open edits the selected order; new creates one.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION browseOrderList() RETURNS ()
   VAR newId INTEGER
   LET int_flag = FALSE
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
#+ addressed by its form field name (see the SalesOrders form). The status list is
#+ this feature's own (the model labels the codes); the others come from the lookups.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION fillOrderCombos() RETURNS ()
   CALL fillStatusCombo()
   CALL SalesPersonsLookup.fillSalesPersons(ui.ComboBox.forName("salesPersonId"))
   CALL TerritoriesLookup.fillTerritories(ui.ComboBox.forName("territoryId"))
   CALL ProductsLookup.fillProducts(ui.ComboBox.forName("productId"))
   CALL SpecialOffersLookup.fillSpecialOffers(ui.ComboBox.forName("specialOfferId"))
   # salesperson and territory are optional on an order
   CALL ui.ComboBox.forName("salesPersonId").addItem(NULL, "(none)")
   CALL ui.ComboBox.forName("territoryId").addItem(NULL, "(none)")
END FUNCTION

#-------------------------------------------------------------------------------
#+ Fill the order-status combobox with its code/label pairs.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION fillStatusCombo() RETURNS ()
   VAR comboBox ui.ComboBox = ui.ComboBox.forName("statusCode")
   VAR code INTEGER
   CALL comboBox.clear()
   FOR code = 1 TO SalesOrdersModel.cLastStatus
      CALL comboBox.addItem(code, SFMT("%1 - %2", code, SalesOrdersModel.statusLabel(code)))
   END FOR
END FUNCTION

#-------------------------------------------------------------------------------
#+ Load the editable header fields, with the customer name resolved by join.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION loadOrderHeader() RETURNS ()
   VAR customerId INTEGER
   SELECT salesorderheader.orderdate, salesorderheader.status, salesorderheader.shipdate,
         salesorderheader.salespersonid, salesorderheader.territoryid,
         salesorderheader.comment, salesorderheader.subtotal, salesorderheader.taxamt,
         salesorderheader.freight, salesorderheader.customerid,
         CASE WHEN store.name IS NOT NULL THEN store.name
            ELSE TRIM(person.lastname) || ', ' || TRIM(person.firstname) END
      INTO orderHeader.orderDate, orderHeader.statusCode, orderHeader.shipDate,
         orderHeader.salesPersonId, orderHeader.territoryId, orderHeader.comment,
         orderHeader.subtotal, orderHeader.taxAmt, orderHeader.freight, customerId,
         orderHeader.customerName
      FROM salesorderheader
      LEFT JOIN customer ON customer.customerid = salesorderheader.customerid
      LEFT JOIN person ON person.businessentityid = customer.personid
      LEFT JOIN store ON store.businessentityid = customer.storeid
      WHERE salesorderheader.salesorderid = currentOrderId
   LET orderHeader.salesOrderNumber = SalesOrdersModel.orderNumber(currentOrderId)
   IF orderHeader.customerName IS NULL THEN
      LET orderHeader.customerName = SFMT("Customer %1", customerId)
   END IF
END FUNCTION

#-------------------------------------------------------------------------------
#+ Load the order's line items. The column list follows tLineView; the line total is
#+ derived afterwards by recomputeTotals.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION loadOrderLines() RETURNS ()
   VAR rec tLineView
   CALL lineList.clear()
   DECLARE cursLines CURSOR FOR
      SELECT salesorderdetail.productid, salesorderdetail.specialofferid,
            salesorderdetail.orderqty, salesorderdetail.unitprice,
            salesorderdetail.unitpricediscount
         FROM salesorderdetail
         WHERE salesorderdetail.salesorderid = currentOrderId
         ORDER BY salesorderdetail.salesorderdetailid
   FOREACH cursLines INTO rec.productId, rec.specialOfferId, rec.orderQty,
         rec.unitPrice, rec.unitPriceDiscount
      LET lineList[lineList.getLength() + 1] = rec
   END FOREACH
END FUNCTION

#-------------------------------------------------------------------------------
#+ The master-detail dialog: header INPUT + editable line-item grid.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION runOrderDialog() RETURNS ()
   LET int_flag = FALSE
   DIALOG ATTRIBUTES(UNBUFFERED)

      INPUT BY NAME orderHeader.* ATTRIBUTES(WITHOUT DEFAULTS)
      END INPUT

      INPUT ARRAY lineList FROM srLines.*
         ATTRIBUTES(WITHOUT DEFAULTS, APPEND ROW = TRUE, DELETE ROW = TRUE, INSERT ROW = FALSE)

         AFTER INSERT
            LET lineList[arr_curr()].specialOfferId = SalesOrdersModel.cNoDiscountOffer
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
         IF saveCurrentOrder() THEN
            MESSAGE "Order saved."
            EXIT DIALOG
         END IF

      ON ACTION cancel
         EXIT DIALOG

   END DIALOG
END FUNCTION

#-------------------------------------------------------------------------------
#+ List price for a product, or NULL if the product is unknown. A read for the screen
#+ default of a line, so it is the controller's.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION listPrice(productId INTEGER) RETURNS DECIMAL(20,4)
   VAR price DECIMAL(20,4)
   LET price = NULL
   SELECT product.listprice INTO price FROM product WHERE product.productid = productId
   RETURN price
END FUNCTION

#-------------------------------------------------------------------------------
#+ Default a line's unit price from the chosen product's list price.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION setLinePrice(rowIndex INTEGER) RETURNS ()
   VAR price DECIMAL(20,4)
   IF lineList[rowIndex].productId IS NULL THEN
      RETURN
   END IF
   LET price = listPrice(lineList[rowIndex].productId)
   IF price IS NOT NULL THEN
      LET lineList[rowIndex].unitPrice = price
   END IF
   # Reflect a valid offer for the chosen product (keeps the display honest; the model
   # enforces the same rule at save time).
   LET lineList[rowIndex].specialOfferId =
      SalesOrdersModel.resolveOffer(lineList[rowIndex].productId, lineList[rowIndex].specialOfferId)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Recompute every line total, the subtotal and the total due, and reflect the
#+ header totals on screen. The arithmetic lives in SalesOrdersModel (tested).
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
      LET lineList[i].lineTotal = SalesOrdersModel.lineTotal(lineList[i].orderQty,
         lineList[i].unitPrice, lineList[i].unitPriceDiscount)
      LET runningTotal = runningTotal + lineList[i].lineTotal
   END FOR
   LET orderHeader.subtotal = runningTotal
   LET orderHeader.totalDue = SalesOrdersModel.orderTotal(orderHeader.subtotal,
      orderHeader.taxAmt, orderHeader.freight)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Convert the screen to database records, have the model validate the lines, then
#+ save the header and the lines in one transaction. Shows the model's message when it
#+ refuses. Returns TRUE if the order was saved.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION saveCurrentOrder() RETURNS BOOLEAN
   VAR dbHeader SalesOrdersModel.tOrderHeader
   VAR dbLines DYNAMIC ARRAY OF SalesOrdersModel.tOrderLine
   VAR valid BOOLEAN
   VAR messageText STRING
   LET dbHeader = toDbOrderHeader(orderHeader, currentOrderId)
   CALL toDbOrderLines(lineList, currentOrderId, dbLines)
   CALL SalesOrdersModel.validateOrderLines(dbLines) RETURNING valid, messageText
   IF NOT valid THEN
      ERROR messageText
      RETURN FALSE
   END IF
   CALL SalesOrdersModel.saveOrder(dbHeader, dbLines) RETURNING valid, messageText
   IF NOT valid THEN
      ERROR messageText
      RETURN FALSE
   END IF
   RETURN TRUE
END FUNCTION

################################################################################
# New order
################################################################################

#-------------------------------------------------------------------------------
#+ Ask for a customer and have the model create a new (empty) order for it. Returns
#+ the new sales order id, or 0 if the user cancelled or the order could not be created.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION newOrder() RETURNS INTEGER
   VAR customerId INTEGER
   VAR created BOOLEAN
   VAR messageText STRING
   VAR newOrderId INTEGER
   LET customerId = NULL
   OPEN WINDOW wNewOrder WITH FORM "NewOrder"
      ATTRIBUTES(TEXT = "New order", STYLE = "dialog")
   LET int_flag = FALSE
   INPUT customerId FROM customerId
   CLOSE WINDOW wNewOrder
   IF int_flag THEN
      RETURN 0
   END IF
   IF customerId IS NULL THEN
      RETURN 0
   END IF
   CALL SalesOrdersModel.createOrder(customerId) RETURNING created, messageText, newOrderId
   IF NOT created THEN
      ERROR messageText
      RETURN 0
   END IF
   RETURN newOrderId
END FUNCTION
