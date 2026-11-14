10 REM LOAN.BAS - a loan's monthly payment, and its first year
20 REM RetrOS sample program.
30 CLS:KEY OFF
40 PRINT "LOAN PAYMENTS":PRINT
50 INPUT "Amount borrowed";P
60 INPUT "Yearly interest rate, percent";R
70 INPUT "Years to pay";N
80 IF P<=0 OR R<0 OR N<=0 THEN PRINT "Those will not do.":PRINT:GOTO 50
90 I=R/1200:M=N*12
100 IF I=0 THEN PAY=P/M ELSE PAY=P*I/(1-(1+I)^-M)
110 PRINT:PRINT USING "Monthly payment   $$###,###.##";PAY
120 PRINT USING "Total of payments $$###,###.##";PAY*M
130 PRINT USING "Total interest    $$###,###.##";PAY*M-P
140 PRINT:PRINT "Month   Interest  Principal      Balance"
150 B=P:F$=" ###  ######.##  #######.##  ##########.##"
160 FOR K=1 TO 12
170   IF K>M THEN 210
180   IT=B*I:PR=PAY-IT:B=B-PR:IF B<0 THEN B=0
190   PRINT USING F$;K;IT;PR;B
200 NEXT K
210 PRINT:INPUT "Another (Y/N)";A$
220 IF A$="Y" OR A$="y" THEN 30
230 KEY ON:END
