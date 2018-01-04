REPORT zmke_screenshot_enhance.

PARAMETERS: pa_kword TYPE text20 AS LISTBOX VISIBLE LENGTH 20 DEFAULT '1',
            pa_txstr TYPE text20.

			
INITIALIZATION.
   PERFORM initialization.

AT SELECTION-SCREEN OUTPUT.
   PERFORM at_selection_screen_output.

START-OF-SELECTION.
   PERFORM main.

   
FORM main.

   DATA: lv_subrc TYPE sysubrc,
         lv_image TYPE xstring.

   IF pa_kword IS INITIAL.
     MESSAGE 'Please choose a keyword.' TYPE 'I'.
     RETURN.
   ENDIF.

   IF pa_txstr IS INITIAL.
     MESSAGE 'Please supply a text string.' TYPE 'I'.
     RETURN.
   ENDIF.

   PERFORM screenshot_create
           CHANGING lv_subrc
                    lv_image.

   IF lv_subrc <> 0.
     RETURN.
   ENDIF.

   PERFORM screenshot_enhance
           CHANGING lv_subrc
                    lv_image.

   IF lv_subrc <> 0.
     RETURN.
   ENDIF.

   PERFORM screenshot_download
           USING    lv_image
           CHANGING lv_subrc.

   IF lv_subrc <> 0.
     RETURN.
   ENDIF.

ENDFORM.                    " MAIN


FORM screenshot_create CHANGING cv_subrc TYPE sysubrc
                                cv_image TYPE xstring.

   DATA lv_mtype TYPE string.

   CALL METHOD cl_gui_frontend_services=>get_screenshot
     IMPORTING
       mime_type_str        = lv_mtype
       image                = cv_image
     EXCEPTIONS
       access_denied        = 1
       cntl_error           = 2
       error_no_gui         = 3
       not_supported_by_gui = 4
       OTHERS               = 5.

   IF sy–subrc <> 0.
     cv_subrc = sy–subrc.
     RETURN.
   ENDIF.

ENDFORM.                    " SCREENSHOT_CREATE


FORM screenshot_enhance CHANGING cv_subrc TYPE sysubrc
                                 cv_image TYPE xstring.

   CONSTANTS: lc_zero  TYPE xstring VALUE '00',
              lc_space TYPE xstring VALUE '20'.

   TYPES: BEGIN OF line,
           text TYPE text132,
          END OF line.

   DATA: lv_chunk  TYPE xstring,
         lv_ileng  TYPE i,
         lv_xleng  TYPE x LENGTH 4,
         lv_icrc   TYPE i,
         lv_xcrc   TYPE x LENGTH 4,
         lt_stext  TYPE TABLE OF line,
         ls_stext  TYPE line,
         lv_search TYPE xstring,
         lv_rest   TYPE REF TO data,
         lv_offset TYPE i,
         lv_kword  TYPE text20.

   FIELD-SYMBOLS <fs_rest> TYPE any.

* choose keyword
   CASE pa_kword.
     WHEN '1'.
       lv_kword = 'Title'.

     WHEN '2'.
       lv_kword = 'Author'.

     WHEN '3'.
       lv_kword = 'Description'.

     WHEN '4'.
       lv_kword = 'Source'.

     WHEN '5'.
       lv_kword = 'Comment'.
   ENDCASE.

* combine chunk type ("tEXt") and keyword
  CONCATENATE 'tEXt' lv_kword INTO ls_stext.

* combine chunk type, keyword and text string
  CONCATENATE ls_stext pa_txstr INTO ls_stext SEPARATED BY space.
  APPEND ls_stext TO lt_stext.

   CALL FUNCTION 'SCMS_TEXT_TO_XSTRING'
*   EXPORTING
*     FIRST_LINE       = 0
*     LAST_LINE        = 0
*     MIMETYPE         = ' '
*     ENCODING         =
     IMPORTING
       buffer   = lv_chunk
     TABLES
       text_tab = lt_stext
     EXCEPTIONS
       failed   = 1
       OTHERS   = 2.

   IF sy–subrc <> 0.
     cv_subrc = sy–subrc.
     RETURN.
   ENDIF.

* "Zero Byte" is delimiter between keyword and text string
* (remember: keyword and text string are our "chunk data")
   REPLACE FIRST OCCURRENCE OF lc_space
           IN lv_chunk
           WITH lc_zero
           IN BYTE MODE.

   IF sy–subrc <> 0.
     cv_subrc = sy–subrc.
     RETURN.
   ENDIF.

* function "SCMS_TEXT_TO_XSTRING" adds a line break at the end
* which has to be removed
   lv_ileng = xstrlen( lv_chunk ) – 2.
   lv_chunk = lv_chunk+0(lv_ileng).

* get length of chunk data (ignore chunk type by -4)
   CLEAR lv_ileng.
   lv_ileng = xstrlen( lv_chunk ) – 4.
   lv_xleng = lv_ileng.

* generate CRC32 for chunk type and chunk data
   CALL METHOD cl_abap_zip=>crc32
     EXPORTING
       content = lv_chunk
     RECEIVING
       crc32   = lv_icrc.

   lv_xcrc = lv_icrc.

* build complete chunk
   CONCATENATE lv_xleng lv_chunk lv_xcrc INTO lv_chunk IN BYTE MODE.

* place the new chunk before "IEND"-chunk
   CLEAR lt_stext.
   ls_stext = 'IEND'.
   APPEND ls_stext TO lt_stext.

   CALL FUNCTION 'SCMS_TEXT_TO_XSTRING'
*  	EXPORTING
*     FIRST_LINE       = 0
*     LAST_LINE        = 0
*     MIMETYPE         = ' '
*     ENCODING         =
     IMPORTING
       buffer   = lv_search
     TABLES
       text_tab = lt_stext
     EXCEPTIONS
       failed   = 1
       OTHERS   = 2.

   IF sy–subrc <> 0.
     cv_subrc = sy–subrc.
     RETURN.
   ENDIF.

   lv_search = lv_search+0(4). " avoid line break

   FIND FIRST OCCURRENCE OF lv_search
        IN cv_image
        IN BYTE MODE
        MATCH OFFSET lv_offset
        MATCH LENGTH lv_ileng.

   IF sy–subrc <> 0.
     cv_subrc = sy–subrc.
     RETURN.
   ENDIF.

* respect length indication befor "IEND"-chunk by -4
   lv_offset = lv_offset – 4.
   lv_ileng = xstrlen( cv_image ) – lv_offset.

* create variable for the image's tail
   CREATE DATA lv_rest TYPE x LENGTH lv_ileng.
   ASSIGN lv_rest->* TO <fs_rest>.
   IF sy–subrc <> 0.
     cv_subrc = sy–subrc.
     RETURN.
   ENDIF.

   <fs_rest> = cv_image+lv_offset(lv_ileng).

   CONCATENATE lv_chunk <fs_rest> INTO lv_chunk IN BYTE MODE.
   REPLACE SECTION OFFSET lv_offset
           OF cv_image
           WITH lv_chunk
           IN BYTE MODE.

   IF sy–subrc <> 0.
     cv_subrc = sy–subrc.
     RETURN.
   ENDIF.

ENDFORM.                    " SCREENSHOT_ENHANCE


FORM screenshot_download USING    uv_image TYPE xstring
                          CHANGING cv_subrc TYPE sysubrc.

   DATA: lt_bdata  TYPE TABLE OF x,
         lv_title  TYPE string,
         lv_dname  TYPE string,
         lv_fname  TYPE string,
         lv_fpath  TYPE string,
         lv_path   TYPE string,
         lv_usrac  TYPE i,
         lv_filter TYPE string.

   CALL FUNCTION 'SCMS_XSTRING_TO_BINARY'
     EXPORTING
       buffer     = uv_image
*      APPEND_TO_TABLE = ' '
*   IMPORTING
*      OUTPUT_LENGTH   =
     TABLES
       binary_tab = lt_bdata.

   IF lt_bdata IS INITIAL.
     cv_subrc = 4.
     RETURN.
   ENDIF.

   lv_title = 'Download image to …'.
   CONCATENATE sy–datum '-' sy–uzeit '.png' INTO lv_dname.
   lv_filter = '*.png'.

   CALL METHOD cl_gui_frontend_services=>file_save_dialog
     EXPORTING
       window_title         = lv_title
       default_extension    = '*.png'
       default_file_name    = lv_dname
*      with_encoding        =
       file_filter          = lv_filter
*      initial_directory    =
*      prompt_on_overwrite  = 'X'
     CHANGING
       filename             = lv_fname
       path                 = lv_path
       fullpath             = lv_fpath
       user_action          = lv_usrac
*      file_encoding        =
     EXCEPTIONS
       cntl_error           = 1
       error_no_gui         = 2
       not_supported_by_gui = 3
       OTHERS               = 4.

   IF sy–subrc <> 0.
     cv_subrc = sy–subrc.
     RETURN.
   ENDIF.

   IF lv_usrac = cl_gui_frontend_services=>action_cancel.
     RETURN.
   ENDIF.

   CALL METHOD cl_gui_frontend_services=>gui_download
     EXPORTING
*      BIN_FILESIZE            =
       filename                = lv_fname
       filetype                = 'BIN'
*      APPEND                  = SPACE
*      WRITE_FIELD_SEPARATOR   = SPACE
*      HEADER                  = '00'
*      TRUNC_TRAILING_BLANKS   = SPACE
*      WRITE_LF                = 'X'
*      COL_SELECT              = SPACE
*      COL_SELECT_MASK         = SPACE
*      DAT_MODE                = SPACE
*      CONFIRM_OVERWRITE       = SPACE
*      NO_AUTH_CHECK           = SPACE
*      CODEPAGE                = SPACE
*      IGNORE_CERR             = ABAP_TRUE
*      REPLACEMENT             = '#'
*      WRITE_BOM               = SPACE
*      TRUNC_TRAILING_BLANKS_EOL = 'X'
*      WK1_N_FORMAT            = SPACE
*      WK1_N_SIZE              = SPACE
*      WK1_T_FORMAT            = SPACE
*      WK1_T_SIZE              = SPACE
*      SHOW_TRANSFER_STATUS    = 'X'
*      FIELDNAMES              =
*      WRITE_LF_AFTER_LAST_LINE  = 'X'
*      VIRUS_SCAN_PROFILE      = '/SCET/GUI_DOWNLOAD'
*    IMPORTING
*      FILELENGTH              =
     CHANGING
       data_tab                = lt_bdata
     EXCEPTIONS
       file_write_error        = 1
       no_batch                = 2
       gui_refuse_filetransfer = 3
       invalid_type            = 4
       no_authority            = 5
       unknown_error           = 6
       header_not_allowed      = 7
       separator_not_allowed   = 8
       filesize_not_allowed    = 9
       header_too_long         = 10
       dp_error_create         = 11
       dp_error_send           = 12
       dp_error_write          = 13
       unknown_dp_error        = 14
       access_denied           = 15
       dp_out_of_memory        = 16
       disk_full               = 17
       dp_timeout              = 18
       file_not_found          = 19
       dataprovider_exception  = 20
       control_flush_error     = 21
       not_supported_by_gui    = 22
       error_no_gui            = 23
       OTHERS                  = 24.

   IF sy–subrc <> 0.
     cv_subrc = sy–subrc.
     RETURN.
   ENDIF.

ENDFORM.                    " SCREENSHOT_DOWNLOAD


FORM at_selection_screen_output.

   DATA: ls_values TYPE vrm_value,
         lt_values TYPE vrm_values.

   ls_values–key  = '1'.
   ls_values–text = 'Title'.
   APPEND ls_values TO lt_values.

   ls_values–key  = '2'.
   ls_values–text = 'Author'.
   APPEND ls_values TO lt_values.

   ls_values–key  = '3'.
   ls_values–text = 'Description'.
   APPEND ls_values TO lt_values.

   ls_values–key  = '4'.
   ls_values–text = 'Source'.
   APPEND ls_values TO lt_values.

   ls_values–key  = '5'.
   ls_values–text = 'Comment'.
   APPEND ls_values TO lt_values.

   CALL FUNCTION 'VRM_SET_VALUES'
     EXPORTING
       id              = 'PA_KWORD'
       values          = lt_values
     EXCEPTIONS
       id_illegal_name = 1
       OTHERS          = 2.

   IF sy–subrc <> 0.
     RETURN.
   ENDIF.

ENDFORM.                    " AT_SELECTION_SCREEN_OUTPUT


FORM initialization.

   pa_txstr = 'Hello World!'.

ENDFORM.                    " INITIALIZATION