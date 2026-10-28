################################################################################
# TerritoriesLookup.4gl - lookup that fills comboboxes with the sales territories.
#
# A lookup is a controller helper: any controller may import it, a model never does.
# It is a leaf (it imports no application module). Each function takes the combobox
# as a parameter and fills it, so the controller finds the combobox by its form field
# name and passes it in. The cursor is declared lazily, on the first call, and lives
# as long as the database connection.
################################################################################

SCHEMA adventureworks

#+ One combobox entry: the value the field stores and the text the user sees.
PRIVATE TYPE tTerritoryItem RECORD
   territoryId   INTEGER,
   territoryName STRING
END RECORD

PRIVATE DEFINE declared BOOLEAN

#-------------------------------------------------------------------------------
#+ Fill a combobox with the sales territories ordered by name, replacing what it
#+ held. The stored value is the territory id.
#+
#+ @param comboBox the combobox to fill, found by the caller by its field name
#-------------------------------------------------------------------------------
PUBLIC FUNCTION fillTerritories(comboBox ui.ComboBox) RETURNS ()
   VAR item tTerritoryItem
   IF NOT declared THEN
      DECLARE cursTerritoryItems CURSOR FOR
         SELECT salesterritory.territoryid, salesterritory.name
            FROM salesterritory
            ORDER BY salesterritory.name
      LET declared = TRUE
   END IF
   CALL comboBox.clear()
   FOREACH cursTerritoryItems INTO item.*
      CALL comboBox.addItem(item.territoryId, item.territoryName)
   END FOREACH
END FUNCTION
