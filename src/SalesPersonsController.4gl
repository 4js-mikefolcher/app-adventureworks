################################################################################
# SalesPersonsController.4gl - browse and maintain sales people.
#
# Read-only list with inline edit of territory / quota / bonus / commission and
# delete. The controller owns the dialogs, the user flow and the SELECT that fills
# the list (names resolve through person); the validation and every write go through
# SalesPersonsModel, and the territory combobox is filled by TerritoriesLookup. The
# view record adds the resolved name, so toDbSalesPerson converts to the database
# record.
#
# Public entry: salesPersonsRun()
################################################################################

IMPORT util

IMPORT FGL DialogHelper
IMPORT FGL SalesPersonsModel
IMPORT FGL TerritoriesLookup

#+ The view record: one salesperson row as shown and edited in the list. The name is
#+ resolved from person for display only; the JSON bridge ignores it. The YTD figure
#+ is system-maintained and shown read-only.
PUBLIC TYPE tSalesPersonView RECORD
   businessEntityId INTEGER,
   salesPersonName  VARCHAR(120),
   territoryId      INTEGER,
   salesQuota       DECIMAL(20,4),
   bonus            DECIMAL(20,4),
   commissionPct    DECIMAL(10,4),
   salesYtd         DECIMAL(20,4)
END RECORD

PRIVATE DEFINE salesPersonList DYNAMIC ARRAY OF tSalesPersonView

#-------------------------------------------------------------------------------
#+ View record to database record. The JSON bridge copies every member whose name
#+ matches a column (case-insensitive), ignores salesPersonName, and sets the columns
#+ the view does not carry to NULL, so the model's UPDATE names the columns it writes.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION toDbSalesPerson(viewRec tSalesPersonView) RETURNS SalesPersonsModel.tSalesPerson
   VAR dbRec SalesPersonsModel.tSalesPerson
   CALL util.JSONObject.fromFGL(viewRec).toFGL(dbRec)
   RETURN dbRec
END FUNCTION

#-------------------------------------------------------------------------------
#+ Open the sales-persons window and run the browse/maintain dialog.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION salesPersonsRun() RETURNS ()
   OPEN WINDOW wSalesPersons WITH FORM "SalesPersons"
      ATTRIBUTES(TEXT = "Sales Persons", STYLE = "dialog")
   CALL TerritoriesLookup.fillTerritories(ui.ComboBox.forName("territoryId"))
   CALL loadSalesPersons()
   CALL browseSalesPersons()
   CLOSE WINDOW wSalesPersons
END FUNCTION

#-------------------------------------------------------------------------------
#+ Load all sales people with their resolved names, ordered by name. The column list
#+ follows tSalesPersonView member for member.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION loadSalesPersons() RETURNS ()
   VAR rec tSalesPersonView
   CALL salesPersonList.clear()
   DECLARE cursSalesPersons CURSOR FOR
      SELECT salesperson.businessentityid,
            TRIM(person.lastname) || ', ' || TRIM(person.firstname),
            salesperson.territoryid, salesperson.salesquota, salesperson.bonus,
            salesperson.commissionpct, salesperson.salesytd
         FROM salesperson
         LEFT JOIN person ON person.businessentityid = salesperson.businessentityid
         ORDER BY 2
   FOREACH cursSalesPersons INTO rec.*
      LET salesPersonList[salesPersonList.getLength() + 1] = rec
   END FOREACH
END FUNCTION

#-------------------------------------------------------------------------------
#+ Browse dialog: inline edit of territory / quota / bonus / commission; delete.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION browseSalesPersons() RETURNS ()
   VAR rec tSalesPersonView
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
            IF DialogHelper.confirm("Delete sales person",
                  SFMT("Delete sales person %1?", salesPersonList[arr_curr()].salesPersonName)) THEN
               IF removeSalesPerson(salesPersonList[arr_curr()].businessEntityId) THEN
                  CALL salesPersonList.deleteElement(arr_curr())
               END IF
            END IF
         END IF

   END DISPLAY
END FUNCTION

#-------------------------------------------------------------------------------
#+ Inline edit of the editable salesperson columns. The model validates; the
#+ controller shows the message and picks the field.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION inputSalesPerson(line INTEGER, rec tSalesPersonView INOUT) RETURNS BOOLEAN
   VAR valid BOOLEAN
   VAR messageText STRING
   LET int_flag = FALSE
   INPUT rec.territoryId, rec.salesQuota, rec.bonus, rec.commissionPct
      FROM srSalesPersons[line].territoryId, srSalesPersons[line].salesQuota,
         srSalesPersons[line].bonus, srSalesPersons[line].commissionPct
      ATTRIBUTES(WITHOUT DEFAULTS)
      AFTER INPUT
         IF NOT int_flag THEN
            CALL SalesPersonsModel.validateSalesPerson(toDbSalesPerson(rec))
               RETURNING valid, messageText
            IF NOT valid THEN
               ERROR messageText
               NEXT FIELD bonus
            END IF
         END IF
   END INPUT
   RETURN (NOT int_flag)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Persist the editable salesperson attributes through the model and show its error,
#+ if any. Returns TRUE on success.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION saveSalesPerson(rec tSalesPersonView INOUT) RETURNS BOOLEAN
   VAR saved BOOLEAN
   VAR messageText STRING
   CALL SalesPersonsModel.updateSalesPerson(toDbSalesPerson(rec)) RETURNING saved, messageText
   IF NOT saved THEN
      ERROR messageText
   END IF
   RETURN saved
END FUNCTION

#-------------------------------------------------------------------------------
#+ Delete a salesperson through the model and show its message, if any. Returns TRUE
#+ when the row was removed.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION removeSalesPerson(entityId INTEGER) RETURNS BOOLEAN
   VAR removed BOOLEAN
   VAR messageText STRING
   CALL SalesPersonsModel.deleteSalesPerson(entityId) RETURNING removed, messageText
   IF NOT removed THEN
      ERROR messageText
   END IF
   RETURN removed
END FUNCTION
