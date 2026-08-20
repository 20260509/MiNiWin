BITS 16
CPU X64
DEFAULT ABS
ORG 0x7C00

; MiniWin / DOS / HEX integrated image - v26 / Version 6.2
; - Ctrl+Backspace in a HEX or HEX -MEM multi-selection fills the complete
;   selected byte range with 00h as one undoable edit
; - HEX F1 help uses 80x25 text mode and restores the editor's 80x50 mode
; - F5 in HEX and HEX -MEM discards the displayed buffer and rereads the
;   current 512-byte disk sector or physical-memory page
; - Custom Program line numbers are left-aligned in the fixed gutter
; - Debug fault buttons execute architectural faulting instructions even when
;   graphical blue screens are disabled; software INTs remain only fallbacks
; - Program Manager Apps menu includes Custom as its final item
; - Custom receives its task button immediately and taskbar switching now
;   minimizes/restores it while preserving the normal-window Z-order
; - eight application slots use an extended-memory backing store and one safe
;   conventional-memory working arena; Custom abbreviates to CP when crowded
; - unchanged documents save silently; long save errors wrap inside the dialog
; - Custom Program status text wraps and its resize grip uses the NW-SE cursor
; - Custom Program close confirmation is fixed-size with Yes/No/Cancel
; - Custom Program image loading accounts for the HEX character-data trailer
; - Custom Program is a resizable/minimizable/maximizable task window
; - Custom Program persistence is confined to LBA 500..1500
; - Notepad/Paint Ctrl+S persistence uses LBA 1501..2000 with overwrite prompts
; - HEX searches service the watchdog and throttle progress redraws to 200 ms
; - HEX -MEM search progress shows full 64-bit hexadecimal physical addresses
; - HEX and HEX -MEM provide mode-specific F1 help on a blue screen
; - HEX PS/2 polling never consumes BIOS keyboard scan codes
; - HEX entry clears stale TF/RF and hardware-debug state before installing hooks
; - Custom Program Execute now selects Real, Protected, or Long Mode
; - protected/long custom programs return through the verified Real Mode path
; - selectable Real/Protected/Long Mode blue-screen launcher
; - CRASH accepts an optional stop code plus -PM or -LM
; - every blue screen prints a stable stop code and a two-line reason area
; - robust Ctrl+Alt+Del state seeding when entering from 320x200 graphics
; - full-buffer Notepad input backlog is discarded without redraw storms
; - GUI state survives the resident HEX overlay and WIN -KEEP round trip
; - BIOS-free direct-VGA 80x25 blue screens in MiniWin/DOS and HEX
; - blue-screen DAC entries are restored and verified after graphics mode
; - transactional Notepad undo snapshots and synchronized invalidation
; - Notepad snapshot DS/ES always use the same validated process arena
; - full-buffer Backspace keeps its no-undo edit group across validation
; - software INT 05h is separated from a genuine CPU BOUND exception
; - CLI-safe Ctrl+Alt+Del polling hard-resets from every blue-screen loop
; - optional blue-screen gate plus critical live-memory write detection
; - GUI custom-program editor with LBA 500..1500 persistence and LBA 2048 execution staging
; - bounded custom-program execution with a far-return trampoline to MiniWin
; - Stage-2 extension reached with explicit 16:16 far transfers
; - logical-line rendering, horizontal scrolling, and clipped editor output
; - single-transaction custom-editor undo/redo (Ctrl+Z, Ctrl+Y, Ctrl+Shift+Z)
; - interrupt-free 15-second blue-screen countdown and stable hardware reset
; - scan-set-1/2 Ctrl+Alt+Del parsing with no BIOS keyboard backlog
; - parallel newline metadata keeps opcode 0Ah distinct from an Enter newline
; - persistent Control option for automatic blue-screen restart
; - critical live-memory guards are limited to Custom Program and HEX -MEM
; - pre-accessed read-only GDT descriptors keep Long Custom Mode fault-safe

%define CLIP_SEG               0x8000
%define SELECT_SEG             0x5000
%define UNDO_SEG               0x5800
%define BACKBUF_SEG            0x7000
%define STACK_SEG              0x8800
%define STACK_TOP              0x7FFE
%if ((STACK_SEG << 4) + STACK_TOP) >= 0x90000
    %error "GUI stack enters the EBDA window"
%endif
%define BOOT_SETTING_IO_SEG    0x0600    ; fixed 512-byte scratch buffer at physical 06000h
%define BLUESCREEN_ENABLE_ADDR 0x0500    ; persistent low-memory gate: 0=disabled, nonzero=enabled
%define BLUESCREEN_FONT_OFF_ADDR 0x0502  ; cached ROM 8x16 pointer, survives HEX overlay
%define BLUESCREEN_FONT_SEG_ADDR 0x0504
; Stop-code registry: 00h..0Fh are real-mode CPU exceptions; 00h..1Fh are
; protected/long-mode CPU exceptions.  Internal fatal reasons use 80h..85h.
%define BSOD_STOP_NOTEPAD       0x80
%define BSOD_STOP_TABLES        0x81
%define BSOD_STOP_WATCHDOG      0x82
%define BSOD_STOP_REBOOT        0x83
%define BSOD_STOP_MANUAL        0x84
%define BSOD_STOP_CRITICAL_WRITE 0x85
%define VGA_SEG                0xA000
%define TEXT_SEG               0xB800
%define STAGE2_SEG             0x07E0    ; physical 0000:7E00, IP window extends past 64 KiB
%define STAGE2_LINEAR_BASE     (STAGE2_SEG << 4)
; STAGE2_SECTORS is resolved after stage2_end.  The extension is stored after
; the sector-padded base image and is loaded together with Stage 2, so resident
; integrity/configuration helpers can live outside the 64-KiB near-code window.
%define STAGE2_EXT_SEG         (STAGE2_SEG + (STAGE2_SECTORS * 0x20))
%define HEX_EDITOR_SECTORS     64        ; v15-fix3 HEX payload, loaded as 07E0:0000
%define HEX_TRAILER_SECTORS    1         ; post-payload character probe data
; HEX temporarily replaces the complete stage-2 image at physical 07E00h.
; Preserve MiniWin's segment-zero globals in the unused 1A000h..1FFFFh gap;
; process arenas begin at 20000h.  18000h..19FFFh is reserved for the always
; loaded Stage-2 extension, whose exact start follows the padded base image.
%define GUI_SNAPSHOT_SEG       0x1A00
%define GUI_SNAPSHOT_DATA_OFF  0x0010
%define GUI_SNAPSHOT_MAGIC     0x504E5347 ; "GSNP" in little endian
%define GUI_SESSION_MAGIC      0x5045454B ; "KEEP" in little endian
%define GUI_SNAPSHOT_CAPACITY  (0x6000-GUI_SNAPSHOT_DATA_OFF)

; The custom-program editor deliberately uses extended RAM, never the
; 90000h..9FFFFh EBDA window. The
; persistent range is split into 500 source sectors and 501 metadata sectors.
%define PERSISTENCE_FIRST_LBA    500
%define CUSTOM_SOURCE_FIRST_LBA  500
%define CUSTOM_SOURCE_LAST_LBA   999
%define CUSTOM_NEWLINE_FIRST_LBA 1000
%define CUSTOM_NEWLINE_LAST_LBA  1500
%define NOTE_SAVE_FIRST_LBA      1501
%define NOTE_SAVE_LAST_LBA       1750
%define PAINT_SAVE_FIRST_LBA     1751
%define PAINT_SAVE_LAST_LBA      2000
; Execution staging is transient and deliberately outside all saved data.
%define CUSTOM_EXEC_FIRST_LBA    499
%define CUSTOM_SOURCE_SECTORS   (CUSTOM_SOURCE_LAST_LBA-CUSTOM_SOURCE_FIRST_LBA+1)
%define CUSTOM_SOURCE_CAPACITY  ((CUSTOM_SOURCE_SECTORS*512)-3)
%define CUSTOM_NEWLINE_HEADER_SIZE 7
%define CUSTOM_NEWLINE_SECTORS  ((CUSTOM_SOURCE_CAPACITY+CUSTOM_NEWLINE_HEADER_SIZE+511)/512)
%define CUSTOM_NEWLINE_MAGIC    0x33464C4E ; "NLF3"
%define NOTE_SAVE_MAGIC         0x3136544E ; "NT61"
%define PAINT_SAVE_MAGIC        0x31365450 ; "PT61"
%define NOTE_SAVE_HEADER_SIZE   8
%define PAINT_SAVE_HEADER_SIZE  32
%define CUSTOM_BUFFER_PHYS      0x00100000
%define CUSTOM_CLIP_PHYS        0x00180000
%define CUSTOM_EXEC_PHYS        0x00200000
%define CUSTOM_UNDO_PHYS        0x00210000
%define CUSTOM_REDO_PHYS        0x00290000
%define CUSTOM_NEWLINE_PHYS     0x00310000
%define CUSTOM_CLIP_NEWLINE_PHYS 0x00390000
%define CUSTOM_UNDO_NEWLINE_PHYS 0x00410000
%define CUSTOM_REDO_NEWLINE_PHYS 0x00490000
%define CUSTOM_EXEC_SEG         0x6000
%define CUSTOM_EXEC_LINEAR      (CUSTOM_EXEC_SEG << 4)
%define CUSTOM_EXEC_MAX         0x0000FFF0
%define CUSTOM_EXEC_RETURN_SIZE 5
%define CUSTOM_CODE_SEG         0x6000
%define CUSTOM_EDITOR_SECTORS   48
%define CUSTOM_DEFAULT_X        12
%define CUSTOM_DEFAULT_Y        6
%define CUSTOM_DEFAULT_W        296
%define CUSTOM_DEFAULT_H        176
%define CUSTOM_MIN_W            248
%define CUSTOM_MIN_H            140
%define CUSTOM_MAX_VIEW_ROWS    12
%define CUSTOM_ROW_H            9
%define CUSTOM_LINE_NO_COLS     7
%define CUSTOM_PROMPT_MAX_CHARS 20      ; one line; also keeps HEX input even
%define CUSTOM_SCROLL_THUMB_H   12
%define CUSTOM_HSCROLL_THUMB_W  20
; The close confirmation is screen-modal and deliberately independent of the
; resizable Custom Program parent window.
%define CUSTOM_CONFIRM_X        40
%define CUSTOM_CONFIRM_Y        70
%define CUSTOM_CONFIRM_W        240
%define CUSTOM_CONFIRM_H        76
%define CUSTOM_CONFIRM_BTN_Y    (CUSTOM_CONFIRM_Y+48)
%define CUSTOM_CONFIRM_BTN_W    62
%define CUSTOM_CONFIRM_BTN_H    22
%define CUSTOM_CONFIRM_YES_X    (CUSTOM_CONFIRM_X+10)
%define CUSTOM_CONFIRM_NO_X     (CUSTOM_CONFIRM_X+89)
%define CUSTOM_CONFIRM_CANCEL_X (CUSTOM_CONFIRM_X+164)

%if (CUSTOM_REDO_PHYS+CUSTOM_SOURCE_CAPACITY) > CUSTOM_NEWLINE_PHYS
    %error "Custom redo data overlaps the source newline metadata"
%endif
%if (CUSTOM_NEWLINE_PHYS+CUSTOM_SOURCE_CAPACITY) > CUSTOM_CLIP_NEWLINE_PHYS
    %error "Custom source and clipboard newline metadata overlap"
%endif
%if (CUSTOM_CLIP_NEWLINE_PHYS+CUSTOM_SOURCE_CAPACITY) > CUSTOM_UNDO_NEWLINE_PHYS
    %error "Custom clipboard and undo newline metadata overlap"
%endif
%if (CUSTOM_UNDO_NEWLINE_PHYS+CUSTOM_SOURCE_CAPACITY) > CUSTOM_REDO_NEWLINE_PHYS
    %error "Custom undo and redo newline metadata overlap"
%endif
%if (CUSTOM_SOURCE_CAPACITY+CUSTOM_NEWLINE_HEADER_SIZE) > (CUSTOM_NEWLINE_SECTORS*512)
    %error "Custom newline metadata disk range is too small"
%endif
%if (CUSTOM_NEWLINE_FIRST_LBA+CUSTOM_NEWLINE_SECTORS-1) > CUSTOM_NEWLINE_LAST_LBA
    %error "Custom Program persistence exceeds LBA 1500"
%endif
%if NOTE_SAVE_FIRST_LBA <> (CUSTOM_NEWLINE_LAST_LBA+1)
    %error "Notepad persistence must start at LBA 1501"
%endif
%if PAINT_SAVE_FIRST_LBA <> (NOTE_SAVE_LAST_LBA+1)
    %error "Paint persistence must follow Notepad persistence"
%endif
%if PAINT_SAVE_LAST_LBA <> 2000
    %error "Application persistence must end at LBA 2000"
%endif

; Fixed low-memory workspace, immediately above the 0600:0000 disk sector
; buffer and below the resident boot sector.  This keeps stage 2 within its
; strict 64-KiB code-segment limit.
%define CUSTOM_WORK_BASE         0x6200
%define custom_view_row_starts   (CUSTOM_WORK_BASE+0)
%define custom_prompt_buf        (CUSTOM_WORK_BASE+52)
%define custom_find_buf          (CUSTOM_WORK_BASE+117)
%define custom_replace_buf       (CUSTOM_WORK_BASE+149)
%define custom_line_buf          (CUSTOM_WORK_BASE+181)
%define custom_dap               (CUSTOM_WORK_BASE+221)
%define custom_flat_saved_gdtr   (CUSTOM_WORK_BASE+237)
%define custom_hscroll_thumb_x   (CUSTOM_WORK_BASE+243)
%define custom_undo_valid        (CUSTOM_WORK_BASE+245)
%define custom_redo_valid        (CUSTOM_WORK_BASE+246)
%define custom_undo_selection    (CUSTOM_WORK_BASE+247)
%define custom_redo_selection    (CUSTOM_WORK_BASE+248)
%define custom_undo_dirty        (CUSTOM_WORK_BASE+249)
%define custom_redo_dirty        (CUSTOM_WORK_BASE+250)
%define custom_hscroll_col       (CUSTOM_WORK_BASE+251)
%define custom_max_line_cols     (CUSTOM_WORK_BASE+255)
%define custom_token_col         (CUSTOM_WORK_BASE+259)
%define custom_exec_stage_len    (CUSTOM_WORK_BASE+263)
%define custom_undo_len          (CUSTOM_WORK_BASE+267)
%define custom_undo_cursor       (CUSTOM_WORK_BASE+271)
%define custom_undo_anchor       (CUSTOM_WORK_BASE+275)
%define custom_undo_scroll       (CUSTOM_WORK_BASE+279)
%define custom_undo_hscroll      (CUSTOM_WORK_BASE+283)
%define custom_redo_len          (CUSTOM_WORK_BASE+287)
%define custom_redo_cursor       (CUSTOM_WORK_BASE+291)
%define custom_redo_anchor       (CUSTOM_WORK_BASE+295)
%define custom_redo_scroll       (CUSTOM_WORK_BASE+299)
%define custom_redo_hscroll      (CUSTOM_WORK_BASE+303)
%define custom_ext_loaded        (CUSTOM_WORK_BASE+307)

%if (CUSTOM_WORK_BASE+308) > 0x7C00
    %error "Custom editor low-memory workspace overlaps the resident boot sector"
%endif

; Real-mode Custom Program integrity snapshot. It occupies the gap immediately
; after the long-mode IDT; protected/long custom execution treats page 5
; read-only, while page 6 remains available for panic and Real Custom Program
; stacks.
%define SYSTEM_INTEGRITY_WORK_BASE 0x5400
%define system_expected_bda_ebda     (SYSTEM_INTEGRITY_WORK_BASE+0)
%define system_expected_bda_memory   (SYSTEM_INTEGRITY_WORK_BASE+2)
%define system_expected_font_off     (SYSTEM_INTEGRITY_WORK_BASE+4)
%define system_expected_font_seg     (SYSTEM_INTEGRITY_WORK_BASE+6)
%define system_expected_boot_hash    (SYSTEM_INTEGRITY_WORK_BASE+8)
%define system_expected_irq_hash     (SYSTEM_INTEGRITY_WORK_BASE+10)
%define system_expected_panic_hash   (SYSTEM_INTEGRITY_WORK_BASE+12)
%define system_expected_mbr_tail_hash (SYSTEM_INTEGRITY_WORK_BASE+14)
%define system_expected_proc_hash    (SYSTEM_INTEGRITY_WORK_BASE+16)
%define system_expected_ivt          (SYSTEM_INTEGRITY_WORK_BASE+18)
%define SYSTEM_INTEGRITY_WORK_END    (system_expected_ivt+(256*4))

%if SYSTEM_INTEGRITY_WORK_END > 0x6000
    %error "Integrity monitor workspace overlaps the page-6 custom stack"
%endif

; Slot 0 is Program Manager and slots 1..8 are application processes.  A
; single 48-KiB conventional-memory working arena remains at 20000h; every
; application's authoritative private bytes are swapped to a disjoint backing
; slot above all Custom Program buffers.  This keeps eight simultaneous Paint
; or Notepad instances possible without overlapping selection/undo/backbuffer.
%define MAX_PROCS              9
%define PROC_BASE_SEG          0x2000
%define PROC_SEG_STEP          0x0C00
%define PROC_ARENA_WORDS       24576
%define PROC_ARENA_BYTES       (PROC_ARENA_WORDS * 2)
%define PROC_ACTIVE_PHYS       (PROC_BASE_SEG << 4)
%define PROC_BACKING_PHYS      0x00500000
%define PROC_BACKING_END_PHYS  (PROC_BACKING_PHYS + ((MAX_PROCS-1) * PROC_ARENA_BYTES))
%define APP_NONE               0
%define APP_PAINT              1
%define APP_NOTEPAD            2
%define APP_CALC               3
%define NOTE_UNDO_OFF          0x6000

%define SCREEN_W               320
%define SCREEN_H               200

%define COL_BLACK              0
%define COL_BLUE               1
%define COL_GREEN              2
%define COL_CYAN               3
%define COL_RED                4
%define COL_MAGENTA            5
%define COL_BROWN              6
%define COL_GRAY               7
%define COL_DARKGRAY           8
%define COL_LIGHTBLUE          9
%define COL_LIGHTGREEN         10
%define COL_LIGHTCYAN          11
%define COL_LIGHTRED           12
%define COL_LIGHTMAGENTA       13
%define COL_YELLOW             14
%define COL_WHITE              15

%define TITLE_H                18
%define MENU_H                 14
%define CTRL_W                 18
%define CTRL_H                 12

%define TASKBAR_Y              184
%define TASKBAR_H              16
%define TASK_BUTTON_W          58
%define TASK_BUTTON_MIN_W      27

%define WIN_MAIN               0
%define WIN_PAINT              1       ; legacy app-type value
%define WIN_NOTEPAD            2       ; legacy app-type value
%define WIN_CALC               3       ; legacy app-type value
%define WIN_CUSTOM             0xFE    ; modal overlay with its own task button

%define MENU_NONE              0
%define MENU_MAIN_FILE         1
%define MENU_MAIN_APPS         2
%define MENU_MAIN_HELP         3
%define MENU_PAINT_FILE        4
%define MENU_PAINT_EDIT        5
%define MENU_PAINT_VIEW        6
%define MENU_NOTE_FILE          7
%define MENU_NOTE_EDIT          8
%define MENU_NOTE_HELP          9
%define MENU_CALC_FILE          10
%define MENU_CALC_HELP          11
%define MENU_SYS_MAIN           12
%define MENU_SYS_PAINT          13
%define MENU_SYS_NOTE           14
%define MENU_SYS_CALC           15

%define MSG_TEXT               0
%define MSG_ABOUT              1
%define MSG_SYSTEM             3
%define MSG_EXIT_CONFIRM       4
%define MSG_UNSAVED           5
%define MSG_DEBUG_RESULT      6
%define MSG_LONG_RESULT       7
%define MSG_OVERWRITE         8

%define DEBUG_MAIN_X           55
%define DEBUG_MAIN_Y           4
%define DEBUG_MAIN_W           210
%define DEBUG_MAIN_H           178
%define DEBUG_INT_X            42
%define DEBUG_INT_Y            8
%define DEBUG_INT_W            236
%define DEBUG_INT_H            174
%define DEBUG_INT_VISIBLE      6
%define DEBUG_INT_ITEM_XOFF    18
%define DEBUG_INT_ITEM_YOFF    47
%define DEBUG_INT_ITEM_W       174
%define DEBUG_INT_ITEM_H       16
%define DEBUG_INT_ITEM_STEP    18
%define DEBUG_SCROLL_XOFF      202
%define DEBUG_SCROLL_UP_YOFF   45
%define DEBUG_SCROLL_DOWN_YOFF 139
%define DEBUG_SCROLL_TRACK_YOFF 59
%define DEBUG_SCROLL_TRACK_H   80
%define DEBUG_SCROLL_THUMB_H   12
%define DEBUG_SCROLL_TRAVEL    (DEBUG_SCROLL_TRACK_H-DEBUG_SCROLL_THUMB_H)
%define DEBUG_SCROLL_MAX       (256-DEBUG_INT_VISIBLE)
%define DEBUG_NORMAL_COUNT     16
%define DEBUG_NORMAL_SCROLL_MAX (DEBUG_NORMAL_COUNT-DEBUG_INT_VISIBLE)

%define MAIN_DEF_X             24
%define MAIN_DEF_Y             12
%define MAIN_DEF_W             270
%define MAIN_DEF_H             164
%define MAIN_MIN_W             220
%define MAIN_MIN_H             164

%define PAINT_W                300
%define PAINT_H                164
%define PAINT_MIN_W            300
%define PAINT_MIN_H            164
%define PAINT_TOOLBAR_W        54
%define PAINT_CANVAS_XOFF      58
%define PAINT_CANVAS_YOFF      62
%define PAINT_CANVAS_DEFAULT_W 234
%define PAINT_CANVAS_DEFAULT_H 88
%define PAINT_CANVAS_RIGHT_MARGIN 8
%define PAINT_CANVAS_BOTTOM_MARGIN 14
%define PAINT_CANVAS_MAX_W     (SCREEN_W-PAINT_CANVAS_XOFF-PAINT_CANVAS_RIGHT_MARGIN)
%define PAINT_CANVAS_MAX_H     (TASKBAR_Y-PAINT_CANVAS_YOFF-PAINT_CANVAS_BOTTOM_MARGIN)
%define PAINT_CANVAS_STRIDE    PAINT_CANVAS_MAX_W
%define PAINT_CANVAS_STORAGE_SIZE (PAINT_CANVAS_STRIDE * PAINT_CANVAS_MAX_H)
%define PAINT_TEXT_MAX         8192
%define PAINT_TEXT_BASE        PAINT_CANVAS_STORAGE_SIZE
%define PAINT_TEXT_COLOR_BASE  (PAINT_TEXT_BASE + PAINT_TEXT_MAX)
%define PAINT_PERSIST_BYTES    (PAINT_CANVAS_STORAGE_SIZE+(PAINT_TEXT_MAX*2))

%define PAINT_TOOL_PENCIL      0
%define PAINT_TOOL_FILL        1
%define PAINT_TOOL_TEXT        2
%define PAINT_TOOL_ERASER      3
%define PAINT_TOOL_EYEDROP     4
%define PAINT_TOOL_LINE        5
%define PAINT_TOOL_RECT        6
%define PAINT_TOOL_ELLIPSE     7
%define PAINT_TOOL_SELECT      8
%define PAINT_TOOL_MAGNIFY     9
%define PAINT_TOOL_COUNT       10

; Legacy pending constants remain for state cleanup; one-shot tools now execute at the stabilized press hotspot.
%define PAINT_PENDING_NONE       0
%define PAINT_PENDING_FILL       1
%define PAINT_PENDING_TEXT       2
%define PAINT_PENDING_EYEDROP    3
%define PAINT_FILL_MARKER        255     ; temporary flood-fill marker; palette uses 0..247

%define NOTE_W                 286
%define NOTE_H                 158
%define NOTE_MIN_W             286
%define NOTE_MIN_H             158
%define NOTE_TEXT_XOFF         8
%define NOTE_TEXT_YOFF         39
%define NOTE_TEXT_W            270
%define NOTE_TEXT_H            108
%define NOTE_SCROLL_W          14
%define NOTE_VIEW_W            (NOTE_TEXT_W-NOTE_SCROLL_W)
%define NOTE_COLS              30
%define NOTE_ROWS              10
%define NOTE_MAX               16384
%define CLIP_MAX               32767
%define NOTE_TYPE_GROUP_TICKS  18
%define NOTE_GROUP_FULL_BACKSPACE 4

%if (NOTE_SAVE_HEADER_SIZE+NOTE_MAX) > ((NOTE_SAVE_LAST_LBA-NOTE_SAVE_FIRST_LBA+1)*512)
    %error "Notepad persistence range is too small"
%endif
%if (PAINT_SAVE_HEADER_SIZE+PAINT_PERSIST_BYTES) > ((PAINT_SAVE_LAST_LBA-PAINT_SAVE_FIRST_LBA+1)*512)
    %error "Paint persistence range is too small"
%endif

%if (NOTE_UNDO_OFF + NOTE_MAX + 1) > (PROC_ARENA_WORDS * 2)
    %error "Notepad document and undo regions exceed the process arena"
%endif

; Compile-time proof for the complete conventional-memory partition used by
; the GUI.  Keeping the buffers disjoint is essential: process metadata is
; stored in segment zero, but the large document/canvas bytes live here.
%define PROC_REGION_END_SEG    (PROC_BASE_SEG + PROC_SEG_STEP)
%define SELECT_END_SEG         (SELECT_SEG + ((PAINT_CANVAS_STORAGE_SIZE + 15) >> 4))
%define UNDO_END_SEG           (UNDO_SEG + ((PAINT_CANVAS_STORAGE_SIZE + 15) >> 4))
%define BACKBUF_END_SEG        (BACKBUF_SEG + (((SCREEN_W * SCREEN_H) + 15) >> 4))
%define CLIP_END_SEG           (CLIP_SEG + (((CLIP_MAX + 1) + 15) >> 4))

%if PROC_REGION_END_SEG > SELECT_SEG
    %error "Process arenas overlap the Paint selection buffer"
%endif
%if SELECT_END_SEG > UNDO_SEG
    %error "Paint selection and undo buffers overlap"
%endif
%if UNDO_END_SEG > BACKBUF_SEG
    %error "Paint undo and screen back buffers overlap"
%endif
%if BACKBUF_END_SEG > CLIP_SEG
    %error "Screen back buffer overlaps the clipboard"
%endif
%if CLIP_END_SEG > STACK_SEG
    %error "Clipboard overlaps the GUI stack"
%endif
%if CUSTOM_CODE_SEG < UNDO_END_SEG
    %error "Custom editor overlay overlaps the GUI work buffers"
%endif
%if PROC_BACKING_PHYS < (CUSTOM_REDO_NEWLINE_PHYS + CUSTOM_SOURCE_CAPACITY)
    %error "Process backing store overlaps Custom Program extended buffers"
%endif
%if (CUSTOM_CODE_SEG+0x1000) > BACKBUF_SEG
    %error "Custom editor overlay overlaps the screen back buffer"
%endif

%define CALC_W                 266
%define CALC_H                 180
%define CALC_MIN_W             266
%define CALC_MIN_H             180
%define CALC_SCALE             10000000

; Calculator v6.0 uses signed 96-bit fixed point.  The supported real range is
; exactly -2^64 through +2^64, inclusive, with seven fractional decimal digits.
; Its transient multi-precision workspace reuses the second half of the
; existing 0600:0000 boot-sector I/O buffer.  Calculator actions and boot
; setting disk I/O are synchronous, so no persistent state is kept here.
%define CALC96_LIMIT_HI        0x00989680 ; (2^64 * 10,000,000) >> 64
%define CALC96_A               0x6100     ; 3 dwords
%define CALC96_B               0x610C     ; 3 dwords
%define CALC96_C               0x6118     ; 3 dwords
%define CALC96_REM             0x6124     ; 3 dwords
%define CALC96_WIDE            0x6130     ; 6 dwords
%define CALC96_PROD            0x6148     ; 6 dwords
%define CALC96_LOW             0x6160     ; qword
%define CALC96_HIGH            0x6168     ; qword
%define CALC96_MID             0x6170     ; qword
%define CALC96_SIGN            0x6178     ; byte
%define CALC96_SIGN_B          0x6179     ; byte
%define CALC96_DIGIT           0x617A     ; byte
%define CALC96_FRAC            0x617C     ; dword

; Captured classic-button actions. A button executes only when released inside.
%define BTN_NONE               0
%define BTN_TASK_MAIN          1
%define BTN_TASK_PAINT         2
%define BTN_TASK_NOTE          3
%define BTN_TASK_CALC          4
%define BTN_MAIN_MIN           10
%define BTN_MAIN_MAX           11
%define BTN_MAIN_CLOSE         12
%define BTN_MAIN_PAINT         14
%define BTN_MAIN_NOTE          15
%define BTN_MAIN_CALC          16
%define BTN_MAIN_CONTROL       17
%define BTN_MAIN_DEBUG         18
%define BTN_MAIN_CUSTOM        19
%define BTN_PAINT_MIN          20
%define BTN_PAINT_CLOSE        21
%define BTN_PAINT_ERASE        22
%define BTN_PAINT_CLEAR        23
%define BTN_PAINT_MAX          24
%define BTN_PAINT_PALETTE      25
%define BTN_PALETTE_CLOSE      26
%define BTN_PALETTE_OK         27
%define BTN_NOTE_MIN           30
%define BTN_NOTE_CLOSE         31
%define BTN_NOTE_SCROLL_UP     32
%define BTN_NOTE_SCROLL_DOWN   33
%define BTN_NOTE_PAGE_UP       34
%define BTN_NOTE_PAGE_DOWN   35
%define BTN_NOTE_MAX            36
%define BTN_CALC_MIN           40
%define BTN_CALC_CLOSE         41
%define BTN_CALC_MAX           43
%define BTN_SYS_MENU           44
%define BTN_MSG_CLOSE          45
%define BTN_MSG_OK             46
%define BTN_MSG_YES            47
%define BTN_MSG_NO             48
%define BTN_CONTROL_AUTORESTART 49
%define BTN_CALC_7             50
%define BTN_CALC_8             51
%define BTN_CALC_9             52
%define BTN_CALC_ADD           53
%define BTN_CALC_4             54
%define BTN_CALC_5             55
%define BTN_CALC_6             56
%define BTN_CALC_SUB           57
%define BTN_CALC_1             58
%define BTN_CALC_2             59
%define BTN_CALC_3             60
%define BTN_CALC_MUL           61
%define BTN_CALC_CLEAR         62
%define BTN_CALC_0             63
%define BTN_CALC_EQUAL         64
%define BTN_CALC_DIV           65
%define BTN_CALC_DECIMAL       66
%define BTN_CALC_PERCENT       67
%define BTN_CALC_SQRT          68
%define BTN_CALC_BACK          69
%define BTN_CONTROL_CLOSE      70
%define BTN_CONTROL_SWAP       71
%define BTN_CONTROL_BOOT_DOS   72
%define BTN_DEBUG_CLOSE        73
%define BTN_DEBUG_INT_TEST     74
%define BTN_DEBUG_INT_CLOSE    75
%define BTN_DEBUG_SCROLL_UP    76
%define BTN_DEBUG_SCROLL_DOWN  77
%define BTN_DEBUG_INT_ITEM     78
%define BTN_DEBUG_PROTECTED    79
%define BTN_DEBUG_LONG         80
%define BTN_DEBUG_BLUE         81
%define BTN_DEBUG_INT_EXEC     82
%define BTN_DEBUG_BLUE_TOGGLE  83
%define BTN_DEBUG_BLUE_CLOSE   84
%define BTN_DEBUG_BLUE_REAL    85
%define BTN_DEBUG_BLUE_PM      86
%define BTN_DEBUG_BLUE_LM      87
%define BTN_CUSTOM_CLOSE       88
%define BTN_CUSTOM_EXEC        89
%define BTN_CUSTOM_SCROLL_UP   90
%define BTN_CUSTOM_SCROLL_DOWN 91
%define BTN_CUSTOM_CONFIRM_YES 92
%define BTN_CUSTOM_CONFIRM_NO  93
%define BTN_CUSTOM_HSCROLL_LEFT 94
%define BTN_CUSTOM_HSCROLL_RIGHT 95
%define BTN_CUSTOM_EXEC_REAL   96
%define BTN_CUSTOM_EXEC_PM     97
%define BTN_CUSTOM_EXEC_LM     98
%define BTN_DEBUG_FAULT        99
%define BTN_DEBUG_FAULT_CLOSE  100
%define BTN_DEBUG_FAULT_NORMAL 101
%define BTN_DEBUG_FAULT_DOUBLE 102
%define BTN_DEBUG_FAULT_TRIPLE 103
%define BTN_DEBUG_NORMAL_CLOSE 104
%define BTN_DEBUG_NORMAL_ITEM  105
%define BTN_DEBUG_NORMAL_SCROLL_UP 106
%define BTN_DEBUG_NORMAL_SCROLL_DOWN 107
%define BTN_CUSTOM_MIN         108
%define BTN_CUSTOM_MAX         109
%define BTN_CUSTOM_CONFIRM_CANCEL 110
%define BTN_TASK_BASE          120     ; BTN_TASK_BASE + process id
%define BTN_TASK_CUSTOM        (BTN_TASK_BASE+MAX_PROCS)

%define DEBUG_BLUE_X           28
%define DEBUG_BLUE_Y           36
%define DEBUG_BLUE_W           264
%define DEBUG_BLUE_H           126
%define DEBUG_FAULT_X          DEBUG_BLUE_X
%define DEBUG_FAULT_Y          DEBUG_BLUE_Y
%define DEBUG_FAULT_W          DEBUG_BLUE_W
%define DEBUG_FAULT_H          DEBUG_BLUE_H

%define DEBUG_PM_CODE32_SEL    0x0008
%define DEBUG_PM_DATA32_SEL    0x0010
%define DEBUG_PM_CODE16_SEL    0x0018
%define DEBUG_LM_CODE64_SEL    0x0020
%define DEBUG_PM_TSS_SEL       0x0028
%define DEBUG_PM_USER_CODE_SEL 0x0038
%define DEBUG_PM_USER_DATA_SEL 0x0040
%define DEBUG_PM_CODE32_ACCESS 0x9B
%define DEBUG_PM_DATA32_ACCESS 0x93
%define DEBUG_PM_CODE16_ACCESS 0x9B
%define DEBUG_LM_CODE64_ACCESS 0x9B

%if ((DEBUG_PM_CODE32_ACCESS & 1) = 0) || ((DEBUG_PM_DATA32_ACCESS & 1) = 0) || ((DEBUG_PM_CODE16_ACCESS & 1) = 0) || ((DEBUG_LM_CODE64_ACCESS & 1) = 0)
    %error "Read-only Custom Program GDT descriptors must preset Accessed"
%endif

%define DEBUG_PM_PD_PHYS       0x00001000
%define DEBUG_PM_PT_PHYS       0x00002000
%define DEBUG_LM_PML4_PHYS     0x00001000
%define DEBUG_LM_PDPT_PHYS     0x00002000
%define DEBUG_LM_PD_PHYS       0x00003000
%define DEBUG_LM_PT_PHYS       0x00004000
%define DEBUG_PM_IDT32_PHYS    0x00005000
%define DEBUG_LM_IDT64_PHYS    0x00005200
%define DEBUG_LM_IST_TOP       0x000067F0
%define DEBUG_LM_STACK_TOP     0x00006FF0
%define DEBUG_PM_PANIC_STACK_TOP 0x00006FF0
%define CUSTOM_PROTECT_LOW_END    0x00006000
%define CUSTOM_PROTECT_STAGE_START 0x00007000
%define CUSTOM_PROTECT_STAGE_END  0x00020000
%define CUSTOM_PROTECT_STACK_START (STACK_SEG << 4)
%define CUSTOM_PROTECT_STACK_END   ((STACK_SEG + 0x0800) << 4)

%define CURSOR_W               13
%define CURSOR_H               16

%define CONTROL_W              224
%define CONTROL_H              142
%define CONTROL_CHECK_XOFF     18
%define CONTROL_SWAP_YOFF      34
%define CONTROL_BOOT_YOFF      56
%define CONTROL_AUTORESTART_YOFF 78
%define CONTROL_SPEED_YOFF     110
%define CONTROL_SLIDER_XOFF    72
%define CONTROL_SLIDER_W       126
%define CONTROL_SLIDER_STEPS   14

%define VMWARE_MAGIC                    0x564D5868
%define VMWARE_PORT                     0x5658
%define VMWARE_CMD_GETVERSION           10
%define VMWARE_CMD_ABSPOINTER_DATA      39
%define VMWARE_CMD_ABSPOINTER_STATUS    40
%define VMWARE_CMD_ABSPOINTER_COMMAND   41
%define VMWARE_CMD_ABSPOINTER_RESTRICT  86
%define VMMOUSE_CMD_ENABLE              0x45414552
%define VMMOUSE_CMD_DISABLE             0x000000F5
%define VMMOUSE_CMD_REQUEST_ABSOLUTE    0x53424152
%define VMMOUSE_VERSION_ID              0x3442554A
%define VMMOUSE_RELATIVE_PACKET         0x00010000
%define VMMOUSE_LEFT_BUTTON             0x20
%define VMMOUSE_RIGHT_BUTTON            0x10
%define VMMOUSE_MIDDLE_BUTTON           0x08
%define VMMOUSE_ERROR                   0xFFFF0000
%define VMMOUSE_RESTRICT_CPL0           0x01

; =============================================================================
; Sector 0: loader + 55 AA
; =============================================================================
boot_start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    cld
    mov [boot_drive], dl
    mov [os_boot_drive], dl
    ; Persistent byte in this MBR: 1 = graphical Program Manager, 0 = DOS.
    ; For the valid values 1/0 this compact mapping produces boot_action 0/2.
    mov al, [boot_default_gui]
    dec al
    and al, 2
    mov [boot_action], al

    ; Prefer EDD/LBA reads.
    mov ah, 0x41
    mov bx, 0x55AA
    mov dl, [boot_drive]
    int 0x13
    jc boot_try_chs
    cmp bx, 0xAA55
    jne boot_try_chs
    test cx, 1
    jz boot_try_chs

    mov si, boot_dap
    mov dl, [boot_drive]
    mov ah, 0x42
    int 0x13
    jc boot_try_chs

boot_edd_first_complete:
    ; The imported HEX image is a single short transfer. MiniWin uses two
    ; transfers so neither EDD request exceeds the widely supported 127-sector
    ; BIOS limit: all but the final base sector, then that sector + extension.
    cmp byte [boot_action], 1
    je boot_load_complete
    mov si, boot_tail_dap
    mov dl, [boot_drive]
    mov ah, 0x42
    int 0x13
    jnc boot_load_complete

boot_try_chs:
    xor ah, ah
    mov dl, [boot_drive]
    int 0x13

    mov ah, 0x08
    mov dl, [boot_drive]
    int 0x13
    jc boot_error

    mov al, cl
    and al, 0x3F
    jz boot_error
    mov [boot_spt], al

    mov al, dh
    inc al
    jz boot_error
    mov [boot_heads], al

    ; INT 13h/AH=08 may return a parameter-table pointer in ES:DI.
    ; Action 1 loads the imported HEX editor at physical 0000:7E00.
    ; Actions 0 and 2 load/restore the original MiniWin stage 2 at 07E0:0000.
    cmp byte [boot_action], 1
    je .hex_params

    push word STAGE2_SEG
    pop es
    mov word [boot_lba], 1
    mov word [boot_dest], 0
    mov word [boot_left], STAGE2_SECTORS + STAGE2_EXT_SECTORS
    jmp short .params_ready

.hex_params:
    push word STAGE2_SEG
    pop es
    mov word [boot_lba], HEX_IMAGE_LBA
    mov word [boot_dest], 0x0000
    mov word [boot_left], HEX_EDITOR_SECTORS

.params_ready:

boot_chs_next:
    cmp word [boot_left], 0
    je boot_load_complete

    ; Convert small LBA to CHS.
    mov ax, [boot_lba]
    xor dx, dx
    xor bx, bx
    mov bl, [boot_spt]
    div bx
    mov cl, dl
    inc cl

    xor dx, dx
    xor bx, bx
    mov bl, [boot_heads]
    div bx
    cmp ax, 1023
    ja boot_error

    mov ch, al
    mov al, ah
    and al, 3
    shl al, 6
    or cl, al
    mov dh, dl

    mov bx, [boot_dest]
    mov si, 3
boot_chs_retry:
    mov ax, 0x0201
    mov dl, [boot_drive]
    int 0x13
    jnc boot_chs_ok

    xor ah, ah
    mov dl, [boot_drive]
    int 0x13
    dec si
    jnz boot_chs_retry
    jmp boot_error

boot_chs_ok:
    add word [boot_dest], 512
    jnc .dest_ready
    mov ax, es
    add ax, 0x1000
    mov es, ax
.dest_ready:
    inc word [boot_lba]
    dec word [boot_left]
    jmp boot_chs_next

boot_load_complete:
    cmp byte [boot_action], 1
    je boot_jump_hexeditor
    cmp byte [boot_action], 2
    je boot_jump_dos

boot_jump_stage2:
    ; Execute the complete stage-2 image in a single code segment.  Near
    ; calls into the extended Paint routines now resolve to their real linear
    ; addresses instead of wrapping at IP=FFFFh and jumping into data.
    jmp STAGE2_SEG:0x0000

boot_jump_hexeditor:
    jmp 0x0000:0x7E00

boot_jump_dos:
    ; The original stage 2 has just been restored from disk.
    ; A direct default-to-DOS boot bypasses stage2_start, so initialize the
    ; blue-screen gate here as well.  Boot preference and blue-screen policy
    ; are independent.  Bit 7 is set only by the resident HEX return loader,
    ; where an explicit Debug toggle must survive the overlay round trip.
    test byte [hex_launch_mode], 0x80
    jnz .preserve_blue_gate
    mov byte [BLUESCREEN_ENABLE_ADDR], 1
.preserve_blue_gate:
    and byte [hex_launch_mode], 1
    jmp STAGE2_SEG:(enter_dos_mode-stage2_start)

; Entered from the DOS HEX command.  This code resides in sector 0, so it is
; not destroyed while the editor payload overwrites physical 7E00h..FDFFh.
hex_launch_loader:
    mov ah, 1
    mov si, hex_dap
    jmp short boot_external_load

; Entered by ESC or Shift+ESC in the imported editor.  Restore MiniWin stage 2
; from the original boot disk, then resume the DOS command environment.
hex_return_loader:
    or byte [hex_launch_mode], 0x80
    mov ah, 2
    mov si, boot_dap

boot_external_load:
    cli
    xor bx, bx
    mov ds, bx
    mov es, bx
    mov [boot_action], ah
    mov dl, [os_boot_drive]
    mov [boot_drive], dl
    mov ah, 0x42
    int 0x13
    jnc boot_edd_first_complete
    jmp boot_try_chs

boot_error:
    mov si, boot_error_text
boot_print:
    lodsb
    test al, al
    jz boot_hang
    mov ah, 0x0E
    mov bx, 0x0007
    int 0x10
    jmp boot_print
boot_hang:
    cli
    hlt
    jmp boot_hang

boot_drive          db 0
boot_default_gui   db 1    ; persisted in LBA 0: 1=GUI, 0=DOS
boot_autorestart   db 1    ; persisted in LBA 0: 1=automatic BSOD reset, 0=Ctrl+Alt+Del only
os_boot_drive       db 0
boot_action         db 0    ; 0=normal boot, 1=launch HEX, 2=return to DOS
hex_launch_mode     db 0    ; 0=disk sector editor, 1=physical memory editor
boot_spt            db 0
boot_heads      db 0
boot_lba        dw 0
boot_dest       dw 0
boot_left       dw 0

boot_dap:
    db 0x10, 0
    dw STAGE2_SECTORS-1
    dw 0x0000
    dw STAGE2_SEG
    dq 1

boot_tail_dap:
    db 0x10, 0
    dw 1 + STAGE2_EXT_SECTORS
    dw 0x0000
    dw STAGE2_SEG + ((STAGE2_SECTORS-1) * 0x20)
    dq STAGE2_SECTORS

hex_dap:
    db 0x10, 0
    dw HEX_EDITOR_SECTORS
    dw 0x0000
    dw STAGE2_SEG
    dq HEX_IMAGE_LBA

boot_error_text db 'Disk read error', 0

times 510-($-$$) db 0
dw 0xAA55

; =============================================================================
; Sector 1 and later: graphical environment
; =============================================================================
stage2_start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    ; A normal boot always starts with blue screens enabled.  The byte lives
    ; outside the replaceable stage-2/HEX image so the Debug setting survives
    ; a DOS -> HEX -MEM -> DOS round trip.
    mov byte [BLUESCREEN_ENABLE_ADDR], 1
    ; The sector-0 loader reads the base and far extension in one contiguous
    ; transfer. Mark it present before any resident wrapper can call it.
    mov byte [custom_ext_loaded], 1
    mov ax, STACK_SEG
    mov ss, ax
    mov sp, STACK_TOP
    cld
    mov ax, GUI_SNAPSHOT_SEG
    mov es, ax
    mov dword es:[0], 0
    xor ax, ax
    mov es, ax

    call system_install_exception_hooks
    call init_font_and_video
    call init_state
    call init_mouse_support
    sti

    call redraw_all
    call mouse_cursor_show

main_loop:
    mov byte [system_watchdog_ticks], 0
    call poll_mouse
    cmp byte [mouse_changed], 0
    je .keyboard
    call mouse_cursor_hide
    call handle_mouse_events
    call mouse_cursor_show

.keyboard:
    mov ah, 0x01
    int 0x16
    jz .sleep
    call mouse_cursor_hide
    mov ah, 0x00
    int 0x16
    call handle_key
    call mouse_cursor_show

.sleep:
    sti
    ; The PS/2 backend is polled with IRQ12 disabled. HLT therefore used to
    ; wait for an unrelated keyboard/timer interrupt and made mouse motion
    ; visibly stutter. Keep polling continuously.
    nop
    jmp main_loop

; =============================================================================
; Global real-mode critical-error handling
; =============================================================================
; Real mode shares vectors 08h..0Fh with the master PIC.  The shared stubs
; inspect the PIC in-service register: real hardware IRQs are chained to the
; original BIOS handler, while CPU exceptions enter the global blue screen.
; This keeps the timer, keyboard and BIOS disk services working in both the
; MiniWin and DOS environments without leaving double fault unhandled.

%macro SYSTEM_EXCEPTION_STUB 2
%1:
    push ax
    mov al, %2
    jmp system_exception_common
%endmacro

%macro SYSTEM_SHARED_IRQ_STUB 3
%1:
    push ax
    push ds
    xor ax, ax
    mov ds, ax
    mov al, 0x0B
    out 0x20, al
    jmp short $+2
    in al, 0x20
    mov ah, al
    mov al, 0x0A
    out 0x20, al
    test ah, (1 << %3)
    jz %%cpu_fault
%if %2 = 8
    ; Own IRQ0 instead of entering BIOS timer code through BDA/EBDA state which
    ; the memory editor may have changed.  This keeps the watchdog independent
    ; of those tables and avoids calling through a damaged firmware data path.
    call system_timer_irq
%else
    pushf
    call far [system_old_ivt + (%2 * 4)]
%endif
    pop ds
    pop ax
    iret
%%cpu_fault:
    pop ds
    mov al, %2
    jmp system_exception_common
%endmacro

system_integrity_code_start:
SYSTEM_EXCEPTION_STUB system_exception_00, 0
SYSTEM_EXCEPTION_STUB system_exception_01, 1
SYSTEM_EXCEPTION_STUB system_exception_02, 2
SYSTEM_EXCEPTION_STUB system_exception_03, 3
SYSTEM_EXCEPTION_STUB system_exception_04, 4
SYSTEM_EXCEPTION_STUB system_exception_06, 6
SYSTEM_EXCEPTION_STUB system_exception_07, 7
SYSTEM_SHARED_IRQ_STUB system_exception_08, 8, 0
SYSTEM_SHARED_IRQ_STUB system_exception_09, 9, 1
SYSTEM_SHARED_IRQ_STUB system_exception_0a, 10, 2
SYSTEM_SHARED_IRQ_STUB system_exception_0b, 11, 3
SYSTEM_SHARED_IRQ_STUB system_exception_0c, 12, 4
SYSTEM_SHARED_IRQ_STUB system_exception_0d, 13, 5
SYSTEM_SHARED_IRQ_STUB system_exception_0e, 14, 6
SYSTEM_SHARED_IRQ_STUB system_exception_0f, 15, 7

system_exception_05:
    ; INT 05h and the CPU BOUND-range exception share one real-mode vector.
    ; A literal CD 05 software interrupt is not a CPU fault and must never open
    ; the blue screen (including while the blue-screen gate is disabled).
    ; Inspect the saved return CS:IP before entering the common panic path.
    push ax
    push bx
    push ds
    push bp
    mov bp, sp
    mov bx, [ss:bp+8]
    cmp bx, 2
    jb .cpu_bound_fault
    mov ax, [ss:bp+10]
    mov ds, ax
    cmp byte [bx-2], 0xCD
    jne .cpu_bound_fault
    cmp byte [bx-1], 0x05
    jne .cpu_bound_fault
.software_int:
    pop bp
    pop ds
    pop bx
    pop ax
    iret
.cpu_bound_fault:
    pop bp
    pop ds
    pop bx
    mov al, 5
    jmp system_exception_common

system_exception_common:
    ; With blue screens disabled, preserve the original interrupted stack and
    ; chain the firmware handler saved before our IVT hooks were installed.
    ; This test must precede the emergency-stack switch because that switch is
    ; deliberately irreversible.
    push bx
    xor bx, bx
    mov bl, al
    push ds
    xor ax, ax
    mov ds, ax
    cmp byte [BLUESCREEN_ENABLE_ADDR], 0
    jne .blue_enabled
    shl bx, 1
    shl bx, 1
    pushf
    call far [system_old_ivt + bx]
    pop ds
    pop bx
    pop ax
    iret
.blue_enabled:
    mov al, bl
    pop ds
    pop bx
    ; The interrupted stack may be corrupt.  Do not unwind it: switch to the
    ; known global emergency stack before drawing text.
    cli
    cld
    mov dl, al
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov [system_panic_vector], dl
    mov ax, STACK_SEG
    mov ss, ax
    mov sp, STACK_TOP
    mov al, dl
    jmp system_blue_screen

system_install_exception_hooks:
    pushf
    cli
    pusha
    push ds
    push es
    xor ax, ax
    mov ds, ax
    mov es, ax
    cmp byte [system_exception_hooks_installed], 0
    jne .done

    ; Preserve vectors 00h..0Fh so shared IRQs can be chained and the table can
    ; be restored before the stage-2 image is replaced by the HEX payload.
    xor si, si
    mov di, system_old_ivt
    mov cx, 32
    cld
    rep movsw
    mov si, system_exception_stub_offsets
    xor di, di
    mov cx, 16
.install:
    lodsw
    cmp di, (9 * 4)
    je .keep_bios_keyboard
    stosw
    mov ax, STAGE2_SEG
    stosw
    jmp short .next
.keep_bios_keyboard:
    add di, 4
.next:
    loop .install
    mov byte [system_exception_hooks_installed], 1
.done:
    pop es
    pop ds
    popa
    popf
    ret

system_uninstall_exception_hooks:
    pushf
    cli
    pusha
    push ds
    push es
    xor ax, ax
    mov ds, ax
    mov es, ax
    cmp byte [system_exception_hooks_installed], 0
    je .done
    mov si, system_old_ivt
    xor di, di
    mov cx, 32
    cld
    rep movsw
    mov byte [system_exception_hooks_installed], 0
.done:
    pop es
    pop ds
    popa
    popf
    ret

system_timer_irq:
    ; Maintain the standard BIOS tick value without entering the original
    ; timer ISR.  The comparison constant is the normal ticks-per-day value.
    inc dword [0x046C]
    cmp dword [0x046C], 0x001800B0
    jb .tick_ready
    sub dword [0x046C], 0x001800B0
    mov byte [0x0470], 1
.tick_ready:
    mov al, 0x20
    out 0x20, al
    cmp byte [system_watchdog_enabled], 1
    jne .done
    cmp byte [system_watchdog_ticks], 200
    jae .fatal
    inc byte [system_watchdog_ticks]
    ret
.fatal:
    cmp byte [BLUESCREEN_ENABLE_ADDR], 0
    jne .show_blue_screen
    mov byte [system_watchdog_ticks], 0
    ret
.show_blue_screen:
    mov al, [system_watchdog_reason]
    jmp system_blue_screen
.done:
    ret

system_integrity_code_end:

gui_snapshot_save:
    ; Called immediately before HEX replaces stage 2.  The header magic is
    ; committed last, so an interrupted copy can never be accepted as valid.
    pushf
    cli
    pusha
    push ds
    push es
    xor ax, ax
    mov ds, ax
    mov ax, GUI_SNAPSHOT_SEG
    mov es, ax
    mov dword es:[0], 0
    cmp dword [gui_session_cookie], GUI_SESSION_MAGIC
    jne .done
    mov word es:[4], gui_state_image_end-gui_state_image_start
    mov si, gui_state_image_start
    mov di, GUI_SNAPSHOT_DATA_OFF
    mov cx, gui_state_image_end-gui_state_image_start
    cld
    rep movsb

    ; A small additive checksum detects accidental edits of the snapshot page
    ; in HEX -mem and prevents WIN -KEEP from restoring corrupt GUI globals.
    mov ax, GUI_SNAPSHOT_SEG
    mov ds, ax
    mov si, GUI_SNAPSHOT_DATA_OFF
    mov cx, gui_state_image_end-gui_state_image_start
    xor bx, bx
.sum:
    lodsb
    xor ah, ah
    add bx, ax
    loop .sum
    mov es:[6], bx
    mov dword es:[0], GUI_SNAPSHOT_MAGIC
.done:
    pop es
    pop ds
    popa
    popf
    ret

gui_snapshot_restore:
    ; After the resident loader restores stage 2 from disk, rebuild the GUI
    ; globals before DOS modifies them.  Invalid/missing snapshots are simply
    ; ignored; WIN -KEEP will then fall back to a clean GUI initialization.
    pushf
    cli
    pusha
    push ds
    push es
    mov ax, GUI_SNAPSHOT_SEG
    mov ds, ax
    cmp dword [0], GUI_SNAPSHOT_MAGIC
    jne .invalid
    cmp word [4], gui_state_image_end-gui_state_image_start
    jne .invalid
    mov si, GUI_SNAPSHOT_DATA_OFF
    mov cx, gui_state_image_end-gui_state_image_start
    xor bx, bx
.sum:
    lodsb
    xor ah, ah
    add bx, ax
    loop .sum
    cmp bx, [6]
    jne .invalid

    mov dword [0], 0
    xor ax, ax
    mov es, ax
    mov si, GUI_SNAPSHOT_DATA_OFF
    mov di, gui_state_image_start
    mov cx, gui_state_image_end-gui_state_image_start
    cld
    rep movsb
    jmp short .done
.invalid:
    mov dword [0], 0
.done:
    pop es
    pop ds
    popa
    popf
    ret

system_panic_code_start:
system_blue_screen:
    ; AL=00h..0Fh for a real-mode CPU exception, or a defined internal stop
    ; code.  Unknown values deliberately use the generic internal reason.
    ; This entry is safe to call from MiniWin, DOS, or a real-mode exception.
    cli
    cld
    mov dl, al
    xor ax, ax
    mov ds, ax
    mov es, ax
    cmp byte [BLUESCREEN_ENABLE_ADDR], 0
    jne .blue_enabled
.blue_disabled_wait:
    xor si, si
    jmp system_bsod_wait_ctrl_alt_del
.blue_enabled:
    mov [system_panic_vector], dl
    mov ax, STACK_SEG
    mov ss, ax
    mov sp, STACK_TOP

    ; A panic must not enter firmware: IVT/BDA/EBDA state and the interrupted
    ; stack may already be damaged.  Program VGA mode 03h-compatible 80x25
    ; text registers and reload the ROM 8x16 font through memory/ports only.
    call system_vga_set_text_80x25
    xor ax, ax
    mov ds, ax
    mov ax, TEXT_SEG
    mov es, ax
    xor di, di
    mov ax, 0x1F20
    mov cx, 80*25
    rep stosw

    mov si, system_panic_title
    mov di, (0*80+25)*2
    call system_bsod_puts
    mov si, system_panic_line1
    mov di, (4*80+19)*2
    call system_bsod_puts
    mov si, system_panic_line2
    mov di, (6*80+26)*2
    call system_bsod_puts
    mov si, system_panic_line3
    mov di, (8*80+22)*2
    call system_bsod_puts
    cmp byte [boot_autorestart], 0
    je .automatic_line_done
    mov si, system_panic_line4
    mov di, (10*80+21)*2
    call system_bsod_puts
.automatic_line_done:

    mov dl, [system_panic_vector]
    mov di, (21*80+2)*2
    cmp dl, 16
    jae .internal_reason
    mov si, system_panic_cpu_prefix
    call system_bsod_puts
    mov al, dl
    call system_bsod_hex_byte
    mov al, ' '
    mov ah, 0x1F
    stosw
    xor bx, bx
    mov bl, dl
    shl bx, 1
    mov si, [system_exception_name_table+bx]
    call system_bsod_puts
    jmp .stopcode

.internal_reason:
    cmp dl, BSOD_STOP_NOTEPAD
    jne .check_tables
    mov si, system_panic_notepad_reason
    call system_bsod_puts
    jmp .stopcode
.check_tables:
    cmp dl, BSOD_STOP_TABLES
    jne .check_watchdog
    mov si, system_panic_tables_reason
    call system_bsod_puts
    jmp .stopcode
.check_watchdog:
    cmp dl, BSOD_STOP_WATCHDOG
    jne .check_reboot
    mov si, system_panic_watchdog_reason
    call system_bsod_puts
    jmp .stopcode
.check_reboot:
    cmp dl, BSOD_STOP_REBOOT
    jne .check_manual
    mov si, system_panic_reboot_reason
    call system_bsod_puts
    jmp .stopcode
.check_manual:
    cmp dl, BSOD_STOP_MANUAL
    jne .check_critical_write
    mov si, system_panic_manual_reason
    call system_bsod_puts
    jmp .stopcode
.check_critical_write:
    cmp dl, BSOD_STOP_CRITICAL_WRITE
    jne .generic_internal
    mov si, system_panic_critical_write_reason
    call system_bsod_puts
    jmp .stopcode
.generic_internal:
    mov si, system_panic_internal_reason
    call system_bsod_puts

.stopcode:
    mov di, (23*80+2)*2
    mov si, system_panic_stopcode_prefix
    call system_bsod_puts
    mov al, [system_panic_vector]
    call system_bsod_hex_byte

    ; Hide the hardware cursor directly, then poll the keyboard controller with
    ; interrupts still disabled.  No BIOS handler or HLT instruction is used.
    mov dx, 0x03D4
    mov al, 0x0A
    out dx, al
    inc dx
    in al, dx
    or al, 0x20
    out dx, al
    cli
    xor si, si
    cmp byte [boot_autorestart], 0
    je system_bsod_wait_ctrl_alt_del
    inc si
    jmp system_bsod_wait_ctrl_alt_del

system_bsod_wait_ctrl_alt_del:
    ; BL bit 0=Ctrl, bit 1=Alt. BH bit 0=E0 prefix, bit 1=F0 break prefix.
    ; Both translated scan set 1 and untranslated scan set 2 are accepted.
    ; CL is the remaining seconds and CH is the last RTC second. SI is nonzero
    ; only when the blue screen was actually rendered.
    cli
    xor bx, bx
    mov cl, 15
    xor bp, bp
    mov al, 0x80
    out 0x70, al
    in al, 0x71
    mov ch, al
    mov al, [0x0417]
    test al, 0x04
    jz .seed_alt
    or bl, 0x01
.seed_alt:
    test al, 0x08
    jz .poll
    or bl, 0x02
.poll:
    ; Reading CMOS on every spin is unnecessarily expensive on VMs. The
    ; keyboard controller is still checked every spin; RTC is sampled every
    ; 1024 iterations and continues running while interrupts are disabled.
    inc bp
    test bp, 0x03FF
    jnz .keyboard
    mov al, 0x80
    out 0x70, al
    in al, 0x71
    cmp al, ch
    je .keyboard
    mov ch, al
    test si, si
    jz .keyboard
    dec cl
    push ax
    push dx
    push di
    mov al, cl
    aam 10
    mov dl, al
    mov al, ah
    test al, al
    jnz .tens
    mov al, ' '
    jmp short .put_tens
.tens:
    add al, '0'
.put_tens:
    mov ah, 0x1F
    mov di, (10*80+47)*2
    stosw
    mov al, dl
    add al, '0'
    mov ah, 0x1F
    stosw
    pop di
    pop dx
    pop ax
.count_ready:
    test cl, cl
    jz system_bsod_hard_reset
.keyboard:
    mov dx, 0x0064
    in al, dx
    test al, 0x01
    jz .poll
    mov ah, al
    mov dx, 0x0060
    in al, dx
    test ah, 0x20
    jnz .clear_prefix
    cmp al, 0xE0
    je .e0_prefix
    cmp al, 0xF0
    je .f0_prefix
    cmp al, 0x1D
    je .ctrl_set1_make
    cmp al, 0x9D
    je .ctrl_set1_break
    cmp al, 0x38
    je .alt_set1_make
    cmp al, 0xB8
    je .alt_set1_break
    cmp al, 0x14
    je .ctrl_set2
    cmp al, 0x11
    je .alt_set2
    cmp al, 0x53
    je .delete_set1
    cmp al, 0x71
    jne .clear_prefix
    test bh, 0x01
    jz .clear_prefix
    test bh, 0x02
    jnz .clear_prefix
    jmp short .check_reset
.delete_set1:
    test bh, 0x02
    jnz .clear_prefix
.check_reset:
    ; Merge the last BIOS modifier flags in case IRQ1 consumed Ctrl/Alt just
    ; before CLI, then prioritize Delete immediately over unrelated key data.
    mov al, [0x0417]
    test al, 0x04
    jz .check_bda_alt
    or bl, 0x01
.check_bda_alt:
    test al, 0x08
    jz .test_chord
    or bl, 0x02
.test_chord:
    mov al, bl
    and al, 0x03
    cmp al, 0x03
    je system_bsod_hard_reset
.clear_prefix:
    xor bh, bh
    jmp .poll
.e0_prefix:
    or bh, 0x01
    jmp .poll
.f0_prefix:
    or bh, 0x02
    jmp .poll
.ctrl_set1_make:
    or bl, 0x01
    jmp .clear_prefix
.ctrl_set1_break:
    and bl, 0xFE
    jmp .clear_prefix
.alt_set1_make:
    or bl, 0x02
    jmp .clear_prefix
.alt_set1_break:
    and bl, 0xFD
    jmp .clear_prefix
.ctrl_set2:
    test bh, 0x02
    jnz .ctrl_set1_break
    jmp short .ctrl_set1_make
.alt_set2:
    test bh, 0x02
    jnz .alt_set1_break
    jmp short .alt_set1_make

system_bsod_hard_reset:
    ; Try the chipset reset port first, then the 8042 reset command, and finally
    ; force a triple fault. Do not jump to INT 19h, F000:FFF0, or 0000:7C00:
    ; those paths retain controller/CPU state and can crash VMware or leave
    ; the keyboard unusable.
    cli
    mov dx, 0x0CF9
    mov al, 0x06
    out dx, al
    mov dx, 0x0064
    mov al, 0xFE
    out dx, al
    lidt [system_reset_null_idtr]
    int 3
.reset_pending:
    hlt
    jmp short .reset_pending

system_vga_set_text_80x25:
    ; Direct standard VGA 720x400 text timing (80 columns, 25 rows, 9x16
    ; cells).  No BIOS interrupt, saved IVT entry, BDA field, or EBDA field is
    ; read here.  This also converts an active 80x50 text screen to 80x25.
    push ax
    push bx
    push cx
    push dx
    push si

    mov dx, 0x03C2
    mov al, 0x67
    out dx, al

    mov si, system_vga_text_seq
    xor bx, bx
    mov cx, 5
.seq_loop:
    mov dx, 0x03C4
    mov al, bl
    out dx, al
    inc dx
    lodsb
    out dx, al
    inc bl
    loop .seq_loop

    ; Unlock CRTC registers 00h..07h and then write the full timing table.
    mov dx, 0x03D4
    mov al, 0x03
    out dx, al
    inc dx
    in al, dx
    or al, 0x80
    out dx, al
    dec dx
    mov al, 0x11
    out dx, al
    inc dx
    in al, dx
    and al, 0x7F
    out dx, al

    mov si, system_vga_text_crtc
    xor bx, bx
    mov cx, 25
.crtc_loop:
    mov dx, 0x03D4
    mov al, bl
    out dx, al
    inc dx
    lodsb
    out dx, al
    inc bl
    loop .crtc_loop

    mov si, system_vga_text_gc
    xor bx, bx
    mov cx, 9
.gc_loop:
    mov dx, 0x03CE
    mov al, bl
    out dx, al
    inc dx
    lodsb
    out dx, al
    inc bl
    loop .gc_loop

    mov si, system_vga_text_ac
    xor bx, bx
    mov cx, 21
.ac_loop:
    mov dx, 0x03DA
    in al, dx
    mov dx, 0x03C0
    mov al, bl
    out dx, al
    lodsb
    out dx, al
    inc bl
    loop .ac_loop

    call system_vga_load_font_8x16

    ; Unblank the attribute controller and allow every DAC entry.
    mov dx, 0x03DA
    in al, dx
    mov dx, 0x03C0
    mov al, 0x20
    out dx, al
    mov dx, 0x03C6
    mov al, 0xFF
    out dx, al
    ; Program panic colors last.  This avoids any SVGA implementation treating
    ; the attribute unblank/PEL-mask sequence as a reason to retain mode-13h
    ; DAC state.
    call system_vga_set_bsod_palette

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

system_vga_load_font_8x16:
    ; The font address was obtained during stable video initialization.  Copy
    ; 256 glyphs into VGA plane 2 without calling INT 10h.
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds
    push es
    mov ax, [BLUESCREEN_FONT_SEG_ADDR]
    test ax, ax
    jz .done
    mov si, [BLUESCREEN_FONT_OFF_ADDR]
    mov ds, ax
    mov ax, 0xA000
    mov es, ax

    mov dx, 0x03C4
    mov ax, 0x0402
    out dx, ax
    mov ax, 0x0704
    out dx, ax
    mov dx, 0x03CE
    mov ax, 0x0204
    out dx, ax
    mov ax, 0x0005
    out dx, ax
    mov ax, 0x0406
    out dx, ax

    xor di, di
    mov bp, 256
.glyph:
    mov cx, 16
    rep movsb
    add di, 16
    dec bp
    jnz .glyph

    ; Restore the normal odd/even text-memory mapping at B8000h.
    mov dx, 0x03C4
    mov ax, 0x0302
    out dx, ax
    mov ax, 0x0304
    out dx, ax
    mov dx, 0x03CE
    mov ax, 0x0004
    out dx, ax
    mov ax, 0x1005
    out dx, ax
    mov ax, 0x0E06
    out dx, ax
.done:
    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

system_vga_set_bsod_palette:
    ; The panic attribute table below maps foreground 15 directly to DAC 0Fh.
    ; Program both 0Fh and the legacy mode-03h mapping 3Fh as white so neither
    ; VGA implementation can expose the old mode-13h 52,52,255 entry.  VGA DAC
    ; components are six-bit; 63,63,63 is displayed as 255,255,255.
    push ax
    push cx
    push dx
    mov cx, 3
.program:
    mov dx, 0x03C8
    mov al, 0x01
    out dx, al
    inc dx
    xor al, al
    out dx, al
    out dx, al
    mov al, 42
    out dx, al
    dec dx
    mov al, 0x0F
    out dx, al
    inc dx
    mov al, 63
    out dx, al
    out dx, al
    out dx, al
    dec dx
    mov al, 0x3F
    out dx, al
    inc dx
    mov al, 63
    out dx, al
    out dx, al
    out dx, al

    ; Read both possible white entries back.  Retry the direct programming a
    ; few times if an emulator/SVGA latch did not accept the first sequence.
    mov dx, 0x03C7
    mov al, 0x0F
    out dx, al
    mov dx, 0x03C9
    in al, dx
    cmp al, 63
    jne .retry
    in al, dx
    cmp al, 63
    jne .retry
    in al, dx
    cmp al, 63
    jne .retry
    mov dx, 0x03C7
    mov al, 0x3F
    out dx, al
    mov dx, 0x03C9
    in al, dx
    cmp al, 63
    jne .retry
    in al, dx
    cmp al, 63
    jne .retry
    in al, dx
    cmp al, 63
    je .done
.retry:
    loop .program
.done:
    pop dx
    pop cx
    pop ax
    ret

system_vga_text_seq:
    db 0x03,0x00,0x03,0x00,0x02
system_vga_text_crtc:
    db 0x5F,0x4F,0x50,0x82,0x55,0x81,0xBF,0x1F
    db 0x00,0x4F,0x0D,0x0E,0x00,0x00,0x00,0x50
    db 0x9C,0x0E,0x8F,0x28,0x1F,0x96,0xB9,0xA3,0xFF
system_vga_text_gc:
    db 0x00,0x00,0x00,0x00,0x00,0x10,0x0E,0x00,0xFF
system_vga_text_ac:
    ; Identity mapping makes text attribute foreground 0Fh select DAC 0Fh.
    db 0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07
    db 0x08,0x09,0x0A,0x0B,0x0C,0x0D,0x0E,0x0F
    db 0x0C,0x00,0x0F,0x08,0x00

system_bsod_puts:
    lodsb
    test al, al
    jz .done
    mov ah, 0x1F
    stosw
    jmp system_bsod_puts
.done:
    ret

system_bsod_hex_byte:
    push ax
    push dx
    mov dl, al
    shr al, 4
    call system_bsod_hex_nibble
    mov al, dl
    and al, 0x0F
    call system_bsod_hex_nibble
    pop dx
    pop ax
    ret

system_bsod_hex_nibble:
    cmp al, 10
    jb .digit
    add al, 'A'-10
    jmp short .emit
.digit:
    add al, '0'
.emit:
    mov ah, 0x1F
    stosw
    ret

system_panic_code_end:
system_exception_stub_offsets:
    dw system_exception_00-stage2_start, system_exception_01-stage2_start
    dw system_exception_02-stage2_start, system_exception_03-stage2_start
    dw system_exception_04-stage2_start, system_exception_05-stage2_start
    dw system_exception_06-stage2_start, system_exception_07-stage2_start
    dw system_exception_08-stage2_start, system_exception_09-stage2_start
    dw system_exception_0a-stage2_start, system_exception_0b-stage2_start
    dw system_exception_0c-stage2_start, system_exception_0d-stage2_start
    dw system_exception_0e-stage2_start, system_exception_0f-stage2_start

system_exception_name_table:
    dw system_exc_00, system_exc_01, system_exc_02, system_exc_03
    dw system_exc_04, system_exc_05, system_exc_06, system_exc_07
    dw system_exc_08, system_exc_09, system_exc_0a, system_exc_0b
    dw system_exc_0c, system_exc_0d, system_exc_0e, system_exc_0f

system_exception_hooks_installed db 0
system_panic_vector db 0xFF
system_display_mode db 0          ; 0=text, 1=320x200 graphics
system_watchdog_enabled db 0
system_watchdog_ticks db 0
system_watchdog_reason db BSOD_STOP_WATCHDOG
system_old_ivt times (16*4) db 0
system_reset_null_idtr:
    dw 0
    dq 0

system_panic_title      db '*** SYSTEM CRITICAL ERROR ***',0
system_panic_line1      db 'The system can no longer continue safely.',0
system_panic_line2      db 'Please restart the computer.',0
system_panic_line3      db 'Press Ctrl+Alt+Del to hard restart.',0
system_panic_line4      db 'Automatic hard restart in 15 seconds.',0
system_panic_cpu_prefix db 'Reason: CPU exception 0x',0
system_panic_pm_prefix db 'Reason: protected-mode CPU exception 0x',0
system_panic_lm_prefix db 'Reason: long-mode CPU exception 0x',0
system_panic_double_suffix db ' - Double fault',0
system_panic_notepad_reason db 'Reason: Notepad buffer boundary violation',0
system_panic_tables_reason db 'Reason: critical IVT/BDA integrity check failed',0
system_panic_watchdog_reason db 'Reason: system execution watchdog timeout',0
system_panic_reboot_reason db 'Reason: soft reboot stopped responding',0
system_panic_manual_reason db 'Reason: manually triggered blue screen',0
system_panic_critical_write_reason db 'Reason: critical live-memory write detected',0
system_panic_internal_reason db 'Reason: unrecoverable internal system failure',0
system_panic_stopcode_prefix db 'Stopcode: 0x',0
system_exc_00 db '- Divide error',0
system_exc_01 db '- Debug exception',0
system_exc_02 db '- Non-maskable interrupt',0
system_exc_03 db '- Breakpoint',0
system_exc_04 db '- Overflow',0
system_exc_05 db '- Bounds check',0
system_exc_06 db '- Invalid opcode',0
system_exc_07 db '- Coprocessor unavailable',0
system_exc_08 db '- Double fault',0
system_exc_09 db '- Coprocessor segment overrun',0
system_exc_0a db '- Invalid task state segment',0
system_exc_0b db '- Segment not present',0
system_exc_0c db '- Stack fault',0
system_exc_0d db '- General protection fault',0
system_exc_0e db '- Page fault',0
system_exc_0f db '- Reserved exception',0

; =============================================================================
; Data
; =============================================================================
gui_state_image_start:
gui_session_cookie  dd 0
font_seg            dw 0
font_off            dw 0
draw_seg            dw VGA_SEG

main_x              dw 0
main_y              dw 0
main_w              dw 0
main_h              dw 0
main_restore_x      dw 0
main_restore_y      dw 0
main_restore_w      dw 0
main_restore_h      dw 0
main_minimized      db 0
main_maximized      db 0
main_app_x1         dw 0
main_app_x2         dw 0
main_app_x3         dw 0
main_app_x4         dw 0
main_app_btn_w      dw 0
main_app_btn_w_last dw 0

; Fixed process table. Slots 1..8 own extended-memory 48-KiB backing arenas.
; Metadata itself lives in the unused protected page-5 tail (5810h..5FFFh),
; outside the replaceable Stage-2 image. Custom execution already maps this
; whole page read-only, so a payload cannot corrupt scheduler state.
ABSOLUTE 0x5900
proc_type               resb MAX_PROCS
proc_minimized          resb MAX_PROCS
proc_x                  resw MAX_PROCS
proc_y                  resw MAX_PROCS
proc_w                  resw MAX_PROCS
proc_h                  resw MAX_PROCS
proc_restore_x          resw MAX_PROCS
proc_restore_y          resw MAX_PROCS
proc_restore_w          resw MAX_PROCS
proc_restore_h          resw MAX_PROCS
proc_maximized          resb MAX_PROCS
proc_paint_color        resb MAX_PROCS
proc_paint_eraser       resb MAX_PROCS
proc_paint_rainbow      resb MAX_PROCS
proc_paint_phase        resb MAX_PROCS
proc_paint_brush        resb MAX_PROCS
proc_paint_tool         resb MAX_PROCS
proc_paint_text_sel     resb MAX_PROCS
proc_paint_text_input   resb MAX_PROCS
proc_paint_text_size    resb MAX_PROCS
proc_paint_canvas_w     resw MAX_PROCS
proc_paint_canvas_h     resw MAX_PROCS
proc_paint_text_active  resb MAX_PROCS
proc_paint_text_x       resw MAX_PROCS
proc_paint_text_y       resw MAX_PROCS
proc_paint_text_len     resw MAX_PROCS
proc_paint_text_cursor  resw MAX_PROCS
proc_paint_text_anchor  resw MAX_PROCS
proc_paint_text_sel_active resb MAX_PROCS
proc_paint_text_mouse_sel resb MAX_PROCS
proc_paint_palette_open resb MAX_PROCS
proc_paint_rgb_focus    resb MAX_PROCS
proc_paint_rgb_r        resb MAX_PROCS
proc_paint_rgb_g        resb MAX_PROCS
proc_paint_rgb_b        resb MAX_PROCS
proc_paint_custom_color resb MAX_PROCS
proc_paint_custom_active resb MAX_PROCS
proc_paint_rgb_replace  resb MAX_PROCS
proc_painting_active    resb MAX_PROCS
proc_paint_prev_valid   resb MAX_PROCS
proc_paint_prev_x       resw MAX_PROCS
proc_paint_prev_y       resw MAX_PROCS
proc_paint_undo         resb MAX_PROCS
proc_dirty              resb MAX_PROCS
proc_has_saved          resb MAX_PROCS
proc_note_focus         resb MAX_PROCS
proc_note_len           resw MAX_PROCS
proc_note_cursor        resw MAX_PROCS
proc_note_anchor        resw MAX_PROCS
proc_note_scroll        resw MAX_PROCS
proc_note_sel           resb MAX_PROCS
proc_note_mouse_sel     resb MAX_PROCS
proc_note_undo_valid    resb MAX_PROCS
proc_note_undo_sel      resb MAX_PROCS
proc_note_undo_len      resw MAX_PROCS
proc_note_undo_cursor   resw MAX_PROCS
proc_note_undo_anchor   resw MAX_PROCS
proc_note_undo_scroll   resw MAX_PROCS
proc_calc_acc           resd (MAX_PROCS*3)
proc_calc_current       resd (MAX_PROCS*3)
proc_calc_op            resb MAX_PROCS
proc_calc_entry         resb MAX_PROCS
proc_calc_error         resb MAX_PROCS
proc_calc_fresh         resb MAX_PROCS
proc_calc_decimal       resb MAX_PROCS
proc_calc_frac          resb MAX_PROCS
process_table_end:
%if process_table_end > 0x6000
    %error "Process metadata exceeds protected page-5 workspace"
%endif
SECTION .text

active_pid          db 0
active_type         db 0
active_data_seg     dw 0
proc_arena_pid      db 0        ; process currently resident in PROC_BASE_SEG
next_spawn          db 0

paint_x             dw 0
paint_y             dw 0
paint_w             dw PAINT_W
paint_h             dw PAINT_H
paint_restore_x     dw 0
paint_restore_y     dw 0
paint_restore_w     dw PAINT_W
paint_restore_h     dw PAINT_H
paint_maximized     db 0
paint_open          db 0
paint_minimized     db 0
paint_color         db 0
paint_eraser        db 0
paint_rainbow       db 0
paint_rainbow_phase db 0
paint_brush_size    db 0
paint_tool          db 0
paint_text_selected db 0xFF
paint_text_input    db 0
paint_text_key_char db 0
paint_text_key_scan db 0
paint_text_size     db 1
paint_canvas_w      dw PAINT_CANVAS_DEFAULT_W
paint_canvas_h      dw PAINT_CANVAS_DEFAULT_H
paint_text_active   db 0
paint_text_x        dw 0
paint_text_y        dw 0
paint_text_len      dw 0
paint_text_cursor   dw 0
paint_text_anchor   dw 0
paint_text_sel_active db 0
paint_text_mouse_select db 0
paint_palette_open  db 0
paint_rgb_focus     db 0
paint_rgb_r         db 0
paint_rgb_g         db 0
paint_rgb_b         db 255
paint_custom_color  db COL_WHITE
paint_custom_active db 0
paint_rgb_replace   db 0
painting_active     db 0
paint_prev_valid    db 0
paint_prev_x        dw 0
paint_prev_y        dw 0
paint_target_x      dw 0
paint_target_y      dw 0
paint_live_active   db 0
paint_live_started  db 0
paint_live_prev_valid db 0
paint_live_prev_x   dw 0
paint_live_prev_y   dw 0
paint_pending_action db PAINT_PENDING_NONE
paint_pending_x      dw 0
paint_pending_y      dw 0
paint_canvas_screen_x dw 0
paint_canvas_screen_y dw 0
paint_canvas_screen_w dw 0
paint_canvas_screen_h dw 0
paint_screen_row    dw 0
paint_screen_col    dw 0
paint_src_row_off   dw 0
paint_mapped_x      dw 0
paint_cell_x0       dw 0
paint_cell_y0       dw 0
paint_cell_w        dw 0
paint_present_x     dw 0
paint_custom_x      dw 0
paint_rgb_button_x  dw 0
paint_clear_button_x dw 0
text_box_x          dw 0
text_local_x        dw 0
text_local_y        dw 0
text_caret_x        dw 0
text_caret_y        dw 0
text_caret_valid    db 0
text_char_selected  db 0
text_point_x        dw 0
text_target_row     dw 0
text_target_col     dw 0
text_sel_start      dw 0
text_sel_end        dw 0
shape_start_x       dw 0
shape_start_y       dw 0
shape_end_x         dw 0
shape_end_y         dw 0
shape_dx_signed     dw 0
shape_dy_signed     dw 0
shape_abs_dx        dw 0
shape_abs_dy        dw 0
shape_color         db 0
shape_center_x      dw 0
shape_center_y      dw 0
shape_radius_x      dw 0
shape_radius_y      dw 0
shape_point_index   dw 0
shape_point_x       dw 0
shape_point_y       dw 0
shape_prev_x        dw 0
shape_prev_y        dw 0
line_fixed_x0       dw 0
line_fixed_y0       dw 0
line_fixed_x1       dw 0
line_fixed_y1       dw 0
resize_canvas_new_w dw 0
resize_canvas_new_h dw 0
undo_available      db 0
paint_undo_pid       db 0xFF

note_x              dw 0
note_y              dw 0
note_w              dw NOTE_W
note_h              dw NOTE_H
note_restore_x      dw 0
note_restore_y      dw 0
note_restore_w      dw NOTE_W
note_restore_h      dw NOTE_H
note_maximized      db 0
note_open           db 0
note_minimized      db 0
note_focus          db 0
note_len            dw 0
note_cursor         dw 0
note_anchor         dw 0
note_scroll_row     dw 0
note_sel_active     db 0
note_mouse_select   db 0
note_undo_valid     db 0
note_undo_sel       db 0
note_undo_len       dw 0
note_undo_cursor    dw 0
note_undo_anchor    dw 0
note_undo_scroll    dw 0
note_target_row     dw 0
note_target_col     dw 0
note_sel_start_tmp  dw 0
note_sel_end_tmp    dw 0
note_delete_start   dw 0
note_delete_end     dw 0
note_insert_ptr     dw 0
note_insert_seg     dw 0
note_insert_len     dw 0
note_insert_char_tmp db 0
note_cache_total_pid db 0xFF
note_cache_total_len dw 0
note_cache_total_cols dw 0
note_cache_total_rows dw 1
note_cache_pos_pid  db 0xFF
note_cache_pos_len  dw 0
note_cache_pos_cols dw 0
note_cache_pos_index dw 0
note_cache_pos_row  dw 0
note_cache_pos_col  dw 0
note_edit_group_pid db 0xFF
note_edit_group_kind db 0
note_edit_group_tick dw 0
note_edit_group_cursor dw 0
note_edit_group_size dw 0
note_batch_input    db 0
note_batch_changed  db 0
note_scrollbar_x    dw 0
note_scrollbar_y    dw 0
note_track_y        dw 0
note_thumb_y        dw 0
note_thumb_h        dw 0
note_max_scroll_tmp dw 0
note_text_x_dyn     dw 0
note_text_y_dyn     dw 0
note_text_w_dyn     dw 0
note_text_h_dyn     dw 0
note_view_w_dyn     dw 0
note_cols_dyn       dw NOTE_COLS
note_rows_dyn       dw NOTE_ROWS
note_track_h        dw 0
note_total_rows_tmp dw 0
note_thumb_range    dw 0
note_thumb_drag_offset dw 0
clipboard_len       dw 0

calc_x              dw 0
calc_y              dw 0
calc_w              dw CALC_W
calc_h              dw CALC_H
calc_restore_x      dw 0
calc_restore_y      dw 0
calc_restore_w      dw CALC_W
calc_restore_h      dw CALC_H
calc_maximized      db 0
calc_open           db 0
calc_minimized      db 0
calc_acc            times 3 dd 0
calc_current        times 3 dd 0
calc_op             db 0
calc_entry          db 0
calc_error          db 0
calc_result_fresh   db 0
calc_decimal        db 0
calc_frac_digits    db 0
calc_display_buf    times 32 db 0
calc_hit_row        dw 0
calc_hit_col        dw 0
calc_hit_x          dw 0
calc_display_x      dw 0
calc_display_y      dw 0
calc_display_w      dw 0
calc_key_left       dw 0
calc_key_top        dw 0
calc_key_w          dw 0
calc_key_h          dw 0
calc_key_step_x     dw 0
calc_key_step_y     dw 0
datetime_buf        times 20 db 0

foreground_window   db 0
z_count             db 0
z_order             times MAX_PROCS db 0
task_count          db 0
task_order          times (MAX_PROCS+1) db 0
task_draw_x         dw 0
task_draw_id        db 0
task_button_w       dw TASK_BUTTON_W
task_label_buf      times 12 db 0
menu_open           db 0
menu_owner_pid      db 0
message_open        db 0
message_kind        db 0
system_menu_window  db 0
system_message_ptr  dw 0
app_dirty          db 0
app_has_saved      db 0
pending_unsaved_pid db 0
pending_unsaved_action db 0    ; 1=close, 2=Paint New, 3=Notepad New
control_open       db 0
control_slider_drag db 0
control_x          dw 48
control_y          dw 28
mouse_swap_buttons db 0
mouse_speed        db 8         ; 1..15, 8 = normal
control_boot_dos   db 0
control_autorestart db 1
control_write_result db 0
control_disk_value db 1
control_autorestart_disk_value db 1
control_write_retries db 0
debug_open         db 0        ; 0=closed, 1=main, 2=INT test, 3=INT execute, 4=BSOD, 5=Fault, 6=normal faults
debug_scroll_drag  db 0
debug_scroll_offset dw 0       ; first visible INT or normal-fault item
debug_scroll_thumb_y dw 0
debug_scroll_drag_dy dw 0
debug_pending_int  db 0
debug_pending_fault db 0
debug_raw_target   dw 0
debug_draw_int     db 0
debug_draw_fault   db 0
debug_result_success db 0
debug_int13_status db 0
debug_probe_seen   db 0
debug_probe_old_off dw 0
debug_probe_old_seg dw 0
debug_result_line1_ptr dw 0
debug_result_line2_ptr dw 0
debug_list_button_y dw 0
debug_int_label_buf times 9 db 0
debug_pm_saved_ss  dw 0
debug_pm_saved_sp  dw 0
debug_pm_saved_cmos db 0
debug_lm_fail_reason db 0
debug_mode_action db 0         ; 0=CPU-mode test, 1=blue screen, 2=custom program
debug_crash_code  db BSOD_STOP_MANUAL

; Custom-program editor state.  The actual source and private clipboard live
; above 1 MiB; only indices, UI state and small prompt buffers live here.
custom_open            db 0
custom_created         db 0
custom_minimized       db 0
custom_maximized       db 0
custom_dirty           db 0
custom_hex_half        db 0
custom_selection       db 0
custom_mouse_select    db 0
custom_scroll_drag     db 0     ; 0=none, 1=vertical, 2=horizontal
custom_confirm         db 0     ; 0=none, 1=save before close, 2=clear
custom_exec_dialog     db 0     ; nonzero while the three-mode Execute dialog is open
custom_exec_mode       db 0     ; 0=Real Mode, 1=Protected Mode, 2=Long Mode
custom_prompt_mode     db 0     ; 1=goto, 2=find, 3=find-for-replace, 4=replace
custom_prompt_len      db 0
custom_find_len        db 0
custom_replace_len     db 0
custom_io_result       db 0
custom_io_status       db 0
custom_io_retry        db 0
custom_edd_available   db 0
custom_save_close      db 0
custom_render_comment  db 0
custom_line_visible    db 0
custom_terminated      db 0
custom_status_ptr      dw 0
custom_scroll_thumb_y  dw 0
custom_scroll_drag_dy  dw 0
custom_render_y        dw 0
custom_cursor_draw_x   dw 0
custom_cursor_draw_y   dw 0
custom_token_width     dw 0
custom_exec_load_seg   dw CUSTOM_EXEC_SEG
custom_len             dd 0
custom_cursor          dd 0
custom_anchor          dd 0
custom_scroll_line     dd 0
custom_total_lines     dd 1
custom_pending_pos     dd 0
custom_clip_len        dd 0
custom_io_lba          dd 0
custom_io_pos          dd 0
custom_io_current_lba  dd 0
custom_load_remaining  dd 0
custom_render_pos      dd 0
custom_render_line     dd 0
custom_exec_len        dd 0
custom_io_offset       dw 0
custom_gateway_target  dw 0
custom_x               dw CUSTOM_DEFAULT_X
custom_y               dw CUSTOM_DEFAULT_Y
custom_w               dw CUSTOM_DEFAULT_W
custom_h               dw CUSTOM_DEFAULT_H
custom_restore_x       dw CUSTOM_DEFAULT_X
custom_restore_y       dw CUSTOM_DEFAULT_Y
custom_restore_w       dw CUSTOM_DEFAULT_W
custom_restore_h       dw CUSTOM_DEFAULT_H
custom_editor_x        dw 0
custom_editor_y        dw 0
custom_editor_w        dw 0
custom_editor_h        dw 0
custom_view_rows       dw 0
custom_view_cols       dw 0
custom_total_text_cols dw 0
custom_scroll_x        dw 0
custom_scroll_track_y  dw 0
custom_scroll_track_h  dw 0
custom_scroll_travel   dw 0
custom_hscroll_y       dw 0
custom_hscroll_left_x  dw 0
custom_hscroll_right_x dw 0
custom_hscroll_track_x dw 0
custom_hscroll_track_w dw 0
custom_hscroll_travel  dw 0
custom_prompt_input_x  dw 0
custom_status_y        dw 0
custom_action_y        dw 0
custom_resize_drag     db 0
custom_resize_start_w  dw 0
custom_resize_start_h  dw 0
custom_resize_start_x  dw 0
custom_resize_start_y  dw 0
app_io_lba             dd 0
app_io_pos             dd 0
app_io_remaining       dd 0
app_io_offset          dw 0
app_io_result          db 0
app_io_retry           db 0
align 4, db 0
debug_lm_saved_cr0 dd 0
debug_lm_saved_cr3 dd 0
debug_lm_saved_cr4 dd 0
debug_lm_saved_efer_lo dd 0
debug_lm_saved_efer_hi dd 0
debug_pm_saved_gdtr:
    times 6 db 0
debug_pm_saved_idtr:
    times 6 db 0
debug_pm_idtr32:
    dw (32*8)-1
    dd DEBUG_PM_IDT32_PHYS
debug_lm_idtr64:
    dw (32*16)-1
    dq DEBUG_LM_IDT64_PHYS
align 8, db 0
debug_pm_gdt:
    dq 0
    ; Flat 32-bit code and data descriptors.
    dw 0xFFFF, 0x0000
    ; Accessed is preset because Custom Program paging makes the Stage-2/GDT
    ; page read-only under CR0.WP.  Letting the CPU set this bit lazily would
    ; page-fault while loading the descriptor.
    db 0x00, DEBUG_PM_CODE32_ACCESS, 0xCF, 0x00
    dw 0xFFFF, 0x0000
    db 0x00, DEBUG_PM_DATA32_ACCESS, 0xCF, 0x00
    ; 16-bit protected-mode exit code, based at the MiniWin stage-2 segment.
    dw 0xFFFF
    dw STAGE2_LINEAR_BASE & 0xFFFF
    db (STAGE2_LINEAR_BASE >> 16) & 0xFF
    db DEBUG_PM_CODE16_ACCESS, 0x00
    db (STAGE2_LINEAR_BASE >> 24) & 0xFF
    ; 64-bit code descriptor used only after CPUID confirms Long Mode.
    dw 0x0000, 0x0000
    ; This bit is essential for the PG+WP transition: the first Long Mode far
    ; jump must be a read-only GDT lookup, never an implicit descriptor write.
    db 0x00, DEBUG_LM_CODE64_ACCESS, 0x20, 0x00
    ; Runtime-built available 32-bit TSS descriptor.  Loading TR with this
    ; descriptor prevents an old BIOS 16-bit TSS from rejecting IA-32e entry.
    dq 0, 0
    ; Flat ring-3 descriptors used only to generate a genuine #AC. Accessed is
    ; preset for the same read-only-GDT safety property as the ring-0 entries.
    dw 0xFFFF, 0x0000
    db 0x00, 0xFB, 0xCF, 0x00
    dw 0xFFFF, 0x0000
    db 0x00, 0xF3, 0xCF, 0x00
debug_pm_gdt_end:
debug_pm_gdtr:
    dw debug_pm_gdt_end - debug_pm_gdt - 1
    dd debug_pm_gdt
align 4, db 0
debug_lm_tss:
    times 104 db 0
keyboard_move_mode  db 0
last_sys_window     db 0
last_sys_tick       dw 0
menu_draw_x         dw 0
menu_draw_y         dw 0

drag_mode           db 0
drag_pid            db 0
interaction_pid     db 0
click_target_pid    db 0
drag_dx             dw 0
drag_dy             dw 0
resize_start_w      dw 0
resize_start_h      dw 0
resize_start_x      dw 0
resize_start_y      dw 0

captured_button     db 0
captured_pid        db 0
capture_inside      db 0
capture_x           dw 0
capture_y           dw 0
capture_w           dw 0
capture_h           dw 0
capture_label       dw 0
temp_x              dw 0
temp_y              dw 0
temp_w              dw 0
temp_h              dw 0
temp_label          dw 0
temp_action         dw 0

mouse_mode          db 0
mouse_x             dw 0
mouse_y             dw 0
mouse_last_x        dw 0
mouse_last_y        dw 0
mouse_hover_x       dw 0
mouse_hover_y       dw 0
mouse_hover_valid   db 0
mouse_buttons       db 0
mouse_raw_buttons   db 0
mouse_prev_buttons  db 0
mouse_changed       db 0
mouse_wheel         db 0
cursor_visible      db 0
cursor_kind         db 0
cursor_hotspot_x    dw 0
cursor_hotspot_y    dw 0
cursor_draw_x       dw 0
cursor_draw_y       dw 0

clipboard_kind      db 0         ; 0=empty/undo, 1=text, 2=Paint bitmap
paint_zoom           db 1         ; 1x..4x
paint_scroll_x       dw 0
paint_scroll_y       dw 0
paint_scroll_max_x   dw 0
paint_scroll_max_y   dw 0
paint_visible_cols   dw 0
paint_visible_rows   dw 0
paint_htrack_x       dw 0
paint_htrack_y       dw 0
paint_htrack_len     dw 0
paint_vtrack_x       dw 0
paint_vtrack_y       dw 0
paint_vtrack_len     dw 0
paint_hthumb_x       dw 0
paint_hthumb_y       dw 0
paint_hthumb_w       dw 0
paint_vthumb_x       dw 0
paint_vthumb_y       dw 0
paint_vthumb_h       dw 0
paint_hthumb_range   dw 0
paint_vthumb_range   dw 0
paint_scroll_drag_offset dw 0
paint_zoom_anchor_x  dw 0
paint_zoom_anchor_y  dw 0
paint_select_active  db 0
paint_select_drag    db 0         ; 1=create, 2=move, 3=resize
paint_select_pending db 0         ; transformed preview awaits Enter/tool switch
paint_select_handle  db 0
paint_select_x       dw 0
paint_select_y       dw 0
paint_select_w       dw 0
paint_select_h       dw 0
paint_select_anchor_x dw 0
paint_select_anchor_y dw 0
paint_select_start_x dw 0
paint_select_start_y dw 0
paint_select_orig_x  dw 0
paint_select_orig_y  dw 0
paint_select_orig_w  dw 0
paint_select_orig_h  dw 0
paint_select_source_x dw 0
paint_select_source_y dw 0
paint_select_source_w dw 0
paint_select_source_h dw 0
paint_clip_w         dw 0
paint_clip_h         dw 0
paint_select_buffer_valid db 0
paint_saved_clip_kind db 0
paint_saved_clip_len  dw 0
paint_palette_drag   db 0
paint_palette_drag_dx dw 0
paint_palette_drag_dy dw 0
paint_palette_positioned db 0
paint_view_w         dw 0
paint_view_h         dw 0
paint_src_x_tmp      dw 0
paint_src_y_tmp      dw 0
paint_dst_x_tmp      dw 0
paint_dst_y_tmp      dw 0
paint_sel_color_tmp  db 0
paint_select_screen_x dw 0
paint_select_screen_y dw 0
paint_select_screen_w dw 0
paint_select_screen_h dw 0
paint_select_full_screen_w dw 0
paint_select_full_screen_h dw 0
paint_select_full_screen_x dw 0
paint_select_full_screen_y dw 0
paint_select_full_screen_r dw 0
paint_select_full_screen_b dw 0
paint_preview_off_x  dw 0
paint_preview_off_y  dw 0
paint_select_clip_x  dw 0
paint_select_clip_y  dw 0
paint_select_clip_r  dw 0
paint_select_clip_b  dw 0
paint_select_cur_x   dw 0
paint_select_cur_y   dw 0
paint_preview_w      dw 0
paint_preview_h      dw 0
vm_abs_prev_x        dw 0
vm_abs_prev_y        dw 0
vm_abs_valid         db 0
vm_abs_new_x         dw 0
vm_abs_new_y         dw 0
vm_abs_cal_counter   db 0

mouse_ps2_packet_size db 3
mouse_ps2_device_id   db 0
mouse_ps2_pktcnt      db 0
mouse_ps2_pkt         times 4 db 0

vm_flags            dd 0
vm_x                dw 0
vm_y                dw 0
vm_z                dd 0

last_key            dw 0
shift_flags         db 0

; DOS shell editor, command history and COLOR state.
dos_attr            db 0x07
dos_errorlevel      db 0
dos_crash_mode      db 0       ; 0=real, 1=protected, 2=long
dos_crash_code      db BSOD_STOP_MANUAL
dos_crash_seen_code db 0
dos_cursor_x        db 0
dos_cursor_y        db 0
dos_input_x         db 0
dos_input_y         db 0
dos_line_len        db 0
dos_cursor_pos      db 0
dos_history_count   db 0
dos_history_pos     db 0
; Seven history entries plus one dedicated 64-byte command-line buffer.
dos_history         times (8*64) db 0
dos_line            equ dos_history+(7*64)

rect_x              dw 0
rect_y              dw 0
rect_w              dw 0
rect_h              dw 0
rect_color          db 0
pixel_color         db 0
box_x               dw 0
box_y               dw 0
box_w               dw 0
box_h               dw 0
button_x            dw 0
button_y            dw 0
button_w            dw 0
button_h            dw 0
button_label        dw 0
paint_tool_icon_x   dw 0
paint_tool_icon_y   dw 0
paint_tool_icon_bits dw 0
char_code           db 0
char_color          db 0
char_x              dw 0
char_y              dw 0
canvas_px           dw 0
canvas_py           dw 0
canvas_pc           db 0
palette_draw_x      dw 0
palette_draw_y      dw 0
rainbow_icon_x      dw 0
rainbow_icon_y      dw 0
scaled_char_code    db 0
scaled_char_color   db 0
scaled_char_scale   db 1
scaled_char_x       dw 0
scaled_char_y       dw 0
scaled_char_bits    db 0
scaled_char_mask    db 0
scaled_pixel_x      dw 0
scaled_pixel_y      dw 0
resize_grip_x       dw 0
resize_grip_y       dw 0
calc_key_index      dw 0
paint_text_hit_x    dw 0
paint_text_hit_y    dw 0
paint_text_ptr      dw 0
paint_fill_target   db 0
paint_fill_new      db 0
paint_fill_changed  db 0
paint_palette_x     dw 0
paint_palette_y     dw 0
paint_wheel_x       dw 0
paint_wheel_y       dw 0
rgb_value_buf       times 4 db 0
calc_temp_value     dd 0
calc_temp_mul       dd 0
calc_temp_qword     dq 0
calc_fpu_cw_old     dw 0
calc_fpu_cw_trunc   dw 0
calc_sqrt_target    dd 0
calc_scale_integer  dd CALC_SCALE
calc_temp_sign      db 0
calc_temp_frac      dw 0
calc_temp_digits    db 0
text_draw_x          dw 0
text_draw_y          dw 0
text_char_advance    dw 0
paint_commit_block_x    dw 0
paint_commit_block_y    dw 0
paint_commit_block_size dw 1
paint_commit_char_x     dw 0
paint_commit_char_y     dw 0
paint_commit_scale      dw 1
paint_commit_glyph      dw 0
paint_commit_row        dw 0
paint_commit_col        dw 0
paint_commit_bits       db 0
paint_commit_mask       db 0
paint_commit_color      db 0

brush_base_x        dw 0
brush_base_y        dw 0
brush_size_w        dw 0
brush_half          dw 0
brush_color         db 0
line_x              dw 0
line_y              dw 0
line_dx             dw 0
line_dy             dw 0
line_sx             dw 0
line_sy             dw 0
line_err            dw 0
line_e2             dw 0

calc_key_actions    db BTN_CALC_SQRT, BTN_CALC_PERCENT, BTN_CALC_DECIMAL, BTN_CALC_BACK
                    db BTN_CALC_7, BTN_CALC_8, BTN_CALC_9, BTN_CALC_ADD
                    db BTN_CALC_4, BTN_CALC_5, BTN_CALC_6, BTN_CALC_SUB
                    db BTN_CALC_1, BTN_CALC_2, BTN_CALC_3, BTN_CALC_MUL
                    db BTN_CALC_CLEAR, BTN_CALC_0, BTN_CALC_EQUAL, BTN_CALC_DIV
calc_key_labels     dw str_sqrt, str_percent, str_decimal, str_back
                    dw str_7, str_8, str_9, str_plus
                    dw str_4, str_5, str_6, str_minus
                    dw str_1, str_2, str_3, str_mul
                    dw str_c, str_0, str_equal, str_div
str_sqrt            db 'sqrt', 0
str_percent         db '%', 0
str_decimal         db '.', 0
str_back            db '<-', 0

palette_colors      db COL_BLACK, COL_RED, COL_GREEN, COL_BLUE
                    db COL_YELLOW, COL_MAGENTA, COL_CYAN, 0
vga_color_levels    db 0, 13, 25, 38, 50, 63
classic_rgb_values db 0, 0, 0, 0, 0, 170, 0, 170, 0, 0, 170, 170, 170, 0, 0, 170, 0, 170, 170, 85, 0, 170, 170, 170, 85, 85, 85, 85, 85, 255, 85, 255, 85, 85, 255, 255, 255, 85, 85, 255, 85, 255, 255, 255, 85, 255, 255, 255
rainbow_gradient_colors:
    ; Emulator-safe classic VGA gradient. It never depends on extended DAC
    ; entries, so the brush cannot collapse to red/blue/black on limited BIOSes.
    ; Exact order: red -> orange -> yellow -> green -> cyan -> blue -> purple.
    db COL_RED, COL_RED, COL_LIGHTRED, COL_LIGHTRED
    db COL_BROWN, COL_BROWN, COL_BROWN, COL_BROWN
    db COL_YELLOW, COL_YELLOW, COL_YELLOW, COL_YELLOW
    db COL_LIGHTGREEN, COL_LIGHTGREEN, COL_GREEN, COL_GREEN, COL_GREEN, COL_GREEN
    db COL_LIGHTCYAN, COL_LIGHTCYAN, COL_CYAN, COL_CYAN, COL_CYAN, COL_CYAN
    db COL_LIGHTBLUE, COL_LIGHTBLUE, COL_BLUE, COL_BLUE, COL_BLUE, COL_BLUE
    db COL_LIGHTMAGENTA, COL_LIGHTMAGENTA, COL_MAGENTA, COL_MAGENTA, COL_MAGENTA, COL_MAGENTA
rainbow_gradient_colors_end:
rainbow_colors      db COL_RED, COL_BROWN, COL_YELLOW, COL_GREEN, COL_CYAN, COL_BLUE, COL_MAGENTA
rainbow_offsets     db 0, 2, 4, 6, 8, 10, 11
rainbow_heights     db 2, 2, 2, 2, 2, 1, 1

; Color wheel pixels are generated by paint_wheel_color_at.

cursor_shape:
    db 1,0,0,0,0,0,0,0,0,0,0,0,0
    db 1,1,0,0,0,0,0,0,0,0,0,0,0
    db 1,2,1,0,0,0,0,0,0,0,0,0,0
    db 1,2,2,1,0,0,0,0,0,0,0,0,0
    db 1,2,2,2,1,0,0,0,0,0,0,0,0
    db 1,2,2,2,2,1,0,0,0,0,0,0,0
    db 1,2,2,2,2,2,1,0,0,0,0,0,0
    db 1,2,2,2,2,2,2,1,0,0,0,0,0
    db 1,2,2,2,2,1,1,1,1,0,0,0,0
    db 1,2,2,1,2,1,0,0,0,0,0,0,0
    db 1,2,1,0,1,2,1,0,0,0,0,0,0
    db 1,1,0,0,1,2,1,0,0,0,0,0,0
    db 1,0,0,0,0,1,2,1,0,0,0,0,0
    db 0,0,0,0,0,1,2,1,0,0,0,0,0
    db 0,0,0,0,0,0,1,2,1,0,0,0,0
    db 0,0,0,0,0,0,1,1,1,0,0,0,0
picker_cursor_shape:
    ; Exact brush-1 3x3 picker target: 111 / 101 / 111.
    ; Hotspot (1,1) is the transparent center and is the sampled pixel.
    db 1,1,1,0,0,0,0,0,0,0,0,0,0
    db 1,0,1,0,0,0,0,0,0,0,0,0,0
    db 1,1,1,0,0,0,0,0,0,0,0,0,0
    times (CURSOR_W*(CURSOR_H-3)) db 0
ibeam_cursor_shape:
    db 0,1,1,1,1,1,0,0,0,0,0,0,0
    db 0,0,0,1,0,0,0,0,0,0,0,0,0
    db 0,0,0,1,0,0,0,0,0,0,0,0,0
    db 0,0,0,1,0,0,0,0,0,0,0,0,0
    db 0,0,0,1,0,0,0,0,0,0,0,0,0
    db 0,0,0,1,0,0,0,0,0,0,0,0,0
    db 0,0,0,1,0,0,0,0,0,0,0,0,0
    db 0,0,0,1,0,0,0,0,0,0,0,0,0
    db 0,0,0,1,0,0,0,0,0,0,0,0,0
    db 0,0,0,1,0,0,0,0,0,0,0,0,0
    db 0,1,1,1,1,1,0,0,0,0,0,0,0
    times (CURSOR_W*(CURSOR_H-11)) db 0
aero_move_cursor_shape:
    db 0,0,0,0,0,0,1,0,0,0,0,0,0
    db 0,0,0,0,0,1,2,1,0,0,0,0,0
    db 0,0,0,0,1,2,2,2,1,0,0,0,0
	db 0,0,0,0,0,1,2,1,0,0,0,0,0
    db 0,0,1,0,0,1,2,1,0,0,1,0,0
    db 0,1,2,1,1,1,2,1,1,1,2,1,0
    db 1,2,2,2,2,2,2,2,2,2,2,2,1
    db 0,1,2,1,1,1,2,1,1,1,2,1,0
    db 0,0,1,0,0,1,2,1,0,0,1,0,0
    db 0,0,0,0,0,1,2,1,0,0,0,0,0
    db 0,0,0,0,1,2,2,2,1,0,0,0,0
    db 0,0,0,0,0,1,2,1,0,0,0,0,0
    db 0,0,0,0,0,0,1,0,0,0,0,0,0
    times (CURSOR_W*(CURSOR_H-9)) db 0
aero_nwse_cursor_shape:
    db 1,1,1,1,1,0,0,0,0,0,0,0,0
    db 1,2,2,2,1,0,0,0,0,0,0,0,0
    db 1,2,2,1,0,0,0,0,0,0,0,0,0
    db 1,2,1,2,1,0,0,0,0,0,0,0,0
    db 1,1,0,1,2,1,0,0,0,0,0,0,0
    db 0,0,0,0,1,2,1,0,1,1,0,0,0
    db 0,0,0,0,0,1,2,1,2,1,0,0,0
    db 0,0,0,0,0,0,1,2,2,1,0,0,0
    db 0,0,0,0,0,1,2,2,2,1,0,0,0
    db 0,0,0,0,0,1,1,1,1,1,0,0,0
    times (CURSOR_W*(CURSOR_H-10)) db 0
aero_nesw_cursor_shape:
    db 0,0,0,0,0,0,1,1,1,1,1,0,0
    db 0,0,0,0,0,0,1,2,2,2,1,0,0
    db 0,0,0,0,0,0,0,1,2,2,1,0,0
    db 0,0,0,0,0,0,1,2,1,2,1,0,0
    db 0,0,0,0,0,1,2,1,0,1,1,0,0
    db 0,1,1,0,1,2,1,0,0,0,0,0,0
    db 0,1,2,1,2,1,0,0,0,0,0,0,0
    db 0,1,2,2,1,0,0,0,0,0,0,0,0
    db 0,1,2,2,2,1,0,0,0,0,0,0,0
    db 0,1,1,1,1,1,0,0,0,0,0,0,0
    times (CURSOR_W*(CURSOR_H-10)) db 0
aero_ns_cursor_shape:
    db 0,0,0,0,0,1,0,0,0,0,0,0,0
    db 0,0,0,0,1,2,1,0,0,0,0,0,0
    db 0,0,0,1,2,2,2,1,0,0,0,0,0
    db 0,0,0,0,1,2,1,0,0,0,0,0,0
    db 0,0,0,0,1,2,1,0,0,0,0,0,0
    db 0,0,0,0,1,2,1,0,0,0,0,0,0
    db 0,0,0,0,1,2,1,0,0,0,0,0,0
    db 0,0,0,0,1,2,1,0,0,0,0,0,0
    db 0,0,0,1,2,2,2,1,0,0,0,0,0
    db 0,0,0,0,1,2,1,0,0,0,0,0,0
    db 0,0,0,0,0,1,0,0,0,0,0,0,0
    times (CURSOR_W*(CURSOR_H-11)) db 0
aero_ew_cursor_shape:
    db 0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0
    db 0,0,1,0,0,0,0,0,1,0,0,0,0
    db 0,1,2,1,1,1,1,1,2,1,0,0,0
    db 1,2,2,2,2,2,2,2,2,2,1,0,0
    db 0,1,2,1,1,1,1,1,2,1,0,0,0
    db 0,0,1,0,0,0,0,0,1,0,0,0,0
    times (CURSOR_W*(CURSOR_H-9)) db 0
cursor_save         times (CURSOR_W*CURSOR_H) db 0

str_empty           db 0
str_scroll_up       db 0x1E,0
str_scroll_down     db 0x1F,0
str_scroll_left     db 0x11,0
str_scroll_right    db 0x10,0
str_main_title      db 'Program Manager',0
str_programs        db 'Applications',0
str_paint           db 'Paint',0
str_min             db '-',0
str_max             db '[]',0
str_restore         db '<>',0
str_close           db 'X',0
str_task_main       db 'Progman',0
str_task_main_small db 'PM',0
str_task_paint      db 'Paint',0
str_task_note       db 'Notepad',0
str_task_calc       db 'Calc',0
str_task_custom     db 'Custom',0
str_task_custom_small db 'CP',0
str_task_paint_base db 'P',0
str_task_note_base  db 'N',0
str_task_calc_base  db 'C',0
str_process_limit   db 'Process limit: 8 apps.',0
str_paint_title     db 'Paint',0
str_notepad_title   db 'Notepad',0
str_calc_title      db 'Calculator',0
str_notepad_short   db 'Notepad',0
str_calc_short      db 'Calc',0
str_control         db 'Control',0
str_debug           db 'Debug',0
str_custom_program  db 'Custom',0
str_custom_title    db 'Custom Program',0
str_custom_execute  db 'Execute',0
str_custom_exec_mode_title db 'Execution Mode',0
str_custom_exec_mode_prompt db 'Select execution mode:',0
str_custom_exec_real db 'Real',0
str_custom_exec_pm   db 'Protected',0
str_custom_exec_lm   db 'Long',0
str_custom_file     db 'File',0
str_custom_edit     db 'Edit',0
str_custom_search   db 'Search',0
str_custom_go       db 'Go',0
str_debug_title     db 'Debug',0
str_int_test        db 'INT test',0
str_int_test_title  db 'INT test',0
str_int_execute     db 'INT execute',0
str_int_exec_title  db 'INT execute',0
str_bluescreen      db 'Bluescreen',0
str_bluescreen_mode db 'Bluescreen Mode',0
str_bluescreen_real db 'Real Mode Bluescreen',0
str_bluescreen_pm   db 'Protected Mode Bluescreen',0
str_bluescreen_lm   db 'Long Mode Bluescreen',0
str_fault           db 'Fault',0
str_fault_title     db 'Fault',0
str_normal_fault    db 'Normal fault',0
str_double_fault    db 'Double fault',0
str_triple_fault    db 'Triple fault',0
str_normal_fault_title db 'Normal fault',0
str_exceptions      db 'Exceptions',0
str_disable_bluescreen db 'Disable Bluescreen',0
str_enable_bluescreen  db 'Enable Bluescreen',0
str_bluescreen_disabled db 'Bluescreen disabled.',0
str_bluescreen_enabled  db 'Bluescreen enabled.',0
str_bluescreen_is_disabled db 'Bluescreen is disabled.',0
str_go_protected    db 'Go to Protected Mode',0
str_go_long         db 'Go to Long Mode',0
str_pm_line1        db 'Now in Protected Mode!',0
str_pm_line2        db 'Press any key to return to Real Mode',0
str_lm_line1        db 'Now in Long Mode!',0
str_lm_line2        db 'Press any key to return to Real Mode',0
str_interrupts      db 'Interrupts',0
str_erase           db 'Erase',0
str_clear           db 'Clear',0
str_palette         db 'RGB',0
str_rgb_palette     db 'RGB Palette',0
str_rgb_hint        db '0-255',0
str_r               db 'R',0
str_g               db 'G',0
str_b               db 'B',0
str_pencil          db 'Pencil',0
str_eraser          db 'Eraser',0
str_undo            db 'Undo',0
str_cut             db 'Cut',0
str_copy            db 'Copy',0
str_paste           db 'Paste',0
str_select_all      db 'Select All',0
str_new_canvas      db 'New canvas',0
str_new             db 'New',0
str_insert_datetime db 'Time/Date',0
str_minimize        db 'Minimize',0
str_maximize        db 'Maximize',0
str_restore_word    db 'Restore',0
str_move            db 'Move',0
str_close_word      db 'Close',0
str_exit_windows    db 'Exit Windows',0
str_about           db 'About',0
str_menu_file       db 'File',0
str_menu_apps       db 'Apps',0
str_menu_help       db 'Help',0
str_menu_edit       db 'Edit',0
str_menu_view       db 'View',0
str_status_pencil   db 'Pencil',0
str_status_eraser   db 'Eraser',0
str_status_rainbow  db 'Rainbow',0
str_status_fill     db 'Fill',0
str_status_text     db 'Text',0
str_status_eyedrop  db 'Eyedropper',0
str_status_line      db 'Line',0
str_status_rect      db 'Rectangle',0
str_status_ellipse   db 'Ellipse',0
str_status_select    db 'Select',0
str_status_magnify   db 'Magnifier',0
str_text_1x         db 'Text 1x',0
str_text_2x         db 'Text 2x',0
str_text_3x         db 'Text 3x',0
str_brush_1         db 'Brush 1',0
str_brush_2         db 'Brush 2',0
str_brush_4         db 'Brush 4',0
str_message_title   db 'Message',0
str_about_title     db 'About MiniWin',0
str_system_title    db 'System',0
str_exit_title      db 'Exit Windows',0
str_exit_question   db 'Do you want to exit Windows?',0
str_unsaved_title   db 'Unsaved Changes',0
str_overwrite_title db 'Confirm Overwrite',0
str_debug_result_title db 'INT Test Result',0
str_long_result_title db 'Long Mode Test',0
str_unsaved_line1   db 'Discard unsaved changes?',0
str_unsaved_line2   db 'Your changes will be lost.',0
str_overwrite_question db 'A saved file already exists. Overwrite the previous content?',0
str_swap_mouse      db 'Swap mouse buttons',0
str_mouse_speed     db 'Mouse speed',0
str_slow            db 'Slow',0
str_fast            db 'Fast',0
mouse_speed_num     db 1,2,3,4,5,6,7,8,10,12,14,16,18,21,24
str_boot_dos        db 'Boot to DOS by default',0
str_auto_restart_bsod db 'Auto restart after BSOD',0
str_control_write_error db 'Could not write Control setting to disk.',0
str_check           db 0xDB,0
str_yes             db 'Yes',0
str_no              db 'No',0
str_cancel          db 'Cancel',0
str_ok              db 'OK',0
str_about_line1     db 'MiniWin 6.1',0
str_about_line2     db 'In BIOS environment',0
str_about_line3     db 0
str_system_line1    db 'Document stored in memory.',0
str_system_line2    db 'No disk file was created.',0
str_app_saved_ok    db 'Saved successfully.',0
str_app_save_failed db 'Could not save the document to disk.',0
str_memory_line1    db 'Operation completed.',0
str_debug_success   db 'Success!',0
str_debug_failed    db 'Failed!',0
str_lm_not_supported db 'Long Mode is not supported.',0
str_lm_no_cpuid     db 'CPU does not support CPUID.',0
str_lm_no_x64       db 'CPU is x86 and has no x64 support.',0
str_lm_no_pae_msr   db 'CPU lacks required PAE/MSR support.',0
str_custom_reload_error db 'Could not reload Custom Program.',0
str_fault_de        db '#DE Divide Error',0
str_fault_db        db '#DB Debug',0
str_fault_bp        db '#BP Breakpoint',0
str_fault_of        db '#OF Overflow',0
str_fault_br        db '#BR BOUND Range',0
str_fault_ud        db '#UD Invalid Opcode',0
str_fault_nm        db '#NM Device Missing',0
str_fault_ts        db '#TS Invalid TSS',0
str_fault_np        db '#NP Not Present',0
str_fault_ss        db '#SS Stack Fault',0
str_fault_gp        db '#GP General Protection',0
str_fault_pf        db '#PF Page Fault',0
str_fault_mf        db '#MF x87 FP',0
str_fault_ac        db '#AC Alignment Check',0
str_fault_mc        db '#MC Machine Check',0
str_fault_xm        db '#XM SIMD FP',0

debug_normal_fault_vectors:
    db 0,1,3,4,5,6,7,10,11,12,13,14,16,17,18,19
debug_normal_fault_labels:
    dw str_fault_de,str_fault_db,str_fault_bp,str_fault_of
    dw str_fault_br,str_fault_ud,str_fault_nm,str_fault_ts
    dw str_fault_np,str_fault_ss,str_fault_gp,str_fault_pf
    dw str_fault_mf,str_fault_ac,str_fault_mc,str_fault_xm
str_debug_probe_failed db 'INT dispatch did not return.',0
str_debug_probe_line2 db 'Vector '
debug_probe_seg_hex db '0000'
                    db ':'
debug_probe_off_hex db '0000'
                    db ' (safe)',0
str_debug_int13_line1 db 'INT 13h AH=00h disk reset',0
str_debug_int13_line2 db 'DL='
debug_int13_drive_hex db '00'
                    db 'h status AH='
debug_int13_status_hex db '00'
                    db 'h',0
str_debug_int10_line1 db 'INT 10h BIOS video query',0
str_debug_int10_line2 db 'Mode='
debug_int10_mode_hex db '00'
                    db 'h cols='
debug_int10_cols_hex db '00'
                    db ' page='
debug_int10_page_hex db '00',0
str_debug_int11_line1 db 'INT 11h equipment list',0
str_debug_int11_line2 db 'Equipment AX='
debug_int11_ax_hex  db '0000h',0
str_debug_int12_line1 db 'INT 12h conventional RAM',0
str_debug_int12_line2 db 'Memory KB='
debug_int12_ax_hex  db '0000h',0
str_debug_int14_line1 db 'INT 14h serial COM1 status',0
str_debug_int14_line2 db 'Returned AX='
debug_int14_ax_hex  db '0000h',0
str_debug_int15_line1 db 'INT 15h extended memory',0
str_debug_int15_line2 db 'AX='
debug_int15_ax_hex  db '0000'
                    db 'h CF='
debug_int15_cf_char db '0',0
str_debug_int16_line1 db 'INT 16h keyboard status',0
str_debug_int16_ready db 'Key ready; AX contains code',0
str_debug_int16_empty db 'No key is currently ready',0
str_debug_int17_line1 db 'INT 17h printer LPT1 status',0
str_debug_int17_line2 db 'Status AH='
debug_int17_ah_hex  db '00h',0
str_debug_int1a_line1 db 'INT 1Ah BIOS clock query',0
str_debug_int1a_line2 db 'Ticks='
debug_int1a_cx_hex  db '0000'
                    db ':'
debug_int1a_dx_hex  db '0000',0

str_int_desc_00 db 'Divide error exception',0
str_int_desc_01 db 'Single-step exception',0
str_int_desc_02 db 'Non-maskable interrupt',0
str_int_desc_03 db 'Breakpoint exception',0
str_int_desc_04 db 'Overflow exception',0
str_int_desc_05 db 'Bounds check exception',0
str_int_desc_06 db 'Invalid opcode exception',0
str_int_desc_07 db 'Coprocessor unavailable',0
str_int_desc_08 db 'Timer IRQ / double fault',0
str_int_desc_09 db 'Keyboard IRQ / coprocessor',0
str_int_desc_0a db 'IRQ2 / invalid TSS',0
str_int_desc_0b db 'IRQ3 / segment missing',0
str_int_desc_0c db 'IRQ4 / stack fault',0
str_int_desc_0d db 'IRQ5 / protection fault',0
str_int_desc_0e db 'IRQ6 / page fault',0
str_int_desc_0f db 'IRQ7 / reserved',0
str_int_desc_10 db 'BIOS video services',0
str_int_desc_11 db 'BIOS equipment list',0
str_int_desc_12 db 'BIOS conventional memory',0
str_int_desc_13 db 'BIOS disk services',0
str_int_desc_14 db 'BIOS serial services',0
str_int_desc_15 db 'BIOS system services',0
str_int_desc_16 db 'BIOS keyboard services',0
str_int_desc_17 db 'BIOS printer services',0
str_int_desc_18 db 'ROM BASIC / boot failure',0
str_int_desc_19 db 'BIOS bootstrap loader',0
str_int_desc_1a db 'BIOS clock services',0
str_int_desc_1b db 'Ctrl-Break handler',0
str_int_desc_1c db 'BIOS timer tick hook',0
str_int_desc_1d db 'Video parameter table',0
str_int_desc_1e db 'Diskette parameter table',0
str_int_desc_1f db 'Graphics font table',0
debug_int_desc_00_1f:
    dw str_int_desc_00, str_int_desc_01, str_int_desc_02, str_int_desc_03
    dw str_int_desc_04, str_int_desc_05, str_int_desc_06, str_int_desc_07
    dw str_int_desc_08, str_int_desc_09, str_int_desc_0a, str_int_desc_0b
    dw str_int_desc_0c, str_int_desc_0d, str_int_desc_0e, str_int_desc_0f
    dw str_int_desc_10, str_int_desc_11, str_int_desc_12, str_int_desc_13
    dw str_int_desc_14, str_int_desc_15, str_int_desc_16, str_int_desc_17
    dw str_int_desc_18, str_int_desc_19, str_int_desc_1a, str_int_desc_1b
    dw str_int_desc_1c, str_int_desc_1d, str_int_desc_1e, str_int_desc_1f

str_int_desc_20 db 'DOS terminate process',0
str_int_desc_21 db 'DOS API services',0
str_int_desc_22 db 'DOS terminate address',0
str_int_desc_23 db 'DOS Ctrl-Break handler',0
str_int_desc_24 db 'DOS critical error',0
str_int_desc_25 db 'DOS absolute disk read',0
str_int_desc_26 db 'DOS absolute disk write',0
str_int_desc_27 db 'DOS stay resident',0
str_int_desc_28 db 'DOS idle hook',0
str_int_desc_29 db 'DOS fast console output',0
str_int_desc_2a db 'DOS network hook',0
str_int_desc_2b db 'DOS reserved service',0
str_int_desc_2c db 'DOS reserved service',0
str_int_desc_2d db 'DOS reserved service',0
str_int_desc_2e db 'DOS command execution',0
str_int_desc_2f db 'DOS multiplex services',0
debug_int_desc_20_2f:
    dw str_int_desc_20, str_int_desc_21, str_int_desc_22, str_int_desc_23
    dw str_int_desc_24, str_int_desc_25, str_int_desc_26, str_int_desc_27
    dw str_int_desc_28, str_int_desc_29, str_int_desc_2a, str_int_desc_2b
    dw str_int_desc_2c, str_int_desc_2d, str_int_desc_2e, str_int_desc_2f

str_int_desc_system db 'System/application vector',0
str_int_desc_user   db 'User software interrupt',0
str_int_desc_reserved db 'User/reserved interrupt',0
str_int_desc_irq_hi db 'Hardware IRQ 8-15',0
str_int_desc_firmware db 'Firmware/user interrupt',0
str_datetime_unknown db '[date/time unavailable]',0
str_error           db 'Error',0
str_0               db '0',0
str_1               db '1',0
str_2               db '2',0
str_3               db '3',0
str_4               db '4',0
str_5               db '5',0
str_6               db '6',0
str_7               db '7',0
str_8               db '8',0
str_9               db '9',0
str_plus            db '+',0
str_minus           db '-',0
str_mul              db '*',0
str_div              db '/',0
str_equal            db '=',0
str_c                db 'C',0
str_poweroff         db 'Power off...',0
; DOS command environment strings.
dos_banner_text     db 'MiniWin DOS Environment [Version 6.1]',13,10
                    db 'Type HELP for available commands.',13,10,13,10,0
dos_prompt          db '>',0
dos_bad_command     db 'Bad command or file name.',13,10,0
dos_win_usage       db 'Usage: WIN or WIN -KEEP.',13,10,0
dos_reboot_usage    db 'Usage: REBOOT or REBOOT -HARD.',13,10,0
dos_help_text       db 'HELP            Show this command list',13,10
                    db 'CLS             Clear the screen',13,10
                    db 'VER             Show the version',13,10
                    db 'COLOR [xy]      Set background x and foreground y',13,10
                    db '                Hex digits: 0-9 and A-F',13,10
                    db 'DATE            Show the current date',13,10
                    db 'TIME            Show the current time',13,10
                    db 'ECHO text       Print text',13,10
                    db 'HEX [-MEM]      Open the disk or physical memory HEX editor',13,10
                    db 'WIN [-KEEP]     Restart MiniWin or return and preserve GUI',13,10
                    db 'CRASH [0xNN] [-PM|-LM]  Trigger a mode-specific blue screen',13,10
                    db 'HLT             Halt the CPU',13,10
                    db 'REBOOT [-HARD]  Reboot or Hard Reboot the system',13,10
                    db 'RESTORE         Restore the MBR and reboot',13,10
                    db 'EXIT            Power off the computer',13,10,0
dos_ver_text        db 'MiniWin DOS Version 6.1',13,10,0
dos_color_usage     db 'Usage: COLOR [attr], for example COLOR FC.',13,10,0
dos_hex_usage       db 'Usage: HEX or HEX -MEM.',13,10,0
dos_crash_usage     db 'Usage: CRASH [0xNN] [-PM|-LM].',13,10,0
dos_crash_lm_unsupported db 'CRASH: Long Mode is not supported by this CPU.',13,10,0
dos_color_help      db 'Sets the default console foreground and background colors.',13,10
                    db 'COLOR [attr]',13,10,13,10
                    db 'The first hex digit is the background; the second is foreground.',13,10
                    db '0 Black       8 Gray',13,10
                    db '1 Blue        9 Light Blue',13,10
                    db '2 Green       A Light Green',13,10
                    db '3 Aqua        B Light Aqua',13,10
                    db '4 Red         C Light Red',13,10
                    db '5 Purple      D Light Purple',13,10
                    db '6 Yellow      E Light Yellow',13,10
                    db '7 White       F Bright White',13,10
                    db 'Example: COLOR FC.',13,10,0
dos_color_same      db 'Foreground and background cannot be the same.',13,10,0
dos_date_prefix     db 'Current date: ',0
dos_time_prefix     db 'Current time: ',0
dos_rtc_unknown     db 'RTC date/time unavailable.',13,10,0
dos_restore_err_read   db 'RESTORE: failed to read backup MBR from LBA 2047.',13,10,0
dos_restore_err_write  db 'RESTORE: failed to write MBR to LBA 0.',13,10,0
dos_restore_err_zero   db 'RESTORE: failed to zero LBA range 1-2047.',13,10,0

dos_restore_dap        times 16 db 0
control_dap            times 16 db 0
dos_restore_cur_lba    dd 0
dos_restore_spt        db 0
dos_restore_heads      db 0

align 2
; Reuse 0600:0000 to keep the resident Stage 2 within its 64-KiB limit.
dos_restore_buf        equ (BOOT_SETTING_IO_SEG << 4)
gui_state_image_end:
%if (gui_state_image_end-gui_state_image_start) > GUI_SNAPSHOT_CAPACITY
    %error "GUI state image exceeds the reserved snapshot arena"
%endif
; =============================================================================
; Initialization and global state
; =============================================================================
init_font_and_video:
    ; BIOS 8x8 ROM font pointer -> ES:BP.
    mov ax, 0x1130
    mov bh, 0x03
    int 0x10
    xor ax, ax
    mov ds, ax
    mov [font_seg], es
    mov [font_off], bp

    ; Save the 8x16 ROM font while the firmware environment is still stable.
    ; Blue-screen rendering later consumes this pointer without calling BIOS.
    mov ax, 0x1130
    mov bh, 0x06
    int 0x10
    xor ax, ax
    mov ds, ax
    mov [BLUESCREEN_FONT_SEG_ADDR], es
    mov [BLUESCREEN_FONT_OFF_ADDR], bp

    mov ax, 0x0013
    int 0x10
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov byte [system_display_mode], 1
    call init_extended_palette
    ret

init_extended_palette:
    ; Preserve the classic 0..15 colors. 16..231 is a 6x6x6 RGB cube and
    ; 232..247 is a grayscale ramp, so arbitrary 0..255 RGB input can be
    ; selected through RGB and represented by the nearest VGA palette color.
    push ax
    push bx
    push dx
    push si
    push di
    push bp
    mov dx, 0x3C8
    mov al, 16
    out dx, al
    inc dx
    ; Use DS-default index registers for every color component.  In 16-bit
    ; addressing, an address containing BP defaults to SS, not DS.  The old
    ; green lookup therefore read STACK_SEG instead of vga_color_levels, which
    ; programmed the DAC with a zero/garbage green component (255,255,255 then
    ; appeared magenta).  BX defaults to DS and keeps all three lookups in the
    ; program data segment.
    xor si, si
.r_loop:
    xor bx, bx
.g_loop:
    xor di, di
.b_loop:
    mov al, [vga_color_levels+si]
    out dx, al
    mov al, [vga_color_levels+bx]
    out dx, al
    mov al, [vga_color_levels+di]
    out dx, al
    inc di
    cmp di, 6
    jb .b_loop
    inc bx
    cmp bx, 6
    jb .g_loop
    inc si
    cmp si, 6
    jb .r_loop
    xor bx, bx
.gray_loop:
    mov al, bl
    shl al, 2
    cmp bl, 15
    jne .gray_ready
    mov al, 63
.gray_ready:
    out dx, al
    out dx, al
    out dx, al
    inc bl
    cmp bl, 16
    jb .gray_loop
    pop bp
    pop di
    pop si
    pop dx
    pop bx
    pop ax
    ret

init_state:
    mov dword [gui_session_cookie], GUI_SESSION_MAGIC
    mov byte [system_watchdog_enabled], 1
    mov byte [system_watchdog_ticks], 0
    mov byte [system_watchdog_reason], BSOD_STOP_WATCHDOG
    mov word [main_x], MAIN_DEF_X
    mov word [main_y], MAIN_DEF_Y
    mov word [main_w], MAIN_DEF_W
    mov word [main_h], MAIN_DEF_H
    mov word [main_restore_x], MAIN_DEF_X
    mov word [main_restore_y], MAIN_DEF_Y
    mov word [main_restore_w], MAIN_DEF_W
    mov word [main_restore_h], MAIN_DEF_H
    mov byte [main_minimized], 0
    mov byte [main_maximized], 0

    ; Reset the fixed-size process table.  Process 0 is Program Manager;
    ; slots 1..8 use private 48-KiB extended-memory backing arenas.
    push es
    xor ax, ax
    mov es, ax
    mov di, proc_type
    mov cx, process_table_end-proc_type
    xor al, al
    rep stosb
    pop es
    mov byte [proc_type], 0xFF
    mov byte [active_pid], 0
    mov byte [active_type], APP_NONE
    mov word [active_data_seg], 0
    mov byte [proc_arena_pid], 0
    mov byte [next_spawn], 0

    mov word [clipboard_len], 0
    push es
    mov ax, CLIP_SEG
    mov es, ax
    xor di, di
    mov cx, 16384
    xor ax, ax
    rep stosw
    pop es

    mov byte [foreground_window], WIN_MAIN
    mov byte [z_count], 1
    mov byte [z_order], WIN_MAIN
    mov byte [task_count], 1
    mov byte [task_order], WIN_MAIN
    mov byte [menu_open], MENU_NONE
    mov byte [menu_owner_pid], WIN_MAIN
    mov byte [message_open], 0
    mov byte [message_kind], MSG_TEXT
    mov byte [app_dirty], 0
    mov byte [app_has_saved], 0
    mov byte [pending_unsaved_pid], 0
    mov byte [pending_unsaved_action], 0
    mov byte [control_open], 0
    mov byte [control_slider_drag], 0
    mov byte [debug_open], 0
    mov byte [debug_scroll_drag], 0
    mov word [debug_scroll_offset], 0
    mov byte [debug_pending_int], 0
    mov byte [debug_pending_fault], 0
    mov byte [debug_result_success], 0
    mov byte [debug_probe_seen], 0
    mov byte [custom_open], 0
    mov byte [custom_created], 0
    mov byte [custom_minimized], 0
    mov byte [custom_maximized], 0
    mov byte [custom_dirty], 0
    mov byte [custom_hex_half], 0
    mov byte [custom_selection], 0
    mov byte [custom_mouse_select], 0
    mov byte [custom_scroll_drag], 0
    mov byte [custom_resize_drag], 0
    mov byte [custom_confirm], 0
    mov byte [custom_prompt_mode], 0
    mov dword [custom_len], 0
    mov dword [custom_cursor], 0
    mov dword [custom_anchor], 0
    mov dword [custom_scroll_line], 0
    mov dword [custom_total_lines], 1
    mov dword [custom_hscroll_col], 0
    mov dword [custom_max_line_cols], 0
    mov dword [custom_clip_len], 0
    mov byte [custom_undo_valid], 0
    mov byte [custom_redo_valid], 0
    mov byte [custom_ext_loaded], 1
    mov word [custom_status_ptr], str_custom_ready
    mov word [custom_x], CUSTOM_DEFAULT_X
    mov word [custom_y], CUSTOM_DEFAULT_Y
    mov word [custom_w], CUSTOM_DEFAULT_W
    mov word [custom_h], CUSTOM_DEFAULT_H
    mov word [custom_restore_x], CUSTOM_DEFAULT_X
    mov word [custom_restore_y], CUSTOM_DEFAULT_Y
    mov word [custom_restore_w], CUSTOM_DEFAULT_W
    mov word [custom_restore_h], CUSTOM_DEFAULT_H
    mov word [control_x], 48
    mov word [control_y], 28
    mov byte [mouse_swap_buttons], 0
    mov byte [mouse_speed], 8
    mov al, [boot_default_gui]
    xor al, 1
    and al, 1
    mov [control_boot_dos], al

    mov byte [drag_mode], 0
    mov byte [drag_pid], 0
    mov byte [interaction_pid], 0
    mov byte [painting_active], 0
    mov byte [paint_live_active], 0
    mov byte [paint_live_started], 0
    mov byte [paint_live_prev_valid], 0
    mov byte [paint_pending_action], PAINT_PENDING_NONE
    mov byte [captured_button], BTN_NONE
    mov byte [captured_pid], 0
    mov byte [capture_inside], 0
    mov byte [keyboard_move_mode], 0
    mov byte [last_sys_window], 0xFF
    mov word [last_sys_tick], 0
    mov word [draw_seg], VGA_SEG
    mov byte [note_cache_total_pid], 0xFF
    mov byte [note_cache_pos_pid], 0xFF
    mov byte [note_edit_group_pid], 0xFF
    mov byte [note_edit_group_kind], 0
    mov byte [note_batch_input], 0
    mov byte [note_batch_changed], 0

    mov byte [dos_attr], 0x07
    mov byte [dos_history_count], 0
    mov byte [dos_history_pos], 0
    mov byte [dos_line_len], 0
    mov byte [dos_cursor_pos], 0

    mov word [mouse_x], 160
    mov word [mouse_y], 100
    mov word [mouse_last_x], 160
    mov word [mouse_last_y], 100
    mov word [mouse_hover_x], 160
    mov word [mouse_hover_y], 100
    mov byte [mouse_hover_valid], 1
    mov word [cursor_draw_x], 160
    mov word [cursor_draw_y], 100
    mov byte [mouse_buttons], 0
    mov byte [mouse_raw_buttons], 0
    mov byte [mouse_prev_buttons], 0
    mov byte [mouse_changed], 0
    mov byte [mouse_wheel], 0
    mov byte [cursor_visible], 0
    mov byte [clipboard_kind], 0
    mov byte [paint_zoom], 1
    mov word [paint_scroll_x], 0
    mov word [paint_scroll_y], 0
    mov byte [paint_select_active], 0
    mov byte [paint_select_drag], 0
    mov byte [paint_select_pending], 0
    mov byte [paint_select_buffer_valid], 0
    mov byte [paint_palette_positioned], 0
    mov byte [paint_palette_drag], 0
    mov byte [vm_abs_valid], 0
    mov byte [vm_abs_cal_counter], 0
    ret

; =============================================================================
; Basic drawing
; =============================================================================
putpixel:
    ; CX=x, DX=y, AL=color
    push ax
    push bx
    push di
    push es
    mov [pixel_color], al
    cmp cx, SCREEN_W
    jae .done
    cmp dx, SCREEN_H
    jae .done
    mov bx, dx
    mov di, bx
    shl di, 6
    shl bx, 8
    add di, bx
    add di, cx
    mov ax, [draw_seg]
    mov es, ax
    mov al, [pixel_color]
    mov es:[di], al
.done:
    pop es
    pop di
    pop bx
    pop ax
    ret

putpixel_vga:
    ; CX=x, DX=y, AL=color. Used for immediate Paint feedback while the
    ; persistent copy is also written to the process canvas/back buffer.
    push ax
    push bx
    push di
    push es
    mov [pixel_color], al
    cmp cx, SCREEN_W
    jae .done
    cmp dx, SCREEN_H
    jae .done
    mov bx, dx
    mov di, bx
    shl di, 6
    shl bx, 8
    add di, bx
    add di, cx
    mov ax, VGA_SEG
    mov es, ax
    mov al, [pixel_color]
    mov es:[di], al
.done:
    pop es
    pop di
    pop bx
    pop ax
    ret

fill_rect:
    ; AX=x, BX=y, CX=w, DX=h, SI=color
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push es
    mov [rect_x], ax
    mov [rect_y], bx
    mov [rect_w], cx
    mov [rect_h], dx
    mov ax, si
    mov [rect_color], al
    mov ax, [draw_seg]
    mov es, ax
    xor bp, bp
.row:
    cmp bp, [rect_h]
    jae .done
    mov bx, [rect_y]
    add bx, bp
    cmp bx, SCREEN_H
    jae .next
    mov di, bx
    mov ax, bx
    shl di, 6
    shl ax, 8
    add di, ax
    add di, [rect_x]
    mov cx, [rect_w]
    mov al, [rect_color]
    rep stosb
.next:
    inc bp
    jmp .row
.done:
    pop es
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

hline:
    ; AX=x, BX=y, CX=len, DL=color
    push ax
    push bx
    push cx
    push dx
    push di
    push es
    cmp bx, SCREEN_H
    jae .done
    mov di, bx
    mov bx, di
    shl di, 6
    shl bx, 8
    add di, bx
    add di, ax
    mov ax, [draw_seg]
    mov es, ax
    mov al, dl
    rep stosb
.done:
    pop es
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

vline:
    ; AX=x, BX=y, CX=len, DL=color
    push ax
    push bx
    push cx
    push dx
    push di
    push es
    mov di, bx
    mov bx, di
    shl di, 6
    shl bx, 8
    add di, bx
    add di, ax
    mov ax, [draw_seg]
    mov es, ax
    mov al, dl
.loop:
    cmp cx, 0
    je .done
    mov es:[di], al
    add di, SCREEN_W
    dec cx
    jmp .loop
.done:
    pop es
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_bevel_box:
    ; AX=x, BX=y, CX=w, DX=h
    push ax
    push bx
    push cx
    push dx
    push si
    mov [box_x], ax
    mov [box_y], bx
    mov [box_w], cx
    mov [box_h], dx
    mov si, COL_GRAY
    call fill_rect

    mov ax, [box_x]
    mov bx, [box_y]
    mov cx, [box_w]
    mov dl, COL_WHITE
    call hline
    mov ax, [box_x]
    mov bx, [box_y]
    mov cx, [box_h]
    mov dl, COL_WHITE
    call vline

    mov ax, [box_x]
    mov bx, [box_y]
    add bx, [box_h]
    dec bx
    mov cx, [box_w]
    mov dl, COL_DARKGRAY
    call hline
    mov ax, [box_x]
    add ax, [box_w]
    dec ax
    mov bx, [box_y]
    mov cx, [box_h]
    mov dl, COL_DARKGRAY
    call vline
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_frame_black:
    ; AX=x, BX=y, CX=w, DX=h
    push ax
    push bx
    push cx
    push dx
    mov [box_x], ax
    mov [box_y], bx
    mov [box_w], cx
    mov [box_h], dx

    mov dl, COL_BLACK
    call hline
    mov ax, [box_x]
    mov bx, [box_y]
    mov cx, [box_h]
    call vline
    mov ax, [box_x]
    mov bx, [box_y]
    add bx, [box_h]
    dec bx
    mov cx, [box_w]
    call hline
    mov ax, [box_x]
    add ax, [box_w]
    dec ax
    mov bx, [box_y]
    mov cx, [box_h]
    call vline
    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_resize_grip:
    ; AX=x, BX=y, CX=w, DX=h. Draw the classic bottom-right resize marks.
    push ax
    push bx
    push cx
    push dx
    push si
    mov [resize_grip_x], ax
    add [resize_grip_x], cx
    sub word [resize_grip_x], 8
    mov [resize_grip_y], bx
    add [resize_grip_y], dx
    sub word [resize_grip_y], 7
    mov ax, [resize_grip_x]
    add ax, 4
    mov bx, [resize_grip_y]
    mov cx, 3
    mov dl, COL_DARKGRAY
    call hline
    mov ax, [resize_grip_x]
    add ax, 2
    mov bx, [resize_grip_y]
    add bx, 2
    mov cx, 5
    mov dl, COL_DARKGRAY
    call hline
    mov ax, [resize_grip_x]
    mov bx, [resize_grip_y]
    add bx, 4
    mov cx, 7
    mov dl, COL_DARKGRAY
    call hline
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

strlen_z:
    ; DS:SI -> string, returns CX, preserves SI
    push ax
    push si
    xor cx, cx
.loop:
    lodsb
    test al, al
    jz .done
    inc cx
    jmp .loop
.done:
    pop si
    pop ax
    ret

draw_char:
    ; AL=ASCII, CX=x, DX=y, BL=color, transparent background
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push es
    push fs
    mov [char_code], al
    mov [char_x], cx
    mov [char_y], dx
    mov [char_color], bl

    xor ah, ah
    mov al, [char_code]
    shl ax, 3
    add ax, [font_off]
    mov si, ax
    mov ax, [font_seg]
    mov fs, ax
    mov ax, [draw_seg]
    mov es, ax

    xor bp, bp
.row:
    cmp bp, 8
    jae .done
    mov bl, fs:[si+bp]
    mov ax, [char_y]
    add ax, bp
    mov di, ax
    mov dx, ax
    shl di, 6
    shl dx, 8
    add di, dx
    add di, [char_x]
    mov dl, 0x80
    mov cx, 8
.bit:
    test bl, dl
    jz .skip
    mov al, [char_color]
    mov es:[di], al
.skip:
    inc di
    shr dl, 1
    loop .bit
    inc bp
    jmp .row
.done:
    pop fs
    pop es
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_char_scaled:
    ; AL=ASCII, CX=x, DX=y, BL=color, BH=scale (1..3).
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push fs
    mov [scaled_char_code], al
    mov [scaled_char_x], cx
    mov [scaled_char_y], dx
    mov [scaled_char_color], bl
    mov [scaled_char_scale], bh
    cmp byte [scaled_char_scale], 1
    jae .scale_ok
    mov byte [scaled_char_scale], 1
.scale_ok:
    xor ah, ah
    mov al, [scaled_char_code]
    shl ax, 3
    add ax, [font_off]
    mov si, ax
    mov ax, [font_seg]
    mov fs, ax
    xor bp, bp
.row:
    cmp bp, 8
    jae .done
    mov al, fs:[si+bp]
    mov [scaled_char_bits], al
    mov byte [scaled_char_mask], 0x80
    xor di, di
.col:
    cmp di, 8
    jae .next_row
    mov al, [scaled_char_bits]
    test al, [scaled_char_mask]
    jz .skip
    mov ax, di
    xor bx, bx
    mov bl, [scaled_char_scale]
    mul bx
    add ax, [scaled_char_x]
    mov [scaled_pixel_x], ax
    mov ax, bp
    mul bx
    add ax, [scaled_char_y]
    mov [scaled_pixel_y], ax
    ; fill_rect takes the color in SI, but SI is also our ROM-font glyph
    ; pointer. Preserve it for all remaining pixels and rows of this character.
    push si
    xor ax, ax
    mov al, [scaled_char_color]
    mov si, ax
    mov ax, [scaled_pixel_x]
    mov bx, [scaled_pixel_y]
    xor cx, cx
    mov cl, [scaled_char_scale]
    xor dx, dx
    mov dl, [scaled_char_scale]
    call fill_rect
    pop si
.skip:
    shr byte [scaled_char_mask], 1
    inc di
    jmp .col
.next_row:
    inc bp
    jmp .row
.done:
    pop fs
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_text:
    ; DS:SI zero-terminated, CX=x, DX=y, BL=color
    push ax
    push cx
    push dx
    push si
.next:
    lodsb
    test al, al
    jz .done
    call draw_char
    add cx, 8
    jmp .next
.done:
    pop si
    pop dx
    pop cx
    pop ax
    ret

draw_text_wrapped:
    ; DS:SI zero-terminated, CX=x, DX=y, BL=color, DI=right edge.
    ; Long status/reason text wraps automatically onto 13-pixel rows.
    push ax
    push cx
    push dx
    push si
    push di
    push bp
    mov bp, cx
.next:
    lodsb
    test al, al
    jz .done
    cmp al, 0x0A
    je .new_line
    push ax
    mov ax, cx
    add ax, 8
    cmp ax, di
    pop ax
    jbe .draw
.new_line:
    mov cx, bp
    add dx, 13
    cmp al, 0x0A
    je .next
.draw:
    call draw_char
    add cx, 8
    jmp .next
.done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop ax
    ret

draw_button:
    ; AX=x, BX=y, CX=w, DX=h, SI=label
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov [button_x], ax
    mov [button_y], bx
    mov [button_w], cx
    mov [button_h], dx
    mov [button_label], si
    call draw_bevel_box

    mov si, [button_label]
    call strlen_z
    mov ax, cx
    shl ax, 3
    mov di, [button_w]
    cmp di, ax
    jae .label_fits
    xor di, di                 ; never underflow when a label is wider
    jmp short .label_offset_ready
.label_fits:
    sub di, ax
    shr di, 1
.label_offset_ready:
    add di, [button_x]
    mov cx, di
    mov dx, [button_h]
    sub dx, 8
    shr dx, 1
    add dx, [button_y]
    mov si, [button_label]
    mov bl, COL_BLACK
    call draw_text
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret



draw_button_pressed:
    ; AX=x, BX=y, CX=w, DX=h, SI=label. Classic sunken button.
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov [button_x], ax
    mov [button_y], bx
    mov [button_w], cx
    mov [button_h], dx
    mov [button_label], si

    mov si, COL_GRAY
    call fill_rect
    mov ax, [button_x]
    mov bx, [button_y]
    mov cx, [button_w]
    mov dl, COL_DARKGRAY
    call hline
    mov ax, [button_x]
    mov bx, [button_y]
    mov cx, [button_h]
    mov dl, COL_DARKGRAY
    call vline
    mov ax, [button_x]
    inc ax
    mov bx, [button_y]
    inc bx
    mov cx, [button_w]
    sub cx, 2
    mov dl, COL_BLACK
    call hline
    mov ax, [button_x]
    inc ax
    mov bx, [button_y]
    inc bx
    mov cx, [button_h]
    sub cx, 2
    mov dl, COL_BLACK
    call vline
    mov ax, [button_x]
    mov bx, [button_y]
    add bx, [button_h]
    dec bx
    mov cx, [button_w]
    mov dl, COL_WHITE
    call hline
    mov ax, [button_x]
    add ax, [button_w]
    dec ax
    mov bx, [button_y]
    mov cx, [button_h]
    mov dl, COL_WHITE
    call vline

    mov si, [button_label]
    call strlen_z
    mov ax, cx
    shl ax, 3
    mov di, [button_w]
    cmp di, ax
    jae .pressed_label_fits
    xor di, di                 ; never underflow when a label is wider
    jmp short .pressed_label_offset_ready
.pressed_label_fits:
    sub di, ax
    shr di, 1
.pressed_label_offset_ready:
    add di, [button_x]
    inc di
    mov cx, di
    mov dx, [button_h]
    sub dx, 8
    shr dx, 1
    add dx, [button_y]
    inc dx
    mov si, [button_label]
    mov bl, COL_BLACK
    call draw_text
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_system_button:
    ; AX=x, BX=y, classic control-menu button with three horizontal bars.
    push ax
    push bx
    push cx
    push dx
    call draw_bevel_box
    mov cx, 10
    add ax, 4
    add bx, 3
    mov dl, COL_BLACK
    call hline
    add bx, 2
    call hline
    add bx, 2
    call hline
    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_system_button_pressed:
    ; AX=x, BX=y, CX=w, DX=h. Sunken classic control-menu button.
    push ax
    push bx
    push cx
    push dx
    push si
    mov [button_x], ax
    mov [button_y], bx
    mov [button_w], cx
    mov [button_h], dx
    mov si, COL_GRAY
    call fill_rect

    mov ax, [button_x]
    mov bx, [button_y]
    mov cx, [button_w]
    mov dl, COL_DARKGRAY
    call hline
    mov ax, [button_x]
    mov bx, [button_y]
    mov cx, [button_h]
    mov dl, COL_DARKGRAY
    call vline
    mov ax, [button_x]
    mov bx, [button_y]
    add bx, [button_h]
    dec bx
    mov cx, [button_w]
    mov dl, COL_WHITE
    call hline
    mov ax, [button_x]
    add ax, [button_w]
    dec ax
    mov bx, [button_y]
    mov cx, [button_h]
    mov dl, COL_WHITE
    call vline

    mov ax, [button_x]
    add ax, 5
    mov bx, [button_y]
    add bx, 4
    mov cx, 10
    mov dl, COL_BLACK
    call hline
    add bx, 2
    call hline
    add bx, 2
    call hline
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_captured_button_overlay:
    cmp byte [captured_button], BTN_NONE
    je .done
    cmp byte [capture_inside], 0
    je .done
    ; Task labels share task_label_buf. redraw_all redraws every task button
    ; before this pressed overlay, so regenerate the captured task's label
    ; here instead of reusing the final label left by draw_taskbar.
    cmp byte [captured_button], BTN_TASK_BASE
    jb .label_ready
    cmp byte [captured_button], BTN_TASK_CUSTOM
    ja .label_ready
    mov al, [captured_pid]
    call task_get_label_action
    mov [capture_label], si
.label_ready:
    cmp byte [captured_button], BTN_DEBUG_INT_ITEM
    jne .debug_label_ready
    mov al, [debug_pending_int]
    call debug_build_int_label
    mov word [capture_label], debug_int_label_buf
.debug_label_ready:
    cmp byte [captured_button], BTN_DEBUG_NORMAL_ITEM
    jne .normal_fault_label_ready
    mov al, [debug_pending_fault]
    call debug_fault_get_label
    mov [capture_label], si
.normal_fault_label_ready:
    ; Paint RGB-related buttons are rendered in their owning Paint window.
    ; Do not draw a second global overlay: redraw_all may have loaded another
    ; process after Paint, which made the old duplicate animation appear at an
    ; unrelated screen position.
    cmp byte [captured_button], BTN_PAINT_PALETTE
    je .done
    cmp byte [captured_button], BTN_PALETTE_CLOSE
    je .done
    cmp byte [captured_button], BTN_PALETTE_OK
    je .done
    mov ax, [capture_x]
    mov bx, [capture_y]
    mov cx, [capture_w]
    mov dx, [capture_h]
    cmp byte [captured_button], BTN_SYS_MENU
    je .system
    mov si, [capture_label]
    call draw_button_pressed
    ret
.system:
    call draw_system_button_pressed
.done:
    ret

; =============================================================================
; Process table and instance state swapping
; =============================================================================
proc_segment_for_pid:
    ; AL=process id 1..8 -> AX=shared conventional-memory working segment.
    ; The far-extension swapper maps this arena to the pid's private extended
    ; backing slot. Preserve DX because callers keep process/type values in DL.
    ; Invalid ids return AX=0 so a caller can never turn one into an IVT/BDA
    ; write through a bogus private-memory segment.
    push bx
    push dx
    xor ah, ah
    cmp ax, 1
    jb .invalid
    cmp ax, MAX_PROCS
    jae .invalid
    mov ax, PROC_BASE_SEG
    jmp .done
.invalid:
    xor ax, ax
.done:
    pop dx
    pop bx
    ret

proc_load:
    ; AL=process id. Load common geometry and type-specific state.
    push ax
    push bx
    push si
    push di
    cmp al, MAX_PROCS
    jb .pid_valid
    xor al, al
.pid_valid:
    ; Swap the 48-KiB working arena only when another process owns it.  Track
    ; that owner separately from active_pid because modal code legitimately
    ; sets active_pid to Program Manager without touching the private bytes.
    cmp al, [proc_arena_pid]
    je .arena_resident
    push ax
    call STAGE2_EXT_SEG:(proc_backing_save_ext-stage2_ext_start)
    pop ax
    mov [proc_arena_pid], al
    test al, al
    jz .arena_resident
    push ax
    call STAGE2_EXT_SEG:(proc_backing_load_ext-stage2_ext_start)
    pop ax
.arena_resident:
    mov [active_pid], al
    xor bx, bx
    mov bl, al
    mov al, [proc_type+bx]
    mov [active_type], al
    mov al, [active_pid]
    test al, al
    jz .main_segment
    call proc_segment_for_pid
    jmp .segment_ready
.main_segment:
    xor ax, ax
.segment_ready:
    mov [active_data_seg], ax
    xor bx, bx
    mov bl, [active_pid]
    test bx, bx
    jz .done
    mov si, bx
    shl si, 1
    mov al, [proc_dirty+bx]
    mov [app_dirty], al
    mov al, [proc_has_saved+bx]
    mov [app_has_saved], al

    mov al, [proc_type+bx]
    cmp al, APP_PAINT
    je .paint
    cmp al, APP_NOTEPAD
    je .note
    cmp al, APP_CALC
    je .calc
    jmp .done

.paint:
    mov ax, [proc_x+si]
    mov [paint_x], ax
    mov ax, [proc_y+si]
    mov [paint_y], ax
    mov ax, [proc_w+si]
    mov [paint_w], ax
    mov ax, [proc_h+si]
    mov [paint_h], ax
    mov ax, [proc_restore_x+si]
    mov [paint_restore_x], ax
    mov ax, [proc_restore_y+si]
    mov [paint_restore_y], ax
    mov ax, [proc_restore_w+si]
    mov [paint_restore_w], ax
    mov ax, [proc_restore_h+si]
    mov [paint_restore_h], ax
    mov byte [paint_open], 1
    mov al, [proc_minimized+bx]
    mov [paint_minimized], al
    mov al, [proc_maximized+bx]
    mov [paint_maximized], al
    mov al, [proc_paint_color+bx]
    mov [paint_color], al
    mov al, [proc_paint_eraser+bx]
    mov [paint_eraser], al
    mov al, [proc_paint_rainbow+bx]
    mov [paint_rainbow], al
    mov al, [proc_paint_phase+bx]
    mov [paint_rainbow_phase], al
    mov al, [proc_paint_brush+bx]
    mov [paint_brush_size], al
    mov al, [proc_paint_tool+bx]
    mov [paint_tool], al
    mov al, [proc_paint_text_sel+bx]
    mov [paint_text_selected], al
    mov al, [proc_paint_text_input+bx]
    mov [paint_text_input], al
    mov al, [proc_paint_text_size+bx]
    mov [paint_text_size], al
    mov ax, [proc_paint_canvas_w+si]
    mov [paint_canvas_w], ax
    mov ax, [proc_paint_canvas_h+si]
    mov [paint_canvas_h], ax
    mov al, [proc_paint_text_active+bx]
    mov [paint_text_active], al
    mov ax, [proc_paint_text_x+si]
    mov [paint_text_x], ax
    mov ax, [proc_paint_text_y+si]
    mov [paint_text_y], ax
    mov ax, [proc_paint_text_len+si]
    mov [paint_text_len], ax
    mov ax, [proc_paint_text_cursor+si]
    mov [paint_text_cursor], ax
    mov ax, [proc_paint_text_anchor+si]
    mov [paint_text_anchor], ax
    mov al, [proc_paint_text_sel_active+bx]
    mov [paint_text_sel_active], al
    mov al, [proc_paint_text_mouse_sel+bx]
    mov [paint_text_mouse_select], al
    mov al, [proc_paint_palette_open+bx]
    mov [paint_palette_open], al
    mov al, [proc_paint_rgb_focus+bx]
    mov [paint_rgb_focus], al
    mov al, [proc_paint_rgb_r+bx]
    mov [paint_rgb_r], al
    mov al, [proc_paint_rgb_g+bx]
    mov [paint_rgb_g], al
    mov al, [proc_paint_rgb_b+bx]
    mov [paint_rgb_b], al
    mov al, [proc_paint_custom_color+bx]
    mov [paint_custom_color], al
    mov al, [proc_paint_custom_active+bx]
    mov [paint_custom_active], al
    mov al, [proc_paint_rgb_replace+bx]
    mov [paint_rgb_replace], al
    mov al, [proc_painting_active+bx]
    mov [painting_active], al
    mov al, [proc_paint_prev_valid+bx]
    mov [paint_prev_valid], al
    mov ax, [proc_paint_prev_x+si]
    mov [paint_prev_x], ax
    mov ax, [proc_paint_prev_y+si]
    mov [paint_prev_y], ax
    mov al, [proc_paint_undo+bx]
    mov [undo_available], al
    jmp .done

.note:
    mov ax, [proc_x+si]
    mov [note_x], ax
    mov ax, [proc_y+si]
    mov [note_y], ax
    mov ax, [proc_w+si]
    mov [note_w], ax
    mov ax, [proc_h+si]
    mov [note_h], ax
    mov ax, [proc_restore_x+si]
    mov [note_restore_x], ax
    mov ax, [proc_restore_y+si]
    mov [note_restore_y], ax
    mov ax, [proc_restore_w+si]
    mov [note_restore_w], ax
    mov ax, [proc_restore_h+si]
    mov [note_restore_h], ax
    mov byte [note_open], 1
    mov al, [proc_minimized+bx]
    mov [note_minimized], al
    mov al, [proc_maximized+bx]
    mov [note_maximized], al
    mov al, [proc_note_focus+bx]
    mov [note_focus], al
    mov ax, [proc_note_len+si]
    mov [note_len], ax
    mov ax, [proc_note_cursor+si]
    mov [note_cursor], ax
    mov ax, [proc_note_anchor+si]
    mov [note_anchor], ax
    mov ax, [proc_note_scroll+si]
    mov [note_scroll_row], ax
    mov al, [proc_note_sel+bx]
    mov [note_sel_active], al
    mov al, [proc_note_mouse_sel+bx]
    mov [note_mouse_select], al
    mov al, [proc_note_undo_valid+bx]
    mov [note_undo_valid], al
    mov al, [proc_note_undo_sel+bx]
    mov [note_undo_sel], al
    mov ax, [proc_note_undo_len+si]
    mov [note_undo_len], ax
    mov ax, [proc_note_undo_cursor+si]
    mov [note_undo_cursor], ax
    mov ax, [proc_note_undo_anchor+si]
    mov [note_undo_anchor], ax
    mov ax, [proc_note_undo_scroll+si]
    mov [note_undo_scroll], ax
    call notepad_validate_state
    jmp .done

.calc:
    mov ax, [proc_x+si]
    mov [calc_x], ax
    mov ax, [proc_y+si]
    mov [calc_y], ax
    mov ax, [proc_w+si]
    mov [calc_w], ax
    mov ax, [proc_h+si]
    mov [calc_h], ax
    mov ax, [proc_restore_x+si]
    mov [calc_restore_x], ax
    mov ax, [proc_restore_y+si]
    mov [calc_restore_y], ax
    mov ax, [proc_restore_w+si]
    mov [calc_restore_w], ax
    mov ax, [proc_restore_h+si]
    mov [calc_restore_h], ax
    mov byte [calc_open], 1
    mov al, [proc_minimized+bx]
    mov [calc_minimized], al
    mov al, [proc_maximized+bx]
    mov [calc_maximized], al
    mov di, bx
    shl di, 1
    add di, bx
    shl di, 2
    mov eax, [proc_calc_acc+di]
    mov [calc_acc], eax
    mov eax, [proc_calc_acc+di+4]
    mov [calc_acc+4], eax
    mov eax, [proc_calc_acc+di+8]
    mov [calc_acc+8], eax
    mov eax, [proc_calc_current+di]
    mov [calc_current], eax
    mov eax, [proc_calc_current+di+4]
    mov [calc_current+4], eax
    mov eax, [proc_calc_current+di+8]
    mov [calc_current+8], eax
    mov al, [proc_calc_op+bx]
    mov [calc_op], al
    mov al, [proc_calc_entry+bx]
    mov [calc_entry], al
    mov al, [proc_calc_error+bx]
    mov [calc_error], al
    mov al, [proc_calc_fresh+bx]
    mov [calc_result_fresh], al
    mov al, [proc_calc_decimal+bx]
    mov [calc_decimal], al
    mov al, [proc_calc_frac+bx]
    mov [calc_frac_digits], al
.done:
    pop di
    pop si
    pop bx
    pop ax
    ret

proc_save:
    ; Save the currently loaded scratch state back to its process slot.
    push ax
    push bx
    push si
    push di
    xor bx, bx
    mov bl, [active_pid]
    test bx, bx
    jz .done
    cmp bx, MAX_PROCS
    jae .done
    mov al, [proc_type+bx]
    test al, al
    jz .done
    mov si, bx
    shl si, 1
    mov al, [app_dirty]
    mov [proc_dirty+bx], al
    mov al, [app_has_saved]
    mov [proc_has_saved+bx], al
    mov al, [proc_type+bx]
    cmp al, APP_PAINT
    je .paint
    cmp al, APP_NOTEPAD
    je .note
    cmp al, APP_CALC
    je .calc
    jmp .done
.paint:
    mov ax, [paint_x]
    mov [proc_x+si], ax
    mov ax, [paint_y]
    mov [proc_y+si], ax
    mov ax, [paint_w]
    mov [proc_w+si], ax
    mov ax, [paint_h]
    mov [proc_h+si], ax
    mov ax, [paint_restore_x]
    mov [proc_restore_x+si], ax
    mov ax, [paint_restore_y]
    mov [proc_restore_y+si], ax
    mov ax, [paint_restore_w]
    mov [proc_restore_w+si], ax
    mov ax, [paint_restore_h]
    mov [proc_restore_h+si], ax
    mov al, [paint_minimized]
    mov [proc_minimized+bx], al
    mov al, [paint_maximized]
    mov [proc_maximized+bx], al
    mov al, [paint_color]
    mov [proc_paint_color+bx], al
    mov al, [paint_eraser]
    mov [proc_paint_eraser+bx], al
    mov al, [paint_rainbow]
    mov [proc_paint_rainbow+bx], al
    mov al, [paint_rainbow_phase]
    mov [proc_paint_phase+bx], al
    mov al, [paint_brush_size]
    mov [proc_paint_brush+bx], al
    mov al, [paint_tool]
    mov [proc_paint_tool+bx], al
    mov al, [paint_text_selected]
    mov [proc_paint_text_sel+bx], al
    mov al, [paint_text_input]
    mov [proc_paint_text_input+bx], al
    mov al, [paint_text_size]
    mov [proc_paint_text_size+bx], al
    mov ax, [paint_canvas_w]
    mov [proc_paint_canvas_w+si], ax
    mov ax, [paint_canvas_h]
    mov [proc_paint_canvas_h+si], ax
    mov al, [paint_text_active]
    mov [proc_paint_text_active+bx], al
    mov ax, [paint_text_x]
    mov [proc_paint_text_x+si], ax
    mov ax, [paint_text_y]
    mov [proc_paint_text_y+si], ax
    mov ax, [paint_text_len]
    mov [proc_paint_text_len+si], ax
    mov ax, [paint_text_cursor]
    mov [proc_paint_text_cursor+si], ax
    mov ax, [paint_text_anchor]
    mov [proc_paint_text_anchor+si], ax
    mov al, [paint_text_sel_active]
    mov [proc_paint_text_sel_active+bx], al
    mov al, [paint_text_mouse_select]
    mov [proc_paint_text_mouse_sel+bx], al
    mov al, [paint_palette_open]
    mov [proc_paint_palette_open+bx], al
    mov al, [paint_rgb_focus]
    mov [proc_paint_rgb_focus+bx], al
    mov al, [paint_rgb_r]
    mov [proc_paint_rgb_r+bx], al
    mov al, [paint_rgb_g]
    mov [proc_paint_rgb_g+bx], al
    mov al, [paint_rgb_b]
    mov [proc_paint_rgb_b+bx], al
    mov al, [paint_custom_color]
    mov [proc_paint_custom_color+bx], al
    mov al, [paint_custom_active]
    mov [proc_paint_custom_active+bx], al
    mov al, [paint_rgb_replace]
    mov [proc_paint_rgb_replace+bx], al
    mov al, [painting_active]
    mov [proc_painting_active+bx], al
    mov al, [paint_prev_valid]
    mov [proc_paint_prev_valid+bx], al
    mov ax, [paint_prev_x]
    mov [proc_paint_prev_x+si], ax
    mov ax, [paint_prev_y]
    mov [proc_paint_prev_y+si], ax
    mov al, [undo_available]
    mov [proc_paint_undo+bx], al
    jmp .done
.note:
    call notepad_validate_state
    mov ax, [note_x]
    mov [proc_x+si], ax
    mov ax, [note_y]
    mov [proc_y+si], ax
    mov ax, [note_w]
    mov [proc_w+si], ax
    mov ax, [note_h]
    mov [proc_h+si], ax
    mov ax, [note_restore_x]
    mov [proc_restore_x+si], ax
    mov ax, [note_restore_y]
    mov [proc_restore_y+si], ax
    mov ax, [note_restore_w]
    mov [proc_restore_w+si], ax
    mov ax, [note_restore_h]
    mov [proc_restore_h+si], ax
    mov al, [note_minimized]
    mov [proc_minimized+bx], al
    mov al, [note_maximized]
    mov [proc_maximized+bx], al
    mov al, [note_focus]
    mov [proc_note_focus+bx], al
    mov ax, [note_len]
    mov [proc_note_len+si], ax
    mov ax, [note_cursor]
    mov [proc_note_cursor+si], ax
    mov ax, [note_anchor]
    mov [proc_note_anchor+si], ax
    mov ax, [note_scroll_row]
    mov [proc_note_scroll+si], ax
    mov al, [note_sel_active]
    mov [proc_note_sel+bx], al
    mov al, [note_mouse_select]
    mov [proc_note_mouse_sel+bx], al
    mov al, [note_undo_valid]
    mov [proc_note_undo_valid+bx], al
    mov al, [note_undo_sel]
    mov [proc_note_undo_sel+bx], al
    mov ax, [note_undo_len]
    mov [proc_note_undo_len+si], ax
    mov ax, [note_undo_cursor]
    mov [proc_note_undo_cursor+si], ax
    mov ax, [note_undo_anchor]
    mov [proc_note_undo_anchor+si], ax
    mov ax, [note_undo_scroll]
    mov [proc_note_undo_scroll+si], ax
    jmp .done
.calc:
    mov ax, [calc_x]
    mov [proc_x+si], ax
    mov ax, [calc_y]
    mov [proc_y+si], ax
    mov ax, [calc_w]
    mov [proc_w+si], ax
    mov ax, [calc_h]
    mov [proc_h+si], ax
    mov ax, [calc_restore_x]
    mov [proc_restore_x+si], ax
    mov ax, [calc_restore_y]
    mov [proc_restore_y+si], ax
    mov ax, [calc_restore_w]
    mov [proc_restore_w+si], ax
    mov ax, [calc_restore_h]
    mov [proc_restore_h+si], ax
    mov al, [calc_minimized]
    mov [proc_minimized+bx], al
    mov al, [calc_maximized]
    mov [proc_maximized+bx], al
    mov di, bx
    shl di, 1
    add di, bx
    shl di, 2
    mov eax, [calc_acc]
    mov [proc_calc_acc+di], eax
    mov eax, [calc_acc+4]
    mov [proc_calc_acc+di+4], eax
    mov eax, [calc_acc+8]
    mov [proc_calc_acc+di+8], eax
    mov eax, [calc_current]
    mov [proc_calc_current+di], eax
    mov eax, [calc_current+4]
    mov [proc_calc_current+di+4], eax
    mov eax, [calc_current+8]
    mov [proc_calc_current+di+8], eax
    mov al, [calc_op]
    mov [proc_calc_op+bx], al
    mov al, [calc_entry]
    mov [proc_calc_entry+bx], al
    mov al, [calc_error]
    mov [proc_calc_error+bx], al
    mov al, [calc_result_fresh]
    mov [proc_calc_fresh+bx], al
    mov al, [calc_decimal]
    mov [proc_calc_decimal+bx], al
    mov al, [calc_frac_digits]
    mov [proc_calc_frac+bx], al
.done:
    pop di
    pop si
    pop bx
    pop ax
    ret

proc_clear_private_memory:
    push ax
    push cx
    push di
    push es
    ; Recompute and verify the segment before a 48 KiB clear.  If process
    ; state was damaged, returning is safe; clearing segment zero is not.
    mov al, [active_pid]
    call proc_segment_for_pid
    test ax, ax
    jz .done
    cmp ax, [active_data_seg]
    jne .done
    mov es, ax
    xor di, di
    xor ax, ax
    mov cx, PROC_ARENA_WORDS
    cld
    rep stosw
.done:
    pop es
    pop di
    pop cx
    pop ax
    ret

proc_create:
    ; AL=APP_*; create a fresh independent process every time.
    push ax
    push bx
    push dx
    mov dl, al
    mov bx, 1
.find:
    cmp bx, MAX_PROCS
    jae .full
    cmp byte [proc_type+bx], APP_NONE
    je .found
    inc bx
    jmp .find
.found:
    mov [proc_type+bx], dl
    mov byte [proc_minimized+bx], 0
    mov byte [proc_dirty+bx], 0
    mov byte [proc_has_saved+bx], 0
    mov al, bl
    call proc_load
    call proc_clear_private_memory

    ; Cascaded but deterministic positions keep every new process reachable.
    xor ax, ax
    mov al, [next_spawn]
    inc byte [next_spawn]
    and byte [next_spawn], MAX_PROCS-2
    mov cx, ax
    mov al, dl
    cmp al, APP_PAINT
    je .init_paint
    cmp al, APP_NOTEPAD
    je .init_note
    jmp .init_calc
.init_paint:
    mov ax, cx
    mov dx, 7
    mul dx
    add ax, 8
    cmp ax, SCREEN_W-PAINT_W
    jbe .px_ok
    mov ax, SCREEN_W-PAINT_W
.px_ok:
    mov [paint_x], ax
    mov ax, cx
    mov dx, 3
    mul dx
    add ax, 1
    cmp ax, TASKBAR_Y-PAINT_H
    jbe .py_ok
    mov ax, TASKBAR_Y-PAINT_H
.py_ok:
    mov [paint_y], ax
    mov word [paint_w], PAINT_W
    mov word [paint_h], PAINT_H
    mov word [paint_restore_x], 0
    mov word [paint_restore_y], 0
    mov word [paint_restore_w], PAINT_W
    mov word [paint_restore_h], PAINT_H
    mov byte [paint_maximized], 0
    mov byte [paint_open], 1
    mov byte [paint_minimized], 0
    mov byte [app_dirty], 0
    mov byte [app_has_saved], 0
    mov byte [paint_color], COL_BLUE
    mov byte [paint_eraser], 0
    mov byte [paint_rainbow], 0
    mov byte [paint_rainbow_phase], 0
    mov byte [paint_brush_size], 2
    mov byte [paint_tool], PAINT_TOOL_PENCIL
    mov byte [paint_text_selected], 0xFF
    mov byte [paint_text_input], 0
    mov byte [paint_text_size], 1
    mov word [paint_canvas_w], PAINT_CANVAS_DEFAULT_W
    mov word [paint_canvas_h], PAINT_CANVAS_DEFAULT_H
    mov byte [paint_text_active], 0
    mov word [paint_text_x], 0
    mov word [paint_text_y], 0
    mov word [paint_text_len], 0
    mov word [paint_text_cursor], 0
    mov word [paint_text_anchor], 0
    mov byte [paint_text_sel_active], 0
    mov byte [paint_text_mouse_select], 0
    mov byte [paint_palette_open], 0
    mov byte [paint_rgb_focus], 0
    mov byte [paint_rgb_r], 0
    mov byte [paint_rgb_g], 0
    mov byte [paint_rgb_b], 255
    mov byte [paint_custom_color], COL_WHITE
    mov byte [paint_custom_active], 0
    mov byte [paint_rgb_replace], 0
    mov byte [painting_active], 0
    mov byte [paint_prev_valid], 0
    mov byte [paint_zoom], 1
    mov word [paint_scroll_x], 0
    mov word [paint_scroll_y], 0
    mov byte [paint_select_active], 0
    mov byte [paint_select_drag], 0
    mov byte [paint_select_pending], 0
    mov byte [paint_select_buffer_valid], 0
    mov byte [paint_palette_positioned], 0
    mov byte [undo_available], 0
    call canvas_clear_memory
    call paint_text_clear_all
    call STAGE2_EXT_SEG:(app_storage_load_paint_ext-stage2_ext_start)
    jmp .ready
.init_note:
    mov ax, cx
    shl ax, 2
    add ax, 2
    cmp ax, SCREEN_W-NOTE_W
    jbe .nx_ok
    mov ax, SCREEN_W-NOTE_W
.nx_ok:
    mov [note_x], ax
    mov ax, cx
    shl ax, 1
    add ax, 2
    cmp ax, TASKBAR_Y-NOTE_H
    jbe .ny_ok
    mov ax, TASKBAR_Y-NOTE_H
.ny_ok:
    mov [note_y], ax
    mov word [note_w], NOTE_W
    mov word [note_h], NOTE_H
    mov word [note_restore_x], 0
    mov word [note_restore_y], 0
    mov word [note_restore_w], NOTE_W
    mov word [note_restore_h], NOTE_H
    mov byte [note_maximized], 0
    mov byte [note_open], 1
    mov byte [note_minimized], 0
    mov byte [app_dirty], 0
    mov byte [app_has_saved], 0
    mov byte [note_focus], 1
    mov word [note_len], 0
    mov word [note_cursor], 0
    mov word [note_anchor], 0
    mov word [note_scroll_row], 0
    mov byte [note_sel_active], 0
    mov byte [note_mouse_select], 0
    call notepad_clear_undo_state
    call STAGE2_EXT_SEG:(app_storage_load_note_ext-stage2_ext_start)
    jmp .ready
.init_calc:
    mov ax, cx
    mov dx, 15
    mul dx
    add ax, 18
    cmp ax, SCREEN_W-CALC_W
    jbe .cx_ok
    mov ax, SCREEN_W-CALC_W
.cx_ok:
    mov [calc_x], ax
    mov ax, cx
    mov dx, 3
    mul dx
    add ax, 1
    cmp ax, TASKBAR_Y-CALC_H
    jbe .cy_ok
    mov ax, TASKBAR_Y-CALC_H
.cy_ok:
    mov [calc_y], ax
    mov word [calc_w], CALC_W
    mov word [calc_h], CALC_H
    mov word [calc_restore_x], 0
    mov word [calc_restore_y], 0
    mov word [calc_restore_w], CALC_W
    mov word [calc_restore_h], CALC_H
    mov byte [calc_maximized], 0
    mov byte [calc_open], 1
    mov byte [calc_minimized], 0
    mov byte [app_dirty], 0
    mov dword [calc_acc], 0
    mov dword [calc_acc+4], 0
    mov dword [calc_acc+8], 0
    mov dword [calc_current], 0
    mov dword [calc_current+4], 0
    mov dword [calc_current+8], 0
    mov byte [calc_op], 0
    mov byte [calc_entry], 0
    mov byte [calc_error], 0
    mov byte [calc_result_fresh], 0
    mov byte [calc_decimal], 0
    mov byte [calc_frac_digits], 0
.ready:
    call proc_save
    mov al, [active_pid]
    call task_add_window
    mov al, [active_pid]
    call bring_to_front
    mov byte [menu_open], MENU_NONE
    call redraw_all
    pop dx
    pop bx
    pop ax
    ret
.full:
    mov byte [message_kind], MSG_SYSTEM
    mov byte [message_open], 1
    mov si, str_process_limit
    mov [system_message_ptr], si
    call redraw_all
    pop dx
    pop bx
    pop ax
    ret

proc_close:
    ; AL=pid. Paint and Notepad ask before discarding modified content.
    cmp al, WIN_MAIN
    jne .app
    jmp show_exit_confirmation
.app:
    push ax
    push bx
    xor bx, bx
    mov bl, al
    cmp bx, MAX_PROCS
    jae .no_prompt
    mov ah, [proc_type+bx]
    cmp ah, APP_PAINT
    je .check_dirty
    cmp ah, APP_NOTEPAD
    jne .no_prompt
.check_dirty:
    cmp byte [proc_dirty+bx], 0
    je .no_prompt
    pop bx
    pop ax
    mov byte [pending_unsaved_action], 1
    jmp show_unsaved_prompt
.no_prompt:
    pop bx
    pop ax

proc_close_force:
    push ax
    call z_remove_window
    pop ax
    push ax
    call task_remove_window
    pop ax
    xor bx, bx
    mov bl, al
    mov byte [proc_type+bx], APP_NONE
    mov byte [proc_minimized+bx], 0
    mov byte [proc_dirty+bx], 0
    mov byte [proc_has_saved+bx], 0
    mov byte [menu_open], MENU_NONE
    mov byte [drag_mode], 0
    mov byte [captured_button], BTN_NONE
    call normalize_foreground
    call redraw_all
    ret

proc_minimize:
    cmp al, WIN_MAIN
    jne .app
    jmp minimize_main
.app:
    push ax
    xor bx, bx
    mov bl, al
    cmp bx, MAX_PROCS
    jae .bad
    cmp byte [proc_type+bx], APP_NONE
    je .bad
    mov byte [proc_minimized+bx], 1
    ; Reload the slot after changing the table so redraw_all cannot save a
    ; stale minimized flag from the scratch variables back over it.
    call proc_load
    mov byte [menu_open], MENU_NONE
    mov byte [drag_mode], 0
    call normalize_foreground
    call redraw_all
.bad:
    pop ax
    ret

proc_restore:
    cmp al, WIN_MAIN
    jne .app
    mov byte [main_minimized], 0
    call bring_to_front
    mov byte [menu_open], MENU_NONE
    call redraw_all
    ret
.app:
    push ax
    xor bx, bx
    mov bl, al
    cmp bx, MAX_PROCS
    jae .done
    cmp byte [proc_type+bx], APP_NONE
    je .done
    mov byte [proc_minimized+bx], 0
    call proc_load
    pop ax
    push ax
    call bring_to_front
    mov byte [menu_open], MENU_NONE
    call redraw_all
.done:
    pop ax
    ret

; =============================================================================
; Desktop, windows, menus and taskbar
; =============================================================================
normalize_foreground:
    ; Select the topmost visible window from the real Z-order list.
    push ax
    push bx
    ; Custom Program is a full modal overlay rather than a child of Progman.
    ; Use an out-of-range foreground id while it is open so Progman's title,
    ; task button, resize grip, and cursor hit testing all lose focus.
    cmp byte [custom_open], 0
    je .scan_windows
    mov byte [foreground_window], 0xFF
    pop bx
    pop ax
    ret
.scan_windows:
    xor bx, bx
    mov bl, [z_count]
    test bx, bx
    jz .none
    dec bx
.scan:
    mov al, [z_order+bx]
    call window_is_visible
    jc .choose
    test bx, bx
    jz .none
    dec bx
    jmp .scan
.choose:
    mov [foreground_window], al
    pop bx
    pop ax
    ret
.none:
    mov byte [foreground_window], WIN_MAIN
    pop bx
    pop ax
    ret

window_is_open:
    ; AL=process id, CF=1 while its task exists. Preserve the caller's BX,
    ; because Z-order and taskbar scans use BX as their loop index.
    push bx
    cmp al, WIN_MAIN
    je .yes
    xor bx, bx
    mov bl, al
    cmp bx, MAX_PROCS
    jae .no
    cmp byte [proc_type+bx], APP_NONE
    jne .yes
.no:
    pop bx
    clc
    ret
.yes:
    pop bx
    stc
    ret

window_is_visible:
    ; AL=process id, CF=1 when open and not minimized. Preserve BX.
    push bx
    cmp al, WIN_MAIN
    jne .app
    cmp byte [main_minimized], 0
    jne .no
    jmp .yes
.app:
    xor bx, bx
    mov bl, al
    cmp bx, MAX_PROCS
    jae .no
    cmp byte [proc_type+bx], APP_NONE
    je .no
    cmp byte [proc_minimized+bx], 0
    jne .no
.yes:
    pop bx
    stc
    ret
.no:
    pop bx
    clc
    ret

bring_to_front:
    ; AL=pid. Move an existing process to the top of z_order.
    push ax
    push bx
    push cx
    push dx
    push si
    mov dl, al
    xor cx, cx
    mov cl, [z_count]
    xor bx, bx
.find:
    cmp bx, cx
    jae .append
    cmp byte [z_order+bx], dl
    je .found
    inc bx
    jmp .find
.found:
    mov si, bx
.shift:
    mov ax, cx
    dec ax
    cmp si, ax
    jae .store_existing
    mov al, [z_order+si+1]
    mov [z_order+si], al
    inc si
    jmp .shift
.store_existing:
    mov si, cx
    dec si
    jmp .store
.append:
    cmp cx, MAX_PROCS
    jae .foreground_only
    mov si, cx
    inc byte [z_count]
.store:
    mov [z_order+si], dl
.foreground_only:
    mov [foreground_window], dl
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

z_remove_window:
    ; AL=pid.
    push ax
    push bx
    push cx
    push dx
    mov dl, al
    xor cx, cx
    mov cl, [z_count]
    xor bx, bx
.find:
    cmp bx, cx
    jae .done
    cmp byte [z_order+bx], dl
    je .shift
    inc bx
    jmp .find
.shift:
    mov ax, bx
    inc ax
    cmp ax, cx
    jae .shrink
    mov al, [z_order+bx+1]
    mov [z_order+bx], al
    inc bx
    jmp .shift
.shrink:
    cmp byte [z_count], 0
    je .done
    dec byte [z_count]
.done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

task_add_window:
    ; AL=pid. Tasks retain actual launch order.
    push ax
    push bx
    push cx
    push dx
    mov dl, al
    xor cx, cx
    mov cl, [task_count]
    xor bx, bx
.find:
    cmp bx, cx
    jae .append
    cmp byte [task_order+bx], dl
    je .done
    inc bx
    jmp .find
.append:
    cmp cx, MAX_PROCS+1
    jae .done
    mov [task_order+bx], dl
    inc byte [task_count]
.done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

task_remove_window:
    push ax
    push bx
    push cx
    push dx
    mov dl, al
    xor cx, cx
    mov cl, [task_count]
    xor bx, bx
.find:
    cmp bx, cx
    jae .done
    cmp byte [task_order+bx], dl
    je .shift
    inc bx
    jmp .find
.shift:
    mov ax, bx
    inc ax
    cmp ax, cx
    jae .shrink
    mov al, [task_order+bx+1]
    mov [task_order+bx], al
    inc bx
    jmp .shift
.shrink:
    cmp byte [task_count], 0
    je .done
    dec byte [task_count]
.done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

task_compute_width:
    ; Fit every task from the left edge without reserving privileged space.
    push ax
    push bx
    push dx
    xor bx, bx
    mov bl, [task_count]
    test bx, bx
    jnz .divide
    mov bx, 1
.divide:
    mov ax, SCREEN_W-4
    xor dx, dx
    div bx
    sub ax, 2
    cmp ax, TASK_BUTTON_W
    jbe .max_ok
    mov ax, TASK_BUTTON_W
.max_ok:
    cmp ax, TASK_BUTTON_MIN_W
    jae .store
    mov ax, TASK_BUTTON_MIN_W
.store:
    mov [task_button_w], ax
    pop dx
    pop bx
    pop ax
    ret

task_get_label_action:
    ; AL=pid -> SI=label, DI=BTN_TASK_BASE+pid.
    push ax
    push bx
    xor bx, bx
    mov bl, al
    mov di, task_label_buf
    cmp al, WIN_CUSTOM
    je .custom
    cmp al, WIN_MAIN
    jne .app
    mov si, str_task_main
    cmp byte [task_count], 5
    jbe .copy
    mov si, str_task_main_small
    jmp .copy
.custom:
    mov si, str_task_custom
    cmp byte [task_count], 5
    jbe .copy_no_suffix
    mov si, str_task_custom_small
    jmp .copy_no_suffix
.app:
    mov al, [proc_type+bx]
    cmp al, APP_PAINT
    je .paint
    cmp al, APP_NOTEPAD
    je .note
    mov si, str_task_calc_base
    jmp .copy
.paint:
    mov si, str_task_paint_base
    jmp .copy
.note:
    mov si, str_task_note_base
.copy:
    mov di, task_label_buf
.copy_no_suffix:
.copy_loop_entry:
.copy_loop:
    lodsb
    test al, al
    jz .suffix
    stosb
    jmp .copy_loop
.suffix:
    cmp bl, WIN_CUSTOM
    je .terminate
    cmp bl, 0
    je .terminate
    mov al, '#'
    stosb
    mov al, bl
    add al, '0'
    stosb
.terminate:
    xor al, al
    stosb
    mov si, task_label_buf
    xor di, di
    cmp bl, WIN_CUSTOM
    jne .normal_action
    mov di, BTN_TASK_CUSTOM
    jmp .action_ready
.normal_action:
    mov di, bx
    add di, BTN_TASK_BASE
.action_ready:
    pop bx
    pop ax
    ret

draw_window_id:
    ; AL=pid. Load its private state and draw by process type.
    push ax
    call window_is_visible
    jnc .not_visible
    pop ax
    cmp al, WIN_MAIN
    je .main
    call proc_load
    mov al, [active_type]
    cmp al, APP_PAINT
    je .paint
    cmp al, APP_NOTEPAD
    je .note
    cmp al, APP_CALC
    je .calc
    ret
.main:
    mov byte [active_pid], WIN_MAIN
    mov byte [active_type], APP_NONE
    call draw_main_window
    ret
.paint:
    call draw_paint_window
    ret
.note:
    call draw_notepad_window
    ret
.calc:
    call draw_calc_window
    ret
.not_visible:
    pop ax
    ret

redraw_all:
    ; Persist the active process, render off-screen, then present in one copy.
    call proc_save
    mov word [draw_seg], BACKBUF_SEG
    call normalize_foreground
    call draw_desktop
    xor bx, bx
    xor cx, cx
    mov cl, [z_count]
.windows:
    cmp bx, cx
    jae .after_windows
    mov al, [z_order+bx]
    push bx
    push cx
    call draw_window_id
    pop cx
    pop bx
    inc bx
    jmp .windows
.after_windows:
    call draw_taskbar
    cmp byte [menu_open], MENU_NONE
    je .control
    call draw_open_menu
.control:
    cmp byte [control_open], 0
    je .debug
    call draw_control_panel
.debug:
    cmp byte [debug_open], 0
    je .custom
    call draw_debug_window
.custom:
    cmp byte [custom_open], 0
    je .message
    call CUSTOM_CODE_SEG:custom_entry_draw
.message:
    cmp byte [message_open], 0
    je .pressed
    call draw_messagebox
.pressed:
    call draw_captured_button_overlay
    call present_backbuffer
    ret

present_backbuffer:
    pushf
    cli
    push ax
    push cx
    push si
    push di
    push ds
    push es
    mov ax, BACKBUF_SEG
    mov ds, ax
    mov ax, VGA_SEG
    mov es, ax
    xor si, si
    xor di, di
    mov cx, 32000
    rep movsw
    pop es
    pop ds
    pop di
    pop si
    pop cx
    pop ax
    popf
    mov word [draw_seg], VGA_SEG
    ret

draw_desktop:
    mov ax, 0
    mov bx, 0
    mov cx, SCREEN_W
    mov dx, TASKBAR_Y
    mov si, COL_CYAN
    call fill_rect
    ret

draw_taskbar:
    mov ax, 0
    mov bx, TASKBAR_Y
    mov cx, SCREEN_W
    mov dx, TASKBAR_H
    call draw_bevel_box
    call task_compute_width

    xor bx, bx
    mov word [task_draw_x], 2
.loop:
    xor cx, cx
    mov cl, [task_count]
    cmp bx, cx
    jae .done
    mov al, [task_order+bx]
    mov [task_draw_id], al
    call task_get_label_action
    mov ax, [task_draw_x]
    mov dx, TASKBAR_H-2
    mov cx, [task_button_w]
    push bx
    mov bx, TASKBAR_Y+1
    call draw_button
    pop bx

    mov al, [task_draw_id]
    cmp al, WIN_CUSTOM
    jne .normal_active_check
    cmp byte [custom_open], 0
    je .next
    jmp short .draw_active_frame
.normal_active_check:
    cmp al, [foreground_window]
    jne .next
    call window_is_visible
    jnc .next
.draw_active_frame:
    mov ax, [task_draw_x]
    dec ax
    push bx
    mov bx, TASKBAR_Y
    mov cx, [task_button_w]
    add cx, 2
    mov dx, TASKBAR_H
    call draw_frame_black
    pop bx
.next:
    mov ax, [task_button_w]
    add ax, 2
    add [task_draw_x], ax
    inc bx
    jmp .loop
.done:
    ret

draw_main_window:
    mov ax, [main_x]
    mov bx, [main_y]
    mov cx, [main_w]
    mov dx, [main_h]
    call draw_bevel_box
    call draw_frame_black

    mov ax, [main_x]
    add ax, 3
    mov bx, [main_y]
    add bx, 3
    mov cx, [main_w]
    sub cx, 6
    mov dx, TITLE_H
    mov si, COL_DARKGRAY
    cmp byte [foreground_window], WIN_MAIN
    jne .title_color_ready
    mov si, COL_BLUE
.title_color_ready:
    call fill_rect

    mov si, str_main_title
    mov cx, [main_x]
    add cx, 27
    mov dx, [main_y]
    add dx, 8
    mov bl, COL_WHITE
    call draw_text
    call draw_main_controls
    call draw_main_menu_bar

    mov si, str_programs
    mov cx, [main_x]
    add cx, 16
    mov dx, [main_y]
    add dx, 47
    mov bl, COL_BLACK
    call draw_text

    call main_compute_app_layout

    ; Two rows keep every application label comfortably inside its button.
    ; Row 1: Paint / Notepad. Row 2: Calc / Control.
    mov ax, [main_app_x1]
    mov bx, [main_y]
    add bx, 63
    mov cx, [main_app_btn_w]
    mov dx, 28
    mov si, str_paint
    call draw_button

    mov ax, [main_app_x2]
    mov bx, [main_y]
    add bx, 63
    mov cx, [main_app_btn_w]
    mov dx, 28
    mov si, str_notepad_short
    call draw_button

    mov ax, [main_app_x3]
    mov bx, [main_y]
    add bx, 99
    mov cx, [main_app_btn_w]
    mov dx, 28
    mov si, str_calc_short
    call draw_button

    mov ax, [main_app_x4]
    mov bx, [main_y]
    add bx, 99
    mov cx, [main_app_btn_w_last]
    mov dx, 28
    mov si, str_control
    call draw_button

    ; Debug and Custom Program use the same two-column geometry as the rows
    ; above, keeping both launchers compact and aligned.
    mov ax, [main_app_x1]
    mov bx, [main_y]
    add bx, 133
    mov cx, [main_app_btn_w]
    mov dx, 24
    mov si, str_debug
    call draw_button

    mov ax, [main_app_x2]
    mov bx, [main_y]
    add bx, 133
    mov cx, [main_app_btn_w_last]
    mov dx, 24
    mov si, str_custom_program
    call draw_button
    cmp byte [main_maximized], 0
    jne .done
    mov ax, [main_x]
    mov bx, [main_y]
    mov cx, [main_w]
    mov dx, [main_h]
    call draw_resize_grip
.done:
    ret

main_compute_app_layout:
    ; Two equal columns with 16 px side margins and an 8 px center gap.
    ; x1/x3 are the left column; x2/x4 are the right column.
    push ax
    push bx
    push dx
    mov ax, [main_w]
    sub ax, 40                 ; 16 + 16 side margins and one 8 px gap
    xor dx, dx
    mov bx, 2
    div bx
    cmp ax, 72                 ; enough for the 7-character labels
    jae .width_ok
    mov ax, 72
.width_ok:
    mov [main_app_btn_w], ax
    mov [main_app_btn_w_last], ax
    mov bx, [main_x]
    add bx, 16
    mov [main_app_x1], bx
    mov [main_app_x3], bx
    add bx, ax
    add bx, 8
    mov [main_app_x2], bx
    mov [main_app_x4], bx
    pop dx
    pop bx
    pop ax
    ret

draw_main_controls:
    ; Left button is the control-menu icon; minimize stays on the right.
    mov ax, [main_x]
    add ax, 4
    mov bx, [main_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    call draw_system_button

    mov ax, [main_x]
    add ax, [main_w]
    sub ax, 59
    mov bx, [main_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_min
    call draw_button

    mov ax, [main_x]
    add ax, [main_w]
    sub ax, 40
    mov bx, [main_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    cmp byte [main_maximized], 0
    je .max_symbol
    mov si, str_restore
    jmp .draw_max
.max_symbol:
    mov si, str_max
.draw_max:
    call draw_button

    mov ax, [main_x]
    add ax, [main_w]
    sub ax, 21
    mov bx, [main_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_close
    call draw_button
    ret

draw_main_menu_bar:
    mov ax, [main_x]
    add ax, 3
    mov bx, [main_y]
    add bx, 22
    mov cx, [main_w]
    sub cx, 6
    mov dx, MENU_H
    mov si, COL_GRAY
    call fill_rect
    mov ax, [main_x]
    add ax, 3
    mov bx, [main_y]
    add bx, 35
    mov cx, [main_w]
    sub cx, 6
    mov dl, COL_DARKGRAY
    call hline

    mov si, str_menu_file
    mov cx, [main_x]
    add cx, 7
    mov dx, [main_y]
    add dx, 25
    mov bl, COL_BLACK
    call draw_text
    mov si, str_menu_apps
    mov cx, [main_x]
    add cx, 47
    mov dx, [main_y]
    add dx, 25
    mov bl, COL_BLACK
    call draw_text
    mov si, str_menu_help
    mov cx, [main_x]
    add cx, 87
    mov dx, [main_y]
    add dx, 25
    mov bl, COL_BLACK
    call draw_text
    ret

draw_paint_window:
    mov ax, [paint_x]
    mov bx, [paint_y]
    mov cx, [paint_w]
    mov dx, [paint_h]
    call draw_bevel_box
    call draw_frame_black

    mov ax, [paint_x]
    add ax, 3
    mov bx, [paint_y]
    add bx, 3
    mov cx, [paint_w]
    sub cx, 6
    mov dx, TITLE_H
    mov si, COL_DARKGRAY
    push ax
    mov al, [foreground_window]
    cmp al, [active_pid]
    pop ax
    jne .title_ready
    mov si, COL_BLUE
.title_ready:
    call fill_rect

    mov si, str_paint_title
    mov cx, [paint_x]
    add cx, 27
    mov dx, [paint_y]
    add dx, 8
    mov bl, COL_WHITE
    call draw_text

    mov ax, [paint_x]
    add ax, 4
    mov bx, [paint_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    call draw_system_button

    mov ax, [paint_x]
    add ax, [paint_w]
    sub ax, 59
    mov bx, [paint_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_min
    call draw_button

    mov ax, [paint_x]
    add ax, [paint_w]
    sub ax, 40
    mov bx, [paint_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    cmp byte [paint_maximized], 0
    je .max_symbol
    mov si, str_restore
    jmp .draw_max
.max_symbol:
    mov si, str_max
.draw_max:
    call draw_button

    mov ax, [paint_x]
    add ax, [paint_w]
    sub ax, 21
    mov bx, [paint_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_close
    call draw_button

    call draw_paint_menu_bar
    call draw_paint_toolbar
    call draw_palette
    call paint_compute_canvas_rect

    mov ax, [paint_canvas_screen_x]
    dec ax
    mov bx, [paint_canvas_screen_y]
    dec bx
    mov cx, [paint_canvas_screen_w]
    add cx, 2
    mov dx, [paint_canvas_screen_h]
    add dx, 2
    mov si, COL_BLACK
    call fill_rect
    call draw_canvas_to_screen
    call draw_paint_scrollbars
    call draw_paint_status

    cmp byte [paint_maximized], 0
    jne .palette_dialog
    mov ax, [paint_x]
    mov bx, [paint_y]
    mov cx, [paint_w]
    mov dx, [paint_h]
    call draw_resize_grip
.palette_dialog:
    cmp byte [paint_palette_open], 0
    je .done
    call draw_paint_palette_dialog
.done:
    ret

paint_compute_canvas_rect:
    mov ax, [paint_x]
    add ax, PAINT_CANVAS_XOFF
    mov [paint_canvas_screen_x], ax
    mov ax, [paint_y]
    add ax, PAINT_CANVAS_YOFF
    mov [paint_canvas_screen_y], ax
    mov ax, [paint_w]
    sub ax, PAINT_CANVAS_XOFF+PAINT_CANVAS_RIGHT_MARGIN
    cmp byte [paint_zoom], 1
    jbe .width_ready
    sub ax, 12
.width_ready:
    mov [paint_canvas_screen_w], ax
    mov [paint_view_w], ax
    mov ax, [paint_h]
    sub ax, PAINT_CANVAS_YOFF+PAINT_CANVAS_BOTTOM_MARGIN
    cmp byte [paint_zoom], 1
    jbe .height_ready
    sub ax, 12
.height_ready:
    mov [paint_canvas_screen_h], ax
    mov [paint_view_h], ax
    ret

draw_paint_menu_bar:
    mov ax, [paint_x]
    add ax, 3
    mov bx, [paint_y]
    add bx, 22
    mov cx, [paint_w]
    sub cx, 6
    mov dx, MENU_H
    mov si, COL_GRAY
    call fill_rect
    mov ax, [paint_x]
    add ax, 3
    mov bx, [paint_y]
    add bx, 35
    mov cx, [paint_w]
    sub cx, 6
    mov dl, COL_DARKGRAY
    call hline

    mov si, str_menu_file
    mov cx, [paint_x]
    add cx, 7
    mov dx, [paint_y]
    add dx, 25
    mov bl, COL_BLACK
    call draw_text
    mov si, str_menu_edit
    mov cx, [paint_x]
    add cx, 47
    mov dx, [paint_y]
    add dx, 25
    mov bl, COL_BLACK
    call draw_text
    mov si, str_menu_view
    mov cx, [paint_x]
    add cx, 87
    mov dx, [paint_y]
    add dx, 25
    mov bl, COL_BLACK
    call draw_text
    ret

draw_paint_toolbar:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    xor di, di
.loop:
    cmp di, PAINT_TOOL_COUNT
    jae .done
    mov ax, di
    and ax, 1
    mov cx, 25
    mul cx
    add ax, [paint_x]
    add ax, 5
    mov [button_x], ax
    mov bx, di
    shr bx, 1
    mov ax, bx
    mov cx, 21
    mul cx
    add ax, [paint_y]
    add ax, 39
    mov bx, ax
    mov ax, [button_x]
    mov cx, 23
    mov dx, 19
    mov si, paint_tool_labels_early
    mov ax, di
    shl ax, 1
    add si, ax
    mov si, [si]
    mov ax, [button_x]
    call draw_button
    call draw_paint_tool_icon
    xor ax, ax
    mov al, [paint_tool]
    cmp ax, di
    jne .next
    mov ax, [button_x]
    sub ax, 2
    sub bx, 2
    mov cx, 27
    mov dx, 23
    call draw_frame_black
.next:
    inc di
    jmp .loop
.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_paint_tool_icon:
    ; DI=tool index. Most custom tools use compact 11x11 monochrome bitmaps;
    ; Select uses the exact centered 13x13 reference bitmap.
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    cmp di, PAINT_TOOL_EYEDROP
    je .eyedrop
    cmp di, PAINT_TOOL_LINE
    je .line
    cmp di, PAINT_TOOL_RECT
    je .rect
    cmp di, PAINT_TOOL_SELECT
    je .select
    cmp di, PAINT_TOOL_MAGNIFY
    jne .done
    mov si, paint_icon_magnify_11
    jmp .draw
.eyedrop:
    mov si, paint_icon_eyedrop_11
    jmp .draw
.line:
    mov si, paint_icon_line_11
    jmp .draw
.rect:
    mov si, paint_icon_rect_11
    jmp .draw
.select:
    mov si, paint_icon_select_13
    mov ax, [button_x]
    add ax, 5
    mov bx, [button_y]
    add bx, 3
    call draw_paint_icon_13x13
    jmp .done
.draw:
    mov ax, [button_x]
    add ax, 6
    mov bx, [button_y]
    add bx, 4
    call draw_paint_icon_11x11
.done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_paint_icon_13x13:
    ; AX/BX=top-left, DS:SI=13 words. Bits 12..0 map left-to-right.
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    mov [paint_tool_icon_x], ax
    mov [paint_tool_icon_y], bx
    xor bp, bp
.row:
    cmp bp, 13
    jae .done
    mov ax, [si]
    add si, 2
    mov [paint_tool_icon_bits], ax
    xor di, di
.col:
    cmp di, 13
    jae .next_row
    test word [paint_tool_icon_bits], 0x1000
    jz .skip
    mov cx, [paint_tool_icon_x]
    add cx, di
    mov dx, [paint_tool_icon_y]
    add dx, bp
    mov al, COL_BLACK
    call putpixel
.skip:
    shl word [paint_tool_icon_bits], 1
    inc di
    jmp .col
.next_row:
    inc bp
    jmp .row
.done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_paint_icon_11x11:
    ; AX/BX=top-left, DS:SI=11 words. Bits 10..0 map left-to-right.
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    mov [paint_tool_icon_x], ax
    mov [paint_tool_icon_y], bx
    xor bp, bp
.row:
    cmp bp, 11
    jae .done
    mov ax, [si]
    add si, 2
    mov [paint_tool_icon_bits], ax
    xor di, di
.col:
    cmp di, 11
    jae .next_row
    test word [paint_tool_icon_bits], 0x0400
    jz .skip
    mov cx, [paint_tool_icon_x]
    add cx, di
    mov dx, [paint_tool_icon_y]
    add dx, bp
    mov al, COL_BLACK
    call putpixel
.skip:
    shl word [paint_tool_icon_bits], 1
    inc di
    jmp .col
.next_row:
    inc bp
    jmp .row
.done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Pointer tables used by 16-bit DS=0 drawing code must remain below physical
; 10000h. Keeping both Paint and Calculator labels here prevents wrapped
; pointers and the calculator's former garbage button captions.
paint_tool_labels_early:
    dw .pencil, .fill, .text, .eraser, .eyedrop, .line, .rect, .ellipse
    dw .select, .magnify
.pencil db 'P',0
.fill   db 'F',0
.text   db 'T',0
.eraser db 'E',0
.eyedrop db 0
.line   db 0
.rect   db 0
.ellipse db 'O',0
.select db 0
.magnify db 0

; Exact 13x13 all-black select icon from the supplied reference bitmap.
; Every original value 1 or 2 is rendered as black.
paint_icon_select_13:
    dw 0x040,0x0E0,0x1F0,0x0E0,0x4E4,0x0FFE,0x1FFF
    dw 0x0FFE,0x4E4,0x0E0,0x1F0,0x0E0,0x040

; Magnifier: a hollow round lens followed by a one-pixel diagonal handle.
paint_icon_magnify_11:
    dw 0x1C0,0x220,0x410,0x410,0x410,0x220
    dw 0x1D0,0x008,0x004,0x002,0x001

; Hollow 9x9 square centered inside the common 11x11 icon cell.
paint_icon_rect_11:
    dw 0x000,0x3FE,0x202,0x202,0x202,0x202
    dw 0x202,0x202,0x202,0x3FE,0x000

; Nine-pixel backslash: one pixel longer than the former 8x8 BIOS glyph.
paint_icon_line_11:
    dw 0x000,0x200,0x100,0x080,0x040,0x020
    dw 0x010,0x008,0x004,0x002,0x000

; Right-facing eyedropper in backslash direction: hollow rubber bulb at the
; upper-left, a broad collar, a solid diagonal tube and a pointed lower-right tip.
paint_icon_eyedrop_11:
    dw 0x380,0x440,0x460,0x3F8,0x1F0,0x0E0
    dw 0x070,0x038,0x01C,0x00E,0x001

calc_key_labels_early:
    dw .sqrt, .percent, .decimal, .back
    dw .seven, .eight, .nine, .plus
    dw .four, .five, .six, .minus
    dw .one, .two, .three, .multiply
    dw .clear, .zero, .equal, .divide
.sqrt db 'sqrt',0
.percent db '%',0
.back db '<-',0
.decimal db '.',0
.seven db '7',0
.eight db '8',0
.nine db '9',0
.plus db '+',0
.four db '4',0
.five db '5',0
.six db '6',0
.minus db '-',0
.one db '1',0
.two db '2',0
.three db '3',0
.multiply db '*',0
.clear db 'C',0
.zero db '0',0
.equal db '=',0
.divide db '/',0

; 32-segment unit circle, scaled by 127, used by the ellipse preview.
circle_cos_early:
    db 127,124,117,106,90,71,49,25,0,-25,-49,-71,-90,-106,-117,-124
    db -127,-124,-117,-106,-90,-71,-49,-25,0,25,49,71,90,106,117,124,127
circle_sin_early:
    db 0,25,49,71,90,106,117,124,127,124,117,106,90,71,49,25
    db 0,-25,-49,-71,-90,-106,-117,-124,-127,-124,-117,-106,-90,-71,-49,-25,0

draw_notepad_window:
    mov ax, [note_x]
    mov bx, [note_y]
    mov cx, [note_w]
    mov dx, [note_h]
    call draw_bevel_box
    call draw_frame_black

    mov ax, [note_x]
    add ax, 3
    mov bx, [note_y]
    add bx, 3
    mov cx, [note_w]
    sub cx, 6
    mov dx, TITLE_H
    mov si, COL_DARKGRAY
    push ax
    mov al, [foreground_window]
    cmp al, [active_pid]
    pop ax
    jne .title_ready
    mov si, COL_BLUE
.title_ready:
    call fill_rect
    mov si, str_notepad_title
    mov cx, [note_x]
    add cx, 27
    mov dx, [note_y]
    add dx, 8
    mov bl, COL_WHITE
    call draw_text

    mov ax, [note_x]
    add ax, 4
    mov bx, [note_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    call draw_system_button

    mov ax, [note_x]
    add ax, [note_w]
    sub ax, 59
    mov bx, [note_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_min
    call draw_button

    mov ax, [note_x]
    add ax, [note_w]
    sub ax, 40
    mov bx, [note_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    cmp byte [note_maximized], 0
    je .max_symbol
    mov si, str_restore
    jmp .draw_max
.max_symbol:
    mov si, str_max
.draw_max:
    call draw_button

    mov ax, [note_x]
    add ax, [note_w]
    sub ax, 21
    mov bx, [note_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_close
    call draw_button

    call draw_notepad_menu_bar
    call note_compute_layout
    mov ax, [note_text_x_dyn]
    mov bx, [note_text_y_dyn]
    mov cx, [note_text_w_dyn]
    mov dx, [note_text_h_dyn]
    mov si, COL_WHITE
    call fill_rect
    call draw_frame_black
    call draw_notepad_text
    call draw_notepad_scrollbar
    cmp byte [note_maximized], 0
    jne .done
    mov ax, [note_x]
    mov bx, [note_y]
    mov cx, [note_w]
    mov dx, [note_h]
    call draw_resize_grip
.done:
    ret

note_compute_layout:
    ; Text client grows with the window; wrapping and scrollbar use the same values.
    push ax
    push bx
    push dx
    mov ax, [note_x]
    add ax, NOTE_TEXT_XOFF
    mov [note_text_x_dyn], ax
    mov ax, [note_y]
    add ax, NOTE_TEXT_YOFF
    mov [note_text_y_dyn], ax
    mov ax, [note_w]
    sub ax, 16
    cmp ax, NOTE_SCROLL_W+18
    jae .w_ok
    mov ax, NOTE_SCROLL_W+18
.w_ok:
    mov [note_text_w_dyn], ax
    mov bx, ax
    sub bx, NOTE_SCROLL_W
    mov [note_view_w_dyn], bx
    mov ax, [note_h]
    sub ax, 50
    cmp ax, 26
    jae .h_ok
    mov ax, 26
.h_ok:
    mov [note_text_h_dyn], ax

    mov ax, [note_view_w_dyn]
    cmp ax, 10
    ja .cols_sub
    mov ax, 1
    jmp .cols_store
.cols_sub:
    sub ax, 10
    xor dx, dx
    mov bx, 8
    div bx
    cmp ax, 1
    jae .cols_store
    mov ax, 1
.cols_store:
    mov [note_cols_dyn], ax

    mov ax, [note_text_h_dyn]
    cmp ax, 10
    ja .rows_sub
    mov ax, 1
    jmp .rows_store
.rows_sub:
    sub ax, 10
    xor dx, dx
    mov bx, 8
    div bx
    cmp ax, 1
    jae .rows_store
    mov ax, 1
.rows_store:
    mov [note_rows_dyn], ax

    mov ax, [note_text_x_dyn]
    add ax, [note_text_w_dyn]
    sub ax, NOTE_SCROLL_W
    mov [note_scrollbar_x], ax
    mov ax, [note_text_y_dyn]
    mov [note_scrollbar_y], ax
    add ax, NOTE_SCROLL_W
    mov [note_track_y], ax
    mov ax, [note_text_h_dyn]
    sub ax, NOTE_SCROLL_W*2
    cmp ax, 4
    jae .track_ok
    mov ax, 4
.track_ok:
    mov [note_track_h], ax
    pop dx
    pop bx
    pop ax
    ret

draw_notepad_scrollbar:
    push ax
    push bx
    push cx
    push dx
    push si
    call note_compute_layout

    mov ax, [note_scrollbar_x]
    mov bx, [note_scrollbar_y]
    mov cx, NOTE_SCROLL_W
    mov dx, NOTE_SCROLL_W
    mov si, str_scroll_up
    call draw_button

    mov ax, [note_scrollbar_x]
    mov bx, [note_scrollbar_y]
    add bx, [note_text_h_dyn]
    sub bx, NOTE_SCROLL_W
    mov cx, NOTE_SCROLL_W
    mov dx, NOTE_SCROLL_W
    mov si, str_scroll_down
    call draw_button

    mov ax, [note_scrollbar_x]
    mov bx, [note_track_y]
    mov cx, NOTE_SCROLL_W
    mov dx, [note_track_h]
    mov si, COL_GRAY
    call fill_rect
    call draw_frame_black

    call notepad_compute_scrollbar
    mov ax, [note_scrollbar_x]
    inc ax
    mov bx, [note_thumb_y]
    mov cx, NOTE_SCROLL_W-2
    mov dx, [note_thumb_h]
    call draw_bevel_box

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_notepad_menu_bar:
    mov ax, [note_x]
    add ax, 3
    mov bx, [note_y]
    add bx, 22
    mov cx, [note_w]
    sub cx, 6
    mov dx, MENU_H
    mov si, COL_GRAY
    call fill_rect
    mov ax, [note_x]
    add ax, 3
    mov bx, [note_y]
    add bx, 35
    mov cx, [note_w]
    sub cx, 6
    mov dl, COL_DARKGRAY
    call hline
    mov si, str_menu_file
    mov cx, [note_x]
    add cx, 7
    mov dx, [note_y]
    add dx, 25
    mov bl, COL_BLACK
    call draw_text
    mov si, str_menu_edit
    mov cx, [note_x]
    add cx, 47
    mov dx, [note_y]
    add dx, 25
    mov bl, COL_BLACK
    call draw_text
    mov si, str_menu_help
    mov cx, [note_x]
    add cx, 87
    mov dx, [note_y]
    add dx, 25
    mov bl, COL_BLACK
    call draw_text
    ret

draw_notepad_text:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push fs
    call note_compute_layout
    mov ax, [active_data_seg]
    mov fs, ax

    call notepad_selection_bounds
    mov [note_sel_start_tmp], ax
    mov [note_sel_end_tmp], dx

    xor si, si
    xor di, di
    xor bp, bp
.scan:
    cmp si, [note_len]
    jae .caret
    ; Once the scan has passed the visible rows, the remaining document does
    ; not affect this frame.  The caret position is calculated separately.
    mov ax, [note_scroll_row]
    add ax, [note_rows_dyn]
    cmp bp, ax
    jae .caret
    mov al, fs:[si]
    cmp al, 13
    je .newline

    mov ax, bp
    cmp ax, [note_scroll_row]
    jb .advance_char
    mov dx, [note_scroll_row]
    add dx, [note_rows_dyn]
    cmp ax, dx
    jae .advance_char

    mov cx, [note_text_x_dyn]
    add cx, 5
    mov ax, di
    shl ax, 3
    add cx, ax
    mov dx, [note_text_y_dyn]
    add dx, 5
    mov ax, bp
    sub ax, [note_scroll_row]
    shl ax, 3
    add dx, ax

    mov ax, si
    cmp ax, [note_sel_start_tmp]
    jb .normal_char
    cmp ax, [note_sel_end_tmp]
    jae .normal_char
    push cx
    push dx
    push si
    mov ax, cx
    mov bx, dx
    mov cx, 8
    mov dx, 8
    mov si, COL_BLUE
    call fill_rect
    pop si
    pop dx
    pop cx
    mov al, fs:[si]
    mov bl, COL_WHITE
    call draw_char
    jmp .advance_char
.normal_char:
    mov al, fs:[si]
    mov bl, COL_BLACK
    call draw_char
.advance_char:
    inc si
    inc di
    cmp di, [note_cols_dyn]
    jb .scan
    xor di, di
    inc bp
    jmp .scan
.newline:
    inc si
    xor di, di
    inc bp
    jmp .scan

.caret:
    cmp byte [note_focus], 0
    je .done
    mov al, [foreground_window]
    cmp al, [active_pid]
    jne .done
    mov ax, [note_cursor]
    call notepad_index_to_rowcol
    mov dx, bx
    cmp dx, [note_scroll_row]
    jb .done
    mov ax, [note_scroll_row]
    add ax, [note_rows_dyn]
    cmp dx, ax
    jae .done
    sub dx, [note_scroll_row]
    shl dx, 3
    mov ax, [note_text_x_dyn]
    add ax, 5
    mov si, cx
    shl si, 3
    add ax, si
    mov bx, [note_text_y_dyn]
    add bx, 4
    add bx, dx
    mov cx, 9
    mov dl, COL_BLACK
    call vline
.done:
    pop fs
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

notepad_total_rows:
    ; Return AX=number of visual rows, including the final row.
    push bx
    push cx
    push dx
    push si
    push fs
    call note_compute_layout
    mov al, [active_pid]
    cmp al, [note_cache_total_pid]
    jne .scan_setup
    mov ax, [note_len]
    cmp ax, [note_cache_total_len]
    jne .scan_setup
    mov ax, [note_cols_dyn]
    cmp ax, [note_cache_total_cols]
    jne .scan_setup
    mov ax, [note_cache_total_rows]
    jmp .return
.scan_setup:
    mov ax, [active_data_seg]
    mov fs, ax
    xor si, si
    xor bx, bx
    xor cx, cx
.scan:
    cmp si, [note_len]
    jae .done_scan
    mov dl, fs:[si]
    inc si
    cmp dl, 13
    je .newline
    inc cx
    cmp cx, [note_cols_dyn]
    jb .scan
.newline:
    xor cx, cx
    inc bx
    jmp .scan
.done_scan:
    mov ax, bx
    inc ax
    mov [note_cache_total_rows], ax
    mov dl, [active_pid]
    mov [note_cache_total_pid], dl
    mov dx, [note_len]
    mov [note_cache_total_len], dx
    mov dx, [note_cols_dyn]
    mov [note_cache_total_cols], dx
.return:
    pop fs
    pop si
    pop dx
    pop cx
    pop bx
    ret

notepad_get_max_scroll:
    call note_compute_layout
    call notepad_total_rows
    cmp ax, [note_rows_dyn]
    ja .subtract
    xor ax, ax
    ret
.subtract:
    sub ax, [note_rows_dyn]
    ret

notepad_compute_scrollbar:
    ; Compute proportional draggable thumb position.
    push ax
    push bx
    push cx
    push dx
    call note_compute_layout
    call notepad_total_rows
    mov [note_total_rows_tmp], ax
    call notepad_get_max_scroll
    mov [note_max_scroll_tmp], ax
    test ax, ax
    jnz .scrollable
    mov ax, [note_track_h]
    sub ax, 2
    cmp ax, 2
    jae .full_thumb
    mov ax, 2
.full_thumb:
    mov [note_thumb_h], ax
    mov ax, [note_track_y]
    inc ax
    mov [note_thumb_y], ax
    jmp .done
.scrollable:
    mov ax, [note_track_h]
    sub ax, 2
    mov bx, [note_rows_dyn]
    mul bx
    mov bx, [note_total_rows_tmp]
    div bx
    cmp ax, 10
    jae .thumb_min_ok
    mov ax, 10
.thumb_min_ok:
    mov bx, [note_track_h]
    sub bx, 2
    cmp ax, bx
    jbe .thumb_max_ok
    mov ax, bx
.thumb_max_ok:
    mov [note_thumb_h], ax

    mov bx, [note_track_h]
    sub bx, 2
    sub bx, ax
    mov [note_thumb_range], bx
    mov ax, [note_scroll_row]
    mul bx
    mov bx, [note_max_scroll_tmp]
    div bx
    add ax, [note_track_y]
    inc ax
    mov [note_thumb_y], ax
.done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

notepad_scroll_line_up_no_draw:
    cmp word [note_scroll_row], 0
    je .done
    dec word [note_scroll_row]
.done:
    ret

notepad_scroll_line_down_no_draw:
    push ax
    call notepad_get_max_scroll
    cmp [note_scroll_row], ax
    jae .done
    inc word [note_scroll_row]
.done:
    pop ax
    ret

notepad_scroll_line_up:
    call notepad_scroll_line_up_no_draw
    call redraw_all
    ret

notepad_scroll_line_down:
    call notepad_scroll_line_down_no_draw
    call redraw_all
    ret

notepad_scroll_page_up:
    push ax
    call note_compute_layout
    mov ax, [note_scroll_row]
    cmp ax, [note_rows_dyn]
    jae .subtract
    xor ax, ax
    jmp .store
.subtract:
    sub ax, [note_rows_dyn]
.store:
    mov [note_scroll_row], ax
    pop ax
    call redraw_all
    ret

notepad_scroll_page_down:
    push ax
    push bx
    call note_compute_layout
    call notepad_get_max_scroll
    mov bx, [note_scroll_row]
    add bx, [note_rows_dyn]
    cmp bx, ax
    jbe .store
    mov bx, ax
.store:
    mov [note_scroll_row], bx
    pop bx
    pop ax
    call redraw_all
    ret

notepad_selection_bounds:
    ; Returns AX=start and DX=end (exclusive). Equal when there is no selection.
    mov ax, [note_cursor]
    mov dx, ax
    cmp byte [note_sel_active], 0
    je .done
    mov dx, [note_anchor]
    cmp ax, dx
    jbe .ordered
    xchg ax, dx
.ordered:
.done:
    ret

notepad_index_to_rowcol:
    ; AX=index -> BX=absolute visual row, CX=column.
    push ax
    push dx
    push si
    push fs
    call note_compute_layout
    mov dx, ax
    mov al, [active_pid]
    cmp al, [note_cache_pos_pid]
    jne .scan_setup
    cmp dx, [note_cache_pos_index]
    jne .scan_setup
    mov ax, [note_len]
    cmp ax, [note_cache_pos_len]
    jne .scan_setup
    mov ax, [note_cols_dyn]
    cmp ax, [note_cache_pos_cols]
    jne .scan_setup
    mov bx, [note_cache_pos_row]
    mov cx, [note_cache_pos_col]
    jmp .return
.scan_setup:
    mov ax, [active_data_seg]
    mov fs, ax
    xor si, si
    xor bx, bx
    xor cx, cx
.loop:
    cmp si, dx
    jae .done
    cmp si, [note_len]
    jae .done
    mov al, fs:[si]
    inc si
    cmp al, 13
    je .newline
    inc cx
    cmp cx, [note_cols_dyn]
    jb .loop
.newline:
    xor cx, cx
    inc bx
    jmp .loop
.done:
    mov [note_cache_pos_index], dx
    mov [note_cache_pos_row], bx
    mov [note_cache_pos_col], cx
    mov al, [active_pid]
    mov [note_cache_pos_pid], al
    mov ax, [note_len]
    mov [note_cache_pos_len], ax
    mov ax, [note_cols_dyn]
    mov [note_cache_pos_cols], ax
.return:
    pop fs
    pop si
    pop dx
    pop ax
    ret

notepad_rowcol_to_index:
    ; BX=absolute visual row, CX=column -> AX=nearest buffer index.
    push bx
    push cx
    push dx
    push si
    push fs
    call note_compute_layout
    mov [note_target_row], bx
    mov [note_target_col], cx
    mov ax, [active_data_seg]
    mov fs, ax
    xor si, si
    xor bx, bx
    xor cx, cx
.scan:
    cmp bx, [note_target_row]
    jb .advance
    cmp bx, [note_target_row]
    ja .return
    cmp cx, [note_target_col]
    jae .return
    cmp si, [note_len]
    jae .return
    cmp byte fs:[si], 13
    je .return
.advance:
    cmp si, [note_len]
    jae .return
    mov dl, fs:[si]
    inc si
    cmp dl, 13
    je .newline
    inc cx
    cmp cx, [note_cols_dyn]
    jb .scan
.newline:
    xor cx, cx
    inc bx
    jmp .scan
.return:
    mov ax, si
    pop fs
    pop si
    pop dx
    pop cx
    pop bx
    ret

notepad_ensure_cursor_visible:
    push ax
    push bx
    push cx
    call note_compute_layout
    mov ax, [note_cursor]
    call notepad_index_to_rowcol
    cmp bx, [note_scroll_row]
    jae .check_bottom
    mov [note_scroll_row], bx
    jmp .done
.check_bottom:
    mov ax, [note_scroll_row]
    add ax, [note_rows_dyn]
    cmp bx, ax
    jb .done
    mov ax, bx
    sub ax, [note_rows_dyn]
    inc ax
    mov [note_scroll_row], ax
.done:
    call notepad_get_max_scroll
    cmp [note_scroll_row], ax
    jbe .clamped
    mov [note_scroll_row], ax
.clamped:
    pop cx
    pop bx
    pop ax
    ret

notepad_mouse_to_index:
    ; Current mouse point -> AX index, CF=1 when in text area.
    call note_compute_layout
    mov cx, [note_text_x_dyn]
    mov dx, [note_text_y_dyn]
    mov si, [note_view_w_dyn]
    mov di, [note_text_h_dyn]
    call hit_rect
    jnc .outside
    mov ax, [mouse_y]
    sub ax, [note_text_y_dyn]
    sub ax, 5
    jnc .row_nonneg
    xor ax, ax
.row_nonneg:
    xor dx, dx
    mov bx, 8
    div bx
    mov bx, [note_rows_dyn]
    dec bx
    cmp ax, bx
    jbe .row_ok
    mov ax, bx
.row_ok:
    add ax, [note_scroll_row]
    mov bx, ax
    mov ax, [mouse_x]
    sub ax, [note_text_x_dyn]
    sub ax, 5
    jnc .col_nonneg
    xor ax, ax
.col_nonneg:
    xor dx, dx
    mov cx, 8
    div cx
    cmp ax, [note_cols_dyn]
    jbe .col_ok
    mov ax, [note_cols_dyn]
.col_ok:
    mov cx, ax
    call notepad_rowcol_to_index
    stc
    ret
.outside:
    clc
    ret

draw_calc_window:
    mov ax, [calc_x]
    mov bx, [calc_y]
    mov cx, [calc_w]
    mov dx, [calc_h]
    call draw_bevel_box
    call draw_frame_black

    mov ax, [calc_x]
    add ax, 3
    mov bx, [calc_y]
    add bx, 3
    mov cx, [calc_w]
    sub cx, 6
    mov dx, TITLE_H
    mov si, COL_DARKGRAY
    push ax
    mov al, [foreground_window]
    cmp al, [active_pid]
    pop ax
    jne .title_ready
    mov si, COL_BLUE
.title_ready:
    call fill_rect
    mov si, str_calc_title
    mov cx, [calc_x]
    add cx, 27
    mov dx, [calc_y]
    add dx, 8
    mov bl, COL_WHITE
    call draw_text

    mov ax, [calc_x]
    add ax, 4
    mov bx, [calc_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    call draw_system_button

    mov ax, [calc_x]
    add ax, [calc_w]
    sub ax, 59
    mov bx, [calc_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_min
    call draw_button

    mov ax, [calc_x]
    add ax, [calc_w]
    sub ax, 40
    mov bx, [calc_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    cmp byte [calc_maximized], 0
    je .max_symbol
    mov si, str_restore
    jmp .draw_max
.max_symbol:
    mov si, str_max
.draw_max:
    call draw_button

    mov ax, [calc_x]
    add ax, [calc_w]
    sub ax, 21
    mov bx, [calc_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_close
    call draw_button
    call draw_calc_menu_bar
    call calc_compute_layout

    mov ax, [calc_display_x]
    mov bx, [calc_display_y]
    mov cx, [calc_display_w]
    mov dx, 20
    mov si, COL_WHITE
    call fill_rect
    call draw_frame_black
    call calc_format_display
    mov si, calc_display_buf
    call strlen_z
    mov ax, cx
    shl ax, 3
    mov cx, [calc_display_x]
    add cx, [calc_display_w]
    sub cx, 5
    sub cx, ax
    mov dx, [calc_display_y]
    add dx, 6
    mov bl, COL_BLACK
    mov si, calc_display_buf
    call draw_text

    mov word [calc_key_index], 0
.key_loop:
    cmp word [calc_key_index], 20
    jae .keys_done
    call calc_get_key_rect
    mov si, [calc_key_index]
    shl si, 1
    mov si, [calc_key_labels_early+si]
    call draw_button
    inc word [calc_key_index]
    jmp .key_loop
.keys_done:
    cmp byte [calc_maximized], 0
    jne .done
    mov ax, [calc_x]
    mov bx, [calc_y]
    mov cx, [calc_w]
    mov dx, [calc_h]
    call draw_resize_grip
.done:
    ret

calc_compute_layout:
    push ax
    push bx
    push dx
    mov ax, [calc_x]
    add ax, 9
    mov [calc_display_x], ax
    mov ax, [calc_y]
    add ax, 39
    mov [calc_display_y], ax
    mov ax, [calc_w]
    sub ax, 18
    cmp ax, 32
    jae .display_ok
    mov ax, 32
.display_ok:
    mov [calc_display_w], ax
    mov ax, [calc_x]
    add ax, 10
    mov [calc_key_left], ax
    mov ax, [calc_y]
    add ax, 64
    mov [calc_key_top], ax
    mov ax, [calc_w]
    sub ax, 32                 ; 20 px side margins + three 4 px gaps
    xor dx, dx
    mov bx, 4
    div bx
    cmp ax, 18
    jae .key_w_ok
    mov ax, 18
.key_w_ok:
    mov [calc_key_w], ax
    add ax, 4
    mov [calc_key_step_x], ax
    mov ax, [calc_h]
    sub ax, 85                 ; top 64, bottom 9 and four 3 px gaps
    xor dx, dx
    mov bx, 5
    div bx
    cmp ax, 12
    jae .key_h_ok
    mov ax, 12
.key_h_ok:
    mov [calc_key_h], ax
    add ax, 3
    mov [calc_key_step_y], ax
    pop dx
    pop bx
    pop ax
    ret

calc_get_key_rect:
    ; Return the current key rectangle relative to the current Calculator
    ; window.  The key index is read from calc_key_index (0..19).
    push si
    push di
    push bp
    mov bp, [calc_key_index]

    mov ax, bp
    and ax, 3
    mul word [calc_key_step_x]
    add ax, [calc_key_left]
    mov di, ax

    mov ax, bp
    shr ax, 2
    mul word [calc_key_step_y]
    add ax, [calc_key_top]
    mov bx, ax

    mov ax, di
    mov cx, [calc_key_w]
    mov dx, [calc_key_h]
    pop bp
    pop di
    pop si
    ret

draw_calc_menu_bar:
    mov ax, [calc_x]
    add ax, 3
    mov bx, [calc_y]
    add bx, 22
    mov cx, [calc_w]
    sub cx, 6
    mov dx, MENU_H
    mov si, COL_GRAY
    call fill_rect
    mov ax, [calc_x]
    add ax, 3
    mov bx, [calc_y]
    add bx, 35
    mov cx, [calc_w]
    sub cx, 6
    mov dl, COL_DARKGRAY
    call hline
    mov si, str_menu_file
    mov cx, [calc_x]
    add cx, 7
    mov dx, [calc_y]
    add dx, 25
    mov bl, COL_BLACK
    call draw_text
    mov si, str_menu_help
    mov cx, [calc_x]
    add cx, 55
    mov dx, [calc_y]
    add dx, 25
    mov bl, COL_BLACK
    call draw_text
    ret

draw_rainbow_swatch:
    ; AX=x, BX=y, draw a square icon containing all seven rainbow colors.
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov [rainbow_icon_x], ax
    mov [rainbow_icon_y], bx
    xor di, di
.loop:
    cmp di, 7
    jae .done
    mov ax, [rainbow_icon_x]
    mov bx, [rainbow_icon_y]
    xor cx, cx
    mov cl, [rainbow_offsets+di]
    add bx, cx
    mov cx, 12
    xor dx, dx
    mov dl, [rainbow_heights+di]
    xor si, si
    mov si, di
    mov al, [rainbow_colors+si]
    xor ah, ah
    mov si, ax
    mov ax, [rainbow_icon_x]
    call fill_rect
    inc di
    jmp .loop
.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_palette:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    xor di, di
.loop:
    cmp di, 8
    jae .custom
    mov ax, di
    mov cx, 15
    mul cx
    add ax, [paint_x]
    add ax, 60
    mov [palette_draw_x], ax
    mov bx, [paint_y]
    add bx, 41
    mov [palette_draw_y], bx
    cmp di, 7
    je .rainbow
    mov si, palette_colors
    add si, di
    xor dx, dx
    mov dl, [si]
    mov si, dx
    mov ax, [palette_draw_x]
    mov bx, [palette_draw_y]
    mov cx, 12
    mov dx, 12
    call fill_rect
    jmp .frame
.rainbow:
    mov ax, [palette_draw_x]
    mov bx, [palette_draw_y]
    call draw_rainbow_swatch
.frame:
    mov ax, [palette_draw_x]
    mov bx, [palette_draw_y]
    mov cx, 12
    mov dx, 12
    call draw_frame_black
    cmp di, 7
    jne .normal_select
    cmp byte [paint_rainbow], 0
    je .next
    jmp .selected
.normal_select:
    cmp byte [paint_rainbow], 0
    jne .next
    mov si, palette_colors
    add si, di
    mov al, [si]
    cmp al, [paint_color]
    jne .next
.selected:
    mov ax, [palette_draw_x]
    sub ax, 2
    mov bx, [palette_draw_y]
    sub bx, 2
    mov cx, 16
    mov dx, 16
    call draw_frame_black
.next:
    inc di
    jmp .loop

.custom:
    call paint_compute_palette_controls
    mov ax, [paint_custom_x]
    mov [paint_present_x], ax
    mov bx, [paint_y]
    add bx, 41
    mov cx, 12
    mov dx, 12
    xor ax, ax
    mov al, [paint_custom_color]
    mov si, ax
    mov ax, [paint_present_x]
    call fill_rect
    call draw_frame_black
    cmp byte [paint_custom_active], 0
    je .buttons
    cmp byte [paint_rainbow], 0
    jne .buttons
    mov ax, [paint_custom_x]
    sub ax, 2
    mov bx, [paint_y]
    add bx, 39
    mov cx, 16
    mov dx, 16
    call draw_frame_black

.buttons:
    mov ax, [paint_rgb_button_x]
    mov bx, [paint_y]
    add bx, 39
    mov cx, 38
    mov dx, 18
    mov si, str_palette
    cmp byte [captured_button], BTN_PAINT_PALETTE
    jne .rgb_button_normal
    push ax                         ; comparing process IDs uses AL
    mov al, [captured_pid]
    cmp al, [active_pid]
    pop ax                          ; restore the real absolute button X
    jne .rgb_button_normal
    cmp byte [capture_inside], 0
    je .rgb_button_normal
    call draw_button_pressed
    jmp .rgb_button_done
.rgb_button_normal:
    call draw_button
.rgb_button_done:
    cmp byte [paint_palette_open], 0
    je .clear
    mov ax, [paint_rgb_button_x]
    sub ax, 2
    mov bx, [paint_y]
    add bx, 37
    mov cx, 42
    mov dx, 22
    call draw_frame_black
.clear:
    mov ax, [paint_clear_button_x]
    mov bx, [paint_y]
    add bx, 39
    mov cx, 52
    mov dx, 18
    mov si, str_clear
    call draw_button
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

paint_compute_palette_controls:
    mov ax, [paint_x]
    add ax, [paint_w]
    sub ax, 120
    mov [paint_custom_x], ax
    add ax, 18
    mov [paint_rgb_button_x], ax
    add ax, 42
    mov [paint_clear_button_x], ax
    ret

paint_wheel_color_at:
    ; DI=x and BP=y in a 64x64 color wheel. Return AL=VGA palette index,
    ; or FFh outside the circle. Colors are generated at runtime to keep the
    ; boot image inside the single real-mode code segment.
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    mov ax, di
    sub ax, 31
    mov bx, ax
    imul bx
    mov cx, ax
    mov ax, bp
    sub ax, 31
    mov bx, ax
    imul bx
    add cx, ax
    cmp cx, 961
    ja .outside

    ; Red varies left-to-right, green top-to-bottom, and blue on the opposite
    ; diagonal. The 6x6x6 cube gives a continuous-looking classic VGA wheel.
    mov ax, di
    mov bx, 6
    mul bx
    shr ax, 6
    mov bx, 36
    mul bx
    mov si, ax

    mov ax, bp
    mov bx, 6
    mul bx
    shr ax, 6
    mov bx, 6
    mul bx
    add si, ax

    mov ax, 63
    sub ax, di
    add ax, bp
    mov bx, 6
    mul bx
    shr ax, 7
    cmp ax, 5
    jbe .blue_ready
    mov ax, 5
.blue_ready:
    add si, ax
    add si, 16
    mov ax, si
    jmp .done
.outside:
    mov al, 0xFF
.done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    ret

draw_color_wheel:
    push ax
    push bx
    push cx
    push dx
    push di
    push bp
    xor bp, bp
.row:
    cmp bp, 64
    jae .done
    xor di, di
.col:
    cmp di, 64
    jae .next_row
    call paint_wheel_color_at
    cmp al, 0xFF
    je .skip
    mov cx, [paint_wheel_x]
    add cx, di
    mov dx, [paint_wheel_y]
    add dx, bp
    call putpixel
.skip:
    inc di
    jmp .col
.next_row:
    inc bp
    jmp .row
.done:
    pop bp
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

byte_to_dec_buf:
    ; AL -> zero-terminated decimal string at rgb_value_buf.
    push ax
    push bx
    push dx
    push di
    xor ah, ah
    mov di, rgb_value_buf
    mov bx, 100
    xor dx, dx
    div bx
    test ax, ax
    jz .tens
    add al, '0'
    stosb
    mov ax, dx
    mov bx, 10
    xor dx, dx
    div bx
    add al, '0'
    stosb
    mov al, dl
    add al, '0'
    stosb
    jmp .term
.tens:
    mov ax, dx
    mov bx, 10
    xor dx, dx
    div bx
    test ax, ax
    jz .ones
    add al, '0'
    stosb
.ones:
    mov al, dl
    add al, '0'
    stosb
.term:
    xor al, al
    stosb
    pop di
    pop dx
    pop bx
    pop ax
    ret

draw_paint_palette_dialog:
    push ax
    push bx
    push cx
    push dx
    push si
    cmp byte [paint_palette_positioned], 0
    jne .position_ready
    mov ax, [paint_x]
    add ax, [paint_w]
    sub ax, 217
    cmp ax, [paint_x]
    jae .x_ok
    mov ax, [paint_x]
    add ax, 3
.x_ok:
    mov [paint_palette_x], ax
    mov bx, [paint_y]
    add bx, 37
    mov [paint_palette_y], bx
    mov byte [paint_palette_positioned], 1
.position_ready:
    mov ax, [paint_palette_x]
    mov bx, [paint_palette_y]
    mov cx, 210
    mov dx, 122
    call draw_bevel_box
    call draw_frame_black

    mov ax, [paint_palette_x]
    add ax, 3
    mov bx, [paint_palette_y]
    add bx, 3
    mov cx, 204
    mov dx, 16
    mov si, COL_BLUE
    call fill_rect
    mov si, str_rgb_palette
    mov cx, [paint_palette_x]
    add cx, 7
    mov dx, [paint_palette_y]
    add dx, 7
    mov bl, COL_WHITE
    call draw_text
    mov ax, [paint_palette_x]
    add ax, 190
    mov bx, [paint_palette_y]
    add bx, 4
    mov cx, 16
    mov dx, 14
    mov si, str_close
    cmp byte [captured_button], BTN_PALETTE_CLOSE
    jne .close_button_normal
    push ax                         ; do not destroy the button X via AL
    mov al, [captured_pid]
    cmp al, [active_pid]
    pop ax
    jne .close_button_normal
    cmp byte [capture_inside], 0
    je .close_button_normal
    call draw_button_pressed
    jmp .close_button_done
.close_button_normal:
    call draw_button
.close_button_done:

    mov ax, [paint_palette_x]
    add ax, 8
    mov [paint_wheel_x], ax
    mov ax, [paint_palette_y]
    add ax, 23
    mov [paint_wheel_y], ax
    call draw_color_wheel

    mov si, str_r
    mov cx, [paint_palette_x]
    add cx, 82
    mov dx, [paint_palette_y]
    add dx, 29
    mov bl, COL_BLACK
    call draw_text
    mov si, str_g
    mov cx, [paint_palette_x]
    add cx, 82
    mov dx, [paint_palette_y]
    add dx, 53
    mov bl, COL_BLACK
    call draw_text
    mov si, str_b
    mov cx, [paint_palette_x]
    add cx, 82
    mov dx, [paint_palette_y]
    add dx, 77
    mov bl, COL_BLACK
    call draw_text

    mov ax, [paint_palette_x]
    add ax, 102
    mov bx, [paint_palette_y]
    add bx, 25
    mov cx, 48
    mov dx, 16
    mov si, COL_WHITE
    call fill_rect
    call draw_frame_black
    mov al, [paint_rgb_r]
    call byte_to_dec_buf
    mov si, rgb_value_buf
    mov cx, [paint_palette_x]
    add cx, 108
    mov dx, [paint_palette_y]
    add dx, 29
    mov bl, COL_BLACK
    call draw_text
    cmp byte [paint_rgb_focus], 1
    jne .g_box
    mov ax, [paint_palette_x]
    add ax, 100
    mov bx, [paint_palette_y]
    add bx, 23
    mov cx, 52
    mov dx, 20
    call draw_frame_black
.g_box:
    mov ax, [paint_palette_x]
    add ax, 102
    mov bx, [paint_palette_y]
    add bx, 49
    mov cx, 48
    mov dx, 16
    mov si, COL_WHITE
    call fill_rect
    call draw_frame_black
    mov al, [paint_rgb_g]
    call byte_to_dec_buf
    mov si, rgb_value_buf
    mov cx, [paint_palette_x]
    add cx, 108
    mov dx, [paint_palette_y]
    add dx, 53
    mov bl, COL_BLACK
    call draw_text
    cmp byte [paint_rgb_focus], 2
    jne .b_box
    mov ax, [paint_palette_x]
    add ax, 100
    mov bx, [paint_palette_y]
    add bx, 47
    mov cx, 52
    mov dx, 20
    call draw_frame_black
.b_box:
    mov ax, [paint_palette_x]
    add ax, 102
    mov bx, [paint_palette_y]
    add bx, 73
    mov cx, 48
    mov dx, 16
    mov si, COL_WHITE
    call fill_rect
    call draw_frame_black
    mov al, [paint_rgb_b]
    call byte_to_dec_buf
    mov si, rgb_value_buf
    mov cx, [paint_palette_x]
    add cx, 108
    mov dx, [paint_palette_y]
    add dx, 77
    mov bl, COL_BLACK
    call draw_text
    cmp byte [paint_rgb_focus], 3
    jne .swatch
    mov ax, [paint_palette_x]
    add ax, 100
    mov bx, [paint_palette_y]
    add bx, 71
    mov cx, 52
    mov dx, 20
    call draw_frame_black
.swatch:
    ; Fixed preview in the dialog's upper-right blank area.
    mov ax, [paint_palette_x]
    add ax, 163
    mov [paint_present_x], ax
    mov bx, [paint_palette_y]
    add bx, 25
    mov cx, 34
    mov dx, 38
    xor ax, ax
    mov al, [paint_color]
    mov si, ax
    mov ax, [paint_present_x]
    call fill_rect
    call draw_frame_black
    mov si, str_rgb_hint
    mov cx, [paint_palette_x]
    add cx, 82
    mov dx, [paint_palette_y]
    add dx, 99
    mov bl, COL_DARKGRAY
    call draw_text
    mov ax, [paint_palette_x]
    add ax, 154
    mov bx, [paint_palette_y]
    add bx, 94
    mov cx, 42
    mov dx, 19
    mov si, str_ok
    cmp byte [captured_button], BTN_PALETTE_OK
    jne .ok_button_normal
    push ax                         ; do not destroy the button X via AL
    mov al, [captured_pid]
    cmp al, [active_pid]
    pop ax
    jne .ok_button_normal
    cmp byte [capture_inside], 0
    je .ok_button_normal
    call draw_button_pressed
    jmp .ok_button_done
.ok_button_normal:
    call draw_button
.ok_button_done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_paint_status:
    mov si, str_status_pencil
    mov al, [paint_tool]
    cmp al, PAINT_TOOL_FILL
    je .fill
    cmp al, PAINT_TOOL_TEXT
    je .text
    cmp al, PAINT_TOOL_ERASER
    je .eraser
    cmp al, PAINT_TOOL_EYEDROP
    je .eyedrop
    cmp al, PAINT_TOOL_LINE
    je .line
    cmp al, PAINT_TOOL_RECT
    je .rect
    cmp al, PAINT_TOOL_ELLIPSE
    je .ellipse
    cmp al, PAINT_TOOL_SELECT
    je .select
    cmp al, PAINT_TOOL_MAGNIFY
    je .magnify
    cmp byte [paint_rainbow], 0
    je .tool_ready
    mov si, str_status_rainbow
    jmp .tool_ready
.fill:
    mov si, str_status_fill
    jmp .tool_ready
.text:
    mov si, str_status_text
    jmp .tool_ready
.eraser:
    mov si, str_status_eraser
    jmp .tool_ready
.eyedrop:
    mov si, str_status_eyedrop
    jmp .tool_ready
.line:
    mov si, str_status_line
    jmp .tool_ready
.rect:
    mov si, str_status_rect
    jmp .tool_ready
.ellipse:
    mov si, str_status_ellipse
    jmp .tool_ready
.select:
    mov si, str_status_select
    jmp .tool_ready
.magnify:
    mov si, str_status_magnify
.tool_ready:
    mov cx, [paint_x]
    add cx, 60
    mov dx, [paint_y]
    add dx, [paint_h]
    sub dx, 11
    mov bl, COL_DARKGRAY
    call draw_text

    mov si, str_brush_1
    cmp byte [paint_tool], PAINT_TOOL_TEXT
    jne .brush
    mov si, str_text_1x
    cmp byte [paint_text_size], 1
    je .size_ready
    mov si, str_text_2x
    cmp byte [paint_text_size], 2
    je .size_ready
    mov si, str_text_3x
    jmp .size_ready
.brush:
    cmp byte [paint_brush_size], 1
    je .size_ready
    mov si, str_brush_2
    cmp byte [paint_brush_size], 2
    je .size_ready
    mov si, str_brush_4
.size_ready:
    mov cx, [paint_x]
    add cx, 150
    mov dx, [paint_y]
    add dx, [paint_h]
    sub dx, 11
    mov bl, COL_DARKGRAY
    call draw_text
    ret

draw_canvas_to_screen:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push es
    push fs
    call paint_clamp_scroll
    mov ax, [active_data_seg]
    mov fs, ax
    mov ax, [draw_seg]
    mov es, ax
    xor bp, bp
.row:
    cmp bp, [paint_canvas_screen_h]
    jae .copied
    mov ax, bp
    xor dx, dx
    xor cx, cx
    mov cl, [paint_zoom]
    div cx
    add ax, [paint_scroll_y]
    mov [paint_src_y_tmp], ax
    mov bx, [paint_canvas_screen_y]
    add bx, bp
    mov di, bx
    mov ax, bx
    shl di, 6
    shl ax, 8
    add di, ax
    add di, [paint_canvas_screen_x]
    xor bx, bx
.col:
    cmp bx, [paint_canvas_screen_w]
    jae .next_row
    mov ax, bx
    xor dx, dx
    xor cx, cx
    mov cl, [paint_zoom]
    div cx
    add ax, [paint_scroll_x]
    mov [paint_src_x_tmp], ax
    cmp ax, [paint_canvas_w]
    jae .white
    mov ax, [paint_src_y_tmp]
    cmp ax, [paint_canvas_h]
    jae .white
    mov cx, PAINT_CANVAS_STRIDE
    mul cx
    add ax, [paint_src_x_tmp]
    mov si, ax
    mov al, fs:[si]
    jmp .store
.white:
    mov al, COL_WHITE
.store:
    mov es:[di], al
    inc di
    inc bx
    jmp .col
.next_row:
    inc bp
    jmp .row
.copied:
    pop fs
    pop es
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    cmp byte [paint_zoom], 1
    jne .selection
    call draw_paint_text_objects
.selection:
    call draw_paint_selection
    ret

paint_compute_scroll_limits:
    ; Convert the screen viewport to canvas-pixel units and derive the last
    ; useful scroll origin. Ceil division prevents a partial zoomed pixel at
    ; the right/bottom edge from creating an unnecessary blank strip.
    push ax
    push bx
    push dx
    call paint_compute_canvas_rect
    xor bx, bx
    mov bl, [paint_zoom]
    cmp bx, 1
    jae .zoom_ready
    mov bx, 1
.zoom_ready:
    mov ax, [paint_view_w]
    add ax, bx
    dec ax
    xor dx, dx
    div bx
    cmp ax, [paint_canvas_w]
    jbe .cols_ready
    mov ax, [paint_canvas_w]
.cols_ready:
    mov [paint_visible_cols], ax
    mov dx, [paint_canvas_w]
    sub dx, ax
    mov [paint_scroll_max_x], dx

    mov ax, [paint_view_h]
    add ax, bx
    dec ax
    xor dx, dx
    div bx
    cmp ax, [paint_canvas_h]
    jbe .rows_ready
    mov ax, [paint_canvas_h]
.rows_ready:
    mov [paint_visible_rows], ax
    mov dx, [paint_canvas_h]
    sub dx, ax
    mov [paint_scroll_max_y], dx
    pop dx
    pop bx
    pop ax
    ret

paint_clamp_scroll:
    push ax
    call paint_compute_scroll_limits
    cmp byte [paint_zoom], 1
    ja .clamp
    mov word [paint_scroll_x], 0
    mov word [paint_scroll_y], 0
    jmp .done
.clamp:
    mov ax, [paint_scroll_max_x]
    cmp [paint_scroll_x], ax
    jbe .y
    mov [paint_scroll_x], ax
.y:
    mov ax, [paint_scroll_max_y]
    cmp [paint_scroll_y], ax
    jbe .done
    mov [paint_scroll_y], ax
.done:
    pop ax
    ret

paint_compute_scroll_metrics:
    ; Compute proportional thumb geometry shared by drawing, hit testing and
    ; dragging. All positions are inside the one-pixel scrollbar frames.
    push ax
    push bx
    push cx
    push dx
    call paint_clamp_scroll

    mov ax, [paint_canvas_screen_x]
    inc ax
    mov [paint_htrack_x], ax
    mov ax, [paint_canvas_screen_y]
    add ax, [paint_canvas_screen_h]
    inc ax
    mov [paint_htrack_y], ax
    mov ax, [paint_canvas_screen_w]
    sub ax, 2
    mov [paint_htrack_len], ax

    mov ax, [paint_canvas_screen_x]
    add ax, [paint_canvas_screen_w]
    inc ax
    mov [paint_vtrack_x], ax
    mov ax, [paint_canvas_screen_y]
    inc ax
    mov [paint_vtrack_y], ax
    mov ax, [paint_canvas_screen_h]
    sub ax, 2
    mov [paint_vtrack_len], ax

    mov ax, [paint_htrack_len]
    mul word [paint_visible_cols]
    mov bx, [paint_canvas_w]
    test bx, bx
    jnz .h_divide
    mov bx, 1
.h_divide:
    div bx
    cmp ax, 12
    jae .h_min_ready
    mov ax, 12
.h_min_ready:
    cmp ax, [paint_htrack_len]
    jbe .h_size_ready
    mov ax, [paint_htrack_len]
.h_size_ready:
    mov [paint_hthumb_w], ax
    mov bx, [paint_htrack_len]
    sub bx, ax
    mov [paint_hthumb_range], bx
    xor cx, cx
    mov ax, [paint_scroll_max_x]
    test ax, ax
    jz .h_position_ready
    mov ax, [paint_scroll_x]
    mul bx
    div word [paint_scroll_max_x]
    mov cx, ax
.h_position_ready:
    mov ax, [paint_htrack_x]
    add ax, cx
    mov [paint_hthumb_x], ax
    mov ax, [paint_htrack_y]
    mov [paint_hthumb_y], ax

    mov ax, [paint_vtrack_len]
    mul word [paint_visible_rows]
    mov bx, [paint_canvas_h]
    test bx, bx
    jnz .v_divide
    mov bx, 1
.v_divide:
    div bx
    cmp ax, 12
    jae .v_min_ready
    mov ax, 12
.v_min_ready:
    cmp ax, [paint_vtrack_len]
    jbe .v_size_ready
    mov ax, [paint_vtrack_len]
.v_size_ready:
    mov [paint_vthumb_h], ax
    mov bx, [paint_vtrack_len]
    sub bx, ax
    mov [paint_vthumb_range], bx
    xor cx, cx
    mov ax, [paint_scroll_max_y]
    test ax, ax
    jz .v_position_ready
    mov ax, [paint_scroll_y]
    mul bx
    div word [paint_scroll_max_y]
    mov cx, ax
.v_position_ready:
    mov ax, [paint_vtrack_x]
    mov [paint_vthumb_x], ax
    mov ax, [paint_vtrack_y]
    add ax, cx
    mov [paint_vthumb_y], ax
    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_paint_scrollbars:
    cmp byte [paint_zoom], 1
    jbe .done
    push ax
    push bx
    push cx
    push dx
    push si
    call paint_compute_scroll_metrics
    mov ax, [paint_canvas_screen_x]
    add ax, [paint_canvas_screen_w]
    mov bx, [paint_canvas_screen_y]
    mov cx, 11
    mov dx, [paint_canvas_screen_h]
    mov si, COL_GRAY
    call fill_rect
    call draw_frame_black
    mov ax, [paint_canvas_screen_x]
    mov bx, [paint_canvas_screen_y]
    add bx, [paint_canvas_screen_h]
    mov cx, [paint_canvas_screen_w]
    mov dx, 11
    mov si, COL_GRAY
    call fill_rect
    call draw_frame_black

    mov ax, [paint_hthumb_x]
    mov bx, [paint_hthumb_y]
    mov cx, [paint_hthumb_w]
    mov dx, 9
    call draw_bevel_box
    mov ax, [paint_vthumb_x]
    mov bx, [paint_vthumb_y]
    mov cx, 9
    mov dx, [paint_vthumb_h]
    call draw_bevel_box
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
.done:
    ret

paint_try_scrollbar_click:
    ; CF=1 when either Paint scrollbar captured the pointer. Pressing the
    ; track also starts a centered thumb drag, so both bars respond even when
    ; their proportional thumb is small.
    cmp byte [paint_zoom], 1
    jbe .no
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    call paint_compute_scroll_metrics

    mov cx, [paint_canvas_screen_x]
    mov dx, [paint_canvas_screen_y]
    add dx, [paint_canvas_screen_h]
    mov si, [paint_canvas_screen_w]
    mov di, 11
    call hit_rect
    jc .horizontal
    mov cx, [paint_canvas_screen_x]
    add cx, [paint_canvas_screen_w]
    mov dx, [paint_canvas_screen_y]
    mov si, 11
    mov di, [paint_canvas_screen_h]
    call hit_rect
    jc .vertical
    jmp .restore_no

.horizontal:
    mov byte [drag_mode], 9
    mov al, [active_pid]
    mov [drag_pid], al
    mov ax, [mouse_x]
    cmp ax, [paint_hthumb_x]
    jb .h_center
    mov bx, [paint_hthumb_x]
    add bx, [paint_hthumb_w]
    cmp ax, bx
    jae .h_center
    sub ax, [paint_hthumb_x]
    jmp .h_offset_ready
.h_center:
    mov ax, [paint_hthumb_w]
    shr ax, 1
.h_offset_ready:
    mov [paint_scroll_drag_offset], ax
    call update_paint_hscroll_drag
    jmp .restore_yes

.vertical:
    mov byte [drag_mode], 10
    mov al, [active_pid]
    mov [drag_pid], al
    mov ax, [mouse_y]
    cmp ax, [paint_vthumb_y]
    jb .v_center
    mov bx, [paint_vthumb_y]
    add bx, [paint_vthumb_h]
    cmp ax, bx
    jae .v_center
    sub ax, [paint_vthumb_y]
    jmp .v_offset_ready
.v_center:
    mov ax, [paint_vthumb_h]
    shr ax, 1
.v_offset_ready:
    mov [paint_scroll_drag_offset], ax
    call update_paint_vscroll_drag
.restore_yes:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    stc
    ret
.restore_no:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
.no:
    clc
    ret

draw_paint_selection:
    cmp byte [paint_select_active], 0
    je .done
    cmp byte [paint_tool], PAINT_TOOL_SELECT
    jne .done
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    call paint_compute_scroll_limits

    ; Intersect the selection with the current canvas viewport in canvas
    ; coordinates first. This avoids unsigned underflow when its top-left is
    ; above/left of the scrolled viewport and prevents frame drawing from
    ; escaping the Paint window after Ctrl+wheel zoom.
    mov ax, [paint_select_x]
    cmp ax, [paint_scroll_x]
    jae .clip_left_ready
    mov ax, [paint_scroll_x]
.clip_left_ready:
    mov [paint_select_clip_x], ax
    mov dx, [paint_select_x]
    add dx, [paint_select_w]
    mov cx, [paint_scroll_x]
    add cx, [paint_visible_cols]
    cmp dx, cx
    jbe .clip_right_ready
    mov dx, cx
.clip_right_ready:
    cmp dx, ax
    jbe .restore
    mov [paint_select_clip_r], dx

    mov ax, [paint_select_y]
    cmp ax, [paint_scroll_y]
    jae .clip_top_ready
    mov ax, [paint_scroll_y]
.clip_top_ready:
    mov [paint_select_clip_y], ax
    mov dx, [paint_select_y]
    add dx, [paint_select_h]
    mov cx, [paint_scroll_y]
    add cx, [paint_visible_rows]
    cmp dx, cx
    jbe .clip_bottom_ready
    mov dx, cx
.clip_bottom_ready:
    cmp dx, ax
    jbe .restore
    mov [paint_select_clip_b], dx

    xor bx, bx
    mov bl, [paint_zoom]
    mov ax, [paint_select_clip_x]
    sub ax, [paint_scroll_x]
    mul bx
    add ax, [paint_canvas_screen_x]
    mov [paint_select_screen_x], ax
    mov ax, [paint_select_clip_y]
    sub ax, [paint_scroll_y]
    mul bx
    add ax, [paint_canvas_screen_y]
    mov [paint_select_screen_y], ax

    mov ax, [paint_select_clip_r]
    sub ax, [paint_select_clip_x]
    mul bx
    mov cx, [paint_canvas_screen_x]
    add cx, [paint_canvas_screen_w]
    sub cx, [paint_select_screen_x]
    cmp ax, cx
    jbe .clip_screen_w_ready
    mov ax, cx
.clip_screen_w_ready:
    mov [paint_select_screen_w], ax
    mov ax, [paint_select_clip_b]
    sub ax, [paint_select_clip_y]
    mul bx
    mov cx, [paint_canvas_screen_y]
    add cx, [paint_canvas_screen_h]
    sub cx, [paint_select_screen_y]
    cmp ax, cx
    jbe .clip_screen_h_ready
    mov ax, cx
.clip_screen_h_ready:
    mov [paint_select_screen_h], ax

    mov ax, [paint_select_w]
    mul bx
    mov [paint_select_full_screen_w], ax
    mov ax, [paint_select_h]
    mul bx
    mov [paint_select_full_screen_h], ax
    mov ax, [paint_select_clip_x]
    sub ax, [paint_select_x]
    mul bx
    mov [paint_preview_off_x], ax
    mov ax, [paint_select_clip_y]
    sub ax, [paint_select_y]
    mul bx
    mov [paint_preview_off_y], ax

    ; Keep the true scaled selection frame separate from the clipped preview.
    ; These coordinates are intentionally signed: after scrolling/zooming an
    ; original edge can lie above or left of the visible canvas viewport.
    mov ax, [paint_select_screen_x]
    sub ax, [paint_preview_off_x]
    mov [paint_select_full_screen_x], ax
    mov dx, ax
    add dx, [paint_select_full_screen_w]
    dec dx
    mov [paint_select_full_screen_r], dx
    mov ax, [paint_select_screen_y]
    sub ax, [paint_preview_off_y]
    mov [paint_select_full_screen_y], ax
    mov dx, ax
    add dx, [paint_select_full_screen_h]
    dec dx
    mov [paint_select_full_screen_b], dx

    cmp word [paint_select_screen_w], 0
    je .restore
    cmp word [paint_select_screen_h], 0
    je .restore
    call draw_paint_selection_preview

    ; Draw each original boundary independently. If an original boundary is
    ; outside the visible canvas, omit it instead of replacing it with a false
    ; boundary at the clipped viewport edge. Perpendicular boundaries may
    ; still have their visible spans clipped safely to the viewport.
    mov ax, [paint_select_full_screen_x]
    mov bx, [paint_select_full_screen_y]
    mov cx, [paint_select_full_screen_r]
    call draw_paint_select_h_edge
    mov ax, [paint_select_full_screen_x]
    mov bx, [paint_select_full_screen_b]
    mov cx, [paint_select_full_screen_r]
    call draw_paint_select_h_edge
    mov ax, [paint_select_full_screen_x]
    mov bx, [paint_select_full_screen_y]
    mov cx, [paint_select_full_screen_b]
    call draw_paint_select_v_edge
    mov ax, [paint_select_full_screen_r]
    mov bx, [paint_select_full_screen_y]
    mov cx, [paint_select_full_screen_b]
    call draw_paint_select_v_edge

    ; Place the eight sizing handles at their true selection coordinates.
    ; A handle whose center is outside the viewport is omitted, so clipping
    ; never invents a replacement handle on the canvas edge.
    mov ax, [paint_select_full_screen_x]
    mov bx, [paint_select_full_screen_y]
    call draw_paint_select_handle_if_visible
    mov ax, [paint_select_full_screen_x]
    mov cx, [paint_select_full_screen_w]
    shr cx, 1
    add ax, cx
    mov bx, [paint_select_full_screen_y]
    call draw_paint_select_handle_if_visible
    mov ax, [paint_select_full_screen_r]
    mov bx, [paint_select_full_screen_y]
    call draw_paint_select_handle_if_visible
    mov ax, [paint_select_full_screen_x]
    mov bx, [paint_select_full_screen_y]
    mov cx, [paint_select_full_screen_h]
    shr cx, 1
    add bx, cx
    call draw_paint_select_handle_if_visible
    mov ax, [paint_select_full_screen_r]
    mov bx, [paint_select_full_screen_y]
    mov cx, [paint_select_full_screen_h]
    shr cx, 1
    add bx, cx
    call draw_paint_select_handle_if_visible
    mov ax, [paint_select_full_screen_x]
    mov bx, [paint_select_full_screen_b]
    call draw_paint_select_handle_if_visible
    mov ax, [paint_select_full_screen_x]
    mov cx, [paint_select_full_screen_w]
    shr cx, 1
    add ax, cx
    mov bx, [paint_select_full_screen_b]
    call draw_paint_select_handle_if_visible
    mov ax, [paint_select_full_screen_r]
    mov bx, [paint_select_full_screen_b]
    call draw_paint_select_handle_if_visible
.restore:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
.done:
    ret

draw_paint_select_h_edge:
    ; AX=unclipped left, BX=true boundary y, CX=unclipped right (inclusive).
    ; Hide the whole edge when its true Y is outside the canvas viewport.
    push ax
    push bx
    push cx
    push dx
    mov dx, [paint_canvas_screen_y]
    cmp bx, dx
    jl .done
    add dx, [paint_canvas_screen_h]
    dec dx
    cmp bx, dx
    jg .done

    mov dx, [paint_canvas_screen_x]
    cmp ax, dx
    jge .left_ready
    mov ax, dx
.left_ready:
    mov dx, [paint_canvas_screen_x]
    add dx, [paint_canvas_screen_w]
    dec dx
    cmp cx, dx
    jle .right_ready
    mov cx, dx
.right_ready:
    cmp cx, ax
    jl .done
    sub cx, ax
    inc cx
    mov dl, COL_BLACK
    call hline
.done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_paint_select_v_edge:
    ; AX=true boundary x, BX=unclipped top, CX=unclipped bottom (inclusive).
    ; Hide the whole edge when its true X is outside the canvas viewport.
    push ax
    push bx
    push cx
    push dx
    mov dx, [paint_canvas_screen_x]
    cmp ax, dx
    jl .done
    add dx, [paint_canvas_screen_w]
    dec dx
    cmp ax, dx
    jg .done

    mov dx, [paint_canvas_screen_y]
    cmp bx, dx
    jge .top_ready
    mov bx, dx
.top_ready:
    mov dx, [paint_canvas_screen_y]
    add dx, [paint_canvas_screen_h]
    dec dx
    cmp cx, dx
    jle .bottom_ready
    mov cx, dx
.bottom_ready:
    cmp cx, bx
    jl .done
    sub cx, bx
    inc cx
    mov dl, COL_BLACK
    call vline
.done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_paint_select_handle_if_visible:
    ; AX/BX=true handle center. Do not move an off-viewport handle onto the
    ; clipped frame; only partially clip a handle whose center is still valid.
    push dx
    mov dx, [paint_canvas_screen_x]
    cmp ax, dx
    jl .done
    add dx, [paint_canvas_screen_w]
    cmp ax, dx
    jge .done
    mov dx, [paint_canvas_screen_y]
    cmp bx, dx
    jl .done
    add dx, [paint_canvas_screen_h]
    cmp bx, dx
    jge .done
    call draw_paint_select_handle
.done:
    pop dx
    ret

draw_paint_select_handle:
    ; Clip a visible-centered 5x5 handle to the canvas viewport. Generic
    ; fill_rect assumes its horizontal span is already valid, so this guard
    ; also prevents handles from corrupting neighboring windows.
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov si, ax
    mov di, bx
    sub ax, 2
    cmp ax, [paint_canvas_screen_x]
    jae .left_ready
    mov ax, [paint_canvas_screen_x]
.left_ready:
    mov cx, si
    add cx, 3
    mov dx, [paint_canvas_screen_x]
    add dx, [paint_canvas_screen_w]
    cmp cx, dx
    jbe .right_ready
    mov cx, dx
.right_ready:
    sub cx, ax
    jbe .handle_done

    sub bx, 2
    cmp bx, [paint_canvas_screen_y]
    jae .top_ready
    mov bx, [paint_canvas_screen_y]
.top_ready:
    mov dx, di
    add dx, 3
    mov si, [paint_canvas_screen_y]
    add si, [paint_canvas_screen_h]
    cmp dx, si
    jbe .bottom_ready
    mov dx, si
.bottom_ready:
    sub dx, bx
    jbe .handle_done
    mov si, COL_BLACK
    call fill_rect
.handle_done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_paint_selection_preview:
    cmp byte [paint_select_drag], 2
    je .draw
    cmp byte [paint_select_drag], 3
    je .draw
    cmp byte [paint_select_pending], 0
    je .done
.draw:
    cmp byte [paint_select_buffer_valid], 0
    je .done
    cmp word [paint_select_full_screen_w], 0
    je .done
    cmp word [paint_select_full_screen_h], 0
    je .done
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push gs
    mov ax, [paint_select_screen_w]
    mov [paint_preview_w], ax
    mov ax, [paint_select_screen_h]
    mov [paint_preview_h], ax
    mov ax, SELECT_SEG
    mov gs, ax
    xor bp, bp
.row:
    cmp bp, [paint_preview_h]
    jae .restore
    mov ax, bp
    add ax, [paint_preview_off_y]
    mul word [paint_clip_h]
    div word [paint_select_full_screen_h]
    mul word [paint_clip_w]
    mov si, ax
    xor di, di
.col:
    cmp di, [paint_preview_w]
    jae .next
    mov ax, di
    add ax, [paint_preview_off_x]
    mul word [paint_clip_w]
    div word [paint_select_full_screen_w]
    mov bx, si
    add bx, ax
    mov al, gs:[bx]
    mov cx, [paint_select_screen_x]
    add cx, di
    mov dx, [paint_select_screen_y]
    add dx, bp
    ; redraw_all may be rendering into BACKBUF_SEG; respect draw_seg so the
    ; preview survives the final back-buffer blit without flashing.
    call putpixel
    inc di
    jmp .col
.next:
    inc bp
    jmp .row
.restore:
    pop gs
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
.done:
    ret

draw_paint_selection_source_hole:
    push ax
    push bx
    push cx
    push dx
    push si
    mov ax, [paint_select_source_x]
    cmp ax, [paint_scroll_x]
    jb .done
    sub ax, [paint_scroll_x]
    xor bx, bx
    mov bl, [paint_zoom]
    mul bx
    add ax, [paint_canvas_screen_x]
    mov cx, ax
    mov ax, [paint_select_source_y]
    cmp ax, [paint_scroll_y]
    jb .done
    sub ax, [paint_scroll_y]
    mul bx
    add ax, [paint_canvas_screen_y]
    mov dx, ax
    mov ax, [paint_select_source_w]
    mul bx
    mov si, ax
    mov ax, [paint_canvas_screen_x]
    add ax, [paint_canvas_screen_w]
    sub ax, cx
    cmp si, ax
    jbe .width_ready
    mov si, ax
.width_ready:
    mov ax, [paint_select_source_h]
    mul bx
    mov bx, ax
    mov ax, [paint_canvas_screen_y]
    add ax, [paint_canvas_screen_h]
    sub ax, dx
    cmp bx, ax
    jbe .height_ready
    mov bx, ax
.height_ready:
    push dx
    mov ax, cx
    mov cx, si
    mov si, COL_WHITE
    mov dx, bx
    pop bx
    call fill_rect
.done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

draw_paint_text_objects:
    ; One editable multiline text layer per Paint process. Characters and their
    ; colors live in the process arena, so input can continue far beyond the
    ; visible canvas; only complete glyphs inside the canvas are rendered.
    cmp byte [paint_text_active], 0
    je .done
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push fs
    call paint_compute_canvas_rect
    mov ax, [active_data_seg]
    mov fs, ax
    xor ax, ax
    mov al, [paint_text_size]
    shl ax, 3
    mov [text_char_advance], ax
    mov ax, [paint_text_x]
    mov [text_local_x], ax
    mov ax, [paint_text_y]
    mov [text_local_y], ax
    mov word [text_caret_x], 0
    mov word [text_caret_y], 0
    mov byte [text_caret_valid], 0
    xor si, si
.char_loop:
    cmp si, [paint_text_len]
    jae .after_chars
    cmp si, [paint_text_cursor]
    jne .not_caret
    mov ax, [text_local_x]
    mov [text_caret_x], ax
    mov ax, [text_local_y]
    mov [text_caret_y], ax
    mov byte [text_caret_valid], 1
.not_caret:
    mov al, fs:[PAINT_TEXT_BASE+si]
    cmp al, 13
    jne .draw_char
    mov ax, [paint_text_x]
    mov [text_local_x], ax
    mov ax, [text_char_advance]
    add [text_local_y], ax
    inc si
    jmp .char_loop
.draw_char:
    mov ax, [text_local_x]
    add ax, [text_char_advance]
    cmp ax, [paint_canvas_w]
    ja .advance
    mov ax, [text_local_y]
    add ax, [text_char_advance]
    cmp ax, [paint_canvas_h]
    ja .advance
    mov ax, [text_local_x]
    add ax, [paint_canvas_screen_x]
    mov [text_draw_x], ax
    mov ax, [text_local_y]
    add ax, [paint_canvas_screen_y]
    mov [text_draw_y], ax
    mov byte [text_char_selected], 0
    cmp byte [paint_text_sel_active], 0
    je .selection_ready
    mov ax, [paint_text_anchor]
    mov bx, [paint_text_cursor]
    cmp ax, bx
    jbe .ordered
    xchg ax, bx
.ordered:
    cmp si, ax
    jb .selection_ready
    cmp si, bx
    jae .selection_ready
    mov byte [text_char_selected], 1
.selection_ready:
    cmp byte [text_char_selected], 0
    je .normal_color
    mov ax, [text_draw_x]
    mov bx, [text_draw_y]
    mov cx, [text_char_advance]
    mov dx, [text_char_advance]
    mov di, COL_BLUE
    push si
    mov si, di
    call fill_rect
    pop si
    mov bl, COL_WHITE
    jmp .glyph
.normal_color:
    mov bx, PAINT_TEXT_COLOR_BASE
    add bx, si
    mov bl, fs:[bx]
.glyph:
    mov al, fs:[PAINT_TEXT_BASE+si]
    mov bh, [paint_text_size]
    mov cx, [text_draw_x]
    mov dx, [text_draw_y]
    call draw_char_scaled
.advance:
    mov ax, [text_char_advance]
    add [text_local_x], ax
    inc si
    jmp .char_loop
.after_chars:
    cmp si, [paint_text_cursor]
    jne .caret
    mov ax, [text_local_x]
    mov [text_caret_x], ax
    mov ax, [text_local_y]
    mov [text_caret_y], ax
    mov byte [text_caret_valid], 1
.caret:
    cmp byte [paint_text_input], 0
    je .restore
    cmp byte [text_caret_valid], 0
    je .restore
    mov ax, [text_caret_x]
    cmp ax, [paint_canvas_w]
    jae .restore
    mov bx, [text_caret_y]
    cmp bx, [paint_canvas_h]
    jae .restore
    add ax, [paint_canvas_screen_x]
    add bx, [paint_canvas_screen_y]
    mov cx, [text_char_advance]
    mov dl, COL_BLACK
    call vline
.restore:
    pop fs
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
.done:
    ret

draw_dropdown_box:
    ; AX=x, BX=y, CX=w, DX=h
    push si
    mov si, COL_WHITE
    call fill_rect
    call draw_frame_black
    pop si
    ret

draw_open_menu:
    mov al, [menu_owner_pid]
    cmp al, WIN_MAIN
    je .owner_ready
    call proc_load
.owner_ready:
    mov al, [menu_open]
    cmp al, MENU_MAIN_FILE
    je .main_file
    cmp al, MENU_MAIN_APPS
    je .main_apps
    cmp al, MENU_MAIN_HELP
    je .main_help
    cmp al, MENU_PAINT_FILE
    je .paint_file
    cmp al, MENU_PAINT_EDIT
    je .paint_edit
    cmp al, MENU_PAINT_VIEW
    je .paint_view
    cmp al, MENU_NOTE_FILE
    je .note_file
    cmp al, MENU_NOTE_EDIT
    je .note_edit
    cmp al, MENU_NOTE_HELP
    je .note_help
    cmp al, MENU_CALC_FILE
    je .calc_file
    cmp al, MENU_CALC_HELP
    je .calc_help
    cmp al, MENU_SYS_MAIN
    je .sys_main
    cmp al, MENU_SYS_PAINT
    je .sys_paint
    cmp al, MENU_SYS_NOTE
    je .sys_note
    cmp al, MENU_SYS_CALC
    je .sys_calc
    ret
.main_file:
    mov ax, [main_x]
    add ax, 4
    mov bx, [main_y]
    add bx, 36
    mov cx, 112
    mov dx, 16
    call draw_dropdown_box
    mov si, str_exit_windows
    mov cx, [main_x]
    add cx, 10
    mov dx, [main_y]
    add dx, 40
    mov bl, COL_BLACK
    call draw_text
    ret
.main_apps:
    mov ax, [main_x]
    add ax, 44
    mov bx, [main_y]
    add bx, 36
    mov cx, 112
    mov dx, 68
    call draw_dropdown_box
    mov si, str_paint
    mov cx, [main_x]
    add cx, 50
    mov dx, [main_y]
    add dx, 40
    mov bl, COL_BLACK
    call draw_text
    mov si, str_notepad_title
    mov cx, [main_x]
    add cx, 50
    mov dx, [main_y]
    add dx, 53
    mov bl, COL_BLACK
    call draw_text
    mov si, str_calc_title
    mov cx, [main_x]
    add cx, 50
    mov dx, [main_y]
    add dx, 66
    mov bl, COL_BLACK
    call draw_text
    mov si, str_control
    mov cx, [main_x]
    add cx, 50
    mov dx, [main_y]
    add dx, 79
    mov bl, COL_BLACK
    call draw_text
    mov si, str_custom_program
    mov cx, [main_x]
    add cx, 50
    mov dx, [main_y]
    add dx, 92
    mov bl, COL_BLACK
    call draw_text
    ret
.main_help:
    mov ax, [main_x]
    add ax, 84
    mov bx, [main_y]
    add bx, 36
    mov cx, 104
    mov dx, 16
    call draw_dropdown_box
    mov si, str_about
    mov cx, [main_x]
    add cx, 90
    mov dx, [main_y]
    add dx, 40
    mov bl, COL_BLACK
    call draw_text
    ret
.paint_file:
    mov ax, [paint_x]
    add ax, 4
    mov bx, [paint_y]
    add bx, 36
    mov cx, 96
    mov dx, 42
    call draw_dropdown_box
    mov si, str_new_canvas
    mov cx, [paint_x]
    add cx, 10
    mov dx, [paint_y]
    add dx, 40
    mov bl, COL_BLACK
    call draw_text
    mov si, str_minimize
    mov cx, [paint_x]
    add cx, 10
    mov dx, [paint_y]
    add dx, 53
    mov bl, COL_BLACK
    call draw_text
    mov si, str_close_word
    mov cx, [paint_x]
    add cx, 10
    mov dx, [paint_y]
    add dx, 66
    mov bl, COL_BLACK
    call draw_text
    ret
.paint_edit:
    mov ax, [paint_x]
    add ax, 44
    mov bx, [paint_y]
    add bx, 36
    mov cx, 88
    mov dx, 68
    call draw_dropdown_box
    mov si, str_undo
    mov cx, [paint_x]
    add cx, 50
    mov dx, [paint_y]
    add dx, 40
    mov bl, COL_BLACK
    call draw_text
    mov si, str_cut
    mov cx, [paint_x]
    add cx, 50
    mov dx, [paint_y]
    add dx, 53
    mov bl, COL_BLACK
    call draw_text
    mov si, str_copy
    mov cx, [paint_x]
    add cx, 50
    mov dx, [paint_y]
    add dx, 66
    mov bl, COL_BLACK
    call draw_text
    mov si, str_paste
    mov cx, [paint_x]
    add cx, 50
    mov dx, [paint_y]
    add dx, 79
    mov bl, COL_BLACK
    call draw_text
    mov si, str_clear
    mov cx, [paint_x]
    add cx, 50
    mov dx, [paint_y]
    add dx, 92
    mov bl, COL_BLACK
    call draw_text
    ret
.paint_view:
    mov ax, [paint_x]
    add ax, 84
    mov bx, [paint_y]
    add bx, 36
    mov cx, 96
    mov dx, 42
    call draw_dropdown_box
    mov si, str_brush_1
    cmp byte [paint_tool], PAINT_TOOL_TEXT
    jne .view_label1
    mov si, str_text_1x
.view_label1:
    mov cx, [paint_x]
    add cx, 90
    mov dx, [paint_y]
    add dx, 40
    mov bl, COL_BLACK
    call draw_text
    mov si, str_brush_2
    cmp byte [paint_tool], PAINT_TOOL_TEXT
    jne .view_label2
    mov si, str_text_2x
.view_label2:
    mov cx, [paint_x]
    add cx, 90
    mov dx, [paint_y]
    add dx, 53
    mov bl, COL_BLACK
    call draw_text
    mov si, str_brush_4
    cmp byte [paint_tool], PAINT_TOOL_TEXT
    jne .view_label3
    mov si, str_text_3x
.view_label3:
    mov cx, [paint_x]
    add cx, 90
    mov dx, [paint_y]
    add dx, 66
    mov bl, COL_BLACK
    call draw_text
    ret
.note_file:
    mov ax, [note_x]
    add ax, 4
    mov bx, [note_y]
    add bx, 36
    mov cx, 120
    mov dx, 42
    call draw_dropdown_box
    mov si, str_new
    mov cx, [note_x]
    add cx, 10
    mov dx, [note_y]
    add dx, 40
    mov bl, COL_BLACK
    call draw_text
    mov si, str_insert_datetime
    mov cx, [note_x]
    add cx, 10
    mov dx, [note_y]
    add dx, 53
    mov bl, COL_BLACK
    call draw_text
    mov si, str_close_word
    mov cx, [note_x]
    add cx, 10
    mov dx, [note_y]
    add dx, 66
    mov bl, COL_BLACK
    call draw_text
    ret
.note_edit:
    mov ax, [note_x]
    add ax, 44
    mov bx, [note_y]
    add bx, 36
    mov cx, 112
    mov dx, 68
    call draw_dropdown_box
    mov si, str_undo
    mov cx, [note_x]
    add cx, 50
    mov dx, [note_y]
    add dx, 40
    mov bl, COL_BLACK
    call draw_text
    mov si, str_cut
    mov cx, [note_x]
    add cx, 50
    mov dx, [note_y]
    add dx, 53
    mov bl, COL_BLACK
    call draw_text
    mov si, str_copy
    mov cx, [note_x]
    add cx, 50
    mov dx, [note_y]
    add dx, 66
    mov bl, COL_BLACK
    call draw_text
    mov si, str_paste
    mov cx, [note_x]
    add cx, 50
    mov dx, [note_y]
    add dx, 79
    mov bl, COL_BLACK
    call draw_text
    mov si, str_select_all
    mov cx, [note_x]
    add cx, 50
    mov dx, [note_y]
    add dx, 92
    mov bl, COL_BLACK
    call draw_text
    ret
.note_help:
    mov ax, [note_x]
    add ax, 84
    mov bx, [note_y]
    add bx, 36
    mov cx, 104
    mov dx, 16
    call draw_dropdown_box
    mov si, str_about
    mov cx, [note_x]
    add cx, 90
    mov dx, [note_y]
    add dx, 40
    mov bl, COL_BLACK
    call draw_text
    ret
.calc_file:
    mov ax, [calc_x]
    add ax, 4
    mov bx, [calc_y]
    add bx, 36
    mov cx, 96
    mov dx, 42
    call draw_dropdown_box
    mov si, str_clear
    mov cx, [calc_x]
    add cx, 10
    mov dx, [calc_y]
    add dx, 40
    mov bl, COL_BLACK
    call draw_text
    mov si, str_minimize
    mov cx, [calc_x]
    add cx, 10
    mov dx, [calc_y]
    add dx, 53
    mov bl, COL_BLACK
    call draw_text
    mov si, str_close_word
    mov cx, [calc_x]
    add cx, 10
    mov dx, [calc_y]
    add dx, 66
    mov bl, COL_BLACK
    call draw_text
    ret
.calc_help:
    mov ax, [calc_x]
    add ax, 52
    mov bx, [calc_y]
    add bx, 36
    mov cx, 104
    mov dx, 16
    call draw_dropdown_box
    mov si, str_about
    mov cx, [calc_x]
    add cx, 58
    mov dx, [calc_y]
    add dx, 40
    mov bl, COL_BLACK
    call draw_text
    ret
.sys_main:
    mov ax, [main_x]
    mov bx, [main_y]
    call draw_system_menu_main
    ret
.sys_paint:
    mov ax, [paint_x]
    mov bx, [paint_y]
    call draw_system_menu_app
    ret
.sys_note:
    mov ax, [note_x]
    mov bx, [note_y]
    call draw_system_menu_app
    ret
.sys_calc:
    mov ax, [calc_x]
    mov bx, [calc_y]
    call draw_system_menu_app
    ret

draw_system_menu_main:
    add ax, 4
    add bx, 18
    push ax
    push bx
    mov cx, 104
    mov dx, 68
    call draw_dropdown_box
    pop bx
    pop ax
    mov [menu_draw_x], ax
    mov [menu_draw_y], bx
    mov si, str_restore_word
    call draw_system_menu_line
    add word [menu_draw_y], 13
    mov si, str_move
    call draw_system_menu_line
    add word [menu_draw_y], 13
    mov si, str_minimize
    call draw_system_menu_line
    add word [menu_draw_y], 13
    mov si, str_maximize
    call draw_system_menu_line
    add word [menu_draw_y], 13
    mov si, str_close_word
    call draw_system_menu_line
    ret

draw_system_menu_app:
    add ax, 4
    add bx, 18
    push ax
    push bx
    mov cx, 104
    mov dx, 68
    call draw_dropdown_box
    pop bx
    pop ax
    mov [menu_draw_x], ax
    mov [menu_draw_y], bx
    mov si, str_restore_word
    call draw_system_menu_line
    add word [menu_draw_y], 13
    mov si, str_move
    call draw_system_menu_line
    add word [menu_draw_y], 13
    mov si, str_minimize
    call draw_system_menu_line
    add word [menu_draw_y], 13
    mov si, str_maximize
    call draw_system_menu_line
    add word [menu_draw_y], 13
    mov si, str_close_word
    call draw_system_menu_line
    ret

draw_system_menu_line:
    mov cx, [menu_draw_x]
    add cx, 6
    mov dx, [menu_draw_y]
    add dx, 4
    mov bl, COL_BLACK
    call draw_text
    ret

draw_control_panel:
    mov ax, [control_x]
    mov bx, [control_y]
    mov cx, CONTROL_W
    mov dx, CONTROL_H
    call draw_bevel_box
    call draw_frame_black

    mov ax, [control_x]
    add ax, 3
    mov bx, [control_y]
    add bx, 3
    mov cx, CONTROL_W-6
    mov dx, TITLE_H
    mov si, COL_BLUE
    call fill_rect
    mov si, str_control
    mov cx, [control_x]
    add cx, 10
    mov dx, [control_y]
    add dx, 8
    mov bl, COL_WHITE
    call draw_text

    mov ax, [control_x]
    add ax, CONTROL_W-21
    mov bx, [control_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_close
    call draw_button

    mov ax, [control_x]
    add ax, CONTROL_CHECK_XOFF
    mov bx, [control_y]
    add bx, CONTROL_SWAP_YOFF
    mov dl, [mouse_swap_buttons]
    call draw_control_checkbox
    mov si, str_swap_mouse
    mov cx, [control_x]
    add cx, CONTROL_CHECK_XOFF+18
    mov dx, [control_y]
    add dx, CONTROL_SWAP_YOFF+2
    mov bl, COL_BLACK
    call draw_text

    mov ax, [control_x]
    add ax, CONTROL_CHECK_XOFF
    mov bx, [control_y]
    add bx, CONTROL_BOOT_YOFF
    mov dl, [control_boot_dos]
    call draw_control_checkbox
    mov si, str_boot_dos
    mov cx, [control_x]
    add cx, CONTROL_CHECK_XOFF+18
    mov dx, [control_y]
    add dx, CONTROL_BOOT_YOFF+2
    mov bl, COL_BLACK
    call draw_text

    mov ax, [control_x]
    add ax, CONTROL_CHECK_XOFF
    mov bx, [control_y]
    add bx, CONTROL_AUTORESTART_YOFF
    mov dl, [control_autorestart]
    call draw_control_checkbox
    mov si, str_auto_restart_bsod
    mov cx, [control_x]
    add cx, CONTROL_CHECK_XOFF+18
    mov dx, [control_y]
    add dx, CONTROL_AUTORESTART_YOFF+2
    mov bl, COL_BLACK
    call draw_text

    mov si, str_mouse_speed
    mov cx, [control_x]
    add cx, CONTROL_CHECK_XOFF
    mov dx, [control_y]
    add dx, CONTROL_SPEED_YOFF-14
    mov bl, COL_BLACK
    call draw_text
    mov ax, [control_x]
    add ax, CONTROL_SLIDER_XOFF
    mov bx, [control_y]
    add bx, CONTROL_SPEED_YOFF
    mov cx, CONTROL_SLIDER_W
    mov dx, 4
    mov si, COL_WHITE
    call fill_rect
    call draw_frame_black
    mov si, str_slow
    mov cx, [control_x]
    add cx, CONTROL_SLIDER_XOFF
    mov dx, [control_y]
    add dx, CONTROL_SPEED_YOFF+12
    mov bl, COL_DARKGRAY
    call draw_text
    mov si, str_fast
    mov cx, [control_x]
    add cx, CONTROL_SLIDER_XOFF+CONTROL_SLIDER_W-32
    mov dx, [control_y]
    add dx, CONTROL_SPEED_YOFF+12
    mov bl, COL_DARKGRAY
    call draw_text

    xor ax, ax
    mov al, [mouse_speed]
    dec ax
    mov bx, 9
    mul bx
    add ax, [control_x]
    add ax, CONTROL_SLIDER_XOFF
    sub ax, 4
    mov bx, [control_y]
    add bx, CONTROL_SPEED_YOFF-6
    mov cx, 9
    mov dx, 16
    call draw_bevel_box
    call draw_frame_black
    ret

draw_control_checkbox:
    ; AX=x, BX=y, DL=checked.
    push ax
    push bx
    push cx
    push dx
    push si
    mov cx, 12
    mov dx, 12
    mov si, COL_WHITE
    call fill_rect
    call draw_frame_black
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    test dl, dl
    jz .done
    push ax
    push bx
    mov si, str_check
    mov cx, ax
    add cx, 2
    mov dx, bx
    add dx, 2
    mov bl, COL_BLACK
    call draw_text
    pop bx
    pop ax
.done:
    ret

handle_control_mouse_down:
    mov ax, [control_x]
    add ax, CONTROL_W-21
    mov bx, [control_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_close
    mov di, BTN_CONTROL_CLOSE
    call try_capture_button
    jc .done

    mov ax, [control_x]
    add ax, CONTROL_CHECK_XOFF
    mov bx, [control_y]
    add bx, CONTROL_SWAP_YOFF
    mov cx, 12
    mov dx, 12
    mov si, str_empty
    mov di, BTN_CONTROL_SWAP
    call try_capture_button
    jc .done

    mov ax, [control_x]
    add ax, CONTROL_CHECK_XOFF
    mov bx, [control_y]
    add bx, CONTROL_BOOT_YOFF
    mov cx, 12
    mov dx, 12
    mov si, str_empty
    mov di, BTN_CONTROL_BOOT_DOS
    call try_capture_button
    jc .done

    mov ax, [control_x]
    add ax, CONTROL_CHECK_XOFF
    mov bx, [control_y]
    add bx, CONTROL_AUTORESTART_YOFF
    mov cx, 12
    mov dx, 12
    mov si, str_empty
    mov di, BTN_CONTROL_AUTORESTART
    call try_capture_button
    jc .done

    mov cx, [control_x]
    add cx, CONTROL_SLIDER_XOFF-6
    mov dx, [control_y]
    add dx, CONTROL_SPEED_YOFF-8
    mov si, CONTROL_SLIDER_W+12
    mov di, 22
    call hit_rect
    jnc .done
    mov byte [control_slider_drag], 1
    call control_update_slider
    jmp .done

.title:
.done:
    ; The remaining title-bar area starts a movable modal window drag.
    cmp byte [control_slider_drag], 0
    jne .ret
    cmp byte [captured_button], BTN_NONE
    jne .ret
    mov cx, [control_x]
    add cx, 4
    mov dx, [control_y]
    add dx, 4
    mov si, CONTROL_W-28
    mov di, TITLE_H-2
    call hit_rect
    jnc .ret
    mov byte [drag_mode], 8
    mov ax, [mouse_x]
    sub ax, [control_x]
    mov [drag_dx], ax
    mov ax, [mouse_y]
    sub ax, [control_y]
    mov [drag_dy], ax
.ret:
    ret

control_update_slider:
    push ax
    push bx
    push dx
    mov ax, [mouse_x]
    sub ax, [control_x]
    sub ax, CONTROL_SLIDER_XOFF
    jns .nonnegative
    xor ax, ax
.nonnegative:
    cmp ax, CONTROL_SLIDER_W
    jbe .clamped
    mov ax, CONTROL_SLIDER_W
.clamped:
    add ax, 4
    xor dx, dx
    mov bx, 9
    div bx
    inc al
    cmp al, 15
    jbe .store
    mov al, 15
.store:
    cmp al, [mouse_speed]
    je .done
    mov [mouse_speed], al
    mov byte [vm_abs_valid], 0
    call redraw_all
.done:
    pop dx
    pop bx
    pop ax
    ret

open_control_panel:
    mov byte [menu_open], MENU_NONE
    mov byte [message_open], 0
    mov byte [debug_open], 0
    mov byte [custom_open], 0
    mov byte [control_open], 1
    mov byte [control_slider_drag], 0
    mov al, [boot_default_gui]
    xor al, 1
    and al, 1
    mov [control_boot_dos], al
    mov al, [boot_autorestart]
    and al, 1
    mov [control_autorestart], al
    call redraw_all
    ret

open_debug_panel:
    mov byte [menu_open], MENU_NONE
    mov byte [message_open], 0
    mov byte [control_open], 0
    mov byte [custom_open], 0
    mov byte [control_slider_drag], 0
    mov byte [debug_open], 1
    mov byte [debug_scroll_drag], 0
    mov word [debug_scroll_offset], 0
    call redraw_all
    ret

; The complete Debug list renderer and formatter block is emitted in the
; always-resident far extension.  Keeping the implementation in a macro lets
; this remain a single-source flat binary while the small entry wrappers below
; keep every legacy near call inside Stage 2's strict 64-KiB IP window.
%macro DEBUG_UI_EXT_IMPL 0
draw_debug_window:
    cmp byte [debug_open], 4
    je draw_debug_blue_window
    cmp byte [debug_open], 5
    je draw_debug_fault_window
    cmp byte [debug_open], 6
    je draw_debug_normal_window
    cmp byte [debug_open], 2
    jae draw_debug_int_window

draw_debug_main_window:
    mov ax, DEBUG_MAIN_X
    mov bx, DEBUG_MAIN_Y
    mov cx, DEBUG_MAIN_W
    mov dx, DEBUG_MAIN_H
    call draw_bevel_box
    call draw_frame_black

    mov ax, DEBUG_MAIN_X+3
    mov bx, DEBUG_MAIN_Y+3
    mov cx, DEBUG_MAIN_W-6
    mov dx, TITLE_H
    mov si, COL_BLUE
    call fill_rect
    mov si, str_debug_title
    mov cx, DEBUG_MAIN_X+9
    mov dx, DEBUG_MAIN_Y+8
    mov bl, COL_WHITE
    call draw_text

    mov ax, DEBUG_MAIN_X+DEBUG_MAIN_W-21
    mov bx, DEBUG_MAIN_Y+6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_close
    call draw_button

    ; A framed vertical tool group containing the interrupt and CPU-mode tests.
    mov ax, DEBUG_MAIN_X+14
    mov bx, DEBUG_MAIN_Y+34
    mov cx, DEBUG_MAIN_W-28
    mov dx, DEBUG_MAIN_H-47
    mov si, COL_GRAY
    call fill_rect
    call draw_frame_black
    ; Clear a real caption gap in the frame before drawing the group title.
    ; Drawing transparent glyphs directly over the border made the line cut
    ; through "Debug".
    mov ax, DEBUG_MAIN_X+19
    mov bx, DEBUG_MAIN_Y+29
    mov cx, 45
    mov dx, 10
    mov si, COL_GRAY
    call fill_rect
    mov si, str_debug
    mov cx, DEBUG_MAIN_X+22
    mov dx, DEBUG_MAIN_Y+30
    mov bl, COL_BLACK
    call draw_text

    mov ax, DEBUG_MAIN_X+21
    mov bx, DEBUG_MAIN_Y+39
    mov cx, DEBUG_MAIN_W-42
    mov dx, 15
    mov si, str_bluescreen
    call draw_button

    mov ax, DEBUG_MAIN_X+21
    mov bx, DEBUG_MAIN_Y+57
    mov cx, DEBUG_MAIN_W-42
    mov dx, 15
    mov si, str_fault
    call draw_button

    mov ax, DEBUG_MAIN_X+21
    mov bx, DEBUG_MAIN_Y+75
    mov cx, DEBUG_MAIN_W-42
    mov dx, 15
    mov si, str_int_test
    call draw_button

    mov ax, DEBUG_MAIN_X+21
    mov bx, DEBUG_MAIN_Y+93
    mov cx, DEBUG_MAIN_W-42
    mov dx, 15
    mov si, str_int_execute
    call draw_button

    mov ax, DEBUG_MAIN_X+21
    mov bx, DEBUG_MAIN_Y+111
    mov cx, DEBUG_MAIN_W-42
    mov dx, 15
    mov si, str_go_protected
    call draw_button

    mov ax, DEBUG_MAIN_X+21
    mov bx, DEBUG_MAIN_Y+129
    mov cx, DEBUG_MAIN_W-42
    mov dx, 15
    mov si, str_go_long
    call draw_button

    mov ax, DEBUG_MAIN_X+21
    mov bx, DEBUG_MAIN_Y+147
    mov cx, DEBUG_MAIN_W-42
    mov dx, 15
    mov si, str_disable_bluescreen
    cmp byte [BLUESCREEN_ENABLE_ADDR], 0
    jne .blue_toggle_label_ready
    mov si, str_enable_bluescreen
.blue_toggle_label_ready:
    call draw_button
    ret

draw_debug_blue_window:
    mov ax, DEBUG_BLUE_X
    mov bx, DEBUG_BLUE_Y
    mov cx, DEBUG_BLUE_W
    mov dx, DEBUG_BLUE_H
    call draw_bevel_box
    call draw_frame_black

    mov ax, DEBUG_BLUE_X+3
    mov bx, DEBUG_BLUE_Y+3
    mov cx, DEBUG_BLUE_W-6
    mov dx, TITLE_H
    mov si, COL_BLUE
    call fill_rect
    mov si, str_bluescreen_mode
    mov cx, DEBUG_BLUE_X+9
    mov dx, DEBUG_BLUE_Y+8
    mov bl, COL_WHITE
    call draw_text

    mov ax, DEBUG_BLUE_X+DEBUG_BLUE_W-21
    mov bx, DEBUG_BLUE_Y+6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_close
    call draw_button

    mov ax, DEBUG_BLUE_X+12
    mov bx, DEBUG_BLUE_Y+31
    mov cx, DEBUG_BLUE_W-24
    mov dx, 24
    mov si, str_bluescreen_real
    call draw_button

    mov ax, DEBUG_BLUE_X+12
    mov bx, DEBUG_BLUE_Y+61
    mov cx, DEBUG_BLUE_W-24
    mov dx, 24
    mov si, str_bluescreen_pm
    call draw_button

    mov ax, DEBUG_BLUE_X+12
    mov bx, DEBUG_BLUE_Y+91
    mov cx, DEBUG_BLUE_W-24
    mov dx, 24
    mov si, str_bluescreen_lm
    call draw_button
    ret

draw_debug_fault_window:
    mov ax, DEBUG_FAULT_X
    mov bx, DEBUG_FAULT_Y
    mov cx, DEBUG_FAULT_W
    mov dx, DEBUG_FAULT_H
    call draw_bevel_box
    call draw_frame_black

    mov ax, DEBUG_FAULT_X+3
    mov bx, DEBUG_FAULT_Y+3
    mov cx, DEBUG_FAULT_W-6
    mov dx, TITLE_H
    mov si, COL_BLUE
    call fill_rect
    mov si, str_fault_title
    mov cx, DEBUG_FAULT_X+9
    mov dx, DEBUG_FAULT_Y+8
    mov bl, COL_WHITE
    call draw_text

    mov ax, DEBUG_FAULT_X+DEBUG_FAULT_W-21
    mov bx, DEBUG_FAULT_Y+6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_close
    call draw_button

    mov ax, DEBUG_FAULT_X+12
    mov bx, DEBUG_FAULT_Y+31
    mov cx, DEBUG_FAULT_W-24
    mov dx, 24
    mov si, str_normal_fault
    call draw_button

    mov ax, DEBUG_FAULT_X+12
    mov bx, DEBUG_FAULT_Y+61
    mov cx, DEBUG_FAULT_W-24
    mov dx, 24
    mov si, str_double_fault
    call draw_button

    mov ax, DEBUG_FAULT_X+12
    mov bx, DEBUG_FAULT_Y+91
    mov cx, DEBUG_FAULT_W-24
    mov dx, 24
    mov si, str_triple_fault
    call draw_button
    ret

draw_debug_normal_window:
    mov ax, DEBUG_INT_X
    mov bx, DEBUG_INT_Y
    mov cx, DEBUG_INT_W
    mov dx, DEBUG_INT_H
    call draw_bevel_box
    call draw_frame_black

    mov ax, DEBUG_INT_X+3
    mov bx, DEBUG_INT_Y+3
    mov cx, DEBUG_INT_W-6
    mov dx, TITLE_H
    mov si, COL_BLUE
    call fill_rect
    mov si, str_normal_fault_title
    mov cx, DEBUG_INT_X+9
    mov dx, DEBUG_INT_Y+8
    mov bl, COL_WHITE
    call draw_text

    mov ax, DEBUG_INT_X+DEBUG_INT_W-21
    mov bx, DEBUG_INT_Y+6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_close
    call draw_button

    mov ax, DEBUG_INT_X+10
    mov bx, DEBUG_INT_Y+34
    mov cx, DEBUG_INT_W-20
    mov dx, DEBUG_INT_H-42
    mov si, COL_GRAY
    call fill_rect
    call draw_frame_black
    mov ax, DEBUG_INT_X+14
    mov bx, DEBUG_INT_Y+29
    mov cx, 72
    mov dx, 10
    mov si, COL_GRAY
    call fill_rect
    mov si, str_exceptions
    mov cx, DEBUG_INT_X+17
    mov dx, DEBUG_INT_Y+30
    mov bl, COL_BLACK
    call draw_text

    push ax
    push bx
    push cx
    push dx
    push si
    push di
    xor bx, bx
    mov word [debug_list_button_y], DEBUG_INT_Y+DEBUG_INT_ITEM_YOFF
.item_loop:
    cmp bx, DEBUG_INT_VISIBLE
    jae .items_done
    mov ax, [debug_scroll_offset]
    add ax, bx
    cmp ax, DEBUG_NORMAL_COUNT
    jae .items_done
    mov [debug_draw_fault], al
    call debug_fault_get_label
    mov ax, DEBUG_INT_X+DEBUG_INT_ITEM_XOFF
    mov bx, [debug_list_button_y]
    mov cx, DEBUG_INT_ITEM_W
    mov dx, DEBUG_INT_ITEM_H
    call draw_button
    add word [debug_list_button_y], DEBUG_INT_ITEM_STEP
    xor bx, bx
    mov bl, [debug_draw_fault]
    sub bx, [debug_scroll_offset]
    inc bx
    jmp .item_loop
.items_done:
    call draw_debug_scrollbar
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

debug_fault_get_label:
    ; AL=normal-fault list index, SI=label.
    push ax
    push bx
    xor ah, ah
    mov bx, ax
    shl bx, 1
    mov si, [debug_normal_fault_labels+bx]
    pop bx
    pop ax
    ret

draw_debug_int_window:
    mov ax, DEBUG_INT_X
    mov bx, DEBUG_INT_Y
    mov cx, DEBUG_INT_W
    mov dx, DEBUG_INT_H
    call draw_bevel_box
    call draw_frame_black

    mov ax, DEBUG_INT_X+3
    mov bx, DEBUG_INT_Y+3
    mov cx, DEBUG_INT_W-6
    mov dx, TITLE_H
    mov si, COL_BLUE
    call fill_rect
    mov si, str_int_test_title
    cmp byte [debug_open], 3
    jne .title_ready
    mov si, str_int_exec_title
.title_ready:
    mov cx, DEBUG_INT_X+9
    mov dx, DEBUG_INT_Y+8
    mov bl, COL_WHITE
    call draw_text

    mov ax, DEBUG_INT_X+DEBUG_INT_W-21
    mov bx, DEBUG_INT_Y+6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_close
    call draw_button

    mov ax, DEBUG_INT_X+10
    mov bx, DEBUG_INT_Y+34
    mov cx, DEBUG_INT_W-20
    mov dx, DEBUG_INT_H-42
    mov si, COL_GRAY
    call fill_rect
    call draw_frame_black
    ; Groupbox captions occupy a gap in the top border rather than being
    ; painted transparently on top of it.
    mov ax, DEBUG_INT_X+14
    mov bx, DEBUG_INT_Y+29
    mov cx, 84
    mov dx, 10
    mov si, COL_GRAY
    call fill_rect
    mov si, str_interrupts
    mov cx, DEBUG_INT_X+17
    mov dx, DEBUG_INT_Y+30
    mov bl, COL_BLACK
    call draw_text

    push ax
    push bx
    push cx
    push dx
    push si
    push di
    xor bx, bx
    mov word [debug_list_button_y], DEBUG_INT_Y+DEBUG_INT_ITEM_YOFF
.item_loop:
    cmp bx, DEBUG_INT_VISIBLE
    jae .items_done
    mov ax, [debug_scroll_offset]
    add ax, bx
    cmp ax, 256
    jae .items_done
    mov [debug_draw_int], al
    call debug_build_int_label
    mov ax, DEBUG_INT_X+DEBUG_INT_ITEM_XOFF
    mov bx, [debug_list_button_y]
    mov cx, DEBUG_INT_ITEM_W
    mov dx, DEBUG_INT_ITEM_H
    mov si, debug_int_label_buf
    call draw_button
    add word [debug_list_button_y], DEBUG_INT_ITEM_STEP
    xor bx, bx
    mov bl, [debug_draw_int]
    sub bx, [debug_scroll_offset]
    inc bx
    jmp .item_loop
.items_done:
    call draw_debug_scrollbar
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

debug_build_int_label:
    ; AL=interrupt number. Build a fixed uppercase label "INT XXh".
    push ax
    push bx
    push di
    mov bl, al
    mov di, debug_int_label_buf
    mov byte [di+0], 'I'
    mov byte [di+1], 'N'
    mov byte [di+2], 'T'
    mov byte [di+3], ' '
    mov al, bl
    shr al, 4
    call debug_nibble_to_ascii
    mov [di+4], al
    mov al, bl
    and al, 0x0F
    call debug_nibble_to_ascii
    mov [di+5], al
    mov byte [di+6], 'h'
    mov byte [di+7], 0
    pop di
    pop bx
    pop ax
    ret

debug_nibble_to_ascii:
    and al, 0x0F
    cmp al, 9
    jbe .digit
    add al, 'A'-10
    ret
.digit:
    add al, '0'
    ret

debug_compute_scroll_thumb:
    push ax
    push bx
    push dx
    mov ax, [debug_scroll_offset]
    mov bx, DEBUG_SCROLL_TRAVEL
    mul bx
    call debug_get_scroll_max
    xor dx, dx
    div bx
    add ax, DEBUG_INT_Y+DEBUG_SCROLL_TRACK_YOFF
    mov [debug_scroll_thumb_y], ax
    pop dx
    pop bx
    pop ax
    ret

debug_get_scroll_max:
    mov bx, DEBUG_SCROLL_MAX
    cmp byte [debug_open], 6
    jne .done
    mov bx, DEBUG_NORMAL_SCROLL_MAX
.done:
    ret

draw_debug_scrollbar:
    mov ax, DEBUG_INT_X+DEBUG_SCROLL_XOFF
    mov bx, DEBUG_INT_Y+DEBUG_SCROLL_UP_YOFF
    mov cx, 16
    mov dx, 14
    mov si, str_scroll_up
    call draw_button

    mov ax, DEBUG_INT_X+DEBUG_SCROLL_XOFF
    mov bx, DEBUG_INT_Y+DEBUG_SCROLL_TRACK_YOFF
    mov cx, 16
    mov dx, DEBUG_SCROLL_TRACK_H
    mov si, COL_DARKGRAY
    call fill_rect
    call draw_frame_black

    mov ax, DEBUG_INT_X+DEBUG_SCROLL_XOFF
    mov bx, DEBUG_INT_Y+DEBUG_SCROLL_DOWN_YOFF
    mov cx, 16
    mov dx, 14
    mov si, str_scroll_down
    call draw_button

    call debug_compute_scroll_thumb
    mov ax, DEBUG_INT_X+DEBUG_SCROLL_XOFF+2
    mov bx, [debug_scroll_thumb_y]
    mov cx, 12
    mov dx, DEBUG_SCROLL_THUMB_H
    call draw_bevel_box
    call draw_frame_black
    ret

debug_scroll_one_up:
    cmp word [debug_scroll_offset], 0
    je .redraw
    dec word [debug_scroll_offset]
.redraw:
    call redraw_all
    ret

debug_scroll_one_down:
    push bx
    call debug_get_scroll_max
    cmp word [debug_scroll_offset], bx
    jae .redraw
    inc word [debug_scroll_offset]
.redraw:
    pop bx
    call redraw_all
    ret

debug_scroll_page_up:
    cmp word [debug_scroll_offset], DEBUG_INT_VISIBLE
    jb .top
    sub word [debug_scroll_offset], DEBUG_INT_VISIBLE
    jmp .redraw
.top:
    mov word [debug_scroll_offset], 0
.redraw:
    call redraw_all
    ret

debug_scroll_page_down:
    push bx
    add word [debug_scroll_offset], DEBUG_INT_VISIBLE
    call debug_get_scroll_max
    cmp word [debug_scroll_offset], bx
    jbe .ready
    mov [debug_scroll_offset], bx
.ready:
    pop bx
    call redraw_all
    ret

debug_byte_to_hex:
    ; AL=value, DS:DI=two-byte output field.
    push ax
    push bx
    mov bl, al
    shr al, 4
    call debug_nibble_to_ascii
    mov [di], al
    mov al, bl
    and al, 0x0F
    call debug_nibble_to_ascii
    mov [di+1], al
    pop bx
    pop ax
    ret

debug_word_to_hex:
    ; AX=value, DS:DI=four-byte uppercase output field.
    push ax
    push bx
    push di
    mov bx, ax
    mov al, bh
    call debug_byte_to_hex
    add di, 2
    mov al, bl
    call debug_byte_to_hex
    pop di
    pop bx
    pop ax
    ret

debug_get_interrupt_description:
    ; AL=vector, returns DS:SI=human-readable service/category description.
    push ax
    push bx
    xor bx, bx
    mov bl, al
    cmp al, 0x20
    jb .low_table
    cmp al, 0x30
    jb .dos_table
    cmp al, 0x60
    jb .system
    cmp al, 0x68
    jb .user
    cmp al, 0x70
    jb .reserved
    cmp al, 0x78
    jb .irq_high
    mov si, str_int_desc_firmware
    jmp .done
.low_table:
    shl bx, 1
    mov si, [debug_int_desc_00_1f+bx]
    jmp .done
.dos_table:
    sub bx, 0x20
    shl bx, 1
    mov si, [debug_int_desc_20_2f+bx]
    jmp .done
.system:
    mov si, str_int_desc_system
    jmp .done
.user:
    mov si, str_int_desc_user
    jmp .done
.reserved:
    mov si, str_int_desc_reserved
    jmp .done
.irq_high:
    mov si, str_int_desc_irq_hi
.done:
    pop bx
    pop ax
    ret

debug_run_interrupt_test:
    mov [debug_pending_int], al
    cmp al, 0x10
    je .int10
    cmp al, 0x11
    je .int11
    cmp al, 0x12
    je .int12
    cmp al, 0x13
    je .int13
    cmp al, 0x14
    je .int14
    cmp al, 0x15
    je .int15
    cmp al, 0x16
    je .int16
    cmp al, 0x17
    je .int17
    cmp al, 0x1A
    je .int1a
    call debug_safe_interrupt_probe
    jmp .show
.int10:
    push ax
    push bx
    push di
    mov ah, 0x0F
    int 0x10
    mov di, debug_int10_mode_hex
    call debug_byte_to_hex
    mov al, ah
    mov di, debug_int10_cols_hex
    call debug_byte_to_hex
    mov al, bh
    mov di, debug_int10_page_hex
    call debug_byte_to_hex
    mov byte [debug_result_success], 1
    mov word [debug_result_line1_ptr], str_debug_int10_line1
    mov word [debug_result_line2_ptr], str_debug_int10_line2
    pop di
    pop bx
    pop ax
    jmp .show
.int11:
    push ax
    push di
    int 0x11
    mov di, debug_int11_ax_hex
    call debug_word_to_hex
    mov byte [debug_result_success], 1
    mov word [debug_result_line1_ptr], str_debug_int11_line1
    mov word [debug_result_line2_ptr], str_debug_int11_line2
    pop di
    pop ax
    jmp .show
.int12:
    push ax
    push di
    int 0x12
    mov di, debug_int12_ax_hex
    call debug_word_to_hex
    mov byte [debug_result_success], 1
    mov word [debug_result_line1_ptr], str_debug_int12_line1
    mov word [debug_result_line2_ptr], str_debug_int12_line2
    pop di
    pop ax
    jmp .show
.int13:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es
    xor ah, ah                       ; INT 13h AH=00h: reset disk system
    mov dl, [os_boot_drive]
    int 0x13
    mov [debug_int13_status], ah
    jc .int13_failed
    mov byte [debug_result_success], 1
    jmp .int13_details
.int13_failed:
    mov byte [debug_result_success], 0
.int13_details:
    mov al, [os_boot_drive]
    mov di, debug_int13_drive_hex
    call debug_byte_to_hex
    mov al, [debug_int13_status]
    mov di, debug_int13_status_hex
    call debug_byte_to_hex
    mov word [debug_result_line1_ptr], str_debug_int13_line1
    mov word [debug_result_line2_ptr], str_debug_int13_line2
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
.int13_done:
    jmp .show
.int14:
    push ax
    push dx
    push di
    mov ax, 0x0300                  ; read COM1 port status
    xor dx, dx
    int 0x14
    mov di, debug_int14_ax_hex
    call debug_word_to_hex
    mov byte [debug_result_success], 1
    mov word [debug_result_line1_ptr], str_debug_int14_line1
    mov word [debug_result_line2_ptr], str_debug_int14_line2
    pop di
    pop dx
    pop ax
    jmp .show
.int15:
    pushf
    push ax
    push dx
    push di
    mov ah, 0x88                   ; query contiguous extended-memory KiB
    int 0x15
    pushf
    pop dx
    mov di, debug_int15_ax_hex
    call debug_word_to_hex
    mov byte [debug_int15_cf_char], '0'
    mov byte [debug_result_success], 1
    test dl, 1
    jz .int15_result
    mov byte [debug_int15_cf_char], '1'
    mov byte [debug_result_success], 0
.int15_result:
    mov word [debug_result_line1_ptr], str_debug_int15_line1
    mov word [debug_result_line2_ptr], str_debug_int15_line2
    pop di
    pop dx
    pop ax
    popf
    jmp .show
.int16:
    push ax
    mov ah, 0x01                   ; nonblocking keyboard status
    int 0x16
    jz .int16_empty
    mov word [debug_result_line2_ptr], str_debug_int16_ready
    jmp .int16_result
.int16_empty:
    mov word [debug_result_line2_ptr], str_debug_int16_empty
.int16_result:
    mov byte [debug_result_success], 1
    mov word [debug_result_line1_ptr], str_debug_int16_line1
    pop ax
    jmp .show
.int17:
    push ax
    push dx
    push di
    mov ah, 0x02                   ; read LPT1 status without printing
    xor dx, dx
    int 0x17
    mov al, ah
    mov di, debug_int17_ah_hex
    call debug_byte_to_hex
    mov byte [debug_result_success], 1
    mov word [debug_result_line1_ptr], str_debug_int17_line1
    mov word [debug_result_line2_ptr], str_debug_int17_line2
    pop di
    pop dx
    pop ax
    jmp .show
.int1a:
    push ax
    push cx
    push dx
    push di
    xor ah, ah                     ; read BIOS tick counter
    int 0x1A
    mov ax, cx
    mov di, debug_int1a_cx_hex
    call debug_word_to_hex
    mov ax, dx
    mov di, debug_int1a_dx_hex
    call debug_word_to_hex
    mov byte [debug_result_success], 1
    mov word [debug_result_line1_ptr], str_debug_int1a_line1
    mov word [debug_result_line2_ptr], str_debug_int1a_line2
    pop di
    pop dx
    pop cx
    pop ax
.show:
    mov byte [message_kind], MSG_DEBUG_RESULT
    mov byte [message_open], 1
    call redraw_all
    ret

%endmacro

%macro DEBUG_UI_EXT_WRAPPER 2
%1:
    call STAGE2_EXT_SEG:(%2-stage2_ext_start)
    ret
%endmacro

DEBUG_UI_EXT_WRAPPER draw_debug_window, debug_ext_entry_draw_window
DEBUG_UI_EXT_WRAPPER debug_fault_get_label, debug_ext_entry_fault_label
DEBUG_UI_EXT_WRAPPER debug_build_int_label, debug_ext_entry_build_int_label
DEBUG_UI_EXT_WRAPPER debug_nibble_to_ascii, debug_ext_entry_nibble
DEBUG_UI_EXT_WRAPPER debug_compute_scroll_thumb, debug_ext_entry_compute_thumb
DEBUG_UI_EXT_WRAPPER debug_get_scroll_max, debug_ext_entry_scroll_max
DEBUG_UI_EXT_WRAPPER debug_scroll_one_up, debug_ext_entry_scroll_up
DEBUG_UI_EXT_WRAPPER debug_scroll_one_down, debug_ext_entry_scroll_down
DEBUG_UI_EXT_WRAPPER debug_scroll_page_up, debug_ext_entry_page_up
DEBUG_UI_EXT_WRAPPER debug_scroll_page_down, debug_ext_entry_page_down
DEBUG_UI_EXT_WRAPPER debug_byte_to_hex, debug_ext_entry_byte_hex
DEBUG_UI_EXT_WRAPPER debug_word_to_hex, debug_ext_entry_word_hex
DEBUG_UI_EXT_WRAPPER debug_get_interrupt_description, debug_ext_entry_int_description
DEBUG_UI_EXT_WRAPPER debug_run_interrupt_test, debug_ext_entry_run_interrupt

%unmacro DEBUG_UI_EXT_WRAPPER 2

debug_safe_interrupt_probe:
    ; Every INT 00h..FFh button performs an actual software-INT dispatch
    ; without running an unknown firmware/application handler.  Temporarily
    ; point the selected IVT entry at an IRET probe, execute CD xx, then restore
    ; the original vector.  This keeps hazardous vectors such as INT 00h,
    ; INT 08h and INT 19h from hanging or rebooting the machine.
    pushf
    cli
    push ax
    push bx
    push dx
    push di
    push si
    push es
    mov dl, [debug_pending_int]
    xor dh, dh
    mov bx, dx
    shl bx, 1
    shl bx, 1
    xor ax, ax
    mov es, ax
    mov ax, es:[bx]
    mov [debug_probe_old_off], ax
    mov ax, es:[bx+2]
    mov [debug_probe_old_seg], ax

    mov word es:[bx], debug_interrupt_probe_handler
    mov word es:[bx+2], 0
    mov byte [debug_probe_seen], 0
    ; Use a fixed three-byte entry for every vector.  Rewriting the immediate
    ; byte of one INT instruction left stale prefetch bytes on some CPUs.
    xor ax, ax
    mov al, [debug_pending_int]
    mov si, ax
    shl ax, 1
    add si, ax
    ; The GUI runs with CS=07E0h while data labels use physical DS=0000h.
    ; An indirect near call therefore needs the table's stage-2-relative IP.
    add si, debug_interrupt_probe_table-stage2_start
    call si

    mov ax, [debug_probe_old_off]
    mov es:[bx], ax
    mov ax, [debug_probe_old_seg]
    mov es:[bx+2], ax

    mov ax, [debug_probe_old_seg]
    mov di, debug_probe_seg_hex
    call debug_word_to_hex
    mov ax, [debug_probe_old_off]
    mov di, debug_probe_off_hex
    call debug_word_to_hex

    mov byte [debug_result_success], 0
    mov word [debug_result_line1_ptr], str_debug_probe_failed
    cmp byte [debug_probe_seen], 0
    je .result_ready
    mov byte [debug_result_success], 1
    mov al, [debug_pending_int]
    call debug_get_interrupt_description
    mov [debug_result_line1_ptr], si
.result_ready:
    mov word [debug_result_line2_ptr], str_debug_probe_line2
    pop es
    pop si
    pop di
    pop dx
    pop bx
    pop ax
    popf
    ret

debug_execute_interrupt_raw:
    ; Select the requested CD xx entry while all caller-visible register and
    ; flag values are saved, then restore them before executing the interrupt.
    ; Thus no BIOS/DOS function number (AH, AL, etc.) is prepared for the
    ; handler; it receives exactly the UI execution context.
    ; Low vectors are exception aliases.  When blue screens are disabled, do
    ; not dispatch them at all: returning them through an old firmware vector
    ; can recursively re-enter our hooks (INT 05h was the reproducible case).
    cmp byte [BLUESCREEN_ENABLE_ADDR], 0
    jne .execute
    cmp byte [debug_pending_int], 0x10
    jae .execute
    ; Disabled blue screens suppress incidental low-vector faults silently.
    ; Only the explicit Bluescreen button and CRASH command report the gate.
    call redraw_all
    ret
.execute:
    pushf
    pusha
    push ds
    push es
    push fs
    push gs
    xor ax, ax
    mov ds, ax
    xor bx, bx
    mov bl, [debug_pending_int]
    mov si, bx
    shl bx, 1
    add si, bx
    add si, debug_interrupt_probe_table-stage2_start
    mov [debug_raw_target], si
    pop gs
    pop fs
    pop es
    pop ds
    popa
    popf
    call word [debug_raw_target]

    ; If the raw handler returns, rebuild the GUI video/mouse state because a
    ; random INT 10h or firmware vector may have changed it.
    xor ax, ax
    mov ds, ax
    mov es, ax
    call init_font_and_video
    call init_mouse_support
    mov byte [cursor_visible], 0
    call redraw_all
    call mouse_cursor_show
    ret

debug_interrupt_probe_table:
%assign debug_probe_vector_number 0
%rep 256
    db 0xCD, debug_probe_vector_number, 0xC3
%assign debug_probe_vector_number debug_probe_vector_number+1
%endrep

debug_interrupt_probe_handler:
    mov byte [cs:debug_probe_seen], 1
    iret

debug_pm_prepare_custom_paging:
    call STAGE2_EXT_SEG:(debug_pm_prepare_custom_paging_ext-stage2_ext_start)
    ret

debug_build_fault_idts:
    ; Build both transition IDTs in low identity-mapped memory.  The 32-bit
    ; table protects the PE/PAE/long-mode entry window; the 64-bit table uses
    ; IST1 so even #DF receives a fresh, known-good stack.
    push eax
    push cx
    push si
    push di
    push es
    push fs
    xor ax, ax
    mov es, ax

    mov eax, debug_pm_fault_stub_table
    mov si, ax
    and si, 0x000F
    shr eax, 4
    mov fs, ax
    mov di, DEBUG_PM_IDT32_PHYS
    mov cx, 32
.gate32:
    mov eax, [fs:si]
    mov word es:[di+0], ax
    mov word es:[di+2], DEBUG_PM_CODE32_SEL
    mov byte es:[di+4], 0
    mov byte es:[di+5], 0x8E
    shr eax, 16
    mov word es:[di+6], ax
    add si, 4
    add di, 8
    loop .gate32

    mov eax, debug_lm_fault_stub_table
    mov si, ax
    and si, 0x000F
    shr eax, 4
    mov fs, ax
    mov di, DEBUG_LM_IDT64_PHYS
    mov cx, 32
.gate64:
    mov eax, [fs:si]
    mov word es:[di+0], ax
    mov word es:[di+2], DEBUG_LM_CODE64_SEL
    mov byte es:[di+4], 1          ; IST1
    mov byte es:[di+5], 0x8E
    shr eax, 16
    mov word es:[di+6], ax
    mov dword es:[di+8], 0
    mov dword es:[di+12], 0
    add si, 4
    add di, 16
    loop .gate64

    pop fs
    pop es
    pop di
    pop si
    pop cx
    pop eax
    ret

align 4, db 0
debug_pm_fault_stub_table:
    dd debug_pm_fault_stub_00, debug_pm_fault_stub_01
    dd debug_pm_fault_stub_02, debug_pm_fault_stub_03
    dd debug_pm_fault_stub_04, debug_pm_fault_stub_05
    dd debug_pm_fault_stub_06, debug_pm_fault_stub_07
    dd debug_pm_fault_stub_08, debug_pm_fault_stub_09
    dd debug_pm_fault_stub_10, debug_pm_fault_stub_11
    dd debug_pm_fault_stub_12, debug_pm_fault_stub_13
    dd debug_pm_fault_stub_14, debug_pm_fault_stub_15
    dd debug_pm_fault_stub_16, debug_pm_fault_stub_17
    dd debug_pm_fault_stub_18, debug_pm_fault_stub_19
    dd debug_pm_fault_stub_20, debug_pm_fault_stub_21
    dd debug_pm_fault_stub_22, debug_pm_fault_stub_23
    dd debug_pm_fault_stub_24, debug_pm_fault_stub_25
    dd debug_pm_fault_stub_26, debug_pm_fault_stub_27
    dd debug_pm_fault_stub_28, debug_pm_fault_stub_29
    dd debug_pm_fault_stub_30, debug_pm_fault_stub_31

debug_lm_fault_stub_table:
    dd debug_lm_fault_stub_00, debug_lm_fault_stub_01
    dd debug_lm_fault_stub_02, debug_lm_fault_stub_03
    dd debug_lm_fault_stub_04, debug_lm_fault_stub_05
    dd debug_lm_fault_stub_06, debug_lm_fault_stub_07
    dd debug_lm_fault_stub_08, debug_lm_fault_stub_09
    dd debug_lm_fault_stub_10, debug_lm_fault_stub_11
    dd debug_lm_fault_stub_12, debug_lm_fault_stub_13
    dd debug_lm_fault_stub_14, debug_lm_fault_stub_15
    dd debug_lm_fault_stub_16, debug_lm_fault_stub_17
    dd debug_lm_fault_stub_18, debug_lm_fault_stub_19
    dd debug_lm_fault_stub_20, debug_lm_fault_stub_21
    dd debug_lm_fault_stub_22, debug_lm_fault_stub_23
    dd debug_lm_fault_stub_24, debug_lm_fault_stub_25
    dd debug_lm_fault_stub_26, debug_lm_fault_stub_27
    dd debug_lm_fault_stub_28, debug_lm_fault_stub_29
    dd debug_lm_fault_stub_30, debug_lm_fault_stub_31

; Enter 32-bit protected mode with a flat address space, display a short
; confirmation directly in VGA text memory, then return to the existing
; real-mode GUI after a raw keyboard make code arrives.
debug_enter_protected_mode:
    pushf
    pusha
    push ds
    push es
    push fs
    push gs

    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ax, ss
    mov [debug_pm_saved_ss], ax
    mov [debug_pm_saved_sp], sp

    ; Stop a polling PS/2 mouse so auxiliary bytes cannot starve the keyboard
    ; while interrupts and BIOS services are unavailable in protected mode.
    cmp byte [mouse_mode], 0
    jne .mouse_quiet
    call mouse_ps2_disable_stream
.mouse_quiet:

    ; Discard any BIOS key queued before the test and select VGA text mode
    ; while BIOS interrupts are still usable.
.flush_bios_keys:
    mov ah, 0x01
    int 0x16
    jz .keys_flushed
    xor ah, ah
    int 0x16
    jmp .flush_bios_keys
.keys_flushed:
    mov ax, 0x0003
    int 0x10
    mov ax, 0x1003
    xor bx, bx
    int 0x10
    call debug_build_fault_idts
    cmp byte [debug_mode_action], 2
    je .prepare_custom_paging
    ; A genuine #PF needs paging to be active. Build the same safe identity
    ; map used by Custom Program, then the trigger accesses the first absent
    ; PDE at 00400000h. Other fault buttons leave paging untouched.
    cmp byte [debug_mode_action], 1
    jne .custom_paging_ready
    cmp byte [debug_crash_code], 14
    jne .custom_paging_ready
    call debug_pm_prepare_custom_paging
    jmp short .custom_paging_ready
.prepare_custom_paging:
    mov eax, cr0
    mov [debug_lm_saved_cr0], eax
    mov eax, cr3
    mov [debug_lm_saved_cr3], eax
    mov eax, cr4
    mov [debug_lm_saved_cr4], eax
    call debug_pm_prepare_custom_paging
.custom_paging_ready:

    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    o32 sgdt [debug_pm_saved_gdtr]
    o32 sidt [debug_pm_saved_idtr]
    in al, 0x70
    mov [debug_pm_saved_cmos], al
    or al, 0x80
    out 0x70, al
    o32 lgdt [debug_pm_gdtr]
    o32 lidt [debug_pm_idtr32]
    ; Make the real-mode SS value a valid protected-mode data selector before
    ; setting CR0.PE.  Its hidden real-mode base still places SP at 00007B00h,
    ; closing the invalid-SS double/triple-fault window before the far jump.
    mov ax, DEBUG_PM_DATA32_SEL
    mov ss, ax
    mov sp, 0x7A00
    mov eax, cr0
    or eax, 0x00000001
    mov cr0, eax
    jmp dword DEBUG_PM_CODE32_SEL:debug_pm_entry32

BITS 32
debug_pm_entry32:
    mov ax, DEBUG_PM_DATA32_SEL
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax
    ; Use the free low-memory area immediately below the resident boot sector.
    ; The real-mode stack and its saved register frame remain untouched.
    mov esp, DEBUG_PM_PANIC_STACK_TOP
    cld
    cmp byte [debug_mode_action], 2
    je .custom_program
    cmp byte [debug_mode_action], 0
    je .mode_test
    ; The dedicated Double fault button requests vector 08h.  Generate a real
    ; architectural #DF instead of merely painting the vector number: make the
    ; #GP gate non-present, then provoke #GP with an invalid segment selector.
    ; The second contributory exception is combined by the CPU into #DF, whose
    ; still-valid vector-08 gate enters debug_pm_fault_stub_08.
    cmp byte [debug_crash_code], 8
    jne .direct_fault
    mov byte [DEBUG_PM_IDT32_PHYS + (13*8) + 5], 0
    mov ax, 0xFFFF
    mov ds, ax
    ; A conforming CPU never reaches this software fallback: #GP delivery
    ; through the non-present gate has already generated architectural #DF.
    int 8
.direct_fault:
    mov eax, (STAGE2_EXT_SEG << 4) + (debug_pm_trigger_fault32_ext-stage2_ext_start)
    jmp eax

.custom_program:
    ; An explicit RET returns here; normal fall-through uses the appended E9
    ; directly to the same exit label and does not depend on the payload stack.
    mov eax, [debug_lm_saved_cr4]
    and eax, 0xFFFFFFDF           ; legacy paging, never PAE
    mov cr4, eax
    mov eax, DEBUG_PM_PD_PHYS
    mov cr3, eax
    mov eax, cr0
    or eax, 0x80010000           ; CR0.PG | CR0.WP
    mov cr0, eax
    jmp short .paging_active
.paging_active:
    mov dl, [os_boot_drive]
    mov eax, CUSTOM_EXEC_LINEAR
    call eax
    jmp debug_pm_custom_return32

.mode_test:
    mov edi, 0x000B8000
    mov ax, 0xF020
    mov ecx, 80*25
    rep stosw

    mov esi, str_pm_line1
    mov edi, 0x000B8000 + ((10*80+29)*2)
    call debug_pm_puts_success32
    mov esi, str_pm_line2
    mov edi, 0x000B8000 + ((12*80+22)*2)
    call debug_pm_puts_success32

    ; Wait for a keyboard make code. Break codes and mouse packets do not
    ; dismiss the screen.
.wait_key:
    in al, 0x64
    test al, 0x01
    jz .wait_key
    mov ah, al
    in al, 0x60
    test ah, 0x20
    jnz .wait_key
    test al, 0x80
    jnz .wait_key

debug_pm_custom_return32:
    cli
    cmp byte [debug_mode_action], 2
    jne .paging_restored
    mov esp, DEBUG_PM_PANIC_STACK_TOP
    mov eax, cr0
    and eax, 0x7FFEFFFF           ; clear PG and WP on the identity map
    mov cr0, eax
    mov eax, [debug_lm_saved_cr4]
    mov cr4, eax
    mov eax, [debug_lm_saved_cr3]
    mov cr3, eax
    mov eax, [debug_lm_saved_cr0]
    or eax, 1                     ; keep PE until debug_pm_exit16
    mov cr0, eax
.paging_restored:
    jmp word DEBUG_PM_CODE16_SEL:(debug_pm_exit16-stage2_start)

debug_pm_puts32:
    lodsb
    test al, al
    jz .done
    mov ah, 0x1F
    stosw
    jmp debug_pm_puts32
.done:
    ret

debug_pm_puts_success32:
    lodsb
    test al, al
    jz .done
    mov ah, 0xF0
    stosw
    jmp debug_pm_puts_success32
.done:
    ret

%macro DEBUG_PM_FAULT_STUB 2
%1:
    mov ebp, %2
    jmp debug_pm_fault32
%endmacro

DEBUG_PM_FAULT_STUB debug_pm_fault_stub_00, 0
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_01, 1
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_02, 2
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_03, 3
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_04, 4
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_05, 5
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_06, 6
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_07, 7
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_08, 8
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_09, 9
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_10, 10
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_11, 11
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_12, 12
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_13, 13
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_14, 14
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_15, 15
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_16, 16
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_17, 17
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_18, 18
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_19, 19
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_20, 20
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_21, 21
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_22, 22
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_23, 23
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_24, 24
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_25, 25
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_26, 26
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_27, 27
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_28, 28
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_29, 29
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_30, 30
DEBUG_PM_FAULT_STUB debug_pm_fault_stub_31, 31

debug_pm_fault32:
    cli
    mov ax, DEBUG_PM_DATA32_SEL
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax
    mov esp, DEBUG_PM_PANIC_STACK_TOP
    cmp ebp, 14
    jne .fault_classified
    cmp byte [debug_mode_action], 2
    jne .fault_classified
    mov eax, cr2
    cmp eax, CUSTOM_PROTECT_LOW_END
    jb .critical_write
    cmp eax, CUSTOM_PROTECT_STAGE_START
    jb .fault_classified
    cmp eax, CUSTOM_PROTECT_STAGE_END
    jb .critical_write
    cmp eax, CUSTOM_PROTECT_STACK_START
    jb .fault_classified
    cmp eax, CUSTOM_PROTECT_STACK_END
    jae .fault_classified
.critical_write:
    mov ebp, BSOD_STOP_CRITICAL_WRITE
.fault_classified:
    cmp byte [BLUESCREEN_ENABLE_ADDR], 0
    je .disabled_halt
    cld
    ; BIOS mode 03h enables the CRTC text cursor.  A panic screen must never
    ; expose it, so hide it again with direct VGA I/O in protected mode.
    mov dx, 0x03D4
    mov al, 0x0A
    out dx, al
    inc dx
    in al, dx
    or al, 0x20
    out dx, al
    mov edx, ebp
    mov edi, 0x000B8000
    mov ax, 0x1F20
    mov ecx, 80*25
    rep stosw
    mov esi, system_panic_title
    mov edi, 0x000B8000 + ((0*80+25)*2)
    call debug_pm_puts32
    mov esi, system_panic_line1
    mov edi, 0x000B8000 + ((4*80+19)*2)
    call debug_pm_puts32
    mov esi, system_panic_line2
    mov edi, 0x000B8000 + ((6*80+26)*2)
    call debug_pm_puts32
    mov esi, system_panic_line3
    mov edi, 0x000B8000 + ((8*80+22)*2)
    call debug_pm_puts32
    cmp byte [boot_autorestart], 0
    je .automatic_line_done
    mov esi, system_panic_line4
    mov edi, 0x000B8000 + ((10*80+21)*2)
    call debug_pm_puts32
.automatic_line_done:

    mov edi, 0x000B8000 + ((21*80+2)*2)
    cmp dl, 32
    jae .internal_reason
    mov esi, system_panic_pm_prefix
    call debug_pm_puts32
    mov eax, edx
    call debug_pm_hex_byte32
    cmp dl, 16
    jae .stopcode
    mov al, ' '
    mov ah, 0x1F
    stosw
    movzx ebx, dl
    movzx esi, word [system_exception_name_table+ebx*2]
    call debug_pm_puts32
    jmp .stopcode

.internal_reason:
    cmp dl, BSOD_STOP_NOTEPAD
    jne .check_tables
    mov esi, system_panic_notepad_reason
    jmp .put_internal
.check_tables:
    cmp dl, BSOD_STOP_TABLES
    jne .check_watchdog
    mov esi, system_panic_tables_reason
    jmp .put_internal
.check_watchdog:
    cmp dl, BSOD_STOP_WATCHDOG
    jne .check_reboot
    mov esi, system_panic_watchdog_reason
    jmp .put_internal
.check_reboot:
    cmp dl, BSOD_STOP_REBOOT
    jne .check_manual
    mov esi, system_panic_reboot_reason
    jmp .put_internal
.check_manual:
    cmp dl, BSOD_STOP_MANUAL
    jne .check_critical_write
    mov esi, system_panic_manual_reason
    jmp .put_internal
.check_critical_write:
    cmp dl, BSOD_STOP_CRITICAL_WRITE
    jne .generic_internal
    mov esi, system_panic_critical_write_reason
    jmp .put_internal
.generic_internal:
    mov esi, system_panic_internal_reason
.put_internal:
    call debug_pm_puts32

.stopcode:
    mov edi, 0x000B8000 + ((23*80+2)*2)
    mov esi, system_panic_stopcode_prefix
    call debug_pm_puts32
    mov eax, edx
    call debug_pm_hex_byte32
    xor esi, esi
    cmp byte [boot_autorestart], 0
    je short .wait_for_reset
    inc esi
    jmp short .wait_for_reset
.disabled_halt:
    xor esi, esi
.wait_for_reset:
    call debug_pm_lm_bsod_wait
    jmp debug_pm_bsod_hard_reset32

debug_pm_bsod_hard_reset32:
    cli
    mov dx, 0x0CF9
    mov al, 0x06
    out dx, al
    mov dx, 0x0064
    mov al, 0xFE
    out dx, al
    lidt [system_reset_null_idtr]
    int 3
.reset_pending:
    hlt
    jmp short .reset_pending

; This polling core deliberately uses only encodings whose behavior is
; identical in 32-bit protected mode and 64-bit long mode.  Sharing it avoids
; duplicating the countdown and scan-set parser inside the 64-KiB base image.
; ESI is nonzero when the countdown line is visible. It returns only when the
; timer expires or Ctrl+Alt+Del is recognized.
debug_pm_lm_bsod_wait:
    cli
    xor ebx, ebx
    mov cl, 15
    xor ebp, ebp
    mov al, 0x80
    out 0x70, al
    in al, 0x71
    mov ch, al
    mov edi, 0x00000417
    mov al, [edi]
    test al, 0x04
    jz .seed_alt
    or bl, 0x01
.seed_alt:
    test al, 0x08
    jz .poll
    or bl, 0x02
.poll:
    ; ADD is used instead of the one-byte 32-bit INC opcode, because 40h..4Fh
    ; are REX prefixes when these same bytes execute in long mode.
    add ebp, 1
    test ebp, 0x000003FF
    jnz .keyboard
    mov al, 0x80
    out 0x70, al
    in al, 0x71
    cmp al, ch
    je .keyboard
    mov ch, al
    test esi, esi
    jz .keyboard
    dec cl
    mov al, cl
    xor ah, ah
    mov dl, 10
    div dl
    mov dl, ah
    test al, al
    jnz .tens
    mov al, ' '
    jmp short .put_tens
.tens:
    add al, '0'
.put_tens:
    mov ah, 0x1F
    mov edi, 0x000B8000 + ((10*80+47)*2)
    stosw
    mov al, dl
    add al, '0'
    mov ah, 0x1F
    stosw
.count_ready:
    test cl, cl
    jz .reset
.keyboard:
    mov dx, 0x0064
    in al, dx
    test al, 0x01
    jz .poll
    mov ah, al
    mov dx, 0x0060
    in al, dx
    test ah, 0x20
    jnz .clear_prefix
    cmp al, 0xE0
    je .e0_prefix
    cmp al, 0xF0
    je .f0_prefix
    cmp al, 0x1D
    je .ctrl_set1_make
    cmp al, 0x9D
    je .ctrl_set1_break
    cmp al, 0x38
    je .alt_set1_make
    cmp al, 0xB8
    je .alt_set1_break
    cmp al, 0x14
    je .ctrl_set2
    cmp al, 0x11
    je .alt_set2
    cmp al, 0x53
    je .delete_set1
    cmp al, 0x71
    jne .clear_prefix
    test bh, 0x01
    jz .clear_prefix
    test bh, 0x02
    jnz .clear_prefix
    jmp short .check_reset
.delete_set1:
    test bh, 0x02
    jnz .clear_prefix
.check_reset:
    mov edi, 0x00000417
    mov al, [edi]
    test al, 0x04
    jz .check_bda_alt
    or bl, 0x01
.check_bda_alt:
    test al, 0x08
    jz .test_chord
    or bl, 0x02
.test_chord:
    mov al, bl
    and al, 0x03
    cmp al, 0x03
    je .reset
.clear_prefix:
    xor bh, bh
    jmp .poll
.e0_prefix:
    or bh, 0x01
    jmp .poll
.f0_prefix:
    or bh, 0x02
    jmp .poll
.ctrl_set1_make:
    or bl, 0x01
    jmp .clear_prefix
.ctrl_set1_break:
    and bl, 0xFE
    jmp .clear_prefix
.alt_set1_make:
    or bl, 0x02
    jmp .clear_prefix
.alt_set1_break:
    and bl, 0xFD
    jmp .clear_prefix
.ctrl_set2:
    test bh, 0x02
    jnz .ctrl_set1_break
    jmp short .ctrl_set1_make
.alt_set2:
    test bh, 0x02
    jnz .alt_set1_break
    jmp short .alt_set1_make
.reset:
    ret

debug_pm_hex_byte32:
    push eax
    push edx
    mov dl, al
    shr al, 4
    call debug_pm_hex_nibble32
    mov al, dl
    and al, 0x0F
    call debug_pm_hex_nibble32
    pop edx
    pop eax
    ret

debug_pm_hex_nibble32:
    cmp al, 10
    jb .digit
    add al, 'A'-10
    jmp short .emit
.digit:
    add al, '0'
.emit:
    mov ah, 0x1F
    stosw
    ret

BITS 16
debug_pm_exit16:
    mov eax, cr0
    and eax, 0xFFFFFFFE
    mov cr0, eax
    jmp STAGE2_SEG:(debug_pm_real_return-stage2_start)

debug_pm_real_return:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    o32 lgdt [debug_pm_saved_gdtr]
    o32 lidt [debug_pm_saved_idtr]
    mov al, [debug_pm_saved_cmos]
    out 0x70, al
    mov ax, [debug_pm_saved_ss]
    mov ss, ax
    mov sp, [debug_pm_saved_sp]

    pop gs
    pop fs
    pop es
    pop ds
    popa
    popf

    ; Recreate mode 13h and the active mouse backend without resetting any
    ; windows or application data, then redraw the same MiniWin screen.
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    call init_font_and_video
    call init_mouse_support
    mov byte [mouse_buttons], 0
    mov byte [mouse_raw_buttons], 0
    mov byte [mouse_prev_buttons], 0
    mov byte [mouse_changed], 0
    mov byte [cursor_visible], 0
    mov byte [vm_abs_valid], 0
    sti
    ; A Custom Program has overwritten its editor overlay. Its caller reloads
    ; that overlay and redraws the editor immediately after this return. Do not
    ; first draw Program Manager or save its pixels under the mouse cursor:
    ; that stale cursor background would be restored on the first mouse move.
    cmp byte [debug_mode_action], 2
    je .done
    call redraw_all
    call mouse_cursor_show
.done:
    ret

; Return CF=0 only when CPUID, MSR, PAE, and the architectural Long Mode bit
; are all present.  On failure debug_lm_fail_reason is suitable for a GUI
; MessageBox instead of risking an invalid-opcode or triple-fault reset.
debug_cpu_supports_long_mode:
    call STAGE2_EXT_SEG:(debug_cpu_supports_long_mode_ext-stage2_ext_start)
    ret

debug_show_long_mode_failure:
    mov byte [debug_result_success], 0
    mov word [debug_result_line1_ptr], str_lm_not_supported
    mov si, str_lm_no_x64
    cmp byte [debug_lm_fail_reason], 1
    jne .not_cpuid
    mov si, str_lm_no_cpuid
    jmp short .reason_ready
.not_cpuid:
    cmp byte [debug_lm_fail_reason], 3
    jne .reason_ready
    mov si, str_lm_no_pae_msr
.reason_ready:
    mov [debug_result_line2_ptr], si
    mov byte [message_kind], MSG_LONG_RESULT
    mov byte [message_open], 1
    call redraw_all
    ret

debug_lm_mark_custom_pages_readonly:
    call STAGE2_EXT_SEG:(debug_lm_mark_custom_pages_readonly_ext-stage2_ext_start)
    ret

; Build an identity map for the first 2 MiB.  The tables live in otherwise
; unused low memory, below the boot sector and the program's 0600h I/O buffer.
debug_lm_prepare_tables:
    push eax
    push ebx
    push cx
    push di
    push es
    cld
    call debug_build_fault_idts

    mov ax, DEBUG_LM_PML4_PHYS >> 4
    call .clear_table
    mov ax, DEBUG_LM_PDPT_PHYS >> 4
    call .clear_table
    mov ax, DEBUG_LM_PD_PHYS >> 4
    call .clear_table

    mov ax, DEBUG_LM_PML4_PHYS >> 4
    mov es, ax
    mov dword es:[0], DEBUG_LM_PDPT_PHYS | 0x00000003
    mov dword es:[4], 0

    mov ax, DEBUG_LM_PDPT_PHYS >> 4
    mov es, ax
    mov dword es:[0], DEBUG_LM_PD_PHYS | 0x00000003
    mov dword es:[4], 0

    mov ax, DEBUG_LM_PD_PHYS >> 4
    mov es, ax
    mov dword es:[0], DEBUG_LM_PT_PHYS | 0x00000003
    mov dword es:[4], 0

    mov ax, DEBUG_LM_PT_PHYS >> 4
    mov es, ax
    xor di, di
    xor ebx, ebx
    mov cx, 512
.identity:
    mov eax, ebx
    or eax, 0x00000003
    stosd
    xor eax, eax
    stosd
    add ebx, 0x1000
    loop .identity
    cmp byte [debug_mode_action], 2
    jne .page_permissions_ready
    call debug_lm_mark_custom_pages_readonly
.page_permissions_ready:

    ; Build and clear a minimal 32-bit TSS.  Some BIOS implementations leave
    ; TR referring to a 16-bit TSS; Intel defines that as a #GP condition when
    ; IA-32e mode is activated.  LTR in the protected-mode entry below replaces
    ; that stale task-register state before paging is enabled.
    xor ax, ax
    mov es, ax
    mov di, debug_lm_tss
    xor eax, eax
    mov cx, 26
    rep stosd
    mov dword [debug_lm_tss + 36], DEBUG_LM_IST_TOP
    mov dword [debug_lm_tss + 40], 0
    mov word [debug_lm_tss + 102], 104
    mov word [debug_pm_gdt + DEBUG_PM_TSS_SEL + 0], 103
    mov eax, debug_lm_tss
    mov word [debug_pm_gdt + DEBUG_PM_TSS_SEL + 2], ax
    shr eax, 16
    mov byte [debug_pm_gdt + DEBUG_PM_TSS_SEL + 4], al
    mov byte [debug_pm_gdt + DEBUG_PM_TSS_SEL + 5], 0x89
    mov byte [debug_pm_gdt + DEBUG_PM_TSS_SEL + 6], 0x00
    mov byte [debug_pm_gdt + DEBUG_PM_TSS_SEL + 7], ah

    pop es
    pop di
    pop cx
    pop ebx
    pop eax
    ret
.clear_table:
    mov es, ax
    xor di, di
    xor eax, eax
    mov cx, 1024
    rep stosd
    ret

; Enter IA-32e Long Mode, print a confirmation directly to VGA text memory,
; wait for a real keyboard make code, and return through compatibility mode.
; CPU capability is checked by the caller before this routine is entered.
debug_enter_long_mode:
    pushf
    pusha
    push ds
    push es
    push fs
    push gs

    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ax, ss
    mov [debug_pm_saved_ss], ax
    mov [debug_pm_saved_sp], sp

    cmp byte [mouse_mode], 0
    jne .mouse_quiet
    call mouse_ps2_disable_stream
.mouse_quiet:
.flush_bios_keys:
    mov ah, 0x01
    int 0x16
    jz .keys_flushed
    xor ah, ah
    int 0x16
    jmp .flush_bios_keys
.keys_flushed:
    mov ax, 0x0003
    int 0x10
    mov ax, 0x1003
    xor bx, bx
    int 0x10
    call debug_lm_prepare_tables

    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    o32 sgdt [debug_pm_saved_gdtr]
    o32 sidt [debug_pm_saved_idtr]
    in al, 0x70
    mov [debug_pm_saved_cmos], al
    or al, 0x80
    out 0x70, al
    mov eax, cr0
    mov [debug_lm_saved_cr0], eax
    mov eax, cr3
    mov [debug_lm_saved_cr3], eax
    mov eax, cr4
    mov [debug_lm_saved_cr4], eax
    o32 lgdt [debug_pm_gdtr]
    o32 lidt [debug_pm_idtr32]
    ; Keep a valid selector and emergency linear stack throughout the
    ; CR0.PE-to-far-jump interval, just as in the 32-bit test path.
    mov ax, DEBUG_PM_DATA32_SEL
    mov ss, ax
    mov sp, DEBUG_LM_STACK_TOP - (DEBUG_PM_DATA32_SEL << 4)
    mov eax, cr0
    or eax, 0x00000001
    mov cr0, eax
    jmp dword DEBUG_PM_CODE32_SEL:debug_lm_entry32

BITS 32
debug_lm_entry32:
    mov ax, DEBUG_PM_DATA32_SEL
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax
    mov esp, DEBUG_LM_STACK_TOP

    mov ax, DEBUG_PM_TSS_SEL
    ltr ax

    ; CR3 must be loaded only after CR4.PAE is active.  Otherwise some CPUs
    ; keep legacy paging semantics (or stale PDPTE state) and enabling PG
    ; below can triple-fault at the very first Long Mode transition.
    mov eax, cr4
    and eax, 0xFFFDEFFF           ; force 4-level paging: clear LA57/PCIDE
    or eax, (1 << 5)               ; CR4.PAE
    mov cr4, eax
    mov eax, DEBUG_LM_PML4_PHYS
    mov cr3, eax
    mov ecx, 0xC0000080            ; IA32_EFER
    rdmsr
    mov [debug_lm_saved_efer_lo], eax
    mov [debug_lm_saved_efer_hi], edx
    or eax, (1 << 8)               ; EFER.LME
    wrmsr
    mov eax, cr0
    or eax, 0x80000000             ; CR0.PG
    cmp byte [debug_mode_action], 2
    jne .wp_ready
    or eax, 0x00010000             ; CR0.WP: CPL0 obeys read-only PTEs
.wp_ready:
    mov cr0, eax
    jmp dword DEBUG_LM_CODE64_SEL:debug_lm_entry64

BITS 64
debug_lm_entry64:
    mov ax, DEBUG_PM_DATA32_SEL
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax
    mov rsp, DEBUG_LM_STACK_TOP
    cld
    lidt [abs debug_lm_idtr64]
    cmp byte [debug_mode_action], 2
    je .custom_program
    cmp byte [debug_mode_action], 0
    je .mode_test
    movzx ebp, byte [debug_crash_code]
    jmp debug_lm_fault64

.custom_program:
    ; The first 2 MiB are identity mapped, so the same 60000h payload address
    ; is directly executable in Long Mode.
    mov dl, [os_boot_drive]
    mov eax, CUSTOM_EXEC_LINEAR
    call rax
    jmp debug_lm_custom_return64

.mode_test:
    mov edi, 0x000B8000
    mov ax, 0xF020
    mov ecx, 80*25
    rep stosw

    mov esi, str_lm_line1
    mov edi, 0x000B8000 + ((10*80+31)*2)
    call debug_lm_puts_success64
    mov esi, str_lm_line2
    mov edi, 0x000B8000 + ((12*80+22)*2)
    call debug_lm_puts_success64

.wait_key:
    in al, 0x64
    test al, 0x01
    jz .wait_key
    mov ah, al
    in al, 0x60
    test ah, 0x20
    jnz .wait_key
    test al, 0x80
    jnz .wait_key

debug_lm_custom_return64:
    ; A fall-through E9 can arrive after arbitrary stack use. Re-establish the
    ; private LM stack before the compatibility-mode far return.
    mov rsp, DEBUG_LM_STACK_TOP
    cli
    push qword DEBUG_PM_CODE32_SEL
    mov eax, debug_lm_exit32
    push rax
    retfq

debug_lm_puts64:
    lodsb
    test al, al
    jz .done
    mov ah, 0x1F
    stosw
    jmp debug_lm_puts64
.done:
    ret

debug_lm_puts_success64:
    lodsb
    test al, al
    jz .done
    mov ah, 0xF0
    stosw
    jmp debug_lm_puts_success64
.done:
    ret

%macro DEBUG_LM_FAULT_STUB 2
%1:
    mov ebp, %2
    jmp debug_lm_fault64
%endmacro

DEBUG_LM_FAULT_STUB debug_lm_fault_stub_00, 0
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_01, 1
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_02, 2
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_03, 3
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_04, 4
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_05, 5
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_06, 6
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_07, 7
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_08, 8
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_09, 9
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_10, 10
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_11, 11
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_12, 12
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_13, 13
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_14, 14
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_15, 15
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_16, 16
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_17, 17
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_18, 18
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_19, 19
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_20, 20
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_21, 21
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_22, 22
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_23, 23
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_24, 24
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_25, 25
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_26, 26
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_27, 27
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_28, 28
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_29, 29
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_30, 30
DEBUG_LM_FAULT_STUB debug_lm_fault_stub_31, 31

debug_lm_fault64:
    cli
    mov rsp, DEBUG_LM_IST_TOP
    mov ax, DEBUG_PM_DATA32_SEL
    mov ds, ax
    mov es, ax
    mov ss, ax
    cmp ebp, 14
    jne .fault_classified
    cmp byte [debug_mode_action], 2
    jne .fault_classified
    mov rax, cr2
    cmp rax, CUSTOM_PROTECT_LOW_END
    jb .critical_write
    cmp rax, CUSTOM_PROTECT_STAGE_START
    jb .fault_classified
    cmp rax, CUSTOM_PROTECT_STAGE_END
    jb .critical_write
    cmp rax, CUSTOM_PROTECT_STACK_START
    jb .fault_classified
    cmp rax, CUSTOM_PROTECT_STACK_END
    jae .fault_classified
.critical_write:
    mov ebp, BSOD_STOP_CRITICAL_WRITE
.fault_classified:
    cmp byte [BLUESCREEN_ENABLE_ADDR], 0
    je .disabled_halt
    cld
    ; The mode-set path left the hardware text cursor enabled.  Hide it
    ; directly; no firmware service is safe in a long-mode fault handler.
    mov dx, 0x03D4
    mov al, 0x0A
    out dx, al
    inc dx
    in al, dx
    or al, 0x20
    out dx, al
    mov edx, ebp
    mov edi, 0x000B8000
    mov ax, 0x1F20
    mov ecx, 80*25
    rep stosw
    mov esi, system_panic_title
    mov edi, 0x000B8000 + ((0*80+25)*2)
    call debug_lm_puts64
    mov esi, system_panic_line1
    mov edi, 0x000B8000 + ((4*80+19)*2)
    call debug_lm_puts64
    mov esi, system_panic_line2
    mov edi, 0x000B8000 + ((6*80+26)*2)
    call debug_lm_puts64
    mov esi, system_panic_line3
    mov edi, 0x000B8000 + ((8*80+22)*2)
    call debug_lm_puts64
    cmp byte [boot_autorestart], 0
    je .automatic_line_done
    mov esi, system_panic_line4
    mov edi, 0x000B8000 + ((10*80+21)*2)
    call debug_lm_puts64
.automatic_line_done:

    mov edi, 0x000B8000 + ((21*80+2)*2)
    cmp dl, 32
    jae .internal_reason
    mov esi, system_panic_lm_prefix
    call debug_lm_puts64
    mov eax, edx
    call debug_lm_hex_byte64
    cmp dl, 16
    jae .stopcode
    mov al, ' '
    mov ah, 0x1F
    stosw
    movzx ebx, dl
    movzx esi, word [system_exception_name_table+rbx*2]
    call debug_lm_puts64
    jmp .stopcode

.internal_reason:
    cmp dl, BSOD_STOP_NOTEPAD
    jne .check_tables
    mov esi, system_panic_notepad_reason
    jmp .put_internal
.check_tables:
    cmp dl, BSOD_STOP_TABLES
    jne .check_watchdog
    mov esi, system_panic_tables_reason
    jmp .put_internal
.check_watchdog:
    cmp dl, BSOD_STOP_WATCHDOG
    jne .check_reboot
    mov esi, system_panic_watchdog_reason
    jmp .put_internal
.check_reboot:
    cmp dl, BSOD_STOP_REBOOT
    jne .check_manual
    mov esi, system_panic_reboot_reason
    jmp .put_internal
.check_manual:
    cmp dl, BSOD_STOP_MANUAL
    jne .check_critical_write
    mov esi, system_panic_manual_reason
    jmp .put_internal
.check_critical_write:
    cmp dl, BSOD_STOP_CRITICAL_WRITE
    jne .generic_internal
    mov esi, system_panic_critical_write_reason
    jmp .put_internal
.generic_internal:
    mov esi, system_panic_internal_reason
.put_internal:
    call debug_lm_puts64

.stopcode:
    mov edi, 0x000B8000 + ((23*80+2)*2)
    mov esi, system_panic_stopcode_prefix
    call debug_lm_puts64
    mov eax, edx
    call debug_lm_hex_byte64
    xor esi, esi
    cmp byte [boot_autorestart], 0
    je short .wait_for_reset
    inc esi
    jmp short .wait_for_reset
.disabled_halt:
    xor esi, esi
.wait_for_reset:
    ; debug_pm_lm_bsod_wait was encoded in the 32-bit section using only
    ; instructions with identical long-mode encodings and register addressing.
    call debug_pm_lm_bsod_wait
    jmp debug_lm_bsod_hard_reset64

debug_lm_bsod_hard_reset64:
    cli
    mov dx, 0x0CF9
    mov al, 0x06
    out dx, al
    mov dx, 0x0064
    mov al, 0xFE
    out dx, al
    lidt [system_reset_null_idtr]
    int 3
.reset_pending:
    hlt
    jmp short .reset_pending

debug_lm_hex_byte64:
    push rax
    push rdx
    mov dl, al
    shr al, 4
    call debug_lm_hex_nibble64
    mov al, dl
    and al, 0x0F
    call debug_lm_hex_nibble64
    pop rdx
    pop rax
    ret

debug_lm_hex_nibble64:
    cmp al, 10
    jb .digit
    add al, 'A'-10
    jmp short .emit
.digit:
    add al, '0'
.emit:
    mov ah, 0x1F
    stosw
    ret

BITS 32
debug_lm_exit32:
    mov eax, cr0
    and eax, 0x7FFFFFFF
    mov cr0, eax
    mov ecx, 0xC0000080
    mov eax, [debug_lm_saved_efer_lo]
    mov edx, [debug_lm_saved_efer_hi]
    wrmsr
    ; Restore the original paging mode before CR3.  Loading a legacy CR3
    ; while PAE is still set can make the CPU validate arbitrary memory as
    ; PDPTEs and fault during the return to Real Mode.
    mov eax, [debug_lm_saved_cr4]
    mov cr4, eax
    mov eax, [debug_lm_saved_cr3]
    mov cr3, eax
    jmp word DEBUG_PM_CODE16_SEL:(debug_lm_exit16-stage2_start)

BITS 16
debug_lm_exit16:
    mov eax, [debug_lm_saved_cr0]
    mov cr0, eax
    jmp STAGE2_SEG:(debug_pm_real_return-stage2_start)

handle_debug_mouse_down:
    mov byte [active_pid], WIN_MAIN
    mov byte [active_type], APP_NONE
    mov word [active_data_seg], 0
    cmp byte [debug_open], 4
    je .blue_window
    cmp byte [debug_open], 5
    je .fault_window
    cmp byte [debug_open], 6
    je .normal_window
    cmp byte [debug_open], 2
    jae .int_window

    mov ax, DEBUG_MAIN_X+DEBUG_MAIN_W-21
    mov bx, DEBUG_MAIN_Y+6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_close
    mov di, BTN_DEBUG_CLOSE
    call try_capture_button
    jc .done
    mov ax, DEBUG_MAIN_X+21
    mov bx, DEBUG_MAIN_Y+39
    mov cx, DEBUG_MAIN_W-42
    mov dx, 15
    mov si, str_bluescreen
    mov di, BTN_DEBUG_BLUE
    call try_capture_button
    jc .done
    mov ax, DEBUG_MAIN_X+21
    mov bx, DEBUG_MAIN_Y+57
    mov cx, DEBUG_MAIN_W-42
    mov dx, 15
    mov si, str_fault
    mov di, BTN_DEBUG_FAULT
    call try_capture_button
    jc .done
    mov ax, DEBUG_MAIN_X+21
    mov bx, DEBUG_MAIN_Y+75
    mov cx, DEBUG_MAIN_W-42
    mov dx, 15
    mov si, str_int_test
    mov di, BTN_DEBUG_INT_TEST
    call try_capture_button
    jc .done
    mov ax, DEBUG_MAIN_X+21
    mov bx, DEBUG_MAIN_Y+93
    mov cx, DEBUG_MAIN_W-42
    mov dx, 15
    mov si, str_int_execute
    mov di, BTN_DEBUG_INT_EXEC
    call try_capture_button
    jc .done
    mov ax, DEBUG_MAIN_X+21
    mov bx, DEBUG_MAIN_Y+111
    mov cx, DEBUG_MAIN_W-42
    mov dx, 15
    mov si, str_go_protected
    mov di, BTN_DEBUG_PROTECTED
    call try_capture_button
    jc .done
    mov ax, DEBUG_MAIN_X+21
    mov bx, DEBUG_MAIN_Y+129
    mov cx, DEBUG_MAIN_W-42
    mov dx, 15
    mov si, str_go_long
    mov di, BTN_DEBUG_LONG
    call try_capture_button
    jc .done
    mov ax, DEBUG_MAIN_X+21
    mov bx, DEBUG_MAIN_Y+147
    mov cx, DEBUG_MAIN_W-42
    mov dx, 15
    mov si, str_disable_bluescreen
    cmp byte [BLUESCREEN_ENABLE_ADDR], 0
    jne .blue_toggle_label_ready
    mov si, str_enable_bluescreen
.blue_toggle_label_ready:
    mov di, BTN_DEBUG_BLUE_TOGGLE
    call try_capture_button
    ret

.fault_window:
    mov ax, DEBUG_FAULT_X+DEBUG_FAULT_W-21
    mov bx, DEBUG_FAULT_Y+6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_close
    mov di, BTN_DEBUG_FAULT_CLOSE
    call try_capture_button
    jc .done

    mov ax, DEBUG_FAULT_X+12
    mov bx, DEBUG_FAULT_Y+31
    mov cx, DEBUG_FAULT_W-24
    mov dx, 24
    mov si, str_normal_fault
    mov di, BTN_DEBUG_FAULT_NORMAL
    call try_capture_button
    jc .done

    mov ax, DEBUG_FAULT_X+12
    mov bx, DEBUG_FAULT_Y+61
    mov cx, DEBUG_FAULT_W-24
    mov dx, 24
    mov si, str_double_fault
    mov di, BTN_DEBUG_FAULT_DOUBLE
    call try_capture_button
    jc .done

    mov ax, DEBUG_FAULT_X+12
    mov bx, DEBUG_FAULT_Y+91
    mov cx, DEBUG_FAULT_W-24
    mov dx, 24
    mov si, str_triple_fault
    mov di, BTN_DEBUG_FAULT_TRIPLE
    call try_capture_button
    ret

.normal_window:
    mov ax, DEBUG_INT_X+DEBUG_INT_W-21
    mov bx, DEBUG_INT_Y+6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_close
    mov di, BTN_DEBUG_NORMAL_CLOSE
    call try_capture_button
    jc .done

    mov ax, DEBUG_INT_X+DEBUG_SCROLL_XOFF
    mov bx, DEBUG_INT_Y+DEBUG_SCROLL_UP_YOFF
    mov cx, 16
    mov dx, 14
    mov si, str_scroll_up
    mov di, BTN_DEBUG_NORMAL_SCROLL_UP
    call try_capture_button
    jc .done
    mov ax, DEBUG_INT_X+DEBUG_SCROLL_XOFF
    mov bx, DEBUG_INT_Y+DEBUG_SCROLL_DOWN_YOFF
    mov cx, 16
    mov dx, 14
    mov si, str_scroll_down
    mov di, BTN_DEBUG_NORMAL_SCROLL_DOWN
    call try_capture_button
    jc .done

    push bp
    xor bp, bp
    mov word [debug_list_button_y], DEBUG_INT_Y+DEBUG_INT_ITEM_YOFF
.normal_item_loop:
    cmp bp, DEBUG_INT_VISIBLE
    jae .normal_items_done
    mov ax, [debug_scroll_offset]
    add ax, bp
    cmp ax, DEBUG_NORMAL_COUNT
    jae .normal_items_done
    mov [debug_pending_fault], al
    call debug_fault_get_label
    mov ax, DEBUG_INT_X+DEBUG_INT_ITEM_XOFF
    mov bx, [debug_list_button_y]
    mov cx, DEBUG_INT_ITEM_W
    mov dx, DEBUG_INT_ITEM_H
    mov di, BTN_DEBUG_NORMAL_ITEM
    call try_capture_button
    jc .normal_item_captured
    add word [debug_list_button_y], DEBUG_INT_ITEM_STEP
    inc bp
    jmp .normal_item_loop
.normal_item_captured:
    pop bp
    ret
.normal_items_done:
    pop bp
    jmp .scrollbar_hit_test

.blue_window:
    mov ax, DEBUG_BLUE_X+DEBUG_BLUE_W-21
    mov bx, DEBUG_BLUE_Y+6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_close
    mov di, BTN_DEBUG_BLUE_CLOSE
    call try_capture_button
    jc .done

    mov ax, DEBUG_BLUE_X+12
    mov bx, DEBUG_BLUE_Y+31
    mov cx, DEBUG_BLUE_W-24
    mov dx, 24
    mov si, str_bluescreen_real
    mov di, BTN_DEBUG_BLUE_REAL
    call try_capture_button
    jc .done

    mov ax, DEBUG_BLUE_X+12
    mov bx, DEBUG_BLUE_Y+61
    mov cx, DEBUG_BLUE_W-24
    mov dx, 24
    mov si, str_bluescreen_pm
    mov di, BTN_DEBUG_BLUE_PM
    call try_capture_button
    jc .done

    mov ax, DEBUG_BLUE_X+12
    mov bx, DEBUG_BLUE_Y+91
    mov cx, DEBUG_BLUE_W-24
    mov dx, 24
    mov si, str_bluescreen_lm
    mov di, BTN_DEBUG_BLUE_LM
    call try_capture_button
    ret

.int_window:
    mov ax, DEBUG_INT_X+DEBUG_INT_W-21
    mov bx, DEBUG_INT_Y+6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_close
    mov di, BTN_DEBUG_INT_CLOSE
    call try_capture_button
    jc .done

    mov ax, DEBUG_INT_X+DEBUG_SCROLL_XOFF
    mov bx, DEBUG_INT_Y+DEBUG_SCROLL_UP_YOFF
    mov cx, 16
    mov dx, 14
    mov si, str_scroll_up
    mov di, BTN_DEBUG_SCROLL_UP
    call try_capture_button
    jc .done
    mov ax, DEBUG_INT_X+DEBUG_SCROLL_XOFF
    mov bx, DEBUG_INT_Y+DEBUG_SCROLL_DOWN_YOFF
    mov cx, 16
    mov dx, 14
    mov si, str_scroll_down
    mov di, BTN_DEBUG_SCROLL_DOWN
    call try_capture_button
    jc .done

    push bp
    xor bp, bp
    mov word [debug_list_button_y], DEBUG_INT_Y+DEBUG_INT_ITEM_YOFF
.item_loop:
    cmp bp, DEBUG_INT_VISIBLE
    jae .items_done
    mov ax, [debug_scroll_offset]
    add ax, bp
    cmp ax, 256
    jae .items_done
    mov [debug_pending_int], al
    call debug_build_int_label
    mov ax, DEBUG_INT_X+DEBUG_INT_ITEM_XOFF
    mov bx, [debug_list_button_y]
    mov cx, DEBUG_INT_ITEM_W
    mov dx, DEBUG_INT_ITEM_H
    mov si, debug_int_label_buf
    mov di, BTN_DEBUG_INT_ITEM
    call try_capture_button
    jc .item_captured
    add word [debug_list_button_y], DEBUG_INT_ITEM_STEP
    inc bp
    jmp .item_loop
.item_captured:
    pop bp
    ret
.items_done:
    pop bp

.scrollbar_hit_test:
    call debug_compute_scroll_thumb
    mov cx, DEBUG_INT_X+DEBUG_SCROLL_XOFF+2
    mov dx, [debug_scroll_thumb_y]
    mov si, 12
    mov di, DEBUG_SCROLL_THUMB_H
    call hit_rect
    jnc .track
    mov byte [debug_scroll_drag], 1
    mov ax, [mouse_y]
    sub ax, [debug_scroll_thumb_y]
    mov [debug_scroll_drag_dy], ax
    ret
.track:
    mov cx, DEBUG_INT_X+DEBUG_SCROLL_XOFF
    mov dx, DEBUG_INT_Y+DEBUG_SCROLL_TRACK_YOFF
    mov si, 16
    mov di, DEBUG_SCROLL_TRACK_H
    call hit_rect
    jnc .done
    mov ax, [mouse_y]
    cmp ax, [debug_scroll_thumb_y]
    jb .page_up
    call debug_scroll_page_down
    ret
.page_up:
    call debug_scroll_page_up
.done:
    ret

update_debug_scroll_drag:
    push ax
    push bx
    push dx
    mov ax, [mouse_y]
    sub ax, DEBUG_INT_Y+DEBUG_SCROLL_TRACK_YOFF
    sub ax, [debug_scroll_drag_dy]
    jns .nonnegative
    xor ax, ax
.nonnegative:
    cmp ax, DEBUG_SCROLL_TRAVEL
    jbe .position_ready
    mov ax, DEBUG_SCROLL_TRAVEL
.position_ready:
    call debug_get_scroll_max
    mul bx
    mov bx, DEBUG_SCROLL_TRAVEL
    xor dx, dx
    div bx
    cmp ax, [debug_scroll_offset]
    je .done
    mov [debug_scroll_offset], ax
    call redraw_all
.done:
    pop dx
    pop bx
    pop ax
    ret

draw_messagebox:
    call STAGE2_EXT_SEG:(draw_messagebox_ext-stage2_ext_start)
    ret

canvas_clear_memory:
    push ax
    push cx
    push di
    push es
    mov ax, [active_data_seg]
    mov es, ax
    xor di, di
    mov al, COL_WHITE
    mov cx, PAINT_CANVAS_STORAGE_SIZE
    rep stosb
    pop es
    pop di
    pop cx
    pop ax
    ret

canvas_backup_memory:
    ; Paint undo has a dedicated segment so text/bitmap clipboard contents are
    ; never destroyed merely by selecting or editing the canvas.
    push ax
    push cx
    push si
    push di
    push es
    push fs
    mov ax, [active_data_seg]
    mov fs, ax
    mov ax, UNDO_SEG
    mov es, ax
    xor si, si
    xor di, di
    mov cx, PAINT_CANVAS_STORAGE_SIZE
.copy:
    mov al, fs:[si]
    mov es:[di], al
    inc si
    inc di
    loop .copy
    mov byte [undo_available], 1
    mov al, [active_pid]
    mov [paint_undo_pid], al
    call mark_active_dirty
    pop fs
    pop es
    pop di
    pop si
    pop cx
    pop ax
    ret

canvas_swap_undo:
    cmp byte [undo_available], 0
    je .done
    mov al, [active_pid]
    cmp al, [paint_undo_pid]
    jne .done
    push ax
    push bx
    push cx
    push si
    push di
    push es
    push fs
    mov ax, [active_data_seg]
    mov fs, ax
    mov ax, UNDO_SEG
    mov es, ax
    xor si, si
    xor di, di
    mov cx, PAINT_CANVAS_STORAGE_SIZE
.swap:
    mov al, fs:[si]
    mov bl, es:[di]
    mov fs:[si], bl
    mov es:[di], al
    inc si
    inc di
    loop .swap
    pop fs
    pop es
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    mov byte [paint_select_active], 0
    mov byte [paint_select_drag], 0
    mov byte [paint_select_pending], 0
    call redraw_all
.done:
    ret

paint_clear_with_undo:
    call canvas_backup_memory
    call canvas_clear_memory
    call paint_text_clear_all
    mov byte [paint_prev_valid], 0
    mov byte [paint_select_active], 0
    mov byte [paint_select_drag], 0
    mov byte [paint_select_pending], 0
    call proc_save
    call redraw_all
    ret

paint_get_local:
    mov ax, [mouse_x]
    mov bx, [mouse_y]
    jmp paint_screen_point_to_local

paint_get_hover_local:
    cmp byte [mouse_hover_valid], 0
    je .outside
    mov ax, [mouse_hover_x]
    mov bx, [mouse_hover_y]
    jmp paint_screen_point_to_local
.outside:
    clc
    ret

paint_get_visible_cursor_local:
    ; Use the hotspot that was actually drawn in the preceding frame. This is
    ; the source of truth for click-only Paint tools and fixes the VMMouse/PS2
    ; transition packet that occasionally reports the canvas left edge.
    mov ax, [cursor_draw_x]
    add ax, [cursor_hotspot_x]
    mov bx, [cursor_draw_y]
    add bx, [cursor_hotspot_y]
    jmp paint_screen_point_to_local

paint_begin_pending_action:
    mov [paint_pending_action], dl
    mov ax, [paint_target_x]
    mov [paint_pending_x], ax
    mov ax, [paint_target_y]
    mov [paint_pending_y], ax
    mov al, [active_pid]
    mov [interaction_pid], al
    ret

paint_update_pending_action:
    ret

paint_execute_pending_action:
    cmp byte [paint_pending_action], PAINT_PENDING_NONE
    je .none
    mov dl, [paint_pending_action]
    mov byte [paint_pending_action], PAINT_PENDING_NONE
    mov ax, [paint_pending_x]
    mov bx, [paint_pending_y]
    cmp dl, PAINT_PENDING_FILL
    je .fill
    cmp dl, PAINT_PENDING_TEXT
    je .text
    cmp dl, PAINT_PENDING_EYEDROP
    je .pick
    jmp .none
.fill:
    call paint_flood_fill
    stc
    ret
.text:
    call paint_text_click
    stc
    ret
.pick:
    call paint_pick_color
    stc
    ret
.none:
    clc
    ret

paint_current_color:
    cmp byte [paint_tool], PAINT_TOOL_ERASER
    je .eraser
    cmp byte [paint_eraser], 0
    jne .eraser
    cmp byte [paint_rainbow], 0
    jne .rainbow
    mov dl, [paint_color]
    ret
.eraser:
    mov dl, COL_WHITE
    ret
.rainbow:
    push bx
    xor bx, bx
    mov bl, [paint_rainbow_phase]
    mov dl, [rainbow_gradient_colors+bx]
    inc bl
    cmp bl, rainbow_gradient_colors_end-rainbow_gradient_colors
    jb .phase_ok
    xor bl, bl
.phase_ok:
    mov [paint_rainbow_phase], bl
    pop bx
    ret

paint_begin_stroke:
    call canvas_backup_memory
    mov byte [paint_live_active], 1
    mov byte [paint_live_started], 0
    mov byte [paint_live_prev_valid], 0
    mov byte [painting_active], 1
    mov al, [active_pid]
    mov [interaction_pid], al
    call proc_save
    ret

paint_continue_stroke:
    cmp byte [paint_live_active], 0
    je .done
    cmp byte [paint_tool], PAINT_TOOL_LINE
    je paint_continue_shape
    cmp byte [paint_tool], PAINT_TOOL_RECT
    je paint_continue_shape
    cmp byte [paint_tool], PAINT_TOOL_ELLIPSE
    je paint_continue_shape
    call paint_get_local
    jc .inside
    mov byte [paint_live_prev_valid], 0
    ret
.inside:
    mov [paint_target_x], ax
    mov [paint_target_y], bx
    cmp byte [paint_live_started], 0
    jne .have_started
    mov byte [paint_live_started], 1
    mov [paint_live_prev_x], ax
    mov [paint_live_prev_y], bx
    mov byte [paint_live_prev_valid], 1
    call paint_current_color
    call canvas_draw_brush
    ret
.have_started:
    cmp byte [paint_live_prev_valid], 0
    je .restart_anchor
    mov ax, [paint_live_prev_x]
    cmp ax, [paint_canvas_w]
    jae .restart_anchor
    mov ax, [paint_live_prev_y]
    cmp ax, [paint_canvas_h]
    jae .restart_anchor
    call canvas_draw_line
    mov ax, [paint_target_x]
    mov [paint_live_prev_x], ax
    mov ax, [paint_target_y]
    mov [paint_live_prev_y], ax
    ret
.restart_anchor:
    mov ax, [paint_target_x]
    mov bx, [paint_target_y]
    mov [paint_live_prev_x], ax
    mov [paint_live_prev_y], bx
    mov byte [paint_live_prev_valid], 1
    call paint_current_color
    call canvas_draw_brush
.done:
    ret

paint_finalize_stroke:
    cmp byte [paint_live_active], 0
    je .done
    cmp byte [paint_tool], PAINT_TOOL_LINE
    je .shape
    cmp byte [paint_tool], PAINT_TOOL_RECT
    je .shape
    cmp byte [paint_tool], PAINT_TOOL_ELLIPSE
    je .shape
    cmp byte [paint_live_started], 0
    jne .done
    call paint_continue_stroke
    cmp byte [paint_live_started], 0
    jne .done
    mov ax, [paint_target_x]
    cmp ax, [paint_canvas_w]
    jae .done
    mov bx, [paint_target_y]
    cmp bx, [paint_canvas_h]
    jae .done
    mov byte [paint_live_started], 1
    call paint_current_color
    call canvas_draw_brush
    jmp .done
.shape:
    call paint_continue_shape
.done:
    ret

canvas_draw_brush:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov [brush_base_x], ax
    mov [brush_base_y], bx
    mov [brush_color], dl
    xor ax, ax
    mov al, [paint_brush_size]
    mov [brush_size_w], ax
    shr ax, 1
    mov [brush_half], ax
    xor si, si
.row:
    cmp si, [brush_size_w]
    jae .done
    xor di, di
.col:
    cmp di, [brush_size_w]
    jae .next_row
    mov ax, [brush_base_x]
    add ax, di
    sub ax, [brush_half]
    mov bx, [brush_base_y]
    add bx, si
    sub bx, [brush_half]
    mov dl, [brush_color]
    call canvas_set_pixel
    inc di
    jmp .col
.next_row:
    inc si
    jmp .row
.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

canvas_draw_line:
    mov ax, [paint_live_prev_x]
    mov [line_fixed_x0], ax
    mov ax, [paint_live_prev_y]
    mov [line_fixed_y0], ax
    mov ax, [paint_target_x]
    mov [line_fixed_x1], ax
    mov ax, [paint_target_y]
    mov [line_fixed_y1], ax
    call paint_current_color
    mov [shape_color], dl
    jmp canvas_draw_line_fixed

canvas_set_pixel:
    ; AX=canvas x, BX=canvas y, DL=color; fixed maximum stride, dynamic bounds.
    push ax
    push bx
    push cx
    push dx
    push di
    push fs
    cmp ax, [paint_canvas_w]
    jae .done
    cmp bx, [paint_canvas_h]
    jae .done
    mov [canvas_px], ax
    mov [canvas_py], bx
    mov [canvas_pc], dl
    mov ax, bx
    mov cx, PAINT_CANVAS_STRIDE
    mul cx
    add ax, [canvas_px]
    mov di, ax
    mov ax, [active_data_seg]
    mov fs, ax
    mov al, [canvas_pc]
    mov fs:[di], al
    call paint_present_canvas_pixel
.done:
    pop fs
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

paint_present_canvas_pixel:
    push ax
    push bx
    push cx
    push dx
    push si
    ; Immediate stroke feedback must use the same scroll/zoom transform as
    ; draw_canvas_to_screen. The old 1:1 write made the current stroke appear
    ; at the wrong position and thickness until the next full redraw.
    mov ax, [canvas_px]
    cmp ax, [paint_scroll_x]
    jb .done
    sub ax, [paint_scroll_x]
    xor bx, bx
    mov bl, [paint_zoom]
    mul bx
    add ax, [paint_canvas_screen_x]
    mov cx, [paint_canvas_screen_x]
    add cx, [paint_canvas_screen_w]
    cmp ax, cx
    jae .done
    sub cx, ax
    cmp cx, bx
    jbe .width_ready
    mov cx, bx
.width_ready:
    push ax
    mov ax, [canvas_py]
    cmp ax, [paint_scroll_y]
    jb .drop_x
    sub ax, [paint_scroll_y]
    mul bx
    add ax, [paint_canvas_screen_y]
    mov dx, [paint_canvas_screen_y]
    add dx, [paint_canvas_screen_h]
    cmp ax, dx
    jae .drop_x
    sub dx, ax
    cmp dx, bx
    jbe .height_ready
    mov dx, bx
.height_ready:
    mov bx, ax
    pop ax
    push ax
    xor ax, ax
    mov al, [canvas_pc]
    xor si, si
    mov si, ax
    pop ax
    call fill_rect
    jmp .done
.drop_x:
    pop ax
.done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; =============================================================================
; Paint tools, editable text, shapes and RGB palette helpers
; =============================================================================
paint_canvas_fill_block_memory:
    ; AX=x, BX=y, CX=size, DL=color. Write only inside current bitmap dimensions.
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push es
    mov [paint_commit_block_x], ax
    mov [paint_commit_block_y], bx
    mov [paint_commit_block_size], cx
    mov [paint_commit_color], dl
    mov ax, [active_data_seg]
    mov es, ax
    xor si, si
.row:
    cmp si, [paint_commit_block_size]
    jae .done
    mov bx, [paint_commit_block_y]
    add bx, si
    cmp bx, [paint_canvas_h]
    jae .next_row
    mov ax, bx
    mov bp, PAINT_CANVAS_STRIDE
    mul bp
    add ax, [paint_commit_block_x]
    mov bp, ax
    xor di, di
.col:
    cmp di, [paint_commit_block_size]
    jae .next_row
    mov ax, [paint_commit_block_x]
    add ax, di
    cmp ax, [paint_canvas_w]
    jae .next_col
    mov al, [paint_commit_color]
    mov es:[bp+di], al
.next_col:
    inc di
    jmp .col
.next_row:
    inc si
    jmp .row
.done:
    pop es
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

paint_commit_text_objects:
    cmp byte [paint_text_active], 0
    je .clear
    cmp word [paint_text_len], 0
    je .clear
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push fs
    push gs
    mov ax, [active_data_seg]
    mov gs, ax
    mov ax, [font_seg]
    mov fs, ax
    call canvas_backup_memory
    xor ax, ax
    mov al, [paint_text_size]
    test ax, ax
    jnz .scale_ok
    mov ax, 1
.scale_ok:
    mov [paint_commit_scale], ax
    mov ax, [paint_text_x]
    mov [paint_commit_char_x], ax
    mov ax, [paint_text_y]
    mov [paint_commit_char_y], ax
    xor si, si
.char_loop:
    cmp si, [paint_text_len]
    jae .finish
    mov al, gs:[PAINT_TEXT_BASE+si]
    cmp al, 13
    jne .glyph
    mov ax, [paint_text_x]
    mov [paint_commit_char_x], ax
    mov ax, [paint_commit_scale]
    shl ax, 3
    add [paint_commit_char_y], ax
    inc si
    jmp .char_loop
.glyph:
    mov bx, PAINT_TEXT_COLOR_BASE
    add bx, si
    mov al, gs:[bx]
    mov [paint_commit_color], al
    xor ax, ax
    mov al, gs:[PAINT_TEXT_BASE+si]
    shl ax, 3
    add ax, [font_off]
    mov [paint_commit_glyph], ax
    mov word [paint_commit_row], 0
.glyph_row:
    cmp word [paint_commit_row], 8
    jae .next_char
    mov bx, [paint_commit_glyph]
    add bx, [paint_commit_row]
    mov al, fs:[bx]
    mov [paint_commit_bits], al
    mov byte [paint_commit_mask], 0x80
    mov word [paint_commit_col], 0
.glyph_col:
    cmp word [paint_commit_col], 8
    jae .next_glyph_row
    mov al, [paint_commit_bits]
    test al, [paint_commit_mask]
    jz .skip_pixel
    mov ax, [paint_commit_col]
    mul word [paint_commit_scale]
    add ax, [paint_commit_char_x]
    mov bx, ax
    mov ax, [paint_commit_row]
    mul word [paint_commit_scale]
    add ax, [paint_commit_char_y]
    xchg ax, bx
    mov cx, [paint_commit_scale]
    mov dl, [paint_commit_color]
    call paint_canvas_fill_block_memory
.skip_pixel:
    shr byte [paint_commit_mask], 1
    inc word [paint_commit_col]
    jmp .glyph_col
.next_glyph_row:
    inc word [paint_commit_row]
    jmp .glyph_row
.next_char:
    mov ax, [paint_commit_scale]
    shl ax, 3
    add [paint_commit_char_x], ax
    inc si
    jmp .char_loop
.finish:
    pop gs
    pop fs
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
.clear:
    call paint_text_clear_all
    ret

paint_text_clear_all:
    mov byte [paint_text_active], 0
    mov byte [paint_text_selected], 0xFF
    mov byte [paint_text_input], 0
    mov byte [paint_text_sel_active], 0
    mov byte [paint_text_mouse_select], 0
    mov word [paint_text_len], 0
    mov word [paint_text_cursor], 0
    mov word [paint_text_anchor], 0
    ret

paint_text_click:
    ; AX/BX is the exact displayed cursor hotspot in local canvas coordinates.
    mov [paint_target_x], ax
    mov [paint_target_y], bx
    cmp byte [paint_text_active], 0
    je .new_box
    call paint_text_point_to_index
    jnc .commit_new
    mov [paint_text_cursor], ax
    mov [paint_text_anchor], ax
    mov byte [paint_text_sel_active], 0
    mov byte [paint_text_mouse_select], 1
    mov byte [paint_text_input], 1
    mov al, [active_pid]
    mov [interaction_pid], al
    call proc_save
    call redraw_all
    ret
.commit_new:
    call paint_commit_text_objects
.new_box:
    mov byte [paint_text_active], 1
    mov byte [paint_text_selected], 0
    mov byte [paint_text_input], 1
    mov byte [paint_text_sel_active], 0
    mov byte [paint_text_mouse_select], 1
    mov ax, [paint_target_x]
    mov [paint_text_x], ax
    mov ax, [paint_target_y]
    mov [paint_text_y], ax
    mov word [paint_text_len], 0
    mov word [paint_text_cursor], 0
    mov word [paint_text_anchor], 0
    mov al, [active_pid]
    mov [interaction_pid], al
    call proc_save
    call redraw_all
    ret

paint_text_key:
    ; AX is BIOS key (AL ASCII, AH scan). Supports multiline editing, selection,
    ; arrows, Home/End, Delete/Backspace and Shift-extended selections.
    mov [paint_text_key_char], al
    mov [paint_text_key_scan], ah
    cmp byte [paint_text_active], 0
    je .done
    cmp al, 27
    je .finish_input
    cmp ah, 0x4B
    je .left
    cmp ah, 0x4D
    je .right
    cmp ah, 0x48
    je .up
    cmp ah, 0x50
    je .down
    cmp ah, 0x47
    je .home
    cmp ah, 0x4F
    je .end
    cmp ah, 0x53
    je .delete
    cmp al, 8
    je .backspace
    cmp al, 13
    je .enter
    cmp al, 32
    jb .done
    cmp al, 126
    ja .done
    call paint_text_insert_char
    jmp .changed
.left:
    call paint_text_prepare_move
    cmp word [paint_text_cursor], 0
    je .move_done
    dec word [paint_text_cursor]
    jmp .move_done
.right:
    call paint_text_prepare_move
    mov ax, [paint_text_cursor]
    cmp ax, [paint_text_len]
    jae .move_done
    inc word [paint_text_cursor]
    jmp .move_done
.up:
    call paint_text_prepare_move
    mov ax, [paint_text_cursor]
    call paint_text_index_to_rowcol
    test bx, bx
    jz .move_done
    dec bx
    call paint_text_rowcol_to_index
    jnc .move_done
    mov [paint_text_cursor], ax
    jmp .move_done
.down:
    call paint_text_prepare_move
    mov ax, [paint_text_cursor]
    call paint_text_index_to_rowcol
    inc bx
    call paint_text_rowcol_to_index
    jnc .move_done
    mov [paint_text_cursor], ax
    jmp .move_done
.home:
    call paint_text_prepare_move
    mov ax, [paint_text_cursor]
    call paint_text_index_to_rowcol
    xor cx, cx
    call paint_text_rowcol_to_index
    mov [paint_text_cursor], ax
    jmp .move_done
.end:
    call paint_text_prepare_move
    mov ax, [paint_text_cursor]
    call paint_text_index_to_rowcol
    mov cx, 0x7FFF
    call paint_text_rowcol_to_index
    mov [paint_text_cursor], ax
.move_done:
    jmp paint_text_finish_move
.backspace:
    cmp byte [paint_text_sel_active], 0
    jne .delete_selection
    cmp word [paint_text_cursor], 0
    je .done
    mov ax, [paint_text_cursor]
    dec ax
    mov [paint_text_anchor], ax
    mov byte [paint_text_sel_active], 1
    jmp .delete_selection
.delete:
    cmp byte [paint_text_sel_active], 0
    jne .delete_selection
    mov ax, [paint_text_cursor]
    cmp ax, [paint_text_len]
    jae .done
    inc ax
    mov [paint_text_anchor], ax
    mov byte [paint_text_sel_active], 1
.delete_selection:
    call paint_text_delete_selection
    jmp .changed
.enter:
    mov al, 13
    call paint_text_insert_char
    jmp .changed
.finish_input:
    mov byte [paint_text_input], 0
.changed:
    call proc_save
    call redraw_all
.done:
    ret

paint_apply_color_to_selected:
    ; Recolor only the selected character range. With no selection, the chosen
    ; palette color becomes the insertion color for subsequent input.
    cmp byte [paint_text_active], 0
    je .done
    cmp byte [paint_text_sel_active], 0
    je .done
    push ax
    push bx
    push si
    push di
    push fs
    mov ax, [paint_text_anchor]
    mov bx, [paint_text_cursor]
    cmp ax, bx
    jbe .ordered
    xchg ax, bx
.ordered:
    mov si, ax
    mov ax, [active_data_seg]
    mov fs, ax
.loop:
    cmp si, bx
    jae .restore
    mov ax, PAINT_TEXT_COLOR_BASE
    add ax, si
    mov di, ax
    mov al, [paint_color]
    mov fs:[di], al
    inc si
    jmp .loop
.restore:
    pop fs
    pop di
    pop si
    pop bx
    pop ax
.done:
    ret

paint_apply_size_to_selected:
    ; The text object uses one scale; changing size preserves all content and
    ; character colors.
    ret

paint_sync_custom_swatch:
    ; Standard colors select their own swatch; all other colors occupy Current.
    push ax
    push bx
    push si
    xor bx, bx
.loop:
    cmp bx, 7
    jae .custom
    mov si, palette_colors
    add si, bx
    mov al, [paint_color]
    cmp al, [si]
    je .standard
    inc bx
    jmp .loop
.standard:
    mov byte [paint_custom_active], 0
    jmp .done
.custom:
    mov al, [paint_color]
    mov [paint_custom_color], al
    mov byte [paint_custom_active], 1
.done:
    pop si
    pop bx
    pop ax
    ret

paint_palette_key:
    ; AL=ASCII; edit the focused R/G/B value. First digit replaces the field.
    ; Select the field explicitly instead of indexing from paint_rgb_r. This
    ; keeps G independent and prevents layout changes from silently addressing
    ; the wrong byte.
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov dl, al
    mov al, [paint_rgb_focus]
    cmp al, 1
    jb .done
    cmp al, 3
    ja .done
    cmp al, 1
    je .select_r
    cmp al, 2
    je .select_g
    mov di, paint_rgb_b
    jmp .field_ready
.select_r:
    mov di, paint_rgb_r
    jmp .field_ready
.select_g:
    mov di, paint_rgb_g
.field_ready:
    cmp dl, 9
    je .tab
    cmp dl, 13
    je .apply
    cmp dl, 27
    je .close
    cmp dl, 8
    je .backspace
    cmp dl, '0'
    jb .done
    cmp dl, '9'
    ja .done
    sub dl, '0'
    cmp byte [paint_rgb_replace], 0
    je .append
    mov [di], dl
    mov byte [paint_rgb_replace], 0
    jmp .apply
.append:
    xor dh, dh
    mov si, dx
    mov al, [di]
    xor ah, ah
    mov cx, 10
    mul cx
    add ax, si
    cmp ax, 255
    jbe .store
    mov ax, 255
.store:
    mov [di], al
    jmp .apply
.backspace:
    mov byte [paint_rgb_replace], 0
    mov al, [di]
    xor ah, ah
    mov cx, 10
    xor dx, dx
    div cx
    mov [di], al
    jmp .apply
.tab:
    inc byte [paint_rgb_focus]
    cmp byte [paint_rgb_focus], 3
    jbe .tab_ready
    mov byte [paint_rgb_focus], 1
.tab_ready:
    mov byte [paint_rgb_replace], 1
    call proc_save
    call redraw_all
    jmp .done
.apply:
    call paint_rgb_to_index
    call proc_save
    call redraw_all
    jmp .done
.close:
    mov byte [paint_palette_open], 0
    mov byte [paint_rgb_focus], 0
    mov byte [paint_rgb_replace], 0
    call proc_save
    call redraw_all
.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

paint_palette_click:
    ; CF=1 when the open palette dialog consumed the click.  Close and OK
    ; use the normal capture/release path so they animate like every button.
    cmp byte [paint_palette_open], 0
    je .no

    mov ax, [paint_palette_x]
    add ax, 190
    mov bx, [paint_palette_y]
    add bx, 4
    mov cx, 16
    mov dx, 14
    mov si, str_close
    mov di, BTN_PALETTE_CLOSE
    call try_capture_button
    jc .consumed

    ; Drag the RGB Palette by any unused part of its blue title bar.
    mov cx, [paint_palette_x]
    add cx, 4
    mov dx, [paint_palette_y]
    add dx, 4
    mov si, 184
    mov di, 14
    call hit_rect
    jnc .dialog_controls
    mov byte [drag_mode], 7
    mov ax, [mouse_x]
    sub ax, [paint_palette_x]
    mov [paint_palette_drag_dx], ax
    mov ax, [mouse_y]
    sub ax, [paint_palette_y]
    mov [paint_palette_drag_dy], ax
    stc
    ret

.dialog_controls:

    mov cx, [paint_wheel_x]
    mov dx, [paint_wheel_y]
    mov si, 64
    mov di, 64
    call hit_rect
    jc .wheel

    mov cx, [paint_palette_x]
    add cx, 102
    mov dx, [paint_palette_y]
    add dx, 25
    mov si, 48
    mov di, 16
    call hit_rect
    jc .focus_r
    mov cx, [paint_palette_x]
    add cx, 102
    mov dx, [paint_palette_y]
    add dx, 49
    mov si, 48
    mov di, 16
    call hit_rect
    jc .focus_g
    mov cx, [paint_palette_x]
    add cx, 102
    mov dx, [paint_palette_y]
    add dx, 73
    mov si, 48
    mov di, 16
    call hit_rect
    jc .focus_b

    mov ax, [paint_palette_x]
    add ax, 154
    mov bx, [paint_palette_y]
    add bx, 94
    mov cx, 42
    mov dx, 19
    mov si, str_ok
    mov di, BTN_PALETTE_OK
    call try_capture_button
    jc .consumed

    ; The dialog is modal: clicks in unused dialog space are consumed.
    stc
    ret
.focus_r:
    mov byte [paint_rgb_focus], 1
    mov byte [paint_rgb_replace], 1
    jmp .redraw
.focus_g:
    mov byte [paint_rgb_focus], 2
    mov byte [paint_rgb_replace], 1
    jmp .redraw
.focus_b:
    mov byte [paint_rgb_focus], 3
    mov byte [paint_rgb_replace], 1
    jmp .redraw
.wheel:
    push di
    push bp
    mov di, [mouse_x]
    sub di, [paint_wheel_x]
    mov bp, [mouse_y]
    sub bp, [paint_wheel_y]
    call paint_wheel_color_at
    pop bp
    pop di
    cmp al, 0xFF
    je .redraw
    mov [paint_color], al
    mov byte [paint_rainbow], 0
    mov byte [paint_eraser], 0
    call paint_index_to_rgb
    call paint_sync_custom_swatch
    call paint_apply_color_to_selected
.redraw:
    call proc_save
    call redraw_all
    stc
    ret
.consumed:
    stc
    ret
.no:
    clc
    ret

paint_pick_color:
    ; AX=x, BX=y in the current 1:1 bitmap.
    ; Keep X in DI. 16-bit MUL writes DX:AX, so saving X in DX and then doing
    ; MUL destroyed X and always sampled column zero.
    push ax
    push bx
    push cx
    push di
    push fs
    mov di, ax
    mov ax, bx
    mov cx, PAINT_CANVAS_STRIDE
    mul cx
    add di, ax
    mov ax, [active_data_seg]
    mov fs, ax
    mov al, fs:[di]
    mov [paint_color], al
    mov byte [paint_rainbow], 0
    mov byte [paint_eraser], 0
    call paint_index_to_rgb
    call paint_sync_custom_swatch
    call paint_apply_color_to_selected
    call proc_save
    call redraw_all
    pop fs
    pop di
    pop cx
    pop bx
    pop ax
    ret

hit_rect:
    ; Uses current mouse point. CX=x, DX=y, SI=w, DI=h. CF=1 inside.
    push ax
    push bx
    mov ax, [mouse_x]
    cmp ax, cx
    jb .outside
    add cx, si
    cmp ax, cx
    jae .outside
    mov bx, [mouse_y]
    cmp bx, dx
    jb .outside
    add dx, di
    cmp bx, dx
    jae .outside
    pop bx
    pop ax
    stc
    ret
.outside:
    pop bx
    pop ax
    clc
    ret

handle_mouse_events:
    cmp byte [mouse_wheel], 0
    je .buttons
    call handle_mouse_wheel
    mov byte [mouse_wheel], 0
.buttons:
    mov al, [mouse_buttons]
    mov bl, [mouse_prev_buttons]
    test al, 1
    jz .left_up
    test bl, 1
    jz .left_down
    call mouse_left_hold
    jmp .done
.left_down:
    call mouse_left_down
    jmp .done
.left_up:
    test bl, 1
    jz .done
    call mouse_left_up
.done:
    mov al, [mouse_buttons]
    mov [mouse_prev_buttons], al
    ret

handle_mouse_wheel:
    ; Paint uses Ctrl+wheel for magnification and plain wheel for the zoomed
    ; vertical viewport. Notepad keeps its normal wheel scrolling.
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    cmp byte [message_open], 0
    jne .done
    cmp byte [custom_open], 0
    je .not_custom
    mov al, [mouse_wheel]
    test al, 0x80
    jnz .custom_down
    call CUSTOM_CODE_SEG:custom_entry_page_up
    jmp .done
.custom_down:
    call CUSTOM_CODE_SEG:custom_entry_page_down
    jmp .done
.not_custom:
    cmp byte [debug_open], 2
    je .debug
    cmp byte [debug_open], 3
    je .debug
    cmp byte [debug_open], 6
    je .debug
    cmp byte [debug_open], 0
    jne .done
    mov al, [foreground_window]
    cmp al, WIN_MAIN
    je .done
    call proc_load
    cmp byte [active_type], APP_PAINT
    je .paint
    cmp byte [active_type], APP_NOTEPAD
    jne .done
    call note_compute_layout
    mov cx, [note_text_x_dyn]
    mov dx, [note_text_y_dyn]
    mov si, [note_text_w_dyn]
    mov di, [note_text_h_dyn]
    call hit_rect
    jnc .done
    mov al, [mouse_wheel]
    test al, al
    jz .done
    test al, 0x80
    jnz .down
    jmp .up
.up:
    mov cx, 3
.up_loop:
    call notepad_scroll_line_up_no_draw
    loop .up_loop
    jmp .redraw
.down:
    mov cx, 3
.down_loop:
    call notepad_scroll_line_down_no_draw
    loop .down_loop
.redraw:
    call proc_save
    call redraw_all
    jmp .done
.debug:
    mov cx, DEBUG_INT_X+10
    mov dx, DEBUG_INT_Y+34
    mov si, DEBUG_INT_W-20
    mov di, DEBUG_INT_H-42
    call hit_rect
    jnc .done
    mov al, [mouse_wheel]
    test al, al
    jz .done
    ; A wheel scroll moves every visible INT row. Cancel the current mouse
    ; capture before redrawing so its pressed overlay cannot stay at the old
    ; row, and releasing the still-held button cannot execute the wrong item.
    mov byte [captured_button], BTN_NONE
    mov byte [capture_inside], 0
    test al, 0x80
    jnz .debug_down
    cmp word [debug_scroll_offset], 3
    jb .debug_top
    sub word [debug_scroll_offset], 3
    jmp .debug_redraw
.debug_top:
    mov word [debug_scroll_offset], 0
    jmp .debug_redraw
.debug_down:
    add word [debug_scroll_offset], 3
    call debug_get_scroll_max
    cmp word [debug_scroll_offset], bx
    jbe .debug_redraw
    mov [debug_scroll_offset], bx
.debug_redraw:
    call redraw_all
    jmp .done
.paint:
    mov ah, 0x02
    int 0x16
    mov [shift_flags], al
    call paint_compute_canvas_rect
    mov cx, [paint_canvas_screen_x]
    mov dx, [paint_canvas_screen_y]
    mov si, [paint_canvas_screen_w]
    mov di, [paint_canvas_screen_h]
    call hit_rect
    jnc .done
    test byte [shift_flags], 0x04
    jz .paint_scroll
    ; Keep the bitmap point under the pointer stable while changing zoom.
    ; This also keeps an active selection from jumping across the viewport.
    call paint_get_local
    jnc .done
    mov [paint_zoom_anchor_x], ax
    mov [paint_zoom_anchor_y], bx
    mov al, [mouse_wheel]
    test al, 0x80
    jnz .zoom_out
    cmp byte [paint_zoom], 4
    jae .done
    inc byte [paint_zoom]
    jmp .zoom_recenter
.zoom_out:
    cmp byte [paint_zoom], 1
    jbe .done
    dec byte [paint_zoom]
.zoom_recenter:
    call paint_compute_canvas_rect
    mov ax, [mouse_x]
    sub ax, [paint_canvas_screen_x]
    xor dx, dx
    xor cx, cx
    mov cl, [paint_zoom]
    div cx
    mov dx, [paint_zoom_anchor_x]
    cmp dx, ax
    jb .zoom_x_zero
    sub dx, ax
    mov [paint_scroll_x], dx
    jmp .zoom_y
.zoom_x_zero:
    mov word [paint_scroll_x], 0
.zoom_y:
    mov ax, [mouse_y]
    sub ax, [paint_canvas_screen_y]
    xor dx, dx
    div cx
    mov dx, [paint_zoom_anchor_y]
    cmp dx, ax
    jb .zoom_y_zero
    sub dx, ax
    mov [paint_scroll_y], dx
    jmp .paint_redraw
.zoom_y_zero:
    mov word [paint_scroll_y], 0
    jmp .paint_redraw
.paint_scroll:
    cmp byte [paint_zoom], 1
    jbe .done
    test byte [shift_flags], 0x03
    jnz .paint_scroll_horizontal
    mov al, [mouse_wheel]
    test al, 0x80
    jnz .scroll_down
    cmp word [paint_scroll_y], 8
    jb .scroll_top
    sub word [paint_scroll_y], 8
    jmp .paint_redraw
.scroll_top:
    mov word [paint_scroll_y], 0
    jmp .paint_redraw
.scroll_down:
    add word [paint_scroll_y], 8
    jmp .paint_redraw
.paint_scroll_horizontal:
    mov al, [mouse_wheel]
    test al, 0x80
    jnz .scroll_right
    cmp word [paint_scroll_x], 8
    jb .scroll_left_edge
    sub word [paint_scroll_x], 8
    jmp .paint_redraw
.scroll_left_edge:
    mov word [paint_scroll_x], 0
    jmp .paint_redraw
.scroll_right:
    add word [paint_scroll_x], 8
.paint_redraw:
    call paint_clamp_scroll
    call proc_save
    call redraw_all
.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

try_capture_button:
    ; AX=x, BX=y, CX=w, DX=h, SI=label, DI=action. CF=1 if captured.
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov [temp_x], ax
    mov [temp_y], bx
    mov [temp_w], cx
    mov [temp_h], dx
    mov [temp_label], si
    mov [temp_action], di
    mov cx, ax
    mov dx, bx
    mov si, [temp_w]
    mov di, [temp_h]
    call hit_rect
    jnc .no
    mov ax, [temp_x]
    mov [capture_x], ax
    mov ax, [temp_y]
    mov [capture_y], ax
    mov ax, [temp_w]
    mov [capture_w], ax
    mov ax, [temp_h]
    mov [capture_h], ax
    mov ax, [temp_label]
    mov [capture_label], ax
    mov ax, [temp_action]
    mov [captured_button], al
    mov al, [active_pid]
    mov [captured_pid], al
    mov byte [capture_inside], 1
    call redraw_all
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    stc
    ret
.no:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    clc
    ret

capture_pointer_inside:
    mov cx, [capture_x]
    mov dx, [capture_y]
    mov si, [capture_w]
    mov di, [capture_h]
    call hit_rect
    ret

try_capture_open_system_icon:
    ; Keep double-click-to-close working even while the first click's system
    ; menu is open. CF=1 when the owner icon captured the press.
    mov al, [menu_open]
    cmp al, MENU_SYS_MAIN
    jb .no
    cmp al, MENU_SYS_CALC
    ja .no
    mov al, [menu_owner_pid]
    cmp al, WIN_MAIN
    je .main
    call proc_load
    mov al, [active_type]
    cmp al, APP_PAINT
    je .paint
    cmp al, APP_NOTEPAD
    je .note
    cmp al, APP_CALC
    je .calc
    jmp .no
.main:
    mov byte [active_pid], WIN_MAIN
    mov ax, [main_x]
    mov bx, [main_y]
    jmp .capture
.paint:
    mov ax, [paint_x]
    mov bx, [paint_y]
    jmp .capture
.note:
    mov ax, [note_x]
    mov bx, [note_y]
    jmp .capture
.calc:
    mov ax, [calc_x]
    mov bx, [calc_y]
.capture:
    add ax, 4
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_empty
    mov di, BTN_SYS_MENU
    call try_capture_button
    ret
.no:
    clc
    ret

mouse_stabilize_left_press:
    ; One-shot Paint tools (Fill/Text/Eyedropper) execute on button-down.  Some
    ; absolute-mouse backends report a transient, badly displaced press packet,
    ; while the immediately preceding button-up hover coordinate is correct.
    ; When that saved hover point is inside the foreground Paint canvas, use it
    ; whenever the press packet is outside the canvas or differs by more than
    ; two screen pixels.  Normal clicks are unchanged.
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    cmp byte [mouse_hover_valid], 0
    je .done
    xor bx, bx
    mov bl, [foreground_window]
    test bx, bx
    jz .done
    cmp bx, MAX_PROCS
    jae .done
    cmp byte [proc_type+bx], APP_PAINT
    jne .done
    cmp byte [proc_minimized+bx], 0
    jne .done
    mov si, bx
    shl si, 1

    mov cx, [proc_x+si]
    add cx, PAINT_CANVAS_XOFF
    mov dx, [proc_y+si]
    add dx, PAINT_CANVAS_YOFF
    mov di, [proc_w+si]
    sub di, PAINT_CANVAS_XOFF+PAINT_CANVAS_RIGHT_MARGIN
    mov bp, [proc_h+si]
    sub bp, PAINT_CANVAS_YOFF+PAINT_CANVAS_BOTTOM_MARGIN

    ; Saved hover must be inside this exact canvas.
    mov ax, [mouse_hover_x]
    cmp ax, cx
    jb .done
    mov bx, cx
    add bx, di
    cmp ax, bx
    jae .done
    mov ax, [mouse_hover_y]
    cmp ax, dx
    jb .done
    mov bx, dx
    add bx, bp
    cmp ax, bx
    jae .done

    ; Replace an outside press packet immediately.
    mov ax, [mouse_x]
    cmp ax, cx
    jb .restore
    mov bx, cx
    add bx, di
    cmp ax, bx
    jae .restore
    mov ax, [mouse_y]
    cmp ax, dx
    jb .restore
    mov bx, dx
    add bx, bp
    cmp ax, bx
    jae .restore

    ; A real button-down packet should be essentially at the saved hover point.
    mov ax, [mouse_x]
    sub ax, [mouse_hover_x]
    jns .dx_abs
    neg ax
.dx_abs:
    cmp ax, 2
    ja .restore
    mov ax, [mouse_y]
    sub ax, [mouse_hover_y]
    jns .dy_abs
    neg ax
.dy_abs:
    cmp ax, 2
    jbe .done
.restore:
    mov ax, [mouse_hover_x]
    mov [mouse_x], ax
    mov ax, [mouse_hover_y]
    mov [mouse_y], ax
.done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

mouse_left_down:
    call mouse_stabilize_left_press
    cmp byte [captured_button], BTN_NONE
    jne .done
    ; Modal message box is always topmost.
    cmp byte [message_open], 0
    je .taskbar
    mov ax, 261
    mov bx, 51
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_close
    mov di, BTN_MSG_CLOSE
    call try_capture_button
    jc .done
    cmp byte [message_kind], MSG_EXIT_CONFIRM
    je .yes_no_message
    cmp byte [message_kind], MSG_UNSAVED
    je .yes_no_message
    cmp byte [message_kind], MSG_OVERWRITE
    jne .normal_message
.yes_no_message:
    mov ax, 86
    mov bx, 116
    mov cx, 62
    mov dx, 22
    mov si, str_yes
    mov di, BTN_MSG_YES
    call try_capture_button
    jc .done
    mov ax, 172
    mov bx, 116
    mov cx, 62
    mov dx, 22
    mov si, str_no
    mov di, BTN_MSG_NO
    call try_capture_button
    ret
.normal_message:
    mov ax, 124
    mov bx, 127
    mov cx, 72
    mov dx, 20
    mov si, str_ok
    mov di, BTN_MSG_OK
    call try_capture_button
    ret

.taskbar:
    cmp byte [custom_open], 0
    je .debug_modal
    cmp word [mouse_y], TASKBAR_Y
    jae .real_taskbar
    call CUSTOM_CODE_SEG:custom_entry_mouse_down
    ret
.debug_modal:
    cmp byte [debug_open], 0
    je .control_modal
    call handle_debug_mouse_down
    ret
.control_modal:
    cmp byte [control_open], 0
    je .real_taskbar
    call handle_control_mouse_down
    ret
.real_taskbar:
    cmp word [mouse_y], TASKBAR_Y
    jb .menu
    call handle_taskbar_click
    ret
.menu:
    cmp byte [menu_open], MENU_NONE
    je .windows
    call try_capture_open_system_icon
    jc .done
    call handle_open_menu_click
    jc .done
    mov byte [menu_open], MENU_NONE
    call redraw_all
    ret
.windows:
    ; Hit test the real Z-order from top to bottom.
    xor bx, bx
    mov bl, [z_count]
    test bx, bx
    jz .desktop
    dec bx
.zloop:
    mov al, [z_order+bx]
    push bx
    call try_window_click
    pop bx
    jc .done
    test bx, bx
    jz .desktop
    dec bx
    jmp .zloop
.desktop:
    mov byte [note_focus], 0
    mov byte [note_mouse_select], 0
    mov byte [menu_open], MENU_NONE
    call redraw_all
.done:
    ret

try_window_click:
    ; AL=pid, CF=1 if point was inside and dispatched.
    push ax
    call window_is_visible
    jnc .not_visible
    pop ax
    mov [click_target_pid], al
    cmp al, WIN_MAIN
    je .main_rect
    call proc_load
    mov al, [active_type]
    cmp al, APP_PAINT
    je .paint_rect
    cmp al, APP_NOTEPAD
    je .note_rect
    cmp al, APP_CALC
    je .calc_rect
    clc
    ret
.main_rect:
    mov byte [active_pid], WIN_MAIN
    mov byte [active_type], APP_NONE
    mov cx, [main_x]
    mov dx, [main_y]
    mov si, [main_w]
    mov di, [main_h]
    jmp .test
.paint_rect:
    mov cx, [paint_x]
    mov dx, [paint_y]
    mov si, [paint_w]
    mov di, [paint_h]
    jmp .test
.note_rect:
    mov cx, [note_x]
    mov dx, [note_y]
    mov si, [note_w]
    mov di, [note_h]
    jmp .test
.calc_rect:
    mov cx, [calc_x]
    mov dx, [calc_y]
    mov si, [calc_w]
    mov di, [calc_h]
.test:
    call hit_rect
    jnc .outside
    mov al, [click_target_pid]
    call bring_to_front
    mov byte [menu_open], MENU_NONE
    call redraw_all
    mov al, [click_target_pid]
    cmp al, WIN_MAIN
    je .dispatch_main
    call proc_load
    mov al, [active_type]
    cmp al, APP_PAINT
    je .dispatch_paint
    cmp al, APP_NOTEPAD
    je .dispatch_note
    call process_calc_click
    stc
    ret
.dispatch_main:
    mov byte [active_pid], WIN_MAIN
    mov byte [active_type], APP_NONE
    call process_main_click
    stc
    ret
.dispatch_paint:
    call process_paint_click
    stc
    ret
.dispatch_note:
    call process_note_click
    stc
    ret
.outside:
    clc
    ret
.not_visible:
    pop ax
    clc
    ret

handle_taskbar_click:
    call task_compute_width
    xor bx, bx
    mov word [task_draw_x], 2
.loop:
    xor cx, cx
    mov cl, [task_count]
    cmp bx, cx
    jae .done
    mov al, [task_order+bx]
    mov [task_draw_id], al
    call task_get_label_action
    mov al, [task_draw_id]
    mov [active_pid], al
    mov ax, [task_draw_x]
    push bx
    mov bx, TASKBAR_Y+1
    mov cx, [task_button_w]
    mov dx, TASKBAR_H-2
    call try_capture_button
    pop bx
    jc .done
    mov ax, [task_button_w]
    add ax, 2
    add [task_draw_x], ax
    inc bx
    jmp .loop
.done:
    ret

handle_open_menu_click:
    mov al, [menu_owner_pid]
    cmp al, WIN_MAIN
    je .owner_ready
    call proc_load
.owner_ready:
    mov al, [menu_open]
    cmp al, MENU_MAIN_FILE
    je .main_file
    cmp al, MENU_MAIN_APPS
    je .main_apps
    cmp al, MENU_MAIN_HELP
    je .main_help
    cmp al, MENU_PAINT_FILE
    je .paint_file
    cmp al, MENU_PAINT_EDIT
    je .paint_edit
    cmp al, MENU_PAINT_VIEW
    je .paint_view
    cmp al, MENU_NOTE_FILE
    je .note_file
    cmp al, MENU_NOTE_EDIT
    je .note_edit
    cmp al, MENU_NOTE_HELP
    je .note_help
    cmp al, MENU_CALC_FILE
    je .calc_file
    cmp al, MENU_CALC_HELP
    je .calc_help
    cmp al, MENU_SYS_MAIN
    je .sys_main
    cmp al, MENU_SYS_PAINT
    je .sys_paint
    cmp al, MENU_SYS_NOTE
    je .sys_note
    cmp al, MENU_SYS_CALC
    je .sys_calc
    clc
    ret
.main_file:
    mov cx, [main_x]
    add cx, 4
    mov dx, [main_y]
    add dx, 36
    mov si, 112
    mov di, 16
    call hit_rect
    jnc .outside
    call show_exit_confirmation
    stc
    ret
.main_apps:
    mov cx, [main_x]
    add cx, 44
    mov dx, [main_y]
    add dx, 36
    mov si, 112
    mov di, 68
    call hit_rect
    jnc .outside
    mov ax, [mouse_y]
    sub ax, [main_y]
    cmp ax, 49
    jb .open_paint
    cmp ax, 62
    jb .open_note
    cmp ax, 75
    jb .open_calc_menu
    cmp ax, 88
    jb .open_control_menu
    mov byte [menu_open], MENU_NONE
    call custom_launch_editor
    stc
    ret
.open_control_menu:
    call open_control_panel
    stc
    ret
.open_calc_menu:
    call open_calc_foreground
    stc
    ret
.main_help:
    mov cx, [main_x]
    add cx, 84
    mov dx, [main_y]
    add dx, 36
    mov si, 104
    mov di, 16
    call hit_rect
    jnc .outside
    call show_about
    stc
    ret
.paint_file:
    mov cx, [paint_x]
    add cx, 4
    mov dx, [paint_y]
    add dx, 36
    mov si, 96
    mov di, 42
    call hit_rect
    jnc .outside
    mov ax, [mouse_y]
    sub ax, [paint_y]
    cmp ax, 49
    jb .new_canvas
    cmp ax, 62
    jb .min_paint
    call close_paint
    stc
    ret
.new_canvas:
    mov byte [menu_open], MENU_NONE
    call request_paint_new
    stc
    ret
.min_paint:
    call minimize_paint
    stc
    ret
.paint_edit:
    mov cx, [paint_x]
    add cx, 44
    mov dx, [paint_y]
    add dx, 36
    mov si, 88
    mov di, 68
    call hit_rect
    jnc .outside
    mov ax, [mouse_y]
    sub ax, [paint_y]
    cmp ax, 49
    jb .paint_undo
    cmp ax, 62
    jb .paint_cut_menu
    cmp ax, 75
    jb .paint_copy_menu
    cmp ax, 88
    jb .paint_paste_menu
    mov byte [menu_open], MENU_NONE
    call paint_clear_with_undo
    stc
    ret
.paint_cut_menu:
    mov byte [menu_open], MENU_NONE
    cmp byte [paint_tool], PAINT_TOOL_TEXT
    jne .paint_cut_bitmap
    call paint_text_cut
    stc
    ret
.paint_cut_bitmap:
    call paint_selection_cut
    stc
    ret
.paint_copy_menu:
    mov byte [menu_open], MENU_NONE
    cmp byte [paint_tool], PAINT_TOOL_TEXT
    jne .paint_copy_bitmap
    call paint_text_copy
    call redraw_all
    stc
    ret
.paint_copy_bitmap:
    call paint_selection_copy
    call redraw_all
    stc
    ret
.paint_paste_menu:
    mov byte [menu_open], MENU_NONE
    cmp byte [clipboard_kind], 1
    jne .paint_paste_bitmap
    call paint_text_paste
    stc
    ret
.paint_paste_bitmap:
    call paint_selection_paste
    stc
    ret
.paint_undo:
    mov byte [menu_open], MENU_NONE
    call canvas_swap_undo
    stc
    ret
.paint_view:
    mov cx, [paint_x]
    add cx, 84
    mov dx, [paint_y]
    add dx, 36
    mov si, 96
    mov di, 42
    call hit_rect
    jnc .outside
    mov ax, [mouse_y]
    sub ax, [paint_y]
    cmp ax, 49
    jb .brush1
    cmp ax, 62
    jb .brush2
    mov byte [paint_brush_size], 4
    jmp .brush_done
.brush1:
    mov byte [paint_brush_size], 1
    jmp .brush_done
.brush2:
    mov byte [paint_brush_size], 2
.brush_done:
    cmp byte [paint_tool], PAINT_TOOL_TEXT
    jne .brush_save
    mov al, [paint_brush_size]
    cmp al, 4
    jne .text_size_ready
    mov al, 3
.text_size_ready:
    mov [paint_text_size], al
    call paint_apply_size_to_selected
.brush_save:
    call proc_save
    mov byte [menu_open], MENU_NONE
    call redraw_all
    stc
    ret
.note_file:
    mov cx, [note_x]
    add cx, 4
    mov dx, [note_y]
    add dx, 36
    mov si, 120
    mov di, 42
    call hit_rect
    jnc .outside
    mov ax, [mouse_y]
    sub ax, [note_y]
    cmp ax, 49
    jb .new_note
    cmp ax, 62
    jb .insert_time
    call close_notepad
    stc
    ret
.new_note:
    call request_notepad_new
    stc
    ret
.insert_time:
    call notepad_insert_datetime
    stc
    ret
.note_edit:
    mov cx, [note_x]
    add cx, 44
    mov dx, [note_y]
    add dx, 36
    mov si, 112
    mov di, 68
    call hit_rect
    jnc .outside
    mov ax, [mouse_y]
    sub ax, [note_y]
    cmp ax, 49
    jb .note_undo
    cmp ax, 62
    jb .note_cut
    cmp ax, 75
    jb .note_copy
    cmp ax, 88
    jb .note_paste
    call notepad_select_all
    stc
    ret
.note_undo:
    call notepad_undo
    stc
    ret
.note_cut:
    call notepad_cut
    stc
    ret
.note_copy:
    call notepad_copy
    stc
    ret
.note_paste:
    call notepad_paste
    stc
    ret
.note_help:
    mov cx, [note_x]
    add cx, 84
    mov dx, [note_y]
    add dx, 36
    mov si, 104
    mov di, 16
    call hit_rect
    jnc .outside
    call show_about
    stc
    ret
.calc_file:
    mov cx, [calc_x]
    add cx, 4
    mov dx, [calc_y]
    add dx, 36
    mov si, 96
    mov di, 42
    call hit_rect
    jnc .outside
    mov ax, [mouse_y]
    sub ax, [calc_y]
    cmp ax, 49
    jb .clear_calc
    cmp ax, 62
    jb .min_calc
    call close_calc
    stc
    ret
.clear_calc:
    call calc_clear
    stc
    ret
.min_calc:
    call minimize_calc
    stc
    ret
.calc_help:
    mov cx, [calc_x]
    add cx, 52
    mov dx, [calc_y]
    add dx, 36
    mov si, 104
    mov di, 16
    call hit_rect
    jnc .outside
    call show_about
    stc
    ret
.sys_main:
    mov byte [system_menu_window], WIN_MAIN
    ; The second click of a double-click must not be swallowed by the open menu.
    mov cx, [main_x]
    add cx, 4
    mov dx, [main_y]
    add dx, 6
    mov si, CTRL_W
    mov di, CTRL_H
    call hit_rect
    jnc .sys_main_menu_area
    mov al, WIN_MAIN
    call system_box_click
    stc
    ret
.sys_main_menu_area:
    mov cx, [main_x]
    add cx, 4
    mov dx, [main_y]
    add dx, 18
    mov si, 104
    mov di, 68
    call hit_rect
    jnc .outside
    mov ax, [mouse_y]
    sub ax, [main_y]
    cmp ax, 31
    jb .sys_restore
    cmp ax, 44
    jb .sys_move
    cmp ax, 57
    jb .sys_minimize
    cmp ax, 70
    jb .sys_maximize
    jmp .sys_close
.sys_paint:
    mov al, [menu_owner_pid]
    mov [system_menu_window], al
    mov bx, [paint_x]
    mov bp, [paint_y]
    jmp .sys_app_icon_test
.sys_note:
    mov al, [menu_owner_pid]
    mov [system_menu_window], al
    mov bx, [note_x]
    mov bp, [note_y]
    jmp .sys_app_icon_test
.sys_calc:
    mov al, [menu_owner_pid]
    mov [system_menu_window], al
    mov bx, [calc_x]
    mov bp, [calc_y]
.sys_app_icon_test:
    mov cx, bx
    add cx, 4
    mov dx, bp
    add dx, 6
    mov si, CTRL_W
    mov di, CTRL_H
    call hit_rect
    jnc .sys_app_test
    mov al, [system_menu_window]
    call system_box_click
    stc
    ret
.sys_app_test:
    mov cx, bx
    add cx, 4
    mov dx, bp
    add dx, 18
    mov si, 104
    mov di, 68
    call hit_rect
    jnc .outside
    mov ax, [mouse_y]
    sub ax, bp
    cmp ax, 31
    jb .sys_restore
    cmp ax, 44
    jb .sys_move
    cmp ax, 57
    jb .sys_minimize
    cmp ax, 70
    jb .sys_maximize
    jmp .sys_close
.sys_restore:
    mov al, [system_menu_window]
    call restore_window_by_id
    stc
    ret
.sys_move:
    mov al, [system_menu_window]
    inc al
    mov [keyboard_move_mode], al
    mov byte [menu_open], MENU_NONE
    call redraw_all
    stc
    ret
.sys_minimize:
    mov al, [system_menu_window]
    call minimize_window_by_id
    stc
    ret
.sys_maximize:
    mov byte [menu_open], MENU_NONE
    mov al, [system_menu_window]
    call toggle_maximize
    stc
    ret
.sys_close:
    mov al, [system_menu_window]
    call close_window_by_id
    stc
    ret
.open_paint:
    call open_paint_foreground
    stc
    ret
.open_note:
    call open_notepad_foreground
    stc
    ret
.outside:
    clc
    ret

process_main_click:
    mov cx, [main_x]
    add cx, 4
    mov dx, [main_y]
    add dx, 6
    mov si, CTRL_W
    mov di, CTRL_H
    call hit_rect
    jnc .controls
    mov ax, [main_x]
    add ax, 4
    mov bx, [main_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_empty
    mov di, BTN_SYS_MENU
    call try_capture_button
    ret
.controls:
    mov ax, [main_x]
    add ax, [main_w]
    sub ax, 21
    mov bx, [main_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_close
    mov di, BTN_MAIN_CLOSE
    call try_capture_button
    jc .done
    mov ax, [main_x]
    add ax, [main_w]
    sub ax, 40
    mov bx, [main_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_max
    cmp byte [main_maximized], 0
    je .max_label
    mov si, str_restore
.max_label:
    mov di, BTN_MAIN_MAX
    call try_capture_button
    jc .done
    mov ax, [main_x]
    add ax, [main_w]
    sub ax, 59
    mov bx, [main_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_min
    mov di, BTN_MAIN_MIN
    call try_capture_button
    jc .done

    mov cx, [main_x]
    add cx, 4
    mov dx, [main_y]
    add dx, 22
    mov si, 40
    mov di, MENU_H
    call hit_rect
    jc .menu_file
    mov cx, [main_x]
    add cx, 44
    mov dx, [main_y]
    add dx, 22
    mov si, 40
    mov di, MENU_H
    call hit_rect
    jc .menu_apps
    mov cx, [main_x]
    add cx, 84
    mov dx, [main_y]
    add dx, 22
    mov si, 48
    mov di, MENU_H
    call hit_rect
    jc .menu_help

    cmp byte [main_maximized], 0
    jne .content
    mov cx, [main_x]
    add cx, [main_w]
    sub cx, 9
    mov dx, [main_y]
    add dx, [main_h]
    sub dx, 9
    mov si, 9
    mov di, 9
    call hit_rect
    jc .start_resize
    mov cx, [main_x]
    add cx, 24
    mov dx, [main_y]
    add dx, 4
    mov si, [main_w]
    sub si, 87
    mov di, TITLE_H-2
    call hit_rect
    jc .start_drag
.content:
    call main_compute_app_layout
    mov ax, [main_app_x1]
    mov bx, [main_y]
    add bx, 63
    mov cx, [main_app_btn_w]
    mov dx, 28
    mov si, str_paint
    mov di, BTN_MAIN_PAINT
    call try_capture_button
    jc .done
    mov ax, [main_app_x2]
    mov bx, [main_y]
    add bx, 63
    mov cx, [main_app_btn_w]
    mov dx, 28
    mov si, str_notepad_short
    mov di, BTN_MAIN_NOTE
    call try_capture_button
    jc .done
    mov ax, [main_app_x3]
    mov bx, [main_y]
    add bx, 99
    mov cx, [main_app_btn_w]
    mov dx, 28
    mov si, str_calc_short
    mov di, BTN_MAIN_CALC
    call try_capture_button
    jc .done
    mov ax, [main_app_x4]
    mov bx, [main_y]
    add bx, 99
    mov cx, [main_app_btn_w_last]
    mov dx, 28
    mov si, str_control
    mov di, BTN_MAIN_CONTROL
    call try_capture_button
    jc .done
    mov ax, [main_app_x1]
    mov bx, [main_y]
    add bx, 133
    mov cx, [main_app_btn_w]
    mov dx, 24
    mov si, str_debug
    mov di, BTN_MAIN_DEBUG
    call try_capture_button
    jc .done
    mov ax, [main_app_x2]
    mov bx, [main_y]
    add bx, 133
    mov cx, [main_app_btn_w_last]
    mov dx, 24
    mov si, str_custom_program
    mov di, BTN_MAIN_CUSTOM
    call try_capture_button
.done:
    ret
.menu_file:
    mov byte [menu_owner_pid], WIN_MAIN
    mov byte [menu_open], MENU_MAIN_FILE
    call redraw_all
    ret
.menu_apps:
    mov byte [menu_owner_pid], WIN_MAIN
    mov byte [menu_open], MENU_MAIN_APPS
    call redraw_all
    ret
.menu_help:
    mov byte [menu_owner_pid], WIN_MAIN
    mov byte [menu_open], MENU_MAIN_HELP
    call redraw_all
    ret
.start_drag:
    mov byte [drag_mode], 1
    mov byte [drag_pid], WIN_MAIN
    mov ax, [mouse_x]
    sub ax, [main_x]
    mov [drag_dx], ax
    mov ax, [mouse_y]
    sub ax, [main_y]
    mov [drag_dy], ax
    ret
.start_resize:
    mov byte [drag_mode], 5
    mov byte [drag_pid], WIN_MAIN
    mov ax, [main_w]
    mov [resize_start_w], ax
    mov ax, [main_h]
    mov [resize_start_h], ax
    mov ax, [mouse_x]
    mov [resize_start_x], ax
    mov ax, [mouse_y]
    mov [resize_start_y], ax
    ret

process_paint_click:
    ; The RGB dialog is modal inside Paint.
    call paint_palette_click
    jc .done
    mov cx, [paint_x]
    add cx, 4
    mov dx, [paint_y]
    add dx, 6
    mov si, CTRL_W
    mov di, CTRL_H
    call hit_rect
    jnc .controls
    mov ax, [paint_x]
    add ax, 4
    mov bx, [paint_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_empty
    mov di, BTN_SYS_MENU
    call try_capture_button
    ret
.controls:
    mov ax, [paint_x]
    add ax, [paint_w]
    sub ax, 21
    mov bx, [paint_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_close
    mov di, BTN_PAINT_CLOSE
    call try_capture_button
    jc .done
    mov ax, [paint_x]
    add ax, [paint_w]
    sub ax, 40
    mov bx, [paint_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_max
    cmp byte [paint_maximized], 0
    je .max_label
    mov si, str_restore
.max_label:
    mov di, BTN_PAINT_MAX
    call try_capture_button
    jc .done
    mov ax, [paint_x]
    add ax, [paint_w]
    sub ax, 59
    mov bx, [paint_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_min
    mov di, BTN_PAINT_MIN
    call try_capture_button
    jc .done

    mov cx, [paint_x]
    add cx, 4
    mov dx, [paint_y]
    add dx, 22
    mov si, 40
    mov di, MENU_H
    call hit_rect
    jc .menu_file
    mov cx, [paint_x]
    add cx, 44
    mov dx, [paint_y]
    add dx, 22
    mov si, 40
    mov di, MENU_H
    call hit_rect
    jc .menu_edit
    mov cx, [paint_x]
    add cx, 84
    mov dx, [paint_y]
    add dx, 22
    mov si, 48
    mov di, MENU_H
    call hit_rect
    jc .menu_view

    cmp byte [paint_maximized], 0
    jne .toolbar
    mov cx, [paint_x]
    add cx, [paint_w]
    sub cx, 9
    mov dx, [paint_y]
    add dx, [paint_h]
    sub dx, 9
    mov si, 9
    mov di, 9
    call hit_rect
    jc .start_resize
    mov cx, [paint_x]
    add cx, 24
    mov dx, [paint_y]
    add dx, 4
    mov si, [paint_w]
    sub si, 87
    mov di, TITLE_H-2
    call hit_rect
    jc .start_drag
.toolbar:
    xor bx, bx
.tool_loop:
    cmp bx, PAINT_TOOL_COUNT
    jae .palette
    mov ax, bx
    and ax, 1
    mov cx, 25
    mul cx
    add ax, [paint_x]
    add ax, 5
    mov cx, ax
    mov ax, bx
    shr ax, 1
    mov dx, 21
    mul dx
    add ax, [paint_y]
    add ax, 39
    mov dx, ax
    mov si, 23
    mov di, 19
    call hit_rect
    jc .choose_tool
    inc bx
    jmp .tool_loop
.choose_tool:
    cmp byte [paint_tool], PAINT_TOOL_SELECT
    jne .check_text_tool
    cmp bl, PAINT_TOOL_SELECT
    je .check_text_tool
    push bx
    call paint_selection_confirm
    pop bx
.check_text_tool:
    ; Leaving Text commits the editable object into the canvas before the new
    ; tool is selected.  This removes the box and makes the text erasable.
    cmp byte [paint_tool], PAINT_TOOL_TEXT
    jne .set_tool
    cmp bl, PAINT_TOOL_TEXT
    je .set_tool
    push bx
    call paint_commit_text_objects
    pop bx
    ; paint_commit_text_objects rasterizes glyphs and clears all object records.
    ; Clear the scratch selection as well so no stale frame can survive a tool switch.
    mov byte [paint_text_selected], 0xFF
    mov byte [paint_text_input], 0
.set_tool:
    mov [paint_tool], bl
    mov byte [paint_eraser], 0
    cmp bl, PAINT_TOOL_ERASER
    jne .tool_ready
    mov byte [paint_eraser], 1
.tool_ready:
    mov byte [paint_text_input], 0
    mov byte [paint_pending_action], PAINT_PENDING_NONE
    mov byte [paint_live_active], 0
    mov byte [paint_live_started], 0
    mov byte [paint_live_prev_valid], 0
    call proc_save
    call redraw_all
    ret
.palette:
    xor bx, bx
.palette_loop:
    cmp bx, 8
    jae .custom_swatch
    mov ax, bx
    mov cx, 15
    mul cx
    add ax, [paint_x]
    add ax, 60
    mov cx, ax
    mov dx, [paint_y]
    add dx, 41
    mov si, 12
    mov di, 12
    call hit_rect
    jc .choose_color
    inc bx
    jmp .palette_loop
.choose_color:
    cmp bx, 7
    je .choose_rainbow
    mov si, palette_colors
    add si, bx
    mov al, [si]
    mov [paint_color], al
    mov byte [paint_rainbow], 0
    mov byte [paint_eraser], 0
    mov byte [paint_custom_active], 0
    call paint_index_to_rgb
    call paint_apply_color_to_selected
    call proc_save
    call redraw_all
    ret
.choose_rainbow:
    mov byte [paint_rainbow], 1
    mov byte [paint_eraser], 0
    mov byte [paint_custom_active], 0
    mov byte [paint_rainbow_phase], 0
    call proc_save
    call redraw_all
    ret
.custom_swatch:
    call paint_compute_palette_controls
    mov cx, [paint_custom_x]
    mov dx, [paint_y]
    add dx, 41
    mov si, 12
    mov di, 12
    call hit_rect
    jnc .buttons
    mov al, [paint_custom_color]
    mov [paint_color], al
    mov byte [paint_custom_active], 1
    mov byte [paint_rainbow], 0
    mov byte [paint_eraser], 0
    call paint_index_to_rgb
    call paint_apply_color_to_selected
    call proc_save
    call redraw_all
    ret
.buttons:
    mov ax, [paint_rgb_button_x]
    mov bx, [paint_y]
    add bx, 39
    mov cx, 38
    mov dx, 18
    mov si, str_palette
    mov di, BTN_PAINT_PALETTE
    call try_capture_button
    jc .done
    mov ax, [paint_clear_button_x]
    mov bx, [paint_y]
    add bx, 39
    mov cx, 52
    mov dx, 18
    mov si, str_clear
    mov di, BTN_PAINT_CLEAR
    call try_capture_button
    jc .done
    call paint_try_scrollbar_click
    jc .done

    ; Click-only tools execute at the cursor hotspot that was visibly drawn,
    ; not at a transient mouse transition packet. This fixes Fill/Eyedropper
    ; sampling the far-left pixel shown in the reported bug.
    cmp byte [paint_tool], PAINT_TOOL_FILL
    je .one_shot
    cmp byte [paint_tool], PAINT_TOOL_TEXT
    je .one_shot
    cmp byte [paint_tool], PAINT_TOOL_EYEDROP
    je .one_shot
    cmp byte [paint_tool], PAINT_TOOL_LINE
    je .shape
    cmp byte [paint_tool], PAINT_TOOL_RECT
    je .shape
    cmp byte [paint_tool], PAINT_TOOL_ELLIPSE
    je .shape
    cmp byte [paint_tool], PAINT_TOOL_SELECT
    je .select
    cmp byte [paint_tool], PAINT_TOOL_MAGNIFY
    je .magnify
    call paint_get_local
    jnc .outside
    mov [paint_target_x], ax
    mov [paint_target_y], bx
    call paint_begin_stroke
    ret
.shape:
    call paint_get_visible_cursor_local
    jc .shape_ready
    call paint_get_hover_local
    jc .shape_ready
    call paint_get_local
    jnc .outside
.shape_ready:
    call paint_begin_shape
    ret
.select:
    call paint_get_local
    jnc .outside
    call paint_selection_begin
    ret
.magnify:
    call paint_get_local
    jnc .outside
    cmp byte [paint_zoom], 4
    jae .magnify_reset
    inc byte [paint_zoom]
    mov [paint_scroll_x], ax
    mov [paint_scroll_y], bx
    call paint_clamp_scroll
    call proc_save
    call redraw_all
    ret
.magnify_reset:
    mov byte [paint_zoom], 1
    mov word [paint_scroll_x], 0
    mov word [paint_scroll_y], 0
    call proc_save
    call redraw_all
    ret
.one_shot:
    call paint_get_visible_cursor_local
    jc .one_shot_ready
    call paint_get_hover_local
    jc .one_shot_ready
    call paint_get_local
    jnc .outside
.one_shot_ready:
    mov [paint_target_x], ax
    mov [paint_target_y], bx
    cmp byte [paint_tool], PAINT_TOOL_FILL
    je .fill
    cmp byte [paint_tool], PAINT_TOOL_TEXT
    je .text
    call paint_pick_color
    ret
.fill:
    call paint_flood_fill
    ret
.text:
    call paint_text_click
    ret
.outside:
    mov byte [paint_text_input], 0
    call proc_save
    call redraw_all
.done:
    ret
.menu_file:
    mov al, [active_pid]
    mov [menu_owner_pid], al
    mov byte [menu_open], MENU_PAINT_FILE
    call redraw_all
    ret
.menu_edit:
    mov al, [active_pid]
    mov [menu_owner_pid], al
    mov byte [menu_open], MENU_PAINT_EDIT
    call redraw_all
    ret
.menu_view:
    mov al, [active_pid]
    mov [menu_owner_pid], al
    mov byte [menu_open], MENU_PAINT_VIEW
    call redraw_all
    ret
.start_drag:
    mov byte [drag_mode], 2
    mov al, [active_pid]
    mov [drag_pid], al
    mov ax, [mouse_x]
    sub ax, [paint_x]
    mov [drag_dx], ax
    mov ax, [mouse_y]
    sub ax, [paint_y]
    mov [drag_dy], ax
    ret
.start_resize:
    mov byte [drag_mode], 5
    mov al, [active_pid]
    mov [drag_pid], al
    mov ax, [paint_w]
    mov [resize_start_w], ax
    mov ax, [paint_h]
    mov [resize_start_h], ax
    mov ax, [mouse_x]
    mov [resize_start_x], ax
    mov ax, [mouse_y]
    mov [resize_start_y], ax
    ret

process_note_click:
    mov cx, [note_x]
    add cx, 4
    mov dx, [note_y]
    add dx, 6
    mov si, CTRL_W
    mov di, CTRL_H
    call hit_rect
    jnc .controls
    mov ax, [note_x]
    add ax, 4
    mov bx, [note_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_empty
    mov di, BTN_SYS_MENU
    call try_capture_button
    ret
.controls:
    mov ax, [note_x]
    add ax, [note_w]
    sub ax, 21
    mov bx, [note_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_close
    mov di, BTN_NOTE_CLOSE
    call try_capture_button
    jc .done
    mov ax, [note_x]
    add ax, [note_w]
    sub ax, 40
    mov bx, [note_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_max
    cmp byte [note_maximized], 0
    je .max_label
    mov si, str_restore
.max_label:
    mov di, BTN_NOTE_MAX
    call try_capture_button
    jc .done
    mov ax, [note_x]
    add ax, [note_w]
    sub ax, 59
    mov bx, [note_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_min
    mov di, BTN_NOTE_MIN
    call try_capture_button
    jc .done

    mov cx, [note_x]
    add cx, 4
    mov dx, [note_y]
    add dx, 22
    mov si, 40
    mov di, MENU_H
    call hit_rect
    jc .menu_file
    mov cx, [note_x]
    add cx, 44
    mov dx, [note_y]
    add dx, 22
    mov si, 40
    mov di, MENU_H
    call hit_rect
    jc .menu_edit
    mov cx, [note_x]
    add cx, 84
    mov dx, [note_y]
    add dx, 22
    mov si, 48
    mov di, MENU_H
    call hit_rect
    jc .menu_help

    cmp byte [note_maximized], 0
    jne .scrollbar
    mov cx, [note_x]
    add cx, [note_w]
    sub cx, 9
    mov dx, [note_y]
    add dx, [note_h]
    sub dx, 9
    mov si, 9
    mov di, 9
    call hit_rect
    jc .start_resize
.scrollbar:
    call note_compute_layout
    mov ax, [note_scrollbar_x]
    mov bx, [note_scrollbar_y]
    mov cx, NOTE_SCROLL_W
    mov dx, NOTE_SCROLL_W
    mov si, str_scroll_up
    mov di, BTN_NOTE_SCROLL_UP
    call try_capture_button
    jc .done
    mov ax, [note_scrollbar_x]
    mov bx, [note_scrollbar_y]
    add bx, [note_text_h_dyn]
    sub bx, NOTE_SCROLL_W
    mov cx, NOTE_SCROLL_W
    mov dx, NOTE_SCROLL_W
    mov si, str_scroll_down
    mov di, BTN_NOTE_SCROLL_DOWN
    call try_capture_button
    jc .done

    mov cx, [note_scrollbar_x]
    mov dx, [note_track_y]
    mov si, NOTE_SCROLL_W
    mov di, [note_track_h]
    call hit_rect
    jnc .after_scrollbar
    call notepad_compute_scrollbar
    mov ax, [mouse_y]
    cmp ax, [note_thumb_y]
    jb .scroll_page_up
    mov bx, [note_thumb_y]
    add bx, [note_thumb_h]
    cmp ax, bx
    jae .scroll_page_down
    mov byte [drag_mode], 6
    mov al, [active_pid]
    mov [drag_pid], al
    mov ax, [mouse_y]
    sub ax, [note_thumb_y]
    mov [note_thumb_drag_offset], ax
    ret
.scroll_page_up:
    call notepad_scroll_page_up
    ret
.scroll_page_down:
    call notepad_scroll_page_down
    ret
.after_scrollbar:
    cmp byte [note_maximized], 0
    jne .text
    mov cx, [note_x]
    add cx, 24
    mov dx, [note_y]
    add dx, 4
    mov si, [note_w]
    sub si, 87
    mov di, TITLE_H-2
    call hit_rect
    jc .start_drag
.text:
    call notepad_mouse_to_index
    jnc .unfocus
    mov [note_cursor], ax
    mov [note_anchor], ax
    mov byte [note_sel_active], 0
    mov byte [note_mouse_select], 1
    mov al, [active_pid]
    mov [interaction_pid], al
    mov byte [note_focus], 1
    call notepad_ensure_cursor_visible
    call redraw_all
    ret
.unfocus:
    mov byte [note_focus], 0
    mov byte [note_mouse_select], 0
    call redraw_all
.done:
    ret
.menu_file:
    mov al, [active_pid]
    mov [menu_owner_pid], al
    mov byte [menu_open], MENU_NOTE_FILE
    call redraw_all
    ret
.menu_edit:
    mov al, [active_pid]
    mov [menu_owner_pid], al
    mov byte [menu_open], MENU_NOTE_EDIT
    call redraw_all
    ret
.menu_help:
    mov al, [active_pid]
    mov [menu_owner_pid], al
    mov byte [menu_open], MENU_NOTE_HELP
    call redraw_all
    ret
.start_drag:
    mov byte [drag_mode], 3
    mov al, [active_pid]
    mov [drag_pid], al
    mov ax, [mouse_x]
    sub ax, [note_x]
    mov [drag_dx], ax
    mov ax, [mouse_y]
    sub ax, [note_y]
    mov [drag_dy], ax
    ret
.start_resize:
    mov byte [drag_mode], 5
    mov al, [active_pid]
    mov [drag_pid], al
    mov ax, [note_w]
    mov [resize_start_w], ax
    mov ax, [note_h]
    mov [resize_start_h], ax
    mov ax, [mouse_x]
    mov [resize_start_x], ax
    mov ax, [mouse_y]
    mov [resize_start_y], ax
    ret

process_calc_click:
    mov cx, [calc_x]
    add cx, 4
    mov dx, [calc_y]
    add dx, 6
    mov si, CTRL_W
    mov di, CTRL_H
    call hit_rect
    jnc .controls
    mov ax, [calc_x]
    add ax, 4
    mov bx, [calc_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_empty
    mov di, BTN_SYS_MENU
    call try_capture_button
    ret
.controls:
    mov ax, [calc_x]
    add ax, [calc_w]
    sub ax, 21
    mov bx, [calc_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_close
    mov di, BTN_CALC_CLOSE
    call try_capture_button
    jc .done
    mov ax, [calc_x]
    add ax, [calc_w]
    sub ax, 40
    mov bx, [calc_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_max
    cmp byte [calc_maximized], 0
    je .max_label
    mov si, str_restore
.max_label:
    mov di, BTN_CALC_MAX
    call try_capture_button
    jc .done
    mov ax, [calc_x]
    add ax, [calc_w]
    sub ax, 59
    mov bx, [calc_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_min
    mov di, BTN_CALC_MIN
    call try_capture_button
    jc .done

    mov cx, [calc_x]
    add cx, 4
    mov dx, [calc_y]
    add dx, 22
    mov si, 48
    mov di, MENU_H
    call hit_rect
    jc .menu_file
    mov cx, [calc_x]
    add cx, 52
    mov dx, [calc_y]
    add dx, 22
    mov si, 48
    mov di, MENU_H
    call hit_rect
    jc .menu_help

    cmp byte [calc_maximized], 0
    jne .keys
    mov cx, [calc_x]
    add cx, [calc_w]
    sub cx, 9
    mov dx, [calc_y]
    add dx, [calc_h]
    sub dx, 9
    mov si, 9
    mov di, 9
    call hit_rect
    jc .start_resize
    mov cx, [calc_x]
    add cx, 24
    mov dx, [calc_y]
    add dx, 4
    mov si, [calc_w]
    sub si, 87
    mov di, TITLE_H-2
    call hit_rect
    jc .start_drag
.keys:
    call calc_compute_layout
    mov word [calc_key_index], 0
.key_loop:
    cmp word [calc_key_index], 20
    jae .done
    call calc_get_key_rect
    ; Save the rectangle before reading the action byte. The old code loaded
    ; the action into AL and therefore destroyed the low byte of AX (key x).
    push ax
    push bx
    push cx
    push dx
    mov si, [calc_key_index]
    xor ax, ax
    mov al, [calc_key_actions+si]
    mov [temp_action], ax
    shl si, 1
    mov si, [calc_key_labels_early+si]
    mov di, [temp_action]
    pop dx
    pop cx
    pop bx
    pop ax
    call try_capture_button
    jc .done
    inc word [calc_key_index]
    jmp .key_loop
.done:
    ret
.menu_file:
    mov al, [active_pid]
    mov [menu_owner_pid], al
    mov byte [menu_open], MENU_CALC_FILE
    call redraw_all
    ret
.menu_help:
    mov al, [active_pid]
    mov [menu_owner_pid], al
    mov byte [menu_open], MENU_CALC_HELP
    call redraw_all
    ret
.start_drag:
    mov byte [drag_mode], 4
    mov al, [active_pid]
    mov [drag_pid], al
    mov ax, [mouse_x]
    sub ax, [calc_x]
    mov [drag_dx], ax
    mov ax, [mouse_y]
    sub ax, [calc_y]
    mov [drag_dy], ax
    ret
.start_resize:
    mov byte [drag_mode], 5
    mov al, [active_pid]
    mov [drag_pid], al
    mov ax, [calc_w]
    mov [resize_start_w], ax
    mov ax, [calc_h]
    mov [resize_start_h], ax
    mov ax, [mouse_x]
    mov [resize_start_x], ax
    mov ax, [mouse_y]
    mov [resize_start_y], ax
    ret

mouse_left_hold:
    cmp byte [custom_resize_drag], 0
    je .not_custom_resize
    call CUSTOM_CODE_SEG:custom_entry_resize_drag
    ret
.not_custom_resize:
    cmp byte [custom_scroll_drag], 0
    je .not_custom_scroll
    call CUSTOM_CODE_SEG:custom_entry_scroll_drag
    ret
.not_custom_scroll:
    cmp byte [custom_mouse_select], 0
    je .not_custom_select
    call CUSTOM_CODE_SEG:custom_entry_mouse_select
    ret
.not_custom_select:
    cmp byte [debug_scroll_drag], 0
    je .not_debug_scroll
    call update_debug_scroll_drag
    ret
.not_debug_scroll:
    cmp byte [control_slider_drag], 0
    je .not_control_slider
    call control_update_slider
    ret
.not_control_slider:
    cmp byte [captured_button], BTN_NONE
    jne .button
    cmp byte [drag_mode], 1
    je update_main_drag
    cmp byte [drag_mode], 6
    je update_note_scroll_drag
    cmp byte [drag_mode], 8
    je update_control_drag
    cmp byte [drag_mode], 7
    je update_palette_drag
    cmp byte [drag_mode], 9
    je update_paint_hscroll_drag
    cmp byte [drag_mode], 10
    je update_paint_vscroll_drag
    cmp byte [drag_mode], 5
    je update_resize_drag
    cmp byte [drag_mode], 0
    je .interaction
    mov al, [drag_pid]
    call proc_load
    cmp byte [drag_mode], 2
    je update_paint_drag
    cmp byte [drag_mode], 3
    je update_note_drag
    cmp byte [drag_mode], 4
    je update_calc_drag
    ret
.interaction:
    mov al, [interaction_pid]
    test al, al
    jz .done
    call proc_load
    mov al, [active_type]
    cmp al, APP_NOTEPAD
    je .note
    cmp al, APP_PAINT
    je .paint
    jmp .done
.note:
    cmp byte [note_mouse_select], 0
    je .done
    call notepad_mouse_to_index
    jnc .done
    cmp ax, [note_cursor]
    je .done
    mov [note_cursor], ax
    mov dx, [note_anchor]
    cmp ax, dx
    jne .selected
    mov byte [note_sel_active], 0
    jmp .selection_ready
.selected:
    mov byte [note_sel_active], 1
.selection_ready:
    call notepad_ensure_cursor_visible
    call redraw_all
    ret
.paint:
    cmp byte [paint_select_drag], 0
    je .paint_text_select
    call paint_selection_update
    ret
.paint_text_select:
    cmp byte [paint_text_mouse_select], 0
    je .paint_pending
    call paint_get_local
    jnc .done
    call paint_text_point_to_index
    jnc .done
    cmp ax, [paint_text_cursor]
    je .done
    mov [paint_text_cursor], ax
    mov dx, [paint_text_anchor]
    cmp ax, dx
    jne .text_selected
    mov byte [paint_text_sel_active], 0
    jmp .text_redraw
.text_selected:
    mov byte [paint_text_sel_active], 1
.text_redraw:
    call proc_save
    call redraw_all
    ret
.paint_pending:
    cmp byte [paint_pending_action], PAINT_PENDING_NONE
    je .paint_live
    mov al, [foreground_window]
    cmp al, [active_pid]
    jne .done
    call paint_update_pending_action
    ret
.paint_live:
    cmp byte [paint_live_active], 0
    je .done
    mov al, [foreground_window]
    cmp al, [active_pid]
    jne .done
    call paint_continue_stroke
    call proc_save
    ret
.button:
    call capture_pointer_inside
    mov al, 0
    jnc .state
    mov al, 1
.state:
    cmp al, [capture_inside]
    je .done
    mov [capture_inside], al
    call redraw_all
.done:
    ret

mouse_left_up:
    cmp byte [custom_resize_drag], 0
    je .not_custom_resize
    mov byte [custom_resize_drag], 0
    ret
.not_custom_resize:
    cmp byte [custom_scroll_drag], 0
    je .not_custom_scroll
    mov byte [custom_scroll_drag], 0
    ret
.not_custom_scroll:
    cmp byte [custom_mouse_select], 0
    je .not_custom_select
    mov byte [custom_mouse_select], 0
    ret
.not_custom_select:
    cmp byte [debug_scroll_drag], 0
    je .not_debug_scroll
    mov byte [debug_scroll_drag], 0
    ret
.not_debug_scroll:
    cmp byte [control_slider_drag], 0
    je .normal_release
    mov byte [control_slider_drag], 0
    ret
.normal_release:
    mov byte [drag_mode], 0
    mov al, [interaction_pid]
    test al, al
    jz .clear_live
    call proc_load
    cmp byte [active_type], APP_PAINT
    jne .interaction_ready
    cmp byte [paint_select_drag], 0
    je .paint_normal_finish
    call paint_selection_finish
    jmp .interaction_ready
.paint_normal_finish:
    call paint_execute_pending_action
    jc .interaction_ready
    call paint_finalize_stroke
.interaction_ready:
    mov byte [painting_active], 0
    mov byte [paint_prev_valid], 0
    mov byte [note_mouse_select], 0
    mov byte [paint_text_mouse_select], 0
    call proc_save
.clear_live:
    mov byte [paint_live_active], 0
    mov byte [paint_live_started], 0
    mov byte [paint_live_prev_valid], 0
    mov byte [paint_pending_action], PAINT_PENDING_NONE
.after_interaction:
    mov byte [interaction_pid], 0
    cmp byte [captured_button], BTN_NONE
    je .done
    call capture_pointer_inside
    mov al, [captured_button]
    mov dl, [captured_pid]
    mov byte [captured_button], BTN_NONE
    mov byte [capture_inside], 0
    jnc .cancel
    push ax
    mov al, dl
    cmp al, WIN_MAIN
    jne .load_app_target
    mov byte [active_pid], WIN_MAIN
    mov byte [active_type], APP_NONE
    mov word [active_data_seg], 0
    jmp .target_loaded
.load_app_target:
    call proc_load
.target_loaded:
    pop ax
    call dispatch_button_action
    ret
.cancel:
    call redraw_all
.done:
    ret

dispatch_button_action:
    cmp al, BTN_TASK_CUSTOM
    je .custom_restore
    cmp al, BTN_TASK_BASE
    jb .regular
    cmp al, BTN_TASK_BASE+MAX_PROCS
    jae .regular
    sub al, BTN_TASK_BASE
    cmp byte [custom_open], 0
    je .restore_regular_task
    mov byte [custom_open], 0
    mov byte [custom_minimized], 1
    mov byte [custom_resize_drag], 0
    mov byte [custom_scroll_drag], 0
    mov byte [custom_mouse_select], 0
.restore_regular_task:
    call proc_restore
    ret
.regular:
    cmp al, BTN_MAIN_MIN
    je .main_min
    cmp al, BTN_MAIN_MAX
    je .main_max
    cmp al, BTN_MAIN_CLOSE
    je .main_close
    cmp al, BTN_MAIN_PAINT
    je .open_paint
    cmp al, BTN_MAIN_NOTE
    je .open_note
    cmp al, BTN_MAIN_CALC
    je .open_calc
    cmp al, BTN_MAIN_CONTROL
    je .open_control
    cmp al, BTN_MAIN_DEBUG
    je .open_debug
    cmp al, BTN_MAIN_CUSTOM
    je .open_custom
    cmp al, BTN_PAINT_MIN
    je .paint_min
    cmp al, BTN_PAINT_MAX
    je .paint_max
    cmp al, BTN_PAINT_CLOSE
    je .paint_close
    cmp al, BTN_PAINT_CLEAR
    je .paint_clear
    cmp al, BTN_PAINT_PALETTE
    je .paint_palette
    cmp al, BTN_PALETTE_CLOSE
    je .paint_palette_close
    cmp al, BTN_PALETTE_OK
    je .paint_palette_ok
    cmp al, BTN_NOTE_MIN
    je .note_min
    cmp al, BTN_NOTE_MAX
    je .note_max
    cmp al, BTN_NOTE_CLOSE
    je .note_close
    cmp al, BTN_NOTE_SCROLL_UP
    je .note_scroll_up
    cmp al, BTN_NOTE_SCROLL_DOWN
    je .note_scroll_down
    cmp al, BTN_NOTE_PAGE_UP
    je .note_page_up
    cmp al, BTN_NOTE_PAGE_DOWN
    je .note_page_down
    cmp al, BTN_CALC_MIN
    je .calc_min
    cmp al, BTN_CALC_MAX
    je .calc_max
    cmp al, BTN_CALC_CLOSE
    je .calc_close
    cmp al, BTN_SYS_MENU
    je .sys_menu
    cmp al, BTN_MSG_YES
    je .msg_yes
    cmp al, BTN_MSG_NO
    je .msg_close
    cmp al, BTN_MSG_CLOSE
    je .msg_close
    cmp al, BTN_MSG_OK
    je .msg_close
    cmp al, BTN_CONTROL_CLOSE
    je .control_close
    cmp al, BTN_CONTROL_SWAP
    je .control_swap
    cmp al, BTN_CONTROL_BOOT_DOS
    je .control_boot
    cmp al, BTN_CONTROL_AUTORESTART
    je .control_autorestart
    cmp al, BTN_DEBUG_CLOSE
    je .debug_close
    cmp al, BTN_DEBUG_INT_TEST
    je .debug_int_test
    cmp al, BTN_DEBUG_INT_EXEC
    je .debug_int_exec
    cmp al, BTN_DEBUG_BLUE
    je .debug_blue
    cmp al, BTN_DEBUG_BLUE_TOGGLE
    je .debug_blue_toggle
    cmp al, BTN_DEBUG_BLUE_CLOSE
    je .debug_blue_close
    cmp al, BTN_DEBUG_BLUE_REAL
    je .debug_blue_real
    cmp al, BTN_DEBUG_BLUE_PM
    je .debug_blue_pm
    cmp al, BTN_DEBUG_BLUE_LM
    je .debug_blue_lm
    cmp al, BTN_DEBUG_INT_CLOSE
    je .debug_int_close
    cmp al, BTN_DEBUG_SCROLL_UP
    je .debug_scroll_up
    cmp al, BTN_DEBUG_SCROLL_DOWN
    je .debug_scroll_down
    cmp al, BTN_DEBUG_INT_ITEM
    je .debug_int_item
    cmp al, BTN_DEBUG_PROTECTED
    je .debug_protected
    cmp al, BTN_DEBUG_LONG
    je .debug_long
    cmp al, BTN_DEBUG_FAULT
    je .debug_fault
    cmp al, BTN_DEBUG_FAULT_CLOSE
    je .debug_fault_close
    cmp al, BTN_DEBUG_FAULT_NORMAL
    je .debug_fault_normal
    cmp al, BTN_DEBUG_FAULT_DOUBLE
    je .debug_fault_double
    cmp al, BTN_DEBUG_FAULT_TRIPLE
    je .debug_fault_triple
    cmp al, BTN_DEBUG_NORMAL_CLOSE
    je .debug_normal_close
    cmp al, BTN_DEBUG_NORMAL_ITEM
    je .debug_normal_item
    cmp al, BTN_DEBUG_NORMAL_SCROLL_UP
    je .debug_scroll_up
    cmp al, BTN_DEBUG_NORMAL_SCROLL_DOWN
    je .debug_scroll_down
    cmp al, BTN_CUSTOM_CLOSE
    je .custom_close
    cmp al, BTN_CUSTOM_EXEC
    je .custom_exec
    cmp al, BTN_CUSTOM_SCROLL_UP
    je .custom_scroll_up
    cmp al, BTN_CUSTOM_SCROLL_DOWN
    je .custom_scroll_down
    cmp al, BTN_CUSTOM_HSCROLL_LEFT
    je .custom_hscroll_left
    cmp al, BTN_CUSTOM_HSCROLL_RIGHT
    je .custom_hscroll_right
    cmp al, BTN_CUSTOM_CONFIRM_YES
    je .custom_confirm_yes
    cmp al, BTN_CUSTOM_CONFIRM_NO
    je .custom_confirm_no
    cmp al, BTN_CUSTOM_CONFIRM_CANCEL
    je .custom_confirm_cancel
    cmp al, BTN_CUSTOM_EXEC_REAL
    je .custom_exec_real
    cmp al, BTN_CUSTOM_EXEC_PM
    je .custom_exec_pm
    cmp al, BTN_CUSTOM_EXEC_LM
    je .custom_exec_lm
    cmp al, BTN_CUSTOM_MIN
    je .custom_min
    cmp al, BTN_CUSTOM_MAX
    je .custom_max
    cmp al, BTN_CALC_7
    jb .done
    cmp al, BTN_CALC_BACK
    ja .done
    call calc_button_action
    ret
.main_min:
    call minimize_main
    ret
.main_max:
    mov al, WIN_MAIN
    call toggle_maximize
    ret
.main_close:
    call show_exit_confirmation
    ret
.open_paint:
    mov al, APP_PAINT
    call proc_create
    ret
.open_note:
    mov al, APP_NOTEPAD
    call proc_create
    ret
.open_calc:
    mov al, APP_CALC
    call proc_create
    ret
.open_control:
    call open_control_panel
    ret
.open_debug:
    call open_debug_panel
    ret
.open_custom:
    mov byte [drag_mode], 0
    mov byte [drag_pid], 0
    mov byte [interaction_pid], 0
    mov byte [captured_button], BTN_NONE
    mov byte [capture_inside], 0
    mov byte [menu_open], MENU_NONE
    call custom_launch_editor
    ret
.custom_restore:
    mov byte [custom_open], 1
    mov byte [custom_minimized], 0
    mov byte [menu_open], MENU_NONE
    call redraw_all
    ret
.paint_min:
    mov al, [active_pid]
    call proc_minimize
    ret
.paint_max:
    mov al, [active_pid]
    call toggle_maximize
    ret
.paint_close:
    mov al, [active_pid]
    call proc_close
    ret
.paint_clear:
    call paint_clear_with_undo
    ret
.paint_palette:
    mov byte [paint_palette_open], 1
    mov byte [paint_palette_positioned], 0
    mov byte [paint_rgb_focus], 1
    mov byte [paint_rgb_replace], 1
    mov al, [paint_color]
    call paint_index_to_rgb
    call proc_save
    call redraw_all
    ret
.paint_palette_close:
    mov byte [paint_palette_open], 0
    mov byte [paint_rgb_focus], 0
    mov byte [paint_rgb_replace], 0
    call proc_save
    call redraw_all
    ret
.paint_palette_ok:
    ; RGB values are previewed/applied live; OK commits by closing the dialog.
    mov byte [paint_palette_open], 0
    mov byte [paint_rgb_focus], 0
    mov byte [paint_rgb_replace], 0
    call proc_save
    call redraw_all
    ret
.note_min:
    mov al, [active_pid]
    call proc_minimize
    ret
.note_max:
    mov al, [active_pid]
    call toggle_maximize
    ret
.note_close:
    mov al, [active_pid]
    call proc_close
    ret
.note_scroll_up:
    call notepad_scroll_line_up
    ret
.note_scroll_down:
    call notepad_scroll_line_down
    ret
.note_page_up:
    call notepad_scroll_page_up
    ret
.note_page_down:
    call notepad_scroll_page_down
    ret
.calc_min:
    mov al, [active_pid]
    call proc_minimize
    ret
.calc_max:
    mov al, [active_pid]
    call toggle_maximize
    ret
.calc_close:
    mov al, [active_pid]
    call proc_close
    ret
.sys_menu:
    mov al, [active_pid]
    call system_box_click
    ret
.msg_yes:
    cmp byte [message_kind], MSG_EXIT_CONFIRM
    je .exit_yes
    cmp byte [message_kind], MSG_UNSAVED
    je .unsaved_yes
    cmp byte [message_kind], MSG_OVERWRITE
    je .overwrite_yes
    jmp .msg_close
.exit_yes:
    mov byte [message_open], 0
    jmp enter_dos_mode
.unsaved_yes:
    call handle_unsaved_yes
    ret
.overwrite_yes:
    call handle_overwrite_yes
    ret
.msg_close:
    mov byte [message_open], 0
    mov byte [pending_unsaved_pid], 0
    mov byte [pending_unsaved_action], 0
    call redraw_all
    ret
.control_close:
    mov byte [control_open], 0
    mov byte [control_slider_drag], 0
    call redraw_all
    ret
.control_swap:
    xor byte [mouse_swap_buttons], 1
    mov byte [mouse_buttons], 0
    mov byte [mouse_raw_buttons], 0
    mov byte [mouse_prev_buttons], 0
    call redraw_all
    ret
.control_boot:
    xor byte [control_boot_dos], 1
    call control_write_boot_setting
    jnc .control_boot_ok
    xor byte [control_boot_dos], 1
    mov si, str_control_write_error
    mov [system_message_ptr], si
    mov byte [message_kind], MSG_SYSTEM
    mov byte [message_open], 1
.control_boot_ok:
    call redraw_all
    ret
.control_autorestart:
    xor byte [control_autorestart], 1
    call control_write_boot_setting
    jnc .control_autorestart_ok
    xor byte [control_autorestart], 1
    mov si, str_control_write_error
    mov [system_message_ptr], si
    mov byte [message_kind], MSG_SYSTEM
    mov byte [message_open], 1
.control_autorestart_ok:
    call redraw_all
    ret
.debug_close:
    mov byte [debug_open], 0
    mov byte [debug_scroll_drag], 0
    call redraw_all
    ret
.debug_int_test:
    mov byte [debug_open], 2
    mov byte [debug_scroll_drag], 0
    mov word [debug_scroll_offset], 0
    call redraw_all
    ret
.debug_int_exec:
    mov byte [debug_open], 3
    mov byte [debug_scroll_drag], 0
    mov word [debug_scroll_offset], 0
    call redraw_all
    ret
.debug_blue:
    cmp byte [BLUESCREEN_ENABLE_ADDR], 0
    je .debug_blue_blocked
    mov byte [debug_open], 4
    mov byte [debug_scroll_drag], 0
    call redraw_all
    ret
.debug_blue_blocked:
    mov si, str_bluescreen_is_disabled
    mov [system_message_ptr], si
    mov byte [message_kind], MSG_SYSTEM
    mov byte [message_open], 1
    call redraw_all
    ret
.debug_blue_close:
    mov byte [debug_open], 1
    call redraw_all
    ret
.debug_fault:
    mov byte [debug_open], 5
    mov byte [debug_scroll_drag], 0
    call redraw_all
    ret
.debug_fault_close:
    mov byte [debug_open], 1
    mov byte [debug_scroll_drag], 0
    call redraw_all
    ret
.debug_fault_normal:
    mov byte [debug_open], 6
    mov byte [debug_scroll_drag], 0
    mov word [debug_scroll_offset], 0
    call redraw_all
    ret
.debug_normal_close:
    mov byte [debug_open], 5
    mov byte [debug_scroll_drag], 0
    call redraw_all
    ret
.debug_normal_item:
    xor bx, bx
    mov bl, [debug_pending_fault]
    mov al, [debug_normal_fault_vectors+bx]
    mov [debug_crash_code], al
    mov byte [debug_open], 0
    mov byte [debug_scroll_drag], 0
    mov byte [debug_mode_action], 1
    call debug_enter_protected_mode
    ret
.debug_fault_double:
    mov byte [debug_open], 0
    mov byte [debug_mode_action], 1
    mov byte [debug_crash_code], 8
    call debug_enter_protected_mode
    ret
.debug_fault_triple:
    cli
    lidt [system_reset_null_idtr]
    int 3
.debug_triple_pending:
    hlt
    jmp short .debug_triple_pending
.debug_blue_real:
    mov byte [debug_open], 0
    mov al, BSOD_STOP_MANUAL
    jmp system_blue_screen
.debug_blue_pm:
    mov byte [debug_open], 0
    mov byte [debug_mode_action], 1
    mov byte [debug_crash_code], BSOD_STOP_MANUAL
    call debug_enter_protected_mode
    ret
.debug_blue_lm:
    call debug_cpu_supports_long_mode
    jc .debug_long_failed
    mov byte [debug_open], 0
    mov byte [debug_mode_action], 1
    mov byte [debug_crash_code], BSOD_STOP_MANUAL
    call debug_enter_long_mode
    ret
.debug_blue_toggle:
    pushf
    cli
    cmp byte [BLUESCREEN_ENABLE_ADDR], 0
    je .debug_blue_enable
    mov byte [BLUESCREEN_ENABLE_ADDR], 0
    mov si, str_bluescreen_disabled
    jmp short .debug_blue_state_changed
.debug_blue_enable:
    mov byte [BLUESCREEN_ENABLE_ADDR], 1
    mov si, str_bluescreen_enabled
.debug_blue_state_changed:
    popf
    mov [system_message_ptr], si
    mov byte [message_kind], MSG_SYSTEM
    mov byte [message_open], 1
    call redraw_all
    ret
.debug_int_close:
    mov byte [debug_open], 1
    mov byte [debug_scroll_drag], 0
    call redraw_all
    ret
.debug_scroll_up:
    call debug_scroll_one_up
    ret
.debug_scroll_down:
    call debug_scroll_one_down
    ret
.debug_int_item:
    cmp byte [debug_open], 3
    je .debug_raw_int_item
    mov al, [debug_pending_int]
    call debug_run_interrupt_test
    ret
.debug_raw_int_item:
    call debug_execute_interrupt_raw
    ret
.debug_protected:
    mov byte [debug_open], 0
    mov byte [debug_scroll_drag], 0
    mov byte [debug_mode_action], 0
    call debug_enter_protected_mode
    ret
.debug_long:
    call debug_cpu_supports_long_mode
    jc .debug_long_failed
    mov byte [debug_open], 0
    mov byte [debug_scroll_drag], 0
    mov byte [debug_mode_action], 0
    call debug_enter_long_mode
    ret
.debug_long_failed:
    call debug_show_long_mode_failure
    ret
.custom_close:
    call CUSTOM_CODE_SEG:custom_entry_close
    ret
.custom_exec:
    call CUSTOM_CODE_SEG:custom_entry_execute
    ret
.custom_exec_real:
    call CUSTOM_CODE_SEG:custom_entry_execute_real
    ret
.custom_exec_pm:
    call CUSTOM_CODE_SEG:custom_entry_execute_pm
    ret
.custom_exec_lm:
    call CUSTOM_CODE_SEG:custom_entry_execute_lm
    ret
.custom_scroll_up:
    call CUSTOM_CODE_SEG:custom_entry_scroll_up
    ret
.custom_scroll_down:
    call CUSTOM_CODE_SEG:custom_entry_scroll_down
    ret
.custom_hscroll_left:
    call CUSTOM_CODE_SEG:custom_entry_hscroll_left
    ret
.custom_hscroll_right:
    call CUSTOM_CODE_SEG:custom_entry_hscroll_right
    ret
.custom_confirm_yes:
    call CUSTOM_CODE_SEG:custom_entry_confirm_yes
    ret
.custom_confirm_no:
    call CUSTOM_CODE_SEG:custom_entry_confirm_no
    ret
.custom_confirm_cancel:
    call CUSTOM_CODE_SEG:custom_entry_confirm_cancel
    ret
.custom_min:
    call CUSTOM_CODE_SEG:custom_entry_minimize
    ret
.custom_max:
    call CUSTOM_CODE_SEG:custom_entry_maximize
    ret
.done:
    ret

minimize_main:
    mov byte [main_minimized], 1
    mov byte [menu_open], MENU_NONE
    mov byte [drag_mode], 0
    call normalize_foreground
    call redraw_all
    ret

minimize_paint:
    mov al, [active_pid]
    jmp proc_minimize

close_paint:
    mov al, [active_pid]
    jmp proc_close

open_paint_foreground:
    mov al, APP_PAINT
    jmp proc_create

minimize_notepad:
    mov al, [active_pid]
    jmp proc_minimize

close_notepad:
    mov al, [active_pid]
    jmp proc_close

open_notepad_foreground:
    mov al, APP_NOTEPAD
    jmp proc_create

request_paint_new:
    cmp byte [app_dirty], 0
    je paint_new_force
    mov byte [pending_unsaved_action], 2
    mov al, [active_pid]
    jmp show_unsaved_prompt

paint_new_force:
    call paint_clear_with_undo
    mov byte [paint_zoom], 1
    mov word [paint_scroll_x], 0
    mov word [paint_scroll_y], 0
    call mark_active_clean
    call proc_save
    ret

request_notepad_new:
    cmp byte [app_dirty], 0
    je notepad_new_force
    mov byte [pending_unsaved_action], 3
    mov al, [active_pid]
    jmp show_unsaved_prompt

notepad_new_force:
    call clear_notepad
    call mark_active_clean
    call proc_save
    ret

clear_notepad:
    call notepad_save_undo
    mov word [note_len], 0
    mov word [note_cursor], 0
    mov word [note_anchor], 0
    mov word [note_scroll_row], 0
    mov byte [note_sel_active], 0
    push fs
    mov ax, [active_data_seg]
    mov fs, ax
    mov byte fs:[0], 0
    pop fs
    mov byte [menu_open], MENU_NONE
    call redraw_all
    ret

minimize_calc:
    mov al, [active_pid]
    jmp proc_minimize

close_calc:
    mov al, [active_pid]
    jmp proc_close

open_calc_foreground:
    mov al, APP_CALC
    jmp proc_create

calc_clear:
    mov dword [calc_acc], 0
    mov dword [calc_acc+4], 0
    mov dword [calc_acc+8], 0
    mov dword [calc_current], 0
    mov dword [calc_current+4], 0
    mov dword [calc_current+8], 0
    mov byte [calc_op], 0
    mov byte [calc_entry], 0
    mov byte [calc_error], 0
    mov byte [calc_result_fresh], 0
    mov byte [calc_decimal], 0
    mov byte [calc_frac_digits], 0
    mov byte [menu_open], MENU_NONE
    call redraw_all
    ret

show_system_message:
    mov word [system_message_ptr], 0
    mov byte [menu_open], MENU_NONE
    mov byte [message_kind], MSG_SYSTEM
    mov byte [message_open], 1
    mov byte [note_focus], 0
    call redraw_all
    ret

show_about:
    mov byte [menu_open], MENU_NONE
    mov byte [message_kind], MSG_ABOUT
    mov byte [message_open], 1
    call redraw_all
    ret

show_exit_confirmation:
    mov byte [menu_open], MENU_NONE
    mov byte [control_open], 0
    mov byte [message_kind], MSG_EXIT_CONFIRM
    mov byte [message_open], 1
    mov byte [note_focus], 0
    mov byte [note_mouse_select], 0
    call redraw_all
    ret

show_unsaved_prompt:
    ; AL=target process, pending_unsaved_action already selected.
    mov [pending_unsaved_pid], al
    mov byte [menu_open], MENU_NONE
    mov byte [control_open], 0
    mov byte [message_kind], MSG_UNSAVED
    mov byte [message_open], 1
    mov byte [note_focus], 0
    mov byte [note_mouse_select], 0
    call redraw_all
    ret

handle_unsaved_yes:
    call STAGE2_EXT_SEG:(handle_unsaved_yes_ext-stage2_ext_start)
    ret

; Ctrl+S creates the first saved copy immediately. Once a saved copy exists,
; only a modified document asks for confirmation before overwriting it.
request_app_save:
    call STAGE2_EXT_SEG:(request_app_save_ext-stage2_ext_start)
    ret

handle_overwrite_yes:
    call STAGE2_EXT_SEG:(handle_overwrite_yes_ext-stage2_ext_start)
    ret

mark_active_dirty:
    push ax
    push bx
    mov byte [app_dirty], 1
    xor bx, bx
    mov bl, [active_pid]
    cmp bx, MAX_PROCS
    jae .dirty_done
    mov byte [proc_dirty+bx], 1
.dirty_done:
    pop bx
    pop ax
    ret

mark_active_clean:
    push ax
    push bx
    mov byte [app_dirty], 0
    xor bx, bx
    mov bl, [active_pid]
    cmp bx, MAX_PROCS
    jae .clean_done
    mov byte [proc_dirty+bx], 0
.clean_done:
    pop bx
    pop ax
    ret

system_box_click:
    ; AL=pid. A second click within about half a second closes that instance.
    push ax
    push bx
    push dx
    mov dl, al
    mov bx, [0x046C]
    mov ax, bx
    sub ax, [last_sys_tick]
    cmp dl, [last_sys_window]
    jne .single
    cmp ax, 9
    ja .single
    mov byte [last_sys_window], 0xFF
    mov al, dl
    call proc_close
    jmp .done
.single:
    mov [last_sys_tick], bx
    mov [last_sys_window], dl
    mov [system_menu_window], dl
    mov [menu_owner_pid], dl
    cmp dl, WIN_MAIN
    jne .app
    mov byte [menu_open], MENU_SYS_MAIN
    jmp .draw
.app:
    xor bx, bx
    mov bl, dl
    mov al, [proc_type+bx]
    cmp al, APP_PAINT
    je .paint
    cmp al, APP_NOTEPAD
    je .note
    mov byte [menu_open], MENU_SYS_CALC
    jmp .draw
.paint:
    mov byte [menu_open], MENU_SYS_PAINT
    jmp .draw
.note:
    mov byte [menu_open], MENU_SYS_NOTE
.draw:
    call redraw_all
.done:
    pop dx
    pop bx
    pop ax
    ret

minimize_window_by_id:
    jmp proc_minimize

restore_window_by_id:
    push ax
    cmp al, WIN_MAIN
    jne .app
    mov byte [main_minimized], 0
    cmp byte [main_maximized], 0
    je .main_front
    mov al, WIN_MAIN
    call toggle_maximize
    pop ax
    ret
.main_front:
    mov al, WIN_MAIN
    call bring_to_front
    call redraw_all
    pop ax
    ret
.app:
    xor bx, bx
    mov bl, al
    mov byte [proc_minimized+bx], 0
    call proc_load
    cmp byte [proc_maximized+bx], 0
    je .app_front
    mov al, [active_pid]
    call toggle_maximize
    pop ax
    ret
.app_front:
    mov al, [active_pid]
    call bring_to_front
    call redraw_all
    pop ax
    ret

close_window_by_id:
    jmp proc_close

update_main_drag:
    cmp byte [main_maximized], 0
    jne .done
    mov ax, [mouse_x]
    sub ax, [drag_dx]
    mov [main_x], ax
    mov ax, [mouse_y]
    sub ax, [drag_dy]
    mov [main_y], ax
    call clamp_main_position
    call redraw_all
.done:
    ret

update_paint_drag:
    cmp byte [paint_maximized], 0
    jne .done
    mov ax, [mouse_x]
    sub ax, [drag_dx]
    mov [paint_x], ax
    mov ax, [mouse_y]
    sub ax, [drag_dy]
    mov [paint_y], ax
    call clamp_paint_position
    call redraw_all
.done:
    ret

update_note_drag:
    cmp byte [note_maximized], 0
    jne .done
    mov ax, [mouse_x]
    sub ax, [drag_dx]
    mov [note_x], ax
    mov ax, [mouse_y]
    sub ax, [drag_dy]
    mov [note_y], ax
    call clamp_note_position
    call redraw_all
.done:
    ret

update_calc_drag:
    cmp byte [calc_maximized], 0
    jne .done
    mov ax, [mouse_x]
    sub ax, [drag_dx]
    mov [calc_x], ax
    mov ax, [mouse_y]
    sub ax, [drag_dy]
    mov [calc_y], ax
    call clamp_calc_position
    call redraw_all
.done:
    ret

update_control_drag:
    mov ax, [mouse_x]
    sub ax, [drag_dx]
    jns .x_nonnegative
    xor ax, ax
.x_nonnegative:
    cmp ax, SCREEN_W-CONTROL_W
    jbe .x_ok
    mov ax, SCREEN_W-CONTROL_W
.x_ok:
    mov [control_x], ax
    mov ax, [mouse_y]
    sub ax, [drag_dy]
    jns .y_nonnegative
    xor ax, ax
.y_nonnegative:
    cmp ax, TASKBAR_Y-CONTROL_H
    jbe .y_ok
    mov ax, TASKBAR_Y-CONTROL_H
.y_ok:
    mov [control_y], ax
    call redraw_all
    ret

update_palette_drag:
    mov ax, [mouse_x]
    sub ax, [paint_palette_drag_dx]
    jns .x_nonnegative
    xor ax, ax
.x_nonnegative:
    cmp ax, SCREEN_W-210
    jbe .x_ok
    mov ax, SCREEN_W-210
.x_ok:
    mov [paint_palette_x], ax
    mov ax, [mouse_y]
    sub ax, [paint_palette_drag_dy]
    jns .y_nonnegative
    xor ax, ax
.y_nonnegative:
    cmp ax, TASKBAR_Y-122
    jbe .y_ok
    mov ax, TASKBAR_Y-122
.y_ok:
    mov [paint_palette_y], ax
    call redraw_all
    ret

update_paint_hscroll_drag:
    push ax
    push bx
    push cx
    push dx
    mov al, [drag_pid]
    call proc_load
    cmp byte [active_type], APP_PAINT
    jne .done
    call paint_compute_scroll_metrics
    mov ax, [mouse_x]
    sub ax, [paint_scroll_drag_offset]
    mov cx, [paint_htrack_x]
    cmp ax, cx
    jae .left_ready
    mov ax, cx
.left_ready:
    mov dx, cx
    add dx, [paint_hthumb_range]
    cmp ax, dx
    jbe .right_ready
    mov ax, dx
.right_ready:
    sub ax, cx
    mov bx, [paint_hthumb_range]
    test bx, bx
    jz .zero
    mul word [paint_scroll_max_x]
    div bx
    mov [paint_scroll_x], ax
    jmp .save
.zero:
    mov word [paint_scroll_x], 0
.save:
    call proc_save
    call redraw_all
.done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

update_paint_vscroll_drag:
    push ax
    push bx
    push cx
    push dx
    mov al, [drag_pid]
    call proc_load
    cmp byte [active_type], APP_PAINT
    jne .done
    call paint_compute_scroll_metrics
    mov ax, [mouse_y]
    sub ax, [paint_scroll_drag_offset]
    mov cx, [paint_vtrack_y]
    cmp ax, cx
    jae .top_ready
    mov ax, cx
.top_ready:
    mov dx, cx
    add dx, [paint_vthumb_range]
    cmp ax, dx
    jbe .bottom_ready
    mov ax, dx
.bottom_ready:
    sub ax, cx
    mov bx, [paint_vthumb_range]
    test bx, bx
    jz .zero
    mul word [paint_scroll_max_y]
    div bx
    mov [paint_scroll_y], ax
    jmp .save
.zero:
    mov word [paint_scroll_y], 0
.save:
    call proc_save
    call redraw_all
.done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

update_note_scroll_drag:
    push ax
    push bx
    push cx
    push dx
    mov al, [drag_pid]
    call proc_load
    cmp byte [active_type], APP_NOTEPAD
    jne .done
    call notepad_compute_scrollbar
    mov ax, [note_max_scroll_tmp]
    test ax, ax
    jz .done
    mov bx, [note_track_h]
    sub bx, 2
    sub bx, [note_thumb_h]
    cmp bx, 1
    jae .range_ok
    mov bx, 1
.range_ok:
    mov [note_thumb_range], bx
    mov ax, [mouse_y]
    sub ax, [note_thumb_drag_offset]
    mov cx, [note_track_y]
    inc cx
    cmp ax, cx
    jae .top_ok
    mov ax, cx
.top_ok:
    mov dx, cx
    add dx, bx
    cmp ax, dx
    jbe .bottom_ok
    mov ax, dx
.bottom_ok:
    sub ax, cx
    mul word [note_max_scroll_tmp]
    div word [note_thumb_range]
    mov [note_scroll_row], ax
    call proc_save
    call redraw_all
.done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

update_resize_drag:
    push ax
    push bx
    push cx
    push dx
    mov ax, [mouse_x]
    sub ax, [resize_start_x]
    add ax, [resize_start_w]
    mov bx, [mouse_y]
    sub bx, [resize_start_y]
    add bx, [resize_start_h]
    mov dl, [drag_pid]
    cmp dl, WIN_MAIN
    jne .app
    cmp ax, MAIN_MIN_W
    jae .main_w_ok
    mov ax, MAIN_MIN_W
.main_w_ok:
    mov cx, SCREEN_W
    sub cx, [main_x]
    cmp ax, cx
    jbe .main_w_max
    mov ax, cx
.main_w_max:
    cmp bx, MAIN_MIN_H
    jae .main_h_ok
    mov bx, MAIN_MIN_H
.main_h_ok:
    mov cx, TASKBAR_Y
    sub cx, [main_y]
    cmp bx, cx
    jbe .main_store
    mov bx, cx
.main_store:
    mov [main_w], ax
    mov [main_h], bx
    jmp .draw
.app:
    push ax
    push bx
    mov al, dl
    call proc_load
    pop bx
    pop ax
    mov dl, [active_type]
    cmp dl, APP_PAINT
    je .paint
    cmp dl, APP_NOTEPAD
    je .note
    jmp .calc
.paint:
    cmp ax, PAINT_MIN_W
    jae .paint_w_ok
    mov ax, PAINT_MIN_W
.paint_w_ok:
    mov cx, SCREEN_W
    sub cx, [paint_x]
    cmp ax, cx
    jbe .paint_w_max
    mov ax, cx
.paint_w_max:
    cmp bx, PAINT_MIN_H
    jae .paint_h_ok
    mov bx, PAINT_MIN_H
.paint_h_ok:
    mov cx, TASKBAR_Y
    sub cx, [paint_y]
    cmp bx, cx
    jbe .paint_store
    mov bx, cx
.paint_store:
    mov [paint_w], ax
    mov [paint_h], bx
    call paint_resize_canvas_from_window
    jmp .draw
.note:
    cmp ax, NOTE_MIN_W
    jae .note_w_ok
    mov ax, NOTE_MIN_W
.note_w_ok:
    mov cx, SCREEN_W
    sub cx, [note_x]
    cmp ax, cx
    jbe .note_w_max
    mov ax, cx
.note_w_max:
    cmp bx, NOTE_MIN_H
    jae .note_h_ok
    mov bx, NOTE_MIN_H
.note_h_ok:
    mov cx, TASKBAR_Y
    sub cx, [note_y]
    cmp bx, cx
    jbe .note_store
    mov bx, cx
.note_store:
    mov [note_w], ax
    mov [note_h], bx
    jmp .draw
.calc:
    cmp ax, CALC_MIN_W
    jae .calc_w_ok
    mov ax, CALC_MIN_W
.calc_w_ok:
    mov cx, SCREEN_W
    sub cx, [calc_x]
    cmp ax, cx
    jbe .calc_w_max
    mov ax, cx
.calc_w_max:
    cmp bx, CALC_MIN_H
    jae .calc_h_ok
    mov bx, CALC_MIN_H
.calc_h_ok:
    mov cx, TASKBAR_Y
    sub cx, [calc_y]
    cmp bx, cx
    jbe .calc_store
    mov bx, cx
.calc_store:
    mov [calc_w], ax
    mov [calc_h], bx
.draw:
    call proc_save
    call redraw_all
    pop dx
    pop cx
    pop bx
    pop ax
    ret

toggle_maximize:
    ; AL=pid, toggle between stored geometry and the full work area.
    cmp al, WIN_MAIN
    jne .app
    cmp byte [main_maximized], 0
    jne .main_restore
    mov ax, [main_x]
    mov [main_restore_x], ax
    mov ax, [main_y]
    mov [main_restore_y], ax
    mov ax, [main_w]
    mov [main_restore_w], ax
    mov ax, [main_h]
    mov [main_restore_h], ax
    mov word [main_x], 0
    mov word [main_y], 0
    mov word [main_w], SCREEN_W
    mov word [main_h], TASKBAR_Y
    mov byte [main_maximized], 1
    call redraw_all
    ret
.main_restore:
    mov ax, [main_restore_x]
    mov [main_x], ax
    mov ax, [main_restore_y]
    mov [main_y], ax
    mov ax, [main_restore_w]
    mov [main_w], ax
    mov ax, [main_restore_h]
    mov [main_h], ax
    mov byte [main_maximized], 0
    call redraw_all
    ret
.app:
    call proc_load
    mov al, [active_type]
    cmp al, APP_PAINT
    je .paint
    cmp al, APP_NOTEPAD
    je .note
    jmp .calc
.paint:
    cmp byte [paint_maximized], 0
    jne .paint_restore
    mov ax, [paint_x]
    mov [paint_restore_x], ax
    mov ax, [paint_y]
    mov [paint_restore_y], ax
    mov ax, [paint_w]
    mov [paint_restore_w], ax
    mov ax, [paint_h]
    mov [paint_restore_h], ax
    mov word [paint_x], 0
    mov word [paint_y], 0
    mov word [paint_w], SCREEN_W
    mov word [paint_h], TASKBAR_Y
    mov byte [paint_maximized], 1
    call paint_resize_canvas_from_window
    jmp .app_done
.paint_restore:
    mov ax, [paint_restore_x]
    mov [paint_x], ax
    mov ax, [paint_restore_y]
    mov [paint_y], ax
    mov ax, [paint_restore_w]
    mov [paint_w], ax
    mov ax, [paint_restore_h]
    mov [paint_h], ax
    mov byte [paint_maximized], 0
    call paint_resize_canvas_from_window
    jmp .app_done
.note:
    cmp byte [note_maximized], 0
    jne .note_restore
    mov ax, [note_x]
    mov [note_restore_x], ax
    mov ax, [note_y]
    mov [note_restore_y], ax
    mov ax, [note_w]
    mov [note_restore_w], ax
    mov ax, [note_h]
    mov [note_restore_h], ax
    mov word [note_x], 0
    mov word [note_y], 0
    mov word [note_w], SCREEN_W
    mov word [note_h], TASKBAR_Y
    mov byte [note_maximized], 1
    jmp .app_done
.note_restore:
    mov ax, [note_restore_x]
    mov [note_x], ax
    mov ax, [note_restore_y]
    mov [note_y], ax
    mov ax, [note_restore_w]
    mov [note_w], ax
    mov ax, [note_restore_h]
    mov [note_h], ax
    mov byte [note_maximized], 0
    jmp .app_done
.calc:
    cmp byte [calc_maximized], 0
    jne .calc_restore
    mov ax, [calc_x]
    mov [calc_restore_x], ax
    mov ax, [calc_y]
    mov [calc_restore_y], ax
    mov ax, [calc_w]
    mov [calc_restore_w], ax
    mov ax, [calc_h]
    mov [calc_restore_h], ax
    mov word [calc_x], 0
    mov word [calc_y], 0
    mov word [calc_w], SCREEN_W
    mov word [calc_h], TASKBAR_Y
    mov byte [calc_maximized], 1
    jmp .app_done
.calc_restore:
    mov ax, [calc_restore_x]
    mov [calc_x], ax
    mov ax, [calc_restore_y]
    mov [calc_y], ax
    mov ax, [calc_restore_w]
    mov [calc_w], ax
    mov ax, [calc_restore_h]
    mov [calc_h], ax
    mov byte [calc_maximized], 0
.app_done:
    call proc_save
    call redraw_all
    ret

; =============================================================================
; Notepad helpers and calculator engine

; =============================================================================
; Notepad helpers and calculator engine
; =============================================================================
notepad_invalidate_cache:
    mov byte [note_cache_total_pid], 0xFF
    mov byte [note_cache_pos_pid], 0xFF
    ret

notepad_clear_undo_metadata:
    ; Invalid means no undo metadata is observable.  Keeping every field in a
    ; canonical zero state prevents a later validator/assertion from combining
    ; a new valid flag with stale NOTE_MAX-era indices.  This smaller helper
    ; deliberately preserves the current edit group.
    mov byte [note_undo_valid], 0
    mov byte [note_undo_sel], 0
    mov word [note_undo_len], 0
    mov word [note_undo_cursor], 0
    mov word [note_undo_anchor], 0
    mov word [note_undo_scroll], 0
    ret

notepad_clear_undo_state:
    call notepad_clear_undo_metadata
    mov byte [note_edit_group_pid], 0xFF
    mov byte [note_edit_group_kind], 0
    mov word [note_edit_group_size], 0
    ret

notepad_validate_state:
    ; Clamp all externally restored indices before any text scan or copy.
    ; This turns stale/corrupt process metadata into a bounded document rather
    ; than allowing a 16-bit walk into the undo area or another arena.
    push ax
    push bx
    push di
    push es
    mov al, [active_pid]
    call proc_segment_for_pid
    test ax, ax
    jz .invalid_arena
    cmp ax, [active_data_seg]
    je .arena_ready
    mov [active_data_seg], ax
.arena_ready:
    cmp word [note_len], NOTE_MAX
    jbe .len_ok
    mov word [note_len], NOTE_MAX
.len_ok:
    mov ax, [note_len]
    cmp [note_cursor], ax
    jbe .cursor_ok
    mov [note_cursor], ax
.cursor_ok:
    cmp [note_anchor], ax
    jbe .anchor_ok
    mov [note_anchor], ax
.anchor_ok:
    mov bx, ax
    mov ax, [active_data_seg]
    mov es, ax
    mov byte es:[bx], 0
    cmp byte [note_undo_valid], 0
    jne .validate_undo
    ; Canonicalize invalid undo metadata without destroying a live no-undo
    ; Backspace group.  The full-buffer fast path relies on that group so the
    ; immediately following Backspace cannot start a NOTE_MAX-sized snapshot.
    call notepad_clear_undo_metadata
    jmp .selection
.validate_undo:
    cmp word [note_undo_len], NOTE_MAX
    jbe .undo_len_ok
    mov word [note_undo_len], NOTE_MAX
.undo_len_ok:
    mov ax, [note_undo_len]
    cmp [note_undo_cursor], ax
    jbe .undo_cursor_ok
    mov [note_undo_cursor], ax
.undo_cursor_ok:
    cmp [note_undo_anchor], ax
    jbe .undo_anchor_ok
    mov [note_undo_anchor], ax
.undo_anchor_ok:
    mov di, NOTE_UNDO_OFF
    add di, ax
    mov byte es:[di], 0
.selection:
    cmp byte [note_sel_active], 0
    je .selection_ok
    mov ax, [note_cursor]
    cmp ax, [note_anchor]
    jne .selection_ok
    mov byte [note_sel_active], 0
.selection_ok:
    cmp byte [note_undo_sel], 0
    je .state_ready
    mov ax, [note_undo_cursor]
    cmp ax, [note_undo_anchor]
    jne .state_ready
    mov byte [note_undo_sel], 0
.state_ready:
    call notepad_invalidate_cache
    jmp .done
.invalid_arena:
    ; Never attempt a terminator write through segment zero or an unexpected
    ; segment.  Discard only the loaded scratch metadata; proc_load will
    ; restore a valid instance on the next legitimate activation.
    mov word [note_len], 0
    mov word [note_cursor], 0
    mov word [note_anchor], 0
    mov word [note_scroll_row], 0
    mov byte [note_sel_active], 0
    mov byte [note_mouse_select], 0
    call notepad_clear_undo_state
    mov word [active_data_seg], 0
    call notepad_invalidate_cache
.done:
    pop es
    pop di
    pop bx
    pop ax
    ret

notepad_assert_state:
    ; Post-mutation invariant check.  If an edit ever escapes its 24 KiB
    ; document/undo partition, stop on the global blue screen instead of
    ; allowing a later redraw or paste loop to execute through corrupt memory.
    pushf
    pusha
    push es
    mov al, [active_pid]
    call proc_segment_for_pid
    test ax, ax
    jz .fatal
    cmp ax, [active_data_seg]
    jne .fatal
    mov es, ax
    mov bx, [note_len]
    cmp bx, NOTE_MAX
    ja .fatal
    cmp [note_cursor], bx
    ja .fatal
    cmp [note_anchor], bx
    ja .fatal
    cmp byte es:[bx], 0
    jne .fatal
    cmp word [note_undo_len], NOTE_MAX
    ja .fatal
    cmp byte [note_undo_valid], 0
    je .ok
    mov bx, [note_undo_len]
    mov di, NOTE_UNDO_OFF
    add di, bx
    cmp byte es:[di], 0
    jne .fatal
.ok:
    pop es
    popa
    popf
    ret
.fatal:
    cmp byte [BLUESCREEN_ENABLE_ADDR], 0
    je .ok
    mov al, BSOD_STOP_NOTEPAD
    jmp system_blue_screen

notepad_save_undo_typing:
    ; Coalesce a fast stream of adjacent BIOS key events into one undo unit.
    ; Host/emulator paste is delivered as individual keystrokes; without this
    ; guard every byte copied the whole document into the undo block.
    push ax
    push bx
    push dx
    cmp byte [note_sel_active], 0
    jne .new_group
    mov al, [active_pid]
    cmp al, [note_edit_group_pid]
    jne .new_group
    cmp byte [note_edit_group_kind], 1
    jne .new_group
    mov ax, [note_cursor]
    cmp ax, [note_edit_group_cursor]
    jne .new_group
    mov bx, [0x046C]
    mov dx, bx
    sub dx, [note_edit_group_tick]
    cmp dx, NOTE_TYPE_GROUP_TICKS
    ja .new_group
    mov [note_edit_group_tick], bx
    call mark_active_dirty
    jmp .done
.new_group:
    call notepad_save_undo
    mov al, [active_pid]
    mov [note_edit_group_pid], al
    mov byte [note_edit_group_kind], 1
    mov bx, [0x046C]
    mov [note_edit_group_tick], bx
    mov ax, [note_cursor]
    mov [note_edit_group_cursor], ax
.done:
    pop dx
    pop bx
    pop ax
    ret

notepad_save_undo_paste:
    ; Repeated adjacent Ctrl+V operations share one snapshot just like one
    ; normal paste transaction.  Clipboard length is part of the key so a new
    ; copied payload starts a fresh undo unit.
    push ax
    push bx
    push dx
    cmp byte [note_sel_active], 0
    jne .new_group
    mov al, [active_pid]
    cmp al, [note_edit_group_pid]
    jne .new_group
    cmp byte [note_edit_group_kind], 2
    jne .new_group
    mov ax, [note_cursor]
    cmp ax, [note_edit_group_cursor]
    jne .new_group
    mov ax, [note_insert_len]
    cmp ax, [note_edit_group_size]
    jne .new_group
    mov bx, [0x046C]
    mov dx, bx
    sub dx, [note_edit_group_tick]
    cmp dx, NOTE_TYPE_GROUP_TICKS
    ja .new_group
    mov [note_edit_group_tick], bx
    call mark_active_dirty
    jmp .done
.new_group:
    call notepad_save_undo
    mov al, [active_pid]
    mov [note_edit_group_pid], al
    mov byte [note_edit_group_kind], 2
    mov ax, [note_insert_len]
    mov [note_edit_group_size], ax
    mov bx, [0x046C]
    mov [note_edit_group_tick], bx
    mov ax, [note_cursor]
    mov [note_edit_group_cursor], ax
.done:
    pop dx
    pop bx
    pop ax
    ret

notepad_save_undo_backspace:
    ; A held Backspace key is one edit transaction.  Reusing its first undo
    ; snapshot avoids copying a nearly full 24 KiB document for every repeat.
    push ax
    push bx
    push dx
    cmp byte [note_sel_active], 0
    jne .new_group
    mov al, [active_pid]
    cmp al, [note_edit_group_pid]
    jne .new_group
    cmp byte [note_edit_group_kind], 3
    jne .new_group
    mov ax, [note_cursor]
    cmp ax, [note_edit_group_cursor]
    jne .new_group
    mov bx, [0x046C]
    mov dx, bx
    sub dx, [note_edit_group_tick]
    cmp dx, NOTE_TYPE_GROUP_TICKS
    ja .new_group
    mov [note_edit_group_tick], bx
    call mark_active_dirty
    jmp .done
.new_group:
    call notepad_save_undo
    mov al, [active_pid]
    mov [note_edit_group_pid], al
    mov byte [note_edit_group_kind], 3
    mov word [note_edit_group_size], 0
    mov bx, [0x046C]
    mov [note_edit_group_tick], bx
    mov ax, [note_cursor]
    mov [note_edit_group_cursor], ax
.done:
    pop dx
    pop bx
    pop ax
    ret

notepad_advance_edit_group:
    push ax
    push bx
    mov al, [active_pid]
    cmp al, [note_edit_group_pid]
    jne .done
    cmp byte [note_edit_group_kind], 0
    je .done
    mov ax, [note_cursor]
    mov [note_edit_group_cursor], ax
    mov bx, [0x046C]
    mov [note_edit_group_tick], bx
.done:
    pop bx
    pop ax
    ret

notepad_can_insert:
    ; CF=1 if one character can change the document.  Preserve AX/DX so the
    ; caller can test capacity without losing the BIOS character in AL.
    push ax
    push dx
    cmp word [note_len], NOTE_MAX
    jb .yes
    cmp byte [note_sel_active], 0
    je .no
    call notepad_selection_bounds
    cmp ax, dx
    jne .yes
.no:
    pop dx
    pop ax
    clc
    ret
.yes:
    pop dx
    pop ax
    stc
    ret

notepad_drain_printable_keys:
    ; Drain the BIOS type-ahead buffer before repainting.  Emulator/host paste
    ; arrives as a burst of ordinary key events, so this turns many expensive
    ; full-screen redraws into one bounded batch without swallowing shortcuts
    ; or navigation keys.
    push ax
    push cx
    mov cx, 512
.next:
    mov ah, 0x01
    push cx
    int 0x16
    pop cx
    jz .done
    cmp al, 13
    je .consume_char
    cmp al, 9
    je .consume_tab
    cmp al, 0x20
    jb .done
    cmp al, 0x7E
    ja .done
.consume_char:
    xor ah, ah
    push cx
    int 0x16
    pop cx
    call notepad_can_insert
    jnc .skip_char
    call notepad_insert_char
.skip_char:
    loop .next
    jmp .done
.consume_tab:
    xor ah, ah
    push cx
    int 0x16
    pop cx
    push cx
    mov cx, 4
.tab_spaces:
    mov al, ' '
    push cx
    call notepad_can_insert
    jnc .tab_space_done
    call notepad_insert_char
.tab_space_done:
    pop cx
    loop .tab_spaces
    pop cx
    loop .next
.done:
    pop cx
    pop ax
    ret

notepad_discard_printable_keys:
    ; At NOTE_MAX a host clipboard paste is delivered as a stream of ordinary
    ; BIOS keystrokes, not necessarily Ctrl+V.  Consume that printable backlog
    ; without validation, undo copies, cursor scans or redraws.  Stop at the
    ; first shortcut/navigation key so Backspace remains actionable.
    push ax
    push cx
    mov cx, 512
.next:
    mov ah, 0x01
    push cx
    int 0x16
    pop cx
    jz .done
    cmp al, 13
    je .consume
    cmp al, 9
    je .consume
    cmp al, 0x20
    jb .done
    cmp al, 0x7E
    ja .done
.consume:
    xor ah, ah
    push cx
    int 0x16
    pop cx
    loop .next
.done:
    pop cx
    pop ax
    ret

notepad_drain_paste_keys:
    ; Collapse queued Ctrl+V keystrokes into the same redraw transaction.
    push ax
    push cx
    push si
    mov cx, 512
.next:
    mov ah, 0x01
    push cx
    int 0x16
    pop cx
    jz .done
    cmp al, 0x16
    jne .done
    xor ah, ah
    push cx
    int 0x16
    pop cx
    cmp byte [clipboard_kind], 1
    jne .done
    push cx
    mov cx, [clipboard_len]
    cmp cx, CLIP_MAX
    jbe .clip_len_ready
    mov cx, CLIP_MAX
.clip_len_ready:
    xor si, si
    mov ax, CLIP_SEG
    call notepad_insert_block_external
    pop cx
    loop .next
.done:
    pop si
    pop cx
    pop ax
    ret

notepad_drain_backspace_keys:
    ; Consume a bounded BIOS repeat burst and redraw only once.  Scan code 0Eh
    ; prevents unrelated control characters from being mistaken for Backspace.
    push ax
    push cx
    mov cx, 64
.next:
    mov ah, 0x01
    push cx
    int 0x16
    pop cx
    jz .done
    cmp al, 0x08
    jne .done
    cmp ah, 0x0E
    jne .done
    xor ah, ah
    push cx
    int 0x16
    pop cx
    call notepad_backspace_one
    loop .next
.done:
    pop cx
    pop ax
    ret

notepad_discard_paste_keys:
    ; Full-buffer Ctrl+V is a no-op.  Remove only queued Ctrl+V events, without
    ; revalidating or rescanning the unchanged document for each one.
    push ax
    push cx
    mov cx, 512
.next:
    mov ah, 0x01
    push cx
    int 0x16
    pop cx
    jz .done
    cmp al, 0x16
    jne .done
    xor ah, ah
    push cx
    int 0x16
    pop cx
    loop .next
.done:
    pop cx
    pop ax
    ret

notepad_save_undo:
    call notepad_validate_state
    cmp word [active_data_seg], 0
    je .return
    mov byte [note_edit_group_kind], 0
    call mark_active_dirty
    ; Transactional snapshot: invalidate/canonicalize first, copy the complete
    ; NUL-terminated document, then publish all metadata and set valid last.
    ; An interrupt or failed copy can therefore expose only "no undo", never a
    ; valid flag paired with a stale NOTE_MAX length.
    call notepad_clear_undo_state
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es
    mov dx, [note_len]
    mov cx, dx
    inc cx
    mov bx, cx
    mov ax, [active_data_seg]
    mov ds, ax
    mov es, ax
    xor si, si
    mov di, NOTE_UNDO_OFF
    cld
    shr cx, 1
    rep movsw
    test bl, 1
    jz .copy_done
    movsb
.copy_done:
    ; Make the boundary byte explicit even if a future optimized copy changes
    ; how the odd final byte is handled.
    mov di, NOTE_UNDO_OFF
    add di, dx
    mov byte es:[di], 0
    pop es
    pop ds
    mov [note_undo_len], dx
    mov ax, [note_cursor]
    mov [note_undo_cursor], ax
    mov ax, [note_anchor]
    mov [note_undo_anchor], ax
    mov ax, [note_scroll_row]
    mov [note_undo_scroll], ax
    mov al, [note_sel_active]
    mov [note_undo_sel], al
    mov byte [note_undo_valid], 1
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
.return:
    ret

notepad_undo:
    call notepad_validate_state
    cmp byte [note_undo_valid], 0
    je .redraw
    push ax
    push bx
    push cx
    push si
    push di
    push ds
    push es
    mov cx, [note_undo_len]
    inc cx
    mov bx, cx
    mov ax, [active_data_seg]
    mov ds, ax
    mov es, ax
    mov si, NOTE_UNDO_OFF
    xor di, di
    cld
    shr cx, 1
    rep movsw
    test bl, 1
    jz .copy_done
    movsb
.copy_done:
    pop es
    pop ds
    mov ax, [note_undo_len]
    mov [note_len], ax
    mov ax, [note_undo_cursor]
    mov [note_cursor], ax
    mov ax, [note_undo_anchor]
    mov [note_anchor], ax
    mov ax, [note_undo_scroll]
    mov [note_scroll_row], ax
    mov al, [note_undo_sel]
    mov [note_sel_active], al
    call notepad_clear_undo_state
    call notepad_invalidate_cache
    call mark_active_dirty
    pop di
    pop si
    pop cx
    pop bx
    pop ax
.redraw:
    mov byte [menu_open], MENU_NONE
    call notepad_ensure_cursor_visible
    call redraw_all
    ret

notepad_delete_selection_raw:
    ; Delete active selection without taking an undo snapshot. CF=1 if changed.
    cmp byte [note_sel_active], 0
    je .none
    call notepad_selection_bounds
    cmp ax, dx
    je .none
    mov [note_delete_start], ax
    mov [note_delete_end], dx
    push ax
    push bx
    push cx
    push si
    push di
    push ds
    push es
    mov bx, [note_len]
    sub bx, dx
    inc bx                      ; include terminator
    mov si, dx
    mov di, ax
    mov cx, bx
    mov ax, [active_data_seg]
    mov ds, ax
    mov es, ax
    cld
    rep movsb
    pop es
    pop ds
    mov ax, [note_delete_end]
    sub ax, [note_delete_start]
    sub [note_len], ax
    mov ax, [note_delete_start]
    mov [note_cursor], ax
    mov [note_anchor], ax
    mov byte [note_sel_active], 0
    call notepad_invalidate_cache
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    call notepad_assert_state
    stc
    ret
.none:
    clc
    ret

notepad_delete_selection:
    cmp byte [note_sel_active], 0
    je .redraw
    call notepad_save_undo
    call notepad_delete_selection_raw
    call notepad_ensure_cursor_visible
.redraw:
    mov byte [menu_open], MENU_NONE
    call redraw_all
    ret

notepad_insert_char:
    ; AL=character. Inserts at the caret, replacing a selection.
    mov [note_insert_char_tmp], al
    call notepad_validate_state
    cmp word [active_data_seg], 0
    je .done
    cmp word [note_len], NOTE_MAX
    jb .can_edit
    cmp byte [note_sel_active], 0
    je .done
.can_edit:
    call notepad_save_undo_typing
    call notepad_delete_selection_raw
    cmp word [note_len], NOTE_MAX
    jae .done
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es
    mov cx, [note_len]
    sub cx, [note_cursor]
    inc cx                      ; include terminator
    mov si, [note_len]
    mov di, si
    inc di
    mov bx, [note_cursor]
    mov dl, [note_insert_char_tmp]
    mov ax, [active_data_seg]
    mov ds, ax
    mov es, ax
    std
    rep movsb
    cld
    mov [bx], dl
    pop es
    pop ds
    inc word [note_len]
    inc word [note_cursor]
    mov ax, [note_cursor]
    mov [note_anchor], ax
    mov byte [note_sel_active], 0
    call notepad_invalidate_cache
    call notepad_advance_edit_group
    mov byte [note_batch_changed], 1
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    call notepad_assert_state
.done:
    cmp byte [note_batch_input], 0
    jne .return
    call notepad_ensure_cursor_visible
.return:
    ret

notepad_backspace:
    ; Process one BIOS key event per main-loop pass.  Nested INT 16h polling
    ; here used to re-enter the VMware keyboard path while a 24 KiB undo copy
    ; was active and could corrupt the return path at the full-buffer edge.
    call notepad_backspace_one
    call notepad_ensure_cursor_visible
    call redraw_all
    ret

notepad_backspace_one:
    call notepad_validate_state
    cmp word [active_data_seg], 0
    je .done
    cmp byte [note_sel_active], 0
    je .single
    call notepad_save_undo
    call notepad_delete_selection_raw
    ; Any queued Backspace repeats remain part of the same transaction.
    mov al, [active_pid]
    mov [note_edit_group_pid], al
    mov byte [note_edit_group_kind], 3
    mov word [note_edit_group_size], 0
    mov ax, [0x046C]
    mov [note_edit_group_tick], ax
    mov ax, [note_cursor]
    mov [note_edit_group_cursor], ax
    jmp .finish
.single:
    cmp word [note_cursor], 0
    je .done

    ; At the document tail, the first deletion from NOTE_MAX starts a dedicated
    ; no-undo transaction.  Every following tail Backspace stays on this direct
    ; path with no timeout, no undo snapshot and no REP move.  This guarantees
    ; that the second key cannot re-enter the near-NOTE_MAX copy path even when
    ; a slow redraw consumes more than NOTE_TYPE_GROUP_TICKS.
    mov ax, [note_cursor]
    cmp ax, [note_len]
    jne .normal_single
    cmp word [note_len], NOTE_MAX
    je .start_full_tail_group
    cmp byte [note_undo_valid], 0
    jne .normal_single
    mov al, [active_pid]
    cmp al, [note_edit_group_pid]
    jne .normal_single
    cmp byte [note_edit_group_kind], NOTE_GROUP_FULL_BACKSPACE
    jne .normal_single
    jmp .full_tail_delete

.start_full_tail_group:
    call notepad_clear_undo_state
    mov al, [active_pid]
    mov [note_edit_group_pid], al
    mov byte [note_edit_group_kind], NOTE_GROUP_FULL_BACKSPACE
    mov word [note_edit_group_size], 0

.full_tail_delete:
    call mark_active_dirty
    dec word [note_len]
    dec word [note_cursor]
    mov bx, [note_len]
    push es
    mov ax, [active_data_seg]
    mov es, ax
    mov byte es:[bx], 0
    pop es
    mov ax, [note_cursor]
    mov [note_anchor], ax
    mov ax, [note_cursor]
    mov [note_edit_group_cursor], ax
    mov ax, [0x046C]
    mov [note_edit_group_tick], ax
    call notepad_invalidate_cache
    jmp .finish
.normal_single:
    call notepad_save_undo_backspace
    push ax
    push bx
    push cx
    push si
    push di
    push ds
    push es
    mov ax, [note_cursor]
    mov si, ax
    mov di, ax
    dec di
    mov cx, [note_len]
    sub cx, ax
    inc cx
    mov ax, [active_data_seg]
    mov ds, ax
    mov es, ax
    cld
    rep movsb
    pop es
    pop ds
    dec word [note_len]
    dec word [note_cursor]
    mov ax, [note_cursor]
    mov [note_anchor], ax
    call notepad_invalidate_cache
    call notepad_advance_edit_group
    pop di
    pop si
    pop cx
    pop bx
    pop ax
.finish:
    mov byte [note_sel_active], 0
    call notepad_assert_state
.done:
    ret

notepad_delete_forward:
    cmp byte [note_sel_active], 0
    je .single
    call notepad_save_undo
    call notepad_delete_selection_raw
    jmp .finish
.single:
    mov ax, [note_cursor]
    cmp ax, [note_len]
    jae .redraw
    call notepad_save_undo
    push ax
    push cx
    push si
    push di
    push ds
    push es
    mov si, [note_cursor]
    inc si
    mov di, [note_cursor]
    mov cx, [note_len]
    sub cx, [note_cursor]
    mov ax, [active_data_seg]
    mov ds, ax
    mov es, ax
    cld
    rep movsb
    pop es
    pop ds
    dec word [note_len]
    call notepad_invalidate_cache
    pop di
    pop si
    pop cx
    pop ax
    call notepad_assert_state
.finish:
    mov byte [note_sel_active], 0
    call notepad_invalidate_cache
    mov ax, [note_cursor]
    mov [note_anchor], ax
    call notepad_assert_state
.redraw:
    call redraw_all
    ret

notepad_copy_raw:
    ; Copy the active selection from NOTE_SEG to CLIP_SEG.
    mov byte [note_edit_group_kind], 0
    call notepad_validate_state
    cmp word [active_data_seg], 0
    je .empty
    call notepad_selection_bounds
    cmp ax, dx
    je .empty
    mov cx, dx
    sub cx, ax
    cmp cx, CLIP_MAX
    jbe .len_ok
    mov cx, CLIP_MAX
.len_ok:
    mov [clipboard_len], cx
    mov byte [clipboard_kind], 1
    push ax
    push bx
    push cx
    push si
    push di
    push ds
    push es
    mov si, ax
    mov ax, [active_data_seg]
    mov ds, ax
    mov ax, CLIP_SEG
    mov es, ax
    xor di, di
    cld
    rep movsb
    pop es
    pop ds
    mov bx, [clipboard_len]
    push es
    mov ax, CLIP_SEG
    mov es, ax
    mov byte es:[bx], 0
    pop es
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret
.empty:
    mov word [clipboard_len], 0
    mov byte [clipboard_kind], 0
    ret

notepad_copy:
    call notepad_copy_raw
    mov byte [menu_open], MENU_NONE
    call redraw_all
    ret

notepad_cut:
    cmp byte [note_sel_active], 0
    je .redraw
    call notepad_save_undo
    call notepad_copy_raw
    call notepad_delete_selection_raw
    call notepad_ensure_cursor_visible
.redraw:
    mov byte [menu_open], MENU_NONE
    call redraw_all
    ret

notepad_insert_block:
    ; Segment-zero source string, CX length.
    mov word [note_insert_seg], 0
    jmp notepad_insert_block_common

notepad_insert_block_external:
    ; AX:SI source segment:offset, CX length. DS remains zero for globals.
    mov [note_insert_seg], ax

notepad_insert_block_common:
    ; Replaces selection, up to the bounded 24 KiB document region.
    mov [note_insert_ptr], si
    mov [note_insert_len], cx
    cmp cx, 0
    je .done
    call notepad_validate_state

    ; A paste into a full document with no nonempty selection cannot mutate
    ; anything.  Return before copying 24 KiB into undo or marking the process
    ; dirty; repeated Ctrl+V bursts at the limit otherwise look like a hang.
    cmp word [note_len], NOTE_MAX
    jb .mutation_possible
    cmp byte [note_sel_active], 0
    je .done
    call notepad_selection_bounds
    cmp ax, dx
    je .done
.mutation_possible:
    cmp word [note_insert_seg], CLIP_SEG
    jne .normal_undo
    call notepad_save_undo_paste
    jmp .undo_ready
.normal_undo:
    call notepad_save_undo
.undo_ready:
    call notepad_delete_selection_raw
    mov ax, NOTE_MAX
    sub ax, [note_len]
    cmp [note_insert_len], ax
    jbe .len_ready
    mov [note_insert_len], ax
.len_ready:
    cmp word [note_insert_len], 0
    je .done
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds
    push es
    mov dx, [note_insert_len]
    mov bx, [note_cursor]
    mov cx, [note_len]
    sub cx, bx
    inc cx
    mov si, [note_len]
    mov di, si
    add di, dx

    ; CS is 07E0h for the enlarged stage-2 image, so CS overrides no longer
    ; address segment-zero globals. Save the source far pointer while DS is
    ; still zero, then restore it directly after the backward document move.
    push word [note_insert_seg]
    push word [note_insert_ptr]
    mov ax, [active_data_seg]
    mov ds, ax
    mov es, ax
    std
    rep movsb
    cld

    pop si
    pop ds
    mov di, bx
    mov cx, dx
    rep movsb

    pop es
    pop ds
    mov ax, [note_insert_len]
    add [note_len], ax
    add [note_cursor], ax
    mov ax, [note_cursor]
    mov [note_anchor], ax
    mov byte [note_sel_active], 0
    call notepad_invalidate_cache
    call notepad_advance_edit_group
    mov byte [note_batch_changed], 1
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    call notepad_assert_state
.done:
    cmp byte [note_batch_input], 0
    jne .return
    call notepad_ensure_cursor_visible
.return:
    ret

notepad_paste:
    cmp byte [clipboard_kind], 1
    jne .done
    cmp word [clipboard_len], 0
    je .done
    call notepad_validate_state
    ; A full document with no nonempty selection is a true no-op.  Leave any
    ; additional BIOS events to the outer main loop instead of recursively
    ; consuming them from inside the editor.
    cmp word [note_len], NOTE_MAX
    jb .mutate
    cmp byte [note_sel_active], 0
    je .full_noop
    call notepad_selection_bounds
    cmp ax, dx
    jne .mutate
.full_noop:
    cmp byte [menu_open], MENU_NONE
    je .done
    mov byte [menu_open], MENU_NONE
    call redraw_all
    ret
.mutate:
    mov cx, [clipboard_len]
    cmp cx, CLIP_MAX
    jbe .clip_len_ready
    mov cx, CLIP_MAX
.clip_len_ready:
    xor si, si
    mov ax, CLIP_SEG
    call notepad_insert_block_external
    call notepad_ensure_cursor_visible
    mov byte [menu_open], MENU_NONE
    call redraw_all
.done:
    ret

notepad_select_all:
    mov word [note_anchor], 0
    mov ax, [note_len]
    mov [note_cursor], ax
    cmp ax, 0
    je .none
    mov byte [note_sel_active], 1
    jmp .finish
.none:
    mov byte [note_sel_active], 0
.finish:
    call notepad_ensure_cursor_visible
    mov byte [menu_open], MENU_NONE
    call redraw_all
    ret

notepad_prepare_move:
    test byte [shift_flags], 0x03
    jz .no_shift
    cmp byte [note_sel_active], 0
    jne .done
    mov ax, [note_cursor]
    mov [note_anchor], ax
    jmp .done
.no_shift:
    mov byte [note_sel_active], 0
.done:
    ret

notepad_finish_move:
    test byte [shift_flags], 0x03
    jz .no_shift
    mov ax, [note_cursor]
    cmp ax, [note_anchor]
    je .clear
    mov byte [note_sel_active], 1
    jmp .visible
.no_shift:
    mov ax, [note_cursor]
    mov [note_anchor], ax
.clear:
    mov byte [note_sel_active], 0
.visible:
    call notepad_ensure_cursor_visible
    call redraw_all
    ret

notepad_move_left:
    test byte [shift_flags], 0x03
    jnz .ordinary
    cmp byte [note_sel_active], 0
    je .ordinary
    call notepad_selection_bounds
    mov [note_cursor], ax
    mov [note_anchor], ax
    mov byte [note_sel_active], 0
    jmp notepad_finish_move
.ordinary:
    call notepad_prepare_move
    cmp word [note_cursor], 0
    je notepad_finish_move
    dec word [note_cursor]
    jmp notepad_finish_move

notepad_move_right:
    test byte [shift_flags], 0x03
    jnz .ordinary
    cmp byte [note_sel_active], 0
    je .ordinary
    call notepad_selection_bounds
    mov [note_cursor], dx
    mov [note_anchor], dx
    mov byte [note_sel_active], 0
    jmp notepad_finish_move
.ordinary:
    call notepad_prepare_move
    mov ax, [note_cursor]
    cmp ax, [note_len]
    jae notepad_finish_move
    inc word [note_cursor]
    jmp notepad_finish_move

notepad_move_up:
    call notepad_prepare_move
    mov ax, [note_cursor]
    call notepad_index_to_rowcol
    test bx, bx
    jz notepad_finish_move
    dec bx
    call notepad_rowcol_to_index
    mov [note_cursor], ax
    jmp notepad_finish_move

notepad_move_down:
    call notepad_prepare_move
    mov ax, [note_cursor]
    call notepad_index_to_rowcol
    inc bx
    call notepad_rowcol_to_index
    mov [note_cursor], ax
    jmp notepad_finish_move

notepad_move_home:
    call notepad_prepare_move
    mov ax, [note_cursor]
    call notepad_index_to_rowcol
    xor cx, cx
    call notepad_rowcol_to_index
    mov [note_cursor], ax
    jmp notepad_finish_move

notepad_move_end:
    call notepad_prepare_move
    mov ax, [note_cursor]
    call notepad_index_to_rowcol
    call note_compute_layout
    mov cx, [note_cols_dyn]
    call notepad_rowcol_to_index
    mov [note_cursor], ax
    jmp notepad_finish_move

notepad_page_up:
    call notepad_prepare_move
    mov ax, [note_cursor]
    call notepad_index_to_rowcol
    call note_compute_layout
    cmp bx, [note_rows_dyn]
    jae .subtract
    xor bx, bx
    jmp .map
.subtract:
    sub bx, [note_rows_dyn]
.map:
    call notepad_rowcol_to_index
    mov [note_cursor], ax
    jmp notepad_finish_move

notepad_page_down:
    call notepad_prepare_move
    mov ax, [note_cursor]
    call notepad_index_to_rowcol
    call note_compute_layout
    add bx, [note_rows_dyn]
    call notepad_rowcol_to_index
    mov [note_cursor], ax
    jmp notepad_finish_move

notepad_append_char:
    ; Compatibility entry: insertion now happens at the caret.
    jmp notepad_insert_char

bcd_to_ascii_pair:
    ; AL=packed BCD, DS:DI destination, advances DI by 2.
    push ax
    mov ah, al
    and al, 0x0F
    shr ah, 4
    add ah, '0'
    mov [di], ah
    inc di
    add al, '0'
    mov [di], al
    inc di
    pop ax
    ret

notepad_insert_datetime:
    mov byte [menu_open], MENU_NONE
    mov ah, 0x04
    int 0x1A
    jc .fallback
    mov di, datetime_buf
    mov al, ch
    call bcd_to_ascii_pair
    mov al, cl
    call bcd_to_ascii_pair
    mov byte [di], '-'
    inc di
    mov al, dh
    call bcd_to_ascii_pair
    mov byte [di], '-'
    inc di
    mov al, dl
    call bcd_to_ascii_pair
    mov byte [di], ' '
    inc di
    mov ah, 0x02
    int 0x1A
    jc .fallback
    mov al, ch
    call bcd_to_ascii_pair
    mov byte [di], ':'
    inc di
    mov al, cl
    call bcd_to_ascii_pair
    mov byte [di], 0
    mov si, datetime_buf
    call strlen_z
    call notepad_insert_block
    call redraw_all
    ret
.fallback:
    mov si, str_datetime_unknown
    call strlen_z
    call notepad_insert_block
    call redraw_all
    ret

notepad_word_left:
    call notepad_prepare_move
    push fs
    mov ax, [active_data_seg]
    mov fs, ax
    mov bx, [note_cursor]
    test bx, bx
    jz .store
    dec bx
.skip_delim:
    mov al, fs:[bx]
    cmp al, ' '
    je .delim_back
    cmp al, 13
    je .delim_back
    jmp .word_back
.delim_back:
    test bx, bx
    jz .store
    dec bx
    jmp .skip_delim
.word_back:
    test bx, bx
    jz .store
    mov al, fs:[bx-1]
    cmp al, ' '
    je .store
    cmp al, 13
    je .store
    dec bx
    jmp .word_back
.store:
    mov [note_cursor], bx
    pop fs
    jmp notepad_finish_move

notepad_word_right:
    call notepad_prepare_move
    push fs
    mov ax, [active_data_seg]
    mov fs, ax
    mov bx, [note_cursor]
    mov dx, [note_len]
.word_forward:
    cmp bx, dx
    jae .store
    mov al, fs:[bx]
    cmp al, ' '
    je .skip_delim
    cmp al, 13
    je .skip_delim
    inc bx
    jmp .word_forward
.skip_delim:
    cmp bx, dx
    jae .store
    mov al, fs:[bx]
    cmp al, ' '
    je .advance_delim
    cmp al, 13
    jne .store
.advance_delim:
    inc bx
    jmp .skip_delim
.store:
    mov [note_cursor], bx
    pop fs
    jmp notepad_finish_move

notepad_delete_word_left:
    cmp byte [note_sel_active], 0
    jne .delete_selection
    cmp word [note_cursor], 0
    je .redraw
    call notepad_save_undo
    mov ax, [note_cursor]
    mov [note_anchor], ax
    push fs
    mov ax, [active_data_seg]
    mov fs, ax
    mov bx, [note_cursor]
    dec bx
.skip_delim:
    mov al, fs:[bx]
    cmp al, ' '
    je .delim_back
    cmp al, 13
    je .delim_back
    jmp .word_back
.delim_back:
    test bx, bx
    jz .mark
    dec bx
    jmp .skip_delim
.word_back:
    test bx, bx
    jz .mark
    mov al, fs:[bx-1]
    cmp al, ' '
    je .mark
    cmp al, 13
    je .mark
    dec bx
    jmp .word_back
.mark:
    pop fs
    mov [note_cursor], bx
    mov byte [note_sel_active], 1
    call notepad_delete_selection_raw
    jmp .finish
.delete_selection:
    call notepad_save_undo
    call notepad_delete_selection_raw
.finish:
    call notepad_ensure_cursor_visible
.redraw:
    call redraw_all
    ret

notepad_delete_word_right:
    cmp byte [note_sel_active], 0
    jne .delete_selection
    mov bx, [note_cursor]
    cmp bx, [note_len]
    jae .redraw
    call notepad_save_undo
    mov ax, bx
    mov [note_anchor], ax
    push fs
    mov ax, [active_data_seg]
    mov fs, ax
    mov dx, [note_len]
.word_forward:
    cmp bx, dx
    jae .mark
    mov al, fs:[bx]
    cmp al, ' '
    je .skip_delim
    cmp al, 13
    je .skip_delim
    inc bx
    jmp .word_forward
.skip_delim:
    cmp bx, dx
    jae .mark
    mov al, fs:[bx]
    cmp al, ' '
    je .advance
    cmp al, 13
    jne .mark
.advance:
    inc bx
    jmp .skip_delim
.mark:
    pop fs
    mov [note_cursor], bx
    mov byte [note_sel_active], 1
    call notepad_delete_selection_raw
    jmp .finish
.delete_selection:
    call notepad_save_undo
    call notepad_delete_selection_raw
.finish:
    call notepad_ensure_cursor_visible
.redraw:
    call redraw_all
    ret

calc_backspace:
    jmp calc96_backspace_impl

calc_backspace_legacy:
    cmp byte [calc_result_fresh], 0
    jne .done
    cmp byte [calc_error], 0
    je .normal
    call calc_clear_no_draw
    ret
.normal:
    cmp byte [calc_entry], 0
    je .done
    cmp byte [calc_frac_digits], 0
    je .integer
    mov al, [calc_frac_digits]
    cmp al, 1
    je .frac_1
    cmp al, 2
    je .frac_2
    mov dword [calc_temp_value], 10
    jmp .frac_ready
.frac_1:
    mov dword [calc_temp_value], 1000
    jmp .frac_ready
.frac_2:
    mov dword [calc_temp_value], 100
.frac_ready:
    mov eax, [calc_temp_value]
    mov [calc_temp_mul], eax
    call calc_truncate_current_by
    dec byte [calc_frac_digits]
    jmp .done
.integer:
    mov dword [calc_temp_value], 10000
    mov dword [calc_temp_mul], 1000
    call calc_truncate_current_by
.done:
    ret

calc_truncate_current_by:
    fnstcw [calc_fpu_cw_old]
    mov ax, [calc_fpu_cw_old]
    or ax, 0x0C00
    mov [calc_fpu_cw_trunc], ax
    fldcw [calc_fpu_cw_trunc]
    fild qword [calc_current]
    fidiv dword [calc_temp_value]
    frndint
    fimul dword [calc_temp_mul]
    fistp qword [calc_current]
    fldcw [calc_fpu_cw_old]
    ret

calc_clear_no_draw:
    mov dword [calc_acc], 0
    mov dword [calc_acc+4], 0
    mov dword [calc_acc+8], 0
    mov dword [calc_current], 0
    mov dword [calc_current+4], 0
    mov dword [calc_current+8], 0
    mov byte [calc_op], 0
    mov byte [calc_entry], 0
    mov byte [calc_error], 0
    mov byte [calc_result_fresh], 0
    mov byte [calc_decimal], 0
    mov byte [calc_frac_digits], 0
    ret

calc_button_action:
    cmp al, BTN_CALC_DECIMAL
    je .decimal
    cmp al, BTN_CALC_PERCENT
    je .percent
    cmp al, BTN_CALC_SQRT
    je .sqrt
    cmp al, BTN_CALC_BACK
    je .back
    cmp al, BTN_CALC_7
    je .d7
    cmp al, BTN_CALC_8
    je .d8
    cmp al, BTN_CALC_9
    je .d9
    cmp al, BTN_CALC_ADD
    je .add
    cmp al, BTN_CALC_4
    je .d4
    cmp al, BTN_CALC_5
    je .d5
    cmp al, BTN_CALC_6
    je .d6
    cmp al, BTN_CALC_SUB
    je .sub
    cmp al, BTN_CALC_1
    je .d1
    cmp al, BTN_CALC_2
    je .d2
    cmp al, BTN_CALC_3
    je .d3
    cmp al, BTN_CALC_MUL
    je .mul
    cmp al, BTN_CALC_CLEAR
    je .clear
    cmp al, BTN_CALC_0
    je .d0
    cmp al, BTN_CALC_EQUAL
    je .equal
    mov al, '/'
    jmp .operator
.d7: mov al, 7
    jmp .digit
.d8: mov al, 8
    jmp .digit
.d9: mov al, 9
    jmp .digit
.d4: mov al, 4
    jmp .digit
.d5: mov al, 5
    jmp .digit
.d6: mov al, 6
    jmp .digit
.d1: mov al, 1
    jmp .digit
.d2: mov al, 2
    jmp .digit
.d3: mov al, 3
    jmp .digit
.d0: xor al, al
.digit:
    call calc_input_digit
    jmp .save
.add: mov al, '+'
    jmp .operator
.sub: mov al, '-'
    jmp .operator
.mul: mov al, '*'
.operator:
    call calc_set_operator
    jmp .save
.equal:
    call calc_equal
    jmp .save
.decimal:
    call calc_input_decimal
    jmp .save
.percent:
    call calc_percent
    jmp .save
.sqrt:
    call calc_sqrt
    jmp .save
.back:
    call calc_backspace
    jmp .save
.clear:
    call calc_clear_no_draw
.save:
    call proc_save
    call redraw_all
    ret

calc_prepare_new_entry:
    cmp byte [calc_result_fresh], 0
    je .error
    call calc_clear_no_draw
.error:
    cmp byte [calc_error], 0
    je .done
    call calc_clear_no_draw
.done:
    ret

calc_input_digit:
    jmp calc96_input_digit_impl

calc_input_digit_legacy:
    ; AL=digit. Values use signed 64-bit fixed point internally, while every
    ; accepted/displayed result is constrained to the full signed 32-bit real
    ; range (-2147483648..2147483647).
    push eax
    push ebx
    push ecx
    push edx
    mov cl, al
    call calc_prepare_new_entry
    cmp byte [calc_decimal], 0
    jne .fraction
    mov eax, [calc_current]
    mov edx, [calc_current+4]
    mov ebx, 10
    mul ebx
    mov ebx, [calc_current+4]
    imul ebx, ebx, 10
    add edx, ebx
    xor ebx, ebx
    mov bl, cl
    imul ebx, ebx, CALC_SCALE
    add eax, ebx
    adc edx, 0
    mov [calc_current], eax
    mov [calc_current+4], edx
    call calc_check_current_range
    jc .overflow
    mov byte [calc_entry], 1
    jmp .done
.fraction:
    cmp byte [calc_frac_digits], 3
    jae .done
    xor eax, eax
    mov al, cl
    mov bl, [calc_frac_digits]
    cmp bl, 0
    je .hundreds
    cmp bl, 1
    je .tens
    jmp .ones
.hundreds:
    imul eax, eax, 100
    jmp .add_fraction
.tens:
    imul eax, eax, 10
.add_fraction:
.ones:
    add [calc_current], eax
    adc dword [calc_current+4], 0
    call calc_check_current_range
    jc .overflow
    inc byte [calc_frac_digits]
    mov byte [calc_entry], 1
    jmp .done
.overflow:
    mov byte [calc_error], 1
.done:
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

calc_input_decimal:
    call calc_prepare_new_entry
    mov byte [calc_decimal], 1
    mov byte [calc_entry], 1
    ret

calc_check_current_range:
    mov eax, [calc_current+4]
    test eax, eax
    js .negative
    cmp eax, 0x000001F3
    ja .bad
    jb .ok
    cmp dword [calc_current], 0xFFFFFC18
    ja .bad
.ok:
    clc
    ret
.negative:
    cmp eax, 0xFFFFFE0C
    jl .bad
    clc
    ret
.bad:
    stc
    ret

calc_check_temp_range:
    mov eax, [calc_temp_qword+4]
    test eax, eax
    js .negative
    cmp eax, 0x000001F3
    ja .bad
    jb .ok
    cmp dword [calc_temp_qword], 0xFFFFFC18
    ja .bad
.ok:
    clc
    ret
.negative:
    cmp eax, 0xFFFFFE0C
    jl .bad
    clc
    ret
.bad:
    stc
    ret

calc_set_operator:
    jmp calc96_set_operator_impl

calc_set_operator_legacy:
    push ax
    mov byte [calc_result_fresh], 0
    cmp byte [calc_error], 0
    jne .done
    cmp byte [calc_op], 0
    je .store_first
    cmp byte [calc_entry], 0
    je .replace
    call calc_apply
    cmp byte [calc_error], 0
    jne .done
    jmp .replace
.store_first:
    mov eax, [calc_current]
    mov [calc_acc], eax
    mov eax, [calc_current+4]
    mov [calc_acc+4], eax
.replace:
    pop ax
    mov [calc_op], al
    mov dword [calc_current], 0
    mov dword [calc_current+4], 0
    mov byte [calc_entry], 0
    mov byte [calc_decimal], 0
    mov byte [calc_frac_digits], 0
    ret
.done:
    pop ax
    ret

calc_equal:
    jmp calc96_equal_impl

calc_equal_legacy:
    cmp byte [calc_error], 0
    jne .done
    cmp byte [calc_op], 0
    je .done
    call calc_apply
    cmp byte [calc_error], 0
    jne .done
    mov eax, [calc_acc]
    mov [calc_current], eax
    mov eax, [calc_acc+4]
    mov [calc_current+4], eax
    mov byte [calc_op], 0
    mov byte [calc_entry], 1
    mov byte [calc_result_fresh], 1
    mov byte [calc_decimal], 0
    mov byte [calc_frac_digits], 0
.done:
    ret

calc_apply:
    jmp calc96_apply_impl

calc_apply_legacy:
    push eax
    push ebx
    push ecx
    push edx
    mov cl, [calc_op]
    cmp cl, '/'
    jne .load
    mov eax, [calc_current]
    or eax, [calc_current+4]
    jz .error
.load:
    finit
    fild qword [calc_acc]
    fild qword [calc_current]
    cmp cl, '+'
    je .add
    cmp cl, '-'
    je .sub
    cmp cl, '*'
    je .mul
    fdivp st1, st0
    fimul dword [calc_scale_integer]
    jmp .round_store
.add:
    faddp st1, st0
    jmp .round_store
.sub:
    fsubp st1, st0
    jmp .round_store
.mul:
    fmulp st1, st0
    fidiv dword [calc_scale_integer]
.round_store:
    fistp qword [calc_temp_qword]
    call calc_check_temp_range
    jc .error
    mov eax, [calc_temp_qword]
    mov [calc_acc], eax
    mov eax, [calc_temp_qword+4]
    mov [calc_acc+4], eax
    jmp .done
.error:
    mov byte [calc_error], 1
.done:
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

calc_percent:
    jmp calc96_percent_impl

calc_percent_legacy:
    cmp byte [calc_error], 0
    jne .done
    finit
    fild qword [calc_current]
    mov dword [calc_temp_value], 100
    fidiv dword [calc_temp_value]
    fistp qword [calc_current]
    mov byte [calc_entry], 1
    mov byte [calc_result_fresh], 0
.done:
    ret

calc_sqrt:
    jmp calc96_sqrt_impl

calc_sqrt_legacy:
    ; sqrt(real_value) in the same 1/1000 fixed-point scale.
    cmp byte [calc_error], 0
    jne .done
    cmp dword [calc_current+4], 0
    jl .error
    finit
    fild qword [calc_current]
    fimul dword [calc_scale_integer]
    fsqrt
    fistp qword [calc_current]
    call calc_check_current_range
    jc .error
    mov byte [calc_entry], 1
    mov byte [calc_result_fresh], 1
    mov byte [calc_decimal], 0
    mov byte [calc_frac_digits], 0
    ret
.error:
    mov byte [calc_error], 1
.done:
    ret

calc_format_display:
    jmp calc96_format_impl

calc_format_display_legacy:
    push eax
    push ebx
    push ecx
    push edx
    push si
    push di
    cmp byte [calc_error], 0
    je .number
    mov si, str_error
    mov di, calc_display_buf
.copy_error:
    lodsb
    stosb
    test al, al
    jnz .copy_error
    jmp .done
.number:
    mov eax, [calc_current]
    mov edx, [calc_current+4]
    cmp byte [calc_entry], 0
    jne .have
    mov eax, [calc_acc]
    mov edx, [calc_acc+4]
.have:
    mov byte [calc_temp_sign], 0
    test edx, edx
    jns .divide_scaled
    mov byte [calc_temp_sign], 1
.divide_scaled:
    mov ebx, CALC_SCALE
    idiv ebx
    test eax, eax
    jns .quotient_abs
    neg eax
.quotient_abs:
    test edx, edx
    jns .fraction_abs
    neg edx
.fraction_abs:
    mov [calc_temp_frac], dx
    mov di, calc_display_buf+22
    mov byte [di], 0
    dec di
    mov ebx, 10
    test eax, eax
    jnz .integer_loop
    mov byte [di], '0'
    dec di
    jmp .integer_done
.integer_loop:
    xor edx, edx
    div ebx
    add dl, '0'
    mov [di], dl
    dec di
    test eax, eax
    jnz .integer_loop
.integer_done:
    cmp byte [calc_temp_sign], 0
    je .shift_integer
    mov byte [di], '-'
    dec di
.shift_integer:
    inc di
    mov si, di
    mov di, calc_display_buf
.copy_integer:
    lodsb
    stosb
    test al, al
    jnz .copy_integer
    dec di
    mov ax, [calc_temp_frac]
    cmp ax, 0
    jne .fraction
    cmp byte [calc_decimal], 0
    je .terminate
    mov byte [di], '.'
    inc di
    jmp .terminate
.fraction:
    mov byte [di], '.'
    inc di
    xor dx, dx
    mov bx, 100
    div bx
    add al, '0'
    stosb
    mov ax, dx
    xor dx, dx
    mov bx, 10
    div bx
    add al, '0'
    stosb
    mov al, dl
    add al, '0'
    stosb
    ; Trim only insignificant zeros.
    cmp byte [di-1], '0'
    jne .terminate
    dec di
    cmp byte [di-1], '0'
    jne .terminate
    dec di
.terminate:
    mov byte [di], 0
.done:
    pop di
    pop si
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; =============================================================================
; Keyboard and shortcuts

; =============================================================================
; Keyboard and shortcuts
; =============================================================================
handle_key:
    mov [last_key], ax
    push ax
    mov ah, 0x02
    int 0x16
    mov [shift_flags], al
    pop ax

    cmp byte [message_open], 0
    jne .modal
    cmp byte [custom_open], 0
    jne .custom_modal
    cmp byte [debug_open], 0
    jne .debug_modal
    cmp byte [control_open], 0
    jne .control_modal
    cmp byte [keyboard_move_mode], 0
    jne .move_mode

    mov al, [foreground_window]
    cmp al, WIN_MAIN
    je .foreground_loaded
    call proc_load
.foreground_loaded:
    mov ax, [last_key]

    test byte [shift_flags], 0x08
    jz .function_keys
    cmp ah, 0x3E              ; Alt+F4
    je .alt_f4
    cmp ah, 0x0F              ; Alt+Tab
    je .alt_tab
    cmp ah, 0x39              ; Alt+Space: foreground system menu
    je .alt_space
    jmp .window_keys
.alt_f4:
    call close_foreground
    ret
.alt_tab:
    call switch_foreground
    ret
.alt_space:
    call open_foreground_system_menu
    ret

.function_keys:
.f10:
    cmp ah, 0x44              ; F10
    jne .ctrl_keys
    mov al, [foreground_window]
    mov [menu_owner_pid], al
    cmp al, WIN_MAIN
    je .f10_main
    mov al, [active_type]
    cmp al, APP_PAINT
    je .f10_paint
    cmp al, APP_NOTEPAD
    je .f10_note
    mov byte [menu_open], MENU_CALC_FILE
    jmp .f10_draw
.f10_main:
    mov byte [menu_open], MENU_MAIN_FILE
    jmp .f10_draw
.f10_paint:
    mov byte [menu_open], MENU_PAINT_FILE
    jmp .f10_draw
.f10_note:
    mov byte [menu_open], MENU_NOTE_FILE
.f10_draw:
    call redraw_all
    ret

.ctrl_keys:
    test byte [shift_flags], 0x04
    jz .menu_escape
    cmp byte [active_type], APP_NOTEPAD
    je .note_ctrl
    cmp byte [active_type], APP_PAINT
    je .paint_ctrl
    jmp .menu_escape
.paint_ctrl:
    cmp al, 0x13              ; Ctrl+S
    je .app_save
    cmp al, 0x03              ; Ctrl+C
    je .paint_copy
    cmp al, 0x18              ; Ctrl+X
    je .paint_cut
    cmp al, 0x16              ; Ctrl+V
    je .paint_paste
    cmp al, 0x0E              ; Ctrl+N
    je .paint_new
    cmp al, 0x1A              ; Ctrl+Z
    je .paint_undo
    jmp .menu_escape
.paint_new:
    call request_paint_new
    ret
.paint_undo:
    call canvas_swap_undo
    ret
.paint_copy:
    cmp byte [paint_tool], PAINT_TOOL_TEXT
    jne .paint_copy_bitmap
    call paint_text_copy
    ret
.paint_copy_bitmap:
    call paint_selection_copy
    ret
.paint_cut:
    cmp byte [paint_tool], PAINT_TOOL_TEXT
    jne .paint_cut_bitmap
    call paint_text_cut
    ret
.paint_cut_bitmap:
    call paint_selection_cut
    ret
.paint_paste:
    cmp byte [clipboard_kind], 1
    jne .paint_paste_bitmap
    cmp byte [paint_tool], PAINT_TOOL_TEXT
    jne .done
    call paint_text_paste
    ret
.paint_paste_bitmap:
    call paint_selection_paste
    ret
.note_ctrl:
    cmp al, 0x01              ; Ctrl+A
    je .note_select_all
    cmp al, 0x03              ; Ctrl+C
    je .note_copy
    cmp al, 0x18              ; Ctrl+X
    je .note_cut
    cmp al, 0x16              ; Ctrl+V
    je .note_paste
    cmp al, 0x1A              ; Ctrl+Z
    je .note_undo
    cmp al, 0x0E              ; Ctrl+N
    je .note_new
    cmp al, 0x13              ; Ctrl+S (memory-only save acknowledgement)
    je .note_save
    cmp ah, 0x47              ; Ctrl+Home
    je .note_doc_home
    cmp ah, 0x4F              ; Ctrl+End
    je .note_doc_end
    cmp ah, 0x4B              ; Ctrl+Left
    je .note_word_left
    cmp ah, 0x4D              ; Ctrl+Right
    je .note_word_right
    cmp ah, 0x52              ; Ctrl+Insert = Copy
    je .note_copy
    cmp ah, 0x0E              ; Ctrl+Backspace = delete previous word
    je .note_delete_word_left
    cmp ah, 0x53              ; Ctrl+Delete = delete next word
    je .note_delete_word_right
    jmp .menu_escape
.note_select_all:
    call notepad_select_all
    ret
.note_copy:
    call notepad_copy
    ret
.note_cut:
    call notepad_cut
    ret
.note_paste:
    call notepad_paste
    ret
.note_undo:
    call notepad_undo
    ret
.note_new:
    call request_notepad_new
    ret
.note_save:
    call request_app_save
    ret
.app_save:
    call request_app_save
    ret
.note_doc_home:
    call notepad_prepare_move
    mov word [note_cursor], 0
    jmp notepad_finish_move
.note_doc_end:
    call notepad_prepare_move
    mov ax, [note_len]
    mov [note_cursor], ax
    jmp notepad_finish_move
.note_word_left:
    call notepad_word_left
    ret
.note_word_right:
    call notepad_word_right
    ret
.note_delete_word_left:
    call notepad_delete_word_left
    ret
.note_delete_word_right:
    call notepad_delete_word_right
    ret

.menu_escape:
    cmp byte [menu_open], MENU_NONE
    je .escape
    cmp al, 0x1B
    jne .window_keys
    mov byte [menu_open], MENU_NONE
    call redraw_all
    ret
.escape:
    cmp al, 0x1B
    jne .window_keys
    cmp byte [active_type], APP_NOTEPAD
    jne .escape_paint
    mov byte [note_sel_active], 0
    mov byte [note_mouse_select], 0
    jmp .escape_draw
.escape_paint:
    cmp byte [active_type], APP_PAINT
    jne .escape_draw
    cmp byte [paint_palette_open], 0
    je .escape_text
    mov byte [paint_palette_open], 0
    mov byte [paint_rgb_focus], 0
.escape_text:
    mov byte [paint_text_input], 0
    mov byte [paint_text_mouse_select], 0
.escape_draw:
    call redraw_all
    ret

.window_keys:
    cmp byte [active_type], APP_PAINT
    je .paint_keys
    cmp byte [active_type], APP_NOTEPAD
    je .note_keys
    cmp byte [active_type], APP_CALC
    je .calc_keys
    ret
.paint_keys:
    cmp byte [paint_palette_open], 0
    je .paint_text_keys
    call paint_palette_key
    ret
.paint_text_keys:
    cmp byte [paint_tool], PAINT_TOOL_SELECT
    jne .paint_text_mode
    cmp al, 13
    jne .paint_select_delete
    call paint_selection_confirm
    ret
.paint_select_delete:
    cmp ah, 0x53
    jne .done
    call paint_selection_delete
    ret
.paint_text_mode:
    cmp byte [paint_text_input], 0
    je .done
    call paint_text_key
    ret
.note_keys:
    cmp byte [note_open], 0
    je .done
    cmp byte [note_minimized], 0
    jne .done
    ; A foreground Notepad always routes keyboard input to its editor.  Paint,
    ; menus and title-bar clicks can legitimately leave the saved focus byte
    ; clear; requiring a second mouse click here caused intermittent dead input.
    mov byte [note_focus], 1
    ; Windows-style alternate clipboard keys.
    cmp ah, 0x52              ; Insert
    jne .note_delete_key
    test byte [shift_flags], 0x03
    jnz .note_paste
    ret
.note_delete_key:
    cmp ah, 0x53              ; Delete / Shift+Delete
    jne .note_arrows
    test byte [shift_flags], 0x03
    jnz .note_cut
    call notepad_delete_forward
    ret
.note_arrows:
    cmp ah, 0x4B
    je .note_left
    cmp ah, 0x4D
    je .note_right
    cmp ah, 0x48
    je .note_up
    cmp ah, 0x50
    je .note_down
    cmp ah, 0x47
    je .note_home
    cmp ah, 0x4F
    je .note_end
    cmp ah, 0x49
    je .note_pgup
    cmp ah, 0x51
    je .note_pgdn
    cmp al, 0x08
    je .note_backspace
    cmp al, 0x0D
    je .note_enter
    cmp al, 0x09
    je .note_tab
    cmp al, 0x20
    jb .done
    cmp al, 0x7E
    ja .done
    call notepad_can_insert
    jc .note_printable_mutate
    ret
.note_printable_mutate:
    mov byte [note_batch_changed], 0
    call notepad_insert_char
    cmp byte [note_batch_changed], 0
    je .done
    call notepad_ensure_cursor_visible
    call redraw_all
    ret
.note_left:
    call notepad_move_left
    ret
.note_right:
    call notepad_move_right
    ret
.note_up:
    call notepad_move_up
    ret
.note_down:
    call notepad_move_down
    ret
.note_home:
    call notepad_move_home
    ret
.note_end:
    call notepad_move_end
    ret
.note_pgup:
    call notepad_page_up
    ret
.note_pgdn:
    call notepad_page_down
    ret
.note_backspace:
    call notepad_backspace
    ret
.note_enter:
    call notepad_can_insert
    jc .note_enter_mutate
    ret
.note_enter_mutate:
    mov byte [note_batch_changed], 0
    mov al, 13
    call notepad_insert_char
    cmp byte [note_batch_changed], 0
    je .done
    call notepad_ensure_cursor_visible
    call redraw_all
    ret
.note_tab:
    call notepad_can_insert
    jc .note_tab_mutate
    ret
.note_tab_mutate:
    mov byte [note_batch_changed], 0
    mov byte [note_batch_input], 1
    mov cx, 4
.tab_loop:
    mov al, ' '
    push cx
    call notepad_insert_char
    pop cx
    loop .tab_loop
    mov byte [note_batch_input], 0
    cmp byte [note_batch_changed], 0
    je .done
    call notepad_ensure_cursor_visible
    call redraw_all
    ret

.calc_keys:
    cmp byte [calc_open], 0
    je .done
    cmp byte [calc_minimized], 0
    jne .done
    ; Numeric keypad works regardless of NumLock state.
    cmp ah, 0x47
    je .kp7
    cmp ah, 0x48
    je .kp8
    cmp ah, 0x49
    je .kp9
    cmp ah, 0x4B
    je .kp4
    cmp ah, 0x4C
    je .kp5
    cmp ah, 0x4D
    je .kp6
    cmp ah, 0x4F
    je .kp1
    cmp ah, 0x50
    je .kp2
    cmp ah, 0x51
    je .kp3
    cmp ah, 0x52
    je .kp0
    cmp ah, 0x4E
    je .kpplus
    cmp ah, 0x4A
    je .kpminus
    cmp ah, 0x37
    je .kpmul
    cmp al, '0'
    jb .calc_ops
    cmp al, '9'
    ja .calc_ops
    sub al, '0'
    call calc_input_digit
    call proc_save
    call redraw_all
    ret
.kp7:
    mov al, 7
    jmp .calc_digit
.kp8:
    mov al, 8
    jmp .calc_digit
.kp9:
    mov al, 9
    jmp .calc_digit
.kp4:
    mov al, 4
    jmp .calc_digit
.kp5:
    mov al, 5
    jmp .calc_digit
.kp6:
    mov al, 6
    jmp .calc_digit
.kp1:
    mov al, 1
    jmp .calc_digit
.kp2:
    mov al, 2
    jmp .calc_digit
.kp3:
    mov al, 3
    jmp .calc_digit
.kp0:
    xor al, al
.calc_digit:
    call calc_input_digit
    call proc_save
    call redraw_all
    ret
.kpplus:
    mov al, '+'
    jmp .calc_op
.kpminus:
    mov al, '-'
    jmp .calc_op
.kpmul:
    mov al, '*'
    jmp .calc_op
.calc_ops:
    cmp al, '+'
    je .calc_op
    cmp al, '-'
    je .calc_op
    cmp al, '*'
    je .calc_op
    cmp al, '/'
    je .calc_op
    cmp al, '.'
    je .calc_decimal
    cmp al, '%'
    je .calc_percent
    cmp al, 'r'
    je .calc_sqrt
    cmp al, 'R'
    je .calc_sqrt
    cmp al, 's'
    je .calc_sqrt
    cmp al, 'S'
    je .calc_sqrt
    cmp al, '='
    je .calc_equal
    cmp al, 0x0D
    je .calc_equal
    cmp al, 'c'
    je .calc_clear
    cmp al, 'C'
    je .calc_clear
    cmp al, 0x1B
    je .calc_clear
    cmp al, 0x08
    je .calc_back
    jmp .done
.calc_decimal:
    call calc_input_decimal
    call proc_save
    call redraw_all
    ret
.calc_percent:
    call calc_percent
    call proc_save
    call redraw_all
    ret
.calc_sqrt:
    call calc_sqrt
    call proc_save
    call redraw_all
    ret
.calc_op:
    call calc_set_operator
    call proc_save
    call redraw_all
    ret
.calc_equal:
    call calc_equal
    call proc_save
    call redraw_all
    ret
.calc_clear:
    call calc_clear
    ret
.calc_back:
    call calc_backspace
    call proc_save
    call redraw_all
.done:
    ret

.custom_modal:
    call CUSTOM_CODE_SEG:custom_entry_key
    ret

.debug_modal:
    cmp al, 0x1B
    jne .debug_nav
    cmp byte [debug_open], 6
    jne .debug_not_normal
    mov byte [debug_open], 5
    mov byte [debug_scroll_drag], 0
    call redraw_all
    ret
.debug_not_normal:
    cmp byte [debug_open], 2
    jb .debug_close
    mov byte [debug_open], 1
    mov byte [debug_scroll_drag], 0
    call redraw_all
    ret
.debug_close:
    mov byte [debug_open], 0
    mov byte [debug_scroll_drag], 0
    call redraw_all
    ret
.debug_nav:
    cmp byte [debug_open], 2
    je .debug_nav_ready
    cmp byte [debug_open], 3
    je .debug_nav_ready
    cmp byte [debug_open], 6
    jne .done
.debug_nav_ready:
    cmp ah, 0x48
    je .debug_key_up
    cmp ah, 0x50
    je .debug_key_down
    cmp ah, 0x49
    je .debug_key_page_up
    cmp ah, 0x51
    jne .done
    call debug_scroll_page_down
    ret
.debug_key_up:
    call debug_scroll_one_up
    ret
.debug_key_down:
    call debug_scroll_one_down
    ret
.debug_key_page_up:
    call debug_scroll_page_up
    ret

.control_modal:
    cmp al, 0x1B
    jne .control_key_speed
    mov byte [control_open], 0
    mov byte [control_slider_drag], 0
    call redraw_all
    ret
.control_key_speed:
    cmp ah, 0x4B
    je .control_slower
    cmp ah, 0x4D
    jne .done
    cmp byte [mouse_speed], 15
    jae .done
    inc byte [mouse_speed]
    mov byte [vm_abs_valid], 0
    call redraw_all
    ret
.control_slower:
    cmp byte [mouse_speed], 1
    jbe .done
    dec byte [mouse_speed]
    mov byte [vm_abs_valid], 0
    call redraw_all
    ret

.modal:
    cmp byte [message_kind], MSG_EXIT_CONFIRM
    je .modal_yes_no
    cmp byte [message_kind], MSG_UNSAVED
    je .modal_yes_no
    cmp byte [message_kind], MSG_OVERWRITE
    jne .modal_normal
.modal_yes_no:
    cmp al, 'y'
    je .modal_yes
    cmp al, 'Y'
    je .modal_yes
    cmp al, 'n'
    je .close_message
    cmp al, 'N'
    je .close_message
    cmp al, 0x1B
    je .close_message
    ret
.modal_yes:
    cmp byte [message_kind], MSG_EXIT_CONFIRM
    je enter_dos_mode
    cmp byte [message_kind], MSG_OVERWRITE
    je handle_overwrite_yes
    call handle_unsaved_yes
    ret
.modal_normal:
    cmp al, 0x1B
    je .close_message
    cmp al, 0x0D
    jne .done
.close_message:
    mov byte [message_open], 0
    mov byte [pending_unsaved_pid], 0
    mov byte [pending_unsaved_action], 0
    call redraw_all
    ret

.move_mode:
    cmp al, 0x1B
    je .move_done
    cmp al, 0x0D
    je .move_done
    cmp ah, 0x4B
    je .move_left
    cmp ah, 0x4D
    je .move_right
    cmp ah, 0x48
    je .move_up
    cmp ah, 0x50
    je .move_down
    ret
.move_left:
    mov dx, -2
    xor cx, cx
    jmp .move_apply
.move_right:
    mov dx, 2
    xor cx, cx
    jmp .move_apply
.move_up:
    xor dx, dx
    mov cx, -2
    jmp .move_apply
.move_down:
    xor dx, dx
    mov cx, 2
.move_apply:
    call keyboard_move_window
    ret
.move_done:
    mov byte [keyboard_move_mode], 0
    call redraw_all
    ret

keyboard_move_window:
    ; DX=signed x delta, CX=signed y delta, mode stores pid+1.
    push ax
    push bx
    mov al, [keyboard_move_mode]
    dec al
    cmp al, WIN_MAIN
    jne .app
    cmp byte [main_maximized], 0
    jne .done
    mov ax, [main_x]
    add ax, dx
    mov [main_x], ax
    mov ax, [main_y]
    add ax, cx
    mov [main_y], ax
    call clamp_main_position
    jmp .redraw
.app:
    call proc_load
    mov al, [active_type]
    cmp al, APP_PAINT
    je .paint
    cmp al, APP_NOTEPAD
    je .note
    cmp al, APP_CALC
    je .calc
    jmp .done
.paint:
    cmp byte [paint_maximized], 0
    jne .done
    mov ax, [paint_x]
    add ax, dx
    mov [paint_x], ax
    mov ax, [paint_y]
    add ax, cx
    mov [paint_y], ax
    call clamp_paint_position
    jmp .redraw
.note:
    cmp byte [note_maximized], 0
    jne .done
    mov ax, [note_x]
    add ax, dx
    mov [note_x], ax
    mov ax, [note_y]
    add ax, cx
    mov [note_y], ax
    call clamp_note_position
    jmp .redraw
.calc:
    cmp byte [calc_maximized], 0
    jne .done
    mov ax, [calc_x]
    add ax, dx
    mov [calc_x], ax
    mov ax, [calc_y]
    add ax, cx
    mov [calc_y], ax
    call clamp_calc_position
.redraw:
    call redraw_all
.done:
    pop bx
    pop ax
    ret

clamp_main_position:
    cmp word [main_x], SCREEN_W
    jb .x_positive
    mov word [main_x], 0
.x_positive:
    mov ax, SCREEN_W
    sub ax, [main_w]
    cmp [main_x], ax
    jbe .y
    mov [main_x], ax
.y:
    cmp word [main_y], TASKBAR_Y
    jb .y_positive
    mov word [main_y], 0
.y_positive:
    mov ax, TASKBAR_Y
    sub ax, [main_h]
    cmp [main_y], ax
    jbe .done
    mov [main_y], ax
.done:
    ret

clamp_paint_position:
    cmp word [paint_x], SCREEN_W
    jb .x_ok0
    mov word [paint_x], 0
.x_ok0:
    mov ax, SCREEN_W
    sub ax, [paint_w]
    cmp [paint_x], ax
    jbe .y
    mov [paint_x], ax
.y:
    cmp word [paint_y], TASKBAR_Y
    jb .y_ok0
    mov word [paint_y], 0
.y_ok0:
    mov ax, TASKBAR_Y
    sub ax, [paint_h]
    cmp [paint_y], ax
    jbe .done
    mov [paint_y], ax
.done:
    ret

clamp_note_position:
    cmp word [note_x], SCREEN_W
    jb .x_ok0
    mov word [note_x], 0
.x_ok0:
    mov ax, SCREEN_W
    sub ax, [note_w]
    cmp [note_x], ax
    jbe .y
    mov [note_x], ax
.y:
    cmp word [note_y], TASKBAR_Y
    jb .y_ok0
    mov word [note_y], 0
.y_ok0:
    mov ax, TASKBAR_Y
    sub ax, [note_h]
    cmp [note_y], ax
    jbe .done
    mov [note_y], ax
.done:
    ret

clamp_calc_position:
    cmp word [calc_x], SCREEN_W
    jb .x_ok0
    mov word [calc_x], 0
.x_ok0:
    mov ax, SCREEN_W
    sub ax, [calc_w]
    cmp [calc_x], ax
    jbe .y
    mov [calc_x], ax
.y:
    cmp word [calc_y], TASKBAR_Y
    jb .y_ok0
    mov word [calc_y], 0
.y_ok0:
    mov ax, TASKBAR_Y
    sub ax, [calc_h]
    cmp [calc_y], ax
    jbe .done
    mov [calc_y], ax
.done:
    ret

open_foreground_system_menu:
    mov al, [foreground_window]
    mov [menu_owner_pid], al
    mov [system_menu_window], al
    cmp al, WIN_MAIN
    jne .app
    mov byte [menu_open], MENU_SYS_MAIN
    jmp .draw
.app:
    call proc_load
    mov al, [active_type]
    cmp al, APP_PAINT
    je .paint
    cmp al, APP_NOTEPAD
    je .note
    mov byte [menu_open], MENU_SYS_CALC
    jmp .draw
.paint:
    mov byte [menu_open], MENU_SYS_PAINT
    jmp .draw
.note:
    mov byte [menu_open], MENU_SYS_NOTE
.draw:
    call redraw_all
    ret

close_foreground:
    cmp byte [message_open], 0
    jne .close_message
    mov al, [foreground_window]
    call close_window_by_id
    ret
.close_message:
    mov byte [message_open], 0
    call redraw_all
    ret

switch_foreground:
    ; Cycle through the dynamically packed task list.
    push ax
    push bx
    push cx
    push dx
    xor cx, cx
    mov cl, [task_count]
    cmp cx, 1
    jbe .done
    xor bx, bx
.find_current:
    cmp bx, cx
    jae .start_zero
    mov al, [task_order+bx]
    cmp al, [foreground_window]
    je .next
    inc bx
    jmp .find_current
.start_zero:
    xor bx, bx
    jmp .try
.next:
    inc bx
    cmp bx, cx
    jb .try
    xor bx, bx
.try:
    mov dl, [task_order+bx]
    cmp dl, [foreground_window]
    je .done
    cmp dl, WIN_CUSTOM
    jne .normal_task
    mov byte [custom_open], 1
    mov byte [custom_minimized], 0
    mov byte [menu_open], MENU_NONE
    call redraw_all
    jmp short .done
.normal_task:
    cmp byte [custom_open], 0
    je .restore_task
    mov byte [custom_open], 0
    mov byte [custom_minimized], 1
.restore_task:
    mov al, dl
    call restore_window_no_draw
    mov al, dl
    call bring_to_front
    mov byte [menu_open], MENU_NONE
    call redraw_all
.done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

restore_window_no_draw:
    cmp al, WIN_MAIN
    jne .app
    mov byte [main_minimized], 0
    ret
.app:
    xor bx, bx
    mov bl, al
    cmp bx, MAX_PROCS
    jae .done
    cmp byte [proc_type+bx], APP_NONE
    je .done
    mov byte [proc_minimized+bx], 0
    call proc_load
.done:
    ret

mouse_cursor_hide:
    cmp byte [cursor_visible], 0
    je .done
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push es
    mov ax, VGA_SEG
    mov es, ax
    xor bp, bp
    xor si, si
.row:
    cmp bp, CURSOR_H
    jae .finish
    xor bx, bx
.col:
    cmp bx, CURSOR_W
    jae .next_row
    mov ax, [cursor_draw_x]
    add ax, bx
    cmp ax, SCREEN_W
    jae .skip
    mov dx, [cursor_draw_y]
    add dx, bp
    cmp dx, SCREEN_H
    jae .skip
    mov di, dx
    mov cx, dx
    shl di, 6
    shl cx, 8
    add di, cx
    add di, ax
    mov al, [cursor_save+si]
    mov es:[di], al
.skip:
    inc si
    inc bx
    jmp .col
.next_row:
    inc bp
    jmp .row
.finish:
    mov byte [cursor_visible], 0
    pop es
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
.done:
    ret

mouse_cursor_show:
    cmp byte [cursor_visible], 0
    jne .done
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push es
    call cursor_choose_shape
    mov ax, [mouse_x]
    sub ax, [cursor_hotspot_x]
    jnc .x_ready
    xor ax, ax
.x_ready:
    mov [cursor_draw_x], ax
    mov ax, [mouse_y]
    sub ax, [cursor_hotspot_y]
    jnc .y_ready
    xor ax, ax
.y_ready:
    mov [cursor_draw_y], ax
    mov ax, VGA_SEG
    mov es, ax
    xor bp, bp
    xor si, si
.row:
    cmp bp, CURSOR_H
    jae .finish
    xor bx, bx
.col:
    cmp bx, CURSOR_W
    jae .next_row
    mov ax, [cursor_draw_x]
    add ax, bx
    cmp ax, SCREEN_W
    jae .offscreen
    mov dx, [cursor_draw_y]
    add dx, bp
    cmp dx, SCREEN_H
    jae .offscreen
    mov di, dx
    mov cx, dx
    shl di, 6
    shl cx, 8
    add di, cx
    add di, ax
    mov al, es:[di]
    mov [cursor_save+si], al
    cmp byte [cursor_kind], 0
    je .arrow_shape
    cmp byte [cursor_kind], 1
    je .picker_shape
    cmp byte [cursor_kind], 2
    je .ibeam_shape
    cmp byte [cursor_kind], 3
    je .move_shape
    cmp byte [cursor_kind], 5
    je .nwse_shape
    cmp byte [cursor_kind], 6
    je .nesw_shape
    cmp byte [cursor_kind], 7
    je .ns_shape
    mov al, [aero_ew_cursor_shape+si]
    jmp .shape_ready
.ibeam_shape:
    mov al, [ibeam_cursor_shape+si]
    jmp .shape_ready
.arrow_shape:
    mov al, [cursor_shape+si]
    jmp .shape_ready
.picker_shape:
    mov al, [picker_cursor_shape+si]
    jmp .shape_ready
.move_shape:
    mov al, [aero_move_cursor_shape+si]
    jmp .shape_ready
.nwse_shape:
    mov al, [aero_nwse_cursor_shape+si]
    jmp .shape_ready
.nesw_shape:
    mov al, [aero_nesw_cursor_shape+si]
    jmp .shape_ready
.ns_shape:
    mov al, [aero_ns_cursor_shape+si]
.shape_ready:
    test al, al
    jz .advance
    cmp al, 1
    jne .white
    mov byte es:[di], COL_BLACK
    jmp .advance
.white:
    mov byte es:[di], COL_WHITE
    jmp .advance
.offscreen:
    mov byte [cursor_save+si], 0
.advance:
    inc si
    inc bx
    jmp .col
.next_row:
    inc bp
    jmp .row
.finish:
    mov byte [cursor_visible], 1
    pop es
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
.done:
    ret

cursor_choose_shape:
    ; Special cursors are used only over the foreground Paint canvas.
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov byte [cursor_kind], 0
    mov word [cursor_hotspot_x], 0
    mov word [cursor_hotspot_y], 0

    ; Modal UI normally uses the arrow.  The Custom Program window is the one
    ; exception: its live bottom-right resize grip advertises NW-SE resizing.
    cmp byte [message_open], 0
    jne .done
    cmp byte [debug_open], 0
    jne .done
    cmp byte [control_open], 0
    jne .done
    cmp byte [custom_open], 0
    je .not_custom
    ; Keep the overlay-specific hit test in the Custom Program segment.  This
    ; also preserves the base stage's original on-disk sector layout.
    call CUSTOM_CODE_SEG:custom_entry_cursor_shape
    jmp .done
.not_custom:
    call cursor_choose_window_resize
    jc .done

    xor bx, bx
    mov bl, [foreground_window]
    test bx, bx
    jz .done
    cmp bx, MAX_PROCS
    jae .done
    cmp byte [proc_type+bx], APP_PAINT
    jne .done
    cmp byte [proc_minimized+bx], 0
    jne .done
    cmp byte [proc_paint_palette_open+bx], 0
    jne .done

    mov si, bx
    shl si, 1
    mov cx, [proc_x+si]
    add cx, PAINT_CANVAS_XOFF
    mov dx, [proc_y+si]
    add dx, PAINT_CANVAS_YOFF
    mov ax, [proc_w+si]
    sub ax, PAINT_CANVAS_XOFF+PAINT_CANVAS_RIGHT_MARGIN
    mov di, ax
    mov ax, [proc_h+si]
    sub ax, PAINT_CANVAS_YOFF+PAINT_CANVAS_BOTTOM_MARGIN
    mov si, ax
    xchg si, di                 ; SI=width, DI=height for hit_rect
    call hit_rect
    jnc .done

    xor bx, bx
    mov bl, [foreground_window]
    cmp byte [proc_paint_tool+bx], PAINT_TOOL_EYEDROP
    je .picker
    cmp byte [proc_paint_tool+bx], PAINT_TOOL_TEXT
    je .ibeam
    cmp byte [proc_paint_tool+bx], PAINT_TOOL_SELECT
    je .select
    jmp .done
.picker:
    mov byte [cursor_kind], 1
    mov word [cursor_hotspot_x], 1
    mov word [cursor_hotspot_y], 1
    jmp .done
.ibeam:
    mov byte [cursor_kind], 2
    mov word [cursor_hotspot_x], 3
    mov word [cursor_hotspot_y], 5
    jmp .done
.select:
    cmp byte [paint_select_active], 0
    je .done
    ; The selection state belongs to the active Paint process. Convert the
    ; pointer to local coordinates and show an open/closed hand in its body.
    mov ax, [mouse_x]
    mov bx, [mouse_y]
    call paint_screen_point_to_local
    jnc .done
    cmp ax, [paint_select_x]
    jb .done
    mov dx, [paint_select_x]
    add dx, [paint_select_w]
    cmp ax, dx
    ja .done
    cmp bx, [paint_select_y]
    jb .done
    mov dx, [paint_select_y]
    add dx, [paint_select_h]
    cmp bx, dx
    ja .done
    cmp byte [paint_select_drag], 2
    je .select_move
    cmp byte [paint_select_drag], 3
    je .select_handle_ready
    mov byte [paint_select_handle], 0
    mov dx, ax
    sub dx, [paint_select_x]
    cmp dx, 2
    ja .hover_right
    or byte [paint_select_handle], 1
.hover_right:
    mov dx, [paint_select_x]
    add dx, [paint_select_w]
    dec dx
    sub dx, ax
    cmp dx, 2
    ja .hover_top
    or byte [paint_select_handle], 2
.hover_top:
    mov dx, bx
    sub dx, [paint_select_y]
    cmp dx, 2
    ja .hover_bottom
    or byte [paint_select_handle], 4
.hover_bottom:
    mov dx, [paint_select_y]
    add dx, [paint_select_h]
    dec dx
    sub dx, bx
    cmp dx, 2
    ja .select_handle_ready
    or byte [paint_select_handle], 8
.select_handle_ready:
    mov al, [paint_select_handle]
    test al, al
    jz .select_move
    cmp al, 5
    je .select_nwse
    cmp al, 10
    je .select_nwse
    cmp al, 6
    je .select_nesw
    cmp al, 9
    je .select_nesw
    test al, 0x0C
    jnz .select_ns
    mov byte [cursor_kind], 8
    jmp .select_hotspot
.select_nwse:
    mov byte [cursor_kind], 5
    jmp .select_hotspot
.select_nesw:
    mov byte [cursor_kind], 6
    jmp .select_hotspot
.select_ns:
    mov byte [cursor_kind], 7
    jmp .select_hotspot
.select_move:
    mov byte [cursor_kind], 3
.select_hotspot:
    mov word [cursor_hotspot_x], 5
    mov word [cursor_hotspot_y], 5
.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

cursor_choose_window_resize:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    xor bx, bx
    mov bl, [foreground_window]
    test bx, bx
    jz .main
    cmp bx, MAX_PROCS
    jae .no
    cmp byte [proc_minimized+bx], 0
    jne .no
    cmp byte [proc_maximized+bx], 0
    jne .no
    mov si, bx
    shl si, 1
    mov cx, [proc_x+si]
    add cx, [proc_w+si]
    sub cx, 10
    mov dx, [proc_y+si]
    add dx, [proc_h+si]
    sub dx, 10
    jmp .hit
.main:
    cmp byte [main_minimized], 0
    jne .no
    cmp byte [main_maximized], 0
    jne .no
    mov cx, [main_x]
    add cx, [main_w]
    sub cx, 10
    mov dx, [main_y]
    add dx, [main_h]
    sub dx, 10
.hit:
    mov si, 10
    mov di, 10
    call hit_rect
    jnc .no
    mov byte [cursor_kind], 5
    mov word [cursor_hotspot_x], 5
    mov word [cursor_hotspot_y], 5
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    stc
    ret
.no:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    clc
    ret

init_mouse_support:
    mov byte [mouse_mode], 0
    mov byte [mouse_ps2_packet_size], 3
    mov byte [mouse_ps2_device_id], 0
    mov byte [mouse_ps2_pktcnt], 0
    call mouse_vmware_detect
    jc .ps2
    call mouse_vmware_enable_abs
    jc .ps2
    mov byte [mouse_mode], 1
    ret
.ps2:
    mov byte [mouse_mode], 0
    call mouse_ps2_init
    ret

mouse_record_hover_if_released:
    ; Mouse backends can drain several packets in one poll.  Record every
    ; button-up packet immediately so a following bad press packet cannot erase
    ; the last real pointer position before Paint receives the click.
    push ax
    test byte [mouse_buttons], 1
    jnz .done
.released:
    mov ax, [mouse_x]
    mov [mouse_hover_x], ax
    mov ax, [mouse_y]
    mov [mouse_hover_y], ax
    mov byte [mouse_hover_valid], 1
.done:
    pop ax
    ret

mouse_scale_delta:
    ; AX=signed relative delta. Fifteen useful steps span 1/4x..3x, with
    ; step 8 exactly 1x.
    push bx
    push cx
    push dx
    xor bx, bx
    mov bl, [mouse_speed]
    dec bx
    mov cl, [mouse_speed_num+bx]
    xor ch, ch
    imul cx
    mov cx, 8
    idiv cx
.done:
    pop dx
    pop cx
    pop bx
    ret

mouse_apply_button_swap:
    push ax
    push bx
    mov al, [mouse_raw_buttons]
    cmp byte [mouse_swap_buttons], 0
    je .store
    mov bl, al
    and al, 0xFC
    test bl, 1
    jz .no_left
    or al, 2
.no_left:
    test bl, 2
    jz .no_right
    or al, 1
.no_right:
.store:
    mov [mouse_buttons], al
    pop bx
    pop ax
.done:
    ret

control_write_boot_setting:
    call STAGE2_EXT_SEG:(control_write_boot_setting_ext-stage2_ext_start)
    ret

poll_mouse:
    cmp byte [mouse_mode], 1
    jne .ps2
    call mouse_poll_vmware
    jmp .compare
.ps2:
    call mouse_poll_ps2
.compare:
    call mouse_apply_button_swap
    call mouse_record_hover_if_released
    mov byte [mouse_changed], 0
    cmp byte [mouse_wheel], 0
    jne .changed
    mov ax, [mouse_x]
    cmp ax, [mouse_last_x]
    jne .changed
    mov ax, [mouse_y]
    cmp ax, [mouse_last_y]
    jne .changed
    mov al, [mouse_buttons]
    cmp al, [mouse_prev_buttons]
    jne .changed
    ret
.changed:
    mov byte [mouse_changed], 1
    mov ax, [mouse_x]
    mov [mouse_last_x], ax
    mov ax, [mouse_y]
    mov [mouse_last_y], ax
    ret

mouse_clamp:
    cmp word [mouse_x], SCREEN_W-1
    jbe .y
    mov word [mouse_x], SCREEN_W-1
.y:
    cmp word [mouse_y], SCREEN_H-1
    jbe .done
    mov word [mouse_y], SCREEN_H-1
.done:
    ret

mouse_ps2_wait_input_clear:
    push cx
    mov cx, 0xFFFF
.loop:
    in al, 0x64
    test al, 2
    jz .ok
    loop .loop
    pop cx
    stc
    ret
.ok:
    pop cx
    clc
    ret

mouse_ps2_wait_output:
    push cx
    mov cx, 0xFFFF
.loop:
    in al, 0x64
    test al, 1
    jnz .ok
    loop .loop
    pop cx
    stc
    ret
.ok:
    pop cx
    clc
    ret

mouse_ps2_flush:
    push ax
    push cx
    mov cx, 0x1000
.loop:
    in al, 0x64
    test al, 1
    jz .done
    test al, 0x20
    jz .done                       ; leave keyboard bytes for BIOS IRQ1
    in al, 0x60
    loop .loop
.done:
    pop cx
    pop ax
    ret

mouse_ps2_write_aux:
    push bx
    mov bl, al
    call mouse_ps2_wait_input_clear
    jc .fail
    mov al, 0xD4
    out 0x64, al
    call mouse_ps2_wait_input_clear
    jc .fail
    mov al, bl
    out 0x60, al
    pop bx
    clc
    ret
.fail:
    pop bx
    stc
    ret

mouse_ps2_read_ack:
    call mouse_ps2_wait_output
    jc .fail
    in al, 0x60
    cmp al, 0xFA
    jne .fail
    clc
    ret
.fail:
    stc
    ret

mouse_ps2_send_cmd:
    push ax
    call mouse_ps2_write_aux
    jc .fail
    call mouse_ps2_read_ack
    jc .fail
    pop ax
    clc
    ret
.fail:
    pop ax
    stc
    ret

mouse_ps2_send_cmd_data:
    push ax
    push bx
    mov bl, al
    call mouse_ps2_write_aux
    jc .fail
    call mouse_ps2_read_ack
    jc .fail
    mov al, ah
    call mouse_ps2_write_aux
    jc .fail
    call mouse_ps2_read_ack
    jc .fail
    pop bx
    pop ax
    clc
    ret
.fail:
    pop bx
    pop ax
    stc
    ret

mouse_ps2_get_id:
    mov al, 0xF2
    call mouse_ps2_send_cmd
    jc .fail
    call mouse_ps2_wait_output
    jc .fail
    in al, 0x60
    clc
    ret
.fail:
    stc
    ret

mouse_ps2_init:
    call mouse_ps2_flush
    call mouse_ps2_wait_input_clear
    jc .done
    mov al, 0xA8
    out 0x64, al

    ; Enable the auxiliary clock; keep IRQ12 disabled because we poll.
    call mouse_ps2_wait_input_clear
    jc .defaults
    mov al, 0x20
    out 0x64, al
    call mouse_ps2_wait_output
    jc .defaults
    in al, 0x60
    and al, 0xFD
    and al, 0xDF
    mov bl, al
    call mouse_ps2_wait_input_clear
    jc .defaults
    mov al, 0x60
    out 0x64, al
    call mouse_ps2_wait_input_clear
    jc .defaults
    mov al, bl
    out 0x60, al

.defaults:
    mov al, 0xF6
    call mouse_ps2_send_cmd
    mov byte [mouse_ps2_packet_size], 3

    ; IntelliMouse wheel negotiation: 200,100,80.
    mov ax, 0xC8F3
    call mouse_ps2_send_cmd_data
    jc .stream
    mov ax, 0x64F3
    call mouse_ps2_send_cmd_data
    jc .stream
    mov ax, 0x50F3
    call mouse_ps2_send_cmd_data
    jc .stream
    call mouse_ps2_get_id
    jc .stream
    cmp al, 3
    je .wheel_id_ok
    cmp al, 4
    jne .stream
.wheel_id_ok:
    mov [mouse_ps2_device_id], al
    mov byte [mouse_ps2_packet_size], 4
.stream:
    mov al, 0xF4
    call mouse_ps2_send_cmd
.done:
    ret

mouse_ps2_disable_stream:
    ; Restore a clean BIOS-keyboard controller state before blocking in INT 16h.
    ; IRQs are masked while controller replies are read so the BIOS IRQ1 handler
    ; cannot consume the command-byte response.  No user key can be pending here:
    ; DOS is entered by releasing the mouse on the confirmation button.
    pushf
    cli
    push ax

    ; Controller-level clock gating is sufficient here.  Do not wait for a
    ; mouse-device ACK while changing pages.
    call mouse_ps2_wait_input_clear
    jc .enable_keyboard_only
    mov al, 0xA7                    ; disable auxiliary interface
    out 0x64, al
    call mouse_ps2_flush            ; remove stale mouse/ACK packets

.enable_keyboard_only:
    call mouse_ps2_wait_input_clear
    jc .done
    mov al, 0xAE                    ; explicitly enable keyboard interface
    out 0x64, al
    ; Leave keyboard scan, typematic and queued key data entirely to BIOS.
.done:
    pop ax
    popf
    ret


mouse_ps2_try_read:
    in al, 0x64
    test al, 1
    jz .none
    test al, 0x20
    jz .none                 ; do not steal keyboard bytes from BIOS
    in al, 0x60
    clc
    ret
.none:
    stc
    ret

mouse_poll_ps2:
.loop:
    call mouse_ps2_try_read
    jc .done
    xor bx, bx
    mov bl, [mouse_ps2_pktcnt]
    mov [mouse_ps2_pkt+bx], al
    inc byte [mouse_ps2_pktcnt]
    cmp byte [mouse_ps2_pktcnt], 1
    jne .full_check
    test al, 0x08
    jnz .full_check
    mov byte [mouse_ps2_pktcnt], 0
    jmp .loop
.full_check:
    mov al, [mouse_ps2_pktcnt]
    cmp al, [mouse_ps2_packet_size]
    jb .loop
    mov byte [mouse_ps2_pktcnt], 0

    mov al, [mouse_ps2_pkt]
    test al, 0xC0
    jnz .loop

    mov al, [mouse_ps2_pkt+1]
    cbw
    call mouse_scale_delta
    mov bx, [mouse_x]
    add bx, ax
    jns .x_nonneg
    xor bx, bx
.x_nonneg:
    cmp bx, SCREEN_W-1
    jbe .x_store
    mov bx, SCREEN_W-1
.x_store:
    mov [mouse_x], bx

    mov al, [mouse_ps2_pkt+2]
    cbw
    call mouse_scale_delta
    neg ax
    mov bx, [mouse_y]
    add bx, ax
    jns .y_nonneg
    xor bx, bx
.y_nonneg:
    cmp bx, SCREEN_H-1
    jbe .y_store
    mov bx, SCREEN_H-1
.y_store:
    mov [mouse_y], bx

    xor al, al
    mov bl, [mouse_ps2_pkt]
    test bl, 1
    jz .no_l
    or al, 1
.no_l:
    test bl, 2
    jz .no_r
    or al, 2
.no_r:
    test bl, 4
    jz .no_m
    or al, 4
.no_m:
    mov [mouse_raw_buttons], al
    cmp byte [mouse_ps2_packet_size], 4
    jne .loop
    ; Normalize to MiniWin convention: positive=scroll up, negative=down.
    ; ID 3 carries a signed byte; ID 4 carries signed 4-bit wheel data.
    mov al, [mouse_ps2_pkt+3]
    cmp byte [mouse_ps2_device_id], 3
    je .wheel_signed
    and al, 0x0F
    shl al, 4
    sar al, 4
.wheel_signed:
    neg al
    test al, al
    jz .loop
    mov [mouse_wheel], al
    jmp .loop
.done:
    ret

mouse_vmware_detect:
    mov eax, VMWARE_MAGIC
    mov ebx, 0xFFFFFFFF
    mov ecx, VMWARE_CMD_GETVERSION
    mov dx, VMWARE_PORT
    in eax, dx
    cmp ebx, VMWARE_MAGIC
    jne .no
    cmp eax, 0xFFFFFFFF
    je .no
    clc
    ret
.no:
    stc
    ret

mouse_vmware_send_cmd:
    mov eax, VMWARE_MAGIC
    mov ecx, VMWARE_CMD_ABSPOINTER_COMMAND
    mov dx, VMWARE_PORT
    in eax, dx
    ret

mouse_vmware_status:
    mov eax, VMWARE_MAGIC
    xor ebx, ebx
    mov ecx, VMWARE_CMD_ABSPOINTER_STATUS
    mov dx, VMWARE_PORT
    in eax, dx
    ret

mouse_vmware_read4:
    mov eax, VMWARE_MAGIC
    mov ebx, 4
    mov ecx, VMWARE_CMD_ABSPOINTER_DATA
    mov dx, VMWARE_PORT
    in eax, dx
    ret

mouse_vmware_enable_abs:
    mov ebx, VMMOUSE_CMD_ENABLE
    call mouse_vmware_send_cmd
    call mouse_vmware_status
    and eax, 0xFFFF
    jz .fail

    mov eax, VMWARE_MAGIC
    mov ebx, 1
    mov ecx, VMWARE_CMD_ABSPOINTER_DATA
    mov dx, VMWARE_PORT
    in eax, dx
    cmp eax, VMMOUSE_VERSION_ID
    jne .disable

    mov eax, VMWARE_MAGIC
    mov ebx, VMMOUSE_RESTRICT_CPL0
    mov ecx, VMWARE_CMD_ABSPOINTER_RESTRICT
    mov dx, VMWARE_PORT
    in eax, dx

    mov ebx, VMMOUSE_CMD_REQUEST_ABSOLUTE
    call mouse_vmware_send_cmd
    clc
    ret
.disable:
    mov ebx, VMMOUSE_CMD_DISABLE
    call mouse_vmware_send_cmd
.fail:
    stc
    ret

mouse_poll_vmware:
    call mouse_vmware_status
    mov edx, eax
    and edx, VMMOUSE_ERROR
    cmp edx, VMMOUSE_ERROR
    je .done
    and eax, 0xFFFF
    cmp ax, 4
    jb .done
.loop:
    call mouse_vmware_read4
    mov [vm_flags], eax
    mov [vm_x], bx
    mov [vm_y], cx
    mov [vm_z], edx
    ; VMMouse reports wheel z in the signed low byte.  Testing the sign of
    ; the whole EDX made both 00000001h and 000000FFh look positive, so both
    ; wheel directions scrolled upward.  Linux-compatible normalization is
    ; REL_WHEEL = -(signed byte)z.
    mov al, [vm_z]
    cbw
    neg ax
    test al, al
    jz .wheel_done
    mov [mouse_wheel], al
.wheel_done:

    xor al, al
    test word [vm_flags], VMMOUSE_LEFT_BUTTON
    jz .no_l
    or al, 1
.no_l:
    test word [vm_flags], VMMOUSE_RIGHT_BUTTON
    jz .no_r
    or al, 2
.no_r:
    test word [vm_flags], VMMOUSE_MIDDLE_BUTTON
    jz .no_m
    or al, 4
.no_m:
    mov [mouse_raw_buttons], al

    test dword [vm_flags], VMMOUSE_RELATIVE_PACKET
    jnz .relative

    mov ax, [vm_x]
    mov bx, SCREEN_W
    mul bx
    mov [vm_abs_new_x], dx
    mov ax, [vm_y]
    mov bx, SCREEN_H
    mul bx
    mov [vm_abs_new_y], dx
    cmp byte [vm_abs_valid], 0
    jne .abs_delta
    mov byte [vm_abs_valid], 1
    mov ax, [vm_abs_new_x]
    mov [mouse_x], ax
    mov [vm_abs_prev_x], ax
    mov ax, [vm_abs_new_y]
    mov [mouse_y], ax
    mov [vm_abs_prev_y], ax
    jmp .next
.abs_delta:
    cmp byte [mouse_speed], 8
    jne .abs_scaled
    ; At the normal setting the guest cursor follows the host absolute
    ; coordinate every packet, continuously eliminating accumulated offset.
    mov ax, [vm_abs_new_x]
    mov [mouse_x], ax
    mov [vm_abs_prev_x], ax
    mov ax, [vm_abs_new_y]
    mov [mouse_y], ax
    mov [vm_abs_prev_y], ax
    jmp .next
.abs_scaled:
    mov ax, [vm_abs_new_x]
    sub ax, [vm_abs_prev_x]
    call mouse_scale_delta
    movsx eax, ax
    movzx ebx, word [mouse_x]
    add eax, ebx
    cmp eax, 0
    jge .abs_x_nonnegative
    xor eax, eax
.abs_x_nonnegative:
    cmp eax, SCREEN_W-1
    jle .abs_x_store
    mov eax, SCREEN_W-1
.abs_x_store:
    mov [mouse_x], ax
    mov ax, [vm_abs_new_y]
    sub ax, [vm_abs_prev_y]
    call mouse_scale_delta
    movsx eax, ax
    movzx ebx, word [mouse_y]
    add eax, ebx
    cmp eax, 0
    jge .abs_y_nonnegative
    xor eax, eax
.abs_y_nonnegative:
    cmp eax, SCREEN_H-1
    jle .abs_y_store
    mov eax, SCREEN_H-1
.abs_y_store:
    mov [mouse_y], ax
    mov ax, [vm_abs_new_x]
    mov [vm_abs_prev_x], ax
    mov ax, [vm_abs_new_y]
    mov [vm_abs_prev_y], ax
    jmp .next

.relative:
    mov ax, [vm_x]
    call mouse_scale_delta
    movsx eax, ax
    movzx ebx, word [mouse_x]
    add eax, ebx
    cmp eax, 0
    jge .rx_nonneg
    xor eax, eax
.rx_nonneg:
    cmp eax, SCREEN_W-1
    jle .rx_store
    mov eax, SCREEN_W-1
.rx_store:
    mov [mouse_x], ax

    mov ax, [vm_y]
    call mouse_scale_delta
    movsx eax, ax
    movzx ebx, word [mouse_y]
    sub ebx, eax
    cmp ebx, 0
    jge .ry_nonneg
    xor ebx, ebx
.ry_nonneg:
    cmp ebx, SCREEN_H-1
    jle .ry_store
    mov ebx, SCREEN_H-1
.ry_store:
    mov [mouse_y], bx

.next:
    call mouse_clamp
    call mouse_vmware_status
    mov edx, eax
    and edx, VMMOUSE_ERROR
    cmp edx, VMMOUSE_ERROR
    je .done
    and eax, 0xFFFF
    cmp ax, 4
    jae .loop
.done:
    ret

; =============================================================================
; DOS-like command environment entered after leaving Program Manager
; =============================================================================
enter_dos_mode:
    ; Discard GUI handler return frames and enter a text-mode command shell.
    cli
    mov ax, STACK_SEG
    mov ss, ax
    mov sp, STACK_TOP
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov byte [custom_ext_loaded], 1
    mov byte [system_watchdog_enabled], 0
    mov byte [system_watchdog_ticks], 0
    call system_install_exception_hooks
    call gui_snapshot_restore
    sti
    call mouse_cursor_hide
    call mouse_ps2_disable_stream
    mov ax, 0x0003
    int 0x10
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov byte [system_display_mode], 0
    ; Disable blink so the high background bit provides all 16 colors.
    mov ax, 0x1003
    xor bx, bx
    int 0x10
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov byte [cursor_visible], 0
    mov byte [mouse_prev_buttons], 0
    mov byte [dos_attr], 0x07
    mov byte [dos_errorlevel], 0
    call dos_clear_screen
    mov eax, dos_banner_text
    call dos_print_linear

dos_command_loop:
    mov byte [system_watchdog_enabled], 0
    mov eax, dos_prompt
    call dos_print_linear
    call dos_readline
    call dos_crlf
    mov byte [system_watchdog_ticks], 0
    mov byte [system_watchdog_reason], BSOD_STOP_WATCHDOG
    mov byte [system_watchdog_enabled], 1
    call dos_execute
    mov byte [system_watchdog_enabled], 0
    jmp dos_command_loop

dos_set_cursor:
    push ax
    push bx
    push dx
    push si
    push di
    push bp
    push ds
    push es
    mov ah, 0x02
    xor bh, bh
    mov dh, [dos_cursor_y]
    mov dl, [dos_cursor_x]
    int 0x10
    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop dx
    pop bx
    pop ax
    ret

dos_scroll_if_needed:
    cmp byte [dos_cursor_y], 25
    jb .done
    push ax
    push bx
    push cx
    push dx
    push ds
    push es
    mov ax, 0x0601
    mov bh, [dos_attr]
    xor cx, cx
    mov dx, 0x184F
    int 0x10
    pop es
    pop ds
    mov byte [dos_cursor_y], 24
    pop dx
    pop cx
    pop bx
    pop ax
.done:
    ret

dos_putchar:
    ; AL=character. Direct text-memory output makes COLOR deterministic.
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push es
    cmp al, 13
    je .cr
    cmp al, 10
    je .lf
    cmp al, 8
    je .back
    mov cl, al
    xor ax, ax
    mov al, [dos_cursor_y]
    mov bx, 160
    mul bx
    mov di, ax
    xor ax, ax
    mov al, [dos_cursor_x]
    shl ax, 1
    add di, ax
    mov ax, TEXT_SEG
    mov es, ax
    mov al, cl
    mov ah, [dos_attr]
    mov es:[di], ax
    inc byte [dos_cursor_x]
    cmp byte [dos_cursor_x], 80
    jb .position
    mov byte [dos_cursor_x], 0
    inc byte [dos_cursor_y]
    call dos_scroll_if_needed
    jmp .position
.cr:
    mov byte [dos_cursor_x], 0
    jmp .position
.lf:
    inc byte [dos_cursor_y]
    call dos_scroll_if_needed
    jmp .position
.back:
    cmp byte [dos_cursor_x], 0
    je .position
    dec byte [dos_cursor_x]
.position:
    call dos_set_cursor
    pop es
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

dos_print:
    push ax
    push si
.next:
    lodsb
    test al, al
    jz .done
    ; INT 10h is not required to preserve SI.  dos_putchar updates the BIOS
    ; cursor, so protect the advanced string pointer around every character.
    push si
    call dos_putchar
    pop si
    jmp .next
.done:
    pop si
    pop ax
    ret


dos_print_linear:
    ; EAX = physical linear address of an immutable zero-terminated string.
    ;
    ; The stage-2 image can extend past physical 10000h.  A normal
    ;     mov si, label / DS=0
    ; silently truncates such a label to 16 bits, which made HELP read a short
    ; unrelated string and made VER start on a zero byte.  Convert the full
    ; 32-bit label to FS:SI, while keeping DS=0 for all DOS state variables.
    push eax
    push si
    push fs
    mov esi, eax
    and si, 0x000F
    shr eax, 4
    mov fs, ax
.next:
    mov al, fs:[si]
    test al, al
    jz .done
    inc si
    push si
    call dos_putchar
    pop si
    jmp .next
.done:
    pop fs
    pop si
    pop eax
    ret

dos_crlf:
    push ax
    mov al, 13
    call dos_putchar
    mov al, 10
    call dos_putchar
    pop ax
    ret

dos_clear_screen:
    push ax
    push bx
    push cx
    push dx
    push ds
    push es
    mov ax, 0x0600
    mov bh, [dos_attr]
    xor cx, cx
    mov dx, 0x184F
    int 0x10
    pop es
    pop ds
    mov byte [dos_cursor_x], 0
    mov byte [dos_cursor_y], 0
    call dos_set_cursor
    pop dx
    pop cx
    pop bx
    pop ax
    ret

dos_redraw_line:
    ; Redraw the editable command without disturbing the prompt.
    push ax
    push bx
    push cx
    push si
    mov al, [dos_input_x]
    mov [dos_cursor_x], al
    mov al, [dos_input_y]
    mov [dos_cursor_y], al
    mov cx, 63
.clear:
    mov al, ' '
    call dos_putchar
    loop .clear
    mov al, [dos_input_x]
    mov [dos_cursor_x], al
    mov al, [dos_input_y]
    mov [dos_cursor_y], al
    mov si, dos_line
    call dos_print
    mov al, [dos_input_x]
    add al, [dos_cursor_pos]
    mov [dos_cursor_x], al
    mov al, [dos_input_y]
    mov [dos_cursor_y], al
    call dos_set_cursor
    pop si
    pop cx
    pop bx
    pop ax
    ret

dos_history_store:
    cmp byte [dos_line_len], 0
    je .done
    push ax
    push bx
    push cx
    push si
    push di
    ; When full, shift entries 1..7 down to 0..6.
    cmp byte [dos_history_count], 7
    jb .space
    mov si, dos_history+64
    mov di, dos_history
    mov cx, 6*64
    cld
    rep movsb
    mov byte [dos_history_count], 6
.space:
    xor ax, ax
    mov al, [dos_history_count]
    mov bx, 64
    mul bx
    mov di, dos_history
    add di, ax
    mov si, dos_line
    mov cx, 64
    cld
    rep movsb
    inc byte [dos_history_count]
    mov al, [dos_history_count]
    mov [dos_history_pos], al
    pop di
    pop si
    pop cx
    pop bx
    pop ax
.done:
    ret

dos_history_load:
    ; AL=history index.
    push ax
    push bx
    push cx
    push si
    push di
    xor ah, ah
    mov bx, 64
    mul bx
    mov si, dos_history
    add si, ax
    mov di, dos_line
    mov cx, 64
    cld
    rep movsb
    mov si, dos_line
    xor cx, cx
.len:
    cmp byte [si], 0
    je .len_done
    inc si
    inc cx
    cmp cx, 63
    jb .len
.len_done:
    mov [dos_line_len], cl
    mov [dos_cursor_pos], cl
    call dos_redraw_line
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

dos_readline:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov byte [dos_line_len], 0
    mov byte [dos_cursor_pos], 0
    mov byte [dos_line], 0
    mov al, [dos_cursor_x]
    mov [dos_input_x], al
    mov al, [dos_cursor_y]
    mov [dos_input_y], al
    mov al, [dos_history_count]
    mov [dos_history_pos], al
.read:
    xor ah, ah
    int 0x16
    cmp al, 13
    je .enter
    cmp al, 8
    je .backspace
    cmp al, 0
    je .extended
    cmp al, 0xE0
    jne .printable
.extended:
    cmp ah, 0x4B
    je .left
    cmp ah, 0x4D
    je .right
    cmp ah, 0x48
    je .history_up
    cmp ah, 0x50
    je .history_down
    cmp ah, 0x47
    je .home
    cmp ah, 0x4F
    je .end
    cmp ah, 0x53
    je .delete
    jmp .read
.printable:
    cmp al, 32
    jb .read
    cmp al, 126
    ja .read
    cmp byte [dos_line_len], 63
    jae .read
    mov dl, al
    xor bx, bx
    mov bl, [dos_cursor_pos]
    xor cx, cx
    mov cl, [dos_line_len]
    mov si, dos_line
    add si, cx
    mov di, si
    inc di
.shift_right:
    cmp cx, bx
    jb .insert
    mov al, [si]
    mov [di], al
    dec si
    dec di
    dec cx
    jns .shift_right
.insert:
    mov [dos_line+bx], dl
    inc byte [dos_line_len]
    inc byte [dos_cursor_pos]
    call dos_redraw_line
    jmp .read
.backspace:
    cmp byte [dos_cursor_pos], 0
    je .read
    dec byte [dos_cursor_pos]
    jmp .delete_at_cursor
.delete:
    mov al, [dos_cursor_pos]
    cmp al, [dos_line_len]
    jae .read
.delete_at_cursor:
    xor bx, bx
    mov bl, [dos_cursor_pos]
    xor cx, cx
    mov cl, [dos_line_len]
    sub cx, bx
    mov si, dos_line
    add si, bx
    mov di, si
    inc si
.shift_left:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    loop .shift_left
    dec byte [dos_line_len]
    call dos_redraw_line
    jmp .read
.left:
    cmp byte [dos_cursor_pos], 0
    je .read
    dec byte [dos_cursor_pos]
    call dos_redraw_line
    jmp .read
.right:
    mov al, [dos_cursor_pos]
    cmp al, [dos_line_len]
    jae .read
    inc byte [dos_cursor_pos]
    call dos_redraw_line
    jmp .read
.home:
    mov byte [dos_cursor_pos], 0
    call dos_redraw_line
    jmp .read
.end:
    mov al, [dos_line_len]
    mov [dos_cursor_pos], al
    call dos_redraw_line
    jmp .read
.history_up:
    cmp byte [dos_history_count], 0
    je .read
    cmp byte [dos_history_pos], 0
    je .load_history
    dec byte [dos_history_pos]
.load_history:
    mov al, [dos_history_pos]
    call dos_history_load
    jmp .read
.history_down:
    mov al, [dos_history_pos]
    cmp al, [dos_history_count]
    jae .read
    inc byte [dos_history_pos]
    mov al, [dos_history_pos]
    cmp al, [dos_history_count]
    jb .load_down
    mov byte [dos_line_len], 0
    mov byte [dos_cursor_pos], 0
    mov byte [dos_line], 0
    call dos_redraw_line
    jmp .read
.load_down:
    call dos_history_load
    jmp .read
.enter:
    xor bx, bx
    mov bl, [dos_line_len]
    mov byte [dos_line+bx], 0
    call dos_history_store
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

dos_skip_spaces:
    cmp byte [si], ' '
    jne .done
    inc si
    jmp dos_skip_spaces
.done:
    ret

dos_hex_value:
    ; AL=hex digit -> AL=value, CF=1 valid.
    cmp al, '0'
    jb .bad
    cmp al, '9'
    jbe .digit
    cmp al, 'A'
    jb .lower
    cmp al, 'F'
    jbe .upper
.lower:
    cmp al, 'a'
    jb .bad
    cmp al, 'f'
    ja .bad
    sub al, 'a'-10
    stc
    ret
.upper:
    sub al, 'A'-10
    stc
    ret
.digit:
    sub al, '0'
    stc
    ret
.bad:
    clc
    ret

dos_color_command:
    mov si, dos_line
    call dos_skip_spaces
    add si, 5
    call dos_skip_spaces
    cmp byte [si], 0
    je .defaults
    cmp byte [si], '/'
    jne .parse
    cmp byte [si+1], '?'
    jne .parse
    cmp byte [si+2], 0
    jne .parse
    mov byte [dos_errorlevel], 0
    mov eax, dos_color_help
    call dos_print_linear
    ret
.defaults:
    mov byte [dos_attr], 0x07
    mov byte [dos_errorlevel], 0
    call dos_recolor_screen
    ret
.parse:
    mov al, [si]
    call dos_hex_value
    jnc .invalid
    shl al, 4
    mov bl, al
    inc si
    mov al, [si]
    call dos_hex_value
    jnc .invalid
    or bl, al
    inc si
    call dos_skip_spaces
    cmp byte [si], 0
    jne .invalid
    mov al, bl
    mov ah, al
    and al, 0x0F
    shr ah, 4
    cmp al, ah
    je .same
    mov [dos_attr], bl
    mov byte [dos_errorlevel], 0
    call dos_recolor_screen
    ret
.same:
    mov byte [dos_errorlevel], 1
    mov eax, dos_color_same
    call dos_print_linear
    ret
.invalid:
    mov byte [dos_errorlevel], 1
    mov eax, dos_color_usage
    call dos_print_linear
    ret

dos_recolor_screen:
    ; Preserve all characters and cursor position while applying the new attribute.
    push ax
    push cx
    push di
    push es
    mov ax, TEXT_SEG
    mov es, ax
    xor di, di
    mov cx, 2000
.loop:
    mov al, es:[di]
    mov ah, [dos_attr]
    mov es:[di], ax
    add di, 2
    loop .loop
    call dos_set_cursor
    pop es
    pop di
    pop cx
    pop ax
    ret

dos_hash_word:
    ; DS:SI -> word. Skip leading spaces and return AX=case-insensitive
    ; 16-bit djb2-style hash, CL=length, SI=first delimiter.
    push bx
    push dx
    call dos_skip_spaces
    xor ax, ax
    xor cx, cx
.hash_loop:
    mov dl, [si]
    test dl, dl
    jz .hash_done
    cmp dl, ' '
    je .hash_done
    cmp dl, 'A'
    jb .lower_ready
    cmp dl, 'Z'
    ja .lower_ready
    add dl, 'a'-'A'
.lower_ready:
    mov bx, ax
    shl ax, 5
    add ax, bx
    xor dh, dh
    add ax, dx
    inc si
    inc cl
    jmp .hash_loop
.hash_done:
    pop dx
    pop bx
    ret

dos_execute:
    mov si, dos_line
    call dos_hash_word
    test cl, cl
    jz .done

    cmp cl, 4
    jne .len3
    cmp ax, 0xC369                 ; help
    je .help
    cmp ax, 0x81DE                 ; date
    je .date
    cmp ax, 0x690F                 ; time
    je .time
    cmp ax, 0x153F                 ; echo
    je .echo
    cmp ax, 0x6EBA                 ; exit
    je power_off
    jmp .bad
.len3:
    cmp cl, 3
    jne .len5
    cmp ax, 0xB382                 ; cls
    je .cls
    cmp ax, 0x036D                 ; ver
    je .ver
    cmp ax, 0x082E                 ; win
    je dos_win_command
    cmp ax, 0xC7E5                 ; hex
    je dos_hex_command
	cmp ax, 0xC8C8                 ; hlt
    je hlt_cmd
    jmp .bad
.len5:
    cmp cl, 5
    jne .len6
    cmp ax, 0x321F                 ; color
    je .color
    cmp ax, 0xA8F1                 ; crash
    je dos_crash_command
    jmp .bad
.len6:
    cmp cl, 6
    jne .len7
    cmp ax, 0x66AB                 ; reboot
    je reboot_cmd
    jmp .bad
.len7:
    cmp cl, 7
    jne .bad
    cmp ax, 0x9AA4                 ; restore
    je dos_restore_command
    jmp .bad
.bad:
    mov byte [dos_errorlevel], 1
    mov eax, dos_bad_command
    call dos_print_linear
    jmp .done
.help:
    mov byte [dos_errorlevel], 0
    mov eax, dos_help_text
    call dos_print_linear
    jmp .done
.cls:
    mov byte [dos_errorlevel], 0
    call dos_clear_screen
    jmp .done
.ver:
    mov byte [dos_errorlevel], 0
    mov eax, dos_ver_text
    call dos_print_linear
    jmp .done
.color:
    call dos_color_command
    jmp .done
.date:
    mov byte [dos_errorlevel], 0
    call dos_show_date
    jmp .done
.time:
    mov byte [dos_errorlevel], 0
    call dos_show_time
    jmp .done
.echo:
    mov byte [dos_errorlevel], 0
    mov si, dos_line
    call dos_skip_spaces
    add si, 4
    call dos_skip_spaces
    call dos_print
    call dos_crlf
.done:
    ret

dos_hex_command:
    mov si, dos_line
    call dos_skip_spaces
    add si, 3
    call dos_skip_spaces
    cmp byte [si], 0
    je .disk
    cmp byte [si], '-'
    jne .invalid
    inc si
    call dos_hash_word
    push ax
    push cx
    call dos_skip_spaces
    cmp byte [si], 0
    jne .invalid_pop
    pop cx
    pop ax
    cmp cl, 3
    jne .invalid
    cmp ax, 0xDD1F                 ; mem
    jne .invalid
    mov byte [hex_launch_mode], 1
    mov byte [dos_errorlevel], 0
    cli
    call gui_snapshot_save
    call system_uninstall_exception_hooks
    jmp 0x0000:hex_launch_loader
.disk:
    mov byte [hex_launch_mode], 0
    mov byte [dos_errorlevel], 0
    cli
    call gui_snapshot_save
    call system_uninstall_exception_hooks
    jmp 0x0000:hex_launch_loader
.invalid_pop:
    pop cx
    pop ax
.invalid:
    mov byte [dos_errorlevel], 1
    mov eax, dos_hex_usage
    call dos_print_linear
    ret

dos_win_command:
    mov si, dos_line
    call dos_skip_spaces
    add si, 3
    call dos_skip_spaces
    cmp byte [si], 0
    je return_to_gui_reset
    cmp byte [si], '-'
    jne .hash_arg
    inc si
.hash_arg:
    call dos_hash_word
    push ax
    push cx
    call dos_skip_spaces
    cmp byte [si], 0
    jne .invalid_pop
    pop cx
    pop ax
    cmp cl, 4
    jne .check_preserve
    cmp ax, 0x67A5                 ; keep
    je return_to_gui_preserve
.check_preserve:
    cmp cl, 8
    jne .invalid
    cmp ax, 0x90AC                 ; preserve
    je return_to_gui_preserve
.invalid:
    mov byte [dos_errorlevel], 1
    mov eax, dos_win_usage
    call dos_print_linear
    ret
.invalid_pop:
    pop cx
    pop ax
    jmp .invalid

dos_put_bcd:
    push ax
    mov ah, al
    shr al, 4
    and al, 0x0F
    add al, '0'
    call dos_putchar
    mov al, ah
    and al, 0x0F
    add al, '0'
    call dos_putchar
    pop ax
    ret

dos_show_date:
    push ax
    push cx
    push dx
    mov ah, 0x04
    int 0x1A
    jc .unknown
    mov eax, dos_date_prefix
    call dos_print_linear
    mov al, ch
    call dos_put_bcd
    mov al, cl
    call dos_put_bcd
    mov al, '-'
    call dos_putchar
    mov al, dh
    call dos_put_bcd
    mov al, '-'
    call dos_putchar
    mov al, dl
    call dos_put_bcd
    call dos_crlf
    jmp .done
.unknown:
    mov eax, dos_rtc_unknown
    call dos_print_linear
.done:
    pop dx
    pop cx
    pop ax
    ret

dos_show_time:
    push ax
    push cx
    push dx
    mov ah, 0x02
    int 0x1A
    jc .unknown
    mov eax, dos_time_prefix
    call dos_print_linear
    mov al, ch
    call dos_put_bcd
    mov al, ':'
    call dos_putchar
    mov al, cl
    call dos_put_bcd
    mov al, ':'
    call dos_putchar
    mov al, dh
    call dos_put_bcd
    call dos_crlf
    jmp .done
.unknown:
    mov eax, dos_rtc_unknown
    call dos_print_linear
.done:
    pop dx
    pop cx
    pop ax
    ret

return_to_gui:
    ; Compatibility alias: preserve the old session.
    jmp return_to_gui_preserve

return_to_gui_reset:
    cli
    mov ax, STACK_SEG
    mov ss, ax
    mov sp, STACK_TOP
    call init_font_and_video
    call init_state
    sti
    call init_mouse_support
    mov word [draw_seg], VGA_SEG
    mov byte [cursor_visible], 0
    call redraw_all
    call mouse_cursor_show
    jmp main_loop

return_to_gui_preserve:
    cli
    mov ax, STACK_SEG
    mov ss, ax
    mov sp, STACK_TOP
    xor ax, ax
    mov ds, ax
    mov es, ax
    cmp dword [gui_session_cookie], GUI_SESSION_MAGIC
    jne return_to_gui_reset
    call init_font_and_video
    sti
    mov byte [system_watchdog_enabled], 1
    mov byte [system_watchdog_ticks], 0
    mov byte [system_watchdog_reason], BSOD_STOP_WATCHDOG
    call init_mouse_support
    mov word [draw_seg], VGA_SEG
    mov byte [cursor_visible], 0
    mov byte [mouse_prev_buttons], 0
    mov byte [mouse_buttons], 0
    mov byte [message_open], 0
    mov byte [menu_open], MENU_NONE
    mov byte [drag_mode], 0
    mov byte [interaction_pid], 0
    mov byte [paint_pending_action], PAINT_PENDING_NONE
    call redraw_all
    call mouse_cursor_show
    jmp main_loop

hard_reboot:
    cli
    jmp system_bsod_hard_reset

reboot_cmd:
    mov si, dos_line
    call dos_skip_spaces
    add si, 6
    call dos_skip_spaces
    cmp byte [si], 0
    je .soft
    cmp byte [si], '-'
    jne .invalid
    inc si
    call dos_hash_word
    push ax
    push cx
    call dos_skip_spaces
    cmp byte [si], 0
    jne .invalid_pop
    pop cx
    pop ax
    cmp cl, 4
    jne .invalid
    cmp ax, 0xB31F                 ; hard
    je .hard
.invalid:
    mov byte [dos_errorlevel], 1
    mov eax, dos_reboot_usage
    call dos_print_linear
    ret
.invalid_pop:
    pop cx
    pop ax
    jmp .invalid
.soft:
    ; INT 19h is the requested soft bootstrap.  Restore the BIOS exception/IRQ
    ; vectors first; INT 19h preserves the IVT and may otherwise re-enter our
    ; resident Stage-2 handlers after the new boot sector takes control.
    cli
    call system_uninstall_exception_hooks
    xor ax, ax
    mov ds, ax
    mov es, ax
    int 0x19
    ; A successful bootstrap never returns.
    mov al, BSOD_STOP_REBOOT
    jmp system_blue_screen
.hard:
    jmp hard_reboot

dos_crash_command:
    mov byte [dos_crash_mode], 0
    mov byte [dos_crash_code], BSOD_STOP_MANUAL
    mov byte [dos_crash_seen_code], 0
    mov si, dos_line
    call dos_skip_spaces
    add si, 5

.next_argument:
    call dos_skip_spaces
    cmp byte [si], 0
    je .arguments_ready
    cmp byte [si], '-'
    je .mode_argument

    ; A stop code is one or two hexadecimal digits with a mandatory 0x
    ; prefix.  Both argument orders are accepted: "0x0F -PM" and "-PM 0x0F".
    cmp byte [dos_crash_seen_code], 0
    jne .invalid
    cmp byte [si], '0'
    jne .invalid
    mov al, [si+1]
    cmp al, 'x'
    je .hex_prefix
    cmp al, 'X'
    jne .invalid
.hex_prefix:
    add si, 2
    mov al, [si]
    call dos_hex_value
    jnc .invalid
    mov bl, al
    inc si
    cmp byte [si], 0
    je .single_digit
    cmp byte [si], ' '
    je .single_digit
    mov al, [si]
    call dos_hex_value
    jnc .invalid
    shl bl, 4
    or bl, al
    inc si
    cmp byte [si], 0
    je .store_code
    cmp byte [si], ' '
    jne .invalid
    jmp short .store_code
.single_digit:
    ; "0xF" is accepted and normalized to stop code 0Fh.
.store_code:
    mov [dos_crash_code], bl
    mov byte [dos_crash_seen_code], 1
    jmp .next_argument

.mode_argument:
    cmp byte [dos_crash_mode], 0
    jne .invalid
    inc si
    call dos_hash_word
    cmp cl, 2
    jne .invalid
    cmp ax, 0x0EDD                 ; pm
    je .protected_mode
    cmp ax, 0x0E59                 ; lm
    jne .invalid
    mov byte [dos_crash_mode], 2
    jmp .next_argument
.protected_mode:
    mov byte [dos_crash_mode], 1
    jmp .next_argument

.arguments_ready:
    cmp byte [BLUESCREEN_ENABLE_ADDR], 0
    je .disabled
    mov byte [dos_errorlevel], 0
    mov al, [dos_crash_mode]
    cmp al, 1
    je .crash_pm
    cmp al, 2
    je .crash_lm
    mov al, [dos_crash_code]
    jmp system_blue_screen

.crash_pm:
    mov al, [dos_crash_code]
    mov [debug_crash_code], al
    mov byte [debug_mode_action], 1
    call debug_enter_protected_mode
    ret

.crash_lm:
    call debug_cpu_supports_long_mode
    jc .long_mode_unsupported
    mov al, [dos_crash_code]
    mov [debug_crash_code], al
    mov byte [debug_mode_action], 1
    call debug_enter_long_mode
    ret

.long_mode_unsupported:
    mov byte [dos_errorlevel], 1
    mov eax, dos_crash_lm_unsupported
    call dos_print_linear
    ret

.invalid:
    mov byte [dos_errorlevel], 1
    mov eax, dos_crash_usage
    call dos_print_linear
    ret

.disabled:
    mov byte [dos_errorlevel], 1
    mov eax, dos_bluescreen_disabled_text
    call dos_print_linear
    ret

dos_bluescreen_disabled_text db 'Bluescreen is currently disabled.',13,10,0

hlt_cmd:
    cli
	mov ah, 0x01
    mov cx, 0x2000
    int 0x10
	call dos_clear_screen
    mov eax, hlt_msg
    call dos_print_linear
.hlt_loop:
    hlt
    jmp .hlt_loop
hlt_msg db 'System halted.',13,10,0

power_off:
    call mouse_cursor_hide
    sti

    mov ax, 0x5300
    xor bx, bx
    int 0x15
    jc .ports
    cmp bx, 0x504D
    jne .ports

    mov ax, 0x5301
    xor bx, bx
    int 0x15

    mov ax, 0x530E
    xor bx, bx
    mov cx, 0x0102
    int 0x15

    mov ax, 0x5307
    mov bx, 0x0001
    mov cx, 0x0003
    int 0x15

.ports:
    cli
    ; QEMU / ACPI test port.
    mov dx, 0x0604
    mov ax, 0x2000
    out dx, ax
    ; Bochs / older emulators.
    mov dx, 0xB004
    out dx, ax
    ; VirtualBox fallback.
    mov dx, 0x4004
    mov ax, 0x3400
    out dx, ax

    sti
    mov ax, 0x0013
    int 0x10
    mov word [draw_seg], VGA_SEG
    mov ax, 0
    mov bx, 0
    mov cx, SCREEN_W
    mov dx, SCREEN_H
    mov si, COL_BLACK
    call fill_rect
    mov si, str_poweroff
    mov cx, 96
    mov dx, 96
    mov bl, COL_WHITE
    call draw_text
    cli
.hang:
    hlt
    jmp .hang

dos_restore_command:
    ; Step 1: Read LBA 2047 into a buffer
    ; Step 2: Write buffer to LBA 0
    ; Step 3: Zero LBA 1..2047
    ; Step 4: Hard reboot on success, print error on failure

    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es
    push ds

    xor ax, ax
    mov ds, ax
    mov es, ax

    ; ── Step 1: read LBA 2047 ──────────────────────────────────────────────
    ; Build DAP in dos_restore_dap
    mov byte [dos_restore_dap],      0x10   ; size
    mov byte [dos_restore_dap + 1],  0x00   ; reserved
    mov word [dos_restore_dap + 2],  1      ; 1 sector
    mov word [dos_restore_dap + 4],  dos_restore_buf   ; offset
    mov word [dos_restore_dap + 6],  0x0000             ; segment 0
    mov dword [dos_restore_dap + 8], 2047   ; LBA lo  (2047 = 0x7FF)
    mov dword [dos_restore_dap + 12], 0     ; LBA hi

    ; Try EDD read first
    mov ah, 0x41
    mov bx, 0x55AA
    mov dl, [os_boot_drive]
    int 0x13
    jc .try_chs_read
    cmp bx, 0xAA55
    jne .try_chs_read
    test cx, 1
    jz .try_chs_read

    ; EDD available – use INT 13h/42h
    mov si, dos_restore_dap
    mov dl, [os_boot_drive]
    mov ah, 0x42
    int 0x13
    jnc .read_ok

.try_chs_read:
    ; CHS fallback for LBA 2047
    xor ah, ah
    mov dl, [os_boot_drive]
    int 0x13                    ; reset drive

    mov ah, 0x08
    mov dl, [os_boot_drive]
    int 0x13
    jc .err_read
    mov bl, cl
    and cl, 0x3F
    jz .err_read
    mov [dos_restore_spt], cl
    mov al, dh
    inc al
    jz .err_read
    mov [dos_restore_heads], al

    ; Convert LBA 2047 to CHS
    mov ax, 2047
    xor dx, dx
    xor bx, bx
    mov bl, [dos_restore_spt]
    div bx
    mov cl, dl
    inc cl                      ; sector (1-based)
    xor dx, dx
    xor bx, bx
    mov bl, [dos_restore_heads]
    div bx
    ; ax = cylinder, dx = head
    cmp ax, 1023
    ja .err_read
    mov ch, al                  ; cylinder low 8 bits
    mov al, ah
    and al, 3
    shl al, 6
    or cl, al                   ; cylinder high 2 bits into cl[7:6]
    mov dh, dl                  ; head

    mov bx, dos_restore_buf
    mov ax, 0x0201              ; read 1 sector
    mov dl, [os_boot_drive]
    int 0x13
    jc .err_read

.read_ok:
    ; ── Step 2: write buffer to LBA 0 ─────────────────────────────────────
    mov byte [dos_restore_dap],      0x10
    mov byte [dos_restore_dap + 1],  0x00
    mov word [dos_restore_dap + 2],  1
    mov word [dos_restore_dap + 4],  dos_restore_buf
    mov word [dos_restore_dap + 6],  0x0000
    mov dword [dos_restore_dap + 8], 0      ; LBA 0
    mov dword [dos_restore_dap + 12], 0

    mov ah, 0x41
    mov bx, 0x55AA
    mov dl, [os_boot_drive]
    int 0x13
    jc .try_chs_write0
    cmp bx, 0xAA55
    jne .try_chs_write0
    test cx, 1
    jz .try_chs_write0

    mov si, dos_restore_dap
    mov dl, [os_boot_drive]
    mov ah, 0x43
    xor al, al
    int 0x13
    jnc .write0_ok

.try_chs_write0:
    ; CHS write to LBA 0  → cylinder 0, head 0, sector 1
    mov bx, dos_restore_buf
    mov cx, 0x0001              ; cylinder 0, sector 1
    xor dh, dh
    mov ax, 0x0301              ; write 1 sector
    mov dl, [os_boot_drive]
    int 0x13
    jc .err_write

.write0_ok:
    ; ── Step 3: zero LBA 1 … 2047 ─────────────────────────────────────────
    ; Clear the scratch buffer
    push es
    push di
    xor ax, ax
    mov es, ax
    mov di, dos_restore_buf
    mov cx, 256                 ; 512 bytes / 2
    rep stosw
    pop di
    pop es

    mov dword [dos_restore_cur_lba], 1   ; start at LBA 1

.zero_loop:
    cmp dword [dos_restore_cur_lba], 2048
    jae .zero_done              ; written 1..2047 inclusive

    ; Build DAP for current LBA
    mov byte [dos_restore_dap],      0x10
    mov byte [dos_restore_dap + 1],  0x00
    mov word [dos_restore_dap + 2],  1
    mov word [dos_restore_dap + 4],  dos_restore_buf
    mov word [dos_restore_dap + 6],  0x0000
    mov eax, [dos_restore_cur_lba]
    mov [dos_restore_dap + 8],  eax
    mov dword [dos_restore_dap + 12], 0

    mov ah, 0x41
    mov bx, 0x55AA
    mov dl, [os_boot_drive]
    int 0x13
    jc .zero_try_chs
    cmp bx, 0xAA55
    jne .zero_try_chs
    test cx, 1
    jz .zero_try_chs

    mov si, dos_restore_dap
    mov dl, [os_boot_drive]
    mov ah, 0x43
    xor al, al
    int 0x13
    jnc .zero_next

.zero_try_chs:
    ; CHS fallback for current LBA
    mov ax, [dos_restore_cur_lba]   ; LBA fits in 16 bits for ≤2047
    xor dx, dx
    xor bx, bx
    mov bl, [dos_restore_spt]
    test bl, bl
    jz .err_zero                ; no CHS geometry – cannot proceed
    div bx
    mov cl, dl
    inc cl
    xor dx, dx
    xor bx, bx
    mov bl, [dos_restore_heads]
    test bl, bl
    jz .err_zero
    div bx
    cmp ax, 1023
    ja .err_zero
    mov ch, al
    mov al, ah
    and al, 3
    shl al, 6
    or cl, al
    mov dh, dl

    mov bx, dos_restore_buf
    mov ax, 0x0301
    mov dl, [os_boot_drive]
    int 0x13
    jc .err_zero

.zero_next:
    inc dword [dos_restore_cur_lba]
    jmp .zero_loop

.zero_done:
    ; ── Step 4: hard reboot ───────────────────────────────────────────────
    pop ds
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    cli
    jmp system_bsod_hard_reset

    ; ── Error handlers ────────────────────────────────────────────────────
.err_read:
    pop ds
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    mov byte [dos_errorlevel], 1
    mov eax, dos_restore_err_read
    call dos_print_linear
    ret

.err_write:
    pop ds
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    mov byte [dos_errorlevel], 1
    mov eax, dos_restore_err_write
    call dos_print_linear
    ret

.err_zero:
    pop ds
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    mov byte [dos_errorlevel], 1
    mov eax, dos_restore_err_zero
    call dos_print_linear
    ret

; Command names are recognized by dos_hash_word and require no late token table.


; =============================================================================
; Relocated extended Paint routines
; Data, cursor bitmaps and GUI strings stay below physical 10000h for DS=0.
; Stage 2 executes as 07E0:0000, so these routines may safely reside above
; physical 10000h while remaining in the same 64 KiB CS:IP window.
; =============================================================================

; =============================================================================
; Calculator v6.0: compact signed 96-bit fixed-point core
; =============================================================================

; Copy three dwords from DS:SI to DS:DI.
calc96_copy:
    mov eax, [si]
    mov [di], eax
    mov eax, [si+4]
    mov [di+4], eax
    mov eax, [si+8]
    mov [di+8], eax
    ret

calc96_zero:
    mov dword [di], 0
    mov dword [di+4], 0
    mov dword [di+8], 0
    ret

; Two's-complement the signed/magnitude value at DS:SI.
calc96_neg:
    not dword [si]
    not dword [si+4]
    not dword [si+8]
    add dword [si], 1
    adc dword [si+4], 0
    adc dword [si+8], 0
    ret

; Return ZF=1 when the three-dword value at DS:SI is zero.
calc96_is_zero:
    mov eax, [si]
    or eax, [si+4]
    or eax, [si+8]
    ret

; Unsigned comparison DS:SI versus DS:DI.  Flags match SI-DI.
calc96_cmp:
    mov eax, [si+8]
    cmp eax, [di+8]
    jne .done
    mov eax, [si+4]
    cmp eax, [di+4]
    jne .done
    mov eax, [si]
    cmp eax, [di]
.done:
    ret

; CALC96_A := abs(signed DS:SI), and record the original sign.
calc96_abs_to_a:
    mov di, CALC96_A
    call calc96_copy
    mov byte [CALC96_SIGN], 0
    test dword [CALC96_A+8], 0x80000000
    jz .done
    mov byte [CALC96_SIGN], 1
    mov si, CALC96_A
    call calc96_neg
.done:
    ret

; Magnitude in CALC96_A must be <= 2^64 * CALC_SCALE.
calc96_check_a_limit:
    mov eax, [CALC96_A+8]
    cmp eax, CALC96_LIMIT_HI
    jb .ok
    ja .bad
    mov eax, [CALC96_A]
    or eax, [CALC96_A+4]
    jnz .bad
.ok:
    clc
    ret
.bad:
    stc
    ret

calc96_check_c_range:
    mov si, CALC96_C
    call calc96_abs_to_a
    call calc96_check_a_limit
    ret

; DS:DI += DS:SI, both three dwords.
calc96_add:
    mov eax, [si]
    add [di], eax
    mov eax, [si+4]
    adc [di+4], eax
    mov eax, [si+8]
    adc [di+8], eax
    ret

; DS:DI -= DS:SI, both three dwords.
calc96_sub:
    mov eax, [si]
    sub [di], eax
    mov eax, [si+4]
    sbb [di+4], eax
    mov eax, [si+8]
    sbb [di+8], eax
    ret

; DS:DI := unsigned DS:SI * EBX.  Products used here fit in 96 bits.
calc96_mul_dword:
    mov eax, [si]
    mul ebx
    mov [di], eax
    mov ecx, edx
    mov eax, [si+4]
    mul ebx
    add eax, ecx
    adc edx, 0
    mov [di+4], eax
    mov ecx, edx
    mov eax, [si+8]
    mul ebx
    add eax, ecx
    mov [di+8], eax
    ret

; In-place unsigned 96/32 division.  Remainder is returned in EDX.
calc96_div_dword:
    xor edx, edx
    mov eax, [si+8]
    div ebx
    mov [si+8], eax
    mov eax, [si+4]
    div ebx
    mov [si+4], eax
    mov eax, [si]
    div ebx
    mov [si], eax
    ret

calc96_shr:
    shr dword [si+8], 1
    rcr dword [si+4], 1
    rcr dword [si], 1
    ret

calc96_shl:
    shl dword [si], 1
    rcl dword [si+4], 1
    rcl dword [si+8], 1
    ret

calc96_zero6:
    mov dword [di], 0
    mov dword [di+4], 0
    mov dword [di+8], 0
    mov dword [di+12], 0
    mov dword [di+16], 0
    mov dword [di+20], 0
    ret

calc96_shl6:
    shl dword [si], 1
    rcl dword [si+4], 1
    rcl dword [si+8], 1
    rcl dword [si+12], 1
    rcl dword [si+16], 1
    rcl dword [si+20], 1
    ret

; DS:DI += DS:SI, both six dwords.
calc96_add6:
    mov eax, [si]
    add [di], eax
    mov eax, [si+4]
    adc [di+4], eax
    mov eax, [si+8]
    adc [di+8], eax
    mov eax, [si+12]
    adc [di+12], eax
    mov eax, [si+16]
    adc [di+16], eax
    mov eax, [si+20]
    adc [di+20], eax
    ret

; In-place unsigned 192/32 division.  Remainder is returned in EDX.
calc96_div6_dword:
    xor edx, edx
    mov eax, [si+20]
    div ebx
    mov [si+20], eax
    mov eax, [si+16]
    div ebx
    mov [si+16], eax
    mov eax, [si+12]
    div ebx
    mov [si+12], eax
    mov eax, [si+8]
    div ebx
    mov [si+8], eax
    mov eax, [si+4]
    div ebx
    mov [si+4], eax
    mov eax, [si]
    div ebx
    mov [si], eax
    ret

calc96_inc6:
    add dword [si], 1
    adc dword [si+4], 0
    adc dword [si+8], 0
    adc dword [si+12], 0
    adc dword [si+16], 0
    adc dword [si+20], 0
    ret

; CALC96_WIDE := CALC96_A * EBX, zero-extended to six dwords.
calc96_a_mul_dword_wide:
    mov eax, [CALC96_A]
    mul ebx
    mov [CALC96_WIDE], eax
    mov ecx, edx
    mov eax, [CALC96_A+4]
    mul ebx
    add eax, ecx
    adc edx, 0
    mov [CALC96_WIDE+4], eax
    mov ecx, edx
    mov eax, [CALC96_A+8]
    mul ebx
    add eax, ecx
    adc edx, 0
    mov [CALC96_WIDE+8], eax
    mov [CALC96_WIDE+12], edx
    mov dword [CALC96_WIDE+16], 0
    mov dword [CALC96_WIDE+20], 0
    ret

; Unsigned CALC96_A * CALC96_B / CALC_SCALE, rounded to nearest.
; Returns CALC96_C and CF=0, or CF=1 if the quotient does not fit 96 bits.
calc96_mul_abs:
    mov di, CALC96_WIDE
    call calc96_zero6
    mov di, CALC96_PROD
    call calc96_zero6
    mov si, CALC96_A
    mov di, CALC96_WIDE
    call calc96_copy
    mov cx, 96
.loop:
    test dword [CALC96_B], 1
    jz .no_add
    mov si, CALC96_WIDE
    mov di, CALC96_PROD
    call calc96_add6
.no_add:
    mov si, CALC96_B
    call calc96_shr
    mov si, CALC96_WIDE
    call calc96_shl6
    loop .loop
    mov si, CALC96_PROD
    mov ebx, CALC_SCALE
    call calc96_div6_dword
    add edx, edx
    cmp edx, CALC_SCALE
    jb .fit_check
    mov si, CALC96_PROD
    call calc96_inc6
.fit_check:
    mov eax, [CALC96_PROD+12]
    or eax, [CALC96_PROD+16]
    or eax, [CALC96_PROD+20]
    jnz .overflow
    mov si, CALC96_PROD
    mov di, CALC96_C
    call calc96_copy
    clc
    ret
.overflow:
    stc
    ret

; Unsigned (CALC96_A * CALC_SCALE) / CALC96_B, rounded to nearest.
; A 192-bit restoring divider avoids every hardware divide-overflow case.
calc96_div_abs:
    mov ebx, CALC_SCALE
    call calc96_a_mul_dword_wide
    mov di, CALC96_PROD
    call calc96_zero6
    mov di, CALC96_REM
    call calc96_zero
    mov cx, 192
.loop:
    mov eax, [CALC96_WIDE+20]
    shr eax, 31
    mov [CALC96_DIGIT], al
    mov si, CALC96_WIDE
    call calc96_shl6
    mov si, CALC96_REM
    call calc96_shl
    cmp byte [CALC96_DIGIT], 0
    je .bit_ready
    or dword [CALC96_REM], 1
.bit_ready:
    mov si, CALC96_PROD
    call calc96_shl6
    mov si, CALC96_REM
    mov di, CALC96_B
    call calc96_cmp
    jb .next
    mov si, CALC96_B
    mov di, CALC96_REM
    call calc96_sub
    or dword [CALC96_PROD], 1
.next:
    loop .loop
    ; Round half up by comparing twice the remainder with the divisor.
    mov si, CALC96_REM
    call calc96_shl
    mov si, CALC96_REM
    mov di, CALC96_B
    call calc96_cmp
    jb .fit_check
    mov si, CALC96_PROD
    call calc96_inc6
.fit_check:
    mov eax, [CALC96_PROD+12]
    or eax, [CALC96_PROD+16]
    or eax, [CALC96_PROD+20]
    jnz .overflow
    mov si, CALC96_PROD
    mov di, CALC96_C
    call calc96_copy
    clc
    ret
.overflow:
    stc
    ret

; Convert both persistent operands to magnitudes and retain their result sign.
calc96_prepare_abs_pair:
    mov si, calc_acc
    mov di, CALC96_A
    call calc96_copy
    mov byte [CALC96_SIGN], 0
    test dword [CALC96_A+8], 0x80000000
    jz .acc_ready
    mov byte [CALC96_SIGN], 1
    mov si, CALC96_A
    call calc96_neg
.acc_ready:
    mov si, calc_current
    mov di, CALC96_B
    call calc96_copy
    mov byte [CALC96_SIGN_B], 0
    test dword [CALC96_B+8], 0x80000000
    jz .current_ready
    mov byte [CALC96_SIGN_B], 1
    mov si, CALC96_B
    call calc96_neg
.current_ready:
    mov al, [CALC96_SIGN_B]
    xor [CALC96_SIGN], al
    ret

calc96_input_digit_impl:
    push eax
    push ebx
    push ecx
    push edx
    push si
    push di
    mov [CALC96_DIGIT], al
    call calc_prepare_new_entry
    mov si, calc_current
    call calc96_abs_to_a
    mov al, [CALC96_SIGN]
    mov [CALC96_SIGN_B], al
    cmp byte [calc_decimal], 0
    jne .fraction
    mov si, CALC96_A
    mov di, CALC96_C
    mov ebx, 10
    call calc96_mul_dword
    xor eax, eax
    mov al, [CALC96_DIGIT]
    imul eax, eax, CALC_SCALE
    add [CALC96_C], eax
    adc dword [CALC96_C+4], 0
    adc dword [CALC96_C+8], 0
    jmp .range
.fraction:
    cmp byte [calc_frac_digits], 7
    jae .done
    mov si, CALC96_A
    mov di, CALC96_C
    call calc96_copy
    mov eax, 1000000
    xor ecx, ecx
    mov cl, [calc_frac_digits]
.factor_loop:
    test cl, cl
    jz .factor_ready
    xor edx, edx
    mov ebx, 10
    div ebx
    dec cl
    jmp .factor_loop
.factor_ready:
    xor edx, edx
    mov dl, [CALC96_DIGIT]
    imul edx, eax
    add [CALC96_C], edx
    adc dword [CALC96_C+4], 0
    adc dword [CALC96_C+8], 0
.range:
    mov si, CALC96_C
    mov di, CALC96_A
    call calc96_copy
    call calc96_check_a_limit
    jc .overflow
    cmp byte [CALC96_SIGN_B], 0
    je .store
    mov si, CALC96_C
    call calc96_neg
.store:
    mov si, CALC96_C
    mov di, calc_current
    call calc96_copy
    cmp byte [calc_decimal], 0
    je .entry
    inc byte [calc_frac_digits]
.entry:
    mov byte [calc_entry], 1
    jmp .done
.overflow:
    mov byte [calc_error], 1
.done:
    pop di
    pop si
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

calc96_backspace_impl:
    push eax
    push ebx
    push ecx
    push edx
    push si
    push di
    cmp byte [calc_result_fresh], 0
    jne .done
    cmp byte [calc_error], 0
    je .normal
    call calc_clear_no_draw
    jmp .done
.normal:
    cmp byte [calc_entry], 0
    je .done
    mov si, calc_current
    call calc96_abs_to_a
    mov al, [CALC96_SIGN]
    mov [CALC96_SIGN_B], al
    cmp byte [calc_frac_digits], 0
    je .integer
    mov eax, 1
    mov cl, 8
    sub cl, [calc_frac_digits]
.factor_loop:
    imul eax, eax, 10
    dec cl
    jnz .factor_loop
    mov ebx, eax
    mov si, CALC96_A
    call calc96_div_dword
    mov si, CALC96_A
    mov di, CALC96_C
    call calc96_mul_dword
    dec byte [calc_frac_digits]
    jmp .restore_sign
.integer:
    mov si, CALC96_A
    mov ebx, (CALC_SCALE*10)
    call calc96_div_dword
    mov si, CALC96_A
    mov di, CALC96_C
    mov ebx, CALC_SCALE
    call calc96_mul_dword
.restore_sign:
    cmp byte [CALC96_SIGN_B], 0
    je .store
    mov si, CALC96_C
    call calc96_neg
.store:
    mov si, CALC96_C
    mov di, calc_current
    call calc96_copy
.done:
    pop di
    pop si
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

calc96_set_operator_impl:
    push ax
    mov byte [calc_result_fresh], 0
    cmp byte [calc_error], 0
    jne .done
    cmp byte [calc_op], 0
    je .store_first
    cmp byte [calc_entry], 0
    je .replace
    call calc96_apply_impl
    cmp byte [calc_error], 0
    jne .done
    jmp .replace
.store_first:
    mov si, calc_current
    mov di, calc_acc
    call calc96_copy
.replace:
    pop ax
    mov [calc_op], al
    mov di, calc_current
    call calc96_zero
    mov byte [calc_entry], 0
    mov byte [calc_decimal], 0
    mov byte [calc_frac_digits], 0
    ret
.done:
    pop ax
    ret

calc96_equal_impl:
    cmp byte [calc_error], 0
    jne .done
    cmp byte [calc_op], 0
    je .done
    call calc96_apply_impl
    cmp byte [calc_error], 0
    jne .done
    mov si, calc_acc
    mov di, calc_current
    call calc96_copy
    mov byte [calc_op], 0
    mov byte [calc_entry], 1
    mov byte [calc_result_fresh], 1
    mov byte [calc_decimal], 0
    mov byte [calc_frac_digits], 0
.done:
    ret

calc96_apply_impl:
    push eax
    push ebx
    push ecx
    push edx
    push si
    push di
    mov al, [calc_op]
    cmp al, '+'
    je .add
    cmp al, '-'
    je .sub
    cmp al, '*'
    je .mul
    cmp al, '/'
    jne .error
    mov si, calc_current
    call calc96_is_zero
    jz .error
    call calc96_prepare_abs_pair
    call calc96_div_abs
    jc .error
    jmp .restore_sign
.mul:
    call calc96_prepare_abs_pair
    call calc96_mul_abs
    jc .error
.restore_sign:
    cmp byte [CALC96_SIGN], 0
    je .commit
    mov si, CALC96_C
    call calc96_neg
    jmp .commit
.add:
    mov si, calc_acc
    mov di, CALC96_C
    call calc96_copy
    mov si, calc_current
    mov di, CALC96_C
    call calc96_add
    jmp .commit
.sub:
    mov si, calc_acc
    mov di, CALC96_C
    call calc96_copy
    mov si, calc_current
    mov di, CALC96_C
    call calc96_sub
.commit:
    call calc96_check_c_range
    jc .error
    mov si, CALC96_C
    mov di, calc_acc
    call calc96_copy
    jmp .done
.error:
    mov byte [calc_error], 1
.done:
    pop di
    pop si
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

calc96_percent_impl:
    push eax
    push ebx
    push edx
    push si
    push di
    cmp byte [calc_error], 0
    jne .done
    mov si, calc_current
    call calc96_abs_to_a
    mov al, [CALC96_SIGN]
    mov [CALC96_SIGN_B], al
    mov si, CALC96_A
    mov ebx, 100
    call calc96_div_dword
    cmp edx, 50
    jb .signed
    add dword [CALC96_A], 1
    adc dword [CALC96_A+4], 0
    adc dword [CALC96_A+8], 0
.signed:
    cmp byte [CALC96_SIGN_B], 0
    je .store
    mov si, CALC96_A
    call calc96_neg
.store:
    mov si, CALC96_A
    mov di, calc_current
    call calc96_copy
    mov byte [calc_entry], 1
    mov byte [calc_result_fresh], 0
    mov byte [calc_decimal], 0
    mov byte [calc_frac_digits], 0
.done:
    pop di
    pop si
    pop edx
    pop ebx
    pop eax
    ret

; Square the unsigned qword at CALC96_MID into four low product dwords.
calc96_square_mid:
    mov dword [CALC96_PROD], 0
    mov dword [CALC96_PROD+4], 0
    mov dword [CALC96_PROD+8], 0
    mov dword [CALC96_PROD+12], 0
    mov eax, [CALC96_MID]
    mov ebx, eax
    mul ebx
    mov [CALC96_PROD], eax
    mov [CALC96_PROD+4], edx
    mov eax, [CALC96_MID]
    mul dword [CALC96_MID+4]
    add [CALC96_PROD+4], eax
    adc [CALC96_PROD+8], edx
    adc dword [CALC96_PROD+12], 0
    add [CALC96_PROD+4], eax
    adc [CALC96_PROD+8], edx
    adc dword [CALC96_PROD+12], 0
    mov eax, [CALC96_MID+4]
    mul dword [CALC96_MID+4]
    add [CALC96_PROD+8], eax
    adc [CALC96_PROD+12], edx
    ret

calc96_sqrt_impl:
    push eax
    push ebx
    push ecx
    push edx
    push si
    push di
    cmp byte [calc_error], 0
    jne .done
    test dword [calc_current+8], 0x80000000
    jnz .error
    mov si, calc_current
    mov di, CALC96_A
    call calc96_copy
    mov ebx, CALC_SCALE
    call calc96_a_mul_dword_wide
    mov dword [CALC96_LOW], 0
    mov dword [CALC96_LOW+4], 0
    mov dword [CALC96_HIGH], 0
    mov dword [CALC96_HIGH+4], 0x01000000
.search:
    mov eax, [CALC96_LOW+4]
    cmp eax, [CALC96_HIGH+4]
    jb .make_mid
    ja .finish
    mov eax, [CALC96_LOW]
    cmp eax, [CALC96_HIGH]
    jae .finish
.make_mid:
    mov eax, [CALC96_LOW]
    mov edx, [CALC96_LOW+4]
    add eax, [CALC96_HIGH]
    adc edx, [CALC96_HIGH+4]
    add eax, 1
    adc edx, 0
    shrd eax, edx, 1
    shr edx, 1
    mov [CALC96_MID], eax
    mov [CALC96_MID+4], edx
    call calc96_square_mid
    mov eax, [CALC96_PROD+12]
    cmp eax, [CALC96_WIDE+12]
    jb .fits
    ja .too_high
    mov eax, [CALC96_PROD+8]
    cmp eax, [CALC96_WIDE+8]
    jb .fits
    ja .too_high
    mov eax, [CALC96_PROD+4]
    cmp eax, [CALC96_WIDE+4]
    jb .fits
    ja .too_high
    mov eax, [CALC96_PROD]
    cmp eax, [CALC96_WIDE]
    jbe .fits
.too_high:
    mov eax, [CALC96_MID]
    mov edx, [CALC96_MID+4]
    sub eax, 1
    sbb edx, 0
    mov [CALC96_HIGH], eax
    mov [CALC96_HIGH+4], edx
    jmp .search
.fits:
    mov eax, [CALC96_MID]
    mov edx, [CALC96_MID+4]
    mov [CALC96_LOW], eax
    mov [CALC96_LOW+4], edx
    jmp .search
.finish:
    ; Round the integer square root to the nearest 1/10,000,000 unit.
    ; With R=floor(sqrt(N)), round upward exactly when N-R^2 > R.
    mov eax, [CALC96_LOW]
    mov [CALC96_MID], eax
    mov eax, [CALC96_LOW+4]
    mov [CALC96_MID+4], eax
    call calc96_square_mid
    mov eax, [CALC96_WIDE]
    sub eax, [CALC96_PROD]
    mov [CALC96_REM], eax
    mov eax, [CALC96_WIDE+4]
    sbb eax, [CALC96_PROD+4]
    mov [CALC96_REM+4], eax
    mov eax, [CALC96_WIDE+8]
    sbb eax, [CALC96_PROD+8]
    mov [CALC96_REM+8], eax
    cmp dword [CALC96_REM+8], 0
    jne .round_up
    mov eax, [CALC96_REM+4]
    cmp eax, [CALC96_LOW+4]
    ja .round_up
    jb .store
    mov eax, [CALC96_REM]
    cmp eax, [CALC96_LOW]
    jbe .store
.round_up:
    add dword [CALC96_LOW], 1
    adc dword [CALC96_LOW+4], 0
.store:
    mov eax, [CALC96_LOW]
    mov [calc_current], eax
    mov eax, [CALC96_LOW+4]
    mov [calc_current+4], eax
    mov dword [calc_current+8], 0
    mov byte [calc_entry], 1
    mov byte [calc_result_fresh], 1
    mov byte [calc_decimal], 0
    mov byte [calc_frac_digits], 0
    jmp .done
.error:
    mov byte [calc_error], 1
.done:
    pop di
    pop si
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

calc96_format_impl:
    push eax
    push ebx
    push ecx
    push edx
    push si
    push di
    cmp byte [calc_error], 0
    je .number
    mov si, str_error
    mov di, calc_display_buf
.copy_error:
    lodsb
    stosb
    test al, al
    jnz .copy_error
    jmp .done
.number:
    mov si, calc_current
    cmp byte [calc_entry], 0
    jne .selected
    mov si, calc_acc
.selected:
    call calc96_abs_to_a
    mov si, CALC96_A
    mov ebx, CALC_SCALE
    call calc96_div_dword
    mov [CALC96_FRAC], edx
    mov di, calc_display_buf+30
    mov byte [di], 0
    dec di
    mov si, CALC96_A
    call calc96_is_zero
    jnz .integer_loop
    mov byte [di], '0'
    dec di
    jmp .integer_done
.integer_loop:
    mov si, CALC96_A
    mov ebx, 10
    call calc96_div_dword
    add dl, '0'
    mov [di], dl
    dec di
    mov si, CALC96_A
    call calc96_is_zero
    jnz .integer_loop
.integer_done:
    cmp byte [CALC96_SIGN], 0
    je .shift_integer
    mov byte [di], '-'
    dec di
.shift_integer:
    inc di
    mov si, di
    mov di, calc_display_buf
.copy_integer:
    lodsb
    stosb
    test al, al
    jnz .copy_integer
    dec di
    cmp dword [CALC96_FRAC], 0
    jne .fraction
    cmp byte [calc_decimal], 0
    je .terminate
    mov byte [di], '.'
    inc di
    jmp .terminate
.fraction:
    mov byte [di], '.'
    inc di
    mov cx, 7
.fraction_loop:
    mov eax, [CALC96_FRAC]
    imul eax, eax, 10
    xor edx, edx
    mov ebx, CALC_SCALE
    div ebx
    add al, '0'
    stosb
    mov [CALC96_FRAC], edx
    loop .fraction_loop
.trim:
    cmp byte [di-1], '0'
    jne .terminate
    dec di
    jmp .trim
.terminate:
    mov byte [di], 0
.done:
    pop di
    pop si
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

paint_flood_fill:
    ; Marker propagation scans only active rows/columns while using the fixed
    ; maximum stride. This avoids both resize padding and unrelated left-edge
    ; regions becoming accidental seeds.
    ; Keep X in DI. 16-bit MUL writes DX:AX; the old DX temporary was therefore
    ; overwritten and every fill began at x=0 regardless of the click position.
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push fs
    mov di, ax
    mov ax, bx
    mov cx, PAINT_CANVAS_STRIDE
    mul cx
    add di, ax
    mov ax, [active_data_seg]
    mov fs, ax
    mov al, fs:[di]
    mov [paint_fill_target], al
    call paint_current_color
    mov [paint_fill_new], dl
    cmp al, dl
    je .done
    call canvas_backup_memory
    mov byte fs:[di], PAINT_FILL_MARKER
.repeat:
    mov byte [paint_fill_changed], 0
    xor bp, bp
.forward_row:
    cmp bp, [paint_canvas_h]
    jae .reverse_start
    mov ax, bp
    mov cx, PAINT_CANVAS_STRIDE
    mul cx
    mov si, ax
    xor bx, bx
.forward_col:
    cmp bx, [paint_canvas_w]
    jae .forward_next
    mov al, fs:[si]
    cmp al, [paint_fill_target]
    jne .forward_advance
    cmp bx, 0
    je .f_right
    cmp byte fs:[si-1], PAINT_FILL_MARKER
    je .f_set
.f_right:
    mov ax, [paint_canvas_w]
    dec ax
    cmp bx, ax
    jae .f_up
    cmp byte fs:[si+1], PAINT_FILL_MARKER
    je .f_set
.f_up:
    cmp bp, 0
    je .f_down
    cmp byte fs:[si-PAINT_CANVAS_STRIDE], PAINT_FILL_MARKER
    je .f_set
.f_down:
    mov ax, [paint_canvas_h]
    dec ax
    cmp bp, ax
    jae .forward_advance
    cmp byte fs:[si+PAINT_CANVAS_STRIDE], PAINT_FILL_MARKER
    jne .forward_advance
.f_set:
    mov byte fs:[si], PAINT_FILL_MARKER
    mov byte [paint_fill_changed], 1
.forward_advance:
    inc si
    inc bx
    jmp .forward_col
.forward_next:
    inc bp
    jmp .forward_row
.reverse_start:
    mov bp, [paint_canvas_h]
    dec bp
.reverse_row:
    mov ax, bp
    mov cx, PAINT_CANVAS_STRIDE
    mul cx
    mov si, ax
    add si, [paint_canvas_w]
    dec si
    mov bx, [paint_canvas_w]
    dec bx
.reverse_col:
    mov al, fs:[si]
    cmp al, [paint_fill_target]
    jne .reverse_advance
    cmp bx, 0
    je .r_right
    cmp byte fs:[si-1], PAINT_FILL_MARKER
    je .r_set
.r_right:
    mov ax, [paint_canvas_w]
    dec ax
    cmp bx, ax
    jae .r_up
    cmp byte fs:[si+1], PAINT_FILL_MARKER
    je .r_set
.r_up:
    cmp bp, 0
    je .r_down
    cmp byte fs:[si-PAINT_CANVAS_STRIDE], PAINT_FILL_MARKER
    je .r_set
.r_down:
    mov ax, [paint_canvas_h]
    dec ax
    cmp bp, ax
    jae .reverse_advance
    cmp byte fs:[si+PAINT_CANVAS_STRIDE], PAINT_FILL_MARKER
    jne .reverse_advance
.r_set:
    mov byte fs:[si], PAINT_FILL_MARKER
    mov byte [paint_fill_changed], 1
.reverse_advance:
    cmp bx, 0
    je .reverse_next
    dec si
    dec bx
    jmp .reverse_col
.reverse_next:
    cmp bp, 0
    je .check_repeat
    dec bp
    jmp .reverse_row
.check_repeat:
    cmp byte [paint_fill_changed], 0
    jne .repeat
    xor bp, bp
.commit_row:
    cmp bp, [paint_canvas_h]
    jae .commit_done
    mov ax, bp
    mov cx, PAINT_CANVAS_STRIDE
    mul cx
    mov si, ax
    mov cx, [paint_canvas_w]
.commit_col:
    cmp byte fs:[si], PAINT_FILL_MARKER
    jne .commit_next
    mov al, [paint_fill_new]
    mov fs:[si], al
.commit_next:
    inc si
    loop .commit_col
    inc bp
    jmp .commit_row
.commit_done:
    call proc_save
    call redraw_all
.done:
    pop fs
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; =============================================================================
; Hit testing and mouse UI actions; =============================================================================
; Hit testing and mouse UI actions
; =============================================================================

paint_index_to_rgb:
    ; AL=palette index, update RGB edit fields.
    push ax
    push bx
    push dx
    cmp al, 16
    jb .classic
    cmp al, 231
    ja .gray
    sub al, 16
    xor ah, ah
    mov bl, 36
    div bl
    mov dl, ah
    mov bl, 51
    mul bl
    mov [paint_rgb_r], al
    mov al, dl
    xor ah, ah
    mov bl, 6
    div bl
    mov dl, ah
    mov bl, 51
    mul bl
    mov [paint_rgb_g], al
    mov al, dl
    mov bl, 51
    mul bl
    mov [paint_rgb_b], al
    jmp .done
.classic:
    xor ah, ah
    mov bl, 3
    mul bl
    mov bx, ax
    mov al, [classic_rgb_values+bx]
    mov [paint_rgb_r], al
    mov al, [classic_rgb_values+bx+1]
    mov [paint_rgb_g], al
    mov al, [classic_rgb_values+bx+2]
    mov [paint_rgb_b], al
    jmp .done
.gray:
    cmp al, 232
    jb .done
    cmp al, 247
    ja .done
    sub al, 232
    mov bl, 17
    mul bl
    mov [paint_rgb_r], al
    mov [paint_rgb_g], al
    mov [paint_rgb_b], al
.done:
    pop dx
    pop bx
    pop ax
    ret

paint_rgb_to_index:
    ; Quantize all three independent 0..255 fields to the 6x6x6 VGA cube.
    ; Build the index in SI so the green contribution cannot be lost through
    ; shared byte-register arithmetic: index = 16 + R*36 + G*6 + B.
    push ax
    push bx
    push cx
    push dx
    push si

    mov al, [paint_rgb_r]
    xor ah, ah
    add ax, 25
    mov bl, 51
    div bl
    cmp al, 5
    jbe .r_ok
    mov al, 5
.r_ok:
    xor ah, ah
    mov bl, 36
    mul bl
    mov si, ax

    mov al, [paint_rgb_g]
    xor ah, ah
    add ax, 25
    mov bl, 51
    div bl
    cmp al, 5
    jbe .g_ok
    mov al, 5
.g_ok:
    xor ah, ah
    mov bl, 6
    mul bl
    add si, ax

    mov al, [paint_rgb_b]
    xor ah, ah
    add ax, 25
    mov bl, 51
    div bl
    cmp al, 5
    jbe .b_ok
    mov al, 5
.b_ok:
    xor ah, ah
    add si, ax
    add si, 16
    mov ax, si
    mov [paint_color], al
    mov byte [paint_rainbow], 0
    mov byte [paint_eraser], 0
    call paint_sync_custom_swatch
    call paint_apply_color_to_selected

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

canvas_restore_from_undo:
    cmp byte [undo_available], 0
    je .done
    mov al, [active_pid]
    cmp al, [paint_undo_pid]
    jne .done
    push ax
    push cx
    push si
    push di
    push es
    push fs
    mov ax, UNDO_SEG
    mov fs, ax
    mov ax, [active_data_seg]
    mov es, ax
    xor si, si
    xor di, di
    mov cx, PAINT_CANVAS_STORAGE_SIZE
.copy:
    mov al, fs:[si]
    mov es:[di], al
    inc si
    inc di
    loop .copy
    pop fs
    pop es
    pop di
    pop si
    pop cx
    pop ax
.done:
    ret

paint_screen_point_to_local:
    ; AX=screen x, BX=screen y -> AX/BX local, CF=1 when inside.
    ; paint_compute_canvas_rect uses AX as scratch. Preserve the incoming
    ; screen point or every Paint operation collapses onto one fixed X.
    push ax
    push bx
    call paint_compute_canvas_rect
    pop bx
    pop ax
    cmp ax, [paint_canvas_screen_x]
    jb .outside
    mov dx, [paint_canvas_screen_x]
    add dx, [paint_canvas_screen_w]
    cmp ax, dx
    jae .outside
    cmp bx, [paint_canvas_screen_y]
    jb .outside
    mov dx, [paint_canvas_screen_y]
    add dx, [paint_canvas_screen_h]
    cmp bx, dx
    jae .outside
    sub ax, [paint_canvas_screen_x]
    sub bx, [paint_canvas_screen_y]
    push dx
    push cx
    xor dx, dx
    xor cx, cx
    mov cl, [paint_zoom]
    div cx
    add ax, [paint_scroll_x]
    xchg ax, bx
    xor dx, dx
    div cx
    add ax, [paint_scroll_y]
    xchg ax, bx
    pop cx
    pop dx
    cmp ax, [paint_canvas_w]
    jae .outside
    cmp bx, [paint_canvas_h]
    jae .outside
    stc
    ret
.outside:
    clc
    ret

paint_selection_prepare_transform:
    cmp byte [paint_select_pending], 0
    jne .done
    call canvas_backup_memory
    call paint_selection_capture
    mov ax, [paint_select_x]
    mov [paint_select_source_x], ax
    mov ax, [paint_select_y]
    mov [paint_select_source_y], ax
    mov ax, [paint_select_w]
    mov [paint_select_source_w], ax
    mov ax, [paint_select_h]
    mov [paint_select_source_h], ax
    ; Clear only the selected object's old pixels from the working canvas.
    ; The pre-move canvas remains in UNDO_SEG and destination pixels stay
    ; unchanged until the move/resize is confirmed.
    call paint_selection_clear_original
.done:
    ret

paint_selection_begin:
    ; AX/BX local canvas point.
    mov [paint_select_cur_x], ax
    mov [paint_select_cur_y], bx
    cmp byte [paint_select_active], 0
    je .create
    mov dx, [paint_select_x]
    cmp ax, dx
    jb .create
    add dx, [paint_select_w]
    cmp ax, dx
    ja .create
    mov dx, [paint_select_y]
    cmp bx, dx
    jb .create
    add dx, [paint_select_h]
    cmp bx, dx
    ja .create
    ; Points close to any of the eight handles resize; the interior moves.
    mov byte [paint_select_handle], 0
    mov dx, ax
    sub dx, [paint_select_x]
    cmp dx, 2
    ja .check_right
    or byte [paint_select_handle], 1
.check_right:
    mov dx, [paint_select_x]
    add dx, [paint_select_w]
    dec dx
    sub dx, ax
    cmp dx, 2
    ja .check_top
    or byte [paint_select_handle], 2
.check_top:
    mov dx, bx
    sub dx, [paint_select_y]
    cmp dx, 2
    ja .check_bottom
    or byte [paint_select_handle], 4
.check_bottom:
    mov dx, [paint_select_y]
    add dx, [paint_select_h]
    dec dx
    sub dx, bx
    cmp dx, 2
    ja .handle_ready
    or byte [paint_select_handle], 8
.handle_ready:
    cmp byte [paint_select_handle], 0
    jne .resize
    call paint_selection_prepare_transform
    mov byte [paint_select_drag], 2
    mov ax, [paint_select_x]
    mov [paint_select_orig_x], ax
    mov ax, [paint_select_y]
    mov [paint_select_orig_y], ax
    mov ax, [paint_select_w]
    mov [paint_select_orig_w], ax
    mov ax, [paint_select_h]
    mov [paint_select_orig_h], ax
    mov ax, [paint_select_cur_x]
    sub ax, [paint_select_x]
    mov [paint_select_anchor_x], ax
    mov ax, [paint_select_cur_y]
    sub ax, [paint_select_y]
    mov [paint_select_anchor_y], ax
    jmp .start
.resize:
    call paint_selection_prepare_transform
    mov byte [paint_select_drag], 3
    mov ax, [paint_select_x]
    mov [paint_select_orig_x], ax
    mov ax, [paint_select_y]
    mov [paint_select_orig_y], ax
    mov ax, [paint_select_w]
    mov [paint_select_orig_w], ax
    mov ax, [paint_select_h]
    mov [paint_select_orig_h], ax
    jmp .start
.create:
    cmp byte [paint_select_pending], 0
    je .create_ready
    push ax
    push bx
    call paint_selection_commit_pending
    pop bx
    pop ax
.create_ready:
    mov byte [paint_select_active], 1
    mov byte [paint_select_drag], 1
    mov [paint_select_start_x], ax
    mov [paint_select_start_y], bx
    mov [paint_select_x], ax
    mov [paint_select_y], bx
    mov word [paint_select_w], 1
    mov word [paint_select_h], 1
.start:
    mov al, [active_pid]
    mov [interaction_pid], al
    call proc_save
    call redraw_all
    ret

paint_selection_update:
    cmp byte [paint_select_drag], 0
    je .done
    call paint_get_local
    jnc .done
    mov [paint_select_cur_x], ax
    mov [paint_select_cur_y], bx
    cmp byte [paint_select_drag], 1
    je .create
    cmp byte [paint_select_drag], 2
    je .move
    ; Resize from the chosen edge/corner, keeping the opposite side fixed.
    mov ax, [paint_select_orig_x]
    mov [paint_select_x], ax
    mov ax, [paint_select_orig_w]
    mov [paint_select_w], ax
    test byte [paint_select_handle], 1
    jz .resize_right
    mov ax, [paint_select_cur_x]
    mov dx, [paint_select_orig_x]
    add dx, [paint_select_orig_w]
    dec dx
    cmp ax, dx
    jbe .left_ok
    mov ax, dx
.left_ok:
    mov [paint_select_x], ax
    sub dx, ax
    inc dx
    mov [paint_select_w], dx
    jmp .resize_vertical
.resize_right:
    test byte [paint_select_handle], 2
    jz .resize_vertical
    mov ax, [paint_select_cur_x]
    sub ax, [paint_select_orig_x]
    inc ax
    jg .right_ok
    mov ax, 1
.right_ok:
    mov [paint_select_w], ax
.resize_vertical:
    mov ax, [paint_select_orig_y]
    mov [paint_select_y], ax
    mov ax, [paint_select_orig_h]
    mov [paint_select_h], ax
    test byte [paint_select_handle], 4
    jz .resize_bottom
    mov ax, [paint_select_cur_y]
    mov dx, [paint_select_orig_y]
    add dx, [paint_select_orig_h]
    dec dx
    cmp ax, dx
    jbe .top_ok
    mov ax, dx
.top_ok:
    mov [paint_select_y], ax
    sub dx, ax
    inc dx
    mov [paint_select_h], dx
    jmp .check_ratio
.resize_bottom:
    test byte [paint_select_handle], 8
    jz .check_ratio
    mov ax, [paint_select_cur_y]
    sub ax, [paint_select_orig_y]
    inc ax
    jg .bottom_ok
    mov ax, 1
.bottom_ok:
    mov [paint_select_h], ax
.check_ratio:
    mov ah, 0x02
    int 0x16
    test al, 0x03
    jz .redraw
    test byte [paint_select_handle], 3
    jnz .ratio_from_width
    mov ax, [paint_select_h]
    mul word [paint_select_orig_w]
    xor dx, dx
    div word [paint_select_orig_h]
    cmp ax, 1
    jae .ratio_width_ok
    mov ax, 1
.ratio_width_ok:
    mov dx, [paint_canvas_w]
    sub dx, [paint_select_x]
    cmp ax, dx
    jbe .ratio_width_clamped
    mov ax, dx
.ratio_width_clamped:
    mov [paint_select_w], ax
    jmp .redraw
.ratio_from_width:
    mov ax, [paint_select_w]
    mul word [paint_select_orig_h]
    xor dx, dx
    div word [paint_select_orig_w]
    cmp ax, 1
    jae .ratio_ok
    mov ax, 1
.ratio_ok:
    mov dx, [paint_canvas_h]
    sub dx, [paint_select_orig_y]
    cmp ax, dx
    jbe .ratio_clamped
    mov ax, dx
.ratio_clamped:
    mov [paint_select_h], ax
    test byte [paint_select_handle], 4
    jz .redraw
    mov dx, [paint_select_orig_y]
    add dx, [paint_select_orig_h]
    sub dx, ax
    mov [paint_select_y], dx
    jmp .redraw
.move:
    mov ax, [paint_select_cur_x]
    sub ax, [paint_select_anchor_x]
    jns .mx_ok
    xor ax, ax
.mx_ok:
    mov dx, [paint_canvas_w]
    sub dx, [paint_select_w]
    cmp ax, dx
    jbe .mx_clamped
    mov ax, dx
.mx_clamped:
    mov [paint_select_x], ax
    mov ax, [paint_select_cur_y]
    sub ax, [paint_select_anchor_y]
    jns .my_ok
    xor ax, ax
.my_ok:
    mov dx, [paint_canvas_h]
    sub dx, [paint_select_h]
    cmp ax, dx
    jbe .my_clamped
    mov ax, dx
.my_clamped:
    mov [paint_select_y], ax
    jmp .redraw
.create:
    mov dx, [paint_select_start_x]
    cmp ax, dx
    jae .cx_ordered
    mov [paint_select_x], ax
    sub dx, ax
    inc dx
    mov [paint_select_w], dx
    jmp .cy
.cx_ordered:
    mov [paint_select_x], dx
    sub ax, dx
    inc ax
    mov [paint_select_w], ax
.cy:
    mov ax, bx
    mov dx, [paint_select_start_y]
    cmp ax, dx
    jae .cy_ordered
    mov [paint_select_y], ax
    sub dx, ax
    inc dx
    mov [paint_select_h], dx
    jmp .redraw
.cy_ordered:
    mov [paint_select_y], dx
    sub ax, dx
    inc ax
    mov [paint_select_h], ax
.redraw:
    call redraw_all
.done:
    ret

paint_selection_finish:
    cmp byte [paint_select_drag], 2
    je .pending
    cmp byte [paint_select_drag], 3
    jne .finish
.pending:
    mov byte [paint_select_pending], 1
.finish:
    mov byte [paint_select_drag], 0
    call proc_save
    call redraw_all
    ret

paint_selection_confirm:
    cmp byte [paint_select_drag], 0
    je .hide
    call paint_selection_finish
.hide:
    call paint_selection_commit_pending
    mov byte [paint_select_active], 0
    mov byte [paint_select_drag], 0
    mov byte [paint_select_pending], 0
    call proc_save
    call redraw_all
    ret

paint_selection_commit_pending:
    cmp byte [paint_select_pending], 0
    je .done
    ; The source was cleared when transformation began. Commit only the
    ; destination now; unrelated pixels under the preview were preserved.
    call paint_selection_paste_to_canvas
    mov byte [paint_select_pending], 0
    call proc_save
.done:
    ret

paint_selection_clear_original:
    push ax
    push bx
    mov ax, [paint_select_x]
    push ax
    mov ax, [paint_select_y]
    push ax
    mov ax, [paint_select_w]
    push ax
    mov ax, [paint_select_h]
    push ax
    mov ax, [paint_select_source_x]
    mov [paint_select_x], ax
    mov ax, [paint_select_source_y]
    mov [paint_select_y], ax
    mov ax, [paint_select_source_w]
    mov [paint_select_w], ax
    mov ax, [paint_select_source_h]
    mov [paint_select_h], ax
    call paint_selection_clear_area
    pop ax
    mov [paint_select_h], ax
    pop ax
    mov [paint_select_w], ax
    pop ax
    mov [paint_select_y], ax
    pop ax
    mov [paint_select_x], ax
    pop bx
    pop ax
    ret

paint_selection_capture:
    mov al, [clipboard_kind]
    mov [paint_saved_clip_kind], al
    mov ax, [clipboard_len]
    mov [paint_saved_clip_len], ax
    call paint_selection_copy
    mov al, [paint_saved_clip_kind]
    mov [clipboard_kind], al
    mov ax, [paint_saved_clip_len]
    mov [clipboard_len], ax
    ret

paint_selection_copy:
    cmp byte [paint_select_active], 0
    je .done
    cmp byte [paint_select_pending], 0
    je .capture
    mov ax, [paint_clip_w]
    mul word [paint_clip_h]
    mov [clipboard_len], ax
    mov byte [clipboard_kind], 2
    ret
.capture:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push es
    push fs
    mov ax, [paint_select_w]
    mov [paint_clip_w], ax
    mov bx, [paint_select_h]
    mov [paint_clip_h], bx
    mul bx
    cmp ax, CLIP_MAX
    ja .restore
    mov [clipboard_len], ax
    mov byte [clipboard_kind], 2
    mov byte [paint_select_buffer_valid], 1
    mov ax, [active_data_seg]
    mov fs, ax
    mov ax, SELECT_SEG
    mov es, ax
    xor di, di
    xor bp, bp
.row:
    cmp bp, [paint_select_h]
    jae .restore
    mov ax, [paint_select_y]
    add ax, bp
    mov bx, PAINT_CANVAS_STRIDE
    mul bx
    add ax, [paint_select_x]
    mov si, ax
    mov cx, [paint_select_w]
.col:
    mov al, fs:[si]
    mov es:[di], al
    inc si
    inc di
    loop .col
    inc bp
    jmp .row
.restore:
    pop fs
    pop es
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
.done:
    ret

paint_selection_clear_area:
    cmp byte [paint_select_active], 0
    je .done
    push ax
    push bx
    push cx
    push dx
    push di
    push bp
    push fs
    mov ax, [active_data_seg]
    mov fs, ax
    xor bp, bp
.row:
    cmp bp, [paint_select_h]
    jae .restore
    mov ax, [paint_select_y]
    add ax, bp
    cmp ax, [paint_canvas_h]
    jae .next
    mov bx, PAINT_CANVAS_STRIDE
    mul bx
    add ax, [paint_select_x]
    mov di, ax
    mov cx, [paint_select_w]
.col:
    cmp cx, 0
    je .next
    mov byte fs:[di], COL_WHITE
    inc di
    dec cx
    jmp .col
.next:
    inc bp
    jmp .row
.restore:
    pop fs
    pop bp
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
.done:
    ret

paint_selection_paste_to_canvas:
    cmp byte [paint_select_buffer_valid], 0
    je .done
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push fs
    push gs
    mov ax, [active_data_seg]
    mov fs, ax
    mov ax, SELECT_SEG
    mov gs, ax
    xor bp, bp
.row:
    cmp bp, [paint_select_h]
    jae .restore
    mov ax, bp
    mul word [paint_clip_h]
    div word [paint_select_h]
    mov bx, [paint_clip_w]
    mul bx
    mov si, ax
    mov ax, [paint_select_y]
    add ax, bp
    cmp ax, [paint_canvas_h]
    jae .next_row
    mov bx, PAINT_CANVAS_STRIDE
    mul bx
    add ax, [paint_select_x]
    mov di, ax
    xor cx, cx
.col:
    cmp cx, [paint_select_w]
    jae .next_row
    mov ax, cx
    mul word [paint_clip_w]
    div word [paint_select_w]
    mov bx, si
    add bx, ax
    mov al, gs:[bx]
    mov fs:[di], al
    inc di
    inc cx
    jmp .col
.next_row:
    inc bp
    jmp .row
.restore:
    pop gs
    pop fs
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    call mark_active_dirty
.done:
    ret

paint_selection_cut:
    cmp byte [paint_select_active], 0
    je .done
    call paint_selection_copy
    cmp byte [paint_select_pending], 0
    je .normal
    call paint_selection_clear_original
    mov byte [paint_select_pending], 0
    jmp .hide
.normal:
    call canvas_backup_memory
    call paint_selection_clear_area
.hide:
    mov byte [paint_select_active], 0
    call mark_active_dirty
    call proc_save
    call redraw_all
.done:
    ret

paint_selection_delete:
    cmp byte [paint_select_active], 0
    je .done
    cmp byte [paint_select_pending], 0
    je .normal
    call paint_selection_clear_original
    mov byte [paint_select_pending], 0
    jmp .hide
.normal:
    call canvas_backup_memory
    call paint_selection_clear_area
.hide:
    mov byte [paint_select_active], 0
    call mark_active_dirty
    call proc_save
    call redraw_all
.done:
    ret

paint_selection_paste:
    cmp byte [clipboard_kind], 2
    jne .done
    call paint_selection_commit_pending
    cmp byte [paint_select_active], 0
    je .origin
    add word [paint_select_x], 4
    add word [paint_select_y], 4
    jmp .size
.origin:
    mov word [paint_select_x], 0
    mov word [paint_select_y], 0
.size:
    mov ax, [paint_clip_w]
    mov [paint_select_w], ax
    mov ax, [paint_clip_h]
    mov [paint_select_h], ax
    mov ax, [paint_canvas_w]
    sub ax, [paint_select_w]
    cmp [paint_select_x], ax
    jbe .paste_x_ok
    mov [paint_select_x], ax
.paste_x_ok:
    mov ax, [paint_canvas_h]
    sub ax, [paint_select_h]
    cmp [paint_select_y], ax
    jbe .paste_y_ok
    mov [paint_select_y], ax
.paste_y_ok:
    mov byte [paint_select_active], 1
    mov byte [paint_tool], PAINT_TOOL_SELECT
    call canvas_backup_memory
    call paint_selection_paste_to_canvas
    call proc_save
    call redraw_all
.done:
    ret

paint_begin_shape:
    ; AX/BX is the displayed cursor hotspot captured at button-down.
    call canvas_backup_memory
    mov [shape_start_x], ax
    mov [shape_start_y], bx
    mov [shape_end_x], ax
    mov [shape_end_y], bx
    mov byte [paint_live_active], 1
    mov byte [paint_live_started], 1
    mov byte [painting_active], 1
    mov al, [active_pid]
    mov [interaction_pid], al
    call proc_save
    ret

paint_continue_shape:
    call paint_get_local
    jnc .done
    mov [shape_end_x], ax
    mov [shape_end_y], bx
    call canvas_restore_from_undo
    call paint_shape_constrain
    call paint_current_color
    mov [shape_color], dl
    mov al, [paint_tool]
    cmp al, PAINT_TOOL_LINE
    je .line
    cmp al, PAINT_TOOL_RECT
    je .rect
    call canvas_draw_ellipse_fixed
    jmp .redraw
.line:
    mov ax, [shape_start_x]
    mov [line_fixed_x0], ax
    mov ax, [shape_start_y]
    mov [line_fixed_y0], ax
    mov ax, [shape_end_x]
    mov [line_fixed_x1], ax
    mov ax, [shape_end_y]
    mov [line_fixed_y1], ax
    call canvas_draw_line_fixed
    jmp .redraw
.rect:
    call canvas_draw_rect_fixed
.redraw:
    call redraw_all
.done:
    ret

paint_shape_constrain:
    push ax
    push bx
    push cx
    push dx
    mov ah, 0x02
    int 0x16
    test al, 0x03
    jz .done
    mov ax, [shape_end_x]
    sub ax, [shape_start_x]
    mov [shape_dx_signed], ax
    cwd
    xor ax, dx
    sub ax, dx
    mov [shape_abs_dx], ax
    mov ax, [shape_end_y]
    sub ax, [shape_start_y]
    mov [shape_dy_signed], ax
    cwd
    xor ax, dx
    sub ax, dx
    mov [shape_abs_dy], ax
    cmp byte [paint_tool], PAINT_TOOL_LINE
    jne .square
    mov ax, [shape_abs_dx]
    mov bx, [shape_abs_dy]
    mov cx, bx
    shl cx, 1
    cmp ax, cx
    ja .horizontal
    mov cx, ax
    shl cx, 1
    cmp bx, cx
    ja .vertical
    cmp ax, bx
    jae .diag_size
    mov ax, bx
.diag_size:
    mov dx, [shape_dx_signed]
    test dx, dx
    jns .diag_x_pos
    neg ax
.diag_x_pos:
    add ax, [shape_start_x]
    mov [shape_end_x], ax
    mov ax, [shape_abs_dx]
    cmp ax, [shape_abs_dy]
    jae .diag_y_size
    mov ax, [shape_abs_dy]
.diag_y_size:
    mov dx, [shape_dy_signed]
    test dx, dx
    jns .diag_y_pos
    neg ax
.diag_y_pos:
    add ax, [shape_start_y]
    mov [shape_end_y], ax
    jmp .clamp
.horizontal:
    mov ax, [shape_start_y]
    mov [shape_end_y], ax
    jmp .clamp
.vertical:
    mov ax, [shape_start_x]
    mov [shape_end_x], ax
    jmp .clamp
.square:
    mov ax, [shape_abs_dx]
    cmp ax, [shape_abs_dy]
    jae .size_ready
    mov ax, [shape_abs_dy]
.size_ready:
    mov dx, [shape_dx_signed]
    test dx, dx
    jns .square_x_pos
    neg ax
.square_x_pos:
    add ax, [shape_start_x]
    mov [shape_end_x], ax
    mov ax, [shape_abs_dx]
    cmp ax, [shape_abs_dy]
    jae .square_y_size
    mov ax, [shape_abs_dy]
.square_y_size:
    mov dx, [shape_dy_signed]
    test dx, dx
    jns .square_y_pos
    neg ax
.square_y_pos:
    add ax, [shape_start_y]
    mov [shape_end_y], ax
.clamp:
    cmp word [shape_end_x], 0
    jge .x_nonneg
    mov word [shape_end_x], 0
.x_nonneg:
    mov ax, [paint_canvas_w]
    dec ax
    cmp [shape_end_x], ax
    jbe .x_ok
    mov [shape_end_x], ax
.x_ok:
    cmp word [shape_end_y], 0
    jge .y_nonneg
    mov word [shape_end_y], 0
.y_nonneg:
    mov ax, [paint_canvas_h]
    dec ax
    cmp [shape_end_y], ax
    jbe .done
    mov [shape_end_y], ax
.done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

canvas_draw_line_fixed:
    mov ax, [line_fixed_x0]
    mov [line_x], ax
    mov ax, [line_fixed_y0]
    mov [line_y], ax
    mov ax, [line_fixed_x1]
    sub ax, [line_x]
    jns .dx_positive
    neg ax
    mov word [line_sx], -1
    jmp .dx_ready
.dx_positive:
    mov word [line_sx], 1
.dx_ready:
    mov [line_dx], ax
    mov ax, [line_fixed_y1]
    sub ax, [line_y]
    jns .dy_positive
    neg ax
    mov word [line_sy], -1
    jmp .dy_ready
.dy_positive:
    mov word [line_sy], 1
.dy_ready:
    neg ax
    mov [line_dy], ax
    mov ax, [line_dx]
    add ax, [line_dy]
    mov [line_err], ax
.loop:
    mov ax, [line_x]
    mov bx, [line_y]
    mov dl, [shape_color]
    call canvas_draw_brush
    mov ax, [line_x]
    cmp ax, [line_fixed_x1]
    jne .step
    mov ax, [line_y]
    cmp ax, [line_fixed_y1]
    je .done
.step:
    mov ax, [line_err]
    shl ax, 1
    mov [line_e2], ax
    cmp ax, [line_dy]
    jl .skip_x
    mov ax, [line_err]
    add ax, [line_dy]
    mov [line_err], ax
    mov ax, [line_x]
    add ax, [line_sx]
    mov [line_x], ax
.skip_x:
    mov ax, [line_e2]
    cmp ax, [line_dx]
    jg .skip_y
    mov ax, [line_err]
    add ax, [line_dx]
    mov [line_err], ax
    mov ax, [line_y]
    add ax, [line_sy]
    mov [line_y], ax
.skip_y:
    jmp .loop
.done:
    ret

canvas_draw_rect_fixed:
    mov ax, [shape_start_x]
    mov [line_fixed_x0], ax
    mov ax, [shape_start_y]
    mov [line_fixed_y0], ax
    mov ax, [shape_end_x]
    mov [line_fixed_x1], ax
    mov ax, [shape_start_y]
    mov [line_fixed_y1], ax
    call canvas_draw_line_fixed
    mov ax, [shape_end_x]
    mov [line_fixed_x0], ax
    mov ax, [shape_start_y]
    mov [line_fixed_y0], ax
    mov ax, [shape_end_x]
    mov [line_fixed_x1], ax
    mov ax, [shape_end_y]
    mov [line_fixed_y1], ax
    call canvas_draw_line_fixed
    mov ax, [shape_end_x]
    mov [line_fixed_x0], ax
    mov ax, [shape_end_y]
    mov [line_fixed_y0], ax
    mov ax, [shape_start_x]
    mov [line_fixed_x1], ax
    mov ax, [shape_end_y]
    mov [line_fixed_y1], ax
    call canvas_draw_line_fixed
    mov ax, [shape_start_x]
    mov [line_fixed_x0], ax
    mov ax, [shape_end_y]
    mov [line_fixed_y0], ax
    mov ax, [shape_start_x]
    mov [line_fixed_x1], ax
    mov ax, [shape_start_y]
    mov [line_fixed_y1], ax
    call canvas_draw_line_fixed
    ret

canvas_draw_ellipse_fixed:
    push ax
    push bx
    push cx
    push dx
    push si
    mov ax, [shape_start_x]
    add ax, [shape_end_x]
    sar ax, 1
    mov [shape_center_x], ax
    mov ax, [shape_start_y]
    add ax, [shape_end_y]
    sar ax, 1
    mov [shape_center_y], ax
    mov ax, [shape_end_x]
    sub ax, [shape_start_x]
    cwd
    xor ax, dx
    sub ax, dx
    shr ax, 1
    mov [shape_radius_x], ax
    mov ax, [shape_end_y]
    sub ax, [shape_start_y]
    cwd
    xor ax, dx
    sub ax, dx
    shr ax, 1
    mov [shape_radius_y], ax
    mov word [shape_point_index], 0
.point_loop:
    mov si, [shape_point_index]
    xor ax, ax
    mov al, [circle_cos_early+si]
    cbw
    imul word [shape_radius_x]
    mov bx, 127
    idiv bx
    add ax, [shape_center_x]
    mov [shape_point_x], ax
    xor ax, ax
    mov al, [circle_sin_early+si]
    cbw
    imul word [shape_radius_y]
    mov bx, 127
    idiv bx
    add ax, [shape_center_y]
    mov [shape_point_y], ax
    cmp word [shape_point_index], 0
    je .store_prev
    mov ax, [shape_prev_x]
    mov [line_fixed_x0], ax
    mov ax, [shape_prev_y]
    mov [line_fixed_y0], ax
    mov ax, [shape_point_x]
    mov [line_fixed_x1], ax
    mov ax, [shape_point_y]
    mov [line_fixed_y1], ax
    call canvas_draw_line_fixed
.store_prev:
    mov ax, [shape_point_x]
    mov [shape_prev_x], ax
    mov ax, [shape_point_y]
    mov [shape_prev_y], ax
    inc word [shape_point_index]
    cmp word [shape_point_index], 33
    jb .point_loop
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

paint_text_rowcol_to_index:
    ; BX=row, CX=column -> AX insertion index, CF=1 if row exists.
    push bx
    push cx
    push dx
    push si
    push fs
    mov [text_target_row], bx
    mov [text_target_col], cx
    mov ax, [active_data_seg]
    mov fs, ax
    xor si, si
    xor dx, dx
.find_row:
    cmp dx, [text_target_row]
    je .row_found
    cmp si, [paint_text_len]
    jae .missing
    mov al, fs:[PAINT_TEXT_BASE+si]
    inc si
    cmp al, 13
    jne .find_row
    inc dx
    jmp .find_row
.row_found:
    xor bx, bx
.col_loop:
    cmp bx, [text_target_col]
    jae .ready
    cmp si, [paint_text_len]
    jae .ready
    cmp byte fs:[PAINT_TEXT_BASE+si], 13
    je .ready
    inc si
    inc bx
    jmp .col_loop
.ready:
    mov ax, si
    pop fs
    pop si
    pop dx
    pop cx
    pop bx
    stc
    ret
.missing:
    pop fs
    pop si
    pop dx
    pop cx
    pop bx
    clc
    ret

paint_text_index_to_rowcol:
    ; AX=index -> BX=row, CX=column.
    push ax
    push dx
    push si
    push fs
    mov dx, ax
    mov ax, [active_data_seg]
    mov fs, ax
    xor si, si
    xor bx, bx
    xor cx, cx
.loop:
    cmp si, dx
    jae .done
    cmp si, [paint_text_len]
    jae .done
    mov al, fs:[PAINT_TEXT_BASE+si]
    inc si
    cmp al, 13
    jne .column
    inc bx
    xor cx, cx
    jmp .loop
.column:
    inc cx
    jmp .loop
.done:
    pop fs
    pop si
    pop dx
    pop ax
    ret

paint_text_point_to_index:
    ; AX/BX local canvas point -> AX insertion index, CF=1 on active text line.
    cmp byte [paint_text_active], 0
    je .outside
    cmp ax, [paint_text_x]
    jae .x_ok
    mov ax, [paint_text_x]
.x_ok:
    cmp bx, [paint_text_y]
    jb .outside
    sub ax, [paint_text_x]
    mov [text_point_x], ax
    mov ax, bx
    sub ax, [paint_text_y]
    xor dx, dx
    xor cx, cx
    mov cl, [paint_text_size]
    shl cx, 3
    test cx, cx
    jnz .cell_ready
    mov cx, 8
.cell_ready:
    div cx
    mov bx, ax
    mov ax, [text_point_x]
    mov dx, cx
    shr dx, 1
    add ax, dx
    xor dx, dx
    div cx
    mov cx, ax
    call paint_text_rowcol_to_index
    ret
.outside:
    clc
    ret

paint_text_copy:
    cmp byte [paint_text_sel_active], 0
    je .done
    push ax
    push bx
    push cx
    push si
    push di
    push es
    push fs
    mov ax, [paint_text_anchor]
    mov bx, [paint_text_cursor]
    cmp ax, bx
    jbe .ordered
    xchg ax, bx
.ordered:
    mov cx, bx
    sub cx, ax
    mov [clipboard_len], cx
    mov byte [clipboard_kind], 1
    mov si, ax
    add si, PAINT_TEXT_BASE
    mov ax, [active_data_seg]
    mov fs, ax
    mov ax, CLIP_SEG
    mov es, ax
    xor di, di
.copy:
    test cx, cx
    jz .copied
    mov al, fs:[si]
    mov es:[di], al
    inc si
    inc di
    dec cx
    jmp .copy
.copied:
    mov byte es:[di], 0
    pop fs
    pop es
    pop di
    pop si
    pop cx
    pop bx
    pop ax
.done:
    ret

paint_text_cut:
    cmp byte [paint_text_sel_active], 0
    je .done
    call paint_text_copy
    call paint_text_delete_selection
    call proc_save
    call redraw_all
.done:
    ret

paint_text_paste:
    cmp byte [clipboard_kind], 1
    jne .done
    cmp byte [paint_text_active], 0
    jne .ready
    mov byte [paint_text_active], 1
    mov byte [paint_text_input], 1
    mov word [paint_text_x], 0
    mov word [paint_text_y], 0
    mov word [paint_text_len], 0
    mov word [paint_text_cursor], 0
    mov word [paint_text_anchor], 0
.ready:
    push ax
    push cx
    push si
    push gs
    mov ax, CLIP_SEG
    mov gs, ax
    xor si, si
    mov cx, [clipboard_len]
.loop:
    test cx, cx
    jz .finish
    mov al, gs:[si]
    push cx
    call paint_text_insert_char
    pop cx
    inc si
    dec cx
    jmp .loop
.finish:
    pop gs
    pop si
    pop cx
    pop ax
    call proc_save
    call redraw_all
.done:
    ret

paint_text_delete_selection:
    cmp byte [paint_text_sel_active], 0
    je .done
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push fs
    mov ax, [paint_text_anchor]
    mov bx, [paint_text_cursor]
    cmp ax, bx
    jbe .ordered
    xchg ax, bx
.ordered:
    cmp ax, bx
    je .clear
    mov [text_sel_start], ax
    mov [text_sel_end], bx
    mov dx, bx
    sub dx, ax
    mov ax, [active_data_seg]
    mov fs, ax
    mov si, [text_sel_end]
    mov di, [text_sel_start]
.shift:
    cmp si, [paint_text_len]
    jae .shift_done
    mov al, fs:[PAINT_TEXT_BASE+si]
    mov fs:[PAINT_TEXT_BASE+di], al
    mov bx, PAINT_TEXT_COLOR_BASE
    add bx, si
    mov al, fs:[bx]
    mov bx, PAINT_TEXT_COLOR_BASE
    add bx, di
    mov fs:[bx], al
    inc si
    inc di
    jmp .shift
.shift_done:
    sub [paint_text_len], dx
    mov ax, [text_sel_start]
    mov [paint_text_cursor], ax
    mov [paint_text_anchor], ax
.clear:
    mov byte [paint_text_sel_active], 0
    pop fs
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
.done:
    ret

paint_text_insert_char:
    ; AL=character, replacing the selected range and preserving per-char color.
    mov [paint_text_key_char], al
    call paint_text_delete_selection
    mov ax, [paint_text_len]
    cmp ax, PAINT_TEXT_MAX
    jae .done
    push ax
    push bx
    push si
    push di
    push fs
    mov ax, [active_data_seg]
    mov fs, ax
    mov si, [paint_text_len]
    mov di, si
    inc di
.shift_right:
    cmp si, [paint_text_cursor]
    jbe .insert
    dec si
    dec di
    mov al, fs:[PAINT_TEXT_BASE+si]
    mov fs:[PAINT_TEXT_BASE+di], al
    mov bx, PAINT_TEXT_COLOR_BASE
    add bx, si
    mov al, fs:[bx]
    mov bx, PAINT_TEXT_COLOR_BASE
    add bx, di
    mov fs:[bx], al
    jmp .shift_right
.insert:
    mov di, [paint_text_cursor]
    mov al, [paint_text_key_char]
    mov fs:[PAINT_TEXT_BASE+di], al
    mov bx, PAINT_TEXT_COLOR_BASE
    add bx, di
    mov al, [paint_color]
    mov fs:[bx], al
    inc word [paint_text_len]
    inc word [paint_text_cursor]
    mov ax, [paint_text_cursor]
    mov [paint_text_anchor], ax
    pop fs
    pop di
    pop si
    pop bx
    pop ax
.done:
    ret

paint_text_prepare_move:
    test byte [shift_flags], 0x03
    jnz .shift
    mov byte [paint_text_sel_active], 0
    ret
.shift:
    cmp byte [paint_text_sel_active], 0
    jne .done
    mov ax, [paint_text_cursor]
    mov [paint_text_anchor], ax
.done:
    ret

paint_text_finish_move:
    test byte [shift_flags], 0x03
    jnz .shift
    mov ax, [paint_text_cursor]
    mov [paint_text_anchor], ax
    mov byte [paint_text_sel_active], 0
    jmp .done
.shift:
    mov ax, [paint_text_cursor]
    cmp ax, [paint_text_anchor]
    jne .selected
    mov byte [paint_text_sel_active], 0
    jmp .done
.selected:
    mov byte [paint_text_sel_active], 1
.done:
    call proc_save
    call redraw_all
    ret

paint_resize_canvas:
    ; AX=new width, BX=new height. Cropped bitmap pixels are discarded; growth
    ; exposes freshly white storage instead of stretching existing content.
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es
    cmp ax, 1
    jae .w_min
    mov ax, 1
.w_min:
    cmp ax, PAINT_CANVAS_MAX_W
    jbe .w_max
    mov ax, PAINT_CANVAS_MAX_W
.w_max:
    cmp bx, 1
    jae .h_min
    mov bx, 1
.h_min:
    cmp bx, PAINT_CANVAS_MAX_H
    jbe .h_max
    mov bx, PAINT_CANVAS_MAX_H
.h_max:
    mov [resize_canvas_new_w], ax
    mov [resize_canvas_new_h], bx
    mov dx, [paint_canvas_w]
    cmp ax, dx
    jae .height_crop
    mov ax, [active_data_seg]
    mov es, ax
    xor si, si
.clear_right_row:
    cmp si, [paint_canvas_h]
    jae .height_crop
    mov ax, si
    mov cx, PAINT_CANVAS_STRIDE
    mul cx
    add ax, [resize_canvas_new_w]
    mov di, ax
    mov cx, [paint_canvas_w]
    sub cx, [resize_canvas_new_w]
    mov al, COL_WHITE
    rep stosb
    inc si
    jmp .clear_right_row
.height_crop:
    mov bx, [resize_canvas_new_h]
    cmp bx, [paint_canvas_h]
    jae .store
    mov ax, [active_data_seg]
    mov es, ax
    mov ax, bx
    mov cx, PAINT_CANVAS_STRIDE
    mul cx
    mov di, ax
    mov ax, [paint_canvas_h]
    sub ax, bx
    mov cx, PAINT_CANVAS_STRIDE
    mul cx
    mov cx, ax
    mov al, COL_WHITE
    rep stosb
.store:
    mov ax, [resize_canvas_new_w]
    mov [paint_canvas_w], ax
    mov ax, [resize_canvas_new_h]
    mov [paint_canvas_h], ax
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

paint_resize_canvas_from_window:
    mov ax, [paint_w]
    sub ax, PAINT_CANVAS_XOFF+PAINT_CANVAS_RIGHT_MARGIN
    mov bx, [paint_h]
    sub bx, PAINT_CANVAS_YOFF+PAINT_CANVAS_BOTTOM_MARGIN
    jmp paint_resize_canvas

; Far-call bridge used by the separately loaded custom-editor code segment.
; The requested stage-2 routine returns near to this bridge; RETF then returns
; to the editor at 6000h without requiring duplicate GUI primitives.
custom_stage2_gateway:
    call word [custom_gateway_target]
    retf

custom_launch_editor:
    pushad
    push ds
    push es
    xor ax, ax
    mov ds, ax
    cmp byte [custom_created], 1
    jne .load_editor
    mov byte [custom_open], 1
    mov byte [custom_minimized], 0
    mov al, WIN_CUSTOM
    call task_add_window
    pop es
    pop ds
    popad
    call redraw_all
    ret
.load_editor:
    ; The execution/return path lives in the far extension. It is loaded by the
    ; boot sector; retain the reload fallback for a damaged/cleared state byte.
    cmp byte [custom_ext_loaded], 1
    je .extension_ready
    mov byte [custom_dap+0], 0x10
    mov byte [custom_dap+1], 0
    mov word [custom_dap+2], STAGE2_EXT_SECTORS
    mov word [custom_dap+4], 0
    mov word [custom_dap+6], STAGE2_EXT_SEG
    mov dword [custom_dap+8], STAGE2_EXT_IMAGE_LBA
    mov dword [custom_dap+12], 0
    mov si, custom_dap
    mov dl, [os_boot_drive]
    mov ah, 0x42
    int 0x13
    jc .failed
    mov byte [custom_ext_loaded], 1
.extension_ready:
    ; The editor-sector transfer lives beyond the base segment as well; this
    ; keeps the Stage-2 near-code window below 64 KiB.
    call STAGE2_EXT_SEG:(custom_stage2_ext_open_editor-stage2_ext_start)
    jc .failed
    mov al, WIN_CUSTOM
    call task_add_window
    ; open_custom_editor performed its initial redraw before this resident
    ; task entry existed. Redraw once more now so the button is immediate.
    call redraw_all
    pop es
    pop ds
    popad
    ret
.failed:
    xor ax, ax
    mov ds, ax
    mov si, str_control_write_error
    mov [system_message_ptr], si
    mov byte [message_kind], MSG_SYSTEM
    mov byte [message_open], 1
    pop es
    pop ds
    popad
    call redraw_all
    ret

; The editor is a disk-loaded overlay.  Keeping it outside .text preserves the
; original stage-2 64-KiB code-segment contract.
SECTION .stage2ext follows=.text align=512 vstart=0
SECTION .hexeditor follows=.stage2ext align=512 vstart=0x7E00
SECTION .customeditor follows=.hexeditor align=512 vstart=0

%macro CUSTOM_STAGE2_PROXY 2
%1:
    mov word [custom_gateway_target], %2-stage2_start
    call STAGE2_SEG:(custom_stage2_gateway-stage2_start)
    ret
%endmacro

CUSTOM_STAGE2_PROXY custom_proxy_redraw_all, redraw_all
CUSTOM_STAGE2_PROXY custom_proxy_debug_nibble, debug_nibble_to_ascii
CUSTOM_STAGE2_PROXY custom_proxy_mouse_hide, mouse_cursor_hide
CUSTOM_STAGE2_PROXY custom_proxy_mouse_quiet, mouse_ps2_disable_stream
CUSTOM_STAGE2_PROXY custom_proxy_draw_bevel, draw_bevel_box
CUSTOM_STAGE2_PROXY custom_proxy_draw_frame, draw_frame_black
CUSTOM_STAGE2_PROXY custom_proxy_fill_rect, fill_rect
CUSTOM_STAGE2_PROXY custom_proxy_draw_text, draw_text
CUSTOM_STAGE2_PROXY custom_proxy_draw_char, draw_char
CUSTOM_STAGE2_PROXY custom_proxy_draw_button, draw_button
CUSTOM_STAGE2_PROXY custom_proxy_capture_button, try_capture_button
CUSTOM_STAGE2_PROXY custom_proxy_hit_rect, hit_rect
CUSTOM_STAGE2_PROXY custom_proxy_check_long_mode, debug_cpu_supports_long_mode
CUSTOM_STAGE2_PROXY custom_proxy_draw_grip, draw_resize_grip
CUSTOM_STAGE2_PROXY custom_proxy_task_remove, task_remove_window

%define redraw_all               custom_proxy_redraw_all
%define debug_nibble_to_ascii    custom_proxy_debug_nibble
%define mouse_cursor_hide        custom_proxy_mouse_hide
%define mouse_ps2_disable_stream custom_proxy_mouse_quiet
%define draw_bevel_box           custom_proxy_draw_bevel
%define draw_frame_black         custom_proxy_draw_frame
%define fill_rect                custom_proxy_fill_rect
%define draw_text                custom_proxy_draw_text
%define draw_char                custom_proxy_draw_char
%define draw_button              custom_proxy_draw_button
%define try_capture_button       custom_proxy_capture_button
%define hit_rect                 custom_proxy_hit_rect
%define draw_resize_grip         custom_proxy_draw_grip

str_custom_ready    db 'Ready',0
str_custom_saved    db 'Save succeeded.',0
str_custom_loaded   db 'Program loaded from LBA 500.',0
str_custom_empty    db 'No saved program; new buffer.',0
str_custom_full     db 'Space used up (LBA 500-999).',0
str_custom_no_edd   db 'Save failed: EDD disk I/O unavailable.',0
str_custom_read_failed db 'Load failed: disk read error.',0
str_custom_write_failed db 'Save failed: disk write error.',0
str_custom_bad_header db 'Load failed: invalid length header.',0
str_custom_exec_too_large db 'Execute failed: program exceeds 65520 bytes.',0
str_custom_exec_empty db 'Execute failed: program is empty.',0
str_custom_exec_write db 'Execute failed: staging write error.',0
str_custom_exec_read  db 'Execute failed: staging read error.',0
str_custom_exec_length db 'Execute failed: source length mismatch.',0
str_custom_exec_no_long db 'Execute failed: Long Mode is not supported.',0
str_custom_save_before_close db 'Save changes before closing?',0
str_custom_clear_question db 'Clear the entire program?',0
str_custom_prompt_goto db 'Go to line: ',0
str_custom_prompt_find db 'Find hex bytes: ',0
str_custom_prompt_find_replace db 'Find for replace: ',0
str_custom_prompt_replace db 'Replace with hex: ',0
str_custom_not_found db 'Pattern not found.',0
str_custom_replaced db 'Replacement completed.',0
str_custom_undone   db 'Undo completed.',0
str_custom_redone   db 'Redo completed.',0
str_custom_bad_input db 'Invalid or incomplete hex input.',0

; Draw a string stored in this overlay's own CS while using the resident
; stage-2 glyph renderer.  CX/DX/BL match draw_text.
custom_draw_text_local:
    push ax
    push bx
    push cx
    push dx
    push si
.next:
    mov ax, [custom_x]
    add ax, [custom_w]
    sub ax, 12
    cmp cx, ax
    ja .done
    mov al, [cs:si]
    inc si
    test al, al
    jz .done
    call draw_char
    add cx, 8
    jmp .next
.done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Draw an overlay-local string with a caller-supplied right edge in DI.
; Unlike custom_draw_text_local this routine wraps instead of silently
; clipping, so status details remain visible in a narrow parent window.
custom_draw_text_local_wrapped:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    mov bp, cx
.next:
    mov al, [cs:si]
    inc si
    test al, al
    jz .done
    cmp al, 0x0A
    je .new_line
    push ax
    mov ax, cx
    add ax, 8
    cmp ax, di
    pop ax
    jbe .draw
.new_line:
    mov cx, bp
    add dx, 10
    cmp al, 0x0A
    je .next
.draw:
    call draw_char
    add cx, 8
    jmp .next
.done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

custom_entry_open:
    call open_custom_editor
    retf
custom_entry_draw:
    call draw_custom_editor
    retf
custom_entry_key:
    call custom_handle_key
    retf
custom_entry_mouse_down:
    call handle_custom_mouse_down
    retf
custom_entry_scroll_drag:
    call custom_update_scroll_drag
    retf
custom_entry_mouse_select:
    call custom_update_mouse_selection
    retf
custom_entry_scroll_up:
    call custom_scroll_one_up
    retf
custom_entry_scroll_down:
    call custom_scroll_one_down
    retf
custom_entry_hscroll_left:
    call custom_hscroll_one_left
    retf
custom_entry_hscroll_right:
    call custom_hscroll_one_right
    retf
custom_entry_page_up:
    cmp byte [custom_exec_dialog], 0
    jne .page_up_done
    call custom_scroll_page_up
.page_up_done:
    retf
custom_entry_page_down:
    cmp byte [custom_exec_dialog], 0
    jne .page_down_done
    call custom_scroll_page_down
.page_down_done:
    retf
custom_entry_close:
    call custom_request_close
    retf
custom_entry_execute:
    call custom_request_execute
    retf
custom_entry_execute_real:
    xor al, al
    call custom_select_execute_mode
    retf
custom_entry_execute_pm:
    mov al, 1
    call custom_select_execute_mode
    retf
custom_entry_execute_lm:
    mov al, 2
    call custom_select_execute_mode
    retf
custom_entry_confirm_yes:
    call custom_confirm_yes
    retf
custom_entry_confirm_no:
    call custom_confirm_no
    retf
custom_entry_confirm_cancel:
    call custom_confirm_cancel
    retf
custom_entry_cursor_shape:
    call custom_choose_cursor_shape
    retf
custom_entry_minimize:
    call custom_minimize
    retf
custom_entry_maximize:
    call custom_toggle_maximize
    retf
custom_entry_resize_drag:
    call custom_update_resize_drag
    retf

; =============================================================================
; Custom Program editor
; =============================================================================
; Source bytes are kept at CUSTOM_BUFFER_PHYS.  CUSTOM_NEWLINE_PHYS contains
; one parallel flag byte per source position: 1 means the byte came from
; Enter, 0 means an ordinary machine/comment byte. Therefore opcode 0Ah and a
; structural newline may share the same byte value without sharing semantics.

custom_choose_cursor_shape:
    cmp byte [custom_confirm], 0
    jne .done
    cmp byte [custom_exec_dialog], 0
    jne .done
    cmp byte [custom_maximized], 0
    jne .done
    cmp byte [custom_resize_drag], 0
    jne .resize
    mov cx, [custom_x]
    add cx, [custom_w]
    sub cx, 10
    mov dx, [custom_y]
    add dx, [custom_h]
    sub dx, 10
    mov si, 10
    mov di, 10
    call hit_rect
    jnc .done
.resize:
    mov byte [cursor_kind], 5
    mov word [cursor_hotspot_x], 5
    mov word [cursor_hotspot_y], 5
.done:
    ret

open_custom_editor:
    mov byte [menu_open], MENU_NONE
    mov byte [message_open], 0
    mov byte [control_open], 0
    mov byte [debug_open], 0
    mov byte [custom_open], 1
    mov byte [custom_created], 1
    mov byte [custom_minimized], 0
    mov byte [custom_maximized], 0
    mov word [custom_x], CUSTOM_DEFAULT_X
    mov word [custom_y], CUSTOM_DEFAULT_Y
    mov word [custom_w], CUSTOM_DEFAULT_W
    mov word [custom_h], CUSTOM_DEFAULT_H
    mov word [custom_restore_x], CUSTOM_DEFAULT_X
    mov word [custom_restore_y], CUSTOM_DEFAULT_Y
    mov word [custom_restore_w], CUSTOM_DEFAULT_W
    mov word [custom_restore_h], CUSTOM_DEFAULT_H
    mov byte [custom_confirm], 0
    mov byte [custom_exec_dialog], 0
    mov byte [custom_exec_mode], 0
    mov byte [custom_prompt_mode], 0
    mov byte [custom_scroll_drag], 0
    mov byte [custom_resize_drag], 0
    mov byte [custom_mouse_select], 0
    mov byte [custom_undo_valid], 0
    mov byte [custom_redo_valid], 0
    mov dword [custom_hscroll_col], 0
    call custom_enable_a20
    call custom_check_edd
    jc .io_unavailable
    call custom_load
    jnc .loaded
    mov dword [custom_len], 0
    mov dword [custom_cursor], 0
    mov dword [custom_anchor], 0
    mov dword [custom_scroll_line], 0
    mov dword [custom_hscroll_col], 0
    mov byte [custom_dirty], 0
    mov word [custom_status_ptr], str_custom_read_failed
    jmp short .finish
.io_unavailable:
    mov dword [custom_len], 0
    mov dword [custom_cursor], 0
    mov dword [custom_anchor], 0
    mov dword [custom_scroll_line], 0
    mov dword [custom_hscroll_col], 0
    mov byte [custom_dirty], 0
    mov word [custom_status_ptr], str_custom_no_edd
    jmp short .finish
.loaded:
    cmp dword [custom_len], 0
    jne .has_data
    mov word [custom_status_ptr], str_custom_empty
    jmp short .finish
.has_data:
    mov word [custom_status_ptr], str_custom_loaded
.finish:
    call custom_count_lines
    call redraw_all
    ret

custom_enable_a20:
    push ax
    in al, 0x92
    or al, 0x02
    and al, 0xFE
    out 0x92, al
    pop ax
    ret

; Install a 4-GiB hidden limit in GS ("unreal mode").  No stack access occurs
; while CR0.PE is set, and the caller's GDTR is restored before returning.
custom_enable_flat_gs:
    pushf
    push eax
    push edx
    cli
    o32 sgdt [custom_flat_saved_gdtr]
    o32 lgdt [debug_pm_gdtr]
    mov eax, cr0
    mov edx, eax
    or eax, 1
    mov cr0, eax
    mov ax, DEBUG_PM_DATA32_SEL
    mov gs, ax
    mov eax, edx
    and eax, 0xFFFFFFFE
    mov cr0, eax
    o32 lgdt [custom_flat_saved_gdtr]
    pop edx
    pop eax
    popf
    ret

; EDI=source index, returns AL.
custom_get_byte:
    call custom_enable_flat_gs
    mov al, [gs:CUSTOM_BUFFER_PHYS+edi]
    ret

; EDI=source index, returns AL=0 for a machine byte or 1 for an Enter newline.
custom_get_newline:
    call custom_enable_flat_gs
    mov al, [gs:CUSTOM_NEWLINE_PHYS+edi]
    ret

; EDI=source index, AL=value.
custom_set_byte:
    push eax
    call custom_enable_flat_gs
    pop eax
    mov [gs:CUSTOM_BUFFER_PHYS+edi], al
    ret

; Copy the live source into the physical address in EDI.  The editor keeps one
; complete undo image and one complete redo image so every public edit can be
; reverted atomically, including Clear, Paste, Cut, and Replace.
custom_copy_current_to_phys:
    pushad
    mov ebp, edi
    mov edx, CUSTOM_UNDO_NEWLINE_PHYS
    cmp ebp, CUSTOM_UNDO_PHYS
    je .metadata_ready
    mov edx, CUSTOM_REDO_NEWLINE_PHYS
.metadata_ready:
    xor esi, esi
    mov edi, ebp
    mov ecx, [custom_len]
    call custom_enable_flat_gs
.loop:
    test ecx, ecx
    jz .done
    mov al, [gs:CUSTOM_BUFFER_PHYS+esi]
    mov [gs:edi], al
    mov al, [gs:CUSTOM_NEWLINE_PHYS+esi]
    mov [gs:edx], al
    inc esi
    inc edi
    inc edx
    dec ecx
    jmp .loop
.done:
    popad
    ret

; Restore ECX bytes from the physical address in ESI.
custom_copy_phys_to_current:
    pushad
    mov ebp, esi
    mov edx, CUSTOM_UNDO_NEWLINE_PHYS
    cmp ebp, CUSTOM_UNDO_PHYS
    je .metadata_ready
    mov edx, CUSTOM_REDO_NEWLINE_PHYS
.metadata_ready:
    mov esi, ebp
    xor edi, edi
    call custom_enable_flat_gs
.loop:
    test ecx, ecx
    jz .done
    mov al, [gs:esi]
    mov [gs:CUSTOM_BUFFER_PHYS+edi], al
    mov al, [gs:edx]
    mov [gs:CUSTOM_NEWLINE_PHYS+edi], al
    inc esi
    inc edi
    inc edx
    dec ecx
    jmp .loop
.done:
    popad
    ret

custom_snapshot_undo:
    pushad
    mov byte [custom_undo_valid], 0
    mov eax, [custom_len]
    mov [custom_undo_len], eax
    mov eax, [custom_cursor]
    mov [custom_undo_cursor], eax
    mov eax, [custom_anchor]
    mov [custom_undo_anchor], eax
    mov eax, [custom_scroll_line]
    mov [custom_undo_scroll], eax
    mov eax, [custom_hscroll_col]
    mov [custom_undo_hscroll], eax
    mov al, [custom_selection]
    mov [custom_undo_selection], al
    mov al, [custom_dirty]
    mov [custom_undo_dirty], al
    mov edi, CUSTOM_UNDO_PHYS
    call custom_copy_current_to_phys
    mov byte [custom_undo_valid], 1
    popad
    ret

custom_snapshot_redo:
    pushad
    mov byte [custom_redo_valid], 0
    mov eax, [custom_len]
    mov [custom_redo_len], eax
    mov eax, [custom_cursor]
    mov [custom_redo_cursor], eax
    mov eax, [custom_anchor]
    mov [custom_redo_anchor], eax
    mov eax, [custom_scroll_line]
    mov [custom_redo_scroll], eax
    mov eax, [custom_hscroll_col]
    mov [custom_redo_hscroll], eax
    mov al, [custom_selection]
    mov [custom_redo_selection], al
    mov al, [custom_dirty]
    mov [custom_redo_dirty], al
    mov edi, CUSTOM_REDO_PHYS
    call custom_copy_current_to_phys
    mov byte [custom_redo_valid], 1
    popad
    ret

custom_begin_edit:
    call custom_snapshot_undo
    mov byte [custom_redo_valid], 0
    ret

custom_undo:
    cmp byte [custom_undo_valid], 0
    je .done
    call custom_snapshot_redo
    mov ecx, [custom_undo_len]
    mov esi, CUSTOM_UNDO_PHYS
    call custom_copy_phys_to_current
    mov eax, [custom_undo_len]
    mov [custom_len], eax
    mov eax, [custom_undo_cursor]
    mov [custom_cursor], eax
    mov eax, [custom_undo_anchor]
    mov [custom_anchor], eax
    mov eax, [custom_undo_scroll]
    mov [custom_scroll_line], eax
    mov eax, [custom_undo_hscroll]
    mov [custom_hscroll_col], eax
    mov al, [custom_undo_selection]
    mov [custom_selection], al
    mov al, [custom_undo_dirty]
    mov [custom_dirty], al
    mov byte [custom_undo_valid], 0
    mov byte [custom_hex_half], 0
    mov word [custom_status_ptr], str_custom_undone
    call custom_count_lines
    call custom_ensure_cursor_visible
    call redraw_all
.done:
    ret

custom_redo:
    cmp byte [custom_redo_valid], 0
    je .done
    call custom_snapshot_undo
    mov ecx, [custom_redo_len]
    mov esi, CUSTOM_REDO_PHYS
    call custom_copy_phys_to_current
    mov eax, [custom_redo_len]
    mov [custom_len], eax
    mov eax, [custom_redo_cursor]
    mov [custom_cursor], eax
    mov eax, [custom_redo_anchor]
    mov [custom_anchor], eax
    mov eax, [custom_redo_scroll]
    mov [custom_scroll_line], eax
    mov eax, [custom_redo_hscroll]
    mov [custom_hscroll_col], eax
    mov al, [custom_redo_selection]
    mov [custom_selection], al
    mov al, [custom_redo_dirty]
    mov [custom_dirty], al
    mov byte [custom_redo_valid], 0
    mov byte [custom_hex_half], 0
    mov word [custom_status_ptr], str_custom_redone
    call custom_count_lines
    call custom_ensure_cursor_visible
    call redraw_all
.done:
    ret

custom_selection_bounds:
    ; Returns EAX=start and EDX=end (exclusive). CF=0 when nonempty.
    cmp byte [custom_selection], 0
    je .none
    mov eax, [custom_anchor]
    mov edx, [custom_cursor]
    cmp eax, edx
    jbe .ordered
    xchg eax, edx
.ordered:
    cmp eax, edx
    je .none
    clc
    ret
.none:
    stc
    ret

custom_delete_range:
    ; EAX=start, EDX=end exclusive.
    pushad
    mov ebp, eax
    cmp eax, edx
    jae .done
    cmp edx, [custom_len]
    jbe .end_ok
    mov edx, [custom_len]
.end_ok:
    mov ebx, edx
    sub ebx, eax
    mov esi, edx
    mov edi, eax
    mov ecx, [custom_len]
    sub ecx, edx
    call custom_enable_flat_gs
.shift:
    test ecx, ecx
    jz .shifted
    mov al, [gs:CUSTOM_BUFFER_PHYS+esi]
    mov [gs:CUSTOM_BUFFER_PHYS+edi], al
    mov al, [gs:CUSTOM_NEWLINE_PHYS+esi]
    mov [gs:CUSTOM_NEWLINE_PHYS+edi], al
    inc esi
    inc edi
    dec ecx
    jmp .shift
.shifted:
    sub [custom_len], ebx
    mov [custom_cursor], ebp
    mov [custom_anchor], ebp
    mov byte [custom_selection], 0
    mov byte [custom_hex_half], 0
    mov byte [custom_dirty], 1
.done:
    popad
    ret

custom_delete_selection:
    call custom_selection_bounds
    jc .none
    call custom_delete_range
    clc
    ret
.none:
    stc
    ret

custom_insert_byte:
    ; AL=ordinary byte.
    push bx
    xor bh, bh
    call custom_insert_byte_with_kind
    pop bx
    ret

custom_insert_byte_with_kind:
    ; AL=byte, BH=1 only for a real Enter newline. CF=1 when full.
    pushad
    mov bl, al
    call custom_delete_selection
    mov eax, [custom_len]
    cmp eax, CUSTOM_SOURCE_CAPACITY
    jae .full
    call custom_enable_flat_gs
    mov esi, [custom_len]
    mov edi, esi
    inc edi
    mov ecx, esi
    sub ecx, [custom_cursor]
.shift_right:
    test ecx, ecx
    jz .store
    dec esi
    dec edi
    mov al, [gs:CUSTOM_BUFFER_PHYS+esi]
    mov [gs:CUSTOM_BUFFER_PHYS+edi], al
    mov al, [gs:CUSTOM_NEWLINE_PHYS+esi]
    mov [gs:CUSTOM_NEWLINE_PHYS+edi], al
    dec ecx
    jmp .shift_right
.store:
    mov edi, [custom_cursor]
    mov [gs:CUSTOM_BUFFER_PHYS+edi], bl
    mov [gs:CUSTOM_NEWLINE_PHYS+edi], bh
    inc dword [custom_cursor]
    inc dword [custom_len]
    mov eax, [custom_cursor]
    mov [custom_anchor], eax
    mov byte [custom_selection], 0
    mov byte [custom_dirty], 1
    popad
    clc
    ret
.full:
    mov word [custom_status_ptr], str_custom_full
    popad
    stc
    ret

custom_delete_back:
    call custom_selection_bounds
    jnc .edit
    cmp dword [custom_cursor], 0
    je .done
.edit:
    call custom_begin_edit
    call custom_delete_selection
    jnc .changed
    mov eax, [custom_cursor]
    dec eax
    mov edx, [custom_cursor]
    call custom_delete_range
.changed:
    mov byte [custom_hex_half], 0
    call custom_after_edit
.done:
    ret

custom_delete_forward:
    call custom_selection_bounds
    jnc .edit
    mov eax, [custom_cursor]
    cmp eax, [custom_len]
    jae .done
.edit:
    call custom_begin_edit
    call custom_delete_selection
    jnc .changed
    mov edx, eax
    inc edx
    call custom_delete_range
.changed:
    mov byte [custom_hex_half], 0
    call custom_after_edit
.done:
    ret

custom_after_edit:
    mov word [custom_status_ptr], str_custom_ready
    call custom_count_lines
    call custom_ensure_cursor_visible
    call redraw_all
    ret

custom_copy:
    call custom_selection_bounds
    jc .done
    pushad
    mov ecx, edx
    sub ecx, eax
    mov [custom_clip_len], ecx
    mov esi, eax
    xor edi, edi
    call custom_enable_flat_gs
.loop:
    test ecx, ecx
    jz .copied
    mov al, [gs:CUSTOM_BUFFER_PHYS+esi]
    mov [gs:CUSTOM_CLIP_PHYS+edi], al
    mov al, [gs:CUSTOM_NEWLINE_PHYS+esi]
    mov [gs:CUSTOM_CLIP_NEWLINE_PHYS+edi], al
    inc esi
    inc edi
    dec ecx
    jmp .loop
.copied:
    popad
.done:
    ret

custom_cut:
    call custom_copy
    call custom_selection_bounds
    jc .done
    call custom_begin_edit
    call custom_delete_selection
    jc .done
    call custom_after_edit
.done:
    ret

custom_paste:
    cmp dword [custom_clip_len], 0
    jne .begin
    cmp byte [custom_selection], 0
    je .nothing
.begin:
    call custom_begin_edit
    pushad
    call custom_delete_selection
    mov eax, [custom_len]
    add eax, [custom_clip_len]
    cmp eax, CUSTOM_SOURCE_CAPACITY
    ja .full
    mov ecx, [custom_len]
    sub ecx, [custom_cursor]
    mov esi, [custom_len]
    mov edi, esi
    add edi, [custom_clip_len]
    call custom_enable_flat_gs
.shift:
    test ecx, ecx
    jz .copy
    dec esi
    dec edi
    mov al, [gs:CUSTOM_BUFFER_PHYS+esi]
    mov [gs:CUSTOM_BUFFER_PHYS+edi], al
    mov al, [gs:CUSTOM_NEWLINE_PHYS+esi]
    mov [gs:CUSTOM_NEWLINE_PHYS+edi], al
    dec ecx
    jmp .shift
.copy:
    xor esi, esi
    mov edi, [custom_cursor]
    mov ecx, [custom_clip_len]
.copy_loop:
    test ecx, ecx
    jz .done_copy
    mov al, [gs:CUSTOM_CLIP_PHYS+esi]
    mov [gs:CUSTOM_BUFFER_PHYS+edi], al
    mov al, [gs:CUSTOM_CLIP_NEWLINE_PHYS+esi]
    mov [gs:CUSTOM_NEWLINE_PHYS+edi], al
    inc esi
    inc edi
    dec ecx
    jmp .copy_loop
.done_copy:
    mov eax, [custom_clip_len]
    add [custom_len], eax
    add [custom_cursor], eax
    mov eax, [custom_cursor]
    mov [custom_anchor], eax
    mov byte [custom_selection], 0
    mov byte [custom_hex_half], 0
    mov byte [custom_dirty], 1
    popad
    call custom_after_edit
    ret
.full:
    mov word [custom_status_ptr], str_custom_full
    popad
    call redraw_all
    ret
.nothing:
    ret

custom_select_all:
    mov dword [custom_anchor], 0
    mov eax, [custom_len]
    mov [custom_cursor], eax
    test eax, eax
    setnz byte [custom_selection]
    mov byte [custom_hex_half], 0
    call custom_ensure_cursor_visible
    call redraw_all
    ret

custom_count_lines:
    pushad
    mov dword [custom_total_lines], 1
    xor eax, eax                 ; current logical display width
    xor edx, edx                 ; maximum logical display width
    xor ebx, ebx                 ; BL=inside comment, BH=current byte
    xor esi, esi
    mov ecx, [custom_len]
    call custom_enable_flat_gs
.loop:
    test ecx, ecx
    jz .finish_line
    mov bh, [gs:CUSTOM_BUFFER_PHYS+esi]
    cmp byte [gs:CUSTOM_NEWLINE_PHYS+esi], 0
    jne .newline
    test bl, bl
    jnz .comment
    cmp bh, 0x3B
    je .semicolon
    add eax, 3
    jmp short .next
.semicolon:
    add eax, 2
    mov bl, 1
    jmp short .next
.comment:
    inc eax
.next:
    inc esi
    dec ecx
    jmp .loop
.newline:
    cmp eax, edx
    jbe .line_counted
    mov edx, eax
.line_counted:
    xor eax, eax
    xor bl, bl
    inc dword [custom_total_lines]
    jmp short .next
.finish_line:
    cmp eax, edx
    jbe .store
    mov edx, eax
.store:
    mov [custom_max_line_cols], edx
    popad
    call custom_hscroll_clamp
    ret

custom_hscroll_clamp:
    push eax
    push ebx
    mov eax, [custom_max_line_cols]
    movzx ebx, word [custom_view_cols]
    cmp eax, ebx
    jb .zero
    dec ebx
    sub eax, ebx
    cmp [custom_hscroll_col], eax
    jbe .done
    mov [custom_hscroll_col], eax
    jmp short .done
.zero:
    mov dword [custom_hscroll_col], 0
.done:
    pop ebx
    pop eax
    ret

custom_find_line_offset:
    ; EAX=zero-based line, returns EDI=byte offset; CF=1 if beyond EOF.
    push ebx
    push ecx
    push edx
    mov edx, eax
    xor eax, eax
    xor edi, edi
    mov ecx, [custom_len]
    test edx, edx
    jz .found
    call custom_enable_flat_gs
.scan:
    test ecx, ecx
    jz .missing
    cmp byte [gs:CUSTOM_NEWLINE_PHYS+edi], 0
    jne .newline
    inc edi
    dec ecx
    jmp .scan
.newline:
    inc edi
    dec ecx
    inc eax
    cmp eax, edx
    jb .scan
.found:
    pop edx
    pop ecx
    pop ebx
    clc
    ret
.missing:
    pop edx
    pop ecx
    pop ebx
    stc
    ret

custom_line_for_pos:
    ; EDI=position, returns EAX=zero-based line.
    push ebx
    push ecx
    push edi
    xor eax, eax
    mov ecx, edi
    xor edi, edi
    call custom_enable_flat_gs
.scan:
    test ecx, ecx
    jz .done
    cmp byte [gs:CUSTOM_NEWLINE_PHYS+edi], 0
    je .next
    inc eax
.next:
    inc edi
    dec ecx
    jmp .scan
.done:
    pop edi
    pop ecx
    pop ebx
    ret

; EDI=source position, returns EAX=logical display column within its line.
; Machine-code bytes occupy three columns, the semicolon delimiter two, and
; comment characters one.  This is independent of the horizontal viewport.
custom_column_for_pos:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov edx, edi
.back:
    test edi, edi
    jz .line_start
    dec edi
    call custom_get_newline
    test al, al
    jz .back
    inc edi
.line_start:
    mov esi, edi
    mov ecx, edx
    sub ecx, esi
    xor eax, eax
    xor ebx, ebx
    call custom_enable_flat_gs
.scan:
    test ecx, ecx
    jz .done
    mov dl, [gs:CUSTOM_BUFFER_PHYS+esi]
    cmp byte [gs:CUSTOM_NEWLINE_PHYS+esi], 0
    jne .done
    test bl, bl
    jnz .comment
    cmp dl, 0x3B
    je .semicolon
    add eax, 3
    jmp short .next
.semicolon:
    add eax, 2
    mov bl, 1
    jmp short .next
.comment:
    inc eax
.next:
    inc esi
    dec ecx
    jmp .scan
.done:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

custom_ensure_cursor_visible:
    pushad
    mov edi, [custom_cursor]
    call custom_line_for_pos
    mov edx, [custom_scroll_line]
    cmp eax, edx
    jae .check_bottom
    mov [custom_scroll_line], eax
    jmp short .horizontal
.check_bottom:
    movzx ebx, word [custom_view_rows]
    add edx, ebx
    cmp eax, edx
    jb .horizontal
    dec ebx
    sub eax, ebx
    mov [custom_scroll_line], eax
.horizontal:
    mov edi, [custom_cursor]
    call custom_column_for_pos
    mov edx, [custom_hscroll_col]
    cmp eax, edx
    jae .check_right
    mov [custom_hscroll_col], eax
    jmp short .clamp
.check_right:
    movzx ebx, word [custom_view_cols]
    add edx, ebx
    cmp eax, edx
    jb .clamp
    dec ebx
    sub eax, ebx
    mov [custom_hscroll_col], eax
.clamp:
    call custom_hscroll_clamp
    popad
    ret

custom_cursor_in_comment:
    ; Returns AL=1 if a semicolon occurs after the last newline before cursor.
    push ebx
    push ecx
    push edx
    push edi
    mov edi, [custom_cursor]
    cmp byte [custom_selection], 0
    je .position_ready
    mov eax, [custom_anchor]
    cmp eax, edi
    jae .position_ready
    mov edi, eax
.position_ready:
    mov edx, edi
.back:
    test edi, edi
    jz .start
    dec edi
    call custom_get_newline
    test al, al
    jnz .after_newline
    jmp .back
.after_newline:
    inc edi
.start:
    xor ebx, ebx
    mov ecx, edx
    sub ecx, edi
    call custom_enable_flat_gs
.forward:
    test ecx, ecx
    jz .finish
    cmp byte [gs:CUSTOM_BUFFER_PHYS+edi], 0x3B
    jne .next
    mov bl, 1
.next:
    inc edi
    dec ecx
    jmp .forward
.finish:
    mov al, bl
    pop edi
    pop edx
    pop ecx
    pop ebx
    ret

custom_move_left:
    cmp dword [custom_cursor], 0
    je .done
    dec dword [custom_cursor]
    jmp short custom_finish_move
.done:
    ret

custom_move_right:
    mov eax, [custom_cursor]
    cmp eax, [custom_len]
    jae .done
    inc dword [custom_cursor]
    jmp short custom_finish_move
.done:
    ret

custom_line_home:
    pushad
    mov edi, [custom_cursor]
.loop:
    test edi, edi
    jz .set
    dec edi
    call custom_get_newline
    test al, al
    jz .loop
    inc edi
.set:
    mov [custom_cursor], edi
    popad
    jmp short custom_finish_move

custom_line_end:
    pushad
    mov edi, [custom_cursor]
    mov ecx, [custom_len]
    sub ecx, edi
    call custom_enable_flat_gs
.loop:
    test ecx, ecx
    jz .set
    cmp byte [gs:CUSTOM_NEWLINE_PHYS+edi], 0
    jne .set
    inc edi
    dec ecx
    jmp .loop
.set:
    mov [custom_cursor], edi
    popad
    jmp short custom_finish_move

custom_finish_move:
    mov byte [custom_hex_half], 0
    test byte [shift_flags], 0x03
    jnz .selecting
    mov eax, [custom_cursor]
    mov [custom_anchor], eax
    mov byte [custom_selection], 0
    jmp short .visible
.selecting:
    mov eax, [custom_cursor]
    cmp eax, [custom_anchor]
    setne byte [custom_selection]
.visible:
    call custom_ensure_cursor_visible
    call redraw_all
    ret

custom_move_up:
    pushad
    mov edi, [custom_cursor]
    call custom_line_for_pos
    test eax, eax
    jz .done
    mov ebx, eax
    mov eax, ebx
    call custom_find_line_offset
    mov ecx, [custom_cursor]
    sub ecx, edi
    mov eax, ebx
    dec eax
    call custom_find_line_offset
    mov eax, edi
    mov edx, ecx
    mov ecx, [custom_len]
    sub ecx, edi
    call custom_enable_flat_gs
.clamp:
    test edx, edx
    jz .store_eax
    test ecx, ecx
    jz .store_eax
    cmp byte [gs:CUSTOM_NEWLINE_PHYS+eax], 0
    jne .store_eax
    inc eax
    dec edx
    dec ecx
    jmp .clamp
.store_eax:
    mov [custom_cursor], eax
.done:
    popad
    jmp custom_finish_move

custom_move_down:
    pushad
    mov edi, [custom_cursor]
    call custom_line_for_pos
    mov ebx, eax
    mov eax, ebx
    call custom_find_line_offset
    mov ecx, [custom_cursor]
    sub ecx, edi
    mov edx, ecx
    mov eax, ebx
    inc eax
    call custom_find_line_offset
    jc .done
    mov eax, edi
    mov ecx, [custom_len]
    sub ecx, edi
    call custom_enable_flat_gs
.clamp:
    test edx, edx
    jz .store
    test ecx, ecx
    jz .store
    cmp byte [gs:CUSTOM_NEWLINE_PHYS+eax], 0
    jne .store
    inc eax
    dec edx
    dec ecx
    jmp .clamp
.store:
    mov [custom_cursor], eax
.done:
    popad
    jmp custom_finish_move

custom_hex_value:
    ; AL=ASCII, returns AL=0..15 and CF=0, or CF=1.
    cmp al, '0'
    jb .bad
    cmp al, '9'
    jbe .digit
    and al, 0xDF
    cmp al, 'A'
    jb .bad
    cmp al, 'F'
    ja .bad
    sub al, 'A'-10
    clc
    ret
.digit:
    sub al, '0'
    clc
    ret
.bad:
    stc
    ret

custom_type_hex:
    call custom_hex_value
    jc .done
    mov bl, al
    cmp byte [custom_hex_half], 0
    jne .low_nibble
    call custom_begin_edit
    shl bl, 4
    mov al, bl
    call custom_insert_byte
    jc .done
    mov eax, [custom_cursor]
    dec eax
    mov [custom_pending_pos], eax
    mov byte [custom_hex_half], 1
    call custom_after_edit
    ret
.low_nibble:
    mov edi, [custom_pending_pos]
    call custom_get_byte
    and al, 0xF0
    or al, bl
    call custom_set_byte
    mov byte [custom_hex_half], 0
    mov byte [custom_dirty], 1
    call custom_after_edit
.done:
    ret

custom_type_comment:
    ; AL=printable ASCII.
    push ax
    call custom_begin_edit
    pop ax
    call custom_insert_byte
    jc .done
    mov byte [custom_hex_half], 0
    call custom_after_edit
.done:
    ret

custom_insert_newline:
    call custom_begin_edit
    push bx
    mov bh, 1
    mov al, 0x0A
    call custom_insert_byte_with_kind
    pop bx
    jc .done
    mov byte [custom_hex_half], 0
    call custom_after_edit
.done:
    ret

custom_start_prompt:
    ; AL=mode.
    mov [custom_prompt_mode], al
    mov byte [custom_prompt_len], 0
    mov byte [custom_prompt_buf], 0
    mov byte [custom_confirm], 0
    call redraw_all
    ret

custom_prompt_key:
    mov ax, [last_key]
    cmp al, 0x1B
    je .cancel
    cmp al, 0x08
    je .backspace
    cmp al, 0x0D
    je .commit
    cmp byte [custom_prompt_len], CUSTOM_PROMPT_MAX_CHARS
    jae .done
    cmp byte [custom_prompt_mode], 1
    je .decimal
    cmp al, ' '
    je .done
    call custom_hex_value
    jc .done
    call debug_nibble_to_ascii
    jmp short .append
.decimal:
    cmp al, '0'
    jb .done
    cmp al, '9'
    ja .done
.append:
    xor bx, bx
    mov bl, [custom_prompt_len]
    mov [custom_prompt_buf+bx], al
    inc byte [custom_prompt_len]
    inc bx
    mov byte [custom_prompt_buf+bx], 0
    call redraw_all
.done:
    ret
.backspace:
    cmp byte [custom_prompt_len], 0
    je .done
    dec byte [custom_prompt_len]
    xor bx, bx
    mov bl, [custom_prompt_len]
    mov byte [custom_prompt_buf+bx], 0
    call redraw_all
    ret
.cancel:
    mov byte [custom_prompt_mode], 0
    mov word [custom_status_ptr], str_custom_ready
    call redraw_all
    ret
.commit:
    cmp byte [custom_prompt_mode], 1
    je custom_prompt_commit_goto
    cmp byte [custom_prompt_mode], 2
    je custom_prompt_commit_find
    cmp byte [custom_prompt_mode], 3
    je custom_prompt_commit_find_replace
    jmp custom_prompt_commit_replace

custom_prompt_commit_goto:
    xor eax, eax
    xor ebx, ebx
    xor ecx, ecx
    xor esi, esi
    mov cl, [custom_prompt_len]
    test ecx, ecx
    jz custom_prompt_invalid
.parse:
    imul eax, eax, 10
    mov bl, [custom_prompt_buf+si]
    sub bl, '0'
    movzx edx, bl
    add eax, edx
    inc si
    loop .parse
    test eax, eax
    jz custom_prompt_invalid
    dec eax
    call custom_find_line_offset
    jc custom_prompt_invalid
    mov [custom_cursor], edi
    mov [custom_anchor], edi
    mov [custom_scroll_line], eax
    mov dword [custom_hscroll_col], 0
    mov byte [custom_selection], 0
    mov byte [custom_hex_half], 0
    mov byte [custom_prompt_mode], 0
    mov word [custom_status_ptr], str_custom_ready
    call redraw_all
    ret

custom_parse_prompt_hex:
    ; DS:custom_prompt_buf -> DS:DI, stores parsed length in AL. CF=1 invalid.
    push bx
    push cx
    push dx
    xor bx, bx
    xor cx, cx
    mov cl, [custom_prompt_len]
    test cl, 1
    jnz .bad
    test cx, cx
    jz .bad
    shr cx, 1
    cmp cx, 32
    ja .bad
    mov dl, cl
.loop:
    mov al, [custom_prompt_buf+bx]
    call custom_hex_value
    jc .bad
    shl al, 4
    mov ah, al
    inc bx
    mov al, [custom_prompt_buf+bx]
    call custom_hex_value
    jc .bad
    or al, ah
    mov [di], al
    inc di
    inc bx
    loop .loop
    mov al, dl
    pop dx
    pop cx
    pop bx
    clc
    ret
.bad:
    pop dx
    pop cx
    pop bx
    stc
    ret

custom_prompt_commit_find:
    mov di, custom_find_buf
    call custom_parse_prompt_hex
    jc custom_prompt_invalid
    mov [custom_find_len], al
    mov byte [custom_prompt_mode], 0
    call custom_find_next
    ret

custom_prompt_commit_find_replace:
    mov di, custom_find_buf
    call custom_parse_prompt_hex
    jc custom_prompt_invalid
    mov [custom_find_len], al
    mov al, 4
    jmp custom_start_prompt

custom_prompt_commit_replace:
    ; Empty replacement is allowed and deletes the located pattern.
    cmp byte [custom_prompt_len], 0
    je .empty
    mov di, custom_replace_buf
    call custom_parse_prompt_hex
    jc custom_prompt_invalid
    mov [custom_replace_len], al
    jmp short .find
.empty:
    mov byte [custom_replace_len], 0
.find:
    mov byte [custom_prompt_mode], 0
    call custom_find_next_no_draw
    jc .not_found
    call custom_replace_selection
    mov word [custom_status_ptr], str_custom_replaced
    call custom_after_edit
    ret
.not_found:
    mov word [custom_status_ptr], str_custom_not_found
    call redraw_all
    ret

custom_prompt_invalid:
    mov byte [custom_prompt_mode], 0
    mov word [custom_status_ptr], str_custom_bad_input
    call redraw_all
    ret

custom_match_at:
    ; EDI=candidate offset. CF=0 on match.
    pushad
    movzx ecx, byte [custom_find_len]
    mov eax, edi
    add eax, ecx
    cmp eax, [custom_len]
    ja .miss
    xor ebx, ebx
    call custom_enable_flat_gs
.loop:
    test ecx, ecx
    jz .hit
    mov al, [gs:CUSTOM_BUFFER_PHYS+edi]
    cmp byte [gs:CUSTOM_NEWLINE_PHYS+edi], 0
    jne .miss
    cmp al, [custom_find_buf+bx]
    jne .miss
    inc edi
    inc bx
    dec ecx
    jmp .loop
.hit:
    popad
    clc
    ret
.miss:
    popad
    stc
    ret

custom_find_next_no_draw:
    ; Select next occurrence at/after cursor, wrapping once. CF=1 if absent.
    pushad
    mov edi, [custom_cursor]
    mov edx, [custom_len]
.forward:
    cmp edi, edx
    jae .wrap
    call custom_match_at
    jnc .found
    inc edi
    jmp .forward
.wrap:
    xor edi, edi
    mov edx, [custom_cursor]
.wrapped_loop:
    cmp edi, edx
    jae .miss
    call custom_match_at
    jnc .found
    inc edi
    jmp .wrapped_loop
.found:
    mov [custom_anchor], edi
    movzx eax, byte [custom_find_len]
    add eax, edi
    mov [custom_cursor], eax
    mov byte [custom_selection], 1
    popad
    clc
    ret
.miss:
    popad
    stc
    ret

custom_find_next:
    call custom_find_next_no_draw
    jc .miss
    mov word [custom_status_ptr], str_custom_ready
    call custom_ensure_cursor_visible
    call redraw_all
    ret
.miss:
    mov word [custom_status_ptr], str_custom_not_found
    call redraw_all
    ret

custom_replace_selection:
    call custom_begin_edit
    call custom_delete_selection
    xor bx, bx
    movzx cx, byte [custom_replace_len]
.loop:
    test cx, cx
    jz .done
    mov al, [custom_replace_buf+bx]
    call custom_insert_byte
    jc .done
    inc bx
    dec cx
    jmp .loop
.done:
    ret

custom_handle_key:
    cmp byte [custom_exec_dialog], 0
    jne .execute_dialog
    cmp byte [custom_confirm], 0
    jne .confirm
    cmp byte [custom_prompt_mode], 0
    jne custom_prompt_key
    mov ax, [last_key]
    test byte [shift_flags], 0x04
    jz .not_ctrl
    cmp al, 0x13                 ; Ctrl+S
    je .save
    cmp al, 0x11                 ; Ctrl+Q
    je .clear
    cmp al, 0x18                 ; Ctrl+X
    je .cut
    cmp al, 0x03                 ; Ctrl+C
    je .copy
    cmp al, 0x16                 ; Ctrl+V
    je .paste
    cmp al, 0x07                 ; Ctrl+G
    je .goto
    cmp al, 0x06                 ; Ctrl+F
    je .find
    cmp al, 0x08                 ; Ctrl+H
    je .replace
    cmp al, 0x01                 ; Ctrl+A
    je .select_all
    cmp al, 0x1A                 ; Ctrl+Z / Ctrl+Shift+Z
    je .undo_or_redo
    cmp al, 0x19                 ; Ctrl+Y
    je .redo
    ret
.not_ctrl:
    cmp al, 0x1B
    je .close
    cmp ah, 0x4B
    je custom_move_left
    cmp ah, 0x4D
    je custom_move_right
    cmp ah, 0x48
    je custom_move_up
    cmp ah, 0x50
    je custom_move_down
    cmp ah, 0x47
    je custom_line_home
    cmp ah, 0x4F
    je custom_line_end
    cmp ah, 0x49
    je .page_up
    cmp ah, 0x51
    je .page_down
    cmp ah, 0x53
    je .delete
    cmp al, 0x08
    je .backspace
    cmp al, 0x0D
    je custom_insert_newline
    cmp al, ';'
    je .semicolon
    call custom_cursor_in_comment
    test al, al
    jnz .comment
    mov ax, [last_key]
    jmp custom_type_hex
.comment:
    mov ax, [last_key]
    cmp al, 0x20
    jb .done
    cmp al, 0x7E
    ja .done
    jmp custom_type_comment
.semicolon:
    mov al, 0x3B
    jmp custom_type_comment
.save:
    call custom_save
    ret
.clear:
    mov byte [custom_confirm], 2
    call redraw_all
    ret
.cut:
    call custom_cut
    ret
.copy:
    call custom_copy
    call redraw_all
    ret
.paste:
    call custom_paste
    ret
.goto:
    mov al, 1
    jmp custom_start_prompt
.find:
    mov al, 2
    jmp custom_start_prompt
.replace:
    mov al, 3
    jmp custom_start_prompt
.select_all:
    jmp custom_select_all
.undo_or_redo:
    test byte [shift_flags], 0x03
    jnz .redo
    call custom_undo
    ret
.redo:
    call custom_redo
    ret
.close:
    call custom_request_close
    ret
.page_up:
    call custom_scroll_page_up
    ret
.page_down:
    call custom_scroll_page_down
    ret
.delete:
    call custom_delete_forward
    ret
.backspace:
    call custom_delete_back
    ret
.execute_dialog:
    mov ax, [last_key]
    cmp al, 0x1B
    je .cancel_execute_dialog
    cmp al, '1'
    je custom_select_execute_real
    cmp al, '2'
    je custom_select_execute_pm
    cmp al, '3'
    je custom_select_execute_lm
    ret
.cancel_execute_dialog:
    mov byte [custom_exec_dialog], 0
    call redraw_all
    ret
.confirm:
    mov ax, [last_key]
    cmp al, 'y'
    je custom_confirm_yes
    cmp al, 'Y'
    je custom_confirm_yes
    cmp al, 'n'
    je .confirm_no
    cmp al, 'N'
    je .confirm_no
    cmp al, 'c'
    je .confirm_cancel
    cmp al, 'C'
    je .confirm_cancel
    cmp al, 0x1B
    je .confirm_cancel
    ret
.confirm_no:
    call custom_confirm_no
    ret
.confirm_cancel:
    call custom_confirm_cancel
.done:
    ret

custom_check_edd:
    pushad
    push ds
    push es
    xor ax, ax
    mov ds, ax
    mov byte [custom_edd_available], 0
    mov ah, 0x41
    mov bx, 0x55AA
    mov dl, [os_boot_drive]
    int 0x13
    jc .done
    cmp bx, 0xAA55
    jne .done
    test cx, 1
    jz .done
    mov byte [custom_edd_available], 1
.done:
    pop es
    pop ds
    popad
    cmp byte [custom_edd_available], 1
    jne .failed
    clc
    ret
.failed:
    stc
    ret

custom_build_dap:
    ; EAX=LBA, BX=buffer segment.
    mov byte [custom_dap+0], 0x10
    mov byte [custom_dap+1], 0
    mov word [custom_dap+2], 1
    mov word [custom_dap+4], 0
    mov word [custom_dap+6], bx
    mov [custom_dap+8], eax
    mov dword [custom_dap+12], 0
    ret

custom_disk_read_sector:
    ; EAX=LBA, reads to BOOT_SETTING_IO_SEG:0000.
    mov [custom_io_lba], eax
    mov byte [custom_io_result], 1
    mov byte [custom_io_status], 0
    pushad
    push ds
    push es
    xor ax, ax
    mov ds, ax
    mov byte [custom_io_retry], 3
.retry:
    mov eax, [custom_io_lba]
    mov bx, BOOT_SETTING_IO_SEG
    call custom_build_dap
    mov si, custom_dap
    mov dl, [os_boot_drive]
    mov ah, 0x42
    int 0x13
    jnc .ok
    xor bx, bx
    mov ds, bx
    mov [custom_io_status], ah
    xor ah, ah
    mov dl, [os_boot_drive]
    int 0x13
    xor bx, bx
    mov ds, bx
    dec byte [custom_io_retry]
    jnz .retry
    jmp short .done
.ok:
    xor ax, ax
    mov ds, ax
    mov byte [custom_io_result], 0
.done:
    pop es
    pop ds
    popad
    cmp byte [custom_io_result], 0
    jne .failed
    clc
    ret
.failed:
    stc
    ret

custom_disk_write_sector:
    ; EAX=LBA, writes BOOT_SETTING_IO_SEG:0000.
    mov [custom_io_lba], eax
    mov byte [custom_io_result], 1
    mov byte [custom_io_status], 0
    pushad
    push ds
    push es
    xor ax, ax
    mov ds, ax
    mov byte [custom_io_retry], 3
.retry:
    mov eax, [custom_io_lba]
    mov bx, BOOT_SETTING_IO_SEG
    call custom_build_dap
    mov si, custom_dap
    mov dl, [os_boot_drive]
    mov ax, 0x4300
    int 0x13
    jnc .ok
    xor bx, bx
    mov ds, bx
    mov [custom_io_status], ah
    xor ah, ah
    mov dl, [os_boot_drive]
    int 0x13
    xor bx, bx
    mov ds, bx
    dec byte [custom_io_retry]
    jnz .retry
    jmp short .done
.ok:
    xor ax, ax
    mov ds, ax
    mov byte [custom_io_result], 0
.done:
    pop es
    pop ds
    popad
    cmp byte [custom_io_result], 0
    jne .failed
    clc
    ret
.failed:
    stc
    ret

custom_load:
    pushad
    push es
    mov dword [custom_len], 0
    mov dword [custom_cursor], 0
    mov dword [custom_anchor], 0
    mov dword [custom_scroll_line], 0
    mov dword [custom_hscroll_col], 0
    mov byte [custom_selection], 0
    mov byte [custom_hex_half], 0
    mov byte [custom_dirty], 0
    mov byte [custom_terminated], 0

    ; Read the source header first. In v22-fix3 it is the exact source length,
    ; including Enter newlines. A matching NLF3 metadata header selects the new
    ; format; otherwise the old non-newline-count format is imported once.
    mov eax, CUSTOM_SOURCE_FIRST_LBA
    call custom_disk_read_sector
    jc .read_fail
    mov ax, BOOT_SETTING_IO_SEG
    mov es, ax
    movzx eax, byte es:[0]
    shl eax, 16
    movzx ebx, byte es:[1]
    shl ebx, 8
    or eax, ebx
    movzx ebx, byte es:[2]
    or eax, ebx
    cmp eax, CUSTOM_SOURCE_CAPACITY
    ja .bad_header
    mov [custom_load_remaining], eax

    mov eax, CUSTOM_NEWLINE_FIRST_LBA
    call custom_disk_read_sector
    jc .legacy_format
    mov ax, BOOT_SETTING_IO_SEG
    mov es, ax
    cmp dword es:[0], CUSTOM_NEWLINE_MAGIC
    jne .legacy_format
    movzx edx, byte es:[4]
    shl edx, 16
    movzx ebx, byte es:[5]
    shl ebx, 8
    or edx, ebx
    movzx ebx, byte es:[6]
    or edx, ebx
    cmp edx, [custom_load_remaining]
    jne .legacy_format

    ; New format: copy exactly the header length. Byte value 0Ah has no
    ; structural meaning until its parallel metadata flag is loaded.
    mov dword [custom_io_current_lba], CUSTOM_SOURCE_FIRST_LBA
    mov word [custom_io_offset], 3
.new_source_sector:
    cmp dword [custom_load_remaining], 0
    je .new_metadata_start
    mov eax, [custom_io_current_lba]
    cmp eax, CUSTOM_SOURCE_LAST_LBA
    ja .bad_header
    call custom_disk_read_sector
    jc .read_fail
    mov ax, BOOT_SETTING_IO_SEG
    mov es, ax
    call custom_enable_flat_gs
.new_source_byte:
    cmp dword [custom_load_remaining], 0
    je .new_metadata_start
    cmp word [custom_io_offset], 512
    jae .new_source_next
    mov bx, [custom_io_offset]
    mov al, es:[bx]
    mov edi, [custom_len]
    mov [gs:CUSTOM_BUFFER_PHYS+edi], al
    inc dword [custom_len]
    inc word [custom_io_offset]
    dec dword [custom_load_remaining]
    jmp .new_source_byte
.new_source_next:
    inc dword [custom_io_current_lba]
    mov word [custom_io_offset], 0
    jmp .new_source_sector

.new_metadata_start:
    mov eax, [custom_len]
    mov [custom_load_remaining], eax
    mov dword [custom_io_pos], 0
    mov dword [custom_io_current_lba], CUSTOM_NEWLINE_FIRST_LBA
    mov word [custom_io_offset], CUSTOM_NEWLINE_HEADER_SIZE
.new_metadata_sector:
    cmp dword [custom_load_remaining], 0
    je .loaded
    mov eax, [custom_io_current_lba]
    cmp eax, CUSTOM_NEWLINE_LAST_LBA
    ja .bad_header
    call custom_disk_read_sector
    jc .read_fail
    mov ax, BOOT_SETTING_IO_SEG
    mov es, ax
    call custom_enable_flat_gs
.new_metadata_byte:
    cmp dword [custom_load_remaining], 0
    je .loaded
    cmp word [custom_io_offset], 512
    jae .new_metadata_next
    mov bx, [custom_io_offset]
    mov al, es:[bx]
    cmp al, 1
    ja .bad_header
    mov edi, [custom_io_pos]
    test al, al
    jz .store_metadata
    cmp byte [gs:CUSTOM_BUFFER_PHYS+edi], 0x0A
    jne .bad_header
.store_metadata:
    mov [gs:CUSTOM_NEWLINE_PHYS+edi], al
    inc dword [custom_io_pos]
    inc word [custom_io_offset]
    dec dword [custom_load_remaining]
    jmp .new_metadata_byte
.new_metadata_next:
    inc dword [custom_io_current_lba]
    mov word [custom_io_offset], 0
    jmp .new_metadata_sector

.legacy_format:
    ; v22-fix2 stored only a non-newline count. Re-read the first source sector
    ; and derive newline flags from byte value 0Ah for backward compatibility.
    mov dword [custom_len], 0
    mov dword [custom_io_current_lba], CUSTOM_SOURCE_FIRST_LBA
    mov word [custom_io_offset], 3
    mov eax, CUSTOM_SOURCE_FIRST_LBA
    call custom_disk_read_sector
    jc .read_fail
    mov ax, BOOT_SETTING_IO_SEG
    mov es, ax
.legacy_sector_loop:
    mov eax, [custom_io_current_lba]
    cmp eax, CUSTOM_SOURCE_FIRST_LBA
    je .legacy_sector_ready
    cmp eax, CUSTOM_SOURCE_LAST_LBA
    ja .legacy_boundary
    call custom_disk_read_sector
    jc .read_fail
    mov ax, BOOT_SETTING_IO_SEG
    mov es, ax
    mov word [custom_io_offset], 0
.legacy_sector_ready:
    call custom_enable_flat_gs
.legacy_byte_loop:
    cmp word [custom_io_offset], 512
    jae .legacy_next_sector
    cmp dword [custom_load_remaining], 0
    jne .legacy_payload
    mov bx, [custom_io_offset]
    cmp byte es:[bx], 0
    je .loaded
    cmp byte es:[bx], 0x0A
    jne .repair_terminator
    cmp dword [custom_len], CUSTOM_SOURCE_CAPACITY
    jae .legacy_boundary
    mov edi, [custom_len]
    mov byte [gs:CUSTOM_BUFFER_PHYS+edi], 0x0A
    mov byte [gs:CUSTOM_NEWLINE_PHYS+edi], 1
    inc dword [custom_len]
    inc word [custom_io_offset]
    jmp .legacy_byte_loop
.repair_terminator:
    ; Header length is authoritative.  Repair a missing terminator in place
    ; immediately, preserving the remainder of the sector.
    mov byte es:[bx], 0
    mov eax, [custom_io_current_lba]
    call custom_disk_write_sector
    jc .read_fail
    jmp short .loaded
.legacy_payload:
    cmp dword [custom_len], CUSTOM_SOURCE_CAPACITY
    jae .legacy_boundary
    mov bx, [custom_io_offset]
    mov al, es:[bx]
    mov edi, [custom_len]
    mov [gs:CUSTOM_BUFFER_PHYS+edi], al
    mov byte [gs:CUSTOM_NEWLINE_PHYS+edi], 0
    inc dword [custom_len]
    inc word [custom_io_offset]
    cmp al, 0x0A
    jne .legacy_machine_byte
    mov byte [gs:CUSTOM_NEWLINE_PHYS+edi], 1
    jmp .legacy_byte_loop
.legacy_machine_byte:
    dec dword [custom_load_remaining]
    jmp .legacy_byte_loop
.legacy_next_sector:
    inc dword [custom_io_current_lba]
    jmp .legacy_sector_loop
.legacy_boundary:
    cmp dword [custom_load_remaining], 0
    jne .bad_header
    ; The NLF3 length header is authoritative for a completely full payload;
    ; no marker sector outside LBA 500..1500 is used.
    jmp short .loaded
.loaded:
    mov eax, [custom_len]
    mov [custom_cursor], eax
    mov [custom_anchor], eax
    pop es
    popad
    clc
    ret
.bad_header:
    mov word [custom_status_ptr], str_custom_bad_header
    jmp short .failed
.read_fail:
    mov word [custom_status_ptr], str_custom_read_failed
.failed:
    pop es
    popad
    stc
    ret

custom_clear_io_buffer:
    push ax
    push cx
    push di
    push es
    mov ax, BOOT_SETTING_IO_SEG
    mov es, ax
    xor di, di
    xor ax, ax
    mov cx, 256
    rep stosw
    pop es
    pop di
    pop cx
    pop ax
    ret

custom_save_newline_metadata:
    ; Persist an NLF3 header followed by one flag byte per source byte. Write
    ; this stream before changing the source header so an interrupted save
    ; falls back to the legacy importer instead of mixing the two formats.
    pushad
    push es
    mov dword [custom_io_pos], 0
    mov dword [custom_io_current_lba], CUSTOM_NEWLINE_FIRST_LBA
    mov byte [custom_terminated], 0
.sector_loop:
    call custom_clear_io_buffer
    mov ax, BOOT_SETTING_IO_SEG
    mov es, ax
    mov word [custom_io_offset], 0
    cmp dword [custom_io_current_lba], CUSTOM_NEWLINE_FIRST_LBA
    jne .payload
    mov dword es:[0], CUSTOM_NEWLINE_MAGIC
    mov eax, [custom_len]
    mov ebx, eax
    shr eax, 16
    mov es:[4], al
    mov eax, ebx
    shr eax, 8
    mov es:[5], al
    mov es:[6], bl
    mov word [custom_io_offset], CUSTOM_NEWLINE_HEADER_SIZE
.payload:
    call custom_enable_flat_gs
.fill:
    cmp word [custom_io_offset], 512
    jae .write
    mov edi, [custom_io_pos]
    cmp edi, [custom_len]
    jae .complete
    mov al, [gs:CUSTOM_NEWLINE_PHYS+edi]
    and al, 1
    mov bx, [custom_io_offset]
    mov es:[bx], al
    inc dword [custom_io_pos]
    inc word [custom_io_offset]
    jmp .fill
.complete:
    mov byte [custom_terminated], 1
.write:
    mov eax, [custom_io_current_lba]
    call custom_disk_write_sector
    jc .failed
    cmp byte [custom_terminated], 1
    je .saved
    inc dword [custom_io_current_lba]
    cmp dword [custom_io_current_lba], CUSTOM_NEWLINE_LAST_LBA
    jbe .sector_loop
    jmp short .failed
.saved:
    pop es
    popad
    clc
    ret
.failed:
    pop es
    popad
    stc
    ret

custom_save:
    call custom_check_edd
    jc .no_edd
    pushad
    push es
    call custom_save_newline_metadata
    jc .write_failed_pop
    mov dword [custom_io_pos], 0
    mov dword [custom_io_current_lba], CUSTOM_SOURCE_FIRST_LBA
    mov byte [custom_terminated], 0

.sector_loop:
    call custom_clear_io_buffer
    mov ax, BOOT_SETTING_IO_SEG
    mov es, ax
    mov word [custom_io_offset], 0
    cmp dword [custom_io_current_lba], CUSTOM_SOURCE_FIRST_LBA
    jne .payload
    ; The source header is now the exact stored-byte count. Execution subtracts
    ; only metadata-marked newlines and comment bytes from this value.
    mov eax, [custom_len]
    mov ebx, eax
    shr eax, 16
    mov es:[0], al
    mov eax, ebx
    shr eax, 8
    mov es:[1], al
    mov es:[2], bl
    mov word [custom_io_offset], 3
.payload:
    call custom_enable_flat_gs
.fill:
    cmp word [custom_io_offset], 512
    jae .write
    mov edi, [custom_io_pos]
    cmp edi, [custom_len]
    jae .place_terminator
    mov al, [gs:CUSTOM_BUFFER_PHYS+edi]
    mov bx, [custom_io_offset]
    mov es:[bx], al
    inc dword [custom_io_pos]
    inc word [custom_io_offset]
    jmp .fill
.place_terminator:
    cmp dword [custom_len], CUSTOM_SOURCE_CAPACITY
    jae .write
    mov bx, [custom_io_offset]
    mov byte es:[bx], 0
    mov byte [custom_terminated], 1
.write:
    mov eax, [custom_io_current_lba]
    call custom_disk_write_sector
    jc .write_failed_pop
    cmp byte [custom_terminated], 1
    je .saved_pop
    mov eax, [custom_io_pos]
    cmp eax, [custom_len]
    jb .next
    cmp dword [custom_len], CUSTOM_SOURCE_CAPACITY
    je .full_marker
.next:
    inc dword [custom_io_current_lba]
    cmp dword [custom_io_current_lba], CUSTOM_SOURCE_LAST_LBA
    jbe .sector_loop
    jmp short .full_marker

.full_marker:
    ; A full source range has no terminator byte. The already-written NLF3
    ; metadata header carries the exact length, so the save is complete.
    jmp short .saved_pop
.saved_pop:
    pop es
    popad
    mov byte [custom_dirty], 0
    cmp byte [custom_undo_valid], 0
    je .no_undo_snapshot
    mov byte [custom_undo_dirty], 1
.no_undo_snapshot:
    cmp byte [custom_redo_valid], 0
    je .snapshots_updated
    mov byte [custom_redo_dirty], 1
.snapshots_updated:
    mov word [custom_status_ptr], str_custom_saved
    cmp byte [custom_save_close], 0
    je .redraw
    mov byte [custom_save_close], 0
    mov byte [custom_open], 0
    mov byte [custom_created], 0
    mov byte [custom_minimized], 0
    mov al, WIN_CUSTOM
    call custom_proxy_task_remove
.redraw:
    call redraw_all
    clc
    ret
.write_failed_pop:
    pop es
    popad
    mov word [custom_status_ptr], str_custom_write_failed
    mov byte [custom_save_close], 0
    call redraw_all
    stc
    ret
.no_edd:
    mov word [custom_status_ptr], str_custom_no_edd
    mov byte [custom_save_close], 0
    call redraw_all
    stc
    ret

custom_request_close:
    cmp byte [custom_dirty], 0
    je .close
    mov byte [custom_confirm], 1
    call redraw_all
    ret
.close:
    mov byte [custom_open], 0
    mov byte [custom_created], 0
    mov byte [custom_minimized], 0
    mov byte [custom_confirm], 0
    mov al, WIN_CUSTOM
    call custom_proxy_task_remove
    call redraw_all
    ret

custom_confirm_yes:
    cmp byte [custom_confirm], 2
    je .clear
    mov byte [custom_confirm], 0
    mov byte [custom_save_close], 1
    call custom_save
    ret
.clear:
    call custom_begin_edit
    mov dword [custom_len], 0
    mov dword [custom_cursor], 0
    mov dword [custom_anchor], 0
    mov dword [custom_scroll_line], 0
    mov dword [custom_hscroll_col], 0
    mov dword [custom_total_lines], 1
    mov byte [custom_selection], 0
    mov byte [custom_hex_half], 0
    mov byte [custom_confirm], 0
    mov byte [custom_dirty], 1
    mov word [custom_status_ptr], str_custom_ready
    call redraw_all
    ret

custom_confirm_no:
    cmp byte [custom_confirm], 1
    jne .cancel
    mov byte [custom_open], 0
    mov byte [custom_created], 0
    mov byte [custom_minimized], 0
    mov al, WIN_CUSTOM
    call custom_proxy_task_remove
.cancel:
    mov byte [custom_confirm], 0
    call redraw_all
    ret

custom_confirm_cancel:
    mov byte [custom_confirm], 0
    mov byte [custom_save_close], 0
    call redraw_all
    ret

custom_request_execute:
    mov byte [custom_exec_dialog], 1
    call redraw_all
    ret

custom_select_execute_real:
    xor al, al
    jmp short custom_select_execute_mode

custom_select_execute_pm:
    mov al, 1
    jmp short custom_select_execute_mode

custom_select_execute_lm:
    mov al, 2

custom_select_execute_mode:
    mov [custom_exec_mode], al
    mov byte [custom_exec_dialog], 0
    cmp al, 2
    jne .execute
    call custom_proxy_check_long_mode
    jnc .execute
    mov word [custom_status_ptr], str_custom_exec_no_long
    call redraw_all
    ret
.execute:
    call custom_execute
    ret

custom_execute:
    cmp dword [custom_len], 0
    je .empty
    cmp byte [custom_dirty], 0
    je .read_header
    call custom_save
    jc .done
.read_header:
    ; LBA 500 bytes 0..2 are the big-endian count of every stored source byte.
    ; Subtract only metadata-marked Enter newlines and comment bytes while
    ; compacting, so a machine opcode 0Ah remains executable.
    mov eax, CUSTOM_SOURCE_FIRST_LBA
    call custom_disk_read_sector
    jc .read_failed
    push es
    mov ax, BOOT_SETTING_IO_SEG
    mov es, ax
    movzx eax, byte es:[0]
    shl eax, 16
    movzx ebx, byte es:[1]
    shl ebx, 8
    or eax, ebx
    movzx ebx, byte es:[2]
    or eax, ebx
    mov [custom_exec_len], eax
    pop es

    pushad
    push es
    xor edi, edi
    xor esi, esi
    mov ecx, [custom_len]
    xor ebx, ebx                 ; BL=inside comment
    call custom_enable_flat_gs
.transform:
    test ecx, ecx
    jz .transformed
    mov al, [gs:CUSTOM_BUFFER_PHYS+esi]
    cmp byte [gs:CUSTOM_NEWLINE_PHYS+esi], 0
    jne .structural_newline
    test bl, bl
    jnz .comment
    cmp al, 0x3B
    je .start_comment
    cmp edi, CUSTOM_EXEC_MAX-CUSTOM_EXEC_RETURN_SIZE
    jae .too_large_pop
    jmp short .store
.structural_newline:
    cmp dword [custom_exec_len], 0
    je .length_mismatch_pop
    dec dword [custom_exec_len]
    xor bl, bl
    jmp short .skip
.start_comment:
    mov bl, 1
    cmp dword [custom_exec_len], 0
    je .length_mismatch_pop
    dec dword [custom_exec_len]
    jmp short .skip
.comment:
    cmp dword [custom_exec_len], 0
    je .length_mismatch_pop
    dec dword [custom_exec_len]
    jmp short .skip
.skip:
    inc esi
    dec ecx
    jmp .transform
.store:
    mov [gs:CUSTOM_EXEC_PHYS+edi], al
    inc esi
    inc edi
    dec ecx
    jmp .transform
.transformed:
    cmp edi, [custom_exec_len]
    jne .length_mismatch_pop
    test edi, edi
    jz .empty_pop

    ; Real Mode has no caller frame, so fall-through uses the original far
    ; return trampoline. Protected/Long Mode use a relative jump to a mode exit
    ; stub; an explicit RET returns through the CALL made by the mode entry.
    cmp byte [custom_exec_mode], 0
    jne .append_mode_jump
    mov byte [gs:CUSTOM_EXEC_PHYS+edi], 0xEA
    inc edi
    mov word [gs:CUSTOM_EXEC_PHYS+edi], custom_stage2_ext_return_exec-stage2_ext_start
    add edi, 2
    mov word [gs:CUSTOM_EXEC_PHYS+edi], STAGE2_EXT_SEG
    add edi, 2
    jmp short .trailer_ready
.append_mode_jump:
    mov byte [gs:CUSTOM_EXEC_PHYS+edi], 0xE9
    inc edi
    mov eax, debug_pm_custom_return32
    cmp byte [custom_exec_mode], 1
    je .mode_target_ready
    mov eax, debug_lm_custom_return64
.mode_target_ready:
    sub eax, CUSTOM_EXEC_LINEAR
    sub eax, edi
    sub eax, 4
    mov dword [gs:CUSTOM_EXEC_PHYS+edi], eax
    add edi, 4
.trailer_ready:
    mov [custom_exec_stage_len], edi
    mov dword [custom_io_pos], 0
    mov dword [custom_io_current_lba], CUSTOM_EXEC_FIRST_LBA

.write_sector:
    call custom_clear_io_buffer
    mov ax, BOOT_SETTING_IO_SEG
    mov es, ax
    xor bx, bx
    call custom_enable_flat_gs
.copy_to_io:
    cmp bx, 512
    jae .write_lba
    mov eax, [custom_io_pos]
    cmp eax, [custom_exec_stage_len]
    jae .write_lba
    mov esi, [custom_io_pos]
    mov al, [gs:CUSTOM_EXEC_PHYS+esi]
    mov es:[bx], al
    inc dword [custom_io_pos]
    inc bx
    jmp .copy_to_io
.write_lba:
    mov eax, [custom_io_current_lba]
    call custom_disk_write_sector
    jc .exec_write_fail
    mov eax, [custom_io_pos]
    cmp eax, [custom_exec_stage_len]
    jae .reload_setup
    inc dword [custom_io_current_lba]
    jmp .write_sector

.reload_setup:
    pop es
    popad
    jmp STAGE2_EXT_SEG:(custom_stage2_ext_launch_exec-stage2_ext_start)

.exec_write_fail:
    pop es
    popad
    mov word [custom_status_ptr], str_custom_exec_write
    call redraw_all
    ret
.length_mismatch_pop:
    pop es
    popad
    mov word [custom_status_ptr], str_custom_exec_length
    call redraw_all
    ret
.empty_pop:
    pop es
    popad
    jmp short .empty
.too_large_pop:
    pop es
    popad
    jmp short .too_large
.read_failed:
    mov word [custom_status_ptr], str_custom_exec_read
    call redraw_all
    ret
.empty:
    mov word [custom_status_ptr], str_custom_exec_empty
    call redraw_all
    ret
.too_large:
    mov word [custom_status_ptr], str_custom_exec_too_large
    call redraw_all
.done:
    ret

custom_compute_layout:
    push ax
    push bx
    push dx
    mov ax, [custom_x]
    add ax, 4
    mov [custom_editor_x], ax
    mov ax, [custom_y]
    add ax, 40
    mov [custom_editor_y], ax
    mov ax, [custom_w]
    sub ax, 28
    mov [custom_editor_w], ax
    mov bx, ax
    sub bx, 2
    shr bx, 3
    sub bx, CUSTOM_LINE_NO_COLS
    cmp bx, 12
    jae .cols_ok
    mov bx, 12
.cols_ok:
    mov [custom_view_cols], bx
    add bx, CUSTOM_LINE_NO_COLS
    mov [custom_total_text_cols], bx
    mov ax, [custom_h]
    sub ax, 88
    xor dx, dx
    mov bx, CUSTOM_ROW_H
    div bx
    cmp ax, 4
    jae .rows_min_ok
    mov ax, 4
.rows_min_ok:
    cmp ax, CUSTOM_MAX_VIEW_ROWS
    jbe .rows_ok
    mov ax, CUSTOM_MAX_VIEW_ROWS
.rows_ok:
    mov [custom_view_rows], ax
    mov bx, CUSTOM_ROW_H
    mul bx
    mov [custom_editor_h], ax
    mov ax, [custom_x]
    add ax, [custom_w]
    sub ax, 20
    mov [custom_scroll_x], ax
    mov ax, [custom_editor_y]
    add ax, 14
    mov [custom_scroll_track_y], ax
    mov ax, [custom_editor_h]
    sub ax, 28
    mov [custom_scroll_track_h], ax
    sub ax, CUSTOM_SCROLL_THUMB_H
    mov [custom_scroll_travel], ax
    mov ax, [custom_editor_y]
    add ax, [custom_editor_h]
    inc ax
    mov [custom_hscroll_y], ax
    mov ax, [custom_editor_x]
    mov [custom_hscroll_left_x], ax
    add ax, [custom_editor_w]
    sub ax, 14
    mov [custom_hscroll_right_x], ax
    mov ax, [custom_hscroll_left_x]
    add ax, 14
    mov [custom_hscroll_track_x], ax
    mov ax, [custom_editor_w]
    sub ax, 28
    mov [custom_hscroll_track_w], ax
    sub ax, CUSTOM_HSCROLL_THUMB_W
    mov [custom_hscroll_travel], ax
    mov ax, [custom_x]
    add ax, 134
    mov [custom_prompt_input_x], ax
    mov ax, [custom_hscroll_y]
    add ax, 15
    mov [custom_status_y], ax
    mov ax, [custom_y]
    add ax, [custom_h]
    sub ax, 24
    mov [custom_action_y], ax
    pop dx
    pop bx
    pop ax
    ret

custom_minimize:
    mov byte [custom_open], 0
    mov byte [custom_minimized], 1
    mov byte [custom_resize_drag], 0
    mov byte [custom_scroll_drag], 0
    call redraw_all
    ret

custom_toggle_maximize:
    cmp byte [custom_maximized], 0
    jne .restore
    mov ax, [custom_x]
    mov [custom_restore_x], ax
    mov ax, [custom_y]
    mov [custom_restore_y], ax
    mov ax, [custom_w]
    mov [custom_restore_w], ax
    mov ax, [custom_h]
    mov [custom_restore_h], ax
    mov word [custom_x], 0
    mov word [custom_y], 0
    mov word [custom_w], SCREEN_W
    mov word [custom_h], TASKBAR_Y
    mov byte [custom_maximized], 1
    jmp short .changed
.restore:
    mov ax, [custom_restore_x]
    mov [custom_x], ax
    mov ax, [custom_restore_y]
    mov [custom_y], ax
    mov ax, [custom_restore_w]
    mov [custom_w], ax
    mov ax, [custom_restore_h]
    mov [custom_h], ax
    mov byte [custom_maximized], 0
.changed:
    mov byte [custom_resize_drag], 0
    call custom_compute_layout
    call custom_count_lines
    call custom_scroll_clamp
    call custom_hscroll_clamp
    call redraw_all
    ret

custom_update_resize_drag:
    push ax
    push bx
    mov ax, [mouse_x]
    sub ax, [custom_resize_start_x]
    add ax, [custom_resize_start_w]
    cmp ax, CUSTOM_MIN_W
    jae .width_min_ok
    mov ax, CUSTOM_MIN_W
.width_min_ok:
    mov bx, SCREEN_W
    sub bx, [custom_x]
    cmp ax, bx
    jbe .width_ok
    mov ax, bx
.width_ok:
    mov [custom_w], ax
    mov ax, [mouse_y]
    sub ax, [custom_resize_start_y]
    add ax, [custom_resize_start_h]
    cmp ax, CUSTOM_MIN_H
    jae .height_min_ok
    mov ax, CUSTOM_MIN_H
.height_min_ok:
    mov bx, TASKBAR_Y
    sub bx, [custom_y]
    cmp ax, bx
    jbe .height_ok
    mov ax, bx
.height_ok:
    mov [custom_h], ax
    call custom_compute_layout
    call custom_count_lines
    call custom_scroll_clamp
    call custom_hscroll_clamp
    pop bx
    pop ax
    call redraw_all
    ret

draw_custom_editor:
    call custom_compute_layout
    mov ax, [custom_x]
    mov bx, [custom_y]
    mov cx, [custom_w]
    mov dx, [custom_h]
    call draw_bevel_box
    call draw_frame_black

    mov ax, [custom_x]
    add ax, 3
    mov bx, [custom_y]
    add bx, 3
    mov cx, [custom_w]
    sub cx, 6
    mov dx, TITLE_H
    mov si, COL_BLUE
    call fill_rect
    mov si, str_custom_title
    mov cx, [custom_x]
    add cx, 8
    mov dx, [custom_y]
    add dx, 8
    mov bl, COL_WHITE
    call draw_text
    mov ax, [custom_x]
    add ax, [custom_w]
    sub ax, 21
    mov bx, [custom_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_close
    call draw_button
    sub ax, 19
    mov si, str_max
    cmp byte [custom_maximized], 0
    je .max_label_ready
    mov si, str_restore
.max_label_ready:
    call draw_button
    sub ax, 19
    mov si, str_min
    call draw_button

    mov ax, [custom_x]
    add ax, 3
    mov bx, [custom_y]
    add bx, 22
    mov cx, [custom_w]
    sub cx, 6
    mov dx, MENU_H
    mov si, COL_GRAY
    call fill_rect
    mov si, str_custom_file
    mov cx, [custom_x]
    add cx, 6
    mov dx, [custom_y]
    add dx, 25
    mov bl, COL_BLACK
    call draw_text
    mov si, str_custom_edit
    mov cx, [custom_x]
    add cx, 46
    mov dx, [custom_y]
    add dx, 25
    mov bl, COL_BLACK
    call draw_text
    mov si, str_custom_search
    mov cx, [custom_x]
    add cx, 86
    mov dx, [custom_y]
    add dx, 25
    mov bl, COL_BLACK
    call draw_text
    mov si, str_custom_go
    mov cx, [custom_x]
    add cx, 142
    mov dx, [custom_y]
    add dx, 25
    mov bl, COL_BLACK
    call draw_text

    mov ax, [custom_editor_x]
    mov bx, [custom_editor_y]
    mov cx, [custom_editor_w]
    mov dx, [custom_editor_h]
    mov si, COL_WHITE
    call fill_rect
    call draw_frame_black

    call custom_count_lines
    call custom_scroll_clamp
    mov byte [custom_line_visible], 0
    xor bx, bx
.init_rows:
    cmp bx, [custom_view_rows]
    jae .rows_initialized
    mov si, bx
    shl si, 2
    mov eax, [custom_len]
    mov [custom_view_row_starts+si], eax
    inc bx
    jmp .init_rows
.rows_initialized:
    mov eax, [custom_scroll_line]
    call custom_find_line_offset
    jc .after_lines
    mov [custom_render_pos], edi
    mov eax, [custom_scroll_line]
    mov [custom_render_line], eax
    xor bx, bx
.line_loop:
    cmp bx, [custom_view_rows]
    jae .after_lines
    mov eax, [custom_render_line]
    cmp eax, [custom_total_lines]
    jae .after_lines
    mov si, bx
    shl si, 2
    mov eax, [custom_render_pos]
    mov [custom_view_row_starts+si], eax
    mov edi, eax
    mov eax, [custom_render_line]
    mov dx, bx
    imul dx, CUSTOM_ROW_H
    add dx, [custom_editor_y]
    inc dx
    push bx
    call custom_format_line
    pop bx
    mov eax, [custom_render_pos]
    cmp eax, [custom_len]
    jb .continue_lines
    mov si, bx
    shl si, 2
    cmp [custom_view_row_starts+si], eax
    je .after_lines
.continue_lines:
    inc dword [custom_render_line]
    inc bx
    jmp .line_loop
.after_lines:
    cmp byte [custom_line_visible], 0
    je .no_cursor
    mov ax, [custom_cursor_draw_x]
    mov bx, [custom_cursor_draw_y]
    mov cx, 1
    mov dx, 8
    mov si, COL_BLUE
    call fill_rect
.no_cursor:
    call draw_custom_scrollbar
    call draw_custom_hscrollbar

    mov si, [custom_status_ptr]
    mov cx, [custom_x]
    add cx, 6
    mov dx, [custom_status_y]
    mov bl, COL_BLACK
    mov di, [custom_x]
    add di, [custom_w]
    sub di, 12
    call custom_draw_text_local_wrapped

    cmp byte [custom_prompt_mode], 0
    je .no_prompt
    mov si, str_custom_prompt_goto
    cmp byte [custom_prompt_mode], 1
    je .prompt_label
    mov si, str_custom_prompt_find
    cmp byte [custom_prompt_mode], 2
    je .prompt_label
    mov si, str_custom_prompt_find_replace
    cmp byte [custom_prompt_mode], 3
    je .prompt_label
    mov si, str_custom_prompt_replace
.prompt_label:
    mov cx, [custom_x]
    add cx, 6
    mov dx, [custom_status_y]
    add dx, 10
    mov bl, COL_BLACK
    call custom_draw_text_local
    mov si, custom_prompt_buf
    mov cx, [custom_prompt_input_x]
    mov dx, [custom_status_y]
    add dx, 10
    mov bl, COL_BLUE
    call draw_text
    jmp short .confirm
.no_prompt:
    mov ax, [custom_x]
    add ax, [custom_w]
    sub ax, 72
    mov bx, [custom_action_y]
    mov cx, 64
    mov dx, 20
    mov si, str_custom_execute
    call draw_button
    cmp byte [custom_maximized], 0
    jne .confirm
    mov ax, [custom_x]
    mov bx, [custom_y]
    mov cx, [custom_w]
    mov dx, [custom_h]
    call draw_resize_grip
.confirm:
    cmp byte [custom_confirm], 0
    je .execute_dialog
    call draw_custom_confirm
.execute_dialog:
    cmp byte [custom_exec_dialog], 0
    je .done
    call draw_custom_execute_dialog
.done:
    ret

custom_mark_token:
    ; Uses custom_render_pos/token_col/token_width/render_y.  Token columns are
    ; logical content columns (line numbers are fixed outside the viewport).
    pushad
    mov esi, [custom_token_col]
    mov eax, esi
    movzx ebx, word [custom_token_width]
    add eax, ebx
    mov ecx, [custom_hscroll_col]
    cmp eax, ecx
    jbe .done
    movzx edi, word [custom_view_cols]
    add ecx, edi
    cmp esi, ecx
    jae .done

    mov eax, [custom_render_pos]
    cmp eax, [custom_cursor]
    jne .selection
    mov eax, esi
    sub eax, [custom_hscroll_col]
    jc .selection
    cmp eax, edi
    jae .selection
    add eax, CUSTOM_LINE_NO_COLS
    shl eax, 3
    add ax, [custom_editor_x]
    inc ax
    mov [custom_cursor_draw_x], ax
    mov ax, [custom_render_y]
    mov [custom_cursor_draw_y], ax
    mov byte [custom_line_visible], 1

.selection:
    call custom_selection_bounds
    jc .done
    mov ecx, [custom_render_pos]
    cmp ecx, eax
    jb .done
    cmp ecx, edx
    jae .done

    ; Clip the selected token to the horizontal content viewport.
    mov eax, esi
    movzx ebx, word [custom_token_width]
    mov edx, eax
    add edx, ebx
    mov ecx, [custom_hscroll_col]
    cmp eax, ecx
    jae .left_ok
    mov eax, ecx
.left_ok:
    mov ebp, ecx
    movzx edi, word [custom_view_cols]
    add ebp, edi
    cmp edx, ebp
    jbe .right_ok
    mov edx, ebp
.right_ok:
    cmp eax, edx
    jae .done
    sub eax, ecx
    sub edx, ecx
    mov ebp, edx
    sub ebp, eax
    add eax, CUSTOM_LINE_NO_COLS
    shl eax, 3
    add ax, [custom_editor_x]
    inc ax
    mov bx, [custom_render_y]
    mov cx, bp
    shl cx, 3
    mov dx, 8
    mov si, COL_LIGHTBLUE
    call fill_rect
.done:
    popad
    ret

; AL=character, ECX=logical content column.  Characters outside the viewport
; are deliberately discarded so draw_text can never cross the editor frame.
custom_put_visible_char:
    push eax
    push ebx
    push edx
    mov dl, al
    mov eax, ecx
    cmp eax, [custom_hscroll_col]
    jb .done
    sub eax, [custom_hscroll_col]
    movzx ebx, word [custom_view_cols]
    cmp eax, ebx
    jae .done
    mov bx, ax
    mov [custom_line_buf+CUSTOM_LINE_NO_COLS+bx], dl
.done:
    pop edx
    pop ebx
    pop eax
    ret

custom_format_line:
    ; EAX=line number (zero based), EDI=start, DX=screen y.
    pushad
    mov [custom_render_y], dx
    mov [custom_render_pos], edi
    mov byte [custom_render_comment], 0
    mov di, custom_line_buf
    mov cx, [custom_total_text_cols]
    mov al, ' '
    rep stosb
    mov bx, [custom_total_text_cols]
    mov byte [custom_line_buf+bx], 0

    ; Six-character left-aligned line number followed by one space.
    mov eax, [custom_render_line]
    inc eax
    mov di, custom_line_buf+5
    mov ebx, 10
.digits:
    xor edx, edx
    div ebx
    add dl, '0'
    mov [di], dl
    dec di
    test eax, eax
    jnz .digits
    ; The division loop builds the digits at the right edge. Move the finished
    ; digit run to column zero, then blank the remaining gutter columns.
    mov si, di
    inc si
    mov di, custom_line_buf
.left_align_digits:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    cmp si, custom_line_buf+6
    jb .left_align_digits
.blank_gutter_tail:
    cmp di, custom_line_buf+6
    jae .line_number_done
    mov byte [di], ' '
    inc di
    jmp .blank_gutter_tail
.line_number_done:
    mov byte [custom_line_buf+6], ' '
    mov dword [custom_token_col], 0
    call custom_enable_flat_gs

.content:
    mov esi, [custom_render_pos]
    cmp esi, [custom_len]
    jae .end_cursor
    mov al, [gs:CUSTOM_BUFFER_PHYS+esi]
    cmp byte [gs:CUSTOM_NEWLINE_PHYS+esi], 0
    jne .newline
    cmp byte [custom_render_comment], 0
    jne .comment_char
    cmp al, 0x3B
    je .semicolon
    mov word [custom_token_width], 3
    call custom_mark_token
    mov ah, al
    shr al, 4
    call debug_nibble_to_ascii
    mov ecx, [custom_token_col]
    call custom_put_visible_char
    mov al, ah
    and al, 0x0F
    call debug_nibble_to_ascii
    inc ecx
    call custom_put_visible_char
    mov al, ' '
    inc ecx
    call custom_put_visible_char
    add dword [custom_token_col], 3
    inc dword [custom_render_pos]
    jmp .content
.semicolon:
    mov word [custom_token_width], 2
    call custom_mark_token
    mov al, ';'
    mov ecx, [custom_token_col]
    call custom_put_visible_char
    mov al, ' '
    inc ecx
    call custom_put_visible_char
    add dword [custom_token_col], 2
    inc dword [custom_render_pos]
    mov byte [custom_render_comment], 1
    jmp .content
.comment_char:
    mov word [custom_token_width], 1
    call custom_mark_token
    cmp al, 0x20
    jb .dot
    cmp al, 0x7E
    jbe .emit_comment
.dot:
    mov al, '.'
.emit_comment:
    mov ecx, [custom_token_col]
    call custom_put_visible_char
    inc dword [custom_token_col]
    inc dword [custom_render_pos]
    jmp .content
.newline:
    mov word [custom_token_width], 1
    call custom_mark_token
    inc dword [custom_render_pos]
    jmp short .terminate
.end_cursor:
    mov word [custom_token_width], 1
    call custom_mark_token
.terminate:
    mov si, custom_line_buf
    mov cx, [custom_editor_x]
    inc cx
    mov dx, [custom_render_y]
    mov bl, COL_BLACK
    call draw_text
    popad
    ret

custom_scroll_clamp:
    push eax
    push ebx
    mov eax, [custom_total_lines]
    movzx ebx, word [custom_view_rows]
    cmp eax, ebx
    jbe .zero
    sub eax, ebx
    cmp [custom_scroll_line], eax
    jbe .done
    mov [custom_scroll_line], eax
    jmp short .done
.zero:
    mov dword [custom_scroll_line], 0
.done:
    pop ebx
    pop eax
    ret

custom_compute_scroll_thumb:
    pushad
    mov ax, [custom_scroll_track_y]
    mov [custom_scroll_thumb_y], ax
    mov eax, [custom_total_lines]
    movzx ecx, word [custom_view_rows]
    cmp eax, ecx
    jbe .done
    sub eax, ecx
    mov ebx, eax
    mov eax, [custom_scroll_line]
    movzx ecx, word [custom_scroll_travel]
    mul ecx
    div ebx
    add ax, [custom_scroll_track_y]
    mov [custom_scroll_thumb_y], ax
.done:
    popad
    ret

draw_custom_scrollbar:
    mov ax, [custom_scroll_x]
    mov bx, [custom_editor_y]
    mov cx, 16
    mov dx, 14
    mov si, str_scroll_up
    call draw_button
    mov ax, [custom_scroll_x]
    mov bx, [custom_scroll_track_y]
    mov cx, 16
    mov dx, [custom_scroll_track_h]
    mov si, COL_DARKGRAY
    call fill_rect
    call draw_frame_black
    mov ax, [custom_scroll_x]
    mov bx, [custom_scroll_track_y]
    add bx, [custom_scroll_track_h]
    mov cx, 16
    mov dx, 14
    mov si, str_scroll_down
    call draw_button
    call custom_compute_scroll_thumb
    mov ax, [custom_scroll_x]
    add ax, 2
    mov bx, [custom_scroll_thumb_y]
    mov cx, 12
    mov dx, CUSTOM_SCROLL_THUMB_H
    call draw_bevel_box
    call draw_frame_black
    ret

custom_compute_hscroll_thumb:
    pushad
    mov ax, [custom_hscroll_track_x]
    mov [custom_hscroll_thumb_x], ax
    mov eax, [custom_max_line_cols]
    movzx ecx, word [custom_view_cols]
    cmp eax, ecx
    jb .done
    dec ecx
    sub eax, ecx
    mov ebx, eax
    mov eax, [custom_hscroll_col]
    movzx ecx, word [custom_hscroll_travel]
    mul ecx
    div ebx
    add ax, [custom_hscroll_track_x]
    mov [custom_hscroll_thumb_x], ax
.done:
    popad
    ret

draw_custom_hscrollbar:
    mov ax, [custom_hscroll_left_x]
    mov bx, [custom_hscroll_y]
    mov cx, 14
    mov dx, 14
    mov si, str_scroll_left
    call draw_button
    mov ax, [custom_hscroll_track_x]
    mov bx, [custom_hscroll_y]
    mov cx, [custom_hscroll_track_w]
    mov dx, 14
    mov si, COL_DARKGRAY
    call fill_rect
    call draw_frame_black
    mov ax, [custom_hscroll_right_x]
    mov bx, [custom_hscroll_y]
    mov cx, 14
    mov dx, 14
    mov si, str_scroll_right
    call draw_button
    call custom_compute_hscroll_thumb
    mov ax, [custom_hscroll_thumb_x]
    mov bx, [custom_hscroll_y]
    inc bx
    mov cx, CUSTOM_HSCROLL_THUMB_W
    mov dx, 12
    call draw_bevel_box
    call draw_frame_black
    ret

draw_custom_confirm:
    mov ax, CUSTOM_CONFIRM_X
    mov bx, CUSTOM_CONFIRM_Y
    mov cx, CUSTOM_CONFIRM_W
    mov dx, CUSTOM_CONFIRM_H
    call draw_bevel_box
    call draw_frame_black
    mov ax, CUSTOM_CONFIRM_X+3
    mov bx, CUSTOM_CONFIRM_Y+3
    mov cx, CUSTOM_CONFIRM_W-6
    mov dx, TITLE_H
    mov si, COL_BLUE
    call fill_rect
    mov si, str_custom_title
    mov cx, CUSTOM_CONFIRM_X+8
    mov dx, CUSTOM_CONFIRM_Y+8
    mov bl, COL_WHITE
    call draw_text
    mov si, str_custom_save_before_close
    cmp byte [custom_confirm], 1
    je .question
    mov si, str_custom_clear_question
.question:
    mov cx, CUSTOM_CONFIRM_X+8
    mov dx, CUSTOM_CONFIRM_Y+32
    mov bl, COL_BLACK
    mov di, CUSTOM_CONFIRM_X+CUSTOM_CONFIRM_W-8
    call custom_draw_text_local_wrapped
    cmp byte [custom_confirm], 1
    jne .clear_buttons
    mov ax, CUSTOM_CONFIRM_YES_X
    mov bx, CUSTOM_CONFIRM_BTN_Y
    mov cx, CUSTOM_CONFIRM_BTN_W
    mov dx, CUSTOM_CONFIRM_BTN_H
    mov si, str_yes
    call draw_button
    mov ax, CUSTOM_CONFIRM_NO_X
    mov si, str_no
    call draw_button
    mov ax, CUSTOM_CONFIRM_CANCEL_X
    mov si, str_cancel
    call draw_button
    ret
.clear_buttons:
    mov ax, 86
    mov bx, CUSTOM_CONFIRM_BTN_Y
    mov cx, CUSTOM_CONFIRM_BTN_W
    mov dx, CUSTOM_CONFIRM_BTN_H
    mov si, str_yes
    call draw_button
    mov ax, 172
    mov si, str_no
    call draw_button
    ret

draw_custom_execute_dialog:
    mov ax, 24
    mov bx, 52
    mov cx, 272
    mov dx, 92
    call draw_bevel_box
    call draw_frame_black
    mov ax, 27
    mov bx, 55
    mov cx, 266
    mov dx, TITLE_H
    mov si, COL_BLUE
    call fill_rect
    mov si, str_custom_exec_mode_title
    mov cx, 36
    mov dx, 60
    mov bl, COL_WHITE
    call draw_text
    mov si, str_custom_exec_mode_prompt
    mov cx, 72
    mov dx, 84
    mov bl, COL_BLACK
    call draw_text

    mov ax, 32
    mov bx, 108
    mov cx, 80
    mov dx, 24
    mov si, str_custom_exec_real
    call draw_button
    mov ax, 120
    mov bx, 108
    mov cx, 80
    mov dx, 24
    mov si, str_custom_exec_pm
    call draw_button
    mov ax, 208
    mov bx, 108
    mov cx, 80
    mov dx, 24
    mov si, str_custom_exec_lm
    call draw_button
    ret

custom_scroll_one_up:
    cmp dword [custom_scroll_line], 0
    je .draw
    dec dword [custom_scroll_line]
.draw:
    call redraw_all
    ret

custom_scroll_one_down:
    inc dword [custom_scroll_line]
    call custom_scroll_clamp
    call redraw_all
    ret

custom_scroll_page_up:
    movzx eax, word [custom_view_rows]
    cmp dword [custom_scroll_line], eax
    jb .top
    sub dword [custom_scroll_line], eax
    jmp short .draw
.top:
    mov dword [custom_scroll_line], 0
.draw:
    call redraw_all
    ret

custom_scroll_page_down:
    movzx eax, word [custom_view_rows]
    add dword [custom_scroll_line], eax
    call custom_scroll_clamp
    call redraw_all
    ret

custom_hscroll_one_left:
    cmp dword [custom_hscroll_col], 0
    je .draw
    dec dword [custom_hscroll_col]
.draw:
    call redraw_all
    ret

custom_hscroll_one_right:
    inc dword [custom_hscroll_col]
    call custom_hscroll_clamp
    call redraw_all
    ret

custom_hscroll_page_left:
    movzx eax, word [custom_view_cols]
    cmp dword [custom_hscroll_col], eax
    jb .zero
    sub dword [custom_hscroll_col], eax
    jmp short .draw
.zero:
    mov dword [custom_hscroll_col], 0
.draw:
    call redraw_all
    ret

custom_hscroll_page_right:
    movzx eax, word [custom_view_cols]
    add dword [custom_hscroll_col], eax
    call custom_hscroll_clamp
    call redraw_all
    ret

custom_update_scroll_drag:
    cmp byte [custom_scroll_drag], 2
    je .horizontal
    pushad
    mov ax, [mouse_y]
    sub ax, [custom_scroll_track_y]
    sub ax, [custom_scroll_drag_dy]
    jns .nonnegative
    xor ax, ax
.nonnegative:
    cmp ax, [custom_scroll_travel]
    jbe .position
    mov ax, [custom_scroll_travel]
.position:
    movzx eax, ax
    mov edx, [custom_total_lines]
    movzx ebx, word [custom_view_rows]
    cmp edx, ebx
    jbe .zero
    sub edx, ebx
    imul eax, edx
    movzx ecx, word [custom_scroll_travel]
    xor edx, edx
    div ecx
    mov [custom_scroll_line], eax
    jmp short .draw
.zero:
    mov dword [custom_scroll_line], 0
.draw:
    popad
    call redraw_all
    ret

.horizontal:
    pushad
    mov ax, [mouse_x]
    sub ax, [custom_hscroll_track_x]
    sub ax, [custom_scroll_drag_dy]
    jns .h_nonnegative
    xor ax, ax
.h_nonnegative:
    cmp ax, [custom_hscroll_travel]
    jbe .h_position
    mov ax, [custom_hscroll_travel]
.h_position:
    movzx eax, ax
    mov edx, [custom_max_line_cols]
    movzx ebx, word [custom_view_cols]
    cmp edx, ebx
    jb .h_zero
    dec ebx
    sub edx, ebx
    imul eax, edx
    movzx ecx, word [custom_hscroll_travel]
    xor edx, edx
    div ecx
    mov [custom_hscroll_col], eax
    jmp short .h_draw
.h_zero:
    mov dword [custom_hscroll_col], 0
.h_draw:
    popad
    call redraw_all
    ret

custom_screen_to_pos:
    ; Uses mouse_x/mouse_y. Returns EAX=source offset and CF=0.
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov ax, [mouse_y]
    cmp ax, [custom_editor_y]
    jb .miss
    sub ax, [custom_editor_y]
    xor dx, dx
    mov bx, CUSTOM_ROW_H
    div bx
    cmp ax, [custom_view_rows]
    jae .miss
    mov bx, ax
    shl bx, 2
    mov edi, [custom_view_row_starts+bx]
    mov ax, [mouse_x]
    mov cx, [custom_editor_x]
    inc cx
    cmp ax, cx
    jb .miss
    sub ax, cx
    shr ax, 3
    cmp ax, [custom_total_text_cols]
    jb .column_ok
    mov ax, [custom_total_text_cols]
    dec ax
.column_ok:
    cmp ax, CUSTOM_LINE_NO_COLS
    jb .found
    sub ax, CUSTOM_LINE_NO_COLS
    movzx edx, ax                 ; target viewport content column
    add edx, [custom_hscroll_col]
    xor ecx, ecx                 ; current logical content column
    xor ebx, ebx                 ; BL=comment
    call custom_enable_flat_gs
.scan:
    cmp edi, [custom_len]
    jae .found
    mov al, [gs:CUSTOM_BUFFER_PHYS+edi]
    cmp byte [gs:CUSTOM_NEWLINE_PHYS+edi], 0
    jne .found
    test bl, bl
    jnz .comment
    cmp al, 0x3B
    je .semi
    mov esi, 3
    jmp short .test
.semi:
    mov bl, 1
    mov esi, 2
    jmp short .test
.comment:
    mov esi, 1
.test:
    mov eax, ecx
    add eax, esi
    cmp edx, eax
    jb .found
    add ecx, esi
    inc edi
    jmp .scan
.found:
    mov eax, edi
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    clc
    ret
.miss:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    stc
    ret

custom_update_mouse_selection:
    call custom_screen_to_pos
    jc .done
    cmp eax, [custom_cursor]
    je .done
    mov [custom_cursor], eax
    cmp eax, [custom_anchor]
    setne byte [custom_selection]
    mov byte [custom_hex_half], 0
    call custom_ensure_cursor_visible
    call redraw_all
.done:
    ret

handle_custom_mouse_down:
    call custom_compute_layout
    cmp byte [custom_exec_dialog], 0
    je .check_confirm
    mov ax, 32
    mov bx, 108
    mov cx, 80
    mov dx, 24
    mov si, str_custom_exec_real
    mov di, BTN_CUSTOM_EXEC_REAL
    call try_capture_button
    jc .done
    mov ax, 120
    mov bx, 108
    mov cx, 80
    mov dx, 24
    mov si, str_custom_exec_pm
    mov di, BTN_CUSTOM_EXEC_PM
    call try_capture_button
    jc .done
    mov ax, 208
    mov bx, 108
    mov cx, 80
    mov dx, 24
    mov si, str_custom_exec_lm
    mov di, BTN_CUSTOM_EXEC_LM
    call try_capture_button
    ret
.check_confirm:
    cmp byte [custom_confirm], 0
    je .normal
    cmp byte [custom_confirm], 1
    jne .clear_confirm
    mov ax, CUSTOM_CONFIRM_YES_X
    mov bx, CUSTOM_CONFIRM_BTN_Y
    mov cx, CUSTOM_CONFIRM_BTN_W
    mov dx, CUSTOM_CONFIRM_BTN_H
    mov si, str_yes
    mov di, BTN_CUSTOM_CONFIRM_YES
    call try_capture_button
    jc .done
    mov ax, CUSTOM_CONFIRM_NO_X
    mov si, str_no
    mov di, BTN_CUSTOM_CONFIRM_NO
    call try_capture_button
    jc .done
    mov ax, CUSTOM_CONFIRM_CANCEL_X
    mov si, str_cancel
    mov di, BTN_CUSTOM_CONFIRM_CANCEL
    call try_capture_button
    ret
.clear_confirm:
    mov ax, 86
    mov bx, CUSTOM_CONFIRM_BTN_Y
    mov cx, CUSTOM_CONFIRM_BTN_W
    mov dx, CUSTOM_CONFIRM_BTN_H
    mov si, str_yes
    mov di, BTN_CUSTOM_CONFIRM_YES
    call try_capture_button
    jc .done
    mov ax, 172
    mov si, str_no
    mov di, BTN_CUSTOM_CONFIRM_NO
    call try_capture_button
    ret
.normal:
    mov ax, [custom_x]
    add ax, [custom_w]
    sub ax, 21
    mov bx, [custom_y]
    add bx, 6
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_close
    mov di, BTN_CUSTOM_CLOSE
    call try_capture_button
    jc .done
    sub ax, 19
    mov si, str_max
    cmp byte [custom_maximized], 0
    je .max_capture_label
    mov si, str_restore
.max_capture_label:
    mov di, BTN_CUSTOM_MAX
    call try_capture_button
    jc .done
    sub ax, 19
    mov si, str_min
    mov di, BTN_CUSTOM_MIN
    call try_capture_button
    jc .done
    cmp byte [custom_prompt_mode], 0
    jne .editor
    mov ax, [custom_x]
    add ax, [custom_w]
    sub ax, 72
    mov bx, [custom_action_y]
    mov cx, 64
    mov dx, 20
    mov si, str_custom_execute
    mov di, BTN_CUSTOM_EXEC
    call try_capture_button
    jc .done
.editor:
    cmp byte [custom_maximized], 0
    jne .scrollbars
    mov cx, [custom_x]
    add cx, [custom_w]
    sub cx, 9
    mov dx, [custom_y]
    add dx, [custom_h]
    sub dx, 9
    mov si, 9
    mov di, 9
    call hit_rect
    jnc .scrollbars
    mov byte [custom_resize_drag], 1
    mov ax, [custom_w]
    mov [custom_resize_start_w], ax
    mov ax, [custom_h]
    mov [custom_resize_start_h], ax
    mov ax, [mouse_x]
    mov [custom_resize_start_x], ax
    mov ax, [mouse_y]
    mov [custom_resize_start_y], ax
    ret
.scrollbars:
    mov ax, [custom_hscroll_left_x]
    mov bx, [custom_hscroll_y]
    mov cx, 14
    mov dx, 14
    mov si, str_scroll_left
    mov di, BTN_CUSTOM_HSCROLL_LEFT
    call try_capture_button
    jc .done
    mov ax, [custom_hscroll_right_x]
    mov bx, [custom_hscroll_y]
    mov cx, 14
    mov dx, 14
    mov si, str_scroll_right
    mov di, BTN_CUSTOM_HSCROLL_RIGHT
    call try_capture_button
    jc .done

    mov cx, [custom_hscroll_track_x]
    mov dx, [custom_hscroll_y]
    mov si, [custom_hscroll_track_w]
    mov di, 14
    call hit_rect
    jnc .vertical_scrollbar
    call custom_compute_hscroll_thumb
    mov ax, [mouse_x]
    cmp ax, [custom_hscroll_thumb_x]
    jb .h_page_left
    mov bx, [custom_hscroll_thumb_x]
    add bx, CUSTOM_HSCROLL_THUMB_W
    cmp ax, bx
    jae .h_page_right
    mov byte [custom_scroll_drag], 2
    sub ax, [custom_hscroll_thumb_x]
    mov [custom_scroll_drag_dy], ax
    ret
.h_page_left:
    call custom_hscroll_page_left
    ret
.h_page_right:
    call custom_hscroll_page_right
    ret

.vertical_scrollbar:
    mov ax, [custom_scroll_x]
    mov bx, [custom_editor_y]
    mov cx, 16
    mov dx, 14
    mov si, str_scroll_up
    mov di, BTN_CUSTOM_SCROLL_UP
    call try_capture_button
    jc .done
    mov ax, [custom_scroll_x]
    mov bx, [custom_scroll_track_y]
    add bx, [custom_scroll_track_h]
    mov cx, 16
    mov dx, 14
    mov si, str_scroll_down
    mov di, BTN_CUSTOM_SCROLL_DOWN
    call try_capture_button
    jc .done

    mov cx, [custom_scroll_x]
    mov dx, [custom_scroll_track_y]
    mov si, 16
    mov di, [custom_scroll_track_h]
    call hit_rect
    jnc .menus
    mov ax, [mouse_y]
    cmp ax, [custom_scroll_thumb_y]
    jb .page_up
    mov bx, [custom_scroll_thumb_y]
    add bx, CUSTOM_SCROLL_THUMB_H
    cmp ax, bx
    jae .page_down
    mov byte [custom_scroll_drag], 1
    sub ax, [custom_scroll_thumb_y]
    mov [custom_scroll_drag_dy], ax
    ret
.page_up:
    call custom_scroll_page_up
    ret
.page_down:
    call custom_scroll_page_down
    ret
.menus:
    mov ax, [mouse_y]
    mov bx, [custom_y]
    add bx, 22
    cmp ax, bx
    jb .text_area
    add bx, MENU_H
    cmp ax, bx
    jae .text_area
    mov ax, [mouse_x]
    sub ax, [custom_x]
    cmp ax, 44
    jb .menu_save
    cmp ax, 84
    jb .menu_edit
    cmp ax, 140
    jb .menu_search
    cmp ax, 172
    jb .menu_go
    ret
.menu_save:
    call custom_save
    ret
.menu_edit:
    call custom_select_all
    ret
.menu_search:
    mov al, 2
    call custom_start_prompt
    ret
.menu_go:
    mov al, 1
    call custom_start_prompt
    ret
.text_area:
    mov cx, [custom_editor_x]
    mov dx, [custom_editor_y]
    mov si, [custom_editor_w]
    mov di, [custom_editor_h]
    call hit_rect
    jnc .done
    call custom_screen_to_pos
    jc .done
    mov [custom_cursor], eax
    mov [custom_anchor], eax
    mov byte [custom_selection], 0
    mov byte [custom_mouse_select], 1
    mov byte [custom_hex_half], 0
    call redraw_all
.done:
    ret

align 512, db 0
times (CUSTOM_EDITOR_SECTORS * 512) - ($ - $$) db 0

%undef redraw_all
%undef debug_nibble_to_ascii
%undef mouse_cursor_hide
%undef mouse_ps2_disable_stream
%undef draw_bevel_box
%undef draw_frame_black
%undef fill_rect
%undef draw_text
%undef draw_char
%undef draw_button
%undef try_capture_button
%undef hit_rect
%undef draw_resize_grip

SECTION .text

stage2_end:
%if (stage2_end - stage2_start) > 0x10000
    %error "Stage 2 exceeds the real-mode 64-KiB code segment"
%endif
STAGE2_SECTORS equ ((stage2_end - stage2_start + 511) / 512)
times (STAGE2_SECTORS * 512) - (stage2_end - stage2_start) db 0

; =============================================================================
; Stage-2 far extension
; =============================================================================
; This region is not addressed through STAGE2_SEG. The boot loader keeps it
; resident at STAGE2_EXT_SEG, and every transfer between it and the base Stage
; 2 uses an explicit 16:16 far call/jump.
STAGE2_EXT_IMAGE_LBA equ (1 + STAGE2_SECTORS)

SECTION .stage2ext
stage2_ext_start:

%macro STAGE2_EXT_CALL_BASE 1
    mov word [custom_gateway_target], %1-stage2_start
    call STAGE2_SEG:(custom_stage2_gateway-stage2_start)
%endmacro

BITS 16

; Preserve eight 48-KiB application arenas without consuming the Paint,
; backbuffer, clipboard, or stack partitions below 90000h.  GS receives a
; temporary 4-GiB unreal-mode limit; both copy endpoints use GS explicitly, so
; DS/ES and the caller's real-mode addressing remain unchanged.
proc_enable_flat_gs_ext:
    pushf
    push eax
    push edx
    cli
    in al, 0x92
    or al, 0x02
    and al, 0xFE
    out 0x92, al
    o32 sgdt [custom_flat_saved_gdtr]
    o32 lgdt [debug_pm_gdtr]
    mov eax, cr0
    mov edx, eax
    or eax, 1
    mov cr0, eax
    mov ax, DEBUG_PM_DATA32_SEL
    mov gs, ax
    mov eax, edx
    and eax, 0xFFFFFFFE
    mov cr0, eax
    o32 lgdt [custom_flat_saved_gdtr]
    pop edx
    pop eax
    popf
    ret

proc_backing_save_ext:
    pushad
    push ds
    push gs
    xor ax, ax
    mov ds, ax
    movzx eax, byte [proc_arena_pid]
    cmp eax, 1
    jb .done
    cmp eax, MAX_PROCS
    jae .done
    dec eax
    imul eax, PROC_ARENA_BYTES
    add eax, PROC_BACKING_PHYS
    mov edi, eax
    mov esi, PROC_ACTIVE_PHYS
    mov ecx, PROC_ARENA_BYTES/4
    call proc_enable_flat_gs_ext
.copy:
    mov eax, [gs:esi]
    mov [gs:edi], eax
    add esi, 4
    add edi, 4
    dec ecx
    jnz .copy
.done:
    pop gs
    pop ds
    popad
    retf

proc_backing_load_ext:
    pushad
    push ds
    push gs
    xor ax, ax
    mov ds, ax
    movzx eax, byte [proc_arena_pid]
    cmp eax, 1
    jb .done
    cmp eax, MAX_PROCS
    jae .done
    dec eax
    imul eax, PROC_ARENA_BYTES
    add eax, PROC_BACKING_PHYS
    mov esi, eax
    mov edi, PROC_ACTIVE_PHYS
    mov ecx, PROC_ARENA_BYTES/4
    call proc_enable_flat_gs_ext
.copy:
    mov eax, [gs:esi]
    mov [gs:edi], eax
    add esi, 4
    add edi, 4
    dec ecx
    jnz .copy
.done:
    pop gs
    pop ds
    popad
    retf

BITS 32
; Protected-mode architectural fault generator. The base segment jumps here
; by flat physical address, leaving scarce 16-bit near-code space untouched.
; Each INT is a fallback after the corresponding faulting instruction.
debug_pm_trigger_fault32_ext:
    movzx ebp, byte [debug_crash_code]
    cmp ebp, 32
    jae .enter_handler
    cmp ebp, 0
    je .de
    cmp ebp, 1
    je .db
    cmp ebp, 3
    je .bp
    cmp ebp, 4
    je .of
    cmp ebp, 5
    je .br
    cmp ebp, 6
    je .ud
    cmp ebp, 7
    je .nm
    cmp ebp, 10
    je .ts
    cmp ebp, 11
    je .np
    cmp ebp, 12
    je .ss
    cmp ebp, 13
    je .gp
    cmp ebp, 14
    je .pf
    cmp ebp, 16
    je .mf
    cmp ebp, 17
    je .ac
    cmp ebp, 18
    je .mc
    cmp ebp, 19
    je .xm
    jmp .enter_handler
.de:
    xor ax, ax
    div ax
    int 0
.db:
    pushfd
    or dword [esp], 0x00000100
    popfd
    nop
    int 1
.bp:
    int 3
.of:
    mov al, 0x7F
    add al, 1
    into
    int 4
.br:
    mov eax, 2
    bound eax, [(STAGE2_EXT_SEG << 4) + (.bound_limits32-stage2_ext_start)]
    int 5
.ud:
    ud2
    int 6
.nm:
    mov eax, cr0
    or eax, 0x00000008
    mov cr0, eax
    fnop
    int 7
.ts:
    ; A zero-limit available TSS raises #TS before committing a task switch.
    mov word [debug_pm_gdt + DEBUG_PM_TSS_SEL + 0], 0
    mov word [debug_pm_gdt + DEBUG_PM_TSS_SEL + 2], 0
    mov byte [debug_pm_gdt + DEBUG_PM_TSS_SEL + 4], 0
    mov byte [debug_pm_gdt + DEBUG_PM_TSS_SEL + 5], 0x89
    mov byte [debug_pm_gdt + DEBUG_PM_TSS_SEL + 6], 0
    mov byte [debug_pm_gdt + DEBUG_PM_TSS_SEL + 7], 0
    jmp dword DEBUG_PM_TSS_SEL:0
    int 10
.np:
    mov byte [debug_pm_gdt + DEBUG_PM_TSS_SEL + 5], 0x12
    mov ax, DEBUG_PM_TSS_SEL
    mov ds, ax
    int 11
.ss:
    mov byte [debug_pm_gdt + DEBUG_PM_TSS_SEL + 5], 0x12
    mov ax, DEBUG_PM_TSS_SEL
    mov ss, ax
    int 12
.gp:
    mov ax, 0xFFFF
    mov ds, ax
    int 13
.pf:
    mov eax, DEBUG_PM_PD_PHYS
    mov cr3, eax
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax
    mov eax, [0x00400000]
    int 14
.mf:
    mov eax, cr0
    and eax, 0xFFFFFFF3
    or eax, 0x00000020
    mov cr0, eax
    fninit
    sub esp, 4
    fnstcw [esp]
    and word [esp], 0xFFFB
    fldcw [esp]
    fld1
    fldz
    fdivp st1, st0
    fwait
    int 16
.ac:
    ; Alignment checking is architecturally active only at CPL3. Install a
    ; valid ring-0 return stack in the TSS, permit the vector-17 software
    ; fallback from ring 3, then IRETD to a flat user segment with EFLAGS.AC.
    mov eax, cr0
    or eax, (1 << 18)
    mov cr0, eax
    mov edi, debug_lm_tss
    xor eax, eax
    mov ecx, 26
    rep stosd
    mov dword [debug_lm_tss+4], DEBUG_PM_PANIC_STACK_TOP
    mov word [debug_lm_tss+8], DEBUG_PM_DATA32_SEL
    mov word [debug_lm_tss+102], 104
    mov word [debug_pm_gdt + DEBUG_PM_TSS_SEL + 0], 103
    mov eax, debug_lm_tss
    mov word [debug_pm_gdt + DEBUG_PM_TSS_SEL + 2], ax
    shr eax, 16
    mov byte [debug_pm_gdt + DEBUG_PM_TSS_SEL + 4], al
    mov byte [debug_pm_gdt + DEBUG_PM_TSS_SEL + 5], 0x89
    mov byte [debug_pm_gdt + DEBUG_PM_TSS_SEL + 6], 0
    mov byte [debug_pm_gdt + DEBUG_PM_TSS_SEL + 7], ah
    mov ax, DEBUG_PM_TSS_SEL
    ltr ax
    mov byte [DEBUG_PM_IDT32_PHYS + (17*8) + 5], 0xEE
    mov ax, DEBUG_PM_USER_DATA_SEL | 3
    mov ds, ax
    mov es, ax
    push dword (DEBUG_PM_USER_DATA_SEL | 3)
    push dword 0x00006B00
    pushfd
    pop eax
    or eax, (1 << 18)
    push eax
    push dword (DEBUG_PM_USER_CODE_SEL | 3)
    push dword ((STAGE2_EXT_SEG << 4) + (.ac_user-stage2_ext_start))
    iretd
.ac_user:
    mov eax, [0x00000401]
    int 17
.mc:
    ; Machine check requires external CPU/chipset error injection. Vector 18
    ; is therefore the one unavoidable software fallback in this list.
    int 18
.xm:
    ; Toggle EFLAGS.ID first so pre-CPUID processors take the vector-19
    ; fallback instead of accidentally producing #UD at CPUID itself.
    pushfd
    pop eax
    mov ecx, eax
    xor eax, (1 << 21)
    push eax
    popfd
    pushfd
    pop eax
    push ecx
    popfd
    xor eax, ecx
    test eax, (1 << 21)
    jz .xm_fallback
    mov eax, 1
    cpuid
    test edx, (1 << 25)
    jz .xm_fallback
    mov eax, cr0
    and eax, 0xFFFFFFF3
    mov cr0, eax
    mov eax, cr4
    or eax, (3 << 9)
    mov cr4, eax
    sub esp, 16
    stmxcsr [esp]
    and dword [esp], 0xFFFFFDFF
    ldmxcsr [esp]
    mov dword [esp+4], 0x3F800000
    movss xmm0, [esp+4]
    xorps xmm1, xmm1
    divss xmm0, xmm1
.xm_fallback:
    int 19
.enter_handler:
    mov eax, debug_pm_fault32
    jmp eax

align 4, db 0
.bound_limits32:
    dd 0, 1

BITS 16

; Near-call gateways used by the Debug UI implementation after it is emitted
; in this far segment.  The resident gateway performs the segment transition
; and returns here; these thunks then return normally to the moved code.
%macro DEBUG_EXT_BASE_PROXY 2
%1:
    mov word [custom_gateway_target], %2-stage2_start
    call STAGE2_SEG:(custom_stage2_gateway-stage2_start)
    ret
%endmacro

DEBUG_EXT_BASE_PROXY debug_ext_base_draw_bevel, draw_bevel_box
DEBUG_EXT_BASE_PROXY debug_ext_base_draw_frame, draw_frame_black
DEBUG_EXT_BASE_PROXY debug_ext_base_fill_rect, fill_rect
DEBUG_EXT_BASE_PROXY debug_ext_base_draw_text, draw_text
DEBUG_EXT_BASE_PROXY debug_ext_base_draw_button, draw_button
DEBUG_EXT_BASE_PROXY debug_ext_base_redraw, redraw_all
DEBUG_EXT_BASE_PROXY debug_ext_base_safe_probe, debug_safe_interrupt_probe
DEBUG_EXT_BASE_PROXY app_ext_base_draw_text_wrapped, draw_text_wrapped
DEBUG_EXT_BASE_PROXY app_ext_base_proc_load, proc_load
DEBUG_EXT_BASE_PROXY app_ext_base_proc_save, proc_save
DEBUG_EXT_BASE_PROXY app_ext_base_proc_close_force, proc_close_force
DEBUG_EXT_BASE_PROXY app_ext_base_paint_new_force, paint_new_force
DEBUG_EXT_BASE_PROXY app_ext_base_notepad_new_force, notepad_new_force

%unmacro DEBUG_EXT_BASE_PROXY 2

; The message box and save controller live in the resident far extension so
; the near Stage-2 segment remains below its strict 64-KiB limit.
draw_messagebox_ext:
    mov ax, 38
    mov bx, 45
    mov cx, 244
    mov dx, 108
    call debug_ext_base_draw_bevel
    call debug_ext_base_draw_frame

    mov ax, 41
    mov bx, 48
    mov cx, 238
    mov dx, TITLE_H
    mov si, COL_BLUE
    call debug_ext_base_fill_rect

    mov si, str_message_title
    cmp byte [message_kind], MSG_ABOUT
    jne .not_about_title
    mov si, str_about_title
.not_about_title:
    cmp byte [message_kind], MSG_SYSTEM
    jne .not_system_title
    mov si, str_system_title
.not_system_title:
    cmp byte [message_kind], MSG_EXIT_CONFIRM
    jne .not_exit_title
    mov si, str_exit_title
.not_exit_title:
    cmp byte [message_kind], MSG_UNSAVED
    jne .not_unsaved_title
    mov si, str_unsaved_title
.not_unsaved_title:
    cmp byte [message_kind], MSG_OVERWRITE
    jne .not_overwrite_title
    mov si, str_overwrite_title
.not_overwrite_title:
    cmp byte [message_kind], MSG_DEBUG_RESULT
    jne .not_debug_result_title
    mov si, str_debug_result_title
.not_debug_result_title:
    cmp byte [message_kind], MSG_LONG_RESULT
    jne .title_ready
    mov si, str_long_result_title
.title_ready:
    mov cx, 46
    mov dx, 53
    mov bl, COL_WHITE
    call debug_ext_base_draw_text

    mov ax, 261
    mov bx, 51
    mov cx, CTRL_W
    mov dx, CTRL_H
    mov si, str_close
    call debug_ext_base_draw_button

    cmp byte [message_kind], MSG_EXIT_CONFIRM
    je .exit_message
    cmp byte [message_kind], MSG_UNSAVED
    je .unsaved_message
    cmp byte [message_kind], MSG_OVERWRITE
    je .overwrite_message
    cmp byte [message_kind], MSG_ABOUT
    je .about_message
    cmp byte [message_kind], MSG_SYSTEM
    je .system_message
    cmp byte [message_kind], MSG_DEBUG_RESULT
    je .debug_result_message
    cmp byte [message_kind], MSG_LONG_RESULT
    je .debug_result_message

    mov si, str_memory_line1
    mov cx, 54
    mov dx, 84
    mov bl, COL_BLACK
    call debug_ext_base_draw_text
    jmp .ok
.debug_result_message:
    mov si, str_debug_failed
    cmp byte [debug_result_success], 0
    je .debug_result_state_ready
    mov si, str_debug_success
.debug_result_state_ready:
    mov cx, 54
    mov dx, 76
    mov bl, COL_BLACK
    call debug_ext_base_draw_text
    mov si, [debug_result_line1_ptr]
    mov cx, 54
    mov dx, 91
    mov bl, COL_BLACK
    call debug_ext_base_draw_text
    mov si, [debug_result_line2_ptr]
    mov cx, 54
    mov dx, 104
    mov bl, COL_BLACK
    mov di, 270
    call app_ext_base_draw_text_wrapped
    jmp .ok
.system_message:
    mov si, [system_message_ptr]
    test si, si
    jz .default_system_message
    mov cx, 54
    mov dx, 88
    mov bl, COL_BLACK
    mov di, 266
    call app_ext_base_draw_text_wrapped
    jmp .ok
.default_system_message:
    mov si, str_system_line1
    mov cx, 54
    mov dx, 82
    mov bl, COL_BLACK
    call debug_ext_base_draw_text
    mov si, str_system_line2
    mov cx, 54
    mov dx, 96
    mov bl, COL_BLACK
    call debug_ext_base_draw_text
    jmp .ok
.about_message:
    mov si, str_about_line1
    mov cx, 54
    mov dx, 78
    mov bl, COL_BLACK
    call debug_ext_base_draw_text
    mov si, str_about_line2
    mov cx, 54
    mov dx, 91
    mov bl, COL_BLACK
    call debug_ext_base_draw_text
    mov si, str_about_line3
    mov cx, 54
    mov dx, 104
    mov bl, COL_BLACK
    call debug_ext_base_draw_text
    jmp .ok
.unsaved_message:
    mov si, str_unsaved_line1
    mov cx, 54
    mov dx, 79
    mov bl, COL_BLACK
    call debug_ext_base_draw_text
    mov si, str_unsaved_line2
    mov cx, 54
    mov dx, 94
    mov bl, COL_BLACK
    call debug_ext_base_draw_text
    jmp .yes_no
.overwrite_message:
    mov si, str_overwrite_question
    mov cx, 54
    mov dx, 74
    mov bl, COL_BLACK
    mov di, 266
    call app_ext_base_draw_text_wrapped
    jmp .yes_no
.exit_message:
    mov si, str_exit_question
    mov cx, 54
    mov dx, 82
    mov bl, COL_BLACK
    call debug_ext_base_draw_text
.yes_no:
    mov ax, 86
    mov bx, 116
    mov cx, 62
    mov dx, 22
    mov si, str_yes
    call debug_ext_base_draw_button
    mov ax, 172
    mov bx, 116
    mov cx, 62
    mov dx, 22
    mov si, str_no
    call debug_ext_base_draw_button
    retf
.ok:
    mov ax, 124
    mov bx, 127
    mov cx, 72
    mov dx, 20
    mov si, str_ok
    call debug_ext_base_draw_button
    retf

handle_unsaved_yes_ext:
    mov byte [message_open], 0
    mov al, [pending_unsaved_pid]
    test al, al
    jz .finish
    call app_ext_base_proc_load
    mov al, [pending_unsaved_action]
    cmp al, 1
    je .close
    cmp al, 2
    je .paint_new
    cmp al, 3
    je .note_new
    jmp .finish
.close:
    mov al, [pending_unsaved_pid]
    call app_ext_base_proc_close_force
    jmp .clear
.paint_new:
    call app_ext_base_paint_new_force
    jmp .clear
.note_new:
    call app_ext_base_notepad_new_force
    jmp .clear
.finish:
    call debug_ext_base_redraw
.clear:
    mov byte [pending_unsaved_pid], 0
    mov byte [pending_unsaved_action], 0
    retf

request_app_save_ext:
    mov byte [menu_open], MENU_NONE
    cmp byte [app_has_saved], 0
    je perform_app_save_ext
    cmp byte [app_dirty], 0
    jne .confirm_overwrite
    ; A saved document with no edits needs no message.  Close any File menu
    ; visually and return without creating an uninitialised system-message
    ; pointer (the old path produced the stray "No changes" dialog).
    mov byte [pending_unsaved_pid], 0
    mov byte [pending_unsaved_action], 0
    call debug_ext_base_redraw
    retf
.confirm_overwrite:
    mov al, [active_pid]
    mov [pending_unsaved_pid], al
    mov byte [pending_unsaved_action], 0
    mov byte [message_kind], MSG_OVERWRITE
    mov byte [message_open], 1
    mov byte [note_focus], 0
    mov byte [note_mouse_select], 0
    call debug_ext_base_redraw
    retf

handle_overwrite_yes_ext:
    mov byte [message_open], 0
    mov al, [pending_unsaved_pid]
    test al, al
    jz .cancel
    call app_ext_base_proc_load
    jmp perform_app_save_ext
.cancel:
    mov byte [pending_unsaved_pid], 0
    mov byte [pending_unsaved_action], 0
    call debug_ext_base_redraw
    retf

perform_app_save_ext:
    mov byte [message_open], 0
    call app_ext_base_proc_save
    cmp byte [active_type], APP_NOTEPAD
    je .note
    cmp byte [active_type], APP_PAINT
    jne .failed
    call STAGE2_EXT_SEG:(app_storage_save_paint_ext-stage2_ext_start)
    jmp short .result
.note:
    call STAGE2_EXT_SEG:(app_storage_save_note_ext-stage2_ext_start)
.result:
    jc .failed
    mov byte [app_dirty], 0
    mov byte [app_has_saved], 1
    call app_ext_base_proc_save
    mov si, str_app_saved_ok
    jmp short .finish
.failed:
    mov si, str_app_save_failed
.finish:
    mov byte [pending_unsaved_pid], 0
    mov byte [pending_unsaved_action], 0

show_app_storage_message_ext:
    mov [system_message_ptr], si
    mov byte [message_kind], MSG_SYSTEM
    mov byte [message_open], 1
    call debug_ext_base_redraw
    retf

; Rename all non-local labels while expanding the implementation so the base
; segment can retain compact compatibility wrappers with the original names.
%define draw_debug_window debug_ext_draw_debug_window
%define draw_debug_main_window debug_ext_draw_debug_main_window
%define draw_debug_blue_window debug_ext_draw_debug_blue_window
%define draw_debug_fault_window debug_ext_draw_debug_fault_window
%define draw_debug_normal_window debug_ext_draw_debug_normal_window
%define debug_fault_get_label debug_ext_fault_get_label
%define draw_debug_int_window debug_ext_draw_debug_int_window
%define debug_build_int_label debug_ext_build_int_label
%define debug_nibble_to_ascii debug_ext_nibble_to_ascii
%define debug_compute_scroll_thumb debug_ext_compute_scroll_thumb
%define debug_get_scroll_max debug_ext_get_scroll_max
%define draw_debug_scrollbar debug_ext_draw_scrollbar
%define debug_scroll_one_up debug_ext_scroll_one_up
%define debug_scroll_one_down debug_ext_scroll_one_down
%define debug_scroll_page_up debug_ext_scroll_page_up
%define debug_scroll_page_down debug_ext_scroll_page_down
%define debug_byte_to_hex debug_ext_byte_to_hex
%define debug_word_to_hex debug_ext_word_to_hex
%define debug_get_interrupt_description debug_ext_get_interrupt_description
%define debug_run_interrupt_test debug_ext_run_interrupt_test
%define draw_bevel_box debug_ext_base_draw_bevel
%define draw_frame_black debug_ext_base_draw_frame
%define fill_rect debug_ext_base_fill_rect
%define draw_text debug_ext_base_draw_text
%define draw_button debug_ext_base_draw_button
%define redraw_all debug_ext_base_redraw
%define debug_safe_interrupt_probe debug_ext_base_safe_probe

DEBUG_UI_EXT_IMPL

%undef draw_debug_window
%undef draw_debug_main_window
%undef draw_debug_blue_window
%undef draw_debug_fault_window
%undef draw_debug_normal_window
%undef debug_fault_get_label
%undef draw_debug_int_window
%undef debug_build_int_label
%undef debug_nibble_to_ascii
%undef debug_compute_scroll_thumb
%undef debug_get_scroll_max
%undef draw_debug_scrollbar
%undef debug_scroll_one_up
%undef debug_scroll_one_down
%undef debug_scroll_page_up
%undef debug_scroll_page_down
%undef debug_byte_to_hex
%undef debug_word_to_hex
%undef debug_get_interrupt_description
%undef debug_run_interrupt_test
%undef draw_bevel_box
%undef draw_frame_black
%undef fill_rect
%undef draw_text
%undef draw_button
%undef redraw_all
%undef debug_safe_interrupt_probe

; Public entry thunks consume the far return address from their Stage-2
; wrappers only after the moved implementation has completed its normal RET.
debug_ext_entry_draw_window:
    call debug_ext_draw_debug_window
    retf
debug_ext_entry_fault_label:
    call debug_ext_fault_get_label
    retf
debug_ext_entry_build_int_label:
    call debug_ext_build_int_label
    retf
debug_ext_entry_nibble:
    call debug_ext_nibble_to_ascii
    retf
debug_ext_entry_compute_thumb:
    call debug_ext_compute_scroll_thumb
    retf
debug_ext_entry_scroll_max:
    call debug_ext_get_scroll_max
    retf
debug_ext_entry_scroll_up:
    call debug_ext_scroll_one_up
    retf
debug_ext_entry_scroll_down:
    call debug_ext_scroll_one_down
    retf
debug_ext_entry_page_up:
    call debug_ext_scroll_page_up
    retf
debug_ext_entry_page_down:
    call debug_ext_scroll_page_down
    retf
debug_ext_entry_byte_hex:
    call debug_ext_byte_to_hex
    retf
debug_ext_entry_word_hex:
    call debug_ext_word_to_hex
    retf
debug_ext_entry_int_description:
    call debug_ext_get_interrupt_description
    retf
debug_ext_entry_run_interrupt:
    call debug_ext_run_interrupt_test
    retf

%unmacro DEBUG_UI_EXT_IMPL 0

; Capture the strict Real Mode Custom Program snapshot immediately before the
; payload starts. No MiniWin or DOS path consumes this snapshot.
system_integrity_rebase_ext:
    pushf
    cli
    pusha
    push ds
    push es
    xor ax, ax
    mov ds, ax
    mov es, ax

    xor si, si
    mov di, system_expected_ivt
    mov cx, 512
    cld
    rep movsw
    mov ax, [0x040E]
    mov [system_expected_bda_ebda], ax
    mov ax, [0x0413]
    mov [system_expected_bda_memory], ax
    mov ax, [BLUESCREEN_FONT_OFF_ADDR]
    mov [system_expected_font_off], ax
    mov ax, [BLUESCREEN_FONT_SEG_ADDR]
    mov [system_expected_font_seg], ax

    mov si, boot_start
    mov cx, boot_drive-boot_start
    call system_integrity_checksum_ext
    mov [system_expected_boot_hash], ax
    mov si, boot_dap
    mov cx, 512-(boot_dap-boot_start)
    call system_integrity_checksum_ext
    mov [system_expected_mbr_tail_hash], ax
    mov si, system_integrity_code_start
    mov cx, system_integrity_code_end-system_integrity_code_start
    call system_integrity_checksum_ext
    mov [system_expected_irq_hash], ax
    mov si, system_panic_code_start
    mov cx, system_panic_code_end-system_panic_code_start
    call system_integrity_checksum_ext
    mov [system_expected_panic_hash], ax
    mov si, proc_type
    mov cx, process_table_end-proc_type
    call system_integrity_checksum_ext
    mov [system_expected_proc_hash], ax

    pop es
    pop ds
    popa
    popf
    retf

; Custom Program's Real Mode tracer calls this strict checker only after an
; executed payload instruction. It retains the full live-memory snapshot
; checks without imposing them on MiniWin, DOS, or any other path.
system_custom_integrity_check_ext:
    pushf
    cli
    pusha
    push ds
    push es
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ax, [system_expected_font_off]
    cmp [BLUESCREEN_FONT_OFF_ADDR], ax
    jne .fatal
    mov ax, [system_expected_font_seg]
    cmp [BLUESCREEN_FONT_SEG_ADDR], ax
    jne .fatal
    mov ax, [system_expected_bda_ebda]
    cmp [0x040E], ax
    jne .fatal
    mov ax, [system_expected_bda_memory]
    cmp [0x0413], ax
    jne .fatal
    cmp word [0x7DFE], 0xAA55
    jne .fatal
    cmp byte [boot_default_gui], 1
    ja .fatal
    cmp byte [boot_autorestart], 1
    ja .fatal

    xor si, si
    mov di, system_expected_ivt
    mov cx, 512
    cld
    repe cmpsw
    jne .fatal
    mov si, boot_start
    mov cx, boot_drive-boot_start
    call system_integrity_checksum_ext
    cmp ax, [system_expected_boot_hash]
    jne .fatal
    mov si, boot_dap
    mov cx, 512-(boot_dap-boot_start)
    call system_integrity_checksum_ext
    cmp ax, [system_expected_mbr_tail_hash]
    jne .fatal
    mov si, system_integrity_code_start
    mov cx, system_integrity_code_end-system_integrity_code_start
    call system_integrity_checksum_ext
    cmp ax, [system_expected_irq_hash]
    jne .fatal
    mov si, system_panic_code_start
    mov cx, system_panic_code_end-system_panic_code_start
    call system_integrity_checksum_ext
    cmp ax, [system_expected_panic_hash]
    jne .fatal
    mov si, proc_type
    mov cx, process_table_end-proc_type
    call system_integrity_checksum_ext
    cmp ax, [system_expected_proc_hash]
    jne .fatal
    jmp short .done

.fatal:
    cmp byte [BLUESCREEN_ENABLE_ADDR], 0
    je .done
    mov al, BSOD_STOP_CRITICAL_WRITE
    jmp STAGE2_SEG:(system_blue_screen-stage2_start)

.done:
    pop es
    pop ds
    popa
    popf
    retf

system_integrity_checksum_ext:
    ; DS:SI/CX -> AX. The rotate/XOR fold catches byte values and ordering.
    xor dx, dx
.next:
    lodsb
    rol dx, 1
    xor dl, al
    loop .next
    mov ax, dx
    ret

; Real Mode has no supervisor write protection. While a Real Custom Program
; runs, vector 1 points here and TF remains set. Distinguish a literal CD 01
; from a CPU single-step trap. A trap whose saved CS is still the payload
; segment validates the strict snapshot immediately; the far return trap has a
; different CS and therefore cannot leak a pending check into MiniWin.
custom_real_trace_ext:
    ; DR6.BS distinguishes the private TF single-step stream from a genuine
    ; software INT 1.  This avoids guessing from the two bytes before saved IP
    ; (which could be an immediate value ending in CD 01) while still making a
    ; literal CD 01 at any payload position enter the Debug Exception screen.
    push eax
    mov eax, dr6
    test eax, 0x00004000
    jnz .trace_entry
    pop eax
    push ax
    mov al, 1
    jmp STAGE2_SEG:(system_exception_common-stage2_start)
.trace_entry:
    mov eax, 0xFFFF0FF0
    mov dr6, eax
    pop eax
    push ax
    push bx
    push ds
    push bp
    mov bp, sp
    mov bx, [ss:bp+8]
    mov ax, [ss:bp+10]
    cmp ax, CUSTOM_EXEC_SEG
    jne .single_step
    mov ds, ax

    ; A TF trap is delivered at the first payload IP and after every later
    ; instruction. Catch the next literal CD 01 before it executes; the DR6
    ; path above remains a fallback for a software INT 1 already in flight.
    cmp byte [bx], 0xCD
    jne .check_halt
    cmp byte [bx+1], 0x01
    jne .check_halt
.debug_exception:
    pop bp
    pop ds
    pop bx
    mov al, 1
    jmp STAGE2_SEG:(system_exception_common-stage2_start)
.check_halt:
    ; TF normally raises #DB immediately after HLT, which makes Real Mode
    ; "CLI; HLT" continue into the return trampoline instead of stopping the
    ; CPU. If IF is already clear, remove TF from the interrupted FLAGS image:
    ; HLT then has its architectural indefinite-stop behavior. The strict
    ; snapshot is still checked below before IRET executes the HLT.
    cmp byte [bx], 0xF4
    jne .single_step
    test word [ss:bp+12], 0x0200
    jnz .single_step
    and word [ss:bp+12], 0xFEFF
.single_step:
    pop bp
    pop ds
    pop bx
    push ds
    push bp
    mov bp, sp
    mov ax, [bp+8]
    cmp ax, CUSTOM_EXEC_SEG
    jne .done
    xor ax, ax
    mov ds, ax
    call STAGE2_EXT_SEG:(system_custom_integrity_check_ext-stage2_ext_start)
.done:
    pop bp
    pop ds
    pop ax
    iret

; Build a legacy 4 KiB identity map for the first 4 MiB. Custom Program
; code/data and VGA stay writable, while live IVT/BDA/MBR/Stage-2/return
; stack pages are supervisor read-only and CR0.WP makes CPL0 obey them.
debug_pm_prepare_custom_paging_ext:
    push eax
    push ebx
    push cx
    push di
    push es
    cld

    mov ax, DEBUG_PM_PD_PHYS >> 4
    mov es, ax
    xor di, di
    xor eax, eax
    mov cx, 1024
    rep stosd
    mov dword es:[0], DEBUG_PM_PT_PHYS | 0x00000003

    mov ax, DEBUG_PM_PT_PHYS >> 4
    mov es, ax
    xor di, di
    mov eax, 0x00000003
    mov cx, 1024
.map:
    stosd
    add eax, 0x1000
    loop .map

    xor di, di
    mov cx, CUSTOM_PROTECT_LOW_END >> 12
.protect_low:
    and dword es:[di], 0xFFFFFFFD
    add di, 4
    loop .protect_low
    mov di, (CUSTOM_PROTECT_STAGE_START >> 12) * 4
    mov cx, (CUSTOM_PROTECT_STAGE_END-CUSTOM_PROTECT_STAGE_START) >> 12
.protect_stage:
    and dword es:[di], 0xFFFFFFFD
    add di, 4
    loop .protect_stage
    mov di, (CUSTOM_PROTECT_STACK_START >> 12) * 4
    mov cx, (CUSTOM_PROTECT_STACK_END-CUSTOM_PROTECT_STACK_START) >> 12
.protect_return_stack:
    and dword es:[di], 0xFFFFFFFD
    add di, 4
    loop .protect_return_stack

    pop es
    pop di
    pop cx
    pop ebx
    pop eax
    retf

; ES is DEBUG_LM_PT_PHYS. IA-32e PTEs are eight bytes each.
debug_lm_mark_custom_pages_readonly_ext:
    push cx
    push di
    xor di, di
    mov cx, CUSTOM_PROTECT_LOW_END >> 12
.protect_low:
    and dword es:[di], 0xFFFFFFFD
    add di, 8
    loop .protect_low
    mov di, (CUSTOM_PROTECT_STAGE_START >> 12) * 8
    mov cx, (CUSTOM_PROTECT_STAGE_END-CUSTOM_PROTECT_STAGE_START) >> 12
.protect_stage:
    and dword es:[di], 0xFFFFFFFD
    add di, 8
    loop .protect_stage
    mov di, (CUSTOM_PROTECT_STACK_START >> 12) * 8
    mov cx, (CUSTOM_PROTECT_STACK_END-CUSTOM_PROTECT_STACK_START) >> 12
.protect_return_stack:
    and dword es:[di], 0xFFFFFFFD
    add di, 8
    loop .protect_return_stack
    pop di
    pop cx
    retf

; Return CF=0 only when CPUID, MSR, PAE, and architectural Long Mode support
; are present.  The near wrapper propagates CF unchanged to every caller.
debug_cpu_supports_long_mode_ext:
    push eax
    push ebx
    push ecx
    push edx
    mov byte [debug_lm_fail_reason], 1

    pushfd
    pop eax
    mov ecx, eax
    xor eax, 0x00200000
    push eax
    popfd
    pushfd
    pop eax
    push ecx
    popfd
    xor eax, ecx
    test eax, 0x00200000
    jz .failed

    xor eax, eax
    cpuid
    cmp eax, 1
    jb .failed

    mov byte [debug_lm_fail_reason], 2
    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000001
    jb .failed
    mov eax, 0x80000001
    cpuid
    test edx, (1 << 29)
    jz .failed

    mov byte [debug_lm_fail_reason], 3
    mov eax, 1
    cpuid
    test edx, (1 << 3)
    jz .failed
    test edx, (1 << 5)
    jz .failed
    test edx, (1 << 6)
    jz .failed

    mov byte [debug_lm_fail_reason], 0
    pop edx
    pop ecx
    pop ebx
    pop eax
    clc
    retf
.failed:
    pop edx
    pop ecx
    pop ebx
    pop eax
    stc
    retf

; Persist both Control check boxes in the real disk's LBA 0.  A fixed 0600:0
; scratch sector keeps the BIOS transfer independent of extension placement.
control_write_boot_setting_ext:
    pushf
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es
    xor ax, ax
    mov ds, ax
    mov byte [control_write_result], 1
    mov byte [control_write_retries], 3

    mov al, [control_boot_dos]
    xor al, 1
    and al, 1
    mov [control_disk_value], al
    mov al, [control_autorestart]
    and al, 1
    mov [control_autorestart_disk_value], al

    mov ax, BOOT_SETTING_IO_SEG
    mov es, ax
    mov si, 0x7C00
    xor di, di
    mov cx, 256
    cld
    rep movsw

    xor bx, bx
    mov al, [control_disk_value]
    mov es:[bx + (boot_default_gui-boot_start)], al
    mov al, [control_autorestart_disk_value]
    mov es:[bx + (boot_autorestart-boot_start)], al
    cmp word es:[510], 0xAA55
    jne .finish

.retry:
    xor ax, ax
    mov ds, ax
    mov dl, [os_boot_drive]
    int 0x13

    xor ax, ax
    mov ds, ax
    mov ax, BOOT_SETTING_IO_SEG
    mov es, ax
    mov ax, 0x0301
    xor bx, bx
    mov cx, 0x0001
    xor dh, dh
    mov dl, [os_boot_drive]
    int 0x13
    jnc .success
    xor ax, ax
    mov ds, ax
    dec byte [control_write_retries]
    jnz .retry
    jmp .finish

.success:
    xor ax, ax
    mov ds, ax
    mov al, [control_disk_value]
    mov [boot_default_gui], al
    mov al, [control_autorestart_disk_value]
    mov [boot_autorestart], al
    mov byte [control_write_result], 0
.finish:
    pop es
    pop ds
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    popf
    cmp byte [control_write_result], 0
    je .ok
    stc
    retf
.ok:
    clc
    retf

; Load the custom-editor overlay and enter it.  This is called through a far
; pointer by the small resident loader and therefore consumes no base Stage-2
; near-code address space.
custom_stage2_ext_open_editor:
    mov byte [custom_dap+0], 0x10
    mov byte [custom_dap+1], 0
    mov word [custom_dap+2], CUSTOM_EDITOR_SECTORS
    mov word [custom_dap+4], 0
    mov word [custom_dap+6], CUSTOM_CODE_SEG
    mov dword [custom_dap+8], CUSTOM_IMAGE_LBA
    mov dword [custom_dap+12], 0
    mov si, custom_dap
    mov dl, [os_boot_drive]
    mov ah, 0x42
    int 0x13
    jc .failed
    xor ax, ax
    mov ds, ax
    call CUSTOM_CODE_SEG:custom_entry_open
    clc
    retf
.failed:
    stc
    retf

; The payload temporarily occupies CUSTOM_CODE_SEG, so every execution mode
; must reload the editor overlay before returning to MiniWin.  CF reports the
; reload result; on failure a normal system message remains available.
custom_stage2_ext_reopen_after_exec:
    xor ax, ax
    mov ds, ax
    mov es, ax
    call STAGE2_EXT_SEG:(custom_stage2_ext_open_editor-stage2_ext_start)
    jc .failed
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov byte [custom_ext_loaded], 1
    clc
    ret
.failed:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov byte [custom_open], 0
    mov byte [custom_created], 0
    mov byte [custom_minimized], 0
    mov al, WIN_CUSTOM
    STAGE2_EXT_CALL_BASE task_remove_window
    mov si, str_custom_reload_error
    mov [system_message_ptr], si
    mov byte [message_kind], MSG_SYSTEM
    mov byte [message_open], 1
    STAGE2_EXT_CALL_BASE redraw_all
    stc
    ret

; Load the compacted custom payload from transient LBA 2048+ into 6000:0000.
; lives outside the editor overlay and outside the base Stage-2 code segment.
custom_stage2_ext_launch_exec:
    cli
    xor ax, ax
    mov ds, ax
    mov ax, STACK_SEG
    mov ss, ax
    mov sp, STACK_TOP
    sti
    mov dword [custom_io_pos], 0
    mov dword [custom_io_current_lba], CUSTOM_EXEC_FIRST_LBA
    mov word [custom_exec_load_seg], CUSTOM_EXEC_SEG
.read_loop:
    mov byte [custom_dap+0], 0x10
    mov byte [custom_dap+1], 0
    mov word [custom_dap+2], 1
    mov word [custom_dap+4], 0
    mov word [custom_dap+6], BOOT_SETTING_IO_SEG
    mov eax, [custom_io_current_lba]
    mov [custom_dap+8], eax
    mov dword [custom_dap+12], 0
    mov si, custom_dap
    mov dl, [os_boot_drive]
    mov ah, 0x42
    int 0x13
    jc .failed

    mov ax, [custom_exec_load_seg]
    mov es, ax
    mov ax, BOOT_SETTING_IO_SEG
    mov ds, ax
    xor si, si
    xor di, di
    mov cx, 256
    rep movsw
    xor ax, ax
    mov ds, ax
    add word [custom_exec_load_seg], 0x20
    add dword [custom_io_pos], 512
    mov eax, [custom_io_pos]
    cmp eax, [custom_exec_stage_len]
    jae .launch
    inc dword [custom_io_current_lba]
    jmp .read_loop
.launch:
    STAGE2_EXT_CALL_BASE mouse_cursor_hide
    STAGE2_EXT_CALL_BASE mouse_ps2_disable_stream
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov dl, [os_boot_drive]
    mov al, [custom_exec_mode]
    test al, al
    jz .launch_real
    ; The editor overlay has been replaced by the payload. Reload it as soon as
    ; the shared mode framework has restored graphics and mouse support.
    mov byte [custom_open], 0
    mov byte [debug_mode_action], 2
    cmp al, 1
    je .launch_protected
    STAGE2_EXT_CALL_BASE debug_enter_long_mode
    jmp short .reopen_after_mode
.launch_protected:
    STAGE2_EXT_CALL_BASE debug_enter_protected_mode
.reopen_after_mode:
    call custom_stage2_ext_reopen_after_exec
    mov byte [debug_mode_action], 0
    STAGE2_EXT_CALL_BASE mouse_cursor_show
    jmp STAGE2_SEG:(main_loop-stage2_start)
.launch_real:
    ; Use the disposable 64-KiB screen back buffer as the program stack, not
    ; MiniWin's return stack. Install the TF trace vector before enabling the
    ; first instruction trap, then rebase the expected IVT around that vector.
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov word [0x0004], custom_real_trace_ext-stage2_ext_start
    mov word [0x0006], STAGE2_EXT_SEG
    call STAGE2_EXT_SEG:(system_integrity_rebase_ext-stage2_ext_start)
    mov ax, BACKBUF_SEG
    mov ss, ax
    mov sp, 0xFFFE
    mov eax, 0xFFFF0FF0
    mov dr6, eax
    pushf
    pop ax
    or ax, 0x0300                 ; IF | TF
    push ax
    popf
    jmp CUSTOM_EXEC_SEG:0x0000
.failed:
    xor ax, ax
    mov ds, ax
    mov es, ax
    call custom_stage2_ext_reopen_after_exec
    jc .failed_done
    mov word [custom_status_ptr], str_custom_exec_read
    STAGE2_EXT_CALL_BASE redraw_all
.failed_done:
    jmp STAGE2_SEG:(main_loop-stage2_start)

; The generated EA ptr16:16 after the last executable byte lands here.  Reset
; volatile execution state, rebuild graphics/mouse support, reload the
; overwritten editor overlay, and resume MiniWin with a far jump.
custom_stage2_ext_return_exec:
    ; A TF exception may have delivered us here immediately after the payload's
    ; final far jump. Clear TF before rebuilding MiniWin state.
    pushf
    pop ax
    and ax, 0xFEFF
    push ax
    popf
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ax, STACK_SEG
    mov ss, ax
    mov sp, STACK_TOP
    cld
    mov word [0x0004], system_exception_01-stage2_start
    mov word [0x0006], STAGE2_SEG
    mov byte [custom_scroll_drag], 0
    mov byte [custom_mouse_select], 0
    mov byte [mouse_buttons], 0
    mov byte [mouse_raw_buttons], 0
    mov byte [mouse_prev_buttons], 0
    mov byte [mouse_changed], 0
    mov byte [cursor_visible], 0
    mov byte [vm_abs_valid], 0
    mov byte [custom_ext_loaded], 1
    STAGE2_EXT_CALL_BASE init_font_and_video
    STAGE2_EXT_CALL_BASE init_mouse_support
    mov word [draw_seg], VGA_SEG
    sti
    call custom_stage2_ext_reopen_after_exec
    STAGE2_EXT_CALL_BASE mouse_cursor_show
    jmp STAGE2_SEG:(main_loop-stage2_start)

; =============================================================================
; Notepad/Paint persistent storage (LBA 1501..2000)
; =============================================================================
; These routines live in the resident far extension so Ctrl+S never depends on
; the separately loaded Custom Program overlay. All transfers use the existing
; 0600:0000 scratch sector and a 16-byte EDD packet in segment zero.

app_storage_clear_buffer_ext:
    push ax
    push cx
    push di
    push es
    mov ax, BOOT_SETTING_IO_SEG
    mov es, ax
    xor di, di
    xor ax, ax
    mov cx, 256
    cld
    rep stosw
    pop es
    pop di
    pop cx
    pop ax
    ret

app_storage_read_sector_ext:
    push ax
    push bx
    push cx
    push dx
    push si
    mov byte [app_io_retry], 3
.retry:
    mov byte [control_dap+0], 0x10
    mov byte [control_dap+1], 0
    mov word [control_dap+2], 1
    mov word [control_dap+4], 0
    mov word [control_dap+6], BOOT_SETTING_IO_SEG
    mov eax, [app_io_lba]
    mov [control_dap+8], eax
    mov dword [control_dap+12], 0
    mov byte [system_watchdog_ticks], 0
    mov si, control_dap
    mov dl, [os_boot_drive]
    mov ah, 0x42
    int 0x13
    jnc .ok
    xor ah, ah
    mov dl, [os_boot_drive]
    int 0x13
    dec byte [app_io_retry]
    jnz .retry
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    stc
    ret
.ok:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    clc
    ret

app_storage_write_sector_ext:
    push ax
    push bx
    push cx
    push dx
    push si
    mov byte [app_io_retry], 3
.retry:
    mov byte [control_dap+0], 0x10
    mov byte [control_dap+1], 0
    mov word [control_dap+2], 1
    mov word [control_dap+4], 0
    mov word [control_dap+6], BOOT_SETTING_IO_SEG
    mov eax, [app_io_lba]
    mov [control_dap+8], eax
    mov dword [control_dap+12], 0
    mov byte [system_watchdog_ticks], 0
    mov si, control_dap
    mov dl, [os_boot_drive]
    mov ah, 0x43
    xor al, al
    int 0x13
    jnc .ok
    xor ah, ah
    mov dl, [os_boot_drive]
    int 0x13
    dec byte [app_io_retry]
    jnz .retry
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    stc
    ret
.ok:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    clc
    ret

app_storage_load_note_ext:
    pushad
    push ds
    push es
    push fs
    xor ax, ax
    mov ds, ax
    mov dword [app_io_lba], NOTE_SAVE_FIRST_LBA
    call app_storage_read_sector_ext
    jc .failed
    mov ax, BOOT_SETTING_IO_SEG
    mov es, ax
    cmp dword es:[0], NOTE_SAVE_MAGIC
    jne .failed
    movzx eax, word es:[4]
    cmp eax, NOTE_MAX
    ja .failed
    mov [app_io_remaining], eax
    mov dword [app_io_pos], 0
    mov word [app_io_offset], NOTE_SAVE_HEADER_SIZE
    mov ax, [active_data_seg]
    mov fs, ax
.sector:
    mov ax, BOOT_SETTING_IO_SEG
    mov es, ax
.copy:
    cmp dword [app_io_remaining], 0
    je .loaded
    cmp word [app_io_offset], 512
    jae .next_sector
    mov bx, [app_io_offset]
    mov al, es:[bx]
    mov edi, [app_io_pos]
    mov fs:[edi], al
    inc dword [app_io_pos]
    inc word [app_io_offset]
    dec dword [app_io_remaining]
    jmp .copy
.next_sector:
    inc dword [app_io_lba]
    cmp dword [app_io_lba], NOTE_SAVE_LAST_LBA
    ja .failed
    call app_storage_read_sector_ext
    jc .failed
    mov word [app_io_offset], 0
    jmp .sector
.loaded:
    movzx eax, word [app_io_pos]
    mov [note_len], ax
    mov [note_cursor], ax
    mov [note_anchor], ax
    mov word [note_scroll_row], 0
    mov byte [note_sel_active], 0
    mov byte [note_mouse_select], 0
    mov byte [note_undo_valid], 0
    mov byte fs:[eax], 0
    mov byte [app_has_saved], 1
    mov byte [app_dirty], 0
    pop fs
    pop es
    pop ds
    popad
    clc
    retf
.failed:
    pop fs
    pop es
    pop ds
    popad
    stc
    retf

app_storage_save_note_ext:
    pushad
    push ds
    push es
    push fs
    xor ax, ax
    mov ds, ax
    movzx eax, word [note_len]
    cmp eax, NOTE_MAX
    ja .failed
    mov [app_io_remaining], eax
    mov dword [app_io_pos], 0
    mov dword [app_io_lba], NOTE_SAVE_FIRST_LBA
    mov ax, [active_data_seg]
    mov fs, ax
.sector:
    call app_storage_clear_buffer_ext
    mov ax, BOOT_SETTING_IO_SEG
    mov es, ax
    mov word [app_io_offset], 0
    cmp dword [app_io_lba], NOTE_SAVE_FIRST_LBA
    jne .copy
    mov dword es:[0], NOTE_SAVE_MAGIC
    mov ax, [note_len]
    mov es:[4], ax
    mov word es:[6], 0
    mov word [app_io_offset], NOTE_SAVE_HEADER_SIZE
.copy:
    cmp dword [app_io_remaining], 0
    je .write_last
    cmp word [app_io_offset], 512
    jae .write_more
    mov esi, [app_io_pos]
    mov al, fs:[esi]
    mov bx, [app_io_offset]
    mov es:[bx], al
    inc dword [app_io_pos]
    inc word [app_io_offset]
    dec dword [app_io_remaining]
    jmp .copy
.write_more:
    call app_storage_write_sector_ext
    jc .failed
    inc dword [app_io_lba]
    cmp dword [app_io_lba], NOTE_SAVE_LAST_LBA
    jbe .sector
    jmp short .failed
.write_last:
    call app_storage_write_sector_ext
    jc .failed
    pop fs
    pop es
    pop ds
    popad
    clc
    retf
.failed:
    pop fs
    pop es
    pop ds
    popad
    stc
    retf

app_storage_load_paint_ext:
    pushad
    push ds
    push es
    push fs
    xor ax, ax
    mov ds, ax
    mov dword [app_io_lba], PAINT_SAVE_FIRST_LBA
    call app_storage_read_sector_ext
    jc .failed
    mov ax, BOOT_SETTING_IO_SEG
    mov es, ax
    cmp dword es:[0], PAINT_SAVE_MAGIC
    jne .failed
    mov ax, es:[4]
    test ax, ax
    jz .failed
    cmp ax, PAINT_CANVAS_MAX_W
    ja .failed
    mov [paint_canvas_w], ax
    mov ax, es:[6]
    test ax, ax
    jz .failed
    cmp ax, PAINT_CANVAS_MAX_H
    ja .failed
    mov [paint_canvas_h], ax
    mov ax, es:[8]
    cmp ax, PAINT_TEXT_MAX
    ja .failed
    mov [paint_text_len], ax
    mov al, es:[10]
    mov [paint_color], al
    mov al, es:[11]
    mov [paint_brush_size], al
    mov al, es:[12]
    cmp al, PAINT_TOOL_COUNT
    jb .tool_ok
    xor al, al
.tool_ok:
    mov [paint_tool], al
    mov al, es:[13]
    cmp al, 3
    jbe .text_size_ok
    mov al, 1
.text_size_ok:
    mov [paint_text_size], al
    mov al, es:[14]
    and al, 1
    mov [paint_text_active], al
    mov ax, es:[16]
    mov [paint_text_x], ax
    mov ax, es:[18]
    mov [paint_text_y], ax
    mov al, es:[20]
    mov [paint_rgb_r], al
    mov al, es:[21]
    mov [paint_rgb_g], al
    mov al, es:[22]
    mov [paint_rgb_b], al
    mov al, es:[23]
    mov [paint_custom_color], al
    mov al, es:[24]
    and al, 1
    mov [paint_rainbow], al
    mov al, es:[25]
    and al, 1
    mov [paint_eraser], al
    mov dword [app_io_remaining], PAINT_PERSIST_BYTES
    mov dword [app_io_pos], 0
    mov word [app_io_offset], PAINT_SAVE_HEADER_SIZE
    mov ax, [active_data_seg]
    mov fs, ax
.sector:
    mov ax, BOOT_SETTING_IO_SEG
    mov es, ax
.copy:
    cmp dword [app_io_remaining], 0
    je .loaded
    cmp word [app_io_offset], 512
    jae .next_sector
    mov bx, [app_io_offset]
    mov al, es:[bx]
    mov edi, [app_io_pos]
    mov fs:[edi], al
    inc dword [app_io_pos]
    inc word [app_io_offset]
    dec dword [app_io_remaining]
    jmp .copy
.next_sector:
    inc dword [app_io_lba]
    cmp dword [app_io_lba], PAINT_SAVE_LAST_LBA
    ja .failed
    call app_storage_read_sector_ext
    jc .failed
    mov word [app_io_offset], 0
    jmp .sector
.loaded:
    mov ax, [paint_text_len]
    mov [paint_text_cursor], ax
    mov [paint_text_anchor], ax
    mov byte [paint_text_sel_active], 0
    mov byte [paint_text_mouse_select], 0
    mov byte [paint_select_active], 0
    mov byte [paint_select_drag], 0
    mov byte [undo_available], 0
    mov byte [paint_zoom], 1
    mov word [paint_scroll_x], 0
    mov word [paint_scroll_y], 0
    mov byte [app_has_saved], 1
    mov byte [app_dirty], 0
    pop fs
    pop es
    pop ds
    popad
    clc
    retf
.failed:
    pop fs
    pop es
    pop ds
    popad
    stc
    retf

app_storage_save_paint_ext:
    pushad
    push ds
    push es
    push fs
    xor ax, ax
    mov ds, ax
    cmp word [paint_canvas_w], PAINT_CANVAS_MAX_W
    ja .failed
    cmp word [paint_canvas_h], PAINT_CANVAS_MAX_H
    ja .failed
    cmp word [paint_text_len], PAINT_TEXT_MAX
    ja .failed
    mov dword [app_io_remaining], PAINT_PERSIST_BYTES
    mov dword [app_io_pos], 0
    mov dword [app_io_lba], PAINT_SAVE_FIRST_LBA
    mov ax, [active_data_seg]
    mov fs, ax
.sector:
    call app_storage_clear_buffer_ext
    mov ax, BOOT_SETTING_IO_SEG
    mov es, ax
    mov word [app_io_offset], 0
    cmp dword [app_io_lba], PAINT_SAVE_FIRST_LBA
    jne .copy
    mov dword es:[0], PAINT_SAVE_MAGIC
    mov ax, [paint_canvas_w]
    mov es:[4], ax
    mov ax, [paint_canvas_h]
    mov es:[6], ax
    mov ax, [paint_text_len]
    mov es:[8], ax
    mov al, [paint_color]
    mov es:[10], al
    mov al, [paint_brush_size]
    mov es:[11], al
    mov al, [paint_tool]
    mov es:[12], al
    mov al, [paint_text_size]
    mov es:[13], al
    mov al, [paint_text_active]
    mov es:[14], al
    mov ax, [paint_text_x]
    mov es:[16], ax
    mov ax, [paint_text_y]
    mov es:[18], ax
    mov al, [paint_rgb_r]
    mov es:[20], al
    mov al, [paint_rgb_g]
    mov es:[21], al
    mov al, [paint_rgb_b]
    mov es:[22], al
    mov al, [paint_custom_color]
    mov es:[23], al
    mov al, [paint_rainbow]
    mov es:[24], al
    mov al, [paint_eraser]
    mov es:[25], al
    mov word [app_io_offset], PAINT_SAVE_HEADER_SIZE
.copy:
    cmp dword [app_io_remaining], 0
    je .write_last
    cmp word [app_io_offset], 512
    jae .write_more
    mov esi, [app_io_pos]
    mov al, fs:[esi]
    mov bx, [app_io_offset]
    mov es:[bx], al
    inc dword [app_io_pos]
    inc word [app_io_offset]
    dec dword [app_io_remaining]
    jmp .copy
.write_more:
    call app_storage_write_sector_ext
    jc .failed
    inc dword [app_io_lba]
    cmp dword [app_io_lba], PAINT_SAVE_LAST_LBA
    jbe .sector
    jmp short .failed
.write_last:
    call app_storage_write_sector_ext
    jc .failed
    pop fs
    pop es
    pop ds
    popad
    clc
    retf
.failed:
    pop fs
    pop es
    pop ds
    popad
    stc
    retf

stage2_ext_end:
%if (stage2_ext_end - stage2_ext_start) > 0x10000
    %error "Stage-2 far extension exceeds its own 64-KiB code segment"
%endif
STAGE2_EXT_SECTORS equ ((stage2_ext_end - stage2_ext_start + 511) / 512)
times (STAGE2_EXT_SECTORS * 512) - (stage2_ext_end - stage2_ext_start) db 0

%unmacro STAGE2_EXT_CALL_BASE 1

%if (STAGE2_EXT_SEG + (STAGE2_EXT_SECTORS * 0x20)) > GUI_SNAPSHOT_SEG
    %error "Stage-2 far extension overlaps the GUI snapshot arena"
%endif

; The imported editors follow the base Stage 2 and its sector-padded extension.
HEX_IMAGE_LBA equ (STAGE2_EXT_IMAGE_LBA + STAGE2_EXT_SECTORS)
; The HEX section carries one aligned character-probe sector after its
; 64-sector executable payload.  Custom Program begins after that trailer.
CUSTOM_IMAGE_LBA equ (HEX_IMAGE_LBA + HEX_EDITOR_SECTORS + HEX_TRAILER_SECTORS)

%if (CUSTOM_IMAGE_LBA + CUSTOM_EDITOR_SECTORS) > PERSISTENCE_FIRST_LBA
    %error "System image overlaps the persistent data area beginning at LBA 500"
%endif


; =============================================================================
; Imported HEX editor from 2.asm
; - Its original stage 1 is omitted; MiniWin's sector-0 loader starts it.
; - All private symbols are prefixed with hx_ to avoid changing either codebase.
; - ESC and Shift+ESC restore MiniWin and return to DOS; Ctrl+ESC hard reboots.
; =============================================================================
%define hx_STAGE2_START_LBA     3
%define hx_STAGE2_LOAD_SECTORS HEX_EDITOR_SECTORS
%define hx_STAGE2_LOAD_ADDR    0x7E00
; Reuse MiniWin's stack arena below 90000h.  The former stack entered the
; firmware EBDA window.
%define hx_STACK_SEG           0x8800
%define hx_STACK_TOP           0x7FFE
%if ((hx_STACK_SEG << 4) + hx_STACK_TOP) >= 0x90000
    %error "HEX stack enters the EBDA window"
%endif
%define hx_VIDEO_SEG           0xB800
%define hx_SCREEN_COLS         80
%define hx_SCREEN_ROWS         50
%define hx_DATA_ROWS           32
%define hx_BYTES_PER_ROW       16
%define hx_BYTES_PER_SECTOR    512
%define hx_MEMORY_FALLBACK_PAGES 2048
%define hx_HIGH_MEMORY_FIRST_PAGE 0x00800000 ; 4 GiB / 512
%define hx_PAE_WINDOW          0x00400000
%define hx_PAE_PDPT_PHYS       0x00010000
%define hx_PAE_PD_PHYS         0x00011000
%define hx_PAE_LOW_PT_PHYS     0x00012000
%define hx_PAE_WIN_PT_PHYS     0x00013000
%define hx_PM_IDT32_PHYS       0x00014000
%define hx_LM_IDT64_PHYS       0x00015000
; Keep the private PAE transition stack below 64 KiB. The exit path deliberately
; switches SS back to a 16-bit (D/B=0) descriptor before clearing CR0.PE, so
; both SP and ESP address the same stack and no stale high half can survive.
%define hx_LM_STACK_TOP        0x00007000
%define hx_PM_CODE_SEL         0x0008
%define hx_PM_DATA_SEL         0x0010
%define hx_LM_CODE_SEL         0x0018
%define hx_PM_CODE16_SEL       0x0020
%define hx_PM_DATA16_SEL       0x0028
%define hx_PM_TSS_SEL          0x0030
%define hx_HEX_COL             5
%define hx_ASCII_COL           57
%define hx_HISTORY_MAX         512
%define hx_FIND_TEXT_MAX       64
%define hx_SEARCH_CANCEL_POLL_INTERVAL 128
%define hx_BIOS_HDD_COUNT_ADDR 0x0475
%define hx_DISK_IO_CHS 0
%define hx_DISK_IO_EDD 1

%define hx_HEADER_ROW          0
%define hx_DATA_START_ROW      1

%define hx_MESSAGE_ROW         37
%define hx_JUMP_ROW            38
%define hx_JUMP_HELP_ROW       39
%define hx_STATUS_ROW          49
%define hx_JUMP_INPUT_COL      13
%define hx_MOUSE_SCREEN_MIN_COL  0
%define hx_MOUSE_SCREEN_MAX_COL  (hx_SCREEN_COLS-1)
%define hx_MOUSE_SCREEN_MIN_ROW  0
%define hx_MOUSE_SCREEN_MAX_ROW  (hx_SCREEN_ROWS-1)
%define hx_MOUSE_DATA_END_ROW    (hx_DATA_START_ROW + hx_DATA_ROWS - 1)
%define hx_MOUSE_HEX_END_COL     (hx_HEX_COL + (hx_BYTES_PER_ROW * 3) - 1)
%define hx_MOUSE_ASCII_END_COL   (hx_ASCII_COL + hx_BYTES_PER_ROW - 1)
%define hx_MOUSE_PS2_STEP 8

;%define Fill
;%define SourceCode

; Keep the editor physically after the complete default .text image.
; Using follows=.text avoids NASM treating the explicit start address in the
; ORG 7C00h address space and reporting an overlap.  vstart remains 7E00h
; because the editor is loaded and executed at physical 0000:7E00.
SECTION .hexeditor

hx_stage2_entry:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ax, hx_STACK_SEG
    mov ss, ax
    mov sp, hx_STACK_TOP
    ; HEX may be entered after firmware/debug code which left TF, RF, or a
    ; hardware breakpoint armed.  Owning vector 1 without first clearing that
    ; state turned an otherwise harmless key-buffer write into stop code 01.
    pushfd
    pop eax
    and eax, 0xFFFEFEFF           ; clear RF (bit 16) and TF (bit 8)
    push eax
    popfd
    xor eax, eax
    mov dr7, eax                  ; disable all hardware breakpoints
    mov eax, 0xFFFF0FF0
    mov dr6, eax                  ; clear stale debug-status indications
    xor eax, eax
    cld
    call hx_install_exception_hooks
    mov al, [hex_launch_mode]
    and al, 1
    mov [hx_memory_mode], al

    mov ax, 0x0003
    int 0x10
    ; Cache the ROM 8x16 font now; a later HEX panic must not call firmware.
    mov ax, 0x1130
    mov bh, 0x06
    int 0x10
    xor ax, ax
    mov ds, ax
    mov [BLUESCREEN_FONT_SEG_ADDR], es
    mov [BLUESCREEN_FONT_OFF_ADDR], bp
    mov es, ax
    mov ax, 0x1202
    mov bx, 0x0030
    int 0x10
    mov ax, 0x1112
    xor bx, bx
    int 0x10

    mov ah, 0x01
    mov ch, 0x06
    mov cl, 0x07
    int 0x10

    mov ax, 0x1003
    xor bx, bx
    int 0x10

    call hx_speaker_init
    call hx_init_state
    call hx_init_mouse_support
    cmp byte [hx_memory_mode], 0
    jne .memory_mode
    call hx_init_disk_state
    call hx_query_total_sectors
    jmp short .load_first_page
.memory_mode:
    call hx_init_memory_access
.load_first_page:
    call hx_load_current_sector
    sti
    jc hx_fatal_stage2_disk_error
    call hx_set_msg_loaded_current_lba
    call hx_draw_screen
    call hx_mouse_show_overlay

hx_main_loop:
.wait_input:
    mov byte [hx_watchdog_ticks], 0
    ; Give the BIOS keyboard queue priority.  PS/2 mouse polling is only
    ; reached when no complete key is pending and never drains port 60h data
    ; belonging to IRQ1.
    call hx_kbd_has_key
    jnz .have_key
    call hx_poll_mouse
    ; HEX also polls its mouse; do not sleep until an unrelated IRQ arrives.
    nop
    jmp .wait_input

.have_key:
    call hx_kbd_read_key
    cmp ah, 0x3B                ; F1
    je hx_show_help_page
    cmp ah, 0x3D
    je hx_handle_extended_key
    cmp ah, 0x3E                ; F4
    je hx_switch_next_drive_cmd
    cmp ah, 0x3F                ; F5: reread current 512-byte page
    je hx_refresh_cmd
    call hx_is_shift_down
    jnc .no_shift_prefilter
    cmp ah, 0x4B
    je hx_handle_extended_key
    cmp ah, 0x4D
    je hx_handle_extended_key
    cmp ah, 0x48
    je hx_handle_extended_key
    cmp ah, 0x50
    je hx_handle_extended_key
.no_shift_prefilter:

    cmp al, 0x1B
    je hx_handle_esc
    cmp al, 0x09
    je hx_toggle_mode
    cmp al, 0x13
    je hx_save_current_sector_cmd
    cmp al, 0x19
    je hx_undo_redo_dispatch
    cmp al, 0x1A
    je hx_undo_redo_dispatch
    cmp al, 0x11
    je hx_clear_current_sector_cmd
    cmp al, 0x07
    je hx_jump_to_lba_cmd
    cmp al, 0x06
    je hx_find_cmd
    cmp al, 0x03
    je hx_copy_selection_cmd
    cmp al, 0x18                ; Ctrl+X
    je hx_cut_selection_cmd
    cmp al, 0x01                ; Ctrl+A
    je hx_select_all_cmd
    cmp al, 0x16
    je hx_paste_clipboard_cmd
    cmp al, 0x7F                ; BIOS Ctrl+Backspace ASCII code
    je hx_ctrl_backspace_zero_cmd
    cmp al, 0x08
    jne .not_backspace
    ; Some BIOSes return 08h instead of 7Fh for Ctrl+Backspace, so also
    ; consult the live modifier flags while retaining ordinary Backspace.
    call hx_is_ctrl_down
    jc hx_ctrl_backspace_zero_cmd
    jmp hx_backspace_zero_cmd
.not_backspace:

    cmp byte [hx_edit_mode], 0
    jne hx_ascii_mode_dispatch

    cmp al, '-'
    je hx_prev_sector
    cmp al, '='
    je hx_next_sector

    cmp al, 0
    je hx_handle_extended_key
    cmp al, 0xE0
    je hx_handle_extended_key
    jmp hx_handle_hex_key

hx_show_help_page:
    call hx_mouse_hide_overlay
    ; Help is deliberately shown in standard 80x25 mode.  The editor itself
    ; remains an 80x50 interface and is restored before any editor redraw.
    mov ax, 0x0003
    int 0x10
    ; Paint all 80x25 cells blue with bright-white text (attribute 1Fh).
    mov ax, 0x0600
    mov bh, 0x1F
    xor cx, cx
    mov dx, 0x184F
    int 0x10
    mov ah, 0x02
    xor bh, bh
    xor dx, dx
    int 0x10
    mov si, hx_str_help_disk
    cmp byte [hx_memory_mode], 0
    je .print
    mov si, hx_str_help_memory
.print:
    lodsb
    test al, al
    jz .wait_key
    mov ah, 0x0E
    xor bh, bh
    mov bl, 0x1F
    int 0x10
    jmp .print
.wait_key:
    ; Every key, including Esc and function keys, returns to the editor.
    call hx_kbd_read_key
    ; Recreate the startup 80x50 text mode: 400 scan lines with the ROM 8x8
    ; font, a visible cursor, and intensity backgrounds instead of blinking.
    mov ax, 0x0003
    int 0x10
    mov ax, 0x1202
    mov bx, 0x0030
    int 0x10
    mov ax, 0x1112
    xor bx, bx
    int 0x10
    mov ah, 0x01
    mov ch, 0x06
    mov cl, 0x07
    int 0x10
    mov ax, 0x1003
    xor bx, bx
    int 0x10
    call hx_draw_screen
    call hx_mouse_show_overlay
    jmp hx_main_loop

hx_refresh_cmd:
    ; F5 is an unconditional reread, not a page change: do not ask to save and
    ; do not commit a pending half-byte. Preserve the old display buffer so a
    ; failed BIOS/physical-memory transfer cannot leave a partially read page.
    call hx_copy_sector_to_search_buffer
    call hx_load_current_sector
    jc .failed
    call hx_reset_edit_state_after_load
    call hx_set_msg_loaded_current_lba
    call hx_refresh_sector_area
    jmp hx_main_loop
.failed:
    call hx_copy_search_buffer_to_sector
    call hx_set_read_failure_msg
    call hx_beep
    call hx_refresh_sector_area
    jmp hx_main_loop

hx_undo_redo_dispatch:
    cmp al, 0x19
    je hx_redo_last_edit_cmd
    call hx_is_shift_down
    jc hx_redo_last_edit_cmd
    jmp hx_undo_last_edit_cmd

hx_ascii_mode_dispatch:
    cmp al, 0
    je hx_handle_extended_key
    cmp al, 0xE0
    je hx_handle_extended_key
    jmp hx_handle_ascii_key

hx_handle_ascii_key:
    call hx_commit_pending_hex_edit_if_needed
    mov bl, al
    mov ax, [hx_cursor_pos]
    mov [hx_old_cursor_pos], ax
    cmp bl, 0x20
    jb hx_main_loop
    cmp bl, 0x7F
    je hx_main_loop
    call hx_has_multi_selection
    pushf
    call hx_clear_selection
    call hx_edit_current_byte_ascii
    popf
    jc .full
    mov ax, [hx_old_cursor_pos]
    call hx_refresh_after_cursor_change
    jmp hx_main_loop
.full:
    call hx_refresh_sector_area
    jmp hx_main_loop

hx_handle_hex_key:
    call hx_ascii_hex_to_nibble
    jc hx_main_loop
    mov bl, al
    mov ax, [hx_cursor_pos]
    mov [hx_old_cursor_pos], ax
    call hx_has_multi_selection
    pushf
    call hx_clear_selection
    call hx_edit_current_byte_hex
    popf
    jc .full
    mov ax, [hx_old_cursor_pos]
    call hx_refresh_after_cursor_change
    jmp hx_main_loop
.full:
    call hx_refresh_sector_area
    jmp hx_main_loop

hx_handle_extended_key:
    mov bl, ah
    cmp bl, 0x3D
    je hx_find_next_cmd
.check_arrows:
    call hx_is_shift_down
    jc .shift
    cmp bl, 0x4B
    je hx_key_left
    cmp bl, 0x4D
    je hx_key_right
    cmp bl, 0x48
    je hx_key_up
    cmp bl, 0x50
    je hx_key_down
    jmp hx_main_loop
.shift:
    cmp bl, 0x4B
    je hx_key_shift_left
    cmp bl, 0x4D
    je hx_key_shift_right
    cmp bl, 0x48
    je hx_key_shift_up
    cmp bl, 0x50
    je hx_key_shift_down
    jmp hx_main_loop

hx_key_left:
    mov ax, [hx_cursor_pos]
    mov [hx_old_cursor_pos], ax
    call hx_commit_pending_hex_edit_if_needed
    call hx_has_multi_selection
    pushf
    call hx_clear_selection
    call hx_move_left
    popf
    jc .full
    mov ax, [hx_old_cursor_pos]
    call hx_refresh_after_cursor_change
    jmp hx_main_loop
.full:
    call hx_refresh_sector_area
    jmp hx_main_loop

hx_key_right:
    mov ax, [hx_cursor_pos]
    mov [hx_old_cursor_pos], ax
    call hx_commit_pending_hex_edit_if_needed
    call hx_has_multi_selection
    pushf
    call hx_clear_selection
    call hx_move_right
    popf
    jc .full
    mov ax, [hx_old_cursor_pos]
    call hx_refresh_after_cursor_change
    jmp hx_main_loop
.full:
    call hx_refresh_sector_area
    jmp hx_main_loop

hx_key_up:
    mov ax, [hx_cursor_pos]
    mov [hx_old_cursor_pos], ax
    call hx_commit_pending_hex_edit_if_needed
    call hx_has_multi_selection
    pushf
    call hx_clear_selection
    call hx_move_up
    popf
    jc .full
    mov ax, [hx_old_cursor_pos]
    call hx_refresh_after_cursor_change
    jmp hx_main_loop
.full:
    call hx_refresh_sector_area
    jmp hx_main_loop

hx_key_down:
    mov ax, [hx_cursor_pos]
    mov [hx_old_cursor_pos], ax
    call hx_commit_pending_hex_edit_if_needed
    call hx_has_multi_selection
    pushf
    call hx_clear_selection
    call hx_move_down
    popf
    jc .full
    mov ax, [hx_old_cursor_pos]
    call hx_refresh_after_cursor_change
    jmp hx_main_loop
.full:
    call hx_refresh_sector_area
    jmp hx_main_loop

hx_key_shift_left:
    mov ax, [hx_cursor_pos]
    mov [hx_old_cursor_pos], ax
    call hx_commit_pending_hex_edit_if_needed
    mov ax, [hx_old_cursor_pos]
    call hx_begin_selection_if_needed
    call hx_move_left
    call hx_finalize_shift_selection
    call hx_refresh_sector_area
    jmp hx_main_loop

hx_key_shift_right:
    mov ax, [hx_cursor_pos]
    mov [hx_old_cursor_pos], ax
    call hx_commit_pending_hex_edit_if_needed
    mov ax, [hx_old_cursor_pos]
    call hx_begin_selection_if_needed
    call hx_move_right
    call hx_finalize_shift_selection
    call hx_refresh_sector_area
    jmp hx_main_loop

hx_key_shift_up:
    mov ax, [hx_cursor_pos]
    mov [hx_old_cursor_pos], ax
    call hx_commit_pending_hex_edit_if_needed
    mov ax, [hx_old_cursor_pos]
    call hx_begin_selection_if_needed
    call hx_move_up
    call hx_finalize_shift_selection
    call hx_refresh_sector_area
    jmp hx_main_loop

hx_key_shift_down:
    mov ax, [hx_cursor_pos]
    mov [hx_old_cursor_pos], ax
    call hx_commit_pending_hex_edit_if_needed
    mov ax, [hx_old_cursor_pos]
    call hx_begin_selection_if_needed
    call hx_move_down
    call hx_finalize_shift_selection
    call hx_refresh_sector_area
    jmp hx_main_loop

hx_ctrl_backspace_zero_cmd:
    call hx_commit_pending_hex_edit_if_needed
    call hx_has_multi_selection
    jnc hx_backspace_zero_cmd
    call hx_zero_selected_range
    mov word [hx_msg_ptr], hx_msg_selection_zeroed
    call hx_refresh_sector_area
    jmp hx_main_loop

hx_backspace_zero_cmd:
    mov ax, [hx_cursor_pos]
    mov [hx_old_cursor_pos], ax
    call hx_commit_pending_hex_edit_if_needed
    call hx_has_multi_selection
    pushf
    call hx_clear_selection
    call hx_backspace_zero_current_byte
    popf
    jc .full
    mov ax, [hx_old_cursor_pos]
    call hx_refresh_after_cursor_change
    jmp hx_main_loop
.full:
    call hx_refresh_sector_area
    jmp hx_main_loop

hx_toggle_mode:
    call hx_commit_pending_hex_edit_if_needed
    xor byte [hx_edit_mode], 1
    mov byte [hx_hex_half], 0
    mov word [hx_msg_ptr], hx_msg_mode_switched
    call hx_refresh_meta_ui
    jmp hx_main_loop

hx_save_current_sector_cmd:
    call hx_commit_pending_hex_edit_if_needed
    call hx_save_current_sector
    call hx_refresh_meta_ui
    jmp hx_main_loop

hx_undo_last_edit_cmd:
    mov ax, [hx_cursor_pos]
    mov [hx_old_cursor_pos], ax
    call hx_commit_pending_hex_edit_if_needed
    call hx_has_multi_selection
    pushf
    call hx_clear_selection
    call hx_undo_last_action
    popf
    jc .full
    cmp al, 2
    je .full
    cmp al, 1
    je .byte
    call hx_refresh_meta_ui
    jmp hx_main_loop
.byte:
    mov ax, [hx_old_cursor_pos]
    call hx_refresh_after_cursor_change
    jmp hx_main_loop
.full:
    call hx_refresh_sector_area
    jmp hx_main_loop

hx_redo_last_edit_cmd:
    mov ax, [hx_cursor_pos]
    mov [hx_old_cursor_pos], ax
    call hx_commit_pending_hex_edit_if_needed
    call hx_has_multi_selection
    pushf
    call hx_clear_selection
    call hx_redo_last_action
    popf
    jc .full
    cmp al, 2
    je .full
    cmp al, 1
    je .byte
    call hx_refresh_meta_ui
    jmp hx_main_loop
.byte:
    mov ax, [hx_old_cursor_pos]
    call hx_refresh_after_cursor_change
    jmp hx_main_loop
.full:
    call hx_refresh_sector_area
    jmp hx_main_loop

hx_copy_selection_cmd:
    call hx_commit_pending_hex_edit_if_needed
    call hx_copy_selection_to_clipboard
    call hx_refresh_meta_ui
    jmp hx_main_loop

hx_cut_selection_cmd:
    call hx_commit_pending_hex_edit_if_needed
    call hx_cut_selection_to_clipboard_and_clear
    call hx_refresh_sector_area
    jmp hx_main_loop

hx_select_all_cmd:
    call hx_commit_pending_hex_edit_if_needed
    call hx_select_all_sector
    call hx_refresh_sector_area
    jmp hx_main_loop

hx_paste_clipboard_cmd:
    mov ax, [hx_cursor_pos]
    mov [hx_old_cursor_pos], ax
    call hx_commit_pending_hex_edit_if_needed
    call hx_has_multi_selection
    pushf
    call hx_clear_selection
    call hx_paste_clipboard_at_cursor
    popf
    jc .full
    cmp al, 0
    je .meta
.full:
    call hx_refresh_sector_area
    jmp hx_main_loop
.meta:
    call hx_refresh_meta_ui
    jmp hx_main_loop

hx_find_cmd:
    call hx_commit_pending_hex_edit_if_needed
    call hx_choose_find_mode_dialog
    cmp al, 0
    je .cancel
    mov [hx_find_mode], al
    call hx_preload_find_input_from_selection
    call hx_find_input_dialog
    cmp al, 0
    je .cancel
    call hx_build_find_pattern
    cmp cx, 0
    jne .search
    mov word [hx_msg_ptr], hx_msg_find_empty
    call hx_beep
    call hx_refresh_meta_ui
    jmp hx_main_loop
.search:
    mov [hx_find_pattern_len], cx
    mov byte [hx_last_find_valid], 1
    mov word [hx_msg_ptr], hx_msg_finding
    call hx_refresh_meta_ui
    call hx_reset_find_progress_timer
    mov ax, [hx_cursor_pos]
    mov si, ax
    call hx_find_pattern_across_disk
    cmp al, 2
    je .cancel
    cmp al, 1
    jne .not_found
    call hx_apply_find_hit_and_refresh
    jmp hx_main_loop
.not_found:
    cmp byte [hx_memory_mode], 0
    je .disk_not_found
    mov word [hx_msg_ptr], hx_msg_memory_find_not_found
    jmp short .not_found_ready
.disk_not_found:
    mov word [hx_msg_ptr], hx_msg_find_not_found
.not_found_ready:
    call hx_beep
    call hx_refresh_meta_ui
    jmp hx_main_loop
.cancel:
    mov word [hx_msg_ptr], hx_msg_find_cancel
    call hx_refresh_meta_ui
    jmp hx_main_loop

hx_find_next_cmd:
    call hx_commit_pending_hex_edit_if_needed
    cmp byte [hx_last_find_valid], 0
    jne .have_last
    mov word [hx_msg_ptr], hx_msg_find_no_previous
    call hx_beep
    call hx_refresh_meta_ui
    jmp hx_main_loop
.have_last:
    mov cx, [hx_find_pattern_len]
    cmp cx, 0
    jne .search
    mov word [hx_msg_ptr], hx_msg_find_no_previous
    call hx_beep
    call hx_refresh_meta_ui
    jmp hx_main_loop
.search:
    mov word [hx_msg_ptr], hx_msg_finding
    call hx_refresh_meta_ui
    call hx_reset_find_progress_timer
    call hx_get_selection_bounds
    mov si, dx
    cmp si, hx_BYTES_PER_SECTOR - 1
    jb .normal_next
    mov ax, hx_BYTES_PER_SECTOR
    jmp .do_search
.normal_next:
    inc si
    mov ax, si
.do_search:
    call hx_find_pattern_across_disk
    cmp al, 2
    je .cancel
    cmp al, 1
    jne .not_found
    call hx_apply_find_hit_and_refresh
    jmp hx_main_loop
.not_found:
    cmp byte [hx_memory_mode], 0
    je .disk_not_found
    mov word [hx_msg_ptr], hx_msg_memory_find_not_found
    jmp short .not_found_ready
.disk_not_found:
    mov word [hx_msg_ptr], hx_msg_find_not_found
.not_found_ready:
    call hx_beep
    call hx_refresh_meta_ui
    jmp hx_main_loop
.cancel:
    mov word [hx_msg_ptr], hx_msg_find_cancel
    call hx_refresh_meta_ui
    jmp hx_main_loop

hx_clear_current_sector_cmd:
    call hx_commit_pending_hex_edit_if_needed
    call hx_clear_selection
    call hx_confirm_clear_sector
    cmp al, 1
    jne hx_main_loop
    call hx_copy_sector_to_undo_snapshot
    mov byte [hx_clear_undo_available], 1
    mov byte [hx_clear_redo_available], 0
    mov word [hx_redo_count], 0
    mov word [hx_redo_action_count], 0
    mov word [hx_undo_count], 0
    mov word [hx_undo_action_count], 0
    mov byte [hx_pending_hex_active], 0
    call hx_clear_sector_buf
    call hx_refresh_dirty_flag_from_disk_snapshot
    call hx_set_edit_message_by_dirty
    mov byte [hx_hex_half], 0
    call hx_save_current_sector
    jc .refresh
    cmp byte [hx_memory_mode], 0
    je .disk_cleared
    mov word [hx_msg_ptr], hx_msg_memory_cleared_saved_ok
    jmp short .refresh
.disk_cleared:
    mov word [hx_msg_ptr], hx_msg_cleared_saved_ok
.refresh:
    call hx_refresh_sector_area
    jmp hx_main_loop

hx_jump_to_lba_cmd:
    call hx_commit_pending_hex_edit_if_needed
    cmp byte [hx_dirty_flag], 0
    je .go
    call hx_confirm_save_before_switch
    cmp al, 0
    je .abort
    cmp al, 1
    jne .go
    call hx_save_current_sector
    jc .abort_save_failed
.go:
    call hx_jump_to_lba_dialog
    call hx_refresh_sector_area
.abort:
    jmp hx_main_loop
.abort_save_failed:
    call hx_refresh_meta_ui
    jmp hx_main_loop

hx_set_msg_loaded_current_lba:
    cmp byte [hx_memory_mode], 0
    je .disk
    push eax
    push edx
    push si
    push di
    mov eax, [hx_curr_lba_lo]
    mov edx, [hx_curr_lba_hi]
    shld edx, eax, 9
    shl eax, 9
    mov di, hx_memory_addr_buf
    call hx_u64_to_hex
    mov di, hx_loaded_lba_msg_buf
    mov si, hx_str_loaded_memory_prefix
    call hx_copy_asciiz
    dec di
    mov si, hx_memory_addr_buf
    call hx_copy_asciiz
    dec di
    mov si, hx_str_loaded_memory_suffix
    call hx_copy_asciiz
    mov word [hx_msg_ptr], hx_loaded_lba_msg_buf
    pop di
    pop si
    pop edx
    pop eax
    ret
.disk:
    push eax
    push edx
    push si
    push di
    mov eax, [hx_curr_lba_lo]
    mov [hx_conv_qword + 0], eax
    mov eax, [hx_curr_lba_hi]
    mov [hx_conv_qword + 4], eax
    mov si, hx_conv_qword
    call hx_u64_to_dec
    mov di, hx_loaded_lba_msg_buf
    push si
    mov si, hx_str_loaded_lba_prefix
    call hx_copy_asciiz
    dec di
    pop si
    call hx_copy_asciiz
    dec di
    mov si, hx_str_loaded_lba_suffix
    call hx_copy_asciiz
    mov word [hx_msg_ptr], hx_loaded_lba_msg_buf
    pop di
    pop si
    pop edx
    pop eax
    ret

; -----------------------------------------------------------------------------
; Mouse support
; -----------------------------------------------------------------------------
%define hx_VMWARE_MAGIC                    0x564D5868
%define hx_VMWARE_PORT                     0x5658
%define hx_VMWARE_CMD_GETVERSION           10
%define hx_VMWARE_CMD_ABSPOINTER_DATA      39
%define hx_VMWARE_CMD_ABSPOINTER_STATUS    40
%define hx_VMWARE_CMD_ABSPOINTER_COMMAND   41
%define hx_VMWARE_CMD_ABSPOINTER_RESTRICT  86
%define hx_VMMOUSE_CMD_ENABLE              0x45414552
%define hx_VMMOUSE_CMD_DISABLE             0x000000F5
%define hx_VMMOUSE_CMD_REQUEST_ABSOLUTE    0x53424152
%define hx_VMMOUSE_VERSION_ID              0x3442554A
%define hx_VMMOUSE_RELATIVE_PACKET         0x00010000
%define hx_VMMOUSE_LEFT_BUTTON             0x20
%define hx_VMMOUSE_RIGHT_BUTTON            0x10
%define hx_VMMOUSE_MIDDLE_BUTTON           0x08
%define hx_VMMOUSE_ERROR                   0xFFFF0000
%define hx_VMMOUSE_RESTRICT_CPL0           0x01

hx_init_mouse_support:
    mov byte [hx_mouse_mode], 0
    mov byte [hx_mouse_col], hx_HEX_COL
    mov byte [hx_mouse_row], hx_DATA_START_ROW
    mov byte [hx_mouse_prev_col], hx_HEX_COL
    mov byte [hx_mouse_prev_row], hx_DATA_START_ROW
    mov word [hx_mouse_saved_cell], 0x0720
    mov byte [hx_mouse_overlay_visible], 0
    mov byte [hx_mouse_buttons], 0
    mov byte [hx_mouse_prev_buttons], 0
    mov byte [hx_mouse_drag_active], 0
    mov byte [hx_mouse_drag_moved], 0
    mov byte [hx_mouse_ps2_packet_size], 3
    mov byte [hx_mouse_ps2_pktcnt], 0
    mov word [hx_mouse_ps2_acc_x], 0
    mov word [hx_mouse_ps2_acc_y], 0
    mov byte [hx_mouse_wheel_delta], 0
    call hx_mouse_vmware_detect
    jc .use_ps2
    call hx_mouse_vmware_enable_abs
    jc .use_ps2
    mov byte [hx_mouse_mode], 1
    ret
.use_ps2:
    mov byte [hx_mouse_mode], 0
    call hx_mouse_ps2_init
    ret

hx_poll_mouse:
    cmp byte [hx_mouse_mode], 1
    jne .poll_ps2
    call hx_mouse_poll_vmware
    jmp .process
.poll_ps2:
    call hx_mouse_poll_ps2
.process:
    mov al, [hx_mouse_wheel_delta]
    cmp al, 0
    je .check_move
    mov byte [hx_mouse_wheel_delta], 0
    test al, al
    js .wheel_up
    jmp hx_next_sector
.wheel_up:
    jmp hx_prev_sector
.check_move:
    mov al, [hx_mouse_row]
    cmp al, [hx_mouse_prev_row]
    jne .moved
    mov al, [hx_mouse_col]
    cmp al, [hx_mouse_prev_col]
    jne .moved
    jmp .buttons
.moved:
    call hx_mouse_redraw_overlay
.buttons:
    mov al, [hx_mouse_buttons]
    mov bl, [hx_mouse_prev_buttons]
    test al, 1
    jz .left_up
    test bl, 1
    jz .left_press
    call hx_mouse_left_drag
    jmp .after_left
.left_press:
    call hx_mouse_left_press
    jmp .after_left
.left_up:
    test bl, 1
    jz .after_left
    call hx_mouse_left_release
.after_left:
    mov al, [hx_mouse_buttons]
    mov [hx_mouse_prev_buttons], al
    ret

hx_mouse_left_press:
    ; 先记录旧光标位置，后面用于局部刷新或整块刷新
    mov ax, [hx_cursor_pos]
    mov [hx_old_cursor_pos], ax

    ; 鼠标点击也要先提交半输入的 HEX 编辑
    call hx_commit_pending_hex_edit_if_needed

    ; 记录“按下前是否正处于多选状态”
    ; 如果之前有多选，那么清除后必须整块重绘，否则旧高亮会残留
    call hx_has_multi_selection
    pushf

    ; 命中测试：判断是否点到了数据区
    call hx_mouse_hit_test
    jc .outside

    ; 点在数据区内：移动到点击位置，并且无条件取消多选
    call hx_mouse_apply_hit
    call hx_clear_selection

    ; 进入拖拽候选状态
    mov byte [hx_mouse_drag_active], 1
    mov byte [hx_mouse_drag_moved], 0

    ; 如果按下前存在多选，则必须整块刷新，彻底擦掉旧选区
    popf
    jc .full_refresh

    ; 否则只做轻量刷新
    mov ax, [hx_old_cursor_pos]
    call hx_refresh_after_cursor_change
    ret

.outside:
    ; 点在数据区外：也要取消多选
    mov byte [hx_mouse_drag_active], 0
    mov byte [hx_mouse_drag_moved], 0
    call hx_clear_selection

    ; 如果按下前存在多选，则整块刷新，清掉全部旧高亮
    popf
    jc .full_refresh

    ; 没有旧多选时，只刷新元信息/当前光标显示即可
    mov ax, [hx_old_cursor_pos]
    call hx_refresh_after_cursor_change
    ret

.full_refresh:
    call hx_refresh_sector_area
    ret

hx_mouse_left_drag:
    cmp byte [hx_mouse_drag_active], 0
    je .done
    call hx_mouse_hit_test
    jc .done
    mov ax, [hx_mouse_hit_index]
    cmp ax, [hx_cursor_pos]
    jne .update
    cmp byte [hx_mouse_hit_mode], 0
    jne .same_ascii
    cmp byte [hx_edit_mode], 0
    jne .update
    mov al, [hx_mouse_hit_half]
    cmp al, [hx_hex_half]
    jne .update
    jmp .done
.same_ascii:
    cmp byte [hx_edit_mode], 1
    jne .update
    jmp .done
.update:
    call hx_mouse_apply_hit
    mov ax, [hx_cursor_pos]
    cmp ax, [hx_selection_anchor]
    jne .set_sel
    mov byte [hx_selection_active], 0
    jmp .refresh
.set_sel:
    mov byte [hx_selection_active], 1
    mov byte [hx_mouse_drag_moved], 1
.refresh:
    call hx_refresh_sector_area
.done:
    ret

hx_mouse_left_release:
    cmp byte [hx_mouse_drag_active], 0
    je .done
    mov byte [hx_mouse_drag_active], 0
    cmp byte [hx_mouse_drag_moved], 0
    jne .done
    mov byte [hx_selection_active], 0
.done:
    ret

hx_mouse_apply_hit:
    mov ax, [hx_mouse_hit_index]
    mov [hx_cursor_pos], ax
    cmp byte [hx_mouse_hit_mode], 0
    jne .ascii
    mov byte [hx_edit_mode], 0
    mov al, [hx_mouse_hit_half]
    mov [hx_hex_half], al
    ret
.ascii:
    mov byte [hx_edit_mode], 1
    mov byte [hx_hex_half], 0
    ret

hx_mouse_hit_test:
    push ax
    push bx
    push dx
    mov al, [hx_mouse_row]
    cmp al, hx_DATA_START_ROW
    jb .bad
    cmp al, hx_MOUSE_DATA_END_ROW + 1
    jae .bad
    sub al, hx_DATA_START_ROW
    xor bx, bx
    mov bl, al
    shl bx, 4
    mov al, [hx_mouse_col]
    cmp al, hx_HEX_COL
    jb .check_ascii
    cmp al, hx_MOUSE_HEX_END_COL + 1
    jae .check_ascii
    sub al, hx_HEX_COL
    xor ah, ah
    mov dl, 3
    div dl
    cmp ah, 2
    jne .hex_ok
    cmp al, 15
    ja .bad
.hex_ok:
    xor dx, dx
    mov dl, al
    add bx, dx
    mov [hx_mouse_hit_index], bx
    mov byte [hx_mouse_hit_mode], 0
    cmp ah, 2
    jne .store_half
    mov ah, 1
.store_half:
    mov [hx_mouse_hit_half], ah
    jmp .good
.check_ascii:
    mov al, [hx_mouse_col]
    cmp al, hx_ASCII_COL
    jb .bad
    cmp al, hx_MOUSE_ASCII_END_COL + 1
    jae .bad
    sub al, hx_ASCII_COL
    xor dx, dx
    mov dl, al
    add bx, dx
    mov [hx_mouse_hit_index], bx
    mov byte [hx_mouse_hit_mode], 1
    mov byte [hx_mouse_hit_half], 0
    jmp .good
.bad:
    pop dx
    pop bx
    pop ax
    stc
    ret
.good:
    pop dx
    pop bx
    pop ax
    clc
    ret

hx_mouse_hide_overlay:
    cmp byte [hx_mouse_overlay_visible], 0
    je .done
    push ax
    push dx
    push di
    push es
    mov dh, [hx_mouse_prev_row]
    mov dl, [hx_mouse_prev_col]
    mov ax, hx_VIDEO_SEG
    mov es, ax
    call hx_calc_vid_addr
    mov ax, [hx_mouse_saved_cell]
    mov es:[di], ax
    mov byte [hx_mouse_overlay_visible], 0
    pop es
    pop di
    pop dx
    pop ax
.done:
    ret

hx_mouse_show_overlay:
    push ax
    push bx
    push dx
    push di
    push es
    mov dh, [hx_mouse_row]
    mov dl, [hx_mouse_col]
    cmp byte [hx_mouse_overlay_visible], 0
    je .check_forbidden
    cmp dh, [hx_mouse_prev_row]
    jne .need_hide
    cmp dl, [hx_mouse_prev_col]
    jne .need_hide
    jmp .done
.need_hide:
    call hx_mouse_hide_overlay
.check_forbidden:
    mov [hx_mouse_prev_row], dh
    mov [hx_mouse_prev_col], dl
    cmp dh, 0
    jne .draw
    cmp dl, 0
    jne .draw
    mov byte [hx_mouse_overlay_visible], 0
    jmp .done
.draw:
    mov ax, hx_VIDEO_SEG
    mov es, ax
    call hx_calc_vid_addr
    mov ax, es:[di]
    mov [hx_mouse_saved_cell], ax
    mov bl, ah
    mov bh, bl
    and bl, 0x0F
    shl bl, 4
    shr bh, 4
    or bl, bh
    mov ah, bl
    mov es:[di], ax
    mov byte [hx_mouse_overlay_visible], 1
.done:
    pop es
    pop di
    pop dx
    pop bx
    pop ax
    ret

hx_mouse_redraw_overlay:
    call hx_mouse_show_overlay
    ret

hx_mouse_clamp_position:
    cmp byte [hx_mouse_col], hx_MOUSE_SCREEN_MIN_COL
    jae .col_hi
    mov byte [hx_mouse_col], hx_MOUSE_SCREEN_MIN_COL
.col_hi:
    cmp byte [hx_mouse_col], hx_MOUSE_SCREEN_MAX_COL
    jbe .row_lo
    mov byte [hx_mouse_col], hx_MOUSE_SCREEN_MAX_COL
.row_lo:
    cmp byte [hx_mouse_row], hx_MOUSE_SCREEN_MIN_ROW
    jae .row_hi
    mov byte [hx_mouse_row], hx_MOUSE_SCREEN_MIN_ROW
.row_hi:
    cmp byte [hx_mouse_row], hx_MOUSE_SCREEN_MAX_ROW
    jbe .done
    mov byte [hx_mouse_row], hx_MOUSE_SCREEN_MAX_ROW
.done:
    ret

hx_mouse_ps2_wait_input_clear:
    push cx
    mov cx, 0xFFFF
.wait:
    in al, 0x64
    test al, 2
    jz .ok
    loop .wait
    stc
    pop cx
    ret
.ok:
    clc
    pop cx
    ret

hx_mouse_ps2_wait_output_any:
    push cx
    mov cx, 0xFFFF
.wait:
    in al, 0x64
    test al, 1
    jnz .ok
    loop .wait
    stc
    pop cx
    ret
.ok:
    clc
    pop cx
    ret

hx_mouse_ps2_flush:
    push ax
    push cx
    mov cx, 0x1000
.loop:
    in al, 0x64
    test al, 1
    jz .done
    test al, 0x20
    jz .done                       ; leave keyboard bytes for BIOS IRQ1
    in al, 0x60
    loop .loop
.done:
    pop cx
    pop ax
    ret

hx_mouse_ps2_write_aux:
    push bx
    mov bl, al
    call hx_mouse_ps2_wait_input_clear
    jc .fail
    mov al, 0xD4
    out 0x64, al
    call hx_mouse_ps2_wait_input_clear
    jc .fail
    mov al, bl
    out 0x60, al
    pop bx
    clc
    ret
.fail:
    pop bx
    stc
    ret

hx_mouse_ps2_read_ack:
    call hx_mouse_ps2_wait_output_any
    jc .fail
    in al, 0x60
    cmp al, 0xFA
    jne .fail
    clc
    ret
.fail:
    stc
    ret

hx_mouse_ps2_send_cmd_expect_ack:
    push ax
    call hx_mouse_ps2_write_aux
    jc .err
    call hx_mouse_ps2_read_ack
    jc .err
    pop ax
    clc
    ret
.err:
    pop ax
    stc
    ret

hx_mouse_ps2_send_cmd_data_expect_ack:
    push ax
    push bx
    mov bl, al
    call hx_mouse_ps2_write_aux
    jc .err
    call hx_mouse_ps2_read_ack
    jc .err
    mov al, ah
    call hx_mouse_ps2_write_aux
    jc .err
    call hx_mouse_ps2_read_ack
    jc .err
    pop bx
    pop ax
    clc
    ret
.err:
    pop bx
    pop ax
    stc
    ret

hx_mouse_ps2_get_device_id:
    mov al, 0xF2
    call hx_mouse_ps2_send_cmd_expect_ack
    jc .fail
    call hx_mouse_ps2_wait_output_any
    jc .fail
    in al, 0x60
    clc
    ret
.fail:
    stc
    ret

hx_mouse_ps2_init:
    call hx_mouse_ps2_flush
    call hx_mouse_ps2_wait_input_clear
    jc .fail
    mov al, 0xA8
    out 0x64, al
    mov byte [hx_mouse_ps2_packet_size], 3
    mov al, 0xF6
    call hx_mouse_ps2_send_cmd_expect_ack
    jc .fail
    mov ax, 0xC8F3
    call hx_mouse_ps2_send_cmd_data_expect_ack
    jc .enable_stream
    mov ax, 0x64F3
    call hx_mouse_ps2_send_cmd_data_expect_ack
    jc .enable_stream
    mov ax, 0x50F3
    call hx_mouse_ps2_send_cmd_data_expect_ack
    jc .enable_stream
    call hx_mouse_ps2_get_device_id
    jc .enable_stream
    cmp al, 3
    jne .enable_stream
    mov byte [hx_mouse_ps2_packet_size], 4
.enable_stream:
    mov al, 0xF4
    call hx_mouse_ps2_send_cmd_expect_ack
.fail:
    ret

hx_mouse_ps2_try_read_byte:
    ; Status and data must be sampled atomically.  Most importantly, a byte
    ; with AUX=0 belongs to the keyboard: leave it in the controller so BIOS
    ; IRQ1 can translate it and place the exact key in the BIOS queue.
    pushf
    cli
    in al, 0x64
    test al, 1
    jz .none
    test al, 0x20
    jz .none
    in al, 0x60
    popf
    clc
    ret
.none:
    popf
    stc
    ret

hx_mouse_poll_ps2:
    mov byte [hx_mouse_wheel_delta], 0
.loop:
    call hx_mouse_ps2_try_read_byte
    jc .done
    xor bx, bx
    mov bl, [hx_mouse_ps2_pktcnt]
    mov [hx_mouse_ps2_pkt + bx], al
    inc byte [hx_mouse_ps2_pktcnt]
    cmp byte [hx_mouse_ps2_pktcnt], 1
    jne .check_full
    test al, 0x08
    jnz .check_full
    mov byte [hx_mouse_ps2_pktcnt], 0
    jmp .loop
.check_full:
    mov al, [hx_mouse_ps2_pktcnt]
    cmp al, [hx_mouse_ps2_packet_size]
    jb .loop
    mov byte [hx_mouse_ps2_pktcnt], 0
    mov al, [hx_mouse_ps2_pkt]
    test al, 0xC0
    jnz .loop
    mov al, [hx_mouse_ps2_pkt + 1]
    cbw
    add [hx_mouse_ps2_acc_x], ax
    mov al, [hx_mouse_ps2_pkt + 2]
    cbw
    neg ax
    add [hx_mouse_ps2_acc_y], ax
    call hx_mouse_apply_ps2_accum
    xor al, al
    mov bl, [hx_mouse_ps2_pkt]
    test bl, 1
    jz .no_l
    or al, 1
.no_l:
    test bl, 2
    jz .no_r
    or al, 2
.no_r:
    test bl, 4
    jz .no_m
    or al, 4
.no_m:
    mov [hx_mouse_buttons], al
    cmp byte [hx_mouse_ps2_packet_size], 4
    jne .loop
    mov al, [hx_mouse_ps2_pkt + 3]
    shl al, 4
    sar al, 4
    cmp al, 0
    je .loop
    js .wheel_neg
    mov byte [hx_mouse_wheel_delta], 1
    jmp .loop
.wheel_neg:
    mov byte [hx_mouse_wheel_delta], -1
    jmp .loop
.done:
    ret

hx_mouse_apply_ps2_accum:
.x_pos:
    mov ax, [hx_mouse_ps2_acc_x]
    cmp ax, hx_MOUSE_PS2_STEP
    jl .x_neg
    sub ax, hx_MOUSE_PS2_STEP
    mov [hx_mouse_ps2_acc_x], ax
    cmp byte [hx_mouse_col], hx_SCREEN_COLS - 1
    jae .x_pos
    inc byte [hx_mouse_col]
    jmp .x_pos

.x_neg:
    mov ax, [hx_mouse_ps2_acc_x]
    cmp ax, -hx_MOUSE_PS2_STEP
    jg .y_pos
    add ax, hx_MOUSE_PS2_STEP
    mov [hx_mouse_ps2_acc_x], ax
    cmp byte [hx_mouse_col], 0
    je .x_neg
    dec byte [hx_mouse_col]
    jmp .x_neg

.y_pos:
    mov ax, [hx_mouse_ps2_acc_y]
    cmp ax, hx_MOUSE_PS2_STEP
    jl .y_neg
    sub ax, hx_MOUSE_PS2_STEP
    mov [hx_mouse_ps2_acc_y], ax
    cmp byte [hx_mouse_row], hx_SCREEN_ROWS - 1
    jae .y_pos
    inc byte [hx_mouse_row]
    jmp .y_pos

.y_neg:
    mov ax, [hx_mouse_ps2_acc_y]
    cmp ax, -hx_MOUSE_PS2_STEP
    jg .done
    add ax, hx_MOUSE_PS2_STEP
    mov [hx_mouse_ps2_acc_y], ax
    cmp byte [hx_mouse_row], 0
    je .y_neg
    dec byte [hx_mouse_row]
    jmp .y_neg
.done:
    ret

hx_mouse_vmware_detect:
    mov eax, hx_VMWARE_MAGIC
    mov ebx, 0xFFFFFFFF
    mov ecx, hx_VMWARE_CMD_GETVERSION
    mov dx, hx_VMWARE_PORT
    in eax, dx
    cmp ebx, hx_VMWARE_MAGIC
    jne .no
    cmp eax, 0xFFFFFFFF
    je .no
    clc
    ret
.no:
    stc
    ret

hx_mouse_vmware_send_cmd:
    mov eax, hx_VMWARE_MAGIC
    mov ecx, hx_VMWARE_CMD_ABSPOINTER_COMMAND
    mov dx, hx_VMWARE_PORT
    in eax, dx
    ret

hx_mouse_vmware_status:
    mov eax, hx_VMWARE_MAGIC
    xor ebx, ebx
    mov ecx, hx_VMWARE_CMD_ABSPOINTER_STATUS
    mov dx, hx_VMWARE_PORT
    in eax, dx
    ret

hx_mouse_vmware_read4:
    mov eax, hx_VMWARE_MAGIC
    mov ebx, 4
    mov ecx, hx_VMWARE_CMD_ABSPOINTER_DATA
    mov dx, hx_VMWARE_PORT
    in eax, dx
    ret

hx_mouse_vmware_enable_abs:
    mov ebx, hx_VMMOUSE_CMD_ENABLE
    call hx_mouse_vmware_send_cmd
    call hx_mouse_vmware_status
    and eax, 0xFFFF
    jz .fail
    mov eax, hx_VMWARE_MAGIC
    mov ebx, 1
    mov ecx, hx_VMWARE_CMD_ABSPOINTER_DATA
    mov dx, hx_VMWARE_PORT
    in eax, dx
    cmp eax, hx_VMMOUSE_VERSION_ID
    jne .fail_disable
    mov eax, hx_VMWARE_MAGIC
    mov ebx, hx_VMMOUSE_RESTRICT_CPL0
    mov ecx, hx_VMWARE_CMD_ABSPOINTER_RESTRICT
    mov dx, hx_VMWARE_PORT
    in eax, dx
    mov ebx, hx_VMMOUSE_CMD_REQUEST_ABSOLUTE
    call hx_mouse_vmware_send_cmd
    clc
    ret
.fail_disable:
    mov ebx, hx_VMMOUSE_CMD_DISABLE
    call hx_mouse_vmware_send_cmd
.fail:
    stc
    ret

hx_mouse_poll_vmware:
    mov byte [hx_mouse_wheel_delta], 0
    call hx_mouse_vmware_status
    mov edx, eax
    and edx, hx_VMMOUSE_ERROR
    cmp edx, hx_VMMOUSE_ERROR
    je .done
    and eax, 0xFFFF
    cmp ax, 4
    jb .done
.loop:
    call hx_mouse_vmware_read4
    mov [hx_mouse_vm_tmp_x], bx
    mov [hx_mouse_vm_tmp_y], cx
    mov [hx_mouse_vm_tmp_z], dx
    xor bl, bl
    test ax, hx_VMMOUSE_LEFT_BUTTON
    jz .btn_r
    or bl, 1
.btn_r:
    test ax, hx_VMMOUSE_RIGHT_BUTTON
    jz .btn_m
    or bl, 2
.btn_m:
    test ax, hx_VMMOUSE_MIDDLE_BUTTON
    jz .btn_done
    or bl, 4
.btn_done:
    mov [hx_mouse_buttons], bl
    mov al, [hx_mouse_vm_tmp_z]
    cbw
    or ax, ax
    jz .no_wheel
    js .wheel_neg
    mov byte [hx_mouse_wheel_delta], 1
    jmp .no_wheel
.wheel_neg:
    mov byte [hx_mouse_wheel_delta], -1
.no_wheel:
    test eax, hx_VMMOUSE_RELATIVE_PACKET
    jnz .relative
    mov ax, [hx_mouse_vm_tmp_x]
    mov bx, hx_SCREEN_COLS
    mul bx
    mov al, dl
    mov [hx_mouse_col], al
    mov ax, [hx_mouse_vm_tmp_y]
    mov bx, hx_SCREEN_ROWS
    mul bx
    mov al, dl
    mov [hx_mouse_row], al
    jmp .next_status
.relative:
    mov bx, [hx_mouse_vm_tmp_x]
    xor ax, ax
    mov al, [hx_mouse_col]
    add ax, bx
    jns .rx_nonneg
    xor ax, ax
.rx_nonneg:
    cmp ax, hx_SCREEN_COLS - 1
    jle .rx_store
    mov ax, hx_SCREEN_COLS - 1
.rx_store:
    mov [hx_mouse_col], al
    mov bx, [hx_mouse_vm_tmp_y]
    xor ax, ax
    mov al, [hx_mouse_row]
    sub ax, bx
    jns .ry_nonneg
    xor ax, ax
.ry_nonneg:
    cmp ax, hx_SCREEN_ROWS - 1
    jle .ry_store
    mov ax, hx_SCREEN_ROWS - 1
.ry_store:
    mov [hx_mouse_row], al
.next_status:
    call hx_mouse_clamp_position
    call hx_mouse_vmware_status
    mov edx, eax
    and edx, hx_VMMOUSE_ERROR
    cmp edx, hx_VMMOUSE_ERROR
    je .done
    and eax, 0xFFFF
    cmp ax, 4
    jae .loop
.done:
    ret


hx_switch_next_drive_cmd:
    call hx_commit_pending_hex_edit_if_needed
    cmp byte [hx_memory_mode], 0
    je .disk_mode
    mov word [hx_msg_ptr], hx_msg_drive_memory_mode
    call hx_beep
    call hx_refresh_meta_ui
    jmp hx_main_loop
.disk_mode:

    cmp byte [hx_dirty_flag], 0
    je .go

    call hx_confirm_save_before_switch
    cmp al, 0
    je .abort
    cmp al, 1
    jne .go

    call hx_save_current_sector
    jc .abort_save_failed

.go:
    call hx_switch_to_next_hard_disk
    call hx_refresh_sector_area
    jmp hx_main_loop

.abort:
    jmp hx_main_loop

.abort_save_failed:
    call hx_refresh_meta_ui
    jmp hx_main_loop


hx_next_sector:
    call hx_commit_pending_hex_edit_if_needed
    call hx_can_increment_lba
    jnc .blocked
    cmp byte [hx_dirty_flag], 0
    je .go
    call hx_confirm_save_before_switch
    cmp al, 0
    je .abort
    cmp al, 1
    jne .go
    call hx_save_current_sector
    jc .abort_save_failed
.go:
    call hx_inc_current_lba
    call hx_load_current_sector
    jnc .ok
    call hx_dec_current_lba
    call hx_set_read_failure_msg
    call hx_beep
    call hx_refresh_sector_area
    jmp hx_main_loop
.ok:
    call hx_reset_edit_state_after_load
    call hx_set_msg_loaded_current_lba
    call hx_refresh_sector_area
    jmp hx_main_loop
.blocked:
    call hx_beep
.abort:
    jmp hx_main_loop
.abort_save_failed:
    call hx_refresh_meta_ui
    jmp hx_main_loop

hx_prev_sector:
    call hx_commit_pending_hex_edit_if_needed
    call hx_is_current_lba_zero
    jc .blocked
    cmp byte [hx_dirty_flag], 0
    je .go
    call hx_confirm_save_before_switch
    cmp al, 0
    je .abort
    cmp al, 1
    jne .go
    call hx_save_current_sector
    jc .abort_save_failed
.go:
    call hx_dec_current_lba
    call hx_load_current_sector
    jnc .ok
    call hx_inc_current_lba
    call hx_set_read_failure_msg
    call hx_beep
    call hx_refresh_sector_area
    jmp hx_main_loop
.ok:
    call hx_reset_edit_state_after_load
    call hx_set_msg_loaded_current_lba
    call hx_refresh_sector_area
    jmp hx_main_loop
.blocked:
    call hx_beep
.abort:
    jmp hx_main_loop
.abort_save_failed:
    call hx_refresh_meta_ui
    jmp hx_main_loop

hx_fatal_stage2_disk_error:
    call hx_clear_sector_buf
    call hx_copy_sector_to_undo_snapshot
    call hx_copy_sector_to_disk_snapshot
    call hx_set_read_failure_msg
    call hx_reset_edit_state_after_load
    call hx_draw_screen
    call hx_mouse_show_overlay
    jmp hx_main_loop

hx_soft_reboot:
    cli
    call hx_uninstall_exception_hooks
    jmp 0x0000:hex_return_loader

hx_hard_reboot:
    cli
    jmp hx_bsod_hard_reset

hx_reboot_system equ hx_soft_reboot

hx_handle_esc:
    call hx_is_ctrl_down
    jc hx_hard_reboot
    call hx_is_shift_down
    jc hx_soft_reboot
    cmp byte [hx_dirty_flag], 0
    je hx_soft_reboot
    push bx
    push cx
    push dx
    push si
    push di
    mov word [hx_dialog_line1_ptr], hx_str_save_prompt_reboot
    mov word [hx_dialog_line2_ptr], hx_str_save_help_reboot
    cmp byte [hx_memory_mode], 0
    je .exit_prompt_ready
    mov word [hx_dialog_line1_ptr], hx_str_save_prompt_memory_reboot
    mov word [hx_dialog_line2_ptr], hx_str_save_help_memory_reboot
.exit_prompt_ready:
    call hx_confirm_yes_no_esc_dialog
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    cmp al, 1
    je .save_and_reboot
    cmp al, 2
    je hx_soft_reboot
    jmp hx_main_loop
.save_and_reboot:
    call hx_save_current_sector
    cmp byte [hx_dirty_flag], 0
    jne hx_main_loop
    jmp hx_soft_reboot

hx_init_state:
    xor eax, eax
    mov [hx_curr_lba_lo], eax
    mov [hx_curr_lba_hi], eax
    mov [hx_total_lba_lo], eax
    mov [hx_total_lba_hi], eax
    mov word [hx_cursor_pos], 0
    mov word [hx_old_cursor_pos], 0
    mov word [hx_selection_anchor], 0
    mov word [hx_clipboard_len], 0
    mov word [hx_undo_count], 0
    mov word [hx_redo_count], 0
    mov word [hx_undo_action_count], 0
    mov word [hx_redo_action_count], 0
    mov byte [hx_selection_active], 0
    mov byte [hx_edit_mode], 0
    mov byte [hx_hex_half], 0
    mov byte [hx_dirty_flag], 0
    mov byte [hx_shift_prev], 0
    mov byte [hx_clear_undo_available], 0
    mov byte [hx_clear_redo_available], 0
    mov byte [hx_preserve_undo_after_save], 0
    mov byte [hx_rebase_undo_on_next_edit], 0
    mov byte [hx_pending_hex_active], 0
    mov byte [hx_find_mode], 0
    mov byte [hx_last_find_valid], 0
    mov byte [hx_kbd_pending_valid], 0
    mov byte [hx_search_cancelled_flag], 0
    mov byte [hx_memory_fail_reason], 0
    mov word [hx_kbd_pending_ax], 0
    mov word [hx_find_pattern_len], 0
    call hx_clear_find_buffer
    call hx_set_msg_loaded_current_lba
    mov word [hx_edd_params + 0], 0x001E
    mov word [hx_edd_params + 2], 0x0000
    ret

; -----------------------------------------------------------------------------
; HEX-local real-mode exception hooks and global blue screen
; -----------------------------------------------------------------------------
; The HEX payload replaces MiniWin at physical 7E00h, so it owns an equivalent
; set of hooks while resident.  They are removed before MiniWin is reloaded.

%macro HX_EXCEPTION_STUB 2
%1:
    push ax
    mov al, %2
    jmp hx_exception_common
%endmacro

%macro HX_SHARED_IRQ_STUB 3
%1:
    push ax
    push ds
    xor ax, ax
    mov ds, ax
    mov al, 0x0B
    out 0x20, al
    jmp short $+2
    in al, 0x20
    mov ah, al
    mov al, 0x0A
    out 0x20, al
    test ah, (1 << %3)
    jz %%cpu_fault
%if %2 = 8
    call hx_timer_irq
%else
    pushf
    call far [hx_old_ivt + (%2 * 4)]
%endif
    pop ds
    pop ax
    iret
%%cpu_fault:
    pop ds
    mov al, %2
    jmp hx_exception_common
%endmacro

HX_EXCEPTION_STUB hx_exception_00, 0
HX_EXCEPTION_STUB hx_exception_01, 1
HX_EXCEPTION_STUB hx_exception_02, 2
HX_EXCEPTION_STUB hx_exception_03, 3
HX_EXCEPTION_STUB hx_exception_04, 4
HX_EXCEPTION_STUB hx_exception_06, 6
HX_EXCEPTION_STUB hx_exception_07, 7
HX_SHARED_IRQ_STUB hx_exception_08, 8, 0
HX_SHARED_IRQ_STUB hx_exception_09, 9, 1
HX_SHARED_IRQ_STUB hx_exception_0a, 10, 2
HX_SHARED_IRQ_STUB hx_exception_0b, 11, 3
HX_SHARED_IRQ_STUB hx_exception_0c, 12, 4
HX_SHARED_IRQ_STUB hx_exception_0d, 13, 5
HX_SHARED_IRQ_STUB hx_exception_0e, 14, 6
HX_SHARED_IRQ_STUB hx_exception_0f, 15, 7

hx_exception_05:
    ; Distinguish a literal software INT 05h from a genuine BOUND exception.
    ; Software INT 05h is ignored and can never enter the HEX panic path.
    push ax
    push bx
    push ds
    push bp
    mov bp, sp
    mov bx, [ss:bp+8]
    cmp bx, 2
    jb .cpu_bound_fault
    mov ax, [ss:bp+10]
    mov ds, ax
    cmp byte [bx-2], 0xCD
    jne .cpu_bound_fault
    cmp byte [bx-1], 0x05
    jne .cpu_bound_fault
.software_int:
    pop bp
    pop ds
    pop bx
    pop ax
    iret
.cpu_bound_fault:
    pop bp
    pop ds
    pop bx
    mov al, 5
    jmp hx_exception_common

hx_timer_irq:
    inc dword [0x046C]
    cmp dword [0x046C], 0x001800B0
    jb .tick_ready
    sub dword [0x046C], 0x001800B0
    mov byte [0x0470], 1
.tick_ready:
    mov al, 0x20
    out 0x20, al
    cmp byte [hx_watchdog_ticks], 200
    jae .fatal
    inc byte [hx_watchdog_ticks]
    ret
.fatal:
    cmp byte [BLUESCREEN_ENABLE_ADDR], 0
    jne .show_blue_screen
    mov byte [hx_watchdog_ticks], 0
    ret
.show_blue_screen:
    mov al, BSOD_STOP_WATCHDOG
    jmp hx_blue_screen

hx_exception_common:
    ; When disabled, retain the interrupted stack and chain the original
    ; pre-HEX exception vector.  When enabled, the panic path discards it.
    push bx
    xor bx, bx
    mov bl, al
    push ds
    xor ax, ax
    mov ds, ax
    cmp byte [BLUESCREEN_ENABLE_ADDR], 0
    jne .blue_enabled
    shl bx, 1
    shl bx, 1
    pushf
    call far [hx_old_ivt + bx]
    pop ds
    pop bx
    pop ax
    iret
.blue_enabled:
    mov al, bl
    pop ds
    pop bx
    jmp hx_blue_screen

hx_install_exception_hooks:
    pushf
    cli
    pusha
    push ds
    push es
    xor ax, ax
    mov ds, ax
    mov es, ax
    cmp byte [hx_exception_hooks_installed], 0
    jne .done
    xor si, si
    mov di, hx_old_ivt
    mov cx, 32
    cld
    rep movsw

    mov ax, [0x040E]
    mov [hx_saved_bda_ebda], ax
    mov byte [hx_saved_ebda_kb], 0
    test ax, ax
    jz .ebda_saved
    mov es, ax
    mov al, es:[0]
    cmp al, 1
    jae .ebda_min_ready
    mov al, 1
.ebda_min_ready:
    cmp al, 128
    jbe .ebda_size_ready
    mov al, 128
.ebda_size_ready:
    mov [hx_saved_ebda_kb], al
    xor ax, ax
    mov es, ax
.ebda_saved:
    mov si, hx_exception_stub_offsets
    xor di, di
    mov cx, 16
.install:
    lodsw
    cmp di, (9 * 4)
    je .keep_bios_keyboard
    stosw
    xor ax, ax                    ; HEX executes with CS=0000h
    stosw
    jmp short .next
.keep_bios_keyboard:
    add di, 4
.next:
    loop .install
    mov byte [hx_exception_hooks_installed], 1
.done:
    pop es
    pop ds
    popa
    popf
    ret

hx_uninstall_exception_hooks:
    pushf
    cli
    pusha
    push ds
    push es
    xor ax, ax
    mov ds, ax
    mov es, ax
    cmp byte [hx_exception_hooks_installed], 0
    je .done
    mov si, hx_old_ivt
    xor di, di
    mov cx, 32
    cld
    rep movsw
    mov byte [hx_exception_hooks_installed], 0
.done:
    pop es
    pop ds
    popa
    popf
    ret

hx_blue_screen:
    ; AL=exception/internal reason. Reset the stack and program VGA directly so
    ; this works even after IVT/BDA/EBDA damage or from an 80x50 text screen.
    cli
    cld
    mov dl, al
    xor ax, ax
    mov ds, ax
    mov es, ax
    cmp byte [BLUESCREEN_ENABLE_ADDR], 0
    jne .blue_enabled
.blue_disabled_wait:
    xor si, si
    jmp hx_bsod_wait_ctrl_alt_del
.blue_enabled:
    mov [hx_panic_vector], dl
    mov ax, hx_STACK_SEG
    mov ss, ax
    mov sp, hx_STACK_TOP
    call hx_vga_set_text_80x25
    xor ax, ax
    mov ds, ax
    mov ax, hx_VIDEO_SEG
    mov es, ax
    xor di, di
    mov ax, 0x1F20
    mov cx, 80*25
    rep stosw
    mov si, hx_panic_title
    mov di, (0*80+25)*2
    call hx_bsod_puts
    mov si, hx_panic_line1
    mov di, (4*80+19)*2
    call hx_bsod_puts
    mov si, hx_panic_line2
    mov di, (6*80+26)*2
    call hx_bsod_puts
    mov si, hx_panic_line3
    mov di, (8*80+22)*2
    call hx_bsod_puts
    cmp byte [boot_autorestart], 0
    je .automatic_line_done
    mov si, hx_panic_line4
    mov di, (10*80+21)*2
    call hx_bsod_puts
.automatic_line_done:

    mov di, (21*80+2)*2
    cmp byte [hx_panic_vector], BSOD_STOP_CRITICAL_WRITE
    jne .check_watchdog
    mov si, hx_panic_critical_write_reason
    call hx_bsod_puts
    jmp short .stopcode
.check_watchdog:
    cmp byte [hx_panic_vector], BSOD_STOP_WATCHDOG
    jne .check_cpu
    mov si, hx_panic_watchdog_reason
    call hx_bsod_puts
    jmp short .stopcode
.check_cpu:
    cmp byte [hx_panic_vector], 16
    jae .internal_reason
.cpu_reason:
    mov si, hx_panic_reason
    call hx_bsod_puts
    mov al, [hx_panic_vector]
    call hx_bsod_hex_byte
    cmp byte [hx_panic_vector], 8
    jne .stopcode
    mov si, hx_panic_double_suffix
    call hx_bsod_puts
    jmp short .stopcode
.internal_reason:
    mov si, hx_panic_internal_reason
    call hx_bsod_puts
.stopcode:
    mov di, (23*80+2)*2
    mov si, hx_panic_stopcode_prefix
    call hx_bsod_puts
    mov al, [hx_panic_vector]
    call hx_bsod_hex_byte
.hide_cursor:
    mov dx, 0x03D4
    mov al, 0x0A
    out dx, al
    inc dx
    in al, dx
    or al, 0x20
    out dx, al
    cli
    xor si, si
    cmp byte [boot_autorestart], 0
    je hx_bsod_wait_ctrl_alt_del
    inc si
    jmp hx_bsod_wait_ctrl_alt_del

hx_bsod_wait_ctrl_alt_del:
    cli
    xor bx, bx
    mov cl, 15
    xor bp, bp
    mov al, 0x80
    out 0x70, al
    in al, 0x71
    mov ch, al
    mov al, [0x0417]
    test al, 0x04
    jz .seed_alt
    or bl, 0x01
.seed_alt:
    test al, 0x08
    jz .poll
    or bl, 0x02
.poll:
    inc bp
    test bp, 0x03FF
    jnz .keyboard
    mov al, 0x80
    out 0x70, al
    in al, 0x71
    cmp al, ch
    je .keyboard
    mov ch, al
    test si, si
    jz .keyboard
    dec cl
    push ax
    push dx
    push di
    mov al, cl
    aam 10
    mov dl, al
    mov al, ah
    test al, al
    jnz .tens
    mov al, ' '
    jmp short .put_tens
.tens:
    add al, '0'
.put_tens:
    mov ah, 0x1F
    mov di, (10*80+47)*2
    stosw
    mov al, dl
    add al, '0'
    mov ah, 0x1F
    stosw
    pop di
    pop dx
    pop ax
.count_ready:
    test cl, cl
    jz hx_bsod_hard_reset
.keyboard:
    mov dx, 0x0064
    in al, dx
    test al, 0x01
    jz .poll
    mov ah, al
    mov dx, 0x0060
    in al, dx
    test ah, 0x20
    jnz .clear_prefix
    cmp al, 0xE0
    je .e0_prefix
    cmp al, 0xF0
    je .f0_prefix
    cmp al, 0x1D
    je .ctrl_set1_make
    cmp al, 0x9D
    je .ctrl_set1_break
    cmp al, 0x38
    je .alt_set1_make
    cmp al, 0xB8
    je .alt_set1_break
    cmp al, 0x14
    je .ctrl_set2
    cmp al, 0x11
    je .alt_set2
    cmp al, 0x53
    je .delete_set1
    cmp al, 0x71
    jne .clear_prefix
    test bh, 0x01
    jz .clear_prefix
    test bh, 0x02
    jnz .clear_prefix
    jmp short .check_reset
.delete_set1:
    test bh, 0x02
    jnz .clear_prefix
.check_reset:
    mov al, [0x0417]
    test al, 0x04
    jz .check_bda_alt
    or bl, 0x01
.check_bda_alt:
    test al, 0x08
    jz .test_chord
    or bl, 0x02
.test_chord:
    mov al, bl
    and al, 0x03
    cmp al, 0x03
    je hx_bsod_hard_reset
.clear_prefix:
    xor bh, bh
    jmp .poll
.e0_prefix:
    or bh, 0x01
    jmp .poll
.f0_prefix:
    or bh, 0x02
    jmp .poll
.ctrl_set1_make:
    or bl, 0x01
    jmp .clear_prefix
.ctrl_set1_break:
    and bl, 0xFE
    jmp .clear_prefix
.alt_set1_make:
    or bl, 0x02
    jmp .clear_prefix
.alt_set1_break:
    and bl, 0xFD
    jmp .clear_prefix
.ctrl_set2:
    test bh, 0x02
    jnz .ctrl_set1_break
    jmp short .ctrl_set1_make
.alt_set2:
    test bh, 0x02
    jnz .alt_set1_break
    jmp short .alt_set1_make

hx_bsod_hard_reset:
    cli
    mov dx, 0x0CF9
    mov al, 0x06
    out dx, al
    mov dx, 0x0064
    mov al, 0xFE
    out dx, al
    lidt [hx_reset_null_idtr]
    int 3
.reset_pending:
    hlt
    jmp short .reset_pending

hx_vga_set_text_80x25:
    ; Direct standard VGA 720x400 text timing: 80x25 with 9x16 cells.
    push ax
    push bx
    push cx
    push dx
    push si

    mov dx, 0x03C2
    mov al, 0x67
    out dx, al

    mov si, hx_vga_text_seq
    xor bx, bx
    mov cx, 5
.seq_loop:
    mov dx, 0x03C4
    mov al, bl
    out dx, al
    inc dx
    lodsb
    out dx, al
    inc bl
    loop .seq_loop

    mov dx, 0x03D4
    mov al, 0x03
    out dx, al
    inc dx
    in al, dx
    or al, 0x80
    out dx, al
    dec dx
    mov al, 0x11
    out dx, al
    inc dx
    in al, dx
    and al, 0x7F
    out dx, al

    mov si, hx_vga_text_crtc
    xor bx, bx
    mov cx, 25
.crtc_loop:
    mov dx, 0x03D4
    mov al, bl
    out dx, al
    inc dx
    lodsb
    out dx, al
    inc bl
    loop .crtc_loop

    mov si, hx_vga_text_gc
    xor bx, bx
    mov cx, 9
.gc_loop:
    mov dx, 0x03CE
    mov al, bl
    out dx, al
    inc dx
    lodsb
    out dx, al
    inc bl
    loop .gc_loop

    mov si, hx_vga_text_ac
    xor bx, bx
    mov cx, 21
.ac_loop:
    mov dx, 0x03DA
    in al, dx
    mov dx, 0x03C0
    mov al, bl
    out dx, al
    lodsb
    out dx, al
    inc bl
    loop .ac_loop

    call hx_vga_load_font_8x16

    mov dx, 0x03DA
    in al, dx
    mov dx, 0x03C0
    mov al, 0x20
    out dx, al
    mov dx, 0x03C6
    mov al, 0xFF
    out dx, al
    call hx_vga_set_bsod_palette

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

hx_vga_load_font_8x16:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds
    push es
    mov ax, [BLUESCREEN_FONT_SEG_ADDR]
    test ax, ax
    jz .done
    mov si, [BLUESCREEN_FONT_OFF_ADDR]
    mov ds, ax
    mov ax, 0xA000
    mov es, ax

    mov dx, 0x03C4
    mov ax, 0x0402
    out dx, ax
    mov ax, 0x0704
    out dx, ax
    mov dx, 0x03CE
    mov ax, 0x0204
    out dx, ax
    mov ax, 0x0005
    out dx, ax
    mov ax, 0x0406
    out dx, ax

    xor di, di
    mov bp, 256
.glyph:
    mov cx, 16
    rep movsb
    add di, 16
    dec bp
    jnz .glyph

    mov dx, 0x03C4
    mov ax, 0x0302
    out dx, ax
    mov ax, 0x0304
    out dx, ax
    mov dx, 0x03CE
    mov ax, 0x0004
    out dx, ax
    mov ax, 0x1005
    out dx, ax
    mov ax, 0x0E06
    out dx, ax
.done:
    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

hx_vga_set_bsod_palette:
    ; The identity attribute table selects DAC 0Fh for white.  Mirror white to
    ; legacy entry 3Fh too, and restore the blue background without firmware.
    push ax
    push cx
    push dx
    mov cx, 3
.program:
    mov dx, 0x03C8
    mov al, 0x01
    out dx, al
    inc dx
    xor al, al
    out dx, al
    out dx, al
    mov al, 42
    out dx, al
    dec dx
    mov al, 0x0F
    out dx, al
    inc dx
    mov al, 63
    out dx, al
    out dx, al
    out dx, al
    dec dx
    mov al, 0x3F
    out dx, al
    inc dx
    mov al, 63
    out dx, al
    out dx, al
    out dx, al
    mov dx, 0x03C7
    mov al, 0x0F
    out dx, al
    mov dx, 0x03C9
    in al, dx
    cmp al, 63
    jne .retry
    in al, dx
    cmp al, 63
    jne .retry
    in al, dx
    cmp al, 63
    jne .retry
    mov dx, 0x03C7
    mov al, 0x3F
    out dx, al
    mov dx, 0x03C9
    in al, dx
    cmp al, 63
    jne .retry
    in al, dx
    cmp al, 63
    jne .retry
    in al, dx
    cmp al, 63
    je .done
.retry:
    loop .program
.done:
    pop dx
    pop cx
    pop ax
    ret

hx_vga_text_seq:
    db 0x03,0x00,0x03,0x00,0x02
hx_vga_text_crtc:
    db 0x5F,0x4F,0x50,0x82,0x55,0x81,0xBF,0x1F
    db 0x00,0x4F,0x0D,0x0E,0x00,0x00,0x00,0x50
    db 0x9C,0x0E,0x8F,0x28,0x1F,0x96,0xB9,0xA3,0xFF
hx_vga_text_gc:
    db 0x00,0x00,0x00,0x00,0x00,0x10,0x0E,0x00,0xFF
hx_vga_text_ac:
    db 0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07
    db 0x08,0x09,0x0A,0x0B,0x0C,0x0D,0x0E,0x0F
    db 0x0C,0x00,0x0F,0x08,0x00

hx_bsod_puts:
    lodsb
    test al, al
    jz .done
    mov ah, 0x1F
    stosw
    jmp hx_bsod_puts
.done:
    ret

hx_bsod_hex_byte:
    push ax
    push dx
    mov dl, al
    shr al, 4
    call hx_bsod_hex_nibble
    mov al, dl
    and al, 0x0F
    call hx_bsod_hex_nibble
    pop dx
    pop ax
    ret

hx_bsod_hex_nibble:
    cmp al, 10
    jb .digit
    add al, 'A'-10
    jmp short .emit
.digit:
    add al, '0'
.emit:
    mov ah, 0x1F
    stosw
    ret

hx_exception_stub_offsets:
    dw hx_exception_00, hx_exception_01, hx_exception_02, hx_exception_03
    dw hx_exception_04, hx_exception_05, hx_exception_06, hx_exception_07
    dw hx_exception_08, hx_exception_09, hx_exception_0a, hx_exception_0b
    dw hx_exception_0c, hx_exception_0d, hx_exception_0e, hx_exception_0f
hx_exception_hooks_installed db 0
hx_panic_vector db 0xFF
hx_watchdog_ticks db 0
hx_old_ivt times (16*4) db 0
hx_saved_bda_ebda dw 0
hx_saved_ebda_kb db 0
hx_reset_null_idtr:
    dw 0
    dq 0
hx_panic_title  db '*** SYSTEM CRITICAL ERROR ***',0
hx_panic_line1  db 'The system can no longer continue safely.',0
hx_panic_line2  db 'Please restart the computer.',0
hx_panic_line3  db 'Press Ctrl+Alt+Del to hard restart.',0
hx_panic_line4  db 'Automatic hard restart in 15 seconds.',0
hx_panic_reason db 'Reason: HEX CPU exception 0x',0
hx_panic_critical_write_reason db 'Reason: critical live-memory write detected',0
hx_panic_watchdog_reason db 'Reason: HEX execution watchdog timeout',0
hx_panic_internal_reason db 'Reason: unrecoverable internal system failure',0
hx_panic_stopcode_prefix db 'Stopcode: 0x',0
hx_panic_double_suffix db ' - Double fault',0

hx_reset_edit_state_after_load:
    mov word [hx_cursor_pos], 0
    mov word [hx_old_cursor_pos], 0
    mov word [hx_selection_anchor], 0
    mov word [hx_undo_count], 0
    mov word [hx_redo_count], 0
    mov word [hx_undo_action_count], 0
    mov word [hx_redo_action_count], 0
    mov byte [hx_selection_active], 0
    mov byte [hx_hex_half], 0
    mov byte [hx_dirty_flag], 0
    mov byte [hx_clear_undo_available], 0
    mov byte [hx_clear_redo_available], 0
    mov byte [hx_preserve_undo_after_save], 0
    mov byte [hx_rebase_undo_on_next_edit], 0
    mov byte [hx_pending_hex_active], 0
    mov byte [hx_search_cancelled_flag], 0
    ret

hx_is_current_lba_zero:
    mov eax, [hx_curr_lba_lo]
    mov edx, [hx_curr_lba_hi]
    or eax, edx
    jz .zero
    clc
    ret
.zero:
    stc
    ret

hx_can_increment_lba:
    mov eax, [hx_total_lba_lo]
    mov edx, [hx_total_lba_hi]
    or eax, edx
    jz .yes
    mov eax, [hx_curr_lba_lo]
    mov edx, [hx_curr_lba_hi]
    add eax, 1
    adc edx, 0
    cmp edx, [hx_total_lba_hi]
    jb .yes
    ja .no
    cmp eax, [hx_total_lba_lo]
    jb .yes
.no:
    clc
    ret
.yes:
    stc
    ret

hx_inc_current_lba:
    mov eax, [hx_curr_lba_lo]
    add eax, 1
    mov [hx_curr_lba_lo], eax
    mov eax, [hx_curr_lba_hi]
    adc eax, 0
    mov [hx_curr_lba_hi], eax
    ret

hx_dec_current_lba:
    mov eax, [hx_curr_lba_lo]
    sub eax, 1
    mov [hx_curr_lba_lo], eax
    mov eax, [hx_curr_lba_hi]
    sbb eax, 0
    mov [hx_curr_lba_hi], eax
    ret

; -----------------------------------------------------------------------------
; Physical-memory access (v15-fix7)
; A20 removes the 1 MiB wrap.  The stable BIOS AH=87h block-move service owns
; 1 MiB through 4 GiB-1. Addresses at 4 GiB and above use 32-bit PAE paging
; with one 4 KiB window. Long Mode is deliberately not entered: PAE already
; carries a 52-bit PTE physical address and has a much smaller, more
; compatible transition surface on BIOS/VM firmware. A real 16-bit data/stack
; descriptor is loaded before clearing PE so no cached SS.D/B=1 can escape.
;
; E820 usable/ACPI lengths supply the displayed/navigable installed capacity;
; the highest E820 end is kept separately because PCI/MMIO holes can be
; remapped above 4 GiB.  Treating that endpoint as capacity made 8 GiB appear
; as 9 GiB and made VirtualBox 4 GiB appear as 4.5 GiB. MAXPHYADDR is only a
; paging-entry validity limit and never represents installed RAM.
; The high transfer additionally forces IA32_EFER.LME=0 before enabling paging;
; otherwise CR4.PAE+CR0.PG can select 4-level paging instead of legacy PAE.
; -----------------------------------------------------------------------------

hx_init_memory_access:
    call hx_enable_a20
    ; 0=first MiB, 1=BIOS87 through 4 GiB, 2=BIOS87 + PAE raw physical window.
    mov byte [hx_memory_backend], 0
    mov byte [hx_pae_available], 0
    mov byte [hx_efer_available], 0
    jc .fallback_a20
    call hx_detect_pae_support
    jc .cpu_checked
    mov byte [hx_pae_available], 1
.cpu_checked:
    call hx_detect_e820_memory
    jc .fallback_e820
    ; Some legacy BIOS E820 implementations leave A20 in a different state.
    ; Re-enable it after the final firmware map call, not only before E820.
    call hx_enable_a20
    jc .fallback_a20
    mov byte [hx_memory_backend], 1
    cmp byte [hx_pae_available], 0
    je .flat_only
    mov byte [hx_memory_backend], 2
    ret
.flat_only:
    ; INT 15h/AH=87h descriptors carry only a 32-bit base.
    cmp dword [hx_total_lba_hi], 0
    jne .clamp_flat
    cmp dword [hx_total_lba_lo], 0x00800000
    jbe .flat_ready
.clamp_flat:
    mov dword [hx_total_lba_lo], 0x00800000
    mov dword [hx_total_lba_hi], 0
    call hx_update_memory_max_from_total
.flat_ready:
    mov word [hx_msg_ptr], hx_msg_memory_flat_ready
    ret
.fallback_e820:
    mov word [hx_msg_ptr], hx_msg_memory_e820_failed
    jmp short .set_fallback_limit
.fallback_a20:
    mov word [hx_msg_ptr], hx_msg_memory_a20_failed
    jmp short .set_fallback_limit
.set_fallback_limit:
    mov dword [hx_total_lba_lo], hx_MEMORY_FALLBACK_PAGES
    mov dword [hx_total_lba_hi], 0
    call hx_update_memory_max_from_total
    ret

hx_enable_a20:
    call hx_check_a20
    jnc .ready
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds
    push es
    mov ax, 0x2401
    int 0x15
    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    call hx_check_a20
    jnc .ready
    push ax
    in al, 0x92
    or al, 0x02
    and al, 0xFE
    out 0x92, al
    pop ax
    call hx_check_a20
    jnc .ready
    ; Last portable fallback for BIOSes/VMs which ignore INT 15h/2401h and
    ; port 92h: update the 8042 keyboard-controller output port.
    call hx_enable_a20_kbc
    jc .failed
    call hx_check_a20
    ret
.ready:
    clc
    ret
.failed:
    stc
    ret

hx_enable_a20_kbc:
    push ax
    push bx
    mov bh, 0

    call hx_kbc_wait_input_clear
    jc .failed
    mov al, 0xAD                    ; disable keyboard interface
    out 0x64, al

    ; Discard a pending controller byte before requesting the output port.
    in al, 0x64
    test al, 0x01
    jz .request_output
    in al, 0x60
.request_output:
    call hx_kbc_wait_input_clear
    jc .failed_enable
    mov al, 0xD0
    out 0x64, al
    call hx_kbc_wait_output_full
    jc .failed_enable
    in al, 0x60
    mov bl, al
    or bl, 0x03                    ; A20 on; never assert active-low reset

    call hx_kbc_wait_input_clear
    jc .failed_enable
    mov al, 0xD1
    out 0x64, al
    call hx_kbc_wait_input_clear
    jc .failed_enable
    mov al, bl
    out 0x60, al
    call hx_kbc_wait_input_clear
    jc .failed_enable
    jmp short .enable_keyboard

.failed_enable:
    mov bh, 1
.enable_keyboard:
    call hx_kbc_wait_input_clear
    jnc .send_enable
    mov bh, 1
    jmp short .finish
.send_enable:
    mov al, 0xAE                    ; re-enable keyboard interface
    out 0x64, al
.finish:
    cmp bh, 0
    jne .failed
    pop bx
    pop ax
    clc
    ret
.failed:
    pop bx
    pop ax
    stc
    ret

hx_kbc_wait_input_clear:
    push ax
    push cx
    mov cx, 0xFFFF
.wait:
    in al, 0x64
    test al, 0x02
    jz .ready
    loop .wait
    pop cx
    pop ax
    stc
    ret
.ready:
    pop cx
    pop ax
    clc
    ret

hx_kbc_wait_output_full:
    push ax
    push cx
    mov cx, 0xFFFF
.wait:
    in al, 0x64
    test al, 0x01
    jnz .ready
    loop .wait
    pop cx
    pop ax
    stc
    ret
.ready:
    pop cx
    pop ax
    clc
    ret

hx_check_a20:
    ; Compare 0000:0500 with FFFF:0510 (physical 100500h).  Restore both
    ; bytes before returning. CF=0 means address line 20 is really enabled.
    pushf
    cli
    push ax
    push bx
    push si
    push di
    push ds
    push es
    xor ax, ax
    mov ds, ax
    mov si, 0x0500
    mov ax, 0xFFFF
    mov es, ax
    mov di, 0x0510
    mov bl, [ds:si]
    mov bh, [es:di]
    mov byte [ds:si], 0x00
    mov byte [es:di], 0xFF
    cmp byte [ds:si], 0xFF
    pushf
    mov [es:di], bh
    mov [ds:si], bl
    popf
    je .disabled
    pop es
    pop ds
    pop di
    pop si
    pop bx
    pop ax
    popf
    clc
    ret
.disabled:
    pop es
    pop ds
    pop di
    pop si
    pop bx
    pop ax
    popf
    stc
    ret

hx_detect_pae_support:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    mov byte [hx_phys_addr_bits], 36
    pushfd
    pop eax
    mov ecx, eax
    xor eax, 0x00200000
    push eax
    popfd
    pushfd
    pop eax
    push ecx
    popfd
    xor eax, ecx
    test eax, 0x00200000
    jz .fail

    xor eax, eax
    cpuid
    cmp eax, 1
    jb .fail

    mov eax, 1
    cpuid
    test edx, (1 << 6)             ; PAE provides 64-bit paging entries
    jz .fail
    mov bl, 0
    test edx, (1 << 5)             ; RDMSR/WRMSR instruction support
    jz .basic_ready
    mov bl, 1
.basic_ready:

    mov eax, 0x80000000
    cpuid
    mov esi, eax
    cmp esi, 0x80000001
    jb .check_width
    cmp bl, 0
    je .check_width
    mov eax, 0x80000001
    cpuid
    test edx, (1 << 29)            ; Intel 64 => IA32_EFER.LME exists
    jz .check_width
    mov byte [hx_efer_available], 1
.check_width:
    cmp esi, 0x80000008
    jb .ready
    mov eax, 0x80000008
    cpuid
    cmp al, 32
    jb .ready
    cmp al, 52
    jbe .store_width
    mov al, 52
.store_width:
    mov [hx_phys_addr_bits], al

.ready:
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    clc
    ret
.fail:
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    stc
    ret

hx_detect_e820_memory:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push es
    mov word [hx_e820_guard], 256
    xor eax, eax
    mov [hx_memory_end_lo], eax
    mov [hx_memory_end_hi], eax
    mov [hx_memory_size_lo], eax
    mov [hx_memory_size_hi], eax
    mov [hx_e820_cont], eax
    xor ebx, ebx
.next:
    xor ax, ax
    mov es, ax
    mov dword [hx_e820_entry + 20], 1
    mov eax, 0x0000E820
    mov edx, 0x534D4150
    mov ecx, 24
    mov di, hx_e820_entry
    int 0x15
    ; E820 returns through ES:DI, but a few legacy BIOSes still clobber DS.
    ; Restore the editor's flat real-mode data segment before touching state.
    pushf
    push eax
    xor ax, ax
    mov ds, ax
    pop eax
    popf
    jc .finish
    cmp eax, 0x534D4150
    jne .fail
    mov [hx_e820_cont], ebx
    cmp ecx, 20
    jb .continue
    ; Types 1, 3 and 4 all occupy installed RAM. Types 3/4 are reserved for
    ; ACPI use but still count toward DIMM/VM capacity. MMIO/type-2 holes do
    ; not count; their relocated RAM is reported separately above 4 GiB.
    cmp dword [hx_e820_entry + 16], 1
    je .check_attributes
    cmp dword [hx_e820_entry + 16], 3
    je .check_attributes
    cmp dword [hx_e820_entry + 16], 4
    jne .continue
.check_attributes:
    cmp ecx, 24
    jb .counted_ram
    test dword [hx_e820_entry + 20], 1
    jz .continue
.counted_ram:
    mov eax, [hx_e820_entry + 8]
    mov edx, [hx_e820_entry + 12]
    or eax, edx
    jz .continue

    ; Capacity is the sum of RAM-backed ranges, not the highest physical end.
    mov eax, [hx_memory_size_lo]
    mov edx, [hx_memory_size_hi]
    add eax, [hx_e820_entry + 8]
    adc edx, [hx_e820_entry + 12]
    mov [hx_memory_size_lo], eax
    mov [hx_memory_size_hi], edx

    ; Keep the endpoint separately for diagnostics/remapping logic.
    mov eax, [hx_e820_entry + 0]
    mov edx, [hx_e820_entry + 4]
    add eax, [hx_e820_entry + 8]
    adc edx, [hx_e820_entry + 12]
    cmp edx, [hx_memory_end_hi]
    jb .continue
    ja .store_end
    cmp eax, [hx_memory_end_lo]
    jbe .continue
.store_end:
    mov [hx_memory_end_lo], eax
    mov [hx_memory_end_hi], edx
.continue:
    dec word [hx_e820_guard]
    jz .finish
    mov ebx, [hx_e820_cont]
    test ebx, ebx
    jnz .next
.finish:
    mov eax, [hx_memory_size_lo]
    mov edx, [hx_memory_size_hi]
    mov ecx, eax
    or ecx, edx
    jz .fail

    ; E820 excludes small legacy/firmware reservations inside installed RAM.
    ; Capacity is conventionally MiB-granular, so round the accumulated
    ; RAM-backed length upward to the next MiB. This recovers 4/8 GiB VM sizes
    ; without counting the relocated PCI/MMIO hole twice.
    add eax, 0x000FFFFF
    adc edx, 0
    and eax, 0xFFF00000

    ; Never let a broken map exceed MAXPHYADDR. CPUID.80000008:EAX[7:0] is
    ; capped at the architectural 52-bit paging-structure limit.
    movzx ecx, byte [hx_phys_addr_bits]
    sub ecx, 32
    mov ebx, 1
    shl ebx, cl
    cmp edx, ebx
    jb .physical_end_valid
    ja .clamp_physical_end
    test eax, eax
    jz .physical_end_valid
.clamp_physical_end:
    xor eax, eax
    mov edx, ebx
.physical_end_valid:
    ; The rounded size is already divisible by 512.
    shrd eax, edx, 9
    shr edx, 9
    mov ecx, eax
    or ecx, edx
    jz .fail
    mov [hx_total_lba_lo], eax
    mov [hx_total_lba_hi], edx
    call hx_update_memory_max_from_total
    pop es
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    clc
    ret
.fail:
    pop es
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    stc
    ret

hx_update_memory_max_from_total:
    push eax
    push edx
    mov eax, [hx_total_lba_lo]
    mov edx, [hx_total_lba_hi]
    shld edx, eax, 9
    shl eax, 9
    sub eax, 1
    sbb edx, 0
    mov [hx_memory_max_addr_lo], eax
    mov [hx_memory_max_addr_hi], edx
    pop edx
    pop eax
    ret

; v11 crash source: hx_flat_transfer entered 32-bit protected mode directly.
; VMware can terminate the VCPU when that transition/return path leaves a
; stale or invalid hidden segment state.  v12 removes the function completely.
hx_bios87_transfer:
    ; hx_pm_operation: 0=physical page -> low buffer, 1=low buffer -> page.
    ; hx_pm_phys_hi must be zero.  CF=1 and hx_bios87_status contains the BIOS
    ; status if the firmware cannot perform the 512-byte block move.
    pushf
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es
    cld
    xor dx, dx
    mov ds, dx
    mov es, dx

    mov di, hx_bios87_gdt
    mov cx, 24
    xor ax, ax
    rep stosw

    mov eax, [hx_pm_phys_lo]
    mov ebx, [hx_pm_buffer]
    cmp byte [hx_pm_operation], 0
    je .bases_ready
    xchg eax, ebx
.bases_ready:
    mov di, hx_bios87_gdt+0x10
    call hx_build_bios87_descriptor
    mov eax, ebx
    mov di, hx_bios87_gdt+0x18
    call hx_build_bios87_descriptor

    xor dx, dx
    mov es, dx
    mov si, hx_bios87_gdt
    mov cx, hx_BYTES_PER_SECTOR / 2
    mov ax, 0x8700
    int 0x15
    mov [hx_bios87_status], ah
    mov byte [hx_bios87_failed], 0
    jc .failed
    test ah, ah
    jz .restore
.failed:
    mov byte [hx_bios87_failed], 1
.restore:
    pop es
    pop ds
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    popf
    cmp byte [hx_bios87_failed], 0
    jne .return_failed
    clc
    ret
.return_failed:
    stc
    ret

hx_build_bios87_descriptor:
    ; EAX=32-bit physical base, DS:DI=8-byte descriptor.
    mov word [di+0], 0xFFFF
    mov [di+2], ax
    shr eax, 16
    mov [di+4], al
    mov byte [di+5], 0x93
    mov byte [di+6], 0x00
    mov [di+7], ah
    ret

hx_validate_high_memory_page:
    ; Raw physical access is bounded by CPUID.MAXPHYADDR, not by E820 type.
    ; E820 classifies installed RAM; it is not an access map for firmware,
    ; reserved, or MMIO pages. Reject only reserved PTE bits and 512-byte
    ; requests which wrap or cross the architectural physical-address limit.
    push eax
    push ecx
    push edx
    movzx ecx, byte [hx_phys_addr_bits]
    sub ecx, 32
    mov edx, 1
    shl edx, cl                    ; exclusive high-dword limit
    mov eax, [hx_pm_phys_lo]
    mov ecx, [hx_pm_phys_hi]
    add eax, hx_BYTES_PER_SECTOR - 1
    adc ecx, 0
    jc .invalid
    cmp ecx, edx
    jae .invalid
    pop edx
    pop ecx
    pop eax
    clc
    ret
.invalid:
    pop edx
    pop ecx
    pop eax
    stc
    ret

hx_prepare_pae_tables:
    push eax
    push ebx
    push cx
    push si
    push di
    push es
    cld

    ; PAE uses a four-entry PDPT. Identity-map the first 2 MiB with ordinary
    ; 4 KiB PTEs so no PSE dependency exists. Linear 00400000h is a separate
    ; one-entry window for the requested physical frame.
    mov ax, hx_PAE_PDPT_PHYS >> 4
    call .clear_page
    mov ax, hx_PAE_PD_PHYS >> 4
    call .clear_page
    mov ax, hx_PAE_LOW_PT_PHYS >> 4
    call .clear_page
    mov ax, hx_PAE_WIN_PT_PHYS >> 4
    call .clear_page
    mov ax, hx_PM_IDT32_PHYS >> 4
    call .clear_page

    mov ax, hx_PAE_PDPT_PHYS >> 4
    mov es, ax
    ; In legacy 32-bit PAE, PDPTE bit 1 is reserved (unlike IA-32e).
    mov dword es:[0], hx_PAE_PD_PHYS | 0x00000001
    mov dword es:[4], 0

    mov ax, hx_PAE_PD_PHYS >> 4
    mov es, ax
    mov dword es:[0], hx_PAE_LOW_PT_PHYS | 0x00000003
    mov dword es:[4], 0
    mov dword es:[16], hx_PAE_WIN_PT_PHYS | 0x00000003
    mov dword es:[20], 0

    ; 512 PTEs cover 00000000h..001FFFFFh.
    mov ax, hx_PAE_LOW_PT_PHYS >> 4
    mov es, ax
    xor di, di
    mov eax, 0x00000003
    mov cx, 512
.identity_loop:
    mov dword es:[di+0], eax
    mov dword es:[di+4], 0
    add eax, 0x1000
    add di, 8
    loop .identity_loop

    mov ax, hx_PAE_WIN_PT_PHYS >> 4
    mov es, ax
    mov eax, [hx_pm_phys_lo]
    and eax, 0xFFFFF000
    or eax, 0x00000003
    mov dword es:[0], eax
    mov eax, [hx_pm_phys_hi]
    and eax, 0x000FFFFF
    mov dword es:[4], eax

    ; One ordinary protected-mode IDT owns the whole PAE transition.
    mov ax, hx_PM_IDT32_PHYS >> 4
    mov es, ax
    xor di, di
    mov si, hx_pae_fault_stub_table
    mov cx, 32
.gate32_loop:
    mov eax, [si]
    mov word es:[di+0], ax
    mov word es:[di+2], hx_PM_CODE_SEL
    mov byte es:[di+4], 0
    mov byte es:[di+5], 0x8E
    shr eax, 16
    mov word es:[di+6], ax
    add si, 4
    add di, 8
    loop .gate32_loop

    pop es
    pop di
    pop si
    pop cx
    pop ebx
    pop eax
    ret

.clear_page:
    mov es, ax
    xor di, di
    xor eax, eax
    mov cx, 1024
    rep stosd
    ret

hx_pae_transfer:
    ; hx_pm_operation: 0=physical page -> low buffer, 1=low buffer -> page.
    ; CF=1 means a protected-mode/PAE exception was caught.
    pushf
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds
    push es
    push fs
    push gs
    mov [hx_pm_saved_sp], sp
    mov ax, ss
    mov [hx_pm_saved_ss], ax
    mov byte [hx_pm_faulted], 0
    mov byte [hx_pm_efer_touched], 0
    mov byte [hx_pm_checkpoint], 0
    mov byte [hx_pm_fault_vector], 0xFF
    mov dword [hx_pm_fault_cr2], 0
    cli

    ; Firmware calls may change A20. Re-enable it here with BIOS, port 92h and
    ; 8042 fallbacks instead of merely rejecting the transfer after a check.
    call hx_enable_a20
    jc .preflight_failed

    call hx_prepare_pae_tables
    o32 sgdt [hx_pm_saved_gdtr]
    o32 sidt [hx_pm_saved_idtr]
    mov eax, cr0
    mov [hx_pm_saved_cr0], eax
    mov eax, cr3
    mov [hx_pm_saved_cr3], eax
    mov eax, cr4
    mov [hx_pm_saved_cr4], eax

    in al, 0x70
    mov [hx_pm_saved_cmos], al
    or al, 0x80
    out 0x70, al

    o32 lgdt [hx_pm_gdtr]
    ; The processor starts using protected-mode gate semantics as soon as PE
    ; becomes one.  Install the 8-byte IDT before that write, closing the old
    ; CR0.PE-to-LIDT triple-fault window.  CLI plus the CMOS NMI mask makes the
    ; short real-mode interval deterministic.
    o32 lidt [hx_pm_idtr32]
    ; SS=9000h is not a valid selector after CR0.PE becomes one.  Load the
    ; protected data selector while still in real mode and bias SP so its
    ; hidden real-mode base addresses the same private 00007000h stack.  This
    ; makes an exception in the PE-to-far-jump window catchable instead of
    ; recursively escalating through #SS -> #DF -> triple fault.
    mov ax, hx_PM_DATA_SEL
    mov ss, ax
    mov sp, hx_LM_STACK_TOP - (hx_PM_DATA_SEL << 4)
    mov eax, [hx_pm_saved_cr0]
    and eax, 0x7FFFFFFF
    or eax, 0x00000001
    mov cr0, eax
    jmp dword hx_PM_CODE_SEL:hx_pae_entry32

.preflight_failed:
    mov byte [hx_pm_faulted], 1
    mov byte [hx_pm_checkpoint], 0xEA
    movzx esp, word [hx_pm_saved_sp]
    pop gs
    pop fs
    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    popf
    stc
    ret

BITS 32
hx_pae_entry32:
    mov ax, hx_PM_DATA_SEL
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax
    mov esp, hx_LM_STACK_TOP
    cld
    lidt [hx_pm_idtr32]
    mov byte [hx_pm_checkpoint], 1

    ; PAE paging is selected only when IA32_EFER.LME is zero.  A warm boot or
    ; chain loader is allowed to leave LME set while paging is disabled; if we
    ; failed to clear it, setting CR4.PAE+CR0.PG would select 4-level paging and
    ; interpret the 32-byte PDPT as a PML4, causing an immediate page fault.
    cmp byte [hx_efer_available], 0
    je .legacy_pae_ready
    mov ecx, 0xC0000080
    rdmsr
    mov [hx_pm_saved_efer_lo], eax
    mov [hx_pm_saved_efer_hi], edx
    and eax, 0xFFFFFEFF             ; clear IA32_EFER.LME (bit 8)
    wrmsr
    mov byte [hx_pm_efer_touched], 1
.legacy_pae_ready:
    mov byte [hx_pm_checkpoint], 0x11

    ; Use a minimal CR4: PAE plus an already-enabled MCE bit. No TSS, 64-bit
    ; code segment, or 64-bit IDT participates in this backend.
    mov eax, [hx_pm_saved_cr4]
    and eax, (1 << 6)
    or eax, (1 << 5)
    mov cr4, eax
    mov eax, hx_PAE_PDPT_PHYS
    mov cr3, eax
    mov byte [hx_pm_checkpoint], 2

    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax
    mov byte [hx_pm_checkpoint], 3

    mov esi, hx_PAE_WINDOW
    add esi, [hx_pm_page_offset]
    mov edi, [hx_pm_buffer]
    cmp byte [hx_pm_operation], 0
    jne .write
    mov ecx, hx_BYTES_PER_SECTOR / 4
    rep movsd
    jmp short hx_pae_leave32
.write:
    xchg esi, edi
    mov ecx, hx_BYTES_PER_SECTOR / 4
    rep movsd

hx_pae_leave32:
    cli
    mov byte [hx_pm_checkpoint], 4
    jmp hx_pae_restore32

; Each exception first records its vector. Different hardware stack frames are
; irrelevant because the private stack is discarded on the Real Mode return.
%macro HX_PAE_FAULT_STUB 2
%1:
    mov ebp, %2
    jmp hx_pae_fault32
%endmacro

HX_PAE_FAULT_STUB hx_pae_fault_stub_00, 0
HX_PAE_FAULT_STUB hx_pae_fault_stub_01, 1
HX_PAE_FAULT_STUB hx_pae_fault_stub_02, 2
HX_PAE_FAULT_STUB hx_pae_fault_stub_03, 3
HX_PAE_FAULT_STUB hx_pae_fault_stub_04, 4
HX_PAE_FAULT_STUB hx_pae_fault_stub_05, 5
HX_PAE_FAULT_STUB hx_pae_fault_stub_06, 6
HX_PAE_FAULT_STUB hx_pae_fault_stub_07, 7
HX_PAE_FAULT_STUB hx_pae_fault_stub_08, 8
HX_PAE_FAULT_STUB hx_pae_fault_stub_09, 9
HX_PAE_FAULT_STUB hx_pae_fault_stub_10, 10
HX_PAE_FAULT_STUB hx_pae_fault_stub_11, 11
HX_PAE_FAULT_STUB hx_pae_fault_stub_12, 12
HX_PAE_FAULT_STUB hx_pae_fault_stub_13, 13
HX_PAE_FAULT_STUB hx_pae_fault_stub_14, 14
HX_PAE_FAULT_STUB hx_pae_fault_stub_15, 15
HX_PAE_FAULT_STUB hx_pae_fault_stub_16, 16
HX_PAE_FAULT_STUB hx_pae_fault_stub_17, 17
HX_PAE_FAULT_STUB hx_pae_fault_stub_18, 18
HX_PAE_FAULT_STUB hx_pae_fault_stub_19, 19
HX_PAE_FAULT_STUB hx_pae_fault_stub_20, 20
HX_PAE_FAULT_STUB hx_pae_fault_stub_21, 21
HX_PAE_FAULT_STUB hx_pae_fault_stub_22, 22
HX_PAE_FAULT_STUB hx_pae_fault_stub_23, 23
HX_PAE_FAULT_STUB hx_pae_fault_stub_24, 24
HX_PAE_FAULT_STUB hx_pae_fault_stub_25, 25
HX_PAE_FAULT_STUB hx_pae_fault_stub_26, 26
HX_PAE_FAULT_STUB hx_pae_fault_stub_27, 27
HX_PAE_FAULT_STUB hx_pae_fault_stub_28, 28
HX_PAE_FAULT_STUB hx_pae_fault_stub_29, 29
HX_PAE_FAULT_STUB hx_pae_fault_stub_30, 30
HX_PAE_FAULT_STUB hx_pae_fault_stub_31, 31

hx_pae_fault32:
    cli
    ; The fault may have arrived immediately after CR0.PE, before the normal
    ; entry loaded DS/SS.  Establish valid flat selectors and discard the
    ; exception frame before touching any global state.
    mov ax, hx_PM_DATA_SEL
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, hx_LM_STACK_TOP
    mov eax, ebp
    mov [hx_pm_fault_vector], al
    mov eax, cr2
    mov [hx_pm_fault_cr2], eax
    mov byte [hx_pm_faulted], 1
    mov byte [hx_pm_checkpoint], 0xE3

hx_pae_restore32:
    ; Safe whether the exception happened before or after CR0.PG was set.
    mov eax, cr0
    and eax, 0x7FFFFFFF
    mov cr0, eax
    lidt [hx_pm_idtr32]
    cmp byte [hx_pm_efer_touched], 0
    je .efer_restored
    ; Clear the marker first so a fault in WRMSR cannot recurse forever.
    mov byte [hx_pm_efer_touched], 0
    mov ecx, 0xC0000080
    mov eax, [hx_pm_saved_efer_lo]
    mov edx, [hx_pm_saved_efer_hi]
    wrmsr
.efer_restored:
    mov eax, [hx_pm_saved_cr4]
    mov cr4, eax
    mov eax, [hx_pm_saved_cr3]
    mov cr3, eax
    jmp word hx_PM_CODE16_SEL:hx_pae_exit16

BITS 16
hx_pae_exit16:
    ; CR0.PE is still set here.  Replace every 32-bit data cache, especially
    ; SS.D/B=1, with a genuine 16-bit descriptor before entering Real Mode.
    ; The private stack is below 64 KiB specifically so this SS load is valid.
    mov ax, hx_PM_DATA16_SEL
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov sp, hx_LM_STACK_TOP
    mov eax, [hx_pm_saved_cr0]
    and eax, 0x7FFFFFFF
    mov cr0, eax
    jmp word 0x0000:hx_pae_return

hx_pae_return:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    o32 lgdt [hx_pm_saved_gdtr]
    o32 lidt [hx_pm_saved_idtr]
    mov al, [hx_pm_saved_cmos]
    out 0x70, al
    mov ax, [hx_pm_saved_ss]
    mov ss, ax
    ; Zero the full architectural stack pointer as a second line of defence.
    ; v15-fix3 restored only SP while SS still had a cached D/B=1, leaving
    ; ESP=0001xxxx and making POP/RET read 64 KiB above the caller's stack.
    movzx esp, word [hx_pm_saved_sp]
    pop gs
    pop fs
    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    popf
    cmp byte [hx_pm_fault_vector], 8
    je .double_fault
    cmp byte [hx_pm_faulted], 0
    jne .failed
    clc
    ret
.double_fault:
    cmp byte [BLUESCREEN_ENABLE_ADDR], 0
    je .failed
    mov al, 8
    jmp hx_blue_screen
.failed:
    stc
    ret

align 4, db 0
hx_pae_fault_stub_table:
    dd hx_pae_fault_stub_00, hx_pae_fault_stub_01
    dd hx_pae_fault_stub_02, hx_pae_fault_stub_03
    dd hx_pae_fault_stub_04, hx_pae_fault_stub_05
    dd hx_pae_fault_stub_06, hx_pae_fault_stub_07
    dd hx_pae_fault_stub_08, hx_pae_fault_stub_09
    dd hx_pae_fault_stub_10, hx_pae_fault_stub_11
    dd hx_pae_fault_stub_12, hx_pae_fault_stub_13
    dd hx_pae_fault_stub_14, hx_pae_fault_stub_15
    dd hx_pae_fault_stub_16, hx_pae_fault_stub_17
    dd hx_pae_fault_stub_18, hx_pae_fault_stub_19
    dd hx_pae_fault_stub_20, hx_pae_fault_stub_21
    dd hx_pae_fault_stub_22, hx_pae_fault_stub_23
    dd hx_pae_fault_stub_24, hx_pae_fault_stub_25
    dd hx_pae_fault_stub_26, hx_pae_fault_stub_27
    dd hx_pae_fault_stub_28, hx_pae_fault_stub_29
    dd hx_pae_fault_stub_30, hx_pae_fault_stub_31


; -----------------------------------------------------------------------------
; Disk I/O support
; EDD is preferred. If EDD is missing or fails, CHS is used as fallback.
; F4 switches through BIOS hard disks starting from 80h.
; UI displays disk number as decimal index: disk:0, disk:1, disk:16...
; -----------------------------------------------------------------------------

hx_init_disk_state:
    call hx_init_hdd_count
    call hx_disk_detect_current
    ret

hx_init_hdd_count:
    mov al, [hx_BIOS_HDD_COUNT_ADDR]
    cmp al, 1
    jae .have_count
    mov al, 1

.have_count:
    mov [hx_hdd_count], al

    mov dl, [boot_drive]
    cmp dl, 0x80
    jb .not_hdd_boot

    sub dl, 0x80
    cmp dl, al
    jb .store_index
    xor dl, dl

.store_index:
    mov [hx_current_hdd_index], dl
    ret

.not_hdd_boot:
    mov byte [hx_current_hdd_index], 0
    mov byte [hx_hdd_count], 1
    ret

hx_disk_detect_current:
    mov byte [hx_edd_available], 0
    mov byte [hx_chs_available], 0
    mov byte [hx_disk_io_mode], hx_DISK_IO_CHS
    mov byte [hx_chs_spt], 0
    mov byte [hx_chs_heads], 0
    mov word [hx_chs_cylinders], 0

    ; EDD check
    mov ah, 0x41
    mov bx, 0x55AA
    mov dl, [boot_drive]
    int 0x13
    jc .check_chs
    cmp bx, 0xAA55
    jne .check_chs
    test cx, 1
    jz .check_chs

    mov byte [hx_edd_available], 1
    mov byte [hx_disk_io_mode], hx_DISK_IO_EDD

.check_chs:
    ; Always get CHS geometry too, because it is the fallback.
    mov ah, 0x08
    mov dl, [boot_drive]
    int 0x13
    jc .done

    mov bl, cl
    and cl, 0x3F
    jz .done
    mov [hx_chs_spt], cl

    mov al, dh
    inc al
    jz .done
    mov [hx_chs_heads], al

    xor ax, ax
    mov al, bl
    and ax, 0x00C0
    shl ax, 2
    mov al, ch
    inc ax
    mov [hx_chs_cylinders], ax

    mov byte [hx_chs_available], 1

.done:
    ret

hx_disk_reset_current:
    push ax
    push dx
    xor ah, ah
    mov dl, [boot_drive]
    int 0x13
    pop dx
    pop ax
    ret

hx_disk_read_dap:
    push ax
    push bx
    push cx
    push dx
    push si
    push es

    cmp byte [hx_disk_io_mode], hx_DISK_IO_EDD
    jne .try_chs
    cmp byte [hx_edd_available], 0
    je .try_chs

    mov dl, [boot_drive]
    mov ah, 0x42
    int 0x13
    jnc .edd_ok

    call hx_disk_reset_current
    mov byte [hx_disk_io_mode], hx_DISK_IO_CHS

.try_chs:
    call hx_disk_read_dap_chs_inner
    jc .fail

    mov byte [hx_disk_io_mode], hx_DISK_IO_CHS
    jmp .ok

.edd_ok:
    mov byte [hx_disk_io_mode], hx_DISK_IO_EDD

.ok:
    pop es
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    clc
    ret

.fail:
    pop es
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    stc
    ret

hx_disk_write_dap:
    push ax
    push bx
    push cx
    push dx
    push si
    push es

    cmp byte [hx_disk_io_mode], hx_DISK_IO_EDD
    jne .try_chs
    cmp byte [hx_edd_available], 0
    je .try_chs

    mov dl, [boot_drive]
    mov ah, 0x43
    xor al, al
    int 0x13
    jnc .edd_ok

    call hx_disk_reset_current
    mov byte [hx_disk_io_mode], hx_DISK_IO_CHS

.try_chs:
    call hx_disk_write_dap_chs_inner
    jc .fail

    mov byte [hx_disk_io_mode], hx_DISK_IO_CHS
    jmp .ok

.edd_ok:
    mov byte [hx_disk_io_mode], hx_DISK_IO_EDD

.ok:
    pop es
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    clc
    ret

.fail:
    pop es
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    stc
    ret

hx_disk_read_dap_chs_inner:
    mov byte [hx_disk_chs_cmd], 0x02
    jmp hx_disk_chs_io_dap_inner

hx_disk_write_dap_chs_inner:
    mov byte [hx_disk_chs_cmd], 0x03
    jmp hx_disk_chs_io_dap_inner

hx_disk_chs_io_dap_inner:
    cmp byte [hx_chs_available], 0
    je .fail

    cmp word [si + 2], 1
    jne .fail

    mov eax, [si + 12]
    or eax, eax
    jnz .fail

    mov eax, [si + 8]

    xor edx, edx
    xor ebx, ebx
    mov bl, [hx_chs_spt]
    cmp bl, 0
    je .fail
    div ebx

    mov cl, dl
    inc cl

    xor edx, edx
    xor ebx, ebx
    mov bl, [hx_chs_heads]
    cmp bl, 0
    je .fail
    div ebx

    cmp eax, 1023
    ja .fail

    mov bx, ax
    mov ch, bl

    mov al, bh
    and al, 0x03
    shl al, 6
    or cl, al

    mov dh, dl

    mov bx, [si + 4]
    mov ax, [si + 6]
    mov es, ax

    mov ah, [hx_disk_chs_cmd]
    mov al, 1
    mov dl, [boot_drive]
    int 0x13
    jnc .ok

    call hx_disk_reset_current

.fail:
    stc
    ret

.ok:
    clc
    ret

hx_switch_to_next_hard_disk:
    cmp byte [hx_hdd_count], 1
    ja .have_more

    mov word [hx_msg_ptr], hx_msg_drive_single
    call hx_beep
    stc
    ret

.have_more:
    mov al, [hx_current_hdd_index]
    inc al
    cmp al, [hx_hdd_count]
    jb .store
    xor al, al

.store:
    mov [hx_current_hdd_index], al
    add al, 0x80
    mov [boot_drive], al

    call hx_disk_detect_current

    xor eax, eax
    mov [hx_curr_lba_lo], eax
    mov [hx_curr_lba_hi], eax

    call hx_query_total_sectors
    call hx_load_current_sector
    jnc .ok

    call hx_clear_sector_buf
    call hx_copy_sector_to_undo_snapshot
    call hx_copy_sector_to_disk_snapshot
    call hx_reset_edit_state_after_load

    mov word [hx_msg_ptr], hx_msg_drive_read_failed
    call hx_beep
    stc
    ret

.ok:
    call hx_reset_edit_state_after_load
    mov word [hx_msg_ptr], hx_msg_drive_switched
    clc
    ret

; Convert current disk number to decimal:
; boot_drive 80h -> disk 0
; boot_drive 81h -> disk 1
; boot_drive 90h -> disk 16
hx_make_disk_dec_buf:
    push ax
    push si
    push di

    xor eax, eax
    mov al, [boot_drive]
    cmp al, 0x80
    jb .zero
    sub al, 0x80
    jmp .convert

.zero:
    xor al, al

.convert:
    mov [hx_conv_qword + 0], eax
    mov dword [hx_conv_qword + 4], 0
    mov si, hx_conv_qword
    call hx_u64_to_dec
    mov di, hx_disk_dec_buf
    call hx_copy_asciiz

    pop di
    pop si
    pop ax
    ret


hx_query_total_sectors:
    xor eax, eax
    mov [hx_total_lba_lo], eax
    mov [hx_total_lba_hi], eax

    cmp byte [hx_edd_available], 0
    je .try_chs_total

    mov word [hx_edd_params + 0], 0x001E
    mov word [hx_edd_params + 2], 0x0000
    mov dl, [boot_drive]
    mov si, hx_edd_params
    mov ah, 0x48
    int 0x13
    jc .try_chs_total

    mov eax, [hx_edd_params + 0x10]
    mov [hx_total_lba_lo], eax
    mov eax, [hx_edd_params + 0x14]
    mov [hx_total_lba_hi], eax
    ret

.try_chs_total:
    cmp byte [hx_chs_available], 0
    je .fail

    movzx eax, word [hx_chs_cylinders]
    movzx ebx, byte [hx_chs_heads]
    mul ebx
    movzx ebx, byte [hx_chs_spt]
    mul ebx

    mov [hx_total_lba_lo], eax
    mov [hx_total_lba_hi], edx
    mov word [hx_msg_ptr], hx_msg_total_chs
    ret

.fail:
    xor eax, eax
    mov [hx_total_lba_lo], eax
    mov [hx_total_lba_hi], eax
    mov word [hx_msg_ptr], hx_msg_total_unknown
    ret

hx_load_current_sector:
    cmp byte [hx_memory_mode], 0
    je .disk
    mov eax, [hx_curr_lba_lo]
    mov edx, [hx_curr_lba_hi]
    mov di, hx_sector_buf
    call hx_copy_memory_page_to_buffer
    jc .memory_fail
    call hx_copy_sector_to_undo_snapshot
    call hx_copy_sector_to_disk_snapshot
    clc
    ret
.memory_fail:
    stc
    ret
.disk:
    mov byte [hx_dap_read + 0], 0x10
    mov byte [hx_dap_read + 1], 0x00
    mov word [hx_dap_read + 2], 1
    mov word [hx_dap_read + 4], hx_sector_buf
    mov word [hx_dap_read + 6], 0x0000
    mov eax, [hx_curr_lba_lo]
    mov [hx_dap_read + 8], eax
    mov eax, [hx_curr_lba_hi]
    mov [hx_dap_read + 12], eax

    mov cx, 3

.retry:
    mov si, hx_dap_read
    call hx_disk_read_dap
    jnc .ok

    call hx_disk_reset_current
    loop .retry

    stc
    ret

.ok:
    call hx_copy_sector_to_undo_snapshot
    call hx_copy_sector_to_disk_snapshot
    clc
    ret

hx_set_read_failure_msg:
    push ax
    mov ax, hx_msg_read_failed
    cmp byte [hx_memory_mode], 0
    je .store
    cmp byte [hx_memory_fail_reason], 1
    jne .not_backend
    mov ax, hx_msg_memory_pae_unavailable
    jmp short .store
.not_backend:
    cmp byte [hx_memory_fail_reason], 2
    jne .not_width
    mov ax, hx_msg_memory_address_invalid
    jmp short .store
.not_width:
    cmp byte [hx_memory_fail_reason], 3
    jne .not_a20
    mov ax, hx_msg_memory_a20_transfer_failed
    jmp short .store
.not_a20:
    cmp byte [hx_memory_fail_reason], 4
    jne .not_pae
    call hx_format_pae_fault_message
    mov ax, hx_msg_memory_pae_fault
    jmp short .store
.not_pae:
    cmp byte [hx_memory_fail_reason], 5
    jne .store
    mov ax, hx_msg_memory_bios87_failed
.store:
    mov [hx_msg_ptr], ax
    pop ax
    ret

hx_format_pae_fault_message:
    push eax
    push di
    mov al, [hx_pm_fault_vector]
    mov di, hx_msg_memory_pae_fault_vector
    call hx_store_hex_byte
    mov eax, [hx_pm_fault_cr2]
    mov di, hx_msg_memory_pae_fault_cr2
    call hx_store_hex_dword
    mov al, [hx_pm_checkpoint]
    mov di, hx_msg_memory_pae_fault_step
    call hx_store_hex_byte
    pop di
    pop eax
    ret

; AL -> two uppercase hexadecimal characters at DS:DI.
hx_store_hex_byte:
    push ax
    mov ah, al
    shr al, 4
    call hx_nibble_to_ascii
    mov [di], al
    mov al, ah
    and al, 0x0F
    call hx_nibble_to_ascii
    mov [di+1], al
    pop ax
    ret

; EAX -> eight uppercase hexadecimal characters at DS:DI.
hx_store_hex_dword:
    push eax
    push ebx
    push cx
    push di
    mov ebx, eax
    mov cx, 8
.digit:
    mov eax, ebx
    shr eax, 28
    call hx_nibble_to_ascii
    mov [di], al
    inc di
    shl ebx, 4
    loop .digit
    pop di
    pop cx
    pop ebx
    pop eax
    ret

hx_copy_memory_page_to_buffer:
    ; EDX:EAX=512-byte physical page index, DS:DI=destination buffer.
    ; Direct Real Mode handles the first MiB, BIOS87 handles the next range
    ; through FFFFFFFFh, and the PAE window handles 4 GiB and above.
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push di
    push fs
    mov byte [hx_memory_fail_reason], 0
    mov byte [hx_pm_fault_vector], 0xFF
    mov byte [hx_pm_checkpoint], 0
    test edx, edx
    jnz .high_required
    cmp eax, hx_MEMORY_FALLBACK_PAGES
    jb .fallback
    cmp eax, hx_HIGH_MEMORY_FIRST_PAGE
    jae .high_required

    ; Keep the proven BIOS block-move path for 1 MiB..4 GiB-1.
    ; This avoids a mode transition at exactly 100000h.
    cmp byte [hx_memory_backend], 0
    je .fail
    mov ebx, eax
    shl ebx, 9
    mov [hx_pm_phys_lo], ebx
    mov dword [hx_pm_phys_hi], 0
    movzx eax, di
    mov [hx_pm_buffer], eax
    mov byte [hx_pm_operation], 0
    call hx_bios87_transfer
    jnc .ok
    mov byte [hx_memory_fail_reason], 5
    jmp .fail

.high_required:
    cmp byte [hx_memory_backend], 2
    je .pae
    mov byte [hx_memory_fail_reason], 1
    jmp .fail
.pae:
    ; Convert the 64-bit 512-byte page index into a byte address.
    mov ebx, eax
    mov ecx, edx
    shld ecx, ebx, 9
    shl ebx, 9
    mov [hx_pm_phys_lo], ebx
    mov [hx_pm_phys_hi], ecx
    mov eax, ebx
    and eax, 0x00000FFF
    mov [hx_pm_page_offset], eax
    movzx eax, di
    mov [hx_pm_buffer], eax
    mov byte [hx_pm_operation], 0
    call hx_validate_high_memory_page
    jnc .validated
    mov byte [hx_memory_fail_reason], 2
    jmp .fail
.validated:
    call hx_pae_transfer
    jnc .ok
    cmp byte [hx_pm_checkpoint], 0xEA
    jne .pae_fault
    mov byte [hx_memory_fail_reason], 3
    jmp .fail
.pae_fault:
    mov byte [hx_memory_fail_reason], 4
    jmp .fail
.fallback:
    shl eax, 9
    mov ebx, eax
    movzx edx, di
    shr eax, 4
    mov fs, ax
    xor si, si
    mov cx, hx_BYTES_PER_SECTOR
    cmp edx, ebx
    jbe .forward
    add si, hx_BYTES_PER_SECTOR - 1
    add di, hx_BYTES_PER_SECTOR - 1
.backward_loop:
    mov al, fs:[si]
    mov [di], al
    dec si
    dec di
    loop .backward_loop
    jmp .ok
.forward:
    mov al, fs:[si]
    mov [di], al
    inc si
    inc di
    loop .forward
.ok:
    pop fs
    pop di
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    clc
    ret
.fail:
    pop fs
    pop di
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    stc
    ret

hx_write_current_memory_page:
    ; Copy the edited 512-byte buffer back to its physical memory page.
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push es
    mov eax, [hx_curr_lba_lo]
    mov edx, [hx_curr_lba_hi]
    test edx, edx
    jnz .high_required
    cmp eax, hx_MEMORY_FALLBACK_PAGES
    jb .fallback
    cmp eax, hx_HIGH_MEMORY_FIRST_PAGE
    jae .high_required

    ; Match the read path: BIOS87 is the stable 32-bit physical transfer.
    cmp byte [hx_memory_backend], 0
    je .fail
    mov ebx, eax
    shl ebx, 9
    mov [hx_pm_phys_lo], ebx
    mov dword [hx_pm_phys_hi], 0
    mov dword [hx_pm_buffer], hx_sector_buf
    mov byte [hx_pm_operation], 1
    call hx_bios87_transfer
    jc .fail
    jmp .ok

.high_required:
    cmp byte [hx_memory_backend], 2
    jne .fail
.pae:
    mov ebx, eax
    mov ecx, edx
    shld ecx, ebx, 9
    shl ebx, 9
    mov [hx_pm_phys_lo], ebx
    mov [hx_pm_phys_hi], ecx
    mov eax, ebx
    and eax, 0x00000FFF
    mov [hx_pm_page_offset], eax
    mov dword [hx_pm_buffer], hx_sector_buf
    mov byte [hx_pm_operation], 1
    call hx_validate_high_memory_page
    jc .fail
    call hx_pae_transfer
    jc .fail
    jmp .ok
.fallback:
    shl eax, 9
    mov ebx, eax
    shr eax, 4
    mov es, ax
    xor di, di
    mov si, hx_sector_buf
    mov cx, hx_BYTES_PER_SECTOR
    pushf
    cli
    cmp ebx, hx_sector_buf
    jb .forward
    add si, hx_BYTES_PER_SECTOR - 1
    add di, hx_BYTES_PER_SECTOR - 1
.backward_loop:
    mov al, [si]
    mov es:[di], al
    dec si
    dec di
    loop .backward_loop
    jmp .copied
.forward:
    mov al, [si]
    mov es:[di], al
    inc si
    inc di
    loop .forward
.copied:
    popf
.ok:
    pop es
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    clc
    ret
.fail:
    pop es
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    stc
    ret

hx_is_critical_system_page:
    ; CF=1 when the selected live-memory page overlaps state whose write can
    ; destroy the currently executing environment.  The caller raises the
    ; blue screen before committing the edit, so the panic renderer still has
    ; intact code, stack, VGA font data, and exception hooks.
    push eax
    push ebx
    push edx
    cmp byte [hx_memory_mode], 1
    jne .no
    cmp dword [hx_curr_lba_hi], 0
    jne .no
    mov edx, [hx_curr_lba_lo]

    ; 00000h..005FFh: both IVT pages, the BDA half-page, and the persistent
    ; blue-screen gate in the other half of the same 512-byte editor page.
    cmp edx, 2
    jbe .yes

    ; 07000h..1FFFFh: private mode-transition stack, MBR return loaders,
    ; currently executing HEX image, PAE/GDT/IDT tables, fault stubs, and the
    ; saved MiniWin session image needed by WIN -KEEP.
    cmp edx, (0x00007000 >> 9)
    jb .check_stack
    cmp edx, (0x0001FFFF >> 9)
    jbe .yes

.check_stack:
    ; Protect the complete active real-mode SS window, not merely the current
    ; SP page: a later CALL/interrupt must not grow into bytes just edited.
    xor eax, eax
    mov ax, ss
    shl eax, 4
    mov ebx, eax
    shr eax, 9
    cmp edx, eax
    jb .check_ebda
    add ebx, 0x0000FFFF
    shr ebx, 9
    cmp edx, ebx
    jbe .yes

.check_ebda:
    ; EBDA placement and size are firmware-defined.  Use the stable values
    ; captured at HEX startup rather than the possibly edited live BDA.
    xor eax, eax
    mov ax, [hx_saved_bda_ebda]
    test eax, eax
    jz .no
    shl eax, 4
    mov ebx, eax
    shr eax, 9
    cmp edx, eax
    jb .no
    xor eax, eax
    mov al, [hx_saved_ebda_kb]
    test eax, eax
    jnz .ebda_size_ready
    mov eax, 1
.ebda_size_ready:
    shl eax, 10
    add ebx, eax
    dec ebx
    shr ebx, 9
    cmp edx, ebx
    jbe .yes
.no:
    pop edx
    pop ebx
    pop eax
    clc
    ret
.yes:
    pop edx
    pop ebx
    pop eax
    stc
    ret

hx_finish_critical_write_no_repair:
    ; Used only while blue screens are disabled.  Commit exactly what the user
    ; requested, including damaged IVT/BDA/EBDA/code/stack bytes; merely unmask
    ; NMI/IRQ after the atomic page copy.
    mov dx, 0x0070
    mov al, [hx_critical_saved_cmos]
    out dx, al
    mov byte [hx_critical_write_active], 0
    sti
    ret

hx_save_current_sector:
    push ax
    push bx
    push cx
    push dx
    push si
    cmp byte [hx_dirty_flag], 0
    jne .go
    cmp byte [hx_memory_mode], 0
    je .disk_no_changes
    mov word [hx_msg_ptr], hx_msg_memory_no_changes
    jmp short .no_changes_ready
.disk_no_changes:
    mov word [hx_msg_ptr], hx_msg_no_changes
.no_changes_ready:
    call hx_beep
    clc
    jmp .done
.go:
    mov byte [hx_critical_write_active], 0
    cmp byte [hx_memory_mode], 0
    je .disk_save
    call hx_is_critical_system_page
    jnc .memory_write

    ; Enabled: reject the dangerous live-memory write before a single byte is
    ; committed. Disabled: deliberately allow it, but make the copy atomic.
    cmp byte [BLUESCREEN_ENABLE_ADDR], 0
    je .critical_write_allowed
    mov al, BSOD_STOP_CRITICAL_WRITE
    jmp hx_blue_screen
.critical_write_allowed:
    cli
    mov dx, 0x0070
    in al, dx
    mov [hx_critical_saved_cmos], al
    or al, 0x80
    out dx, al
    mov byte [hx_critical_write_active], 1
.memory_write:
    call hx_write_current_memory_page
    jc .save_failed
    cmp byte [hx_critical_write_active], 0
    je .ok
    call hx_finish_critical_write_no_repair
    jmp short .ok
.disk_save:
    mov byte [hx_dap_write + 0], 0x10
    mov byte [hx_dap_write + 1], 0x00
    mov word [hx_dap_write + 2], 1
    mov word [hx_dap_write + 4], hx_sector_buf
    mov word [hx_dap_write + 6], 0x0000
    mov eax, [hx_curr_lba_lo]
    mov [hx_dap_write + 8], eax
    mov eax, [hx_curr_lba_hi]
    mov [hx_dap_write + 12], eax
    mov cx, 3
.retry:
    mov si, hx_dap_write
    call hx_disk_write_dap
    jnc .ok

    call hx_disk_reset_current
    loop .retry
.save_failed:
    cmp byte [hx_critical_write_active], 0
    je .failure_state_ready
    ; Even a reported failure may have copied part of the page; restore only
    ; interrupt masking state because disabled mode intentionally permits the
    ; edited critical bytes to remain untouched.
    call hx_finish_critical_write_no_repair
.failure_state_ready:
    mov byte [hx_preserve_undo_after_save], 0
    cmp byte [hx_memory_mode], 0
    je .disk_save_failed
    mov word [hx_msg_ptr], hx_msg_memory_save_failed
    jmp short .report_save_failed
.disk_save_failed:
    mov word [hx_msg_ptr], hx_msg_save_failed
.report_save_failed:
    call hx_beep
    stc
    jmp .done
.ok:
    call hx_copy_sector_to_disk_snapshot
    mov byte [hx_rebase_undo_on_next_edit], 1
    cmp byte [hx_preserve_undo_after_save], 0
    je .snapshot_done
    mov byte [hx_preserve_undo_after_save], 0
.snapshot_done:
    mov byte [hx_dirty_flag], 0
    cmp byte [hx_memory_mode], 0
    je .disk_saved
    mov word [hx_msg_ptr], hx_msg_memory_saved_ok
    jmp short .saved_message_done
.disk_saved:
    mov word [hx_msg_ptr], hx_msg_saved_ok
.saved_message_done:
    clc
.done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

hx_kbd_flush:
    push ax
.flush_loop:
    mov ah, 0x01
    int 0x16
    jz .flush_done
    mov ah, 0x00
    int 0x16
    jmp .flush_loop
.flush_done:
    pop ax
    ret

hx_push_undo_entry:
    push si
    push di
    mov si, [hx_undo_count]
    cmp si, hx_HISTORY_MAX
    jae .done
    mov di, si
    shl di, 1
    mov [hx_undo_pos_stack + di], bx
    mov [hx_undo_old_stack + si], al
    mov [hx_undo_new_stack + si], dl
    inc word [hx_undo_count]
.done:
    pop di
    pop si
    ret

hx_push_redo_entry:
    push si
    push di
    mov si, [hx_redo_count]
    cmp si, hx_HISTORY_MAX
    jae .done
    mov di, si
    shl di, 1
    mov [hx_redo_pos_stack + di], bx
    mov [hx_redo_old_stack + si], al
    mov [hx_redo_new_stack + si], dl
    inc word [hx_redo_count]
.done:
    pop di
    pop si
    ret

hx_pop_undo_entry:
    push si
    push di
    cmp word [hx_undo_count], 0
    je .empty
    dec word [hx_undo_count]
    mov si, [hx_undo_count]
    mov di, si
    shl di, 1
    mov bx, [hx_undo_pos_stack + di]
    mov al, [hx_undo_old_stack + si]
    mov dl, [hx_undo_new_stack + si]
    pop di
    pop si
    clc
    ret
.empty:
    pop di
    pop si
    stc
    ret

hx_pop_redo_entry:
    push si
    push di
    cmp word [hx_redo_count], 0
    je .empty
    dec word [hx_redo_count]
    mov si, [hx_redo_count]
    mov di, si
    shl di, 1
    mov bx, [hx_redo_pos_stack + di]
    mov al, [hx_redo_old_stack + si]
    mov dl, [hx_redo_new_stack + si]
    pop di
    pop si
    clc
    ret
.empty:
    pop di
    pop si
    stc
    ret

hx_record_byte_change:
    cmp al, dl
    je .done
    mov cx, 1
    call hx_ensure_undo_capacity
    mov word [hx_redo_count], 0
    mov word [hx_redo_action_count], 0
    mov byte [hx_clear_redo_available], 0
    mov byte [hx_clear_undo_available], 0
    call hx_push_undo_entry
    mov cx, 1
    call hx_push_undo_action_size
.done:
    ret

hx_set_edit_message_by_dirty:
    cmp byte [hx_dirty_flag], 0
    je .clean
    cmp byte [hx_memory_mode], 0
    je .disk_dirty
    mov word [hx_msg_ptr], hx_msg_memory_dirty
    ret
.disk_dirty:
    mov word [hx_msg_ptr], hx_msg_ram_dirty
    ret
.clean:
    cmp byte [hx_memory_mode], 0
    je .disk_clean
    mov word [hx_msg_ptr], hx_msg_memory_no_changes
    ret
.disk_clean:
    mov word [hx_msg_ptr], hx_msg_no_changes
    ret

hx_commit_pending_hex_edit_if_needed:
    cmp byte [hx_pending_hex_active], 0
    je .done
    mov bx, [hx_pending_hex_pos]
    mov al, [hx_pending_hex_old]
    mov dl, [hx_sector_buf + bx]
    call hx_record_byte_change
    mov byte [hx_pending_hex_active], 0
    mov byte [hx_hex_half], 0
    call hx_refresh_dirty_flag_from_disk_snapshot
    call hx_set_edit_message_by_dirty
.done:
    ret

hx_undo_last_action:
    cmp byte [hx_clear_undo_available], 0
    je .normal_undo
    call hx_copy_undo_snapshot_to_sector
    mov word [hx_cursor_pos], 0
    mov byte [hx_selection_active], 0
    mov byte [hx_hex_half], 0
    mov byte [hx_pending_hex_active], 0
    mov byte [hx_clear_undo_available], 0
    mov byte [hx_clear_redo_available], 1
    call hx_refresh_dirty_flag_from_disk_snapshot
    cmp byte [hx_memory_mode], 0
    je .disk_clear_undo
    mov word [hx_msg_ptr], hx_msg_memory_clear_undo_done
    jmp short .clear_undo_ready
.disk_clear_undo:
    mov word [hx_msg_ptr], hx_msg_clear_undo_done
.clear_undo_ready:
    mov al, 2
    ret
.normal_undo:
    call hx_pop_undo_action_size
    jc .nothing
    mov si, cx
    push cx
.loop:
    call hx_pop_undo_entry
    mov [hx_sector_buf + bx], al
    mov [hx_cursor_pos], bx
    mov byte [hx_hex_half], 0
    mov byte [hx_pending_hex_active], 0
    call hx_push_redo_entry
    dec si
    jnz .loop
    pop cx
    call hx_push_redo_action_size
    call hx_refresh_dirty_flag_from_disk_snapshot
    mov word [hx_msg_ptr], hx_msg_undo_done
    cmp cx, 1
    jne .multi
    mov al, 1
    ret
.multi:
    mov al, 2
    ret
.nothing:
    mov word [hx_msg_ptr], hx_msg_nothing_to_undo
    call hx_beep
    xor al, al
    ret

hx_redo_last_action:
    cmp byte [hx_clear_redo_available], 0
    je .normal_redo
    call hx_clear_sector_buf
    mov word [hx_cursor_pos], 0
    mov byte [hx_selection_active], 0
    mov byte [hx_hex_half], 0
    mov byte [hx_pending_hex_active], 0
    mov byte [hx_clear_redo_available], 0
    mov byte [hx_clear_undo_available], 1
    call hx_refresh_dirty_flag_from_disk_snapshot
    cmp byte [hx_memory_mode], 0
    je .disk_clear_redo
    mov word [hx_msg_ptr], hx_msg_memory_clear_redo_done
    jmp short .clear_redo_ready
.disk_clear_redo:
    mov word [hx_msg_ptr], hx_msg_clear_redo_done
.clear_redo_ready:
    mov al, 2
    ret
.normal_redo:
    call hx_pop_redo_action_size
    jc .nothing
    mov si, cx
    push cx
.loop:
    call hx_pop_redo_entry
    mov [hx_sector_buf + bx], dl
    mov [hx_cursor_pos], bx
    mov byte [hx_hex_half], 0
    mov byte [hx_pending_hex_active], 0
    call hx_push_undo_entry
    dec si
    jnz .loop
    pop cx
    call hx_push_undo_action_size
    call hx_refresh_dirty_flag_from_disk_snapshot
    mov word [hx_msg_ptr], hx_msg_redo_done
    cmp cx, 1
    jne .multi
    mov al, 1
    ret
.multi:
    mov al, 2
    ret
.nothing:
    mov word [hx_msg_ptr], hx_msg_nothing_to_redo
    call hx_beep
    xor al, al
    ret

hx_copy_sector_to_undo_snapshot:
    push ax
    push cx
    push si
    push di
    cld
    mov si, hx_sector_buf
    mov di, hx_undo_sector_buf
    mov cx, hx_BYTES_PER_SECTOR
.copy:
    lodsb
    mov [di], al
    inc di
    loop .copy
    pop di
    pop si
    pop cx
    pop ax
    ret

hx_copy_sector_to_disk_snapshot:
    push ax
    push cx
    push si
    push di
    cld
    mov si, hx_sector_buf
    mov di, hx_disk_sector_buf
    mov cx, hx_BYTES_PER_SECTOR
.copy:
    lodsb
    mov [di], al
    inc di
    loop .copy
    pop di
    pop si
    pop cx
    pop ax
    ret

; F5 needs a transactional reread. BIOS disk services are allowed to modify a
; destination buffer even when they finally report CF=1, so keep the displayed
; 512 bytes in the otherwise-idle search buffer until the reload succeeds.
hx_copy_sector_to_search_buffer:
    push si
    push di
    mov si, hx_sector_buf
    mov di, hx_search_sector_buf
    call hx_copy_512_bytes
    pop di
    pop si
    ret

hx_copy_search_buffer_to_sector:
    push si
    push di
    mov si, hx_search_sector_buf
    mov di, hx_sector_buf
    call hx_copy_512_bytes
    pop di
    pop si
    ret

; DS is the editor's zero-based data segment; copy exactly one displayed page.
hx_copy_512_bytes:
    push ax
    push cx
    cld
    mov cx, hx_BYTES_PER_SECTOR
.copy:
    lodsb
    mov [di], al
    inc di
    loop .copy
    pop cx
    pop ax
    ret

hx_refresh_dirty_flag_from_disk_snapshot:
    push ax
    push cx
    push si
    push di
    mov si, hx_sector_buf
    mov di, hx_disk_sector_buf
    mov cx, hx_BYTES_PER_SECTOR
.loop:
    mov al, [si]
    cmp al, [di]
    jne .dirty
    inc si
    inc di
    loop .loop
    mov byte [hx_dirty_flag], 0
    jmp .done
.dirty:
    mov byte [hx_dirty_flag], 1
.done:
    pop di
    pop si
    pop cx
    pop ax
    ret

hx_copy_undo_snapshot_to_sector:
    push ax
    push cx
    push si
    push di
    cld
    mov si, hx_undo_sector_buf
    mov di, hx_sector_buf
    mov cx, hx_BYTES_PER_SECTOR
.copy:
    lodsb
    mov [di], al
    inc di
    loop .copy
    pop di
    pop si
    pop cx
    pop ax
    ret

hx_prepare_undo_snapshot_before_edit:
    cmp byte [hx_rebase_undo_on_next_edit], 0
    je .done
    call hx_copy_sector_to_undo_snapshot
    mov byte [hx_clear_undo_available], 0
    mov byte [hx_rebase_undo_on_next_edit], 0
.done:
    ret

hx_confirm_save_before_switch:
    mov word [hx_dialog_line1_ptr], hx_str_save_prompt
    mov word [hx_dialog_line2_ptr], hx_str_save_help
    cmp byte [hx_memory_mode], 0
    je .prompt_ready
    mov word [hx_dialog_line1_ptr], hx_str_save_prompt_memory
    mov word [hx_dialog_line2_ptr], hx_str_save_help_memory
.prompt_ready:
    call hx_confirm_yes_no_esc_dialog
    cmp al, 0
    jne .done
    mov word [hx_msg_ptr], hx_msg_switch_cancel
    call hx_refresh_meta_ui
.done:
    ret

hx_confirm_clear_sector:
    mov word [hx_dialog_line1_ptr], hx_str_clear_prompt
    mov word [hx_dialog_line2_ptr], hx_str_clear_help
    cmp byte [hx_memory_mode], 0
    je .prompt_ready
    mov word [hx_dialog_line1_ptr], hx_str_clear_prompt_memory
    mov word [hx_dialog_line2_ptr], hx_str_clear_help_memory
.prompt_ready:
    call hx_confirm_yes_no_esc_dialog
    cmp al, 0
    jne .done
    mov word [hx_msg_ptr], hx_msg_clear_cancel
    call hx_refresh_meta_ui
.done:
    ret

hx_confirm_yes_no_esc_dialog:
    push bx
    push cx
    push dx
    push si
    call hx_kbd_flush
.loop:
    call hx_draw_confirm_overlay
    call hx_kbd_read_key
    cmp al, 0x1B
    je .cancel
    cmp al, 'Y'
    je .yes
    cmp al, 'y'
    je .yes
    cmp al, 'N'
    je .no
    cmp al, 'n'
    je .no
    jmp .loop
.yes:
    mov al, 1
    jmp .done
.no:
    mov al, 2
    jmp .done
.cancel:
    xor al, al
.done:
    call hx_clear_overlay_lines
    call hx_update_hw_cursor
    pop si
    pop dx
    pop cx
    pop bx
    ret

hx_draw_confirm_overlay:
    push ax
    push bx
    push dx
    push si
    mov dh, hx_JUMP_ROW
    mov dl, 0
    mov bl, 0x1E
    mov si, hx_str_spaces80
    call hx_print_string_at
    mov dh, hx_JUMP_HELP_ROW
    mov dl, 0
    mov bl, 0x1E
    mov si, hx_str_spaces80
    call hx_print_string_at
    mov dh, hx_JUMP_ROW
    mov dl, 0
    mov bl, 0x1E
    mov si, [hx_dialog_line1_ptr]
    call hx_print_string_at
    mov dh, hx_JUMP_HELP_ROW
    mov dl, 0
    mov bl, 0x1E
    mov si, [hx_dialog_line2_ptr]
    call hx_print_string_at
    mov ah, 0x02
    xor bh, bh
    mov dh, hx_JUMP_HELP_ROW
    mov dl, 0
    int 0x10
    pop si
    pop dx
    pop bx
    pop ax
    ret

hx_jump_to_lba_dialog:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    call hx_clear_jump_buffer
.loop:
    call hx_draw_jump_overlay
    call hx_kbd_read_key
    cmp al, 0x1B
    je .cancel
    cmp al, 0x0D
    je .go
    cmp al, 0x08
    je .backspace
    cmp al, 0
    je .ext_key
    cmp byte [hx_memory_mode], 0
    je .decimal_digit
    push ax
    call hx_ascii_hex_to_nibble
    pop ax
    jc .loop
    cmp al, 'a'
    jb .memory_case_ready
    cmp al, 'f'
    ja .memory_case_ready
    sub al, 'a' - 'A'
.memory_case_ready:
    cmp byte [hx_jump_len], 16
    jae .loop
    jmp short .insert_valid_digit
.decimal_digit:
    cmp al, '0'
    jb .loop
    cmp al, '9'
    ja .loop
    cmp byte [hx_jump_len], 20
    jae .loop
.insert_valid_digit:
    xor bx, bx
    mov bl, [hx_jump_len]
.shift_right:
    mov cl, [hx_jump_cursor]
    cmp bl, cl
    jb .insert_digit
    mov dl, [hx_jump_buf + bx]
    mov [hx_jump_buf + bx + 1], dl
    cmp bl, cl
    je .insert_digit
    dec bx
    jmp .shift_right
.insert_digit:
    xor bx, bx
    mov bl, [hx_jump_cursor]
    mov [hx_jump_buf + bx], al
    inc byte [hx_jump_len]
    inc byte [hx_jump_cursor]
    jmp .loop
.ext_key:
    cmp ah, 0x4B
    je .left
    cmp ah, 0x4D
    je .right
    jmp .loop
.left:
    cmp byte [hx_jump_cursor], 0
    je .loop
    dec byte [hx_jump_cursor]
    jmp .loop
.right:
    mov al, [hx_jump_cursor]
    cmp al, [hx_jump_len]
    jae .loop
    inc byte [hx_jump_cursor]
    jmp .loop
.backspace:
    cmp byte [hx_jump_cursor], 0
    je .loop
    dec byte [hx_jump_cursor]
    xor bx, bx
    mov bl, [hx_jump_cursor]
.shift_left:
    mov dl, [hx_jump_buf + bx + 1]
    mov [hx_jump_buf + bx], dl
    inc bx
    cmp bl, [hx_jump_len]
    jb .shift_left
    dec byte [hx_jump_len]
    jmp .loop
.go:
    cmp byte [hx_jump_len], 0
    je .cancel
    call hx_parse_jump_buffer_to_qword
    mov eax, [hx_total_lba_lo]
    mov edx, [hx_total_lba_hi]
    or eax, edx
    jz .store_target
    mov eax, [hx_jump_value_hi]
    cmp eax, [hx_total_lba_hi]
    jb .store_target
    ja .clamp_high
    mov eax, [hx_jump_value_lo]
    cmp eax, [hx_total_lba_lo]
    jb .store_target
    je .clamp_high
    ja .clamp_high
.clamp_high:
    cmp byte [hx_memory_mode], 0
    jne .memory_out_of_range
    mov eax, [hx_total_lba_lo]
    mov edx, [hx_total_lba_hi]
    sub eax, 1
    sbb edx, 0
    mov [hx_jump_value_lo], eax
    mov [hx_jump_value_hi], edx
    jmp short .store_target
.memory_out_of_range:
    mov word [hx_msg_ptr], hx_msg_memory_address_invalid
    call hx_beep
    jmp .done
.store_target:
    mov eax, [hx_curr_lba_lo]
    mov [hx_saved_lba_lo], eax
    mov eax, [hx_curr_lba_hi]
    mov [hx_saved_lba_hi], eax
    mov eax, [hx_jump_value_lo]
    mov [hx_curr_lba_lo], eax
    mov eax, [hx_jump_value_hi]
    mov [hx_curr_lba_hi], eax
    call hx_load_current_sector
    jnc .ok
    ; Format the failing high-memory reason before reloading the old page,
    ; because that successful recovery read intentionally clears the code.
    call hx_set_read_failure_msg
    mov eax, [hx_saved_lba_lo]
    mov [hx_curr_lba_lo], eax
    mov eax, [hx_saved_lba_hi]
    mov [hx_curr_lba_hi], eax
    call hx_load_current_sector
    call hx_beep
    jmp .done
.ok:
    call hx_reset_edit_state_after_load
    cmp byte [hx_memory_mode], 0
    je .disk_jump_done
    ; Ctrl+G accepts a byte address in memory mode. The loaded page begins at
    ; address & FFFFFE00h, while the cursor selects address & 01FFh in whichever
    ; HEX/ASCII edit mode was already active.
    mov ax, [hx_jump_byte_offset]
    mov [hx_cursor_pos], ax
    mov [hx_old_cursor_pos], ax
    mov word [hx_msg_ptr], hx_msg_memory_jump_done
    jmp short .done
.disk_jump_done:
    mov word [hx_msg_ptr], hx_msg_jump_done
    jmp .done
.cancel:
    mov word [hx_msg_ptr], hx_msg_jump_cancel
.done:
    call hx_clear_overlay_lines
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

hx_clear_jump_buffer:
    mov byte [hx_jump_len], 0
    mov byte [hx_jump_cursor], 0
    mov byte [hx_jump_buf], 0
    mov word [hx_jump_byte_offset], 0
    ret

hx_draw_jump_overlay:
    mov dh, hx_JUMP_ROW
    mov dl, 0
    mov bl, 0x1E
    mov si, hx_str_spaces80
    call hx_print_string_at
    mov dh, hx_JUMP_HELP_ROW
    mov dl, 0
    mov bl, 0x1E
    mov si, hx_str_spaces80
    call hx_print_string_at
    mov dh, hx_JUMP_ROW
    mov dl, 0
    mov bl, 0x1E
    mov si, hx_str_jump_prompt
    cmp byte [hx_memory_mode], 0
    je .prompt_ready
    mov si, hx_str_jump_prompt_memory
.prompt_ready:
    call hx_print_string_at
    mov dh, hx_JUMP_ROW
    mov dl, hx_JUMP_INPUT_COL
    mov bl, 0x1E
    mov si, hx_jump_buf
    call hx_print_string_at
    mov dh, hx_JUMP_HELP_ROW
    mov dl, 0
    mov bl, 0x1E
    mov si, hx_str_jump_help
    cmp byte [hx_memory_mode], 0
    je .help_ready
    mov si, hx_str_jump_help_memory
.help_ready:
    call hx_print_string_at
    mov ah, 0x02
    xor bh, bh
    mov dh, hx_JUMP_ROW
    mov dl, hx_JUMP_INPUT_COL
    add dl, [hx_jump_cursor]
    int 0x10
    ret

hx_clear_overlay_lines:
    push bx
    push dx
    push si
    call hx_mouse_hide_overlay
    mov dh, hx_JUMP_ROW
    mov dl, 0
    mov bl, 0x07
    mov si, hx_str_spaces80
    call hx_print_string_at
    mov dh, hx_JUMP_HELP_ROW
    mov dl, 0
    mov bl, 0x07
    mov si, hx_str_spaces80
    call hx_print_string_at
    call hx_mouse_show_overlay
    pop si
    pop dx
    pop bx
    ret

hx_parse_jump_buffer_to_qword:
    push ax
    push bx
    push cx
    push dx
    push si
    xor eax, eax
    xor edx, edx
    mov [hx_jump_value_lo], eax
    mov [hx_jump_value_hi], edx
    mov word [hx_jump_byte_offset], 0
    mov si, hx_jump_buf
    cmp byte [hx_memory_mode], 0
    jne .hex_loop
.decimal_loop:
    lodsb
    test al, al
    jz .done
    sub al, '0'
    xor ebx, ebx
    mov bl, al
    mov eax, [hx_jump_value_lo]
    mov edx, [hx_jump_value_hi]
    mov [hx_conv_qword + 0], eax
    mov [hx_conv_qword + 4], edx
    shld edx, eax, 1
    shl eax, 1
    mov [hx_parse_tmp_lo], eax
    mov [hx_parse_tmp_hi], edx
    mov eax, [hx_conv_qword + 0]
    mov edx, [hx_conv_qword + 4]
    shld edx, eax, 3
    shl eax, 3
    add eax, [hx_parse_tmp_lo]
    adc edx, [hx_parse_tmp_hi]
    add eax, ebx
    adc edx, 0
    mov [hx_jump_value_lo], eax
    mov [hx_jump_value_hi], edx
    jmp .decimal_loop
.hex_loop:
    lodsb
    test al, al
    jz .hex_done
    call hx_ascii_hex_to_nibble
    xor ebx, ebx
    mov bl, al
    mov eax, [hx_jump_value_lo]
    mov edx, [hx_jump_value_hi]
    shld edx, eax, 4
    shl eax, 4
    or eax, ebx
    mov [hx_jump_value_lo], eax
    mov [hx_jump_value_hi], edx
    jmp .hex_loop
.hex_done:
    mov eax, [hx_jump_value_lo]
    mov edx, [hx_jump_value_hi]
    mov bx, ax
    and bx, hx_BYTES_PER_SECTOR-1
    mov [hx_jump_byte_offset], bx
    shrd eax, edx, 9
    shr edx, 9
    mov [hx_jump_value_lo], eax
    mov [hx_jump_value_hi], edx
.done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

hx_kbd_has_key:
    cmp byte [hx_kbd_pending_valid], 0
    jne .ready
    mov ah, 0x01
    int 0x16
    ret
.ready:
    mov al, 1
    or al, al
    ret

hx_kbd_read_key:
    cmp byte [hx_kbd_pending_valid], 0
    je .bios
    mov ax, [hx_kbd_pending_ax]
    mov byte [hx_kbd_pending_valid], 0
    ret
.bios:
    ; Keep an idle dialog from looking like a hung operation.  Polling still
    ; lets the watchdog detect a BIOS call which itself never returns.
.wait:
    mov byte [hx_watchdog_ticks], 0
    mov ah, 0x01
    int 0x16
    jz .wait
    mov ah, 0x00
    int 0x16
    ret

hx_is_shift_down:
    push ax
    mov ah, 0x02
    int 0x16
    test al, 0x03
    pop ax
    jz .no
    stc
    ret
.no:
    clc
    ret

hx_is_ctrl_down:
    push ax
    mov ah, 0x02
    int 0x16
    test al, 0x0C
    pop ax
    jz .no
    stc
    ret
.no:
    clc
    ret

hx_clear_selection:
    mov byte [hx_selection_active], 0
    mov ax, [hx_cursor_pos]
    mov [hx_selection_anchor], ax
    ret

hx_has_multi_selection:
    cmp byte [hx_selection_active], 0
    je .no
    stc
    ret
.no:
    clc
    ret

hx_begin_selection_if_needed:
    cmp byte [hx_selection_active], 0
    jne .done
    mov [hx_selection_anchor], ax
    mov byte [hx_selection_active], 1
.done:
    ret

hx_finalize_shift_selection:
    mov ax, [hx_cursor_pos]
    cmp ax, [hx_selection_anchor]
    jne .keep
    mov byte [hx_selection_active], 0
    ret
.keep:
    mov byte [hx_selection_active], 1
    ret

hx_get_selection_bounds:
    mov bx, [hx_cursor_pos]
    mov dx, bx
    cmp byte [hx_selection_active], 0
    je .done
    mov ax, [hx_selection_anchor]
    cmp ax, bx
    jbe .anchor_low
    mov dx, ax
    jmp .done
.anchor_low:
    mov dx, bx
    mov bx, ax
.done:
    ret

hx_is_index_highlighted:
    cmp bx, [hx_cursor_pos]
    je .yes
    cmp byte [hx_selection_active], 0
    je .no
    push ax
    push dx
    mov ax, [hx_selection_anchor]
    mov dx, [hx_cursor_pos]
    cmp ax, dx
    jbe .ordered
    xchg ax, dx
.ordered:
    cmp bx, ax
    jb .miss
    cmp bx, dx
    ja .miss
    pop dx
    pop ax
    stc
    ret
.miss:
    pop dx
    pop ax
.no:
    clc
    ret
.yes:
    stc
    ret

hx_get_byte_display_attr:
    mov ah, 0x07

.check_selected:
    push bx
    call hx_is_index_highlighted
    pop bx
    jnc .done
    mov ah, 0xF0
.done:
    ret

hx_clear_normal_history:
    mov word [hx_undo_count], 0
    mov word [hx_redo_count], 0
    mov word [hx_undo_action_count], 0
    mov word [hx_redo_action_count], 0
    ret

hx_ensure_undo_capacity:
    push ax
    mov ax, [hx_undo_count]
    add ax, cx
    cmp ax, hx_HISTORY_MAX
    jbe .check_actions
    call hx_clear_normal_history
.check_actions:
    mov ax, [hx_undo_action_count]
    inc ax
    cmp ax, hx_HISTORY_MAX
    jbe .done
    call hx_clear_normal_history
.done:
    pop ax
    ret

hx_push_undo_action_size:
    push bx
    mov bx, [hx_undo_action_count]
    cmp bx, hx_HISTORY_MAX
    jae .done
    shl bx, 1
    mov [hx_undo_action_sizes + bx], cx
    inc word [hx_undo_action_count]
.done:
    pop bx
    ret

hx_push_redo_action_size:
    push bx
    mov bx, [hx_redo_action_count]
    cmp bx, hx_HISTORY_MAX
    jae .done
    shl bx, 1
    mov [hx_redo_action_sizes + bx], cx
    inc word [hx_redo_action_count]
.done:
    pop bx
    ret

hx_pop_undo_action_size:
    push bx
    cmp word [hx_undo_action_count], 0
    je .empty
    dec word [hx_undo_action_count]
    mov bx, [hx_undo_action_count]
    shl bx, 1
    mov cx, [hx_undo_action_sizes + bx]
    pop bx
    clc
    ret
.empty:
    pop bx
    stc
    ret

hx_pop_redo_action_size:
    push bx
    cmp word [hx_redo_action_count], 0
    je .empty
    dec word [hx_redo_action_count]
    mov bx, [hx_redo_action_count]
    shl bx, 1
    mov cx, [hx_redo_action_sizes + bx]
    pop bx
    clc
    ret
.empty:
    pop bx
    stc
    ret

hx_copy_selection_to_clipboard:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    call hx_get_selection_bounds
    mov si, bx
    mov di, hx_clipboard_buf
    xor cx, cx
.copy:
    mov al, [hx_sector_buf + si]
    mov [di], al
    inc di
    inc cx
    cmp si, dx
    je .done_copy
    inc si
    jmp .copy
.done_copy:
    mov [hx_clipboard_len], cx
    cmp cx, 1
    je .single
    mov word [hx_msg_ptr], hx_msg_copied_multi
    jmp .done
.single:
    mov word [hx_msg_ptr], hx_msg_copied_single
.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

hx_cut_selection_to_clipboard_and_clear:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    ; 1. 将选区内容复制到剪贴板
    call hx_copy_selection_to_clipboard
    cmp word [hx_clipboard_len], 0
    je .nothing_copied

    ; 2. 获取选区范围（起始索引 bx，结束索引 dx）
    call hx_get_selection_bounds
    mov si, bx          ; si = 起始索引
    mov dx, dx          ; dx = 结束索引
    mov cx, dx
    sub cx, si
    inc cx              ; cx = 选区总字节数

    ; 3. 统计实际需要修改的字节数（原值不为0的字节）
    mov bx, si
    xor bp, bp          ; bp = 实际变化数量
.count_changes:
    cmp cx, 0
    je .count_done
    mov al, [hx_sector_buf + bx]
    test al, al
    jz .count_next
    inc bp
.count_next:
    inc bx
    dec cx
    jmp .count_changes
.count_done:
    cmp bp, 0
    jne .have_changes
    ; 没有实际变化，但剪贴板已复制，直接清除高亮并显示成功
    mov word [hx_msg_ptr], hx_msg_cut_done
    call hx_clear_selection
    jmp .done

.have_changes:
    ; 4. 准备撤销快照（保存当前扇区状态）
    call hx_prepare_undo_snapshot_before_edit

    ; 5. 确保撤销栈有足够容量
    mov cx, bp
    call hx_ensure_undo_capacity

    ; 6. 清空重做历史（新操作会使重做失效）
    mov word [hx_redo_count], 0
    mov word [hx_redo_action_count], 0
    mov byte [hx_clear_redo_available], 0
    mov byte [hx_clear_undo_available], 0

    ; 7. 重新遍历选区，清零并记录每个变化的字节
    mov bx, si
    mov cx, dx
    sub cx, si
    inc cx
    xor bp, bp          ; 再次统计实际记录的条目数（应与之前相同）
.apply_loop:
    cmp cx, 0
    je .after_apply
    mov al, [hx_sector_buf + bx]  ; 旧值
    test al, al
    jz .apply_next             ; 若已是0，无需记录
    xor dl, dl                 ; 新值 = 0
    mov [hx_sector_buf + bx], dl  ; 写入0
    call hx_push_undo_entry       ; 记录此字节的变化（旧值 al，新值 dl，位置 bx）
    inc bp
.apply_next:
    inc bx
    dec cx
    jmp .apply_loop

.after_apply:
    ; 8. 将这一批更改作为一个原子动作压入撤销栈
    mov cx, bp
    call hx_push_undo_action_size

    ; 9. 刷新脏标志和消息
    call hx_refresh_dirty_flag_from_disk_snapshot
    call hx_set_edit_message_by_dirty

    ; 10. 清除选区高亮
    call hx_clear_selection
    mov word [hx_msg_ptr], hx_msg_cut_done
    jmp .done

.nothing_copied:
    mov word [hx_msg_ptr], hx_msg_clipboard_empty

.done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Fill the inclusive multi-selection with 00h.  Only bytes whose values really
; change consume history entries, but all changes are grouped into one atomic
; Ctrl+Z/Ctrl+Y action.  This helper intentionally leaves the clipboard alone.
hx_zero_selected_range:
    push ax
    push bx
    push cx
    push dx
    push si
    push bp
    call hx_get_selection_bounds
    mov si, bx
    mov cx, dx
    sub cx, si
    inc cx
    xor bp, bp
.count_changes:
    cmp byte [hx_sector_buf + bx], 0
    je .count_next
    inc bp
.count_next:
    inc bx
    loop .count_changes
    test bp, bp
    jz .finish

    call hx_prepare_undo_snapshot_before_edit
    mov cx, bp
    call hx_ensure_undo_capacity
    mov word [hx_redo_count], 0
    mov word [hx_redo_action_count], 0
    mov byte [hx_clear_redo_available], 0
    mov byte [hx_clear_undo_available], 0

    call hx_get_selection_bounds
    mov si, bx
    mov cx, dx
    sub cx, si
    inc cx
    xor bp, bp
.apply:
    mov al, [hx_sector_buf + bx]
    test al, al
    jz .next
    xor dl, dl
    mov [hx_sector_buf + bx], dl
    call hx_push_undo_entry
    inc bp
.next:
    inc bx
    loop .apply
    mov cx, bp
    call hx_push_undo_action_size
    call hx_refresh_dirty_flag_from_disk_snapshot
    call hx_set_edit_message_by_dirty
.finish:
    call hx_clear_selection
    pop bp
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

hx_select_all_sector:
    push ax
    mov word [hx_cursor_pos], hx_BYTES_PER_SECTOR - 1
    mov word [hx_selection_anchor], 0
    mov byte [hx_selection_active], 1
    mov byte [hx_hex_half], 0
    pop ax
    ret

hx_paste_clipboard_at_cursor:
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    mov cx, [hx_clipboard_len]
    cmp cx, 0
    jne .have_data
    mov word [hx_msg_ptr], hx_msg_clipboard_empty
    call hx_beep
    xor al, al
    jmp .done
.have_data:
    call hx_prepare_undo_snapshot_before_edit
    mov bx, [hx_cursor_pos]
    mov dx, hx_BYTES_PER_SECTOR
    sub dx, bx
    cmp cx, dx
    jbe .count_ok
    mov cx, dx
.count_ok:
    mov dx, cx
    mov si, hx_clipboard_buf
    mov bx, [hx_cursor_pos]
    xor bp, bp
    mov cx, dx
.count_changes:
    cmp cx, 0
    je .count_done
    mov al, [hx_sector_buf + bx]
    cmp al, [si]
    je .count_next
    inc bp
.count_next:
    inc si
    inc bx
    dec cx
    jmp .count_changes
.count_done:
    cmp bp, 0
    jne .have_changes
    mov word [hx_msg_ptr], hx_msg_paste_no_change
    xor al, al
    jmp .done
.have_changes:
    mov cx, bp
    call hx_ensure_undo_capacity
    mov word [hx_redo_count], 0
    mov word [hx_redo_action_count], 0
    mov byte [hx_clear_redo_available], 0
    mov byte [hx_clear_undo_available], 0
    mov si, hx_clipboard_buf
    mov bx, [hx_cursor_pos]
    mov cx, dx
.apply_loop:
    cmp cx, 0
    je .after_apply
    mov al, [hx_sector_buf + bx]
    mov dl, [si]
    cmp al, dl
    je .apply_next
    mov [hx_sector_buf + bx], dl
    call hx_push_undo_entry
.apply_next:
    inc si
    inc bx
    dec cx
    jmp .apply_loop
.after_apply:
    mov cx, bp
    call hx_push_undo_action_size
    cmp bx, hx_BYTES_PER_SECTOR
    jb .store_cursor
    mov bx, hx_BYTES_PER_SECTOR - 1
.store_cursor:
    mov [hx_cursor_pos], bx
    mov [hx_selection_anchor], bx
    mov byte [hx_selection_active], 0
    mov byte [hx_hex_half], 0
    mov byte [hx_pending_hex_active], 0
    call hx_refresh_dirty_flag_from_disk_snapshot
    call hx_set_edit_message_by_dirty
    mov word [hx_msg_ptr], hx_msg_pasted_ok
    mov al, 1
.done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    ret

hx_clear_find_buffer:
    mov byte [hx_find_input_len], 0
    mov byte [hx_find_input_cursor], 0
    mov byte [hx_find_input_buf], 0
    ret

hx_preload_find_input_from_selection:
    call hx_clear_find_buffer
    cmp byte [hx_selection_active], 0
    je .done
    call hx_get_selection_bounds
    mov di, hx_find_input_buf
    xor cx, cx
    cmp byte [hx_find_mode], 1
    je .hex_mode
.ascii_loop:
    mov al, [hx_sector_buf + bx]
    cmp al, 0x20
    jb .ascii_next
    cmp al, 0x7F
    je .ascii_next
    mov [di], al
    inc di
    inc cx
    cmp cx, hx_FIND_TEXT_MAX
    jae .finish
.ascii_next:
    cmp bx, dx
    je .finish
    inc bx
    jmp .ascii_loop
.hex_mode:
.hex_loop:
    mov al, [hx_sector_buf + bx]
    push bx
    mov ah, al
    shr al, 4
    and al, 0x0F
    call hx_nibble_to_ascii
    mov [di], al
    inc di
    inc cx
    cmp cx, hx_FIND_TEXT_MAX
    jae .finish_hex_pop
    mov al, ah
    and al, 0x0F
    call hx_nibble_to_ascii
    mov [di], al
    inc di
    inc cx
    pop bx
    cmp cx, hx_FIND_TEXT_MAX
    jae .finish
    cmp bx, dx
    je .finish
    inc bx
    jmp .hex_loop
.finish_hex_pop:
    pop bx
.finish:
    mov [hx_find_input_len], cl
    mov [hx_find_input_cursor], cl
    mov byte [di], 0
.done:
    ret

hx_normalize_hex_input_char:
    cmp al, '0'
    jb .check_upper
    cmp al, '9'
    jbe .ok
.check_upper:
    cmp al, 'A'
    jb .check_lower
    cmp al, 'F'
    jbe .ok
.check_lower:
    cmp al, 'a'
    jb .bad
    cmp al, 'f'
    ja .bad
    sub al, 32
.ok:
    clc
    ret
.bad:
    stc
    ret

hx_choose_find_mode_dialog:
.loop:
    call hx_draw_find_mode_overlay
    call hx_kbd_read_key
    cmp al, 0x1B
    je .cancel
    cmp al, '1'
    je .hex
    cmp al, '2'
    je .ascii
    jmp .loop
.hex:
    mov al, 1
    jmp .done
.ascii:
    mov al, 2
    jmp .done
.cancel:
    xor al, al
.done:
    call hx_clear_overlay_lines
    call hx_update_hw_cursor
    ret

hx_draw_find_mode_overlay:
    push ax
    push bx
    push dx
    push si
    mov dh, hx_JUMP_ROW
    mov dl, 0
    mov bl, 0x1E
    mov si, hx_str_spaces80
    call hx_print_string_at
    mov dh, hx_JUMP_HELP_ROW
    mov dl, 0
    mov bl, 0x1E
    mov si, hx_str_spaces80
    call hx_print_string_at
    mov dh, hx_JUMP_ROW
    mov dl, 0
    mov bl, 0x1E
    mov si, hx_str_find_mode_prompt
    call hx_print_string_at
    mov dh, hx_JUMP_HELP_ROW
    mov dl, 0
    mov bl, 0x1E
    mov si, hx_str_find_mode_help
    call hx_print_string_at
    mov ah, 0x02
    xor bh, bh
    mov dh, hx_JUMP_HELP_ROW
    mov dl, 0
    int 0x10
    pop si
    pop dx
    pop bx
    pop ax
    ret

hx_find_input_dialog:
    push bx
    push cx
    push dx
    push si
.loop:
    call hx_draw_find_input_overlay
    call hx_kbd_read_key
    cmp al, 0x1B
    je .cancel
    cmp al, 0x0D
    je .accept
    cmp al, 0x08
    je .backspace
    cmp al, 0
    je .ext_key
    cmp byte [hx_find_mode], 1
    jne .ascii_char
    call hx_normalize_hex_input_char
    jc .loop
    jmp .insert
.ascii_char:
    cmp al, 0x20
    jb .loop
    cmp al, 0x7F
    je .loop
.insert:
    cmp byte [hx_find_input_len], hx_FIND_TEXT_MAX
    jae .loop
    xor bx, bx
    mov bl, [hx_find_input_len]
.shift_right:
    mov cl, [hx_find_input_cursor]
    cmp bl, cl
    jb .place
    mov dl, [hx_find_input_buf + bx]
    mov [hx_find_input_buf + bx + 1], dl
    cmp bl, cl
    je .place
    dec bx
    jmp .shift_right
.place:
    xor bx, bx
    mov bl, [hx_find_input_cursor]
    mov [hx_find_input_buf + bx], al
    inc byte [hx_find_input_len]
    inc byte [hx_find_input_cursor]
    xor bx, bx
    mov bl, [hx_find_input_len]
    mov byte [hx_find_input_buf + bx], 0
    jmp .loop
.ext_key:
    cmp ah, 0x4B
    je .left
    cmp ah, 0x4D
    je .right
    jmp .loop
.left:
    cmp byte [hx_find_input_cursor], 0
    je .loop
    dec byte [hx_find_input_cursor]
    jmp .loop
.right:
    mov al, [hx_find_input_cursor]
    cmp al, [hx_find_input_len]
    jae .loop
    inc byte [hx_find_input_cursor]
    jmp .loop
.backspace:
    cmp byte [hx_find_input_cursor], 0
    je .loop
    dec byte [hx_find_input_cursor]
    xor bx, bx
    mov bl, [hx_find_input_cursor]
.shift_left:
    mov dl, [hx_find_input_buf + bx + 1]
    mov [hx_find_input_buf + bx], dl
    inc bx
    cmp bl, [hx_find_input_len]
    jb .shift_left
    dec byte [hx_find_input_len]
    xor bx, bx
    mov bl, [hx_find_input_len]
    mov byte [hx_find_input_buf + bx], 0
    jmp .loop
.accept:
    mov al, 1
    jmp .done
.cancel:
    xor al, al
.done:
    call hx_clear_overlay_lines
    call hx_update_hw_cursor
    pop si
    pop dx
    pop cx
    pop bx
    ret

hx_draw_find_input_overlay:
    push ax
    push bx
    push dx
    push si
    mov dh, hx_JUMP_ROW
    mov dl, 0
    mov bl, 0x1E
    mov si, hx_str_spaces80
    call hx_print_string_at
    mov dh, hx_JUMP_HELP_ROW
    mov dl, 0
    mov bl, 0x1E
    mov si, hx_str_spaces80
    call hx_print_string_at
    cmp byte [hx_find_mode], 1
    jne .ascii_mode
    mov dh, hx_JUMP_ROW
    mov dl, 0
    mov bl, 0x1E
    mov si, hx_str_find_hex_prompt
    call hx_print_string_at
    mov dh, hx_JUMP_ROW
    mov dl, 10
    mov bl, 0x1E
    mov si, hx_find_input_buf
    call hx_print_string_at
    mov dh, hx_JUMP_HELP_ROW
    mov dl, 0
    mov bl, 0x1E
    mov si, hx_str_find_hex_help
    call hx_print_string_at
    mov ah, 0x02
    xor bh, bh
    mov dh, hx_JUMP_ROW
    mov dl, 10
    add dl, [hx_find_input_cursor]
    int 0x10
    jmp .done
.ascii_mode:
    mov dh, hx_JUMP_ROW
    mov dl, 0
    mov bl, 0x1E
    mov si, hx_str_find_ascii_prompt
    call hx_print_string_at
    mov dh, hx_JUMP_ROW
    mov dl, 12
    mov bl, 0x1E
    mov si, hx_find_input_buf
    call hx_print_string_at
    mov dh, hx_JUMP_HELP_ROW
    mov dl, 0
    mov bl, 0x1E
    mov si, hx_str_find_ascii_help
    call hx_print_string_at
    mov ah, 0x02
    xor bh, bh
    mov dh, hx_JUMP_ROW
    mov dl, 12
    add dl, [hx_find_input_cursor]
    int 0x10
.done:
    pop si
    pop dx
    pop bx
    pop ax
    ret

hx_build_find_pattern:
    cmp byte [hx_find_mode], 1
    je .hex_mode
    xor cx, cx
    mov cl, [hx_find_input_len]
    xor bx, bx
.ascii_copy:
    cmp bx, cx
    jae .ascii_done
    mov al, [hx_find_input_buf + bx]
    mov [hx_find_pattern_buf + bx], al
    inc bx
    jmp .ascii_copy
.ascii_done:
    ret
.hex_mode:
    mov al, [hx_find_input_len]
    and al, 1
    jz .hex_even
    dec byte [hx_find_input_len]
    xor bx, bx
    mov bl, [hx_find_input_len]
    mov byte [hx_find_input_buf + bx], 0
.hex_even:
    xor bx, bx
    xor cx, cx
.hex_loop:
    mov al, [hx_find_input_buf + bx]
    test al, al
    jz .hex_done
    call hx_ascii_hex_to_nibble
    shl al, 4
    mov dl, al
    inc bx
    mov al, [hx_find_input_buf + bx]
    call hx_ascii_hex_to_nibble
    or dl, al
    push bx
    mov bx, cx
    mov [hx_find_pattern_buf + bx], dl
    pop bx
    inc cx
    inc bx
    jmp .hex_loop
.hex_done:
    ret

hx_apply_find_hit_and_refresh:
    push bx
    push dx
    mov eax, [hx_find_hit_lba_lo]
    cmp eax, [hx_curr_lba_lo]
    jne .switch_sector
    mov eax, [hx_find_hit_lba_hi]
    cmp eax, [hx_curr_lba_hi]
    jne .switch_sector
    jmp .apply_only
.switch_sector:
    cmp byte [hx_dirty_flag], 0
    je .do_switch
    call hx_confirm_save_before_switch
    cmp al, 0
    je .cancel
    cmp al, 1
    jne .do_switch
    call hx_save_current_sector
    jc .save_fail
.do_switch:
    mov eax, [hx_find_hit_lba_lo]
    mov [hx_curr_lba_lo], eax
    mov eax, [hx_find_hit_lba_hi]
    mov [hx_curr_lba_hi], eax
    call hx_load_current_sector
    jc .load_fail
    call hx_reset_edit_state_after_load
.apply_only:
    pop dx
    pop bx
    mov [hx_cursor_pos], bx
    mov [hx_selection_anchor], dx
    cmp bx, dx
    je .single
    mov byte [hx_selection_active], 1
    mov word [hx_msg_ptr], hx_msg_find_found_multi
    call hx_refresh_sector_area
    mov al, 1
    ret
.single:
    mov byte [hx_selection_active], 0
    mov word [hx_msg_ptr], hx_msg_find_found_single
    call hx_refresh_sector_area
    mov al, 1
    ret
.cancel:
    pop dx
    pop bx
    call hx_refresh_meta_ui
    xor al, al
    ret
.save_fail:
    pop dx
    pop bx
    call hx_refresh_meta_ui
    xor al, al
    ret
.load_fail:
    pop dx
    pop bx
    call hx_set_read_failure_msg
    call hx_beep
    call hx_refresh_meta_ui
    xor al, al
    ret

hx_check_search_cancel:
    push ax
    mov byte [hx_watchdog_ticks], 0
.poll:
    mov ah, 0x01
    int 0x16
    jz .no_key
    mov ah, 0x00
    int 0x16
    cmp al, 0x1B
    je .cancel
    jmp .poll
.no_key:
    pop ax
    clc
    ret
.cancel:
    pop ax
    stc
    ret

hx_reset_search_cancel_poll:
    mov byte [hx_search_cancel_budget], 0
    ret

hx_reset_find_progress_timer:
    push ax
    mov ax, [0x046C]
    sub ax, 4
    mov [hx_find_progress_last_tick], ax
    pop ax
    ret

hx_check_search_cancel_throttled:
    cmp byte [hx_search_cancel_budget], 0
    je .poll
    dec byte [hx_search_cancel_budget]
    clc
    ret
.poll:
    mov byte [hx_search_cancel_budget], hx_SEARCH_CANCEL_POLL_INTERVAL
    jmp hx_check_search_cancel

hx_read_search_sector_by_lba:
    cmp byte [hx_memory_mode], 0
    je .disk
    mov eax, [hx_search_lba_lo]
    mov edx, [hx_search_lba_hi]
    mov di, hx_search_sector_buf
    call hx_copy_memory_page_to_buffer
    ret
.disk:
    mov byte [hx_dap_search + 0], 0x10
    mov byte [hx_dap_search + 1], 0x00
    mov word [hx_dap_search + 2], 1
    mov word [hx_dap_search + 4], hx_search_sector_buf
    mov word [hx_dap_search + 6], 0x0000
    mov eax, [hx_search_lba_lo]
    mov [hx_dap_search + 8], eax
    mov eax, [hx_search_lba_hi]
    mov [hx_dap_search + 12], eax

    mov cx, 3

.retry:
    mov si, hx_dap_search
    call hx_disk_read_dap
    jnc .ok

    call hx_disk_reset_current
    loop .retry

    stc
    ret

.ok:
    clc
    ret


hx_inc_search_lba:
    mov eax, [hx_search_lba_lo]
    add eax, 1
    mov [hx_search_lba_lo], eax
    mov eax, [hx_search_lba_hi]
    adc eax, 0
    mov [hx_search_lba_hi], eax
    ret

hx_dec_search_lba:
    mov eax, [hx_search_lba_lo]
    sub eax, 1
    mov [hx_search_lba_lo], eax
    mov eax, [hx_search_lba_hi]
    sbb eax, 0
    mov [hx_search_lba_hi], eax
    ret

hx_find_pattern_across_disk:
    mov [hx_find_pattern_len], cx
    mov [hx_find_origin_index], ax
    mov byte [hx_search_cancelled_flag], 0
    call hx_reset_search_cancel_poll
    cmp cx, 0
    je .not_found
    mov ax, hx_BYTES_PER_SECTOR
    sub ax, cx
    mov [hx_find_last_start], ax
    mov si, [hx_find_origin_index]
    cmp si, [hx_find_last_start]
    jbe .search_curr_tail
    jmp .after_curr_tail
.search_curr_tail:
    mov di, [hx_find_last_start]
    call hx_find_pattern_in_main_sector_range
    jnc .found_in_current
    cmp byte [hx_search_cancelled_flag], 0
    jne .cancelled
.after_curr_tail:
    mov eax, [hx_curr_lba_lo]
    mov [hx_search_lba_lo], eax
    mov eax, [hx_curr_lba_hi]
    mov [hx_search_lba_hi], eax
    call hx_inc_search_lba
.forward_loop:
    call hx_update_find_progress
    call hx_check_search_cancel
    jc .cancelled
    mov eax, [hx_total_lba_lo]
    mov edx, [hx_total_lba_hi]
    or eax, edx
    jz .forward_read
    mov eax, [hx_search_lba_hi]
    cmp eax, [hx_total_lba_hi]
    jb .forward_read
    ja .wrap_begin
    mov eax, [hx_search_lba_lo]
    cmp eax, [hx_total_lba_lo]
    jb .forward_read
    jmp .wrap_begin
.forward_read:
    call hx_read_search_sector_by_lba
    jc .wrap_begin
    xor si, si
    mov di, [hx_find_last_start]
    call hx_find_pattern_in_search_sector_range
    jnc .found_in_search
    cmp byte [hx_search_cancelled_flag], 0
    jne .cancelled
    call hx_inc_search_lba
    jmp .forward_loop
.wrap_begin:
    xor eax, eax
    mov [hx_search_lba_lo], eax
    mov [hx_search_lba_hi], eax
.wrap_loop:
    call hx_update_find_progress
    call hx_check_search_cancel
    jc .cancelled
    mov eax, [hx_search_lba_hi]
    cmp eax, [hx_curr_lba_hi]
    jb .wrap_read
    ja .search_curr_head
    mov eax, [hx_search_lba_lo]
    cmp eax, [hx_curr_lba_lo]
    jb .wrap_read
    jmp .search_curr_head
.wrap_read:
    call hx_read_search_sector_by_lba
    jc .search_curr_head
    xor si, si
    mov di, [hx_find_last_start]
    call hx_find_pattern_in_search_sector_range
    jnc .found_in_search
    cmp byte [hx_search_cancelled_flag], 0
    jne .cancelled
    call hx_inc_search_lba
    jmp .wrap_loop
.search_curr_head:
    mov ax, [hx_find_origin_index]
    cmp ax, 0
    je .not_found
    dec ax
    cmp ax, [hx_find_last_start]
    jbe .curr_head_ok
    mov ax, [hx_find_last_start]
.curr_head_ok:
    xor si, si
    mov di, ax
    call hx_find_pattern_in_main_sector_range
    jnc .found_in_current
    cmp byte [hx_search_cancelled_flag], 0
    jne .cancelled
.not_found:
    xor al, al
    ret
.cancelled:
    mov al, 2
    ret
.found_in_current:
    mov eax, [hx_curr_lba_lo]
    mov [hx_find_hit_lba_lo], eax
    mov eax, [hx_curr_lba_hi]
    mov [hx_find_hit_lba_hi], eax
    mov al, 1
    ret
.found_in_search:
    mov eax, [hx_search_lba_lo]
    mov [hx_find_hit_lba_lo], eax
    mov eax, [hx_search_lba_hi]
    mov [hx_find_hit_lba_hi], eax
    mov al, 1
    ret

hx_find_pattern_across_disk_reverse:
    mov [hx_find_pattern_len], cx
    mov [hx_find_origin_index], ax
    mov byte [hx_search_cancelled_flag], 0
    call hx_reset_search_cancel_poll
    cmp cx, 0
    je .not_found
    mov ax, hx_BYTES_PER_SECTOR
    sub ax, cx
    mov [hx_find_last_start], ax
    mov si, [hx_find_origin_index]
    cmp si, [hx_find_last_start]
    jbe .curr_ok
    mov si, [hx_find_last_start]
.curr_ok:
    xor di, di
    call hx_find_pattern_in_main_sector_range_reverse
    jnc .found_in_current
    cmp byte [hx_search_cancelled_flag], 0
    jne .cancelled
    mov eax, [hx_curr_lba_lo]
    mov [hx_search_lba_lo], eax
    mov eax, [hx_curr_lba_hi]
    mov [hx_search_lba_hi], eax
    mov eax, [hx_search_lba_lo]
    mov edx, [hx_search_lba_hi]
    or eax, edx
    jz .not_found
    call hx_dec_search_lba
.prev_loop:
    call hx_update_find_progress
    call hx_check_search_cancel
    jc .cancelled
    call hx_read_search_sector_by_lba
    jc .not_found
    mov si, [hx_find_last_start]
    xor di, di
    call hx_find_pattern_in_search_sector_range_reverse
    jnc .found_in_search
    cmp byte [hx_search_cancelled_flag], 0
    jne .cancelled
    mov eax, [hx_search_lba_lo]
    mov edx, [hx_search_lba_hi]
    or eax, edx
    jz .not_found
    call hx_dec_search_lba
    jmp .prev_loop
.not_found:
    xor al, al
    ret
.cancelled:
    mov al, 2
    ret
.found_in_current:
    mov eax, [hx_curr_lba_lo]
    mov [hx_find_hit_lba_lo], eax
    mov eax, [hx_curr_lba_hi]
    mov [hx_find_hit_lba_hi], eax
    mov al, 1
    ret
.found_in_search:
    mov eax, [hx_search_lba_lo]
    mov [hx_find_hit_lba_lo], eax
    mov eax, [hx_search_lba_hi]
    mov [hx_find_hit_lba_hi], eax
    mov al, 1
    ret

hx_find_pattern_in_main_sector_range_reverse:
    cmp si, di
    jb .not_found
    cmp word [hx_find_pattern_len], 1
    je .single
    cmp word [hx_find_pattern_len], 2
    je .double
    mov al, [hx_find_pattern_buf]
.loop:
    call hx_check_search_cancel_throttled
    jc .cancel
    cmp al, [hx_sector_buf + si]
    jne .next
    mov bx, si
    call hx_match_find_pattern_at_main_tail
    jnc .found
.next:
    dec si
    cmp si, di
    jae .loop
.not_found:
    stc
    ret
.single:
    mov al, [hx_find_pattern_buf]
.single_loop:
    call hx_check_search_cancel_throttled
    jc .cancel
    cmp al, [hx_sector_buf + si]
    je .found_single
    dec si
    cmp si, di
    jae .single_loop
    stc
    ret
.double:
    mov al, [hx_find_pattern_buf]
    mov ah, [hx_find_pattern_buf + 1]
.double_loop:
    call hx_check_search_cancel_throttled
    jc .cancel
    cmp al, [hx_sector_buf + si]
    jne .double_next
    cmp ah, [hx_sector_buf + si + 1]
    je .found_double
.double_next:
    dec si
    cmp si, di
    jae .double_loop
    stc
    ret
.cancel:
    mov byte [hx_search_cancelled_flag], 1
    stc
    ret
.found_single:
    mov bx, si
    mov dx, si
    clc
    ret
.found_double:
    mov bx, si
    mov dx, si
    inc dx
    clc
    ret
.found:
    mov dx, bx
    add dx, [hx_find_pattern_len]
    dec dx
    clc
    ret

hx_find_pattern_in_search_sector_range_reverse:
    cmp si, di
    jb .not_found
    cmp word [hx_find_pattern_len], 1
    je .single
    cmp word [hx_find_pattern_len], 2
    je .double
    mov al, [hx_find_pattern_buf]
.loop:
    call hx_check_search_cancel_throttled
    jc .cancel
    cmp al, [hx_search_sector_buf + si]
    jne .next
    mov bx, si
    call hx_match_find_pattern_at_search_tail
    jnc .found
.next:
    dec si
    cmp si, di
    jae .loop
.not_found:
    stc
    ret
.single:
    mov al, [hx_find_pattern_buf]
.single_loop:
    call hx_check_search_cancel_throttled
    jc .cancel
    cmp al, [hx_search_sector_buf + si]
    je .found_single
    dec si
    cmp si, di
    jae .single_loop
    stc
    ret
.double:
    mov al, [hx_find_pattern_buf]
    mov ah, [hx_find_pattern_buf + 1]
.double_loop:
    call hx_check_search_cancel_throttled
    jc .cancel
    cmp al, [hx_search_sector_buf + si]
    jne .double_next
    cmp ah, [hx_search_sector_buf + si + 1]
    je .found_double
.double_next:
    dec si
    cmp si, di
    jae .double_loop
    stc
    ret
.cancel:
    mov byte [hx_search_cancelled_flag], 1
    stc
    ret
.found_single:
    mov bx, si
    mov dx, si
    clc
    ret
.found_double:
    mov bx, si
    mov dx, si
    inc dx
    clc
    ret
.found:
    mov dx, bx
    add dx, [hx_find_pattern_len]
    dec dx
    clc
    ret

hx_find_pattern_in_main_sector_range:
    cmp si, di
    ja .not_found
    cmp word [hx_find_pattern_len], 1
    je .single
    cmp word [hx_find_pattern_len], 2
    je .double
    mov al, [hx_find_pattern_buf]
.loop:
    call hx_check_search_cancel_throttled
    jc .cancel
    cmp al, [hx_sector_buf + si]
    jne .next
    mov bx, si
    call hx_match_find_pattern_at_main_tail
    jnc .found
.next:
    inc si
    cmp si, di
    jbe .loop
.not_found:
    stc
    ret
.single:
    mov al, [hx_find_pattern_buf]
.single_loop:
    call hx_check_search_cancel_throttled
    jc .cancel
    cmp al, [hx_sector_buf + si]
    je .found_single
    inc si
    cmp si, di
    jbe .single_loop
    stc
    ret
.double:
    mov al, [hx_find_pattern_buf]
    mov ah, [hx_find_pattern_buf + 1]
.double_loop:
    call hx_check_search_cancel_throttled
    jc .cancel
    cmp al, [hx_sector_buf + si]
    jne .double_next
    cmp ah, [hx_sector_buf + si + 1]
    je .found_double
.double_next:
    inc si
    cmp si, di
    jbe .double_loop
    stc
    ret
.cancel:
    mov byte [hx_search_cancelled_flag], 1
    stc
    ret
.found_single:
    mov bx, si
    mov dx, si
    clc
    ret
.found_double:
    mov bx, si
    mov dx, si
    inc dx
    clc
    ret
.found:
    mov dx, bx
    add dx, [hx_find_pattern_len]
    dec dx
    clc
    ret

hx_find_pattern_in_search_sector_range:
    cmp si, di
    ja .not_found
    cmp word [hx_find_pattern_len], 1
    je .single
    cmp word [hx_find_pattern_len], 2
    je .double
    mov al, [hx_find_pattern_buf]
.loop:
    call hx_check_search_cancel_throttled
    jc .cancel
    cmp al, [hx_search_sector_buf + si]
    jne .next
    mov bx, si
    call hx_match_find_pattern_at_search_tail
    jnc .found
.next:
    inc si
    cmp si, di
    jbe .loop
.not_found:
    stc
    ret
.single:
    mov al, [hx_find_pattern_buf]
.single_loop:
    call hx_check_search_cancel_throttled
    jc .cancel
    cmp al, [hx_search_sector_buf + si]
    je .found_single
    inc si
    cmp si, di
    jbe .single_loop
    stc
    ret
.double:
    mov al, [hx_find_pattern_buf]
    mov ah, [hx_find_pattern_buf + 1]
.double_loop:
    call hx_check_search_cancel_throttled
    jc .cancel
    cmp al, [hx_search_sector_buf + si]
    jne .double_next
    cmp ah, [hx_search_sector_buf + si + 1]
    je .found_double
.double_next:
    inc si
    cmp si, di
    jbe .double_loop
    stc
    ret
.cancel:
    mov byte [hx_search_cancelled_flag], 1
    stc
    ret
.found_single:
    mov bx, si
    mov dx, si
    clc
    ret
.found_double:
    mov bx, si
    mov dx, si
    inc dx
    clc
    ret
.found:
    mov dx, bx
    add dx, [hx_find_pattern_len]
    dec dx
    clc
    ret

hx_match_find_pattern_at_main_tail:
    push ax
    push cx
    push si
    push di
    mov si, hx_find_pattern_buf + 1
    mov di, bx
    inc di
    mov cx, [hx_find_pattern_len]
    dec cx
.loop:
    cmp cx, 0
    je .match
    mov al, [hx_sector_buf + di]
    cmp al, [si]
    jne .miss
    inc si
    inc di
    dec cx
    jmp .loop
.match:
    pop di
    pop si
    pop cx
    pop ax
    clc
    ret
.miss:
    pop di
    pop si
    pop cx
    pop ax
    stc
    ret

hx_match_find_pattern_at_search_tail:
    push ax
    push cx
    push si
    push di
    mov si, hx_find_pattern_buf + 1
    mov di, bx
    inc di
    mov cx, [hx_find_pattern_len]
    dec cx
.loop:
    cmp cx, 0
    je .match
    mov al, [hx_search_sector_buf + di]
    cmp al, [si]
    jne .miss
    inc si
    inc di
    dec cx
    jmp .loop
.match:
    pop di
    pop si
    pop cx
    pop ax
    clc
    ret
.miss:
    pop di
    pop si
    pop cx
    pop ax
    stc
    ret

hx_move_left:
    cmp word [hx_cursor_pos], 0
    je .done
    dec word [hx_cursor_pos]
    mov byte [hx_hex_half], 0
.done:
    ret

hx_move_right:
    cmp word [hx_cursor_pos], hx_BYTES_PER_SECTOR - 1
    jae .done
    inc word [hx_cursor_pos]
    mov byte [hx_hex_half], 0
.done:
    ret

hx_move_up:
    cmp word [hx_cursor_pos], hx_BYTES_PER_ROW
    jb .done
    sub word [hx_cursor_pos], hx_BYTES_PER_ROW
    mov byte [hx_hex_half], 0
.done:
    ret

hx_move_down:
    cmp word [hx_cursor_pos], hx_BYTES_PER_SECTOR - hx_BYTES_PER_ROW
    jae .done
    add word [hx_cursor_pos], hx_BYTES_PER_ROW
    mov byte [hx_hex_half], 0
.done:
    ret

hx_backspace_zero_current_byte:
    push ax
    push bx
    push dx
    call hx_prepare_undo_snapshot_before_edit
    mov bx, [hx_cursor_pos]
    mov al, [hx_sector_buf + bx]
    xor dl, dl
    mov [hx_sector_buf + bx], dl
    call hx_record_byte_change
    call hx_refresh_dirty_flag_from_disk_snapshot
    mov byte [hx_hex_half], 0
    call hx_set_edit_message_by_dirty
    cmp word [hx_cursor_pos], 0
    je .done
    dec word [hx_cursor_pos]
.done:
    pop dx
    pop bx
    pop ax
    ret

hx_edit_current_byte_ascii:
    push ax
    push bx
    push dx
    call hx_prepare_undo_snapshot_before_edit
    mov dl, bl
    mov bx, [hx_cursor_pos]
    mov al, [hx_sector_buf + bx]
    mov [hx_sector_buf + bx], dl
    call hx_record_byte_change
    call hx_refresh_dirty_flag_from_disk_snapshot
    mov byte [hx_hex_half], 0
    call hx_set_edit_message_by_dirty
    cmp word [hx_cursor_pos], hx_BYTES_PER_SECTOR - 1
    jae .done
    inc word [hx_cursor_pos]
.done:
    pop dx
    pop bx
    pop ax
    ret

hx_edit_current_byte_hex:
    push ax
    push bx
    push cx
    push dx
    mov dl, bl
    mov bx, [hx_cursor_pos]
    mov al, [hx_sector_buf + bx]
    cmp byte [hx_hex_half], 0
    jne .low
    call hx_prepare_undo_snapshot_before_edit
    mov byte [hx_pending_hex_active], 1
    mov [hx_pending_hex_pos], bx
    mov [hx_pending_hex_old], al
    and al, 0x0F
    mov cl, dl
    shl cl, 4
    or al, cl
    mov [hx_sector_buf + bx], al
    mov byte [hx_hex_half], 1
    call hx_refresh_dirty_flag_from_disk_snapshot
    call hx_set_edit_message_by_dirty
    jmp .done
.low:
    and al, 0xF0
    or al, dl
    mov [hx_sector_buf + bx], al
    mov dl, al
    mov al, [hx_pending_hex_old]
    call hx_record_byte_change
    mov byte [hx_pending_hex_active], 0
    mov byte [hx_hex_half], 0
    call hx_refresh_dirty_flag_from_disk_snapshot
    call hx_set_edit_message_by_dirty
    cmp word [hx_cursor_pos], hx_BYTES_PER_SECTOR - 1
    jae .done
    inc word [hx_cursor_pos]
.done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

hx_ascii_hex_to_nibble:
    cmp al, '0'
    jb .check_upper
    cmp al, '9'
    jbe .digit
.check_upper:
    cmp al, 'A'
    jb .check_lower
    cmp al, 'F'
    jbe .upper
.check_lower:
    cmp al, 'a'
    jb .bad
    cmp al, 'f'
    ja .bad
    sub al, 'a' - 10
    clc
    ret
.digit:
    sub al, '0'
    clc
    ret
.upper:
    sub al, 'A' - 10
    clc
    ret
.bad:
    stc
    ret

hx_delay_100ms:
    push ax
    push cx
    push dx
    mov ah, 86h
    mov cx, 0001h
    mov dx, 86A0h
    int 15h
    pop dx
    pop cx
    pop ax
    ret

hx_speaker_init:
    push ax
    push bx
    in   al, 61h
    and  al, 0FDh
    or   al, 01h
    out  61h, al
    mov  al, 0B6h
    out  43h, al
    mov  bx, 1360
    mov  al, bl
    out  42h, al
    mov  al, bh
    out  42h, al
    in   al, 61h
    and  al, 0FCh
    out  61h, al
    pop  bx
    pop  ax
    ret

hx_beep:
    push ax
    in   al, 61h
    or   al, 03h
    out  61h, al
    call hx_delay_100ms
    in   al, 61h
    and  al, 0FDh
    or   al, 01h
    out  61h, al
    in   al, 61h
    and  al, 0FCh
    out  61h, al
    pop ax
    ret

hx_copy_asciiz:
    push ax
    cld
.copy:
    lodsb
    mov [di], al
    inc di
    test al, al
    jnz .copy
    pop ax
    ret

hx_strlen_z:
    push ax
    push si
    cld
    xor cx, cx
.loop:
    lodsb
    test al, al
    jz .done
    inc cx
    jmp .loop
.done:
    pop si
    pop ax
    ret

hx_clear_sector_buf:
    push ax
    push cx
    push di
    push es
    cld
    xor ax, ax
    mov es, ax
    mov di, hx_sector_buf
    xor ax, ax
    mov cx, hx_BYTES_PER_SECTOR / 2
    rep stosw
    pop es
    pop di
    pop cx
    pop ax
    ret

hx_draw_screen:
    push ds
    push es
    call hx_clear_screen
    call hx_draw_header
    call hx_refresh_sector_area
    pop es
    pop ds
    ret

hx_refresh_sector_area:
    call hx_mouse_hide_overlay
    call hx_draw_sector_view
    call hx_refresh_meta_ui
    call hx_mouse_show_overlay
    ret

hx_refresh_meta_ui:
    call hx_mouse_hide_overlay
    call hx_draw_message_line
    call hx_draw_status_line
    call hx_update_hw_cursor
    call hx_mouse_show_overlay
    ret

hx_refresh_after_cursor_change:
    push ax
    push bx
    call hx_mouse_hide_overlay
    mov bx, ax
    cmp bx, [hx_cursor_pos]
    jne .two_cells
    call hx_draw_byte_at_index
    jmp .meta
.two_cells:
    call hx_draw_byte_at_index
    mov bx, [hx_cursor_pos]
    call hx_draw_byte_at_index
.meta:
    call hx_refresh_meta_ui
    call hx_mouse_show_overlay
    pop bx
    pop ax
    ret

hx_draw_byte_at_index:
    push ax
    push bx
    push cx
    push dx
    push di

    mov di, bx
    mov ax, bx
    xor dx, dx
    mov cx, hx_BYTES_PER_ROW
    div cx

    mov dh, al
    add dh, hx_DATA_START_ROW
    mov cx, dx

    mov al, [hx_sector_buf + di]
    push bx
    mov bx, di
    call hx_get_byte_display_attr
    pop bx

    push ax
    mov bx, cx
    shl bx, 1
    add bx, cx
    mov dl, hx_HEX_COL
    add dl, bl
    call hx_print_hex_byte_at
    pop ax

    call hx_sanitize_ascii
    mov dl, hx_ASCII_COL
    add dl, cl
    call hx_put_char_at

    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

hx_clear_screen:
    push ax
    push cx
    push di
    push es
    cld
    mov ax, hx_VIDEO_SEG
    mov es, ax
    xor di, di
    mov ax, 0x0720
    mov cx, hx_SCREEN_COLS * hx_SCREEN_ROWS
    rep stosw
    pop es
    pop di
    pop cx
    pop ax
    ret

hx_draw_header:
    ; Never use ESP as a segment-zero scratch pointer here.  The integrated
    ; HEX stack is 8800:7FFE, while STOSB uses ES:EDI; the old implementation
    ; therefore copied the title into physical 7Fxxh and overwrote the live
    ; editor code.  Fill VGA row 0 directly, then render the selected title.
    push ax
    push bx
    push cx
    push dx
    push esi
    push di
    push es
    cld
    mov ax, hx_VIDEO_SEG
    mov es, ax
    xor di, di
    mov ax, 0x1E20
    mov cx, hx_SCREEN_COLS
    rep stosw
    mov esi, hx_str_header
    cmp byte [hx_memory_mode], 0
    je .print_header
    mov esi, hx_str_memory_header
.print_header:
    mov dh, 0
    mov dl, 0
    mov bl, 0x1E
    call hx_print_string_at
    pop es
    pop di
    pop esi
    pop dx
    pop cx
    pop bx
    pop ax
    ret

hx_draw_sector_view:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov byte [hx_row_idx], 0

.row_loop:
    mov al, [hx_row_idx]
    cmp al, hx_DATA_ROWS
    jae .done

    xor bx, bx
    mov bl, [hx_row_idx]
    shl bx, 4

    mov ax, bx
    mov dh, [hx_row_idx]
    add dh, hx_DATA_START_ROW
    xor dl, dl
    call hx_print_offset3_at

    mov dh, [hx_row_idx]
    add dh, hx_DATA_START_ROW
    mov dl, 3
    mov al, ':'
    mov ah, 0x07
    call hx_put_char_at

    mov dh, [hx_row_idx]
    add dh, hx_DATA_START_ROW
    mov dl, 54
    mov al, '|'
    mov ah, 0x08
    call hx_put_char_at

    xor cx, cx

.col_loop:
    cmp cx, hx_BYTES_PER_ROW
    jae .next_row

    mov di, bx
    add di, cx

    mov al, [hx_sector_buf + di]
    push bx
    mov bx, di
    call hx_get_byte_display_attr
    pop bx

    push ax
    mov dx, cx
    shl dx, 1
    add dx, cx
    add dl, hx_HEX_COL
    mov dh, [hx_row_idx]
    add dh, hx_DATA_START_ROW
    call hx_print_hex_byte_at
    pop ax

    call hx_sanitize_ascii
    mov dl, cl
    add dl, hx_ASCII_COL
    mov dh, [hx_row_idx]
    add dh, hx_DATA_START_ROW
    call hx_put_char_at

    inc cx
    jmp .col_loop

.next_row:
    inc byte [hx_row_idx]
    jmp .row_loop

.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

hx_sanitize_ascii:
    cmp al, 0x00
    je .dot
    ret
.dot:
    mov al, '.'
    ret

hx_draw_message_line:
    mov dh, hx_MESSAGE_ROW
    mov dl, 0
    mov bl, 0x0F
    mov si, hx_str_spaces80
    call hx_print_string_at
    mov dh, hx_MESSAGE_ROW
    mov dl, 0
    mov bl, 0x0F
    mov si, [hx_msg_ptr]
    test si, si
    jnz .print
    mov si, hx_str_blank
.print:
    call hx_print_string_at
    ret

hx_draw_status_line:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov dh, hx_STATUS_ROW
    mov dl, 0
    mov bl, 0xF0
    mov si, hx_str_spaces80
    call hx_print_string_at
    cmp byte [hx_memory_mode], 0
    je .disk_status
    mov eax, [hx_curr_lba_lo]
    mov edx, [hx_curr_lba_hi]
    shld edx, eax, 9
    shl eax, 9
    mov di, hx_memory_addr_buf
    call hx_u64_to_hex
    mov eax, [hx_memory_max_addr_lo]
    mov edx, [hx_memory_max_addr_hi]
    mov di, hx_memory_max_addr_buf
    call hx_u64_to_hex
    mov dh, hx_STATUS_ROW
    mov dl, 0
    mov bl, 0xF0
    mov si, hx_str_memory_status_prefix
    call hx_print_string_at
    mov dh, hx_STATUS_ROW
    mov dl, 6
    mov bl, 0xF0
    mov si, hx_memory_addr_buf
    call hx_print_string_at
    mov dh, hx_STATUS_ROW
    mov dl, 22
    mov bl, 0xF0
    mov si, hx_str_memory_status_suffix
    call hx_print_string_at
    mov dh, hx_STATUS_ROW
    mov dl, 25
    mov bl, 0xF0
    mov si, hx_memory_max_addr_buf
    call hx_print_string_at
    jmp .common_flags
.disk_status:
    mov eax, [hx_curr_lba_lo]
    mov [hx_conv_qword + 0], eax
    mov eax, [hx_curr_lba_hi]
    mov [hx_conv_qword + 4], eax
    mov si, hx_conv_qword
    call hx_u64_to_dec
    mov di, hx_curr_dec_buf
    call hx_copy_asciiz
    mov word [hx_curr_num_ptr], hx_curr_dec_buf
    mov eax, [hx_total_lba_lo]
    mov edx, [hx_total_lba_hi]
    mov [hx_conv_qword + 0], eax
    mov [hx_conv_qword + 4], edx
    or eax, edx
    jz .max_unknown
    mov eax, [hx_conv_qword + 0]
    mov edx, [hx_conv_qword + 4]
    sub eax, 1
    sbb edx, 0
    mov [hx_conv_qword + 0], eax
    mov [hx_conv_qword + 4], edx
    mov si, hx_conv_qword
    call hx_u64_to_dec
    mov di, hx_max_dec_buf
    call hx_copy_asciiz
    mov word [hx_max_num_ptr], hx_max_dec_buf
    jmp .max_done
.max_unknown:
    mov word [hx_max_num_ptr], hx_str_unknown
.max_done:
    mov dh, hx_STATUS_ROW
    mov dl, 0
    mov bl, 0xF0
    mov si, hx_str_status_prefix
    call hx_print_string_at
    mov dh, hx_STATUS_ROW
    mov dl, 4
    mov bl, 0xF0
    mov si, [hx_curr_num_ptr]
    call hx_print_string_at
    mov si, [hx_curr_num_ptr]
    call hx_strlen_z
    mov dh, hx_STATUS_ROW
    mov dl, 4
    add dl, cl
    mov bl, 0xF0
    mov si, hx_str_slash
    call hx_print_string_at
    inc dl
    mov dh, hx_STATUS_ROW
    mov bl, 0xF0
    mov si, [hx_max_num_ptr]
    call hx_print_string_at
    call hx_make_disk_dec_buf
    mov dh, hx_STATUS_ROW
    mov dl, 22
    mov bl, 0xF0
    mov si, hx_str_disk_prefix
    call hx_print_string_at

    mov dh, hx_STATUS_ROW
    mov dl, 28
    mov bl, 0xF0
    mov si, hx_disk_dec_buf
    call hx_print_string_at

.common_flags:
    mov dh, hx_STATUS_ROW
    mov dl, 34
    cmp byte [hx_memory_mode], 0
    je .dirty_col_ready
    mov dl, 42
.dirty_col_ready:
    mov bl, 0xF0
    cmp byte [hx_dirty_flag], 0
    je .clean
    mov si, hx_str_dirty_yes
    jmp .dirty_print
.clean:
    mov si, hx_str_dirty_no
.dirty_print:
    call hx_print_string_at
    mov dh, hx_STATUS_ROW
    mov dl, 48
    cmp byte [hx_memory_mode], 0
    je .mode_col_ready
    mov dl, 52
.mode_col_ready:
    mov bl, 0xF0
    cmp byte [hx_edit_mode], 0
    je .hex_mode
    mov si, hx_str_mode_ascii
    jmp .mode_print
.hex_mode:
    mov si, hx_str_mode_hex
.mode_print:
    call hx_print_string_at
    mov dh, hx_STATUS_ROW
    mov dl, 64
    mov bl, 0xF0
    mov si, hx_str_cursor_prefix
    call hx_print_string_at
    mov ax, [hx_cursor_pos]
    mov dh, hx_STATUS_ROW
    mov dl, 70
    call hx_print_offset3_at_status
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

hx_print_string_at:
    push ax
    push bx
    push cx
    push dx
    push di
    push es
    cld
    xor cx, cx
    mov cl, hx_SCREEN_COLS
    sub cl, dl
    mov ax, hx_VIDEO_SEG
    mov es, ax
    call hx_calc_vid_addr
.next:
    jcxz .done
    lodsb
    test al, al
    jz .done
    mov ah, bl
    stosw
    dec cx
    jmp .next
.done:
    pop es
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

hx_put_char_at:
    push bx
    push dx
    push di
    push es
    cld
    mov bx, ax
    mov ax, hx_VIDEO_SEG
    mov es, ax
    call hx_calc_vid_addr
    mov ax, bx
    stosw
    pop es
    pop di
    pop dx
    pop bx
    ret

hx_update_hw_cursor:
    push ax
    push bx
    push cx
    push dx
    mov ax, [hx_cursor_pos]
    xor dx, dx
    mov bx, hx_BYTES_PER_ROW
    div bx
    mov ch, al
    mov cl, dl
    mov dh, ch
    add dh, hx_DATA_START_ROW
    cmp byte [hx_edit_mode], 0
    jne .ascii_mode
    mov al, cl
    mov bl, 3
    mul bl
    add al, hx_HEX_COL
    add al, [hx_hex_half]
    mov dl, al
    jmp .set
.ascii_mode:
    mov dl, cl
    add dl, hx_ASCII_COL
.set:
    mov ah, 0x02
    xor bh, bh
    int 0x10
    pop dx
    pop cx
    pop bx
    pop ax
    ret

hx_calc_vid_addr:
    push ax
    push bx
    push cx
    xor cx, cx
    mov cl, dl
    shl cx, 1
    xor ax, ax
    mov al, dh
    mov bx, hx_SCREEN_COLS * 2
    mul bx
    add ax, cx
    mov di, ax
    pop cx
    pop bx
    pop ax
    ret

hx_print_offset3_at:
    push ax
    push bx
    push cx
    push dx
    mov bx, ax
    mov ax, bx
    mov cl, 8
    shr ax, cl
    and al, 0x0F
    call hx_nibble_to_ascii
    mov ah, 0x0B
    call hx_put_char_at
    mov ax, bx
    mov cl, 4
    shr ax, cl
    and al, 0x0F
    call hx_nibble_to_ascii
    mov ah, 0x0B
    inc dl
    call hx_put_char_at
    mov ax, bx
    and al, 0x0F
    call hx_nibble_to_ascii
    mov ah, 0x0B
    inc dl
    call hx_put_char_at
    pop dx
    pop cx
    pop bx
    pop ax
    ret

hx_print_offset3_at_status:
    push ax
    push bx
    push cx
    push dx
    mov bx, ax
    mov ax, bx
    mov cl, 8
    shr ax, cl
    and al, 0x0F
    call hx_nibble_to_ascii
    mov ah, 0xF0
    call hx_put_char_at
    mov ax, bx
    mov cl, 4
    shr ax, cl
    and al, 0x0F
    call hx_nibble_to_ascii
    mov ah, 0xF0
    inc dl
    call hx_put_char_at
    mov ax, bx
    and al, 0x0F
    call hx_nibble_to_ascii
    mov ah, 0xF0
    inc dl
    call hx_put_char_at
    pop dx
    pop cx
    pop bx
    pop ax
    ret

hx_print_hex_byte_at:
    push ax
    push bx
    push dx
    mov bl, ah
    mov bh, al
    mov al, bh
    shr al, 4
    and al, 0x0F
    call hx_nibble_to_ascii
    mov ah, bl
    call hx_put_char_at
    mov al, bh
    and al, 0x0F
    call hx_nibble_to_ascii
    mov ah, bl
    inc dl
    call hx_put_char_at
    mov al, ' '
    mov ah, 0x07
    inc dl
    call hx_put_char_at
    pop dx
    pop bx
    pop ax
    ret

hx_nibble_to_ascii:
    cmp al, 9
    jbe .digit
    add al, 'A' - 10
    ret
.digit:
    add al, '0'
    ret

hx_u64_to_hex:
    ; EDX:EAX=value, DS:DI receives 16 uppercase hex digits and a zero.
    push eax
    push ebx
    push ecx
    push edx
    push bp
    mov ebx, eax
    mov ecx, edx
    mov bp, 16
.loop:
    mov eax, ecx
    shr eax, 28
    and al, 0x0F
    call hx_nibble_to_ascii
    mov [di], al
    inc di
    shld ecx, ebx, 4
    shl ebx, 4
    dec bp
    jnz .loop
    mov byte [di], 0
    pop bp
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

hx_u64_to_dec:
    push ax
    push bx
    push cx
    push dx
    push di
    mov eax, [si + 0]
    mov [hx_conv_tmp + 0], eax
    mov eax, [si + 4]
    mov [hx_conv_tmp + 4], eax
    mov di, hx_dec_buf + 20
    mov byte [di], 0
    dec di
    mov eax, [hx_conv_tmp + 0]
    mov edx, [hx_conv_tmp + 4]
    or eax, edx
    jnz .loop
    mov byte [di], '0'
    mov si, di
    jmp .done
.loop:
    call hx_div_conv_tmp_by_10
    add dl, '0'
    mov [di], dl
    dec di
    mov eax, [hx_conv_tmp + 0]
    mov edx, [hx_conv_tmp + 4]
    or eax, edx
    jnz .loop
    inc di
    mov si, di
.done:
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

hx_update_find_progress:
    pushad
    mov ax, [0x046C]
    mov dx, ax
    sub ax, [hx_find_progress_last_tick]
    cmp ax, 4                    ; 4 BIOS ticks ~= 220 ms (200 ms target)
    jb .done
    mov [hx_find_progress_last_tick], dx
    mov ecx, [hx_total_lba_lo]
    mov ebx, [hx_total_lba_hi]
    mov eax, ecx
    or eax, ebx
    jz .no_total
    mov eax, [hx_search_lba_lo]
    mov edx, [hx_search_lba_hi]
    cmp edx, [hx_curr_lba_hi]
    ja .forward_phase
    jb .wrap_phase
    cmp eax, [hx_curr_lba_lo]
    jbe .wrap_phase
.forward_phase:
    sub eax, [hx_curr_lba_lo]
    sbb edx, [hx_curr_lba_hi]
    sub eax, 1
    sbb edx, 0
    jmp .scale_percent
.wrap_phase:
    add eax, ecx
    adc edx, ebx
    sub eax, [hx_curr_lba_lo]
    sbb edx, [hx_curr_lba_hi]
    sub eax, 1
    sbb edx, 0
.scale_percent:
    ; Scale both 64-bit operands together until the denominator fits 32 bits.
    ; This keeps percentage calculation valid even above 2 TiB of memory.
    test ebx, ebx
    jz .calc_percent
    shrd ecx, ebx, 1
    shr ebx, 1
    shrd eax, edx, 1
    shr edx, 1
    jmp .scale_percent
.calc_percent:
    mov ebx, 100
    mul ebx
    div ecx
    cmp eax, 100
    jbe .percent_ready
    mov eax, 100
.percent_ready:
    mov bx, ax
    jmp .build
.no_total:
    mov bx, 0xFFFF
.build:
    mov di, hx_find_progress_buf
    mov si, hx_msg_finding
.copy1:
    lodsb
    stosb
    cmp al, 0
    jne .copy1
    dec di
    cmp bx, 0xFFFF
    je .percent_question
    movzx eax, bx
    mov [hx_conv_qword], eax
    mov dword [hx_conv_qword+4], 0
    mov si, hx_conv_qword
    call hx_u64_to_dec
    jmp .copy2
.percent_question:
    mov al, '?'
    stosb
    jmp .add_percent_symbol
.copy2:
    lodsb
    stosb
    cmp al, 0
    jne .copy2
    dec di
.add_percent_symbol:
    mov al, '%'
    stosb
    mov al, ' '
    stosb
    cmp byte [hx_memory_mode], 0
    je .disk_position
    mov al, '0'
    stosb
    mov al, 'x'
    stosb
    mov eax, [hx_search_lba_lo]
    mov edx, [hx_search_lba_hi]
    shld edx, eax, 9
    shl eax, 9
    push di
    mov di, hx_memory_addr_buf
    call hx_u64_to_hex
    mov si, hx_memory_addr_buf
    pop di
.copy_memory_current:
    lodsb
    stosb
    test al, al
    jnz .copy_memory_current
    dec di
    mov al, '/'
    stosb
    mov al, '0'
    stosb
    mov al, 'x'
    stosb
    mov eax, [hx_memory_max_addr_lo]
    mov edx, [hx_memory_max_addr_hi]
    push di
    mov di, hx_memory_max_addr_buf
    call hx_u64_to_hex
    mov si, hx_memory_max_addr_buf
    pop di
.copy_memory_max:
    lodsb
    stosb
    test al, al
    jnz .copy_memory_max
    jmp short .publish
.disk_position:
    mov eax, [hx_search_lba_lo]
    mov [hx_conv_qword], eax
    mov eax, [hx_search_lba_hi]
    mov [hx_conv_qword+4], eax
    mov si, hx_conv_qword
    call hx_u64_to_dec
.copy3:
    lodsb
    stosb
    cmp al, 0
    jne .copy3
    dec di
    mov al, '/'
    stosb
    mov eax, [hx_total_lba_lo]
    mov [hx_conv_qword], eax
    mov eax, [hx_total_lba_hi]
    mov [hx_conv_qword+4], eax
    mov si, hx_conv_qword
    call hx_u64_to_dec
.copy4:
    lodsb
    stosb
    cmp al, 0
    jne .copy4
.publish:
    mov word [hx_msg_ptr], hx_find_progress_buf
    call hx_refresh_meta_ui
.done:
    popad
    ret

hx_div_conv_tmp_by_10:
    push ax
    push bx
    push cx
    push si
    mov ecx, 10
    xor edx, edx
    mov eax, [hx_conv_tmp + 4]
    div ecx
    mov [hx_conv_tmp + 4], eax
    mov eax, [hx_conv_tmp + 0]
    div ecx
    mov [hx_conv_tmp + 0], eax
    pop si
    pop cx
    pop bx
    pop ax
    ret

hx_str_header             db 'Disk Sector Editor - Press F1 for help', 0
hx_str_memory_header      db 'Physical Memory Editor - Press F1 for help', 0

hx_str_help_disk:
    db 'Disk Sector Hex Editor Help:',0x0D,0x0A,0x0D,0x0A
    db 'Press "-" to go to the previous sector  Press "=" to go to the next sector',0x0D,0x0A
    db 'Arrows: Move Cursor  Shift+Arrows: Multi-Select  Tab: Change Mode',0x0D,0x0A
    db 'Ctrl+G: Jump  Ctrl+F: Find  F3: Find Next  F4: Next Disk  F5: Reload',0x0D,0x0A
    db 'Ctrl+C: Copy  Ctrl+V: Paste  Ctrl+X: Cut  Ctrl+A: Select All  Ctrl+S: Save',0x0D,0x0A
    db 'Ctrl+Z: Undo  Ctrl+Shift+Z/Ctrl+Y: Redo  Ctrl+Q: Clear Sector',0x0D,0x0A
    db 'Ctrl+Backspace: Fill the selected bytes with 0x00',0x0D,0x0A
    db 'ESC: Return to DOS  Shift+ESC: Force Return to DOS  Ctrl+ESC: Force Hard Reboot',0x0D,0x0A
    db 'Mouse Wheel: Change Sector  Drag: Multi-Select',0x0D,0x0A,0x0D,0x0A
    db 'Press any key to continue...',0

hx_str_help_memory:
    db 'Physical Memory Hex Editor Help:',0x0D,0x0A,0x0D,0x0A
    db 'Press "-" for the previous 512-byte page  Press "=" for the next page',0x0D,0x0A
    db 'Arrows: Move Cursor  Shift+Arrows: Multi-Select  Tab: Change Mode',0x0D,0x0A
    db 'Ctrl+G: Jump to Address  Ctrl+F: Find  F3: Find Next  F5: Reload',0x0D,0x0A
    db 'Ctrl+C: Copy  Ctrl+V: Paste  Ctrl+X: Cut  Ctrl+A: Select All  Ctrl+S: Write',0x0D,0x0A
    db 'Ctrl+Z: Undo  Ctrl+Shift+Z/Ctrl+Y: Redo  Ctrl+Q: Clear Page',0x0D,0x0A
    db 'Ctrl+Backspace: Fill the selected bytes with 0x00',0x0D,0x0A
    db 'ESC: Return to DOS  Shift+ESC: Force Return to DOS  Ctrl+ESC: Force Hard Reboot',0x0D,0x0A
    db 'Mouse Wheel: Change Memory Page  Drag: Multi-Select',0x0D,0x0A,0x0D,0x0A
    db 'Press any key to continue...',0

hx_str_status_prefix      db 'LBA:', 0
hx_str_memory_status_prefix db 'MEM:0x', 0
hx_str_memory_status_suffix db '/0x', 0
hx_str_disk_prefix        db ' disk:', 0
hx_str_slash              db '/', 0
hx_str_mode_hex           db 'mode:HEX ', 0
hx_str_mode_ascii         db 'mode:ASCII', 0
hx_str_cursor_prefix      db 'cur:0x', 0
hx_str_unknown            db '?', 0
hx_str_dirty_yes          db 'dirty:*', 0
hx_str_dirty_no           db 'dirty:-', 0
hx_str_blank              db 0
hx_str_spaces80           db '                                                                                ', 0
hx_str_jump_prompt        db 'Jump to LBA: ', 0
hx_str_jump_prompt_memory db 'MEM address: ', 0
hx_str_jump_help          db 'Left/Right=Move  Enter=Go  Esc=Cancel  Backspace=Delete', 0
hx_str_jump_help_memory   db 'Hex address, up to 16 digits  Enter=Go  Esc=Cancel  Backspace=Delete', 0
hx_str_save_prompt        db 'Save to Disk?', 0
hx_str_save_help          db 'Y=Save  N=Discard  ESC=Cancel', 0
hx_str_save_prompt_memory db 'Write edits to physical memory?', 0
hx_str_save_help_memory   db 'Y=Write  N=Discard  ESC=Cancel', 0
hx_str_save_prompt_reboot db 'Save current sector before returning to DOS?', 0
hx_str_save_help_reboot   db 'Y=Save and return  N=Return without saving  ESC=Cancel', 0
hx_str_save_prompt_memory_reboot db 'Write current memory page before returning to DOS?', 0
hx_str_save_help_memory_reboot db 'Y=Write and return  N=Return without writing  ESC=Cancel', 0
hx_str_clear_prompt       db 'Clear this sector and save it?', 0
hx_str_clear_help         db 'Y=Clear  N=No  ESC=Cancel', 0
hx_str_clear_prompt_memory db 'Zero this 512-byte memory page and write it?', 0
hx_str_clear_help_memory  db 'Y=Zero and write  N=No  ESC=Cancel', 0
hx_str_find_mode_prompt   db 'Find mode:', 0
hx_str_find_mode_help     db '1=HEX  2=ASCII  ESC=Cancel', 0
hx_str_find_hex_prompt    db 'Find HEX: ', 0
hx_str_find_ascii_prompt  db 'Find ASCII: ', 0
hx_str_find_hex_help      db 'Hex digits only. Enter=Find  Esc=Cancel  Backspace=Delete', 0
hx_str_find_ascii_help    db 'Printable chars. Enter=Find  Esc=Cancel  Backspace=Delete', 0
hx_str_loaded_lba_prefix  db 'Loaded LBA ', 0
hx_str_loaded_lba_suffix  db ' into the RAM (512 bytes)', 0
hx_str_loaded_memory_prefix db 'Loaded memory page 0x', 0
hx_str_loaded_memory_suffix db ' (512 bytes)', 0

hx_msg_ram_dirty          db 'Sector buffer changed in RAM. Press Ctrl+S to save this sector', 0
hx_msg_memory_dirty       db 'Memory page edited. Press Ctrl+S to write it to physical memory', 0
hx_msg_saved_ok           db 'Saved the current sector to disk', 0
hx_msg_memory_saved_ok    db 'Wrote the current 512-byte page to physical memory', 0
hx_msg_save_failed        db 'Failed to save the current sector to disk', 0
hx_msg_memory_save_failed db 'Failed to write the current page to physical memory', 0
hx_msg_no_changes         db 'No unsaved changes for the current sector', 0
hx_msg_memory_no_changes  db 'No unwritten changes for the current memory page', 0
hx_msg_nothing_to_undo    db 'Nothing left to undo in this 512-byte page', 0
hx_msg_nothing_to_redo    db 'Nothing left to redo in this 512-byte page', 0
hx_msg_undo_done          db 'Reverted the most recently edited byte', 0
hx_msg_redo_done          db 'Restored the most recently undone byte', 0
hx_msg_mode_switched      db 'Mode switched. HEX accepts 0-9/A-F; ASCII accepts printable characters', 0
hx_msg_read_failed        db 'Failed to read the requested disk sector or memory page', 0
hx_msg_total_unknown      db 'Could not query total sector count. Navigation still works until BIOS read fails', 0
hx_msg_total_chs          db 'EDD sector count unavailable; using CHS geometry limit', 0
hx_msg_drive_switched     db 'Switched to next BIOS hard disk', 0
hx_msg_drive_single       db 'Only one BIOS hard disk is available', 0
hx_msg_drive_memory_mode  db 'F4 disk switching is unavailable in HEX -MEM mode', 0
hx_msg_drive_read_failed  db 'Switched drive, but reading LBA 0 failed', 0
hx_msg_jump_done          db 'Jumped to the requested LBA', 0
hx_msg_memory_jump_done   db 'Jumped to the 512-byte page containing that memory address', 0
hx_msg_memory_address_invalid db 'Address exceeds the CPU physical-address width', 0
hx_msg_jump_cancel        db 'Jump canceled', 0
hx_msg_switch_cancel      db 'Page change canceled', 0
hx_msg_clear_cancel       db 'Clear page canceled', 0
hx_msg_cleared_saved_ok   db 'Cleared and saved the current sector', 0
hx_msg_memory_cleared_saved_ok db 'Zeroed and wrote the current memory page', 0
hx_msg_clear_undo_done    db 'Restored this sector in RAM. Press Ctrl+S to write it back to disk', 0
hx_msg_clear_redo_done    db 'Reapplied the cleared sector in RAM. Press Ctrl+S to write it back to disk', 0
hx_msg_memory_clear_undo_done db 'Restored this memory page. Press Ctrl+S to write it to memory', 0
hx_msg_memory_clear_redo_done db 'Reapplied the zeroed page. Press Ctrl+S to write it to memory', 0
hx_msg_copied_single      db 'Copied the current byte to the clipboard', 0
hx_msg_copied_multi       db 'Copied the selected bytes to the clipboard', 0
hx_msg_clipboard_empty    db 'Clipboard is empty', 0
hx_msg_paste_no_change    db 'Paste made no changes to the current page', 0
hx_msg_pasted_ok          db 'Pasted clipboard data into the current page', 0
hx_msg_finding            db 'Finding... ',0
hx_msg_find_cancel        db 'Find canceled', 0
hx_msg_find_empty         db 'Find text is empty after filtering', 0
hx_msg_find_no_previous   db 'There is no previous find pattern. Press Ctrl+F first', 0
hx_msg_find_not_found     db 'Pattern not found from the current sector through the entire disk', 0
hx_msg_memory_find_not_found db 'Pattern not found from this page through physical memory', 0
hx_msg_memory_flat_ready  db 'A20 is enabled; the BIOS block move function is available only for addresses below 4 GiB (up to 0xFFFFFFFF)', 0
hx_msg_memory_pae_unavailable db 'PAE is unavailable; this CPU cannot access physical memory above 0xFFFFFFFF', 0
hx_msg_memory_a20_transfer_failed db 'A20 could not be re-enabled before the high-memory transfer', 0
hx_msg_memory_bios87_failed db 'BIOS INT 15h/87h rejected this physical-memory transfer', 0
hx_msg_memory_pae_fault   db 'PAE exception 0x'
hx_msg_memory_pae_fault_vector db '00'
                           db ' CR2=0x'
hx_msg_memory_pae_fault_cr2 db '00000000'
                           db ' step=0x'
hx_msg_memory_pae_fault_step db '00', 0
hx_msg_memory_e820_failed db 'E820 memory map unavailable; using the first 1 MiB only', 0
hx_msg_memory_a20_failed  db 'A20 could not be enabled; using the first 1 MiB only', 0
hx_msg_find_found_single  db 'Found a matching byte/character', 0
hx_msg_find_found_multi   db 'Found a matching range', 0
hx_msg_cut_done           db 'Cut selection and cleared to zeros', 0
hx_msg_selection_zeroed   db 'Selected bytes were filled with 0x00', 0

align 4, db 0
hx_edd_params:
    times 0x1E db 0

align 4, db 0
hx_dap_read:
    times 16 db 0

align 4, db 0
hx_dap_write:
    times 16 db 0

align 4, db 0
hx_dap_search:
    times 16 db 0

align 4, db 0
hx_sector_buf:
    times hx_BYTES_PER_SECTOR db 0

align 4, db 0
hx_undo_sector_buf:
    times hx_BYTES_PER_SECTOR db 0

align 4, db 0
hx_disk_sector_buf:
    times hx_BYTES_PER_SECTOR db 0

align 4, db 0
hx_search_sector_buf:
    times hx_BYTES_PER_SECTOR db 0

align 4, db 0
hx_conv_qword:
    dq 0
hx_conv_tmp:
    dq 0
hx_parse_tmp_lo:
    dd 0
hx_parse_tmp_hi:
    dd 0

hx_curr_lba_lo      dd 0
hx_curr_lba_hi      dd 0
hx_total_lba_lo     dd 0
hx_total_lba_hi     dd 0
hx_saved_lba_lo     dd 0
hx_saved_lba_hi     dd 0
hx_jump_value_lo    dd 0
hx_jump_value_hi    dd 0
hx_search_lba_lo    dd 0
hx_search_lba_hi    dd 0
hx_find_hit_lba_lo  dd 0
hx_find_hit_lba_hi  dd 0

hx_curr_num_ptr             dw 0
hx_max_num_ptr              dw 0
hx_dialog_line1_ptr         dw 0
hx_dialog_line2_ptr         dw 0
hx_cursor_pos               dw 0
hx_old_cursor_pos           dw 0
hx_selection_anchor         dw 0
hx_msg_ptr                  dw 0
hx_pending_hex_pos          dw 0
hx_clipboard_len            dw 0
hx_undo_count               dw 0
hx_redo_count               dw 0
hx_undo_action_count        dw 0
hx_redo_action_count        dw 0
hx_find_pattern_len         dw 0
hx_find_last_start          dw 0
hx_find_origin_index        dw 0
hx_find_tail_start          dw 0
hx_jump_byte_offset         dw 0
hx_find_progress_last_tick  dw 0

hx_edit_mode                db 0
hx_hex_half                 db 0
hx_row_idx                  db 0
hx_dirty_flag               db 0
hx_critical_write_active    db 0
hx_critical_saved_cmos      db 0
hx_shift_prev               db 0
hx_clear_undo_available     db 0
hx_clear_redo_available     db 0
hx_preserve_undo_after_save db 0
hx_rebase_undo_on_next_edit db 0
hx_selection_active         db 0
hx_jump_len                 db 0
hx_jump_cursor              db 0
hx_pending_hex_active       db 0
hx_pending_hex_old          db 0
hx_find_mode                db 0
hx_find_input_len           db 0
hx_find_input_cursor        db 0
hx_last_find_valid          db 0
hx_kbd_pending_valid        db 0
hx_search_cancelled_flag    db 0
hx_search_cancel_budget     db 0
hx_mouse_mode               db 0
hx_mouse_col                db 0
hx_mouse_row                db 0
hx_mouse_prev_col           db 0
hx_mouse_prev_row           db 0
hx_mouse_overlay_visible    db 0
hx_mouse_buttons            db 0
hx_mouse_prev_buttons       db 0
hx_mouse_drag_active        db 0
hx_mouse_drag_moved         db 0
hx_mouse_ps2_packet_size    db 0
hx_mouse_ps2_pktcnt         db 0
hx_mouse_wheel_delta        db 0
hx_mouse_hit_mode           db 0
hx_mouse_hit_half           db 0

hx_memory_mode              db 0
hx_memory_backend           db 0
hx_pae_available            db 0
hx_efer_available           db 0
hx_phys_addr_bits           db 36
hx_memory_fail_reason       db 0
hx_disk_io_mode             db 0
hx_edd_available            db 0
hx_chs_available            db 0
hx_chs_spt                  db 0
hx_chs_heads                db 0
hx_disk_chs_cmd             db 0
hx_hdd_count                db 1
hx_current_hdd_index        db 0
align 2, db 0
hx_chs_cylinders            dw 0

align 4, db 0
hx_memory_end_lo            dd 0
hx_memory_end_hi            dd 0
hx_memory_size_lo           dd 0
hx_memory_size_hi           dd 0
hx_memory_max_addr_lo       dd 0
hx_memory_max_addr_hi       dd 0
hx_e820_cont                dd 0
hx_e820_guard               dw 0
hx_e820_entry:
    times 24 db 0

hx_pm_phys_lo               dd 0
hx_pm_phys_hi               dd 0
hx_pm_page_offset           dd 0
hx_pm_buffer                dd 0
hx_pm_operation             db 0
hx_bios87_status            db 0
hx_bios87_failed            db 0
hx_pm_saved_cmos            db 0
hx_pm_faulted               db 0
hx_pm_efer_touched          db 0
hx_pm_checkpoint            db 0
hx_pm_fault_vector          db 0xFF
align 4, db 0
hx_pm_fault_cr2             dd 0
align 16, db 0
hx_bios87_gdt:
    times 0x30 db 0
align 2, db 0
hx_pm_saved_ss              dw 0
hx_pm_saved_sp              dw 0
align 4, db 0
hx_pm_saved_cr0             dd 0
hx_pm_saved_cr3             dd 0
hx_pm_saved_cr4             dd 0
hx_pm_saved_efer_lo         dd 0
hx_pm_saved_efer_hi         dd 0
hx_pm_saved_gdtr:
    times 6 db 0
hx_pm_saved_idtr:
    times 6 db 0

align 8, db 0
hx_pm_gdt:
    dq 0
    dw 0xFFFF, 0x0000
    db 0x00, 0x9A, 0xCF, 0x00
    dw 0xFFFF, 0x0000
    db 0x00, 0x92, 0xCF, 0x00
    ; 64-bit code, then flat 16-bit code for the protected-mode exit.
    dw 0x0000, 0x0000
    db 0x00, 0x9A, 0x20, 0x00
    dw 0xFFFF, 0x0000
    db 0x00, 0x9A, 0x00, 0x00
    ; Flat 16-bit data/stack (D/B=0).  Loading SS with this descriptor before
    ; clearing PE prevents a "big real-mode" stack cache from escaping.
    dw 0xFFFF, 0x0000
    db 0x00, 0x92, 0x00, 0x00
    ; Reserved descriptors retained for the independent Long Mode debug tool.
    dq 0, 0
hx_pm_gdt_end:
hx_pm_gdtr:
    dw hx_pm_gdt_end - hx_pm_gdt - 1
    dd hx_pm_gdt

hx_pm_idtr32:
    dw (32 * 8) - 1
    dd hx_PM_IDT32_PHYS

hx_lm_idtr64:
    dw (32 * 16) - 1
    dq hx_LM_IDT64_PHYS

align 4, db 0
hx_pm_tss:
    times 104 db 0

align 2, db 0
hx_mouse_hit_index          dw 0
hx_mouse_saved_cell         dw 0
hx_mouse_vm_tmp_x           dw 0
hx_mouse_vm_tmp_y           dw 0
hx_mouse_vm_tmp_z           dw 0
hx_mouse_ps2_acc_x          dw 0
hx_mouse_ps2_acc_y          dw 0
hx_mouse_ps2_pkt            times 4 db 0
hx_find_progress_buf        times 80 db 0
align 2, db 0
hx_kbd_pending_ax           dw 0
hx_dec_buf:
    times 21 db 0
hx_curr_dec_buf:
    times 21 db 0
hx_max_dec_buf:
    times 21 db 0
hx_disk_dec_buf:
    times 21 db 0
hx_memory_addr_buf:
    times 17 db 0
hx_memory_max_addr_buf:
    times 17 db 0
hx_jump_buf:
    times 21 db 0
hx_find_input_buf:
    times (hx_FIND_TEXT_MAX + 1) db 0
hx_find_pattern_buf:
    times hx_FIND_TEXT_MAX db 0
hx_clipboard_buf:
    times hx_BYTES_PER_SECTOR db 0
hx_loaded_lba_msg_buf:
    times 80 db 0

align 2, db 0
hx_undo_pos_stack:
    times hx_HISTORY_MAX dw 0
hx_undo_old_stack:
    times hx_HISTORY_MAX db 0
hx_undo_new_stack:
    times hx_HISTORY_MAX db 0
hx_undo_action_sizes:
    times hx_HISTORY_MAX dw 0

align 2, db 0
hx_redo_pos_stack:
    times hx_HISTORY_MAX dw 0
hx_redo_old_stack:
    times hx_HISTORY_MAX db 0
hx_redo_new_stack:
    times hx_HISTORY_MAX db 0
hx_redo_action_sizes:
    times hx_HISTORY_MAX dw 0
times (HEX_EDITOR_SECTORS * 512) - ($ - $$) db 0
align 512, db 0
db ' All Characters '
%assign hx_i 0
%rep 0x100
    db hx_i
    %assign hx_i hx_i + 1
%endrep
align 512, db 0
