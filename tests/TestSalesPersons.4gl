################################################################################
# TestSalesPersons.4gl - fglunit suite for the sales-persons feature: the
# view-to-database conversion in SalesPersonsController (the JSON bridge, standards
# rule 13) and the business-rule validation in SalesPersonsModel.
#
# The bridge fails silently: a member that does not match becomes NULL without an
# error. So every member that crosses is populated and asserted not NULL. No
# database is needed.
#
# Build & run (see the top-level Makefile 'test' target):
#   fglcomp -M -Wall -Werror -o bin tests/TestSalesPersons.4gl
#   fglrun bin/TestSalesPersons.42m
################################################################################

IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL com.fourjs.fglunit.CliArgs
IMPORT FGL SalesPersonsController
IMPORT FGL SalesPersonsModel

MAIN
   CALL CliArgs.parse()    -- enable --junit / --filter / -v / --fail-fast
   CALL FglUnit.suite("SalesPersons")

   CALL FglUnit.register("testToDbSalesPersonCrossesEveryMember",
      FUNCTION testToDbSalesPersonCrossesEveryMember)
   CALL FglUnit.register("testToDbSalesPersonKeepsNullQuota", FUNCTION testToDbSalesPersonKeepsNullQuota)
   CALL FglUnit.register("testToDbSalesPersonNullsOtherColumns",
      FUNCTION testToDbSalesPersonNullsOtherColumns)

   CALL FglUnit.register("testValidatePositiveValues",   FUNCTION testValidatePositiveValues)
   CALL FglUnit.register("testValidateZeroValues",       FUNCTION testValidateZeroValues)
   CALL FglUnit.register("testValidateNullQuota",        FUNCTION testValidateNullQuota)
   CALL FglUnit.register("testValidateNegativeBonus",    FUNCTION testValidateNegativeBonus)
   CALL FglUnit.register("testValidateNegativeCommission", FUNCTION testValidateNegativeCommission)
   CALL FglUnit.register("testValidateNegativeQuota",    FUNCTION testValidateNegativeQuota)

   EXIT PROGRAM FglUnit.run()
END MAIN

#+ A view record with every member populated.
PRIVATE FUNCTION fullViewRecord() RETURNS SalesPersonsController.tSalesPersonView
   VAR viewRec SalesPersonsController.tSalesPersonView
   LET viewRec.businessEntityId = 274
   LET viewRec.salesPersonName = "Jiang, Stephen"
   LET viewRec.territoryId = 3
   LET viewRec.salesQuota = 250000.00
   LET viewRec.bonus = 5000.00
   LET viewRec.commissionPct = 0.012
   LET viewRec.salesYtd = 559697.5639
   RETURN viewRec
END FUNCTION

#+ A database record holding only the three validated values.
PRIVATE FUNCTION salesPersonWith(quota DECIMAL(20,4), bonus DECIMAL(20,4),
      commission DECIMAL(10,4)) RETURNS SalesPersonsModel.tSalesPerson
   VAR rec SalesPersonsModel.tSalesPerson
   LET rec.salesquota = quota
   LET rec.bonus = bonus
   LET rec.commissionpct = commission
   RETURN rec
END FUNCTION

#+ TRUE when the model accepts the three values.
PRIVATE FUNCTION valuesValid(quota DECIMAL(20,4), bonus DECIMAL(20,4),
      commission DECIMAL(10,4)) RETURNS BOOLEAN
   VAR valid BOOLEAN
   VAR messageText STRING
   CALL SalesPersonsModel.validateSalesPerson(salesPersonWith(quota, bonus, commission))
      RETURNING valid, messageText
   RETURN valid
END FUNCTION

#--- toDbSalesPerson -----------------------------------------------------------

PUBLIC FUNCTION testToDbSalesPersonCrossesEveryMember() RETURNS ()
   VAR dbRec SalesPersonsModel.tSalesPerson
   LET dbRec = SalesPersonsController.toDbSalesPerson(fullViewRecord())
   CALL Assertions.assertNotNull(dbRec.businessentityid, "businessEntityId crosses")
   CALL Assertions.assertNotNull(dbRec.territoryid, "territoryId crosses")
   CALL Assertions.assertNotNull(dbRec.salesquota, "salesQuota crosses")
   CALL Assertions.assertNotNull(dbRec.bonus, "bonus crosses")
   CALL Assertions.assertNotNull(dbRec.commissionpct, "commissionPct crosses")
   CALL Assertions.assertNotNull(dbRec.salesytd, "salesYtd crosses")
   CALL Assertions.assertEqualsInt(274, dbRec.businessentityid, "businessEntityId value")
   CALL Assertions.assertEqualsInt(3, dbRec.territoryid, "territoryId value")
   CALL Assertions.assertEqualsDec(250000.00, dbRec.salesquota, 0.0001, "salesQuota value")
   CALL Assertions.assertEqualsDec(5000.00, dbRec.bonus, 0.0001, "bonus value")
   CALL Assertions.assertEqualsDec(0.012, dbRec.commissionpct, 0.0001, "commissionPct value")
   CALL Assertions.assertEqualsDec(559697.5639, dbRec.salesytd, 0.0001, "salesYtd value")
END FUNCTION

PUBLIC FUNCTION testToDbSalesPersonKeepsNullQuota() RETURNS ()
   # A NULL quota is allowed and stays NULL, it is not turned into a value.
   VAR viewRec SalesPersonsController.tSalesPersonView
   VAR dbRec SalesPersonsModel.tSalesPerson
   LET viewRec = fullViewRecord()
   LET viewRec.salesQuota = NULL
   LET dbRec = SalesPersonsController.toDbSalesPerson(viewRec)
   CALL Assertions.assertNull(dbRec.salesquota, "NULL salesQuota stays NULL")
   CALL Assertions.assertNotNull(dbRec.bonus, "bonus is unaffected")
END FUNCTION

PUBLIC FUNCTION testToDbSalesPersonNullsOtherColumns() RETURNS ()
   # The bridge replaces the whole target: columns the view does not carry are NULL,
   # which is why the model's UPDATE names the columns it writes.
   VAR dbRec SalesPersonsModel.tSalesPerson
   LET dbRec = SalesPersonsController.toDbSalesPerson(fullViewRecord())
   CALL Assertions.assertNull(dbRec.saleslastyear, "salesLastYear is not carried by the view")
   CALL Assertions.assertNull(dbRec.rowguid, "rowGuid is not carried by the view")
   CALL Assertions.assertNull(dbRec.modifieddate, "modifiedDate is not carried by the view")
END FUNCTION

#--- validateSalesPerson -------------------------------------------------------

PUBLIC FUNCTION testValidatePositiveValues() RETURNS ()
   CALL Assertions.assertTrue(valuesValid(250000, 5000, 0.012), "positive values are valid")
END FUNCTION

PUBLIC FUNCTION testValidateZeroValues() RETURNS ()
   CALL Assertions.assertTrue(valuesValid(0, 0, 0), "zero is not negative")
END FUNCTION

PUBLIC FUNCTION testValidateNullQuota() RETURNS ()
   CALL Assertions.assertTrue(valuesValid(NULL, 5000, 0.012), "a NULL quota is allowed")
END FUNCTION

PUBLIC FUNCTION testValidateNegativeBonus() RETURNS ()
   VAR valid BOOLEAN
   VAR messageText STRING
   CALL SalesPersonsModel.validateSalesPerson(salesPersonWith(1000, -1, 0.01))
      RETURNING valid, messageText
   CALL Assertions.assertFalse(valid, "a negative bonus is invalid")
   CALL Assertions.assertContains(messageText, "negative", "the message says why")
END FUNCTION

PUBLIC FUNCTION testValidateNegativeCommission() RETURNS ()
   CALL Assertions.assertFalse(valuesValid(1000, 100, -0.01), "a negative commission is invalid")
END FUNCTION

PUBLIC FUNCTION testValidateNegativeQuota() RETURNS ()
   CALL Assertions.assertFalse(valuesValid(-1, 100, 0.01), "a negative quota is invalid")
END FUNCTION
