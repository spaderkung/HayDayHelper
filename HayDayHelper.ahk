; ------------------------------------------------------------------------------------------------
; General ahk help
;
; %var% is used only when a legacy ahk function is used
;
; Escape character is angled apostrophe `
; Seconds and milliseconds is not consistent:
;   ms: SetTimer
;    s: MsgBox timeout 
; Arrays are index 1-based
;
; An expression can be used in a parameter that does not directly support it 
;  (except OutputVar parameters) by preceding the expression with a percent sign and a space or tab
;
;   x := coord[1]
;   y := coord[2]
;   MouseMove, x, y
;
; Variables under Function: knows if it's global.
; Variables under Function() {} requires declaration inside function as global var, then the global will be used.
;
; MsgBox given a concat msg must format decimal points (example 2 places):
;  Format("{:.2f}", var)
; ------------------------------------------------------------------------------------------------

; ------------------------------------------------------------------------------------------------
; General VS Code help
;
; ctrl+k+0  - Collapse all
; ctrl+k+c  - Comment lines
; ctrl+k+u  - Uncomment lines
; ------------------------------------------------------------------------------------------------

; ------------------------------------------------------------------------------------------------
; Script info
; Uses by default an LD Player window found.
;
; For auto farming it is required the window be 1080 px wide.
;
; Hotkeys:
;  ctrl+shift+s     - Sells all available corn. Must be in shop when started.
;  ctrl+shift+m     - Snipes a friend. Must be in home when started.
;                   - Auto farming. No items are gained once barn inventory is full.
; ------------------------------------------------------------------------------------------------

; ------------------------------------------------------------------------------------------------
;Script settings
#SingleInstance, force      ; When starting script any old running instance is closed.

; Probably want active window at some point, but if using text boxes then
;  all coords are messed up if active window.
CoordMode, Pixel, Screen
CoordMode, Mouse, Screen

#Include, GeneralFunctions.ahk
; ------------------------------------------------------------------------------------------------


; ------------------------------------------------------------------------------------------------
; Global for program control
FORCE_FARM_OR_SNIPE := 1

tempTxt := ""

TICK_TIME_MS := 200         ; Program scan time
PROGRAM_START_TIME := A_Now

active := false

timerTicks := 0
tempTime := A_Now       
nextRunTimeForAdvert := tempTime
nextRunTimeForFarming := tempTime        ; System time to start next cycle (a blocking time)

lockedInSnipeMode := false  ; When sniping, do not allow for mode change when a snipe is close.

MODE_NONE               := 0
MODE_IDLE               := 1
MODE_SNIPING            := 2
MODE_CREATE_ADVERT      := 3
MODE_FARMING            := 4

ModeName_ToString(mode) {
    if (mode = 1) {
        return "MODE_IDLE"
    }
    else if (mode = 2) {
        return "MODE_SNIPING"
    }
    else if (mode = 3) {
        return "MODE_CREATE_ADVERT"
    }
    else if (mode = 4) {
        return "MODE_FARMING"
    }
    else {
        return "MODE_NONE"
    }
}

mode := MODE_NONE
mode_old := MODE_NONE
; ------------------------------------------------------------------------------------------------


; ------------------------------------------------------------------------------------------------
; Shop enumerations - NOTE - must be copied and made global into the Detect function.
ITEM_ID_SOYBEAN     := 1
ITEM_ID_SUGARCCANE  := 2
ITEM_ID_WHEAT       := 3
ITEM_ID_CARROT      := 4
ITEM_ID_CORN        := 5
ITEM_ID_COTTON      := 6
ITEM_ID_CHILI       := 7
ITEM_ID_LAVENDER    := 8
ITEM_ID_TOMATO      := 9
ITEM_ID_PUMPKIN     := 10
;
;
ITEM_ID_STRAWBERRY  := 13
;
ITEM_ID_POTATO      := 15

; Tools Id
ITEM_ID_SAW     := 101
ITEM_ID_AXE     := 102
;
ItemId_ToString(s) {
    if (s = 1) 
        return "ITEM_ID_CORN"
    if (s = 2) 
        return "ITEM_ID_CARROT"
    if (s = 101) 
        return "ITEM_ID_SAW"
    if (s = 102) 
        return "ITEM_ID_AXE"

    return "INVALID"
}

; Other shop eneumerations
PRICE_MAX   := 0
PRICE_MIN   := 1
; ------------------------------------------------------------------------------------------------


; ------------------------------------------------------------------------------------------------
; Global for sniping - user settings.
SNIPE_INTERVAL_TIME_S := 1      ; After a snipe is done, then resume sniping after this time.
SNIPE_TIMEOUT_TIME_S  := 0      ; Future: If a snipe was not done in this time, exit snipe mode.
MAX_SNIPING_RETRIES := 5        ; Times for all sessions the snipe mode can recover from lost screen.  
snipeCyclesDone := 0            ; Times waited at the trigger
snipesDone := 0                 ; Times triggered

; In the cycle list a friend appears twice if there are two snipe slots to possibly alternate.
friendCycleListIndex := 12
friendCycleList := [[5, 1], [6, 15], [7, 2], [7, 12], [8, 2], [8, 12], [10, 1], [11, 2], [12, 2], [13, 2], [15, 12], [14, 2]]

friendCycleListIndex := 1
friendCycleList := [ [12, 2], [13, 2], [8, 1], [5, 13] ]
frienCycleListSize := 2 ; XXX Automatic
cycleFriendsAfterSnipe := true

; Friends and slots will both change independently, as friend can remove any followers.
;                   Special item   
; Friend         Index   Slot    Price   Goods
; Greg           1
; FB             2
; Google         3
; Malin          4       1               Carrot
; 089            5       13-16   Full     Wheat  <-- Dvs kolla alla 13-16
; 29034          6       2,12       1      Corn->Carrot
; 29036          7       2,12       1      Corn->Carrot
; 55             8       1       Full    Carrot
; Vega           9      
; z278          10       2          ?      Corn     
; haru369       11       2                 Corn    
; 15            12       2, 12?     ?      Corn
; X             13       2          1      Corn
; ceres01       14       2, 12      ?      Corn Säljer utrensning på slot 21, men ej scrollbart dit.
; ceres08       15       2, 12   Full      Corn Säljer utrensning på slot 21, men ej scrollbart dit.
; map           16       
; piggy         17
; ------------------------------------------------------------------------------------------------

; ------------------------------------------------------------------------------------------------
; Global for farming - user settings.

; There is a field sized grid for the playing field with grid 1,1 as much left as it goes to the river,
;  which is the "top" before the view gets its rotated view.
;
; Columns increase along the river towards the cliff.
; Rows increase along the road in direction to shop.
;
; Some grid coordinaes:
;  [ 1, 1]       : As far screen left and towards the river that is plantable.
;  [ 1, 18-19]   : Unplantable river boat pier/stones. As far towards the river that is plantable.
;  [ 1, 32]      : As far towards the river and towards the cliff that is plantable.
;  [16, 1]       : Grass opposite road to mailbox. 
;  [17-19, 1-14] : Road towards mansion. 
RC_PLANT_NEXT_TO_BOARD := [16, 11]     ; Plantable area next to order board towarsd shop.
RC_PLANT_RIGHT_OF_MANSION := [20, 18]  ; Plantable area right of mansion. Back.


;  Unplantable areas of interest.
RC_ORDERS  := [16, 12]  ;[16, 12-13]   : Order board. (Row 15 is unplantable too, but row 16 can be used for selection.)
RC_MANSION := [17, 16]  ;[16-19, 15-18]   : Mansion.
RC_MINE    := [21, 34]  ;[20-21, 34]   : Mine
RC_FISHING := [-1, 14]
RC_SHOP    := [14, -1]
RC_MAILBOX := [20, -1]
RC_GIFTBOX := [22, -1]
RC_HELPERS := [23, 40]
RC_DERBY   := [16, -6]
RC_EVENTS  := [11, -2]

; It is recommended to configure some "safe areas" for clicking. Otherwise any area may be clicked
;  after dragging because Mouse Up sometimes triggers a click. If safe areas are configured then 
;  these will always be clicked when dragging the screen.
RC_SAFE_AREAS := [[0, 0], [0, 0]]

; Configure a field area to use for harvest & plant. The first selected grid can be anywhere. Dragging
;  will start here, then go to the top left grid, then swipe all grids until the lower right.
; Top Left / Lower right are RELATIVE to the selected field and must be reachable on the current screen.
RC_FIELD_AREA_SELECT          := [10 ,8]   ; The grid to click and use to select harvest / plant. Can be anywhere.
RC_FIELD_AREA_REL_TOP_LEFT    := [-7, -7]  ; Top left grid to drag for harvest/plant, relative to selected field. Must be on same screen as selected grid.
RC_FIELD_AREA_REL_LOWER_RIGHT := [0, 0]    ; Lower right grid to harvest plant, relative to selected field. Must be on same screen as selected grid.

FIELD_CROP_ID        := ITEM_ID_CORN
FIELD_CROP_PRICE     := PRICE_MAX
FIELD_CROP_PRICE_MOD := -3
FIELD_CROP_PRICE_AD  := true

MAX_CROP_OVERLAY_SCREEN := 3 ; Speeds up alignment, but has to be set higher for higher level users.

; Mode/State init.
plantDone := false      ; Memory used to go dirctly to shop and sell.
siloBarnFull := false   ; 

farmingStep := 10        
;   0 - Go to shop
;   5 - 
;  10 - Init scale and screen
;  12 - Move to field
;  15 - Get field status
;  20 - Harvest
;  25 - Plant
; 100 - Post sale
; ------------------------------------------------------------------------------------------------


; ------------------------------------------------------------------------------------------------
; Other hay day global
SHOP_SLOTS_ON_SCREEN := 4           ;   Visible slots in the shops, 4 on PC, 8 on MacOS?
SHOP_SLOTS_TO_SCROLL := 4
FRIEND_SLOTS_ON_SCREEN := 7         ;   In the lower right friend list.
FRIEND_SLOTS_TO_DRAG := 1           ;   Allow for not overdragging.
TOP_MAX_SELL_SLOTS_SEARCHED := 8    ;   XXX - Used?

; Update screen recognition functions if adding new.
SCREEN_HOME         := 0
SCREEN_FRIEND       := 1
SCREEN_LOADING      := 2
SCREEN_CONNECTION_LOST  := 3
SCREEN_SILO_BARN_FULL   := 4
; ------------------------------------------------------------------------------------------------


; ------------------------------------------------------------------------------------------------
; Shop enumerations for MY shop
SHOP_ITEM_EMPTY     := 0
SHOP_ITEM_ON_SALE   := 1  
SHOP_ITEM_HAS_AD    := 2
SHOP_ITEM_SOLD      := 3
ShopMyItemStatus_ToString(s) {
    if (s = 0) 
        return "SHOP_ITEM_EMPTY"
    if (s = 1) 
        return "SHOP_ITEM_ON_SALE"
    if (s = 2) 
        return "SHOP_ITEM_HAS_AD"
    if (s = 3) 
        return "SHOP_ITEM_SOLD"

    return "INVALID"
}
; ------------------------------------------------------------------------------------------------


; ------------------------------------------------------------------------------------------------
; Global for mouse data
mouseX := 0             ; Seems not to be global
mouseY := 0
mouseWin := 0
mouseCtrl := ""
mouseCol = 0
; ------------------------------------------------------------------------------------------------


; ------------------------------------------------------------------------------------------------
; Object coordinates in App coords
;  All measured for w,h = 1077, 640
;  All uses a header offset of 34, i.e if a measuered coord is 34, it is top.
;
; All positions needs to be scaled considering header, all sizes need scale only.

;
; Button release counts as click even if dragged into an item. For instance if trying to move
;  top left until no more happens, then mouse drags into screen, and be careful not to 
;  land on stuff. I.e. small moves.
; Zoom out at other player is safe.

; Declaration of variables
; Window position - will be recalculated later.
; For actions the SCREEN positions are used. This does not require the app win to be active.
APP_HEADER_Y        := 34       ; All measured coords will have this as Y0. Affects scale.
APP_SIZE_X_NRM      := 1080     ; All size measurements was done based on this
APP_SIZE_Y_NRM      := 642      ; All size measurements was done based on this
APP_SIZE_X          := 0
APP_CENTER_X        := 0
APP_SIZE_Y          := 0
APP_CENTER_Y        := 0
APP_TOP_LEFT_X      := 0
APP_TOP_LEFT_Y      := 0
APP_SCALE           := 1.0

GAME_AREA_CENTER_X  := 0 
GAME_AREA_CENTER_Y  := 0

; Defines how many fields are reachable to click TODO define instead a screen pixel area. 
SCREEN_REACH_ROWS := [-10, 7]   ; From center field 
SCREEN_REACH_COLS := [-10, 7]   ; From center field 
; ------------------------------------------------------------------------------------------------

; ------------------------------------------------------------------------------------------------
; Declaration of variables to be dynamically scaled.
;  Update init function after adding a variable.
RED_X_DIFF_UP       := 30   ; A point above the x to fit both the large and the small x
RED_X_DIFF_DOWN     := 27

; To be dynamically scaled
; Can be till-sign also. Lower left
BTN_HOME_X          := 55      ; In app window coords.
BTN_HOME_Y          := 570     ; In app window coords.
;
BTN_FRIENDS_X       := 1023     ; In app window coords.
BTN_FRIENDS_Y       := 587      ; In app window coords.
FRIENDS_BAR_OPEN_X  := 175
FRIENDS_BAR_OPEN_Y  := 618
FRIENDS_BAR_OPEN_C  := 0xE89800
; Recognition of Greg in the friend bar to stop scrolling.
; Coordinates are absolute so to detect in other slots need to shift center.
FRIEND_GREG_P1_X :=	342
FRIEND_GREG_P1_Y :=	527
FRIEND_GREG_P1_C :=	0x68C4E8
FRIEND_GREG_P2_X :=	338
FRIEND_GREG_P2_Y :=	563
FRIEND_GREG_P2_C :=	0x752A2E
FRIEND_GREG_P3_X :=	350
FRIEND_GREG_P3_Y :=	575
FRIEND_GREG_P3_C :=	0x541E20
FRIEND_GREG_P4_X :=	393
FRIEND_GREG_P4_Y :=	527
FRIEND_GREG_P4_C :=	0x68C8E8
; For dragging the screen. Have to drag "quick" or the first anchor press will select 
;  object on screen for moving it.
DRAG_ANCHOR_LOWER_LEFT_X    := 155
DRAG_ANCHOR_LOWER_LEFT_Y    := 550
DRAG_ANCHOR_TOP_LEFT_X    := 155
DRAG_ANCHOR_TOP_LEFT_Y    := 124
;
FRIENDS_BAR_HEADER_Y    := 442
FRIENDS_BAR_HEADER_CLAN_X           := 265
FRIENDS_BAR_HEADER_HELP_WANTED_X    := 360
FRIENDS_BAR_HEADER_LAST_HELPERS_X   := 500
FRIENDS_BAR_HEADER_FRIENDS_X        := 690
FRIENDS_BAR_HEADER_FOLLOWERS_X      := 870
; 
FRIEND_SLOT_DIFF_X  := 109
FRIEND_SLOT1_X  := 370     ; From left where greg is 1.
FRIEND_SLOT1_Y  := 548     ;  
; For navigating from friend to their shop. Must be zoomed out first or shop position is too uncertain.
;   Repeat 3 times: Drag from lower left 150, 500 to center
;   Shop is now at 125, 280. 
BTN_FRIEND_SHOP_AFTER_DRAG_X    := 284 ; 275 Can get this from coordinate system.
BTN_FRIEND_SHOP_AFTER_DRAG_Y    := 342 ; 404
; For navigating on the home screen the screen is first centerd top left
ZOOM_OUT_ANCHOR_TOP_LEFT_X  := 200 ;100
ZOOM_OUT_ANCHOR_TOP_LEFT_Y  := 300 ;175
BTN_MY_SHOP_AFTER_DRAG_X    := 443
BTN_MY_SHOP_AFTER_DRAG_Y    := 493 ;432
;
RED_X_EVENT_NOTIFY_X    := 929 
RED_X_EVENT_NOTIFY_Y    := 93
;
RED_X_NEIGHBORHOODS_X    := 926 
RED_X_NEIGHBORHOODS_Y    := 90
;
RED_X_FARM_PASS_X    := 927 
RED_X_FARM_PASS_Y    := 88
;
RED_X_DERBY_X    := 929 
RED_X_DERBY_Y    := 90
;
RED_X_BIG_BOX_X := 930
RED_X_BIG_BOX_Y := 105
;
RED_X_MANSION_X := 931
RED_X_MANSION_Y := 94
;
RED_X_COMMERCIAL_X := 931
RED_X_COMMERCIAL_Y := 95
;
RED_X_GOOGLE_PLAY_X := 931
RED_X_GOOGLE_PLAY_Y := 105
;
BTN_CLOSE_COMMERCIAL_X := 1033
BTN_CLOSE_COMMERCIAL_Y := 71
BTN_START_COMMERCIAL_X := 837
BTN_START_COMMERCIAL_Y := 508

; Check if loading screen, 4 points
LOAD_SCREEN_C := 0x034AC3
LOAD_SCREEN_P1_X := 100
LOAD_SCREEN_P1_Y := 300
LOAD_SCREEN_P2_X := 980
LOAD_SCREEN_P2_Y := 300
LOAD_SCREEN_P3_X := 100
LOAD_SCREEN_P3_Y := 400
LOAD_SCREEN_P4_X := 980
LOAD_SCREEN_P4_Y := 400
; Perhaps not needed. If location lost, and reason is loading screen, it is temporary. Just wait.
LOAD_SCREEN_SUMMER_P1_X := 268
LOAD_SCREEN_SUMMER_P1_Y := 87
LOAD_SCREEN_SUMMER_P1_C := 0x63DE40
LOAD_SCREEN_SUMMER_P2_X := 784
LOAD_SCREEN_SUMMER_P2_Y := 110
LOAD_SCREEN_SUMMER_P2_C := 0x63D430
LOAD_SCREEN_SUMMER_P3_X := 915
LOAD_SCREEN_SUMMER_P3_Y := 561
LOAD_SCREEN_SUMMER_P3_C := 0xFFF8B8
LOAD_SCREEN_SUMMER_P4_X := 208
LOAD_SCREEN_SUMMER_P4_Y := 459
LOAD_SCREEN_SUMMER_P4_C := 0xFFF8B8
; Check if connection lost screen
LOST_SCREEN_P1_X := 268
LOST_SCREEN_P1_Y := 87
LOST_SCREEN_P1_C := 0x63DE40
LOST_SCREEN_P2_X := 784
LOST_SCREEN_P2_Y := 110
LOST_SCREEN_P2_C := 0x63D430
LOST_SCREEN_P3_X := 915
LOST_SCREEN_P3_Y := 561
LOST_SCREEN_P3_C := 0xFFF8B8
LOST_SCREEN_P4_X := 208
LOST_SCREEN_P4_Y := 459
LOST_SCREEN_P4_C := 0xFFF8B8
;
BTN_TRY_AGAIN_X := 544
BTN_TRY_AGAIN_Y := 600
;
; Home screen detected by: 
HOME_SCREEN_P1_X := 47
HOME_SCREEN_P1_Y := 54
HOME_SCREEN_P1_C := 0xF8E850
HOME_SCREEN_P2_X := 28
HOME_SCREEN_P2_Y := 549
HOME_SCREEN_P2_C := 0xF8E850
HOME_SCREEN_P3_X := 1038
HOME_SCREEN_P3_Y := 70
HOME_SCREEN_P3_C := 0xFFF7A2
HOME_SCREEN_P4_X := 970
HOME_SCREEN_P4_Y := 73
HOME_SCREEN_P4_C := 0xFFEB3E
; Friend screen identical except home button instead of casher
FRIEND_SCREEN_P1_X := 47
FRIEND_SCREEN_P1_Y := 54
FRIEND_SCREEN_P1_C := 0xF8E850
FRIEND_SCREEN_P2_X := 28
FRIEND_SCREEN_P2_Y := 549
FRIEND_SCREEN_P2_C := 0xD0FFB0
FRIEND_SCREEN_P3_X := 1038
FRIEND_SCREEN_P3_Y := 70
FRIEND_SCREEN_P3_C := 0xFFF7A2
FRIEND_SCREEN_P4_X := 1038
FRIEND_SCREEN_P4_Y := 135
FRIEND_SCREEN_P4_C := 0xFFF6A0
;
HOME_ICON_P1_X :=	127
HOME_ICON_P1_Y :=	576
HOME_ICON_P1_C :=	0xFFFAD6
HOME_ICON_P2_X :=	17
HOME_ICON_P2_Y :=	591
HOME_ICON_P2_C :=	0x02D929
HOME_ICON_P3_X :=	101
HOME_ICON_P3_Y :=	557
HOME_ICON_P3_C :=	0x03DC2B
HOME_ICON_P4_X :=	69
HOME_ICON_P4_Y :=	555
HOME_ICON_P4_C :=	0xFFF8AB
; Pixel Position of the cell center at the right back side of the mansion.
; This position is valid only if screen is dragged to TOP LEFT REF and then to CENTER REF position. 
; TODO - Seems even the DLL move is a little uncertain. Alignment needed.
;  Like every time the app reloads, the scroll is a little different.
;
; NOTE for moveing screen to see the 1:st field: 
;  Y-pos MUST be 310 - 518 in unscaled app coords or else the screen is moved when clicked. 
;  X-pos MUST be 394 - 1044 in unscaled app coords or else the screen is moved when clicked. 
FIELD_REF_X := 853 ;784 ;807 ;796 ;827 ;776 ;788 ;860 ;774
FIELD_REF_Y := 364 ;335 ;342 ;337 ;351 ;329 ;334 ;365 ;328

; At the calibration screen (top left) this is the initial reference. After scale is measured,
;  then all following drags and positions can be calculated.
;
; Update all of these after each screen scroll (in 'fields'). Or when re-calibrating. The bot must know what
;  at least one field coordinate is at a known screen coordinate. 
;  And that field must be exactly centered to the screen coord for harvest/plant detection to work. 
g_CenterFieldScreenCoordsRaw_X := 507 + 29.57142857     ;
g_CenterFieldScreenCoordsRaw_Y := 315 + 14.82142857     ;  
g_RC_CenterField_Raw := [2, 14]                          ; 


; Updated after each screen scroll to hold the center field pixel coords. Or when re-calibrating.
; It needs recalculation with exact scale to be useful.
g_CenterFieldScreenCoords_X := -1
g_CenterFieldScreenCoords_Y := -1
g_RC_CenterField := g_RC_CenterField_Raw


; Counting screen grid rows/col start top left on screen at max zoom out.
; This is depending on the game zoom factor which varies about 5% each load. But as long as
;   zoom factor determination and this and move uses same calibration it's ok.
; Zoom randomize affects screen moves, but not anything in shops.
; Below when columns are counted alon the river. As if the river was the top and horisontal
COORD_TRANSFORM_ROW_X :=  29.57142857
COORD_TRANSFORM_ROW_Y :=  14.82142857
COORD_TRANSFORM_COL_X :=  29.62068966
COORD_TRANSFORM_COL_Y := -14.86206897

; These belong to the same scale as above and all must be sampled at the same time.
BOAT_DETECT_REF_Y := 210 ;217    ; Below setting gear at level of boat nose.
BOAT_DETECT_X := 376        ; Used to detect scale. Left edge of boat to detect - AT SAME SCALE where FIELD REF and transform was measured.
; Retarded to use boat. It is not always there.
; Use river shore vertically.
; ; Used to detect scale. Left edge of boat to detect - AT SAME SCALE where FIELD REF and transform was measured.
RIVER_DETECT_REF_X := 150
RIVER_DETECT_Y := 401 ;435       ; This value should be in game area coords, excluding any header from LDPlayer or similar. 
;
g_AppScaleExtra := 1.0    ; This is the randomised factor added each time the home screen is opened.
;
; Testing both shores
RIVER_UPPER_REF_Y := 214-34
RIVER_LOWER_REF_Y := 474-34
;
SCREEN_SERVER_OFFLINE_P1_X :=	882
SCREEN_SERVER_OFFLINE_P1_Y :=	580
SCREEN_SERVER_OFFLINE_P1_C :=	0xFBD230
SCREEN_SERVER_OFFLINE_P2_X :=	166
SCREEN_SERVER_OFFLINE_P2_Y :=	579
SCREEN_SERVER_OFFLINE_P2_C :=	0xF8D533
SCREEN_SERVER_OFFLINE_P3_X :=	537
SCREEN_SERVER_OFFLINE_P3_Y :=	307
SCREEN_SERVER_OFFLINE_P3_C :=	0xFFF8B8
SCREEN_SERVER_OFFLINE_P4_X :=	532
SCREEN_SERVER_OFFLINE_P4_Y :=	72
SCREEN_SERVER_OFFLINE_P4_C :=	0x63E448


InitGeneralCoords() {
    global APP_SCALE

    ; These are initial values only. Needs exact scale measurement later to be useful.
    global g_CenterFieldScreenCoordsRaw_X, g_CenterFieldScreenCoordsRaw_Y
    global g_CenterFieldScreenCoords_X := Ceil( AC2SC(g_CenterFieldScreenCoordsRaw_X, 0) )
    global g_CenterFieldScreenCoords_Y := Ceil( AC2SC(g_CenterFieldScreenCoordsRaw_Y, 1) )

    global RED_X_DIFF_UP   := Ceil( APP_SCALE*RED_X_DIFF_UP )
    global RED_X_DIFF_DOWN := Ceil( APP_SCALE*RED_X_DIFF_DOWN )

    global BTN_HOME_X      := Ceil( AC2SC(BTN_HOME_X, 0) )   
    global BTN_HOME_Y      := Ceil( AC2SC(BTN_HOME_Y, 1) )     

    global BTN_FRIENDS_X   := Ceil( AC2SC(BTN_FRIENDS_X, 0) )
    global BTN_FRIENDS_Y   := Ceil( AC2SC(BTN_FRIENDS_Y, 1) )
    global FRIENDS_BAR_OPEN_X  := Ceil( AC2SC(FRIENDS_BAR_OPEN_X, 0) )
    global FRIENDS_BAR_OPEN_Y  := Ceil( AC2SC(FRIENDS_BAR_OPEN_Y, 1) )
    ;
    global FRIENDS_BAR_HEADER_Y                := Ceil( AC2SC(FRIENDS_BAR_HEADER_Y, 1) )
    global FRIENDS_BAR_HEADER_CLAN_X           := Ceil( AC2SC(FRIENDS_BAR_HEADER_CLAN_X, 0) )
    global FRIENDS_BAR_HEADER_HELP_WANTED_X    := Ceil( AC2SC(FRIENDS_BAR_HEADER_HELP_WANTED_X, 0) )
    global FRIENDS_BAR_HEADER_LAST_HELPERS_X   := Ceil( AC2SC(FRIENDS_BAR_HEADER_LAST_HELPERS_X, 0) )
    global FRIENDS_BAR_HEADER_FRIENDS_X        := Ceil( AC2SC(FRIENDS_BAR_HEADER_FRIENDS_X, 0) )
    global FRIENDS_BAR_HEADER_FOLLOWERS_X      := Ceil( AC2SC(FRIENDS_BAR_HEADER_FOLLOWERS_X, 0) )

    global FRIEND_GREG_P1_X := Ceil( AC2SC(FRIEND_GREG_P1_X, 0) )
    global FRIEND_GREG_P1_Y := Ceil( AC2SC(FRIEND_GREG_P1_Y, 1) )
    global FRIEND_GREG_P2_X := Ceil( AC2SC(FRIEND_GREG_P2_X, 0) )
    global FRIEND_GREG_P2_Y := Ceil( AC2SC(FRIEND_GREG_P2_Y, 1) )
    global FRIEND_GREG_P3_X := Ceil( AC2SC(FRIEND_GREG_P3_X, 0) )
    global FRIEND_GREG_P3_Y := Ceil( AC2SC(FRIEND_GREG_P3_Y, 1) )
    global FRIEND_GREG_P4_X := Ceil( AC2SC(FRIEND_GREG_P4_X, 0) )
    global FRIEND_GREG_P4_Y := Ceil( AC2SC(FRIEND_GREG_P4_Y, 1) )

    global FRIEND_SLOT_DIFF_X  := Ceil( APP_SCALE*FRIEND_SLOT_DIFF_X )
    global FRIEND_SLOT1_X  := Ceil( AC2SC(FRIEND_SLOT1_X, 0) )
    global FRIEND_SLOT1_Y  := Ceil( AC2SC(FRIEND_SLOT1_Y, 1) )

    global DRAG_ANCHOR_LOWER_LEFT_X    := Ceil( AC2SC(DRAG_ANCHOR_LOWER_LEFT_X, 0) )
    global DRAG_ANCHOR_LOWER_LEFT_Y    := Ceil( AC2SC(DRAG_ANCHOR_LOWER_LEFT_Y, 1) )
    global DRAG_ANCHOR_TOP_LEFT_X      := Ceil( AC2SC(DRAG_ANCHOR_TOP_LEFT_X, 0) )
    global DRAG_ANCHOR_TOP_LEFT_Y      := Ceil( AC2SC(DRAG_ANCHOR_TOP_LEFT_Y, 1) )

    global FIELD_REF_X := Ceil( AC2SC(FIELD_REF_X, 0) )
    global FIELD_REF_Y := Ceil( AC2SC(FIELD_REF_Y, 1) )

    global BTN_FRIEND_SHOP_AFTER_DRAG_X    := Ceil( AC2SC(BTN_FRIEND_SHOP_AFTER_DRAG_X, 0) )
    global BTN_FRIEND_SHOP_AFTER_DRAG_Y    := Ceil( AC2SC(BTN_FRIEND_SHOP_AFTER_DRAG_Y, 1) )

    global ZOOM_OUT_ANCHOR_TOP_LEFT_X  := Ceil( AC2SC(ZOOM_OUT_ANCHOR_TOP_LEFT_X, 0) )
    global ZOOM_OUT_ANCHOR_TOP_LEFT_Y  := Ceil( AC2SC(ZOOM_OUT_ANCHOR_TOP_LEFT_Y, 1) )
    global BTN_MY_SHOP_AFTER_DRAG_X    := Ceil( AC2SC(BTN_MY_SHOP_AFTER_DRAG_X, 0) )
    global BTN_MY_SHOP_AFTER_DRAG_Y    := Ceil( AC2SC(BTN_MY_SHOP_AFTER_DRAG_Y, 1) )    

    global RED_X_EVENT_NOTIFY_X    := Ceil( AC2SC(RED_X_EVENT_NOTIFY_X, 0) )
    global RED_X_EVENT_NOTIFY_Y    := Ceil( AC2SC(RED_X_EVENT_NOTIFY_Y, 1) )

    global RED_X_NEIGHBORHOODS_X    := Ceil( AC2SC(RED_X_NEIGHBORHOODS_X, 0) )
    global RED_X_NEIGHBORHOODS_Y    := Ceil( AC2SC(RED_X_NEIGHBORHOODS_Y, 1) )

    global RED_X_FARM_PASS_X    := Ceil( AC2SC(RED_X_FARM_PASS_X, 0) )
    global RED_X_FARM_PASS_Y    := Ceil( AC2SC(RED_X_FARM_PASS_Y, 1) )

    global RED_X_DERBY_X    := := Ceil( AC2SC(RED_X_DERBY_X, 0) )
    global RED_X_DERBY_Y    := := Ceil( AC2SC(RED_X_DERBY_Y, 1) )

    global RED_X_BIG_BOX_X := Ceil( AC2SC(RED_X_BIG_BOX_X, 0) )
    global RED_X_BIG_BOX_Y := Ceil( AC2SC(RED_X_BIG_BOX_Y, 1) )

    global RED_X_MANSION_X := Ceil( AC2SC(RED_X_MANSION_X, 0) )
    global RED_X_MANSION_Y := Ceil( AC2SC(RED_X_MANSION_Y, 1) )

    global RED_X_COMMERCIAL_X := Ceil( AC2SC(RED_X_COMMERCIAL_X, 0) )
    global RED_X_COMMERCIAL_Y := Ceil( AC2SC(RED_X_COMMERCIAL_Y, 1) )

    global RED_X_GOOGLE_PLAY_X := Ceil( AC2SC(RED_X_GOOGLE_PLAY_X, 0) )
    global RED_X_GOOGLE_PLAY_Y := Ceil( AC2SC(RED_X_GOOGLE_PLAY_Y, 1) )

    global BTN_CLOSE_COMMERCIAL_X := Ceil( AC2SC(BTN_CLOSE_COMMERCIAL_X, 0) )
    global BTN_CLOSE_COMMERCIAL_Y := Ceil( AC2SC(BTN_CLOSE_COMMERCIAL_Y, 1) )
    global BTN_START_COMMERCIAL_X := Ceil( AC2SC(BTN_START_COMMERCIAL_X, 0) )
    global BTN_START_COMMERCIAL_Y := Ceil( AC2SC(BTN_START_COMMERCIAL_Y, 1) )

    global LOAD_SCREEN_P1_X := Ceil( AC2SC(LOAD_SCREEN_P1_X, 0) )
    global LOAD_SCREEN_P1_Y := Ceil( AC2SC(LOAD_SCREEN_P1_Y, 1) )
    global LOAD_SCREEN_P2_X := Ceil( AC2SC(LOAD_SCREEN_P2_X, 0) )
    global LOAD_SCREEN_P2_Y := Ceil( AC2SC(LOAD_SCREEN_P2_Y, 1) )
    global LOAD_SCREEN_P3_X := Ceil( AC2SC(LOAD_SCREEN_P3_X, 0) )
    global LOAD_SCREEN_P3_Y := Ceil( AC2SC(LOAD_SCREEN_P3_Y, 1) )
    global LOAD_SCREEN_P4_X := Ceil( AC2SC(LOAD_SCREEN_P4_X, 0) )
    global LOAD_SCREEN_P4_Y := Ceil( AC2SC(LOAD_SCREEN_P4_Y, 1) )
    ;
    global LOST_SCREEN_P1_X := Ceil( AC2SC(  LOST_SCREEN_P1_X, 0) )
    global LOST_SCREEN_P1_Y := Ceil( AC2SC(  LOST_SCREEN_P1_Y, 1) )
    global LOST_SCREEN_P2_X := Ceil( AC2SC(  LOST_SCREEN_P2_X, 0) )
    global LOST_SCREEN_P2_Y := Ceil( AC2SC(  LOST_SCREEN_P2_Y, 1) )
    global LOST_SCREEN_P3_X := Ceil( AC2SC(  LOST_SCREEN_P3_X, 0) )
    global LOST_SCREEN_P3_Y := Ceil( AC2SC(  LOST_SCREEN_P3_Y, 1) )
    global LOST_SCREEN_P4_X := Ceil( AC2SC(  LOST_SCREEN_P4_X, 0) )
    global LOST_SCREEN_P4_Y := Ceil( AC2SC(  LOST_SCREEN_P4_Y, 1) )
    global BTN_TRY_AGAIN_X := Ceil( AC2SC(  BTN_TRY_AGAIN_X, 0) )
    global BTN_TRY_AGAIN_Y := Ceil( AC2SC(  BTN_TRY_AGAIN_Y, 1) )
    ;
    global HOME_SCREEN_P1_X := Ceil( AC2SC( HOME_SCREEN_P1_X, 0) )
    global HOME_SCREEN_P1_Y := Ceil( AC2SC( HOME_SCREEN_P1_Y, 1) )
    global HOME_SCREEN_P2_X := Ceil( AC2SC( HOME_SCREEN_P2_X, 0) )
    global HOME_SCREEN_P2_Y := Ceil( AC2SC( HOME_SCREEN_P2_Y, 1) )
    global HOME_SCREEN_P3_X := Ceil( AC2SC( HOME_SCREEN_P3_X, 0) )
    global HOME_SCREEN_P3_Y := Ceil( AC2SC( HOME_SCREEN_P3_Y, 1) )
    global HOME_SCREEN_P4_X := Ceil( AC2SC( HOME_SCREEN_P4_X, 0) )
    global HOME_SCREEN_P4_Y := Ceil( AC2SC( HOME_SCREEN_P4_Y, 1) )
    ;
    global FRIEND_SCREEN_P1_X := Ceil( AC2SC( FRIEND_SCREEN_P1_X, 0) )
    global FRIEND_SCREEN_P1_Y := Ceil( AC2SC( FRIEND_SCREEN_P1_Y, 1) )
    global FRIEND_SCREEN_P2_X := Ceil( AC2SC( FRIEND_SCREEN_P2_X, 0) )
    global FRIEND_SCREEN_P2_Y := Ceil( AC2SC( FRIEND_SCREEN_P2_Y, 1) )
    global FRIEND_SCREEN_P3_X := Ceil( AC2SC( FRIEND_SCREEN_P3_X, 0) )
    global FRIEND_SCREEN_P3_Y := Ceil( AC2SC( FRIEND_SCREEN_P3_Y, 1) )
    global FRIEND_SCREEN_P4_X := Ceil( AC2SC( FRIEND_SCREEN_P4_X, 0) )
    global FRIEND_SCREEN_P4_Y := Ceil( AC2SC( FRIEND_SCREEN_P4_Y, 1) )
    ;
    global HOME_ICON_P1_X :=	Ceil( AC2SC(HOME_ICON_P1_X, 0) )
    global HOME_ICON_P1_Y :=	Ceil( AC2SC(HOME_ICON_P1_Y, 1) )
    global HOME_ICON_P2_X :=	Ceil( AC2SC(HOME_ICON_P2_X, 0) )
    global HOME_ICON_P2_Y :=	Ceil( AC2SC(HOME_ICON_P2_Y, 1) )
    global HOME_ICON_P3_X :=	Ceil( AC2SC(HOME_ICON_P3_X, 0) )
    global HOME_ICON_P3_Y :=	Ceil( AC2SC(HOME_ICON_P3_Y, 1) )
    global HOME_ICON_P4_X :=	Ceil( AC2SC(HOME_ICON_P4_X, 0) )
    global HOME_ICON_P4_Y :=	Ceil( AC2SC(HOME_ICON_P4_Y, 1) )
    ; Do not round these here.
    global COORD_TRANSFORM_ROW_X := COORD_TRANSFORM_ROW_X*APP_SCALE
    global COORD_TRANSFORM_ROW_Y := COORD_TRANSFORM_ROW_Y*APP_SCALE
    global COORD_TRANSFORM_COL_X := COORD_TRANSFORM_COL_X*APP_SCALE
    global COORD_TRANSFORM_COL_Y := COORD_TRANSFORM_COL_Y*APP_SCALE
    ;
    global BOAT_DETECT_REF_Y        := Ceil( AC2SC(BOAT_DETECT_REF_Y, 1) )
    global BOAT_DETECT_X            := Ceil( APP_SCALE*BOAT_DETECT_X )       ; Only scale bc counting from left edge.
    ;
    global RIVER_DETECT_REF_X := Ceil( AC2SC(RIVER_DETECT_REF_X, 0) )
    global RIVER_DETECT_Y     := Ceil( APP_SCALE*RIVER_DETECT_Y )            ; Scale Y according to game area!

    global RIVER_UPPER_REF_Y     := Ceil( APP_SCALE*RIVER_UPPER_REF_Y )            ; Scale Y according to game area!
    global RIVER_LOWER_REF_Y     := Ceil( APP_SCALE*RIVER_LOWER_REF_Y )            ; Scale Y according to game area!
    ;
    global SCREEN_SERVER_OFFLINE_P1_X := Ceil( AC2SC( SCREEN_SERVER_OFFLINE_P1_X, 0) )
    global SCREEN_SERVER_OFFLINE_P1_Y := Ceil( AC2SC( SCREEN_SERVER_OFFLINE_P1_Y, 1) )
    global SCREEN_SERVER_OFFLINE_P2_X := Ceil( AC2SC( SCREEN_SERVER_OFFLINE_P2_X, 0) )
    global SCREEN_SERVER_OFFLINE_P2_Y := Ceil( AC2SC( SCREEN_SERVER_OFFLINE_P2_Y, 1) )
    global SCREEN_SERVER_OFFLINE_P3_X := Ceil( AC2SC( SCREEN_SERVER_OFFLINE_P3_X, 0) )
    global SCREEN_SERVER_OFFLINE_P3_Y := Ceil( AC2SC( SCREEN_SERVER_OFFLINE_P3_Y, 1) )
    global SCREEN_SERVER_OFFLINE_P4_X := Ceil( AC2SC( SCREEN_SERVER_OFFLINE_P4_X, 0) )
    global SCREEN_SERVER_OFFLINE_P4_Y := Ceil( AC2SC( SCREEN_SERVER_OFFLINE_P4_Y, 1) )
}
; ------------------------------------------------------------------------------------------------

; ------------------------------------------------------------------------------------------------
; Declaration of variables to be dynamically scaled.
;  Update init function after adding a variable.
SHOP_SLOT_WIDTH     := 190      ; For Icon size use
SHOP_SLOT_HEIGHT    := 210      ; For Icon size use
SHOP_SLOT_DIFF_X    := 202.5    ; To next slot. XXX 
SHOP_SLOT_1_X       := 187      ; Center slot In app window coords.
SHOP_SLOT_1_Y       := 313      ; Center slot In app window coords.
; To compensate for drag a little out of phase.
SHOP_ALIGNMENT_REF_X := 288
SHOP_ALIGNMENT_REF_Y := 215
SHOP_ALIGNMENT_REF_C := 0xC79285
SHOP_ALIGNMENT_DIFF_X := 19
; Recognition of items in shop slots ; For slot 1
; Good on sale must leave the area where the ad is, free.
SHOP_SLOT_ON_SALE_P1_X :=	187 ;179         ; Pricetag left top corner. (The 187 is lower left corner, it is more free when high price.)
SHOP_SLOT_ON_SALE_P1_Y :=	400 ;356
SHOP_SLOT_ON_SALE_P1_C :=	0xFFF8B8
SHOP_SLOT_ON_SALE_P2_X :=	268         ; Center of the coin.
SHOP_SLOT_ON_SALE_P2_Y :=	349
SHOP_SLOT_ON_SALE_P2_C :=	0xFFED53
SHOP_SLOT_ON_SALE_P3_X :=	190         ; Top drawer
SHOP_SLOT_ON_SALE_P3_Y :=	223
SHOP_SLOT_ON_SALE_P3_C :=	0xEEBA43
SHOP_SLOT_ON_SALE_P4_X :=	217         ; Bottom drawer right
SHOP_SLOT_ON_SALE_P4_Y :=	416
SHOP_SLOT_ON_SALE_P4_C :=	0xECB141
;
SHOP_SLOT_1_PRICETAG_X := 187
SHOP_SLOT_1_PRICETAG_Y := 400
SHOP_SLOT_1_PRICETAG_C := 0xFFF8B8
;
SHOP_SLOT_EMPTY_P1_X :=	188             ; Center under
SHOP_SLOT_EMPTY_P1_Y :=	399
SHOP_SLOT_EMPTY_P1_C :=	0xF0CA5A
SHOP_SLOT_EMPTY_P2_X :=	168             ; Lower center left
SHOP_SLOT_EMPTY_P2_Y :=	368
SHOP_SLOT_EMPTY_P2_C :=	0xE2AF3B
SHOP_SLOT_EMPTY_P3_X :=	209             ; Lower center right
SHOP_SLOT_EMPTY_P3_Y :=	368
SHOP_SLOT_EMPTY_P3_C :=	0xE2AD3A
SHOP_SLOT_EMPTY_P4_X :=	209             ; Upper center right
SHOP_SLOT_EMPTY_P4_Y :=	266
SHOP_SLOT_EMPTY_P4_C :=	0xE9C740
;
SHOP_DRAG_Y         := 435      ; Area below items to drag scroll.
SHOP_DRAG_DB        := 25       ; There is a deadband before the slots are moved. Varies, make sure high enough.
SHOP_DRAG_REV_X     := 108-23   ; When overdragging reverse this. XXX Depends on how big shop. 
SHOP_DRAG_REV_P1_X  := 172  
SHOP_DRAG_REV_P1_Y  := 211  
SHOP_DRAG_REV_C     := 0xC79376 ; Shop purple/brown bg at the top (not the same in all y)
; My item is sold - check these points (made for slot 1)
SHOP_SLOT_SOLD_P1_X :=	166             ; In yellow left of chicken
SHOP_SLOT_SOLD_P1_Y :=	265
SHOP_SLOT_SOLD_P1_C :=	0xFFF8B8
SHOP_SLOT_SOLD_P2_X :=	181             ; Inside chicken
SHOP_SLOT_SOLD_P2_Y :=	292
SHOP_SLOT_SOLD_P2_C :=	0xC48821
SHOP_SLOT_SOLD_P3_X :=	193             ; Inside chicken
SHOP_SLOT_SOLD_P3_Y :=	285
SHOP_SLOT_SOLD_P3_C :=	0xC9942D
SHOP_SLOT_SOLD_P4_X :=	214             ; In yellow right of chicken
SHOP_SLOT_SOLD_P4_Y :=	251
SHOP_SLOT_SOLD_P4_C :=	0xFDF4B1

; Recognition of items in shop slots
SHOP_SLOT_CORN_P1_X :=	233
SHOP_SLOT_CORN_P1_Y :=	291
SHOP_SLOT_CORN_P1_C :=	0xE8BF3F
SHOP_SLOT_CORN_P2_X :=	175
SHOP_SLOT_CORN_P2_Y :=	323
SHOP_SLOT_CORN_P2_C :=	0x919803
SHOP_SLOT_CORN_P3_X :=	138
SHOP_SLOT_CORN_P3_Y :=	326
SHOP_SLOT_CORN_P3_C :=	0x8A9000
SHOP_SLOT_CORN_P4_X :=	201
SHOP_SLOT_CORN_P4_Y :=	271
SHOP_SLOT_CORN_P4_C :=	0xFBF77B
;
RED_X_SHOP_X    := 919     ; In app window coords. 
RED_X_SHOP_Y    := 96      ; In app window coords.
;
RED_X_SILO_BARN_FULL_X    := 930     ; In app window coords. 
RED_X_SILO_BARN_FULL_Y    := 105     ; In app window coords.
;
; Advertise an item that was already added to the shop.
; "Edit sale"
BTN_AD_X            := 667      ; Do not click twice here it will be diamond.
BTN_AD_Y            := 314
BTN_AD_DO_X         := 530      ; Always click this aftewards, then at the red cross even if it's not there.
BTN_AD_DO_Y         := 470
BTN_AD_CLOSE_X      := 788      ; Always click this aftewards, then at the red cross even if it's not there.
BTN_AD_CLOSE_Y      := 103
SHOP_AD_X           := 111      ; Ad position on item in shop (grayscale here = item has ad)
SHOP_AD_Y           := 395      ; Ad position on item in shop
; When shopping, the silo/barn is full (this in addition to the same erd cross at shop)
SILO_BARN_FULL_1_X := 327
SILO_BARN_FULL_1_Y := 110
SILO_BARN_FULL_1_C := 0xF8D839
SILO_BARN_FULL_2_X := 733
SILO_BARN_FULL_2_Y := 110
SILO_BARN_FULL_2_C := 0xF8D839
SILO_BARN_FULL_3_X := 548
SILO_BARN_FULL_3_Y := 477
SILO_BARN_FULL_3_C := 0xFFF8B8
SILO_BARN_FULL_4_X := 894
SILO_BARN_FULL_4_Y := 560
SILO_BARN_FULL_4_C := 0xFFF8B8
; For friend's shop
SOLD_FRIEND_SHOP_SLOT_P1_X :=	172
SOLD_FRIEND_SHOP_SLOT_P1_Y :=	361
SOLD_FRIEND_SHOP_SLOT_P1_C :=	0xF3F3F3
SOLD_FRIEND_SHOP_SLOT_P2_X :=	281
SOLD_FRIEND_SHOP_SLOT_P2_Y :=	354
SOLD_FRIEND_SHOP_SLOT_P2_C :=	0xF3F3F3
SOLD_FRIEND_SHOP_SLOT_P3_X :=	115
SOLD_FRIEND_SHOP_SLOT_P3_Y :=	400
SOLD_FRIEND_SHOP_SLOT_P3_C :=	0xC3C3C3
SOLD_FRIEND_SHOP_SLOT_P4_X :=	261
SOLD_FRIEND_SHOP_SLOT_P4_Y :=	399
SOLD_FRIEND_SHOP_SLOT_P4_C :=	0xBABABA

InitShopCoords() {
    global APP_SCALE
    ;
    global SHOP_SLOT_WIDTH          := Ceil( APP_SCALE*SHOP_SLOT_WIDTH )
    global SHOP_SLOT_HEIGHT         := Ceil( APP_SCALE*SHOP_SLOT_HEIGHT )  
    global SHOP_SLOT_DIFF_X         := Ceil( APP_SCALE*SHOP_SLOT_DIFF_X )
    global SHOP_SLOT_1_X            := Ceil( AC2SC(SHOP_SLOT_1_X, 0) )     
    global SHOP_SLOT_1_Y            := Ceil( AC2SC(SHOP_SLOT_1_Y, 1) )
    ;
    global SHOP_ALIGNMENT_REF_X     := Ceil( AC2SC(SHOP_ALIGNMENT_REF_X, 0) )
    global SHOP_ALIGNMENT_REF_Y     := Ceil( AC2SC(SHOP_ALIGNMENT_REF_Y, 1) )
    global SHOP_ALIGNMENT_DIFF_X    := Ceil( APP_SCALE*SHOP_ALIGNMENT_DIFF_X ) 
    ;
    global SHOP_SLOT_ON_SALE_P1_X   := Ceil( AC2SC(SHOP_SLOT_ON_SALE_P1_X, 0) )
    global SHOP_SLOT_ON_SALE_P1_Y   := Ceil( AC2SC(SHOP_SLOT_ON_SALE_P1_Y, 1) )
    global SHOP_SLOT_ON_SALE_P2_X   := Ceil( AC2SC(SHOP_SLOT_ON_SALE_P2_X, 0) )
    global SHOP_SLOT_ON_SALE_P2_Y   := Ceil( AC2SC(SHOP_SLOT_ON_SALE_P2_Y, 1) )
    global SHOP_SLOT_ON_SALE_P3_X   := Ceil( AC2SC(SHOP_SLOT_ON_SALE_P3_X, 0) )
    global SHOP_SLOT_ON_SALE_P3_Y   := Ceil( AC2SC(SHOP_SLOT_ON_SALE_P3_Y, 1) )
    global SHOP_SLOT_ON_SALE_P4_X   := Ceil( AC2SC(SHOP_SLOT_ON_SALE_P4_X, 0) )
    global SHOP_SLOT_ON_SALE_P4_Y   := Ceil( AC2SC(SHOP_SLOT_ON_SALE_P4_Y, 1) )
    ;
    global SHOP_SLOT_1_PRICETAG_X   := Ceil( AC2SC(SHOP_SLOT_1_PRICETAG_X, 0) )
    global SHOP_SLOT_1_PRICETAG_Y   := Ceil( AC2SC(SHOP_SLOT_1_PRICETAG_Y, 1) )
    ;
    global SHOP_SLOT_EMPTY_P1_X :=	Ceil( AC2SC(SHOP_SLOT_EMPTY_P1_X, 0) )
    global SHOP_SLOT_EMPTY_P1_Y :=	Ceil( AC2SC(SHOP_SLOT_EMPTY_P1_Y, 1) )
    global SHOP_SLOT_EMPTY_P2_X :=	Ceil( AC2SC(SHOP_SLOT_EMPTY_P2_X, 0) )
    global SHOP_SLOT_EMPTY_P2_Y :=	Ceil( AC2SC(SHOP_SLOT_EMPTY_P2_Y, 1) )
    global SHOP_SLOT_EMPTY_P3_X :=	Ceil( AC2SC(SHOP_SLOT_EMPTY_P3_X, 0) )
    global SHOP_SLOT_EMPTY_P3_Y :=	Ceil( AC2SC(SHOP_SLOT_EMPTY_P3_Y, 1) )
    global SHOP_SLOT_EMPTY_P4_X :=	Ceil( AC2SC(SHOP_SLOT_EMPTY_P4_X, 0) )
    global SHOP_SLOT_EMPTY_P4_Y :=	Ceil( AC2SC(SHOP_SLOT_EMPTY_P4_Y, 1) )
    ;    
    global SHOP_DRAG_Y         := Ceil( AC2SC(SHOP_DRAG_Y, 1) )
    global SHOP_DRAG_DB        := Ceil( APP_SCALE*SHOP_DRAG_DB )
    global SHOP_DRAG_REV_X     := Ceil( APP_SCALE*SHOP_DRAG_REV_X )
    global SHOP_DRAG_REV_P1_X  := Ceil( AC2SC(SHOP_DRAG_REV_P1_X, 0) )  
    global SHOP_DRAG_REV_P1_Y  := Ceil( AC2SC(SHOP_DRAG_REV_P1_Y, 1) )  
    ;
    global SHOP_SLOT_SOLD_P1_X := Ceil( AC2SC(SHOP_SLOT_SOLD_P1_X, 0) )
    global SHOP_SLOT_SOLD_P1_Y := Ceil( AC2SC(SHOP_SLOT_SOLD_P1_Y, 1) )
    global SHOP_SLOT_SOLD_P2_X := Ceil( AC2SC(SHOP_SLOT_SOLD_P2_X, 0) )
    global SHOP_SLOT_SOLD_P2_Y := Ceil( AC2SC(SHOP_SLOT_SOLD_P2_Y, 1) )
    global SHOP_SLOT_SOLD_P3_X := Ceil( AC2SC(SHOP_SLOT_SOLD_P3_X, 0) )
    global SHOP_SLOT_SOLD_P3_Y := Ceil( AC2SC(SHOP_SLOT_SOLD_P3_Y, 1) )
    global SHOP_SLOT_SOLD_P4_X := Ceil( AC2SC(SHOP_SLOT_SOLD_P4_X, 0) )
    global SHOP_SLOT_SOLD_P4_Y := Ceil( AC2SC(SHOP_SLOT_SOLD_P4_Y, 1) )
    ;    
    global SHOP_SLOT_CORN_P1_X := Ceil( AC2SC(SHOP_SLOT_CORN_P1_X, 0) )
    global SHOP_SLOT_CORN_P1_Y := Ceil( AC2SC(SHOP_SLOT_CORN_P1_Y, 1) )
    global SHOP_SLOT_CORN_P2_X := Ceil( AC2SC(SHOP_SLOT_CORN_P2_X, 0) )
    global SHOP_SLOT_CORN_P2_Y := Ceil( AC2SC(SHOP_SLOT_CORN_P2_Y, 1) )
    global SHOP_SLOT_CORN_P3_X := Ceil( AC2SC(SHOP_SLOT_CORN_P3_X, 0) )
    global SHOP_SLOT_CORN_P3_Y := Ceil( AC2SC(SHOP_SLOT_CORN_P3_Y, 1) )
    global SHOP_SLOT_CORN_P4_X := Ceil( AC2SC(SHOP_SLOT_CORN_P4_X, 0) )
    global SHOP_SLOT_CORN_P4_Y := Ceil( AC2SC(SHOP_SLOT_CORN_P4_Y, 1) )
    ;       
    global RED_X_SHOP_X    := Ceil( AC2SC(RED_X_SHOP_X, 0) )     
    global RED_X_SHOP_Y    := Ceil( AC2SC(RED_X_SHOP_Y, 1) )
    ;
    global RED_X_SILO_BARN_FULL_X    := Ceil( AC2SC(RED_X_SILO_BARN_FULL_X, 0) )     
    global RED_X_SILO_BARN_FULL_Y    := Ceil( AC2SC(RED_X_SILO_BARN_FULL_Y, 1) )
    ;
    global BTN_AD_X            := Ceil( AC2SC(BTN_AD_X, 0) )   
    global BTN_AD_Y            := Ceil( AC2SC(BTN_AD_Y, 1) )
    global BTN_AD_DO_X         := Ceil( AC2SC(BTN_AD_DO_X, 0) )      
    global BTN_AD_DO_Y         := Ceil( AC2SC(BTN_AD_DO_Y, 1) )
    global BTN_AD_CLOSE_X      := Ceil( AC2SC(BTN_AD_CLOSE_X, 0) )  
    global BTN_AD_CLOSE_Y      := Ceil( AC2SC(BTN_AD_CLOSE_Y, 1) )
    global SHOP_AD_X           := Ceil( AC2SC(SHOP_AD_X, 0) ) 
    global SHOP_AD_Y           := Ceil( AC2SC(SHOP_AD_Y, 1) )
    ;
    global SILO_BARN_FULL_1_X := Ceil( AC2SC( SILO_BARN_FULL_1_X, 0) )
    global SILO_BARN_FULL_1_Y := Ceil( AC2SC( SILO_BARN_FULL_1_Y, 1) )
    global SILO_BARN_FULL_2_X := Ceil( AC2SC( SILO_BARN_FULL_2_X, 0) )
    global SILO_BARN_FULL_2_Y := Ceil( AC2SC( SILO_BARN_FULL_2_Y, 1) )
    global SILO_BARN_FULL_3_X := Ceil( AC2SC( SILO_BARN_FULL_3_X, 0) )
    global SILO_BARN_FULL_3_Y := Ceil( AC2SC( SILO_BARN_FULL_3_Y, 1) )
    global SILO_BARN_FULL_4_X := Ceil( AC2SC( SILO_BARN_FULL_4_X, 0) )
    global SILO_BARN_FULL_4_Y := Ceil( AC2SC( SILO_BARN_FULL_4_Y, 1) )
    ;
    global SOLD_FRIEND_SHOP_SLOT_P1_X := Ceil( AC2SC( SOLD_FRIEND_SHOP_SLOT_P1_X, 0) )
    global SOLD_FRIEND_SHOP_SLOT_P1_Y := Ceil( AC2SC( SOLD_FRIEND_SHOP_SLOT_P1_Y, 1) )
    global SOLD_FRIEND_SHOP_SLOT_P2_X := Ceil( AC2SC( SOLD_FRIEND_SHOP_SLOT_P2_X, 0) )
    global SOLD_FRIEND_SHOP_SLOT_P2_Y := Ceil( AC2SC( SOLD_FRIEND_SHOP_SLOT_P2_Y, 1) )
    global SOLD_FRIEND_SHOP_SLOT_P3_X := Ceil( AC2SC( SOLD_FRIEND_SHOP_SLOT_P3_X, 0) )
    global SOLD_FRIEND_SHOP_SLOT_P3_Y := Ceil( AC2SC( SOLD_FRIEND_SHOP_SLOT_P3_Y, 1) )
    global SOLD_FRIEND_SHOP_SLOT_P4_X := Ceil( AC2SC( SOLD_FRIEND_SHOP_SLOT_P4_X, 0) )
    global SOLD_FRIEND_SHOP_SLOT_P4_Y := Ceil( AC2SC( SOLD_FRIEND_SHOP_SLOT_P4_Y, 1) )
}
; ------------------------------------------------------------------------------------------------

; ------------------------------------------------------------------------------------------------
; Declaration of variables to be dynamically scaled.
;  Update init function after adding a variable.

;
SELECT_SELL_TYPE_X := 165
SELECT_SELL_TYPE_SILO_Y := 195
SELECT_SELL_TYPE_BARN_Y := 315
SELECT_SELL_TYPE_HELPERS_Y := 435

; Items to sell Left column is 1-4, right column is 5-8
SELL_ITEM_1_X       := 310
SELL_ITEM_1_Y       := 194
SELL_ITEM_DIFF_X    := 181  ; 180 egentligen men måste smootha färgerna.
                            ; Nu är det exakt på pixeln, och även med tolerans så kan det
                            ; skilja svart och vitt.
SELL_ITEM_DIFF_Y    := 104
; Advertise when adding item to sell
BTN_SELL_AD_X       := 708
BTN_SELL_AD_Y       := 472
BTN_PRICE_MAX_X     := 855
BTN_PRICE_MAX_Y     := 325
BTN_PRICE_MIN_X     := 728
BTN_PRICE_MIN_Y     := BTN_PRICE_MIN_X
BTN_PRICE_DOWN_X    := 670
BTN_PRICE_DOWN_Y    := 270
BTN_PRICE_UP_X      := 911
BTN_PRICE_UP_Y      := BTN_PRICE_DOWN_Y
BTN_SELL_CLOSE_X    := 930
BTN_SELL_CLOSE_Y    := 90
BTN_PUT_ON_SALE_X   := 795
BTN_PUT_ON_SALE_Y   := 592
; Sell slot Goods profiles for goods to sell (the small icon) - relative to center of slot
DETECT_CORN_P1_X := 6
DETECT_CORN_P1_Y := -6
DETECT_CORN_P1_C := 0xF8EB1A
DETECT_CORN_P2_X := -30
DETECT_CORN_P2_Y := 31
DETECT_CORN_P2_C := 0x848800
DETECT_CORN_P3_X := -2
DETECT_CORN_P3_Y := 22
DETECT_CORN_P3_C := 0x949C03
DETECT_CORN_P4_X := -4
DETECT_CORN_P4_Y := -25
DETECT_CORN_P4_C := 0xFFF8B8
;
DETECT_CARROT_P1_X :=	270
DETECT_CARROT_P1_Y :=	210
DETECT_CARROT_P1_C :=	0xFFF8B8
DETECT_CARROT_P2_X :=	292
DETECT_CARROT_P2_Y :=	185
DETECT_CARROT_P2_C :=	0xFFF8B8
DETECT_CARROT_P3_X :=	309
DETECT_CARROT_P3_Y :=	226
DETECT_CARROT_P3_C :=	0xFFF8B8
DETECT_CARROT_P4_X :=	300
DETECT_CARROT_P4_Y :=	197
DETECT_CARROT_P4_C :=	0xFFDE00
;
DETECT_SOYBEAN_P1_X :=	745
DETECT_SOYBEAN_P1_Y :=	227
DETECT_SOYBEAN_P1_C :=	0xECEE6E
DETECT_SOYBEAN_P2_X :=	726
DETECT_SOYBEAN_P2_Y :=	216
DETECT_SOYBEAN_P2_C :=	0xFFF8B8
DETECT_SOYBEAN_P3_X :=	772
DETECT_SOYBEAN_P3_Y :=	229
DETECT_SOYBEAN_P3_C :=	0xFFF8B8
DETECT_SOYBEAN_P4_X :=	735
DETECT_SOYBEAN_P4_Y :=	181
DETECT_SOYBEAN_P4_C :=	0xFFF8B8
; Tricky. Checks only outside of it.
DETECT_WHEAT_P1_X :=	1639
DETECT_WHEAT_P1_Y :=	272
DETECT_WHEAT_P1_C :=	0xFFF8B8
DETECT_WHEAT_P2_X :=	1662
DETECT_WHEAT_P2_Y :=	287
DETECT_WHEAT_P2_C :=	0xFFF8B8
DETECT_WHEAT_P3_X :=	1661
DETECT_WHEAT_P3_Y :=	223
DETECT_WHEAT_P3_C :=	0xFFF8B8
DETECT_WHEAT_P4_X :=	1715
DETECT_WHEAT_P4_Y :=	222
DETECT_WHEAT_P4_C :=	0xFFF8B8


InitSellCoords() {
    global APP_SCALE
    ;
    global SELECT_SELL_TYPE_X          := Ceil( AC2SC(SELECT_SELL_TYPE_X, 0) )
    global SELECT_SELL_TYPE_SILO_Y     := Ceil( AC2SC(SELECT_SELL_TYPE_SILO_Y, 1) )
    global SELECT_SELL_TYPE_BARN_Y     := Ceil( AC2SC(SELECT_SELL_TYPE_BARN_Y, 1) )
    global SELECT_SELL_TYPE_HELPERS_Y  := Ceil( AC2SC(SELECT_SELL_TYPE_HELPERS_Y, 1) )
    ;
    global SELL_ITEM_1_X       := Ceil( AC2SC(SELL_ITEM_1_X, 0) )
    global SELL_ITEM_1_Y       := Ceil( AC2SC(SELL_ITEM_1_Y, 1) )
    global SELL_ITEM_DIFF_X    := Ceil( APP_SCALE*SELL_ITEM_DIFF_X )
    global SELL_ITEM_DIFF_Y    := Ceil( APP_SCALE*SELL_ITEM_DIFF_Y )
    ;
    global BTN_SELL_AD_X       := Ceil( AC2SC(BTN_SELL_AD_X, 0) )
    global BTN_SELL_AD_Y       := Ceil( AC2SC(BTN_SELL_AD_Y, 1) )
    global BTN_PRICE_MAX_X     := Ceil( AC2SC(BTN_PRICE_MAX_X, 0) )
    global BTN_PRICE_MAX_Y     := Ceil( AC2SC(BTN_PRICE_MAX_Y, 1) )
    global BTN_PRICE_MIN_X     := Ceil( AC2SC(BTN_PRICE_MIN_X, 0) )
    global BTN_PRICE_MIN_Y     := BTN_PRICE_MAX_Y
    global BTN_PRICE_DOWN_X    := Ceil( AC2SC(BTN_PRICE_DOWN_X, 0) )
    global BTN_PRICE_DOWN_Y    := Ceil( AC2SC(BTN_PRICE_DOWN_Y, 1) )
    global BTN_PRICE_UP_X      := Ceil( AC2SC(BTN_PRICE_UP_X, 0) )
    global BTN_PRICE_UP_Y      := BTN_PRICE_DOWN_Y
    global BTN_SELL_CLOSE_X    := Ceil( AC2SC(BTN_SELL_CLOSE_X, 0) )
    global BTN_SELL_CLOSE_Y    := Ceil( AC2SC(BTN_SELL_CLOSE_Y, 1) )
    global BTN_PUT_ON_SALE_X   := Ceil( AC2SC(BTN_PUT_ON_SALE_X, 0) )
    global BTN_PUT_ON_SALE_Y   := Ceil( AC2SC(BTN_PUT_ON_SALE_Y, 1) )
    ; These are app scaled - not screen position. They are origin based on sell slot 1.
    global DETECT_CORN_P1_X    := Ceil( APP_SCALE*DETECT_CORN_P1_X)
    global DETECT_CORN_P1_Y    := Ceil( APP_SCALE*DETECT_CORN_P1_Y)
    global DETECT_CORN_P2_X    := Ceil( APP_SCALE*DETECT_CORN_P2_X)
    global DETECT_CORN_P2_Y    := Ceil( APP_SCALE*DETECT_CORN_P2_Y)
    global DETECT_CORN_P3_X    := Ceil( APP_SCALE*DETECT_CORN_P3_X)
    global DETECT_CORN_P3_Y    := Ceil( APP_SCALE*DETECT_CORN_P3_Y)
    global DETECT_CORN_P4_X    := Ceil( APP_SCALE*DETECT_CORN_P4_X)
    global DETECT_CORN_P4_Y    := Ceil( APP_SCALE*DETECT_CORN_P4_Y)
    ;
    global DETECT_CARROT_P1_X := Ceil( DETECT_CARROT_P1_X )
    global DETECT_CARROT_P1_Y := Ceil( DETECT_CARROT_P1_Y )
    global DETECT_CARROT_P2_X := Ceil( DETECT_CARROT_P2_X )
    global DETECT_CARROT_P2_Y := Ceil( DETECT_CARROT_P2_Y )
    global DETECT_CARROT_P3_X := Ceil( DETECT_CARROT_P3_X )
    global DETECT_CARROT_P3_Y := Ceil( DETECT_CARROT_P3_Y )
    global DETECT_CARROT_P4_X := Ceil( DETECT_CARROT_P4_X )
    global DETECT_CARROT_P4_Y := Ceil( DETECT_CARROT_P4_Y )
    ;
    global DETECT_SOYBEAN_P1_X := Ceil( DETECT_SOYBEAN_P1_X )
    global DETECT_SOYBEAN_P1_Y := Ceil( DETECT_SOYBEAN_P1_Y )
    global DETECT_SOYBEAN_P2_X := Ceil( DETECT_SOYBEAN_P2_X )
    global DETECT_SOYBEAN_P2_Y := Ceil( DETECT_SOYBEAN_P2_Y )
    global DETECT_SOYBEAN_P3_X := Ceil( DETECT_SOYBEAN_P3_X )
    global DETECT_SOYBEAN_P3_Y := Ceil( DETECT_SOYBEAN_P3_Y )
    global DETECT_SOYBEAN_P4_X := Ceil( DETECT_SOYBEAN_P4_X )
    global DETECT_SOYBEAN_P4_Y := Ceil( DETECT_SOYBEAN_P4_Y )
    ;
    global DETECT_WHEAT_P1_X := Ceil( DETECT_WHEAT_P1_X )
    global DETECT_WHEAT_P1_Y := Ceil( DETECT_WHEAT_P1_Y )
    global DETECT_WHEAT_P2_X := Ceil( DETECT_WHEAT_P2_X )
    global DETECT_WHEAT_P2_Y := Ceil( DETECT_WHEAT_P2_Y )
    global DETECT_WHEAT_P3_X := Ceil( DETECT_WHEAT_P3_X )
    global DETECT_WHEAT_P3_Y := Ceil( DETECT_WHEAT_P3_Y )
    global DETECT_WHEAT_P4_X := Ceil( DETECT_WHEAT_P4_X )
    global DETECT_WHEAT_P4_Y := Ceil( DETECT_WHEAT_P4_Y )
}
; ------------------------------------------------------------------------------------------------

; ------------------------------------------------------------------------------------------------
; Plant and harvest

; For Crop page 1 and position of crop amount relative to the center of the clicked field.
;  Requires the clicked field is:
;    * roughly in center screen.
;    * of full zoomed out screen.
;  If the field is off center, then the crop selection overlay is shifted a bit.

; ALL RELATIVE POSITIONS ARE AFFECTED BY ZOOM. 
;  Not so much. In x-pos almost nothing, but they are in y-pos. Moving up when zoomed in.

; Relative positions compared to the clicked field. 
;  New nbr is on arrow, so can use for color check. But then arrow pos need to sample for unknown screens in code.
;   So perhaps screen 1 is used to validate overlay, then screen selection by the indicators.
; Crops on selection  1
CROP_SELECT1_R1C1_X  :=  -70  ;	Top crop                    S1: Soybean
CROP_SELECT1_R1C1_Y  := -167  

CROP_SELECT1_R2C1_X  := -190  ; Middle left crop            S1: Sugar cane
CROP_SELECT1_R2C1_Y  :=  -97  
CROP_SELECT1_R2C2_X  :=  -39  ; Middle right crop           S1: Wheat
CROP_SELECT1_R2C2_Y  :=  -59  
	
CROP_SELECT1_R3C1_X  := -276  ; Lower left crop             S1: Carrot
CROP_SELECT1_R3C1_Y  :=   28  	
CROP_SELECT1_R3C2_X  := -129  ; Lower right crop            S1: Corn
CROP_SELECT1_R3C2_Y  :=   18  

CROP_SELECT_ARROW_C := 0xF1A200 ; An average of the arrow color.

; Relative positions compared to the CENTER OF the clicked field.
CROP_SELECT_SCREEN_SWITCH_X := -329  ; Crop screen switch
CROP_SELECT_SCREEN_SWITCH_Y := 81

CROPS_PER_OVERLAY_SCREEN    := 5 ; Constant, not scaled.
CROP_OVERLAY_SICKLE         := 1 ; Constant, not scaled.
CROP_OVERLAY_PROGRESS_BAR   := 2 ; Constant, not scaled.
CROP_OVERLAY_CROPS          := 3 ; Constant, not scaled.

; Relative positions compared to the clicked field.
CROP_SELECT_SCREEN_IND_C    := 0xFFFBDE ; The 'white' circle.
CROP_SELECT_SCREEN_IND1_X   := -270	; Crop screen indicator 1
CROP_SELECT_SCREEN_IND1_Y   := 80
CROP_SELECT_SCREEN_IND_DIFF := -34
	
SICKLE_REL_X := -94 ; Relative position of sickle from pressing a field.
SICKLE_REL_Y := -6
;
SICKLE_DETECT_P1_X := -91
SICKLE_DETECT_P1_Y :=  -9
SICKLE_DETECT_P2_X := -144
SICKLE_DETECT_P2_Y := -58
SICKLE_DETECT_P3_X := -125
SICKLE_DETECT_P3_Y := -79

SICKLE_DETECT_P1_X :=	-93         ; Arrow
SICKLE_DETECT_P1_Y :=	-10
SICKLE_DETECT_P1_C :=	0xF3A500	
SICKLE_DETECT_P2_X :=	-93         ; Arrow (duplicate)
SICKLE_DETECT_P2_Y :=	-10
SICKLE_DETECT_P2_C :=	0xF3A500	
SICKLE_DETECT_P3_X :=	-147        ; Sickle
SICKLE_DETECT_P3_Y :=	-58
SICKLE_DETECT_P3_C :=	0xE0DFE5	
SICKLE_DETECT_P4_X :=	-139    ; Sickle
SICKLE_DETECT_P4_Y :=	-73
SICKLE_DETECT_P4_C :=	0xF5F6F8	


; Detection of progress bar for maturing crops, relative to the clicked field.
CROP_PROGRESS_P1_X :=	-141
CROP_PROGRESS_P1_Y :=	169
CROP_PROGRESS_P1_C :=	0xFFFBD7
CROP_PROGRESS_P2_X :=	119
CROP_PROGRESS_P2_Y :=	169
CROP_PROGRESS_P2_C :=	0xFFFBD7
CROP_PROGRESS_P3_X :=	212
CROP_PROGRESS_P3_Y :=	125
CROP_PROGRESS_P3_C :=	0xFFF8B0
CROP_PROGRESS_P4_X :=	262
CROP_PROGRESS_P4_Y :=	151
CROP_PROGRESS_P4_C :=	0xFFFBD7

InitCropCoords() {
    GLOBAL APP_SCALE

    global CROP_SELECT1_R1C1_X  := Ceil( APP_SCALE*CROP_SELECT1_R1C1_X ) 
    global CROP_SELECT1_R1C1_Y  := Ceil( APP_SCALE*CROP_SELECT1_R1C1_Y ) 
    global CROP_SELECT1_R2C1_X  := Ceil( APP_SCALE*CROP_SELECT1_R2C1_X ) 
    global CROP_SELECT1_R2C1_Y  := Ceil( APP_SCALE*CROP_SELECT1_R2C1_Y ) 
    global CROP_SELECT1_R2C2_X  := Ceil( APP_SCALE*CROP_SELECT1_R2C2_X ) 
    global CROP_SELECT1_R2C2_Y  := Ceil( APP_SCALE*CROP_SELECT1_R2C2_Y ) 
    global CROP_SELECT1_R3C1_X  := Ceil( APP_SCALE*CROP_SELECT1_R3C1_X ) 
    global CROP_SELECT1_R3C1_Y  := Ceil( APP_SCALE*CROP_SELECT1_R3C1_Y ) 
    global CROP_SELECT1_R3C2_X  := Ceil( APP_SCALE*CROP_SELECT1_R3C2_X ) 
    global CROP_SELECT1_R3C2_Y  := Ceil( APP_SCALE*CROP_SELECT1_R3C2_Y ) 
    ;
    global CROP_SELECT_SCREEN_SWITCH_X := Ceil( APP_SCALE*CROP_SELECT_SCREEN_SWITCH_X ) 
    global CROP_SELECT_SCREEN_SWITCH_Y := Ceil( APP_SCALE*CROP_SELECT_SCREEN_SWITCH_Y ) 
    ;
    global CROP_SELECT_SCREEN_IND1_X   := Ceil( APP_SCALE*CROP_SELECT_SCREEN_IND1_X )
    global CROP_SELECT_SCREEN_IND1_Y   := Ceil( APP_SCALE*CROP_SELECT_SCREEN_IND1_Y )
    global CROP_SELECT_SCREEN_IND_DIFF := Ceil( APP_SCALE*CROP_SELECT_SCREEN_IND_DIFF )
    ;
    global SICKLE_REL_X := Ceil( APP_SCALE*SICKLE_REL_X )
    global SICKLE_REL_Y := Ceil( APP_SCALE*SICKLE_REL_Y )
    ;
    global SICKLE_DETECT_P1_X := Ceil( APP_SCALE*SICKLE_DETECT_P1_X )
    global SICKLE_DETECT_P1_Y := Ceil( APP_SCALE*SICKLE_DETECT_P1_Y )
    global SICKLE_DETECT_P2_X := Ceil( APP_SCALE*SICKLE_DETECT_P2_X )
    global SICKLE_DETECT_P2_Y := Ceil( APP_SCALE*SICKLE_DETECT_P2_Y )
    global SICKLE_DETECT_P3_X := Ceil( APP_SCALE*SICKLE_DETECT_P3_X )
    global SICKLE_DETECT_P3_Y := Ceil( APP_SCALE*SICKLE_DETECT_P3_Y )
    global SICKLE_DETECT_P4_X := Ceil( APP_SCALE*SICKLE_DETECT_P4_X )
    global SICKLE_DETECT_P4_Y := Ceil( APP_SCALE*SICKLE_DETECT_P4_Y )
    ;
    global CROP_PROGRESS_P1_X := Ceil( APP_SCALE*CROP_PROGRESS_P1_X )
    global CROP_PROGRESS_P1_Y := Ceil( APP_SCALE*CROP_PROGRESS_P1_Y )
    global CROP_PROGRESS_P2_X := Ceil( APP_SCALE*CROP_PROGRESS_P2_X )
    global CROP_PROGRESS_P2_Y := Ceil( APP_SCALE*CROP_PROGRESS_P2_Y )
    global CROP_PROGRESS_P3_X := Ceil( APP_SCALE*CROP_PROGRESS_P3_X )
    global CROP_PROGRESS_P3_Y := Ceil( APP_SCALE*CROP_PROGRESS_P3_Y )
    global CROP_PROGRESS_P4_X := Ceil( APP_SCALE*CROP_PROGRESS_P4_X )
    global CROP_PROGRESS_P4_Y := Ceil( APP_SCALE*CROP_PROGRESS_P4_Y )
}
; ------------------------------------------------------------------------------------------------


; ------------------------------------------------------------------------------------------------
; Declaration of variables to be dynamically scaled.

;  Update init function after adding a variable.
; Determine if app is at default position and zoomed in.
;  Clicks where the order board is, and detects it?
; 357, 423 när man går in på annan. nej. varierar.
BOARD_CORNER_IF_DEF_X   := 250    ;452 / 216    Efter en automatisk reload kan det variera.
BOARD_CORNER_IF_DEF_Y   := 514    ;403 / 534
BTN_BOARD_CLOSE_X       := 930
BTN_BOARD_CLOSE_Y       :=  80
BP1_X := 107
BP1_Y := 150
BP1_C := 0xD8B098       
BP2_X := 600
BP2_Y := 150
BP2_C := 0xD8B098       
BP3_X := 107
BP3_Y := 588
BP3_C := 0xC08770       ; Some variance is needed here.
BP4_X := 598
BP4_Y := 588
BP4_C := 0xC08C70       ; Some variance is needed here.

InitBoardCoords() {
    global APP_SCALE

    global BOARD_CORNER_IF_DEF_X   := Ceil( AC2SC(BOARD_CORNER_IF_DEF_X, 0) )    
    global BOARD_CORNER_IF_DEF_Y   := Ceil( AC2SC(BOARD_CORNER_IF_DEF_Y, 1) )  
    global BTN_BOARD_CLOSE_X       := Ceil( AC2SC(BTN_BOARD_CLOSE_X, 0) )
    global BTN_BOARD_CLOSE_Y       := Ceil( AC2SC(BTN_BOARD_CLOSE_Y, 1) )
    global BP1_X := Ceil( AC2SC(BP1_X, 0) )
    global BP1_Y := Ceil( AC2SC(BP1_Y, 1) )
    global BP2_X := Ceil( AC2SC(BP2_X, 0) )
    global BP2_Y := Ceil( AC2SC(BP2_Y, 1) )
    global BP3_X := Ceil( AC2SC(BP3_X, 0) )
    global BP3_Y := Ceil( AC2SC(BP3_Y, 1) )
    global BP4_X := Ceil( AC2SC(BP4_X, 0) )
    global BP4_Y := Ceil( AC2SC(BP4_Y, 1) )
}
; ------------------------------------------------------------------------------------------------


; At init and after scaling / moving - recalculate all positions and sizes.
InitAllCoords() {
    InitBoardCoords()
    InitGeneralCoords()
    InitSellCoords()
    InitShopCoords()
}
; ------------------------------------------------------------------------------------------------







; ------------------------------------------------------------------------------------------------
; GUI init
; Gui, +AlwaysOnTop +Disabled -SysMenu +Owner  ; +Owner avoids a taskbar button.
; Gui, +AlwaysOnTop +Disabled -SysMenu +Owner  ; +Owner avoids a taskbar button.
Gui, -SysMenu ; +Owner avoids a taskbar button.
Gui, Font, s9  ; Set a large font size (32-point).
msgInitRow := "Some text to display. Some text to display. Some text to display. Some text to display. Some text to display."
Gui, Add, Text, vGuiTxtRow1, %msgInitRow%
Gui, Add, Text, vGuiTxtRow2, %msgInitRow%
Gui, Add, Text, vGuiTxtRow3, %msgInitRow%
Gui, Add, Text, vGuiTxtRow4, %msgInitRow%
Gui, Add, Text, vGuiTxtRow5, %msgInitRow%
Gui, Add, Text, vGuiTxtRow6, %msgInitRow%
Gui, Add, Text, vGuiTxtRow7, %msgInitRow%
Gui, Add, Text, vGuiTxtRow8, %msgInitRow%
Gui, Add, Text, vGuiTxtRow9, %msgInitRow%
Gui, Add, Text, vGuiTxtRow10, %msgInitRow%
Gui, Add, Text, vGuiTxtRow11, %msgInitRow%
Gui, Add, Text, vGuiTxtRow12, %msgInitRow%
Gui, Add, Text, vGuiTxtRow13, %msgInitRow%
Gui, Add, Text, vGuiTxtRow14, %msgInitRow%
Gui, Add, Text, vGuiTxtRow15, %msgInitRow%
Gui, Add, Text, vGuiTxtRow16, %msgInitRow%
Gui, Add, Text, vGuiTxtRow17, %msgInitRow%
Gui, Add, Text, vGuiTxtRow18, %msgInitRow%
Gui, Add, Text, vGuiTxtRow19, %msgInitRow%
Gui, Add, Text, vGuiTxtMode, %msgInitRow%       ; Current mode.
Gui, Add, Text, vGuiTxtStep, %msgInitRow%       ; Current step.
Gui, Add, Text, vGuiTxtFunc0, %msgInitRow%      ; Output from First called function.
Gui, Add, Text, vGuiTxtFunc1, %msgInitRow%
Gui, Add, Text, vGuiTxtFunc2, %msgInitRow%
Gui, Add, Text, vGuiTxtFunc3, %msgInitRow%      ; Output from function called in this level.
Gui, Add, Text, vGuiTxtScale, %msgInitRow%      ; Game area scale factor, modifying max zoom out.
Gui, Add, Text, vGuiTxtAlignment, %msgInitRow%  ; Shop or otherwise used alignment, translating used coords.
Gui, Add, Text, vGuiTxtDbg, %msgInitRow%
;
Gui, Show, NoActivate, Hay Day Helper  ; NoActivate avoids deactivating the currently active window.

; Update GUI frequently.
SetTimer, guiTimer, 100, On

; ------------------------------------------------------------------------------------------------







; ------------------------------------------------------------------------------------------------
; Program init

; Any initial MsgBox must come before hotkey assignment.

screenInitialised := false
; Screen and scale initialisation.
if WinExist("LDPlayer") {
    WinActivate ; Use the window found by WinExist.
    MsgBox,,INITIALISE SCREEN,LDPlayer window found and activated (front).,2

    ; This gets window. x, y are always relative to the screen.
    WinGet, win_LDPlayer, ID, LDPlayer
    WinGetPos, winX, winY, winW, winH, ahk_id %win_LDPlayer%
}
else {
    msg := "Open and point inside app, then press enter to close this box."
    MsgBox, 0, INITIALISE SCREEN, %msg%

    ; Get mouse postion and window info
    MouseGetPos, mx, my, msWin, msCtrl
    ; This chooses an active area inside a window. x, y are always relative to the parent.
    ControlGetPos, ctrlX, ctrlY, ctrlW, ctrlH, %msCtrl%, ahk_id %msWin%
    ; This gets window. x, y are always relative to the screen.
    WinGetPos, winX, winY, winW, winH, ahk_id %msWin%
}

; Calculate coord info
;  Possibly redo and recalculate all hard coded Y values
;  to remove th 34 pixel header that was there when they were done.
;  Don't seem to be footer.
;  Then the client coordinates can easier be used - BUT now make win active 
;   (msgbox will probably mess up)
APP_SIZE_X          := winW
APP_SIZE_Y          := winH
APP_TOP_LEFT_X      := winX
APP_TOP_LEFT_Y      := winY
; For the app scale do not include header.
APP_SCALE           := (APP_SIZE_Y - APP_HEADER_Y) / (APP_SIZE_Y_NRM - APP_HEADER_Y)
APP_CENTER_X        := 0.5*APP_SIZE_X + APP_TOP_LEFT_X
APP_CENTER_Y        := 0.5*APP_SIZE_Y + APP_TOP_LEFT_Y
;
GAME_AREA_CENTER_X  := APP_CENTER_X
GAME_AREA_CENTER_Y  := 0.5*(APP_SIZE_Y - APP_HEADER_Y) + APP_HEADER_Y + APP_TOP_LEFT_Y
GAME_AREA_TOP_LEFT_X := APP_TOP_LEFT_X
GAME_AREA_TOP_LEFT_Y := APP_TOP_LEFT_Y + APP_HEADER_Y
; Scale all other defined sizes and positions
InitAllCoords()
screenInitialised := true

allowTick := true

; 
msg := "Center field px: " . g_CenterFieldScreenCoords_X . ", " . g_CenterFieldScreenCoords_Y
msg := msg . " field: " . g_RC_CenterField[1] . ", " . g_RC_CenterField[2]
dbgMsgBox(true, "Init", msg)
GuiControl,, GuiTxtRow19, %msg%

; Print info about window so user can verify it seems correct window found.
msg := ""
msg := msg . "Window coordinates initialilzed. Seems like correct window?"
msg := msg . "`n`nW: " . winW . ", H: " . winH
MsgBox,,INITIALISE SCREEN,%msg%,2


msg := ""
msg := msg . "Welcome! `n`nStart and stop with Mouse Back Button.`nExit app with SHIFT+X"
msg := msg . "`n`nKeys:"
msg := msg . "`nCTRL+SHIFT+B: Buy corn - must be in friend shop."
msg := msg . "`nCTRL+SHIFT+S: Sell corn - must be in home shop."
msg := msg . "`nSHIFT+A: Test."
msg := msg . "`nSHIFT+W: Compare two colors."
msg := msg . "`n`nThis box can stay open."
MsgBox 0, HAY DAY HELPER, %msg%

; ------------------------------------------------------------------------------------------------

; Hue
;   0 : Red
;  60 : Yellow
; 120 : Green
; 180 : Cyan
; 240 : Blue
; 300 : Magenta
;
; HayDay grass:
;   76, 83, 82
;   76, 92, 73
;   71, 88, 90  The really light green
;
; HayDay water:
;  190.8, 0.50, 0.60   Mid river
;  189.7, 0.47, 0.72   Lighter river at top edge
;  187.9, 0.40, 0.74   -"-
;  181.0, 0.40, 0.44   Darker area below
;  178.0, 0.38, 0.65   Sunbeam mid river
;  168.0, 0.35, 0.68   -"-
;
;  100, 0.01, 0.96     White ish, as on the boat
;  2.2, 1.0, 0.43      Reddish, as on the boat.
;  172.7, 0.36, 0.45   Boat shadow in river - Too similar to river except on Value.
;  191, 0.53, 0.4      -"-



; ------------------------------------------------------------------------------------------------
; Hotkey assignment

;
; shift+x - exit app
+x::
    Msgbox,,,Quit, 2
    ExitApp
; ----------------------------------------------------------


; shift+z - present pixel color
+z::
    MouseGetPos, x, y
    PixelGetColor, col, x, y, RGB
    hsv := Convert_RGBHSV(col)
    carr := ColToArr(col)
    msg := "RGB: " . carr[1] . " " . carr[2] . " " . carr[3] . "`n"
    msg := msg . "HSV: " . hsv[1] . " " . hsv[2] . " " . hsv[3]
    MsgBox,,,%msg%
    return
; ----------------------------------------------------------


;
;ctrl+shift+b : Buy all corn from current shop
^+b::
    dbgEnable := true
    dbgHeader := "AutoBuyItem"

    dbgMsgBox(dbgEnable, dbgHeader, "Started.")
    if ( IsInShop() > 0 ) {
        itemId := ITEM_ID_CORN
        maxCounts := 0
        res := AutoBuyItem( itemId, maxCounts )
        msg := "AutoBuyItem: " . res[1] . ", Counts: " . res[2]
        dbgMsgBox(dbgEnable, dbgHeader, msg)
    }
    else {
        dbgMsgBox(dbgEnable, dbgHeader, "Start from friend shop.")
    }
    return
; ----------------------------------------------------------

;
;ctrl+shift+s : Sell all corn when in my shop
^+s::
    dbgEnable := true
    dbgHeader := "SellAllItem"

    dbgMsgBox(dbgEnable, dbgHeader, "Started.")
    if ( IsInShop() > 0 ) {
        dbgPriceMod := -3
        dbgAdvertise := 1
        res := SellAllItem( ITEM_ID_CORN, PRICE_MAX, dbgPriceMod, dbgAdvertise )
        msg := "Nbr of sales: " . res
        dbgMsgBox(dbgEnable, dbgHeader, msg)
    }
    else {
        dbgMsgBox(dbgEnable, dbgHeader, "Start from home shop.")
    }
    return
; ----------------------------------------------------------


;
;ctrl+shift+d : Harvest a here configured area. Press field first to get the sickle.
^+d::
    ; Click manually to get overlay.
    MouseGetPos, x, y
    HarvestArea([x, y], [-8, -8], [0, 0])
    return
; ----------------------------------------------------------


;
;ctrl+shift+f : Plant a here configured area. Press field first to get the crop selections.
^+f::
    ; Click manually to get overlay.
    MouseGetPos, x, y
    PlantArea([x, y], [-8, -8], [0, 0], ITEM_ID_CHILI)
    return
; ----------------------------------------------------------


;
;ctrl+shift+q : Calculate the scale - need to be at reference position to start this.
^+q::
    res := InitialiseScrenCoordinates(true)
    msg := "InitialiseScrenCoordinates: " . res
    MsgBox,,,%msg%
    return
; ----------------------------------------------------------


; ctrl+shift+w compare 2 colors using similar, to see result
^+w::
    Msgbox, Move mouse to Color 1 then press Enter
    MouseGetPos, mx, my
    PixelGetColor, col1, mx, my, RGB
    
    Msgbox, Move mouse to Color 2 then press Enter
    MouseGetPos, mx, my
    PixelGetColor, col2, mx, my, RGB

    res := IsAlmostSameColor(col1, col2)
    msg := col1 . "`n"
    msg := msg . col2 . "`n"
    msg := msg . res
    MsgBox,, Similar, %msg%    
    return
; ----------------------------------------------------------


; ctrl+shift+c place mouse on ground commercial, watches all.
^+c::
    MouseGetPos, x, y
    res := WatchCommercialFromPos([x,y])
    msg := "WatchCommercialFromPos: " . res
    MsgBox,,,%res%
    return
; ----------------------------------------------------------


; Key / Mouse event start stops a global timer.
; All in "button" scope is global.
^+m::       ; ctrl+shft+m
    ; För att kunna använda en variabel så börja med ett % i anropet.
    ; Program will wait at the msgbox
    ; Msgbox with Abort/RetryIgnore + Exclamation but subtract 16 means Question, and timeout of 3 sec.
    if (!active) {
        ; Verify home screen (coords need to be initialised before this)
        if ( IsScreenHome() > 0 ) {
            ; This will start once the msgbox is clicked or gone 
            SetTimer, MyTimerTick, %TICK_TIME_MS%

            ; -------------------------------------------------
            ; Mode control init
            tempTime := A_Now

            ; Allow for advertising
            nextRunTimeForAdvert := tempTime

            ; Allow for harvest and sell
            nextRunTimeForFarming := tempTime
            ; -------------------------------------------------

            active := true
            mode := MODE_NONE
            mode_old := MODE_NONE

            snipingErrors := 0

            ; Welcome msg box that will auto close
            msgBoxOpt := 2+48
            MsgBox,,APP INFO,Helper status: STARTED, 1
        }
        else {
            MsgBox,,APP INFO,Start manually when you are in home screen.
        }
    }
    else {
        ; Button pressed while script was acitve. Stop script.
        active := false
        SetTimer, MyTimerTick, Off
        MsgBox,,APP INFO,Helper status: paused, 1
    }
    return
; ----------------------------------------------------------


;
; ctrl+shift+a - For various testing
^+a::
    if ( !screenInitialised ) {
        MsgBox,,,Screen is not initialized.
        return
    }

    res := Helper_IsShopSlotOnSale( 2, -3 )
    MsgBox,,,%res%
    return


    res := ShopScrollSlots( 3 )
    if ( res[1] >= 0 ) {
        MouseMoveDLL([SHOP_SLOT_1_X + res[2], SHOP_SLOT_1_Y])
    }
    alignment := res[2]
    msg := "drag result: " . res[1] . ", drag align: " . res[2]
    msgbox,,,%msg%

    screenSlot := 0
    loop, 4 {
        screenSlot++
        slotStatus := ShopGetMyItemStatusForSlot( screenSlot, alignment )
        msg := "slotstatus: " . screenSlot . ": " . slotStatus
        MsgBox,,,%msg%
    }
    return

    ScrollToFriend( 15 )
    return

    ScrollFriendSlots( 3 )
    return

    MouseGetPos, x, y
    res := SelectPlantOverlayScreenForCrop( [x,y], ITEM_ID_CORN )
    msg := "SelectPlantOverlayScreenForCrop: " . res
    MsgBox,,,%msg%
    return    
    
    
    MouseGetPos, x, y
    res := IsSickleOnOverlay([x, y])
    msg := "IsSickleOnOverlay: " . res
    MsgBox,,,%msg%
    return

    if ( IsScreenSiloBarnFull() > 0 ) {
        CloseScreenSiloBarnFull()
    }
    return

    res := IsScreenSiloBarnFull()
    MsgBox,,,%res%
    return


    GetRiverGrassEdgeBinSearch(20.0, RIVER_UPPER_REF_Y)
    return

    MouseGetPos, x, y
    GridPressAroundShopPos([x,y], 5, 0)
    return

    res := ScrollToFriend(8)
    msg := "ScrollToFriend: " . res
    msgbox,,,%res%
    return


    InitialiseScrenCoordinates(1, 1.01)
    res := DragFieldToCenter(RC_PLANT_RIGHT_OF_MANSION)
    msg := "DragFieldToCenter: " . res
    msgbox,,,%res%
    return


    res := IsScreenMansion()
    MsgBox,,,%res%
    CloseScreenMansion()
    return


    res := Helper_DragField(RC_FIELD_AREA_SELECT, g_RC_CenterField)
    return


    x_g_RC_CenterField := g_RC_CenterField
    g_RC_CenterField := RC_FIELD_AREA_SELECT
    res := IsFieldOnScreen(RC_SHOP)
    g_RC_CenterField := x_g_RC_CenterField
    msg := "IsFieldOnScreen: " . res
    msgbox,,,%res%
    return


    InitialiseScrenCoordinates(true)
    return

    ; Clcik manually to get sickle
    MouseGetPos, x, y
    HarvestArea([x, y], [-8, -8], [0, 0])
    return

    SweepArea([370, 770], 5, 10)
    return

    res := ShopScrollSlots(4)
    msg := "resutl / align: " . res[1] . " / " . res[2]
    MsgBox,,,%msg%
    return


    screenSlot := 1
    slotStatus := ShopGetMyItemStatusForSlot( screenSlot )
    mm := res
    if (slotStatus = SHOP_ITEM_SOLD ) {
        mm := "SHOP_ITEM_SOLD"
    }
    if (slotStatus = SHOP_ITEM_EMPTY ) {
        mm := "SHOP_ITEM_EMPTY"
    }
    if (slotStatus = SHOP_ITEM_HAS_AD ) {
        mm := "SHOP_ITEM_HAS_AD"
    }
    if (slotStatus = SHOP_ITEM_ON_SALE ) {
        mm := "SHOP_ITEM_ON_SALE"
    }
    msg := "ShopGetMyItemStatusForSlot: " . mm
    MsgBox,,,%msg%
    return


    res := IsItemAtSellSlot(2, ITEM_ID_CORN)
    msg := "IsItemAtSellSlot: " . res
    MsgBox,,,%res%
    return


    res := IsScreenHome()
    msg := "IsScreenHome: " . res
    MsgBox,,,%msg%
    return


    res := ShopAdvertiseExistingGoods()
    msg := "ShopAdvertiseExistingGoods: " . res
    MsgBox,,,%msg%
    return


    ; Use this scale modifier
    ; MsgBox,,,orig scale: %scale%
    scale := 1.08
    if (scale > 1.0) {
        scale := 1.0 + 0.8*(scale - 1.0)    ; There is something wrong with scale detect uaing 0.8 as modifier.
    }
    g_AppScaleExtra := scale
    ; MsgBox,,,recalc scale: %scale%
    
    ; Re-calculate coordinates. Needed for all map coordinates. Not for any shop coordinates.
    g_CenterFieldScreenCoords_X := g_CenterFieldScreenCoordsRaw_X * g_AppScaleExtra
    g_CenterFieldScreenCoords_Y := g_CenterFieldScreenCoordsRaw_Y * g_AppScaleExtra
    g_CenterFieldScreenCoords_X := Ceil( AC2SC(g_CenterFieldScreenCoords_X, 0) )
    g_CenterFieldScreenCoords_Y := Ceil( AC2SC(g_CenterFieldScreenCoords_Y, 1) )

    ; Position mouse on the center field in screen. This will be different x, y depending on the scale.
    if (1) {
        msg := "Moving mouse to the CENTER_FIELD_COORD. Scale is: " . scale
        MsgBox,,,%msg%, 3
        MouseMoveDLL([g_CenterFieldScreenCoords_X, g_CenterFieldScreenCoords_Y])
        Sleep, 2000
    }

    DragFieldToCenter( RC_FIELD_AREA_SELECT )
    return


    MouseGetPos, x, y
    res := GetOpenCropPlantSelectScreen([x, y])
    msg := "GetOpenCropPlantSelectScreen: " . res
    MsgBox,,,%msg%
    return



    ; Transform adds.
    ; coords := TransformRowColDiffCoord([-2, -7])
    ; msg := "diff: " . coords[1] . ", " . coords[2]
    ; Msgbox,,,%msg%
    ; return

    ; SweepArea([2779, 1397], 3, 7)
    ; return

    dbgEnable := true
    dbgHeader := "test"
    
    ; Go top left and find out scale. Needs to be done each reload or just returning to home screen.
    InitialiseScrenCoordinates()
    
    ; Drag the select field to center. Uses global config.
    ; TODO details.
    DragFieldToCenter( RC_FIELD_AREA_SELECT )

    ; Harvest or plant
    ; Calculate the corners of harvest area. None of these are necessarily the "select field area" 
    ;  that was dragged to the center.
    ; Origin for calculation is the "select filed area" field - which now is at the center coords.
    if ( dbgEnable ) {
        startCornerCoords := TransformRowColDiffCoord(RC_FIELD_AREA_REL_TOP_LEFT)
        startCornerCoords[1] += g_CenterFieldScreenCoords_X
        startCornerCoords[2] += g_CenterFieldScreenCoords_Y
        MouseMoveDLL(startCornerCoords)
        MsgBox,,,startCornerCoords, 1

        endCornerCoords := TransformRowColDiffCoord(RC_FIELD_AREA_REL_LOWER_RIGHT)
        endCornerCoords[1] += g_CenterFieldScreenCoords_X
        endCornerCoords[2] += g_CenterFieldScreenCoords_Y
        MouseMoveDLL(endCornerCoords)
        MsgBox,,,endCornerCoords, 1    
    }


    ; The start position is the "select field", even if it's in the middle of a large field. 
    ;  Click and deterimne field status.
    refPos := [g_CenterFieldScreenCoords_X, g_CenterFieldScreenCoords_Y]
    MouseMoveDLL(refPos)
    MouseClick, Left
    Sleep, 300
    fieldStatus := GetCropOverlayType(refPos)

    if ( fieldStatus = CROP_OVERLAY_SICKLE ) {
        res := HarvestArea(refPos, RC_FIELD_AREA_REL_TOP_LEFT, RC_FIELD_AREA_REL_LOWER_RIGHT)
    }
    return



    ; Scale verifiaction
    res := FindExtraAppScale()
    scale    := res[1]
    pixelPos := res[2]
    MsgBox,,,scale: %scale%  pixelPos %pixelPos%

    ; Verify the scale
    ; Use this scale modifier
    g_AppScaleExtra := scale

    ; Re-calculate coordinates. Needed for all map coordinates. Not for any shop coordinates.
    g_CenterFieldScreenCoordsRaw_X *= g_AppScaleExtra
    g_CenterFieldScreenCoordsRaw_Y *= g_AppScaleExtra
    g_CenterFieldScreenCoords_X := Ceil( AC2SC(g_CenterFieldScreenCoordsRaw_X, 0) )
    g_CenterFieldScreenCoords_Y := Ceil( AC2SC(g_CenterFieldScreenCoordsRaw_Y, 1) )

    MouseMoveDLL([g_CenterFieldScreenCoords_X, g_CenterFieldScreenCoords_Y])
    MsgBox,,,Done
    return

    ; Show the harvest area. Start with target field - it is now at the center coords.
    ; MouseMoveDLL(dragEndCoords)

    ; ; Move to the corners.
    ; ; The reference known coords is the center, bc the field reference is moved there.
    ; cornerCoord := TransformRowColDiffCoord(RC_FIELD_AREA_REL_TOP_LEFT)
    ; cornerCoord[1] += g_CenterFieldScreenCoords_X
    ; cornerCoord[2] += g_CenterFieldScreenCoords_Y
    ; MouseMoveDLL(cornerCoord)
    ; MsgBox,,, corner 1

    ; cornerCoord := TransformRowColDiffCoord(RC_FIELD_AREA_REL_LOWER_RIGHT)
    ; cornerCoord[1] += g_CenterFieldScreenCoords_X
    ; cornerCoord[2] += g_CenterFieldScreenCoords_Y
    ; MouseMoveDLL(cornerCoord)
    ; MsgBox,,, corner 2
    ; return

    ; All this handled 


    ; Transform adds.
    coords := TransformRowColDiffCoord([4, -6])
    X += coords[1]
    Y += coords[2]
    MouseMove, X, Y, 100
    return


    g_AppScaleExtra := 1.0293
    MouseGetPos, X, Y
    ; Transform adds.
    coords := TransformRowColDiffCoord([13, 10])
    X += coords[1]
    Y += coords[2]
    MouseMove, X, Y, 100
    return

    res := GetRiverBoatEdgeBinSearch()
    msg := "search result: " . res[1] . ", " . "boat pixeledge: " . res[2]
    MsgBox,,,%msg%
    return


    MouseGetPos, X, Y
    PixelGetColor, col, X, Y, RGB
    res := Convert_RGBHSV(col)
    msg := "H: " . res[1] . ", S: " . res[2] . ", V: " . res[3]
    msgbox,,,%msg%
    return


    MouseGetPos, X, Y
    ; Transform adds.
    coords := TransformRowColDiffCoord([14, 6])
    X += coords[1]
    Y += coords[2]
    MouseMove, X, Y, 100
    return

    ;
    ; Move screen diagonal. AHK seems to move diagonal anyway causing a strange twist at the end if not.
    X1 := APP_CENTER_X
    Y1 := APP_CENTER_Y
    
    MouseMoveDLL([X1, Y1])
    Sleep, 300
    d := -400
    dp := APP_SCALE*d
    X2 := X1 + dp
    Y2 := Y1 + dp/1.7
    Send {LButton down}
    Sleep, 300
    ;MouseMove, X2, Y2, 50
    MouseMoveDLL([X2, Y2])
    Sleep, 300    
    Send {LButton up}
    Sleep, 300    
    MouseMoveDLL([FIELD_REF_X, FIELD_REF_Y])
    return


    res := GetCropOverlayType([3000, 1000])
    msg := "GetCropOverlayType: " . res
    MsgBox,,,%msg%
    return

    res := IsCropProgressBar([3000, 1000])
    msg := "IsCropProgressBar: " . res
    MsgBox,,,%msg%

    res := GetOpenCropPlantSelectScreen([3000, 1000])
    msg := "GetOpenCropPlantSelectScreen: " . res
    MsgBox,,,%msg%

    res := GoToFieldAndPlant( 0, 11, 2, ITEM_ID_CORN)
    msg := "GoToFieldAndPlant: " . res
    MsgBox,,,%msg%
    return


    res := IsCropProgressBar([3000, 800])
    msg := "IsCropProgressBar: " . res
    MsgBox,,,%msg%
    return


    res := GoToFieldAndHarvest( 0, 11, 2 )
    msg := "GoToFieldAndPlant: " . res
    MsgBox,,,%msg%
    return


    res := PlantArea([3000, 1000], 11, 2, ITEM_ID_CORN)
    msg := "PlantArea: " . res
    MsgBox,,,%msg%
    return


    res := GoCenterReference()
    msg := res
    MouseMoveDLL([FIELD_REF_X, FIELD_REF_Y])
    dbgMsgBox(true, "GoCenterReference", msg)
    return


    res := GetOpenCropPlantSelectScreen([3000, 1000])
    msg := "GetOpenCropPlantSelectScreen: " . res
    MsgBox,,,%msg%
    return


    i := 0
    loop, 12 {
        i++
        res := GetOverlayRelativePosForCrop(i)
        msg := "itemId, pos: " . i . " / " . res[1] . ", " . res[2]
        MsgBox,,,%msg%
    }
    return


    i := 0
    loop, 12 {
        i++
        res := GetHarvestScreenNbrForCrop(i)
        msg := "itemId, scr: " . i . " / " . res
        MsgBox,,,%msg%
    }
    return






    ; Buy from shop and sell
    MsgBox,,,BuyFromShopAndSell: Started.,1
    if ( IsInShop() > 0 ) {
        itemId := ITEM_ID_CORN
        priceMaxOrMin := PRICE_MAX
        priceModifier := -3
        res := BuyFromShopAndSell( itemId, priceMaxOrMin, priceModifier )
        MsgBox,,,BuyFromShopAndSell: %res%
    }
    else {
        MsgBox,,,BuyFromShopAndSell: Start from friend shop., 2
    }
    return


    res := GoTopLeftReference()
    msg := res
    dbgMsgBox(true, "GoTopLeftReference", msg)
    return

    MouseGetPos, X, Y
    res := GetOpenCropPlantSelectScreen([X, Y])
    msg := res
    dbgMsgBox(true, "GetOpenCropPlantSelectScreen", msg)
    return


    Msgbox,,,testing search
    t0 := A_TickCount
    ; res := GetShopSlotOffset()
    res := GetShopSlotOffsetBinSearch()
    t1 := A_TickCount
    sts := res[1]
    align := res[2]
    ;
    tp := t1-t0
    msg := "Alignment: " . align . ", Ticks: " . tp
    Msgbox,,,%msg%
    return

    if ( IsTargetItemAtShopSlot(4, ITEM_ID_CARROT) > 0 ) {
        msgbox,,,IsCarrotAtShopSlot
    }
    else {
        msgbox,,,No CarrotAtShopSlot       
    }
    return

    res := IsSoldFriendShopSlot(4) 
    msgbox,,,IsSoldFriendShopSlot: %res%
    return

    res := GoToHome()
    msgbox,,,GoToHome: %res%
    return

    res := IsScreen(SCREEN_HOME)
    msgbox,,,SCREEN_HOME: %res%
    return

    ShowDetectionScreenHome()
    return

    res := IsScreen(SCREEN_FRIEND)
    msgbox,,,IsScreenFriend: %res%
    return

    res := IsHomeButtonVisible()
    msgbox,,,IsHomeButtonVisible: %res%
    return

    ShowDetectionHomeButton()
    return

    TryGetRidOfBlockingScreen()
    return

    ; Try the coord transform
    msgbox,,,TransformRowColDiffCoord: put mouse in a farmland and it will move 6 column and 5 rows
    MouseGetPos, x, y
    diff := TransformRowColDiffCoord([5, 6])
    x += diff[1]
    y += diff[2]
    MouseMove, x, y, 50
    return


    ; Go to home shop
    MsgBox,,,GoToHomeAndOpenShop: Started.,1
    res := GoToHomeAndOpenShop()
    MsgBox,,,GoToHomeAndOpenShop: %res%
    return

    
    ; Advertise existing goods.
    MsgBox,,,ShopAdvertiseExistingGoods: Started.,1
    if ( IsInShop() > 0 ) {
        res := ShopAdvertiseExistingGoods()
        MsgBox,,,ShopAdvertiseExistingGoods: %res%
    }
    else {
        MsgBox,,,ShopAdvertiseExistingGoods: Start from home shop., 2
    }
    return


    ; SellAllItem
    MsgBox,,,SellAllItem: Started.,1
    dbgPriceMod := -3
    dbgAdvertise := 1
    res := SellAllItem( ITEM_ID_CORN, PRICE_MAX, dbgPriceMod, dbgAdvertise )
    MsgBox, SellAllItem: %res%
    return


    ; AutoBuyItem
    MsgBox,,,AutoBuyItem: Started.,1
    itemId := ITEM_ID_CORN
    maxCounts := 0
    res := AutoBuyItem( itemId, maxCounts )
    msg := "AutoBuyItem: " . res[1] . "Counts: " . res[2]
    MsgBox, AutoBuyItem: %msg%
    return


    ; IsShopSiloBarnFullRedX
    res := IsShopSiloBarnFullRedX()
    MsgBox,,, IsShopSiloBarnFullRedX: %res%, 2
    res := IsScreenSiloBarnFull()
    MsgBox,,, IsScreenSiloBarnFull: %res%
    return


    ; GetShopSlotOffset
    res := GetShopSlotOffset()
    stat := res[1]
    diff := res[2]
    MsgBox,,,GetShopSlotOffset status %stat% and diff %diff%
    return

    ; IsTargetItemAtShopSlot
    res := IsTargetItemAtShopSlot( 2, ITEM_ID_CORN, diff )
    MsgBox, IsTargetItemAtShopSlot: %res%
    return

    ; res := EnterFriendShop( 12 )
    ; return

    ; res := ScrollToFriend(12)
    ; MsgBox,,,%res%
    ; return

    ; Denna är ok.
    ; res := ShopScrollSlots( SHOP_SLOTS_ON_SCREEN )
    ; MsgBox, ShopScrollSlots: %res%
    ; return

    ; res := IsEmptyShopSlot(1)
    ; MsgBox,,,IsEmptyShopSlot 1: %res%
    ; return

    res := SellItem( ITEM_ID_CORN, PRICE_MAX, dbgPriceMod, dbgAdvertise, dbgStartSellSlot)
    MsgBox, SellItem,Item sold from slot %res%
    return
    

    ; res := SellItemAtSlot( 1, PRICE_MAX, -3, 1 )
    ; MsgBox, Is SellItemAtSlot, %res%

    ; res := IsItemAtSellSlot(2, ITEM_ID_CORN)
    ; MsgBox, Is IsItemAtSellSlot, %res%
    ExitApp
    ; res := IsScreenHome()
    ; MsgBox, Is IsScreenHome(), %res%   
    ; res := IsScreenFriend()
    ; MsgBox, Is IsScreenFriend(), %res%   
    ; ExitApp
    return
; ----------------------------------------------------------



; ------------------------------------------------------------------------------------------------
; GUI Timer event 
guiTimer:

    msg := "Execution time / scan time: " . tickDiff . " / " . TICK_TIME_MS
    GuiControl,, GuiScanTime, %msg%

    return
; ------------------------------------------------------------------------------------------------

P1_X :=	1454
P1_Y :=	269
DIFF_X :=	713
DIFF_Y :=	357






; ------------------------------------------------------------------------------------------------
; Program Timer event (program is here)

; Program scan time of about 100 ms.
; If timer is On, this will be called even if main thread exits.
MyTimerTick:
    if ( !allowTick ) {
        return
    }


    tickCheck := A_TickCount
    timerTicks++

    dbgEnable := true
    dbgHeader := "MyTimerTick"
    dbgEnableWait := dbgEnable && true

    dbgMsgBox(dbgEnable, dbgHeader, "tick")

    ; ------------------------------------------------------------------------------------------
    ; Program control
    ;  Do regular harvest and sell in shop.
    ;  Advertise existing goods in case of full slots and thus no new sale added (with advertisement).
    ;  Snipe other shops for goodies.

    ; Print debug info in timer tick.
    if ( mod(timerTicks, 20) = 0 ) {
        dbgMsgBox(dbgEnable, dbgHeader, "20 cycles passed.")
    }

    ; -----------------------------------------------------------
    ; Select idle mode. Natural or forced.
    ; Initialise program control, abort all and go to idle mode.
    if ( mode = MODE_NONE || false ) {
        mode_temp := MODE_IDLE

        dbgEnable := true
        dbgHeader := "MODE_IDLE"

        ; Init mode
        if ( mode_old != mode_temp ) {
            dbgMsgBox(dbgEnable, dbgHeader, "Init.")
            mode_old := mode_temp
            mode := mode_temp

            ; Init code...
        }
    }

    ; Continuous mode
    ; TODO
    if ( mode = MODE_IDLE ) {
        msg := "Mode: " . ModeName_ToString(mode)
        GuiControl,, GuiTxtMode, %msg%
    }
    ; -----------------------------------------------------------


    ; -----------------------------------------------------------
    ; Select farming mode.
    ; Harvest timer has elapsed.
    tt := A_Now
    if ( FORCE_FARM_OR_SNIPE && mode = MODE_IDLE && (tt >= nextRunTimeForFarming) && !lockedInSnipeMode ) {
        dbgEnable := true
        dbgHeader := "MODE_FARMING"

        mode_temp := MODE_FARMING

        ; Init mode
        if ( mode_old != mode_temp ) {
            dbgMsgBox(dbgEnable, dbgHeader, "Init mode.")

            mode_old := mode_temp
            mode := mode_temp

            ; Init code... no. Keep states between runs unless cleared by intention.
        }
    }

    ; Continuous mode
    if ( mode = MODE_FARMING ) {
        dbgEnable := true
        dbgHeader := "MODE_FARMING"
        dbgEnableWait := dbgEnable && true

        msg := "Mode: " . ModeName_ToString(mode)
        GuiControl,, GuiTxtMode, %msg%

        msg := "Step: " . farmingStep 
        GuiControl,, GuiTxtStep, %msg%

        allowTick := false

        ; Continue to check steps in the current mode scan. Otherwise go to error handling at the end of the mode.
        continueModeScan := true


        ; STEP 0 - Go to shop and sell.

        ; XXX
        ; Need an extra sell in between, but it needs its own timer so it can be evenly spaced.
        ; Go to shop and sell
        if ( farmingStep = 0 ) {
            dbgMsgBox(dbgEnable, dbgHeader, "STEP 0 - Go to shop and sell")
            dbgWait(dbgEnableWait, dbgHeader, 1000)

            res := GoToHomeAndOpenShop()
            if ( res > 0 ) {
                SellAllItem(FIELD_CROP_ID, FIELD_CROP_PRICE, FIELD_CROP_PRICE_MOD, FIELD_CROP_PRICE_AD)

                ; Regardless of result, go to next step.
                farmingStep := 10

                msg := "Step: " . farmingStep 
                GuiControl,, GuiTxtStep, %msg%
            }
            else {
                continueModeScan := false
            }
        }


        ; STEP 10 - Initialise screen and scale.

        ; When this mode is called we can never be certain about the screen or zoom status, which are necessary 
        ;  to know for farming. Only going to shop to sell allows a quicker alignment to be used.
        if ( continueModeScan && farmingStep = 10 ) {
            dbgMsgBox(dbgEnable, dbgHeader, "STEP 10 - Initialise screen and scale.")
            dbgWait(dbgEnableWait, dbgHeader, 1000)

            res := InitialiseScrenCoordinates()
            if ( res <= 0 ) {
                dbgMsgBox(true, dbgHeader, "Error: Go to home.")
                dbgWait(dbgEnableWait, dbgHeader, 1000)
    
                continueModeScan := false
            }
            else {
                farmingStep := 12

                msg := "Step: " . farmingStep 
                GuiControl,, GuiTxtStep, %msg%
            }
        }


        ; STEP 12 - Drag the select field to center. 

        ; Drag the select field to center. Uses global config.
        ; TODO details.
        if ( continueModeScan && farmingStep = 12 ) {
            dbgMsgBox(dbgEnable, dbgHeader, "STEP 12 - Drag the select field to center.")
            dbgWait(dbgEnableWait, dbgHeader, 1000)

            res := DragFieldToCenter( RC_FIELD_AREA_SELECT )
            if ( res > 0 ) {
                farmingStep := 15

                msg := "Step: " . farmingStep 
                GuiControl,, GuiTxtStep, %msg%
            }
            else {
                ; Go back to init screen.
                farmingStep := 10
                continueModeScan := false

                msg := "Step: " . farmingStep 
                GuiControl,, GuiTxtStep, %msg%
            }
        }


        ; STEP 15 - Determine status of the reference field.

        if ( continueModeScan && farmingStep := 15 ) {
            dbgMsgBox(dbgEnable, dbgHeader, "STEP 15 - Determine status of the reference field.")
            dbgWait(dbgEnableWait, dbgHeader, 1000)

            ; Validate screen, handle errors / retries?
            if ( IsScreenHome() > 0 ) {
                ; The start position is the "select field", even if it's in the middle of a large field. 
                ;  Click and deterimne field status.
                refPos := [g_CenterFieldScreenCoords_X, g_CenterFieldScreenCoords_Y]

                ; Click the field to open the overlay.
                MouseMoveDLL(refPos)
                Sleep, 300
                MouseClick, Left
                Sleep, 600

                ; Try a grid pattern for alignment of target pattern.
                ; TODO Evaluate this. XXX Can lead to an invalid field plant and running out of crops? Happened...
                n := 1
                fieldStatus := -1
                pixelDiff := 2*APP_SCALE
                loop {
                    cn := ReturnGridSearchCoord(refPos, pixelDiff, n)
                    refPos_New := cn[1]
                    n_New := cn[2]

                    msg := "Trying grid: " . n . "xy: " . refPos_New[1] . ", " . refPos_New[2]
                    dbgMsgBox(dbgEnable, dbgHeader, msg)

                    fieldStatus := GetCropOverlayType(refPos_New, MAX_CROP_OVERLAY_SCREEN)
                    if ( fieldStatus > 0 ) {
                        ; Valid. Exit.
                        refPos := refPos_New
                        break
                    }
                    else if ( fieldStatus < 0 ) {
                        dbgMsgBox(true, dbgHeader, "Error: !IsScreenHome().")

                        ; Go back to init screen.
                        farmingStep := 10
                        continueModeScan := false

                        msg := "Step: " . farmingStep 
                        GuiControl,, GuiTxtStep, %msg%
                    }

                    dbgMsgBox(dbgEnable, dbgHeader, "Trying next coord to click...")

                    if ( n_New = 0 ) {
                        break
                    }
                    else {
                        n++
                    }
                }

                ; Evaluate the field status.
                if ( fieldStatus <= 0 ) {
                    ; Some error, unknown field status.
                    dbgMsgBox(true, dbgHeader, "Error: Unknown field status.")
                    dbgWait(dbgEnableWait, dbgHeader, 5000)

                    ; Go back to init screen.
                    farmingStep := 10
                    continueModeScan := false

                    msg := "Step: " . farmingStep 
                    GuiControl,, GuiTxtStep, %msg%
                }
                else if ( fieldStatus = CROP_OVERLAY_PROGRESS_BAR ) {
                    ; Crops not ready yet. 
                    nextRunTimeForFarming := A_Now

                    ; Go back to init screen. TODO - If we have checked all steps, then screen is not changed scale now.
                    farmingStep := 10
                    continueModeScan := false

                    msg := "Step: " . farmingStep 
                    GuiControl,, GuiTxtStep, %msg%
                }
                else if ( fieldStatus = CROP_OVERLAY_SICKLE ) {
                    ; Ready to harvest.
                    if ( !siloBarnFull ) {
                        farmingStep := 20

                        msg := "Step: " . farmingStep 
                        GuiControl,, GuiTxtStep, %msg%
                    }
                    else {
                        ; Go to shop and sell
                        farmingStep := 100

                        msg := "Step: " . farmingStep 
                        GuiControl,, GuiTxtStep, %msg%
                    }
                }
                else if ( fieldStatus = CROP_OVERLAY_CROPS ) {
                    ; Ready to plant.
                    farmingStep := 25

                    msg := "Step: " . farmingStep 
                    GuiControl,, GuiTxtStep, %msg%
                }
            }
            else {
                dbgMsgBox(true, dbgHeader, "Error: !IsScreenHome()")

                ; Go back to init screen.
                farmingStep := 10
                continueModeScan := false

                msg := "Step: " . farmingStep 
                GuiControl,, GuiTxtStep, %msg%
            }
        }


        ; STEP 20 - Harvest

        if ( continueModeScan && farmingStep = 20 ) {
            dbgMsgBox(dbgEnable, dbgHeader, "STEP 20 - Harvest.")
            dbgWait(dbgEnableWait, dbgHeader, 1000)

            ; Ready to harvest.
            res := HarvestArea(refPos, RC_FIELD_AREA_REL_TOP_LEFT, RC_FIELD_AREA_REL_LOWER_RIGHT)
            if ( res < 0 ) {
                msg := "Error: HarvestArea: " . res
                dbgMsgBox(true, dbgHeader, msg)
                dbgWait(dbgEnableWait, dbgHeader, 2000)

                ; TODO - Error unknown, so go back to init.
                farmingStep := 10
                continueModeScan := false

                msg := "Step: " . farmingStep 
                GuiControl,, GuiTxtStep, %msg%
            }
            else {
                ; After harvest the silo can be full. In this case we will not do any more harvest attempts until cleared.
                if ( res = 2 ) {
                    ; siloBarnFull := true ; XXX
                    dbgMsgBox(dbgEnable, dbgHeader, "Silo full after harvest.")
                    dbgWait(dbgEnableWait, dbgHeader, 1000)

                    if ( IsScreenSiloBarnFull() > 0 ) {
                        dbgMsgBox(dbgEnable, dbgHeader, "CloseScreenSiloBarnFull.")
                        dbgWait(dbgEnableWait, dbgHeader, 1000)

                        res := CloseScreenSiloBarnFull()

                        dbgMsgBox(dbgEnable, dbgHeader, "Closed.")
                        dbgWait(dbgEnableWait, dbgHeader, 1000)
                    }
                }

                ; Go to plant
                farmingStep := 25

                msg := "Step: " . farmingStep 
                GuiControl,, GuiTxtStep, %msg%            
            }

            ; Verify screen lost.
            if ( IsScreenHome() <= 0 ) {
                dbgMsgBox(true, dbgHeader, "Error: !IsScreenHome()")

                ; Go back to init screen.
                farmingStep := 10
                continueModeScan := false

                msg := "Step: " . farmingStep 
                GuiControl,, GuiTxtStep, %msg%
            }
        }


        ; STEP 25 - Plant

        if ( continueModeScan && farmingStep = 25 ) {
            ; Ready to plant.
            dbgMsgBox(dbgEnable, dbgHeader, "STEP 25 - Plant.")
            dbgWait(dbgEnableWait, dbgHeader, 2000)

            ; Confirm that screen and position was maintained by new click and overlay confirm.
            ; Click the field to open the overlay. Wait for flying crops to clear.
            MouseMoveDLL(refPos)
            Sleep, 1000
            Click
            Sleep, 300

            fieldStatus := GetCropOverlayType(refPos, MAX_CROP_OVERLAY_SCREEN)

            if ( fieldStatus = CROP_OVERLAY_CROPS ) {
                ; Ready to plant.
                dbgMsgBox(dbgEnable, dbgHeader, "Plant from here.")

                res := PlantArea(refPos, RC_FIELD_AREA_REL_TOP_LEFT, RC_FIELD_AREA_REL_LOWER_RIGHT, FIELD_CROP_ID)
                if ( res < 0 ) {
                    msg := "Error: PlantArea: " . res
                    dbgMsgBox(true, dbgHeader, msg)

                    ; Go back to init screen.
                    farmingStep := 10
                    continueModeScan := false

                    msg := "Step: " . farmingStep 
                    GuiControl,, GuiTxtStep, %msg%
                }
                else {
                    plantDone := true
                    siloBarnFull := false
                    nextRunTimeForFarming := A_Now
                    ; nextRunTimeForFarming += 220, seconds   ; Crop mature time minus the overhead time to center screen and move to field.
                    
                    ; For using the alwyas start with sell temporary.
                    nextRunTimeForFarming += 155, seconds   ; 175; Crop mature time minus the overhead time to center screen and move to field.

                    ; Go to shop and sell
                    farmingStep := 100

                    msg := "Step: " . farmingStep 
                    GuiControl,, GuiTxtStep, %msg%
                }
            }
        }


        ; STEP 100 - Sell in shop always - it will also advertise existing goods. 

        ; In theory there could be sold too much, but since the AutoSell can only see the top 8 crops, 
        ;  likely the target crop will still be available afterwards at a low amount.
        ; Problem is more commonly a full inventory and need to check shop often for new sales.
        if ( true ) {
            dbgMsgBox(dbgEnable, dbgHeader, "STEP 100 - Post sale.")
            dbgWait(dbgEnableWait, dbgHeader, 1000)

            if ( farmingStep = 100 ) {
                dbgMsgBox(dbgEnable, dbgHeader, "Came here on purpose.")
                dbgWait(dbgEnableWait, dbgHeader, 1000)
            }

            ; TODO redo - When releasing mouse then the crop growing can be selected, meaning overlay can
            ;  cover the shop coordinates so it's not clickable even if it is on screen.
            if ( farmingStep = 10 || true ) {
                ; It was determined that the home screen has moved.
                dbgMsgBox(dbgEnable, dbgHeader, "Taking the long way to shop.")
                dbgWait(dbgEnableWait, dbgHeader, 1000)

                res := GoToHomeAndOpenShop()
            }
            else {
                ; We can use the field grid coordinates for direct access.
                cfcoord := [g_CenterFieldScreenCoords_X, g_CenterFieldScreenCoords_Y]
                coords := GetScreenCoordFromRowCol(RC_SHOP, g_RC_CenterField, cfcoord)

                msg := "coords: " . vec2_toString(coords)
                dbgMsgBox(dbgEnable, dbgHeader, msg)
                ; dbgWait(dbgEnableWait, dbgHeader)
                msg := "cfcoord: " . vec2_toString(cfcoord)
                dbgMsgBox(dbgEnable, dbgHeader, msg)
                ; dbgWait(dbgEnableWait, dbgHeader)
                msg := "RC_SHOP: " . vec2_toString(RC_SHOP)
                dbgMsgBox(dbgEnable, dbgHeader, msg)
                ; dbgWait(dbgEnableWait, dbgHeader)
                msg := "g_RC_CenterField: " . vec2_toString(g_RC_CenterField)
                dbgMsgBox(dbgEnable, dbgHeader, msg)
                ; dbgWait(dbgEnableWait, dbgHeader)
                

                dbgMsgBox(dbgEnable, dbgHeader, "Entering shop without dragging to a reference.")
                dbgWait(dbgEnableWait, dbgHeader, 1000)

                MouseMoveDLL(coords)
                Sleep, 100
                Click
                Sleep, 500

                res := IsInShop()

                dbgMsgBox(dbgEnable, dbgHeader, "Should be in shop now.")
                dbgWait(dbgEnableWait, dbgHeader, 1000)
            }

            ; In shop. Sell.
            if ( res > 0 ) {
                res := SellAllItem(FIELD_CROP_ID, FIELD_CROP_PRICE, FIELD_CROP_PRICE_MOD, FIELD_CROP_PRICE_AD)
            }
            else {
                continueModeScan := false
            }

            ; Modify step only if sent here deliberately
            if ( farmingStep = 100 ) {
                farmingStep := 0

                msg := "Step: " . farmingStep 
                GuiControl,, GuiTxtStep, %msg%
            }
        }


        ; Exit mode
        ; Release mode when complete
        allowTick := true

        if ( !continueModeScan ) {
            dbgMsgBox(dbgEnable, dbgHeader, "Some error occured. Scheduling next run time directly. Keeping mode.")
            dbgWait(dbgEnableWait, dbgHeader, 1000)

            nextRunTimeForFarming := A_Now
        }
        else {
            dbgMsgBox(dbgEnable, dbgHeader, "All ok. Releasing mode.")
            dbgWait(dbgEnableWait, dbgHeader, 1000)

            mode := MODE_NONE
        }

        GoToHome()
    }
    ; -----------------------------------------------------------


    ; -----------------------------------------------------------
    ; Select advertise mode.
    ; Advertise timer has elapsed.
    if ( 0 && !lockedInSnipeMode ) {
        mode_temp := MODE_CREATE_ADVERT

        ; Init mode
        if ( mode_old != mode_temp ) {
            mode_old := mode_temp
            mode := mode_temp

            ; Init code...
        }
    }

    ; Continuous mode
    ; TODO
    if ( mode = MODE_CREATE_ADVERT ) {
        GuiTxtMode := "Mode: " . ModeName_ToString(mode)

        ; Exit mode
        ; Release mode when complete
        mode := MODE_NONE
    }
    ; -----------------------------------------------------------


    ; -----------------------------------------------------------
    ; Select sniping mode. Currently the default whenever possible.
    if ( !FORCE_FARM_OR_SNIPE && mode = MODE_IDLE && snipingErrors < MAX_SNIPING_RETRIES && true ) {
        mode_temp := MODE_SNIPING

        dbgEnable := true
        dbgHeader := "MODE_SNIPING"
        dbgEnableWait := dbgEnable && true

        ; Init mode
        if ( mode_old != mode_temp ) {
            mode_old := mode_temp
            mode := mode_temp

            dbgMsgBox(dbgEnable, dbgHeader, "Init mode.")

            shopNextCheckTime := A_Now
            siloBarnFull := false
            continueSniping := false
            lockedInSnipeMode := true   ; When entering mode it is locked until the first snipe 

            ; Init code...
            ; Select friend.
            msg := "friendCycleListIndex: " . friendCycleListIndex
            dbgMsgBox(dbgEnable, dbgHeader, msg)
            dbgWait(dbgEnableWait, dbgHeader, 1000)

            fd := friendCycleList[ friendCycleListIndex ]
            friendIndex := fd[1]
            snipeSlotAbsolute := fd[2]

            ; Go home to start from there
            dbgMsgBox(dbgEnable, dbgHeader, "Going home to start from there...")
            res := GoToHome()
            if ( res > 0 ) {
                continueSniping := true
            }
            else {
                msg := "Error: GoToHome(): " . res
                dbgMsgBox(dbgEnable, dbgHeader, msg)
            }

            ; Enter the friends shop
            ; Scroll to the snipe slot
            if ( continueSniping ) {
                dbgMsgBox(dbgEnable, dbgHeader, "GoToFriend.")
                res := GoToFriend( friendIndex )
                if ( res = 1 ) {
                    Sleep, 1000
                    res := EnterFriendShop( snipeSlotAbsolute )
                    snipeSlot := res[1]
                    alignment := res[2]
                    if ( snipeSlot > 0 ) {
                        ; Indicate mouse once on slot so user can validate.
                        ;  The actual snipeslot for pressing is calculated once more, beacuse the snipe is
                        ;  "press shop slot"
                        snipeCoords := Helper_GetClickCoordForShopSlot( snipeSlot )
                        snipeCoords[1] += alignment
                        x := snipeCoords[1]
                        y := snipeCoords[2]
                        MouseMove, x, y
                        dbgMsgBox(true, dbgHeader, "Showing snipe pos.")
                        Sleep, 5
                        
                        continueSniping := true
                        snipeLastStartTime := A_Now
                        enableTrigger := true
                        firstTimeInShop := true
                        friendLastActiveTime := A_Now
                        friendIdleTime := 0
                        slotColors_mem := SampleShopSlotColors()

                        dbgMsgBox(dbgEnable, dbgHeader, "Init done.")
                    }
                }
                else if ( res = -1 ) {
                    ; At friend, but could not open shop.
                    ; TODO - Where recover from this?
                    dbgMsgBox(dbgEnable, dbgHeader, "Error: GoToFriend: At friend, but could not open shop.")
                }
                else if ( res = -2 ) {
                    ; Could not open the friend bar.
                    ; TODO - Where recover from this?
                    dbgMsgBox(dbgEnable, dbgHeader, "Error: GoToFriend: Could not open the friend bar..")
                }
                else {
                    ; Other error
                    ; TODO - Where recover from this?
                    dbgMsgBox(dbgEnable, dbgHeader, "Error: GoToFriend: Other error.")
                }
            }
        }
    }

    ; Continuous mode
    if ( mode = MODE_SNIPING ) {
        ; Call until error.
        msg := ModeName_ToString(mode)
        GuiControl,, GuiTxtMode, %msg%

        ; TODO make step - or not. Steps could release code to main scan, but since some areas should
        ;  be done without risk of screen interrupt, a "locking semaphore would be needed in that case.

        ; Regurarly check if still in shop, every 60s.
        if ( continueSniping ) {
            if ( A_Now > shopNextCheckTime ) {
                dbgMsgBox(dbgEnable, dbgHeader, "A_Now > shopNextCheckTime")
                shopNextCheckTime += 60, seconds
                if ( IsInShop() <= 0 ) {
                    dbgMsgBox(true, dbgHeader, "Error: Not in shop.")
                    snipingErrors++
                    continueSniping := false
                }
            }
        }

        ; Check when there is some activity or new sales. Reset the activity timeout.
        ;  Color match expected to be identical.
        if ( continueSniping ) {
            detectionAtSnipeSlot := false

            slotColors := SampleShopSlotColors()
            anyChange := false
            msg := ""
            i := 0
            loop, 4 {
                i++
                if ( slotColors[i] != slotColors_mem[i] ) {
                    msg := msg . i . ", "

                    anyChange := true
                    slotColors_mem[i] := slotColors[i]

                    if ( i = snipeSlot ) {
                        detectionAtSnipeSlot := true
                        MsgBox,,,detectionAtSnipeSlot,1
                    }
                }
            }

            if ( anyChange ) {
                msgChangeDetect := "Change detected in screen slots: " . msg
                dbgMsgBox(dbgEnable, dbgHeader, msgChangeDetect)

                friendLastActiveTime := A_Now
            }

            friendIdleTime := A_Now
            friendIdleTime -= friendLastActiveTime, seconds

            ; Change friend shop at inactivity.
            if ( friendIdleTime > 12*60 ) {
                dbgMsgBox(dbgEnable, dbgHeader, "Leaving due to no activity in shop for a long time.")
                continueSniping := false
            }

            ; Check how long there has been no snipe since this round started. If > 6 minutes and
            ;  corn there was no loot this time. Time is varying... 6-8 minutes normal.
            snipeTimeDiff := A_Now
            snipeTimeDiff -= snipeLastStartTime, seconds
        }


        ; Take a closer look at trigger at the selected snipe position.
        ; Trigger: Goods on sale.
        if ( continueSniping ) {
            trigger := false
            if ( enableTrigger ) {
                ; TODO - The default on sale detection is rather slow. Consider a faster, yet safe, detection for snipe.
                ; On the other hand it is also desired not sniping a known crop.
                ; Also, to not miss a snipe when entering the shop, the search must be done regardless of change
                ;  detection.

                ; MsgBox,,,In enable trigger
                if ( firstTimeInShop || detectionAtSnipeSlot ) {
                    msg := "In detection / first. Detect: " . detectionAtSnipeSlot . ", first: " . firstTimeInShop . ", align: " . alignment
                    ; MsgBox,,,%msg%
                    dbgMsgBox(dbgEnable, dbgHeader, msg)

                    ; First time enter shop check if item is on sale on snipe slot.
                    if ( firstTimeInShop ) {
                        ; MsgBox,,,In firstTime
                        firstTimeInShop := false
                        trigger := Helper_IsShopSlotOnSale( snipeSlot, alignment )
                    }
                    else if ( detectionAtSnipeSlot ) {
                        ; Check just one point of the Goods on sale for speed.
                        x := SHOP_SLOT_ON_SALE_P1_X + (snipeSlot-1)*SHOP_SLOT_DIFF_X + alignment
                        y := SHOP_SLOT_ON_SALE_P1_Y
                        PixelGetColor, col, x, y, RGB
                        trigger := IsAlmostSameColor(col, SHOP_SLOT_ON_SALE_P1_C)

                        ; msg := "tt: " . trigger
                        ; MsgBox,,,%msg%
                    }
                }
            } 
            else {
                ; No trigger allowed. Re-enable if possible. It is also enabled when switching shop.
                if ( IsSoldFriendShopSlot(snipeSlot, alignment) > 0 ) {
                    enableTrigger := true
                    dbgMsgBox(dbgEnable, dbgHeader, "Sniping re-enabled due to item sold.")
                }
                else if ( Helper_IsShopSlotEmpty(snipeSlot, alignment) > 0 ) {
                    enableTrigger := true
                    dbgMsgBox(dbgEnable, dbgHeader, "Sniping re-enabled due to empty slot.")
                }                    
            }
        }

        ; Cancel the trigger if it is an item not worth sniping.
        ; NOTE: This increases possibly long time before detection to click.
        if ( continueSniping ) {
            if ( trigger ) {
                dbgMsgBox(dbgEnable, dbgHeader, "Trigger: item on sale. Checking if unbuyable item.")

                ; Log before potential clear.
                triggerNewItems++

                ; Rule out some possibly common false triggers, and stop looking from now on.
                if ( IsTargetItemAtShopSlot(snipeSlot, ITEM_ID_CORN, alignment) > 0 ) {
                    dbgMsgBox(dbgEnable, dbgHeader, "Sniping disabled due to corn detection.")
                    trigger := false
                    enableTrigger := false
                }
                else if ( IsTargetItemAtShopSlot(snipeSlot, ITEM_ID_CARROT, alignment) > 0 ) {
                    dbgMsgBox(dbgEnable, dbgHeader, "Sniping disabled due to carrot detection.")
                    trigger := false
                    enableTrigger := false
                }
            }
        }

        ; TRIGGER - Handle the purchase.
        if ( continueSniping ) {
            if ( trigger ) {
                snipesDone++
                snipeLastStartTime := A_Now
                lockedInSnipeMode := false

                dbgMsgBox(dbgEnable, dbgHeader, "Snipe trigger.")

                ; Move the mouse and click, but return it again to allow for usage in other applications.
                MouseGetPos, mouseX, mouseY
                PressShopSlot( snipeSlot )
                MouseMove, mouseX, mouseY, 0
                Sleep, 500

                ; After the trigger, no matter reason, see if it was a click mistake 
                if ( IsInShop() <= 0 ) {
                    dbgMsgBox(true, dbgHeader, "Error: Not in shop after snipe.")
                    snipingErrors++
                    if ( IsScreenSiloBarnFull() > 0 ) {
                        dbgMsgBox(true, dbgHeader, "Silo barn full.")
                        siloBarnFull := true
                    }
                    continueSniping := false
                    ; break
                    ; TODO - Where recover from this?
                }
                else {
                    ; Verify that it was sold. One time someone put a high level fucking ananas on sale.
                    if ( IsSoldFriendShopSlot(snipeSlot, alignment) <= 0 ) {
                        ; Not sold. Unbuyable item?
                        dbgMsgBox(dbgEnable, dbgHeader, "Sniping disabled due to item not sold.")
                        enableTrigger := false
                    }
                }

                ; TODO TEST
                ; Go to next friend to snipe
                if ( cycleFriendsAfterSnipe ) {
                    continueSniping := false
                    ; CloseShop()
                    ; break
                }

                ; Sample new reference colors after the snipe.
                slotColors_mem := SampleShopSlotColors()
            }
        }

        ; Lock mode if close to a snipe on order to prevent any other mode from starting.
        ; Use 4 minutes for the usual 5 minute shop update time if corn.
        if ( continueSniping ) {
            lockedInSnipeMode := snipeTimeDiff > 240 
        }
        else {
            lockedInSnipeMode := false
        }


        ; Exit mode due to error or normal. 
        ; TODO make steps
        if ( !continueSniping ) {
            dbgMsgBox(dbgEnable, dbgHeader, "!continueSniping.")

            ; Allow for some time to manually handle snipe, if online..
            ; TODO - make a "wait" step
            dbgMsgBox(dbgEnable, dbgHeader, "Waiting 15s before going back to shop.")
            Sleep, 15000 

            ; Exit mode (due to normal or error) - only here is "return" allowed.

            msg := "Exit sniping mode."
            dbgMsgBox(dbgEnable, dbgHeader, msg)

            ; Try to leave the mode in the Home screen.
            dbgMsgBox(dbgEnable, dbgHeader, "GoToHome.")
            res := GoToHome()

            msg := "GoToHome result: " . res
            dbgMsgBox(dbgEnable, dbgHeader, msg)

            ; TODO some length check here. A separate list also. One list w all friends. One with current snipes.
            ; Move to next friend.
            if ( cycleFriendsAfterSnipe ) {
                friendCycleListIndex++
                if ( friendCycleListIndex > frienCycleListSize ) {
                    friendCycleListIndex := 1
                }
                msg := "New friend index: " . friendCycleListIndex
                dbgMsgBox(dbgEnable, dbgHeader, msg)
                dbgWait(dbgEnableWait, dbgHeader, 1000)
            }

            ; Release mode when complete
            ; Mode NONE will trigger Init of the sniping mode when re-entered.
            mode := MODE_NONE
        }


        ;----------------------------------------------------------------------
        ; Update GUI data.
        if (1) {
            ; FormatTime, var2, %var1%, yyyy-MM-dd HH:mm:ss   ; A new varable is necessary.
            ; MsgBox, %var2%  ; The answer will be the date 31 days from now.

            currTick := A_TickCount             ; ms since script start, with 10ms resolution
            elapsedMs := currTick - lastTick
            lastTick := currTick

            ; For info
            msg := "Snipe pos: " . snipeCoords[1] . ", " . snipeCoords[2] . "`n"
            GuiControl,, GuiTxtRow1, %msg%
            
            msg := "Trigger enabled: " . enableTrigger
            GuiControl,, GuiTxtRow2, %msg%
            
            msg := "Total snipes: " . snipesDone 
            GuiControl,, GuiTxtRow3, %msg%

            msg := "Waiting at trigger for " . snipeTimeDiff . " sec."
            GuiControl,, GuiTxtRow4, %msg%

            msg := "Friend idle time: " . friendIdleTime . " sec."
            GuiControl,, GuiTxtRow5, %msg%

            td := A_Now
            td -= PROGRAM_START_TIME
            dhms := Convert_secToArrHMS(td)
            msg := "Script duration: " . dhms[2] . ":" . dhms[3] . ":" . dhms[4]
            GuiControl,, GuiTxtRow6, %msg%

            msg := "Snipes / hour: " . snipesDone / (td / 3600)
            GuiControl,, GuiTxtRow7, %msg%

            msg := "Locked in mode: " . lockedInSnipeMode
            GuiControl,, GuiTxtRow8, %msg%

            msg := msgChangeDetect
            GuiControl,, GuiTxtRow9, %msg%

            msg := "Sniping slots: " . snipeSlot
            GuiControl,, GuiTxtRow10, %msg%

            msg := "Triggers before carrot / corn removal of trigger: " . triggerNewItems
            GuiControl,, GuiTxtRow11, %msg%

            tickDiff := A_TickCount
            tickDiff -= tickCheck       ; Tickcheck is updated first in timer tick.
            msg := "Execution time / scan time: " . tickDiff . " / " . TICK_TIME_MS
            GuiControl,, GuiTxtRow12, %msg%

            msg := "Elapsed ms since last update: " . elapsedMs
            GuiControl,, GuiTxtRow13, %msg%

            msg := "Trigger Mem: " . slotColors_mem[1] . ", " . slotColors_mem[2] . ", " . slotColors_mem[3] . ", " . slotColors_mem[4]
            GuiControl,, GuiTxtRow14, %msg%

            msg := "Trigger Col: " . slotColors[1] . ", " . slotColors[2] . ", " . slotColors[3] . ", " . slotColors[4]
            GuiControl,, GuiTxtRow15, %msg%
        }
        ;----------------------------------------------------------------------


        ; Return, stay in mode, stay in shop, just release code.
        return
    }



    ; -----------------------------------------------------------

    ; ------------------------------------------------------------------------------------------

    return  ; MyTimerTick
; ------------------------------------------------------------------------------------------------







; ------------------------------------------------------------------------------------------------
; Hay day specific general functions

; NOT USED
; Positions screen at a known fixed position around the house.
;
; Requires:
;  Home / Friend screen for useful result.
;
; Returns:
;   1 / <0
GoCenterReference() {
    dbgEnable := true
    dbgHeader := "GoCenterReference"

    global APP_CENTER_X, APP_CENTER_Y
    global DRAG_ANCHOR_TOP_LEFT_X, DRAG_ANCHOR_TOP_LEFT_Y
    global DRAG_ANCHOR_LOWER_LEFT_X, DRAG_ANCHOR_LOWER_LEFT_Y
    global SCREEN_HOME

    global g_AppScaleExtra

    ; Go to top left reference since it is the only static known.
    res := GoTopLeftReference()
    if ( res < 0) {
        dbgMsgBox(true, dbgHeader, "Error: Could not reach top left reference.")
        return res
    }

    ; For moving to the center the real app scale must be determined as HayDay on PC seems to scale a little
    ;  random each time home screen.
    res := FindExtraAppScale()
    g_AppScaleExtra := res[1]
    msg := "XXX the extra app scale factor is: " . g_AppScaleExtra
    MsgBox,,,%msg%

    ; Using the scale compensation, the target pixel position, but counted from the top left of game area at the river,
    ;  can be calculated.

    startPos := [APP_CENTER_X, APP_CENTER_Y]
    endPos   := [DRAG_ANCHOR_TOP_LEFT_X, DRAG_ANCHOR_TOP_LEFT_Y]
    res := DragScreen(startPos, endPos, 1, false, SCREEN_HOME, true)
    if ( res < 0) {
        dbgMsgBox(true, dbgHeader, "Error: Could go to center reference.")
        return res
    }

    return 1
}


; screenSelect - verify in this screen. Default: Home
DragScreen(startPos, endPos, drags := 1, staticCheck := true, screenSelect := 0, slow := false) {
    dbgEnable := true
    dbgHeader := "DragScreen"

    global APP_CENTER_X, APP_CENTER_Y, APP_SIZE_X_NRM, APP_SIZE_Y_NRM, APP_SCALE, APP_TOP_LEFT_X, APP_TOP_LEFT_Y
    global SCREEN_HOME, SCREEN_FRIEND

    start_x := startPos[1]
    start_y := startPos[2]
    end_x := endPos[1]
    end_y := endPos[2]

    ; Color abort check little to right of center of screen.
    ; If there is exact color on a pixel before and after move then screen has not moved.
    if ( staticCheck ) {
        ; Four points around the center.
        cx0 := 1.05*APP_CENTER_X
        cy0 := 0.95*APP_CENTER_Y
        cx1 := 1.05*APP_CENTER_X
        cy1 := 1.05*APP_CENTER_Y

        ; Four points at the top left.
        cx0 := APP_TOP_LEFT_X + 0.10*APP_SIZE_X_NRM*APP_SCALE
        cy0 := APP_TOP_LEFT_Y + 0.20*APP_SIZE_Y_NRM*APP_SCALE
        cx1 := APP_TOP_LEFT_X + 0.25*APP_SIZE_X_NRM*APP_SCALE
        cy1 := APP_TOP_LEFT_Y + 0.50*APP_SIZE_Y_NRM*APP_SCALE

        cx0 := Ceil(cx0)
        cy0 := Ceil(cy0)
        cx1 := Ceil(cx1)
        cy1 := Ceil(cy1)
    }

    screenError := false
    loops := 0
    loop {
        if ( staticCheck ) {
            PixelGetColor, col0_a, cx0, cy0, RGB
            PixelGetColor, col1_a, cx1, cy1, RGB
            PixelGetColor, col2_a, cx1, cy0, RGB
            PixelGetColor, col3_a, cx0, cy1, RGB
        }

        ; Drag if in correct screen.
        if ( IsScreen(screenSelect) > 0 ) {
            MouseDragDLL(startPos, endPos)
            Sleep, 300
        }
        else {
            dbgMsgBox(true, dbgHeader, "Error: Not in screen.")
            screenError := true
            break
        }

        ; Detect if scroll complete, no longer needed to drag more.
        if ( staticCheck ) {
            PixelGetColor, col0_b, cx0, cy0, RGB
            PixelGetColor, col1_b, cx1, cy1, RGB
            PixelGetColor, col2_b, cx1, cy0, RGB
            PixelGetColor, col3_b, cx0, cy1, RGB

            msg := "col1_a, b: " . col0_a . ", " . col0_b . "`n" 
            dbgMsgBox(dbgEnable, dbgHeader, msg)
            msg := "col2_a, b: " . col1_a . ", " . col1_b . "`n" 
            dbgMsgBox(dbgEnable, dbgHeader, msg)
            msg := "col3_a, b: " . col2_a . ", " . col2_b . "`n" 
            dbgMsgBox(dbgEnable, dbgHeader, msg)
            msg := "col4_a, b: " . col3_a . ", " . col3_b . "`n" 
            dbgMsgBox(dbgEnable, dbgHeader, msg)

            ; msg := "col1_a, b: " . col0_a . ", " . col0_b . "`n" 
            ; msg := msg . "col2_a, b: " . col1_a . ", " . col1_b . "`n" 
            ; msg := msg . "col3_a, b: " . col2_a . ", " . col2_b . "`n" 
            ; msg := msg . "col4_a, b: " . col3_a . ", " . col3_b . "`n" 
            ; MsgBox,,,%msg%

            ; if ( col0_a = col0_b && col1_a = col1_b && col2_a = col2_b && col3_a = col3_b ) {
            if ( IsAlmostSameColor(col0_a, col0_b) && IsAlmostSameColor(col1_a, col1_b) && IsAlmostSameColor(col2_a, col2_b) && IsAlmostSameColor(col3_a, col3_b) ) {
                msg := "Scroll complete since no screen movement detected."
                dbgMsgBox(dbgEnable, dbgHeader, msg)

                break
            }
        }

        ; Exit loop when done
        loops++
        if ( loops >= drags ) {
            break
        }

        msg := "Loops: " . loops . " / " . drags
        dbgMsgBox(dbgEnable, dbgHeader, msg)
    }

    ; Return result
    if ( screenError ) {
        dbgMsgBox(true, dbgHeader, "Returns -1")
        return -1
    }
    else {
        dbgMsgBox(dbgEnable, dbgHeader, "Returns 1")
        return 1 
    }
}


; Go top left and zoom out. This position is now always the same and can be used as origin.
;
; Inputs:
;  useHomeScreen, default true (else no check of screen)
GoTopLeftReference(useHomeScreen := true) {
    global DRAG_ANCHOR_TOP_LEFT_X    
    global DRAG_ANCHOR_TOP_LEFT_Y    

    global ZOOM_OUT_ANCHOR_TOP_LEFT_X
    global ZOOM_OUT_ANCHOR_TOP_LEFT_Y

    global APP_CENTER_X, APP_CENTER_Y
    global APP_SCALE

    global SCREEN_FRIEND, SCREEN_HOME

    dbgEnable := true
    dbgHeader := "GoTopLeftReference"


    ; Go to the home screen if selected.
    if ( useHomeScreen ) {
        dbgMsgBox(dbgEnable, dbgHeader, "Trying to find home screen")

        res := GoToHome()
        if ( res < 0 ) {
            return res
        }
    }


    ; Drag top left by
    dbgMsgBox(dbgEnable, dbgHeader, "Loop drag n times.")

    startPos := [DRAG_ANCHOR_TOP_LEFT_X, DRAG_ANCHOR_TOP_LEFT_Y]
    endPos := [APP_CENTER_X, APP_CENTER_Y]
    ; XXX Since scale is a little different each time, the center can on a small screen be fishng net,
    ;  and then the mouse click up enters fishing area.
    endPos[1] := 0.5*(endPos[1] + startPos[1])
    endPos[2] := 0.5*(endPos[2] + startPos[2])
    res := DragScreen(startPos, endPos, 20)
    screenError := res <= 0

    if ( screenError ) {
        msg := "Error: Not home screen."
        dbgMsgBox(true, dbgHeader, msg)

        return -1
    }

    ;   Do max zoom out by 2 slightly different center points.
    msg := "Zoom max out."
    dbgMsgBox(true, dbgHeader, msg)

    screenSelection := SCREEN_HOME
    x := ZOOM_OUT_ANCHOR_TOP_LEFT_X
    y := ZOOM_OUT_ANCHOR_TOP_LEFT_Y
    res := ZoomOut( [anchor_x, y], 3, screenSelection)
    if ( screenError ) {
        msg := "Error: Not home screen."
        dbgMsgBox(true, dbgHeader, msg)

        return -1
    }
    res := ZoomOut( [x, y-50*APP_SCALE], 4, screenSelection)
    if ( screenError ) {
        msg := "Error: Not home screen."
        dbgMsgBox(true, dbgHeader, msg)

        return -1
    }

    ; Drag one more
    msg := "Drag one more."
    dbgMsgBox(dbgEnable, dbgHeader, msg)

    ; MouseMove, DRAG_ANCHOR_TOP_LEFT_X, DRAG_ANCHOR_TOP_LEFT_Y, 0
    if ( IsScreen(SCREEN_HOME) <= 0 ) {
        msg := "Error: Not home screen."
        dbgMsgBox(true, dbgHeader, msg)

        return -1
    }
    res := DragScreen(startPos, endPos, 2)


    ; Clear any open
    msg := "Clear any open."
    dbgMsgBox(dbgEnable, dbgHeader, msg)

    MouseMove, DRAG_ANCHOR_TOP_LEFT_X, DRAG_ANCHOR_TOP_LEFT_Y, 20
    Click
    Sleep, 200
    if ( IsScreen(SCREEN_HOME) <= 0 ) {
        msg := "Error: Not home screen."
        dbgMsgBox(true, dbgHeader, msg)

        return -1
    }

    return 1
}


ZoomOutFromCenter() {
    global GAME_AREA_CENTER_X, GAME_AREA_CENTER_Y

    dbgEnable := true
    dbgHeader := "ZoomOutFromCenter"
    dbgMsgBox(dbgEnable, dbgHeader, "")
    
    MouseMove, GAME_AREA_CENTER_X, GAME_AREA_CENTER_Y, 0

    SendEvent {CtrlDown}
    loop, 5 {
        MouseClick, WheelDown,,, 1
        Sleep, 300
    }
    SendEvent {CtrlUp}
    Sleep, 300
}


;
ZoomOut(pos, counts, screenSelection) {
    dbgEnable := true
    dbgHeader := "ZoomOut"
    dbgMsgBox(dbgEnable, dbgHeader, "")

    x := pos[1]
    y := pos[2]
    MouseMove, x, y, 0

    cnt := 0
    loop {
        if ( IsScreen(screenSelection) <= 0 ) {
            dbgMsgBox(true, dbgHeader, "Error: !IsScreen(screenSelection)")
            return -1
        }

        SendEvent {CtrlDown}
        MouseClick, WheelDown,,, 1
        SendEvent {CtrlUp}
        Sleep, 300

        cnt++
        if ( cnt >= counts ) {
            break
        }
    }

    if ( IsScreen(screenSelection) <= 0 ) {
        dbgMsgBox(true, dbgHeader, "Error: !IsScreen(screenSelection)")
        return -1
    }

    return 1
}


; Returns coordinates - TODO nä det är press slot som gäller.
GetSnipePosForSlot(slot) {
    coord := Helper_GetClickCoordForShopSlot(screenSlot)
    return coord
}


; May be used by many, some menus are similar.
IsShopSiloBarnFullRedX() {
    global RED_X_SILO_BARN_FULL_X, RED_X_SILO_BARN_FULL_Y

    x := RED_X_SILO_BARN_FULL_X
    y := RED_X_SILO_BARN_FULL_Y
    return IsCloseButtonAtPos( [x, y] )
}


;
IsItemStorageBarn(itemId) {
    global ITEM_ID_CORN

    if ( itemId = ITEM_ID_CORN ) {
        return true
    }
    return false
} 

; Determines if there is an red x at the coordinate. Input array.
; Target pos is array in SCREEN_COORD and must be scaled before
; The red x detection works for different x as long as points to the center of it.
IsCloseButtonAtPos(targetPos) {
    global RED_X_DIFF_UP, RED_X_DIFF_DOWN

    dbgEnable := true
    dbgHeader := "IsCloseButtonAtPos"

    ;------------------------------------
    ; Set up references
    ; P1 = Center
    P1_X    := targetPos[1]     ;AC2SC(targetPos[1], 0) 
    P1_Y    := targetPos[2]     ;AC2SC(targetPos[2], 1)
    P1_C    := 0xF05A10 ; Center point - With some variance

    P2_X    := P1_X
    P2_Y    := P1_Y - RED_X_DIFF_UP
    P2_C    := 0xF8E850     ; Above - With some variance

    P3_X    := P1_X
    P3_Y    := P1_Y + RED_X_DIFF_DOWN
    P3_C    := 0xE99D00     ; Below - With some variance
    ;------------------------------------

    ;------------------------------------
    ; Determine
    ; Check colors - Seems to be a compiler optimisation that skips before all if false.
    hits := 0

    PixelGetColor, col, P1_X, P1_Y, RGB
    if ( IsAlmostSameColor(P1_C, col) > 0 ) 
        hits++
    msg := P1_X . ", " . P1_Y . ", " . hits
    dbgMsgBox(dbgEnable, dbgHeader, msg)

    PixelGetColor, col, P2_X, P2_Y, RGB
    if ( IsAlmostSameColor(P2_C, col) > 0 )
        hits++
    msg := P2_X . ", " . P2_Y . ", " . hits
    dbgMsgBox(dbgEnable, dbgHeader, msg)

    PixelGetColor, col, P3_X, P3_Y, RGB
    if ( IsAlmostSameColor(P3_C, col) > 0 )
        hits++
    msg := P3_X . ", " . P3_Y . ", " . hits
    dbgMsgBox(dbgEnable, dbgHeader, msg)
    ;------------------------------------

    ;DEBUG
    ; msg := ""
    ; msg := msg . "IsCloseButtonAtPos" . "`n"
    ; msg := msg . "X, Y, Hits: " . targetPos[1] . ", " . targetPos[2] . ", " . hits
    ; MsgBox 0, IsCloseButtonAtPos, %msg%

    return hits >= 3
}


; For field, harvest, but also a general coordinate system for production units.
; Uses the global g_AppScaleExtra for compensation.
;
; Rows are parallell to the river.
; Column increase towards the cliff (screen up right).
;
; Inputs:
;  [rows, cols]
;  scale (default 1.0)
; Returns:
;  [diffX, diffY]
TransformRowColDiffCoord(RowCol) {
    global COORD_TRANSFORM_ROW_X
    global COORD_TRANSFORM_ROW_Y
    global COORD_TRANSFORM_COL_X
    global COORD_TRANSFORM_COL_Y

    global g_AppScaleExtra

    F_ROW_X := COORD_TRANSFORM_ROW_X*g_AppScaleExtra
    F_ROW_Y := COORD_TRANSFORM_ROW_Y*g_AppScaleExtra
    F_COL_X := COORD_TRANSFORM_COL_X*g_AppScaleExtra
    F_COL_Y := COORD_TRANSFORM_COL_Y*g_AppScaleExtra

    return [RowCol[1]*F_ROW_X + RowCol[2]*F_COL_X, RowCol[1]*F_ROW_Y + RowCol[2]*F_COL_Y]
}


; Clicks coords and watches all available commercials.
; Requires:
;  Provided coords for commercial.
;
; Returns:
;  >=0 : Nbr Commercials watched
;   <0 : Nbr Commercials watched but Screen lost
WatchCommercialFromPos(commercialGroundCoords) {
    global RED_X_COMMERCIAL_X 
    global RED_X_COMMERCIAL_Y 

    global RED_X_GOOGLE_PLAY_X
    global RED_X_GOOGLE_PLAY_Y

    global BTN_CLOSE_COMMERCIAL_X
    global BTN_CLOSE_COMMERCIAL_Y

    global BTN_START_COMMERCIAL_X
    global BTN_START_COMMERCIAL_Y

    dbgEnable := true
    dbgHeader := "WatchCommercialFromPos"
    dbgEnableWait := dbgEnable && false

    nbrsWatched := 0

    loop {
        MouseMoveDLL(commercialGroundCoords)
        Click
        Sleep, 1000

        ; In movie screeen
        if ( IsCloseButtonAtPos([RED_X_COMMERCIAL_X, RED_X_COMMERCIAL_Y]) ) {
            dbgMsgBox(dbgEnable, dbgHeader, "In movie screen.")
            dbgWait(dbgEnableWait, dbgHeader, 1000)

            ; Is commercial available?
            MouseMoveDLL([BTN_START_COMMERCIAL_X, BTN_START_COMMERCIAL_Y])
            Sleep, 100
            Click

            ; In screen
            Sleep, 1000
            if ( IsScreenHome() > 0 ) {
                dbgMsgBox(true, dbgHeader, "Error: Still in home screen after clicking commercial on ground.")

                return -nbrsWatched
            }

            if ( IsCloseButtonAtPos([RED_X_COMMERCIAL_X, RED_X_COMMERCIAL_Y]) = 0 ) {
                dbgMsgBox(dbgEnable, dbgHeader, "Watching movie.")
                dbgWait(dbgEnableWait, dbgHeader, 1000)

                ; Watch the commercial
                n := 0
                n_max := 30 ; Delay 1 s is always slower than real time.

                t_end := A_Now
                t_end += 35, seconds
                loop {                
                    Sleep, 1000

                    if ( IsScreenHome() > 0 ) {
                        dbgMsgBox(true, dbgHeader, "Error: Screen left.")

                        return -nbrsWatched
                    }

                    t_now := A_Now
                    n++
                    if ( n >= n_max || t_now >= t_end ) {
                        break
                    }

                    msg := "Watching timeout " . n . " / " . n_max
                    dbgMsgBox(dbgEnable, dbgHeader, msg)
                }

                ; Close the external commercial.
                dbgMsgBox(dbgEnable, dbgHeader, "Close the external commercial.")

                MouseMoveDLL([BTN_CLOSE_COMMERCIAL_X, BTN_CLOSE_COMMERCIAL_Y])
                Sleep, 100
                Click

                ; Sometimes the google play starts coming
                dbgMsgBox(dbgEnable, dbgHeader, "Sometimes the google play starts coming.")

                Sleep, 1000

                ; Get rid of the google play external overlay screen by clicking outside it.
                ; Mixing known coords for this.
                dbgMsgBox(dbgEnable, dbgHeader, "Get rid of the google play external overlay.")

                MouseMoveDLL([BTN_START_COMMERCIAL_X, 0.5*(BTN_START_COMMERCIAL_Y+BTN_CLOSE_COMMERCIAL_Y)])
                Sleep, 100
                Click
                Sleep, 2000

                ; Get rid of the hayday google play screen. It is not always there.
                if ( IsCloseButtonAtPos[RED_X_GOOGLE_PLAY_X, RED_X_GOOGLE_PLAY_Y] ) {
                    dbgMsgBox(dbgEnable, dbgHeader, "Get rid of the hayday google play screen..")
    
                    MouseMoveDLL([RED_X_GOOGLE_PLAY_X, RED_X_GOOGLE_PLAY_Y])
                    Sleep, 100
                    Click
                }

                ; See if any more commercials are available
                Sleep, 1000
                if ( IsScreenHome() > 0 ) {
                    dbgMsgBox(true, dbgHeader, "Error: Screen left when closing commercial.")
                    
                    ; But since home screen, do a gamble click? Screen might be anywhere...
                    ; return -nbrsWatched
                }

                if ( IsCloseButtonAtPos([RED_X_COMMERCIAL_X, RED_X_COMMERCIAL_Y]) = 0 ) {
                    dbgMsgBox(true, dbgHeader, "Error: A red x visible after closing commercial.")
                    
                    ; No action.
                }

                ; Close by the Red X and enter home screen. When no more available then the ground is clear.
                dbgMsgBox(true, dbgHeader, "Close by the Red X and enter home screen. When no more available then the ground is clear.")

                MouseMoveDLL([RED_X_COMMERCIAL_X, RED_X_COMMERCIAL_Y])
                Sleep, 100
                Click
                Sleep, 500
            }
        }
        else {
            ; Either the wrong coords were supplied, or there are no more commercials.
            dbgMsgBox(dbgEnable, dbgHeader, "Either the wrong coords were supplied, or there are no more commercials.")
            dbgWait(dbgEnableWait, dbgHeader)

            return nbrsWatched
        }
    }

    return nbrsWatched
}
; ------------------------------------------------------------------------------------------------



; ------------------------------------------------------------------------------------------------
; Overall functions


; Buy and sell
; Must start in the shop to buy from.
BuyFromShopAndSell( itemId, priceMaxOrMin, priceModifier, advertise := true) {
    dbgEnable := true
    dbgHeader := "BuyFromShopAndSell"

    if ( IsInShop() <= 0 ) {
        dbgMsgBox(true, dbgHeader, "Error: !IsInShop()")
        return -1
    }

    maxCounts := 0
    res := AutoBuyItem( itemId, maxCounts )
    msg := "AutoBuyItem: " . res[1] . "Counts: " . res[2]
    dbgMsgBox(dbgEnable, dbgHeader, msg)

    ; Go to home shop
    ; Must leave friend shop first.
    CloseShop()
    res := GoToHomeAndOpenShop()
    if ( res > 0 ) {
        dbgPriceMod := -3
        dbgAdvertise := 1
        res := SellAllItem( itemId, priceMaxOrMin, priceModifier, advertise )
        msg := "SellAllItem: Result: " . res
        dbgMsgBox(dbgEnable, dbgHeader, msg)
    }
    return res
}

; ------------------------------------------------------------------------------------------------





; ------------------------------------------------------------------------------------------------
; Screen functions


; TODO Since scaling is from top left, a more sensitive value would be from top left edge of boat, not left.
; Takes about 30s.
;
; Returns:
;  search result
;  edge screen pixel
GetRiverBoatEdgeBinSearch(scaleDetectPixelSearchRangeScreenPct := 10.0) {
    dbgEnable := true
    dbgHeader := "GetRiverBoatEdgeBinSearch"

    global APP_SCALE, APP_TOP_LEFT_X, APP_SIZE_X

    global BOAT_DETECT_REF_Y    ; Below setting gear at level of boat nose.
    global BOAT_DETECT_X        ; Left edge of boat to detect - AT SAME SCALE where alse transform was measured.
    
    boatDetectRiverHue := 180.0
    boatDetectRiverHueRange := 38.0 ; Consider as pixel is river if hue +/- this.
    
    ; Search for edge +/- half this around ideal edge position. 
    boatDetectPixelSearchRange := scaleDetectPixelSearchRangeScreenPct*APP_SIZE_X/100.0
    ; MsgBox,,,boatDetectPixelSearchRange: %boatDetectPixelSearchRange%

    ; Uses that river is blue. If not that color, it's the boat.
    ; Uses bin search. Each bin is an x-coordinate.


    eval := 0
    lowerLimit := 0                             ; minus half range from ideal pos.
    upperLimit := ceil(boatDetectPixelSearchRange)   ; plus half range from ideal pos.
    state := 0
    index := 0
    foundBin := 0
    init := true

    counts := 0
    loop {
        counts++

        ; Call bin search until it returns Done or Error.
        binResult := BinSearch(eval, lowerLimit, upperLimit, state, index, foundBin, init)
        ;
        searchResult    := binResult[1]
        lowerLimit      := binResult[2]
        upperLimit      := binResult[3]
        state           := binResult[4]
        index           := binResult[5]
        foundBin        := binResult[6]
        init            := binResult[7]
        ;
        msg := "From search: " . searchResult . ", " . lowerLimit . ", " . upperLimit . ", " . state . ", " . index . ", " . foundBin . ", In: " . init
        dbgMsgBox(dbgEnable, dbgHeader, msg)
        ; MsgBox,,,%msg%
        ;
        if (searchResult = 1) {
            ; Done
            msg := "Search complete at index: " . index
            dbgMsgBox(dbgEnable, dbgHeader, msg)
            ; Exit loop
            break
        }
        else if (searchResult < 0) {
            ; Error in provided interval
            msg := "Search aborted."
            dbgMsgBox(dbgEnable, dbgHeader, msg)
            ; Exit loop
            break
        }

        ; Evaluate search for comparison and provide the result to the next search iteration.
        x := BOAT_DETECT_X + APP_TOP_LEFT_X - 0.5*boatDetectPixelSearchRange + index
        y := BOAT_DETECT_REF_Y

        x := Ceil(x)
        y := Ceil(y)

        if (dbgEnable) {
            MouseMoveDLL([x,y])
        }

        ; Sample a few times because there is butterflies and shit. TODO - edge detect sample several to the left and right of center.
        n := 0
        loop, 4 {
            PixelGetColor, col, x, y, rgb
            hsv := Convert_RGBHSV( col )
            waterDetected := ( abs( hsv[1]-boatDetectRiverHue ) < 0.5*boatDetectRiverHueRange ) && hsv[2] > 0.3 && hsv[2] < 0.55 && hsv[3] > 0.55 && hsv[3] < 0.75
            colorDetected := !waterDetected
            Sleep, 300
            if ( colorDetected ) {
                n++
            }
        }
        if ( n < 3 ) {
            colorDetected := false
        }
        
        msg := "Testing pixel for river hue: " . x . ", " . y . ", Target Hue: " . boatDetectRiverHue . "Found Hue: " . hsv[1]
        dbgMsgBox(dbgEnable, dbgHeader, msg)
        ; MsgBox,,,%msg%

        msg := "Color detection at index: " . index . " Result: " . colorDetected
        dbgMsgBox(dbgEnable, dbgHeader, msg)
        ; MsgBox,,,%msg%
    
        if ( colorDetected ) {
            ; Found the boat here.
            eval := 1
        }
        else {
            eval := 0
        }

        if ( !IsScreenHome() ) {
            searchResult := -1
            break
        }
    }
    ; msgbox,,,%msg%
    return [searchResult, x ]
}


; Returns:
;  search result
;  edge pixel
GetRiverEdgeBinSearch(scaleDetectPixelSearchRangeScreenPct) {
    dbgEnable := true
    dbgHeader := "GetRiverEdgeBinSearch"

    global APP_TOP_LEFT_Y, APP_SIZE_Y, APP_HEADER_Y
    global RIVER_DETECT_REF_X    ; Right of the icons left screen.
    global RIVER_DETECT_Y        ; Lower river shore - AT SAME SCALE where alse transform was measured.
    
    detectRiverHue := 180.0
    detectRiverHueRange := 30.0 ; Consider as pixel is river if hue +/- this.
    ; detectRiverSatRange := 38.0 ; Consider as pixel is river if hue +/- this.
    detectRiverValMax := 0.50 ; The darker river is found by value < this.
    
    ; Search for edge +/- half this around ideal edge position. 
    detectPixelSearchRange := scaleDetectPixelSearchRangeScreenPct*(APP_SIZE_Y - APP_HEADER_Y)/100.0

    ; Uses that river is blue. If not that color, it's edge.
    ; Uses bin search. Each bin is an y-coordinate.

    eval := 0
    lowerLimit := 0                             ; minus half range from ideal pos.
    upperLimit := ceil(detectPixelSearchRange)   ; plus half range from ideal pos.
    state := 0
    index := 0
    foundBin := 0
    init := true

    counts := 0
    loop {
        counts++

        ; Call bin search until it returns Done or Error.
        binResult := BinSearch(eval, lowerLimit, upperLimit, state, index, foundBin, init)
        ;
        searchResult    := binResult[1]
        lowerLimit      := binResult[2]
        upperLimit      := binResult[3]
        state           := binResult[4]
        index           := binResult[5]
        foundBin        := binResult[6]
        init            := binResult[7]
        ;
        msg := "From search: " . searchResult . ", " . lowerLimit . ", " . upperLimit . ", " . state . ", " . index . ", " . foundBin . ", In: " . init
        dbgMsgBox(dbgEnable, dbgHeader, msg)
        ; MsgBox,,,%msg%
        ;
        if (searchResult = 1) {
            ; Done
            msg := "Search complete at index: " . index
            dbgMsgBox(dbgEnable, dbgHeader, msg)
            ; Exit loop
            break
        }
        else if (searchResult < 0) {
            ; Error in provided interval
            msg := "Search aborted."
            dbgMsgBox(dbgEnable, dbgHeader, msg)
            ; Exit loop
            break
        }

        ; Evaluate search for comparison and provide the result to the next search iteration.
        ; This is in screen pixels.
        x := RIVER_DETECT_REF_X
        y := RIVER_DETECT_Y + APP_HEADER_Y + APP_TOP_LEFT_Y - 0.5*detectPixelSearchRange + index
        ; MsgBox,,,x %x% y %y%

        x := Ceil(x)
        y := Ceil(y)

        ; Indicate where sampling.
        if (dbgEnable) {
            MouseMoveDLL([x,y])
        }

        ; Sample a few times because there is butterflies and shit. 
        ; XXX Loop 4, kolla n<3
        n := 0
        loop, 4 {
        ; loop, 1 {
            PixelGetColor, col, x, y, rgb
            hsv := Convert_RGBHSV( col )
            waterDetected := ( abs(hsv[1]-detectRiverHue) < 0.5*detectRiverHueRange ) && hsv[3] > detectRiverValMax
            colorDetected := !waterDetected
            Sleep, 300
            if ( colorDetected ) {
                n++
            }
        }
        if ( n < 3 ) {
        ; if ( n < 1 ) {
            colorDetected := false
        }
        
        msg := "Testing pixel for river hue: " . x . ", " . y . ", HSV: " . hsv[1] . " " . hsv[2] . " " . hsv[3]
        dbgMsgBox(dbgEnable, dbgHeader, msg)
        ; MsgBox,,,%msg%

        msg := "Color detection at index: " . index . " Result: " . colorDetected
        dbgMsgBox(dbgEnable, dbgHeader, msg)
        ; MsgBox,,,%msg%
    
        if ( colorDetected ) {
            ; Found the edge here.
            eval := 1
        }
        else {
            eval := 0
        }

        if ( !IsScreenHome() ) {
            searchResult := -1
            break
        }
    }
    ; msgbox,,,%msg%
    return [searchResult, y ]
}


; Needs grass above
; Returns:
;  search result
;  edge pixel
GetRiverGrassEdgeBinSearch(scaleDetectPixelSearchRangeScreenPct, y_ideal) {
    global APP_TOP_LEFT_Y, APP_SIZE_Y, APP_HEADER_Y
    global RIVER_DETECT_REF_X    ; Right of the icons left screen.
    
    dbgEnable := true
    dbgHeader := "GetRiverEdgeBinSearch"
    dbgEnableWait := dbgEnable && true

    detectRiverHue := 80
    detectRiverHueRange := 15.0 ; Consider as pixel is river if hue +/- this.
    
    ; Search for edge +/- half this around ideal edge position. 
    detectPixelSearchRange := scaleDetectPixelSearchRangeScreenPct*(APP_SIZE_Y - APP_HEADER_Y)/100.0

    ; Uses that river is blue. If not that color, it's edge.
    ; Uses bin search. Each bin is an y-coordinate.

    eval := 0
    lowerLimit := 0                              ; minus half range from ideal pos.
    upperLimit := ceil(detectPixelSearchRange)   ; plus half range from ideal pos.
    state := 0
    index := 0
    foundBin := 0
    init := true

    counts := 0
    loop {
        counts++

        ; Call bin search until it returns Done or Error.
        binResult := BinSearch(eval, lowerLimit, upperLimit, state, index, foundBin, init)
        ;
        searchResult    := binResult[1]
        lowerLimit      := binResult[2]
        upperLimit      := binResult[3]
        state           := binResult[4]
        index           := binResult[5]
        foundBin        := binResult[6]
        init            := binResult[7]
        ;
        msg := "From search: " . searchResult . ", " . lowerLimit . ", " . upperLimit . ", " . state . ", " . index . ", " . foundBin . ", In: " . init
        dbgMsgBox(dbgEnable, dbgHeader, msg)
        ; MsgBox,,,%msg%
        ;
        if (searchResult = 1) {
            ; Done
            msg := "Search complete at index: " . index
            dbgMsgBox(dbgEnable, dbgHeader, msg)
            ; Exit loop
            break
        }
        else if (searchResult < 0) {
            ; Error in provided interval
            msg := "Search aborted."
            dbgMsgBox(dbgEnable, dbgHeader, msg)
            ; Exit loop
            break
        }

        ; Evaluate search for comparison and provide the result to the next search iteration.
        ; This is in screen pixels.
        x := RIVER_DETECT_REF_X
        y := y_ideal + APP_HEADER_Y + APP_TOP_LEFT_Y - 0.5*detectPixelSearchRange + index
        ; MsgBox,,,x %x% y %y%

        x := Ceil(x)
        y := Ceil(y)

        ; Indicate where sampling.
        if (dbgEnable) {
            MouseMoveDLL([x,y])
        }

        ; Sample a few times because there is butterflies and shit. 
        ; XXX Loop 4, kolla n<3
        n := 0
        loop, 4 {
        ; loop, 1 {
            PixelGetColor, col, x, y, rgb
            hsv := Convert_RGBHSV( col )
            waterDetected := abs(hsv[1]-detectRiverHue) < 0.5*detectRiverHueRange
            colorDetected := !waterDetected
            Sleep, 300
            if ( colorDetected ) {
                n++
            }
        }
        if ( n < 3 ) {
        ; if ( n < 1 ) {
            colorDetected := false
        }
        
        msg := "Testing pixel for river hue: " . x . ", " . y . ", HSV: " . hsv[1] . " " . hsv[2] . " " . hsv[3]
        dbgMsgBox(dbgEnable, dbgHeader, msg)
        ; MsgBox,,,%msg%

        msg := "Color detection at index: " . index . " Result: " . colorDetected
        dbgMsgBox(dbgEnable, dbgHeader, msg)
        ; MsgBox,,,%msg%
    
        if ( colorDetected ) {
            ; Found the edge here.
            eval := 1
        }
        else {
            eval := 0
        }

        if ( !IsScreenHome() ) {
            searchResult := -1
            break
        }
    }
    ; msgbox,,,%msg%
    edgeInGamePixels := y - APP_TOP_LEFT_Y - APP_HEADER_Y
    msg := "Done. Index: " . index . ", Edge in game pixels: " . edgeInGamePixels
    dbgMsgBox(dbgEnable, dbgHeader, msg)
    dbgWait(dbgEnableWait, dbgHeader)


    return [searchResult, y ]
}


FindExtraAppScale2(scaleDetectPixelSearchRangeScreenPct := 20) {
    dbgEnable := true
    dbgHeader := "FindExtraAppScale2"
    dbgEnableWait := dbgEnable && true

    ; Ideal position at which scale the other coordinates were measured too. 
    ; In game area coords excluding header.
    global RIVER_DETECT_Y   
    
    global APP_TOP_LEFT_Y
    global APP_HEADER_Y

    idealGameAreaPixel := RIVER_DETECT_Y


    edgeResult := GetRiverEdgeBinSearch(scaleDetectPixelSearchRangeScreenPct)
    if ( edgeResult[1] = 1 ) {
        edgeInGamePixels := edgeResult[2] - APP_TOP_LEFT_Y - APP_HEADER_Y

        ; If target is further away than reference then screen is more zoomed in, larger scale.
        scale := edgeInGamePixels / idealGameAreaPixel

        msg := "Scale: " . scale
        GuiControl,, GuiTxtScale, %msg%

        msg := "Edge found at screen pixel: " . edgeResult[2]
        dbgMsgBox(dbgEnable, dbgHeader, msg)
        dbgWait(dbgEnableWait, dbgHeader, 1000)

        msg := "Edge in game area pixels: " . edgeInGamePixels
        dbgMsgBox(dbgEnable, dbgHeader, msg)
        dbgWait(dbgEnableWait, dbgHeader, 1000)

        msg := "Scale: " . edgeInGamePixels . " / " . idealGameAreaPixel . " = " . scale
        dbgMsgBox(dbgEnable, dbgHeader, msg)
        dbgWait(dbgEnableWait, dbgHeader, 1000)

        return [scale, edgeResult[2]]
    }
    else {
        ; Error: Did not find calibration edge.
        return [-1, -1]
    }
}

; Uses the top left pos and the river boat to determine the randomised scale factor.
; For any screen movement and selecton this is necessary to compensate with.
;  For instance: 
;   a reference in "maxed zoomed out" then drags 500 px and points to a px at lower right.
;   but from the absolute top left of play area, the target pixel must be scaled, using top left as origo.
;
; Returns:
;  [Scale, Screen pixel of found edge]
FindExtraAppScale(scaleDetectPixelSearchRangeScreenPct := 20) {
    dbgEnable := true
    dbgHeader := "FindExtraAppScale"
    dbgEnableWait := dbgEnable && true

    ; Ideal position at which scale the other coordinates were measured too. 
    ; In game area coords excluding header.
    global RIVER_DETECT_Y   
    
    global APP_TOP_LEFT_Y
    global APP_HEADER_Y

    idealGameAreaPixel := RIVER_DETECT_Y


    edgeResult := GetRiverEdgeBinSearch(scaleDetectPixelSearchRangeScreenPct)
    if ( edgeResult[1] = 1 ) {
        edgeInGamePixels := edgeResult[2] - APP_TOP_LEFT_Y - APP_HEADER_Y

        ; If target is further away than reference then screen is more zoomed in, larger scale.
        scale := edgeInGamePixels / idealGameAreaPixel

        msg := "Scale: " . scale
        GuiControl,, GuiTxtScale, %msg%

        msg := "Edge found at screen pixel: " . edgeResult[2]
        dbgMsgBox(dbgEnable, dbgHeader, msg)
        dbgWait(dbgEnableWait, dbgHeader, 1000)

        msg := "Edge in game area pixels: " . edgeInGamePixels
        dbgMsgBox(dbgEnable, dbgHeader, msg)
        dbgWait(dbgEnableWait, dbgHeader, 1000)

        msg := "Scale: " . edgeInGamePixels . " / " . idealGameAreaPixel . " = " . scale
        dbgMsgBox(dbgEnable, dbgHeader, msg)
        dbgWait(dbgEnableWait, dbgHeader, 1000)

        return [scale, edgeResult[2]]
    }
    else {
        ; Error: Did not find calibration edge.
        return [-1, -1]
    }
}


; TODO - Handle impossible fields - drag so that they are on screen and clickable.
; Drag screen to put this field at screen game area center. Uses safe areas if possible to drag from.
; Requires:
;  The grid is possible to drag to center.
;  The scale is calibrated.
;
; Needs a "reference grid" and corresponding screen coordinate to its center. At some point this has
;  to start from the calibration screen area. There the center screen coord of grid 1, 1 is known.
;  Thus also all other grids and their centers.
; Dragging from here to moving the screen, if dragging from centers of grids, to another grid, then
;  a center coordinate to a grid is always known. To have a center coordinate facilitates detection
;  of the harvest overlay. It is not enough reliable to just click anywhere in the field.
CenterThisField(fieldRowCol){
    ; Is grid outside of screen?
    ;  Drag so that the grid enters screen.

    ; Is grid on screen?
    ;  Just drag it to desired pos.
}


; Drags the screen so many times that a desired field (row, col) becomes the 
;  new 'center field' on screen.
;
; Modifies global variables:
;  g_RC_CenterField
;
; Requires:
;  The screen is draggable, correct screen type already selected.
;  It is possible to achieve the result
;    For instance the shop can never be at center screen.
;  Scale is calibrated.
;  A known center field and screen coordinates exist.
;
; Inputs:
;  Absolute Row/Rol of field to drag to center.
;
; Outputs:
;  1 : OK
; -1 : Home screen lost.
DragFieldToCenter(rc_fieldToDrag) {
    global RC_FIELD_AREA_SELECT
    global g_RC_CenterField, g_CenterFieldScreenCoords_X, g_CenterFieldScreenCoords_Y
    global g_AppScaleExtra

    ; Maximum reach on the the current screen.
    SCREEN_REACH_ROWS := 10
    SCREEN_REACH_COLS := 10

    dbgEnable := true
    dbgHeader := "DragFieldToCenter"
    dbgEnableWait := dbgEnable && true

    ; Verify scale.
    if ( g_AppScaleExtra = "" || g_AppScaleExtra < 0.0 ) {
        dbgMsgBox(true, dbgHeader, "Error: Scale must be calculated before calling this function.")
        return -1
    }

    ; Calculate drags and grid to get the desired field visible on screen.
    ; All drags uses Top left, Lower left and Center only. Not areas to the right on screen.
    ; TODO.
    ; Determine if the field is outside a valid area and there is need to drag before it
    ;  can be moved to center.

    ; Drag until done. The helper finction verifies home screen.
    res := 1
    loop {
        ; Determine if field is on screen.
        if ( res < 0 || IsFieldOnScreen(rc_fieldToDrag) > 0 ) {
            break
        }

        ; Drag
        ; Calculate for each updated screen the fields to drag from. (Or instead the same Screen coords could be used every time)
        rc_fieldRef_Row := [g_RC_CenterField[1]-SCREEN_REACH_ROWS, g_RC_CenterField[2]]
        rc_fieldRef_Col := [g_RC_CenterField[1], g_RC_CenterField[2]-SCREEN_REACH_COLS]

        ; Drag either row or col each time, not both. The axis with greatest difference.
        if ( abs(rc_fieldToDrag[1]-g_RC_CenterField[1]) > abs(rc_fieldToDrag[2]-g_RC_CenterField[2]) ) {
            ; Drag row
            if ( rc_fieldToDrag[1] > g_RC_CenterField[1] ) {
                ; Drag to increase row on screen - drag from center to top left.
                dbgMsgBox(dbgEnable, dbgHeader, "Drag to increase row on screen - drag from center to top left.")
                dbgWait(dbgEnableWait, dbgHeader)

                res := Helper_DragField(g_RC_CenterField, rc_fieldRef_Row)
            }
            else {
                dbgMsgBox(dbgEnable, dbgHeader, "Drag to decrease row on screen - drag from top left to center.")
                dbgWait(dbgEnableWait, dbgHeader)

                res := Helper_DragField(rc_fieldRef_Row, g_RC_CenterField)
            }
        }
        else {
            ; Drag col.
            if ( rc_fieldToDrag[2] > g_RC_CenterField[2] ) {
                dbgMsgBox(dbgEnable, dbgHeader, "Drag to increase col on screen - drag from center to lower right.")
                dbgWait(dbgEnableWait, dbgHeader)

                res := Helper_DragField(g_RC_CenterField, rc_fieldRef_Col)
            }
            else {
                dbgMsgBox(dbgEnable, dbgHeader, "Drag to decrease col on screen - drag from lower right to center.")
                dbgWait(dbgEnableWait, dbgHeader)

                res := Helper_DragField(rc_fieldRef_Col, g_RC_CenterField)
            }
        }
    }

    if (res < 0) {
        dbgMsgBox(true, dbgHeader, "Error: Home screen left detected.")
        return -1
    }

    ; It is now determined that both the center grid and the target grid is visible on screen.
    ;  So the target grid can be clicked and dragged to the center (or suitable pos)
    res := Helper_DragField(rc_fieldToDrag, g_RC_CenterField)

    if ( res < 0 ) {
        dbgMsgBox(true, dbgHeader, "Error: Home screen left detected.")
        return -1
    }

    return 1
}


; Drags the selected field (row, col) to be the new 'center field' on screen.
;
; Modifies global variables:
;  g_RC_CenterField
;
; Requires:
;  The fields must be reachable on the screen - no verification is done.
;  The screen is draggable, correct screen type already selected.
;  Scale is calibrated.
;  A known center field and screen coordinates exist.
;
; Inputs:
;  Start field to drag (absolute row/col)
;  End field to drag (absolute row/col)
;
; Outputs:
;  1 : ok
; -1 : Home screen lost.
; -2 : No scale set before or input conditions.
Helper_DragField(rc_fieldToDragStart, rc_fieldToDragEnd) {
    global RC_FIELD_AREA_SELECT
    global g_RC_CenterField, g_CenterFieldScreenCoords_X, g_CenterFieldScreenCoords_Y
    global g_AppScaleExtra

    dbgEnable := true
    dbgHeader := "Helper_DragField"
    dbgEnableWait := dbgEnable && false

    dbgMsgBox(dbgEnable, dbgHeader, "Start.")
    dbgWait(dbgEnableWait, dbgHeader, 1000)

    ; Verify scale.
    if ( g_AppScaleExtra = "" || g_AppScaleExtra < 0.0 ) {
        dbgMsgBox(true, dbgHeader, "Error: Scale must be calculated before calling this function.")
        return -2
    }
    dbgMsgBox(dbgEnable, dbgHeader, "scale verified.")

    ; Verify home screen
    if ( IsScreenHome() <= 0 ) {
        dbgMsgBox(true, dbgHeader, "Error: Not home screen.")
        return -1
    }
    dbgMsgBox(dbgEnable, dbgHeader, "screen verified.")

    ; --------------------------------------------------------------------------------
    ; Drag the target field from wherever on screen so it is in suitable pos.
    ; Use knowledge of center field row/col and screen coord to get screen coords for the rest.
    dragStartCoords := GetScreenCoordFromRowCol(rc_fieldToDragStart, g_RC_CenterField, [g_CenterFieldScreenCoords_X, g_CenterFieldScreenCoords_Y])
    dragEndCoords := GetScreenCoordFromRowCol(rc_fieldToDragEnd, g_RC_CenterField, [g_CenterFieldScreenCoords_X, g_CenterFieldScreenCoords_Y])

    MouseMoveDLL(dragStartCoords)

    dbgMsgBox(dbgEnable, dbgHeader, "at dragStartCoords")
    dbgWait(dbgEnableWait, dbgHeader)

    ; Drag to position.
    MouseDragDLL(dragStartCoords, dragEndCoords)

    dbgMsgBox(dbgEnable, dbgHeader, "at dragEndCoords")
    dbgWait(dbgEnableWait, dbgHeader)
    ; --------------------------------------------------------------------------------

    ; Verify home screen
    if ( IsScreenHome() <= 0 ) {
        dbgMsgBox(true, dbgHeader, "Error: Not home screen.")
        return -1
    }

    ; Now the center field (at the same center screen pixel pos) is another field.
    rc_diff := vec2_sub(rc_fieldToDragStart, rc_fieldToDragEnd)
    g_RC_CenterField := vec2_add( g_RC_CenterField, rc_diff )

    msg := "Center field px: " . g_CenterFieldScreenCoords_X . ", " . g_CenterFieldScreenCoords_Y
    msg := msg . " field: " . vec2_toString( g_RC_CenterField )
    dbgMsgBox(dbgEnable, dbgHeader, msg)
    dbgWait(dbgEnableWait, dbgHeader, 3000)
    ; TODO - To GUI
    GuiControl,, GuiTxtRow19, %msg%

    dbgMsgBox(dbgEnable, dbgHeader, "Finished.")
    dbgWait(dbgEnableWait, dbgHeader, 1000)

    return 1
}


; Returns screen coordinates for a field.
;
; Requires:
;  Legal action - the field must be on screen.
GetScreenCoordFromRowCol(rc_target, rc_center, screenCoords_center) {
    dbgEnable := true
    dbgHeader := "GetScreenCoordFromRowCol"
    dbgEnableWait := dbgEnable && false

    msg := "rc_target: " . rc_target[1] . ", " . rc_target[2]
    dbgMsgBox(dbgEnable, dbgHeader, msg)
    dbgWait(dbgEnableWait, dbgHeader)

    msg := "rc_center: " . rc_center[1] . ", " . rc_center[2]
    dbgMsgBox(dbgEnable, dbgHeader, msg)
    dbgWait(dbgEnableWait, dbgHeader)

    msg := "screenCoords_center: " . screenCoords_center[1] . ", " . screenCoords_center[2]
    dbgMsgBox(dbgEnable, dbgHeader, msg)
    dbgWait(dbgEnableWait, dbgHeader)

    diff_RC := [ rc_target[1]-rc_center[1], rc_target[2]-rc_center[2] ]

    ; These coords are not rounded. Good. works ok with AHK? 
    coords_target := TransformRowColDiffCoord(diff_RC)
    coords_target[1] += screenCoords_center[1]
    coords_target[2] += screenCoords_center[2]

    return coords_target
}


; Determines if the field is in a clickable area on screen. Computes the distance to the center field.
; Requires:
;  Scale
;  Correct screen
;
; Inputs:
;  Absolute field coords to field.
IsFieldOnScreen(rc_field) {
    global APP_TOP_LEFT_X, APP_TOP_LEFT_Y, APP_HEADER_Y, APP_SCALE
    global g_AppScaleExtra
    global g_RC_CenterField
    global g_CenterFieldScreenCoords_X, g_CenterFieldScreenCoords_Y

    dbgEnable := true
    dbgHeader := "IsFieldOnScreen"
    dbgEnableWait := dbgEnable && false

    ; Screen safe area
    x_rng := [APP_TOP_LEFT_X + 150*APP_SCALE, APP_TOP_LEFT_X + 850*APP_SCALE]
    y_rng := [APP_TOP_LEFT_Y + 170*APP_SCALE - APP_HEADER_Y, APP_TOP_LEFT_Y + 670*APP_SCALE - APP_HEADER_Y ]
    msg := "x, y ranges: " . x_rng[1] . ", " x_rng[2] . " / " . y_rng[1] . ", " . y_rng[2]
    dbgMsgBox(dbgEnable, dbgHeader, msg)
    dbgWait(dbgEnableWait, dbgHeader)

    diffCoords := TransformRowColDiffCoord( vec2_sub(rc_field, g_RC_CenterField) )
    msg := "diff screen coords: " . diffCoords[1] . ", " diffCoords[2]
    dbgMsgBox(dbgEnable, dbgHeader, msg)
    dbgWait(dbgEnableWait, dbgHeader)

    msg := "center screen coords: " . g_CenterFieldScreenCoords_X . ", " g_CenterFieldScreenCoords_Y
    dbgMsgBox(dbgEnable, dbgHeader, msg)
    dbgWait(dbgEnableWait, dbgHeader)

    fieldCoords := vec2_add(diffCoords, [g_CenterFieldScreenCoords_X, g_CenterFieldScreenCoords_Y])

    MouseMoveDLL(fieldCoords)    
    msg := "field screen coords: " . vec2_toString( fieldCoords )
    dbgMsgBox(dbgEnable, dbgHeader, msg)
    dbgWait(dbgEnableWait, dbgHeader)

    ; Are screen coords of field on screen?
    if ( fieldCoords[1] <= x_rng[2] && fieldCoords[1] >= x_rng[1] && fieldCoords[2] <= y_rng[2] && fieldCoords[2] >= y_rng[1] ) {
        return 1
    }
    return 0
}


; Goes to home screen, top left (ref) and finds out the scale. 
;
; Modifies global variables:
;  g_CenterFieldScreenCoords_X, g_CenterFieldScreenCoords_Y
;
; Inputs:
;  isAtReferencePosition  - optional to skip going here.
;  useThisScale           - optional to provide a scale.
InitialiseScrenCoordinates(isAtReferencePosition := false, useThisScale := -1) {
    dbgEnable := true
    dbgHeader := "InitialiseScrenCoordinates"
    dbgEnableWait := dbgEnable && true

    global g_CenterFieldScreenCoordsRaw_X, g_CenterFieldScreenCoordsRaw_Y
    global g_CenterFieldScreenCoords_X, g_CenterFieldScreenCoords_Y

    global g_RC_CenterField ; For info, not used.
    global g_AppScaleExtra

    global g_RC_CenterField, g_RC_CenterField_Raw

    dbgMsgBox(dbgEnable, dbgHeader, "Started.")
    dbgWait(dbgEnableWait, dbgHeader, 2000)

    ; Go to reference area.
    if ( !isAtReferencePosition ) {
        res := GoToHome()
        if ( res < 1 ) {
            ; Error
            dbgMsgBox(true, dbgHeader, "Error: Could not go to home screen.")
            dbgWait(dbgEnableWait, dbgHeader, 2000)

            return -1
        }

        res := GoTopLeftReference()
        if ( res < 1 ) {
            ; Error
            dbgMsgBox(true, dbgHeader, "Error: Could not go to top left.")
            dbgWait(dbgEnableWait, dbgHeader, 2000)

            return -1
        }
    }


    ; At the reference, find out the screen scale.
    if ( useThisScale < 0 ) {
        res := FindExtraAppScale(20.0)
        scale    := res[1]
        pixelPos := res[2]

        msg := "scale / pixel: " . scale . ", " . pixelPos
        dbgMsgBox(dbgEnable, dbgHeader, msg)

        if ( scale < 0 ) {
            ; Error
            dbgMsgBox(true, dbgHeader, "Error: Could not calculate scale.")
            dbgWait(dbgEnableWait, dbgHeader, 2000)

            return -1
        }
    }
    else {
        scale := useThisScale
    }

    ; Reset the field row/col
    g_RC_CenterField := g_RC_CenterField_Raw


    ; Use this scale modifier - XXX
    SCALE_MODIFIER := 1.0   ; At found scale 1.02, and at fields further away from top left, this modifier is good.
    if ( scale > 1.02) {
        SCALE_MODIFIER := 1.0 - 0.3/0.08 * (scale - 1.02)
    }

    ; MsgBox,,,orig scale: %scale%
    if (scale > 1.0) {
        scale := 1.0 + SCALE_MODIFIER*(scale - 1.0)    ; There is something wrong with scale detect (or stored edge value) so using 0.8 as modifier.
    }
    g_AppScaleExtra := scale


    ; Re-calculate coordinates. Needed for all map coordinates, but not for any shop / main icon coordinates.
    ; Careful don't destroy the RAW, which all belong together and are measured at the "default max zoom out" (with whatever extra zoom 
    ;  hayday applied when doing this manually)
    g_CenterFieldScreenCoords_X := g_CenterFieldScreenCoordsRaw_X * g_AppScaleExtra
    g_CenterFieldScreenCoords_Y := g_CenterFieldScreenCoordsRaw_Y * g_AppScaleExtra
    g_CenterFieldScreenCoords_X := Ceil( AC2SC(g_CenterFieldScreenCoords_X, 0) )
    g_CenterFieldScreenCoords_Y := Ceil( AC2SC(g_CenterFieldScreenCoords_Y, 1) )

    ; To GUI
    msg := "Center field px: " . vec2_toString( [g_CenterFieldScreenCoords_X, g_CenterFieldScreenCoords_Y] )
    msg := msg . " field: " . vec2_toString( g_RC_CenterField ) 
    GuiControl,, GuiTxtRow19, %msg%
    GuiControl,, GuiTxtScale, %scale%

    ; Position mouse on the center field in screen. This will be different x, y depending on the scale.
    if (dbgEnable) {
        msg := "Moving mouse to the CENTER_FIELD_COORD. Scale is: " . scale
        dbgMsgBox(dbgEnable, dbgHeader, msg)
        MouseMoveDLL([g_CenterFieldScreenCoords_X, g_CenterFieldScreenCoords_Y])
        dbgWait(dbgEnableWait, dbgHeader, 2000)
    }

    return 1
}


; Combined function, takes a little longer.
; Returns: 1 / 0 / <0
IsScreen(screenSelection) {
    global SCREEN_FRIEND, SCREEN_HOME, SCREEN_LOADING, SCREEN_CONNECTION_LOST
    global SCREEN_SILO_BARN_FULL

    dbgEnable := false
    dbgHeader := "IsScreen"

    if ( screenSelection = SCREEN_HOME ) {
        dbgMsgBox(dbgEnable, dbgHeader, "Checking for IsScreenHome.")
        return IsScreenHome()
    }
    else if ( screenSelection = SCREEN_FRIEND ) {
        dbgMsgBox(dbgEnable, dbgHeader, "Checking for IsScreenFriend.")
        return IsScreenFriend()
    }
    else if ( screenSelection = SCREEN_LOADING ) {
        dbgMsgBox(dbgEnable, dbgHeader, "Checking for IsScreenLoading.")
        return IsScreenLoading()
    }
    else if ( screenSelection = SCREEN_CONNECTION_LOST ) {
        dbgMsgBox(dbgEnable, dbgHeader, "Checking for IsScreenConnectionLost.")
        return IsScreenConnectionLost()
    }
    else if ( screenSelection = SCREEN_SILO_BARN_FULL ) {
        dbgMsgBox(dbgEnable, dbgHeader, "Checking for IsScreenSiloBarnFull.")
        return IsScreenSiloBarnFull()
    }
}


;TODO
CloseScreen(screenSelection) {
    return -1
}


; Returns:
;  1: It possibly was this screen.
;  0: It wasn't this screen.
CloseScreenBigBox() {
    global RED_X_BIG_BOX_X, RED_X_BIG_BOX_Y

    x_target := RED_X_BIG_BOX_X
    y_target := RED_X_BIG_BOX_Y

    MouseGetPos, x, y
    res := IsCloseButtonAtPos( [x_target, y_target] )
    if ( res ) {
        MouseClick, left, x_target, y_target
        Sleep, 500
    } 
    MouseMove, x, y
    return res
}

; Asserts whether the current screen is a loading screen. TODO - Only checks the winter loading screen.
IsScreenLoading() {
    global LOAD_SCREEN_P1_X, LOAD_SCREEN_P1_Y, LOAD_SCREEN_P2_X, LOAD_SCREEN_P2_Y
    global LOAD_SCREEN_P3_X, LOAD_SCREEN_P3_Y, LOAD_SCREEN_P4_X, LOAD_SCREEN_P4_Y
    global LOAD_SCREEN_C
    global LOAD_SCREEN_SUMMER_PP1_X, LOAD_SCREEN_SUMMER_P1_Y, LOAD_SCREEN_SUMMER_P2_X, LOAD_SCREEN_SUMMER_P2_Y
    global LOAD_SCREEN_SUMMER_P3_X, LOAD_SCREEN_SUMMER_P3_Y, LOAD_SCREEN_SUMMER_P4_X, LOAD_SCREEN_SUMMER_P4_Y
    global LOAD_SCREEN_SUMMER_P1_C, LOAD_SCREEN_SUMMER_P2_C, LOAD_SCREEN_SUMMER_P3_C, LOAD_SCREEN_SUMMER_P4_C

    x1 := LOAD_SCREEN_SUMMER_PP1_X
    y1 := LOAD_SCREEN_SUMMER_P1_Y
    c1 := LOAD_SCREEN_SUMMER_P1_C

    x2 := LOAD_SCREEN_SUMMER_P2_X
    y2 := LOAD_SCREEN_SUMMER_P2_Y
    c2 := LOAD_SCREEN_SUMMER_P2_C

    x3 := LOAD_SCREEN_SUMMER_P3_X
    y3 := LOAD_SCREEN_SUMMER_P3_Y
    c3 := LOAD_SCREEN_SUMMER_P3_C

    x4 := LOAD_SCREEN_SUMMER_P4_X
    y4 := LOAD_SCREEN_SUMMER_P4_Y
    c4 := LOAD_SCREEN_SUMMER_P4_C

    ; Check colors for screen
    hits := 0

    PixelGetColor, col, x1, y1, RGB
    if (col = c1) {
        hits++
    }
    PixelGetColor, col, x2, y2, RGB
    if (col = c2) {
        hits++
    }
    PixelGetColor, col, x3, y3, RGB
    if (col = c3) {
        hits++
    }
    PixelGetColor, col, x4, y4, RGB
    if (col = c4) {
        hits++
    }

    if (hits >= 3) {
        return true
    }
    return false
}


IsScreenMansion() {
    return IsMansionRedX()
}


IsMansionRedX() {
    global RED_X_MANSION_X, RED_X_MANSION_Y

    x_target := RED_X_MANSION_X
    y_target := RED_X_MANSION_Y

    return IsCloseButtonAtPos([x_target, y_target])
}


CloseScreenMansion() {
    global RED_X_MANSION_X, RED_X_MANSION_Y

    x_target := RED_X_MANSION_X
    y_target := RED_X_MANSION_Y

    MouseGetPos, x, y
    res := IsCloseButtonAtPos( [x_target, y_target] )
    if ( res ) {
        MouseClick, left, x_target, y_target
    } 
    MouseMove, x, y
    return res    
}


; TODO make a "CheckFourSimilarColors" for reuse
; Asserts whether the current screen is a Connection Lost screen.
IsScreenConnectionLost() {
    global LOST_SCREEN_P1_X
    global LOST_SCREEN_P1_Y
    global LOST_SCREEN_P1_C
    global LOST_SCREEN_P2_X
    global LOST_SCREEN_P2_Y
    global LOST_SCREEN_P2_C
    global LOST_SCREEN_P3_X
    global LOST_SCREEN_P3_Y
    global LOST_SCREEN_P3_C
    global LOST_SCREEN_P4_X
    global LOST_SCREEN_P4_Y
    global LOST_SCREEN_P4_C
    global BTN_TRY_AGAIN_X
    global BTN_TRY_AGAIN_Y

    MouseGetPos, x, y
    res := IsSimilarFourColor(LOST_SCREEN_P1_X, LOST_SCREEN_P1_Y, LOST_SCREEN_P1_C, LOST_SCREEN_P2_X, LOST_SCREEN_P2_Y, LOST_SCREEN_P2_C, LOST_SCREEN_P3_X, LOST_SCREEN_P3_Y, LOST_SCREEN_P3_C, LOST_SCREEN_P4_X, LOST_SCREEN_P4_Y, LOST_SCREEN_P4_C)
    MouseMove, x, y
    return res
}


; Asserts whether the current screen is the home screen with the mansion.
IsScreenHome() {
    dbgEnable := false
    dbgHeader := "IsScreenHome"

    global HOME_SCREEN_P1_X
    global HOME_SCREEN_P1_Y
    global HOME_SCREEN_P1_C
    global HOME_SCREEN_P2_X
    global HOME_SCREEN_P2_Y
    global HOME_SCREEN_P2_C
    global HOME_SCREEN_P3_X
    global HOME_SCREEN_P3_Y
    global HOME_SCREEN_P3_C
    global HOME_SCREEN_P4_X
    global HOME_SCREEN_P4_Y
    global HOME_SCREEN_P4_C


    P1_X := HOME_SCREEN_P1_X
    P1_Y := HOME_SCREEN_P1_Y
    P1_C := HOME_SCREEN_P1_C
    P2_X := HOME_SCREEN_P2_X
    P2_Y := HOME_SCREEN_P2_Y
    P2_C := HOME_SCREEN_P2_C
    P3_X := HOME_SCREEN_P3_X
    P3_Y := HOME_SCREEN_P3_Y
    P3_C := HOME_SCREEN_P3_C
    P4_X := HOME_SCREEN_P4_X
    P4_Y := HOME_SCREEN_P4_Y
    P4_C := HOME_SCREEN_P4_C

    MouseGetPos, x, y
    res := IsSimilarFourColor(P1_X, P1_Y, P1_C, P2_X, P2_Y, P2_C, P3_X, P3_Y, P3_C, P4_X, P4_Y, P4_C)
    MouseMove, x, y

    dbgMsgBox(dbgEnable, dbgHeader, res)

    return res
}


; Asserts whether the current screen is the friend screen with the mansion.
IsScreenFriend() {
    global FRIEND_SCREEN_P1_X
    global FRIEND_SCREEN_P1_Y
    global FRIEND_SCREEN_P1_C
    global FRIEND_SCREEN_P2_X
    global FRIEND_SCREEN_P2_Y
    global FRIEND_SCREEN_P2_C
    global FRIEND_SCREEN_P3_X
    global FRIEND_SCREEN_P3_Y
    global FRIEND_SCREEN_P3_C
    global FRIEND_SCREEN_P4_X
    global FRIEND_SCREEN_P4_Y
    global FRIEND_SCREEN_P4_C

    MouseGetPos, x, y
    res := IsSimilarFourColor(FRIEND_SCREEN_P1_X, FRIEND_SCREEN_P1_Y, FRIEND_SCREEN_P1_C, FRIEND_SCREEN_P2_X, FRIEND_SCREEN_P2_Y, FRIEND_SCREEN_P2_C, FRIEND_SCREEN_P3_X, FRIEND_SCREEN_P3_Y, FRIEND_SCREEN_P3_C, FRIEND_SCREEN_P4_X, FRIEND_SCREEN_P4_Y, FRIEND_SCREEN_P4_C)
    MouseMove, x, y
    return res
}


; Shows on screen for troubleshooting
ShowDetectionScreenHome() {
    global HOME_SCREEN_P1_X
    global HOME_SCREEN_P1_Y
    global HOME_SCREEN_P1_C
    global HOME_SCREEN_P2_X
    global HOME_SCREEN_P2_Y
    global HOME_SCREEN_P2_C
    global HOME_SCREEN_P3_X
    global HOME_SCREEN_P3_Y
    global HOME_SCREEN_P3_C
    global HOME_SCREEN_P4_X
    global HOME_SCREEN_P4_Y
    global HOME_SCREEN_P4_C

    P1_X := HOME_SCREEN_P1_X
    P1_Y := HOME_SCREEN_P1_Y
    P1_C := HOME_SCREEN_P1_C
    P2_X := HOME_SCREEN_P2_X
    P2_Y := HOME_SCREEN_P2_Y
    P2_C := HOME_SCREEN_P2_C
    P3_X := HOME_SCREEN_P3_X
    P3_Y := HOME_SCREEN_P3_Y
    P3_C := HOME_SCREEN_P3_C
    P4_X := HOME_SCREEN_P4_X
    P4_Y := HOME_SCREEN_P4_Y
    P4_C := HOME_SCREEN_P4_C

    MouseGetPos, x, y
    ShowFourCoords(P1_X, P1_Y, P2_X, P2_Y, P3_X, P3_Y, P4_X, P4_Y)
    MouseMove, x, y
}


; For debug, use WindowSpy to verify.
ShowFourCoords(_1_X, _1_Y, _2_X, _2_Y, _3_X, _3_Y, _4_X, _4_Y) {
    MouseMove, _1_X, _1_Y, 50
    MsgBox,,,Click to show next.,1
    MouseMove, _2_X, _2_Y, 5o
    MsgBox,,,Click to show next.,1
    MouseMove, _3_X, _3_Y, 50
    MsgBox,,,Click to show next.,1
    MouseMove, _4_X, _4_Y, 50
    MsgBox,,,Click to show next.,1
}


; Returns:
;  Red X found (IsCloseButtonAtPos)
CloseScreenSiloBarnFull() {
    global RED_X_SILO_BARN_FULL_X, RED_X_SILO_BARN_FULL_Y

    target_pos := [RED_X_SILO_BARN_FULL_X, RED_X_SILO_BARN_FULL_Y]

    MouseGetPos, x, y
    loop, 3 {
        res := IsCloseButtonAtPos( target_pos )
        if ( res > 0 ) {
            MouseMoveDLL( target_pos )
            Sleep, 200
            Click        
            Sleep, 200

            if ( IsScreenSiloBarnFull() = 0 ) {
                break
            }
        }
    }

    ; Return mouse    
    MouseMoveDLL([x, y])

    return res 
}


; In shop when buying and silo or barn is full
IsScreenSiloBarnFull() {
    global SILO_BARN_FULL_1_X
    global SILO_BARN_FULL_1_Y
    global SILO_BARN_FULL_1_C
    global SILO_BARN_FULL_2_X
    global SILO_BARN_FULL_2_Y
    global SILO_BARN_FULL_2_C
    global SILO_BARN_FULL_3_X
    global SILO_BARN_FULL_3_Y
    global SILO_BARN_FULL_3_C
    global SILO_BARN_FULL_4_X
    global SILO_BARN_FULL_4_Y
    global SILO_BARN_FULL_4_C

    _1_X := SILO_BARN_FULL_1_X
    _1_Y := SILO_BARN_FULL_1_Y
    _1_C := SILO_BARN_FULL_1_C
    _2_X := SILO_BARN_FULL_2_X
    _2_Y := SILO_BARN_FULL_2_Y
    _2_C := SILO_BARN_FULL_2_C
    _3_X := SILO_BARN_FULL_3_X
    _3_Y := SILO_BARN_FULL_3_Y
    _3_C := SILO_BARN_FULL_3_C
    _4_X := SILO_BARN_FULL_4_X
    _4_Y := SILO_BARN_FULL_4_Y
    _4_C := SILO_BARN_FULL_4_C

    MouseGetPos, x, y
    res := IsShopSiloBarnFullRedX() && IsSimilarFourColor(_1_X, _1_Y, _1_C, _2_X, _2_Y, _2_C, _3_X, _3_Y, _3_C, _4_X, _4_Y, _4_C)
    MouseMove, x, y
    return res
}


; Returns mouse to original postition.
; Returns
;  1 : In home screen after.
; -1 : Not in home screen after.
GoToHome() {
    global SCREEN_FRIEND, SCREEN_HOME, SCREEN_LOADING, SCREEN_CONNECTION_LOST
    global SCREEN_SILO_BARN_FULL

    dbgEnable := true
    dbgHeader := "GoToHome"

    MouseGetPos, x, y

    MAX_TRIES := 5
    cnt := 0
    loop {
        dbgMsgBox(dbgEnable, dbgHeader, "Checking possible screens...")
        cnt++

        dbgMsgBox(dbgEnable, dbgHeader, "Checking SCREEN_FRIEND")
        if ( IsScreen(SCREEN_FRIEND) > 0 ) {
            dbgMsgBox(dbgEnable, dbgHeader, "SCREEN_FRIEND")
            PressHomeButton()
            sleep, 2000
            Continue
        }

        dbgMsgBox(dbgEnable, dbgHeader, "Checking SCREEN_HOME")
        if ( IsScreen(SCREEN_HOME) > 0 ) {
            dbgMsgBox(dbgEnable, dbgHeader, "SCREEN_HOME")
            break
        }

        if ( IsHomeButtonVisible() > 0 ) {
            dbgMsgBox(dbgEnable, dbgHeader, "IsHomeButtonVisible")
            PressHomeButton()
            sleep, 2000
            Continue
        }

        dbgMsgBox(dbgEnable, dbgHeader, "Checking SCREEN_SILO_BARN_FULL")
        if ( IsScreen(SCREEN_SILO_BARN_FULL) > 0 ) {
            dbgMsgBox(dbgEnable, dbgHeader, "SCREEN_SILO_BARN_FULL")
            CloseScreenSiloBarnFull()
            sleep, 500
            Continue
        }

        dbgMsgBox(dbgEnable, dbgHeader, "Checking IsInShop")
        if ( IsInShop() > 0 ) {
            dbgMsgBox(dbgEnable, dbgHeader, "IsInShop")
            CloseShop()
            sleep, 500
            Continue
        }

        dbgMsgBox(dbgEnable, dbgHeader, "Checking IsInEditSale")
        if ( IsInEditSale() > 0 ) {
            dbgMsgBox(dbgEnable, dbgHeader, "IsInEditSale")
            CloseEditSale()
            sleep, 500
            Continue
        }

        dbgMsgBox(dbgEnable, dbgHeader, "Checking CloseNewSale")
        if ( IsInNewSale() > 0 ) {
            dbgMsgBox(dbgEnable, dbgHeader, "CloseNewSale")
            CloseNewSale()
            sleep, 500
            Continue
        }

        if ( IsScreen(SCREEN_LOADING) > 0 ) {
            dbgMsgBox(dbgEnable, dbgHeader, "IsScreenLoading")
            sleep, 5000
            Continue
        }

        if ( IsScreen(SCREEN_CONNECTION_LOST) > 0 ) {
            dbgMsgBox(dbgEnable, dbgHeader, "IsScreenConnectionLost")
            CloseConnectionLostScreen()
            sleep, 5000
            Continue
        }

        if ( cnt >= MAX_TRIES ) {
            msg := "Error: Tried to go to home screen " . MAX_TRIES . " times."
            dbgMsgBox(true, dbgHeader, msg)
            return -1
        }
    }

    MouseMove, x, y
    return 1
}


; Assuming it is there
; Returns: -
PressHomeButton() {
    global BTN_HOME_X, BTN_HOME_Y

    x := BTN_HOME_X
    y := BTN_HOME_Y
    MouseMove, x, y, 0
    Click
}


; Returns:
;  0 / 1
IsHomeButtonVisible() {
    global HOME_ICON_P1_X
    global HOME_ICON_P1_Y
    global HOME_ICON_P1_C
    global HOME_ICON_P2_X
    global HOME_ICON_P2_Y
    global HOME_ICON_P2_C
    global HOME_ICON_P3_X
    global HOME_ICON_P3_Y
    global HOME_ICON_P3_C
    global HOME_ICON_P4_X
    global HOME_ICON_P4_Y
    global HOME_ICON_P4_C

    P1_X := HOME_ICON_P1_X
    P1_Y := HOME_ICON_P1_Y
    P1_C := HOME_ICON_P1_C
    P2_X := HOME_ICON_P2_X
    P2_Y := HOME_ICON_P2_Y
    P2_C := HOME_ICON_P2_C
    P3_X := HOME_ICON_P3_X
    P3_Y := HOME_ICON_P3_Y
    P3_C := HOME_ICON_P3_C
    P4_X := HOME_ICON_P4_X
    P4_Y := HOME_ICON_P4_Y
    P4_C := HOME_ICON_P4_C


    MouseGetPos, x, y
    res := IsSimilarFourColor(P1_X, P1_Y, P1_C, P2_X, P2_Y, P2_C, P3_X, P3_Y, P3_C, P4_X, P4_Y, P4_C)
    MouseMove, x, y

    return res
}

; Shows on screen for troubleshooting
ShowDetectionHomeButton() {
    global HOME_ICON_P1_X
    global HOME_ICON_P1_Y
    global HOME_ICON_P1_C
    global HOME_ICON_P2_X
    global HOME_ICON_P2_Y
    global HOME_ICON_P2_C
    global HOME_ICON_P3_X
    global HOME_ICON_P3_Y
    global HOME_ICON_P3_C
    global HOME_ICON_P4_X
    global HOME_ICON_P4_Y
    global HOME_ICON_P4_C

    P1_X := HOME_ICON_P1_X
    P1_Y := HOME_ICON_P1_Y
    P1_C := HOME_ICON_P1_C
    P2_X := HOME_ICON_P2_X
    P2_Y := HOME_ICON_P2_Y
    P2_C := HOME_ICON_P2_C
    P3_X := HOME_ICON_P3_X
    P3_Y := HOME_ICON_P3_Y
    P3_C := HOME_ICON_P3_C
    P4_X := HOME_ICON_P4_X
    P4_Y := HOME_ICON_P4_Y
    P4_C := HOME_ICON_P4_C

    MouseGetPos, x, y
    ShowFourCoords(P1_X, P1_Y, P2_X, P2_Y, P3_X, P3_Y, P4_X, P4_Y)
    MouseMove, x, y
}


; TODO - Lägg till alla röda X som känns till. Eller trycka ute i kanten tills man 
;  ska vara på aningen Home lr Friend.
; Returns:
;  1 : Locking screen found and tried to close
TryGetRidOfBlockingScreen() {
    dbgEnable := true
    dbgHeader := "TryGetRidOfBlockingScreen"

    if ( IsScreenLoading() > 0 ) {
        dbgMsgBox(dbgEnable, dbgHeader, "IsScreenLoading")
        sleep, 5000
        return 1
    }

    if ( IsScreenConnectionLost() > 0 ) {
        dbgMsgBox(dbgEnable, dbgHeader, "IsScreenConnectionLost")
        CloseConnectionLostScreen()
        return 1
    }
}


; Returns:
;   1: Was in screen, and clicked. Verifies then that not in screen any more.
;  -1: Wasn't in screen. 
CloseConnectionLostScreen() {
    global BTN_TRY_AGAIN_X, BTN_TRY_AGAIN_Y

    MouseGetPos, x, y

    if ( IsScreenConnectionLost() > 0 ) {
        MouseMove, BTN_TRY_AGAIN_X, BTN_TRY_AGAIN_Y, 0
        Click
        ; Reloading time
        Sleep, 5000
        if ( IsScreenConnectionLost() = 0 ) {
            res := 1
        }
        else {
            res := -1
        }
    }
    else {
        res := -1
    }

    MouseMove, x, y
    return res
}

; ------------------------------------------------------------------------------------------------







; ------------------------------------------------------------------------------------------------
; Functions regarding harvest.


; Detects if sickle is in the overlay, ready to harvest.
;
; Requires:
;   a pressed field so the sickle selection is open.
;
; Inputs:
;   center pos of the clicked field that opened the selection overlay.
;
; Outputs:
;   Sickle visible 0 / 1
IsSickleOnOverlay(refPos) {
    dbgEnable := true
    dbgHeader :="IsSickleOnOverlay"
    dbgEnableWait := dbgEnable && false

    global SICKLE_DETECT_P1_X
    global SICKLE_DETECT_P1_Y
    global SICKLE_DETECT_P1_C
    global SICKLE_DETECT_P2_X
    global SICKLE_DETECT_P2_Y
    global SICKLE_DETECT_P2_C
    global SICKLE_DETECT_P3_X
    global SICKLE_DETECT_P3_Y
    global SICKLE_DETECT_P3_C
    global SICKLE_DETECT_P4_X
    global SICKLE_DETECT_P4_Y
    global SICKLE_DETECT_P4_C

    P1_X := SICKLE_DETECT_P1_X + refPos[1]
    P1_Y := SICKLE_DETECT_P1_Y + refPos[2]
    P1_C := SICKLE_DETECT_P1_C
    P2_X := SICKLE_DETECT_P2_X + refPos[1]
    P2_Y := SICKLE_DETECT_P2_Y + refPos[2]
    P2_C := SICKLE_DETECT_P2_C
    P3_X := SICKLE_DETECT_P3_X + refPos[1]
    P3_Y := SICKLE_DETECT_P3_Y + refPos[2]
    P3_C := SICKLE_DETECT_P3_C
    P4_X := SICKLE_DETECT_P4_X + refPos[1]
    P4_Y := SICKLE_DETECT_P4_Y + refPos[2]
    P4_C := SICKLE_DETECT_P4_C

    ; Show it.
    if ( dbgEnable ) {
        MouseMoveDLL([P2_X,P2_Y])
        Sleep, 300
        MouseMoveDLL([P3_X,P3_Y])
        Sleep, 300
        MouseMoveDLL([P4_X,P4_Y])
        Sleep, 300
    }

    ; Sickle is determined by greyscale on the sickle due to the contrasts on it.
    dbgMsgBox(dbgEnable, dbgHeader, "Checking color... ")
    dbgWait(dbgEnableWait, dbgHeader, 1000)

    PixelGetColor, col, P1_X, P1_Y, RGB
    res := IsAlmostSameColor(col, P1_C)
    if ( res = 1) {
        dbgMsgBox(dbgEnable, dbgHeader, "Color 1 ok.")
        dbgWait(dbgEnableWait, dbgHeader, 1000)

        res := IsGrayScaleAtPos([P3_X, P3_Y])
        if ( res = 1) {
            dbgMsgBox(dbgEnable, dbgHeader, "Color 2 ok.")
            dbgWait(dbgEnableWait, dbgHeader, 1000)

            res := IsGrayScaleAtPos([P4_X, P4_Y])
            if ( res = 1) {
                dbgMsgBox(dbgEnable, dbgHeader, "Color 3 ok.")
                dbgWait(dbgEnableWait, dbgHeader, 1000)

                return 1
            }
        }
    }

    dbgMsgBox(dbgEnable, dbgHeader, "No sickle.")
    dbgWait(dbgEnableWait, dbgHeader, 1000)

    return 0
}


; Detects if prograss bar is seen, crop is maturing.
;
; Requires:
;   a pressed field so the progrss bar can be open.
;
; Inputs:
;   center pos of the clicked field that opened the selection overlay / prograss bar.
;
; Outputs:
;   Bar visible 0 / 1
IsCropProgressBar(refPos) {
    global CROP_PROGRESS_P1_X
    global CROP_PROGRESS_P1_Y
    global CROP_PROGRESS_P1_C
    global CROP_PROGRESS_P2_X
    global CROP_PROGRESS_P2_Y
    global CROP_PROGRESS_P2_C
    global CROP_PROGRESS_P3_X
    global CROP_PROGRESS_P3_Y
    global CROP_PROGRESS_P3_C
    global CROP_PROGRESS_P4_X
    global CROP_PROGRESS_P4_Y
    global CROP_PROGRESS_P4_C

    P1_X := CROP_PROGRESS_P1_X + refPos[1]
    P1_Y := CROP_PROGRESS_P1_Y + refPos[2]
    P1_C := CROP_PROGRESS_P1_C
    P2_X := CROP_PROGRESS_P2_X + refPos[1]
    P2_Y := CROP_PROGRESS_P2_Y + refPos[2]
    P2_C := CROP_PROGRESS_P2_C
    P3_X := CROP_PROGRESS_P3_X + refPos[1]
    P3_Y := CROP_PROGRESS_P3_Y + refPos[2]
    P3_C := CROP_PROGRESS_P3_C
    P4_X := CROP_PROGRESS_P4_X + refPos[1]
    P4_Y := CROP_PROGRESS_P4_Y + refPos[2]
    P4_C := CROP_PROGRESS_P4_C

    return IsSimilarFourColor(P1_X,P1_Y,P1_C, P2_X,P2_Y,P2_C, P3_X,P3_Y,P3_C, P4_X,P4_Y,P4_C)
}


; Returns what crop plant selection screen is open.
;
; Requires:
;   a pressed field so the plant selection is open.
;
; Inputs:
;   center pos of the clicked field that opened the selection overlay.
;   nbr of crop screens to check (optional, default 6)
;
; Outputs:
;  >0 : what selection screen is open
;   0 : screen could not be determined
;  -1 : home screen left
GetOpenCropPlantSelectScreen(refPos, nbrOfCropScreens := 6) {
    dbgEnable := true
    dbgHeader := "GetOpenCropPlantSelectScreen"

    global APP_SCALE
    
    global CROP_SELECT_SCREEN_IND_C
    global CROP_SELECT_SCREEN_IND1_X
    global CROP_SELECT_SCREEN_IND1_Y

    global CROP_SELECT_SCREEN_IND_DIFF

    IND_CIRCLE_DIFF := 2

    C := CROP_SELECT_SCREEN_IND_C
    Y := CROP_SELECT_SCREEN_IND1_Y + refPos[2]
    d := ceil( APP_SCALE*IND_CIRCLE_DIFF )

    scr := 1
    loop {
        X := CROP_SELECT_SCREEN_IND1_X + refPos[1] + (1-scr)*CROP_SELECT_SCREEN_IND_DIFF

        if ( dbgEnable ) {
            MouseMoveDLL([X, Y])
            Sleep, 300
        }

        res := IsSimilarFourColor(X-d, Y-d, C,  X+d, Y-d, C,  X+d, Y+d, C,  X+d, Y-d, C)
        if ( res = 1 ) {
            return scr
        }

        scr++
        if ( scr > nbrOfCropScreens ) {
            return 0
        }

        ; Validate screen.
        if ( IsScreenHome() <= 0 ) {
            return -1
        }
    }

    return 0
}


; Selects the target overlay screen for planting a crop.
;
; Requires:
;  a pressed field so the plant selection is open.
;
; Inputs:
;   center pos of the clicked field that opened the selection overlay.
;   crop item id
;
; Ouputs:
;   >0 : screen
;    0 : Did not find screen for crop.
;   -1 : home screen left
;   -2 : Input error
;   -3 : Error in GetHarvestScreenNbrForCrop
SelectPlantOverlayScreenForCrop(refPos, cropItemId) {
    global MAX_CROP_OVERLAY_SCREEN

    dbgEnable := true
    dbgHeader := "SelectPlantOverlayScreenForCrop"
    dbgEnableWait := dbgEnable && false

    dbgMsgBox(true, dbgHeader, "Started.")
    dbgWait(dbgEnableWait, dbgHeader, 1000)

    ; Validate inputs
    if ( cropItemId = "" ) {
        dbgMsgBox(true, dbgHeader, "Error: invalid cropItemId.")

        return -2
    }

    targetScreen := GetHarvestScreenNbrForCrop(cropItemId)
    if ( targetScreen <= 0 ) {
        dbgMsgBox(true, dbgHeader, "Error: invalid targetScreen.")
        
        return -3
    }

    ; Check if correct overlay is open.
    scr := GetOpenCropPlantSelectScreen(refPos)
    if ( scr = targetScreen ) {
        return targetScreen
    }

    dbgMsgBox(true, dbgHeader, "Started 2.")
    dbgWait(dbgEnableWait, dbgHeader, 1000)

    ; Select the correct overlay.
    n := 0
    loop {
        msg := "Looping screens to find the target: " . n
        dbgMsgBox(dbgEnable, dbgHeader, msg)
        dbgWait(dbgEnableWait, dbgHeader, 500)

        n++
        if ( n > MAX_CROP_OVERLAY_SCREEN ) {
            dbgMsgBox(dbgEnable, dbgHeader, "Looping done.")
            dbgWait(dbgEnableWait, dbgHeader, 1000)

            break
        }

        ; Validate home screen.
        if ( IsScreenHome() <= 0 ) {
            return -1
        }

        ; Click and loop through all overlays.
        scr := GetOpenCropPlantSelectScreen(refPos)
        if ( scr = targetScreen ) {
            ; Found
            dbgMsgBox(dbgEnable, dbgHeader, "Found.")
            return scr
        }
        else if ( scr < 0 ) {
            ; Error
            dbgMsgBox(true, dbgHeader, "Error.")
            return scr
        }
        else {
            ; Try next screen
            dbgMsgBox(dbgEnable, dbgHeader, "Selecting next screen.")
            dbgWait(dbgEnableWait, dbgHeader, 1000)

            SelectNextCropPlantSelectScreen(refPos)
            Sleep, 300
        }
    }

    dbgMsgBox(true, dbgHeader, "Error: Did not find screen for crop. Returns 0.")
    return 0
}



; Rotates the target overlay screen for planting a crop.
;
; Requires:
;  a pressed field so the plant selection is open.
;
; Inputs:
;   center pos of the clicked field that opened the selection overlay.
;
; Ouputs:
;   none
SelectNextCropPlantSelectScreen(refPos) {
    dbgEnable := true
    dbgHeader := "SelectNextCropPlantSelectScreen"

    ; Relative positions compared to the clicked field.
    global CROP_SELECT_SCREEN_SWITCH_X
    global CROP_SELECT_SCREEN_SWITCH_Y

    dbgMsgBox(true, dbgHeader, "Moving to position, then click.")
    MouseMoveDLL([CROP_SELECT_SCREEN_SWITCH_X + refPos[1], CROP_SELECT_SCREEN_SWITCH_Y + refPos[2]])
    Sleep, 100
    MouseClick, Left
    Sleep, 100
}


; Drags the pointer along rows and columns without mouse click. 
;   No mouseclick - handle outside function.
;
; Inputs:
;  screen coordinate of start (field)
;  nbr of rows
;  nbr of columns
;
; Outputs:
;  1 : ok
; -1 : Home screen left detected.
; -2 : Silo full
SweepArea(startScreenPos, nRow, nCol) {
    dbgEnable := true
    dbgHeader := "SweepArea"
    dbgEnableWait := dbgEnable && false

    siloBarnFull := false

    MouseMoveDLL(startScreenPos)
    row := 0
    loop {
        col := 0
        loop {
            ; Calculate each time and do not accumulate errors.
            coords := TransformRowColDiffCoord([row, col])
            x := startScreenPos[1] + coords[1]
            y := startScreenPos[2] + coords[2]

            ; Move through each field center, not too fast.
            MouseMove, x, y, 5

            col++
            if (col >= nCol ) {
                break
            }

            ; Verify screen in order to detect a reload.
            if ( Mod(col, 5) = 0 ) {
                if ( IsScreenHome() <= 0 ) {
                    if ( IsScreenSiloBarnFull() > 0 ) {
                        siloBarnFull := true
                        break
                    }
                    else {
                        dbgMsgBox(true, dbgHeader, "Error: home screen lost detected inner loop.")
                        dbgWait(dbgEnableWait, dbgHeader, 1000)

                        return -1
                    }
                }
            }
        }

        row++
        if ( row >= nRow || siloBarnFull ) {
            break
        }

        ; Verify screen in order to detect a reload.
        if ( IsScreenHome() <= 0 ) {
            if ( IsScreenSiloBarnFull() > 0 ) {
                siloBarnFull := true
                break
            }
            else {
                dbgMsgBox(true, dbgHeader, "Error: home screen lost detected outer loop.")
                dbgWait(dbgEnableWait, dbgHeader, 1000)

                return -1
            }
        }
    }

    ; Clear any open?
    if ( siloBarnFull ) {
        dbgMsgBox(true, dbgHeader, "Closing silo barn full screen.")
        dbgWait(dbgEnableWait, dbgHeader, 2000)

        CloseScreenSiloBarnFull()
        return -2
    }

    return 1
}


; Checks what type of overlay was opened.
; Requires overlay is open by clicked field.
;
; Inputs:
;  screen coordinate of start (field)
;  nbr of crop screens to check (optional, default 6)
;
; Outputs:
;   3 : Empty field ready to plant
;   2 : Sickle
;   1 : Crop maturing
;   0 : None found
;  -1 : Home screen left.
GetCropOverlayType(startScreenPos, nbrOfCropScreens := 6) {

    global CROP_OVERLAY_SICKLE      
    global CROP_OVERLAY_PROGRESS_BAR
    global CROP_OVERLAY_CROPS

    dbgEnable := true
    dbgHeader := "GetCropOverlayType"
    dbgEnableWait := dbgEnable && true

    ; Validate sickle
    dbgMsgBox(dbgEnable, dbgHeader, "Validate IsSickleOnOverlay")

    if ( IsSickleOnOverlay(startScreenPos) = 1 ) {
        return CROP_OVERLAY_SICKLE
    }

    ; Validate home screen
    dbgMsgBox(dbgEnable, dbgHeader, "Validate home screen")

    if ( IsScreenHome() <= 0 ) {
        return -1
    }

    ; Validate progress bar
    dbgMsgBox(dbgEnable, dbgHeader, "Validate IsCropProgressBar")

    if ( IsCropProgressBar(startScreenPos) = 1 ) {
        return CROP_OVERLAY_PROGRESS_BAR
    }

    ; Validate home screen
    dbgMsgBox(dbgEnable, dbgHeader, "Validate home screen")

    if ( IsScreenHome() <= 0 ) {
        return -1
    }

    ; Validate any crop screen.
    dbgMsgBox(dbgEnable, dbgHeader, "Validate any crop screen")

    if ( GetOpenCropPlantSelectScreen( startScreenPos, nbrOfCropScreens ) > 0 ) {
        return CROP_OVERLAY_CROPS
    }

    ; Validate home screen
    dbgMsgBox(dbgEnable, dbgHeader, "Validate home screen")

    if ( IsScreenHome() <= 0 ) {
        dbgMsgBox(true, dbgHeader, "Error: Home screen left.")

        return -1
    }

    ; None found.
    dbgMsgBox(true, dbgHeader, "Error: Not found.")
    
    return 0
}


; Clicks to get the sickle.
; Harvests an area using a selected reference field for start, but the larger area
;  is defined separately.
; 
; Inputs:
;  screen coordinate of filed to click for sickle.
;  topLeftFieldRowColRelative to the clicked field
;  lowerRightFieldRowColRelative to the clicked field
;
; Outputs:
;   2 : Silo full
;   1 : ok
;  -1 : Not home screen detected.
;  -2 : Sickle was not visible
HarvestArea(selectFieldPixelPos, topLeftFieldRowColRelative, lowerRightFieldRowColRelative) {
    dbgEnable := true
    dbgHeader := "HarvestArea"
    dbgEnableWait := dbgEnable && true

    global SICKLE_REL_X, SICKLE_REL_Y

    global CROP_OVERLAY_SICKLE      
    global CROP_OVERLAY_PROGRESS_BAR
    global CROP_OVERLAY_CROPS     

    startScreenPos := [0,0] ; Init var.

    ; This is correct
    ; msg := "topLeftFieldRowColRelative: " . topLeftFieldRowColRelative[1] . ", " . topLeftFieldRowColRelative[2]
    ; dbgMsgBox(dbgEnable, dbgHeader, msg)
    ; MsgBox,,,%msg%
    ; Sleep, 500
    ; msg := "lowerRightFieldRowColRelative: " . lowerRightFieldRowColRelative[1] . ", " . lowerRightFieldRowColRelative[2]
    ; dbgMsgBox(dbgEnable, dbgHeader, msg)
    ; MsgBox,,,%msg%
    ; Sleep, 500
    ;
    
    ; Click the field to harvest to open overlay.
    MouseMoveDLL(selectFieldPixelPos)
    MouseClick, Left
    Sleep, 300


    ; Verify sickle is visible
    res := IsSickleOnOverlay(selectFieldPixelPos)
    if ( res <= 0 ) {
        dbgMsgBox(true, dbgHeader, "Error: Sickle not detected for selection.")

        if ( res = -1 ) {
            dbgMsgBox(true, dbgHeader, "Error: Home screen left.")
            return -1
        }

        dbgMsgBox(true, dbgHeader, "Error: Other sickle detection.")
        return -2
    }


    ; Click and hold sickle to start the harvest.
    dbgMsgBox(dbgEnable, dbgHeader, "Click and hold sickle to start the harvest.")

    sicklePos := [selectFieldPixelPos[1] + SICKLE_REL_X, selectFieldPixelPos[2] + SICKLE_REL_Y]
    MouseMoveDLL(sicklePos)
    Sleep, 300
    Click, Down
    Sleep, 600

    ; First harvest the reference field. It is the first one to be checked by also Plant, so keep it clear
    ;  with priority.
    dbgMsgBox(dbgEnable, dbgHeader, "Move to the select field.")
    x := selectFieldPixelPos[1]
    y := selectFieldPixelPos[2]
    MouseMove, x, y


    ; Move to the first corner of the larger harvest area.
    dbgMsgBox(dbgEnable, dbgHeader, "Move to the first corner of the larger harvest area.")

    diffCoords := TransformRowColDiffCoord(topLeftFieldRowColRelative)
    startScreenPos[1] := selectFieldPixelPos[1] + diffCoords[1]
    startScreenPos[2] := selectFieldPixelPos[2] + diffCoords[2]

    x := startScreenPos[1]
    y := startScreenPos[2]
    MouseMove, x, y

    msg := "At top left corner"
    dbgMsgBox(dbgEnable, dbgHeader, msg)


    ; At this point the silo can be full already.
    Sleep, 500
    if ( IsScreenSiloBarnFull() > 0 ) {
        ; Normal, silo full.
        dbgMsgBox(true, dbgHeader, "Harvest done: silo full.")
        dbgWait(dbgEnableWait, dbgHeader, 1000)

        return 2
    }

    ; Verify home screen.
    if ( IsScreenHome() <= 0 ) {
        dbgMsgBox(true, dbgHeader, "Error: home screen lost before sweep.")
        dbgWait(dbgEnableWait, dbgHeader, 1000)
        return -1
    }


    ; Drag the area
    dbgMsgBox(dbgEnable, dbgHeader, "Drag the area.")

    nRow := lowerRightFieldRowColRelative[1] - topLeftFieldRowColRelative[1] + 1
    nCol := lowerRightFieldRowColRelative[2] - topLeftFieldRowColRelative[2] + 1

    msg := "row col: " . nRow . ", " . nCol
    dbgMsgBox(dbgEnable, dbgHeader, msg)

    res := SweepArea(startScreenPos, nRow, nCol)
    if ( res <= 0 ) {
        dbgMsgBox(true, dbgHeader,"Error: Sweep.")

        if ( res = -1 ) {
            dbgMsgBox(true, dbgHeader, "Error: home screen lost during sweeping.")
            dbgWait(dbgEnableWait, dbgHeader, 1000)

            return -1
        }
        else if ( res = -2 ) {
            ; Normal, silo full.
            dbgMsgBox(true, dbgHeader, "Harvest done: silo full.")

            return 2
        }
        else {
            msg := "Error: sweeping: " . res
            dbgMsgBox(true, dbgHeader, msg)
            dbgWait(dbgEnableWait, dbgHeader, 1000)

            return res
        }
    }

    ; Move back to the selected start field, it is a safe are.
    Sleep, 300
    MouseMoveDLL(selectFieldPixelPos)


    ; Release mouse
    Sleep, 300
    Click, Up
    Sleep, 200


    ; Verify home screen.
    if ( IsScreenHome() <= 0 ) {
        dbgMsgBox(true, dbgHeader, "Error: home screen lost.")
        dbgWait(dbgEnableWait, dbgHeader, 1000)

        return -1
    }

    dbgMsgBox(dbgEnable, dbgHeader, "Returns: 1")
    return 1
}


; Returns what overlay screen a crop is found on.
; Uses crops / screen and does not require updating when new crops are added.
GetHarvestScreenNbrForCrop(itemId) {
    global CROPS_PER_OVERLAY_SCREEN
    return floor( (itemId-1) / CROPS_PER_OVERLAY_SCREEN ) + 1
}


; Returns the relative coords from selected field to a crop to plant in the overlay. 
;
; Requires:
;  That the maximum crops per overlay screen is 5.
;
; Returns:
;  [relative x, relative y]
GetOverlayRelativePosForCrop(cropItemId) {
    dbgEnable := true
    dbgHeader := "GetOverlayRelativePosForCrop"

    global CROP_SELECT1_R1C1_X
    global CROP_SELECT1_R1C1_Y
     
    global CROP_SELECT1_R2C1_X
    global CROP_SELECT1_R2C1_Y
    global CROP_SELECT1_R2C2_X
    global CROP_SELECT1_R2C2_Y
     
    global CROP_SELECT1_R3C1_X
    global CROP_SELECT1_R3C1_Y
    global CROP_SELECT1_R3C2_X
    global CROP_SELECT1_R3C2_Y
     
    global CROPS_PER_OVERLAY_SCREEN

    msg := "CropId: " . cropItemId
    dbgMsgBox(dbgEnable, dbgHeader, msg)

    tempId := mod((cropItemId-1), CROPS_PER_OVERLAY_SCREEN) + 1

    if ( tempId = 1 ) {
        return [CROP_SELECT1_R1C1_X, CROP_SELECT1_R1C1_Y]
    }
    else if ( tempId = 2 ){
        return [CROP_SELECT1_R2C1_X, CROP_SELECT1_R2C1_Y]
    }
    else if ( tempId = 3 ){
        return [CROP_SELECT1_R2C2_X, CROP_SELECT1_R2C2_Y]
    }
    else if ( tempId = 4 ){
        return [CROP_SELECT1_R3C1_X, CROP_SELECT1_R3C1_Y]
    }
    else if ( tempId = 5 ){
        return [CROP_SELECT1_R3C2_X, CROP_SELECT1_R3C2_Y]
    }
    
    return [-1, -1]
}


; Plants an area from the selected reference field.
; Requires overlay is open.
;
; Inputs:
;  screen coordinate of start (field)
;  nbr of rows
;  nbr of columns
;  crop item id
;
; Returns:
;   1 : ok
;  -1 : Not home screen after operation
;  -2 : Overlay with crops not found
;  -3 : Crop still maturing
;  -4 : Sickle overlay found 
PlantArea(selectFieldPixelPos, topLeftFieldRowColRelative, lowerRightFieldRowColRelative, cropItemId) {
    dbgEnable := true
    dbgHeader := "PlantArea"

    global CROP_OVERLAY_SICKLE      
    global CROP_OVERLAY_PROGRESS_BAR
    global CROP_OVERLAY_CROPS   

    ; Click the field to plant to open overlay.
    dbgMsgBox(dbgEnable, dbgHeader, "Click the field to plant to open overlay.")

    MouseMoveDLL( selectFieldPixelPos )
    Click
    Sleep, 200

    ; Verify overlay is visible. TODO - Improve. The indicator button is probably not unique enough.
    dbgMsgBox(dbgEnable, dbgHeader, "Verify overlay is visible.")

    cropOverlayScreen := GetOpenCropPlantSelectScreen( selectFieldPixelPos )
    if ( cropOverlayScreen <= 0 ) {
        dbgMsgBox(true, dbgHeader, "Error: Plant overlay screen not open after clicking field.")

        ; See if there is a different overlay.        
        res := GetCropOverlayType(selectFieldPixelPos)
        if ( res = CROP_OVERLAY_SICKLE ) {
            ; Field ready to harvest.
            dbgMsgBox(true, dbgHeader, "Error: CROP_OVERLAY_SICKLE.")

            return -4
        }
        else if ( res = CROP_OVERLAY_PROGRESS_BAR ) {
            ; Crop still maturing
            dbgMsgBox(true, dbgHeader, "Error: CROP_OVERLAY_PROGRESS_BAR.")

            return -3
        }
        else {
            ; No overlay or undetectable.
            dbgMsgBox(true, dbgHeader, "Error: No overlay or undetectable.")

            return -2
        }
    }

    ; Go to the correct overlay screen.
    dbgMsgBox(dbgEnable, dbgHeader, "Go to the correct overlay screen.")

    res := SelectPlantOverlayScreenForCrop( selectFieldPixelPos, cropItemId )
    if ( res <= 0 ) {
        msg := "Error: Plant overlay screen not found for crop: " . cropItemId
        dbgMsgBox(true, dbgHeader, msg)

        return - 2
    }


    ; Click and hold crop.
    dbgMsgBox(dbgEnable, dbgHeader, "Click and hold crop.")

    rPos := GetOverlayRelativePosForCrop( cropItemId )
    cropPos := [selectFieldPixelPos[1] + rPos[1], selectFieldPixelPos[2] + rPos[2]]
    MouseMoveDLL(cropPos)
    Click, Down
    Sleep, 200

    msg := "Relative pos for selection: " . rPos[1] . ", " . rPos[2]
    dbgMsgBox(dbgEnable, dbgHeader, msg)


    ; For planting, the first field to plant must be the select field.
    MouseMoveDLL(selectFieldPixelPos)
    Sleep, 200


    ; Move to the first corner of the larger harvest area.
    dbgMsgBox(dbgEnable, dbgHeader, "Move to the first corner of the larger harvest area.")

    diffCoords := TransformRowColDiffCoord(topLeftFieldRowColRelative)
    startScreenPos := [0,0] ; Init var.
    startScreenPos[1] := selectFieldPixelPos[1] + diffCoords[1]
    startScreenPos[2] := selectFieldPixelPos[2] + diffCoords[2]

    x := startScreenPos[1]
    y := startScreenPos[2]
    MouseMove, x, y

    msg := "At top left corner"
    dbgMsgBox(dbgEnable, dbgHeader, msg)


    ; Drag the area
    dbgMsgBox(dbgEnable, dbgHeader, "Drag the area.")

    nRow := lowerRightFieldRowColRelative[1] - topLeftFieldRowColRelative[1] + 1
    nCol := lowerRightFieldRowColRelative[2] - topLeftFieldRowColRelative[2] + 1

    msg := "row col: " . nRow . ", " . nCol
    dbgMsgBox(dbgEnable, dbgHeader, msg)

    res := SweepArea(startScreenPos, nRow, nCol)
    if ( res < 0 ) {
        dbgMsgBox(true, dbgHeader,"Error: home screen left detected.")

        return -1
    }

    ; Move back to the selected start field, it is a safe are.
    Sleep, 300
    MouseMoveDLL(selectFieldPixelPos)

    ; Release mouse
    Sleep, 300
    Click, Up
    Sleep, 200

    ; Verify home screen. Note, this only captures connection lost and so. Not a reload in the meantime.
    if ( IsScreenHome() ) {
        dbgMsgBox(dbgEnable, dbgHeader, "Returns: 1")

        return 1
    }
    else {
        dbgMsgBox(true, dbgHeader,"Error: home screen left detected.")
        
        return -1
    }
}


;Not used
; TODO - Configuration of the start field. 
;  Entered as row/col from the mansion/board or other universal fixed point. 
;
; Inputs:
;   todo : startFieldReferenceRowCol
;   rows to process
;   cols to process
;   crop to plant 
;
; Returns:
;   1 : ok
;  -1 : Not home screen after operation
;  -2 : Overlay with crops not found
;  -3 : Crop still maturing
;  -4 : Sickle overlay found 
GoToFieldAndPlant(startFieldReferenceRowCol, nRow, nCol, cropItemId) {
    dbgEnable := true
    dbgHeader := "GoToFieldAndPlant"

    ; TODO - This is a configuration input, has to be row col and not coords. Now they are
    ;  only valid for a specific example.
    global FIELD_REF_X
    global FIELD_REF_Y
    startScreenPos := [FIELD_REF_X, FIELD_REF_Y]

    ; Validate screen, handle errors / retries?
    dbgMsgBox(dbgEnable, dbgHeader, "Go to home.")
    res := GoToHome()
    if ( res <= 0 ) {
        return -1
    }

    ; Move screen to reference position
    dbgMsgBox(dbgEnable, dbgHeader, "Go to center.")
    res := GoCenterReference()
    if ( res < 0 ) {
        return -1
    }

    ; Validate screen, handle errors / retries?
    if ( !IsScreenHome() ) {
        return -1
    }

    ; Plant away
    dbgMsgBox(dbgEnable, dbgHeader, "Plant from here.")
    res := PlantArea(startScreenPos, nRow, nCol, cropItemId)
    if ( res < 0 ) {
        ; Wrong overlay type reported here.
        return res
    }

    ; Validate screen, handle errors / retries?
    dbgMsgBox(dbgEnable, dbgHeader, "Validate screen.")
    if ( !IsScreenHome() ) {
        return -1
    }
    else {
        dbgMsgBox(dbgEnable, dbgHeader, "Finished.")
        return res
    }
}


;Not used
; TODO - Configuration of the start field. 
;  Entered as row/col from the mansion/board or other universal fixed point. 
;
; Inputs:
;   todo : startFieldReferenceRowCol
;   rows to process
;   cols to process
;
; Returns:
;   1 : ok
;  -1 : Not home screen after operation
;  -2 : Sickle was not visible
;  -3 : Crop still maturing detected
;  -4 : Field empty and ready to harvest
GoToFieldAndHarvest(startFieldReferenceRowCol, nRow, nCol) {
    dbgEnable := true
    dbgHeader := "GoToFieldAndHarvest"

    ; TODO - This is a configuration input, has to be row col and not coords. Now they are
    ;  only valid for a specific example.
    global FIELD_REF_X
    global FIELD_REF_Y
    startScreenPos := [FIELD_REF_X, FIELD_REF_Y]

    ; Validate screen, handle errors / retries?
    dbgMsgBox(dbgEnable, dbgHeader, "Go to home.")
    res := GoToHome()
    if ( res <= 0 ) {
        return -1
    }

    ; Move screen to reference position
    dbgMsgBox(dbgEnable, dbgHeader, "Go to center.")
    res := GoCenterReference()
    if ( res < 0 ) {
        return -1
    }

    ; Validate screen, handle errors / retries?
    if ( !IsScreenHome() ) {
        return -1
    }

    ; Harvest away
    dbgMsgBox(dbgEnable, dbgHeader, "Harvest from here.")
    res := HarvestArea(startScreenPos, nRow, nCol)
    if ( res < 0 ) {
        ; Wrong overlay type reported here.
        return res
    }

    ; Validate screen, handle errors / retries?
    dbgMsgBox(dbgEnable, dbgHeader, "Validate screen.")
    if ( !IsScreenHome() ) {
        return -1
    }
    else {
        dbgMsgBox(dbgEnable, dbgHeader, "Finished.")
        return res
    }
}

; ------------------------------------------------------------------------------------------------







; ------------------------------------------------------------------------------------------------
; Functions regarding shop in general

; Optional the absolute index to the left (multiples of slots on screen but 1 more.
; Both Shop and Friend uses this for instance.
;
; Returns:
;  [screenSlot, scrollsNeeded]
GetScreenSlotForModulo(n, absoluteSlot, absoluteSlotRef := 1) {
    absoluteSlot := absoluteSlot - absoluteSlotRef + 1

    if ( absoluteSlot > 1 ) {
        screenSlot := Mod(absoluteSlot-1, n) + 1
    }
    else {
        screenSlot := 1
    }
    scrollsNeeded := floor( (absoluteSlot-1) / n )

    return [screenSlot, scrollsNeeded]    
}


; Returns 4 colors to use as change detection
; Uses the the pricetag place.
SampleShopSlotColors(alignment := 0) {
    global SHOP_SLOT_DIFF_X
    global SHOP_SLOT_1_PRICETAG_X, SHOP_SLOT_1_PRICETAG_Y
    
    ret := [-1,-1,-1,-1]

    i := 0
    Y := SHOP_SLOT_1_PRICETAG_Y
    loop, 4 {
        i++
        X := (i - 1)*SHOP_SLOT_DIFF_X + SHOP_SLOT_1_PRICETAG_X + alignment
        PixelGetColor, col, X, Y, RGB
        ret [i] := col
    }

    return ret
}


; Returns:
;  Coordinat in grid search pattern
;  Next index in pattern. When 0 pattern is done.
ReturnGridSearchCoord(pos, pixels, n) {
    global APP_SCALE

    dbgEnable := true
    dbgHeader := "ReturnGridSearchCoord"

    dist := pixels*APP_SCALE

    ; Diagonal spiral

    ; Press center
    if ( n = 1 ) {
        x := pos[1]
        y := pos[2]
    }
    else if (n=2) {
        ; Press 1:st perimeter diagonals
        x := pos[1] + dist*(n-1)
        y := pos[2] - dist*(n-1)
    }
    else if (n=3) {
        ; Press 1:st perimeter diagonals
        x := pos[1] - dist*(n-1)
        y := pos[2] - dist*(n-1)
    }
    else if (n=4) {
        ; Press 1:st perimeter diagonals
        x := pos[1] - dist*(n-1)
        y := pos[2] + dist*(n-1)
    }
    else if (n=5) {
        ; Press 1:st perimeter diagonals
        x := pos[1] + dist*(n-1)
        y := pos[2] + dist*(n-1)
    }
    else if (n=6) {
        ; Press 1:st perimeter centers
        x := pos[1] + dist*(n-1)
        y := pos[2]
    }
    else if (n=7) {
        ; Press 1:st perimeter centers
        x := pos[1]
        y := pos[2] + dist*(n-1)
    }
    else if (n=8) {
        ; Press 1:st perimeter centers
        x := pos[1] - dist*(n-1)
        y := pos[2]
    }
    else if (n=9) {
        ; Press 1:st perimeter centers
        x := pos[1]
        y := pos[2] + dist*(n-1)
    }

    n++
    if ( n >= 9 ) {
        n := -1
    }

    return [[x,y], n+1] 
}


; TODO: For shop then sample several safe areas left of shop to determine if app has reloaded.
;  It can replace the "in screen" verification.
; Returns:
;  1 : Is in shop
; -1 : Wrong screen
GridPressAroundShopPos(pos, pixels, screenSelection) {
    global APP_SCALE

    dbgEnable := true
    dbgHeader := "GridPressAroundShopPos"
    dbgEnableWait := dbgEnable && false

    dist := pixels*APP_SCALE
    screenError := false

    ; Diagonal spiral

    ; Press center
    X := pos[1]
    Y := pos[2]
    MouseMove, X, Y, 0
    Click
    Sleep, 200
    CloseScreenBigBox()
    res := Helper_IsInShopOrScreen(screenSelection)
    if ( res = 1) {
        return 1
    }
    else if ( res < 0 ) {
        return -1
    }

    ; Press 1:st perimeter
    X += dist
    Y -= dist
    MouseMove, X, Y, 0
    Click
    Sleep, 200
    CloseScreenBigBox()
    res := Helper_IsInShopOrScreen(screenSelection)
    if ( res = 1) {
        return 1
    }
    else if ( res < 0 ) {
        return -1
    }

    X -= 2*dist
    MouseMove, X, Y, 0
    Click
    Sleep, 200
    CloseScreenBigBox()
    res := Helper_IsInShopOrScreen(screenSelection)
    if ( res = 1) {
        return 1
    }
    else if ( res < 0 ) {
        return -1
    }

    Y += 2*dist
    MouseMove, X, Y, 0
    Click
    Sleep, 200
    CloseScreenBigBox()
    res := Helper_IsInShopOrScreen(screenSelection)
    if ( res = 1) {
        return 1
    }
    else if ( res < 0 ) {
        return -1
    }

    X += 2*dist
    MouseMove, X, Y, 0
    Click
    Sleep, 200
    CloseScreenBigBox()
    res := Helper_IsInShopOrScreen(screenSelection)
    if ( res = 1) {
        return 1
    }
    else if ( res < 0 ) {
        return -1
    }

    ; Press 2:nd perimeter
    X := pos[1] + 2*dist
    Y := pos[2] - 2*dist
    MouseMove, X, Y, 0
    Click
    Sleep, 200
    CloseScreenBigBox()
    res := Helper_IsInShopOrScreen(screenSelection)
    if ( res = 1) {
        return 1
    }
    else if ( res < 0 ) {
        return -1
    }

    X -= 2*dist
    MouseMove, X, Y, 0
    Click
    Sleep, 200
    CloseScreenBigBox()
    res := Helper_IsInShopOrScreen(screenSelection)
    if ( res = 1) {
        return 1
    }
    else if ( res < 0 ) {
        return -1
    }

    X -= 2*dist
    MouseMove, X, Y, 0
    Click
    Sleep, 200
    CloseScreenBigBox()
    res := Helper_IsInShopOrScreen(screenSelection)
    if ( res = 1) {
        return 1
    }
    else if ( res < 0 ) {
        return -1
    }

    Y += 2*dist
    MouseMove, X, Y, 0
    Click
    Sleep, 200
    CloseScreenBigBox()
    res := Helper_IsInShopOrScreen(screenSelection)
    if ( res = 1) {
        return 1
    }
    else if ( res < 0 ) {
        return -1
    }

    Y += 2*dist
    MouseMove, X, Y, 0
    Click
    Sleep, 200
    CloseScreenBigBox()
    res := Helper_IsInShopOrScreen(screenSelection)
    if ( res = 1) {
        return 1
    }
    else if ( res < 0 ) {
        return -1
    }

    X += 2*dist
    MouseMove, X, Y, 0
    Click
    Sleep, 200
    CloseScreenBigBox()
    res := Helper_IsInShopOrScreen(screenSelection)
    if ( res = 1) {
        return 1
    }
    else if ( res < 0 ) {
        return -1
    }

    X += 2*dist
    MouseMove, X, Y, 0
    Click
    res := Helper_IsInShopOrScreen(screenSelection)
    Sleep, 200
    CloseScreenBigBox()
    if ( res = 1) {
        return 1
    }
    else if ( res < 0 ) {
        return -1
    }

    Y -= 2*dist
    MouseMove, X, Y, 0
    Click
    res := Helper_IsInShopOrScreen(screenSelection)
    Sleep, 200
    CloseScreenBigBox()
    if ( res = 1) {
        return 1
    }
    else if ( res < 0 ) {
        return -1
    }

    return 0
}


Helper_IsInShopOrScreen(screenSelection) {
    global SCREEN_FRIEND

    Sleep, 600
    if ( IsInShop() > 0 ) {
        return 1
    }
    else if ( IsShopRedX() ) {
        ; If not in shop but a red x, then something else was clicked
        ; The red x is the same place shop, derby, farm passX
        dbgMsgBox(dbgEnable, dbgMsgHeader, "Not in shop but red x will be clicked.")
        CloseShop()
        Sleep, 1000
    }

    ; Validate screen
    if ( IsScreen(screenSelection) <= 0 ) {
        dbgMsgBox(true, dbgMsgHeader, "Error: Screen left.")
        return -1
    }

    if ( screenSelection = SCREEN_FRIEND ) {
        ; Test if it was a found big box.
        dbgMsgBox(dbgEnable, dbgMsgHeader, "Test if it was a found big box.")
        Sleep, 500
        CloseScreenBigBox()
    }

    return 0 
}


; Must be in shop - no verification.
; Moves mouse to location.
; Clicks if valid slot where the selected slot on screen is (1 leftmost on screen)
; Returns:
;  [status]
;    status >0 : screenSlot clicked
;    status -1 : invalid screenSlot
PressShopSlot(screenSlot, alignment := 0) {
    global SHOP_SLOTS_ON_SCREEN

    dbgEnable := true
    dbgHeader := "PressShopSlot"
    dbgEnableWait := dbgEnable && false

    coord := Helper_GetClickCoordForShopSlot( screenSlot )
    if ( coord[1] >= 0 ) {
        x := coord[1] + alignment
        y := coord[2]
        
        msg := "gonna click here for slot " . screenSlot . ": " . vec2_toString([x, y])
        dbgMsgBox(dbgEnable, dbgHeader, msg)

        MouseMoveDLL([x, y])
        Sleep, 100
        Click
        Sleep, 200

        return 1
    }

    dbgMsgBox(true, dbgHeader, "Error.")
    return -1
}


; Uses the pricetag for location to get ideal click coord (no alignment).
; Returns:
;    coord     : coord if valid screenSlot, otherwise [-1, -1]
Helper_GetClickCoordForShopSlot(screenSlot) {
    global SHOP_SLOT_DIFF_X      
    global SHOP_SLOTS_ON_SCREEN
    ; Pricetag coords.
    global SHOP_SLOT_ON_SALE_P1_X, SHOP_SLOT_ON_SALE_P1_Y

    dbgEnable := true
    dbgHeader := "Helper_GetClickCoordForShopSlot"
    dbgEnableWait := dbgEnable && false


    if ( (screenSlot != "") && (screenSlot >= 1 && screenSlot <= SHOP_SLOTS_ON_SCREEN ) ) {
        X := SHOP_SLOT_ON_SALE_P1_X + (screenSlot-1)*SHOP_SLOT_DIFF_X
        Y := SHOP_SLOT_ON_SALE_P1_Y
        coord := [X, Y]
    
        return coord
    }
    else {
        dbgMsgBox(true, dbgHeader, "Error.")
    
        return [-1, -1]
    }
}


; Asserts whether the shop is open.
IsInShop() {
    MouseGetPos, x, y
    res := IsShopRedX()
    MouseMove, x, Y
    return res
}


; Closes shop if possible.
; Returns:
;   1: Was in shop, and clicked. Verifies then that not in window any more.
;  -1: Wasn't in shop. 
CloseShop() {
    global RED_X_SHOP_X, RED_X_SHOP_Y

    if ( IsInShop() > 0 ) {
        MouseMove, RED_X_SHOP_X, RED_X_SHOP_Y
        Click
        Sleep, 500
        if ( IsInShop() <= 0 ) {
            return 1
        }
        else {
            return -1
        }
    }
    else {
        return -1
    }
}


; May be used by many, some menus are similar.
IsShopRedX() {
    global RED_X_SHOP_X, RED_X_SHOP_Y

    x := RED_X_SHOP_X
    y := RED_X_SHOP_Y
    return IsCloseButtonAtPos( [x, y] )
}


; Must be in shop.
; Scrolls a multiple of slots on screen, to get to the absolute slot.
; Optional parameter to use if already in shop, and with a known absolute index at screen slot 1.
; Returns:
;  [status, alignment]
;   status:
;    >0: screenSlot (the target slot is somewhere on the current screen)
;    <0: Error
;   alignment x - adjust x coord by this to have slot detection center.
ShopScrollToSlot(absoluteSlot, absoluteSlotRef := 1) {
    global SHOP_SLOTS_ON_SCREEN
    global SHOP_SLOTS_TO_SCROLL

    dbgEnable := true
    dbgHeader := "ShopScrollToSlot"
    dbgEnableWait := dbgEnable && true


    ; Determine the correct output values.
    scrollSlots := SHOP_SLOTS_ON_SCREEN
    out := GetScreenSlotFromAbsoluteSlot( absoluteSlot, scrollSlots, SHOP_SLOTS_ON_SCREEN, absoluteSlotRef )
    screenSlot := out[1]
    scrollsNeeded := out[2]

    ; Debug out
    msg := "Abs slot: " . absoluteSlot . " Scr Slot: " . screenSlot . " Scroll: " . scrollsNeeded
    dbgMsgBox(dbgEnable, dbgHeader, msg)

    ; Scroll to the correct values.
    scrolls := 0
    loop {
        if ( scrolls >= scrollsNeeded ) {
            ; Done - return status & alignment.
            diffResult := GetShopSlotOffset()
            if ( diffResult[1] = 1 ) {
                st := diffResult[1]
                al := diffResult[2]
                msg := "Status: " . st . " X-Align: " . al[1]
                dbgMsgBox(dbgEnable, dbgHeader, msg)
                return [ screenSlot, diffResult[2] ]
            }
            else {
                return [-1, 0]
            }  
        }
        else {
            res := ShopScrollSlots( scrollSlots )
            res := res[1]
            if ( res < 0 ) {
                return -1
            }
            scrolls++
        }
    }
}


; Scroll selected nbr of slots With slot 1 as reference.
;
; Requires:
;  Can only be used for 4 slot scrolls - there is dynamic scroll in the shop depending on where you are.
;  And then only for a small shop, there are accumulating errors for a big.
;
; Inputs:
;  nbr of slots to scroll
;
; Returns:
;  [status, alignment]
;   1 : ok
;   0 : ok but end of the line couldnt scroll all. - TODO refine to return how many slots actually scrolled, including reversing.
;  -1 : screen left
; alignment is the compensation x-value to modify slot center withby other functions.
;
ShopScrollSlots(nbrToScroll) {

    global SHOP_SLOT_DIFF_X, SHOP_SLOT_1_X, SHOP_DRAG_Y, SHOP_DRAG_DB
    global SHOP_DRAG_REV_X, SHOP_DRAG_REV_P1_X, SHOP_DRAG_REV_P1_Y, SHOP_DRAG_REV_C
    global APP_SCALE

    dbgEnable := false
    dbgHeader := "ShopScrollSlots"
    dbgEnableWait := dbgEnable && false

    ; The deadband is bc At start of drag there is a deadband - drag extra.
    ;  This is glide/speed depending.
    ;  For 3 slot at speed 20 there is actually overdragging, so stop before.

    X1 := Ceil( SHOP_SLOT_1_X + nbrToScroll*SHOP_SLOT_DIFF_X )     ; 
    X2 := SHOP_SLOT_1_X + SHOP_DRAG_DB*0.9

    X2 := SHOP_SLOT_1_X + SHOP_DRAG_DB*0.15

    Y1 := SHOP_DRAG_Y
    Y2 := SHOP_DRAG_Y

    ; Drag in left of slot bc middle of nbr 5 (to scroll 4) is outside shop.
    x_off := 0.5*SHOP_SLOT_DIFF_X
    X1 -= x_off
    X2 -= x_off

    X1 := ceil(X1)
    X2 := ceil(X2)
    MouseMoveDLL([X1, Y1])
    Sleep, 300
    Click, Down
    MouseMoveDLL([X2, Y2])
    Sleep, 300
    Click, Up

    Sleep, 300  ; Allow time to snap back if it was at the end.
    if ( IsInShop() > 0 ) {
        ; If there were no even slots for drag then drag to right a little - it means 
        ;  the left slot now was visible before and that there are 3 slots visible now.

        ; Reverse at the end if the slots are misaligned.
        ; If there is shop purple/brown wood here instead of a box it is totally misaligned, indicating end.
        PixelGetColor, col, %SHOP_DRAG_REV_P1_X%, %SHOP_DRAG_REV_P1_Y%, RGB

        if ( IsAlmostSameColor(SHOP_DRAG_REV_C, col, 0.03) > 0 ) {
            ; XXX use this information to return an offset for alignment instead.
            ; If the slots are overdragged to the right they bounce back to this alignment.
            reverseOffsetAlignment := floor((SHOP_SLOT_DIFF_X - 106)*APP_SCALE)
            return [0, reverseOffsetAlignment]



            MouseMove, SHOP_DRAG_REV_P1_X, SHOP_DRAG_REV_P1_Y
            dbgWait(dbgEnableWait, dbgHeader)

            ; DEBUG
            X1 := SHOP_SLOT_1_X
            X2 := SHOP_SLOT_1_X + SHOP_DRAG_REV_X + SHOP_DRAG_DB

            X2 := SHOP_SLOT_1_X + SHOP_DRAG_REV_X + SHOP_DRAG_DB*0.9

            Y1 := SHOP_DRAG_Y
            Y2 := SHOP_DRAG_Y

            X1 := ceil(X1)
            X2 := ceil(X2)
            
            MouseMove, X1, Y1
            MouseClickDrag, Left, %X1%, %Y1%, %X2%, %Y2%, 20

            if ( IsInShop() <= 0 ) {
                return [-1, 0]
            }

            return [0, 0]
        }
        else {
            ; Slots normal alignment, but it could differ a few pixels that we can detect.
            dbgWait(dbgEnableWait, dbgHeader)

            diffResult := GetShopSlotOffset()
            if ( diffResult[1] = 1 ) {
                return [ 1, diffResult[2] ]
            }
            else {
                dbgMsgBox(true, dbgHeader, "Error: alignment not valid, using 0.")
                dbgWait(dbgEnableWait, dbgHeader)
                return [-1, 0]
            }
        }
    }
    else {
        ; Not in shop
        return [-1, 0]
    }

}


; Checks if the slot contains the target item.
;
; Input:
;  slot         : screen slot to evaluate
;  targetItem   : >0 - item to look for.
;  alignment    : optional 0, compensation for slots being misaligned horisontally.
;
; Returns:
; >0 : ItemId at slot 
;  0 : Item not detected.
; -1 : Error
IsTargetItemAtShopSlot(slot, targetItemId, alignment := 0) {
    global APP_SCALE
    ;
    global SHOP_SLOTS_ON_SCREEN
    ;
    global SHOP_SLOT_WIDTH 
    global SHOP_SLOT_HEIGHT
    global SHOP_SLOT_DIFF_X
    global SHOP_SLOT_1_X, SHOP_SLOT_1_Y
    ;
    global ITEM_ID_CORN, ITEM_ID_SAW, ITEM_ID_AXE
    ;
    global SHOP_SLOT_CORN_P1_X
    global SHOP_SLOT_CORN_P1_Y
    global SHOP_SLOT_CORN_P1_C
    global SHOP_SLOT_CORN_P2_X
    global SHOP_SLOT_CORN_P2_Y
    global SHOP_SLOT_CORN_P2_C
    global SHOP_SLOT_CORN_P3_X
    global SHOP_SLOT_CORN_P3_Y
    global SHOP_SLOT_CORN_P3_C
    global SHOP_SLOT_CORN_P4_X
    global SHOP_SLOT_CORN_P4_Y
    global SHOP_SLOT_CORN_P4_C

    dbgEnable := true
    dbgHeader := "IsTargetItemAtShopSlot"

    ; Validate inputs
    if ( targetItemId < 0 || targetItemId = "" || slot > SHOP_SLOTS_ON_SCREEN || slot <= 0 ) {
        ; Null or invalid.
        dbgMsgBox(true, dbgHeader, "Error: Invalid item.")
        return -1
    }

    ; Validate support for Id
    if ( targetItemId > 0 ) {
        if ( targetItemId != ITEM_ID_CORN ) {
            ; Not supported.
            dbgMsgBox(true, dbgHeader, "Error: Non-supported item.")
            return -1
        }        
    }

    ; DEBUG
    if (dbgEnable) {
        x := slotCenter[1]
        y := slotCenter[2]
        MouseMove, x, y
        msg := "Looking at mouse: " . x . ", " . y
        dbgMsgBox(dbgEnable, dbgHeader, msg)
    }

    ; Get data for selected item
    if ( targetItemId = ITEM_ID_CORN ) {
        x1 := SHOP_SLOT_CORN_P1_X
        y1 := SHOP_SLOT_CORN_P1_Y
        c1 := SHOP_SLOT_CORN_P1_C
        x2 := SHOP_SLOT_CORN_P2_X
        y2 := SHOP_SLOT_CORN_P2_Y
        c2 := SHOP_SLOT_CORN_P2_C
        x3 := SHOP_SLOT_CORN_P3_X
        y3 := SHOP_SLOT_CORN_P3_Y
        c3 := SHOP_SLOT_CORN_P3_C
        x4 := SHOP_SLOT_CORN_P4_X
        y4 := SHOP_SLOT_CORN_P4_Y
        c4 := SHOP_SLOT_CORN_P4_C
    } else {
        ; Continue with the other stuff
        return -1
    }

    ; Offset for image recognition
    x_diff := (slot-1)*SHOP_SLOT_DIFF_X + alignment
    x1 += x_diff
    x2 += x_diff
    x3 += x_diff
    x4 += x_diff

    if (dbgEnable) {
        msg := "LookAt Corn: " . x1 . ", " . y1 . " || " . x2 . ", " . y2 . " || " . x3 . ", " . y3 . " || " . x4 . ", " . y4
        dbgMsgBox(dbgEnable, dbgHeader, msg)
    }
    res := IsSimilarFourColor(x1, y1, c1, x2, y2, c2, x3, y3, c3, x4, y4, c4)

    if ( res ) {
        return targetItemId
    }
    else if ( res < 0 ) {
        msg := "Error: res: " . res
        dbgMsgBox(true, dbgHeader, msg)
        return res
    }
    else {
        return 0
    }
}


; TODO Gör en CheckTwoColors
; Helper function - use instead: ShopGetMyItemStatusForSlot
;
; Uses a little larger tolerance on the color comparison
;
; Returns:
;  0 / 1
Helper_IsShopSlotEmpty(screenSlot, alignment := 0) {
    global SHOP_SLOT_DIFF_X
    global SHOP_SLOT_1_X, SHOP_SLOT_1_Y

    global SHOP_ITEM_EMPTY

    global SHOP_SLOT_EMPTY_P1_X
    global SHOP_SLOT_EMPTY_P1_Y
    global SHOP_SLOT_EMPTY_P1_C
    global SHOP_SLOT_EMPTY_P2_X
    global SHOP_SLOT_EMPTY_P2_Y
    global SHOP_SLOT_EMPTY_P2_C
    global SHOP_SLOT_EMPTY_P3_X
    global SHOP_SLOT_EMPTY_P3_Y
    global SHOP_SLOT_EMPTY_P3_C
    global SHOP_SLOT_EMPTY_P4_X
    global SHOP_SLOT_EMPTY_P4_Y
    global SHOP_SLOT_EMPTY_P4_C

    dbgEnable := true
    dbgHeader := "Helper_IsShopSlotEmpty"
    dbgEnableWait := dbgEnable && false

    dbgMsgBox(dbgEnable, dbgHeader, "Started.")
    dbgWait(dbgEnableWait, dbgHeader, 1000)

    x_add := SHOP_SLOT_DIFF_X*(screenSlot - 1) + alignment

    P1_X := SHOP_SLOT_EMPTY_P1_X + x_add
    P1_Y := SHOP_SLOT_EMPTY_P1_Y
    P1_C := SHOP_SLOT_EMPTY_P1_C
    P2_X := SHOP_SLOT_EMPTY_P2_X + x_add
    P2_Y := SHOP_SLOT_EMPTY_P2_Y
    P2_C := SHOP_SLOT_EMPTY_P2_C
    P3_X := SHOP_SLOT_EMPTY_P3_X + x_add
    P3_Y := SHOP_SLOT_EMPTY_P3_Y
    P3_C := SHOP_SLOT_EMPTY_P3_C
    P4_X := SHOP_SLOT_EMPTY_P4_X + x_add
    P4_Y := SHOP_SLOT_EMPTY_P4_Y
    P4_C := SHOP_SLOT_EMPTY_P4_C

    res := IsSimilarFourColor( P1_X,P1_Y,P1_C, P2_X,P2_Y,P2_C, P3_X,P3_Y,P3_C, P4_X,P4_Y,P4_C, 0.03)

    return res
}


; Helper function - use instead: ShopGetMyItemStatusForSlot
; Advertised or not, just any goods on sale.
;
; TODO possibly remove/replace by adjust IsTargetItemAtShopSlot and let "ItemId = 0" check for any item 
;  using like the price tag. But grey one also.
Helper_IsShopSlotOnSale(screenSlot, alignment := 0) {

    global APP_SCALE
    global SHOP_SLOT_DIFF_X

    x_add := SHOP_SLOT_DIFF_X*(screenSlot - 1) + alignment

    global SHOP_SLOT_ON_SALE_P1_X
    global SHOP_SLOT_ON_SALE_P1_Y
    global SHOP_SLOT_ON_SALE_P1_C
    global SHOP_SLOT_ON_SALE_P2_X
    global SHOP_SLOT_ON_SALE_P2_Y
    global SHOP_SLOT_ON_SALE_P2_C
    global SHOP_SLOT_ON_SALE_P3_X
    global SHOP_SLOT_ON_SALE_P3_Y
    global SHOP_SLOT_ON_SALE_P3_C
    global SHOP_SLOT_ON_SALE_P4_X
    global SHOP_SLOT_ON_SALE_P4_Y
    global SHOP_SLOT_ON_SALE_P4_C

    dbgEnable := true
    dbgHeader := "Helper_IsShopSlotOnSale"
    dbgEnableWait := dbgEnable && false

    dbgMsgBox(dbgEnable, dbgHeader, "Started.")
    dbgWait(dbgEnableWait, dbgHeader, 1000)

    P1_X := SHOP_SLOT_ON_SALE_P1_X + x_add
    P1_Y := SHOP_SLOT_ON_SALE_P1_Y
    P1_C := SHOP_SLOT_ON_SALE_P1_C
    P2_X := SHOP_SLOT_ON_SALE_P2_X + x_add
    P2_Y := SHOP_SLOT_ON_SALE_P2_Y
    P2_C := SHOP_SLOT_ON_SALE_P2_C
    P3_X := SHOP_SLOT_ON_SALE_P3_X + x_add
    P3_Y := SHOP_SLOT_ON_SALE_P3_Y
    P3_C := SHOP_SLOT_ON_SALE_P3_C
    P4_X := SHOP_SLOT_ON_SALE_P4_X + x_add
    P4_Y := SHOP_SLOT_ON_SALE_P4_Y
    P4_C := SHOP_SLOT_ON_SALE_P4_C

    ; Compare
    res := IsSimilarFourColor( P1_X,P1_Y,P1_C, P2_X,P2_Y,P2_C, P3_X,P3_Y,P3_C, P4_X,P4_Y,P4_C, 0.03 )

    return res
}


; Must be in shop.
; Returns:
;  [status, alignment] 
;           the nbr of pixels the shop slots are misaligned, as a drag may put them a little off.
; Reference point determines how much error is able to compensate (for instance 10 px wrong drag)
; Should be done once per drag only.
GetShopSlotOffset() {
    res := GetShopSlotOffsetBinSearch()

    msg := "Alignment: " . res[2]
    GuiControl,, GuiTxtAlignment, %msg%

    return [res[1], res[2]]

    ; res := GetShopSlotOffsetLinearSearch()
    ; return [res[1], res[2]]
}


GetShopSlotOffsetLinearSearch() {
  ; To compensate for drag a little out of phase.
    global SHOP_ALIGNMENT_REF_X 
    global SHOP_ALIGNMENT_REF_Y 
    global SHOP_ALIGNMENT_REF_C 
    global SHOP_ALIGNMENT_DIFF_X

    dbgEnable := true
    dbgHeader := "GetShopSlotOffset"

    ; The border between no slot and slot should ideally be detected at REF_X + DIFF_X.

    ; Search - TODO optimise algorithm
    cnt := 0
    loop {
        x := SHOP_ALIGNMENT_REF_X + cnt
        y := SHOP_ALIGNMENT_REF_Y
        PixelGetColor, col, x, y, rgb
        if ( IsAlmostSameColor(col, SHOP_ALIGNMENT_REF_C) <= 0 ) {
            ; Found the box edge here.
            msg := "Found edge after count: " . cnt
            dbgMsgBox(dbgEnable, dbgHeader, msg)
            return [1, cnt - SHOP_ALIGNMENT_DIFF_X ]
        }

        cnt++
        if ( cnt > 2*SHOP_ALIGNMENT_DIFF_X) {
            dbgMsgBox(true, dbgHeader, "Error: Did not find edge.")
            return [-1, 0]
        }
    }
}


; TODO change place to look at to allow for larger misalignment? It is possible with positive misalign
;  up to half a slot. But  not in negative bc first slot will go out of view.
;
; Must be in shop.
; Max misalignment is half the distance between the top of 2 boxes - about 19 px at 1080 res.
; Returns:
;  [status, alignment] 
;           the nbr of pixels the shop slots are misaligned, as a drag may put them a little off.
; Reference point determines how much error is able to compensate (for instance 10 px wrong drag)
; Should be done once per drag only.
GetShopSlotOffsetBinSearch() {
    ; To compensate for drag a little out of phase.
    global SHOP_ALIGNMENT_REF_X 
    global SHOP_ALIGNMENT_REF_Y 
    global SHOP_ALIGNMENT_REF_C 
    global SHOP_ALIGNMENT_DIFF_X

    dbgEnable := true
    dbgHeader := "GetShopSlotOffsetBinSearch"
    dbgEnableWait := true

    ; The border between no slot and slot should ideally be detected at REF_X + DIFF_X.
    ; Uses that between the boxes the bg color is purplish. If not that color, it's a box.

    ; Uses bin search. Each bin is an x-coordinate.

    eval := 0
    lowerLimit := 0
    upperLimit := ceil(SHOP_ALIGNMENT_DIFF_X*2) ; The constant is the ideal distance.
    state := 0
    index := 0
    foundBin := 0
    init := true

    counts := 0
    loop {
        counts++

        ; Call bin search until it returns Done or Error.
        binResult := BinSearch(eval, lowerLimit, upperLimit, state, index, foundBin, init)
        ;
        searchResult    := binResult[1]
        lowerLimit      := binResult[2]
        upperLimit      := binResult[3]
        state           := binResult[4]
        index           := binResult[5]
        foundBin        := binResult[6]
        init            := binResult[7]
        ;
        msg := "From search: " . searchResult . ", " . lowerLimit . ", " . upperLimit . ", " . state . ", " . index . ", " . foundBin . ", In: " . init
        dbgMsgBox(dbgEnable, dbgHeader, msg)
        ; MsgBox,,,%msg%
        ;
        if (searchResult = 1) {
            ; Done
            msg := "Search complete at index: " . index
            dbgMsgBox(dbgEnable, dbgHeader, msg)
            ; Exit loop
            break
        }
        else if (searchResult < 0) {
            ; Error in provided interval
            msg := "Search aborted."
            dbgMsgBox(dbgEnable, dbgHeader, msg)
            ; Exit loop
            break
        }

        ; Evaluate search for comparison and provide the result to the next search iteration.
        x := SHOP_ALIGNMENT_REF_X + index
        y := SHOP_ALIGNMENT_REF_Y
        msg := "Testing pixel for bg color: " . x . ", " . y . ", C: " . SHOP_ALIGNMENT_REF_C
        ; MsgBox,,,%msg%

        PixelGetColor, col, x, y, rgb
        if ( IsAlmostSameColor(col, SHOP_ALIGNMENT_REF_C, 0.03) <= 0 ) {
            ; Found the box edge here.
            msg := "At this index there is a box: " . index
            dbgMsgBox(dbgEnable, dbgHeader, msg)

            eval := 1
        }
        else {
            eval := 0
        }
    }
    ; msgbox,,,%msg%
    return [searchResult, index - SHOP_ALIGNMENT_DIFF_X]
}


; Bin search with "callback function" - call this repeatedly.
; Requires sorted values to search.
; Finds the lowest index to meet criteria.
;
; In general, the search function returns an index, and asks for the evaluation result 
;  for that index.
; Other outputs are used for the search state engine and must just passed back into it, 
;  exactly as they were returned. The function has no instance memory and uses the 
;  return values being passed in again.
; 
; Call repeatedly until result is Done or Error. 
; First time called with init set to true (will be automatically reset).
;
; Inputs:
;  evalResult, lowerBin, upperBin, state, index, init
;  0: Still searching, 1: done, -1: parameter error
;              Lower index (set when init)
;                        Upper index (set when init)
;                                   Internal
;
;                                                Set init true 1:st time
; Outputs:
;  result, lowerLimit, upperLimit, state, index, foundIndex, init
;  1: Done, -1: Error, 0: Continue calling.
;          Internal
;                      Internal
;                                  Internal
;                                         To evaluate and send result for next call.
;                                                Internal
;                                                            Internal
BinSearch(evalResult, lowerBin, upperBin, state, index, foundBin, init) {
    dbgEnable := true
    dbgHeader := "BinSearchBoxAlignment"

    ; Index is the center that is evaluated.

    msg := "Binsearch called with R: " . evalResult . ", L: " . lowerBin . ", U: " . upperBin . ", S: " . state . ", Id: " . index . ", FB: " . foundBin . ", I: " . init
    dbgMsgBox(dbgEnable, dbgHeader, msg)


    if ( init ) {
        init := false

        msg := "Init w lower/upper: " . lowerBin . ", " . upperBin
        dbgMsgBox(dbgEnable, dbgHeader, msg)

        ; Next validate upper limit - ask for that evaluation
        out_Result := false
        out_Bin := upperBin
        foundBin := -1
        state := 5
    }
    else if (state = 5) {
        ; Evaluate upper bin
        if ( evalResult < 1) {
            msg := "Error: Search criteria not met at upper limit."
            dbgMsgBox(true, dbgHeader, msg)

            ; Caller should stop.
            out_Result := -1
            out_Bin := upperBin
        }
        else {
            ; Next validate lower limit - ask for that evaluation
            out_Result := 0
            out_Bin := lowerBin
            state := 10
        }
    }
    else if (state = 10) {
        ; Evaluate lower bin
        if ( evalResult = 1) {
            msg := "Error: Search criteria not met at lower limit."
            dbgMsgBox(true, dbgHeader, msg)

            ; Caller should stop.
            out_Result := -1
            out_Bin := lowerBin
        }
        else {
            ; Next start the binary search - ask for that evaluation

            ; Set index (center)
            index := floor( 0.5*(lowerBin + upperBin) )

            out_Result := 0
            out_Bin := index
            state := 15
        }
    }
    else if ( state = 15 ) {
        if ( index = lowerBin || index = upperBin ) {
            msg := "Finished. Search interval minimum limit reached. Foundbin: " . foundBin
            dbgMsgBox(dbgEnable, dbgHeader, msg)

            out_Result := 1
            out_Bin := foundBin
        }
        else {
            ; Get search result for center bin
            if ( evalResult = 1 ) {
                ; Remember the last found bin.
                foundBin := index

                ; Look more to lower bins
                upperBin := index

                ; Calculate next evaluation bin
                index := floor( 0.5*(lowerBin+upperBin) )
            }
            else {
                ; Look more to higher bins
                lowerBin := index

                ; Calculate next evaluation bin
                index := ceil( 0.5*(lowerBin+upperBin) )
            }
            ; Continue, ask caller for new evaluation.
            out_Result := 0
            out_Bin := index
        }
    }

    return [out_Result, lowerBin, upperBin, state, out_Bin, foundBin, init]
}
; ------------------------------------------------------------------------------------------------





; ------------------------------------------------------------------------------------------------
; Functions regarding friend's shop

; Must be in friend shop when start.
; Leaves on friend screen.
;
; Input
;  itemId (optional, default CORN)
;   >0 : Buy this only
;    0 : Buy any? TODO
;  counts (optional, default 0  -unlimited)
;    0 : Buy until full 
;   >0 : This many successful buys only
;  absoluteStartSlot (optional, default 1)
;
; Returns:
;  Nbr of buys
;  [Status, Nbr of buys]
;  -1 : Screen left / error
;  -2 : Inventory full 
AutoBuyItem(itemId := 1, maxCounts := 0, absoluteStartSlot := 1) {
    global SHOP_SLOTS_ON_SCREEN

    dbgEnable := true
    dbgHeader := "AutoBuyItem"

    ; Copied from SellAllItem and adapted.

    ; Init
    counts := 0
    buyTargetOnly := itemId > 0
    targetStorageFull := false


    ; Vaidate inputs
    if ( itemId <= 0 ) {
        autoBuyResult := [-1, counts] 
        return autoBuyResult
    }

    if ( IsInShop() <= 0 ) {
        autoBuyResult := [-1, counts] 
        return autoBuyResult
    }


    ; Initialize once to have start position on screen. If last call was aborted and not much time passed.
    absoluteSlot := absoluteStartSlot
    res := ShopScrollToSlot( absoluteSlot )
    res := res[1]
    if ( res > 0 ) {
        screenSlot := res
    }
    else {
        autoBuyResult := [-1, counts]
        return autoBuyResult
    }

    ; Get the alignment in order to recognise goods.
    diffResult := GetShopSlotOffset()
    alignment := diffResult[2]

    ; Debug out
    msg := "Abs Slot: " . absoluteSlot . " Scr Slot: " . screenSlot
    dbgMsgBox(dbgEnable, dbgHeader, msg)

    ; Check if inventory full - difference between barn / silo depending on what was clicked (target)
    ; But don't know if clicked ex Carrot if Target was Corn and mode Any. Could be either barn or silo.
    ; Perhaps an ok limitation bc bots have always one crop type, so it is known.
    ;  I.e. if target Corn and Mode any, then in the shop there can only be Corn as a barn item. So if
    ;  click targetItem and StorageFullScreen it's barn. 
    itemStorageIsBarn := IsItemStorageBarn(itemId)

    ; Check all further slots in shop from current position.
    lastLoop := false
    loop {
        ; Debug out
        msg := "Abs Slot: " . absoluteSlot . " Scr Slot: " . screenSlot
        dbgMsgBox(dbgEnable, dbgHeader, msg)

        ; Process screen slots from right to left to avoid a flying item to interfere.
        invertedSlot := SHOP_SLOTS_ON_SCREEN + 1 - screenSlot

        foundTarget := false
        ; See if this slot contains item, then click it.
        if ( buyTargetOnly ) {
            ; Determine if slot has target item.
            if ( IsTargetItemAtShopSlot( invertedSlot, itemId, alignment ) > 0 ) {
                ; Debug out
                msg := "FOUND itemId: " . itemId . " at slot: " . screenSlot
                dbgMsgBox(dbgEnable, dbgHeader, msg)

                foundTarget := true
            }
            else {
                ; Debug out
                msg := "Not found itemId: " . itemId . " at slot: " . screenSlot
                dbgMsgBox(dbgEnable, dbgHeader, msg)
            }
        }
        else {
            ; Buy regardless of item?
        }

        ; Item to buy found and clicked. Buy it.
        if ( foundTarget && !targetStorageFull ) {
            res := PressShopSlot( invertedSlot )
            Sleep, 1000

            ; Check if inventory full, then stop trying to by that type of item.
            if ( IsScreenSiloBarnFull() > 0 ) {
                ; Debug out
                msg := "IsScreenSiloBarnFull()"
                dbgMsgBox(dbgEnable, dbgHeader, msg)

                targetStorageFull := true
                break
            }
            else {
                ; Verify if in shop or else abort.
                if ( IsInShop() <= 0 ) {
                    ; Debug out
                    msg := "Error: !IsInShop()"
                    dbgMsgBox(true, dbgHeader, msg)

                    autoBuyResult := [-1, counts]
                    return autoBuyResult
                }
                counts++
            }
        }


        ; Quit?
        if ( maxCounts > 0 && counts >= maxCounts || buyTargetOnly && targetStorageFull ) {
            break 
        }
        else {
            ; Continue and point to the next slot, scroll if needed.
            ;
            ; If all screen slots done it's time to scroll.
            if ( screenSlot >= SHOP_SLOTS_ON_SCREEN ) {
                ; Debug out
                msg := "Time to scroll."
                dbgMsgBox(dbgEnable, dbgHeader, msg)

                if ( lastLoop ) {
                    ; There has already been one scroll attempt that found end of line.
                    ; Debug out
                    msg := "Breaking coz last loop."
                    dbgMsgBox(dbgEnable, dbgHeader, msg)
                    break
                }
                else {
                    ; Scroll
                    scrollResult := ShopScrollSlots( SHOP_SLOTS_ON_SCREEN )
                    res := scrollResult[1]
                    alignment := scrollResult[2]

                    ; Debug out
                    msg := "Scroll align: " . alignment[1]
                    dbgMsgBox(dbgEnable, dbgHeader, msg)

                    if ( res = 1 ) {
                        ; Full scroll
                        ; Debug out
                        msg := "Full scroll."
                        dbgMsgBox(dbgEnable, dbgHeader, msg)

                        screenSlot := 1
                        absoluteSlot++
                    }
                    else if ( res = 0 ) {
                        ; Partial scroll, dont know so check existing absolute slot again
                        ; Debug out
                        msg := "Partial scroll."
                        dbgMsgBox(dbgEnable, dbgHeader, msg)

                        screenSlot := 1
                        lastLoop := true
                    }
                    else {
                        ; Error
                        autoBuyResult := [-1, counts]
                        return autoBuyResult
                    }
                }
            }
            else {
                ; Check next one on screen
                screenSlot++
                absoluteSlot++
            }
        }
    }

    ; Buy complete one way or the other.
    if ( targetStorageFull ) {
        ; Shop is left automatically when trying to buy. 
        ; Now the screen is on Friend screen where it was when entering shop.
        ;   TODO - This allows for easy re-enter (to fill up other storage) and stay inside loop.
        CloseScreenSiloBarnFull()
        msg := "Closing silobarnfull."
        dbgMsgBox(dbgEnable, dbgHeader, msg)

        Sleep, 500
    }

    if ( IsInShop() > 0 ) {
        CloseShop()
    }

    if ( targetStorageFull ) {
        dbgMsgBox(dbgEnable, dbgHeader, "targetStorageFull")

        autoBuyResult := [-2, counts]
        return autoBuyResult
    }

    autoBuyResult := [1, counts]
    return autoBuyResult
}


; Detects Greg at the left most friend selection slot. 
; Requires:
;  Friend selection bar open.
IsGregAtSlot(slotIndex := 1) {
    global FRIEND_GREG_P1_X
    global FRIEND_GREG_P1_Y
    global FRIEND_GREG_P1_C
    global FRIEND_GREG_P2_X
    global FRIEND_GREG_P2_Y
    global FRIEND_GREG_P2_C
    global FRIEND_GREG_P3_X
    global FRIEND_GREG_P3_Y
    global FRIEND_GREG_P3_C
    global FRIEND_GREG_P4_X
    global FRIEND_GREG_P4_Y
    global FRIEND_GREG_P4_C

    dbgEnable := true
    dbgHeader := "IsGregAtSlot"
    dbgEnableWait := dbgEnable && false

    dbgMsgBox(dbgEnable, dbgHeader, "Started.")
    dbgWait(dbgEnableWait, dbgHeader, 1000)

    ; Greg is max level and leftmost, but at some point maybe the FB icon moves there.
    ; x_add := SHOP_SLOT_DIFF_X*(screenSlot - 1) + alignment
    x_add := 0

    P1_X := FRIEND_GREG_P1_X + x_add
    P1_Y := FRIEND_GREG_P1_Y
    P1_C := FRIEND_GREG_P1_C
    P2_X := FRIEND_GREG_P2_X + x_add
    P2_Y := FRIEND_GREG_P2_Y
    P2_C := FRIEND_GREG_P2_C
    P3_X := FRIEND_GREG_P3_X + x_add
    P3_Y := FRIEND_GREG_P3_Y
    P3_C := FRIEND_GREG_P3_C
    P4_X := FRIEND_GREG_P4_X + x_add
    P4_Y := FRIEND_GREG_P4_Y
    P4_C := FRIEND_GREG_P4_C

    res := IsSimilarFourColor( P1_X,P1_Y,P1_C, P2_X,P2_Y,P2_C, P3_X,P3_Y,P3_C, P4_X,P4_Y,P4_C )

    return res    
}


; TODO - There is a direct scroll route, but also in shop just select next friend.
;  1 : OK
; -1 : Could not open friend bar
; -2 : Could not go to selected friend
GoToFriend( friendIndex ) {
    global FRIEND_SLOT_DIFF_X
    global FRIEND_SLOT1_X
    global FRIEND_SLOT1_Y

    global BTN_FRIENDS_X     
    global BTN_FRIENDS_Y     
    global FRIENDS_BAR_OPEN_X, FRIENDS_BAR_OPEN_Y, FRIENDS_BAR_OPEN_C
    global FRIENDS_BAR_HEADER_Y   
    global FRIENDS_BAR_HEADER_CLAN_X        
    global FRIENDS_BAR_HEADER_HELP_WANTED_X 
    global FRIENDS_BAR_HEADER_LAST_HELPERS_X
    global FRIENDS_BAR_HEADER_FRIENDS_X     
    global FRIENDS_BAR_HEADER_FOLLOWERS_X

    dbgEnable := true
    dbgHeader := "GoToFriend"

    ; Open friend list
    msg := "Open friends list."
    dbgMsgBox(dbgEnable, dbgHeader, msg)

    x := BTN_FRIENDS_X
    y := BTN_FRIENDS_Y
    MouseMove, x, y, 0
    Click
    ; Validate open
    Sleep, 500
    PixelGetColor, col, %FRIENDS_BAR_OPEN_X%, %FRIENDS_BAR_OPEN_Y%, RGB
    if ( IsAlmostSameColor(col, FRIENDS_BAR_OPEN_C) <= 0 ) {
        msg := "Error: Friends bar not open."
        dbgMsgBox(true, dbgHeader, msg)

        return -1
    }

    ; Make sure the friends list is open.
    msg := "Make sure the friends list is open."
    dbgMsgBox(dbgEnable, dbgHeader, msg)

    x := FRIENDS_BAR_HEADER_FRIENDS_X
    y := FRIENDS_BAR_HEADER_Y
    MouseMove, x, y, 20
    Click

    ; Scroll list to position.
    msg := "Scroll list to position."
    dbgMsgBox(dbgEnable, dbgHeader, msg)

    screenSlot := ScrollToFriend( friendIndex )
    if ( screenSlot <= 0 ) {
        return -1
    }

    ; Enter selected friend
    msg := "Enter selected friend."
    dbgMsgBox(dbgEnable, dbgHeader, msg)

    x := FRIEND_SLOT1_X + FRIEND_SLOT_DIFF_X*(screenSlot-1)
    y := FRIEND_SLOT1_Y

    msg := "Friend slot X: " . FRIEND_SLOT1_X . " at: " . x . ", " . y . " Diff X: " . FRIEND_SLOT_DIFF_X . " Fr. id: " . friendIndex
    dbgMsgBox(dbgEnable, dbgHeader, msg)

    MouseMove, x, y, 0
    Click

    ; Validate some times
    n := 0
    Sleep, 1000
    loop, 5 {
        if ( IsScreenFriend() <= 0 ) {
            n++
            if ( n >= 5 ) {
                msg := "Error: Friend screen not open."
                dbgMsgBox(true, dbgHeader, msg)

                return -2
            }
            else {
                msg := "Friend screen not open, trying again."
                dbgMsgBox(dbgEnable, dbgHeader, msg)

                Sleep, 1000
            }
        }
        else {
            break
        }
    }

    dbgMsgBox(dbgEnable, dbgHeader, "Finished.")

    return 1
}


; Requires:
;  There can be only one row of slor
;
; Inputs:
;  Absolute slot
;  Nbr to drag each time
;
; Returns:
;  [screenSlot, scrollsNeeded]
GetScreenSlotFromAbsoluteSlot(absoluteSlot, nbrToDrag, slotsOnScreen, firstAbsoluteSlot := 1) {

    dbgEnable := false
    dbgHeader := "GetScreenSlotFromAbsoluteSlot"
    dbgEnableWait := dbgEnable && true

    scrollsNeeded := 0
    loop {
        screenSlot := absoluteSlot - firstAbsoluteSlot + 1
        msg := "ss: " . screenSlot . ", as1: " . firstAbsoluteSlot
        dbgMsgBox(dbgEnable, dbgHeader, msg)
        dbgWait(dbgEnableWait, dbgHeader)
        if ( screenSlot <= slotsOnScreen ) {
            break
        }
        scrollsNeeded++
        firstAbsoluteSlot += nbrToDrag
    }

    return [screenSlot, scrollsNeeded]
}


; For navigating from friend 'home' screen to their shop into absolute shop slot.
; Returns:
;  [status, alignment]
;  >0 : screenSlot, resulting from a scrolled shop.
;  -1 : Could not find friend home screen
;  -2 : Could not enter shop
EnterFriendShop( absoluteShopSlot) {
    global DRAG_ANCHOR_LOWER_LEFT_X   
    global DRAG_ANCHOR_LOWER_LEFT_Y    

    global BTN_FRIEND_SHOP_AFTER_DRAG_X  
    global BTN_FRIEND_SHOP_AFTER_DRAG_Y
    
    global GAME_AREA_CENTER_X, GAME_AREA_CENTER_Y

    global APP_SCALE, SCREEN_FRIEND

    dbgEnable := false
    dbgMsgHeader := "EnterFriendShop"

    ; Verify at friend
    if ( IsScreenFriend() <= 0 ) {
        dbgMsgBox(true, dbgMsgHeader, "Error: !IsScreenFriend()")
        return [-1, 0]
    }

    ; Zoom out
    dbgMsgBox(dbgEnable, dbgMsgHeader, "ZoomOutFromCenter()")
    ZoomOutFromCenter()

    ; Drag and enter shop
    dbgMsgBox(dbgEnable, dbgMsgHeader, "Drag to shop.")

    X := DRAG_ANCHOR_LOWER_LEFT_X
    Y := DRAG_ANCHOR_LOWER_LEFT_Y
    X2 := GAME_AREA_CENTER_X
    Y2 := GAME_AREA_CENTER_Y
    MouseMove, X, Y, 0
    MouseClickDrag, Left, %X%, %Y%, %X2%, %Y2%, 50
    Sleep, 500

    ; The position when entering home or friend is randomised so press around grid n x n
    dbgMsgBox(dbgEnable, dbgMsgHeader, "Click around to enter shop.")

    res := GridPressAroundShopPos([BTN_FRIEND_SHOP_AFTER_DRAG_X, BTN_FRIEND_SHOP_AFTER_DRAG_Y], 50, SCREEN_FRIEND)
    found := res = 1

    ; Go to the slot
    if ( found ) {
        dbgMsgBox(dbgEnable, dbgMsgHeader, "ShopScrollToSlot( absoluteShopSlot )")

        res := ShopScrollToSlot( absoluteShopSlot )
        screenSlot := res[1]
        alignment := res[2]
        if ( screenSlot < 0 ) {
            ; Error
            dbgMsgBox(true, dbgMsgHeader, "Invalid screen slot after ShopScrollToSlot.")
        }
        else {
            return [screenSlot, alignment]
        }
    }
    else {
        dbgMsgBox(true, dbgMsgHeader, "Shop not found.")

        return [-2, 0]
    }
}


; Scrolls the friend selection bar.
; Scrolls a multiple of slots on screen, to get to the absolute slot.
; Optional parameter to use if already in shop, and with a known absolute index at screen slot 1.
;
; Requirements:
;  Friend list lower right must be open.
;
; Inputs:
;  absolute slot     - to friend
;  absoluteSlotRef   - optional default 1
;
; Returns:
;  >0: screenSlot for selected friend
;  <0: Error
ScrollToFriend(absoluteSlot, absoluteSlotRef := 1) {
    global FRIEND_SLOTS_ON_SCREEN, FRIEND_SLOTS_TO_DRAG
    global FRIEND_SLOT_DIFF_X, FRIEND_SLOT1_X, FRIEND_SLOT1_Y

    dbgEnable := true
    dbgHeader := "ScrollToFriend"
    dbgEnableWait := dbgEnable && false

    ; Determine the correct output values.
    out := GetScreenSlotFromAbsoluteSlot( absoluteSlot, FRIEND_SLOTS_TO_DRAG, FRIEND_SLOTS_ON_SCREEN, absoluteSlotRef )
    screenSlot := out[1]
    scrollsNeeded := out[2]

    msg := ""
    msg := msg . "absoluteSlot: " . absoluteSlot . ", "
    msg := msg . "screenSlot: " . screenSlot . ", "
    msg := msg . "scrollsNeeded: " . scrollsNeeded
    dbgMsgBox(dbgEnable, dbgHeader, msg)
    dbgWait(dbgEnableWait, dbgHeader)

    ; Scroll to the correct values.

    ; The friend bar does not reset so init it even if no scroll.
    diff_x := FRIEND_SLOT_DIFF_X
    x_ref := FRIEND_SLOT1_X
    drag_y := FRIEND_SLOT1_Y
    loop, 3 {
        if ( IsGregAtSlot() > 0 ) {
            dbgMsgBox(dbgEnable, dbgHeader, "Greg found, bar initialised.")

            break
        }

        X1 := x_ref
        X2 := x_ref + 5*diff_x
        Y1 := drag_y
        Y2 := drag_y
        ; 
        MouseMove, X1, Y1
        MouseClickDrag, Left, %X1%, %Y1%, %X2%, %Y2%, 40
        Sleep, 1
        Sleep, 300  ; It will slide when released.

        if ( IsScreenHome() <= 0 ) {
            return -1
        }
    }

    ; Now scroll to friend.
    scrolls := 0
    loop {
        if ( scrolls >= scrollsNeeded ) {
            return screenSlot
        }
        else {
            res := ScrollFriendSlots( FRIEND_SLOTS_TO_DRAG )
            if ( res < 0 ) {
                return res
            }
            scrolls++
        }
    }
}


; Scrolls the friend selection bar.
; Scroll selected nbr of slots With slot 1 as reference.
;
; Inputs:
;  nbrToScroll
;
; Returns:
;   1 : ok
;  -1 : screen left
;
ScrollFriendSlots(nbrToScroll) {

    global FRIEND_SLOT_DIFF_X, FRIEND_SLOT1_X, FRIEND_SLOT1_Y

    dbgEnable := true
    dbgHeader := "ScrollFriendSlots"
    dbgEnableWait := dbgEnable && false

    diff_x := FRIEND_SLOT_DIFF_X
    x_ref := FRIEND_SLOT1_X
    drag_y := FRIEND_SLOT1_Y

    ; The deadband is bc At start of drag there is a deadband - drag extra.
    ;  This is glide/speed depending.
    ;  For 3 slot at speed 20 there is actually overdragging, so stop before.

    X1 := x_ref + nbrToScroll*diff_x 
    X2 := x_ref - Ceil( diff_x*nbrToScroll/9.9 )
    Y1 := drag_y
    Y2 := drag_y

    ; Offset otherwise drag anchor outside screen.
    X1 -= diff_x
    X2 -= diff_x

    ; 
    MouseMoveDLL([X1, Y1])
    Sleep, 100
    dbgWait(dbgEnableWait, dbgHeader)
    Click, Down
    Sleep, 100
    MouseMoveDLL([X2, Y2])

    Sleep, 300  ; Make sure to stop before release.
    dbgWait(dbgEnableWait, dbgHeader)
    Click, Up    
    ; MouseClickDrag, Left, %X1%, %Y1%, %X2%, %Y2%, 40
    Sleep, 300  ; It will slide when released.

    if ( IsScreenHome() <= 0 ) {
        return -1
    }

    return 1
}


; Screenslot
IsSoldFriendShopSlot(screenSlot, alignment := 0) {
    global SOLD_FRIEND_SHOP_SLOT_P1_X
    global SOLD_FRIEND_SHOP_SLOT_P1_Y
    global SOLD_FRIEND_SHOP_SLOT_P1_C
    global SOLD_FRIEND_SHOP_SLOT_P2_X
    global SOLD_FRIEND_SHOP_SLOT_P2_Y
    global SOLD_FRIEND_SHOP_SLOT_P2_C
    global SOLD_FRIEND_SHOP_SLOT_P3_X
    global SOLD_FRIEND_SHOP_SLOT_P3_Y
    global SOLD_FRIEND_SHOP_SLOT_P3_C
    global SOLD_FRIEND_SHOP_SLOT_P4_X
    global SOLD_FRIEND_SHOP_SLOT_P4_Y
    global SOLD_FRIEND_SHOP_SLOT_P4_C

    global SHOP_SLOTS_ON_SCREEN, SHOP_SLOT_DIFF_X

    dbgEnable := true
    dbgHeader := "IsSoldFriendShopSlot"

    if (screenSlot < 1 || screenSlot > SHOP_SLOTS_ON_SCREEN || screenSlot = "") {
        dbgMsgBox(true, dbgHeader, "Invalid screen slot.")
        return -1
    }

    x_ref := (screenSlot-1)*SHOP_SLOT_DIFF_X + alignment

    P1_X :=	SOLD_FRIEND_SHOP_SLOT_P1_X + x_ref
    P1_Y :=	SOLD_FRIEND_SHOP_SLOT_P1_Y
    P1_C :=	SOLD_FRIEND_SHOP_SLOT_P1_C
    P2_X :=	SOLD_FRIEND_SHOP_SLOT_P2_X + x_ref
    P2_Y :=	SOLD_FRIEND_SHOP_SLOT_P2_Y
    P2_C :=	SOLD_FRIEND_SHOP_SLOT_P2_C
    P3_X :=	SOLD_FRIEND_SHOP_SLOT_P3_X + x_ref
    P3_Y :=	SOLD_FRIEND_SHOP_SLOT_P3_Y
    P3_C :=	SOLD_FRIEND_SHOP_SLOT_P3_C
    P4_X :=	SOLD_FRIEND_SHOP_SLOT_P4_X + x_ref
    P4_Y :=	SOLD_FRIEND_SHOP_SLOT_P4_Y
    P4_C :=	SOLD_FRIEND_SHOP_SLOT_P4_C

    return IsSimilarFourColor(P1_X,P1_Y,P1_C, P2_X,P2_Y,P2_C, P3_X,P3_Y,P3_C, P4_X,P4_Y,P4_C, 0.03)
}
; ------------------------------------------------------------------------------------------------






; ------------------------------------------------------------------------------------------------
; Functions regarding player's own shop

;
; Does not work if starting from friend shop - will detect this as home shop.
; Tries to return from wherever to the home screen and then enter the shop.¨
;
; Returns:
;  1 : Is in shop.
; <0 : Error in any function.
GoToHomeAndOpenShop() {
    global DRAG_ANCHOR_LOWER_LEFT_X    
    global DRAG_ANCHOR_LOWER_LEFT_Y    
    global DRAG_ANCHOR_TOP_LEFT_X    
    global DRAG_ANCHOR_TOP_LEFT_Y    

    global ZOOM_OUT_ANCHOR_TOP_LEFT_X
    global ZOOM_OUT_ANCHOR_TOP_LEFT_Y
    global BTN_MY_SHOP_AFTER_DRAG_X  
    global BTN_MY_SHOP_AFTER_DRAG_Y

    global APP_CENTER_X, APP_CENTER_Y

    global SCREEN_FRIEND, SCREEN_HOME

    dbgEnable := true
    dbgHeader := "GoToHomeAndOpenShop"

    ; Is in shop already
    if ( IsInShop() > 0 ) {
        return 1
    }

    ; Go to top left reference
    msg := "Go top left reference."
    dbgMsgBox(dbgEnable, dbgHeader, msg)

    res := GoTopLeftReference()
    if ( res < 0 ) {
        return res
    }

    ;   Go down by:
    msg := "Go down."
    dbgMsgBox(dbgEnable, dbgHeader, msg)

    MouseMove, DRAG_ANCHOR_LOWER_LEFT_X, APP_CENTER_Y, 0
    if ( IsScreen(SCREEN_HOME) <= 0 ) {
        msg := "Error: Not home screen."
        dbgMsgBox(true, dbgHeader, msg)

        return -1
    }
    MouseClickDrag, Left, DRAG_ANCHOR_LOWER_LEFT_X, APP_CENTER_Y, DRAG_ANCHOR_LOWER_LEFT_X, DRAG_ANCHOR_TOP_LEFT_Y, 20
    Sleep, 500

    ;   Search for shop around 461, 467 - This should be prety exact now.
    msg := "Search for shop."
    dbgMsgBox(dbgEnable, dbgHeader, msg)

    if ( IsScreen(SCREEN_HOME) <= 0 ) {
        msg := "Error: Not home screen."
        dbgMsgBox(true, dbgHeader, msg)

        return -1
    }
    res := GridPressAroundShopPos( [BTN_MY_SHOP_AFTER_DRAG_X, BTN_MY_SHOP_AFTER_DRAG_Y], 5, SCREEN_HOME)

    return res
}


; TODO OLD CHECK IF UP TO DATE
; Tries to put an advert on first possible goods.
;
; Returns:
;   0 : Ad not ready
;   1 : A slot was advertised.
;   2 : No goods to advertise.
;  -1 : Error Window left
;  -2 : Error Slot not identified (could be end of line)
;  -3 : Error putting ad (window left?)
ShopAdvertiseExistingGoods() {
    global SHOP_ITEM_ON_SALE
    global SHOP_SLOTS_ON_SCREEN

    dbgEnable := true
    dbgHeader := "ShopAdvertiseExistingGoods"
    dbgEnableWait := dbgEnable && false

    ; From slot 1 until ad is placed
        ; If slot has item without ad
            ; If slot does not have ad
                ; Try Place ad
            ; If ad placed
                ; Exit sale (pressing red cross not necessary) if not already.

    ; Inside shop
    if ( IsInShop() <= 0 ) {
        msg := "Error: not in shop."
        dbgMsgBox(true, dbgHeader, msg)
        Sleep, 1000

        return -1
    }

    ; Assume 
    ;   shop opens with slot 1 to the left.
    ;   shop is 1 horisontal row
    scrolls := 0            ; How many times was shop scrolled?
    endOfLine := false      ; Shop scrolled to the end.
    alignment := 0
    
    loop {
        ; Check 4 slots on screen
        slot := 1       ; Screen slot
        errors := 0
        loop {
            slotStatus := ( slot, alignment )

            msg := "Status: " . slotStatus . " on slot: " . slot . " Align: " . alignment[1]
            dbgMsgBox(dbgEnable, dbgHeader, msg)
            Sleep, 500

            if ( slotStatus = SHOP_ITEM_ON_SALE ) {
                msg := "Item on sale (status: " . slotStatus . ") on slot: " . slot
                dbgMsgBox(dbgEnable, dbgHeader, msg)

                ; Exists without ad.
                ; Try place free ad
                res := ShopPutAdOnSlot( slot )
                if ( res = 0 ) {
                    ; Ad not ready
                    return 0
                }
                else if ( res = 1 ) {
                    ; Ad placed.
                    return 1
                }
                else {
                    ; Error
                    dbgMsgBox(true, dbgHeader, "Error.")

                    return -3
                }
            }
            else if ( slotStatus < 0 ) {
                ; An error could mean the shop is scrolled to the end. Either way abort.
                if ( endOfLine ) {
                    ; Normal
                    return 2
                }
                ; Error
                errors++
                if (errors > 1) {
                    dbgMsgBox(true, dbgHeader, "Error.")
                    Sleep, 1000

                    return -2
                }
            }

            slot++
            if (slot > 4) {
                break
            }
        }

        ; Scroll shop
        res := ShopScrollSlots( SHOP_SLOTS_ON_SCREEN )
        alignment := res[2]
        res := res[1]
        endOfLine := res = 0

        Sleep, 200
        ; Verify
        if ( IsInShop() <= 0 ) {
            dbgMsgBox(true, dbgHeader, "Error. Not in shop.")
            Sleep, 1000

            return -1
        }

        scrolls++
        if ( scrolls > 20 ) {
            ; Something is wrong
            dbgMsgBox(true, dbgHeader, "Error. Too many scrolls.")
            Sleep, 1000

            return -3
        }
    }
}


; Looks in the slots to the left where the goods are and tries to sell the
;  selected item. 
; 
; Requiires:
;  The empty shop box must be clicked already.
; 
; Inputs
;  startSlot : If > 0 then the search for item starts here, speeds up.
;
; Returns
;  >0 : The sell slot the item was found in (for use in next consequtive call) 
;   0 : Item not found in the slots with available items.
;  -1 : Screen left
SellItem( itemId, priceMaxOrMin, priceModifier, advertise, startSlot ) {
    global TOP_MAX_SELL_SLOTS_SEARCHED

    dbgEnable := true
    dbgHeader := "SellItem"

    ; Find if item are among the sell slots.
    if ( startSlot <= 0) {
        sellSlot := 0
    }
    else {
        sellSlot := startSlot - 1
    }

    ; Sell slot at lowest 0 here. 
    res := 0
    loop {
        sellSlot++
        if ( sellSlot > TOP_MAX_SELL_SLOTS_SEARCHED ) {
            break
        }

        res := IsItemAtSellSlot( sellSlot, itemId )
        ; Validate
        if ( IsInNewSale() <= 0 ) {
            dbgMsgBox(true, dbgHeader, "Error: Not in new sale.")
            Sleep, 1000
            return -1
        }

        if ( res > 0 ) {
            break
        }
        else if ( res < 0 ) {
            dbgMsgBox(true, dbgHeader, "Error: IsItemAtSellSlot error.")
            Sleep, 1000    
            return res
        }
    }
    msg := "Slot: " . slot
    dbgMsgBox(dbgEnable, dbgHeader, msg)
    
    ; Enough items in inventory to show up among the selectable slots.
    if ( res > 0 ) {
        ; Sell this slot
        res := SellItemAtSlot( sellSlot, priceMaxOrMin, priceModifier, advertise )
        if ( res < 0 ) {
            return res
        }
    }
    else {
        msg := "Item was never found and returns 0."
        dbgMsgBox(dbgEnable, dbgHeader, msg)
        Sleep, 2000 ; XXX

        return 0
    }

    return sellSlot
}


; Get item status of slot item (on screen) in my own shop. Slot 1-4 on screen.
;
; Inputs:
;  screen slot
;  alignment (optional, default 0)
;
; Outputs:
;  >0 : slot status
;   0 : 
;  -1 : status not found
ShopGetMyItemStatusForSlot(screenSlot, alignment := 0) {
    global SHOP_ITEM_EMPTY, SHOP_ITEM_HAS_AD, SHOP_ITEM_SOLD, SHOP_ITEM_ON_SALE

    global SHOP_SLOT_DIFF_X
    global SHOP_SLOT_1_X
    global SHOP_SLOT_1_Y

    global SHOP_AD_X
    global SHOP_AD_Y


    dbgEnable := true
    dbgHeader := "ShopGetMyItemStatusForSlot"
    dbgEnableWait := dbgEnable && false

    slotStatus := 0

    dbgMsgBox(dbgEnable, dbgHeader, "Check on sale.")
    dbgWait(dbgEnableWait, dbgHeader, 1000)
    ; If slot is on display. Same pricetag check for home and friend shop.
    ; Do not return after this, check ad too.
    if ( Helper_IsShopSlotOnSale(screenSlot, alignment) > 0 ) {        
        dbgMsgBox(dbgEnable, dbgHeader, "Helper_IsShopSlotOnSale.")
        dbgWait(dbgEnableWait, dbgHeader, 1000)

        slotStatus :=  SHOP_ITEM_ON_SALE
    }

    dbgMsgBox(dbgEnable, dbgHeader, "Check advertised.")
    dbgWait(dbgEnableWait, dbgHeader, 1000)
    ; If slot is advertised.
    if ( slotStatus = SHOP_ITEM_ON_SALE ){
        if ( Helper_IsShopSlotAdvertised(screenSlot, alignment) > 0 ) {        
            dbgMsgBox(dbgEnable, dbgHeader, "Helper_IsShopSlotAdvertised")

            return SHOP_ITEM_HAS_AD
        }
        else {
            return SHOP_ITEM_ON_SALE
        }
    }

    dbgMsgBox(dbgEnable, dbgHeader, "Check sold.")
    dbgWait(dbgEnableWait, dbgHeader, 1000)
    ; If slot is sold - chicken in middle
    if ( Helper_IsShopSlotSold(screenSlot, alignment) > 0 ) {
        dbgMsgBox(dbgEnable, dbgHeader, "Helper_IsShopSlotSold.")
        dbgWait(dbgEnableWait, dbgHeader, 1000)

        return SHOP_ITEM_SOLD
    }

    dbgMsgBox(dbgEnable, dbgHeader, "Check empty.")
    dbgWait(dbgEnableWait, dbgHeader, 1000)
    ; If slot is empty
    if ( Helper_IsShopSlotEmpty(screenSlot, alignment) > 0 ) {
        dbgMsgBox(dbgEnable, dbgHeader, "IsEmptyShopSlot.")
        dbgWait(dbgEnableWait, dbgHeader, 1000)

        return SHOP_ITEM_EMPTY
    }

    dbgMsgBox(true, dbgHeader, "Error: returns -1")
    return -1
}


; Helper function - use instead: ShopGetMyItemStatusForSlot
; This will not work for Friend shop as it detects only greyscale?
Helper_IsShopSlotAdvertised(screenSlot, alignment := 0) {
    global SHOP_ITEM_HAS_AD

    global SHOP_SLOT_DIFF_X
    global SHOP_SLOT_1_X
    global SHOP_SLOT_1_Y

    global SHOP_AD_X
    global SHOP_AD_Y

    dbgEnable := true
    dbgHeader := "Helper_IsShopSlotAdvertised"
    dbgEnableWait := dbgEnable && false

    ; Use slot center as location reference?
    ; slot is 1-based
    x_add := SHOP_SLOT_DIFF_X*(screenSlot - 1) + alignment

    ; If slot has ad - gray scale on position
    x := SHOP_AD_X + x_add
    y := SHOP_AD_Y
    PixelGetColor, col, x, y, RGB

    cr := IsGrayScale(col)
    msg := "1. x,y,c,ref: " . x . ", " . y . ", " . col . " Result: " . cr
    dbgMsgBox(dbgEnable, dbgHeader, msg)
    dbgWait(dbgEnableWait, dbgHeader, 5000)

    if ( cr > 0 ) {
        msg := "x,y,col: " . x . ", " . y . ", " . col . " " . "SHOP_ITEM_HAS_AD"
        dbgMsgBox(dbgEnable, dbgHeader, msg)

        return SHOP_ITEM_HAS_AD
    }

    return 0
}


; Helper function - use instead: ShopGetMyItemStatusForSlot
; If slot is sold - chicken in middle
Helper_IsShopSlotSold(screenSlot, alignment := 0) {
    global SHOP_SLOT_DIFF_X
    global SHOP_SLOT_1_X, SHOP_SLOT_1_Y

    global SHOP_ITEM_SOLD

    global SHOP_SLOT_SOLD_P1_X
    global SHOP_SLOT_SOLD_P1_Y
    global SHOP_SLOT_SOLD_P1_C
    global SHOP_SLOT_SOLD_P2_X
    global SHOP_SLOT_SOLD_P2_Y
    global SHOP_SLOT_SOLD_P2_C
    global SHOP_SLOT_SOLD_P3_X
    global SHOP_SLOT_SOLD_P3_Y
    global SHOP_SLOT_SOLD_P3_C
    global SHOP_SLOT_SOLD_P4_X
    global SHOP_SLOT_SOLD_P4_Y
    global SHOP_SLOT_SOLD_P4_C

    dbgEnable := true
    dbgHeader := "Helper_IsShopSlotSold"
    dbgEnableWait := dbgEnable && false

    dbgMsgBox(dbgEnable, dbgHeader, "Started.")
    dbgWait(dbgEnableWait, dbgHeader, 1000)

    x_add := SHOP_SLOT_DIFF_X*(screenSlot - 1) + alignment

    P1_X := SHOP_SLOT_SOLD_P1_X + x_add
    P1_Y := SHOP_SLOT_SOLD_P1_Y
    P1_C := SHOP_SLOT_SOLD_P1_C
    P2_X := SHOP_SLOT_SOLD_P2_X + x_add
    P2_Y := SHOP_SLOT_SOLD_P2_Y
    P2_C := SHOP_SLOT_SOLD_P2_C
    P3_X := SHOP_SLOT_SOLD_P3_X + x_add
    P3_Y := SHOP_SLOT_SOLD_P3_Y
    P3_C := SHOP_SLOT_SOLD_P3_C
    P4_X := SHOP_SLOT_SOLD_P4_X + x_add
    P4_Y := SHOP_SLOT_SOLD_P4_Y
    P4_C := SHOP_SLOT_SOLD_P4_C

    res := IsSimilarFourColor( P1_X,P1_Y,P1_C, P2_X,P2_Y,P2_C, P3_X,P3_Y,P3_C, P4_X,P4_Y,P4_C, 0.03)

    return res
}


; Asserts whether the "Edit Sale" inside the shop is open.
; Edit sale is when an existing item in the shop is clicked.
IsInEditSale() {
    global BTN_AD_CLOSE_X, BTN_AD_CLOSE_Y

    x := BTN_AD_CLOSE_X
    y := BTN_AD_CLOSE_Y
    return IsCloseButtonAtPos( [x, y] )
}


; Closes edit sale if possible.
; Returns:
;   1: Was in sale, and clicked. Verifies then that not in window any more.
;  -1: Wasn't in sale. 
CloseEditSale() {
    global BTN_AD_CLOSE_X, BTN_AD_CLOSE_Y

    if ( IsInEditSale() > 0 ) {
        MouseMove, BTN_AD_CLOSE_X, BTN_AD_CLOSE_Y
        Click
        Sleep, 500
        if ( IsInEditSale() <= 0 ) {
            return 1
        }
        else {
            return -1
        }
    }
    else {
        return -1
    }
}


; Asserts whether the "New Sale" inside the shop is open.
IsNewSaleRedX() {
    global BTN_SELL_CLOSE_X, BTN_SELL_CLOSE_Y

    x := BTN_SELL_CLOSE_X
    y := BTN_SELL_CLOSE_Y
    return IsCloseButtonAtPos( [x, y] )
}


; Closes new sale if possible.
; Returns:
;   1: Was in sale, and clicked. Verifies then that not in window any more.
;  -1: Wasn't in sale. 
CloseNewSale() {
    global BTN_SELL_CLOSE_X, BTN_SELL_CLOSE_Y

    if ( IsInNewSale() ) {
        MouseMove, BTN_SELL_CLOSE_X, BTN_SELL_CLOSE_Y
        Click
        Sleep, 500
        if ( IsInNewSale() <= 0 ) {
            return 1
        }
        else {
            return -1
        }
    }
    else {
        return -1
    }
}


; Asserts whether in new sale window.
IsInNewSale() {
    return IsNewSaleRedX()
}


; XXX glappar ibland?
; Tries to put an ad on the slot passed as parameter.
; Slot is 1 : Left of screen
;
; Returns:
;   -1 : Error - Window left
;    0 : Ad not ready
;    1 : Ad placed
ShopPutAdOnSlot(slot) {
    global SHOP_SLOT_DIFF_X, SHOP_SLOT_1_X, SHOP_SLOT_1_Y

    global BTN_AD_X      
    global BTN_AD_Y     
    global BTN_AD_DO_X   
    global BTN_AD_DO_Y  
    global BTN_AD_CLOSE_X
    global BTN_AD_CLOSE_Y

    dbgEnable := true
    dbgHeader := "ShopPutAdOnSlot"

    ; Press slot
    x := (slot-1)*SHOP_SLOT_DIFF_X + SHOP_SLOT_1_X
    y := SHOP_SLOT_1_Y
    MouseMove, %x%, %y%, 0
    Click
    Sleep, 300
    ; Verify window
    if ( IsInEditSale() <= 0 ) {
        msg := "Error: Not in edit sale after click."
        dbgMsgBox(true, dbgHeader, msg)
        Sleep, 1000

        return -1
    }

    ; Press where ad button is
    x := BTN_AD_X
    y := BTN_AD_Y
    MouseMove, x, y, 0
    Click
    Sleep, 300
    ; Verify window
    if ( IsInEditSale() <= 0 ) {
        msg := "Error: Not in edit sale after ad click."
        dbgMsgBox(true, dbgHeader, msg)
        Sleep, 1000

        return -1
    }

    ; Press where create button is (even if ad was not available)
    ;  a successful ad means that red cross goes away (verify shop cross is still there)
    x := BTN_AD_DO_X
    y := BTN_AD_DO_Y
    MouseMove, x, y, 0
    Sleep, 200
    Click
    Sleep, 300
    if ( IsInEditSale() > 0 ) {
        ; If still here then ad was not ready yet.
        ; Go out to shop again.
        x := BTN_AD_CLOSE_X
        y := BTN_AD_CLOSE_Y
        MouseMove, x, y, 0
        Sleep, 200
        Click
        Sleep, 300
        if ( IsInShop() > 0 ) {
            return 1
        }
        return 0
    }
    else {
        ; If edit sale left but still in shop - ok.
        ; Verify shop window
        if ( IsInShop() > 0 ) {
            return 1
        }
    }

    msg := "Error: Leaving without result."
    dbgMsgBox(true, dbgHeader, msg)
    Sleep, 1000

    return -1
}


; Input:
;  slot         : slot to evaluate
;  targetItem   : >0 - item to look for.
;
; Returns:
; >0 : ItemId at slot 
;  0 : No item detected.
; -1 : Error
IsItemAtSellSlot(sellSlot, targetItemId) {
    global APP_SCALE
    ;
    global SELL_ITEM_1_X    
    global SELL_ITEM_1_Y    
    global SELL_ITEM_DIFF_X 
    global SELL_ITEM_DIFF_Y 
    ;
    global ITEM_ID_CORN
    global ITEM_ID_CARROT
    global ITEM_ID_SAW 
    global ITEM_ID_AXE 
    ;
    global DETECT_CORN_P1_X 
    global DETECT_CORN_P1_Y 
    global DETECT_CORN_P1_C 
    global DETECT_CORN_P2_X 
    global DETECT_CORN_P2_Y 
    global DETECT_CORN_P2_C 
    global DETECT_CORN_P3_X 
    global DETECT_CORN_P3_Y 
    global DETECT_CORN_P3_C 
    global DETECT_CORN_P4_X 
    global DETECT_CORN_P4_Y 
    global DETECT_CORN_P4_C
    ;
    global DETECT_CARROT_P1_X 
    global DETECT_CARROT_P1_Y 
    global DETECT_CARROT_P1_C 
    global DETECT_CARROT_P2_X 
    global DETECT_CARROT_P2_Y 
    global DETECT_CARROT_P2_C 
    global DETECT_CARROT_P3_X 
    global DETECT_CARROT_P3_Y 
    global DETECT_CARROT_P3_C 
    global DETECT_CARROT_P4_X 
    global DETECT_CARROT_P4_Y 
    global DETECT_CARROT_P4_C
    
    dbgEnable := true
    dbgHeader := "IsItemAtSellSlot"

    ; Validate inputs
    if ( targetItemId < 0 || targetItemId = "" ) {
        ; Null or invalid.
        dbgMsgBox(true, dbgHeader, "Invalid item.")
        Sleep, 2000
        return -1
    }

    ; Validate support for Id
    if ( targetItemId > 0 ) {
        if ( targetItemId != ITEM_ID_CORN && targetItemId != ITEM_ID_CARROT ) {
            ; Not supported.
            dbgMsgBox(true, dbgHeader, "Non-supported item.")
            Sleep, 2000
            return -1
        }        
    }

    ; Make reference position for image recognition.
    slotCenter := GetSellSlotCenter( sellSlot )
    ; DEBUG
    ; x := slotCenter[1]
    ; y := slotCenter[2]
    ; MouseMove, x, y
    ; MsgBox,,,IsItemAtSellSlot looking at mouse. %x% .. %y%, 2

    ; Get data for selected item
    if ( targetItemId = ITEM_ID_CORN ) {
        x1 := DETECT_CORN_P1_X
        y1 := DETECT_CORN_P1_Y
        c1 := DETECT_CORN_P1_C
        x2 := DETECT_CORN_P2_X
        y2 := DETECT_CORN_P2_Y
        c2 := DETECT_CORN_P2_C
        x3 := DETECT_CORN_P3_X
        y3 := DETECT_CORN_P3_Y
        c3 := DETECT_CORN_P3_C
        x4 := DETECT_CORN_P4_X
        y4 := DETECT_CORN_P4_Y
        c4 := DETECT_CORN_P4_C
    } 
    else if ( targetItemId = ITEM_ID_CARROT ) {
        x1 := DETECT_CARROT_P1_X
        y1 := DETECT_CARROT_P1_Y
        c1 := DETECT_CARROT_P1_C
        x2 := DETECT_CARROT_P2_X
        y2 := DETECT_CARROT_P2_Y
        c2 := DETECT_CARROT_P2_C
        x3 := DETECT_CARROT_P3_X
        y3 := DETECT_CARROT_P3_Y
        c3 := DETECT_CARROT_P3_C
        x4 := DETECT_CARROT_P4_X
        y4 := DETECT_CARROT_P4_Y
        c4 := DETECT_CARROT_P4_C
    }
    else {
        ; Continue with the other stuff
        return -1
    }

    ; Offset regardless of item
    x1 += slotCenter[1]
    y1 += slotCenter[2]
    x2 += slotCenter[1]
    y2 += slotCenter[2]
    x3 += slotCenter[1]
    y3 += slotCenter[2]
    x4 += slotCenter[1]
    y4 += slotCenter[2]  

    ; msg := ""
    ; msg := msg . x1 . ", " . y1 . "`n"
    ; msg := msg . x2 . ", " . y2 . "`n"
    ; msg := msg . x3 . ", " . y3 . "`n"
    ; msg := msg . x4 . ", " . y4 . "`n"
    ; MsgBox,, Corn, %msg%
    res := IsSimilarFourColor(x1, y1, c1, x2, y2, c2, x3, y3, c3, x4, y4, c4)

    ; if (dbgEnable) {
    ;     ShowFourCoords(x1, y1, x2, y2, x3, y3, x4, y4)
    ; }


    if ( res ) {
        return targetItemId
    }

    return 0
}


; Returns:
;   the coordinates of the slot center.
; -1, -1 if invalid sellSLot
;
; The Slot has to be the same way hay day moves an item based on count
; 1 2
; 3 4
; 5 6
; 7 8
GetSellSlotCenter(screenSlot) {
    global SELL_ITEM_1_X, SELL_ITEM_1_Y
    global SELL_ITEM_DIFF_X, SELL_ITEM_DIFF_Y

    ; Validate inputs
    if ( screenSlot < 1 || screenSlot > 8) {
        return [-1, -1]
    }

    RC := Mod(screenSlot, 2) = 0
    if ( !RC ) {
        ; Column multiplier
        X := SELL_ITEM_1_X

        ; Makes 0-3 of the slot meaning diff y
        slot_temp := ( (screenSlot+1) / 2 ) - 1
    }
    else {
        ; Column multiplier
        X := SELL_ITEM_1_X + SELL_ITEM_DIFF_X
        slot_temp := (screenSlot / 2) - 1
    }
    Y := SELL_ITEM_1_Y + slot_temp*SELL_ITEM_DIFF_Y

    return [X, Y]
}


; Try closes shop from all cases of eit sale, new sale open. Screen should now be 
;  either Home or Friend, but this is not verified. 
CloseShopEditNew() {
    ; Normally all shop functions should themselves exit, so perhaps bug if come in here.
    if ( IsInEditSale() > 0 ) {
        CloseEditSale()
        Sleep, 500
    }

    ; Expected normal way out
    if ( IsInNewSale() > 0 ) {
        CloseNewSale()
        Sleep, 500
    }

    ; Finally check if in shop. Not required but we present status for outside usage.
    if ( IsInShop() > 0 ) {
        res := CloseShop()
        Sleep, 500
        if ( IsInShop() > 0 ) {
            return -1
        }
        else {
            return 1
        }
    }
    else {
        return -1
    }
}


; Requires:
;  Must be in own shop.
;
; Starting at slot nbr, in case previous sell was aborted in the middle due to reload.
; Sells if the item is found in stock.
; Advertises already goods on sale.
;
; Returns
;  >0 : Nbr of sell times.
;   0 : No free slots.
;  <0 : The last absolute slot checked when there was an error
SellAllItem(itemId, priceMaxOrMin, priceModifier, advertise, absoluteStartSlot := 1) {
    global SHOP_SLOTS_ON_SCREEN

    global SHOP_ITEM_EMPTY, SHOP_ITEM_HAS_AD, SHOP_ITEM_ON_SALE, SHOP_ITEM_SOLD

    global SELECT_SELL_TYPE_X         
    global SELECT_SELL_TYPE_SILO_Y    
    global SELECT_SELL_TYPE_BARN_Y    
    global SELECT_SELL_TYPE_HELPERS_Y 

    dbgEnable := true
    dbgHeader := "SellAllItem"
    dbgEnableWait := dbgEnable && false

    absoluteSlot := absoluteStartSlot

    adPlaced := false       ; Remember if a listed goods was advertised.
    anyItemsLeft := true   

    ; Open the menu for the correct type of item - TODO improve.
    selltypeSelected := false

    ; Initialize once to have alignment on screen.
    scrollResult := ShopScrollToSlot( absoluteSlot )
    res := scrollResult[1]
    alignment := scrollResult[2]
    if ( res > 0 ) {
        screenSlot := res
    }
    else {
        dbgMsgBox(true, dbgHeader, "Error: scroll error.")
        Sleep, 1000

        return res
    }

    ; Other initialisations
    sellSlot := 1
    sellCounts := 0

    ; Check all further slots in shop from current position.
    lastLoop := false
    loop {
        msg := "Abs slot / Scr slot: " . absoluteSlot . " / " . screenSlot . " "

        found := 0
        slotStatus := ShopGetMyItemStatusForSlot( screenSlot, alignment )

        msg2 := msg . " Status: " . slotStatus
        dbgMsgBox(dbgEnable, dbgHeader, msg2)
        dbgWait(dbgEnableWait, dbgHeader, 1000)
        
        ; Handle the possible slot statuses.
        if ( slotStatus = SHOP_ITEM_EMPTY && anyItemsLeft ) {
            found := true

            msg := msg . "Gonna press it was empty."
            dbgMsgBox(dbgEnable, dbgHeader, msg)
            dbgWait(dbgEnableWait, dbgHeader, 1000)

            ; Press it
            PressShopSlot( screenSlot )
            Sleep, 500
        }
        else if ( slotStatus = SHOP_ITEM_SOLD && anyItemsLeft ) {
            found := true

            msg := msg . "Sold, get cash."
            dbgMsgBox(dbgEnable, dbgHeader, msg)
            dbgWait(dbgEnableWait, dbgHeader, 1000)

            ; Press it twice - NOTE After the second the wait has to be short or long. If the wait is medium,
            ;  about 500 ms then the money from goods will pass over the red x.
            PressShopSlot( screenSlot )
            Sleep, 500
            PressShopSlot( screenSlot )
            Sleep, 200
        }
        else if ( slotStatus = SHOP_ITEM_ON_SALE && !adPlaced ) {
            ; Try to put an ad on an existing goods on sale without ad.
            ; XXX trycker helt fucked.
            msg := msg . "Will try to advertise it."
            dbgMsgBox(dbgEnable, dbgHeader, msg)
            dbgWait(dbgEnableWait, dbgHeader, 1000)

            res := ShopPutAdOnSlot( screenSlot )
            if ( res > 0) {
                adPlaced := true
            }
        }


        ; Empty slot found and clicked. Sell it.
        if ( found ) {
            ; Verify if in new sale or else abort.
            if ( IsInNewSale() <= 0 ) {
                dbgMsgBox(true, dbgHeader, "Error: Not in New Sale window.")
                dbgWait(dbgEnableWait, dbgHeader, 1000)

                return -absoluteSlot
            }

            ; Select the left menu depending on what to sell. - TODO support more than crops.
            if ( !selltypeSelected ) {
                MouseMoveDLL([SELECT_SELL_TYPE_X, SELECT_SELL_TYPE_SILO_Y])
                Sleep, 100
                Click
                Sleep, 100
                selltypeSelected := true
            }

            msg := "A sale look from sell slot: " . sellSlot
            dbgMsgBox(dbgEnable, dbgHeader, msg)

            ; Sell item gets optional parameter sellSlot where the last item was found, since it moves
            ;  further down the list of available items when reducing. After the sale the new position 
            ;  of the goods to sale is returned to quicker find it for the next shop slot.
            res := SellItem( itemId, priceMaxOrMin, priceModifier, advertise, sellSlot )

            msg := "foundSellSlot: " . res
            dbgMsgBox(dbgEnable, dbgHeader, msg)

            if ( res > 0 ) {
                sellSlot := res
                sellCounts++
            }
            else {
                ; Item to sell was not found, or there was an error.
                if ( res < 0 ) {
                    ; Stop if SellItem error
                    dbgMsgBox(true, dbgHeader, "Error: item to sell.")

                    return -absoluteSlot
                }
                else if ( adPlaced || sellCounts > 0 ) {
                    ; Stop if SellItem Item not found (inventory empty) only if allow for advertisement.
                    dbgMsgBox(dbgEnable, dbgHeader, "No item to sell.")

                    CloseNewSale()
                    break
                }

                ; Continue with loop.
                anyItemsLeft := false
                if ( IsInNewSale() > 0 ) {
                    CloseNewSale()
                    Sleep, 300
                }
                else {
                    dbgMsgBox(true, dbgHeader, "Error: Screen left.")

                    return -absoluteSlot
                }
            }
        }

        ; Continue and point to the next slot, scroll if needed.
        ;
        ; If all screen slots done it's time to scroll.
        if ( screenSlot >= SHOP_SLOTS_ON_SCREEN ) {
            dbgMsgBox(dbgEnable, dbgHeader, "Time to scroll.")

            if ( lastLoop ) {
                ; There has already been one scroll attempt that found end of line.
                dbgMsgBox(dbgEnable, dbgHeader, "Breaking coz last loop.")

                break
            }
            else {
                ; Scroll
                res := ShopScrollSlots( SHOP_SLOTS_ON_SCREEN )
                res := res[1]
    
                msg := "Scroll result: " . res
                dbgMsgBox(dbgEnable, dbgHeader, msg)

                if ( res = 1 ) {
                    ; Full scroll
                    dbgMsgBox(dbgEnable, dbgHeader, "Full scroll.")
                    screenSlot := 1
                    absoluteSlot++
                }
                else if ( res = 0 ) {
                    ; Partial scroll, dont know so check existing absolute slot again
                    dbgMsgBox(dbgEnable, dbgHeader, "Partial scroll.")
                    screenSlot := 1
                    lastLoop := true
                }
                else {
                    ; Error
                    dbgMsgBox(true, dbgHeader, "Error: Scroll error.")
                    return res
                }
            }
        }
        else {
            ; Check next one on screen
            screenSlot++
            absoluteSlot++
        }
    }

    ; Verify in shop after.
    if ( IsInShop() > 0 ) {
        CloseShop()
    }

    msg := "Sellcounts: " . sellCounts
    dbgMsgBox(dbgEnable, dbgHeader, msg)
    
    return sellCounts
}


; TODO make constant
AbsoluteSlotToScreenSlot( absoluteSlot ) {
    global SHOP_SLOTS_ON_SCREEN

    if ( absoluteSlot > SHOP_SLOTS_ON_SCREEN ) {
        return absoluteSlot - SHOP_SLOTS_ON_SCREEN
    }
    else {
        return absoluteSlot 
    }
}


; Helper function. For selling the item found at sellSlot in the list of goods.
;   -1  : Screen left?
;   -2  : Bad input
SellItemAtSlot( sellSlot, priceMaxOrMin, priceModifier, advertise ) {
    global PRICE_MAX, PRICE_MIN
    global BTN_PRICE_MAX_X, BTN_PRICE_MAX_Y
    global BTN_PRICE_MIN_X, BTN_PRICE_MIN_Y
    global BTN_SELL_AD_X, BTN_SELL_AD_Y
    global BTN_PUT_ON_SALE_X, BTN_PUT_ON_SALE_Y
    global BTN_PRICE_DOWN_X, BTN_PRICE_DOWN_Y
    global BTN_PRICE_UP_X, BTN_PRICE_UP_Y

    dbgEnable := true
    dbgHeader := "SellItemAtSlot"

    ; Press item slot
    if ( sellSlot <= 0 ) {
        return -2
    }
    slotCenter := GetSellSlotCenter( sellSlot )
    MouseMove, slotCenter[1], slotCenter[2]
    dbgMsgBox(dbgEnable, dbgHeader, "At slot center.")
    Click
    Sleep, 500

    ; Select the price tag - if max then the modifier can only be down...
    if (priceMaxOrMin = PRICE_MAX) {
        pBtn_X := BTN_PRICE_MAX_X
        pBtn_Y := BTN_PRICE_MAX_Y
        pModBtn_X := BTN_PRICE_DOWN_X
        pModBtn_Y := BTN_PRICE_DOWN_Y
    }
    else if (priceMaxOrMin = PRICE_MIN) {
        pBtn_X := BTN_PRICE_MIN_X
        pBtn_Y := BTN_PRICE_MIN_Y
        pModBtn_X := BTN_PRICE_UP_X
        pModBtn_Y := BTN_PRICE_UP_Y
    }
    else {
        return -1
    }
    ;Press max / min button
    MouseMove, pBtn_X, pBtn_Y
    dbgMsgBox(dbgEnable, dbgHeader, "At price button.")

    Click
    Sleep, 200

    ; Modify the price
    pMod := Abs(priceModifier)
    cnt := 0
    MouseMove, pModBtn_X, pModBtn_Y
    dbgMsgBox(dbgEnable, dbgHeader, "At modifier button.")
    loop {
        if ( cnt >= pMod ) {
            break
        }
        Click
        Sleep, 100
        cnt++
    }

    ; Advertise
    if ( advertise ) {
        MouseMove, BTN_SELL_AD_X, BTN_SELL_AD_Y
        dbgMsgBox(dbgEnable, dbgHeader, "At ad button.")
        Click
        Sleep, 100
    }

    ; Verify better late than never
    if ( IsInNewSale() <= 0 ) {
        dbgMsgBox(true, dbgHeader, "Error: Not in new sale.")

        return -1
    }

    ; Sell it
    MouseMove, BTN_PUT_ON_SALE_X, BTN_PUT_ON_SALE_Y
    dbgMsgBox(dbgEnable, dbgHeader, "At sell button.")
    Click
    Sleep, 100

    return 1
}
; ------------------------------------------------------------------------------------------------











; Test and validation scripts.

; Returns the item of slot 1-4 visible in user's shop.
TEST_GetShopItemStatus() {
    ; Inside shop 

    dbgEnable := true
    dbgHeader := "TEST_GetShopItemStatus"

    ; If slot does not have ad
    ; Press slot
    ; Press where ad button is
    ; Press where create button is
    ;  a successful ad means that red cross goes away (verify shop cross is still there)
    ; Exit sale (pressing red cross not necessary) if not already.
    
    ; If slot is sold

    ; If slot is empty

    slot := 1
    msg := ""
    loop {

        slotStatus := ShopGetMyItemStatusForSlot(slot)
        msg := msg . slot . ": " . ShopMyItemStatus_ToString(slotStatus) . "`n"
        dbgMsgBox(dbgEnable, dbgHeader, msg)

        slot++
        if (slot > 4) {
            break
        }
    }
}
