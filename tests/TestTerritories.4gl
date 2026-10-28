################################################################################
# TestTerritories.4gl - fglunit suite for the view-to-database conversion in
# TerritoriesController (the JSON bridge, standards rule 13).
#
# The bridge fails silently: a member that does not match becomes NULL without an
# error. So every member that crosses is populated and asserted not NULL. No
# database is needed.
#
# Build & run (see the top-level Makefile 'test' target):
#   fglcomp -M -Wall -Werror -o bin tests/TestTerritories.4gl
#   fglrun bin/TestTerritories.42m
################################################################################

IMPORT FGL com.fourjs.fglunit.FglUnit
IMPORT FGL com.fourjs.fglunit.Assertions
IMPORT FGL com.fourjs.fglunit.CliArgs
IMPORT FGL TerritoriesController
IMPORT FGL TerritoriesModel

MAIN
   CALL CliArgs.parse()    -- enable --junit / --filter / -v / --fail-fast
   CALL FglUnit.suite("TerritoriesController conversion")

   CALL FglUnit.register("testToDbTerritoryCrossesEveryMember",
      FUNCTION testToDbTerritoryCrossesEveryMember)
   CALL FglUnit.register("testToDbTerritoryMapsGroupName", FUNCTION testToDbTerritoryMapsGroupName)
   CALL FglUnit.register("testToDbTerritoryNullsOtherColumns",
      FUNCTION testToDbTerritoryNullsOtherColumns)

   EXIT PROGRAM FglUnit.run()
END MAIN

#+ A view record with every member populated.
PRIVATE FUNCTION fullViewRecord() RETURNS TerritoriesController.tTerritoryView
   VAR viewRec TerritoriesController.tTerritoryView
   LET viewRec.territoryId = 7
   LET viewRec.name = "Test Territory"
   LET viewRec.countryRegionCode = "FR"
   LET viewRec.groupName = "Europe"
   LET viewRec.salesYtd = 1234567.8901
   LET viewRec.salesLastYear = 7654321.1098
   RETURN viewRec
END FUNCTION

PUBLIC FUNCTION testToDbTerritoryCrossesEveryMember() RETURNS ()
   VAR dbRec TerritoriesModel.tTerritory
   LET dbRec = TerritoriesController.toDbTerritory(fullViewRecord())
   CALL Assertions.assertNotNull(dbRec.territoryid, "territoryId crosses")
   CALL Assertions.assertNotNull(dbRec.name, "name crosses")
   CALL Assertions.assertNotNull(dbRec.countryregioncode, "countryRegionCode crosses")
   CALL Assertions.assertNotNull(dbRec.group, "groupName crosses")
   CALL Assertions.assertNotNull(dbRec.salesytd, "salesYtd crosses")
   CALL Assertions.assertNotNull(dbRec.saleslastyear, "salesLastYear crosses")
   CALL Assertions.assertEqualsInt(7, dbRec.territoryid, "territoryId value")
   CALL Assertions.assertEquals("Test Territory", dbRec.name, "name value")
   CALL Assertions.assertEquals("FR", dbRec.countryregioncode, "countryRegionCode value")
   CALL Assertions.assertEqualsDec(1234567.8901, dbRec.salesytd, 0.0001, "salesYtd value")
   CALL Assertions.assertEqualsDec(7654321.1098, dbRec.saleslastyear, 0.0001, "salesLastYear value")
END FUNCTION

PUBLIC FUNCTION testToDbTerritoryMapsGroupName() RETURNS ()
   # The view member groupName fills the column "group" through its json_name.
   VAR dbRec TerritoriesModel.tTerritory
   LET dbRec = TerritoriesController.toDbTerritory(fullViewRecord())
   CALL Assertions.assertEquals("Europe", dbRec.group, "groupName fills the group column")
END FUNCTION

PUBLIC FUNCTION testToDbTerritoryNullsOtherColumns() RETURNS ()
   # The bridge replaces the whole target: columns the view does not carry are NULL,
   # which is why the model's INSERT and UPDATE name the columns they write.
   VAR dbRec TerritoriesModel.tTerritory
   LET dbRec = TerritoriesController.toDbTerritory(fullViewRecord())
   CALL Assertions.assertNull(dbRec.costytd, "costYtd is not carried by the view")
   CALL Assertions.assertNull(dbRec.costlastyear, "costLastYear is not carried by the view")
   CALL Assertions.assertNull(dbRec.rowguid, "rowGuid is not carried by the view")
   CALL Assertions.assertNull(dbRec.modifieddate, "modifiedDate is not carried by the view")
END FUNCTION
