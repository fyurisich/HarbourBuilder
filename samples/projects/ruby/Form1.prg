// Form1.prg — TRuby getting started
//--------------------------------------------------------------------

CLASS TForm1 FROM TForm

   DATA oRuby
   DATA oLblSample, oCboSamples
   DATA oLblScript, oScriptEdit
   DATA oBtnRun, oBtnEval, oBtnClear
   DATA oLblOutput, oOutput

   METHOD CreateForm()
   METHOD DoRun()
   METHOD DoEval()
   METHOD DoClear()
   METHOD LoadSample( nIdx )
   METHOD Log( cMsg )

ENDCLASS
//--------------------------------------------------------------------

METHOD CreateForm() CLASS TForm1

   ::Title  := "TRuby — Getting started"
   ::Left   := 280
   ::Top    := 160
   ::Width  := 620
   ::Height := 500

   COMPONENT ::oRuby TYPE CT_RUBY OF Self
   ::oRuby:cRuntimePath := ""
   ::oRuby:OnReady  := { |o| ::Log( "[ready] " + o:cLastResult ) }
   ::oRuby:OnError  := { |o, cErr| ::Log( "[error] " + cErr ) }
   ::oRuby:OnOutput := { |o, cOut| ::Log( cOut ) }

   @ 16, 16 SAY ::oLblSample PROMPT "Sample:" OF Self SIZE 60
   @ 14, 80 COMBOBOX ::oCboSamples OF Self SIZE 360, 26 ;
       ITEMS { "Hello, world", "Sum 1..100", "Time.now", "Eval (2+2)", "SetVar demo" }

   @ 48, 16 SAY ::oLblScript PROMPT "Ruby script (editable):" OF Self SIZE 240
   @ 68, 16 MEMO ::oScriptEdit OF Self SIZE 588, 160

   @ 240, 16  BUTTON ::oBtnRun   PROMPT "Run"   OF Self SIZE 100, 28
   @ 240, 124 BUTTON ::oBtnEval  PROMPT "Eval"  OF Self SIZE 100, 28
   @ 240, 504 BUTTON ::oBtnClear PROMPT "Clear" OF Self SIZE 100, 28
   ::oBtnRun:OnClick   := { || ::DoRun()  }
   ::oBtnEval:OnClick  := { || ::DoEval() }
   ::oBtnClear:OnClick := { || ::DoClear() }
   ::oCboSamples:OnChange := { || ::LoadSample( ::oCboSamples:Value + 1 ) }

   @ 282, 16 SAY ::oLblOutput PROMPT "Output:" OF Self SIZE 200
   @ 302, 16 MEMO ::oOutput OF Self SIZE 588, 160

   ::oScriptEdit:Text := "puts 'Hello, world from Ruby!'" + Chr(10)

return nil
//--------------------------------------------------------------------

METHOD LoadSample( nIdx ) CLASS TForm1
   local cCode := "", e := Chr(10)
   do case
   case nIdx == 1
      cCode := "puts 'Hello, world from Ruby!'" + e
   case nIdx == 2
      cCode := "puts \"sum(1..100) = #{(1..100).sum}\"" + e
   case nIdx == 3
      cCode := "puts Time.now.to_s" + e
   case nIdx == 4
      cCode := "2 + 2"
   case nIdx == 5
      cCode := "puts \"#{greeting}, #{name}!\"" + e
   endcase
   ::oScriptEdit:Text := cCode
return nil
//--------------------------------------------------------------------

METHOD DoRun() CLASS TForm1
   ::oRuby:SetVar( "greeting", "Hello" )
   ::oRuby:SetVar( "name",     "Antonio" )
   ::Log( "=== Run ===" )
   ::oRuby:Exec( ::oScriptEdit:Text )
return nil

METHOD DoEval() CLASS TForm1
   local cExpr := AllTrim( ::oScriptEdit:Text ), cValue
   if Empty( cExpr ); ::Log( "(empty)" ); return nil; endif
   cValue := ::oRuby:Eval( cExpr )
   ::Log( "=== Eval: " + cExpr + " ===" )
   ::Log( cValue )
return nil

METHOD DoClear() CLASS TForm1
   ::oOutput:Text := ""
return nil

METHOD Log( cMsg ) CLASS TForm1
   ::oOutput:Text := ::oOutput:Text + cMsg + Chr(10)
return nil
//--------------------------------------------------------------------
