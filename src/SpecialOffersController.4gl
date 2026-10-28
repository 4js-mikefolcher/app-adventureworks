################################################################################
# SpecialOffersController.4gl - browse and maintain promotions.
#
# Same "modifiable list" pattern as TerritoriesController. The controller owns the
# dialogs, the user flow and the SELECT that fills the list; the validation and
# every write go through SpecialOffersModel. The view record differs from the
# database record (DATE on the screen, DATETIME in the table, and "offerType" for
# the "type" column), so toDbOffer converts between them.
#
# Public entry: specialOffersRun()
################################################################################

IMPORT util

IMPORT FGL DialogHelper
IMPORT FGL SpecialOffersModel

#+ The view record: one special-offer row as shown and edited in the list. "offerType"
#+ is the specialoffer column "type" (a reserved word), so it carries json_name for the
#+ JSON bridge. The dates are DATEs on the screen; the columns are DATETIMEs.
PUBLIC TYPE tOfferView RECORD
   specialOfferId INTEGER,
   description    VARCHAR(255),
   discountPct    DECIMAL(10,4),
   offerType      VARCHAR(50) ATTRIBUTES(json_name = "type"),
   category       VARCHAR(50),
   startDate      DATE,
   endDate        DATE,
   minQty         INTEGER,
   maxQty         INTEGER
END RECORD

PRIVATE DEFINE offerList DYNAMIC ARRAY OF tOfferView

#-------------------------------------------------------------------------------
#+ View record to database record. The JSON bridge copies every member whose name
#+ matches a column (offerType through its json_name) and sets the columns the view
#+ does not carry to NULL, so the model's statements name the columns they write.
#-------------------------------------------------------------------------------
PUBLIC FUNCTION toDbOffer(viewRec tOfferView) RETURNS SpecialOffersModel.tOffer
   VAR dbRec SpecialOffersModel.tOffer
   CALL util.JSONObject.fromFGL(viewRec).toFGL(dbRec)
   # Special case: the screen holds DATEs but the columns are DATETIMEs, and the bridge
   # turns that mismatch into NULL without an error, so assign these members directly.
   LET dbRec.startdate = viewRec.startDate
   LET dbRec.enddate = viewRec.endDate
   RETURN dbRec
END FUNCTION

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
#+ Load all special offers, newest start date first. The column list follows
#+ tOfferView member for member; "type" is quoted, a reserved word.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION loadOffers() RETURNS ()
   VAR rec tOfferView
   VAR sqlText STRING
   LET sqlText =
      'SELECT specialoffer.specialofferid, specialoffer.description,'
      || ' specialoffer.discountpct, specialoffer."type", specialoffer.category,'
      || ' specialoffer.startdate, specialoffer.enddate,'
      || ' specialoffer.minqty, specialoffer.maxqty'
      || ' FROM specialoffer'
      || ' ORDER BY specialoffer.startdate DESC, specialoffer.specialofferid'
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
   VAR rec tOfferView
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
            IF DialogHelper.confirm("Delete offer",
                  SFMT("Delete special offer '%1'?", offerList[arr_curr()].description)) THEN
               IF removeOffer(offerList[arr_curr()].specialOfferId) THEN
                  CALL offerList.deleteElement(arr_curr())
               END IF
            END IF
         END IF

   END DISPLAY
END FUNCTION

#-------------------------------------------------------------------------------
#+ Sensible defaults for a new offer.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION defaultOffer(rec tOfferView INOUT) RETURNS ()
   INITIALIZE rec.* TO NULL
   LET rec.discountPct = 0
   LET rec.minQty = 0
   LET rec.startDate = TODAY
   LET rec.endDate = TODAY
END FUNCTION

#-------------------------------------------------------------------------------
#+ Inline edit of one offer's editable columns. The model validates the date range
#+ and the quantity range; the controller shows the message and picks the field.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION inputOffer(line INTEGER, rec tOfferView INOUT) RETURNS BOOLEAN
   VAR valid BOOLEAN
   VAR messageText STRING
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
            CALL SpecialOffersModel.validateOfferDates(toDbOffer(rec))
               RETURNING valid, messageText
            IF NOT valid THEN
               ERROR messageText
               NEXT FIELD endDate
            END IF
            CALL SpecialOffersModel.validateOfferQuantities(toDbOffer(rec))
               RETURNING valid, messageText
            IF NOT valid THEN
               ERROR messageText
               NEXT FIELD maxQty
            END IF
         END IF
   END INPUT
   RETURN (NOT int_flag)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Persist an offer through the model and show its error, if any. On insert the
#+ model returns the new serial key, which is stored back into the view record.
#+ Returns TRUE on success.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION saveOffer(isNew BOOLEAN, rec tOfferView INOUT) RETURNS BOOLEAN
   VAR saved BOOLEAN
   VAR messageText STRING
   VAR newId INTEGER
   IF isNew THEN
      CALL SpecialOffersModel.insertOffer(toDbOffer(rec)) RETURNING saved, messageText, newId
      IF saved THEN
         LET rec.specialOfferId = newId
      END IF
   ELSE
      CALL SpecialOffersModel.updateOffer(toDbOffer(rec)) RETURNING saved, messageText
   END IF
   IF NOT saved THEN
      ERROR messageText
   END IF
   RETURN saved
END FUNCTION

#-------------------------------------------------------------------------------
#+ Delete an offer through the model and show its message, if any. Returns TRUE
#+ when the row was removed.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION removeOffer(specialOfferId INTEGER) RETURNS BOOLEAN
   VAR removed BOOLEAN
   VAR messageText STRING
   CALL SpecialOffersModel.deleteOffer(specialOfferId) RETURNING removed, messageText
   IF NOT removed THEN
      ERROR messageText
   END IF
   RETURN removed
END FUNCTION
