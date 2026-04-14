// Form1.prg
//--------------------------------------------------------------------

CLASS TForm1 FROM TForm

   // IDE-managed Components
   DATA oLabel1   // TLabel
   DATA oEdit1   // TEdit
   DATA oButton1   // TButton

   // Event handlers

   METHOD CreateForm()

ENDCLASS
//--------------------------------------------------------------------

METHOD CreateForm() CLASS TForm1

   ::Title  := "Hello Android"
   ::Left   := 1153
   ::Top    := 505
   ::Width  := 513
   ::Height := 600
   ::FontName := "Segoe UI"
   ::FontSize := 9
   ::Color  := 2960685

   @ 20, 20 SAY ::oLabel1 PROMPT "Type your name:" OF Self SIZE 300, 30
   ::oLabel1:oFont := "Segoe UI,12"
   @ 76, 76 GET ::oEdit1 VAR "" OF Self SIZE 300, 50
   ::oEdit1:oFont := "Segoe UI,12"
   @ 284, 74 BUTTON ::oButton1 PROMPT "Greet" OF Self SIZE 300, 50
   ::oButton1:oFont := "Segoe UI,12"

   // Event wiring
   ::oButton1:OnClick := { || Button1Click( Self ) }

return nil
//--------------------------------------------------------------------

METHOD Button1Click() CLASS TForm1

   // On Android this handler is wired automatically: the generator
   // emits UI_OnClick( hButton1, {|| Button1Click() } ) because it
   // finds a function named "Button1Click" in this file.
   //
   // Keep handler bodies Android-compatible for now: prefer UI_SetText
   // over MsgInfo, no desktop classes until iteration 2 adds dialogs.
   ::oLabel1:Text := "Hello, " + ::oEdit1:Text + " !"

return nil

//--------------------------------------------------------------------
