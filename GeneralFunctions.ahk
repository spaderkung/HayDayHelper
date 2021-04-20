; Library to be included in other scripts.


; ------------------------------------------------------------------------------------------------
; General functions
;



dbgWait(enable, header, sleepTime := 0) {
    if (enable) {
        if ( sleepTime > 0 ) {
            Sleep, sleepTime
        }
        else {
            msgbox,,,%header%: Debug wait until click.
        }
    }
}


; Returns:
;  [h, s, v]
Convert_RGBHSV(rgb_col) {
    dbgEnable := false
    dbgHeader := "Convert_RGBHSV"

    colarr := ColToArr(rgb_col)
    R := colarr[1] / 255.0
    G := colarr[2] / 255.0
    B := colarr[3] / 255.0

    if (R>G) {
        if (R>B)                                               ;                max=R
        {
            MIN:=B<G ? B : G
            V:=R
            H:=Mod((G-B)/(V-MIN)*60+360,360)                     ;hue
        } 
        else {
            MIN:=R<G ? R : G
            V:=B
            H:=(V=MIN ? 0 : (R-G)/(V-MIN)*60+240)                ;hue
        }
    } 
    else {
        if (G>B) {
            MIN:=B<R ? B : R
            V:=G
            H:=Mod((B-R)/(V-MIN)*60+120,360)                     ;hue
        } 
        else {
            MIN := R<G ? R : G
            V := B
            H := (V=MIN ? 0 : (R-G)/(V-MIN)*60+240)                ;hue
        }
    }

    S := (V=0 ? 0 : (V-MIN)/V)                                 ;     saturation

    return [H, S, V]
}


; Inputs:
;  seconds
;
; Returns:
;  [day, hour, min, sec] 
Convert_secToArrHMS(num) {
    min := 0
    hour := 0
    day := 0

    if ( num > 59 ) {
        sec := Mod(num, 60)
        num := floor(num / 60)
        if ( num > 59) {
            min := Mod(num, 60)
            num := floor(num / 60)
            if (num > 23) {
                hour := Mod(num, 24)
                day := floor(num / 24)
            }
            else {
                hour := num
            }
        }
        else {
            min := num
        }
    }
    else {
        sec := num
    }

    return [day, hour, min, sec] 
}


vec2_sub(v1, v2) {
    return [v1[1]-v2[1], v1[2]-v2[2]]
}


vec2_add(v1, v2) {
    return [v1[1]+v2[1], v1[2]+v2[2]]
}


vec2_toString(v) {
    return "[" . v[1] . ", " . v[2] . "]"
}


; Exact. Not like fucked up AHK MoveMouse.
; Includes a move to the position and wait before click.
; 500 ms minimum. TODO - configure delays. At least 200 ms wait before after needed in HayDay.
MouseDragDLL(startPos, endPos) {
    start_x := startPos[1]
    start_y := startPos[2]
    end_x := endPos[1]
    end_y := endPos[2]

    dly_0 := 100
    dly_1 := 100
    dly_2 := 200
    dly_3 := 200
    dly_4 := 0
    if ( slow ) {
        dly_0 := 400
        dly_1 := 400
        dly_2 := 400
        dly_3 := 400
        dly_4 := 200
    }

    ; Move before clicking.
    Sleep, dly_0
    DllCall("SetCursorPos", "int", start_x, "int", start_y)
    Sleep, dly_1

    ; Click and drag.
    Click, Down
    Sleep, dly_2

    DllCall("SetCursorPos", "int", end_x, "int", end_y)

    Sleep, dly_3
    Click, Up

    Sleep, dly_4
    return
}


; Exact. Not like fucked up AHK MoveMouse.
MouseMoveDLL(targetPos) {
    x := ceil( targetPos[1] )
    y := ceil( targetPos[2] )

    DllCall("SetCursorPos", "int", x, "int", y)
    return
}


; Convert app coord (including header) to screen coord.
AC2SC(coord, vector) {
    global APP_TOP_LEFT_X, APP_TOP_LEFT_Y, APP_SCALE, APP_HEADER_Y

    if (vector = 0) {
        ; x
        return coord*APP_SCALE + APP_TOP_LEFT_X
    }
    else {
        ; y
        return (coord - APP_HEADER_Y)*APP_SCALE + APP_HEADER_Y + APP_TOP_LEFT_Y 
    }
}


; Returns array of three bytes. Hex but still nbr.
ColToArr(col) {
    dbgEnable := false
    dbgHeader := "ColToArr"

    r := col >> 16
    g := (col >> 8) & 0x0000FF
    b := col & 0x0000FF

    if ( dbgEnable ) {
        msg := r . " " . g . " " . b
        dbgMsgBox(dbgEnable, dbgHeader, msg)
    }

    return [r, g, b]
}


; Asserts whether the color is grayscale.
;
; Inputs:
;  color
IsGrayScale(col, saturation := 0.1) {
    dbgEnable := true
    dbgHeader := "IsGrayScale"
    dbgEnableWait := dbgEnable && false

    ; ; Little variance of RGB means gray scale.
    ; colArr := ColToArr(col)
    ; r := colArr[1]
    ; g := colArr[2]
    ; b := colArr[3]

    ; ; Average
    ; avg := (r + g + b) / 3

    ; ; Variance
    ; diff := (r-avg)**2 + (g-avg)**2 + (b-avg)**2

    ; msg := "Color: " . col . " r: " . r . " g: " . g .  " b: " . b . "Diff: " . diff

    ; dbgMsgBox(dbgEnable, dbgHeader, msg)
    ; dbgWait(dbgEnableWait, dbgHeader, 3000)
    
    ; if (diff > 20) {
    ;     return false
    ; }
    ; return true

    hsv := Convert_RGBHSV(col)

    msg := "Color: " . col . " h: " . hsv[1] . " s: " . hsv[2] .  " v: " . hsv[3] . ", sat lim: " . saturation
    dbgMsgBox(dbgEnable, dbgHeader, msg)
    dbgWait(dbgEnableWait, dbgHeader, 3000)

    if (hsv[2] < saturation) {
        return true
    }

    return false
}


; Asserts whether the color at a pixel pos is grayscale.
;
; Inputs:
;  [x, y]
IsGrayScaleAtPos(coords, saturation := 0.1) {
    dbgEnable := true
    dbgHeader := "IsGrayScaleAtPos"
    dbgEnableWait := dbgEnable && false

    X := coords[1]
    Y := coords[2]

    PixelGetColor, col, X, Y, RGB
    return IsGrayScale(col, saturation)
}


; Compare two colors and allow for some difference
;  Uses Hue and Value with same tolerance.
;
; Inputs:
;  color1 RGB
;  color2 RGB
;  tolerance %/100
IsAlmostSameColor(c1, c2, tol := 0.07) {
    dbgEnable := false
    dbgHeader := "IsAlmostSameColor"
    dbgEnableWait := dbgEnable && true

    if ( c1= || c2= ) {
        msg := "IsAlmostSameColor null parameter"
        dbgMsgBox(true, dbgHeader, msg)
    }

    ;--------------
    ; Judge by hue and value, same tolerance for both.
    hsv_c1 := Convert_RGBHSV(c1)
    hsv_c2 := Convert_RGBHSV(c2)
    diff_h := Abs( Mod((hsv_c1[1] - hsv_c2[1]), 360) ) / 360.0
    diff_v := Abs(hsv_c1[3] - hsv_c2[3])

    msg := "h1: " . hsv_c1[1] . ", h2: " . hsv_c2[1] . ", diff: " . diff_h . ", Tol: " . tol
    dbgMsgBox(dbgEnable, dbgHeader, msg)
    dbgWait(dbgEnableWait, dbgHeader)

    msg := "v1: " . hsv_c1[3] . ", v2: " . hsv_c2[3] . ", diff: " . diff_v . ", Tol: " . tol
    dbgMsgBox(dbgEnable, dbgHeader, msg)
    dbgWait(dbgEnableWait, dbgHeader)

    if ( diff_h <= tol && diff_v <= tol ) {
        return 1
    }
    else {
        return 0
    }
    ;--------------

    ; Msgbox,,IsAlmostSameColor,%c1%

    diff := abs(c1-c2)/c1

    c1a := ColToArr(c1)
    c2a := ColToArr(c2)

    rd := abs( c1a[1]-c2a[1] ) / 256
    gd := abs( c1a[2]-c2a[2] ) / 256
    bd := abs( c1a[3]-c2a[3] ) / 256

    diff := ( rd + gd + bd ) / 3

    ;DEBUG
    msg := "c1: " . c1 . ", c2: " . c2 . ", diff: " . diff . ", Tol: " . tol
    dbgMsgBox(dbgEnable, dbgHeader, msg)
    dbgWait(dbgEnableWait, dbgHeader)

    if (diff < tol) {
        return true
    }
    return false
}


; Inputs:
;  Coords and reference color.
;
; Actual color is sampled at coords (blurred) 
; It was not enough to just use 1 pixel even with tolerance. Black/white...
IsSimilarFourColor(x1, y1, c1, x2, y2, c2, x3, y3, c3, x4, y4, c4, tol := 0.07) {
    dbgEnable := false
    dbgHeader := "IsSimilarFourColor"
    dbgEnableWait := dbgEnable && true

    if (x1=""||y1=""||c1=""||x2=""||y2=""||c2=""||x3=""||y3=""||c3=""||x4=""||y4=""||c4=""||) {
        dbgMsgBox(true, dbgHeader, "null parameter.")
    }

    ; Check colors for screen
    hits := 0
    hitsRequired := 4

    ; Blurpixel 
    b := 1  ; 2 makes it rather slow

    ; PixelGetColor, col, x1, y1, RGB
    col := Blur( [x1, y1], b)
    if ( dbgEnable ) {
        MouseMove, x1, y1
        dbgWait(dbgEnableWait, dbgHeader, 1000)
    }
    if ( IsAlmostSameColor(col, c1, tol) > 0 ) {
        hits++
    }
    if ( dbgEnable ) {
        msg := "Col, Ref: " . col . ", " c1 . " Total hits: " . hits 
        dbgMsgBox(dbgEnable, dbgHeader, msg)
        MouseMove, x1, y1
    }

    ; PixelGetColor, col, x2, y2, RGB
    col := Blur( [x2, y2], b)
    if ( dbgEnable ) {
        MouseMove, x2, y2
        dbgWait(dbgEnableWait, dbgHeader, 1000)
    }
    if ( IsAlmostSameColor(col, c2, tol) > 0 ) {
        hits++
    }
    if ( dbgEnable ) {
        msg := "Col, Ref: " . col . ", " c2 . " Total hits: " . hits 
        dbgMsgBox(dbgEnable, dbgHeader, msg)
        MouseMove, x2, y2
    }

    ; PixelGetColor, col, x3, y3, RGB
    col := Blur( [x3, y3], b)
    if ( dbgEnable ) {
        MouseMove, x3, y3
        dbgWait(dbgEnableWait, dbgHeader, 1000)
    }
    if ( IsAlmostSameColor(col, c3, tol) > 0 ) {
        hits++
    }
    if ( dbgEnable ) {
        msg := "Col, Ref: " . col . ", " c3 . " Total hits: " . hits 
        dbgMsgBox(dbgEnable, dbgHeader, msg)
        MouseMove, x3, y3
    }

    ; PixelGetColor, col, x4, y4, RGB
    col := Blur( [x4, y4], b)
    if ( dbgEnable ) {
        MouseMove, x4, y4
        dbgWait(dbgEnableWait, dbgHeader, 1000)
    }
    if ( IsAlmostSameColor(col, c4, tol) > 0 ) {
        hits++
    }
    if ( dbgEnable ) {
        msg := "Col, Ref: " . col . ", " c4 . " Total hits: " . hits 
        dbgMsgBox(dbgEnable, dbgHeader, msg)
        MouseMove, x4, y4
    }

    msg := msg . "Hits / Required: " . hits . " / " . hitsRequired
    dbgMsgBox(dbgEnable, dbgHeader, msg)

    if (hits >= hitsRequired) {
        return true
    }
    return false
}


; Takes n pixel blur at pos
Blur(pos, n) {
    dbgEnable := false
    dbgHeader := "Blur"

    rsum := 0
    gsum := 0
    bsum := 0

    ; Debug out
    X := pos[1]
    Y := pos[2]
    PixelGetColor, col, X, Y, RGB
    msg := "Center: " . col

    ; n := 1  ; Nbr of pixels out from center
    ns := ( 2*n + 1 )**2
    lc := 2*n

    Y := pos[2] - n
    i := 0
    loop {
        X := pos[1] - n
        j := 0
        loop {
            PixelGetColor, col, X, Y, RGB
            colArr := ColToArr(col)
            rsum += colArr[1]
            gsum += colArr[2]
            bsum += colArr[3]

            X++
            j++
            if (j>lc) {
                break
            }
        }
        Y++
        i++
        if (i>lc) {
            break
        }
    }
    rsum := ceil( rsum/ns )
    gsum := ceil( gsum/ns )
    bsum := ceil( bsum/ns )

    rstr := Format("{:X}", rsum)
    gstr := Format("{:X}", gsum)
    bstr := Format("{:X}", bsum)
    
    if (rsum < 16) {
        rstr := "0" . rstr
    }
    if (gsum < 16) {
        gstr := "0" . gstr
    }
    if (bsum < 16) {
        bstr := "0" . bstr
    }
    blurCol := "0x" .  rstr . gstr . bstr
    
    ; Debug
    msg := msg . " Blur: " . blurCol
    dbgMsgBox(dbgEnable, dbgHeader, msg)

    return blurCol
}


; Print debug message to output.
dbgMsgBox(dbgEnable, dbgMsgHeader, dbgMsg, dbgMsgTime := 1) {
    if (dbgEnable) {
        msg := dbgMsgHeader . ": " . dbgMsg
        GuiControl,, GuiTxtDbg, %msg%

        ; Sleep, 5000

        return
    }
}
; ------------------------------------------------------------------------------------------------


