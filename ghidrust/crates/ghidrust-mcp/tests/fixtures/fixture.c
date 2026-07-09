#include <stdio.h>
typedef struct Rect { int left; int top; int right; int bottom; } Rect; // get_datatype struct
enum Color { RED = 0, GREEN = 1, BLUE = 2 };                            // get_datatype enum
Rect g_rect = { 1, 2, 3, 4 };                                          // list_data_items global (uses Rect)
enum Color g_color = GREEN;                                            // global uses Color so its debug info survives
const char *g_banner = "https://example.test/beacon";                   // list_strings + xref target
unsigned add_two(unsigned a, unsigned b) { return a + b; }             // known function (kept for M1a tests)
unsigned mul(unsigned a, unsigned b) { return a * b; }                 // multi-hop callee
unsigned compute(unsigned a, unsigned b) { return add_two(a, mul(a, b)); } // caller chain for get_xrefs
// M2d set_local target: forces real decompiler-visible STACK locals (address-taken scalar + stack array),
// since every other fixture fn decompiles to register-only locals. Decompiler renders `acc` as a clean
// scalar stack local (`local_24 : uint @ stack:-0x24`) — the retype/rename target for the set_local e2e.
unsigned locals_demo(unsigned n) {
    unsigned acc = 0;
    unsigned buf[4];
    unsigned *p = &acc;                 // address-taken -> acc lands on the stack (not a register)
    for (unsigned i = 0; i < 4; i++) { buf[i] = (i + 1) * n; acc += buf[i]; }
    *p += n;
    return acc + buf[2];
}
__declspec(dllexport) unsigned api_entry(unsigned x) {                  // export for list_symbols(export)
    printf("%s\n", g_banner);                                          // import (printf) + string xref
    return compute(x, x);
}
int main(void) { return api_entry(7) + locals_demo(3); }               // call locals_demo so it's analyzed
