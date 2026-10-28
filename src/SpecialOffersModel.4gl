################################################################################
# SpecialOffersModel.4gl - data model for promotions (specialoffer).
#
# Owns the database record, the business-rule validation and the data changes
# (insert, update, delete), each in its own transaction. No UI: success or failure
# goes back to the controller as return values, and the controller shows the
# message. specialoffer has a column literally named "type" (a reserved word), so
# the SQL below is dynamic and quotes the identifier.
################################################################################

IMPORT security

IMPORT FGL SqlHelper

SCHEMA adventureworks

#+ The database record: one row of specialoffer, as the model reads and writes it.
PUBLIC TYPE tOffer RECORD LIKE specialoffer.*

#-------------------------------------------------------------------------------
#+ TRUE when the date range is valid: an open end (NULL) is allowed, otherwise the
#+ end must be on or after the start. A NULL start with a non-NULL end is invalid.
#+
#+ @param rec the offer to check (startdate, enddate)
#+ @return TRUE, or FALSE with the message for the user
#-------------------------------------------------------------------------------
PUBLIC FUNCTION validateOfferDates(rec tOffer) RETURNS (BOOLEAN, STRING)
   IF rec.enddate IS NOT NULL THEN
      IF rec.startdate IS NULL OR rec.enddate < rec.startdate THEN
         RETURN FALSE, "End date must be on or after the start date."
      END IF
   END IF
   RETURN TRUE, NULL
END FUNCTION

#-------------------------------------------------------------------------------
#+ TRUE when the quantity range is valid: an open max is allowed, otherwise the
#+ max must not be below the min.
#+
#+ @param rec the offer to check (minqty, maxqty)
#+ @return TRUE, or FALSE with the message for the user
#-------------------------------------------------------------------------------
PUBLIC FUNCTION validateOfferQuantities(rec tOffer) RETURNS (BOOLEAN, STRING)
   IF rec.maxqty IS NOT NULL AND rec.maxqty < rec.minqty THEN
      RETURN FALSE, "Max quantity cannot be less than min quantity."
   END IF
   RETURN TRUE, NULL
END FUNCTION

#-------------------------------------------------------------------------------
#+ Insert a new offer. The serial key is omitted and read back; the row guid and
#+ modified date are set here.
#+
#+ @param rec the offer to insert
#+ @return TRUE and the new special offer id, or FALSE with the error text
#-------------------------------------------------------------------------------
PUBLIC FUNCTION insertOffer(rec tOffer) RETURNS (BOOLEAN, STRING, INTEGER)
   VAR sqlText STRING
   VAR messageText STRING
   VAR modifiedAt DATETIME YEAR TO SECOND = CURRENT YEAR TO SECOND
   VAR rowGuid VARCHAR(36)
   VAR newId INTEGER
   LET sqlText =
      'INSERT INTO specialoffer'
      || ' (description, discountpct, "type", category, startdate, enddate,'
      || '  minqty, maxqty, rowguid, modifieddate)'
      || ' VALUES (?,?,?,?,?,?,?,?,?,?)'
   BEGIN WORK
   TRY
      LET rowGuid = security.RandomGenerator.CreateUUIDString()
      PREPARE stmtOfferInsert FROM sqlText
      EXECUTE stmtOfferInsert USING rec.description, rec.discountpct, rec.type,
            rec.category, rec.startdate, rec.enddate,
            rec.minqty, rec.maxqty, rowGuid, modifiedAt
      LET newId = sqlca.sqlerrd[2]
      COMMIT WORK
   CATCH
      LET messageText = SqlHelper.errorText("Saving special offer")
      ROLLBACK WORK
      RETURN FALSE, messageText, NULL
   END TRY
   RETURN TRUE, NULL, newId
END FUNCTION

#-------------------------------------------------------------------------------
#+ Update the editable columns of an offer. The statement names its columns, so
#+ the rest of the record is never written.
#+
#+ @param rec the offer to update, identified by its special offer id
#+ @return TRUE, or FALSE with the error text
#-------------------------------------------------------------------------------
PUBLIC FUNCTION updateOffer(rec tOffer) RETURNS (BOOLEAN, STRING)
   VAR sqlText STRING
   VAR messageText STRING
   VAR modifiedAt DATETIME YEAR TO SECOND = CURRENT YEAR TO SECOND
   LET sqlText =
      'UPDATE specialoffer'
      || ' SET description=?, discountpct=?, "type"=?, category=?,'
      || '     startdate=?, enddate=?, minqty=?, maxqty=?, modifieddate=?'
      || ' WHERE specialoffer.specialofferid=?'
   BEGIN WORK
   TRY
      PREPARE stmtOfferUpdate FROM sqlText
      EXECUTE stmtOfferUpdate USING rec.description, rec.discountpct, rec.type,
            rec.category, rec.startdate, rec.enddate,
            rec.minqty, rec.maxqty, modifiedAt, rec.specialofferid
      COMMIT WORK
   CATCH
      LET messageText = SqlHelper.errorText("Saving special offer")
      ROLLBACK WORK
      RETURN FALSE, messageText
   END TRY
   RETURN TRUE, NULL
END FUNCTION

#-------------------------------------------------------------------------------
#+ Delete an offer. One that order details or eligible products still reference
#+ cannot be removed; that comes back as a friendly message, any other SQL error
#+ as the error text.
#+
#+ @param specialOfferId the offer to delete
#+ @return TRUE, or FALSE with the message for the user
#-------------------------------------------------------------------------------
PUBLIC FUNCTION deleteOffer(specialOfferId INTEGER) RETURNS (BOOLEAN, STRING)
   VAR errorCode INTEGER
   VAR messageText STRING
   BEGIN WORK
   TRY
      DELETE FROM specialoffer WHERE specialoffer.specialofferid = specialOfferId
      COMMIT WORK
   CATCH
      LET errorCode = sqlca.sqlcode
      LET messageText = SqlHelper.errorText("Deleting special offer")
      ROLLBACK WORK
      IF errorCode = -692 OR errorCode = -691 THEN
         RETURN FALSE, "Cannot delete: this offer is still referenced by other records."
      END IF
      RETURN FALSE, messageText
   END TRY
   RETURN TRUE, NULL
END FUNCTION
