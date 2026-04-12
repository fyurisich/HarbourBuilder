// Form1.prg
//--------------------------------------------------------------------

CLASS TForm1 FROM TForm

   // IDE-managed Components
   DATA oOpenDialog1   // TOpenDialog

   // Event handlers

   METHOD CreateForm()

ENDCLASS
//--------------------------------------------------------------------

METHOD CreateForm() CLASS TForm1

   ::Title  := "Form1"
   ::Left   := 1129
   ::Top    := 456
   ::Width  := 650
   ::Height := 421
   ::FontName := "Segoe UI"
   ::FontSize := 9
   ::Color  := 2960685

   COMPONENT ::oOpenDialog1 TYPE CT_OPENDIALOG OF Self  // TOpenDialog

   // Event wiring
   ::OnClick := { || Form1Click( Self ) }

return nil
//--------------------------------------------------------------------

//--------------------------------------------------------------------
static function Form1Click( oForm )

   if oForm:oOpenDialog1:Execute()
	   MsgInfo( oForm:oOpenDialog1:cFileName )
	endif	

return nil
