*=$0801
        .word next
        .word 10
        .byte $9e
        .text "2064"
        .byte 0
next    .word 0

*=$0810
        sei

        ldx #0
loop:
        lda message,x
        beq done
        jsr $ffd2       ; KERNAL CHROUT
        inx
        bne loop

done:
        rts

message:
        .text "HELLO WORLD",13,0