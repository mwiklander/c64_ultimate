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

        lda #0
        sta current_level
        lda #5
        sta lives

        ; Sprite pointers in screen memory.
        ; $3800/64 = $e0 (frame A), $3840/64 = $e1 (frame B).
        ; $3900/64 = $e4 (bird frame A), $3940/64 = $e5 (bird frame B).
        ; $3880/64 = $e2 (cloud A), $38c0/64 = $e3 (cloud B).
        lda #$e0
        sta $07f8
        lda #$e4
        sta $07f9
        lda #$e2
        sta $07fa
        lda #$e3
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

        ; Re-enable IRQ so KERNAL keyboard scan/GETIN works.
        cli

main_loop:
        jsr wait_frame

        ; Frame timing marker: red while updates run.
        lda #$02
        sta $d020

        jsr check_star_cheat
        jsr update_clouds
        jsr update_bird
        jsr update_audio

        lda game_state
        cmp #2
        bcs skip_action_poll
        jsr poll_action_keys
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
        lda #$e1
        sta $07f8
        jmp frame_done
frame_a:
        lda #$e0
        sta $07f8

frame_done:
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
        beq run_on_ground
        lda #1
        sta move_step
        rts

run_on_ground:
        lda left_down
        beq check_run_right
        lda right_down
        bne reset_run_speed
        inc hold_left
        lda #0
        sta hold_right
        lda hold_left
        cmp #4
        bcc walk_speed
        lda #2
        sta move_step
        rts

check_run_right:
        lda right_down
        beq reset_run_speed
        inc hold_right
        lda #0
        sta hold_left
        lda hold_right
        cmp #4
        bcc walk_speed
        lda #2
        sta move_step
        rts

walk_speed:
        lda #1
        sta move_step
        rts

reset_run_speed:
        lda #0
        sta hold_left
        sta hold_right
        lda #1
        sta move_step
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
        beq hard_left
        jsr blocked_left_after_scroll
        bcs left_blocked
        dec scroll_col
        jsr draw_world
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
        bcs hard_right
        jsr blocked_right_after_scroll
        bcs right_blocked
        inc scroll_col
        jsr draw_world
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

poll_action_keys:
        ; One-shot action key polling (C/B/R) via KERNAL GETIN.
        jsr $ffe4
        sta action_key
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
        lda #250
        sta bird_x
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
        lda #250
        sta bird_x
        lda #0
        sta bird_tick

bird_active:
        inc bird_tick
        lda bird_tick
        and #%00000001
        bne bird_draw_current

        lda bird_x
        sec
        sbc #1
        sta bird_x
        cmp #2
        bcs bird_draw

        jsr random_bird_delay
        sta bird_delay
        lda #250
        sta bird_x
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
        lda #$e5
        sta $07f9
        rts

bird_frame_a:
        lda #$e4
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
        lda cloud1_x
        clc
        adc #8
        sta x_pos
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
        lda cloud2_x
        clc
        adc #8
        sta x_pos
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
        lda bird_x
        clc
        adc #6
        sta x_pos
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
        inc scroll_col
        jsr draw_world
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
        dec scroll_col
        jsr draw_world
        lda #68
        sta x_pos
        rts

near_cloud1:
        lda cloud1_delay
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
        sta $d005
        rts

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
        sta $d007
        rts

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

draw_timer_hud:
        ldx #0
timer_label_loop:
        lda timer_label_text,x
        beq timer_digits
        sta $0421,x
        lda #$01
        sta $d821,x
        inx
        bne timer_label_loop

timer_digits:
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
        sta $0426
        lda ones_digit
        clc
        adc #48
        sta $0427
        lda #$07
        sta $d826
        sta $d827
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
        bcc collectibles_done
        rts

collect_if_hit:
        jsr get_tile_at
        bcc collect_none
        cmp #5
        beq collect_pineapple_now
        cmp #6
        beq collect_heart_now
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

clear_collectible_tile:
        lda hit_row
        sec
        sbc #7
        jsr set_level_row_ptr
        ldy world_col
        lda #0
        sta ($fb),y
        jsr draw_world

collectibles_done:
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
        jsr restart_game
        rts

restart_default_lives:
        lda #5
        sta lives
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

        ; Clear dynamic world rows to sky.
        lda #32
        sta $0518,x
        sta $0540,x
        sta $0568,x
        sta $0590,x
        sta $05b8,x
        sta $05e0,x
        sta $0608,x
        sta $0630,x
        sta $0658,x
        sta $0680,x
        sta $06a8,x
        sta $06d0,x
        sta $06f8,x
        sta $0720,x
        sta $0748,x
        lda #$0b
        sta $d918,x
        sta $d940,x
        sta $d968,x
        sta $d990,x
        sta $d9b8,x
        sta $d9e0,x
        sta $da08,x
        sta $da30,x
        sta $da58,x
        sta $da80,x
        sta $daa8,x
        sta $dad0,x
        sta $daf8,x
        sta $db20,x
        sta $db48,x

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
        ; Tile ids: 0 sky, 1 ground, 2 stone, 3 grass/top, 4 flag, 5 pineapple, 6 heart
        cmp #1
        beq tile_ground
        cmp #2
        beq tile_stone
        cmp #3
        beq tile_grass
        cmp #4
        beq tile_flag
        cmp #5
        beq tile_pineapple
        cmp #6
        beq tile_heart
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

tile_pineapple:
        lda #87         ; Symbol-like glyph (fruit-ish in C64 graphics set)
        ldy #$07        ; yellow
        rts

tile_heart:
        lda #83         ; Heart suit glyph in C64 graphics set
        ldy #$02        ; red
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

start_level:
        lda #0
        sta scroll_col
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

        jsr clear_top_rows
        jsr draw_banner
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
        lda #$e0
        sta $07f8

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
        lda #$e1
        sta $07f8
        jmp title_poll
title_frame_a:
        lda #$e0
        sta $07f8

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
        ; Wait for raster MSB high (lines 256+), then low again (new frame),
        ; and align to line 0 so frame timing starts at true top.
wait_msb_hi:
        lda $d011
        and #%10000000
        beq wait_msb_hi
wait_msb_lo:
        lda $d011
        and #%10000000
        bne wait_msb_lo
wait_line0:
        lda $d012
        bne wait_line0
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

win_timer:
        .byte 0

end_timer:
        .byte 0

prompt_shown:
        .byte 0

end_wait_release:
        .byte 0

.include "levels/active_levelset.inc"

*=$3800
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

*=$3840
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

*=$3880
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

*=$38c0
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

*=$3900
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

*=$3940
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
