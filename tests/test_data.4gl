################################################################################
# test_data.4gl - fglunit suite for the data-access layer (aw_repo) and the
# name-resolution helpers in lib_aw.
#
# These tests need the live "adventureworks" database. The suite connects once
# in setUpSuite; if the connection fails (DB not running / not configured) every
# test calls skip() rather than erroring, so the suite stays green on machines
# without the database.
#
# Assertions use only stable, relationship-derived facts (formats, fallbacks,
# referential rules) - never hard-coded names - so they are robust to the data.
################################################################################

IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL com.fourjs.fglunit.CliArgs
IMPORT FGL lib_aw
IMPORT FGL aw_repo

PRIVATE DEFINE m_connected BOOLEAN

#+ A customer id that cannot exist in the sample data (used for fallback tests).
PRIVATE CONSTANT MISSING_ID = 99999999

MAIN
    CALL CliArgs.parse()    -- enable --junit / --filter / -v / --fail-fast
    CALL FglUnit.suite("data layer (aw_repo + lib_aw)")
    CALL FglUnit.setSetupSuite(FUNCTION setup_suite)
    CALL FglUnit.setTeardownSuite(FUNCTION teardown_suite)

    CALL FglUnit.register("test_customer_label_individual", FUNCTION test_customer_label_individual)
    CALL FglUnit.register("test_customer_label_store",      FUNCTION test_customer_label_store)
    CALL FglUnit.register("test_customer_label_missing",    FUNCTION test_customer_label_missing)
    CALL FglUnit.register("test_salesperson_label_known",   FUNCTION test_salesperson_label_known)
    CALL FglUnit.register("test_salesperson_label_missing", FUNCTION test_salesperson_label_missing)

    CALL FglUnit.register("test_customer_exists_true",      FUNCTION test_customer_exists_true)
    CALL FglUnit.register("test_customer_exists_false",     FUNCTION test_customer_exists_false)

    CALL FglUnit.register("test_list_price_known",          FUNCTION test_list_price_known)
    CALL FglUnit.register("test_list_price_missing",        FUNCTION test_list_price_missing)

    CALL FglUnit.register("test_resolve_offer_valid_pair",  FUNCTION test_resolve_offer_valid_pair)
    CALL FglUnit.register("test_resolve_offer_fallback",    FUNCTION test_resolve_offer_fallback)
    CALL FglUnit.register("test_resolve_offer_not_sellable",FUNCTION test_resolve_offer_not_sellable)

    EXIT PROGRAM FglUnit.run()
END MAIN

#--- suite fixtures ------------------------------------------------------------

PUBLIC FUNCTION setup_suite()
    LET m_connected = FALSE
    TRY
        CONNECT TO "adventureworks"
        LET m_connected = TRUE
    CATCH
        LET m_connected = FALSE
    END TRY
END FUNCTION

PUBLIC FUNCTION teardown_suite()
    IF m_connected THEN
        DISCONNECT CURRENT
    END IF
END FUNCTION

#+ Guard used at the top of every test; returns TRUE if the test should skip.
PRIVATE FUNCTION db_unavailable() RETURNS BOOLEAN
    IF NOT m_connected THEN
        CALL Assertions.skip("adventureworks database not available")
        RETURN TRUE
    END IF
    RETURN FALSE
END FUNCTION

#--- helpers that fetch stable sample rows by relationship ---------------------

PRIVATE FUNCTION an_individual_customer() RETURNS INTEGER
    DEFINE id INTEGER
    SELECT MIN(customerid) INTO id FROM customer WHERE personid IS NOT NULL
    RETURN id
END FUNCTION

PRIVATE FUNCTION a_store_customer() RETURNS INTEGER
    DEFINE id INTEGER
    SELECT MIN(customerid) INTO id FROM customer WHERE storeid IS NOT NULL
    RETURN id
END FUNCTION

PRIVATE FUNCTION a_salesperson() RETURNS INTEGER
    DEFINE id INTEGER
    SELECT MIN(businessentityid) INTO id FROM salesperson
    RETURN id
END FUNCTION

PRIVATE FUNCTION a_sellable_product() RETURNS INTEGER
    DEFINE id INTEGER
    SELECT MIN(productid) INTO id FROM specialofferproduct
    RETURN id
END FUNCTION

#--- lib_aw.aw_customer_label / aw_salesperson_label ---------------------------

PUBLIC FUNCTION test_customer_label_individual()
    DEFINE id INTEGER
    DEFINE label STRING
    IF db_unavailable() THEN RETURN END IF
    LET id = an_individual_customer()
    LET label = aw_customer_label(id)
    CALL Assertions.assertNotNull(label, "individual customer label is not null")
    # Individuals resolve to "Lastname, Firstname".
    CALL Assertions.assertContains(label, ", ", "individual label is 'Last, First'")
    CALL Assertions.assertNotContains(label, "Customer ",
        "a resolvable customer must not use the fallback label")
END FUNCTION

PUBLIC FUNCTION test_customer_label_store()
    DEFINE id INTEGER
    DEFINE label, expected STRING
    IF db_unavailable() THEN RETURN END IF
    LET id = a_store_customer()
    IF id IS NULL THEN
        CALL Assertions.skip("no store customers in this dataset")
        RETURN
    END IF
    LET label = aw_customer_label(id)
    SELECT store.name INTO expected
      FROM customer, store
     WHERE store.businessentityid = customer.storeid
       AND customer.customerid = id
    CALL Assertions.assertEquals(expected, label, "store customer resolves to the store name")
END FUNCTION

PUBLIC FUNCTION test_customer_label_missing()
    IF db_unavailable() THEN RETURN END IF
    CALL Assertions.assertEquals(SFMT("Customer %1", MISSING_ID),
        aw_customer_label(MISSING_ID), "unknown customer uses the fallback label")
END FUNCTION

PUBLIC FUNCTION test_salesperson_label_known()
    DEFINE id INTEGER
    DEFINE label STRING
    IF db_unavailable() THEN RETURN END IF
    LET id = a_salesperson()
    LET label = aw_salesperson_label(id)
    CALL Assertions.assertContains(label, ", ", "salesperson label is 'Last, First'")
    CALL Assertions.assertNotContains(label, "Salesperson ",
        "a resolvable salesperson must not use the fallback label")
END FUNCTION

PUBLIC FUNCTION test_salesperson_label_missing()
    IF db_unavailable() THEN RETURN END IF
    CALL Assertions.assertEquals(SFMT("Salesperson %1", MISSING_ID),
        aw_salesperson_label(MISSING_ID), "unknown salesperson uses the fallback label")
END FUNCTION

#--- aw_repo.repo_customer_exists ----------------------------------------------

PUBLIC FUNCTION test_customer_exists_true()
    DEFINE id INTEGER
    IF db_unavailable() THEN RETURN END IF
    LET id = an_individual_customer()
    CALL Assertions.assertTrue(aw_repo.repo_customer_exists(id), "existing customer reports true")
END FUNCTION

PUBLIC FUNCTION test_customer_exists_false()
    IF db_unavailable() THEN RETURN END IF
    CALL Assertions.assertFalse(aw_repo.repo_customer_exists(MISSING_ID),
        "non-existent customer reports false")
END FUNCTION

#--- aw_repo.repo_product_list_price -------------------------------------------

PUBLIC FUNCTION test_list_price_known()
    DEFINE id INTEGER
    DEFINE expected, actual DECIMAL(20,4)
    IF db_unavailable() THEN RETURN END IF
    SELECT MIN(productid) INTO id FROM product WHERE listprice > 0
    SELECT listprice INTO expected FROM product WHERE productid = id
    LET actual = aw_repo.repo_product_list_price(id)
    CALL Assertions.assertEqualsDec(expected, actual, 0.0001,
        "repo list price matches the stored value")
END FUNCTION

PUBLIC FUNCTION test_list_price_missing()
    DEFINE maxid INTEGER
    IF db_unavailable() THEN RETURN END IF
    SELECT MAX(productid) INTO maxid FROM product
    CALL Assertions.assertNull(aw_repo.repo_product_list_price(maxid + 1),
        "unknown product has no list price")
END FUNCTION

#--- aw_repo.repo_resolve_offer (composite FK safety) --------------------------

PUBLIC FUNCTION test_resolve_offer_valid_pair()
    DEFINE prod, offer, resolved INTEGER
    IF db_unavailable() THEN RETURN END IF
    LET prod = a_sellable_product()
    SELECT MIN(specialofferid) INTO offer FROM specialofferproduct WHERE productid = prod
    LET resolved = aw_repo.repo_resolve_offer(prod, offer)
    CALL Assertions.assertEqualsInt(offer, resolved,
        "a valid (offer, product) pair is returned unchanged")
END FUNCTION

PUBLIC FUNCTION test_resolve_offer_fallback()
    DEFINE prod, resolved, cnt INTEGER
    IF db_unavailable() THEN RETURN END IF
    LET prod = a_sellable_product()
    # MISSING_ID is not a valid offer for the product -> must fall back to a
    # valid one, and the resolved pair must satisfy the composite FK.
    LET resolved = aw_repo.repo_resolve_offer(prod, MISSING_ID)
    CALL Assertions.assertNotNull(resolved, "fallback returns a valid offer")
    SELECT COUNT(*) INTO cnt FROM specialofferproduct
     WHERE specialofferid = resolved AND productid = prod
    CALL Assertions.assertTrue(cnt > 0, "resolved (offer, product) pair exists in specialofferproduct")
END FUNCTION

PUBLIC FUNCTION test_resolve_offer_not_sellable()
    DEFINE prod INTEGER
    IF db_unavailable() THEN RETURN END IF
    # A product with no specialofferproduct rows cannot be ordered -> NULL.
    LET prod = NULL
    SELECT MIN(productid) INTO prod FROM product
     WHERE productid NOT IN (SELECT productid FROM specialofferproduct)
    IF prod IS NULL THEN
        CALL Assertions.skip("every product is sellable in this dataset")
        RETURN
    END IF
    CALL Assertions.assertNull(aw_repo.repo_resolve_offer(prod, 1),
        "a non-sellable product resolves to NULL")
END FUNCTION
