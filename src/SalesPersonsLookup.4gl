################################################################################
# SalesPersonsLookup.4gl - lookup that fills comboboxes with the sales people.
#
# A lookup is a controller helper: any controller may import it, a model never does.
# It is a leaf (it imports no application module). The function takes the combobox as
# a parameter and fills it, so the controller finds the combobox by its form field name
# and passes it in. The cursor is declared lazily, on the first call, and lives as
# long as the database connection.
################################################################################

SCHEMA adventureworks

#+ One combobox entry: the value the field stores and the text the user sees.
PRIVATE TYPE tSalesPersonItem RECORD
   salesPersonId INTEGER,
   fullName      STRING
END RECORD

PRIVATE DEFINE declared BOOLEAN

#-------------------------------------------------------------------------------
#+ Fill a combobox with the sales people ordered by name ("Last, First"), replacing
#+ what it held. The stored value is the business entity id.
#+
#+ @param comboBox the combobox to fill, found by the caller by its field name
#-------------------------------------------------------------------------------
PUBLIC FUNCTION fillSalesPersons(comboBox ui.ComboBox) RETURNS ()
   VAR item tSalesPersonItem
   IF NOT declared THEN
      DECLARE cursSalesPersonItems CURSOR FOR
         SELECT salesperson.businessentityid,
               TRIM(person.lastname) || ', ' || TRIM(person.firstname)
            FROM salesperson
            INNER JOIN person ON person.businessentityid = salesperson.businessentityid
            ORDER BY person.lastname, person.firstname
      LET declared = TRUE
   END IF
   CALL comboBox.clear()
   FOREACH cursSalesPersonItems INTO item.*
      CALL comboBox.addItem(item.salesPersonId, item.fullName)
   END FOREACH
END FUNCTION
