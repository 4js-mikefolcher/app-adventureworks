################################################################################
# specialoffers.4gl - browse and maintain promotions (specialoffer).
#
# Same "modifiable list" pattern as territories. specialoffer has a column
# literally named "type" (a reserved word), mapped here to the record member
# "offertype" and quoted in SQL.
#
# Public entry: specialoffers_run()
################################################################################

IMPORT security

IMPORT FGL lib_aw
IMPORT FGL aw_calc

#+ One special-offer row. "offertype" maps to the SQL column "type".
TYPE t_offer RECORD
    specialofferid INTEGER,
    description    VARCHAR(255),
    discountpct    DECIMAL(10,4),
    offertype      VARCHAR(50),
    category       VARCHAR(50),
    startdate      DATE,
    enddate        DATE,
    minqty         INTEGER,
    maxqty         INTEGER
END RECORD

PRIVATE DEFINE m_offer DYNAMIC ARRAY OF t_offer

#-------------------------------------------------------------------------------
#+ Open the special-offers window and run the browse/maintain dialog.
#-------------------------------------------------------------------------------
FUNCTION specialoffers_run()
    OPEN WINDOW w_offer WITH FORM "specialoffers"
        ATTRIBUTES(TEXT = "Special Offers", STYLE = "dialog")
    CALL offer_load()
    CALL offer_browse()
    CLOSE WINDOW w_offer
END FUNCTION

#-------------------------------------------------------------------------------
#+ Load all special offers, newest start date first.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION offer_load()
    DEFINE r t_offer
    DEFINE l_sql STRING
    LET l_sql =
        'SELECT specialofferid, description, discountpct, "type", category,'
        || ' startdate, enddate, minqty, maxqty'
        || ' FROM specialoffer ORDER BY startdate DESC, specialofferid'
    CALL m_offer.clear()
    DECLARE c_offer CURSOR FROM l_sql
    FOREACH c_offer INTO r.*
        LET m_offer[m_offer.getLength() + 1] = r
    END FOREACH
END FUNCTION

#-------------------------------------------------------------------------------
#+ Browse dialog with inline add / edit / delete.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION offer_browse()
    DEFINE rec t_offer
    DISPLAY ARRAY m_offer TO sr_offer.* ATTRIBUTES(DOUBLECLICK = update, UNBUFFERED)

        ON UPDATE
            LET rec = m_offer[arr_curr()]
            IF offer_input(scr_line(), rec) THEN
                IF offer_save(FALSE, rec) THEN
                    LET m_offer[arr_curr()] = rec
                END IF
            END IF

        ON APPEND
            CALL offer_defaults(rec)
            IF offer_input(scr_line(), rec) THEN
                IF offer_save(TRUE, rec) THEN
                    LET m_offer[arr_curr()] = rec
                ELSE
                    CALL m_offer.deleteElement(arr_curr())
                END IF
            ELSE
                CALL m_offer.deleteElement(arr_curr())
            END IF

        ON ACTION remove ATTRIBUTES(TEXT = "Delete", IMAGE = "fa-trash")
            IF m_offer.getLength() > 0 THEN
                IF aw_confirm("Delete offer",
                              SFMT("Delete special offer '%1'?", m_offer[arr_curr()].description)) THEN
                    IF offer_delete(m_offer[arr_curr()].specialofferid) THEN
                        CALL m_offer.deleteElement(arr_curr())
                    END IF
                END IF
            END IF

    END DISPLAY
END FUNCTION

#-------------------------------------------------------------------------------
#+ Sensible defaults for a new offer.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION offer_defaults(rec t_offer INOUT)
    INITIALIZE rec.* TO NULL
    LET rec.discountpct = 0
    LET rec.minqty = 0
    LET rec.startdate = TODAY
    LET rec.enddate = TODAY
END FUNCTION

#-------------------------------------------------------------------------------
#+ Inline edit of one offer's editable columns. Validates the date range.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION offer_input(p_line INTEGER, rec t_offer INOUT) RETURNS BOOLEAN
    LET int_flag = FALSE
    INPUT rec.description, rec.discountpct, rec.offertype, rec.category,
          rec.startdate, rec.enddate, rec.minqty, rec.maxqty
        FROM sr_offer[p_line].description, sr_offer[p_line].discountpct,
             sr_offer[p_line].offertype, sr_offer[p_line].category,
             sr_offer[p_line].startdate, sr_offer[p_line].enddate,
             sr_offer[p_line].minqty, sr_offer[p_line].maxqty
        ATTRIBUTES(WITHOUT DEFAULTS)
        AFTER INPUT
            IF NOT int_flag THEN
                IF NOT aw_calc.aw_valid_date_range(rec.startdate, rec.enddate) THEN
                    ERROR "End date must be on or after the start date."
                    NEXT FIELD enddate
                END IF
                IF rec.maxqty IS NOT NULL AND rec.maxqty < rec.minqty THEN
                    ERROR "Max quantity cannot be less than min quantity."
                    NEXT FIELD maxqty
                END IF
            END IF
    END INPUT
    RETURN (NOT int_flag)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Persist an offer. On insert, omit the serial key and read the new id back.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION offer_save(p_new BOOLEAN, rec t_offer INOUT) RETURNS BOOLEAN
    DEFINE l_sql STRING
    DEFINE l_now DATETIME YEAR TO SECOND
    DEFINE l_uuid VARCHAR(36)
    LET l_now = CURRENT YEAR TO SECOND
    BEGIN WORK
    TRY
        IF p_new THEN
            LET l_uuid = security.RandomGenerator.CreateUUIDString()
            LET l_sql =
                'INSERT INTO specialoffer'
                || ' (description, discountpct, "type", category, startdate, enddate,'
                || '  minqty, maxqty, rowguid, modifieddate)'
                || ' VALUES (?,?,?,?,?,?,?,?,?,?)'
            PREPARE p_offer_ins FROM l_sql
            EXECUTE p_offer_ins USING rec.description, rec.discountpct, rec.offertype,
                                      rec.category, rec.startdate, rec.enddate,
                                      rec.minqty, rec.maxqty, l_uuid, l_now
            LET rec.specialofferid = sqlca.sqlerrd[2]
        ELSE
            LET l_sql =
                'UPDATE specialoffer'
                || ' SET description=?, discountpct=?, "type"=?, category=?,'
                || '     startdate=?, enddate=?, minqty=?, maxqty=?, modifieddate=?'
                || ' WHERE specialofferid=?'
            PREPARE p_offer_upd FROM l_sql
            EXECUTE p_offer_upd USING rec.description, rec.discountpct, rec.offertype,
                                      rec.category, rec.startdate, rec.enddate,
                                      rec.minqty, rec.maxqty, l_now, rec.specialofferid
        END IF
        COMMIT WORK
    CATCH
        ROLLBACK WORK
        CALL aw_sql_error("Saving special offer")
        RETURN FALSE
    END TRY
    RETURN TRUE
END FUNCTION

#-------------------------------------------------------------------------------
#+ Delete an offer. An offer referenced by order details or eligible products
#+ cannot be removed.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION offer_delete(p_id INTEGER) RETURNS BOOLEAN
    BEGIN WORK
    TRY
        DELETE FROM specialoffer WHERE specialofferid = p_id
        COMMIT WORK
    CATCH
        ROLLBACK WORK
        IF sqlca.sqlcode = -692 OR sqlca.sqlcode = -691 THEN
            ERROR "Cannot delete: this offer is still referenced by other records."
        ELSE
            CALL aw_sql_error("Deleting special offer")
        END IF
        RETURN FALSE
    END TRY
    RETURN TRUE
END FUNCTION
