// sqlite_example.prg - SQLite database example using TSQLite
// Demonstrates creating tables, inserting data, and querying
//
// Run from: samples/projects/database/

#include "hbbuilder.ch"

function Main()

   local oDb, aRows, aRow, i

   ? "=== TSQLite Example ==="
   ?

   // Open (creates file if not exists)
   oDb := TSQLite():New()
   oDb:cDatabase := "example.sqlite"

   if ! oDb:Open()
      ? "Error: " + oDb:LastError()
      return nil
   endif

   ? "Connected to: " + oDb:cDatabase
   ? "Driver: " + oDb:cDriver
   ?

   // Create table
   ? "Creating table..."
   oDb:Execute( "DROP TABLE IF EXISTS products" )
   oDb:CreateTable( "products", { ;
      { "id",    "INTEGER PRIMARY KEY AUTOINCREMENT" }, ;
      { "name",  "TEXT NOT NULL" }, ;
      { "price", "REAL" }, ;
      { "stock", "INTEGER DEFAULT 0" } } )
   ? "  Table 'products' created"
   ?

   // Insert data using transaction (fast batch insert)
   ? "Inserting data..."
   oDb:BeginTransaction()
   oDb:Execute( "INSERT INTO products (name, price, stock) VALUES ('Laptop', 999.99, 15)" )
   oDb:Execute( "INSERT INTO products (name, price, stock) VALUES ('Mouse', 29.99, 200)" )
   oDb:Execute( "INSERT INTO products (name, price, stock) VALUES ('Keyboard', 79.99, 85)" )
   oDb:Execute( "INSERT INTO products (name, price, stock) VALUES ('Monitor', 449.99, 30)" )
   oDb:Execute( "INSERT INTO products (name, price, stock) VALUES ('USB Cable', 9.99, 500)" )
   oDb:Commit()
   ? "  5 products inserted"
   ? "  Last insert ID: " + hb_ValToStr(oDb:LastInsertId())
   ?

   // Query all products
   ? "All products:"
   ? PadR("ID", 5) + PadR("Name", 20) + PadR("Price", 12) + "Stock"
   ? Replicate("-", 45)

   aRows := oDb:Query( "SELECT id, name, price, stock FROM products ORDER BY name" )
   for i := 1 to Len( aRows )
      aRow := aRows[i]
      ? PadR(hb_ValToStr(aRow[1]), 5) + ;
        PadR(hb_ValToStr(aRow[2]), 20) + ;
        PadR(hb_ValToStr(aRow[3]), 12) + ;
        hb_ValToStr(aRow[4])
   next

   ?
   // Query with filter
   ? "Products over $50:"
   aRows := oDb:Query( "SELECT name, price FROM products WHERE price > 50 ORDER BY price DESC" )
   for i := 1 to Len( aRows )
      ? "  " + PadR(hb_ValToStr(aRows[i][1]), 20) + "$" + hb_ValToStr(aRows[i][2])
   next

   ?
   // Show tables
   ? "Tables in database: " + hb_ValToStr( oDb:Tables() )

   // Check if table exists
   ? "Table 'products' exists: " + iif( oDb:TableExists("products"), "Yes", "No" )
   ? "Table 'orders' exists: " + iif( oDb:TableExists("orders"), "Yes", "No" )

   oDb:Close()
   ?
   ? "=== Done ==="

return nil
