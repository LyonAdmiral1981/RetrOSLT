10 REM PALETTE.BAS - the text colors, and the two graphics palettes
20 REM RetrOS sample program.
30 SCREEN 0:WIDTH 80:COLOR 7,0:CLS:KEY OFF
40 PRINT "COLOR foreground, background: foregrounds 0-15 on backgrounds 0-7"
50 PRINT
60 FOR B=0 TO 7
70   COLOR 7,0:PRINT USING "Background # ";B;
80   FOR F=0 TO 15
90     COLOR F,B:PRINT USING "###";F;
100  NEXT F
110  COLOR 7,0:PRINT
120 NEXT B
130 PRINT:COLOR 23,0:PRINT "Foregrounds 16-31 blink";:COLOR 7,0
140 PRINT " (this is 23: 7, white, blinking)"
150 PRINT:PRINT "Press any key for the graphics palettes"
160 IF INKEY$="" THEN 160
170 SCREEN 1
180 FOR P=0 TO 1
190   COLOR 1,P:CLS
200   LOCATE 2,6:PRINT "COLOR 1,";P;": colors 0 to 3"
210   FOR C=0 TO 3
220     LINE (20+C*72,40)-(80+C*72,150),C,BF
230     LINE (20+C*72,40)-(80+C*72,150),3,B
240     LOCATE 21,5+C*9:PRINT C;
250   NEXT C
260   LOCATE 24,6:PRINT "Press any key";
270   IF INKEY$="" THEN 270
280 NEXT P
290 SCREEN 0:WIDTH 80:KEY ON:END
