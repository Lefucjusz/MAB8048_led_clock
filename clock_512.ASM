;MAB8048H, 9.8304MHz
;Simple clock with seven-segment display by Lefucjusz, Gdansk 2020
;No RTC, main clock signal fed into in internal timer is used as timebase
;Signal feeding timer has a frequency of 9830400/(15*32) = 20480Hz
;Timer counts from 216, generating interrupt when T register overflows (255->0)
;Thus interrupt frequency is 20480/(256-216) = 512Hz
;To obtain 1Hz timebase, registers R5 and R6 are used as an interrupt counter
;Register R5 is never cleared anywhere except for startup_init routine
;It only 'clears' itself when it wraps around
;It means that it goes from any value to the same value within half a second - division by 256
;Register R6 acts as an additional bit in R5 - it is toggled every time R5 overflows
;That provides another division by 2, together creating division by 512, needed to obtain 1Hz timebase
;Addidtionally, R6 is used as colon state register, as it toggles every 500ms
	.cr	8048
	.tf	rom.bin,BIN
	.lf	clock.lst
	
;Variables in RAM	
hr	.eq $20
min	.eq $21
sec	.eq $22

;Defines
timer_init_val .eq 216 ;With 9.8304MHz xtal gives 512 interrupts per second

;Fixed purpose registers
;R4 - display pointer
;R5 - interrupt counter 8 LSBs
;R6 - interrupt counter 9th bit, colon state
;R7 - interrupt flag
	
;Set vectors
	.no $00 ;Set jump to main at reset vector (00h)
	jmp main
	
	.no $07 ;Set jump to timer ISR at timer interrupt vector (07h)
	jmp timer_isr

main:
	call startup_init ;Initialize variables and timer
	
loop:
	mov A,R7
	jz loop ;Loop until flag is set
	
	dec R7 ;Fastest way to clear interrupt flag	
	inc R5 ;Increment interrupt counter
	mov A,R5 
	jnz skip_msb_update	;If interrupt counter 8 LSBs == 0, update MSB
	
	mov A,R6
	xrl A,#%00000001
	mov R6,A ;Toggle counter MSB state	
	
	jnz skip_time_update ;If MSB == 0, update time
	call time_update
	
skip_time_update: ;Check time setting buttons every 500ms (every time R5 == 0)
	call time_set
	
skip_msb_update:	
	call display_update
	jmp loop
	
;----------------Subroutines----------------
;Uses R0,R5,R6,R7
time_set:
	jt0 min_set ;If hours increment key not pressed, go to minutes setting
	mov R0,#hr
	mov A,@R0 ;Load actual minutes value
	cpl A
	add A,#24 ;A = (-hr-1 + 24) -> Z = (++hr == 24)
	jnz time_set_store ;Go to part incrementing value once and storing in memory
	mov A,#0
	mov @R0,A ;Clear minutes
	jmp time_set_end	
min_set:
	jt1 time_set_end ;If minutes increment key not pressed, leave
	mov R0,#min
	mov A,@R0 ;Load actual minutes value
	cpl A
	add A,#60 ;A = (-min-1 + 60) -> Z = (++min == 60)
	jnz time_set_store ;Go to part incrementing value once and storing in memory
	mov A,#0
	mov @R0,A ;Clear minutes
	jmp time_set_end
time_set_store:
	mov A,@R0
	inc A
	mov @R0,A ;Increment value pointed by R0	
	
	mov R0,#sec
	mov A,#0
	mov @R0,A ;Clear seconds
	
	;Reset every internal time countdown value so that first second of the
	;newly set time will really last a second 
	mov R5,#0 ;Clear interrupt counter 8 LSBs	
	mov R6,#0 ;Clear interrupt counter 9th bit
	mov R7,#0 ;Clear interrupt flag	
	call timer_reload ;Set timer register initial value
time_set_end:
	ret
	
;Uses R0	
time_update:
	mov R0,#sec
	mov A,@R0 ;Load actual seconds value
	cpl A
	add A,#60 ;A = (-sec-1 + 60) -> Z = (++sec == 60)
	jnz update_store ;Go to part incrementing value once and storing in memory
	mov A,#0
	mov @R0,A ;Clear seconds
	
	mov R0,#min
	mov A,@R0 ;Load actual minutes value
	cpl A
	add A,#60 ;A = (-min-1 + 60) -> Z = (++min == 60)
	jnz update_store ;Go to part incrementing value once and storing in memory
	mov A,#0
	mov @R0,A ;Clear minutes
	
	mov R0,#hr
	mov A,@R0 ;Load actual minutes value
	cpl A
	add A,#24 ;A = (-hr-1 + 24) -> Z = (++hr == 24)
	jnz update_store ;Go to part incrementing value once and storing in memory
	mov A,#0
	mov @R0,A ;Clear hours
	jmp update_end ;Leave
update_store:
	mov A,@R0
	inc A
	mov @R0,A ;Increment value pointed by R0
update_end:
	ret
	
digits:
	.ot ;Open table to check if whole table and all movps are on the same page
	.db %11000000 ;0
	.db %11111001 ;1
	.db %10100100 ;2
	.db %10110000 ;3
	.db %10011001 ;4
	.db %10010010 ;5
	.db %10000010 ;6
	.db %11111000 ;7
	.db %10000000 ;8
	.db %10010000 ;9

;Uses R0,R1,R4	
display_update:
	anl P2,#%11000000 ;Turn off all displays
	;switch(display_pointer)
	mov A,R4 ;A = R4 -> C = (R4 == 0)
	jz disp_hr_tens ;case 0
	
	cpl A
	inc A ;A = -R4
	
	inc A ;A = -R4+1 -> C = (R4 == 1)
	jz disp_hr_ones ;case 1
	
	inc A ;A = -R4+2 -> C = (R4 == 2)
	jz disp_min_tens ;case 2
	
	inc A ;A = -R4+3 -> C = (R4 == 3)
	jz disp_min_ones ;case 3
	
	inc A ;A = -R4+4 -> C = (R4 == 4)
	jz disp_sec_tens ;case 4
	
	inc A ;A = -R4+5 -> C = (R4 == 5)
	jz disp_sec_ones ;case 5
	
	jmp ptr_reset ;default
	
disp_hr_tens:
	mov R0,#hr
	mov A,@R0
	mov R0,A ;Store hr value in R0
	call byte_split ;Split number
	mov A,#digits ;Load address of digits code array into A
	add A,R1 ;Add tens to compute needed digit code position
	movp A,@A ;Obtain digit code
	outl P1,A ;Write code to cathodes port
	orl P2,#%00100000 ;Turn on first display
	inc R4 ;Select next display
	jmp disp_colon ;Update colon
	
disp_hr_ones:
	mov R0,#hr
	mov A,@R0
	mov R0,A ;Store hr value in R0
	call byte_split ;Split number
	mov A,#digits ;Load address of digits code array into A
	add A,R0 ;Add ones to compute needed digit code position
	movp A,@A ;Obtain digit code
	outl P1,A ;Write code to cathodes port
	orl P2,#%00010000 ;Turn on second display
	inc R4 ;Select next display
	jmp disp_colon ;Update colon
	
disp_min_tens:
	mov R0,#min
	mov A,@R0
	mov R0,A ;Store min value in R0
	call byte_split ;Split number
	mov A,#digits ;Load address of digits code array into A
	add A,R1 ;Add tens to compute needed digit code position
	movp A,@A ;Obtain digit code
	outl P1,A ;Write code to cathodes port
	orl P2,#%00001000 ;Turn on third display
	inc R4 ;Select next display
	jmp disp_colon ;Update colon
	
disp_min_ones:
	mov R0,#min
	mov A,@R0
	mov R0,A ;Store min value in R0
	call byte_split ;Split number
	mov A,#digits ;Load address of digits code array into A
	add A,R0 ;Add ones to compute needed digit code position
	movp A,@A ;Obtain digit code
	outl P1,A ;Write code to cathodes port
	orl P2,#%00000100 ;Turn on fourth display
	inc R4 ;Select next display
	jmp disp_colon ;Update colon
	
disp_sec_tens:
	mov R0,#sec
	mov A,@R0
	mov R0,A ;Store sec value in R0
	call byte_split ;Split number
	mov A,#digits ;Load address of digits code array into A
	add A,R1 ;Add tens to compute needed digit code position
	movp A,@A ;Obtain digit code
	outl P1,A ;Write code to cathodes port
	orl P2,#%00000010 ;Turn on fifth display
	inc R4 ;Select next display
	jmp disp_colon ;Update colon
	
disp_sec_ones:
	mov R0,#sec
	mov A,@R0
	mov R0,A ;Store sec value in R0
	call byte_split ;Split number
	mov A,#digits ;Load address of digits code array into A
	add A,R0 ;Add ones to compute needed digit code position
	movp A,@A ;Obtain digit code
	;Close table after last movp - if whole table and all 
	;movps are not on the same page, assembler will raise an error
	.ct 	
	outl P1,A ;Write code to cathodes port
	orl P2,#%00000001 ;Turn on sixth display	
ptr_reset:
	mov R4,#0 ;Select first display
disp_colon:
	mov A,R6
	jz disp_end ;If colon state is zero, leave colon turned off
	anl P1,#%01111111 ;Otherwise turn it on
disp_end:
	ret

;R0 - value to be split to digits, ones; R1 - tens; uses R0,R1
byte_split:
	mov R1,#0 ;Clear tens
div10:
	mov A,R0 ;Load value to be split to A
	cpl A ;Complement A
	add A,#10 ;Add 10 (C = (R0 < 10))
	jc div10_end ;If there has been carry - break
	cpl A ;Complement A (A=R2-10)
	mov R0,A ;Store new value in R0
	inc R1 ;Increment tens
	jmp div10 ;Perform again, until R0 < 10	
div10_end:
	ret
	
;Uses R0,R4,R5,R6,R7	
startup_init:
	mov A,#0 ;Set A to 0, it will be needed to clear all time countdown related registers and variables
	
	mov R0,#hr
	mov @R0,A ;Clear hours
	
	mov R0,#min
	mov @R0,A ;Clear minutes
	
	mov R0,#sec
	mov @R0,A ;Clear seconds
	
	outl P2,A ;Turn off all displays
	mov R4,A ;Clear display pointer (select first one)
	mov R5,A ;Clear interrupt counter 8 LSBs
	mov R6,A ;Clear interrupt counter 9th bit
	mov R7,A ;Clear interrupt flag	
	
	en tcnti ;Enable timer interrupt
	call timer_reload ;Set timer register initial value
	strt T ;Start timer
	ret
	
;No registers used	
timer_reload:
	mov A,#timer_init_val
	mov T,A ;Set timer register initial value
	ret
	
;Uses R7	
timer_isr:
	call timer_reload ;Set timer register initial value
	inc R7 ;Fastest way to set interrupt flag
	retr