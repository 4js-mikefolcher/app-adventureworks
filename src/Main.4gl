################################################################################
# Main.4gl - entry point for the AdventureWorks Sales management application.
#
# Connects to the database, opens the main navigation window, and routes the
# user to each Sales-domain module. Each domain module exposes one public
# *Run() entry function. The database is assumed to already exist and be
# populated (built by the separate fgl-adventureworks tool).
################################################################################

IMPORT FGL LibAw
IMPORT FGL SalesOrdersController
IMPORT FGL CustomersController
IMPORT FGL SalesPersonsController
IMPORT FGL TerritoriesController
IMPORT FGL SpecialOffersController

MAIN
   DEFER INTERRUPT

   IF NOT LibAw.awConnect() THEN
      EXIT PROGRAM 1
   END IF

   CALL ui.Interface.setText("AdventureWorks Sales")

   OPEN WINDOW wMain WITH FORM "Main" ATTRIBUTES(TEXT = "AdventureWorks Sales")

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

   CLOSE WINDOW wMain
   CALL LibAw.awDisconnect()
END MAIN
