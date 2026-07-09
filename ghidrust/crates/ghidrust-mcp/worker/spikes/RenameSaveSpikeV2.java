// RenameSaveSpikeV2.java — validates the U1 FIX: a GhidraScript (which holds a persistent
// script-framework transaction over run(), exactly like the resident GhidrustWorker) CANNOT
// DomainFile.save() while that tx is open. Fix: end(true) closes the script tx, save persists,
// start() reopens it for subsequent work. Mimics the worker (attached == currentProgram).
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.*;
public class RenameSaveSpikeV2 extends GhidraScript {
    @Override public void run() throws Exception {
        Program p = currentProgram;
        Function fn = getFirstFunction();
        Symbol sym = p.getSymbolTable().getPrimarySymbol(fn.getEntryPoint());
        String orig = sym.getName();
        String probe = "SPIKEV2_" + System.currentTimeMillis();
        // 1) apply the edit in an explicit (nested) transaction, like the worker's withTransaction.
        int tx = p.startTransaction("spikev2 rename");
        boolean ok = false;
        try { sym.setName(probe, SourceType.USER_DEFINED); ok = true; }
        finally { p.endTransaction(tx, ok); }
        // 2) THE FIX: close the persistent script-framework transaction so save() can acquire the lock.
        end(true);
        try {
            p.getDomainFile().save(monitor);
            println("SPIKEV2_SAVED " + orig + " -> " + probe + " canSave=" + p.getDomainFile().canSave());
        } catch (Throwable t) {
            println("SPIKEV2_SAVE_FAIL " + t.getClass().getName() + ": " + t.getMessage());
        } finally {
            // 3) reopen the script tx so the framework's post-run end(true) (and further edits) stay balanced.
            start();
        }
    }
}
