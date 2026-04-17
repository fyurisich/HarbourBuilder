// Form1.prg
//--------------------------------------------------------------------

CLASS TForm1 FROM TForm

   // IDE-managed Components
   DATA oPrinter1   // TPrinter
   DATA oBtnPrint   // TButton
   DATA oBtnPreview   // TButton
   DATA oCbLandscape   // TCheckBox
   DATA oCbCopies   // TComboBox
   DATA oLog   // TMemo

   // Event handlers

   METHOD CreateForm()
   METHOD OnPrintClick()
   METHOD OnPreviewClick()
   METHOD OnBeginDoc()
   METHOD OnEndDoc()
   METHOD OnNewPage()
   METHOD OnPrinterError()

ENDCLASS
//--------------------------------------------------------------------

METHOD CreateForm() CLASS TForm1

   ::Title  := "TPrinter Demo"
   ::Width  := 600
   ::Height := 500

   COMPONENT ::oPrinter1 TYPE CT_PRINTER OF Self  // TPrinter @ 8,440

   // Event wiring
   ::oPrinter1:OnBeginDoc := { || ::OnBeginDoc() }
   ::oPrinter1:OnEndDoc   := { || ::OnEndDoc()   }
   ::oPrinter1:OnNewPage  := { || ::OnNewPage()  }
   ::oPrinter1:OnError    := { || ::OnPrinterError() }

   @ 10, 10 BUTTON ::oBtnPrint PROMPT "Print" OF Self SIZE 100, 32
   ::oBtnPrint:OnClick := { || ::OnPrintClick() }

   @ 10, 120 BUTTON ::oBtnPreview PROMPT "Preview" OF Self SIZE 100, 32
   ::oBtnPreview:OnClick := { || ::OnPreviewClick() }

   @ 16, 240 CHECKBOX ::oCbLandscape PROMPT "Landscape" OF Self SIZE 120

   @ 16, 370 COMBOBOX ::oCbCopies OF Self ITEMS { "1", "2", "3", "5" } SIZE 80, 100

   @ 50, 10 MEMO ::oLog OF Self SIZE 580, 400
   ::oLog:Text := "Ready. Press Print or Preview." + Chr(13) + Chr(10)

return nil
//--------------------------------------------------------------------

METHOD OnPrintClick() CLASS TForm1
   ::oPrinter1:lLandscape := ::oCbLandscape:Value
   ::oPrinter1:nCopies    := Val( ::oCbCopies:Value )
   ::oPrinter1:lPreview   := .F.
   ::DoPrint()
return nil

METHOD OnPreviewClick() CLASS TForm1
   ::oPrinter1:lLandscape := ::oCbLandscape:Value
   ::oPrinter1:nCopies    := 1
   ::oPrinter1:lPreview   := .T.
   ::DoPrint()
return nil

METHOD DoPrint() CLASS TForm1
   ::oPrinter1:BeginDoc( "TPrinter Demo" )

   // Page 1 — text lines
   ::oPrinter1:PrintLine(  20, 20, "HarbourBuilder — TPrinter Demo" )
   ::oPrinter1:PrintLine(  40, 20, "Date: " + DToC( Date() ) + "   Time: " + Time() )
   ::oPrinter1:PrintLine(  60, 20, Replicate( "-", 60 ) )
   ::oPrinter1:PrintLine(  80, 20, "Harbour is a free software compiler for the xBase language." )
   ::oPrinter1:PrintLine( 100, 20, "This demo exercises BeginDoc, PrintLine, PrintRect," )
   ::oPrinter1:PrintLine( 120, 20, "PrintImage, NewPage and EndDoc." )

   // A rectangle as a separator
   ::oPrinter1:PrintRect( 140, 20, 560, 2 )

   ::oPrinter1:PrintLine( 160, 20, "Copies  : " + hb_ntos( ::oPrinter1:nCopies ) )
   ::oPrinter1:PrintLine( 180, 20, "Landscape: " + iif( ::oPrinter1:lLandscape, "Yes", "No" ) )

   // Page 2 — second page demo
   ::oPrinter1:NewPage()
   ::oPrinter1:PrintLine( 20, 20, "Page 2 — NewPage() fired the OnNewPage event." )
   ::oPrinter1:PrintRect( 40, 20, 200, 100 )
   ::oPrinter1:PrintLine( 50, 30, "Rect demo" )

   ::oPrinter1:EndDoc()
return nil

METHOD OnBeginDoc() CLASS TForm1
   ::oLog:Text += "[Event] OnBeginDoc fired" + Chr(13) + Chr(10)
return nil

METHOD OnEndDoc() CLASS TForm1
   ::oLog:Text += "[Event] OnEndDoc fired" + Chr(13) + Chr(10)
return nil

METHOD OnNewPage() CLASS TForm1
   ::oLog:Text += "[Event] OnNewPage fired" + Chr(13) + Chr(10)
return nil

METHOD OnPrinterError() CLASS TForm1
   ::oLog:Text += "[Event] OnError fired" + Chr(13) + Chr(10)
return nil
