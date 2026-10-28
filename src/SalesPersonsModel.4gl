################################################################################
# SalesPersonsModel.4gl - data model for sales people (salesperson).
#
# A salesperson row corresponds to an existing employee (businessentityid is both
# primary key and foreign key), so adding one is outside the Sales scope and the
# model has no insert. Editable attributes: territory, quota, bonus, commission.
# The YTD figure is a system-maintained aggregate. Owns the database record, the
# business-rule validation and the data changes (update, delete), each in its own
# transaction. No UI: results go back to the controller as return values.
################################################################################

IMPORT FGL SqlHelper

SCHEMA adventureworks

#+ The database record: one row of salesperson, as the model reads and writes it.
PUBLIC TYPE tSalesPerson RECORD LIKE salesperson.*

#-------------------------------------------------------------------------------
#+ Quota, bonus and commission must not be negative. A NULL quota is allowed.
#+
#+ @param rec the salesperson to check (salesquota, bonus, commissionpct)
#+ @return TRUE, or FALSE with the message for the user
#-------------------------------------------------------------------------------
PUBLIC FUNCTION validateSalesPerson(rec tSalesPerson) RETURNS (BOOLEAN, STRING)
   IF rec.bonus < 0 OR rec.commissionpct < 0
      OR (rec.salesquota IS NOT NULL AND rec.salesquota < 0) THEN
      RETURN FALSE, "Quota, bonus and commission must not be negative."
   END IF
   RETURN TRUE, NULL
END FUNCTION

#-------------------------------------------------------------------------------
#+ Update the editable salesperson attributes. The statement names its columns, so
#+ the rest of the record (the YTD figures, the row guid) is never written.
#+
#+ @param rec the salesperson to update, identified by its business entity id
#+ @return TRUE, or FALSE with the error text
#-------------------------------------------------------------------------------
PUBLIC FUNCTION updateSalesPerson(rec tSalesPerson) RETURNS (BOOLEAN, STRING)
   VAR messageText STRING
   VAR modifiedAt DATETIME YEAR TO SECOND = CURRENT YEAR TO SECOND
   BEGIN WORK
   TRY
      UPDATE salesperson
         SET territoryid = rec.territoryid, salesquota = rec.salesquota,
            bonus = rec.bonus, commissionpct = rec.commissionpct,
            modifieddate = modifiedAt
         WHERE salesperson.businessentityid = rec.businessentityid
      COMMIT WORK
   CATCH
      LET messageText = SqlHelper.errorText("Saving sales person")
      ROLLBACK WORK
      RETURN FALSE, messageText
   END TRY
   RETURN TRUE, NULL
END FUNCTION

#-------------------------------------------------------------------------------
#+ Delete a salesperson. Usually blocked by order and history references; that comes
#+ back as a friendly message, any other SQL error as the error text.
#+
#+ @param entityId the business entity id of the salesperson to delete
#+ @return TRUE, or FALSE with the message for the user
#-------------------------------------------------------------------------------
PUBLIC FUNCTION deleteSalesPerson(entityId INTEGER) RETURNS (BOOLEAN, STRING)
   VAR errorCode INTEGER
   VAR messageText STRING
   BEGIN WORK
   TRY
      DELETE FROM salesperson WHERE salesperson.businessentityid = entityId
      COMMIT WORK
   CATCH
      LET errorCode = sqlca.sqlcode
      LET messageText = SqlHelper.errorText("Deleting sales person")
      ROLLBACK WORK
      IF errorCode = -692 OR errorCode = -691 THEN
         RETURN FALSE, "Cannot delete: this sales person is referenced by orders or history."
      END IF
      RETURN FALSE, messageText
   END TRY
   RETURN TRUE, NULL
END FUNCTION
