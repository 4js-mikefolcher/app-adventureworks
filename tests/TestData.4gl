################################################################################
# TestData.4gl - fglunit suite for the data-access layer (AwRepo) and the
# name-resolution helpers in LibAw.
#
# These tests need the live "adventureworks" database. The suite connects once
# in setupSuite; if the connection fails (DB not running / not configured) every
# test calls skip() rather than erroring, so the suite stays green on machines
# without the database.
#
# Assertions use only stable, relationship-derived facts (formats, fallbacks,
# referential rules) - never hard-coded names - so they are robust to the data.
################################################################################

IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL com.fourjs.fglunit.CliArgs
IMPORT FGL LibAw
IMPORT FGL AwRepo

PRIVATE DEFINE connected BOOLEAN

#+ A customer id that cannot exist in the sample data (used for fallback tests).
PRIVATE CONSTANT cMissingId = 99999999

MAIN
   CALL CliArgs.parse()    -- enable --junit / --filter / -v / --fail-fast
   CALL FglUnit.suite("data layer (AwRepo + LibAw)")
   CALL FglUnit.setSetupSuite(FUNCTION setupSuite)
   CALL FglUnit.setTeardownSuite(FUNCTION teardownSuite)

   CALL FglUnit.register("testCustomerLabelIndividual", FUNCTION testCustomerLabelIndividual)
   CALL FglUnit.register("testCustomerLabelStore",      FUNCTION testCustomerLabelStore)
   CALL FglUnit.register("testCustomerLabelMissing",    FUNCTION testCustomerLabelMissing)
   CALL FglUnit.register("testSalesPersonLabelKnown",   FUNCTION testSalesPersonLabelKnown)
   CALL FglUnit.register("testSalesPersonLabelMissing", FUNCTION testSalesPersonLabelMissing)

   CALL FglUnit.register("testCustomerExistsTrue",      FUNCTION testCustomerExistsTrue)
   CALL FglUnit.register("testCustomerExistsFalse",     FUNCTION testCustomerExistsFalse)

   CALL FglUnit.register("testListPriceKnown",          FUNCTION testListPriceKnown)
   CALL FglUnit.register("testListPriceMissing",        FUNCTION testListPriceMissing)

   CALL FglUnit.register("testResolveOfferValidPair",   FUNCTION testResolveOfferValidPair)
   CALL FglUnit.register("testResolveOfferFallback",    FUNCTION testResolveOfferFallback)
   CALL FglUnit.register("testResolveOfferNotSellable", FUNCTION testResolveOfferNotSellable)

   EXIT PROGRAM FglUnit.run()
END MAIN

#--- suite fixtures ------------------------------------------------------------

PUBLIC FUNCTION setupSuite() RETURNS ()
   LET connected = FALSE
   TRY
      CONNECT TO LibAw.cAwDbName
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

PRIVATE FUNCTION anIndividualCustomer() RETURNS INTEGER
   VAR id INTEGER
   SELECT MIN(customer.customerid) INTO id FROM customer WHERE customer.personid IS NOT NULL
   RETURN id
END FUNCTION

PRIVATE FUNCTION aStoreCustomer() RETURNS INTEGER
   VAR id INTEGER
   SELECT MIN(customer.customerid) INTO id FROM customer WHERE customer.storeid IS NOT NULL
   RETURN id
END FUNCTION

PRIVATE FUNCTION aSalesPerson() RETURNS INTEGER
   VAR id INTEGER
   SELECT MIN(salesperson.businessentityid) INTO id FROM salesperson
   RETURN id
END FUNCTION

PRIVATE FUNCTION aSellableProduct() RETURNS INTEGER
   VAR id INTEGER
   SELECT MIN(specialofferproduct.productid) INTO id FROM specialofferproduct
   RETURN id
END FUNCTION

#--- LibAw.awCustomerLabel / awSalesPersonLabel --------------------------------

PUBLIC FUNCTION testCustomerLabelIndividual() RETURNS ()
   VAR id INTEGER
   VAR labelText STRING
   IF dbUnavailable() THEN
      RETURN
   END IF
   LET id = anIndividualCustomer()
   LET labelText = LibAw.awCustomerLabel(id)
   CALL Assertions.assertNotNull(labelText, "individual customer label is not null")
   # Individuals resolve to "Lastname, Firstname".
   CALL Assertions.assertContains(labelText, ", ", "individual label is 'Last, First'")
   CALL Assertions.assertNotContains(labelText, "Customer ",
      "a resolvable customer must not use the fallback label")
END FUNCTION

PUBLIC FUNCTION testCustomerLabelStore() RETURNS ()
   VAR id INTEGER
   VAR labelText STRING
   VAR expected STRING
   IF dbUnavailable() THEN
      RETURN
   END IF
   LET id = aStoreCustomer()
   IF id IS NULL THEN
      CALL Assertions.skip("no store customers in this dataset")
      RETURN
   END IF
   LET labelText = LibAw.awCustomerLabel(id)
   SELECT store.name INTO expected
      FROM customer, store
      WHERE store.businessentityid = customer.storeid
         AND customer.customerid = id
   CALL Assertions.assertEquals(expected, labelText, "store customer resolves to the store name")
END FUNCTION

PUBLIC FUNCTION testCustomerLabelMissing() RETURNS ()
   IF dbUnavailable() THEN
      RETURN
   END IF
   CALL Assertions.assertEquals(SFMT("Customer %1", cMissingId),
      LibAw.awCustomerLabel(cMissingId), "unknown customer uses the fallback label")
END FUNCTION

PUBLIC FUNCTION testSalesPersonLabelKnown() RETURNS ()
   VAR id INTEGER
   VAR labelText STRING
   IF dbUnavailable() THEN
      RETURN
   END IF
   LET id = aSalesPerson()
   LET labelText = LibAw.awSalesPersonLabel(id)
   CALL Assertions.assertContains(labelText, ", ", "salesperson label is 'Last, First'")
   CALL Assertions.assertNotContains(labelText, "Salesperson ",
      "a resolvable salesperson must not use the fallback label")
END FUNCTION

PUBLIC FUNCTION testSalesPersonLabelMissing() RETURNS ()
   IF dbUnavailable() THEN
      RETURN
   END IF
   CALL Assertions.assertEquals(SFMT("Salesperson %1", cMissingId),
      LibAw.awSalesPersonLabel(cMissingId), "unknown salesperson uses the fallback label")
END FUNCTION

#--- AwRepo.repoCustomerExists -------------------------------------------------

PUBLIC FUNCTION testCustomerExistsTrue() RETURNS ()
   VAR id INTEGER
   IF dbUnavailable() THEN
      RETURN
   END IF
   LET id = anIndividualCustomer()
   CALL Assertions.assertTrue(AwRepo.repoCustomerExists(id), "existing customer reports true")
END FUNCTION

PUBLIC FUNCTION testCustomerExistsFalse() RETURNS ()
   IF dbUnavailable() THEN
      RETURN
   END IF
   CALL Assertions.assertFalse(AwRepo.repoCustomerExists(cMissingId),
      "non-existent customer reports false")
END FUNCTION

#--- AwRepo.repoProductListPrice -----------------------------------------------

PUBLIC FUNCTION testListPriceKnown() RETURNS ()
   VAR id INTEGER
   VAR expected DECIMAL(20,4)
   VAR actual DECIMAL(20,4)
   IF dbUnavailable() THEN
      RETURN
   END IF
   SELECT MIN(product.productid) INTO id FROM product WHERE product.listprice > 0
   SELECT product.listprice INTO expected FROM product WHERE product.productid = id
   LET actual = AwRepo.repoProductListPrice(id)
   CALL Assertions.assertEqualsDec(expected, actual, 0.0001,
      "repo list price matches the stored value")
END FUNCTION

PUBLIC FUNCTION testListPriceMissing() RETURNS ()
   VAR maxId INTEGER
   IF dbUnavailable() THEN
      RETURN
   END IF
   SELECT MAX(product.productid) INTO maxId FROM product
   CALL Assertions.assertNull(AwRepo.repoProductListPrice(maxId + 1),
      "unknown product has no list price")
END FUNCTION

#--- AwRepo.repoResolveOffer (composite FK safety) -----------------------------

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
   LET resolved = AwRepo.repoResolveOffer(prod, offer)
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
   # cMissingId is not a valid offer for the product -> must fall back to a
   # valid one, and the resolved pair must satisfy the composite FK.
   LET resolved = AwRepo.repoResolveOffer(prod, cMissingId)
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
   CALL Assertions.assertNull(AwRepo.repoResolveOffer(prod, 1),
      "a non-sellable product resolves to NULL")
END FUNCTION
