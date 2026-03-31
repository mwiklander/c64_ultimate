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

        ; Force screen memory to $0400 and character memory to $1000.
        lda #$14
        sta $d018

        ; Clear screen RAM to spaces before drawing UI/world elements.
        lda #32         ; ' '
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

         jsr clear_top_rows
         jsr draw_banner

        lda #0
        sta current_level
        lda #5
        sta lives
        jsr start_level

        ; Sprite pointers in screen memory.
        ; $2000/64 = $80 (frame A), $2040/64 = $81 (frame B).
        ; $2080/64 = $82 (cloud A), $20c0/64 = $83 (cloud B).
        lda #$80
        sta $07f8
        lda #$82
        sta $07f9
        lda #$83
        sta $07fa

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
        and #%11111000
        sta $d010

        ; Keep sprite in front of character graphics.
        lda $d01b
        and #%11111110
        sta $d01b

        ; Enable sprite 0.
        lda $d015
        ora #%00000111
        sta $d015

        ; Clouds are white, double width, and double height.
        lda #$01
        sta $d028
        sta $d029
        lda $d01d
        ora #%00000110
        sta $d01d
        lda $d017
        ora #%00000110
        sta $d017

        jsr init_clouds
        jsr init_sid

        ; Re-enable IRQ so KERNAL keyboard scan/GETIN works.
        cli

main_loop:
        jsr wait_frame

        inc frame_delay
        lda frame_delay
        and #%00000011
        bne main_loop

        jsr check_star_cheat
        jsr update_clouds
        jsr update_audio

        lda game_state
        beq state_running
        cmp #1
        beq state_falling
        cmp #2
        beq state_game_over
        cmp #3
        beq state_level_complete
        cmp #4
        beq state_final_won
        jmp main_loop

state_game_over:
        jsr end_prompt_flow
        jmp main_loop

state_level_complete:
        jsr animate_win
        inc win_timer
        lda win_timer
        cmp #70
        bcs level_complete_advance
        jmp update_sprite

level_complete_advance:
        lda #0
        sta win_timer
        inc current_level
        jsr clear_center_message
        jsr start_level
        jmp update_sprite

state_final_won:
        jsr animate_final_win
        jsr end_prompt_flow
        jmp update_sprite

state_running:
        jsr handle_input
        jsr update_jump
        jsr check_win_target
        lda game_state
        cmp #3
        beq update_sprite
        cmp #4
        beq update_sprite
        jsr check_platform_support
        jmp update_sprite

state_falling:
        lda y_pos
        clc
        adc #3
        bcc fall_store
        lda #255
fall_store:
        sta y_pos
        jsr feet_support
        bcc still_falling

        jsr settle_after_fall
        lda #0
        sta game_state
        jmp update_sprite

still_falling:
        lda y_pos
        cmp #245
        bcs fell_off_screen
        jmp update_sprite

fell_off_screen:
        lda lives
        beq out_of_lives
        dec lives
        jsr draw_lives_hud
        jsr sfx_life_lost
        lda lives
        beq out_of_lives
        jsr clear_center_message
        jsr start_level
        jmp main_loop

out_of_lives:
        jsr sfx_game_over
        lda #2
        sta game_state
        lda #0
        sta end_timer
        sta prompt_shown
        sta end_wait_release

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
        jsr poll_controls

        lda #0
        sta dir_pressed

        lda left_down
        beq check_right
        jsr key_left
        lda #1
        sta dir_pressed
        lda #1
        sta jump_air_dir
        jmp check_jump

check_right:
        lda right_down
        beq check_jump
        jsr key_right
        lda #1
        sta dir_pressed
        lda #2
        sta jump_air_dir

check_jump:
        lda space_down
        beq maybe_air_continue
        lda jump_phase
        bne maybe_air_continue
        lda #1
        sta jump_phase
        jsr sfx_jump
        lda dir_pressed
        bne done_input
        ; If this frame misses X/Z while SPACE starts jump, inherit facing.
        lda direction
        beq jump_face_right
        lda #1
        sta jump_air_dir
        jmp done_input

jump_face_right:
        lda #2
        sta jump_air_dir
        jmp done_input

maybe_air_continue:
        lda jump_phase
        beq done_input
        lda dir_pressed
        bne done_input
        lda jump_air_dir
        beq done_input
        cmp #1
        beq air_left
        jsr key_right
        jmp done_input

air_left:
        jsr key_left

done_input:
        lda #$ff
        sta $dc00
        rts

key_left:
        lda x_pos
        cmp #68
        bcc try_scroll_left
        jsr blocked_left
        bcs left_blocked
        lda x_pos
        sec
        sbc #2
        jmp store_left

try_scroll_left:
        lda scroll_col
        beq hard_left
        dec scroll_col
        jsr draw_world
        jsr blocked_left
        bcc left_ok_after_scroll
        inc scroll_col
        jsr draw_world
        rts

left_ok_after_scroll:
        lda x_pos
        jmp store_left

hard_left:
        lda x_pos
        beq store_left
        jsr blocked_left
        bcs left_blocked
        lda x_pos
        sec
        sbc #2
store_left:
        sta x_pos
        lda #1
        sta direction
        rts

left_blocked:
        rts

key_right:
        lda x_pos
        cmp #208
        bcs try_scroll_right
        jsr blocked_right
        bcs right_blocked
        lda x_pos
        clc
        adc #2
        jmp store_right

try_scroll_right:
        lda scroll_col
        cmp max_scroll
        bcs hard_right
        inc scroll_col
        jsr draw_world
        jsr blocked_right
        bcc right_ok_after_scroll
        dec scroll_col
        jsr draw_world
        rts

right_ok_after_scroll:
        lda x_pos
        jmp store_right

hard_right:
        lda x_pos
        cmp #232
        bcs store_right
        jsr blocked_right
        bcs right_blocked
        lda x_pos
        clc
        adc #2
store_right:
        sta x_pos
        lda #0
        sta direction
        rts

right_blocked:
        rts

blocked_left:
        lda x_pos
        clc
        adc #2
        pha
        lda y_pos
        clc
        adc #6
        tay
        pla
        jsr is_solid_at
        bcs blocked_yes

        lda x_pos
        clc
        adc #2
        pha
        lda y_pos
        clc
        adc #18
        tay
        pla
        jsr is_solid_at
        bcs blocked_yes
        clc
        rts

blocked_right:
        lda x_pos
        clc
        adc #21
        pha
        lda y_pos
        clc
        adc #6
        tay
        pla
        jsr is_solid_at
        bcs blocked_yes

        lda x_pos
        clc
        adc #21
        pha
        lda y_pos
        clc
        adc #18
        tay
        pla
        jsr is_solid_at
        bcs blocked_yes
        clc
        rts

blocked_yes:
        sec
        rts

poll_controls:
        ; Z = PA1/PB4, X = PA2/PB7, SPACE = PA7/PB4.
        lda #0
        sta left_down
        sta right_down
        sta space_down

        lda #$fd
        sta $dc00
        lda $dc01
        and #%00010000
        bne z_done
        lda #1
        sta left_down
z_done:

        lda #$fb
        sta $dc00
        lda $dc01
        and #%10000000
        bne x_done
        lda #1
        sta right_down
x_done:

        lda #$7f
        sta $dc00
        lda $dc01
        and #%00010000
        bne space_done
        lda #1
        sta space_down
space_done:

        lda #$ff
        sta $dc00
        rts

check_star_cheat:
        ; '*' key matrix check without consuming KERNAL key buffer.
        lda #$bf
        sta $dc00
        lda $dc01
        and #%00000010
        bne no_star_cheat
        lda #9
        sta lives
        jsr draw_lives_hud
no_star_cheat:
        lda #$ff
        sta $dc00
        rts

init_clouds:
        lda $d012
        sta rng_state
        jsr random_delay
        sta cloud1_delay
        jsr random_delay
        sta cloud2_delay
        lda #0
        sta cloud1_x
        sta cloud2_x
        sta cloud1_tick
        sta cloud2_tick
        lda #90
        sta cloud1_y
        lda #112
        sta cloud2_y
        lda #255
        sta $d003
        sta $d005
        rts

update_clouds:
        jsr update_cloud1
        jsr update_cloud2
        rts

update_cloud1:
        lda cloud1_delay
        beq cloud1_active
        dec cloud1_delay
        beq cloud1_launch
        lda #255
        sta $d003
        rts

cloud1_launch:
        jsr random_cloud_y
        sta cloud1_y
        lda #0
        sta cloud1_x

cloud1_active:
        inc cloud1_tick
        lda cloud1_tick
        and #%00000001
        bne cloud1_draw_current

        lda cloud1_x
        clc
        adc #1
        sta cloud1_x
        cmp #250
        bcc cloud1_draw
        lda #0
        sta cloud1_x
        jsr random_delay
        sta cloud1_delay
        lda #255
        sta $d003
        rts

cloud1_draw_current:
        lda cloud1_x
        sta $d002
        lda cloud1_y
        sta $d003
        rts

cloud1_draw:
        sta $d002
        lda cloud1_y
        sta $d003
        rts

update_cloud2:
        lda cloud2_delay
        beq cloud2_active
        dec cloud2_delay
        beq cloud2_launch
        lda #255
        sta $d005
        rts

cloud2_launch:
        jsr random_cloud_y
        sta cloud2_y
        lda #0
        sta cloud2_x

cloud2_active:
        inc cloud2_tick
        lda cloud2_tick
        and #%00000011
        bne cloud2_draw_current

        lda cloud2_x
        clc
        adc #1
        sta cloud2_x
        cmp #250
        bcc cloud2_draw
        lda #0
        sta cloud2_x
        jsr random_delay
        sta cloud2_delay
        lda #255
        sta $d005
        rts

cloud2_draw_current:
        lda cloud2_x
        sta $d004
        lda cloud2_y
        sta $d005
        rts

cloud2_draw:
        sta $d004
        lda cloud2_y
        sta $d005
        rts

random_cloud_y:
        jsr next_random
        and #%00111111
        clc
        adc #50
        rts

random_delay:
        jsr next_random
        and #%01111111
        sta rand_tmp
        jsr next_random
        and #%00111111
        clc
        adc rand_tmp
        clc
        adc #20
        rts

next_random:
        lda rng_state
        bne rng_step
        lda #$a5
rng_step:
        asl
        bcc rng_done
        eor #$1d
rng_done:
        sta rng_state
        rts

init_sid:
        lda #0
        sta $d404
        sta $d40b
        sta $d412
        lda #$0f
        sta $d418
        lda #0
        sta sound_timer
        rts

update_audio:
        lda sound_timer
        beq audio_done
        dec sound_timer
        bne audio_done
        lda $d404
        and #%11111110
        sta $d404
audio_done:
        rts

sfx_jump:
        lda #0
        sta $d404
        lda #$80
        sta $d400
        lda #$12
        sta $d401
        lda #$12
        sta $d405
        lda #$08
        sta $d406
        lda #%00100001
        sta $d404
        lda #3
        sta sound_timer
        rts

sfx_life_lost:
        lda #0
        sta $d404
        lda #$c0
        sta $d400
        lda #$06
        sta $d401
        lda #$28
        sta $d405
        lda #$09
        sta $d406
        lda #%01000001
        sta $d404
        lda #8
        sta sound_timer
        rts

sfx_game_over:
        lda #0
        sta $d404
        lda #$30
        sta $d400
        lda #$03
        sta $d401
        lda #$49
        sta $d405
        lda #$0a
        sta $d406
        lda #%01000001
        sta $d404
        lda #16
        sta sound_timer
        rts

sfx_level_clear:
        lda #0
        sta $d404
        lda #$40
        sta $d400
        lda #$18
        sta $d401
        lda #$24
        sta $d405
        lda #$0a
        sta $d406
        lda #%00100001
        sta $d404
        lda #8
        sta sound_timer
        rts

sfx_final_win:
        lda #0
        sta $d404
        lda #$a0
        sta $d400
        lda #$22
        sta $d401
        lda #$36
        sta $d405
        lda #$0b
        sta $d406
        lda #%00100001
        sta $d404
        lda #20
        sta sound_timer
        rts

update_jump:
        lda jump_phase
        beq jump_done
        tax
        lda ground_y
        sec
        sbc jump_table-1,x
        sta y_pos

        ; Head collision while rising: force descent.
        cpx #7
        bcs skip_head_check
        lda x_pos
        clc
        adc #6
        pha
        lda y_pos
        clc
        adc #2
        tay
        pla
        jsr is_solid_at
        bcs force_descent

        lda x_pos
        clc
        adc #18
        pha
        lda y_pos
        clc
        adc #2
        tay
        pla
        jsr is_solid_at
        bcc skip_head_check

force_descent:
        lda #8
        sta jump_phase

skip_head_check:
        inc jump_phase
        lda jump_phase
        cmp #13
        bcc jump_done
        lda #0
        sta jump_phase
        sta jump_air_dir
        lda ground_y
        sta y_pos
jump_done:
        rts

check_platform_support:
        lda jump_phase
        beq check_ground_support

        ; During descent, allow landing on any solid tile layer.
        cmp #8
        bcc support_ok
        jsr feet_support
        bcc support_ok
        lda #0
        sta jump_phase
        jsr settle_after_fall
        jmp support_ok

check_ground_support:
        jsr feet_support
        bcs support_ok
start_fall:
        lda #1
        sta game_state

support_ok:
        rts

feet_support:
        ; Check both feet so edge cases do not drop through immediately.
        lda x_pos
        clc
        adc #6
        pha
        lda y_pos
        clc
        adc #21
        tay
        pla
        jsr is_solid_at
        bcs feet_hit

        lda x_pos
        clc
        adc #18
        pha
        lda y_pos
        clc
        adc #21
        tay
        pla
        jsr is_solid_at
        rts

feet_hit:
        sec
        rts

settle_after_fall:
        ; Back up until feet are no longer inside a solid tile, then step down
        ; one pixel to stand exactly on the surface.
settle_up_loop:
        jsr feet_support
        bcc settle_down_one
        dec y_pos
        jmp settle_up_loop

settle_down_one:
        inc y_pos
        lda y_pos
        sta ground_y
        rts

align_to_hit_row:
        lda hit_row
        asl
        asl
        asl
        clc
        adc #51         ; Screen text area starts around raster Y=51
        sec
        sbc #20
        sta y_pos
        lda y_pos
        sta ground_y
        rts

is_solid_at:
        jsr get_tile_at
        bcc not_solid
        sta hit_tile
        cmp #1
        beq solid_now
        cmp #2
        beq solid_now
        cmp #3
        beq solid_now
not_solid:
        clc
        rts

solid_now:
        sec
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

draw_lives_hud:
        ldx #0
lives_label_loop:
        lda lives_label_text,x
        beq lives_digit
        sta $0401,x
        lda #$01
        sta $d801,x
        inx
        bne lives_label_loop

lives_digit:
        lda lives
        clc
        adc #48
        sta $0408
        lda #$07
        sta $d808
        rts

draw_you_won:
        ldx #0
you_won_loop:
        lda you_won_text,x
        beq you_won_done
        sta $05ec,x
        lda #$05        ; Green text
        sta $d9ec,x
        inx
        bne you_won_loop
you_won_done:
        rts

check_win_target:
        lda x_pos
        clc
        adc #12
        cmp #24
        bcc no_win
        sec
        sbc #24
        lsr
        lsr
        lsr
        clc
        adc scroll_col
        sta flag_col

        jsr has_flag_at_col
        bcs win_hit

        lda flag_col
        beq check_right_col
        dec flag_col
        jsr has_flag_at_col
        bcs win_hit
        inc flag_col

check_right_col:
        inc flag_col
        jsr has_flag_at_col
        bcc no_win

win_hit:
        lda y_pos
        sta win_base_y
        lda #0
        sta win_tick

        lda current_level
        cmp #4
        bcs final_win

        lda #3
        sta game_state
        jsr sfx_level_clear
        jsr draw_level_complete
        rts

final_win:
        lda #4
        sta game_state
        jsr sfx_final_win
        lda #0
        sta end_timer
        sta prompt_shown
        sta end_wait_release
        jsr draw_you_won
no_win:
        rts

has_flag_at_col:
        lda flag_col
        cmp level_width
        bcs no_flag
        sta world_col
        ldx #0
flag_row_loop:
        txa
        jsr get_tile_by_row
        cmp #4
        beq yes_flag
        inx
        cpx level_height
        bcc flag_row_loop
no_flag:
        clc
        rts
yes_flag:
        sec
        rts

animate_win:
        inc win_tick

        ; Small bounce.
        lda win_tick
        and #%00000111
        cmp #4
        bcc win_up
        lda win_base_y
        sta y_pos
        jmp win_color

win_up:
        lda win_base_y
        sec
        sbc #2
        sta y_pos

win_color:
        lda win_tick
        and #%00000011
        bne color_1
        lda #$01        ; white
        sta $d027
        rts

color_1:
        cmp #1
        bne color_2
        lda #$07        ; yellow
        sta $d027
        rts

color_2:
        cmp #2
        bne color_3
        lda #$0a        ; light red
        sta $d027
        rts

color_3:
        lda #$03        ; cyan
        sta $d027
        rts

animate_final_win:
        jsr animate_win
        lda win_tick
        and #%00000111
        bne no_border_flash
        lda $d020
        clc
        adc #1
        and #$0f
        sta $d020
no_border_flash:
        rts

draw_level_complete:
        ldx #0
        lda current_level
        beq draw_lvl1
        cmp #1
        beq draw_lvl2
        cmp #2
        beq draw_lvl3
        cmp #3
        beq draw_lvl4
        jmp draw_lvl4

draw_lvl2:
lvl2_loop:
        lda level2_complete_text,x
        beq level_complete_done
        sta $05e6,x
        lda #$07
        sta $d9e6,x
        inx
        bne lvl2_loop

draw_lvl3:
lvl3_loop:
        lda level3_complete_text,x
        beq level_complete_done
        sta $05e6,x
        lda #$07
        sta $d9e6,x
        inx
        bne lvl3_loop

draw_lvl4:
lvl4_loop:
        lda level4_complete_text,x
        beq level_complete_done
        sta $05e6,x
        lda #$07
        sta $d9e6,x
        inx
        bne lvl4_loop

draw_lvl1:
lvl1_loop:
        lda level1_complete_text,x
        beq level_complete_done
        sta $05e6,x
        lda #$07
        sta $d9e6,x
        inx
        bne lvl1_loop

level_complete_done:
        rts

clear_center_message:
        ldx #0
clear_center_loop:
        lda #32
        sta $05e0,x
        lda #$01
        sta $d9e0,x
        inx
        cpx #32
        bne clear_center_loop
        rts

draw_restart_prompt:
        ldx #0
restart_prompt_loop:
        lda restart_prompt_text,x
        beq restart_prompt_done
        sta $05e8,x
        lda #$01
        sta $d9e8,x
        inx
        bne restart_prompt_loop
restart_prompt_done:
        rts

end_prompt_flow:
        inc end_timer
        lda end_timer
        cmp #13
        bcc end_prompt_done

        lda prompt_shown
        bne check_restart_release
        jsr draw_restart_prompt
        lda #1
        sta prompt_shown
        sta end_wait_release
        rts

check_restart_release:
        lda end_wait_release
        beq check_restart_key
        jsr $ff9f       ; SCNKEY
        jsr $ffe4       ; GETIN
        bne end_prompt_done
        lda #0
        sta end_wait_release
        rts

check_restart_key:
        jsr $ff9f       ; SCNKEY
        jsr $ffe4       ; GETIN
        beq end_prompt_done
        cmp #42         ; '*'
        bne restart_default_lives
        lda #9
        sta lives
        jsr draw_lives_hud
        jsr restart_game
        rts

restart_default_lives:
        lda #5
        sta lives
        jsr draw_lives_hud
        jsr restart_game
        rts

end_prompt_done:
        rts

restart_game:
        jsr clear_center_message
        lda #0
        sta current_level
        sta end_timer
        sta prompt_shown
        sta end_wait_release
        jsr start_level
        rts

draw_world:
        ldx #0
draw_world_loop:
        txa
        clc
        adc scroll_col
        sta world_col

        ; Clear dynamic world rows to sky.
        lda #32
        sta $06a8,x
        sta $06d0,x
        sta $06f8,x
        sta $0720,x
        sta $0748,x
        lda #$0b
        sta $daa8,x
        sta $dad0,x
        sta $daf8,x
        sta $db20,x
        sta $db48,x

        ; Level row 0 -> screen row 17
        lda #0
        jsr get_tile_by_row
        jsr draw_tile_row17

        ; Level row 1 -> screen row 18
        lda #1
        jsr get_tile_by_row
        jsr draw_tile_row18

        ; Level row 2 -> screen row 19
        lda #2
        jsr get_tile_by_row
        jsr draw_tile_row19

        ; Level row 3 -> screen row 20
        lda #3
        jsr get_tile_by_row
        jsr draw_tile_row20

        ; Level row 4 -> screen row 21
        lda #4
        jsr get_tile_by_row
        jsr draw_tile_row21

draw_next:
        inx
        cpx #40
        bne draw_world_loop
        rts

draw_tile_row17:
        jsr decode_tile_char_color
        sta $06a8,x
        tya
        sta $daa8,x
        rts

draw_tile_row18:
        jsr decode_tile_char_color
        sta $06d0,x
        tya
        sta $dad0,x
        rts

draw_tile_row19:
        jsr decode_tile_char_color
        sta $06f8,x
        tya
        sta $daf8,x
        rts

draw_tile_row20:
        jsr decode_tile_char_color
        sta $0720,x
        tya
        sta $db20,x
        rts

draw_tile_row21:
        jsr decode_tile_char_color
        sta $0748,x
        tya
        sta $db48,x
        rts

decode_tile_char_color:
        ; Tile ids: 0 sky, 1 ground, 2 stone, 3 grass/top, 4 flag
        cmp #1
        beq tile_ground
        cmp #2
        beq tile_stone
        cmp #3
        beq tile_grass
        cmp #4
        beq tile_flag
        lda #32
        ldy #$0b
        rts

tile_ground:
        lda #66
        ldy #$08
        rts

tile_stone:
        lda #81
        ldy #$0c
        rts

tile_grass:
        lda #102
        ldy #$05
        rts

tile_flag:
        lda #47
        ldy #$07
        rts

get_tile_at:
        sta sample_x
        sty sample_y

        lda sample_x
        cmp #24
        bcc no_tile
        sec
        sbc #24
        lsr
        lsr
        lsr
        clc
        adc scroll_col
        sta world_col
        cmp level_width
        bcs no_tile

        lda sample_y
        sec
        sbc #51
        bcc no_tile
        lsr
        lsr
        lsr
        sta hit_row
        sec
        sbc #17
        bcc no_tile
        cmp level_height
        bcs no_tile

        jsr get_tile_by_row
        sec
        rts

no_tile:
        lda #0
        clc
        rts

get_tile_by_row:
        ; A = level row index (0..level_height-1), returns tile id in A for current world_col.
        jsr set_level_row_ptr
        ldy world_col
        lda ($fb),y
        rts

set_level_row_ptr:
        ; A = row index. Selects row pointer from current level register table.
        sta row_index
        lda current_level
        asl
        asl
        clc
        adc current_level
        clc
        adc row_index
        tay
        lda level_row_ptr_lo,y
        sta $fb
        lda level_row_ptr_hi,y
        sta $fc
        rts

start_level:
        lda #0
        sta scroll_col
        lda #112
        sta x_pos
        lda #96
        sta y_pos
        lda #1
        sta game_state
        lda #0
        sta jump_phase
        sta jump_air_dir
        sta win_tick
        lda #140
        sta ground_y

        ; Ensure player sprite is visible when a new level starts.
        lda $d015
        ora #%00000001
        sta $d015

        lda current_level
        tay
        lda level_width_table,y
        sta level_width
        lda level_height_table,y
        sta level_height
        lda level_max_scroll_table,y
        sta max_scroll

        jsr clear_top_rows
        jsr draw_banner
        jsr draw_world
        jsr draw_lives_hud
        rts

clear_top_rows:
        ldx #0
clear_top_loop:
        lda #32
        sta $0400,x
        sta $0428,x
        lda #$01
        sta $d800,x
        sta $d828,x
        inx
        cpx #40
        bne clear_top_loop
        rts

draw_banner:
        ldx #0
draw_banner_loop:
        lda banner,x
        beq draw_banner_done
        sta $0404,x
        lda #$01
        sta $d804,x
        inx
        bne draw_banner_loop
draw_banner_done:
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
        .byte 96

direction:
        .byte 0          ; 0 = right, 1 = left

game_state:
        .byte 1          ; 0=running, 1=falling, 2=game over, 3=level complete, 4=final won

anim_tick:
        .byte 0

frame_delay:
        .byte 0

scroll_col:
        .byte 0

jump_phase:
        .byte 0

left_down:
        .byte 0

right_down:
        .byte 0

space_down:
        .byte 0

dir_pressed:
        .byte 0

jump_air_dir:
        .byte 0          ; 0=none, 1=left, 2=right

ground_y:
        .byte 140

lives:
        .byte 5

cloud1_x:
        .byte 0

cloud1_y:
        .byte 64

cloud1_delay:
        .byte 0

cloud1_tick:
        .byte 0

cloud2_x:
        .byte 0

cloud2_y:
        .byte 88

cloud2_delay:
        .byte 0

cloud2_tick:
        .byte 0

rand_tmp:
        .byte 0

sound_timer:
        .byte 0

rng_state:
        .byte $5a

win_tick:
        .byte 0

win_base_y:
        .byte 140

flag_col:
        .byte 0

banner:
        ; Screen codes to avoid PETSCII/charset ambiguity.
        .byte 32,3,54,52,32,19,16,18,9,20,5,32,4,5,13,15
        .byte 58,32,18,5,20,18,15,32,18,21,14,14,5,18,32
        .byte 0

game_over_text:
        ; Screen codes avoid PETSCII/charset ambiguity.
        .byte 32,7,1,13,5,32,15,22,5,18,33,32
        .byte 0

you_won_text:
        .byte 32,25,15,21,32,23,15,14,33,32
        .byte 0

restart_prompt_text:
        .byte 16,18,5,19,19,32,1,32,11,5,25,32,20,15,32,20,18,25,32,1,7,1,9,14
        .byte 0

lives_label_text:
        .byte 12,9,22,5,19,32,32
        .byte 0

level1_complete_text:
        .byte 32,12,5,22,5,12,32,49,32,3,15,13,16,12,5,20,5,32
        .byte 0

level2_complete_text:
        .byte 32,12,5,22,5,12,32,50,32,3,15,13,16,12,5,20,5,32
        .byte 0

level3_complete_text:
        .byte 32,12,5,22,5,12,32,51,32,3,15,13,16,12,5,20,5,32
        .byte 0

level4_complete_text:
        .byte 32,12,5,22,5,12,32,52,32,3,15,13,16,12,5,20,5,32
        .byte 0

jump_table:
        ; 12-frame jump arc as Y offsets from current ground/platform.
        .byte 0,4,9,15,20,24,20,15,9,4,1,0

sample_x:
        .byte 0

sample_y:
        .byte 0

hit_row:
        .byte 0

hit_tile:
        .byte 0

world_col:
        .byte 0

row_index:
        .byte 0

row_ptr_lo:
        .byte 0

row_ptr_hi:
        .byte 0

level_width:
        .byte 80

level_height:
        .byte 5

max_scroll:
        .byte 40

current_level:
        .byte 0

win_timer:
        .byte 0

end_timer:
        .byte 0

prompt_shown:
        .byte 0

end_wait_release:
        .byte 0

level_width_table:
        .byte 96,96,96,96,96

level_height_table:
        .byte 5,5,5,5,5

level_max_scroll_table:
        .byte 56,56,56,56,56

level_row_ptr_lo:
        .byte <level1_row0,<level1_row1,<level1_row2,<level1_row3,<level1_row4
        .byte <level2_row0,<level2_row1,<level2_row2,<level2_row3,<level2_row4
        .byte <level3_row0,<level3_row1,<level3_row2,<level3_row3,<level3_row4
        .byte <level4_row0,<level4_row1,<level4_row2,<level4_row3,<level4_row4
        .byte <level5_row0,<level5_row1,<level5_row2,<level5_row3,<level5_row4

level_row_ptr_hi:
        .byte >level1_row0,>level1_row1,>level1_row2,>level1_row3,>level1_row4
        .byte >level2_row0,>level2_row1,>level2_row2,>level2_row3,>level2_row4
        .byte >level3_row0,>level3_row1,>level3_row2,>level3_row3,>level3_row4
        .byte >level4_row0,>level4_row1,>level4_row2,>level4_row3,>level4_row4
        .byte >level5_row0,>level5_row1,>level5_row2,>level5_row3,>level5_row4

; Level 1 (96x5), tile ids: 0 sky, 1 ground, 2 stone, 3 grass, 4 flag
level1_row0:
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,3,3,3,3,0,0
        .byte 0,0,3,3,0,0,3,0,0,0,0,0,0,0,0,0

level1_row1:
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,2,2,2,2,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,3,3,3,3,3,3,3,3
        .byte 3,3,3,3,4,3,3,3,0,0,0,0,0,0,0,0

level1_row2:
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,2,2,2,2,0,0,0,0
        .byte 0,0,0,0,3,3,3,3,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,3,3,3,0,0,0,3,3,3
        .byte 0,0,0,0,3,3,3,3,3,3,3,3,3,3,3,3
        .byte 3,3,3,3,0,0,0,0,0,0,0,0,0,0,0,0

level1_row3:
        .byte 3,3,3,3,3,3,3,3,3,3,3,3,0,0,3,3
        .byte 3,3,3,3,3,3,3,3,3,3,3,3,0,3,3,3
        .byte 3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3
        .byte 3,3,3,3,0,0,0,0,0,0,0,0,0,3,3,3
        .byte 3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3
        .byte 3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3

level1_row4:
        .byte 1,1,1,1,1,1,1,1,1,1,1,1,0,0,1,1
        .byte 1,1,1,1,1,1,1,1,1,1,1,1,0,1,1,1
        .byte 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
        .byte 1,1,1,1,0,0,0,0,0,0,0,0,0,1,1,1
        .byte 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
        .byte 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1

; Level 2 adds stepped higher ground and a right-side flag.
level2_row0:
        .byte 0,0,0,3,3,0,0,0,0,0,0,0,3,3,3,0
        .byte 0,0,0,0,0,3,3,3,0,0,0,0,0,0,3,3
        .byte 3,0,0,0,0,0,0,3,3,3,0,0,0,0,0,0
        .byte 3,3,3,0,0,0,0,0,0,3,3,3,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

level2_row1:
        .byte 0,0,0,0,0,0,2,0,0,0,0,0,0,0,0,0
        .byte 2,0,0,0,0,0,0,0,2,0,0,0,0,0,0,0
        .byte 0,0,0,2,0,0,0,0,0,0,2,0,0,0,0,0
        .byte 0,0,0,0,0,2,0,0,0,0,0,0,0,0,2,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

level2_row2:
        .byte 0,2,0,0,0,0,0,0,0,2,0,0,0,0,0,0
        .byte 0,0,0,0,2,0,0,0,0,0,0,0,2,0,0,0
        .byte 0,0,0,0,0,0,0,2,0,0,0,0,0,0,0,0
        .byte 0,2,0,0,0,0,0,0,0,0,2,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,4,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

level2_row3:
        .byte 3,3,3,3,3,3,3,0,0,3,3,3,3,3,3,3
        .byte 3,0,0,3,3,3,3,3,3,3,0,0,3,3,3,3
        .byte 3,3,3,3,3,0,0,3,3,3,3,3,3,3,0,0
        .byte 3,3,3,3,3,3,3,3,0,0,3,3,3,3,3,3
        .byte 3,3,3,3,3,3,3,3,3,3,3,4,3,3,3,3
        .byte 3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3

level2_row4:
        .byte 1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1
        .byte 1,0,0,1,1,1,1,1,1,1,0,0,1,1,1,1
        .byte 1,1,1,1,1,0,0,1,1,1,1,1,1,1,0,0
        .byte 1,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1
        .byte 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
        .byte 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1

; Level 3: rolling hill feel using raised grass shelves.
level3_row0:
        .byte 0,0,0,0,0,0,0,0,3,3,3,0,0,0,0,0
        .byte 0,0,0,3,3,3,0,0,0,0,0,0,0,3,3,3
        .byte 0,0,0,0,0,0,0,0,3,3,3,0,0,0,0,0
        .byte 0,0,0,3,3,3,0,0,0,0,0,0,0,3,3,3
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

level3_row1:
        .byte 0,0,2,0,0,0,0,0,0,0,2,0,0,0,0,0
        .byte 0,0,0,0,0,0,2,0,0,0,0,0,0,0,0,0
        .byte 2,0,0,0,0,0,0,0,0,0,2,0,0,0,0,0
        .byte 0,0,0,0,0,0,2,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

level3_row2:
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,4,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

level3_row3:
        .byte 3,3,3,3,3,0,0,3,3,3,3,3,0,0,3,3
        .byte 3,3,3,3,0,0,3,3,3,3,3,0,0,3,3,3
        .byte 3,3,3,0,0,3,3,3,3,3,0,0,3,3,3,3
        .byte 3,3,0,0,3,3,3,3,3,0,0,3,3,3,3,3
        .byte 3,0,0,3,3,3,3,3,0,0,3,3,3,3,3,3
        .byte 3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3

level3_row4:
        .byte 1,1,1,1,1,0,0,1,1,1,1,1,0,0,1,1
        .byte 1,1,1,1,0,0,1,1,1,1,1,0,0,1,1,1
        .byte 1,1,1,0,0,1,1,1,1,1,0,0,1,1,1,1
        .byte 1,1,0,0,1,1,1,1,1,0,0,1,1,1,1,1
        .byte 1,0,0,1,1,1,1,1,0,0,1,1,1,1,1,1
        .byte 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1

; Level 4: more vertical terrain and stepping stones.
level4_row0:
        .byte 0,0,0,3,3,3,0,0,0,0,0,3,3,3,0,0
        .byte 0,0,3,3,3,0,0,0,0,3,3,3,0,0,0,0
        .byte 3,3,3,0,0,0,0,3,3,3,0,0,0,0,3,3
        .byte 3,0,0,0,0,3,3,3,0,0,0,0,3,3,3,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

level4_row1:
        .byte 0,0,0,0,0,2,0,0,0,0,0,0,0,2,0,0
        .byte 0,0,0,0,2,0,0,0,0,0,0,0,2,0,0,0
        .byte 0,0,0,2,0,0,0,0,0,0,2,0,0,0,0,0
        .byte 0,0,2,0,0,0,0,0,0,2,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

level4_row2:
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,4,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

level4_row3:
        .byte 3,3,3,3,0,0,3,3,3,3,0,0,3,3,3,3
        .byte 0,0,3,3,3,3,0,0,3,3,3,3,0,0,3,3
        .byte 3,3,0,0,3,3,3,3,0,0,3,3,3,3,0,0
        .byte 3,3,3,3,0,0,3,3,3,3,0,0,3,3,3,3
        .byte 0,0,3,3,3,3,0,0,3,3,3,3,0,0,3,3
        .byte 3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3

level4_row4:
        .byte 1,1,1,1,0,0,1,1,1,1,0,0,1,1,1,1
        .byte 0,0,1,1,1,1,0,0,1,1,1,1,0,0,1,1
        .byte 1,1,0,0,1,1,1,1,0,0,1,1,1,1,0,0
        .byte 1,1,1,1,0,0,1,1,1,1,0,0,1,1,1,1
        .byte 0,0,1,1,1,1,0,0,1,1,1,1,0,0,1,1
        .byte 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1

; Level 5: final course with broad hills and a reachable final flag.
level5_row0:
        .byte 0,0,3,3,3,0,0,0,0,3,3,3,0,0,0,0
        .byte 3,3,3,0,0,0,0,3,3,3,0,0,0,0,3,3
        .byte 3,0,0,0,0,3,3,3,0,0,0,0,3,3,3,0
        .byte 0,0,0,0,3,3,3,0,0,0,0,3,3,3,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

level5_row1:
        .byte 0,0,0,0,2,0,0,0,0,0,2,0,0,0,0,0
        .byte 0,2,0,0,0,0,0,2,0,0,0,0,0,2,0,0
        .byte 0,0,0,0,2,0,0,0,0,0,2,0,0,0,0,0
        .byte 0,2,0,0,0,0,0,2,0,0,0,0,0,2,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

level5_row2:
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,4,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

level5_row3:
        .byte 3,3,3,0,0,3,3,3,0,0,3,3,3,0,0,3
        .byte 3,3,0,0,3,3,3,0,0,3,3,3,0,0,3,3
        .byte 3,0,0,3,3,3,0,0,3,3,3,0,0,3,3,3
        .byte 0,0,3,3,3,0,0,3,3,3,0,0,3,3,3,0
        .byte 0,3,3,3,0,0,3,3,3,0,0,3,3,3,0,0
        .byte 3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3

level5_row4:
        .byte 1,1,1,0,0,1,1,1,0,0,1,1,1,0,0,1
        .byte 1,1,0,0,1,1,1,0,0,1,1,1,0,0,1,1
        .byte 1,0,0,1,1,1,0,0,1,1,1,0,0,1,1,1
        .byte 0,0,1,1,1,0,0,1,1,1,0,0,1,1,1,0
        .byte 0,1,1,1,0,0,1,1,1,0,0,1,1,1,0,0
        .byte 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1

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

*=$2080
cloud_sprite_a:
        ; 24x21 single-color cloud shape A: rounded summer cloud.
        .byte $00,$00,$00
        .byte $00,$00,$00
        .byte $00,$70,$00
        .byte $01,$fc,$00
        .byte $07,$ff,$00
        .byte $1f,$ff,$c0
        .byte $3f,$ff,$f0
        .byte $7f,$ff,$fc
        .byte $ff,$ff,$fe
        .byte $ff,$ff,$ff
        .byte $ff,$ff,$ff
        .byte $7f,$ff,$ff
        .byte $3f,$ff,$fe
        .byte $1f,$ff,$fc
        .byte $0f,$ff,$f0
        .byte $07,$ff,$c0
        .byte $03,$ff,$80
        .byte $00,$ff,$00
        .byte $00,$38,$00
        .byte $00,$00,$00
        .byte $00,$00,$00
        .byte $00

*=$20c0
cloud_sprite_b:
        ; 24x21 single-color cloud shape B: broader and flatter variant.
        .byte $00,$00,$00
        .byte $00,$00,$00
        .byte $00,$1c,$00
        .byte $00,$7f,$00
        .byte $01,$ff,$c0
        .byte $07,$ff,$f0
        .byte $1f,$ff,$fc
        .byte $3f,$ff,$fe
        .byte $7f,$ff,$ff
        .byte $ff,$ff,$ff
        .byte $ff,$ff,$ff
        .byte $ff,$ff,$fe
        .byte $7f,$ff,$fc
        .byte $3f,$ff,$f8
        .byte $1f,$ff,$f0
        .byte $0f,$ff,$e0
        .byte $07,$ff,$80
        .byte $01,$ff,$00
        .byte $00,$7c,$00
        .byte $00,$00,$00
        .byte $00,$00,$00
        .byte $00
