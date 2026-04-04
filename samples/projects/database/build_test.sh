#!/bin/bash
# Build and run database examples (console mode, no GTK needed)
set -e

HBDIR="${HBDIR:-$HOME/harbour}"
HBBIN="$HBDIR/bin/linux/gcc"
HBINC="$HBDIR/include"
HBLIB="$HBDIR/lib/linux/gcc"
PROJDIR="$(cd "$(dirname "$0")/../../.." && pwd)"
PROG="${1:-dbf_example}"

cd "$(dirname "$0")"

echo "=== Building $PROG ==="

# Compile the example
$HBBIN/harbour $PROG.prg -n -w -q \
   -I"$HBINC" -I"$PROJDIR/include" -I"$PROJDIR/harbour" \
   -o${PROG}.c

# Compile C
gcc -c -g -Wno-unused-value -I"$HBINC" ${PROG}.c -o ${PROG}.o

# Compile GTK3 core (needed for UI_MsgBox etc. referenced by classes.prg)
gcc -c -g -Wno-unused-value -I"$HBINC" \
   $(pkg-config --cflags gtk+-3.0) \
   "$PROJDIR/backends/gtk3/gtk3_core.c" -o gtk3_core.o 2>/dev/null

# Compile classes.prg (has DB classes)
$HBBIN/harbour "$PROJDIR/harbour/classes.prg" -n -w -q \
   -I"$HBINC" -I"$PROJDIR/include" -I"$PROJDIR/harbour" \
   -oclasses.c
gcc -c -g -Wno-unused-value -I"$HBINC" \
   $(pkg-config --cflags gtk+-3.0) \
   classes.c -o classes.o

# Link
gcc ${PROG}.o classes.o gtk3_core.o -g -o ${PROG} \
   -L"$HBLIB" \
   -Wl,--start-group \
   -lhbcommon -lhbvm -lhbrtl -lhbrdd -lhbmacro -lhblang -lhbcpage -lhbpp \
   -lhbcplr -lrddntx -lrddcdx -lrddfpt -lhbsix -lhbusrrdd -lhbct \
   -lhbsqlit3 -lsddsqlt3 -lrddsql \
   -lgttrm -lhbdebug -lhbpcre \
   $(pkg-config --libs gtk+-3.0) \
   -lm -lpthread -ldl -lrt -lsqlite3 \
   -L/usr/lib/x86_64-linux-gnu -l:libncurses.so.6 \
   -Wl,--end-group

echo ""
echo "=== Running $PROG ==="
echo ""
./${PROG}
echo ""
echo "=== Exit code: $? ==="
