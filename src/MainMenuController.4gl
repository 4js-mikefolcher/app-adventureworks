################################################################################
# MainMenuController.4gl - the application menu of the AdventureWorks Sales app.
#
# Opens the main navigation window and routes the user to each feature. It is the one
# controller that may import the other features' controllers, and only to call their
# entry functions: each feature controller exposes one public *Run() function. It holds
# no feature logic and no data access, so it has no model. The view is MainMenu.per.
#
# Public entry: mainMenuRun()
################################################################################

IMPORT FGL CustomersController
IMPORT FGL SalesOrdersController
IMPORT FGL SalesPersonsController
IMPORT FGL SpecialOffersController
IMPORT FGL TerritoriesController

#-------------------------------------------------------------------------------
#+ Open the main window and run the menu until the user quits or closes it.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION mainMenuRun() RETURNS ()
   OPEN WINDOW wMainMenu WITH FORM "MainMenu" ATTRIBUTES(TEXT = "AdventureWorks Sales")

   LET int_flag = FALSE
   MENU "Sales"
      ON ACTION orders
         CALL SalesOrdersController.salesOrdersRun()
      ON ACTION customers
         CALL CustomersController.customersRun()
      ON ACTION salespersons
         CALL SalesPersonsController.salesPersonsRun()
      ON ACTION territories
         CALL TerritoriesController.territoriesRun()
      ON ACTION offers
         CALL SpecialOffersController.specialOffersRun()
      ON ACTION quit
         EXIT MENU
      ON ACTION close
         EXIT MENU
   END MENU

   CLOSE WINDOW wMainMenu
END FUNCTION
