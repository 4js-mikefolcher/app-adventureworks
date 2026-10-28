################################################################################
# LibAw.4gl - database connection for the AdventureWorks Sales application.
#
# What is left of the original shared library once every feature was split into
# model, controller and view (the other services moved to the helpers, the lookups
# and the models). It is used only by the entry module, and goes away when that is
# migrated to MainController.
#
# No MAIN: this is a library module, imported with IMPORT FGL LibAw.
################################################################################

#+ Database source name. Matches the FGLPROFILE entry in res/fglprofile.pgs and
#+ the schema file adventureworks.sch.
PUBLIC CONSTANT cAwDbName = "adventureworks"

#-------------------------------------------------------------------------------
#+ Connect to the AdventureWorks database. Credentials come from FGLPROFILE
#+ (res/fglprofile.pgs). Returns TRUE on success; on failure reports the error
#+ and returns FALSE so the caller can abort.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION awConnect() RETURNS BOOLEAN
   TRY
      CONNECT TO cAwDbName
   CATCH
      CALL awSqlError(SFMT("Connection to '%1' failed", cAwDbName))
      RETURN FALSE
   END TRY
   RETURN TRUE
END FUNCTION

#-------------------------------------------------------------------------------
#+ Close the current database connection (best-effort).
#-------------------------------------------------------------------------------
PUBLIC FUNCTION awDisconnect() RETURNS ()
   WHENEVER ANY ERROR CONTINUE
   DISCONNECT CURRENT
   WHENEVER ANY ERROR STOP
END FUNCTION

#-------------------------------------------------------------------------------
#+ Report an SQL error to the user, prefixed with a caller-supplied context.
#+ Reads sqlca.sqlcode and the last SQL error message; safe to call right after
#+ a CATCH.
#+
#+ @param operation human description of the operation that failed
#-------------------------------------------------------------------------------
PUBLIC FUNCTION awSqlError(operation STRING) RETURNS ()
   VAR code INTEGER = sqlca.sqlcode
   ERROR SFMT("%1: SQL error %2 - %3", operation, code, SQLERRMESSAGE)
END FUNCTION
