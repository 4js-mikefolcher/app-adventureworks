################################################################################
# DialogHelper.4gl - helper for dialogs shared by the controllers.
#
# A helper is a leaf: it imports no application module and knows nothing about
# any feature. Controllers import it; models never do, because it has UI.
################################################################################

#-------------------------------------------------------------------------------
#+ Modal yes/no confirmation. Returns TRUE only if the user picks "Yes".
#+
#+ @param dialogTitle dialog title
#+ @param question    confirmation question shown in the dialog body
#-------------------------------------------------------------------------------
PUBLIC FUNCTION confirm(dialogTitle STRING, question STRING) RETURNS BOOLEAN
   VAR confirmed BOOLEAN = FALSE
   LET int_flag = FALSE
   MENU dialogTitle ATTRIBUTES(STYLE = "dialog", COMMENT = question, IMAGE = "fa-question-circle")
      COMMAND "No"
         LET confirmed = FALSE
      COMMAND "Yes"
         LET confirmed = TRUE
   END MENU
   RETURN confirmed
END FUNCTION
