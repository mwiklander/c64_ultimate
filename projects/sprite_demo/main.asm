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

        lda #$10
        sta d016_base
        lda #0
        sta fine_scroll
        jsr apply_fine_scroll
        lda d016_base
        sta $d016

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

        lda #0
        sta current_level
        lda #5
        sta lives
        lda #0
        sta player_form
        sta key_collected
        sta level_requires_key

        ; Sprite pointers in screen memory.
        ; $3c00/64 = $f0 (frame A), $3c40/64 = $f1 (frame B).
        ; $3d00/64 = $f4 (bird frame A), $3d40/64 = $f5 (bird frame B).
        ; $3c80/64 = $f2 (cloud A), $3cc0/64 = $f3 (cloud B).
        lda #$f0
        sta $07f8
        lda #$f4
        sta $07f9
        lda #$f2
        sta $07fa
        lda #$f3
        sta $07fb

        ; Multicolor sprite setup.
        lda $d01c
        ora #%00000011
        sta $d01c
        lda #$0a
        sta $d025       ; Shared multicolor 0 (light red)
        lda #$07
        sta $d026       ; Shared multicolor 1 (yellow)
        lda #$01
        sta $d027       ; Per-sprite color (white)

        ; Keep X MSB clear so X stays in 0-255 range.
        lda $d010
        and #%11110000
        sta $d010

        ; Keep sprite in front of character graphics.
        lda $d01b
        and #%11111110
        sta $d01b

        ; Enable sprite 0, clouds, and bird.
        lda $d015
        ora #%00001111
        sta $d015

        ; Clouds are white, double width, and double height.
        lda #$01
        sta $d028
        sta $d029
        sta $d02a
        sta $d02b
        lda $d01d
        ora #%00001100
        sta $d01d
        lda $d017
        ora #%00001100
        sta $d017

        jsr init_sid
        jsr restart_game
        jsr init_raster_split

        ; Re-enable IRQ so KERNAL keyboard scan/GETIN works.
        cli

main_loop:
        jsr wait_frame

        ; Frame timing marker: red while updates run.
        lda #$02
        sta $d020

        jsr check_star_cheat

        lda game_state
        cmp #2
        bcs skip_action_poll
        jsr poll_action_keys
        jsr check_level_hotkey
        bcc action_key_continue
        jmp frame_done
action_key_continue:
        jsr check_toggle_debug_rows
        jsr check_easter_chicken
        jsr check_quit_to_title
        bcc continue_after_quit_check
        jmp frame_done
continue_after_quit_check:
skip_action_poll:
        jsr update_ride_mode

        lda ride_mode
        beq ride_not_active
        jmp update_sprite
ride_not_active:

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
        jmp frame_done

state_game_over:
        jsr end_prompt_flow
        jmp frame_done

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
        jsr update_level_timer
        lda game_state
        beq running_continue
        jmp update_sprite
running_continue:
        jsr handle_input
        jsr update_jump
        jsr check_collectibles
        jsr check_win_target
        lda game_state
        cmp #3
        bne running_check_final
        jmp update_sprite
running_check_final:
        cmp #4
        bne running_check_support
        jmp update_sprite
running_check_support:
        jsr check_platform_support
        jmp update_sprite

state_falling:
        jsr update_level_timer
        lda game_state
        cmp #1
        beq falling_continue
        jmp frame_done
falling_continue:
        lda y_pos
        clc
        adc #3
        bcc fall_store
        lda #255
fall_store:
        sta y_pos
        jsr check_collectibles
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
        jsr lose_life_or_game_over
        jmp frame_done

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
        jmp frame_done

lose_life_or_game_over:
        lda lives
        beq out_of_lives
        dec lives
        jsr draw_lives_hud
        jsr sfx_life_lost
        lda lives
        beq out_of_lives
        jsr clear_center_message
        jsr start_level
        rts

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
        jsr set_player_frame_b
        jmp frame_done
frame_a:
        jsr set_player_frame_a

frame_done:
        ; Run cloud/bird/audio updates after movement/scroll so coarse-column shifts
        ; are completed earlier in the frame and avoid boundary wrap flicker.
        jsr update_clouds
        jsr update_bird
        jsr update_aux_sprite_msb
        jsr update_audio
        jsr refresh_uniform_row_idle

        ; Frame timing marker: green when logic/draw is done.
        lda #$05
        sta $d020
        jmp main_loop

handle_input:
        jsr poll_controls
        jsr update_run_speed

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
        lda jump_phase
        and #%00000001
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

update_run_speed:
        lda jump_phase
        beq run_speed_on_ground
        lda #1
        sta move_step
        rts

run_speed_on_ground:
        lda left_down
        beq run_speed_check_right
        lda right_down
        bne run_speed_reset
        inc hold_left
        lda #0
        sta hold_right
        lda hold_left
        cmp #4
        bcc run_speed_walk
        lda #2
        sta move_step
        rts

run_speed_check_right:
        lda right_down
        beq run_speed_reset
        inc hold_right
        lda #0
        sta hold_left
        lda hold_right
        cmp #4
        bcc run_speed_walk
        lda #2
        sta move_step
        rts

run_speed_walk:
        lda #1
        sta move_step
        rts

run_speed_reset:
        lda #0
        sta hold_left
        sta hold_right
        lda #1
        sta move_step
        rts

init_raster_split:
        ; Disable CIA IRQ sources; use VIC raster IRQ only.
        lda #$7f
        sta $dc0d
        sta $dd0d
        lda $dc0d
        lda $dd0d

        lda #<irq_split
        sta $0314
        lda #>irq_split
        sta $0315

        lda #0
        sta irq_phase
        lda #IRQ_LINE_HUD
        sta $d012
        lda $d011
        and #%01111111
        sta $d011
        lda #$01
        sta $d01a
        lda #$01
        sta $d019
        rts

irq_split:
        pha
        txa
        pha
        tya
        pha

        lda irq_phase
        beq irq_hud_phase
        cmp #1
        beq irq_world_phase
        jmp irq_shift_phase

irq_world_phase:
        lda world_d016
        sta $d016

        lda pending_coarse_shift
        beq irq_world_to_hud
        lda #IRQ_LINE_SHIFT
        sta $d012
        lda #2
        sta irq_phase
        jmp irq_done

irq_world_to_hud:
        lda #IRQ_LINE_HUD
        sta $d012
        lda #0
        sta irq_phase
        jmp irq_done

irq_hud_phase:
        lda d016_base
        sta $d016
        lda shift_line_dirty
        beq irq_hud_line_done
        jsr draw_shift_line_hud
        lda #0
        sta shift_line_dirty
irq_hud_line_done:
        lda #IRQ_LINE_WORLD
        sta $d012
        lda #1
        sta irq_phase
        jmp irq_done

irq_shift_phase:
        lda pending_coarse_shift
        beq irq_shift_to_hud
        cmp #1
        beq irq_shift_right

irq_shift_left:
        lda #0
        sta fine_scroll
        jsr apply_fine_scroll
        lda #0
        sta early_world_commit_done
        lda d016_base
        sta $d016
        dec scroll_col
        jsr draw_world_shift_right
        lda #0
        sta pending_coarse_shift
        jmp irq_shift_done

irq_shift_right:
        lda #7
        sta fine_scroll
        jsr apply_fine_scroll
        lda #0
        sta early_world_commit_done
        lda d016_base
        sta $d016
        inc scroll_col
        jsr draw_world_shift_left
        lda #0
        sta pending_coarse_shift

irq_shift_done:
        lda $d011
        and #%10000000
        beq irq_shift_line_low
        lda #1
        sta shift_marker_line_hi
        jmp irq_shift_store_line
irq_shift_line_low:
        lda #0
        sta shift_marker_line_hi
irq_shift_store_line:
        lda $d012
        sta shift_marker_line
        lda #1
        sta shift_line_dirty

        ; The coarse copy and fine scroll change commit together here.
        lda world_d016
        sta $d016

        lda $d011
        and #%10000000
        bne irq_shift_to_hud
        lda $d012
        cmp #IRQ_LINE_HUD
        bcc irq_shift_to_hud
        cmp #IRQ_LINE_WORLD
        bcc irq_shift_to_world

irq_shift_to_hud:
        lda #IRQ_LINE_HUD
        sta $d012
        lda #0
        sta irq_phase
        jmp irq_done

irq_shift_to_world:
        ; If the coarse shift finishes after the HUD split has already passed this
        ; frame, restore HUD scroll immediately so the top rows do not keep the
        ; world fine-scroll setting until the next frame.
        lda d016_base
        sta $d016
        lda #IRQ_LINE_WORLD
        sta $d012
        lda #1
        sta irq_phase
        jmp irq_done

irq_done:
        lda #$01
        sta $d019
        pla
        tay
        pla
        tax
        pla
        jmp $ea31

apply_fine_scroll:
        lda d016_base
        ora fine_scroll
        sta world_d016
apply_fine_done:
        rts

draw_shift_line_hud:
        ; Show row-2 coarse-shift start at HUD cols 28-32 and completion at cols 33-37.
        lda #50
        sta $041c
        lda #$07
        sta $d81c
        lda #58
        sta $041d
        lda #$07
        sta $d81d

        lda row2_marker_line
        ldx row2_marker_line_hi
        jsr format_line_digits
        lda shift_line_hundreds
        clc
        adc #48
        sta $041e
        lda shift_line_tens
        clc
        adc #48
        sta $041f
        lda shift_line_ones
        clc
        adc #48
        sta $0420

        lda #$07
        sta $d81e
        sta $d81f
        sta $d820

        lda #12
        sta $0421
        lda #$07
        sta $d821
        lda #58
        sta $0422
        lda #$07
        sta $d822

        lda shift_marker_line
        ldx shift_marker_line_hi
        jsr format_line_digits

        lda shift_line_hundreds
        clc
        adc #48
        sta $0423
        lda shift_line_tens
        clc
        adc #48
        sta $0424
        lda shift_line_ones
        clc
        adc #48
        sta $0425

        lda #$07
        sta $d823
        sta $d824
        sta $d825
        rts

maybe_commit_world_scroll:
        lda early_world_commit_done
        bne maybe_commit_world_scroll_done
        lda $d011
        and #%10000000
        bne maybe_commit_world_scroll_done
        lda $d012
        cmp #IRQ_LINE_SHIFT
        bcs maybe_commit_world_scroll_done
        cmp #IRQ_LINE_WORLD
        bcc maybe_commit_world_scroll_done
        lda world_d016
        sta $d016
        lda #1
        sta early_world_commit_done
maybe_commit_world_scroll_done:
        rts

format_line_digits:
        cpx #0
        beq format_line_value_ready
        ldy #2
        sty shift_line_hundreds
        clc
        adc #56
        cmp #100
        bcc format_line_tens_prepare
        sec
        sbc #100
        inc shift_line_hundreds
        jmp format_line_tens_prepare

format_line_value_ready:
        ldy #0
format_line_hundreds_loop:
        cmp #100
        bcc format_line_hundreds_done
        sec
        sbc #100
        iny
        bne format_line_hundreds_loop
format_line_hundreds_done:
        sty shift_line_hundreds

format_line_tens_prepare:
        ldy #0
format_line_tens_loop:
        cmp #10
        bcc format_line_tens_done
        sec
        sbc #10
        iny
        bne format_line_tens_loop
format_line_tens_done:
        sty shift_line_tens
        sta shift_line_ones
        rts

camera_scroll_right:
        lda move_step
        sta scroll_steps
cam_scroll_right_loop:
        jsr camera_scroll_right_1px
        dec scroll_steps
        bne cam_scroll_right_loop
        jsr apply_fine_scroll
        rts

camera_scroll_right_1px:
        lda pending_coarse_shift
        bne cam_right_done
        lda scroll_col
        cmp max_scroll
        bcc cam_right_continue
        lda fine_scroll
        beq cam_right_done
cam_right_continue:
        lda fine_scroll
        bne cam_right_dec
        lda #1
        sta pending_coarse_shift
        jmp cam_right_done
cam_right_dec:
        dec fine_scroll
cam_right_done:
        rts

camera_scroll_left:
        lda move_step
        sta scroll_steps
cam_scroll_left_loop:
        jsr camera_scroll_left_1px
        dec scroll_steps
        bne cam_scroll_left_loop
        jsr apply_fine_scroll
        rts

camera_scroll_left_1px:
        lda pending_coarse_shift
        bne cam_left_done
        lda scroll_col
        bne cam_left_continue
        lda fine_scroll
        beq cam_left_done
cam_left_continue:
        lda fine_scroll
        cmp #7
        bne cam_left_inc
        lda #2
        sta pending_coarse_shift
        jmp cam_left_done
cam_left_inc:
        inc fine_scroll
cam_left_done:
        rts

process_pending_coarse_shift:
        rts

key_left:
        lda x_pos
        cmp #68
        bcc try_scroll_left
        jsr blocked_left
        bcs left_blocked
        lda x_pos
        sec
        sbc move_step
        jmp store_left

try_scroll_left:
        lda scroll_col
        bne scroll_left_try
        lda fine_scroll
        beq hard_left
scroll_left_try:
        jsr blocked_left
        bcs left_blocked
        jsr camera_scroll_left
        lda x_pos
        jmp store_left

blocked_left_after_scroll:
        dec scroll_col
        jsr blocked_left
        inc scroll_col
        rts

hard_left:
        lda x_pos
        beq store_left
        jsr blocked_left
        bcs left_blocked
        lda x_pos
        sec
        sbc move_step
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
        adc move_step
        jmp store_right

try_scroll_right:
        lda scroll_col
        cmp max_scroll
        bcc scroll_right_try
        lda fine_scroll
        beq hard_right
scroll_right_try:
        jsr blocked_right
        bcs right_blocked
        jsr camera_scroll_right
        lda x_pos
        jmp store_right

blocked_right_after_scroll:
        inc scroll_col
        jsr blocked_right
        dec scroll_col
        rts

hard_right:
        lda x_pos
        cmp #232
        bcs store_right
        jsr blocked_right
        bcs right_blocked
        lda x_pos
        clc
        adc move_step
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

        sei
        lda #$fd
        sta $dc00
        lda $dc01
        tax
        lda #$ff
        sta $dc00
        cli
        txa
        and #%00010000
        bne z_done
        lda #1
        sta left_down
z_done:

        sei
        lda #$fb
        sta $dc00
        lda $dc01
        tax
        lda #$ff
        sta $dc00
        cli
        txa
        and #%10000000
        bne x_done
        lda #1
        sta right_down
x_done:

        sei
        lda #$7f
        sta $dc00
        lda $dc01
        tax
        lda #$ff
        sta $dc00
        cli
        txa
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
        sei
        lda #$bf
        sta $dc00
        lda $dc01
        tax
        lda #$ff
        sta $dc00
        cli
        txa
        and #%00000010
        bne no_star_cheat
        lda #9
        sta lives
        jsr draw_lives_hud
no_star_cheat:
        lda #$ff
        sta $dc00
        rts

poll_action_keys:
        ; Direct CIA keyboard matrix scan for action keys.
        ; C64 matrix: Row $7F=1,2,Q  Row $FD=3,4,E  Row $FB=5,R,D,C  Row $F7=B
        lda #0
        sta action_key

        ; Row $7F: '1' (bit0), '2' (bit3), 'Q' (bit6)
        sei
        lda #$7f
        sta $dc00
        lda $dc01
        tax
        lda #$ff
        sta $dc00
        cli
        txa
        and #%01000000
        bne not_q_key
        lda #81
        sta action_key
        jmp action_key_done
not_q_key:
        txa
        and #%00000001
        bne not_1_key
        lda #49
        sta action_key
        jmp action_key_done
not_1_key:
        txa
        and #%00001000
        bne not_2_key
        lda #50
        sta action_key
        jmp action_key_done
not_2_key:

        ; Row $FD: '3' (bit0), '4' (bit3), 'E' (bit6)
        sei
        lda #$fd
        sta $dc00
        lda $dc01
        tax
        lda #$ff
        sta $dc00
        cli
        txa
        and #%00000001
        bne not_3_key
        lda #51
        sta action_key
        jmp action_key_done
not_3_key:
        txa
        and #%00001000
        bne not_4_key
        lda #52
        sta action_key
        jmp action_key_done
not_4_key:
        txa
        and #%01000000
        bne not_e_key
        lda #69
        sta action_key
        jmp action_key_done
not_e_key:

        ; Row $FB: '5' (bit0), 'R' (bit1), 'D' (bit2), 'C' (bit4)
        sei
        lda #$fb
        sta $dc00
        lda $dc01
        tax
        lda #$ff
        sta $dc00
        cli
        txa
        and #%00000001
        bne not_5_key
        lda #53
        sta action_key
        jmp action_key_done
not_5_key:
        txa
        and #%00000010
        bne not_r_key
        lda #82
        sta action_key
        jmp action_key_done
not_r_key:
        txa
        and #%00000100
        bne not_d_key
        lda #68
        sta action_key
        jmp action_key_done
not_d_key:
        txa
        and #%00010000
        bne not_c_key
        lda #67
        sta action_key
        jmp action_key_done

not_c_key:
        ; Row $F7: 'B' (bit4)
        sei
        lda #$f7
        sta $dc00
        lda $dc01
        tax
        lda #$ff
        sta $dc00
        cli
        txa
        and #%00010000
        bne action_key_done
        lda #66
        sta action_key

action_key_done:
        lda #$ff
        sta $dc00
        rts

check_level_hotkey:
        ; Number keys 1..LEVEL_COUNT jump directly to that level.
        lda action_key
        sec
        sbc #49
        bcc no_level_hotkey
        cmp #LEVEL_COUNT
        bcs no_level_hotkey
        sta current_level
        lda #0
        sta ride_mode
        sta game_state
        sta jump_phase
        sta jump_air_dir
        jsr clear_center_message
        jsr clear_current_level_collectible_state
        jsr start_level
        lda #0
        sta action_key
        sec
        rts
no_level_hotkey:
        clc
        rts

check_toggle_debug_rows:
        lda action_key
        cmp #68         ; 'D'
        beq toggle_debug_now
        cmp #100        ; 'd'
        bne toggle_debug_done
toggle_debug_now:
        lda debug_rows_enabled
        eor #1
        sta debug_rows_enabled
        lda #0
        sta action_key
        jsr clear_top_rows
        jsr draw_lives_hud
        jsr draw_timer_hud
        jsr draw_world
toggle_debug_done:
        rts

check_easter_chicken:
        lda action_key
        cmp #69         ; 'E'
        beq set_chicken_mode
        cmp #101        ; 'e'
        bne no_chicken_mode
set_chicken_mode:
        lda #1
        sta player_form
        lda #0
        sta action_key
no_chicken_mode:
        rts

check_quit_to_title:
        lda action_key
        cmp #81         ; 'Q'
        beq do_quit_to_title
        cmp #113        ; 'q'
        bne no_quit_to_title
do_quit_to_title:
        lda #0
        sta ride_mode
        sta action_key
        jsr restart_game
        sec
        rts
no_quit_to_title:
        clc
        rts

set_player_frame_a:
        lda player_form
        beq player_a_normal
        lda #$f6
        sta $07f8
        rts
player_a_normal:
        lda #$f0
        sta $07f8
        rts

set_player_frame_b:
        lda player_form
        beq player_b_normal
        lda #$f7
        sta $07f8
        rts
player_b_normal:
        lda #$f1
        sta $07f8
        rts

update_aux_sprite_msb:
        ; Update sprite X MSB bits for bird (bit1), cloud1 (bit2), cloud2 (bit3), preserving other bits.
        lda $d010
        and #%11110001
        sta d010_mask_tmp

        lda #0
        ldy bird_x_msb
        beq msb_bird_done
        ora #%00000010
msb_bird_done:
        ldy cloud1_x_msb
        beq msb_cloud1_done
        ora #%00000100
msb_cloud1_done:
        ldy cloud2_x_msb
        beq msb_cloud2_done
        ora #%00001000
msb_cloud2_done:
        ora d010_mask_tmp
        sta $d010
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
        sta cloud1_x_msb
        sta cloud2_x_msb
        sta cloud1_tick
        sta cloud2_tick
        lda #90
        sta cloud1_y
        lda #112
        sta cloud2_y
        lda #255
        sta $d005
        sta $d007
        rts

update_clouds:
        jsr update_cloud1
        jsr update_cloud2
        rts

init_bird:
        jsr random_bird_delay
        sta bird_delay
        lda #80
        sta bird_x
        lda #1
        sta bird_x_msb
        lda #84
        sta bird_y
        lda #0
        sta bird_tick
        sta bird_chirp_cooldown
        lda #255
        sta $d003
        rts

update_bird:
        lda bird_chirp_cooldown
        beq bird_cooldown_done
        dec bird_chirp_cooldown
bird_cooldown_done:

        lda bird_delay
        beq bird_active
        dec bird_delay
        beq bird_launch
        lda #255
        sta $d003
        rts

bird_launch:
        jsr random_bird_y
        sta bird_y
        lda #80
        sta bird_x
        lda #1
        sta bird_x_msb
        lda #0
        sta bird_tick

bird_active:
        inc bird_tick
        lda bird_tick
        and #%00000001
        bne bird_draw_current

        lda bird_x_msb
        beq bird_move_low
        lda bird_x
        bne bird_move_high_dec
        lda #$ff
        sta bird_x
        lda #0
        sta bird_x_msb
        jmp bird_draw
bird_move_high_dec:
        dec bird_x
        jmp bird_draw

bird_move_low:
        lda bird_x
        sec
        sbc #1
        sta bird_x
        cmp #2
        bcs bird_draw

        jsr random_bird_delay
        sta bird_delay
        lda #80
        sta bird_x
        lda #1
        sta bird_x_msb
        lda #255
        sta $d003
        rts

bird_draw_current:
        lda bird_x
        sta $d002
        jsr set_bird_frame
        jsr set_bird_y
        jsr maybe_bird_chirp
        rts

bird_draw:
        sta $d002
        jsr set_bird_frame
        jsr set_bird_y
        jsr maybe_bird_chirp
        rts

set_bird_frame:
        lda bird_tick
        and #%00000100
        beq bird_frame_a
        lda #$f5
        sta $07f9
        rts

bird_frame_a:
        lda #$f4
        sta $07f9
        rts

set_bird_y:
        lda bird_tick
        and #%00000010
        beq bird_y_base
        lda bird_y
        sec
        sbc #1
        sta $d003
        rts

bird_y_base:
        lda bird_y
        sta $d003
        rts

maybe_bird_chirp:
        lda bird_chirp_cooldown
        bne bird_chirp_done
        lda sound_timer
        bne bird_chirp_done
        lda bird_x_msb
        bne bird_chirp_done

        lda bird_x
        sec
        sbc x_pos
        bcs bird_diff_ready
        eor #$ff
        clc
        adc #1
bird_diff_ready:
        cmp #10
        bcs bird_chirp_done

        jsr sfx_bird
        lda #40
        sta bird_chirp_cooldown
bird_chirp_done:
        rts

update_ride_mode:
        lda ride_mode
        bne ride_follow

        ; Not riding: allow attach by action keys when near host sprites.
        lda action_key
        cmp #67         ; 'C'
        beq try_attach_cloud
        cmp #99         ; 'c'
        beq try_attach_cloud
        cmp #66         ; 'B'
        beq try_attach_bird
        cmp #98         ; 'b'
        beq try_attach_bird
        rts

try_attach_cloud:
        jsr near_cloud1
        bcs attach_cloud1
        jsr near_cloud2
        bcs attach_cloud2
        rts

attach_cloud1:
        lda #1
        sta ride_mode
        jmp ride_attach_common

attach_cloud2:
        lda #2
        sta ride_mode
        jmp ride_attach_common

try_attach_bird:
        jsr near_bird
        bcc ride_attach_done
        lda #3
        sta ride_mode

ride_attach_common:
        lda #0
        sta jump_phase
        sta jump_air_dir
        sta game_state
        sta action_key
ride_attach_done:
        rts

ride_follow:
        lda action_key
        cmp #82         ; 'R'
        beq ride_release
        cmp #114        ; 'r'
        beq ride_release

        lda ride_mode
        cmp #1
        beq follow_cloud1
        cmp #2
        beq follow_cloud2
        jmp follow_bird

ride_release:
        lda #0
        sta ride_mode
        sta action_key
        lda #1
        sta game_state
        lda #0
        sta jump_phase
        sta jump_air_dir
        rts

follow_cloud1:
        lda cloud1_delay
        bne ride_release
        lda cloud1_x_msb
        beq follow_cloud1_low
        lda #232
        sta x_pos
        jmp follow_cloud1_y
follow_cloud1_low:
        lda cloud1_x
        clc
        adc #8
        sta x_pos
follow_cloud1_y:
        lda cloud1_y
        sec
        sbc #10
        sta y_pos
        lda #0
        sta direction
        jmp ride_scroll_right

follow_cloud2:
        lda cloud2_delay
        bne ride_release
        lda cloud2_x_msb
        beq follow_cloud2_low
        lda #232
        sta x_pos
        jmp follow_cloud2_y
follow_cloud2_low:
        lda cloud2_x
        clc
        adc #8
        sta x_pos
follow_cloud2_y:
        lda cloud2_y
        sec
        sbc #10
        sta y_pos
        lda #0
        sta direction
        jmp ride_scroll_right

follow_bird:
        lda bird_delay
        bne ride_release
        lda bird_x_msb
        beq follow_bird_low
        lda #232
        sta x_pos
        jmp follow_bird_y
follow_bird_low:
        lda bird_x
        clc
        adc #6
        sta x_pos
follow_bird_y:
        lda bird_y
        sec
        sbc #8
        sta y_pos
        lda #1
        sta direction
        jmp ride_scroll_left

ride_scroll_right:
        lda x_pos
        cmp #208
        bcc ride_done
        lda scroll_col
        cmp max_scroll
        bcs ride_done

        ; Match background scroll to host cadence while riding.
        lda ride_mode
        cmp #1
        bne check_cloud2_cadence
        lda cloud1_tick
        and #%00000001
        bne ride_done
check_cloud2_cadence:
        lda ride_mode
        cmp #2
        bne do_ride_scroll_right
        lda cloud2_tick
        and #%00000011
        bne ride_done
do_ride_scroll_right:
        jsr camera_scroll_right
        lda #208
        sta x_pos
ride_done:
        rts

ride_scroll_left:
        lda x_pos
        cmp #68
        bcs ride_done
        lda scroll_col
        beq ride_done

        ; Bird advances every other tick, so scroll left at same cadence.
        lda bird_tick
        and #%00000001
        bne ride_done
        jsr camera_scroll_left
        lda #68
        sta x_pos
        rts

near_cloud1:
        lda cloud1_delay
        bne near_cloud1_no
        lda cloud1_x_msb
        bne near_cloud1_no
        lda cloud1_x
        jsr abs_diff_x
        cmp #24
        bcs near_cloud1_no
        lda cloud1_y
        jsr abs_diff_y
        cmp #24
        bcs near_cloud1_no
        sec
        rts
near_cloud1_no:
        clc
        rts

near_cloud2:
        lda cloud2_delay
        bne near_cloud2_no
        lda cloud2_x_msb
        bne near_cloud2_no
        lda cloud2_x
        jsr abs_diff_x
        cmp #24
        bcs near_cloud2_no
        lda cloud2_y
        jsr abs_diff_y
        cmp #24
        bcs near_cloud2_no
        sec
        rts
near_cloud2_no:
        clc
        rts

near_bird:
        lda bird_delay
        bne near_bird_no
        lda bird_x_msb
        bne near_bird_no
        lda bird_x
        jsr abs_diff_x
        cmp #18
        bcs near_bird_no
        lda bird_y
        jsr abs_diff_y
        cmp #18
        bcs near_bird_no
        sec
        rts
near_bird_no:
        clc
        rts

abs_diff_x:
        sec
        sbc x_pos
        bcs abs_x_done
        eor #$ff
        clc
        adc #1
abs_x_done:
        rts

abs_diff_y:
        sec
        sbc y_pos
        bcs abs_y_done
        eor #$ff
        clc
        adc #1
abs_y_done:
        rts

update_cloud1:
        lda cloud1_delay
        beq cloud1_active
        dec cloud1_delay
        beq cloud1_launch
        lda #255
        sta $d005
        rts

cloud1_launch:
        jsr random_cloud_y
        sta cloud1_y
        lda #0
        sta cloud1_x
        sta cloud1_x_msb

cloud1_active:
        inc cloud1_tick
        lda cloud1_tick
        and #%00000001
        bne cloud1_draw_current

        lda cloud1_x
        clc
        adc #1
        sta cloud1_x
        bne cloud1_check_limit
        lda cloud1_x_msb
        eor #1
        sta cloud1_x_msb

cloud1_check_limit:
        lda cloud1_x_msb
        beq cloud1_draw_low
        lda cloud1_x
        cmp #96
        bcc cloud1_draw

        lda #0
        sta cloud1_x
        sta cloud1_x_msb
        jsr random_delay
        sta cloud1_delay
        lda #255
        sta $d005
        rts

cloud1_draw_low:
        lda cloud1_x

cloud1_draw_current:
        lda cloud1_x
        sta $d004
        lda cloud1_y
        sta $d005
        rts

cloud1_draw:
        sta $d004
        lda cloud1_y
        sta $d005
        rts

update_cloud2:
        lda cloud2_delay
        beq cloud2_active
        dec cloud2_delay
        beq cloud2_launch
        lda #255
        sta $d007
        rts

cloud2_launch:
        jsr random_cloud_y
        sta cloud2_y
        lda #0
        sta cloud2_x
        sta cloud2_x_msb

cloud2_active:
        inc cloud2_tick
        lda cloud2_tick
        and #%00000011
        bne cloud2_draw_current

        lda cloud2_x
        clc
        adc #1
        sta cloud2_x
        bne cloud2_check_limit
        lda cloud2_x_msb
        eor #1
        sta cloud2_x_msb

cloud2_check_limit:
        lda cloud2_x_msb
        beq cloud2_draw_low
        lda cloud2_x
        cmp #96
        bcc cloud2_draw

        lda #0
        sta cloud2_x
        sta cloud2_x_msb
        jsr random_delay
        sta cloud2_delay
        lda #255
        sta $d007
        rts

cloud2_draw_low:
        lda cloud2_x

cloud2_draw_current:
        lda cloud2_x
        sta $d006
        lda cloud2_y
        sta $d007
        rts

cloud2_draw:
        sta $d006
        lda cloud2_y
        sta $d007
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

random_bird_y:
        jsr next_random
        and #%00111111
        clc
        adc #70
        rts

random_bird_delay:
        jsr next_random
        and #%01111111
        clc
        adc #30
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
        lda #$00
        sta $d409
        lda #$08
        sta $d40a
        lda #$22
        sta $d40c
        lda #$88
        sta $d40d
        lda #$0f
        sta $d418
        lda #0
        sta sound_timer
        sta music_mode
        sta music_tick
        sta music_step
        rts

update_audio:
        jsr update_music
        lda sound_timer
        beq audio_done
        dec sound_timer
        bne audio_done
        lda $d404
        and #%11111110
        sta $d404
audio_done:
        rts

start_title_music:
        lda #1
        sta music_mode
        lda #0
        sta music_tick
        sta music_step
        sta $d40b
        lda #$14
        sta $d40c
        lda #$a8
        sta $d40d
        rts

start_game_music:
        lda #2
        sta music_mode
        lda #0
        sta music_tick
        sta music_step
        sta $d40b
        lda #$12
        sta $d40c
        lda #$a8
        sta $d40d
        rts

update_music:
        lda music_mode
        bne music_active
        jmp music_done
music_active:

        ldx music_step
        lda music_mode
        cmp #1
        beq music_title_mode

music_game_mode:
        lda gameplay_music_len,x
        sta rand_tmp
        inc music_tick
        lda music_tick
        cmp rand_tmp
        bcc music_done
        lda #0
        sta music_tick

        lda gameplay_music_hi,x
        beq music_game_rest
        lda gameplay_music_lo,x
        sta $d407
        lda gameplay_music_hi,x
        sta $d408
        lda #%00010001
        sta $d40b
        jmp music_advance_game

music_game_rest:
        lda #0
        sta $d40b

music_advance_game:
        inx
        cpx #GAMEPLAY_MUSIC_LEN
        bcc music_store_step
        ldx #0
        jmp music_store_step

music_title_mode:
        lda title_music_len,x
        sta rand_tmp
        inc music_tick
        lda music_tick
        cmp rand_tmp
        bcc music_done
        lda #0
        sta music_tick

        lda title_music_hi,x
        beq music_title_rest
        lda title_music_lo,x
        sta $d407
        lda title_music_hi,x
        sta $d408
        lda #%00010001
        sta $d40b
        jmp music_advance_title

music_title_rest:
        lda #0
        sta $d40b

music_advance_title:
        inx
        cpx #TITLE_MUSIC_LEN
        bcc music_store_step
        ldx #0

music_store_step:
        stx music_step

music_done:
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

sfx_bird:
        lda #0
        sta $d404
        lda #$f0
        sta $d400
        lda #$28
        sta $d401
        lda #$11
        sta $d405
        lda #$04
        sta $d406
        lda #%00100001
        sta $d404
        lda #4
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
        cpx #9
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
        lda #9
        sta jump_phase

skip_head_check:
        inc jump_phase
        lda jump_phase
        cmp #15
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

feet_support_center:
        ; Stricter support used for standing/run state to avoid edge-sticking.
        lda x_pos
        clc
        adc #12
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
        sta $04d3,x
        lda #$02        ; Red text
        sta $d8d3,x
        inx
        bne game_over_loop
game_over_done:
        rts

draw_lives_hud:
        lda #83
        sta $0401
        lda #$02
        sta $d801

        lda lives
        clc
        adc #48
        sta $0403
        lda #$07
        sta $d803
        rts

draw_timer_hud:
        lda #87
        sta $0407
        lda #$07
        sta $d807

        lda timer_seconds
        ldx #0
timer_tens_loop:
        cmp #10
        bcc timer_tens_done
        sec
        sbc #10
        inx
        bne timer_tens_loop

timer_tens_done:
        stx tens_digit
        sta ones_digit
        txa
        clc
        adc #48
        sta $0409
        lda ones_digit
        clc
        adc #48
        sta $040a
        lda #$07
        sta $d809
        sta $d80a

        lda key_collected
        beq hud_key_empty
        lda #107
        sta $040d
        lda #$07
        sta $d80d
        jmp hud_draw_hint

hud_key_empty:
        lda #32
        sta $040d
        lda #$01
        sta $d80d
hud_draw_hint:
        jsr draw_chest_hint_hud
        rts

draw_chest_hint_hud:
        ldx #0
        lda level_requires_key
        bne chest_hint_pick

chest_hint_clear_loop:
        lda #32
        sta $0411,x
        lda #$01
        sta $d811,x
        inx
        cpx #10
        bne chest_hint_clear_loop
        rts

chest_hint_pick:
        lda key_collected
        bne chest_hint_open

chest_hint_find_loop:
        lda find_key_text,x
        beq chest_hint_done
        sta $0411,x
        lda #$07
        sta $d811,x
        inx
        bne chest_hint_find_loop

chest_hint_open:
        ldx #0
chest_hint_open_loop:
        lda open_chest_text,x
        beq chest_hint_done
        sta $0411,x
        lda #$07
        sta $d811,x
        inx
        bne chest_hint_open_loop

chest_hint_done:
        rts

update_level_timer:
        inc timer_tick
        lda timer_tick
        cmp #50
        bcc timer_done
        lda #0
        sta timer_tick
        lda timer_seconds
        beq timer_expired
        dec timer_seconds
        jsr draw_timer_hud
        lda timer_seconds
        bne timer_done

timer_expired:
        jsr lose_life_or_game_over
timer_done:
        rts

check_collectibles:
        ; Probe several points on the sprite body so pickups trigger reliably.
        lda x_pos
        clc
        adc #12
        pha
        lda y_pos
        clc
        adc #12
        tay
        pla
        jsr collect_if_hit
        bcc collect_probe2
        jmp collectibles_done
collect_probe2:

        lda x_pos
        clc
        adc #6
        pha
        lda y_pos
        clc
        adc #12
        tay
        pla
        jsr collect_if_hit
        bcc collect_probe3
        jmp collectibles_done
collect_probe3:

        lda x_pos
        clc
        adc #18
        pha
        lda y_pos
        clc
        adc #12
        tay
        pla
        jsr collect_if_hit
        bcc collect_probe4
        jmp collectibles_done
collect_probe4:

        lda x_pos
        clc
        adc #12
        pha
        lda y_pos
        clc
        adc #20
        tay
        pla
        jsr collect_if_hit
        bcc collect_probe5
        jmp collectibles_done
collect_probe5:

        lda x_pos
        clc
        adc #12
        pha
        lda y_pos
        clc
        adc #6
        tay
        pla
        jsr collect_if_hit
        bcs collect_probe5_hit
        jmp collectibles_done
collect_probe5_hit:
        rts

collect_if_hit:
        jsr get_tile_at
        bcc collect_none
        cmp #5
        beq collect_pineapple_now
        cmp #6
        beq collect_heart_now
        cmp #7
        beq collect_key_now
collect_none:
        clc
        rts

collect_pineapple_now:
        jsr collect_pineapple
        sec
        rts

collect_heart_now:
        jsr collect_heart
        sec
        rts

collect_key_now:
        jsr collect_key
        sec
        rts

collect_pineapple:
        jsr clear_collectible_tile
        ; Add +10 seconds (do not set), clamp to 99.
        lda timer_seconds
        clc
        adc #10
        bcc pine_store
        lda #99
pine_store:
        cmp #100
        bcc pine_ok
        lda #99
pine_ok:
        sta timer_seconds
        jsr draw_timer_hud
        rts

collect_heart:
        jsr clear_collectible_tile
        ; Add +1 life (do not set), clamp to 9.
        lda lives
        cmp #9
        bcs heart_done
        inc lives
        jsr draw_lives_hud
heart_done:
        rts

collect_key:
        lda key_collected
        bne key_done
        jsr clear_collectible_tile
        lda #1
        sta key_collected
        jsr clear_center_message
        jsr draw_timer_hud
key_done:
        rts

clear_collectible_tile:
        lda hit_row
        sec
        sbc #7
        pha
        jsr mark_collectible_removed
        jsr draw_single_world_cell
        pla
        jsr update_uniform_row_state
        jsr refresh_scroll_skip_rows
        jsr draw_bottom_row_debug
        rts

draw_single_world_cell:
        ; Update only the changed visible world cell after collectible pickup.
        lda world_col
        sec
        sbc scroll_col
        bcc draw_single_cell_done
        cmp #40
        bcs draw_single_cell_done
        sta screen_col

        lda hit_row
        sec
        sbc #7
        tax
        lda screen_col
        tay
        lda #0
        jsr decode_tile_char_color

        sta draw_char_tmp
        sty draw_color_tmp
        lda char_row_ptr_lo,x
        sta $fb
        lda char_row_ptr_hi,x
        sta $fc
        lda draw_char_tmp
        ldy screen_col
        sta ($fb),y

        lda color_row_ptr_lo,x
        sta $fd
        lda color_row_ptr_hi,x
        sta $fe
        lda draw_color_tmp
        ldy screen_col
        sta ($fd),y

draw_single_cell_done:
collectibles_done:
        rts

draw_you_won:
        ldx #0
you_won_loop:
        lda you_won_text,x
        beq you_won_done
        sta $04d4,x
        lda #$05        ; Green text
        sta $d8d4,x
        inx
        bne you_won_loop
you_won_done:
        rts

check_win_target:
        lda level_requires_key
        beq check_win_position
        lda key_collected
        beq no_win

check_win_position:
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

        jsr has_chest_at_col
        bcs win_hit

        lda flag_col
        beq check_right_col
        dec flag_col
        jsr has_chest_at_col
        bcs win_hit
        inc flag_col

check_right_col:
        inc flag_col
        jsr has_chest_at_col
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

has_chest_at_col:
        lda flag_col
        cmp level_width
        bcs no_chest
        sta world_col
        ldx #0
flag_row_loop:
        txa
        jsr get_tile_by_row
        cmp #4
        beq yes_chest
        inx
        cpx level_height
        bcc flag_row_loop
no_chest:
        clc
        rts
yes_chest:
        sec
        rts

level_contains_key:
        ldx #0
level_key_row_loop:
        txa
        jsr set_level_row_ptr
        ldy #0
level_key_col_loop:
        lda ($fb),y
        cmp #7
        beq level_has_key_yes
        iny
        cpy level_width
        bcc level_key_col_loop
        inx
        cpx level_height
        bcc level_key_row_loop
        lda #0
        rts
level_has_key_yes:
        lda #1
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
        sta $04ce,x
        lda #$07
        sta $d8ce,x
        inx
        bne lvl2_loop

draw_lvl3:
lvl3_loop:
        lda level3_complete_text,x
        beq level_complete_done
        sta $04ce,x
        lda #$07
        sta $d8ce,x
        inx
        bne lvl3_loop

draw_lvl4:
lvl4_loop:
        lda level4_complete_text,x
        beq level_complete_done
        sta $04ce,x
        lda #$07
        sta $d8ce,x
        inx
        bne lvl4_loop

draw_lvl1:
lvl1_loop:
        lda level1_complete_text,x
        beq level_complete_done
        sta $04ce,x
        lda #$07
        sta $d8ce,x
        inx
        bne lvl1_loop

level_complete_done:
        rts

clear_center_message:
        ldx #0
clear_center_loop:
        lda #32
        sta $04c8,x
        lda #$01
        sta $d8c8,x
        inx
        cpx #32
        bne clear_center_loop
        rts

draw_restart_prompt:
        ldx #0
restart_prompt_loop:
        lda restart_prompt_text,x
        beq restart_prompt_done
        sta $04d0,x
        lda #$01
        sta $d8d0,x
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
        ; Wait for all keys released before accepting restart.
        sei
        lda #$00
        sta $dc00
        lda $dc01
        cmp #$ff
        bne end_prompt_release_wait
        lda #$ff
        sta $dc00
        cli
        lda #0
        sta end_wait_release
        rts
end_prompt_release_wait:
        lda #$ff
        sta $dc00
        cli
        jmp end_prompt_done

check_restart_key:
        ; Check if any key is pressed via CIA direct read.
        sei
        lda #$00
        sta $dc00
        lda $dc01
        cmp #$ff
        beq end_prompt_no_key
        ; Check '*' specifically: row 6 ($BF), bit 1.
        lda #$bf
        sta $dc00
        lda $dc01
        and #%00000010
        bne restart_default_lives
        lda #$ff
        sta $dc00
        cli
        lda #9
        sta lives
        jsr restart_game
        rts
end_prompt_no_key:
        lda #$ff
        sta $dc00
        cli
        jmp end_prompt_done

restart_default_lives:
        lda #$ff
        sta $dc00
        cli
        lda #5
        sta lives
        jsr restart_game
        rts

end_prompt_done:
        rts

restart_game:
        jsr clear_center_message
        jsr clear_collectible_state
        lda #0
        sta current_level
        sta end_timer
        sta prompt_shown
        sta end_wait_release
        jsr draw_title_screen
        jsr wait_title_start
        jsr start_game_music

        lda $d015
        ora #%00001111
        sta $d015
        jsr init_clouds
        jsr init_bird
        jsr start_level
        rts

draw_world:
        ldx #0
draw_world_loop:
        txa
        clc
        adc scroll_col
        sta world_col

        ; Level row 0 -> screen row 7
        lda #0
        jsr get_tile_by_row
        jsr draw_tile_row7

        ; Level row 1 -> screen row 8
        lda #1
        jsr get_tile_by_row
        jsr draw_tile_row8

        ; Level row 2 -> screen row 9
        lda #2
        jsr get_tile_by_row
        jsr draw_tile_row9

        ; Level row 3 -> screen row 10
        lda #3
        jsr get_tile_by_row
        jsr draw_tile_row10

        ; Level row 4 -> screen row 11
        lda #4
        jsr get_tile_by_row
        jsr draw_tile_row11

        ; Level row 5 -> screen row 12
        lda #5
        jsr get_tile_by_row
        jsr draw_tile_row12

        ; Level row 6 -> screen row 13
        lda #6
        jsr get_tile_by_row
        jsr draw_tile_row13

        ; Level row 7 -> screen row 14
        lda #7
        jsr get_tile_by_row
        jsr draw_tile_row14

        ; Level row 8 -> screen row 15
        lda #8
        jsr get_tile_by_row
        jsr draw_tile_row15

        ; Level row 9 -> screen row 16
        lda #9
        jsr get_tile_by_row
        jsr draw_tile_row16

        ; Level row 10 -> screen row 17
        lda #10
        jsr get_tile_by_row
        jsr draw_tile_row17

        ; Level row 11 -> screen row 18
        lda #11
        jsr get_tile_by_row
        jsr draw_tile_row18

        ; Level row 12 -> screen row 19
        lda #12
        jsr get_tile_by_row
        jsr draw_tile_row19

        ; Level row 13 -> screen row 20
        lda #13
        jsr get_tile_by_row
        jsr draw_tile_row20

        ; Level row 14 -> screen row 21
        lda #14
        jsr get_tile_by_row
        jsr draw_tile_row21

draw_next:
        inx
        cpx #40
        beq draw_world_done
        jmp draw_world_loop
draw_world_done:
        jsr scan_uniform_rows
        jsr draw_bottom_row_debug
        rts

draw_world_shift_left:
        lda #$01
        sta $d020
        lda scroll_skip_row_count
        bne draw_world_shift_left_skip
        lda level_height
        sta coarse_rows_updated
        jsr unrolled_shift_left_full
        jmp draw_world_shift_left_done
draw_world_shift_left_skip:
        lda level_height
        sec
        sbc scroll_skip_row_count
        sta coarse_rows_updated
        jsr unrolled_shift_left
draw_world_shift_left_done:
        jsr fill_right_edge_column
        jsr draw_bottom_row_debug
        lda #$05
        sta $d020
        rts

draw_world_shift_right:
        lda #$01
        sta $d020
        lda scroll_skip_row_count
        bne draw_world_shift_right_skip
        lda level_height
        sta coarse_rows_updated
        jsr unrolled_shift_right_full
        jmp draw_world_shift_right_done
draw_world_shift_right_skip:
        lda level_height
        sec
        sbc scroll_skip_row_count
        sta coarse_rows_updated
        jsr unrolled_shift_right
draw_world_shift_right_done:
        jsr fill_left_edge_column
        jsr draw_bottom_row_debug
        lda #$05
        sta $d020
        rts

shift_row_save:
        .byte 0

fill_left_edge_row0:
        lda scroll_col
        sta world_col
        lda #0
        jsr get_tile_by_row
        ldx #0
        jsr decode_tile_char_color
        sta draw_char_tmp
        sta $0518
        tya
        sta $d918
        lda draw_char_tmp
        ldx #0
        jsr update_uniform_row_after_edge
        rts

fill_right_edge_row0:
        lda scroll_col
        clc
        adc #39
        sta world_col
        lda #0
        jsr get_tile_by_row
        ldx #0
        jsr decode_tile_char_color
        sta draw_char_tmp
        sta $053f
        tya
        sta $d93f
        lda draw_char_tmp
        ldx #0
        jsr update_uniform_row_after_edge
        rts

fill_left_edge_column:
        lda scroll_col
        sta world_col
        ldx #1
fill_left_edge_row_loop:
        stx shift_row_save
        txa
        jsr get_tile_by_row
        ldx shift_row_save
        jsr decode_tile_char_color
        sta draw_char_tmp
        sty draw_color_tmp

        lda char_row_ptr_lo,x
        sta $fb
        lda char_row_ptr_hi,x
        sta $fc
        ldy #0
        lda draw_char_tmp
        sta ($fb),y

        lda color_row_ptr_lo,x
        sta $fd
        lda color_row_ptr_hi,x
        sta $fe
        lda draw_color_tmp
        sta ($fd),y

        lda draw_char_tmp
        ldx shift_row_save
        jsr update_uniform_row_after_edge

fill_left_edge_next_row:
        inx
        cpx #15
        bcc fill_left_edge_row_loop
        rts

fill_right_edge_column:
        lda scroll_col
        clc
        adc #39
        sta world_col
        ldx #1
fill_right_edge_row_loop:
        stx shift_row_save
        txa
        jsr get_tile_by_row
        ldx shift_row_save
        jsr decode_tile_char_color
        sta draw_char_tmp
        sty draw_color_tmp

        lda char_row_ptr_lo,x
        sta $fb
        lda char_row_ptr_hi,x
        sta $fc
        ldy #39
        lda draw_char_tmp
        sta ($fb),y

        lda color_row_ptr_lo,x
        sta $fd
        lda color_row_ptr_hi,x
        sta $fe
        lda draw_color_tmp
        sta ($fd),y

        lda draw_char_tmp
        ldx shift_row_save
        jsr update_uniform_row_after_edge

fill_right_edge_next_row:
        inx
        cpx #15
        bcc fill_right_edge_row_loop
        rts

draw_bottom_row_debug:
        lda debug_rows_enabled
        bne draw_bottom_row_debug_active
        jmp draw_bottom_row_debug_done

draw_bottom_row_debug_active:
        ; Show uniform-row count as "UF:nn".
        lda #21
        sta $0430
        lda #6
        sta $0431
        lda #58
        sta $0432
        lda #$0f
        sta $d830
        sta $d831
        sta $d832

        lda uniform_row_count
        cmp #10
        bcc debug_uniform_single_digit
        sec
        sbc #10
        pha
        lda #49
        sta $0433
        lda #$0f
        sta $d833
        pla
        clc
        adc #48
        sta $0434
        lda #$0f
        sta $d834
        jmp debug_uniform_count_done

debug_uniform_single_digit:
        pha
        lda #32
        sta $0433
        lda #$0f
        sta $d833
        pla
        clc
        adc #48
        sta $0434
        lda #$0f
        sta $d834

debug_uniform_count_done:

        ; Show currently skippable rows as "SK:nn".
        lda #19
        sta $0440
        lda #11
        sta $0441
        lda #58
        sta $0442
        lda #$0f
        sta $d840
        sta $d841
        sta $d842

        lda scroll_skip_row_count
        cmp #10
        bcc debug_skip_single_digit
        sec
        sbc #10
        pha
        lda #49
        sta $0443
        lda #$0f
        sta $d843
        pla
        clc
        adc #48
        sta $0444
        lda #$0f
        sta $d844
        jmp debug_skip_count_done

debug_skip_single_digit:
        pha
        lda #32
        sta $0443
        lda #$0f
        sta $d843
        pla
        clc
        adc #48
        sta $0444
        lda #$0f
        sta $d844

debug_skip_count_done:

        ; Show rows updated in the last coarse scroll as "RU:nn".
        lda #18
        sta $0438
        lda #21
        sta $0439
        lda #58
        sta $043a
        lda #$0f
        sta $d838
        sta $d839
        sta $d83a

        lda coarse_rows_updated
        cmp #10
        bcc debug_rows_single_digit
        sec
        sbc #10
        pha
        lda #49
        sta $043b
        lda #$0f
        sta $d83b
        pla
        clc
        adc #48
        sta $043c
        lda #$0f
        sta $d83c
        jmp debug_rows_count_done

debug_rows_single_digit:
        pha
        lda #32
        sta $043b
        lda #$0f
        sta $d83b
        pla
        clc
        adc #48
        sta $043c
        lda #$0f
        sta $d83c

debug_rows_count_done:
draw_bottom_row_debug_done:
        rts

draw_tile_row7:
        jsr decode_tile_char_color
        sta $0518,x
        tya
        sta $d918,x
        rts

draw_tile_row8:
        jsr decode_tile_char_color
        sta $0540,x
        tya
        sta $d940,x
        rts

draw_tile_row9:
        jsr decode_tile_char_color
        sta $0568,x
        tya
        sta $d968,x
        rts

draw_tile_row10:
        jsr decode_tile_char_color
        sta $0590,x
        tya
        sta $d990,x
        rts

draw_tile_row11:
        jsr decode_tile_char_color
        sta $05b8,x
        tya
        sta $d9b8,x
        rts

draw_tile_row12:
        jsr decode_tile_char_color
        sta $05e0,x
        tya
        sta $d9e0,x
        rts

draw_tile_row13:
        jsr decode_tile_char_color
        sta $0608,x
        tya
        sta $da08,x
        rts

draw_tile_row14:
        jsr decode_tile_char_color
        sta $0630,x
        tya
        sta $da30,x
        rts

draw_tile_row15:
        jsr decode_tile_char_color
        sta $0658,x
        tya
        sta $da58,x
        rts

draw_tile_row16:
        jsr decode_tile_char_color
        sta $0680,x
        tya
        sta $da80,x
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
        ; Tile ids: 0 sky, 1 ground, 2 stone, 3 grass/top, 4 chest, 5 pineapple, 6 heart, 7 key
        cmp #1
        beq tile_ground
        cmp #2
        beq tile_stone
        cmp #3
        beq tile_grass
        cmp #4
        beq tile_chest
        cmp #5
        beq tile_pineapple
        cmp #6
        beq tile_heart
        cmp #7
        beq tile_key
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

tile_chest:
        lda #67
        ldy #$09
        rts

tile_pineapple:
        lda #87         ; Symbol-like glyph (fruit-ish in C64 graphics set)
        ldy #$07        ; yellow
        rts

tile_heart:
        lda #83         ; Heart suit glyph in C64 graphics set
        ldy #$02        ; red
        rts

tile_key:
        lda #107
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
        sec
        sbc fine_scroll
        bcc no_tile
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
        sbc #7
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
        cmp #5
        bcc get_tile_by_row_done
        cmp #8
        bcs get_tile_by_row_done
        sta level_tile_tmp
        txa
        pha
        lda row_index
        jsr is_collectible_removed
        pla
        tax
        bcc get_tile_by_row_active
        lda #0
        rts
get_tile_by_row_active:
        lda level_tile_tmp
get_tile_by_row_done:
        rts

set_level_row_ptr:
        ; A = row index. Selects row pointer from current level register table.
        sta row_index
        lda current_level
        asl
        asl
        asl
        asl
        sec
        sbc current_level
        clc
        adc row_index
        tay
        lda level_row_ptr_lo,y
        sta $fb
        lda level_row_ptr_hi,y
        sta $fc
        rts

set_collectible_row_ptr:
        ; A = row index. Select runtime collectible state row for current level.
        sta row_index
        lda current_level
        asl
        asl
        asl
        asl
        sec
        sbc current_level
        clc
        adc row_index
        sta collectible_row_index

        lda collectible_row_index
        sta collectible_offset_lo
        lda #0
        sta collectible_offset_hi

        asl collectible_offset_lo
        rol collectible_offset_hi
        asl collectible_offset_lo
        rol collectible_offset_hi

        lda collectible_offset_lo
        sta collectible_mul_lo
        lda collectible_offset_hi
        sta collectible_mul_hi

        asl collectible_offset_lo
        rol collectible_offset_hi

        clc
        lda collectible_offset_lo
        adc collectible_mul_lo
        sta collectible_offset_lo
        lda collectible_offset_hi
        adc collectible_mul_hi
        sta collectible_offset_hi

        clc
        lda #<level_collectible_state
        adc collectible_offset_lo
        sta $fd
        lda #>level_collectible_state
        adc collectible_offset_hi
        sta $fe
        rts

is_collectible_removed:
        jsr set_collectible_row_ptr
        lda world_col
        lsr
        lsr
        lsr
        tay
        lda world_col
        and #%00000111
        tax
        lda collectible_bit_masks,x
        and ($fd),y
        beq collectible_not_removed
        sec
        rts
collectible_not_removed:
        clc
        rts

mark_collectible_removed:
        jsr set_collectible_row_ptr
        lda world_col
        lsr
        lsr
        lsr
        tay
        lda world_col
        and #%00000111
        tax
        lda collectible_bit_masks,x
        ora ($fd),y
        sta ($fd),y
        rts

clear_collectible_state:
        lda #0
        ldx #0
clear_collectible_state_loop:
        sta level_collectible_state,x
        sta level_collectible_state+$100,x
        sta level_collectible_state+$200,x
        sta level_collectible_state+$300,x
        inx
        bne clear_collectible_state_loop
        rts

scan_uniform_rows:
        lda #0
        sta uniform_row_count
        sta scroll_skip_row_count
        sta uniform_idle_row
        ldx #0
scan_uniform_rows_clear_loop:
        lda #$ff
        sta uniform_row_tiles,x
        inx
        cpx #LEVEL_ROWS
        bcc scan_uniform_rows_clear_loop

        ldx #0
scan_uniform_rows_loop:
        txa
        jsr update_uniform_row_state
        inx
        cpx level_height
        bcc scan_uniform_rows_loop
        jsr refresh_scroll_skip_rows
        rts

update_uniform_row_state:
        sta row_index
        txa
        pha
        tya
        pha
        ldx row_index
        lda char_row_ptr_lo,x
        sta $fb
        lda char_row_ptr_hi,x
        sta $fc
        lda color_row_ptr_lo,x
        sta $fd
        lda color_row_ptr_hi,x
        sta $fe

        ldy #0
        lda ($fb),y
        sta uniform_candidate_tile
        lda ($fd),y
        sta uniform_candidate_color
        iny
update_uniform_row_loop:
        cpy #40
        bcs uniform_row_store_same
        lda ($fb),y
        cmp uniform_candidate_tile
        bne uniform_row_store_mixed
        lda ($fd),y
        cmp uniform_candidate_color
        bne uniform_row_store_mixed
        iny
        bne update_uniform_row_loop

uniform_row_store_same:
        lda uniform_candidate_tile
        ldx row_index
        jsr store_uniform_row_state
        jmp uniform_row_restore

uniform_row_store_mixed:
        lda #$ff
        ldx row_index
        jsr store_uniform_row_state

uniform_row_restore:
        pla
        tay
        pla
        tax
        rts

store_uniform_row_state:
        cmp uniform_row_tiles,x
        beq store_uniform_row_done
        ldy uniform_row_tiles,x
        sta uniform_row_tiles,x
        cpy #$ff
        bne store_uniform_old_uniform
        cmp #$ff
        beq store_uniform_row_done
        inc uniform_row_count
        jmp store_uniform_row_done

store_uniform_old_uniform:
        cmp #$ff
        bne store_uniform_row_done
        dec uniform_row_count

store_uniform_row_done:
        lda uniform_row_count
        sta scroll_skip_row_count
        rts

update_uniform_row_after_edge:
        sta uniform_candidate_tile
        lda uniform_row_tiles,x
        cmp #$ff
        beq update_uniform_row_after_edge_done
        cmp uniform_candidate_tile
        beq update_uniform_row_after_edge_done
        lda #$ff
        jsr store_uniform_row_state
update_uniform_row_after_edge_done:
        rts

refresh_scroll_skip_rows:
        lda uniform_row_count
        sta scroll_skip_row_count
        rts

refresh_uniform_row_idle:
        lda pending_coarse_shift
        bne refresh_uniform_row_idle_done
        lda level_height
        beq refresh_uniform_row_idle_done

        lda uniform_idle_row
        cmp level_height
        bcc refresh_uniform_row_idle_check
        lda #0
        sta uniform_idle_row

refresh_uniform_row_idle_check:
        ldx uniform_idle_row
        lda uniform_row_tiles,x
        cmp #$ff
        bne refresh_uniform_row_idle_advance
        txa
        jsr update_uniform_row_state

refresh_uniform_row_idle_advance:
        inc uniform_idle_row
        lda uniform_idle_row
        cmp level_height
        bcc refresh_uniform_row_idle_done
        lda #0
        sta uniform_idle_row

refresh_uniform_row_idle_done:
        rts

clear_current_level_collectible_state:
        lda #0
        sta collectible_clear_row
clear_current_level_row_loop:
        lda collectible_clear_row
        jsr set_collectible_row_ptr
        lda #0
        ldy #0
clear_current_level_col_loop:
        sta ($fd),y
        iny
        cpy #12
        bne clear_current_level_col_loop
        inc collectible_clear_row
        lda collectible_clear_row
        cmp #LEVEL_ROWS
        bcc clear_current_level_row_loop
        rts

start_level:
        lda #0
        sta scroll_col
        sta fine_scroll
        lda #112
        sta x_pos
        lda #131
        sta y_pos
        lda #0
        sta game_state
        lda #0
        sta jump_phase
        sta jump_air_dir
        sta win_tick
        sta timer_tick
        sta key_collected
        sta level_requires_key
        lda #60
        sta timer_seconds
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
        lda level_height
        sta coarse_rows_updated

        jsr apply_fine_scroll

        jsr level_contains_key
        sta level_requires_key

        jsr clear_top_rows
        jsr draw_world
        jsr place_player_on_ground
        jsr draw_lives_hud
        jsr draw_timer_hud
        rts

place_player_on_ground:
        lda #131
        sta y_pos
spawn_seek_ground:
        jsr feet_support
        bcs spawn_found_ground
        inc y_pos
        lda y_pos
        cmp #220
        bcc spawn_seek_ground
spawn_found_ground:
        jsr settle_after_fall
        lda #0
        sta game_state
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

draw_title_screen:
        lda #0
        sta anim_tick
        jsr start_title_music

        ; Black empty backdrop for title presentation.
        lda #32
        ldx #0
title_fill_screen:
        sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $06e8,x
        inx
        bne title_fill_screen

        lda #$00
        ldx #0
title_fill_color:
        sta $d800,x
        sta $d900,x
        sta $da00,x
        sta $dae8,x
        inx
        bne title_fill_color

        ; Show only Mini sprite at side position.
        lda #$01
        sta $d015
        lda #56
        sta $d000
        lda #120
        sta $d001
        jsr set_player_frame_a

        ; Draw title copy.
        ldx #0
title_name_loop:
        lda title_name_text,x
        beq title_name_done
        sta $0572,x
        lda #$07
        sta $d972,x
        inx
        bne title_name_loop
title_name_done:

        ldx #0
title_credit_loop:
        lda title_credit_text,x
        beq title_credit_done
        sta $0617,x
        lda #$0a
        sta $da17,x
        inx
        bne title_credit_loop
title_credit_done:

        ldx #0
title_prompt_loop:
        lda title_prompt_text,x
        beq title_prompt_done
        sta $06d9,x
        lda #$01
        sta $dad9,x
        inx
        bne title_prompt_loop
title_prompt_done:
        rts

wait_title_start:
title_wait_loop:
        jsr wait_frame
        jsr update_audio

        ; Lightweight title sprite animation.
        inc anim_tick
        lda anim_tick
        and #%00001000
        beq title_frame_a
        jsr set_player_frame_b
        jmp title_poll
title_frame_a:
        jsr set_player_frame_a

        jsr update_title_bob
        jsr update_title_prompt_blink

title_poll:
        jsr poll_controls
        lda space_down
        beq title_wait_loop

title_release_loop:
        jsr wait_frame
        jsr update_audio
        jsr poll_controls
        lda space_down
        bne title_release_loop
        rts

update_title_bob:
        lda anim_tick
        and #%00010000
        beq title_bob_base
        lda #121
        sta $d001
        rts
title_bob_base:
        lda #120
        sta $d001
        rts

update_title_prompt_blink:
        lda anim_tick
        and #%00100000
        beq title_prompt_hide
        lda #$01
        bne title_prompt_set
title_prompt_hide:
        lda #$00
title_prompt_set:
        sta title_prompt_color
        ldx #0
title_prompt_color_loop:
        lda title_prompt_text,x
        beq title_prompt_color_done
        lda title_prompt_color
        sta $dad9,x
        inx
        bne title_prompt_color_loop
title_prompt_color_done:
        rts

wait_frame:
        ; Sync near the end of the visible world so coarse shifts get more
        ; non-visible time before the next frame's world area starts.
wait_below_target:
        lda $d011
        and #%10000000
        bne wait_below_target
        lda $d012
        cmp #230
        bcs wait_below_target
wait_reach_target:
        lda $d011
        and #%10000000
        bne wait_reach_target
        lda $d012
        cmp #230
        bcc wait_reach_target
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

move_step:
        .byte 1

hold_left:
        .byte 0

hold_right:
        .byte 0

jump_air_dir:
        .byte 0          ; 0=none, 1=left, 2=right

action_key:
        .byte 0

player_form:
        .byte 0          ; 0=Mini, 1=chicken easter egg

ride_mode:
        .byte 0          ; 0=none, 1=cloud1, 2=cloud2, 3=bird

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

bird_x:
        .byte 250

bird_y:
        .byte 84

bird_delay:
        .byte 0

bird_tick:
        .byte 0

bird_chirp_cooldown:
        .byte 0

rand_tmp:
        .byte 0

sound_timer:
        .byte 0

music_mode:
        .byte 0          ; 0=off, 1=title, 2=gameplay

music_tick:
        .byte 0

music_step:
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

title_name_text:
        .byte 13,9,14,9,32,20,8,5,32,3,12,15,21,4,32,18,9,4,5,18
        .byte 0

title_credit_text:
        .byte 2,25,32,13,1,7,14,21,19
        .byte 0

title_prompt_text:
        .byte 16,18,5,19,19,32,19,16,1,3,5,32,20,15,32,19,20,1,18,20
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

find_key_text:
        .byte 6,9,14,4,32,11,5,25,33
        .byte 0

open_chest_text:
        .byte 15,16,5,14,32,3,8,5,19,20
        .byte 0

lives_label_text:
        .byte 12,9,22,5,19,32,32
        .byte 0

timer_label_text:
        .byte 20,9,13,5,32
        .byte 0

level1_complete_text:
        .byte 32,12,5,22,5,12,32,49,32,3,15,13,16,12,5,20,5,32
        .byte 0

timer_seconds:
        .byte 60

timer_tick:
        .byte 0

tens_digit:
        .byte 0

ones_digit:
        .byte 0

title_prompt_color:
        .byte 1

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
        ; 14-frame jump arc with a little more height and airtime.
        .byte 0,4,9,15,21,27,30,27,23,18,13,8,4,1

TITLE_MUSIC_LEN = 24
GAMEPLAY_MUSIC_LEN = 32
IRQ_LINE_HUD = 16
IRQ_LINE_WORLD = 80
IRQ_LINE_SHIFT = 184

title_music_lo:
        .byte $2c,$43,$56,$6b,$56,$43,$2c,$22
        .byte $2c,$43,$56,$6b,$56,$43,$2c,$00
        .byte $22,$2c,$43,$56,$43,$2c,$22,$00

title_music_hi:
        .byte $1a,$1b,$1c,$1a,$1c,$1b,$1a,$1a
        .byte $1a,$1b,$1c,$1a,$1c,$1b,$1a,$00
        .byte $1a,$1a,$1b,$1c,$1b,$1a,$1a,$00

title_music_len:
        .byte 8,8,8,12,8,8,8,12
        .byte 8,8,8,12,8,8,8,16
        .byte 8,8,8,12,8,8,8,16

gameplay_music_lo:
        ; Gameplay melody: musical phrase (Ode-to-Joy style) in C major.
        .byte $f3,$f3,$38,$13,$13,$38,$f3,$8f
        .byte $5e,$5e,$8f,$f3,$f3,$8f,$8f,$00
        .byte $f3,$f3,$38,$13,$13,$38,$f3,$8f
        .byte $5e,$5e,$8f,$f3,$8f,$5e,$5e,$00

gameplay_music_hi:
        .byte $15,$15,$17,$1a,$1a,$17,$15,$13
        .byte $11,$11,$13,$15,$15,$13,$13,$00
        .byte $15,$15,$17,$1a,$1a,$17,$15,$13
        .byte $11,$11,$13,$15,$13,$11,$11,$00

gameplay_music_len:
        .byte 6,6,6,6,6,6,6,6
        .byte 6,6,6,6,6,6,12,12
        .byte 6,6,6,6,6,6,6,6
        .byte 6,6,6,6,6,6,12,12

collectible_bit_masks:
        .byte %00000001,%00000010,%00000100,%00001000
        .byte %00010000,%00100000,%01000000,%10000000

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
        .byte 15

max_scroll:
        .byte 40

current_level:
        .byte 0

key_collected:
        .byte 0

level_requires_key:
        .byte 0

debug_rows_enabled:
        .byte 1

fine_scroll:
        .byte 0

d016_base:
        .byte $10

world_d016:
        .byte $10

scroll_steps:
        .byte 0

pending_coarse_shift:
        .byte 0

irq_phase:
        .byte 0

shift_marker_line:
        .byte IRQ_LINE_WORLD

shift_marker_line_hi:
        .byte 0

shift_line_hundreds:
        .byte 0

shift_line_tens:
        .byte 0

shift_line_ones:
        .byte 0

shift_line_dirty:
        .byte 0

row2_marker_line:
        .byte IRQ_LINE_SHIFT

row2_marker_line_hi:
        .byte 0

early_world_commit_done:
        .byte 0

bird_x_msb:
        .byte 1

cloud1_x_msb:
        .byte 0

cloud2_x_msb:
        .byte 0

d010_mask_tmp:
        .byte 0

draw_char_tmp:
        .byte 0

draw_color_tmp:
        .byte 0

screen_col:
        .byte 0

level_tile_tmp:
        .byte 0

collectible_row_index:
        .byte 0

collectible_offset_lo:
        .byte 0

collectible_offset_hi:
        .byte 0

collectible_mul_lo:
        .byte 0

collectible_mul_hi:
        .byte 0

collectible_clear_row:
        .byte 0

uniform_scan_col:
        .byte 0

uniform_candidate_tile:
        .byte $ff

uniform_candidate_color:
        .byte $00

uniform_row_tiles:
        .fill LEVEL_ROWS,$ff

uniform_row_count:
        .byte 0

scroll_skip_row_count:
        .byte 0

uniform_idle_row:
        .byte 0

coarse_rows_updated:
        .byte 15

char_row_ptr_lo:
        .byte <$0518,<$0540,<$0568,<$0590,<$05b8
        .byte <$05e0,<$0608,<$0630,<$0658,<$0680
        .byte <$06a8,<$06d0,<$06f8,<$0720,<$0748

char_row_ptr_hi:
        .byte >$0518,>$0540,>$0568,>$0590,>$05b8
        .byte >$05e0,>$0608,>$0630,>$0658,>$0680
        .byte >$06a8,>$06d0,>$06f8,>$0720,>$0748

color_row_ptr_lo:
        .byte <$d918,<$d940,<$d968,<$d990,<$d9b8
        .byte <$d9e0,<$da08,<$da30,<$da58,<$da80
        .byte <$daa8,<$dad0,<$daf8,<$db20,<$db48

color_row_ptr_hi:
        .byte >$d918,>$d940,>$d968,>$d990,>$d9b8
        .byte >$d9e0,>$da08,>$da30,>$da58,>$da80
        .byte >$daa8,>$dad0,>$daf8,>$db20,>$db48

win_timer:
        .byte 0

end_timer:
        .byte 0

prompt_shown:
        .byte 0

end_wait_release:
        .byte 0

level_collectible_state:
        .fill 1024,0

*=$3c00
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

*=$3c40
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

*=$3c80
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

*=$3cc0
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

*=$3d00
bird_sprite_a:
        ; 24x21 multicolor bird silhouette, wings up.
        .byte $00,$00,$00
        .byte $00,$00,$00
        .byte $00,$00,$00
        .byte $03,$00,$c0
        .byte $07,$81,$e0
        .byte $0f,$c3,$f0
        .byte $1f,$e7,$f8
        .byte $3f,$ff,$fc
        .byte $7f,$ff,$fe
        .byte $3f,$ff,$fc
        .byte $1f,$ff,$f8
        .byte $0f,$ff,$f0
        .byte $07,$ff,$e0
        .byte $03,$ff,$c0
        .byte $01,$ff,$80
        .byte $00,$ff,$00
        .byte $00,$7e,$00
        .byte $00,$3c,$00
        .byte $00,$18,$00
        .byte $00,$18,$00
        .byte $00,$00,$00
        .byte $00

*=$3d40
bird_sprite_b:
        ; 24x21 multicolor bird silhouette, wings down.
        .byte $00,$00,$00
        .byte $00,$00,$00
        .byte $00,$00,$00
        .byte $00,$18,$00
        .byte $00,$3c,$00
        .byte $01,$ff,$80
        .byte $03,$ff,$c0
        .byte $07,$ff,$e0
        .byte $0f,$ff,$f0
        .byte $1f,$ff,$f8
        .byte $3f,$ff,$fc
        .byte $7f,$ff,$fe
        .byte $3f,$ff,$fc
        .byte $1f,$ff,$f8
        .byte $0f,$ff,$f0
        .byte $07,$ff,$e0
        .byte $03,$ff,$c0
        .byte $01,$e7,$80
        .byte $00,$c3,$00
        .byte $00,$81,$00
        .byte $00,$00,$00
        .byte $00

*=$3d80
chicken_sprite_a:
        ; 24x21 multicolor chicken, stance A.
        .byte $00,$00,$00
        .byte $00,$00,$00
        .byte $00,$3c,$00
        .byte $00,$7e,$00
        .byte $00,$ff,$00
        .byte $01,$ff,$80
        .byte $01,$ff,$80
        .byte $03,$ff,$c0
        .byte $03,$ff,$c0
        .byte $03,$ff,$c0
        .byte $03,$ff,$c0
        .byte $03,$ff,$c0
        .byte $01,$ff,$80
        .byte $01,$ff,$80
        .byte $00,$ff,$00
        .byte $00,$7e,$00
        .byte $00,$3c,$00
        .byte $00,$66,$00
        .byte $00,$42,$00
        .byte $00,$24,$00
        .byte $00,$24,$00
        .byte $00

*=$3dc0
chicken_sprite_b:
        ; 24x21 multicolor chicken, stance B.
        .byte $00,$00,$00
        .byte $00,$00,$00
        .byte $00,$3c,$00
        .byte $00,$7e,$00
        .byte $00,$ff,$00
        .byte $01,$ff,$80
        .byte $01,$ff,$80
        .byte $03,$ff,$c0
        .byte $03,$ff,$c0
        .byte $03,$ff,$c0
        .byte $03,$ff,$c0
        .byte $03,$ff,$c0
        .byte $01,$ff,$80
        .byte $01,$ff,$80
        .byte $00,$ff,$00
        .byte $00,$7e,$00
        .byte $00,$3c,$00
        .byte $00,$66,$00
        .byte $00,$24,$00
        .byte $00,$42,$00
        .byte $00,$24,$00
        .byte $00

*=$4000
.include "levels/active_levelset.inc"

; --- Unrolled scroll shift routines, placed after level data ---
; Screen RAM rows: $0518,$0540,$0568,$0590,$05b8,$05e0,$0608,$0630,$0658,$0680,$06a8,$06d0,$06f8,$0720,$0748
; Color RAM = screen + $d400

shift_left_39 .macro base
        lda \base+1
        sta \base+0
        lda \base+2
        sta \base+1
        lda \base+3
        sta \base+2
        lda \base+4
        sta \base+3
        lda \base+5
        sta \base+4
        lda \base+6
        sta \base+5
        lda \base+7
        sta \base+6
        lda \base+8
        sta \base+7
        lda \base+9
        sta \base+8
        lda \base+10
        sta \base+9
        lda \base+11
        sta \base+10
        lda \base+12
        sta \base+11
        lda \base+13
        sta \base+12
        lda \base+14
        sta \base+13
        lda \base+15
        sta \base+14
        lda \base+16
        sta \base+15
        lda \base+17
        sta \base+16
        lda \base+18
        sta \base+17
        lda \base+19
        sta \base+18
        lda \base+20
        sta \base+19
        lda \base+21
        sta \base+20
        lda \base+22
        sta \base+21
        lda \base+23
        sta \base+22
        lda \base+24
        sta \base+23
        lda \base+25
        sta \base+24
        lda \base+26
        sta \base+25
        lda \base+27
        sta \base+26
        lda \base+28
        sta \base+27
        lda \base+29
        sta \base+28
        lda \base+30
        sta \base+29
        lda \base+31
        sta \base+30
        lda \base+32
        sta \base+31
        lda \base+33
        sta \base+32
        lda \base+34
        sta \base+33
        lda \base+35
        sta \base+34
        lda \base+36
        sta \base+35
        lda \base+37
        sta \base+36
        lda \base+38
        sta \base+37
        lda \base+39
        sta \base+38
.endm

shift_right_39 .macro base
        lda \base+38
        sta \base+39
        lda \base+37
        sta \base+38
        lda \base+36
        sta \base+37
        lda \base+35
        sta \base+36
        lda \base+34
        sta \base+35
        lda \base+33
        sta \base+34
        lda \base+32
        sta \base+33
        lda \base+31
        sta \base+32
        lda \base+30
        sta \base+31
        lda \base+29
        sta \base+30
        lda \base+28
        sta \base+29
        lda \base+27
        sta \base+28
        lda \base+26
        sta \base+27
        lda \base+25
        sta \base+26
        lda \base+24
        sta \base+25
        lda \base+23
        sta \base+24
        lda \base+22
        sta \base+23
        lda \base+21
        sta \base+22
        lda \base+20
        sta \base+21
        lda \base+19
        sta \base+20
        lda \base+18
        sta \base+19
        lda \base+17
        sta \base+18
        lda \base+16
        sta \base+17
        lda \base+15
        sta \base+16
        lda \base+14
        sta \base+15
        lda \base+13
        sta \base+14
        lda \base+12
        sta \base+13
        lda \base+11
        sta \base+12
        lda \base+10
        sta \base+11
        lda \base+9
        sta \base+10
        lda \base+8
        sta \base+9
        lda \base+7
        sta \base+8
        lda \base+6
        sta \base+7
        lda \base+5
        sta \base+6
        lda \base+4
        sta \base+5
        lda \base+3
        sta \base+4
        lda \base+2
        sta \base+3
        lda \base+1
        sta \base+2
        lda \base+0
        sta \base+1
.endm

capture_row2_marker .macro
        lda $d011
        and #%10000000
        beq row2_marker_line_low\@
        lda #1
        sta row2_marker_line_hi
        jmp row2_marker_store_line\@
row2_marker_line_low\@:
        lda #0
        sta row2_marker_line_hi
row2_marker_store_line\@:
        lda $d012
        sta row2_marker_line
.endm

shift_left_row0_if_needed .macro
        lda uniform_row_tiles+0
        cmp #$ff
        beq do_shift\@
        jsr maybe_commit_world_scroll
        jmp shift_exit\@
do_shift\@:
        shift_left_39 $0518
        shift_left_39 $d918
        jsr fill_right_edge_row0
        jsr maybe_commit_world_scroll
shift_exit\@:
.endm

shift_left_row_if_needed .macro row, base, colorbase
        lda uniform_row_tiles+\row
        cmp #$ff
        beq do_shift\row
        jsr maybe_commit_world_scroll
        jmp shift_exit\row
do_shift\row:
        shift_left_39 \base
        shift_left_39 \colorbase
        jsr maybe_commit_world_scroll
shift_exit\row:
.endm

shift_right_row0_if_needed .macro
        lda uniform_row_tiles+0
        cmp #$ff
        beq do_shift\@
        jsr maybe_commit_world_scroll
        jmp shift_exit\@
do_shift\@:
        shift_right_39 $0518
        shift_right_39 $d918
        jsr fill_left_edge_row0
        jsr maybe_commit_world_scroll
shift_exit\@:
.endm

shift_right_row_if_needed .macro row, base, colorbase
        lda uniform_row_tiles+\row
        cmp #$ff
        beq do_shift\row
        jsr maybe_commit_world_scroll
        jmp shift_exit\row
do_shift\row:
        shift_right_39 \base
        shift_right_39 \colorbase
        jsr maybe_commit_world_scroll
shift_exit\row:
.endm

unrolled_shift_left_full:
        ; Top to bottom: row 0..14, char then color per row.
        shift_left_39 $0518
        shift_left_39 $d918
        jsr fill_right_edge_row0
        jsr maybe_commit_world_scroll
        shift_left_39 $0540
        shift_left_39 $d940
        jsr maybe_commit_world_scroll
        capture_row2_marker
        shift_left_39 $0568
        shift_left_39 $d968
        jsr maybe_commit_world_scroll
        shift_left_39 $0590
        shift_left_39 $d990
        jsr maybe_commit_world_scroll
        shift_left_39 $05b8
        shift_left_39 $d9b8
        jsr maybe_commit_world_scroll
        shift_left_39 $05e0
        shift_left_39 $d9e0
        jsr maybe_commit_world_scroll
        shift_left_39 $0608
        shift_left_39 $da08
        jsr maybe_commit_world_scroll
        shift_left_39 $0630
        shift_left_39 $da30
        jsr maybe_commit_world_scroll
        shift_left_39 $0658
        shift_left_39 $da58
        jsr maybe_commit_world_scroll
        shift_left_39 $0680
        shift_left_39 $da80
        jsr maybe_commit_world_scroll
        shift_left_39 $06a8
        shift_left_39 $daa8
        jsr maybe_commit_world_scroll
        shift_left_39 $06d0
        shift_left_39 $dad0
        jsr maybe_commit_world_scroll
        shift_left_39 $06f8
        shift_left_39 $daf8
        jsr maybe_commit_world_scroll
        shift_left_39 $0720
        shift_left_39 $db20
        jsr maybe_commit_world_scroll
        shift_left_39 $0748
        shift_left_39 $db48
        jsr maybe_commit_world_scroll
        rts

unrolled_shift_right_full:
        ; Top to bottom: row 0..14, char then color per row.
        shift_right_39 $0518
        shift_right_39 $d918
        jsr fill_left_edge_row0
        jsr maybe_commit_world_scroll
        shift_right_39 $0540
        shift_right_39 $d940
        jsr maybe_commit_world_scroll
        capture_row2_marker
        shift_right_39 $0568
        shift_right_39 $d968
        jsr maybe_commit_world_scroll
        shift_right_39 $0590
        shift_right_39 $d990
        jsr maybe_commit_world_scroll
        shift_right_39 $05b8
        shift_right_39 $d9b8
        jsr maybe_commit_world_scroll
        shift_right_39 $05e0
        shift_right_39 $d9e0
        jsr maybe_commit_world_scroll
        shift_right_39 $0608
        shift_right_39 $da08
        jsr maybe_commit_world_scroll
        shift_right_39 $0630
        shift_right_39 $da30
        jsr maybe_commit_world_scroll
        shift_right_39 $0658
        shift_right_39 $da58
        jsr maybe_commit_world_scroll
        shift_right_39 $0680
        shift_right_39 $da80
        jsr maybe_commit_world_scroll
        shift_right_39 $06a8
        shift_right_39 $daa8
        jsr maybe_commit_world_scroll
        shift_right_39 $06d0
        shift_right_39 $dad0
        jsr maybe_commit_world_scroll
        shift_right_39 $06f8
        shift_right_39 $daf8
        jsr maybe_commit_world_scroll
        shift_right_39 $0720
        shift_right_39 $db20
        jsr maybe_commit_world_scroll
        shift_right_39 $0748
        shift_right_39 $db48
        jsr maybe_commit_world_scroll
        rts

unrolled_shift_left:
        ; Top to bottom: shift only mixed rows, skip uniform rows.
        shift_left_row0_if_needed
        shift_left_row_if_needed 1, $0540, $d940
        capture_row2_marker
        shift_left_row_if_needed 2, $0568, $d968
        shift_left_row_if_needed 3, $0590, $d990
        shift_left_row_if_needed 4, $05b8, $d9b8
        shift_left_row_if_needed 5, $05e0, $d9e0
        shift_left_row_if_needed 6, $0608, $da08
        shift_left_row_if_needed 7, $0630, $da30
        shift_left_row_if_needed 8, $0658, $da58
        shift_left_row_if_needed 9, $0680, $da80
        shift_left_row_if_needed 10, $06a8, $daa8
        shift_left_row_if_needed 11, $06d0, $dad0
        shift_left_row_if_needed 12, $06f8, $daf8
        shift_left_row_if_needed 13, $0720, $db20
        shift_left_row_if_needed 14, $0748, $db48
        rts

unrolled_shift_left_from_row3:
        shift_left_39 $0590
        shift_left_39 $d990
        jsr maybe_commit_world_scroll
unrolled_shift_left_from_row4:
        shift_left_39 $05b8
        shift_left_39 $d9b8
        jsr maybe_commit_world_scroll
unrolled_shift_left_from_row5:
        shift_left_39 $05e0
        shift_left_39 $d9e0
        jsr maybe_commit_world_scroll
unrolled_shift_left_from_row6:
        shift_left_39 $0608
        shift_left_39 $da08
        jsr maybe_commit_world_scroll
unrolled_shift_left_from_row7:
        shift_left_39 $0630
        shift_left_39 $da30
        jsr maybe_commit_world_scroll
unrolled_shift_left_from_row8:
        shift_left_39 $0658
        shift_left_39 $da58
        jsr maybe_commit_world_scroll
unrolled_shift_left_from_row9:
        shift_left_39 $0680
        shift_left_39 $da80
        jsr maybe_commit_world_scroll
unrolled_shift_left_from_row10:
        shift_left_39 $06a8
        shift_left_39 $daa8
        jsr maybe_commit_world_scroll
unrolled_shift_left_from_row11:
        shift_left_39 $06d0
        shift_left_39 $dad0
        jsr maybe_commit_world_scroll
unrolled_shift_left_from_row12:
        shift_left_39 $06f8
        shift_left_39 $daf8
        jsr maybe_commit_world_scroll
unrolled_shift_left_from_row13:
        shift_left_39 $0720
        shift_left_39 $db20
        jsr maybe_commit_world_scroll
unrolled_shift_left_from_row14:
        shift_left_39 $0748
        shift_left_39 $db48
        jsr maybe_commit_world_scroll
unrolled_shift_left_done:
        rts

unrolled_shift_right:
        ; Top to bottom: shift only mixed rows, skip uniform rows.
        shift_right_row0_if_needed
        shift_right_row_if_needed 1, $0540, $d940
        capture_row2_marker
        shift_right_row_if_needed 2, $0568, $d968
        shift_right_row_if_needed 3, $0590, $d990
        shift_right_row_if_needed 4, $05b8, $d9b8
        shift_right_row_if_needed 5, $05e0, $d9e0
        shift_right_row_if_needed 6, $0608, $da08
        shift_right_row_if_needed 7, $0630, $da30
        shift_right_row_if_needed 8, $0658, $da58
        shift_right_row_if_needed 9, $0680, $da80
        shift_right_row_if_needed 10, $06a8, $daa8
        shift_right_row_if_needed 11, $06d0, $dad0
        shift_right_row_if_needed 12, $06f8, $daf8
        shift_right_row_if_needed 13, $0720, $db20
        shift_right_row_if_needed 14, $0748, $db48
        rts

unrolled_shift_right_from_row3:
        shift_right_39 $0590
        shift_right_39 $d990
        jsr maybe_commit_world_scroll
unrolled_shift_right_from_row4:
        shift_right_39 $05b8
        shift_right_39 $d9b8
        jsr maybe_commit_world_scroll
unrolled_shift_right_from_row5:
        shift_right_39 $05e0
        shift_right_39 $d9e0
        jsr maybe_commit_world_scroll
unrolled_shift_right_from_row6:
        shift_right_39 $0608
        shift_right_39 $da08
        jsr maybe_commit_world_scroll
unrolled_shift_right_from_row7:
        shift_right_39 $0630
        shift_right_39 $da30
        jsr maybe_commit_world_scroll
unrolled_shift_right_from_row8:
        shift_right_39 $0658
        shift_right_39 $da58
        jsr maybe_commit_world_scroll
unrolled_shift_right_from_row9:
        shift_right_39 $0680
        shift_right_39 $da80
        jsr maybe_commit_world_scroll
unrolled_shift_right_from_row10:
        shift_right_39 $06a8
        shift_right_39 $daa8
        jsr maybe_commit_world_scroll
unrolled_shift_right_from_row11:
        shift_right_39 $06d0
        shift_right_39 $dad0
        jsr maybe_commit_world_scroll
unrolled_shift_right_from_row12:
        shift_right_39 $06f8
        shift_right_39 $daf8
        jsr maybe_commit_world_scroll
unrolled_shift_right_from_row13:
        shift_right_39 $0720
        shift_right_39 $db20
        jsr maybe_commit_world_scroll
unrolled_shift_right_from_row14:
        shift_right_39 $0748
        shift_right_39 $db48
        jsr maybe_commit_world_scroll
unrolled_shift_right_done:
        rts
