################################################################################
# ProductsLookup.4gl - lookup that fills comboboxes with the products for sale.
#
# A lookup is a controller helper: any controller may import it, a model never does.
# It is a leaf (it imports no application module), and it exists for data that has no
# feature of its own in this application. The function takes the combobox as a
# parameter and fills it, so the controller finds the combobox by its form field name
# and passes it in. The cursor is declared lazily, on the first call, and lives as
# long as the database connection.
################################################################################

SCHEMA adventureworks

#+ One combobox entry: the value the field stores and the text the user sees.
PRIVATE TYPE tProductItem RECORD
   productId   INTEGER,
   productName STRING
END RECORD

PRIVATE DEFINE declared BOOLEAN

#-------------------------------------------------------------------------------
#+ Fill a combobox with the products that can be sold, ordered by name, replacing
#+ what it held. Only products present in specialofferproduct can appear on an order
#+ line: salesorderdetail has a composite foreign key on (specialofferid, productid)
#+ into specialofferproduct. The stored value is the product id.
#+
#+ @param comboBox the combobox to fill, found by the caller by its field name
#-------------------------------------------------------------------------------
PUBLIC FUNCTION fillProducts(comboBox ui.ComboBox) RETURNS ()
   VAR item tProductItem
   IF NOT declared THEN
      DECLARE cursProductItems CURSOR FOR
         SELECT DISTINCT product.productid, product.name
            FROM product
            INNER JOIN specialofferproduct ON specialofferproduct.productid = product.productid
            ORDER BY product.name
      LET declared = TRUE
   END IF
   CALL comboBox.clear()
   FOREACH cursProductItems INTO item.*
      CALL comboBox.addItem(item.productId, item.productName)
   END FOREACH
END FUNCTION
