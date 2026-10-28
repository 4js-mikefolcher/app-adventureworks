################################################################################
# SalesOrdersModel.4gl - data model for sales orders: the header (salesorderheader)
# and its line items (salesorderdetail).
#
# AdventureWorks' computed columns were dropped in the PostgreSQL port, so the
# derived values are rules of this model:
#   * line total      = orderQty * unitPrice * (1 - unitPriceDiscount)
#   * total due       = subtotal + taxAmt + freight
#   * sales order no. = 'SO' || salesorderid
#   * status label    = the text for a status code
#
# Owns the two database records, the business-rule validation, the data changes with
# their transactions, and the SELECTs that serve them (offer resolution, customer
# existence, the defaults of a new order). Line items are persisted with a delete-all
# plus insert-all strategy inside one transaction (salesorderdetail is a leaf table,
# so this is safe and avoids per-row diff tracking). No UI: results go back to the
# controller as return values.
#
# Static SQL always qualifies columns with their table name; identifiers are
# case-insensitive, so an unqualified column such as status or customerid would be
# compiled as a host variable whenever a variable of that name exists.
################################################################################

IMPORT security

IMPORT FGL SqlHelper

SCHEMA adventureworks

#+ specialofferid 1 is the standard "No Discount" offer in AdventureWorks.
PUBLIC CONSTANT cNoDiscountOffer = 1

#+ The highest order status code (1 In process ... 6 Cancelled).
PUBLIC CONSTANT cLastStatus = 6

#+ The database record of an order header: one row of salesorderheader.
PUBLIC TYPE tOrderHeader RECORD LIKE salesorderheader.*

#+ The database record of a line item: one row of salesorderdetail.
PUBLIC TYPE tOrderLine RECORD LIKE salesorderdetail.*

################################################################################
# Derived-value rules (pure: no database, no UI)
################################################################################

#-------------------------------------------------------------------------------
#+ Extended line total for an order line:
#+   orderQty * unitPrice * (1 - unitPriceDiscount)
#+ NULL inputs are treated as zero (matches the on-screen recompute behaviour).
#+
#+ @param orderQty          ordered quantity
#+ @param unitPrice         unit price
#+ @param unitPriceDiscount unit price discount as a fraction (e.g. 0.10 for 10%)
#+ @return the line total
#-------------------------------------------------------------------------------
PUBLIC FUNCTION lineTotal(orderQty INTEGER, unitPrice DECIMAL(20,4),
      unitPriceDiscount DECIMAL(10,4)) RETURNS DECIMAL(20,4)
   VAR qty INTEGER = orderQty
   VAR price DECIMAL(20,4) = unitPrice
   VAR discount DECIMAL(10,4) = unitPriceDiscount
   IF qty IS NULL THEN
      LET qty = 0
   END IF
   IF price IS NULL THEN
      LET price = 0
   END IF
   IF discount IS NULL THEN
      LET discount = 0
   END IF
   RETURN (qty * price) * (1 - discount)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Order total due: subtotal + tax + freight. NULL inputs treated as zero.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION orderTotal(subtotal DECIMAL(20,4), taxAmt DECIMAL(20,4),
      freight DECIMAL(20,4)) RETURNS DECIMAL(20,4)
   VAR sub DECIMAL(20,4) = subtotal
   VAR tax DECIMAL(20,4) = taxAmt
   VAR shipping DECIMAL(20,4) = freight
   IF sub IS NULL THEN
      LET sub = 0
   END IF
   IF tax IS NULL THEN
      LET tax = 0
   END IF
   IF shipping IS NULL THEN
      LET shipping = 0
   END IF
   RETURN sub + tax + shipping
END FUNCTION

#-------------------------------------------------------------------------------
#+ Human-readable label for a sales-order status code (salesorderheader.status).
#-------------------------------------------------------------------------------
PUBLIC FUNCTION statusLabel(statusCode INTEGER) RETURNS STRING
   CASE statusCode
      WHEN 1
         RETURN "In process"
      WHEN 2
         RETURN "Approved"
      WHEN 3
         RETURN "Backordered"
      WHEN 4
         RETURN "Rejected"
      WHEN 5
         RETURN "Shipped"
      WHEN 6
         RETURN "Cancelled"
      OTHERWISE
         RETURN SFMT("Status %1", statusCode)
   END CASE
END FUNCTION

#-------------------------------------------------------------------------------
#+ Derived sales order number: 'SO' || salesorderid. Returns NULL for a NULL id.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION orderNumber(orderId INTEGER) RETURNS STRING
   IF orderId IS NULL THEN
      RETURN NULL
   END IF
   RETURN "SO" || orderId
END FUNCTION

################################################################################
# Validation
################################################################################

#-------------------------------------------------------------------------------
#+ Validate the line items before saving: at least one line, and on each a product,
#+ a quantity above zero and a price that is not negative.
#+
#+ @param lines the line items to check
#+ @return TRUE, or FALSE with the message for the user
#-------------------------------------------------------------------------------
PUBLIC FUNCTION validateOrderLines(lines DYNAMIC ARRAY OF tOrderLine) RETURNS (BOOLEAN, STRING)
   VAR i INTEGER
   IF lines.getLength() = 0 THEN
      RETURN FALSE, "An order must have at least one line item."
   END IF
   FOR i = 1 TO lines.getLength()
      IF lines[i].productid IS NULL THEN
         RETURN FALSE, SFMT("Line %1: a product is required.", i)
      END IF
      IF lines[i].orderqty IS NULL OR lines[i].orderqty <= 0 THEN
         RETURN FALSE, SFMT("Line %1: quantity must be greater than zero.", i)
      END IF
      IF lines[i].unitprice IS NULL OR lines[i].unitprice < 0 THEN
         RETURN FALSE, SFMT("Line %1: unit price must not be negative.", i)
      END IF
   END FOR
   RETURN TRUE, NULL
END FUNCTION

################################################################################
# Reads that serve a write or a validation
################################################################################

#-------------------------------------------------------------------------------
#+ Return a special-offer id that is valid for the product (satisfies the
#+ salesorderdetail composite FK into specialofferproduct). Prefers the supplied
#+ offer if it is valid for the product, otherwise the lowest offer registered
#+ for the product (No Discount = 1 when present). Returns NULL if the product
#+ is not for sale at all. The save uses it, and so does the screen, to keep the
#+ displayed offer honest.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION resolveOffer(productId INTEGER, offerId INTEGER) RETURNS INTEGER
   VAR pairCount INTEGER
   VAR lowestOffer INTEGER
   IF productId IS NULL THEN
      RETURN NULL
   END IF
   IF offerId IS NOT NULL THEN
      SELECT COUNT(*) INTO pairCount FROM specialofferproduct
         WHERE specialofferproduct.specialofferid = offerId
            AND specialofferproduct.productid = productId
      IF pairCount > 0 THEN
         RETURN offerId
      END IF
   END IF
   LET lowestOffer = NULL
   SELECT MIN(specialofferproduct.specialofferid) INTO lowestOffer FROM specialofferproduct
      WHERE specialofferproduct.productid = productId
   RETURN lowestOffer
END FUNCTION

#-------------------------------------------------------------------------------
#+ TRUE if a customer with the given id exists.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION customerExists(customerId INTEGER) RETURNS BOOLEAN
   VAR customerCount INTEGER
   IF customerId IS NULL THEN
      RETURN FALSE
   END IF
   SELECT COUNT(*) INTO customerCount FROM customer WHERE customer.customerid = customerId
   RETURN (customerCount > 0)
END FUNCTION

################################################################################
# Data changes
################################################################################

#-------------------------------------------------------------------------------
#+ Persist header changes and rewrite the line items in one transaction. The header
#+ UPDATE names the columns the editor owns (status, ship date, salesperson,
#+ territory, comment, subtotal), so the rest of the record is never written. Each
#+ line's (specialofferid, productid) pair is resolved to one that satisfies the
#+ composite FK; a product that is not for sale rolls the whole save back.
#+
#+ @param header the order header, identified by its sales order id
#+ @param lines  the line items, which replace the stored ones
#+ @return TRUE, or FALSE with the message for the user
#-------------------------------------------------------------------------------
PUBLIC FUNCTION saveOrder(header tOrderHeader, lines DYNAMIC ARRAY OF tOrderLine)
      RETURNS (BOOLEAN, STRING)
   VAR i INTEGER
   VAR resolvedOffer INTEGER
   VAR sqlText STRING
   VAR messageText STRING
   VAR modifiedAt DATETIME YEAR TO SECOND = CURRENT YEAR TO SECOND
   VAR rowGuid VARCHAR(36)
   LET sqlText =
      "INSERT INTO salesorderdetail"
      || " (salesorderid, orderqty, productid, specialofferid, unitprice,"
      || "  unitpricediscount, rowguid, modifieddate)"
      || " VALUES (?,?,?,?,?,?,?,?)"
   BEGIN WORK
   TRY
      UPDATE salesorderheader
         SET status = header.status, shipdate = header.shipdate,
            salespersonid = header.salespersonid, territoryid = header.territoryid,
            comment = header.comment, subtotal = header.subtotal,
            modifieddate = modifiedAt
         WHERE salesorderheader.salesorderid = header.salesorderid

      DELETE FROM salesorderdetail WHERE salesorderdetail.salesorderid = header.salesorderid

      PREPARE stmtDetailInsert FROM sqlText
      FOR i = 1 TO lines.getLength()
         # Ensure the (specialofferid, productid) pair satisfies the composite FK
         # into specialofferproduct; fall back to a valid offer for the product.
         LET resolvedOffer = resolveOffer(lines[i].productid, lines[i].specialofferid)
         IF resolvedOffer IS NULL THEN
            ROLLBACK WORK
            RETURN FALSE, SFMT("Line %1: that product is not available for sale.", i)
         END IF
         LET rowGuid = security.RandomGenerator.CreateUUIDString()
         EXECUTE stmtDetailInsert USING header.salesorderid, lines[i].orderqty,
               lines[i].productid, resolvedOffer, lines[i].unitprice,
               lines[i].unitpricediscount, rowGuid, modifiedAt
      END FOR

      COMMIT WORK
   CATCH
      LET messageText = SqlHelper.errorText("Saving order")
      ROLLBACK WORK
      RETURN FALSE, messageText
   END TRY
   RETURN TRUE, NULL
END FUNCTION

#-------------------------------------------------------------------------------
#+ Create a new (empty) order for a customer, deriving the required FK values (bill
#+ and ship address, ship method) from the customer. The reads that derive them serve
#+ this write, so they live here.
#+
#+ @param customerId the customer to create the order for
#+ @return TRUE and the new sales order id, or FALSE with the message for the user
#-------------------------------------------------------------------------------
PUBLIC FUNCTION createOrder(customerId INTEGER) RETURNS (BOOLEAN, STRING, INTEGER)
   VAR entityId INTEGER
   VAR addressId INTEGER
   VAR shipMethodId INTEGER
   VAR newOrderId INTEGER
   VAR sqlText STRING
   VAR messageText STRING
   VAR rowGuid VARCHAR(36)
   VAR orderedOn DATE = TODAY
   VAR dueOn DATE = TODAY + 7
   VAR modifiedAt DATETIME YEAR TO SECOND = CURRENT YEAR TO SECOND

   IF NOT customerExists(customerId) THEN
      RETURN FALSE, SFMT("No customer with id %1.", customerId), NULL
   END IF
   SELECT COALESCE(customer.personid, customer.storeid) INTO entityId
      FROM customer WHERE customer.customerid = customerId
   IF entityId IS NULL THEN
      RETURN FALSE, "This customer is not linked to a person or store; cannot derive an address.",
         NULL
   END IF
   SELECT MIN(businessentityaddress.addressid) INTO addressId
      FROM businessentityaddress WHERE businessentityaddress.businessentityid = entityId
   IF addressId IS NULL THEN
      RETURN FALSE, "This customer has no address on file; cannot create an order.", NULL
   END IF
   SELECT MIN(shipmethod.shipmethodid) INTO shipMethodId FROM shipmethod
   IF shipMethodId IS NULL THEN
      RETURN FALSE, "No shipping methods are defined.", NULL
   END IF

   LET sqlText =
      "INSERT INTO salesorderheader"
      || " (revisionnumber, orderdate, duedate, status, onlineorderflag,"
      || "  customerid, billtoaddressid, shiptoaddressid, shipmethodid,"
      || "  subtotal, taxamt, freight, rowguid, modifieddate)"
      || " VALUES (1, ?, ?, 1, FALSE, ?, ?, ?, ?, 0, 0, 0, ?, ?)"
   BEGIN WORK
   TRY
      LET rowGuid = security.RandomGenerator.CreateUUIDString()
      PREPARE stmtOrderInsert FROM sqlText
      EXECUTE stmtOrderInsert USING orderedOn, dueOn, customerId, addressId, addressId,
            shipMethodId, rowGuid, modifiedAt
      LET newOrderId = sqlca.sqlerrd[2]
      COMMIT WORK
   CATCH
      LET messageText = SqlHelper.errorText("Creating order")
      ROLLBACK WORK
      RETURN FALSE, messageText, NULL
   END TRY
   RETURN TRUE, NULL, newOrderId
END FUNCTION
