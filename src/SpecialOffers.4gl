################################################################################
# SpecialOffers.4gl - browse and maintain promotions (specialoffer).
#
# Same "modifiable list" pattern as Territories. specialoffer has a column
# literally named "type" (a reserved word), mapped here to the record member
# "offerType" and quoted in SQL.
#
# Public entry: specialOffersRun()
################################################################################

IMPORT security

IMPORT FGL LibAw
IMPORT FGL AwCalc

#+ One special-offer row. "offerType" maps to the SQL column "type".
PRIVATE TYPE tOffer RECORD
   specialOfferId INTEGER,
   description    VARCHAR(255),
   discountPct    DECIMAL(10,4),
   offerType      VARCHAR(50),
   category       VARCHAR(50),
   startDate      DATE,
   endDate        DATE,
   minQty         INTEGER,
   maxQty         INTEGER
END RECORD

PRIVATE DEFINE offerList DYNAMIC ARRAY OF tOffer

#-------------------------------------------------------------------------------
#+ Open the special-offers window and run the browse/maintain dialog.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION specialOffersRun() RETURNS ()
   OPEN WINDOW wOffers WITH FORM "SpecialOffers"
      ATTRIBUTES(TEXT = "Special Offers", STYLE = "dialog")
   CALL loadOffers()
   CALL browseOffers()
   CLOSE WINDOW wOffers
END FUNCTION

#-------------------------------------------------------------------------------
#+ Load all special offers, newest start date first.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION loadOffers() RETURNS ()
   VAR rec tOffer
   VAR sqlText STRING
   LET sqlText =
      'SELECT specialofferid, description, discountpct, "type", category,'
      || ' startdate, enddate, minqty, maxqty'
      || ' FROM specialoffer ORDER BY startdate DESC, specialofferid'
   CALL offerList.clear()
   DECLARE cursOffers CURSOR FROM sqlText
   FOREACH cursOffers INTO rec.*
      LET offerList[offerList.getLength() + 1] = rec
   END FOREACH
END FUNCTION

#-------------------------------------------------------------------------------
#+ Browse dialog with inline add / edit / delete.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION browseOffers() RETURNS ()
   VAR rec tOffer
   DISPLAY ARRAY offerList TO srOffers.* ATTRIBUTES(DOUBLECLICK = update, UNBUFFERED)

      ON UPDATE
         LET rec = offerList[arr_curr()]
         IF inputOffer(scr_line(), rec) THEN
            IF saveOffer(FALSE, rec) THEN
               LET offerList[arr_curr()] = rec
            END IF
         END IF

      ON APPEND
         CALL defaultOffer(rec)
         IF inputOffer(scr_line(), rec) THEN
            IF saveOffer(TRUE, rec) THEN
               LET offerList[arr_curr()] = rec
            ELSE
               CALL offerList.deleteElement(arr_curr())
            END IF
         ELSE
            CALL offerList.deleteElement(arr_curr())
         END IF

      ON ACTION remove ATTRIBUTES(TEXT = "Delete", IMAGE = "fa-trash")
         IF offerList.getLength() > 0 THEN
            IF LibAw.awConfirm("Delete offer",
                  SFMT("Delete special offer '%1'?", offerList[arr_curr()].description)) THEN
               IF deleteOffer(offerList[arr_curr()].specialOfferId) THEN
                  CALL offerList.deleteElement(arr_curr())
               END IF
            END IF
         END IF

   END DISPLAY
END FUNCTION

#-------------------------------------------------------------------------------
#+ Sensible defaults for a new offer.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION defaultOffer(rec tOffer INOUT) RETURNS ()
   INITIALIZE rec.* TO NULL
   LET rec.discountPct = 0
   LET rec.minQty = 0
   LET rec.startDate = TODAY
   LET rec.endDate = TODAY
END FUNCTION

#-------------------------------------------------------------------------------
#+ Inline edit of one offer's editable columns. Validates the date range.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION inputOffer(line INTEGER, rec tOffer INOUT) RETURNS BOOLEAN
   LET int_flag = FALSE
   INPUT rec.description, rec.discountPct, rec.offerType, rec.category,
         rec.startDate, rec.endDate, rec.minQty, rec.maxQty
      FROM srOffers[line].description, srOffers[line].discountPct,
         srOffers[line].offerType, srOffers[line].category,
         srOffers[line].startDate, srOffers[line].endDate,
         srOffers[line].minQty, srOffers[line].maxQty
      ATTRIBUTES(WITHOUT DEFAULTS)
      AFTER INPUT
         IF NOT int_flag THEN
            IF NOT AwCalc.awValidDateRange(rec.startDate, rec.endDate) THEN
               ERROR "End date must be on or after the start date."
               NEXT FIELD endDate
            END IF
            IF rec.maxQty IS NOT NULL AND rec.maxQty < rec.minQty THEN
               ERROR "Max quantity cannot be less than min quantity."
               NEXT FIELD maxQty
            END IF
         END IF
   END INPUT
   RETURN (NOT int_flag)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Persist an offer. On insert, omit the serial key and read the new id back.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION saveOffer(isNew BOOLEAN, rec tOffer INOUT) RETURNS BOOLEAN
   VAR sqlText STRING
   VAR modifiedAt DATETIME YEAR TO SECOND
   VAR rowGuid VARCHAR(36)
   LET modifiedAt = CURRENT YEAR TO SECOND
   BEGIN WORK
   TRY
      IF isNew THEN
         LET rowGuid = security.RandomGenerator.CreateUUIDString()
         LET sqlText =
            'INSERT INTO specialoffer'
            || ' (description, discountpct, "type", category, startdate, enddate,'
            || '  minqty, maxqty, rowguid, modifieddate)'
            || ' VALUES (?,?,?,?,?,?,?,?,?,?)'
         PREPARE stmtOfferInsert FROM sqlText
         EXECUTE stmtOfferInsert USING rec.description, rec.discountPct, rec.offerType,
               rec.category, rec.startDate, rec.endDate,
               rec.minQty, rec.maxQty, rowGuid, modifiedAt
         LET rec.specialOfferId = sqlca.sqlerrd[2]
      ELSE
         LET sqlText =
            'UPDATE specialoffer'
            || ' SET description=?, discountpct=?, "type"=?, category=?,'
            || '     startdate=?, enddate=?, minqty=?, maxqty=?, modifieddate=?'
            || ' WHERE specialofferid=?'
         PREPARE stmtOfferUpdate FROM sqlText
         EXECUTE stmtOfferUpdate USING rec.description, rec.discountPct, rec.offerType,
               rec.category, rec.startDate, rec.endDate,
               rec.minQty, rec.maxQty, modifiedAt, rec.specialOfferId
      END IF
      COMMIT WORK
   CATCH
      ROLLBACK WORK
      CALL LibAw.awSqlError("Saving special offer")
      RETURN FALSE
   END TRY
   RETURN TRUE
END FUNCTION

#-------------------------------------------------------------------------------
#+ Delete an offer. An offer referenced by order details or eligible products
#+ cannot be removed.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION deleteOffer(specialOfferId INTEGER) RETURNS BOOLEAN
   BEGIN WORK
   TRY
      DELETE FROM specialoffer WHERE specialoffer.specialofferid = specialOfferId
      COMMIT WORK
   CATCH
      ROLLBACK WORK
      IF sqlca.sqlcode = -692 OR sqlca.sqlcode = -691 THEN
         ERROR "Cannot delete: this offer is still referenced by other records."
      ELSE
         CALL LibAw.awSqlError("Deleting special offer")
      END IF
      RETURN FALSE
   END TRY
   RETURN TRUE
END FUNCTION
