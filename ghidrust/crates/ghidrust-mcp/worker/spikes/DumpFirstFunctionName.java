// DumpFirstFunctionName.java — prints the primary symbol name at the first function's entry.
// Used to confirm RenameSaveSpike's rename PERSISTED across a fresh JVM (U1).
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.*;
public class DumpFirstFunctionName extends GhidraScript {
    @Override public void run() throws Exception {
        Program p = currentProgram;
        Function fn = getFirstFunction();
        Symbol sym = p.getSymbolTable().getPrimarySymbol(fn.getEntryPoint());
        println("DUMP_NAME " + sym.getName());
    }
}
