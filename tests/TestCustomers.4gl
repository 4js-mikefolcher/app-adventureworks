################################################################################
# TestCustomers.4gl - fglunit suite for the view-to-database conversion in
# CustomersController (the JSON bridge, standards rule 13).
#
# The bridge fails silently: a member that does not match becomes NULL without an
# error. So every member that crosses is populated and asserted not NULL. No
# database is needed.
#
# Build & run (see the top-level Makefile 'test' target):
#   fglcomp -M -Wall -Werror -o bin tests/TestCustomers.4gl
#   fglrun bin/TestCustomers.42m
################################################################################

IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL com.fourjs.fglunit.CliArgs
IMPORT FGL CustomersController
IMPORT FGL CustomersModel

MAIN
   CALL CliArgs.parse()    -- enable --junit / --filter / -v / --fail-fast
   CALL FglUnit.suite("CustomersController conversion")

   CALL FglUnit.register("testToDbCustomerCrossesEveryMember", FUNCTION testToDbCustomerCrossesEveryMember)
   CALL FglUnit.register("testToDbCustomerKeepsNullTerritory", FUNCTION testToDbCustomerKeepsNullTerritory)
   CALL FglUnit.register("testToDbCustomerNullsOtherColumns", FUNCTION testToDbCustomerNullsOtherColumns)

   EXIT PROGRAM FglUnit.run()
END MAIN

#+ A view record with every member populated.
PRIVATE FUNCTION fullViewRecord() RETURNS CustomersController.tCustomerView
   VAR viewRec CustomersController.tCustomerView
   LET viewRec.customerId = 11000
   LET viewRec.customerType = "Individual"
   LET viewRec.customerName = "Zheng, Jon"
   LET viewRec.territoryId = 9
   RETURN viewRec
END FUNCTION

PUBLIC FUNCTION testToDbCustomerCrossesEveryMember() RETURNS ()
   VAR dbRec CustomersModel.tCustomer
   LET dbRec = CustomersController.toDbCustomer(fullViewRecord())
   CALL Assertions.assertNotNull(dbRec.customerid, "customerId crosses")
   CALL Assertions.assertNotNull(dbRec.territoryid, "territoryId crosses")
   CALL Assertions.assertEqualsInt(11000, dbRec.customerid, "customerId value")
   CALL Assertions.assertEqualsInt(9, dbRec.territoryid, "territoryId value")
END FUNCTION

PUBLIC FUNCTION testToDbCustomerKeepsNullTerritory() RETURNS ()
   # Clearing the territory writes NULL; the bridge must not turn it into a value.
   VAR viewRec CustomersController.tCustomerView
   VAR dbRec CustomersModel.tCustomer
   LET viewRec = fullViewRecord()
   LET viewRec.territoryId = NULL
   LET dbRec = CustomersController.toDbCustomer(viewRec)
   CALL Assertions.assertNull(dbRec.territoryid, "NULL territoryId stays NULL")
   CALL Assertions.assertNotNull(dbRec.customerid, "customerId is unaffected")
END FUNCTION

PUBLIC FUNCTION testToDbCustomerNullsOtherColumns() RETURNS ()
   # The bridge replaces the whole target: columns the view does not carry are NULL,
   # which is why the model's UPDATE names the columns it writes. The type and the name
   # are display-only and have no column.
   VAR dbRec CustomersModel.tCustomer
   LET dbRec = CustomersController.toDbCustomer(fullViewRecord())
   CALL Assertions.assertNull(dbRec.personid, "personId is not carried by the view")
   CALL Assertions.assertNull(dbRec.storeid, "storeId is not carried by the view")
   CALL Assertions.assertNull(dbRec.rowguid, "rowGuid is not carried by the view")
   CALL Assertions.assertNull(dbRec.modifieddate, "modifiedDate is not carried by the view")
END FUNCTION
