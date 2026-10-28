################################################################################
# SpecialOffersLookup.4gl - lookup that fills comboboxes with the special offers.
#
# A lookup is a controller helper: any controller may import it, a model never does.
# It is a leaf (it imports no application module). The function takes the combobox as
# a parameter and fills it, so the controller finds the combobox by its form field name
# and passes it in. The cursor is declared lazily, on the first call, and lives as
# long as the database connection.
################################################################################

SCHEMA adventureworks

#+ One combobox entry: the value the field stores and the text the user sees.
PRIVATE TYPE tOfferItem RECORD
   specialOfferId   INTEGER,
   offerDescription STRING
END RECORD

PRIVATE DEFINE declared BOOLEAN

#-------------------------------------------------------------------------------
#+ Fill a combobox with the special offers ordered by id, replacing what it held.
#+ The stored value is the special offer id.
#+
#+ @param comboBox the combobox to fill, found by the caller by its field name
#-------------------------------------------------------------------------------
PUBLIC FUNCTION fillSpecialOffers(comboBox ui.ComboBox) RETURNS ()
   VAR item tOfferItem
   IF NOT declared THEN
      DECLARE cursOfferItems CURSOR FOR
         SELECT specialoffer.specialofferid, specialoffer.description
            FROM specialoffer
            ORDER BY specialoffer.specialofferid
      LET declared = TRUE
   END IF
   CALL comboBox.clear()
   FOREACH cursOfferItems INTO item.*
      CALL comboBox.addItem(item.specialOfferId, item.offerDescription)
   END FOREACH
END FUNCTION
