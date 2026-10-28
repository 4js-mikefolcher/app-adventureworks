################################################################################
# SalesPersons.4gl - browse and maintain sales people (salesperson).
#
# A salesperson row corresponds to an existing employee (businessentityid is
# both PK and FK), so adding one is outside the Sales scope and not offered.
# Editable attributes: territory, quota, bonus, commission. The YTD figure is a
# system-maintained aggregate, shown read-only. Names resolve via person.
#
# Public entry: salesPersonsRun()
################################################################################

IMPORT FGL LibAw

PRIVATE TYPE tSalesPerson RECORD
   businessEntityId INTEGER,
   salesPersonName  VARCHAR(120),
   territoryId      INTEGER,
   salesQuota       DECIMAL(20,4),
   bonus            DECIMAL(20,4),
   commissionPct    DECIMAL(10,4),
   salesYtd         DECIMAL(20,4)
END RECORD

PRIVATE DEFINE salesPersonList DYNAMIC ARRAY OF tSalesPerson

#-------------------------------------------------------------------------------
#+ Open the sales-persons window and run the browse/maintain dialog.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION salesPersonsRun() RETURNS ()
   OPEN WINDOW wSalesPersons WITH FORM "SalesPersons"
      ATTRIBUTES(TEXT = "Sales Persons", STYLE = "dialog")
   CALL LibAw.awFillComboBox("territoryId",
      "SELECT territoryid, name FROM salesterritory ORDER BY name")
   CALL loadSalesPersons()
   CALL browseSalesPersons()
   CLOSE WINDOW wSalesPersons
END FUNCTION

#-------------------------------------------------------------------------------
#+ Load all sales people with their resolved names, ordered by name.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION loadSalesPersons() RETURNS ()
   VAR rec tSalesPerson
   VAR sqlText STRING
   LET sqlText =
      "SELECT salesperson.businessentityid,"
      || " TRIM(person.lastname) || ', ' || TRIM(person.firstname),"
      || " salesperson.territoryid, salesperson.salesquota, salesperson.bonus,"
      || " salesperson.commissionpct, salesperson.salesytd"
      || " FROM salesperson"
      || " LEFT JOIN person ON person.businessentityid = salesperson.businessentityid"
      || " ORDER BY 2"
   CALL salesPersonList.clear()
   DECLARE cursSalesPersons CURSOR FROM sqlText
   FOREACH cursSalesPersons INTO rec.*
      LET salesPersonList[salesPersonList.getLength() + 1] = rec
   END FOREACH
END FUNCTION

#-------------------------------------------------------------------------------
#+ Browse dialog: inline edit of territory / quota / bonus / commission; delete.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION browseSalesPersons() RETURNS ()
   VAR rec tSalesPerson
   DISPLAY ARRAY salesPersonList TO srSalesPersons.* ATTRIBUTES(DOUBLECLICK = update, UNBUFFERED)

      ON UPDATE
         LET rec = salesPersonList[arr_curr()]
         IF inputSalesPerson(scr_line(), rec) THEN
            IF saveSalesPerson(rec) THEN
               LET salesPersonList[arr_curr()] = rec
            END IF
         END IF

      ON ACTION remove ATTRIBUTES(TEXT = "Delete", IMAGE = "fa-trash")
         IF salesPersonList.getLength() > 0 THEN
            IF LibAw.awConfirm("Delete sales person",
                  SFMT("Delete sales person %1?", salesPersonList[arr_curr()].salesPersonName)) THEN
               IF deleteSalesPerson(salesPersonList[arr_curr()].businessEntityId) THEN
                  CALL salesPersonList.deleteElement(arr_curr())
               END IF
            END IF
         END IF

   END DISPLAY
END FUNCTION

#-------------------------------------------------------------------------------
#+ Inline edit of the editable salesperson columns, with non-negative checks.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION inputSalesPerson(line INTEGER, rec tSalesPerson INOUT) RETURNS BOOLEAN
   LET int_flag = FALSE
   INPUT rec.territoryId, rec.salesQuota, rec.bonus, rec.commissionPct
      FROM srSalesPersons[line].territoryId, srSalesPersons[line].salesQuota,
         srSalesPersons[line].bonus, srSalesPersons[line].commissionPct
      ATTRIBUTES(WITHOUT DEFAULTS)
      AFTER INPUT
         IF NOT int_flag THEN
            IF rec.bonus < 0 OR rec.commissionPct < 0
               OR (rec.salesQuota IS NOT NULL AND rec.salesQuota < 0) THEN
               ERROR "Quota, bonus and commission must not be negative."
               NEXT FIELD bonus
            END IF
         END IF
   END INPUT
   RETURN (NOT int_flag)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Persist the editable salesperson attributes.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION saveSalesPerson(rec tSalesPerson INOUT) RETURNS BOOLEAN
   VAR modifiedAt DATETIME YEAR TO SECOND
   LET modifiedAt = CURRENT YEAR TO SECOND
   BEGIN WORK
   TRY
      UPDATE salesperson
         SET territoryid = rec.territoryId, salesquota = rec.salesQuota,
            bonus = rec.bonus, commissionpct = rec.commissionPct,
            modifieddate = modifiedAt
         WHERE salesperson.businessentityid = rec.businessEntityId
      COMMIT WORK
   CATCH
      ROLLBACK WORK
      CALL LibAw.awSqlError("Saving sales person")
      RETURN FALSE
   END TRY
   RETURN TRUE
END FUNCTION

#-------------------------------------------------------------------------------
#+ Delete a salesperson. Usually blocked by orders / history references.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION deleteSalesPerson(entityId INTEGER) RETURNS BOOLEAN
   BEGIN WORK
   TRY
      DELETE FROM salesperson WHERE salesperson.businessentityid = entityId
      COMMIT WORK
   CATCH
      ROLLBACK WORK
      IF sqlca.sqlcode = -692 OR sqlca.sqlcode = -691 THEN
         ERROR "Cannot delete: this sales person is referenced by orders or history."
      ELSE
         CALL LibAw.awSqlError("Deleting sales person")
      END IF
      RETURN FALSE
   END TRY
   RETURN TRUE
END FUNCTION
