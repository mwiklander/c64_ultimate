*=$0801
        .word next
        .word 10
        .byte $9e
        .text "2064"
        .byte 0
next    .word 0

*=$0810
        sei

        ; Scene colors.
        lda #$06
        sta $d020       ; Border: blue
        lda #$00
        sta $d021       ; Background: black

        ; Use VIC bank 0 so sprite data at $2000 is visible to VIC-II.
        lda $dd00
        ora #%00000011
        sta $dd00

        ; Fill upper screen with a simple sky texture.
        lda #46         ; '.'
        ldx #0
fill_screen:
        sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $06e8,x
        inx
        bne fill_screen

        ; Sky color.
        lda #$0b        ; Light blue
        ldx #0
fill_color:
        sta $d800,x
        sta $d900,x
        sta $da00,x
        sta $dae8,x
        inx
        bne fill_color

        ; Small title text.
        ldx #0
text_loop:
        lda banner,x
        beq text_done
        sta $0410,x
        inx
        bne text_loop
text_done:

        ; Draw a two-layer platform (grass + brick).
        ; X range matches runner turn points: 72..232 (+ sprite width on right).
        ldx #0
platform_loop:
        lda #102        ; 'f' style texture for grass row
        sta $06d6,x
        lda #$05        ; Green
        sta $dad6,x

        lda #66         ; 'b' style texture for brick row
        sta $06fe,x
        lda #$08        ; Orange
        sta $dafe,x
        inx
        cpx #23
        bne platform_loop

        ; Sprite 0 initial position.
        lda #72
        sta x_pos
        lda #172
        sta y_pos
        lda x_pos
        sta $d000
        lda y_pos
        sta $d001

        ; Sprite pointers in screen memory.
        ; $2000/64 = $80 (frame A), $2040/64 = $81 (frame B).
        lda #$80
        sta $07f8

        ; Multicolor sprite setup.
        lda $d01c
        ora #%00000001
        sta $d01c
        lda #$0a
        sta $d025       ; Shared multicolor 0 (light red)
        lda #$07
        sta $d026       ; Shared multicolor 1 (yellow)
        lda #$01
        sta $d027       ; Per-sprite color (white)

        ; Keep X MSB clear so X stays in 0-255 range.
        lda $d010
        and #%11111110
        sta $d010

        ; Keep sprite in front of character graphics.
        lda $d01b
        and #%11111110
        sta $d01b

        ; Enable sprite 0.
        lda $d015
        ora #%00000001
        sta $d015

        ; Re-enable IRQ so KERNAL keyboard scan/GETIN works.
        cli

main_loop:
        jsr wait_frame

        inc frame_delay
        lda frame_delay
        and #%00000011
        bne main_loop

        lda game_state
        beq state_running
        cmp #1
        beq state_falling
        jmp main_loop

state_running:
        jsr handle_input
        jsr check_platform_support
        jmp update_sprite

state_falling:
        lda y_pos
        clc
        adc #3
        sta y_pos
        cmp #245
        bcc update_sprite

        lda #2
        sta game_state

        ; Hide sprite and draw GAME OVER once.
        lda $d015
        and #%11111110
        sta $d015
        jsr draw_game_over
        jmp main_loop

update_sprite:
        lda x_pos
        sta $d000
        lda y_pos
        sta $d001

        ; Flip between two frames for a running look.
        inc anim_tick
        lda anim_tick
        and #%00000100
        beq frame_a
        lda #$81
        sta $07f8
        jmp main_loop
frame_a:
        lda #$80
        sta $07f8
        jmp main_loop

handle_input:
        ; Direct keyboard matrix scan for held-key movement.
        ; Z = PA1/PB4, X = PA2/PB7.
        lda #$fd
        sta $dc00
        lda $dc01
        and #%00010000
        beq key_left

        lda #$fb
        sta $dc00
        lda $dc01
        and #%10000000
        beq key_right
        jmp no_key

key_left:
        lda x_pos
        beq store_left
        sec
        sbc #2
store_left:
        sta x_pos
        lda #$ff
        sta $dc00
        lda #1
        sta direction
        rts

key_right:
        lda x_pos
        cmp #253
        bcs store_right
        clc
        adc #2
store_right:
        sta x_pos
        lda #$ff
        sta $dc00
        lda #0
        sta direction
        rts

no_key:
        lda #$ff
        sta $dc00
        rts

check_platform_support:
        ; Use sprite center/feet area rather than left edge for support checks.
        ; Platform pixels span X=72..255, so left-edge X support is ~60..243.
        lda x_pos
        cmp #59
        bcc start_fall
        cmp #244
        bcs start_fall
        rts

start_fall:
        lda #1
        sta game_state
        rts

draw_game_over:
        ldx #0
game_over_loop:
        lda game_over_text,x
        beq game_over_done
        sta $05eb,x
        lda #$02        ; Red text
        sta $d9eb,x
        inx
        bne game_over_loop
game_over_done:
        rts

wait_frame:
wait_hi:
        lda $d012
        cmp #$ff
        bne wait_hi
wait_lo:
        lda $d012
        cmp #$ff
        beq wait_lo
        rts

x_pos:
        .byte 72

y_pos:
        .byte 172

direction:
        .byte 0          ; 0 = right, 1 = left

game_state:
        .byte 0          ; 0 = running, 1 = falling, 2 = game over

anim_tick:
        .byte 0

frame_delay:
        .byte 0

banner:
        .text " C64 SPRITE DEMO: RETRO RUNNER "
        .byte 0

game_over_text:
        ; Screen codes avoid PETSCII/charset ambiguity.
        .byte 32,7,1,13,5,32,15,22,5,18,33,32
        .byte 0

*=$2000
sprite_frame_a:
        ; 24x21 multicolor sprite: retro runner frame A.
        .byte $00,$00,$00
        .byte $00,$3c,$00
        .byte $00,$ff,$00
        .byte $03,$ff,$c0
        .byte $03,$c3,$c0
        .byte $03,$ff,$c0
        .byte $03,$7e,$c0
        .byte $00,$3c,$00
        .byte $00,$7e,$00
        .byte $00,$ff,$00
        .byte $01,$ff,$80
        .byte $01,$e7,$80
        .byte $01,$e7,$80
        .byte $01,$ff,$80
        .byte $00,$66,$00
        .byte $00,$66,$00
        .byte $00,$e7,$00
        .byte $00,$c3,$00
        .byte $01,$81,$80
        .byte $03,$00,$c0
        .byte $06,$00,$60
        .byte $00

*=$2040
sprite_frame_b:
        ; 24x21 multicolor sprite: retro runner frame B.
        .byte $00,$00,$00
        .byte $00,$3c,$00
        .byte $00,$ff,$00
        .byte $03,$ff,$c0
        .byte $03,$c3,$c0
        .byte $03,$ff,$c0
        .byte $03,$7e,$c0
        .byte $00,$3c,$00
        .byte $00,$7e,$00
        .byte $00,$ff,$00
        .byte $01,$ff,$80
        .byte $01,$e7,$80
        .byte $01,$e7,$80
        .byte $01,$ff,$80
        .byte $00,$66,$00
        .byte $00,$66,$00
        .byte $01,$c3,$80
        .byte $00,$c3,$00
        .byte $00,$81,$00
        .byte $01,$80,$80
        .byte $03,$00,$c0
        .byte $00
