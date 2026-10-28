################################################################################
# AwCalc.4gl - pure derived-value calculations for the Sales domain.
#
# AdventureWorks' computed columns were dropped in the PostgreSQL port, so these
# derived values are computed in the application. This module isolates that pure
# logic (no UI, no database) so it is reusable across the domain modules and
# unit-testable with fglunit.
#
# All functions are deterministic and side-effect free.
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
PUBLIC FUNCTION awLineTotal(orderQty INTEGER, unitPrice DECIMAL(20,4),
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
PUBLIC FUNCTION awOrderTotal(subtotal DECIMAL(20,4), taxAmt DECIMAL(20,4),
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
PUBLIC FUNCTION awStatusLabel(statusCode INTEGER) RETURNS STRING
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
PUBLIC FUNCTION awOrderNumber(orderId INTEGER) RETURNS STRING
   IF orderId IS NULL THEN
      RETURN NULL
   END IF
   RETURN "SO" || orderId
END FUNCTION

#-------------------------------------------------------------------------------
#+ TRUE when a [start, end] date range is valid: an open end (NULL) is allowed,
#+ otherwise the end must be on or after the start. A NULL start with a non-NULL
#+ end is invalid.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION awValidDateRange(startDate DATE, endDate DATE) RETURNS BOOLEAN
   IF endDate IS NULL THEN
      RETURN TRUE
   END IF
   IF startDate IS NULL THEN
      RETURN FALSE
   END IF
   RETURN (endDate >= startDate)
END FUNCTION
