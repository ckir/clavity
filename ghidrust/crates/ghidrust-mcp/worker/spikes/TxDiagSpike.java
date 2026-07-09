// TxDiagSpike.java — diagnostic: prints program transaction state around a rename+save so U1 can
// pinpoint WHY DomainFile.save() throws "Unable to lock due to active transaction" in headless.
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.*;
import ghidra.program.model.symbol.*;
public class TxDiagSpike extends GhidraScript {
    private void dumpTx(String when) {
        ghidra.framework.model.TransactionInfo ti = currentProgram.getCurrentTransactionInfo();
        println("TXDIAG " + when + " tx=" + (ti == null ? "<none>" : ("'" + ti.getDescription() + "' status=" + ti.getStatus())));
    }
    @Override public void run() throws Exception {
        Program p = currentProgram;
        dumpTx("at-entry");
        Function fn = getFirstFunction();
        Symbol sym = p.getSymbolTable().getPrimarySymbol(fn.getEntryPoint());
        String orig = sym.getName();
        String probe = "SPIKE_" + System.currentTimeMillis();
        int tx = p.startTransaction("spike rename");
        boolean ok = false;
        try { sym.setName(probe, SourceType.USER_DEFINED); ok = true; }
        finally { p.endTransaction(tx, ok); }
        dumpTx("after-endTransaction");
        try {
            p.getDomainFile().save(monitor);
            println("TXDIAG SAVE_OK " + orig + " -> " + probe + " canSave=" + p.getDomainFile().canSave());
        } catch (Throwable t) {
            println("TXDIAG SAVE_FAIL " + t.getClass().getName() + ": " + t.getMessage());
            dumpTx("after-save-fail");
        }
    }
}
