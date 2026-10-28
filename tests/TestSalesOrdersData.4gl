################################################################################
# TestSalesOrdersData.4gl - fglunit suite for the reads in SalesOrdersModel that
# serve a write or a validation: the offer resolution (the composite foreign key
# into specialofferproduct) and the customer existence check, plus the refusal of a
# new order for a customer that does not exist.
#
# These tests need the live "adventureworks" database. The suite connects once in
# setupSuite; if the connection fails (DB not running / not configured) every test
# calls skip() rather than erroring, so the suite stays green on machines without the
# database. Nothing here writes: createOrder is only called with a missing customer,
# which it refuses before touching the database.
#
# Assertions use only stable, relationship-derived facts (referential rules), never
# hard-coded names, so they are robust to the data.
################################################################################

IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL com.fourjs.fglunit.CliArgs
IMPORT FGL SalesOrdersModel

SCHEMA adventureworks

PRIVATE DEFINE connected BOOLEAN

#+ Database source name. Matches the FGLPROFILE entry in res/fglprofile.pgs.
PRIVATE CONSTANT cDbName = "adventureworks"

#+ An id that cannot exist in the sample data (used for fallback and missing-row tests).
PRIVATE CONSTANT cMissingId = 99999999

MAIN
   CALL CliArgs.parse()    -- enable --junit / --filter / -v / --fail-fast
   CALL FglUnit.suite("SalesOrdersModel reads (live database)")
   CALL FglUnit.setSetupSuite(FUNCTION setupSuite)
   CALL FglUnit.setTeardownSuite(FUNCTION teardownSuite)

   CALL FglUnit.register("testCustomerExistsTrue",      FUNCTION testCustomerExistsTrue)
   CALL FglUnit.register("testCustomerExistsFalse",     FUNCTION testCustomerExistsFalse)
   CALL FglUnit.register("testCustomerExistsNull",      FUNCTION testCustomerExistsNull)

   CALL FglUnit.register("testResolveOfferValidPair",   FUNCTION testResolveOfferValidPair)
   CALL FglUnit.register("testResolveOfferFallback",    FUNCTION testResolveOfferFallback)
   CALL FglUnit.register("testResolveOfferNotSellable", FUNCTION testResolveOfferNotSellable)

   CALL FglUnit.register("testCreateOrderRefusesMissingCustomer",
      FUNCTION testCreateOrderRefusesMissingCustomer)

   EXIT PROGRAM FglUnit.run()
END MAIN

#--- suite fixtures ------------------------------------------------------------

PUBLIC FUNCTION setupSuite() RETURNS ()
   LET connected = FALSE
   TRY
      CONNECT TO cDbName
      LET connected = TRUE
   CATCH
      LET connected = FALSE
   END TRY
END FUNCTION

PUBLIC FUNCTION teardownSuite() RETURNS ()
   IF connected THEN
      DISCONNECT CURRENT
   END IF
END FUNCTION

#+ Guard used at the top of every test; returns TRUE if the test should skip.
PRIVATE FUNCTION dbUnavailable() RETURNS BOOLEAN
   IF NOT connected THEN
      CALL Assertions.skip("adventureworks database not available")
      RETURN TRUE
   END IF
   RETURN FALSE
END FUNCTION

#--- helpers that fetch stable sample rows by relationship ---------------------

PRIVATE FUNCTION anExistingCustomer() RETURNS INTEGER
   VAR id INTEGER
   SELECT MIN(customer.customerid) INTO id FROM customer
   RETURN id
END FUNCTION

PRIVATE FUNCTION aSellableProduct() RETURNS INTEGER
   VAR id INTEGER
   SELECT MIN(specialofferproduct.productid) INTO id FROM specialofferproduct
   RETURN id
END FUNCTION

#--- SalesOrdersModel.customerExists -------------------------------------------

PUBLIC FUNCTION testCustomerExistsTrue() RETURNS ()
   IF dbUnavailable() THEN
      RETURN
   END IF
   CALL Assertions.assertTrue(SalesOrdersModel.customerExists(anExistingCustomer()),
      "existing customer reports true")
END FUNCTION

PUBLIC FUNCTION testCustomerExistsFalse() RETURNS ()
   IF dbUnavailable() THEN
      RETURN
   END IF
   CALL Assertions.assertFalse(SalesOrdersModel.customerExists(cMissingId),
      "non-existent customer reports false")
END FUNCTION

PUBLIC FUNCTION testCustomerExistsNull() RETURNS ()
   IF dbUnavailable() THEN
      RETURN
   END IF
   CALL Assertions.assertFalse(SalesOrdersModel.customerExists(NULL), "a NULL id reports false")
END FUNCTION

#--- SalesOrdersModel.resolveOffer (composite FK safety) -----------------------

PUBLIC FUNCTION testResolveOfferValidPair() RETURNS ()
   VAR prod INTEGER
   VAR offer INTEGER
   VAR resolved INTEGER
   IF dbUnavailable() THEN
      RETURN
   END IF
   LET prod = aSellableProduct()
   SELECT MIN(specialofferproduct.specialofferid) INTO offer FROM specialofferproduct
      WHERE specialofferproduct.productid = prod
   LET resolved = SalesOrdersModel.resolveOffer(prod, offer)
   CALL Assertions.assertEqualsInt(offer, resolved,
      "a valid (offer, product) pair is returned unchanged")
END FUNCTION

PUBLIC FUNCTION testResolveOfferFallback() RETURNS ()
   VAR prod INTEGER
   VAR resolved INTEGER
   VAR pairCount INTEGER
   IF dbUnavailable() THEN
      RETURN
   END IF
   LET prod = aSellableProduct()
   # cMissingId is not a valid offer for the product -> must fall back to a valid one,
   # and the resolved pair must satisfy the composite FK.
   LET resolved = SalesOrdersModel.resolveOffer(prod, cMissingId)
   CALL Assertions.assertNotNull(resolved, "fallback returns a valid offer")
   SELECT COUNT(*) INTO pairCount FROM specialofferproduct
      WHERE specialofferproduct.specialofferid = resolved
         AND specialofferproduct.productid = prod
   CALL Assertions.assertTrue(pairCount > 0,
      "resolved (offer, product) pair exists in specialofferproduct")
END FUNCTION

PUBLIC FUNCTION testResolveOfferNotSellable() RETURNS ()
   VAR prod INTEGER
   IF dbUnavailable() THEN
      RETURN
   END IF
   # A product with no specialofferproduct rows cannot be ordered -> NULL.
   LET prod = NULL
   SELECT MIN(product.productid) INTO prod FROM product
      WHERE product.productid NOT IN (SELECT specialofferproduct.productid FROM specialofferproduct)
   IF prod IS NULL THEN
      CALL Assertions.skip("every product is sellable in this dataset")
      RETURN
   END IF
   CALL Assertions.assertNull(SalesOrdersModel.resolveOffer(prod, SalesOrdersModel.cNoDiscountOffer),
      "a non-sellable product resolves to NULL")
END FUNCTION

#--- SalesOrdersModel.createOrder (refusal only: nothing is written) ------------

PUBLIC FUNCTION testCreateOrderRefusesMissingCustomer() RETURNS ()
   VAR created BOOLEAN
   VAR messageText STRING
   VAR newOrderId INTEGER
   IF dbUnavailable() THEN
      RETURN
   END IF
   CALL SalesOrdersModel.createOrder(cMissingId) RETURNING created, messageText, newOrderId
   CALL Assertions.assertFalse(created, "no order is created for a missing customer")
   CALL Assertions.assertNull(newOrderId, "no order id comes back")
   CALL Assertions.assertContains(messageText, "No customer with id", "the message says why")
END FUNCTION
