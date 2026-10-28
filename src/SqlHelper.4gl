################################################################################
# SqlHelper.4gl - helper for SQL error text, shared by the data models.
#
# A helper is a leaf: it imports no application module and knows nothing about
# any feature. It has no UI, so the models may import it; the controller shows
# the text the model returns.
################################################################################

#-------------------------------------------------------------------------------
#+ Build the user-facing text for the SQL error that was just raised, prefixed
#+ with a caller-supplied context. Reads sqlca.sqlcode and the SQL error message,
#+ so call it inside the CATCH block before ROLLBACK WORK, which resets both.
#+
#+ @param operation human description of the operation that failed
#+ @return the error text, for example "Saving territory: SQL error -691 - ..."
#-------------------------------------------------------------------------------
PUBLIC FUNCTION errorText(operation STRING) RETURNS STRING
   VAR errorCode INTEGER = sqlca.sqlcode
   RETURN SFMT("%1: SQL error %2 - %3", operation, errorCode, SQLERRMESSAGE)
END FUNCTION
