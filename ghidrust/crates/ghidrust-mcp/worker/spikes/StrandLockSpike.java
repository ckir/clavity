// StrandLockSpike.java — opens the program then strands the .lock crash-shaped (mirrors the M0
// resident-worker teardown: System.exit with NO natural return leaves the .lock). Probes U2:
// does a subsequent WRITABLE reopen+save survive the stranded lock, or throw LockException?
import ghidra.app.script.GhidraScript;
public class StrandLockSpike extends GhidraScript {
    @Override public void run() throws Exception {
        println("STRANDING");
        System.exit(1);
    }
}
