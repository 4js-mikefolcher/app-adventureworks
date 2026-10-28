################################################################################
# AwRepo.4gl - Sales-domain data-access helpers (the "repository" layer).
#
# Read-only lookups that encapsulate non-trivial query logic so it can be reused
# and unit-tested (with a live test database) independently of the UI dialogs.
# A connection to the AdventureWorks database must be open before calling these.
#
# Columns are always qualified with their table name: identifiers are
# case-insensitive, so a parameter such as productId would otherwise be mistaken
# for the column productid and compiled into the query as a host variable.
################################################################################

#-------------------------------------------------------------------------------
#+ Return a special-offer id that is valid for the product (satisfies the
#+ salesorderdetail composite FK into specialofferproduct). Prefers the supplied
#+ offer if it is valid for the product, otherwise the lowest offer registered
#+ for the product (No Discount = 1 when present). Returns NULL if the product
#+ is not for sale at all.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION repoResolveOffer(productId INTEGER, offerId INTEGER) RETURNS INTEGER
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
#+ List price for a product, or NULL if the product is unknown.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION repoProductListPrice(productId INTEGER) RETURNS DECIMAL(20,4)
   VAR price DECIMAL(20,4)
   IF productId IS NULL THEN
      RETURN NULL
   END IF
   LET price = NULL
   SELECT product.listprice INTO price FROM product WHERE product.productid = productId
   RETURN price
END FUNCTION

#-------------------------------------------------------------------------------
#+ TRUE if a customer with the given id exists.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION repoCustomerExists(customerId INTEGER) RETURNS BOOLEAN
   VAR customerCount INTEGER
   IF customerId IS NULL THEN
      RETURN FALSE
   END IF
   SELECT COUNT(*) INTO customerCount FROM customer WHERE customer.customerid = customerId
   RETURN (customerCount > 0)
END FUNCTION
