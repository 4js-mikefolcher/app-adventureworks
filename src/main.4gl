################################################################################
# main.4gl - entry point for the AdventureWorks Sales management application.
#
# Connects to the database, opens the main navigation window, and routes the
# user to each Sales-domain module. Each domain module exposes one public
# *_run() entry function. The database is assumed to already exist and be
# populated (built by the separate fgl-adventureworks tool).
################################################################################

IMPORT FGL lib_aw
IMPORT FGL salesorders
IMPORT FGL customers
IMPORT FGL salespersons
IMPORT FGL territories
IMPORT FGL specialoffers

MAIN
    DEFER INTERRUPT

    IF NOT aw_connect() THEN
        EXIT PROGRAM 1
    END IF

    CALL ui.Interface.setText("AdventureWorks Sales")

    OPEN WINDOW w_main WITH FORM "main" ATTRIBUTES(TEXT = "AdventureWorks Sales")

    MENU "Sales"
        ON ACTION orders
            CALL salesorders_run()
        ON ACTION customers
            CALL customers_run()
        ON ACTION salespersons
            CALL salespersons_run()
        ON ACTION territories
            CALL territories_run()
        ON ACTION offers
            CALL specialoffers_run()
        ON ACTION quit
            EXIT MENU
        ON ACTION close
            EXIT MENU
    END MENU

    CLOSE WINDOW w_main
    CALL aw_disconnect()
END MAIN
