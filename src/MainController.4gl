################################################################################
# MainController.4gl - entry point of the AdventureWorks Sales application.
#
# The program entry module (never called Main.4gl, so that the module name cannot be
# confused with the MAIN block). It does startup only: the database connection and the
# application title, then it hands over to the application menu, MainMenuController,
# and closes the connection when the menu returns. It holds no feature logic and no data
# access. The database is assumed to already exist and be populated (built by the
# separate fgl-adventureworks tool).
#
# The connection is made once and kept for the life of the program: the lookups declare
# their cursors lazily and those cursors live as long as the connection.
################################################################################

IMPORT FGL MainMenuController
IMPORT FGL SqlHelper

#+ Database source name. Matches the FGLPROFILE entry in res/fglprofile.pgs and
#+ the schema file adventureworks.sch.
PRIVATE CONSTANT cDbName = "adventureworks"

MAIN
   DEFER INTERRUPT

   IF NOT connectDatabase() THEN
      EXIT PROGRAM 1
   END IF

   CALL ui.Interface.setText("AdventureWorks Sales")

   CALL MainMenuController.mainMenuRun()

   CALL disconnectDatabase()
END MAIN

#-------------------------------------------------------------------------------
#+ Connect to the AdventureWorks database. Credentials come from FGLPROFILE
#+ (res/fglprofile.pgs). Returns TRUE on success; on failure shows the error and
#+ returns FALSE so the program can stop.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION connectDatabase() RETURNS BOOLEAN
   TRY
      CONNECT TO cDbName
   CATCH
      ERROR SqlHelper.errorText(SFMT("Connection to '%1' failed", cDbName))
      RETURN FALSE
   END TRY
   RETURN TRUE
END FUNCTION

#-------------------------------------------------------------------------------
#+ Close the current database connection (best-effort).
#-------------------------------------------------------------------------------
PRIVATE FUNCTION disconnectDatabase() RETURNS ()
   WHENEVER ANY ERROR CONTINUE
   DISCONNECT CURRENT
   WHENEVER ANY ERROR STOP
END FUNCTION
