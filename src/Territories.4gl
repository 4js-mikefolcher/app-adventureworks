################################################################################
# Territories.4gl - browse and maintain sales territories (salesterritory).
#
# Establishes the reusable "modifiable list" pattern (read + inline add / edit /
# delete) used by the other simple-CRUD modules. salesterritory has a column
# literally named "group" (a reserved word), so this module uses an explicit
# record with safe member names and quotes the identifier in SQL.
#
# Public entry: territoriesRun()
################################################################################

IMPORT security

IMPORT FGL LibAw

#+ One territory row as shown/edited in the list. "groupName" maps to the SQL
#+ column "group"; the YTD figures are system-maintained and shown read-only.
PRIVATE TYPE tTerritory RECORD
   territoryId       INTEGER,
   name              VARCHAR(50),
   countryRegionCode VARCHAR(3),
   groupName         VARCHAR(50),
   salesYtd          DECIMAL(20,4),
   salesLastYear     DECIMAL(20,4)
END RECORD

PRIVATE DEFINE territoryList DYNAMIC ARRAY OF tTerritory

#-------------------------------------------------------------------------------
#+ Open the territories window and run the browse/maintain dialog.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION territoriesRun() RETURNS ()
   OPEN WINDOW wTerritories WITH FORM "Territories"
      ATTRIBUTES(TEXT = "Sales Territories", STYLE = "dialog")
   CALL loadTerritories()
   CALL browseTerritories()
   CLOSE WINDOW wTerritories
END FUNCTION

#-------------------------------------------------------------------------------
#+ Load all territories into the module array, ordered by name.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION loadTerritories() RETURNS ()
   VAR rec tTerritory
   VAR sqlText STRING
   LET sqlText =
      'SELECT territoryid, name, countryregioncode, "group", salesytd, saleslastyear'
      || ' FROM salesterritory ORDER BY name'
   CALL territoryList.clear()
   DECLARE cursTerritories CURSOR FROM sqlText
   FOREACH cursTerritories INTO rec.*
      LET territoryList[territoryList.getLength() + 1] = rec
   END FOREACH
END FUNCTION

#-------------------------------------------------------------------------------
#+ The browse dialog: read-only list with inline add / edit / delete triggers.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION browseTerritories() RETURNS ()
   VAR rec tTerritory
   DISPLAY ARRAY territoryList TO srTerritories.* ATTRIBUTES(DOUBLECLICK = update, UNBUFFERED)

      ON UPDATE
         LET rec = territoryList[arr_curr()]
         IF inputTerritory(scr_line(), rec) THEN
            IF saveTerritory(FALSE, rec) THEN
               LET territoryList[arr_curr()] = rec
            END IF
         END IF

      ON APPEND
         CALL defaultTerritory(rec)
         IF inputTerritory(scr_line(), rec) THEN
            IF saveTerritory(TRUE, rec) THEN
               LET territoryList[arr_curr()] = rec
            ELSE
               CALL territoryList.deleteElement(arr_curr())
            END IF
         ELSE
            CALL territoryList.deleteElement(arr_curr())
         END IF

      ON ACTION remove ATTRIBUTES(TEXT = "Delete", IMAGE = "fa-trash")
         IF territoryList.getLength() > 0 THEN
            IF LibAw.awConfirm("Delete territory",
                  SFMT("Delete territory '%1'?", territoryList[arr_curr()].name)) THEN
               IF deleteTerritory(territoryList[arr_curr()].territoryId) THEN
                  CALL territoryList.deleteElement(arr_curr())
               END IF
            END IF
         END IF

   END DISPLAY
END FUNCTION

#-------------------------------------------------------------------------------
#+ Initialise a blank territory for ON APPEND.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION defaultTerritory(rec tTerritory INOUT) RETURNS ()
   INITIALIZE rec.* TO NULL
   LET rec.salesYtd = 0
   LET rec.salesLastYear = 0
END FUNCTION

#-------------------------------------------------------------------------------
#+ Inline edit of one row's editable columns (name, country, group).
#+
#+ @param line screen line of the row being edited
#+ @param rec  territory record (INOUT)
#+ @return TRUE if the user accepted the input
#-------------------------------------------------------------------------------
PRIVATE FUNCTION inputTerritory(line INTEGER, rec tTerritory INOUT) RETURNS BOOLEAN
   LET int_flag = FALSE
   INPUT rec.name, rec.countryRegionCode, rec.groupName
      FROM srTerritories[line].name, srTerritories[line].countryRegionCode,
         srTerritories[line].groupName
      ATTRIBUTES(WITHOUT DEFAULTS)
   RETURN (NOT int_flag)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Persist a territory. On insert, omit the serial key and read the new id back.
#+ Returns TRUE on success.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION saveTerritory(isNew BOOLEAN, rec tTerritory INOUT) RETURNS BOOLEAN
   VAR sqlText STRING
   VAR modifiedAt DATETIME YEAR TO SECOND
   VAR rowGuid VARCHAR(36)
   LET modifiedAt = CURRENT YEAR TO SECOND
   BEGIN WORK
   TRY
      IF isNew THEN
         LET rowGuid = security.RandomGenerator.CreateUUIDString()
         LET sqlText =
            'INSERT INTO salesterritory'
            || ' (name, countryregioncode, "group", salesytd, saleslastyear,'
            || '  costytd, costlastyear, rowguid, modifieddate)'
            || ' VALUES (?,?,?,0,0,0,0,?,?)'
         PREPARE stmtTerritoryInsert FROM sqlText
         EXECUTE stmtTerritoryInsert USING rec.name, rec.countryRegionCode, rec.groupName,
               rowGuid, modifiedAt
         LET rec.territoryId = sqlca.sqlerrd[2]
      ELSE
         LET sqlText =
            'UPDATE salesterritory'
            || ' SET name=?, countryregioncode=?, "group"=?, modifieddate=?'
            || ' WHERE territoryid=?'
         PREPARE stmtTerritoryUpdate FROM sqlText
         EXECUTE stmtTerritoryUpdate USING rec.name, rec.countryRegionCode, rec.groupName,
               modifiedAt, rec.territoryId
      END IF
      COMMIT WORK
   CATCH
      ROLLBACK WORK
      CALL LibAw.awSqlError("Saving territory")
      RETURN FALSE
   END TRY
   RETURN TRUE
END FUNCTION

#-------------------------------------------------------------------------------
#+ Delete a territory. A territory referenced by customers, salespersons or
#+ orders cannot be removed; that surfaces as a friendly message.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION deleteTerritory(territoryId INTEGER) RETURNS BOOLEAN
   BEGIN WORK
   TRY
      DELETE FROM salesterritory WHERE salesterritory.territoryid = territoryId
      COMMIT WORK
   CATCH
      ROLLBACK WORK
      IF sqlca.sqlcode = -692 OR sqlca.sqlcode = -691 THEN
         ERROR "Cannot delete: this territory is still referenced by other records."
      ELSE
         CALL LibAw.awSqlError("Deleting territory")
      END IF
      RETURN FALSE
   END TRY
   RETURN TRUE
END FUNCTION
