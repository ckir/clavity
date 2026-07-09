// InvalidNameProbe.java — finds a new_name that makes Symbol.setName throw (so the M2a rename
// details.reason e2e has a reliable InvalidInputException/DuplicateNameException trigger). Tries each
// candidate in its own rolled-back transaction and prints the exception class+message, or OK.
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.*;
public class InvalidNameProbe extends GhidraScript {
    @Override public void run() throws Exception {
        Program p = currentProgram;
        Function fn = getFirstFunction();
        Symbol sym = p.getSymbolTable().getPrimarySymbol(fn.getEntryPoint());
        String orig = sym.getName();
        String[] cands = { "", " ", "a b", "1abc", "a\tb", "a.b", "a-b", "foo bar baz", "a/b", "a\\b", "a\nb" };
        for (String c : cands) {
            int id = p.startTransaction("probe");
            boolean threw = false;
            try {
                p.getSymbolTable().getPrimarySymbol(fn.getEntryPoint()).setName(c, SourceType.USER_DEFINED);
                println("PROBE [" + c.replace("\t","\\t").replace("\n","\\n") + "] OK (no throw)");
            } catch (Throwable t) {
                threw = true;
                println("PROBE [" + c.replace("\t","\\t").replace("\n","\\n") + "] THREW " + t.getClass().getName() + ": " + t.getMessage());
            } finally {
                p.endTransaction(id, false); // rollback so orig name is restored for the next candidate
            }
            if (!threw) { /* rolled back anyway */ }
        }
        println("PROBE_DONE orig=" + orig);
    }
}
