# Report Preview, PDF Export, and Rulers Design

## Goal

Allow the user to preview a visual report (bands + fields designed in the IDE) using macOS Preview.app and export it to a PDF file. Additionally, display measurement rulers (horizontal + vertical) in the form designer when the first report band is placed.

## Architecture

### Preview + PDF

```
TReport:Preview()  →  RPT_PreviewOpen / RPT_PreviewAddPage / RPT_PreviewDrawText / RPT_PreviewRender
TReport:ExportPDF(cFile)  →  RPT_ExportPDF( hForm, cFile )
```

All `RPT_*` functions are `HB_FUNC` entries in `cocoa_core.m` that use Core Graphics (`CGPDFContextCreate`, `CGContextDrawPDFPage`, etc.) to render the report.

**Preview flow:**
1. `RPT_PreviewOpen(nPageW, nPageH, nML, nMR, nMT, nMB)` — creates a `CGPDFContext` writing to a temp file `/tmp/hbpreview_XXXXXX.pdf`
2. `RPT_PreviewAddPage()` — calls `CGPDFContextBeginPage`
3. `RPT_PreviewDrawText(nX, nY, cText, cFont, nFSize, lBold, lItalic, nColor)` — draws text at pixel position using `CTFramesetter` / `CTLine` (Core Text)
4. `RPT_PreviewRender()` — calls `CGPDFContextEndPage`, closes context, then opens file with `[[NSWorkspace sharedWorkspace] openFile:...]`
5. `RPT_ExportPDF(cFile)` — same pipeline but writes to `cFile` (user-specified path)

**Coordinate system:** pixels (as stored in `TReportField:nLeft/nTop`). PDF points = pixels × (72/96) — standard screen→PDF scaling. For macOS retina this gives clean output on paper.

**Page size:** `nPageWidth × nPageHeight` in pixels (default 794×1123 = A4 at 96 DPI). A4 at 72 DPI = 595×842 pt, so scale = 0.75.

**No TPrinter dependency:** Preview and PDF export bypass TPrinter entirely and use CGPDFContext directly. TPrinter remains for physical print.

### Rulers

Two thin `NSView` subviews (`HBRulerView`) overlaid on the form's superview when the form is in report-design mode (i.e., at least one CT_BAND child exists):

- **Horizontal ruler**: 20px tall, full form width, docked at top of form container
- **Vertical ruler**: 20px wide, full form height minus 20px, docked at left of form container

The form content view is inset by (20, 20) when rulers are visible. Rulers are created/destroyed by `UI_BandRulersUpdate(hForm)` called from:
- After `BandStackAll` completes (band added or type changed)
- After a band is deleted (form resize removes last band → rulers hidden)

`HBRulerView` draws with `drawRect:`:
- Light gray background (`NSColor.controlBackgroundColor`)
- Tick marks at 50px intervals, labeled at 100px intervals with pixel value
- Corner square at (0,0) intersection: 20×20 filled gray

## File Structure

| File | Change |
|------|--------|
| `source/backends/cocoa/cocoa_core.m` | Add `HBRulerView`, `UI_BandRulersUpdate`, and all `HB_FUNC RPT_*` implementations |
| `source/core/classes.prg` | Add `METHOD ExportPDF(cFile)` to `TReport`; `TReport:Preview()` already calls the RPT_ functions |
| `include/hbbuilder.ch` | Add `#define`s for ruler dimensions (`RULER_SIZE 20`) if needed |

No new files needed.

## Components

### HBRulerView (Objective-C, cocoa_core.m)

```objc
@interface HBRulerView : NSView
@property (assign) BOOL isHorizontal;
@property (assign) int  pixelOffset;   // scroll offset (future)
@end
```

`drawRect:` draws:
- Fill background: `[[NSColor colorWithWhite:0.88 alpha:1] set]`
- Tick marks: every 10px minor tick (1px tall/wide), every 50px medium tick (4px), every 100px major tick (8px) + label
- Label: `NSString stringWithFormat:@"%d"` drawn with small system font, center-aligned above major tick

### UI_BandRulersUpdate

```c
static void UI_BandRulersUpdate( HBControl * form );
```

- Counts CT_BAND children
- If count > 0 and rulers not present: create `HBRulerView` pair, inset `FContentView` by 20px left and 20px top
- If count == 0 and rulers present: remove ruler views, restore content view inset

Rulers are stored as associated objects on the form's NSView via `objc_setAssociatedObject` with two keys (`kRulerH`, `kRulerV`).

Called from:
- End of `BandStackAll()` — covers all band add/resize/type-change paths
- `UI_DeleteControl` in cocoa_core.m — after a CT_BAND is deleted, recount and hide rulers if 0 remain

### HB_FUNC implementations

```c
HB_FUNC( RPT_PREVIEWOPEN )   // params: nW, nH, nML, nMR, nMT, nMB
HB_FUNC( RPT_PREVIEWADDPAGE )
HB_FUNC( RPT_PREVIEWDRAWTEXT ) // params: nX, nY, cText, cFont, nSize, lBold, lItalic, nColor
HB_FUNC( RPT_PREVIEWDRAWRECT ) // params: nX, nY, nW, nH, nBorderColor, nFillColor
HB_FUNC( RPT_PREVIEWRENDER )   // closes PDF, opens with Preview.app
HB_FUNC( RPT_EXPORTPDF )       // params: cFile — same pipeline, skip openFile
```

Global state (static in cocoa_core.m):
```c
static CGContextRef  s_pdfCtx   = NULL;
static CFURLRef      s_pdfURL   = NULL;
static CGRect        s_pageRect  = {{0,0},{595,842}};  // A4 at 72pt
static float         s_scale     = 0.75f;              // 96→72 DPI
```

### TReport:ExportPDF (classes.prg)

```harbour
METHOD ExportPDF( cFile ) CLASS TReport
   local i, j, oBand, oFld, nY
   RPT_PreviewOpen( ::nPageWidth, ::nPageHeight, ;
      ::nMarginLeft, ::nMarginRight, ::nMarginTop, ::nMarginBottom )
   RPT_PreviewAddPage()
   nY := ::nMarginTop
   for i := 1 to Len( ::aDesignBands )
      oBand := ::aDesignBands[i]
      if ! oBand:lVisible; loop; endif
      for j := 1 to Len( oBand:aFields )
         oFld := oBand:aFields[j]
         RPT_PreviewDrawText( ::nMarginLeft + oFld:nLeft, nY + oFld:nTop, ;
            iif( ! Empty(oFld:cText), oFld:cText, "[" + oFld:cFieldName + "]" ), ;
            oFld:cFontName, oFld:nFontSize, oFld:lBold, oFld:lItalic, oFld:nForeColor )
      next
      nY += oBand:nHeight
   next
   RPT_ExportPDF( cFile )
return nil
```

`TReport:Preview()` is identical but calls `RPT_PreviewRender()` instead of `RPT_ExportPDF()`.

## PDF Coordinate Notes

CoreGraphics PDF uses bottom-left origin. Screen uses top-left. Conversion:
```
pdf_y = pageHeight_pt - (screen_y * scale)
```

Where `pageHeight_pt = nPageHeight * scale` (e.g. 1123 * 0.75 = 842.25 ≈ 842 pt = A4).

## Error Handling

- If `CGPDFContextCreate` fails: `RPT_PreviewRender` is a no-op, no crash
- If temp file can't be created: fall back to `/tmp/hbpreview.pdf`
- If `openFile:` returns NO: silently ignored (user will see nothing — acceptable for v1)

## Testing

1. Create a form, add a Header band, add a Label field to it with text "Hello Report"
2. Call `TReport:Preview()` from a button's OnClick
3. macOS Preview.app opens showing "Hello Report" on an A4 page
4. Call `TReport:ExportPDF("/tmp/test.pdf")` — file saved, openable in Preview manually

## Out of Scope (v1)

- Multi-page reports (pagination logic is in `TReport:Print()`, Preview renders one page)
- Data-bound field rendering in Preview (shows field name placeholder `[FIELDNAME]`)
- Drawing images, lines, or boxes (only text for v1)
- Ruler scroll synchronization with form scroll
- Ruler unit toggling (mm/cm/in) — pixels only
