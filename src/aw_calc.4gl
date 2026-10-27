################################################################################
# aw_calc.4gl - pure derived-value calculations for the Sales domain.
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
#+   orderqty * unitprice * (1 - unitpricediscount)
#+ NULL inputs are treated as zero (matches the on-screen recompute behaviour).
#+
#+ @param p_qty   ordered quantity
#+ @param p_price unit price
#+ @param p_disc  unit price discount as a fraction (e.g. 0.10 for 10%)
#+ @return the line total
#-------------------------------------------------------------------------------
PUBLIC FUNCTION aw_line_total(p_qty INTEGER, p_price DECIMAL(20,4), p_disc DECIMAL(10,4))
       RETURNS DECIMAL(20,4)
    DEFINE l_qty INTEGER
    DEFINE l_price DECIMAL(20,4)
    DEFINE l_disc DECIMAL(10,4)
    LET l_qty = p_qty
    LET l_price = p_price
    LET l_disc = p_disc
    IF l_qty IS NULL THEN LET l_qty = 0 END IF
    IF l_price IS NULL THEN LET l_price = 0 END IF
    IF l_disc IS NULL THEN LET l_disc = 0 END IF
    RETURN (l_qty * l_price) * (1 - l_disc)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Order total due: subtotal + tax + freight. NULL inputs treated as zero.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION aw_order_total(p_subtotal DECIMAL(20,4), p_tax DECIMAL(20,4), p_freight DECIMAL(20,4))
       RETURNS DECIMAL(20,4)
    DEFINE l_sub DECIMAL(20,4)
    DEFINE l_tax DECIMAL(20,4)
    DEFINE l_freight DECIMAL(20,4)
    LET l_sub = p_subtotal
    LET l_tax = p_tax
    LET l_freight = p_freight
    IF l_sub IS NULL THEN LET l_sub = 0 END IF
    IF l_tax IS NULL THEN LET l_tax = 0 END IF
    IF l_freight IS NULL THEN LET l_freight = 0 END IF
    RETURN l_sub + l_tax + l_freight
END FUNCTION

#-------------------------------------------------------------------------------
#+ Human-readable label for a sales-order status code (salesorderheader.status).
#-------------------------------------------------------------------------------
PUBLIC FUNCTION aw_status_label(p_code INTEGER) RETURNS STRING
    CASE p_code
        WHEN 1 RETURN "In process"
        WHEN 2 RETURN "Approved"
        WHEN 3 RETURN "Backordered"
        WHEN 4 RETURN "Rejected"
        WHEN 5 RETURN "Shipped"
        WHEN 6 RETURN "Cancelled"
        OTHERWISE RETURN SFMT("Status %1", p_code)
    END CASE
END FUNCTION

#-------------------------------------------------------------------------------
#+ Derived sales order number: 'SO' || salesorderid. Returns NULL for a NULL id.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION aw_order_number(p_soid INTEGER) RETURNS STRING
    IF p_soid IS NULL THEN RETURN NULL END IF
    RETURN "SO" || p_soid
END FUNCTION

#-------------------------------------------------------------------------------
#+ TRUE when a [start, end] date range is valid: an open end (NULL) is allowed,
#+ otherwise the end must be on or after the start. A NULL start with a non-NULL
#+ end is invalid.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION aw_valid_date_range(p_start DATE, p_end DATE) RETURNS BOOLEAN
    IF p_end IS NULL THEN RETURN TRUE END IF
    IF p_start IS NULL THEN RETURN FALSE END IF
    RETURN (p_end >= p_start)
END FUNCTION
