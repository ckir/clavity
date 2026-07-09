// RenameSaveSpike.java — run via analyzeHeadless against the fixture project.
// Proves U1 (DomainFile.save persists) + S1 (natural return drops the .lock).
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.*;
public class RenameSaveSpike extends GhidraScript {
    @Override public void run() throws Exception {
        Program p = currentProgram;
        Function fn = getFirstFunction();                 // any defined function
        Symbol sym = p.getSymbolTable().getPrimarySymbol(fn.getEntryPoint());
        String orig = sym.getName();
        String probe = "SPIKE_" + System.currentTimeMillis();
        int tx = p.startTransaction("spike rename");
        boolean ok = false;
        try { sym.setName(probe, SourceType.USER_DEFINED); ok = true; }
        finally { p.endTransaction(tx, ok); }
        p.getDomainFile().save(monitor);                  // U1: does this persist?
        println("SPIKE_SAVED " + orig + " -> " + probe + " canSave=" + p.getDomainFile().canSave());
        // Natural return (NO System.exit) — headless teardown should drop the lock. S1 checked externally.
    }
}
