################################################################################
# TestSalesOrders.4gl - fglunit suite for the sales-orders feature that needs no
# database: the derived-value rules, the line validation (both in SalesOrdersModel)
# and the view-to-database conversions in SalesOrdersController (the JSON bridge,
# standards rule 13).
#
# The bridge fails silently: a member that does not match, or a DATE going into a
# DATETIME, becomes NULL without an error. So every member that crosses is populated
# and asserted not NULL.
#
# Build & run (see the top-level Makefile 'test' target):
#   fglcomp -M -Wall -Werror -o bin tests/TestSalesOrders.4gl
#   fglrun bin/TestSalesOrders.42m
################################################################################

IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL com.fourjs.fglunit.CliArgs
IMPORT FGL SalesOrdersController
IMPORT FGL SalesOrdersModel

MAIN
   CALL CliArgs.parse()    -- enable --junit / --filter / -v / --fail-fast
   CALL FglUnit.suite("SalesOrders")

   CALL FglUnit.register("testLineTotalBasic",       FUNCTION testLineTotalBasic)
   CALL FglUnit.register("testLineTotalDiscount",    FUNCTION testLineTotalDiscount)
   CALL FglUnit.register("testLineTotalZeroQty",     FUNCTION testLineTotalZeroQty)
   CALL FglUnit.register("testLineTotalNulls",       FUNCTION testLineTotalNulls)

   CALL FglUnit.register("testOrderTotalBasic",      FUNCTION testOrderTotalBasic)
   CALL FglUnit.register("testOrderTotalNulls",      FUNCTION testOrderTotalNulls)

   CALL FglUnit.register("testStatusLabelKnown",     FUNCTION testStatusLabelKnown)
   CALL FglUnit.register("testStatusLabelBounds",    FUNCTION testStatusLabelBounds)
   CALL FglUnit.register("testStatusLabelUnknown",   FUNCTION testStatusLabelUnknown)

   CALL FglUnit.register("testOrderNumber",          FUNCTION testOrderNumber)
   CALL FglUnit.register("testOrderNumberNull",      FUNCTION testOrderNumberNull)

   CALL FglUnit.register("testValidateGoodLines",    FUNCTION testValidateGoodLines)
   CALL FglUnit.register("testValidateNoLines",      FUNCTION testValidateNoLines)
   CALL FglUnit.register("testValidateMissingProduct", FUNCTION testValidateMissingProduct)
   CALL FglUnit.register("testValidateZeroQuantity", FUNCTION testValidateZeroQuantity)
   CALL FglUnit.register("testValidateNullQuantity", FUNCTION testValidateNullQuantity)
   CALL FglUnit.register("testValidateNegativePrice", FUNCTION testValidateNegativePrice)
   CALL FglUnit.register("testValidateNullPrice",    FUNCTION testValidateNullPrice)
   CALL FglUnit.register("testValidateZeroPriceIsFine", FUNCTION testValidateZeroPriceIsFine)

   CALL FglUnit.register("testToDbOrderHeaderCrossesEveryMember",
      FUNCTION testToDbOrderHeaderCrossesEveryMember)
   CALL FglUnit.register("testToDbOrderHeaderMapsStatus", FUNCTION testToDbOrderHeaderMapsStatus)
   CALL FglUnit.register("testToDbOrderHeaderDatesBecomeDatetimes",
      FUNCTION testToDbOrderHeaderDatesBecomeDatetimes)
   CALL FglUnit.register("testToDbOrderHeaderKeepsNullSalesPerson",
      FUNCTION testToDbOrderHeaderKeepsNullSalesPerson)
   CALL FglUnit.register("testToDbOrderHeaderNullsOtherColumns",
      FUNCTION testToDbOrderHeaderNullsOtherColumns)
   CALL FglUnit.register("testToDbOrderLineCrossesEveryMember",
      FUNCTION testToDbOrderLineCrossesEveryMember)
   CALL FglUnit.register("testToDbOrderLinesKeepsOrder", FUNCTION testToDbOrderLinesKeepsOrder)

   EXIT PROGRAM FglUnit.run()
END MAIN

#--- fixtures ------------------------------------------------------------------

#+ A header view record with every member populated.
PRIVATE FUNCTION fullHeaderView() RETURNS SalesOrdersController.tHeaderView
   VAR viewRec SalesOrdersController.tHeaderView
   LET viewRec.salesOrderNumber = "SO43659"
   LET viewRec.orderDate = MDY(7, 1, 2024)
   LET viewRec.customerName = "Zheng, Jon"
   LET viewRec.statusCode = 5
   LET viewRec.shipDate = MDY(7, 8, 2024)
   LET viewRec.salesPersonId = 279
   LET viewRec.territoryId = 5
   LET viewRec.comment = "Rush delivery"
   LET viewRec.subtotal = 1000.00
   LET viewRec.taxAmt = 80.00
   LET viewRec.freight = 25.00
   LET viewRec.totalDue = 1105.00
   RETURN viewRec
END FUNCTION

#+ A line view record with every member populated.
PRIVATE FUNCTION fullLineView() RETURNS SalesOrdersController.tLineView
   VAR viewRec SalesOrdersController.tLineView
   LET viewRec.productId = 707
   LET viewRec.specialOfferId = 2
   LET viewRec.orderQty = 3
   LET viewRec.unitPrice = 34.99
   LET viewRec.unitPriceDiscount = 0.05
   LET viewRec.lineTotal = 99.72
   RETURN viewRec
END FUNCTION

#+ Fill the array with one line that passes validation; the tests then spoil one value.
#+ (An array is filled in place, not returned: see the note on toDbOrderLines.)
PRIVATE FUNCTION fillGoodLines(lines DYNAMIC ARRAY OF SalesOrdersModel.tOrderLine) RETURNS ()
   CALL lines.clear()
   LET lines[1].productid = 707
   LET lines[1].orderqty = 2
   LET lines[1].unitprice = 10.00
END FUNCTION

#+ TRUE when the model accepts the lines.
PRIVATE FUNCTION linesValid(lines DYNAMIC ARRAY OF SalesOrdersModel.tOrderLine) RETURNS BOOLEAN
   VAR valid BOOLEAN
   VAR messageText STRING
   CALL SalesOrdersModel.validateOrderLines(lines) RETURNING valid, messageText
   RETURN valid
END FUNCTION

#--- lineTotal -----------------------------------------------------------------

PUBLIC FUNCTION testLineTotalBasic() RETURNS ()
   # 2 * 10.00 * (1 - 0) = 20.00
   CALL Assertions.assertEqualsDec(20.0, SalesOrdersModel.lineTotal(2, 10.00, 0), 0.0001,
      "2 @ 10.00, no discount")
END FUNCTION

PUBLIC FUNCTION testLineTotalDiscount() RETURNS ()
   # 3 * 100.00 * (1 - 0.10) = 270.00
   CALL Assertions.assertEqualsDec(270.0, SalesOrdersModel.lineTotal(3, 100.00, 0.10), 0.0001,
      "3 @ 100.00, 10% discount")
END FUNCTION

PUBLIC FUNCTION testLineTotalZeroQty() RETURNS ()
   CALL Assertions.assertEqualsDec(0.0, SalesOrdersModel.lineTotal(0, 99.99, 0.25), 0.0001,
      "zero quantity gives zero total")
END FUNCTION

PUBLIC FUNCTION testLineTotalNulls() RETURNS ()
   CALL Assertions.assertEqualsDec(0.0, SalesOrdersModel.lineTotal(NULL, NULL, NULL), 0.0001,
      "NULL inputs are treated as zero")
END FUNCTION

#--- orderTotal ----------------------------------------------------------------

PUBLIC FUNCTION testOrderTotalBasic() RETURNS ()
   # 100.00 + 8.00 + 5.00 = 113.00
   CALL Assertions.assertEqualsDec(113.0, SalesOrdersModel.orderTotal(100.00, 8.00, 5.00), 0.0001,
      "subtotal + tax + freight")
END FUNCTION

PUBLIC FUNCTION testOrderTotalNulls() RETURNS ()
   CALL Assertions.assertEqualsDec(50.0, SalesOrdersModel.orderTotal(50.00, NULL, NULL), 0.0001,
      "NULL tax/freight treated as zero")
END FUNCTION

#--- statusLabel ---------------------------------------------------------------

PUBLIC FUNCTION testStatusLabelKnown() RETURNS ()
   CALL Assertions.assertEquals("In process", SalesOrdersModel.statusLabel(1), "status 1")
   CALL Assertions.assertEquals("Shipped",    SalesOrdersModel.statusLabel(5), "status 5")
END FUNCTION

PUBLIC FUNCTION testStatusLabelBounds() RETURNS ()
   CALL Assertions.assertEquals("Approved",  SalesOrdersModel.statusLabel(2), "status 2")
   CALL Assertions.assertEquals("Cancelled", SalesOrdersModel.statusLabel(SalesOrdersModel.cLastStatus),
      "the last status code")
END FUNCTION

PUBLIC FUNCTION testStatusLabelUnknown() RETURNS ()
   # Unknown codes fall through to a "Status N" label.
   CALL Assertions.assertContains(SalesOrdersModel.statusLabel(99), "99",
      "unknown status code echoes the number")
END FUNCTION

#--- orderNumber ---------------------------------------------------------------

PUBLIC FUNCTION testOrderNumber() RETURNS ()
   CALL Assertions.assertEquals("SO43659", SalesOrdersModel.orderNumber(43659), "order number format")
END FUNCTION

PUBLIC FUNCTION testOrderNumberNull() RETURNS ()
   CALL Assertions.assertNull(SalesOrdersModel.orderNumber(NULL), "NULL id gives NULL order number")
END FUNCTION

#--- validateOrderLines --------------------------------------------------------

PUBLIC FUNCTION testValidateGoodLines() RETURNS ()
   VAR lines DYNAMIC ARRAY OF SalesOrdersModel.tOrderLine
   CALL fillGoodLines(lines)
   CALL Assertions.assertTrue(linesValid(lines), "a complete line is valid")
END FUNCTION

PUBLIC FUNCTION testValidateNoLines() RETURNS ()
   VAR lines DYNAMIC ARRAY OF SalesOrdersModel.tOrderLine
   VAR valid BOOLEAN
   VAR messageText STRING
   CALL SalesOrdersModel.validateOrderLines(lines) RETURNING valid, messageText
   CALL Assertions.assertFalse(valid, "an order needs at least one line")
   CALL Assertions.assertContains(messageText, "at least one line", "the message says why")
END FUNCTION

PUBLIC FUNCTION testValidateMissingProduct() RETURNS ()
   VAR lines DYNAMIC ARRAY OF SalesOrdersModel.tOrderLine
   VAR valid BOOLEAN
   VAR messageText STRING
   CALL fillGoodLines(lines)
   LET lines[1].productid = NULL
   CALL SalesOrdersModel.validateOrderLines(lines) RETURNING valid, messageText
   CALL Assertions.assertFalse(valid, "a line needs a product")
   CALL Assertions.assertContains(messageText, "Line 1", "the message names the line")
END FUNCTION

PUBLIC FUNCTION testValidateZeroQuantity() RETURNS ()
   VAR lines DYNAMIC ARRAY OF SalesOrdersModel.tOrderLine
   CALL fillGoodLines(lines)
   LET lines[1].orderqty = 0
   CALL Assertions.assertFalse(linesValid(lines), "a zero quantity is invalid")
END FUNCTION

PUBLIC FUNCTION testValidateNullQuantity() RETURNS ()
   VAR lines DYNAMIC ARRAY OF SalesOrdersModel.tOrderLine
   CALL fillGoodLines(lines)
   LET lines[1].orderqty = NULL
   CALL Assertions.assertFalse(linesValid(lines), "a NULL quantity is invalid")
END FUNCTION

PUBLIC FUNCTION testValidateNegativePrice() RETURNS ()
   VAR lines DYNAMIC ARRAY OF SalesOrdersModel.tOrderLine
   CALL fillGoodLines(lines)
   LET lines[1].unitprice = -0.01
   CALL Assertions.assertFalse(linesValid(lines), "a negative price is invalid")
END FUNCTION

PUBLIC FUNCTION testValidateNullPrice() RETURNS ()
   VAR lines DYNAMIC ARRAY OF SalesOrdersModel.tOrderLine
   CALL fillGoodLines(lines)
   LET lines[1].unitprice = NULL
   CALL Assertions.assertFalse(linesValid(lines), "a NULL price is invalid")
END FUNCTION

PUBLIC FUNCTION testValidateZeroPriceIsFine() RETURNS ()
   VAR lines DYNAMIC ARRAY OF SalesOrdersModel.tOrderLine
   CALL fillGoodLines(lines)
   LET lines[1].unitprice = 0
   CALL Assertions.assertTrue(linesValid(lines), "a zero price is not negative")
END FUNCTION

#--- toDbOrderHeader -----------------------------------------------------------

PUBLIC FUNCTION testToDbOrderHeaderCrossesEveryMember() RETURNS ()
   VAR dbRec SalesOrdersModel.tOrderHeader
   LET dbRec = SalesOrdersController.toDbOrderHeader(fullHeaderView(), 43659)
   CALL Assertions.assertNotNull(dbRec.salesorderid, "the order id is added")
   CALL Assertions.assertNotNull(dbRec.status, "statusCode crosses")
   CALL Assertions.assertNotNull(dbRec.salespersonid, "salesPersonId crosses")
   CALL Assertions.assertNotNull(dbRec.territoryid, "territoryId crosses")
   CALL Assertions.assertNotNull(dbRec.comment, "comment crosses")
   CALL Assertions.assertNotNull(dbRec.subtotal, "subtotal crosses")
   CALL Assertions.assertNotNull(dbRec.taxamt, "taxAmt crosses")
   CALL Assertions.assertNotNull(dbRec.freight, "freight crosses")
   CALL Assertions.assertEqualsInt(43659, dbRec.salesorderid, "order id value")
   CALL Assertions.assertEqualsInt(5, dbRec.status, "status value")
   CALL Assertions.assertEqualsInt(279, dbRec.salespersonid, "salesPersonId value")
   CALL Assertions.assertEqualsInt(5, dbRec.territoryid, "territoryId value")
   CALL Assertions.assertEquals("Rush delivery", dbRec.comment, "comment value")
   CALL Assertions.assertEqualsDec(1000.00, dbRec.subtotal, 0.0001, "subtotal value")
   CALL Assertions.assertEqualsDec(80.00, dbRec.taxamt, 0.0001, "taxAmt value")
   CALL Assertions.assertEqualsDec(25.00, dbRec.freight, 0.0001, "freight value")
END FUNCTION

PUBLIC FUNCTION testToDbOrderHeaderMapsStatus() RETURNS ()
   # The view member statusCode fills the column "status" through its json_name.
   VAR dbRec SalesOrdersModel.tOrderHeader
   LET dbRec = SalesOrdersController.toDbOrderHeader(fullHeaderView(), 43659)
   CALL Assertions.assertNotNull(dbRec.status, "statusCode fills the status column")
   CALL Assertions.assertEqualsInt(5, dbRec.status, "status value")
END FUNCTION

PUBLIC FUNCTION testToDbOrderHeaderDatesBecomeDatetimes() RETURNS ()
   # The bridge turns DATE into DATETIME as NULL, so the conversion assigns the dates itself.
   VAR dbRec SalesOrdersModel.tOrderHeader
   VAR expectedOrder DATETIME YEAR TO SECOND = MDY(7, 1, 2024)
   VAR expectedShip DATETIME YEAR TO SECOND = MDY(7, 8, 2024)
   LET dbRec = SalesOrdersController.toDbOrderHeader(fullHeaderView(), 43659)
   # A NULL date would make the comparisons below NULL, which assertTrue does not fail on.
   CALL Assertions.assertNotNull(dbRec.orderdate, "orderDate is not lost in the conversion")
   CALL Assertions.assertNotNull(dbRec.shipdate, "shipDate is not lost in the conversion")
   CALL Assertions.assertTrue(dbRec.orderdate = expectedOrder, "orderDate becomes midnight of the day")
   CALL Assertions.assertTrue(dbRec.shipdate = expectedShip, "shipDate becomes midnight of the day")
END FUNCTION

PUBLIC FUNCTION testToDbOrderHeaderKeepsNullSalesPerson() RETURNS ()
   # Salesperson, territory and ship date are optional on an order; NULL must stay NULL.
   VAR viewRec SalesOrdersController.tHeaderView
   VAR dbRec SalesOrdersModel.tOrderHeader
   LET viewRec = fullHeaderView()
   LET viewRec.salesPersonId = NULL
   LET viewRec.territoryId = NULL
   LET viewRec.shipDate = NULL
   LET dbRec = SalesOrdersController.toDbOrderHeader(viewRec, 43659)
   CALL Assertions.assertNull(dbRec.salespersonid, "NULL salesPersonId stays NULL")
   CALL Assertions.assertNull(dbRec.territoryid, "NULL territoryId stays NULL")
   CALL Assertions.assertNull(dbRec.shipdate, "NULL shipDate stays NULL")
   CALL Assertions.assertNotNull(dbRec.status, "status is unaffected")
END FUNCTION

PUBLIC FUNCTION testToDbOrderHeaderNullsOtherColumns() RETURNS ()
   # The bridge replaces the whole target: columns the view does not carry are NULL, which
   # is why the model's UPDATE names the columns it writes. The order number, customer name
   # and total due are display-only and have no column.
   VAR dbRec SalesOrdersModel.tOrderHeader
   LET dbRec = SalesOrdersController.toDbOrderHeader(fullHeaderView(), 43659)
   CALL Assertions.assertNull(dbRec.customerid, "customerId is not carried by the view")
   CALL Assertions.assertNull(dbRec.billtoaddressid, "billToAddressId is not carried by the view")
   CALL Assertions.assertNull(dbRec.rowguid, "rowGuid is not carried by the view")
   CALL Assertions.assertNull(dbRec.modifieddate, "modifiedDate is not carried by the view")
END FUNCTION

#--- toDbOrderLine / toDbOrderLines --------------------------------------------

PUBLIC FUNCTION testToDbOrderLineCrossesEveryMember() RETURNS ()
   VAR dbRec SalesOrdersModel.tOrderLine
   LET dbRec = SalesOrdersController.toDbOrderLine(fullLineView(), 43659)
   CALL Assertions.assertNotNull(dbRec.salesorderid, "the order id is added")
   CALL Assertions.assertNotNull(dbRec.productid, "productId crosses")
   CALL Assertions.assertNotNull(dbRec.specialofferid, "specialOfferId crosses")
   CALL Assertions.assertNotNull(dbRec.orderqty, "orderQty crosses")
   CALL Assertions.assertNotNull(dbRec.unitprice, "unitPrice crosses")
   CALL Assertions.assertNotNull(dbRec.unitpricediscount, "unitPriceDiscount crosses")
   CALL Assertions.assertEqualsInt(43659, dbRec.salesorderid, "order id value")
   CALL Assertions.assertEqualsInt(707, dbRec.productid, "productId value")
   CALL Assertions.assertEqualsInt(2, dbRec.specialofferid, "specialOfferId value")
   CALL Assertions.assertEqualsInt(3, dbRec.orderqty, "orderQty value")
   CALL Assertions.assertEqualsDec(34.99, dbRec.unitprice, 0.0001, "unitPrice value")
   CALL Assertions.assertEqualsDec(0.05, dbRec.unitpricediscount, 0.0001, "unitPriceDiscount value")
END FUNCTION

PUBLIC FUNCTION testToDbOrderLinesKeepsOrder() RETURNS ()
   VAR viewList DYNAMIC ARRAY OF SalesOrdersController.tLineView
   VAR dbList DYNAMIC ARRAY OF SalesOrdersModel.tOrderLine
   LET viewList[1] = fullLineView()
   LET viewList[2] = fullLineView()
   LET viewList[2].productId = 708
   LET viewList[3] = fullLineView()
   LET viewList[3].productId = 709
   CALL SalesOrdersController.toDbOrderLines(viewList, 43659, dbList)
   CALL Assertions.assertEqualsInt(3, dbList.getLength(), "one database line per view line")
   CALL Assertions.assertEqualsInt(707, dbList[1].productid, "first line")
   CALL Assertions.assertEqualsInt(708, dbList[2].productid, "second line")
   CALL Assertions.assertEqualsInt(709, dbList[3].productid, "third line")
   CALL Assertions.assertEqualsInt(43659, dbList[3].salesorderid, "every line carries the order id")
END FUNCTION
