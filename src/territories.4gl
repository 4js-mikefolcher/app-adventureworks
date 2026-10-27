################################################################################
# territories.4gl - browse and maintain sales territories (salesterritory).
#
# Establishes the reusable "modifiable list" pattern (read + inline add / edit /
# delete) used by the other simple-CRUD modules. salesterritory has a column
# literally named "group" (a reserved word), so this module uses an explicit
# record with safe member names and quotes the identifier in SQL.
#
# Public entry: territories_run()
################################################################################

IMPORT security

IMPORT FGL lib_aw

#+ One territory row as shown/edited in the list. "groupname" maps to the SQL
#+ column "group"; the YTD figures are system-maintained and shown read-only.
TYPE t_terr RECORD
    territoryid       INTEGER,
    name              VARCHAR(50),
    countryregioncode VARCHAR(3),
    groupname         VARCHAR(50),
    salesytd          DECIMAL(20,4),
    saleslastyear     DECIMAL(20,4)
END RECORD

PRIVATE DEFINE m_terr DYNAMIC ARRAY OF t_terr

#-------------------------------------------------------------------------------
#+ Open the territories window and run the browse/maintain dialog.
#-------------------------------------------------------------------------------
FUNCTION territories_run()
    OPEN WINDOW w_terr WITH FORM "territories"
        ATTRIBUTES(TEXT = "Sales Territories", STYLE = "dialog")
    CALL terr_load()
    CALL terr_browse()
    CLOSE WINDOW w_terr
END FUNCTION

#-------------------------------------------------------------------------------
#+ Load all territories into the module array, ordered by name.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION terr_load()
    DEFINE r t_terr
    DEFINE l_sql STRING
    LET l_sql =
        'SELECT territoryid, name, countryregioncode, "group", salesytd, saleslastyear'
        || ' FROM salesterritory ORDER BY name'
    CALL m_terr.clear()
    DECLARE c_terr CURSOR FROM l_sql
    FOREACH c_terr INTO r.*
        LET m_terr[m_terr.getLength() + 1] = r
    END FOREACH
END FUNCTION

#-------------------------------------------------------------------------------
#+ The browse dialog: read-only list with inline add / edit / delete triggers.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION terr_browse()
    DEFINE rec t_terr
    DISPLAY ARRAY m_terr TO sr_terr.* ATTRIBUTES(DOUBLECLICK = update, UNBUFFERED)

        ON UPDATE
            LET rec = m_terr[arr_curr()]
            IF terr_input(scr_line(), rec) THEN
                IF terr_save(FALSE, rec) THEN
                    LET m_terr[arr_curr()] = rec
                END IF
            END IF

        ON APPEND
            CALL terr_defaults(rec)
            IF terr_input(scr_line(), rec) THEN
                IF terr_save(TRUE, rec) THEN
                    LET m_terr[arr_curr()] = rec
                ELSE
                    CALL m_terr.deleteElement(arr_curr())
                END IF
            ELSE
                CALL m_terr.deleteElement(arr_curr())
            END IF

        ON ACTION remove ATTRIBUTES(TEXT = "Delete", IMAGE = "fa-trash")
            IF m_terr.getLength() > 0 THEN
                IF aw_confirm("Delete territory",
                              SFMT("Delete territory '%1'?", m_terr[arr_curr()].name)) THEN
                    IF terr_delete(m_terr[arr_curr()].territoryid) THEN
                        CALL m_terr.deleteElement(arr_curr())
                    END IF
                END IF
            END IF

    END DISPLAY
END FUNCTION

#-------------------------------------------------------------------------------
#+ Initialise a blank territory for ON APPEND.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION terr_defaults(rec t_terr INOUT)
    INITIALIZE rec.* TO NULL
    LET rec.salesytd = 0
    LET rec.saleslastyear = 0
END FUNCTION

#-------------------------------------------------------------------------------
#+ Inline edit of one row's editable columns (name, country, group).
#+
#+ @param p_line     screen line of the row being edited
#+ @param rec        territory record (INOUT)
#+ @return TRUE if the user accepted the input
#-------------------------------------------------------------------------------
PRIVATE FUNCTION terr_input(p_line INTEGER, rec t_terr INOUT) RETURNS BOOLEAN
    LET int_flag = FALSE
    INPUT rec.name, rec.countryregioncode, rec.groupname
        FROM sr_terr[p_line].name, sr_terr[p_line].countryregioncode, sr_terr[p_line].groupname
        ATTRIBUTES(WITHOUT DEFAULTS)
    RETURN (NOT int_flag)
END FUNCTION

#-------------------------------------------------------------------------------
#+ Persist a territory. On insert, omit the serial key and read the new id back.
#+ Returns TRUE on success.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION terr_save(p_new BOOLEAN, rec t_terr INOUT) RETURNS BOOLEAN
    DEFINE l_sql STRING
    DEFINE l_now DATETIME YEAR TO SECOND
    DEFINE l_uuid VARCHAR(36)
    LET l_now = CURRENT YEAR TO SECOND
    BEGIN WORK
    TRY
        IF p_new THEN
            LET l_uuid = security.RandomGenerator.CreateUUIDString()
            LET l_sql =
                'INSERT INTO salesterritory'
                || ' (name, countryregioncode, "group", salesytd, saleslastyear,'
                || '  costytd, costlastyear, rowguid, modifieddate)'
                || ' VALUES (?,?,?,0,0,0,0,?,?)'
            PREPARE p_terr_ins FROM l_sql
            EXECUTE p_terr_ins USING rec.name, rec.countryregioncode, rec.groupname,
                                     l_uuid, l_now
            LET rec.territoryid = sqlca.sqlerrd[2]
        ELSE
            LET l_sql =
                'UPDATE salesterritory'
                || ' SET name=?, countryregioncode=?, "group"=?, modifieddate=?'
                || ' WHERE territoryid=?'
            PREPARE p_terr_upd FROM l_sql
            EXECUTE p_terr_upd USING rec.name, rec.countryregioncode, rec.groupname,
                                     l_now, rec.territoryid
        END IF
        COMMIT WORK
    CATCH
        ROLLBACK WORK
        CALL aw_sql_error("Saving territory")
        RETURN FALSE
    END TRY
    RETURN TRUE
END FUNCTION

#-------------------------------------------------------------------------------
#+ Delete a territory. A territory referenced by customers, salespersons or
#+ orders cannot be removed; that surfaces as a friendly message.
#-------------------------------------------------------------------------------
PRIVATE FUNCTION terr_delete(p_id INTEGER) RETURNS BOOLEAN
    BEGIN WORK
    TRY
        DELETE FROM salesterritory WHERE territoryid = p_id
        COMMIT WORK
    CATCH
        ROLLBACK WORK
        IF sqlca.sqlcode = -692 OR sqlca.sqlcode = -691 THEN
            ERROR "Cannot delete: this territory is still referenced by other records."
        ELSE
            CALL aw_sql_error("Deleting territory")
        END IF
        RETURN FALSE
    END TRY
    RETURN TRUE
END FUNCTION
