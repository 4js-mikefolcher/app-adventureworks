################################################################################
# TerritoriesController.4gl - browse and maintain sales territories.
#
# The "modifiable list" pattern (read + inline add / edit / delete) used by the
# other simple-CRUD features. The controller owns the dialogs, the user flow and
# the SELECT that fills the list; every write goes through TerritoriesModel. The
# view record differs from the database record (it adds the read-only YTD figures
# and names the "group" column groupName), so toDbTerritory converts between them.
#
# Public entry: territoriesRun()
################################################################################

IMPORT util

IMPORT FGL DialogHelper
IMPORT FGL TerritoriesModel

#+ The view record: one territory row as shown and edited in the list. "groupName" is
#+ the salesterritory column "group" (a reserved word), so it carries json_name for
#+ the JSON bridge. The YTD figures are system-maintained and shown read-only.
PUBLIC TYPE tTerritoryView RECORD
   territoryId       INTEGER,
   name              VARCHAR(50),
   countryRegionCode VARCHAR(3),
   groupName         VARCHAR(50) ATTRIBUTES(json_name = "group"),
   salesYtd          DECIMAL(20,4),
   salesLastYear     DECIMAL(20,4)
END RECORD

PRIVATE DEFINE territoryList DYNAMIC ARRAY OF tTerritoryView

#-------------------------------------------------------------------------------
#+ View record to database record. The JSON bridge copies every member whose name
#+ matches a column (groupName through its json_name) and sets the columns the view
#+ does not carry to NULL, so the model's statements name the columns they write.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION toDbTerritory(viewRec tTerritoryView) RETURNS TerritoriesModel.tTerritory
   VAR dbRec TerritoriesModel.tTerritory
   CALL util.JSONObject.fromFGL(viewRec).toFGL(dbRec)
   RETURN dbRec
END FUNCTION

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
#+ Load all territories into the module array, ordered by name. The column list
#+ follows tTerritoryView member for member; "group" is quoted, a reserved word.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION loadTerritories() RETURNS ()
   VAR rec tTerritoryView
   VAR sqlText STRING
   LET sqlText =
      'SELECT salesterritory.territoryid, salesterritory.name,'
      || ' salesterritory.countryregioncode, salesterritory."group",'
      || ' salesterritory.salesytd, salesterritory.saleslastyear'
      || ' FROM salesterritory ORDER BY salesterritory.name'
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
   VAR rec tTerritoryView
   DISPLAY ARRAY territoryList TO srTerritories.* ATTRIBUTES(DOUBLECLICK = update, UNBUFFERED)

      ON UPDATE
         LET rec = territoryList[arr_curr()]
         IF inputTerritory(scr_line(), rec) THEN
            IF saveTerritory(FALSE, rec) THEN
               LET territoryList[arr_curr()] = rec
            END IF
         END IF

      ON APPEND
         # When int_flag is TRUE after this block (the input was cancelled, or the save
         # failed), the dialog removes the new row itself, so the program must not delete
         # it as well: that dropped an unrelated row from the list.
         CALL defaultTerritory(rec)
         IF inputTerritory(scr_line(), rec) THEN
            IF saveTerritory(TRUE, rec) THEN
               LET territoryList[arr_curr()] = rec
            ELSE
               LET int_flag = TRUE
            END IF
         END IF

      ON ACTION remove ATTRIBUTES(TEXT = "Delete", IMAGE = "fa-trash")
         IF territoryList.getLength() > 0 THEN
            IF DialogHelper.confirm("Delete territory",
                  SFMT("Delete territory '%1'?", territoryList[arr_curr()].name)) THEN
               IF removeTerritory(territoryList[arr_curr()].territoryId) THEN
                  CALL territoryList.deleteElement(arr_curr())
               END IF
            END IF
         END IF

   END DISPLAY
END FUNCTION

#-------------------------------------------------------------------------------
#+ Initialise a blank territory for ON APPEND.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION defaultTerritory(rec tTerritoryView INOUT) RETURNS ()
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
PRIVATE FUNCTION inputTerritory(line INTEGER, rec tTerritoryView INOUT) RETURNS BOOLEAN
   LET int_flag = FALSE
   INPUT rec.name, rec.countryRegionCode, rec.groupName
      FROM srTerritories[line].name, srTerritories[line].countryRegionCode,
         srTerritories[line].groupName
      ATTRIBUTES(WITHOUT DEFAULTS)
   RETURN (NOT int_flag)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Persist a territory through the model and show its error, if any. On insert the
#+ model returns the new serial key, which is stored back into the view record.
#+ Returns TRUE on success.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION saveTerritory(isNew BOOLEAN, rec tTerritoryView INOUT) RETURNS BOOLEAN
   VAR saved BOOLEAN
   VAR messageText STRING
   VAR newId INTEGER
   IF isNew THEN
      CALL TerritoriesModel.insertTerritory(toDbTerritory(rec))
         RETURNING saved, messageText, newId
      IF saved THEN
         LET rec.territoryId = newId
      END IF
   ELSE
      CALL TerritoriesModel.updateTerritory(toDbTerritory(rec)) RETURNING saved, messageText
   END IF
   IF NOT saved THEN
      ERROR messageText
   END IF
   RETURN saved
END FUNCTION

#-------------------------------------------------------------------------------
#+ Delete a territory through the model and show its message, if any. Returns TRUE
#+ when the row was removed.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION removeTerritory(territoryId INTEGER) RETURNS BOOLEAN
   VAR removed BOOLEAN
   VAR messageText STRING
   CALL TerritoriesModel.deleteTerritory(territoryId) RETURNING removed, messageText
   IF NOT removed THEN
      ERROR messageText
   END IF
   RETURN removed
END FUNCTION
