// Form1.prg
//------------------------------------------------------------------------

CLASS TForm1 FROM TForm

   // IDE-managed Components
   DATA oLblTitle    // TLabel
   DATA oLblCols     // TLabel
   DATA oList        // TListBox
   DATA oLblStatus   // TLabel
   DATA oBtnPrev     // TButton
   DATA oBtnPDF      // TButton

   METHOD CreateForm()

ENDCLASS
//------------------------------------------------------------------------

METHOD CreateForm() CLASS TForm1

   ::Title    := "Sales Report - HarbourBuilder Sample"
   ::Left     := 100
   ::Top      := 100
   ::Width    := 660
   ::Height   := 500
   ::FontName := "Segoe UI"
   ::FontSize := 10

   @ 12, 12 SAY ::oLblTitle PROMPT "Monthly Sales Report" OF Self SIZE 630, 22
   ::oLblTitle:FontSize := 13
   ::oLblTitle:Bold     := .T.

   @ 42, 12 SAY ::oLblCols PROMPT "Customer              Product              Qty    Unit Price      Total" OF Self SIZE 630, 18
   ::oLblCols:FontName := "Courier New"
   ::oLblCols:FontSize := 9

   @ 64, 12 LISTBOX ::oList OF Self SIZE 630, 340
   ::oList:FontName := "Courier New"
   ::oList:FontSize := 9

   @ 412, 12 SAY ::oLblStatus PROMPT "Records: 15" OF Self SIZE 400, 18
   ::oLblStatus:FontSize := 9
   ::oLblStatus:Bold     := .T.

   @ 412, 440 BUTTON ::oBtnPrev PROMPT "Preview..." OF Self SIZE 100, 30
   @ 450, 440 BUTTON ::oBtnPDF PROMPT "Export PDF..." OF Self SIZE 100, 30

return nil
//------------------------------------------------------------------------
