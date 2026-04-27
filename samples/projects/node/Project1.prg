// Project1.prg — TNode demo
#include "hbbuilder.ch"

PROCEDURE Main()
   local oApp, oForm
   oApp := TApplication():New()
   oApp:Title := "TNode Demo"
   oForm := TForm1():New()
   oApp:CreateForm( oForm )
   oApp:Run()
return
