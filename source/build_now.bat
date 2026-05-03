@echo off
setlocal
set HBDIR=C:\harbour
set HBBIN=%HBDIR%\bin\win\bcc
set HBLIB=%HBDIR%\lib\win\bcc
set HBINC=%HBDIR%\include
set CCBIN=C:\bcc77\bin
set CCLIB=C:\bcc77\lib
set PSDKLIB=C:\bcc77\lib\psdk
set INCDIR=..\include
set OUTDIR=..\bin
echo === Compiling PRG ===
"%HBBIN%\harbour.exe" hbbuilder_win.prg -n -w -es2 -q -I%HBINC% -I%INCDIR%
if errorlevel 1 (echo HARBOUR FAILED & exit /b 1)
echo PRG OK
echo === Compiling C ===
"%CCBIN%\bcc32.exe" -c -O2 -tW -w- -I%HBINC% -I%INCDIR% hbbuilder_win.c
if errorlevel 1 (echo BCC C FAILED & exit /b 1)
echo C OK
echo === Compiling C++ ===
"%CCBIN%\bcc32.exe" -c -O2 -tW -w- -I%HBINC% -I%INCDIR% cpp\hbbridge.cpp
if errorlevel 1 (echo BCC hbbridge FAILED & exit /b 1)
"%CCBIN%\bcc32.exe" -c -O2 -tW -w- -I%HBINC% -I%INCDIR% cpp\tcontrols.cpp
if errorlevel 1 (echo BCC tcontrols FAILED & exit /b 1)
"%CCBIN%\bcc32.exe" -c -O2 -tW -w- -I%HBINC% -I%INCDIR% cpp\hb_db_real.cpp
if errorlevel 1 (echo BCC hb_db_real FAILED & exit /b 1)
echo CPP OK
echo === Linking ===
set OBJS=c0w32.obj hbbuilder_win.obj tform.obj hbbridge.obj tcontrol.obj tcontrols.obj hb_db_real.obj
"%CCBIN%\ilink32.exe" -Tpe -aa -Gn -L%CCLIB%;%PSDKLIB%;%HBLIB% %OBJS%, "%OUTDIR%\hbbuilder_win.exe", , cw32mt.lib import32.lib hbvm.lib hbrtl.lib hbcommon.lib hblang.lib hbrdd.lib hbmacro.lib hbpp.lib rddntx.lib rddcdx.lib rddfpt.lib hbsix.lib hbcpage.lib hbpcre.lib hbzlib.lib gtgui.lib gtwin.lib hbsqlit3.lib sqlite3.lib hbdebug.lib user32.lib kernel32.lib gdi32.lib comctl32.lib comdlg32.lib shell32.lib ole32.lib oleaut32.lib advapi32.lib ws2_32.lib winmm.lib msimg32.lib gdiplus.lib
if errorlevel 1 (echo LINK FAILED & exit /b 1)
echo LINK OK
echo.
echo === BUILD SUCCESS ===
exit /b 0
