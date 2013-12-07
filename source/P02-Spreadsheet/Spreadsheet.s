@* Spreadsheet
@*
@* written by			Rob Bishop
@* created on			05 November 2013
@* last modified on		03 December 2013
@*
@* Create a simple one-row spreadsheet. The number of cells in the row
@*		will be selected by the user (minimum number of cells: 2, maximum
@*		number of cells: 10), with one cell extra to contain a calculation result.
@*
@* Your program must provide the following functionality:
@*
@* 1. allow the user to specify how many cells are desired (add one extra cell for the calculation)
@*
@* 2. allow the user to specify what data type (int8, int16, or int32) is desired for her/his "spreadsheet"
@*
@* 3. dynamically allocate a number of bytes to match the number of cells (plus one for the calculation cell)
@*		desired by the user, scaled to match the selected data type -- default value for each cell is zero (0)
@*
@* 4. allow the user to select individual cells (by number) and edit the contents of these cells
@*
@* 5. allow the user to select between sum, average, minimum value, and maximum value calculations
@*		(default is sum) -- the selected calculation will be run on the cells and stored/displayed in the
@*		extra/calculation result cell
@*
@* 6. display the type and result (using the extra/calculation cell) of the calculation (sum, avg, min,
@*		or max) selected by the user -- on overflow (which may happen for sum and average (since average
@*		uses sum), also display "[ERROR]" next to the result
@*
@* 7. allow the user to reset -- the current row of cells will be freed from memory and the user will be
@*		returned to the prompt and be asked once again for the number of cells and the data type desired
@*
@* 8. allow the user to quit at any time -- to achieve this, you should include a menu of options (edit, change
@*		calculation, change presentation, reset, quit)
@*
@* 9. above the menu of options, display all of the cell values and the calculation result cell vertically
@*		(up-and-down) -- this display should be updated each time the user does something that changes the
@*		contents of any of the cells
@*
@* 10. allow the user to toggle between binary, decimal, and hexadecimal presentations of the values in all
@*		of the cells (including the calculation result cell) -- default is decimal
@*/
.equ inputStatus_inputOk,			0
.equ inputStatus_inputNotOk,			1
.equ inputStatus_acceptedControlCharacter,	2

.equ operation_store, 0
.equ operation_display, 1
.equ operation_initAForMin, 2
.equ operation_initAForMax, 3
.equ operation_min, 4
.equ operation_max, 5
.equ operation_accumulate, 6
.equ operation_validateRange, 7

.equ terminalCommand_clearScreen, 0
.equ terminalCommand_cursorUp, 1
.equ terminalCommand_clearToEOL, 2
.equ terminalCommand_colorsError, 3
.equ terminalCommand_colorsNormal, 4

.equ q_reject,	0
.equ q_accept,	1

.equ r_reject,	0
.equ r_accept,	1

.equ inputBufferSize, 100

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ Some macros to make the code a little bit easier to read
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.macro mFunctionSetup
	push {fp}	@ setup local stack frame
	mov fp, sp

	push {lr}	@ preserve return address
	push {v1 - v7}	@ always preserve caller's locals

	push {a1 - a4}	@ Transfer scratch regs to...
	pop  {v1 - v4}	@ local variable regs
.endm

.macro mFunctionBreakdown argumentCount
	pop {v1 - v7}	@ restore caller's locals
	pop {lr}	@ restore return address

	mov sp, fp	@ restore caller's stack frame
	pop {fp}

	add sp, #\argumentCount * 4
.endm

.macro mTerminalCommand operation
	mov a1, \operation
	bl terminalCommand
.endm

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ calcSheetMinMax
@
@ stack:
@	+4: unused but required so main can call minmax
@		and sumavg with the same mechanism
@
@ registers:
@	a1: operations function
@	a2: spreadsheet address
@	a3: number of cells in sheet
@	a4: operation - min or max
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.section .text

calcSheetMinMax:
	mFunctionSetup	@ Setup stack frame and local variables

	cmp v4, #formula_minimum
	beq .L7_initForMin

	mov a4, #operation_initAForMax
	blx v1		@ init A for max

	mov a4, #operation_max
	b .L7_loopInit

.L7_initForMin:
	mov a1, #operation_initAForMin
	blx v1		@ init A for min

	mov a4, #operation_min

.L7_loopInit:
	mov v6, #0
	mov v5, r0	@ init from the initA result

.L7_loopTop:
	cmp v6, v3
	bhs .L7_loopExit

	mov a1, v5	@ current min/max
	mov a2, v2	@ sheet address
	mov a3, v6	@ cell index
	blx v1		@ get min/max between curr and a1
	mov v5, r0	@ save comparison result

.L7_loopBottom:
	add v6, #1
	b .L7_loopTop

.L7_loopExit:
	mov a1, v5	@ result
	mov a2, v2	@ sheet
	mov a3, v6	@ cell "index" -- result cell
	mov a4, #operation_store
	blx v1		@ store result

	mFunctionBreakdown 1	@ restore caller's locals and stack frame
	bx lr
	
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ calcSheetSumAverage
@
@ stack:
@	+4 POINTER TO overflow flag
@
@ registers:
@	a1 operations function
@	a2 spreadsheet base address
@	a3 number of cells in sheet
@	a4 sum/avg indicator
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.section .text

calcSheetSumAverage:
	mFunctionSetup	@ Setup stack frame and local variables

.L11_loopInit:
	mov v5, #0	@ accumulator
	mov v6, #0	@ cell index
	mov v7, #0	@ overflow indicator

.L11_loopTop:
	cmp v6, v3	@ end of loop?
	bhs .L11_loopExit

	mov a1, v5	@ accumulator
	mov a2, v2	@ sheet base address
	mov a3, v6	@ cell index
	mov a4, #operation_accumulate
	blx v1		@ accumulate sum 
	mov v5, r0	@ track accumulator
	orr v7, r1	@ track overflow flag over entire sheet

.L11_loopBottom:
	add v6, #1
	b .L11_loopTop

.L11_loopExit:
	mov a1, v5	@ sum
	cmp v4, #formula_sum
	beq .L11_storeResult

	mov a2, v3	@ denominator for average
	bl divide	@ result in r0

.L11_storeResult:
	mov a2, v2	@ spreadsheet
	mov a3, v6	@ cell "index" -- just past main sheet is result cell
	mov a4, #operation_store
	blx v1		@ store result

	ldr r0, [fp, #4]	@ r0 -> caller's overflow flag
	str v7, [r0]		@ set caller's overflow flag for entire sheet

.L11_epilogue:
	mFunctionBreakdown 1	@ restore caller's locals and stack frame
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ convertBitStringToNumber 
@
@	a1 string to convert
@	a2 data width in bytes
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
convertBitStringToNumber:
	mFunctionSetup	@ Setup stack frame and local variables

	rDataWidthInBytes	.req r1
	rNumberOfBitsToCapture	.req r2
	rMaxDigitsAllowed	.req r3
	rStringToConvert	.req v1
	rBinaryDigitCounter	.req v2
	rDigitTempStore		.req v3
	rLoopCounter		.req v4
	rBitsBetweenUnderscores	.req v5
	rFoundFirstUnderscore	.req v6
	rAccumulator		.req v7
	rFirstSigfigFound	.req ip

	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@@@ All set up-- meat of the function starts here
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

.L17_loopInit:
	mov a1, rStringToConvert
	bl strlen
	mov rNumberOfBitsToCapture, r0

	mov rMaxDigitsAllowed, rDataWidthInBytes, lsl #3
	mov rFoundFirstUnderscore, #0
	mov rBinaryDigitCounter, #0
	mov rDigitTempStore, #0
	mov rBitsBetweenUnderscores, #0
	mov rAccumulator, #0
	mov rLoopCounter, #0
	mov rFirstSigfigFound, #0

.L17_loopTop:
	cmp rLoopCounter, rNumberOfBitsToCapture
	bhs .L17_loopExit

					@ get current digit from string
	ldrb rDigitTempStore, [rStringToConvert, rLoopCounter]

	cmp rDigitTempStore, #'_'
	bne .L17_doneWithUnderscoreCheck

	cmp rFoundFirstUnderscore, #1
	beq .L17_requireFullNybbleBetweenUnderscores

	mov rFoundFirstUnderscore, #1	@ start counting from this underscore
	mov rBitsBetweenUnderscores, #0	@ will require full nybbles in between
	b .L17_loopBottom

.L17_requireFullNybbleBetweenUnderscores:
	tst rBitsBetweenUnderscores, rBitsBetweenUnderscores
	beq .L17_badCharacter		@ don't allow consecutive underscores

	tst rBitsBetweenUnderscores, #4 - 1	@ only complete nybbles...
	bne .L17_badCharacter			@ allowed between underscores
	b .L17_loopBottom			@ underscore ok--go to next digit

.L17_doneWithUnderscoreCheck:
	sub rDigitTempStore, #'0'	@ make it a real 0 or 1
	cmp rDigitTempStore, #1
	bhi .L17_badCharacter

	cmp rDigitTempStore, #0		@ check for first sigfig
	bne .L17_processingSigfigs

	cmp rFirstSigfigFound, #1
	beq .L17_processingSigfigs

	sub rNumberOfBitsToCapture, #1	@ if it's a leading zero, then one...
	add rStringToConvert, #1	@ less bit to capture
	b .L17_loopTop

.L17_processingSigfigs:
	mov rFirstSigfigFound, #1
	add rBinaryDigitCounter, #1	@ track number of bits total
	add rBitsBetweenUnderscores, #1	@ track number of inter-uscore bits

	lsl rAccumulator, #1			@ make room for the new bit
	orr rAccumulator, rDigitTempStore	@ store the new bit

.L17_loopBottom:
	add rLoopCounter, #1
	b .L17_loopTop

.L17_loopExit:
	cmp rFoundFirstUnderscore, #1
	bne .L17_checkMaxDigits

	tst rBitsBetweenUnderscores, rBitsBetweenUnderscores
	beq .L17_badCharacter	@ in case user enters '_' and nothing else

	tst rBitsBetweenUnderscores, #4 - 1	@ only complete nybbles...
	bne .L17_badCharacter			@ allowed between underscores

.L17_checkMaxDigits:
	mov r0, rAccumulator		@ default to everything ok
	mov r1, #inputStatus_inputOk
	cmp rBinaryDigitCounter, rMaxDigitsAllowed
	bls .L17_epilogue

.L17_badCharacter:
	mov r1, #inputStatus_inputNotOk

.L17_epilogue:
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@@@ All done. Undefine register synonyms and
	@@@ restore caller's variables and stack frame. 
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

	.unreq rAccumulator
	.unreq rDataWidthInBytes
	.unreq rNumberOfBitsToCapture
	.unreq rMaxDigitsAllowed
	.unreq rFoundFirstUnderscore
	.unreq rBinaryDigitCounter
	.unreq rDigitTempStore
	.unreq rLoopCounter
	.unreq rBitsBetweenUnderscores
	.unreq rStringToConvert	
	.unreq rFirstSigfigFound

	mFunctionBreakdown 0	@ restore caller's locals and stack frame
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ convertHexStringToNumber 
@
@	a1 string to convert
@	a2 data width in bytes
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
convertHexStringToNumber:
	mFunctionSetup	@ Setup stack frame and local variables

	rFirstSigfigFound		.req r1
	rStringToConvert		.req v1
	rDataWidthInBytes		.req v2	@ used only once
	rMaxDigitsAllowed		.req v2	@ more permanent use
	rDigitTempStore			.req v3
	rLoopCounter			.req v4
	rAccumulator			.req v5
	rHexDigitCounter		.req v6
	rNumberOfNybblesToCapture	.req v7

	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@@@ All set up-- meat of the function starts here
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

.L23_loopInit:
	mov a1, rStringToConvert
	bl strlen
	mov rNumberOfNybblesToCapture, r0

	mov rFirstSigfigFound, #0
	mov rMaxDigitsAllowed, rDataWidthInBytes, lsl #1
	mov rHexDigitCounter, #0
	mov rDigitTempStore, #0
	mov rAccumulator, #0
	mov rLoopCounter, #0

.L23_loopTop:
	cmp rLoopCounter, rNumberOfNybblesToCapture
	bhs .L23_loopExit

					@ get current digit from string
	ldrb rDigitTempStore, [rStringToConvert, rLoopCounter]

	cmp rDigitTempStore, #'0'
	blo .L23_badCharacter
	cmp rDigitTempStore, #'9'
	bls .L23_numeric
	orr rDigitTempStore, #0x20	@ convert to lowercase
	cmp rDigitTempStore, #'a'
	blo .L23_badCharacter
	cmp rDigitTempStore, #'f'
	bhi .L23_badCharacter

	sub rDigitTempStore, #'a' - 10	@ convert alpha digit to actual number
	b .L23_processDigit

.L23_numeric:
	sub rDigitTempStore, #'0'	@ convert numeric digit to actual number

.L23_processDigit:
	cmp rDigitTempStore, #0
	bne .L23_significantDigit

	cmp rFirstSigfigFound, #1	@ ignore all leading zeros
	beq .L23_significantDigit

	add rStringToConvert, #1		@ skip the leading zero 
	sub rNumberOfNybblesToCapture, #1	@ one less digit to capture
	b .L23_loopTop

.L23_significantDigit:

	@@@
	@ more arm coolness -- shift accumulator left by one
	@ nybble, add the temp store into it, and store the
	@ result back into the accumulator. All in one instruction. Cool.
	@@@
	add rAccumulator, rDigitTempStore, rAccumulator, lsl #4 
	mov rFirstSigfigFound, #1	@ done with leading zeros
	add rHexDigitCounter, #1	@ track number of nybbles total

.L23_loopBottom:
	add rLoopCounter, #1
	b .L23_loopTop

.L23_loopExit:
	mov r0, rAccumulator
	mov r1, #inputStatus_inputOk
	cmp rHexDigitCounter, rMaxDigitsAllowed
	bls .L23_epilogue

.L23_badCharacter:
	mov r1, #inputStatus_inputNotOk

.L23_epilogue:
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@@@ All done. Undefine register synonyms and
	@@@ restore caller's variables and stack frame. 
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

	.unreq rAccumulator
	.unreq rDataWidthInBytes
	.unreq rNumberOfNybblesToCapture
	.unreq rMaxDigitsAllowed
	.unreq rHexDigitCounter
	.unreq rDigitTempStore
	.unreq rLoopCounter
	.unreq rFirstSigfigFound
	.unreq rStringToConvert	

	mFunctionBreakdown 0	@ restore caller's locals and stack frame
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ displayGetCellValueBinMenu
@
@ stack:
@	+4 test mode
@
@ registers:
@	a1 cell index
@	a2 data width in bytes
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.section .data

.L14_msgInstructionsTemplate:
	.ascii "Enter up to %d binary digits; underscores optional, but "
	.ascii "complete\nnybbles required after each: 11_1111 ok, but "
	.asciz "not 11_111 or 11_11_1111\n"

.L14_msgInstructionsLength = . - .L14_msgInstructionsTemplate

@@@@@@@@@
@ Buffer to contain the instructions with actual number inserted
@ in the %d. I had to do it this way because the runMenu function
@ wants the full string.
@@@@@@@@@
.L14_msgInstructions: .skip .L14_msgInstructionsLength 

.section .text
.align 3

displayGetCellValueBinMenu:
	mFunctionSetup	@ Setup stack frame and local variables

	ldr a1, =.L14_msgInstructions
	ldr a2, =.L14_msgInstructionsTemplate
	mov a3, v2, lsl #3	@ number of bits allowed for input
	bl sprintf

	ldr a1, =.L14_msgInstructions
	mov a2, v1	@ cell index
	mov a3, #'%'	@ prompt for binary
	bl runGetCellValueMenu

	mFunctionBreakdown 1	@ restore caller's locals and stack frame
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ displayGetCellValueDecMenu
@
@ stack:
@	+4 test mode
@
@ registers:
@	a1 cell index
@	a2 data width in bytes
@	a3 operations function
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.section .data

.L20_msgInstructionsTemplate:
	.asciz "Enter an integer from %d to %d\n"

.L20_msgInstructionsLength = . - .L20_msgInstructionsTemplate

@@@@@@@@@
@ Buffer to contain the instructions with actual number inserted
@ in the %d. I had to do it this way because the runMenu function
@ wants the full string. The 11 is to allow for the maximum
@ length of a 32-bit integer, digits plus sign
@@@@@@@@@
.L20_msgInstructions: .skip .L20_msgInstructionsLength + (2 * 11) 

.section .text
.align 3

displayGetCellValueDecMenu:
	mFunctionSetup	@ Setup stack frame and local variables

	rCellIndex		.req v1
	rDataWidthInBytes	.req v2
	rOperationsFunction	.req v3

	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@@@ Ready to roll
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

	mov a4, #operation_initAForMax
	blx rOperationsFunction
	mov v4, r0

	mov a4, #operation_initAForMin
	blx rOperationsFunction
	mov v5, r0

	ldr a1, =.L20_msgInstructions
	ldr a2, =.L20_msgInstructionsTemplate
	mov a3, v4	@ min
	mov a4, v5	@ max
	bl sprintf	@ r0 -> complete instructions string

	ldr a1, =.L20_msgInstructions
	mov a2, rCellIndex
	mov a3, #0	@ no prompt postfix for decimal
	bl runGetCellValueMenu

	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@@@ Restore caller's locals and stack frame
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

	.unreq rCellIndex
	.unreq rDataWidthInBytes
	.unreq rOperationsFunction

	mFunctionBreakdown 1	@ restore caller's locals and stack frame
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ displayGetCellValueHexMenu
@
@ stack:
@	+4 test mode
@
@ registers:
@	a1 cell index
@	a2 data width in bytes
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.section .data

.L21_msgInstructionsTemplate:
	.asciz "Enter up to %d (significant) hex digits\n" 

.L21_msgInstructionsLength = . - .L20_msgInstructionsTemplate

@@@@@@@@@
@ Buffer to contain the instructions with actual number inserted
@ in the %d. I had to do it this way because the runMenu function
@ wants the full string.
@@@@@@@@@
.L21_msgInstructions: .skip .L21_msgInstructionsLength

.section .text
.align 3

displayGetCellValueHexMenu:
	mFunctionSetup	@ Setup stack frame and local variables

	rCellIndex		.req v1
	rDataWidthInBytes	.req v2

	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@@@ All set up-- meat of the function starts here
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

	ldr a1, =.L21_msgInstructions
	ldr a2, =.L21_msgInstructionsTemplate
	mov a3, rDataWidthInBytes, lsl #1	@ max number of hex digits
	bl sprintf

	ldr a1, =.L21_msgInstructions
	mov a2, rCellIndex
	mov a3, #'$'
	bl runGetCellValueMenu

	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@@@ All done. Undefine register synonyms and
	@@@ restore caller's variables and stack frame. 
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	.unreq rCellIndex
	.unreq rDataWidthInBytes

	mFunctionBreakdown 1	@ restore caller's locals and stack frame
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ displaySheet()
@
@ stack:
@	+12 presentation mode
@	 +8 formula
@	 +4 overflow accumulator
@
@ registers:
@	a1 ops function
@	a2 spreadsheet data
@	a3 number of cells to display
@	a4 data width
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.section .data

.L1_msgSpreadsheetHeader:	.asciz "Simple spreadsheet\n"
.L1_cellNumber:			.asciz "%9d. "

.L1_msgFormula:	.asciz "%9s: "
.L1_fSum:	.asciz "Sum"
.L1_fAverage:	.asciz "Average"
.L1_fMinimum:	.asciz "Minimum"
.L1_fMaximum:	.asciz "Maximum"
.L1_formulas:	.word .L1_fSum, .L1_fAverage, .L1_fMinimum, .L1_fMaximum

.L1_msgDataWidth:	.asciz "%d-bit signed integer mode\n\n"
.L1_msgSpace:		.asciz " "
.L1_msgOverflow:	.asciz "[ERROR]"

.section .text
.align 3

displaySheet:
	mFunctionSetup	@ Setup stack frame and local variables

	ldr a1, =.L1_msgSpreadsheetHeader
	bl printf

	ldr a1, =.L1_msgDataWidth
	mov a2, v4, lsl #3	@ convert data width in bytes to width in bits
	bl printf

.L1_loopInit:
	mov v6, #0

.L1_loopTop:
	cmp v6, v3
	bhs .L1_loopExit

	ldr a1, =.L1_cellNumber
	add a2, v6, #1
	bl printf

	add a1, fp, #12	@ a1 -> presentation indicator
	ldr a1, [a1]	@ a1 = presentation indicator
	mov a2, v2	@ spreadsheet
	mov a3, v6	@ cell index
	mov a4, #operation_display
	blx v1		@ display current cell per data width 
	bl newline

.L1_loopBottom:
	add v6, v6, #1
	b .L1_loopTop

.L1_loopExit:
	bl newline

	add r1, fp, #8		@ r1 -> formula indicator
	ldr r1, [r1]		@ r1 = formula indicator
	ldr r0, =.L1_formulas
	add r0, r1, lsl #2	@ r0 -> formula message pointer
	ldr r1, [r0]		@ r1 -> formula message
	ldr r0, =.L1_msgFormula
	bl printf

	add a1, fp, #12	@ a1 -> presentation indicator
	ldr a1, [a1]	@ a1 = presentation indicator
	mov a2, v2	@ spreadsheet
	mov a3, v6	@ "index" of result cell 
	mov a4, #operation_display
	blx v1		@ display result cell per data width

	ldr r0, [fp, #4]	@ get overflow indicator
	cmp r0, #1
	bne .L1_checkedOverflow

	ldr a1, =.L1_msgSpace
	bl printf
	mTerminalCommand #terminalCommand_colorsError
	ldr a1, =.L1_msgOverflow
	bl printf
	mTerminalCommand #terminalCommand_colorsNormal

.L1_checkedOverflow:
	bl newline
	bl newline

	mFunctionBreakdown 3	@ restore caller's locals and stack frame
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ divide:
@	floating-point divide, store truncated result in r0
@
@	a1 numerator
@	a2 denominator
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
divide:
	vmov s0, a1
	vmov s1, a2
	vcvt.f32.s32 s0, s0
	vcvt.f32.s32 s1, s1
	vdiv.f32 s0, s0, s1
	vcvt.s32.f32 s0, s0
	vmov r0, s0
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ getCellToEdit
@
@ stack: 
@	+4 testMode
@
@ registers:
@	a1 lowest acceptable cell number
@	a2 highest acceptable cell number
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.section .data

.L12_msgInstructions:
	.asciz "Directions (enter 'Q' to quit, 'R' to return to the main menu):\n"
.L12_msgSeparator:
	.asciz "---------------------------------------------------------------\n"

.L12_msgSelectCell:
	.asciz "Select the cell to edit [%d, %d]\n"

.section .text
.align 3

getCellToEdit:
	mFunctionSetup	@ Setup stack frame and local variables

	ldr r0, =.L12_msgInstructions
	bl printf
	ldr r0, =.L12_msgSeparator
	bl printf

	ldr a1, =.L12_msgSelectCell
	mov a2, v1	@ min cell number
	mov a3, v2	@ max cell number
	bl printf

	bl promptForSelection

	ldr r0, [fp, #4]	@ test mode
	push {r0}
	mov a1, v1		@ min cell number
	mov a2, v2		@ max cell number
	mov a3, #q_accept	@ accept 'q' for quit
	mov a4, #r_accept	@ accept 'r' to go up a menu
	bl getMenuSelection

	mFunctionBreakdown 1	@ restore caller's locals and stack frame
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ getCellValueBin
@
@ stack:
@	+4 test mode
@
@ registers:
@	a1 operations function
@	a2 data width in bytes
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.section .data

.L16_getsBuffer:	.skip inputBufferSize	@ arbitrary and hopeful size

.section .text
.align 3

getCellValueBin:
	mFunctionSetup	@ Setup stack frame and local variables

	rTestMode		.req v1
	rOperationsFunction	.req v2
	rDataWidthInBytes	.req v3
	rFirstPass		.req v4

	ldr rTestMode, [fp, #4]

	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@@@ All set up-- meat of the function starts here
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

	mov rFirstPass, #1	@ cursor behavior different on first pass

.L16_tryAgain:
	ldr a1, =.L16_getsBuffer
	bl gets

	ldr r0, =.L16_getsBuffer
	ldrh r0, [r0]		@ get only 2 bytes to check for "q\0" or "r\0"
	orr r0, #0x20		@ make sure it's lowercase

	mov r1, #inputStatus_acceptedControlCharacter
	cmp r0, #'q'
	beq .L16_epilogue
	cmp r0, #'r'
	beq .L16_epilogue

	and r0, #0xFF		@ if in test mode, allow // comments in input
	cmp r0, #'/'
	bne .L16_inputFirstStep
	cmp rTestMode, #1
	beq .L16_tryAgain

.L16_inputFirstStep:
	ldr a1, =.L16_getsBuffer
	mov a2, rDataWidthInBytes
	bl convertBitStringToNumber

	cmp r1, #inputStatus_inputOk
	beq .L16_epilogue

	ldr a1, =.L16_getsBuffer
	mov a2, #'%'
	mov a3, rFirstPass
	bl sayYuck

	mov rFirstPass, #0
	b .L16_tryAgain

.L16_epilogue:
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@@@ Restore caller's locals and stack frame
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	.unreq rFirstPass
	.unreq rDataWidthInBytes
	.unreq rOperationsFunction
	.unreq rTestMode

	mFunctionBreakdown 1	@ restore caller's locals and stack frame
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ getCellValueDec
@
@ stack:
@	+4 test mode
@
@ registers:
@	a1 operations function
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

.section .data

.L19_getsBuffer:	.skip inputBufferSize
.L19_scanf:		.asciz "%d"
.L19_scanfResult:	.word 0

.section .text
.align 3

getCellValueDec:
	mFunctionSetup	@ Setup stack frame and local variables

	rOperationsFunction	.req v1
	rFirstPass		.req v2
	rTestMode		.req v3

	ldr rTestMode, [fp, #4]

	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@@@ All set up-- meat of the function starts here
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

	mov rFirstPass, #1	@ remember we're on the first pass

.L19_tryAgain:
	ldr a1, =.L19_getsBuffer
	bl gets

	ldr r0, =.L19_getsBuffer
	ldrh r0, [r0]		@ get only 2 bytes to check for "q\0" or "r\0"
	orr r0, #0x20		@ make sure it's lowercase

	mov r1, #inputStatus_acceptedControlCharacter
	cmp r0, #'q'
	beq .L19_epilogue
	cmp r0, #'r'
	beq .L19_epilogue

	and r0, #0xFF		@ if in test mode, allow // comments in input
	cmp r0, #'/'
	bne .L19_inputFirstStep
	cmp rTestMode, #1
	beq .L19_tryAgain

.L19_inputFirstStep:
	ldr a1, =.L19_getsBuffer
	ldr a2, =.L19_scanf
	ldr a3, =.L19_scanfResult
	bl sscanf

	ldr a1, =.L19_getsBuffer

.L19_skippingWhitespace:
	ldrb r1, [a1]
	cmp r1, #' '
	bhi .L19_foundNonWhitespace
	cmp r1, #0	@ null terminator--end of input
	beq .L19_yuck	@ nothing but whitespace? yuck!
	add a1, #1
	b .L19_skippingWhitespace

.L19_foundNonWhitespace:
	@ a1 -> first usable char in gets buffer
	ldr a2, =.L19_scanf
	ldr a3, =.L19_scanfResult
	ldr a3, [a3]
	bl matchInputToResult
	cmp r1, #inputStatus_inputNotOk
	beq .L19_yuck

	ldr a1, =.L19_scanfResult
	ldr a1, [a1]
	mov a4, #operation_validateRange
	blx rOperationsFunction	@ returns input status in r1

	cmp r1, #inputStatus_inputOk
	bne .L19_yuck
	ldr r0, =.L19_scanfResult
	ldr r0, [r0]
	b .L19_epilogue

.L19_yuck:
	ldr a1, =.L19_getsBuffer
	mov a2, #0
	mov a3, rFirstPass
	bl sayYuck

	mov rFirstPass, #0
	b .L19_tryAgain

	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@@@ All done. Undefine register synonyms and
	@@@ restore caller's variables and stack frame. 
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.L19_epilogue:

	.unreq rFirstPass
	.unreq rOperationsFunction
	.unreq rTestMode

	mFunctionBreakdown 1	@ restore caller's locals and stack frame
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ getCellValueHex
@
@ stack:
@	+4 test mode
@
@ registers:
@	a1 operations function
@	a2 data width in bytes
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.section .data

.L22_getsBuffer:	.skip inputBufferSize	@ arbitrary and hopeful size

.section .text
.align 3

getCellValueHex:
	mFunctionSetup	@ Setup stack frame and local variables

	rOperationsFunction	.req v1
	rDataWidthInBytes	.req v2
	rFirstPass		.req v3
	rTestMode		.req v4

	ldr rTestMode, [fp, #4]

	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@@@ All set up-- meat of the function starts here
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

	mov rFirstPass, #1	@ cursor behavior different on first pass

.L22_tryAgain:
	ldr a1, =.L22_getsBuffer
	bl gets

	ldr r0, =.L22_getsBuffer
	ldrh r0, [r0]		@ get only 2 bytes to check for "q\0" or "r\0"
	orr r0, #0x20		@ make sure it's lowercase

	mov r1, #inputStatus_acceptedControlCharacter
	cmp r0, #'q'
	beq .L22_epilogue
	cmp r0, #'r'
	beq .L22_epilogue

	and r0, #0xFF		@ if in test mode, allow // comments in input
	cmp r0, #'/'
	bne .L22_inputFirstStep
	cmp rTestMode, #1
	beq .L22_tryAgain

.L22_inputFirstStep:
	ldr a1, =.L22_getsBuffer
	mov a2, rDataWidthInBytes
	bl convertHexStringToNumber

	cmp r1, #inputStatus_inputOk
	beq .L22_epilogue

.L22_yuck:
	ldr a1, =.L22_getsBuffer
	mov a2, #'$'
	mov a3, rFirstPass
	bl sayYuck

	mov rFirstPass, #0
	b .L22_tryAgain
	
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@@@ All done. Undefine register synonyms and
	@@@ restore caller's variables and stack frame. 
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.L22_epilogue:
	.unreq rFirstPass
	.unreq rDataWidthInBytes
	.unreq rOperationsFunction
	.unreq rTestMode

	mFunctionBreakdown 1	@ restore caller's locals and stack frame
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ getFormula
@
@ stack: 
@	+4 testMode
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.section .data

.L8_msgInstructions:
	.asciz "Formula options (enter 'Q' to quit, 'R' to return to the main menu):\n"
.L8_msgSeparator:
	.asciz "--------------------------------------------------------------------\n"

.L8_moSum:	.asciz "Sum"
.L8_moAverage:	.asciz "Average"
.L8_moMinimum:	.asciz "Minimum"
.L8_moMaximum:	.asciz "Maximum"

.L8_menuOptions: .word .L8_moSum, .L8_moAverage, .L8_moMinimum, .L8_moMaximum
.equ .L8_menuOptionsCount, 4
.section .text
.align 3

getFormula:
	mFunctionSetup	@ Setup stack frame and local variables

	add r0, fp, #4	@ test mode
	ldr r0, [r0]
	mov r1, #q_accept
	mov r2, #r_accept
	push {r0}
	push {r1}
	push {r2}
	ldr a1, =.L8_msgInstructions
	ldr a2, =.L8_msgSeparator
	ldr a3, =.L8_menuOptions
	mov a4, #.L8_menuOptionsCount
	bl runMenu

	mFunctionBreakdown 1	@ restore caller's locals and stack frame
	bx lr
	
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ getNewValueForCell
@
@ stack: 
@	+4 testMode
@
@ registers:
@	a1 operations function
@	a2 cell index
@	a3 data width in bytes
@	a4 data presentation mode
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.section .data

.L13_jumpTable:
	.word displayGetCellValueBinMenu, getCellValueBin
	.word displayGetCellValueDecMenu, getCellValueDec
	.word displayGetCellValueHexMenu, getCellValueHex

.section .text
.align 3

getNewValueForCell:
	mFunctionSetup	@ Setup stack frame and local variables

	ldr r0, =.L13_jumpTable
	add r0, v4, lsl #3
	ldr v5, [r0]	@ menu for presentation mode
	add r0, #4
	ldr v6, [r0]	@ get value function for presentation mode

	ldr r0, [fp, #4]
	push {r0}	@ test mode
	mov a1, v2	@ cell index
	mov a2, v3	@ data width in bytes
	mov a3, v1	@ operations function
	blx v5		@ run the menu for this presentation mode

	add r0, fp, #4
	ldr r0, [r0]
	push {r0}	@ test mode
	mov a1, v1	@ operations function
	mov a2, v3	@ data width in bytes
	blx v6		@ get user input for this presentation mode

	mFunctionBreakdown 1	@ restore caller's locals and stack frame
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ getPresentation
@
@ stack: 
@	+4 testMode
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.section .data

.L9_msgInstructions:
	.asciz "Presentation options (enter 'Q' to quit, 'R' to return to the main menu):\n"
.L9_msgSeparator:
	.asciz "---------------------------------------------------------------------------\n"

.L9_moBinary:	.asciz "Binary"
.L9_moDecimal:	.asciz "Decimal"
.L9_moHex:	.asciz "Hexadecimal"

.L9_menuOptions: .word .L9_moBinary, .L9_moDecimal, .L9_moHex
.equ .L9_menuOptionsCount, 3
.section .text
.align 3

getPresentation:
	mFunctionSetup	@ Setup stack frame and local variables

	add r0, fp, #4	@ test mode
	ldr r0, [r0]
	mov r1, #q_accept
	mov r2, #r_accept
	push {r0}
	push {r1}
	push {r2}
	ldr a1, =.L9_msgInstructions
	ldr a2, =.L9_msgSeparator
	ldr a3, =.L9_menuOptions
	mov a4, #.L9_menuOptionsCount
	bl runMenu

	mFunctionBreakdown 1	@ restore caller's locals and stack frame
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ getMainSelection
@
@ stack: 
@	+4 testMode
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.section .data

.L5_msgInstructions:	.asciz "Options (enter 'Q' to quit):\n"
.L5_msgSeparator:	.asciz "----------------------------\n"

mo_editCell:		.asciz "Edit cell"
mo_changeFormula:	.asciz "Change formula"
mo_changeDataRep:	.asciz "Change data presentation"
mo_resetSpreadsheet:	.asciz "Reset spreadsheet"
mo_randomValues:	.asciz "Fill cells with random values"

menuOptions: .word mo_editCell, mo_changeFormula, mo_changeDataRep
		.word mo_resetSpreadsheet, mo_randomValues

.equ menuOptionsCount, 5

.section .text
.align 3

getMainSelection:
	push {lr}
	ldr r0, =testMode
	ldr r0, [r0]
	mov r1, #q_accept
	mov r2, #r_reject
	push {r0}
	push {r1}
	push {r2}
	ldr a1, =.L5_msgInstructions
	ldr a2, =.L5_msgSeparator
	ldr a3, =menuOptions
	mov a4, #menuOptionsCount
	bl runMenu
	pop {lr}
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ getMenuSelection
@
@ stack:
@	+4 test mode
@
@ registers:
@	a1 minimum acceptable input
@	a2 maximum acceptable input
@	a3 accept/reject 'q'
@	a4 accept/reject 'r'
@
@ returns:
@	r0 user input
@	r1 input status
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.section .data

.L2_getsBuffer:		.skip inputBufferSize
.L2_scanf:		.asciz "%d"
.L2_scanfResult:	.word 0

.section .text
.align 3

getMenuSelection:
	mFunctionSetup	@ Setup stack frame and local variables

	rMinimum	.req v1
	rMaximum	.req v2
	rQControl	.req v3
	rRControl	.req v4
	rTestMode	.req v5
	rFirstPass	.req v6

	ldr rTestMode, [fp, #4]

	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@@@ All set up-- meat of the function starts here
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

	mov rFirstPass, #1

.L2_tryAgain:
	ldr a1, =.L2_getsBuffer
	bl gets

	ldr r0, =.L2_getsBuffer
	ldrh r0, [r0]		@ get only 2 bytes to check for "q\0" or "r\0"
	orr r0, #0x20		@ make sure it's lowercase

	cmp r0, #'q'
	bne .L2_checkR

	cmp rQControl, #q_accept
	bne .L2_yuck	
	b .L2_acceptControlCharacter

.L2_checkR:
	cmp r0, #'r'
	bne .L2_notQnotR

	cmp rRControl, #r_accept
	bne .L2_yuck
	b .L2_acceptControlCharacter

.L2_notQnotR:
	and r0, #0xFF		@ if in test mode, allow // comments in input
	cmp r0, #'/'
	bne .L2_inputFirstStep
	cmp rTestMode, #1
	beq .L2_tryAgain

.L2_inputFirstStep:
	ldr a1, =.L2_getsBuffer
	ldr a2, =.L2_scanf
	ldr a3, =.L2_scanfResult
	bl sscanf

	ldr a1, =.L2_getsBuffer

.L2_skippingWhitespace:
	ldrb r1, [a1]
	cmp r1, #' '
	bhi .L2_foundNonWhitespace
	cmp r1, #0	@ null terminator--end of input
	beq .L2_yuck	@ nothing but whitespace? yuck!
	add a1, #1
	b .L2_skippingWhitespace

.L2_foundNonWhitespace:
	@ a1 -> first usable char in gets buffer
	ldr a2, =.L2_scanf
	ldr a3, =.L2_scanfResult
	ldr a3, [a3]
	bl matchInputToResult

	cmp r1, #inputStatus_inputOk
	bne .L2_yuck

	ldr r0, =.L2_scanfResult
	ldr r0, [r0]
	cmp r0, rMinimum	@ Check against min
	blo .L2_yuck

	cmp r0, rMaximum	@ Check against max
	bhi .L2_yuck

	mov r1, #inputStatus_inputOk
	b .L2_epilogue

.L2_yuck:
	ldr a1, =.L2_getsBuffer
	mov a2, #0		@ no prompt suffix for decimal input
	mov a3, rFirstPass	@ first pass indicator
	bl sayYuck
	mov rFirstPass, #0
	b .L2_tryAgain
 
.L2_acceptControlCharacter:
	mov r1, #inputStatus_acceptedControlCharacter

	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@@@ Restore caller's locals and stack frame
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	.unreq rMinimum
	.unreq rMaximum
	.unreq rQControl
	.unreq rRControl
	.unreq rTestMode
	.unreq rFirstPass

.L2_epilogue:
	mFunctionBreakdown 1	@ restore caller's locals and stack frame
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ getSpreadsheetSpecs
@
@ returns
@	r0 number of cells in spreadsheet
@	r1 cell width in bytes
@	r2 input status
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.equ minimumCellCount, 2
.equ maximumCellCount, 10

.section .data

msgEnterSpreadsheetSize:	.asciz "Enter the number of cells for the spreadsheet [2, 10], or 'Q' to quit\n"
msgDataWidthOptions:		.asciz "Data width options (enter 'Q' to quit):\n"
msgSeparator:			.asciz "---------------------------------------\n"
msgSelectDataWidth:		.asciz "\nSelect data width\n"

dwo8:	.asciz "8 bits - range is [-128, 127]"
dwo16:	.asciz "16 bits - range is [-32768, 32767]"
dwo32:	.asciz "32 bits - range is [-2147483648, 2147483647]"

.align 3
dataWidthOptions: .word dwo8, dwo16, dwo32
.equ numberOfDataWidthOptions, 3

.section .text

getSpreadsheetSpecs:
	mFunctionSetup	@ Setup stack frame and local variables

	rInputStatus		.req v1
	rNumberOfCells		.req v2
	rCellWidthInBytes	.req v3

	ldr r0, =msgEnterSpreadsheetSize
	bl printf
	ldr r0, =msgPrompt
	bl printf

	ldr r0, =testMode
	ldr r0, [r0]
	push {r0}
	mov a1, #minimumCellCount
	mov a2, #maximumCellCount
	mov a3, #q_accept
	mov a4, #r_accept
	bl getMenuSelection
	mov rNumberOfCells, r0
	mov rInputStatus, r1

	cmp rInputStatus, #inputStatus_acceptedControlCharacter
	beq epilogue

	bl newline

	ldr r0, =msgDataWidthOptions
	bl printf
	ldr r0, =msgSeparator
	bl printf

	ldr r0, =dataWidthOptions
	mov r1, #numberOfDataWidthOptions
	bl showList
	ldr r0, =msgSelectDataWidth
	bl printf
	ldr r0, =msgPrompt
	bl printf

	ldr r0, =testMode
	ldr r0, [r0]
	push {r0}
	mov a1, #1
	mov a2, #numberOfDataWidthOptions
	mov a3, #q_accept
	mov a4, #r_accept
	bl getMenuSelection
	mov rInputStatus, r1

	cmp rInputStatus, #inputStatus_acceptedControlCharacter
	beq epilogue

	sub r1, r0, #1				@ convert 1-based to 0-based
	mov r0, #1				@ to be shifted
	mov rCellWidthInBytes, r0, lsl r1	@ v2 = data width in bytes

epilogue:
	mov r0, rInputStatus
	mov r1, rNumberOfCells
	mov r2, rCellWidthInBytes

	.unreq rInputStatus
	.unreq rNumberOfCells
	.unreq rCellWidthInBytes

	mFunctionBreakdown 0	@ restore caller's locals and stack frame
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ matchInputToResult
@
@	a1 what the user entered
@	a2 format string used on the user input
@	a3 the value that resulted from the scanf
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.section .data

.L24_sprintfBuffer: .skip inputBufferSize

.section .text
.align 3

matchInputToResult:
	mFunctionSetup	@ Setup stack frame and local variables

	rOriginalUserInput	.req v1
	rFormatString		.req v2
	rScanfResult		.req v3

	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@@@ All set up-- meat of the function starts here
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

	ldr a1, =.L24_sprintfBuffer
	mov a2, rFormatString
	mov a3, rScanfResult
	bl sprintf

	mov r0, rOriginalUserInput

.L24_skipLeadingZeros:	@ caller already skipped whitespace
	ldrb r1, [r0]
	cmp r1, #'0'
	bne .L24_foundMeatOfUserInput

	ldrb r1, [r0, #1]		@ if following char is...
	cmp r1, #0			@ null terminator, accept final...
	beq .L24_foundMeatOfUserInput	@ char as whole input

	add r0, #1			@ leading zero--keep looking
	b .L24_skipLeadingZeros
	
.L24_foundMeatOfUserInput:
	mov a2, r0			@ first usable char of original input
	ldr a1, =.L24_sprintfBuffer	@ result of sprintf using that input
	bl strcmp

	mov r1, #inputStatus_inputOk
	cmp r0, #0
	movne r1, #inputStatus_inputNotOk
	b .L24_epilogue

	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@@@ All done. Undefine register synonyms and
	@@@ restore caller's variables and stack frame. 
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

	.unreq rOriginalUserInput
	.unreq rFormatString
	.unreq rScanfResult

.L24_epilogue:
	pop {v1 - v7}	@ restore caller's locals
	pop {lr}	@ restore return address

	mov sp, fp	@ restore caller's stack frame
	pop {fp}

	bx lr		@ return

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ newline
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.section .data
msgNewline: .asciz "\n"

.section .text
newline:
	push {lr}
	ldr r0, =msgNewline
	bl printf
	pop {pc}

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ operations8
@
@	a1 = accumulator/source
@		except for operation_display -- there it's presentation mode
@	a2 = sheet base address
@	a3 = multi-purpose --
@		usually index of target cell
@	a4 = operation
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.section .data

.ops8_formatDec: .asciz "% 4d"
.ops8_formatHex: .asciz "$%02X"

.ops8_jumpTable:	.word .ops8_store, .ops8_display, .ops8_initAForMin
			.word .ops8_initAForMax, .ops8_min, .ops8_max
			.word .ops8_accumulate, .ops8_validateRange

.section .text
.align 3	@ in case there's an issue with jumping to this via register

operations8:
	mFunctionSetup	@ Setup stack frame and local variables

	rOperationResult	.req r0
	rOverflowIndicator	.req r1
	rInputStatus		.req r1
	rCellContents		.req r1
	rOperand		.req v1
	rAccumulator		.req v1
	rPresentationMode	.req v1
	rSheetBaseAddress	.req v2
	rCellIndex		.req v3
	rOperation		.req v4

	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@@@ All set up-- meat of the function starts here
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

	ldr r0, =.ops8_jumpTable
	ldr r0, [r0, rOperation, lsl #2]
	bx r0

.ops8_validateRange:
	mov rInputStatus, #inputStatus_inputNotOk
	mov r0, #0x80		@ minimum 8-bit value
	sxtb r0, r0		@ sign-extend
	cmp rOperand, r0
	blt .ops8_epilogue
	cmp rOperand, #0x7F	@ maximum 8-bit value
	movle rInputStatus, #inputStatus_inputOk
	b .ops8_epilogue

.ops8_accumulate:
	ldrsb rCellContents, [rSheetBaseAddress, rCellIndex]
	add rOperationResult, rAccumulator, rCellContents

	@@@
	@ notify caller of overflow status relative
	@ to bottom byte of the operation result
	@@@

	mov rOverflowIndicator, #0	@ default to no overflow
	and r2, rOperationResult, #0xFF	@ get bottom byte
	sxtb r2, r2			@ sign-extend r2
	cmp r2, rOperationResult
	movne rOverflowIndicator, #1	@ not equal means overflow

	b .ops8_epilogue

.ops8_display:
	ldrsb rCellContents, [rSheetBaseAddress, rCellIndex]

	cmp rPresentationMode, #presentation_bin
	beq .ops8_displayBin

	ldr a1, =.ops8_formatDec	@ default to decimal
	cmp rPresentationMode, #presentation_hex
	ldreq a1, =.ops8_formatHex	@ cool arm conditional execution
	andeq a2, #0xFF			@ also use only bottom byte if hex
	bl printf
	b .ops8_epilogue

.ops8_displayBin:
	mov a1, rCellContents	@ a1 = data to display
	mov a2, #1		@ a2 = number of bytes
	bl showNumberAsBin
	b .ops8_epilogue

.ops8_initAForMax:
	mov rOperationResult, #0x80		@ lowest possible 8-bit signed value
	sxtb rOperationResult, rOperationResult	@ sign-extend
	b .ops8_epilogue

.ops8_initAForMin:
	mov rOperationResult, #0x7F		@ highest possible 8-bit signed value
	b .ops8_epilogue

.ops8_max:
	ldrsb rCellContents, [rSheetBaseAddress, rCellIndex]
	mov rOperationResult, rOperand		@ current max
	cmp rOperand, rCellContents
	movlt rOperationResult, rCellContents	@ new max if operand < cell value
	b .ops8_epilogue

.ops8_min:
	ldrsb rCellContents, [rSheetBaseAddress, rCellIndex]
	mov rOperationResult, rOperand		@ current min
	cmp rOperand, rCellContents
	movgt rOperationResult, rCellContents	@ new min if operand > cell value
	b .ops8_epilogue

.ops8_store:
	strb rOperand, [rSheetBaseAddress, rCellIndex]
	b .ops8_epilogue

	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@@@ All done. Undefine register synonyms and
	@@@ restore caller's variables and stack frame. 
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

	.unreq rOperationResult
	.unreq rOverflowIndicator
	.unreq rInputStatus
	.unreq rCellContents
	.unreq rOperand
	.unreq rAccumulator
	.unreq rPresentationMode
	.unreq rSheetBaseAddress
	.unreq rCellIndex
	.unreq rOperation

.ops8_epilogue:
	mFunctionBreakdown 0	@ restore caller's locals and stack frame
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ operations16
@
@	a1 = accumulator/source
@		except for operation_display -- there it's presentation mode
@	a2 = sheet base address
@	a3 = multi-purpose --
@		usually index of target cell
@	a4 = operation
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.section .data

.ops16_formatDec: .asciz "% 6d"
.ops16_formatHex: .asciz "$%04X"

.ops16_jumpTable:	.word .ops16_store, .ops16_display, .ops16_initAForMin
			.word .ops16_initAForMax, .ops16_min, .ops16_max
			.word .ops16_accumulate, .ops16_validateRange

.section .text
.align 3	@ in case there's an issue with jumping to this via register

operations16:
	mFunctionSetup	@ Setup stack frame and local variables

	rOperationResult	.req r0
	rOverflowIndicator	.req r1
	rInputStatus		.req r1
	rCellContents		.req r1
	rOperand		.req v1
	rAccumulator		.req v1
	rPresentationMode	.req v1
	rSheetBaseAddress	.req v2
	rCellIndex		.req v3
	rOperation		.req v4
	rHwordMask		.req v5
	rMinimum		.req v6
	rMaximum		.req v7

	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@@@ All set up-- meat of the function starts here
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

	mov r0, #0
	sub r0, #1	@ r0 = 0xFFFFFFFF
	lsr rHwordMask, r0, #16	@ rHwordMask = 0xFFFF
	lsr rMaximum, r0, #17	@ rMaximum = 0x7FFF
	lsl rMinimum, r0, #15	@ rMinimum = 0xFFFF8000

	ldr r0, =.ops16_jumpTable
	ldr r0, [r0, rOperation, lsl #2]
	bx r0

.ops16_validateRange:
	mov rInputStatus, #inputStatus_inputNotOk
	cmp rOperand, rMinimum
	blt .ops16_epilogue
	cmp rOperand, rMaximum
	movle rInputStatus, #inputStatus_inputOk
	b .ops16_epilogue

.ops16_accumulate:
	add r0, rSheetBaseAddress, rCellIndex, lsl #1
	ldrsh rCellContents, [r0]
	add rOperationResult, rAccumulator, rCellContents

	@@@
	@ notify caller of overflow status relative
	@ to bottom hword of the operation result
	@@@

	mov rOverflowIndicator, #0		@ default to no overflow
	and r2, rOperationResult, rHwordMask	@ get bottom byte
	sxth r2, r2				@ sign-extend r2
	cmp r2, rOperationResult
	movne rOverflowIndicator, #1		@ not equal means overflow

	b .ops16_epilogue

.ops16_display:
	add r0, rSheetBaseAddress, rCellIndex, lsl #1
	ldrsh rCellContents, [r0]

	cmp rPresentationMode, #presentation_bin
	beq .ops16_displayBin

	ldr a1, =.ops16_formatDec	@ default to decimal
	cmp rPresentationMode, #presentation_hex
	ldreq a1, =.ops16_formatHex	@ cool arm conditional execution
	andeq a2, rHwordMask		@ also use only bottom hword if hex
	bl printf
	b .ops16_epilogue

.ops16_displayBin:
	mov a1, rCellContents	@ a1 = data to display
	mov a2, #2		@ a2 = number of bytes
	bl showNumberAsBin
	b .ops16_epilogue

.ops16_initAForMax:
	mov rOperationResult, rMinimum	@ min signed 16-bit value
	b .ops16_epilogue

.ops16_initAForMin:
	mov rOperationResult, rMaximum	@ max signed 16-bit value
	b .ops16_epilogue	

.ops16_max:
	add r0, rSheetBaseAddress, rCellIndex, lsl #1
	ldrsh rCellContents, [r0]
	mov rOperationResult, rOperand		@ current max
	cmp rOperand, rCellContents
	movlt rOperationResult, rCellContents	@ new max if operand < cell value
	b .ops16_epilogue

.ops16_min:
	add r0, rSheetBaseAddress, rCellIndex, lsl #1
	ldrsh rCellContents, [r0]
	mov rOperationResult, rOperand		@ current min
	cmp rOperand, rCellContents
	movgt rOperationResult, rCellContents	@ new min if operand > cell value
	b .ops16_epilogue

.ops16_store:
	add r0, rSheetBaseAddress, rCellIndex, lsl #1
	strh rOperand, [r0]
	b .ops16_epilogue

	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@@@ All done. Undefine register synonyms and
	@@@ restore caller's variables and stack frame. 
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

	.unreq rOperationResult
	.unreq rOverflowIndicator
	.unreq rInputStatus
	.unreq rCellContents
	.unreq rOperand
	.unreq rAccumulator
	.unreq rPresentationMode
	.unreq rSheetBaseAddress
	.unreq rCellIndex
	.unreq rOperation
	.unreq rHwordMask
	.unreq rMinimum
	.unreq rMaximum

.ops16_epilogue:
	mFunctionBreakdown 0	@ restore caller's locals and stack frame
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ operations32
@
@	a1 = accumulator/source
@		except for operation_display -- there it's presentation mode
@	a2 = sheet base address
@	a3 = multi-purpose --
@		usually index of target cell
@	a4 = operation
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.section .data

.ops32_formatDec: .asciz "% 11d"
.ops32_formatHex: .asciz "$%08X"

.ops32_jumpTable:	.word .ops32_store, .ops32_display, .ops32_initAForMin
			.word .ops32_initAForMax, .ops32_min, .ops32_max
			.word .ops32_accumulate, .ops32_validateRange

.section .text
.align 3	@ in case there's an issue with jumping to this via register

operations32:
	mFunctionSetup	@ Setup stack frame and local variables

	rOperationResult	.req r0
	rInputStatus		.req r1
	rCellContents		.req r1
	rOverflowIndicator	.req r2
	rOperand		.req v1
	rAccumulator		.req v1
	rPresentationMode	.req v1
	rSheetBaseAddress	.req v2
	rCellIndex		.req v3
	rOperation		.req v4
	rWordMask		.req v5
	rMinimum		.req v6
	rMaximum		.req v7

	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@@@ All set up-- meat of the function starts here
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

	mov r0, #0
	sub r0, #1	@ r0 = 0xFFFFFFFF
	mov rWordMask, r0	@ rWordMask = 0xFFFFFFFF
	lsr rMaximum, r0, #1	@ rMaximum = 0x7FFFFFFF
	lsl rMinimum, r0, #31	@ rMinimum = 0x80000000

	ldr r0, =.ops32_jumpTable
	ldr r0, [r0, rOperation, lsl #2]
	bx r0

.ops32_validateRange:
	mov rInputStatus, #inputStatus_inputNotOk
	cmp rOperand, rMinimum
	blt .ops32_epilogue
	cmp rOperand, rMaximum
	movle rInputStatus, #inputStatus_inputOk
	b .ops32_epilogue

.ops32_accumulate:
	mov rOverflowIndicator, #0	@ default to no overflow
	add r0, rSheetBaseAddress, rCellIndex, lsl #2
	ldr rCellContents, [r0]
	adds rOperationResult, rAccumulator, rCellContents
	orrvs rOverflowIndicator, #1
	mov r1, rOverflowIndicator	@ for caller
	b .ops32_epilogue

.ops32_display:
	add r0, rSheetBaseAddress, rCellIndex, lsl #2
	ldr rCellContents, [r0]

	cmp rPresentationMode, #presentation_bin
	beq .ops32_displayBin

	ldr a1, =.ops32_formatDec	@ default to decimal
	cmp rPresentationMode, #presentation_hex
	ldreq a1, =.ops32_formatHex	@ cool arm conditional execution
	bl printf
	b .ops32_epilogue

.ops32_displayBin:
	mov a1, rCellContents	@ a1 = data to display
	mov a2, #4		@ a2 = number of bytes
	bl showNumberAsBin
	b .ops32_epilogue

.ops32_initAForMax:
	mov rOperationResult, rMinimum	@ min signed 32-bit value
	b .ops32_epilogue

.ops32_initAForMin:
	mov rOperationResult, rMaximum	@ max signed 32-bit value
	b .ops32_epilogue	

.ops32_max:
	add r0, rSheetBaseAddress, rCellIndex, lsl #2
	ldr rCellContents, [r0]
	mov rOperationResult, rOperand		@ current max
	cmp rOperand, rCellContents
	movlt rOperationResult, rCellContents	@ new max if operand < cell value
	b .ops32_epilogue

.ops32_min:
	add r0, rSheetBaseAddress, rCellIndex, lsl #2
	ldr rCellContents, [r0]
	mov rOperationResult, rOperand		@ current min
	cmp rOperand, rCellContents
	movgt rOperationResult, rCellContents	@ new min if operand > cell value
	b .ops32_epilogue

.ops32_store:
	add r0, rSheetBaseAddress, rCellIndex, lsl #2
	str rOperand, [r0]
	b .ops32_epilogue

	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@@@ All done. Undefine register synonyms and
	@@@ restore caller's variables and stack frame. 
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

	.unreq rOperationResult
	.unreq rOverflowIndicator
	.unreq rInputStatus
	.unreq rCellContents
	.unreq rOperand
	.unreq rAccumulator
	.unreq rPresentationMode
	.unreq rSheetBaseAddress
	.unreq rCellIndex
	.unreq rOperation
	.unreq rWordMask
	.unreq rMinimum
	.unreq rMaximum

.ops32_epilogue:
	mFunctionBreakdown 0	@ restore caller's locals and stack frame
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ promptForSelection 
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.section .data

msgEnterSelection:	.asciz "Enter a selection\n"
msgPrompt:		.asciz "-> "

.section .text
.align 3

promptForSelection:
	push {lr}
	bl newline
	ldr r0, =msgEnterSelection
	bl printf
	ldr r0, =msgPrompt
	bl printf
	pop {pc}

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ randomFill
@
@	a1 = operations function
@	a2 = sheet base address
@	a3 = cell count
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
randomFill:
	mFunctionSetup	@ Setup stack frame and local variables

.L6_loopInit:
	mov v6, #0

.L6_loopTop:
	cmp v6, v3
	bhs .L6_loopExit

	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@ Something strange happens with rand that causes me to get all
	@ positive values when working with 16-bit cells. The ror is there to
	@ mix things up a bit and hopefully give me both positive and negative
	@ values in a random, or at least apparently random distribution. 
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	bl rand		@ returns rand in a1 (r0)
	ror a1, #1	@ because I want a full range
	mov a2, v2	@ sheet base address
	mov a3, v6	@ current cell index
	mov r3, #operation_store
	blx v1		@ store a1

.L6_loopBottom:
	add v6, #1
	b .L6_loopTop

.L6_loopExit:
	mFunctionBreakdown 0	@ restore caller's locals and stack frame
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ resetSheet
@
@	a1 = operations function
@	a2 = sheet base address
@	a3 = cell count
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.section .text

	rOperationsFunction	.req v1
	rSheetAddress		.req v2
	rCellCount		.req v3
	rLoopCounter		.req v4

resetSheet:
	mFunctionSetup	@ Setup stack frame and local variables

.L4_init:
	mov rLoopCounter, #0

.L4_top:
	cmp rLoopCounter, rCellCount
	bhs .L4_loopExit

	mov a1, #0		@ data to store
	mov a2, rSheetAddress	@ base address of array
	mov a3, rLoopCounter	@ index of target cell
	mov a4, #operation_store
	blx rOperationsFunction	@ store the zero

.L4_loopBottom:
	add rLoopCounter, #1
	b .L4_top

.L4_loopExit:
	mFunctionBreakdown 0	@ restore caller's locals and stack frame
	bx lr

	.unreq rOperationsFunction
	.unreq rSheetAddress
	.unreq rCellCount
	.unreq rLoopCounter

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ runGetCellValueMenu
@
@	a1 instructions
@	a2 cell index
@	a3 prompt postfix
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.section .data

.L15_msgDirections:
	.ascii "Directions (enter 'Q' to quit, 'R' to return "
	.asciz "to cell selection menu):\n"

.L15_msgSeparator:
	.ascii "---------------------------------------------"
	.asciz "------------------------\n"

.L15_msgNewValue: .asciz "\nNew value for cell %d\n-> "

.section .text
.align 3

runGetCellValueMenu:
	mFunctionSetup	@ Setup stack frame and local variables

	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
	@@@ All set up -- meat of function begins here
	@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

	ldr a1, =.L15_msgDirections
	bl printf
	ldr a1, =.L15_msgSeparator
	bl printf

	mov a1, v1	@ specific instructions
	bl printf

	ldr a1, =.L15_msgNewValue
	mov a2, v2	@ cell index
	bl printf

	mov a1, v3	@ prompt postfix
	cmp a1, #0	@ decimal has no prompt postfix
	blne putchar	@ awesome arm conditional instruction

	mFunctionBreakdown 0	@ restore caller's locals and stack frame
	bx lr
	
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ runMenu
@
@ stack:
@	testMode
@	q accept/reject
@	r accept/reject
@
@ registers:
@	r0/4 instructions message
@	r1/5 separator
@	r2/6 menu options table
@	r3/7 number of options in table
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
runMenu:
	mFunctionSetup	@ Setup stack frame and local variables

	mov r0, r4	@ instructions
	bl printf
	mov r0, r5	@ separator
	bl printf

	mov r0, r6	@ menu options
	mov r1, r7	@ number of options available
	bl showList

	bl promptForSelection

	ldr r0, [fp, #12]	@ test mode
	push {r0}
	mov a1, #1		@ minimum
	mov a2, v4		@ maximum
	ldr a3, [fp, #8]	@ q accept/reject
	ldr a4, [fp, #4]	@ r accept/reject
	bl getMenuSelection

	mFunctionBreakdown 3	@ restore caller's locals and stack frame
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ sayYuck
@
@	a1 string with yucky value
@	a2 prompt suffix
@	a3 skip second cursor-up
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.section .data

.L18_yuckMessage:	.asciz "Uhh... %s? Yuck! Try again!\n-> "

.section .text
.align 3

sayYuck:
	mFunctionSetup	@ Setup stack frame and local variables

	mTerminalCommand #terminalCommand_cursorUp
	mTerminalCommand #terminalCommand_clearToEOL

	cmp v3, #1	@ skip second cursor up?
	beq .L18_cursingComplete

	mTerminalCommand #terminalCommand_cursorUp
	mTerminalCommand #terminalCommand_clearToEOL

.L18_cursingComplete:
	ldr a1, =.L18_yuckMessage
	mov a2, v1
	bl printf

	cmp v2, #0	@ dec mode doesn't have a prompt suffix
	beq .L18_epilogue

	mov a1, v2
	bl putchar

.L18_epilogue:
	mFunctionBreakdown 0	@ restore caller's locals and stack frame
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ showList
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.section .data

msgListElement: .asciz "%d. %s\n"

.section .text

showList:
	mFunctionSetup	@ Setup stack frame and local variables

	mov r4, r0	@ list offset
	mov r5, r1	@ number of elements

.L3_loopInit:
	mov r6, #0

.L3_loopTop:
	add r6, r6, #1
	ldr r0, =msgListElement
	mov r1, r6
	ldr r2, [r4]
	bl printf

	add r4, r4, #4
	subs r5, r5, #1
	bne .L3_loopTop

	mFunctionBreakdown 0	@ restore caller's locals and stack frame
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ showNumberAsBin 
@
@	a1 number to show
@	a2 number of bytes
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
showNumberAsBin:
	mFunctionSetup	@ Setup stack frame and local variables

.L10_loopInit:
	mov a1, #'%'
	bl putchar

	mov r0, #4
	sub v3, r0, v2	@ width in bytes - 4: 1, 2, 4 becomes 3, 2, 0
	lsl v3, #3	@ 3, 2, 0 becomes 24, 16, 0 to shift val to top of reg
	lsl v1, v3	@ shift value up to top of register

	mov v4, #4 - 1	@ for testing whether to show underscore
	mov v3, #1	@ remember we're on the first pass
	lsl v2, #3	@ width in bytes 1, 2, 4 -> width in bits 8, 16, 32

.L10_loopTop:
	cmp v2, #0
	beq .L10_loopExit

	tst v2, v4	@ time for underscore?
	bne .L10_showbit

	cmp v3, #1	@ no underscore on first pass through
	beq .L10_showbit

	mov a1, #'_'
	bl putchar

.L10_showbit:
	mov a1, #'0'	@ default to displaying zero
	lsls v1, #1	@ cool arm conditional instruction coming up
	movcs a1, #'1'	@ move 1 if carry set by above instruction -- cool 
	bl putchar

.L10_loopBottom:
	mov v3, #0	@ no longer on first pass
	sub v2, #1
	b .L10_loopTop

.L10_loopExit:
	mFunctionBreakdown 0	@ restore caller's locals and stack frame
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ terminalCommand
@
@	a1 the command to send
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.section .data

.L25_cmdClearScreen:	.asciz "\033[2J\033[H"
.L25_msgCursorUp:	.asciz "\033[A"
.L25_msgClearToEOL:	.asciz "\033[K"
.L25_colorsError:	.asciz "\033[37;41m"
.L25_colorsNormal:	.asciz "\033[37;40m"

.L25_commands:
	.word .L25_cmdClearScreen, .L25_msgCursorUp, .L25_msgClearToEOL
	.word .L25_colorsError, .L25_colorsNormal

.section .text

terminalCommand:
	push {lr}
	ldr r1, =.L25_commands
	ldr a1, [r1, a1, lsl #2]	@ the command to send
	bl printf
	pop {lr}
	bx lr

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ main
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
.ltorg	@ not too clear on this, but this directive does something
	@ with data sections that keeps the data close enough to the
	@ code that is working on the data. Learn more about this.

.section .data

.equ presentation_bin, 0
.equ presentation_dec, 1
.equ presentation_hex, 2

testMode:			.word 0
cellToEdit:			.word 0
overflowFlag:			.word 0

.align 8

actionsJumpTable:
		.word actionEditCell
		.word actionChangeFormula
		.word actionChangePresentation
		.word actionResetSpreadsheet
		.word actionFillRandom

operationsJumpTable:	.word operations8, operations16, operations32

.equ menuMode_main,			0
.equ menuMode_changeFormula,		1
.equ menuMode_changePresentation,	2
.equ menuMode_getCellToEdit,		3
.equ menuMode_getNewValueForCell,	4

menuModeJumpTable:
		.word menuMain
		.word menuChangeFormula
		.word menuChangePresentation
		.word menuGetCellToEdit
		.word menuGetNewValueForCell

.equ formula_sum,	0
.equ formula_average,	1
.equ formula_minimum,	2
.equ formula_maximum,	3

formulaJumpTable:
		.word calcSheetSumAverage
		.word calcSheetSumAverage
		.word calcSheetMinMax
		.word calcSheetMinMax

msgGreeting:	.asciz "Greetings, data analyzer.\n\n"
msgSetupIntro:	.asciz "To set up, enter spreadsheet size and data width.\n"
msgByeNow:	.asciz "'Bye now!\n"

.section .text
.global main

	rMenuMode			.req v1
	rFormula			.req v2
	rPresentation			.req v3
	rOperationsFunction		.req v4
	rCellWidthInBytes		.req v5
	rNumberOfCellsInSpreadsheet	.req v6
	rSpreadsheetAddress		.req v7

main:
	mov r1, #1	@ default to test mode
	cmp r0, #1
	moveq r1, #0	@ if only one cmdline arg (prog name), not test mode
	ldr r0, =testMode
	str r1, [r0]	@ remember which mode

	mov a1, #0
	bl time
	bl srand

	mTerminalCommand #terminalCommand_colorsNormal
	mTerminalCommand #terminalCommand_clearScreen

greet:
	ldr a1, =msgGreeting
	bl printf

showSetupIntro:
	mov rMenuMode, #menuMode_main
	mov rFormula, #formula_sum
	mov rPresentation, #presentation_dec

	ldr a1, =msgSetupIntro
	bl printf

	bl getSpreadsheetSpecs
	mov rNumberOfCellsInSpreadsheet, r1
	mov rCellWidthInBytes, r2

	cmp r0, #inputStatus_acceptedControlCharacter
	beq actionQuit 

	ldr r0, =operationsJumpTable
	mov r2, rCellWidthInBytes, lsr #1	@ convert 1, 2, 4 to 0, 1, 2
	add r1, r0, r2, lsl #2			@ convert 0, 1, 2 to 0, 4, 8
	ldr rOperationsFunction, [r1]

	add r1, rNumberOfCellsInSpreadsheet, #1	@ make room for result cell
	mul a1, r1, rCellWidthInBytes
	bl malloc
	mov rSpreadsheetAddress, r0

	mov a1, rOperationsFunction
	mov a2, rSpreadsheetAddress
	mov a3, rNumberOfCellsInSpreadsheet
	bl resetSheet

recalculateSheet:
	ldr r0, =overflowFlag
	mov r1, #0
	str r1, [r0]	@ clear overflow flag
	push {r0}	@ pass address of overflow flag to calc function
	ldr r0, =formulaJumpTable
	ldr ip, [r0, rFormula, lsl #2]	@ calc function for formula
	mov a1, rOperationsFunction
	mov a2, rSpreadsheetAddress
	mov a3, rNumberOfCellsInSpreadsheet
	mov a4, rFormula
	blx ip			@ calculate sheet

redisplaySheet:
	mTerminalCommand #terminalCommand_clearScreen

	push {rPresentation}
	push {rFormula}
	ldr r0, =overflowFlag
	ldr r0, [r0]
	push {r0}
	mov a1, rOperationsFunction
	mov a2, rSpreadsheetAddress
	mov a3, rNumberOfCellsInSpreadsheet
	mov a4, rCellWidthInBytes
	bl displaySheet

	ldr r1, =menuModeJumpTable
	ldr r0, [r1, rMenuMode, lsl #2]
	bx r0	@ jump to handler for current menu mode

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ Main Menu
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
menuMain:
	ldr r0, =testMode
	ldr r0, [r0]
	push {r0}
	bl getMainSelection

	cmp r1, #inputStatus_acceptedControlCharacter
	beq actionQuit 
	b actionSwitch

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ Change Formula Menu
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
menuChangeFormula:
	ldr a1, =testMode
	ldr a1, [a1]
	push {a1}
	bl getFormula

	cmp r1, #inputStatus_acceptedControlCharacter
	bne setFormula

	cmp r0, #'q'
	beq actionQuit
	cmp r0, #'r'
	beq returnToMain

setFormula:
	sub rFormula, r0, #1
	b recalculateAndReturnToMain 

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ Change data presentation menu
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
menuChangePresentation:
	ldr a1, =testMode
	ldr a1, [a1]
	push {a1}
	bl getPresentation

	cmp r1, #inputStatus_acceptedControlCharacter
	bne setPresentation

	cmp r0, #'q'
	beq actionQuit
	cmp r0, #'r'
	beq returnToMain

setPresentation:
	sub rPresentation, r0, #1
	b returnToMain

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ Get cell to edit menu
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
menuGetCellToEdit:
	ldr a1, =testMode
	ldr a1, [a1]
	push {a1}
	mov a1, #1				@ lowest acceptable cell number
	mov a2, rNumberOfCellsInSpreadsheet	@ highest acceptable
	bl getCellToEdit

	cmp r1, #inputStatus_acceptedControlCharacter
	bne gotCellToEdit

	cmp r0, #'q'
	beq actionQuit
	b returnToMain	@ control char not q, must be r

gotCellToEdit:
	ldr r1, =cellToEdit
	str r0, [r1]
	mov rMenuMode, #menuMode_getNewValueForCell
	b redisplaySheet

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ Get new value for cell menu
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
menuGetNewValueForCell:
	ldr r0, =testMode
	ldr r0, [r0]
	push {r0}
	mov a1, rOperationsFunction
	ldr a2, =cellToEdit
	ldr a2, [a2]
	mov a3, rCellWidthInBytes
	mov a4, rPresentation
	bl getNewValueForCell

	cmp r1, #inputStatus_acceptedControlCharacter
	bne gotNewValueForCell

	cmp r0, #'q'
	beq actionQuit
	b actionEditCell @ control char not 'q', so 'r' -- return to cell select

gotNewValueForCell:	@ r0/a1 = new value for cell
	mov a2, rSpreadsheetAddress
	ldr a3, =cellToEdit
	ldr a3, [a3]
	sub a3, #1	@ cell to edit, zero-based
	mov a4, #operation_store
	blx rOperationsFunction
	b recalculateAndReturnToMain

actionSwitch:
	sub r0, #1			@ user menu selection to 0-based
	ldr r1, =actionsJumpTable
	add r0, r1, r0, lsl #2
	ldr r0, [r0]
	bx r0

actionEditCell:
	mov rMenuMode, #menuMode_getCellToEdit
	b redisplaySheet

actionChangeFormula:
	mov rMenuMode, #menuMode_changeFormula
	b redisplaySheet

actionChangePresentation:
	mov rMenuMode, #menuMode_changePresentation
	b redisplaySheet

actionResetSpreadsheet:
	mov a1, rSpreadsheetAddress
	bl free
	mTerminalCommand #terminalCommand_clearScreen
	b showSetupIntro

actionFillRandom:
	mov a1, rOperationsFunction
	mov a2, rSpreadsheetAddress
	mov a3, rNumberOfCellsInSpreadsheet
	bl randomFill
	b recalculateSheet

recalculateAndReturnToMain:
	mov rMenuMode, #menuMode_main
	b recalculateSheet

returnToMain:
	mov rMenuMode, #menuMode_main
	b redisplaySheet

actionQuit:
	ldr r0, =msgByeNow
	bl printf
	mov r0, #0
	bl fflush		@ make sure it's all out, for our test harness

	mov r7, $1		@ exit syscall
	svc 0			@ wake kernel

	.unreq rMenuMode
	.unreq rFormula
	.unreq rPresentation
	.unreq rOperationsFunction
	.unreq rCellWidthInBytes
	.unreq rNumberOfCellsInSpreadsheet
	.unreq rSpreadsheetAddress

	.end

