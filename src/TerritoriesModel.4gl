################################################################################
# TerritoriesModel.4gl - data model for sales territories (salesterritory).
#
# Owns the database record and the data changes (insert, update, delete), each in
# its own transaction. No UI: success or failure goes back to the controller as
# return values, and the controller shows the message. salesterritory has a column
# literally named "group" (a reserved word), so the SQL below is dynamic and
# quotes the identifier.
################################################################################

IMPORT security

IMPORT FGL SqlHelper

SCHEMA adventureworks

#+ The database record: one row of salesterritory, as the model reads and writes it.
PUBLIC TYPE tTerritory RECORD LIKE salesterritory.*

#-------------------------------------------------------------------------------
#+ Insert a new territory. The serial key is omitted and read back; the YTD and
#+ cost figures start at zero and the row guid and modified date are set here.
#+
#+ @param rec the territory to insert (name, country region code and group)
#+ @return TRUE and the new territory id, or FALSE with the error text
#-------------------------------------------------------------------------------
PUBLIC FUNCTION insertTerritory(rec tTerritory) RETURNS (BOOLEAN, STRING, INTEGER)
   VAR sqlText STRING
   VAR messageText STRING
   VAR modifiedAt DATETIME YEAR TO SECOND = CURRENT YEAR TO SECOND
   VAR rowGuid VARCHAR(36)
   VAR newId INTEGER
   LET sqlText =
      'INSERT INTO salesterritory'
      || ' (name, countryregioncode, "group", salesytd, saleslastyear,'
      || '  costytd, costlastyear, rowguid, modifieddate)'
      || ' VALUES (?,?,?,0,0,0,0,?,?)'
   BEGIN WORK
   TRY
      LET rowGuid = security.RandomGenerator.CreateUUIDString()
      PREPARE stmtTerritoryInsert FROM sqlText
      EXECUTE stmtTerritoryInsert USING rec.name, rec.countryregioncode, rec.group,
            rowGuid, modifiedAt
      LET newId = sqlca.sqlerrd[2]
      COMMIT WORK
   CATCH
      LET messageText = SqlHelper.errorText("Saving territory")
      ROLLBACK WORK
      RETURN FALSE, messageText, NULL
   END TRY
   RETURN TRUE, NULL, newId
END FUNCTION

#-------------------------------------------------------------------------------
#+ Update the editable columns of a territory (name, country region code, group).
#+ The statement names its columns, so the rest of the record is never written.
#+
#+ @param rec the territory to update, identified by its territory id
#+ @return TRUE, or FALSE with the error text
#-------------------------------------------------------------------------------
PUBLIC FUNCTION updateTerritory(rec tTerritory) RETURNS (BOOLEAN, STRING)
   VAR sqlText STRING
   VAR messageText STRING
   VAR modifiedAt DATETIME YEAR TO SECOND = CURRENT YEAR TO SECOND
   LET sqlText =
      'UPDATE salesterritory'
      || ' SET name=?, countryregioncode=?, "group"=?, modifieddate=?'
      || ' WHERE salesterritory.territoryid=?'
   BEGIN WORK
   TRY
      PREPARE stmtTerritoryUpdate FROM sqlText
      EXECUTE stmtTerritoryUpdate USING rec.name, rec.countryregioncode, rec.group,
            modifiedAt, rec.territoryid
      COMMIT WORK
   CATCH
      LET messageText = SqlHelper.errorText("Saving territory")
      ROLLBACK WORK
      RETURN FALSE, messageText
   END TRY
   RETURN TRUE, NULL
END FUNCTION

#-------------------------------------------------------------------------------
#+ Delete a territory. One that customers, salespersons or orders still reference
#+ cannot be removed; that comes back as a friendly message, any other SQL error
#+ as the error text.
#+
#+ @param territoryId the territory to delete
#+ @return TRUE, or FALSE with the message for the user
#-------------------------------------------------------------------------------
PUBLIC FUNCTION deleteTerritory(territoryId INTEGER) RETURNS (BOOLEAN, STRING)
   VAR errorCode INTEGER
   VAR messageText STRING
   BEGIN WORK
   TRY
      DELETE FROM salesterritory WHERE salesterritory.territoryid = territoryId
      COMMIT WORK
   CATCH
      LET errorCode = sqlca.sqlcode
      LET messageText = SqlHelper.errorText("Deleting territory")
      ROLLBACK WORK
      IF errorCode = -692 OR errorCode = -691 THEN
         RETURN FALSE, "Cannot delete: this territory is still referenced by other records."
      END IF
      RETURN FALSE, messageText
   END TRY
   RETURN TRUE, NULL
END FUNCTION
