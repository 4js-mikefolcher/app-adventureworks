################################################################################
# aw_repo.4gl - Sales-domain data-access helpers (the "repository" layer).
#
# Read-only lookups that encapsulate non-trivial query logic so it can be reused
# and unit-tested (with a live test database) independently of the UI dialogs.
# A connection to the AdventureWorks database must be open before calling these.
################################################################################

#-------------------------------------------------------------------------------
#+ Return a special-offer id that is valid for the product (satisfies the
#+ salesorderdetail composite FK into specialofferproduct). Prefers the supplied
#+ offer if it is valid for the product, otherwise the lowest offer registered
#+ for the product (No Discount = 1 when present). Returns NULL if the product
#+ is not for sale at all.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION repo_resolve_offer(p_prod INTEGER, p_offer INTEGER) RETURNS INTEGER
    DEFINE l_cnt INTEGER
    DEFINE l_offer INTEGER
    IF p_prod IS NULL THEN RETURN NULL END IF
    IF p_offer IS NOT NULL THEN
        SELECT COUNT(*) INTO l_cnt FROM specialofferproduct
         WHERE specialofferid = p_offer AND productid = p_prod
        IF l_cnt > 0 THEN RETURN p_offer END IF
    END IF
    LET l_offer = NULL
    SELECT MIN(specialofferid) INTO l_offer FROM specialofferproduct WHERE productid = p_prod
    RETURN l_offer
END FUNCTION

#-------------------------------------------------------------------------------
#+ List price for a product, or NULL if the product is unknown.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION repo_product_list_price(p_prod INTEGER) RETURNS DECIMAL(20,4)
    DEFINE l_price DECIMAL(20,4)
    IF p_prod IS NULL THEN RETURN NULL END IF
    LET l_price = NULL
    SELECT listprice INTO l_price FROM product WHERE productid = p_prod
    RETURN l_price
END FUNCTION

#-------------------------------------------------------------------------------
#+ TRUE if a customer with the given id exists.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION repo_customer_exists(p_custid INTEGER) RETURNS BOOLEAN
    DEFINE l_cnt INTEGER
    IF p_custid IS NULL THEN RETURN FALSE END IF
    SELECT COUNT(*) INTO l_cnt FROM customer WHERE customerid = p_custid
    RETURN (l_cnt > 0)
END FUNCTION
