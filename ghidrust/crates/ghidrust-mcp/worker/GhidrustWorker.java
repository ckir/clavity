// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// ghidrust-mcp worker: a persistent headless Ghidra worker driven over loopback TCP.
// Boots via `analyzeHeadless … -process <program> -postScript GhidrustWorker.java <port> <tokenFile>`.
// The blocking request loop inside run() keeps the JVM resident (spike D1).
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.framework.model.DomainFile;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Program;
import com.google.gson.Gson;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import java.io.DataInputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

public class GhidrustWorker extends GhidraScript {

    static final int PROTOCOL_VERSION = 1;
    static final String WORKER_SCRIPT_VERSION = "0.7.0";
    static final long MAX_FRAME_LEN = 16L * 1024 * 1024;

    private final Gson gson = new Gson();
    private Program attached; // set by attach_program; null until then (bootstrap == currentProgram)
    private DecompInterface decomp; // one per attached program; rebuilt on re-attach (spec 3.3)

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            println("GhidrustWorker: expected <port> <tokenFile> script args");
            return;
        }
        int port = Integer.parseInt(args[0]);
        String token = new String(Files.readAllBytes(Path.of(args[1])), StandardCharsets.UTF_8).trim();

        try (Socket sock = new Socket()) {
            sock.connect(new InetSocketAddress("127.0.0.1", port));
            InputStream rawIn = sock.getInputStream();
            OutputStream out = sock.getOutputStream();
            DataInputStream in = new DataInputStream(rawIn);

            // 1) init handshake notification (rides the same JSON-RPC path as every later frame)
            JsonObject announce = new JsonObject();
            announce.addProperty("protocol_version", PROTOCOL_VERSION);
            announce.addProperty("ghidra_version", resolveGhidraVersion());
            announce.addProperty("worker_script_version", WORKER_SCRIPT_VERSION);
            announce.addProperty("token", token);
            JsonObject init = new JsonObject();
            init.addProperty("jsonrpc", "2.0");
            init.addProperty("method", "worker/init");
            init.add("params", announce);
            writeFrame(out, gson.toJson(init));

            // 2) request loop
            while (true) {
                byte[] body = readFrame(in);
                if (body == null) {
                    break; // socket closed by host
                }
                JsonObject req;
                try {
                    req = JsonParser.parseString(new String(body, StandardCharsets.UTF_8))
                            .getAsJsonObject();
                } catch (Exception parse) {
                    // A malformed frame must NOT crash the resident worker: return a parse error
                    // (id:null, JSON-RPC 2.0 §5) and keep serving (agy panel R1 — the parse used to
                    // sit outside every try/catch, so one bad frame threw out of run() into exit()).
                    writeFrame(out, parseError());
                    continue;
                }
                String method = req.has("method") ? req.get("method").getAsString() : "";
                if ("shutdown".equals(method)) {
                    writeFrame(out, success(req, new JsonObject()));
                    break;
                }
                String responseJson = dispatch(req, method);
                try {
                    writeFrame(out, responseJson);
                } catch (IllegalStateException tooBig) {
                    // The response exceeded MAX_FRAME_LEN (e.g. a giant decompiled function): send a
                    // small error frame instead of letting the exception crash the resident worker
                    // (agy panel R2 — writeFrame sits outside dispatch()'s try/catch). The error frame
                    // is tiny, so its own writeFrame will not exceed the limit.
                    writeFrame(out, failure(req, "FRAME_TOO_LARGE",
                            "response exceeds the 16 MiB frame limit"));
                }
            }
        }
        // Release the attached program's consumer reference so its .lock/checkout is not leaked on
        // exit (agy panel R1); getDomainObject() ref-counts consumers.
        disposeDecompiler();
        if (this.attached != null) {
            this.attached.release(this);
            this.attached = null;
        }
        // Clean teardown: run() returns naturally (no System.exit) so analyzeHeadless's own native
        // teardown releases the project .lock (Task-0 spike S1 confirmed; spec §7).
    }

    // Named `resolveGhidraVersion` (not `getGhidraVersion`) deliberately: GhidraScript already
    // declares a public `getGhidraVersion()`, so a private same-named method is an illegal
    // weaker-access override and the script fails to compile (surfaced by the real-Ghidra e2e).
    private String resolveGhidraVersion() {
        try {
            return ghidra.framework.Application.getApplicationVersion();
        } catch (Throwable t) {
            return "unknown";
        }
    }

    private String dispatch(JsonObject req, String method) {
        try {
            JsonObject params = req.has("params") && req.get("params").isJsonObject()
                    ? req.getAsJsonObject("params") : new JsonObject();
            switch (method) {
                case "attach_program":
                    return success(req, attachProgram(params));
                case "decompile_function":
                    return success(req, decompileFunction(params));
                case "worker_info":
                    return success(req, workerInfo());
                case "list_project_programs":
                    return success(req, listProjectPrograms(params));
                case "inspect_function":
                    return success(req, inspectFunction(params));
                case "find_functions":
                    return success(req, findFunctions(params));
                case "resolve_symbol":
                    return success(req, resolveSymbol(params));
                case "list_symbols":
                    return success(req, listSymbols(params));
                case "list_strings":
                    return success(req, listStrings(params));
                case "get_xrefs":
                    return success(req, getXrefs(params));
                case "get_disassembly":
                    return success(req, getDisassembly(params));
                case "read_bytes":
                    return success(req, readBytes(params));
                case "get_datatype":
                    return success(req, getDatatype(params));
                case "list_segments":
                    return success(req, listSegments(params));
                case "list_data_items":
                    return success(req, listDataItems(params));
                case "describe_address":
                    return success(req, describeAddress(params));
                case "rename":
                    return success(req, rename(params));
                case "comment":
                    return success(req, comment(params));
                case "set_datatype":
                    return success(req, setDatatype(params));
                case "set_prototype":
                    return success(req, setPrototype(params));
                case "set_local":
                    return success(req, setLocal(params));
                case "__debug_crash":
                    // Test-only: hard-kill the JVM so the host observes a transport crash. Guarded by
                    // an env var the harness sets; never reachable in a normal serve (spec §8).
                    if ("1".equals(System.getenv("GHIDRUST_ALLOW_DEBUG_CRASH"))) {
                        Runtime.getRuntime().halt(137);
                    }
                    return failure(req, "INVALID_PARAMS", "debug crash not enabled");
                case "__debug_sleep":
                    if ("1".equals(System.getenv("GHIDRUST_ALLOW_DEBUG_CRASH"))) {
                        try { Thread.sleep(params.has("ms") ? params.get("ms").getAsLong() : 1000); }
                        catch (InterruptedException ie) { Thread.currentThread().interrupt(); }
                        return success(req, new JsonObject());
                    }
                    return failure(req, "INVALID_PARAMS", "debug sleep not enabled");
                default:
                    return failure(req, "INVALID_PARAMS", "unknown method: " + method);
            }
        } catch (AmbiguousError ae) {
            return failureWithCandidates(req, ae.code, ae.getMessage(), ae.candidates);
        } catch (WorkerError we) {
            return failure(req, we.code, we.getMessage(), we.details); // details=null for the old callers
        } catch (Throwable t) {
            return failure(req, "WORKER_UNAVAILABLE", String.valueOf(t));
        }
    }

    // attach_program { program_path } -> { attached: <path> }
    private JsonObject attachProgram(JsonObject params) throws Exception {
        String path = params.has("program_path") ? params.get("program_path").getAsString() : null;
        if (path == null) {
            throw new WorkerError("INVALID_PARAMS", "attach_program requires program_path");
        }
        DomainFile df = getState().getProject().getProjectData().getFile(path);
        if (df == null) {
            throw new WorkerError("PROGRAM_NOT_FOUND", "no program at VFS path: " + path);
        }
        Object obj = df.getDomainObject(this, false, false, monitor);
        if (!(obj instanceof Program)) {
            throw new WorkerError("PROGRAM_NOT_FOUND", "not a program: " + path);
        }
        // The decompiler is bound to the old program; drop it so decompiler(program) rebuilds for
        // the new attachment (spec 3.3).
        disposeDecompiler();
        // Release the previously attached program before replacing it — getDomainObject() increments
        // a consumer refcount; overwriting without release leaks it and holds that program's .lock
        // for the whole session (agy panel R1).
        if (this.attached != null) {
            this.attached.release(this);
        }
        this.attached = (Program) obj;
        openProgram(this.attached); // sets currentProgram so FlatProgramAPI helpers target it
        JsonObject res = new JsonObject();
        res.addProperty("attached", path);
        res.addProperty("default_space", this.attached.getAddressFactory().getDefaultAddressSpace().getName());
        res.addProperty("pointer_size", this.attached.getDefaultPointerSize());
        return res;
    }

    // worker_info {} -> { attached: <vfs path|null>, default_space, pointer_size }. Lets the server
    // learn the bootstrap program's VFS path + address geometry right after boot (spec 6/7) so it can
    // build an AddressCanonicalizer and re-attach after a crash without an explicit attach_program.
    private JsonObject workerInfo() {
        Program program = this.attached != null ? this.attached : currentProgram;
        JsonObject res = new JsonObject();
        if (program == null) {
            res.add("attached", com.google.gson.JsonNull.INSTANCE);
            res.add("default_space", com.google.gson.JsonNull.INSTANCE);
            res.add("pointer_size", com.google.gson.JsonNull.INSTANCE);
            return res;
        }
        DomainFile df = program.getDomainFile();
        res.addProperty("attached", df != null ? df.getPathname() : null);
        res.addProperty("default_space", program.getAddressFactory().getDefaultAddressSpace().getName());
        res.addProperty("pointer_size", program.getDefaultPointerSize());
        return res;
    }

    // list_project_programs { offset=0, limit=200 } -> { programs:[{program_path,name,language_id?,size?}], total, truncated }
    // Walks the project's DomainFiles (Program content type only). Uses cheap getMetadata() so we do
    // NOT open every program. Paginated so a firmware project's thousands of programs can't nuke the
    // agent's context window (spec 3.1).
    private JsonObject listProjectPrograms(JsonObject params) throws Exception {
        int offset = params.has("offset") ? params.get("offset").getAsInt() : 0;
        int limit = params.has("limit") ? params.get("limit").getAsInt() : 200;
        if (offset < 0) offset = 0;
        if (limit < 0) limit = 0;
        java.util.List<ghidra.framework.model.DomainFile> all = new java.util.ArrayList<>();
        collectProgramFiles(getState().getProject().getProjectData().getRootFolder(), all);
        long total = all.size();
        com.google.gson.JsonArray programs = new com.google.gson.JsonArray();
        int end = Math.min(all.size(), (int) Math.min((long) offset + limit, Integer.MAX_VALUE));
        for (int i = Math.min(offset, all.size()); i < end; i++) {
            ghidra.framework.model.DomainFile df = all.get(i);
            JsonObject row = new JsonObject();
            row.addProperty("program_path", df.getPathname());
            row.addProperty("name", df.getName());
            try {
                java.util.Map<String, String> md = df.getMetadata();
                if (md != null) {
                    if (md.get("Language ID") != null) row.addProperty("language_id", md.get("Language ID"));
                    String bytes = md.get("# of Bytes");
                    if (bytes != null) {
                        try { row.addProperty("size", Long.parseLong(bytes.replace(",", "").trim())); }
                        catch (NumberFormatException ignore) { /* leave size absent */ }
                    }
                }
            } catch (Throwable ignore) { /* metadata is best-effort; leave optional fields absent */ }
            programs.add(row);
        }
        JsonObject res = new JsonObject();
        res.add("programs", programs);
        res.addProperty("total", total);
        res.addProperty("truncated", (long) offset + programs.size() < total);
        return res;
    }

    // Recurse the project folder tree, collecting DomainFiles whose content is a Program.
    private void collectProgramFiles(ghidra.framework.model.DomainFolder folder,
                                     java.util.List<ghidra.framework.model.DomainFile> out) {
        for (ghidra.framework.model.DomainFile df : folder.getFiles()) {
            if (ghidra.program.model.listing.Program.class.getSimpleName().equals(df.getContentType())
                    || "Program".equals(df.getContentType())) {
                out.add(df);
            }
        }
        for (ghidra.framework.model.DomainFolder sub : folder.getFolders()) {
            collectProgramFiles(sub, out);
        }
    }

    // decompile_function { name? , address? } -> { c, signature }
    private JsonObject decompileFunction(JsonObject params) throws Exception {
        Program program = this.attached != null ? this.attached : currentProgram;
        if (program == null) {
            throw new WorkerError("PROGRAM_NOT_OPEN", "attach a program first");
        }
        Function fn = resolveFunction(program, params);
        DecompInterface di = decompiler(program);
        DecompileResults r = di.decompileFunction(fn, 30, monitor);
        if (!r.decompileCompleted()) {
            throw new WorkerError("DECOMPILE_TIMEOUT", "decompile failed: " + r.getErrorMessage());
        }
        JsonObject res = new JsonObject();
        res.addProperty("c", r.getDecompiledFunction().getC());
        res.addProperty("signature", r.getDecompiledFunction().getSignature());
        return res;
    }

    // Resolve a name-or-address selector to exactly one Function, or throw a structured error.
    // Address form: getFunctionAt (unambiguous). Name form: getGlobalFunctions -> 0=NOT_A_FUNCTION,
    // 1=that function, >1=AMBIGUOUS_SYMBOL with candidates. NO silent first-hit (spec 6).
    private Function resolveFunction(Program program, JsonObject params) throws Exception {
        String selector = null;
        boolean asAddress = false;
        if (params.has("function")) {
            selector = params.get("function").getAsString();
        } else if (params.has("address")) {
            selector = params.get("address").getAsString();
            asAddress = true;
        } else if (params.has("name")) {
            selector = params.get("name").getAsString();
        } else {
            throw new WorkerError("INVALID_PARAMS", "requires 'function' (name or address)");
        }
        // Try address first (spec 6 resolution order); fall back to name.
        if (!asAddress) {
            ghidra.program.model.address.Address addr = tryParseAddr(program, selector);
            if (addr != null) {
                Function at = getFunctionAt(addr);
                if (at != null) return at;
                // Parsed as an address but no function sits there. Do NOT give up: an all-hex FUNCTION
                // NAME (e.g. "add", "beef", "face", "dead") parses as a valid hex offset, so fall
                // THROUGH to the name lookup below rather than wrongly returning NOT_A_FUNCTION for a
                // real function named in hex (plan-panel R3 seat-H). `tryParseAddr` already returns null
                // (never throws) for a non-hex name like "main", so that path also falls through.
            }
            // fall through to the name lookup below
        } else {
            ghidra.program.model.address.Address addr = tryParseAddr(program, selector);
            if (addr == null) throw new WorkerError("INVALID_PARAMS", "unparseable address: " + selector);
            Function at = getFunctionAt(addr);
            if (at == null) throw new WorkerError("NOT_A_FUNCTION",
                    "no function defined at " + selector + " (the region may be unanalyzed)");
            return at;
        }
        java.util.List<Function> hits = getGlobalFunctions(selector);
        if (hits.isEmpty()) {
            throw new WorkerError("NOT_A_FUNCTION", "no function named '" + selector + "'");
        }
        if (hits.size() == 1) {
            return hits.get(0);
        }
        com.google.gson.JsonArray cands = new com.google.gson.JsonArray();
        for (Function f : hits) {
            JsonObject c = new JsonObject();
            c.addProperty("name", f.getName());
            c.addProperty("address", addrString(f.getEntryPoint()));
            cands.add(c);
        }
        throw new AmbiguousError("'" + selector + "' matches " + hits.size() + " functions", cands);
    }

    // Parse a lenient address in the program's factory; null if it does not parse (so the caller can
    // fall back to a name lookup). Never throws.
    private ghidra.program.model.address.Address tryParseAddr(Program program, String s) {
        try {
            String t = s.trim();
            if (t.endsWith("L") || t.endsWith("l")) t = t.substring(0, t.length() - 1).trim();
            int colon = t.indexOf(':');
            String off = colon >= 0 ? t.substring(colon + 1).trim() : t;
            if (off.startsWith("0x") || off.startsWith("0X")) off = off.substring(2);
            if (off.isEmpty()) return null;
            Long.parseLong(off, 16); // validate hex; reject plain names like "main"
            return program.getAddressFactory().getAddress(t.startsWith("0x") || t.startsWith("0X") ? off : t);
        } catch (Throwable x) {
            return null;
        }
    }

    // Render a Ghidra Address as the "space:offset" form the Rust AddressCanonicalizer parses.
    private String addrString(ghidra.program.model.address.Address a) {
        return a.getAddressSpace().getName() + ":" + Long.toHexString(a.getOffset());
    }

    // ---- shared read-tool helpers (M1b) ----

    // Filter match (spec §7; M1b Task-1 decision B): substring-contains by DEFAULT (linear, no
    // backtracking). Opt in to regex with regex=true -> java.util.regex, but cap the pattern length as a
    // ReDoS guard and reject an uncompilable pattern with INVALID_PARAMS. A null/empty pattern matches
    // everything. Any residual catastrophic backtracking is bounded by the host's rpc-deadline + the
    // poison/transparent-respawn engine (operator==attacker ⇒ self-DoS). RE2J/vendoring deferred.
    private static final int MAX_FILTER_PATTERN_LEN = 200;
    private final java.util.Map<String, java.util.regex.Pattern> filterCache = new java.util.HashMap<>();
    private boolean matchesFilter(String pattern, boolean regex, String text) {
        if (pattern == null || pattern.isEmpty()) return true;
        String hay = text == null ? "" : text;
        if (!regex) return hay.contains(pattern);
        if (pattern.length() > MAX_FILTER_PATTERN_LEN)
            throw new WorkerError("INVALID_PARAMS", "filter regex too long (max " + MAX_FILTER_PATTERN_LEN + " chars)");
        java.util.regex.Pattern p = filterCache.get(pattern);
        if (p == null) {
            try { p = java.util.regex.Pattern.compile(pattern); }
            catch (java.util.regex.PatternSyntaxException bad) {
                throw new WorkerError("INVALID_PARAMS", "bad filter regex: " + bad.getMessage());
            }
            filterCache.put(pattern, p);
        }
        return p.matcher(hay).find();
    }

    // Read {offset>=0, limit>=0} with defaults, for the limit+1 has_more pagination contract (spec §3.0):
    // a caller fetches up to limit matches and sets has_more when a further match exists beyond the page.
    private int[] readOffsetLimit(JsonObject params, int defLimit) {
        int offset = params.has("offset") && !params.get("offset").isJsonNull() ? params.get("offset").getAsInt() : 0;
        int limit = params.has("limit") && !params.get("limit").isJsonNull() ? params.get("limit").getAsInt() : defLimit;
        if (offset < 0) offset = 0;
        if (limit < 0) limit = 0;
        return new int[]{ offset, limit };
    }

    // Read an optional boolean param (default false); tolerates absence and explicit null.
    private boolean boolParam(JsonObject params, String key) {
        return params.has(key) && !params.get(key).isJsonNull() && params.get(key).getAsBoolean();
    }

    // inspect_function { function|name|address, max_c_lines=2000 } -> FunctionContext (spec 3.3).
    private JsonObject inspectFunction(JsonObject params) throws Exception {
        Program program = this.attached != null ? this.attached : currentProgram;
        if (program == null) throw new WorkerError("PROGRAM_NOT_OPEN", "attach a program first");
        int maxCLines = params.has("max_c_lines") ? params.get("max_c_lines").getAsInt() : 2000;
        if (maxCLines < 1) maxCLines = 1;

        Function fn = resolveFunction(program, params);

        // Gather from-data refs made BY this function's body (cap 256; spec 3.13/M1b Task 16). Iterate
        // ONLY addresses that actually have references (panel r1 seat-6) — NOT every byte in the body
        // (getBody().getAddresses would be O(function-size) API thrash on a large function).
        com.google.gson.JsonArray drefs = new com.google.gson.JsonArray(); boolean drTrunc = false;
        ghidra.program.model.symbol.ReferenceManager drm = program.getReferenceManager();
        ghidra.program.model.address.AddressIterator srcIt = drm.getReferenceSourceIterator(fn.getBody(), true);
        outer:
        while (srcIt.hasNext()) {
            ghidra.program.model.address.Address da = srcIt.next();
            for (ghidra.program.model.symbol.Reference r : drm.getReferencesFrom(da)) {
                if (!r.getReferenceType().isData()) continue;
                // D-TIDY (M2b Task 0): drop local stack/register-slot refs — they are locals, not
                // "data the function touches", and they bury the few named global/PTR refs (dogfood finding 1).
                ghidra.program.model.address.AddressSpace toSpace = r.getToAddress().getAddressSpace();
                if (toSpace.isStackSpace() || toSpace.isRegisterSpace()) continue;
                if (drefs.size() >= 256) { drTrunc = true; break outer; }
                JsonObject j = new JsonObject();
                j.addProperty("address", addrString(r.getToAddress()));
                ghidra.program.model.symbol.Symbol s = program.getSymbolTable().getPrimarySymbol(r.getToAddress());
                if (s != null) j.addProperty("name", s.getName());
                j.addProperty("ref_type", r.getReferenceType().getName());
                drefs.add(j);
            }
        }

        DecompInterface di = decompiler(program);
        DecompileResults r = di.decompileFunction(fn, 30, monitor);
        String fullC;
        if (r != null && r.decompileCompleted() && r.getDecompiledFunction() != null) {
            fullC = r.getDecompiledFunction().getC();
        } else {
            // Distinguish an empty/failed decompile (spec 4.2 seat-5) from a timeout. getErrorMessage
            // is null/empty on a clean-but-empty result; a timeout leaves a message.
            String em = (r != null) ? r.getErrorMessage() : null;
            if (em != null && em.toLowerCase().contains("timed out")) {
                throw new WorkerError("DECOMPILE_TIMEOUT", "decompile timed out: " + em);
            }
            throw new WorkerError("DECOMPILATION_FAILED",
                    "decompiler produced no output" + (em != null && !em.isEmpty() ? ": " + em : ""));
        }
        if (fullC == null || fullC.isEmpty()) {
            throw new WorkerError("DECOMPILATION_FAILED", "decompiler produced empty output");
        }

        // Cap C from the TOP by lines: signature + decls + first N body lines. Never slice through the
        // signature/opening brace (spec 3.4). Append a truncation marker so the agent knows to raise
        // max_c_lines. The head is the valuable part; the tail may be brace-unmatched by design.
        String[] lines = fullC.split("\n", -1);
        boolean truncated = lines.length > maxCLines;
        String c;
        if (!truncated) {
            c = fullC;
        } else {
            // Guarantee at least through the first "{" line so a tiny max_c_lines still returns a whole
            // signature (spec 3.4 seat-4).
            int openBrace = 0;
            for (int i = 0; i < lines.length; i++) { if (lines[i].contains("{")) { openBrace = i; break; } }
            int keep = Math.max(maxCLines, openBrace + 1);
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < Math.min(keep, lines.length); i++) { sb.append(lines[i]).append("\n"); }
            sb.append("// [ghidrust] truncated ").append(lines.length - Math.min(keep, lines.length))
              .append(" more line(s); raise max_c_lines to see the full body\n");
            c = sb.toString();
        }

        // Comments anchored anywhere in this function's body — a decompiler-INDEPENDENT breadcrumb channel
        // (the decompiler can drop comments from generated C). Bounded 100; one row per (address,type).
        com.google.gson.JsonArray comments = new com.google.gson.JsonArray();
        boolean cmtTrunc = false;
        ghidra.program.model.listing.Listing clst = program.getListing();
        ghidra.program.model.address.AddressIterator cIt =
                clst.getCommentAddressIterator(fn.getBody(), true);
        outerC:
        while (cIt.hasNext()) {
            ghidra.program.model.address.Address ca = cIt.next();
            JsonObject cobj = commentsAt(clst, ca);
            if (cobj == null) continue;
            for (java.util.Map.Entry<String, com.google.gson.JsonElement> ce : cobj.entrySet()) {
                if (comments.size() >= 100) { cmtTrunc = true; break outerC; }
                JsonObject row = new JsonObject();
                row.addProperty("address", addrString(ca));
                row.addProperty("type", ce.getKey());
                row.addProperty("comment", ce.getValue().getAsString());
                comments.add(row);
            }
        }

        JsonObject res = new JsonObject();
        res.addProperty("name", fn.getName());
        res.addProperty("entry_point", addrString(fn.getEntryPoint()));
        // M2c Task 0.2: signature + structured prototype from the Program DB (Function.getSignature()),
        // NOT the decompiler — the decompiler infers params not locked in the DB, which set_prototype's
        // CAS/write never touch (panel R2-Seat3/Seat4). The flat `signature` uses the SAME getPrototypeString
        // overload the CAS check uses, so an echoed expected_signature matches exactly.
        ghidra.program.model.listing.FunctionSignature dbSig = fn.getSignature();
        res.addProperty("signature", dbSig.getPrototypeString());
        String cc = fn.getCallingConventionName();
        res.addProperty("calling_convention", cc != null ? cc : "unknown");
        JsonObject proto = new JsonObject();
        proto.addProperty("return_type", dbSig.getReturnType().getName());
        String pcc = fn.getCallingConventionName();
        proto.addProperty("calling_convention", pcc != null ? pcc : "unknown");
        com.google.gson.JsonArray pparams = new com.google.gson.JsonArray();
        for (ghidra.program.model.data.ParameterDefinition pd : dbSig.getArguments()) {
            JsonObject po = new JsonObject();
            // NEVER emit a JSON null for `name`: ParameterDefinition.getName() can be null for an unnamed
            // param, which Rust's `ParamEntry.name: String` (non-Option) would fail to deserialize and break
            // inspect_function (agy plan-panel R1-Seat2). Coalesce to "" — the write side coerces "" back to
            // null to auto-name, so the read↔write round-trip is preserved.
            po.addProperty("name", pd.getName() != null ? pd.getName() : "");
            po.addProperty("type", pd.getDataType().getName());
            pparams.add(po);
        }
        proto.add("params", pparams);
        proto.addProperty("variadic", dbSig.hasVarArgs());
        res.add("prototype", proto);
        res.addProperty("is_thunk", fn.isThunk());
        Function thunked = fn.isThunk() ? fn.getThunkedFunction(true) : null;
        res.add("thunked_to", thunked != null
                ? new com.google.gson.JsonPrimitive(addrString(thunked.getEntryPoint()))
                : com.google.gson.JsonNull.INSTANCE);
        res.addProperty("c", c);
        res.addProperty("c_truncated", truncated);
        res.add("callers", edges(fn.getCallingFunctions(monitor)));
        res.add("callees", edges(fn.getCalledFunctions(monitor)));
        res.add("data_refs", drefs); res.addProperty("data_refs_truncated", drTrunc);
        res.add("comments", comments);
        res.addProperty("comments_truncated", cmtTrunc);

        // M2d: structured decompiler-visible locals (excludes parameters — those are in `prototype`).
        // Sourced from the SAME decompile as `c`, so the names match the body. Bounded 100.
        com.google.gson.JsonArray locals = new com.google.gson.JsonArray();
        boolean localsTrunc = false;
        ghidra.program.model.pcode.HighFunction hf = r.getHighFunction();
        if (hf != null) {
            ghidra.program.model.pcode.LocalSymbolMap lsm = hf.getLocalSymbolMap();
            java.util.Iterator<ghidra.program.model.pcode.HighSymbol> symIt = lsm.getSymbols();
            while (symIt.hasNext()) {
                ghidra.program.model.pcode.HighSymbol hs = symIt.next();
                if (hs.isParameter()) continue; // params belong to prototype
                if (locals.size() >= 100) { localsTrunc = true; break; }
                ghidra.program.model.listing.VariableStorage vs = hs.getStorage();
                JsonObject lo = new JsonObject();
                lo.addProperty("name", hs.getName());
                lo.addProperty("type", hs.getDataType() != null ? hs.getDataType().getName() : "undefined");
                lo.addProperty("storage", storageHandle(vs));
                lo.addProperty("kind", storageKind(vs));
                locals.add(lo);
            }
        }
        res.add("locals", locals);
        res.addProperty("locals_truncated", localsTrunc);
        return res;
    }

    // find_functions { filter?, regex=false, offset=0, limit=100 } -> { functions:[FunctionSummary], has_more, total? }
    private JsonObject findFunctions(JsonObject params) throws Exception {
        Program program = this.attached != null ? this.attached : currentProgram;
        if (program == null) throw new WorkerError("PROGRAM_NOT_OPEN", "attach a program first");
        String filter = params.has("filter") && !params.get("filter").isJsonNull() ? params.get("filter").getAsString() : null;
        boolean regex = boolParam(params, "regex");
        int[] ol = readOffsetLimit(params, 100); int offset = ol[0], limit = ol[1];
        com.google.gson.JsonArray out = new com.google.gson.JsonArray();
        int seen = 0; boolean hasMore = false;
        java.util.Iterator<Function> it = program.getFunctionManager().getFunctions(true).iterator();
        while (it.hasNext()) {
            Function f = it.next();
            if (!matchesFilter(filter, regex, f.getName())) continue;
            if (seen++ < offset) continue;
            if (out.size() >= limit) { hasMore = true; break; }
            JsonObject r = new JsonObject();
            r.addProperty("name", f.getName());
            r.addProperty("entry_point", addrString(f.getEntryPoint()));
            r.addProperty("signature", f.getSignature() != null ? f.getSignature().getPrototypeString() : f.getName());
            String cc = f.getCallingConventionName(); r.addProperty("calling_convention", cc != null ? cc : "unknown");
            r.addProperty("is_thunk", f.isThunk());
            Function th = f.isThunk() ? f.getThunkedFunction(true) : null;
            if (th != null) r.addProperty("thunked_to", addrString(th.getEntryPoint()));
            try { r.addProperty("size", f.getBody().getNumAddresses()); } catch (Throwable ignore) {}
            r.addProperty("external", f.isExternal());
            out.add(r);
        }
        JsonObject res = new JsonObject();
        res.add("functions", out);
        res.addProperty("has_more", hasMore);
        return res; // `total` omitted (filtered/streamed) per spec §3.0
    }

    // resolve_symbol { name } -> { candidates:[Symbol] }. 0 -> SYMBOL_NOT_FOUND; enumerates all matches.
    private JsonObject resolveSymbol(JsonObject params) throws Exception {
        Program program = this.attached != null ? this.attached : currentProgram;
        if (program == null) throw new WorkerError("PROGRAM_NOT_OPEN", "attach a program first");
        String name = params.has("name") ? params.get("name").getAsString() : null;
        if (name == null) throw new WorkerError("INVALID_PARAMS", "resolve_symbol requires name");
        com.google.gson.JsonArray cands = new com.google.gson.JsonArray();
        for (ghidra.program.model.symbol.Symbol s : program.getSymbolTable().getGlobalSymbols(name)) {
            cands.add(symbolJson(s));
        }
        if (cands.size() == 0) throw new WorkerError("SYMBOL_NOT_FOUND", "no symbol named '" + name + "'");
        JsonObject res = new JsonObject(); res.add("candidates", cands); return res;
    }

    // Shared Symbol serializer (reused by list_symbols). kind = lowercase SymbolType name.
    private JsonObject symbolJson(ghidra.program.model.symbol.Symbol s) {
        JsonObject r = new JsonObject();
        r.addProperty("name", s.getName());
        r.addProperty("address", addrString(s.getAddress()));
        r.addProperty("kind", s.getSymbolType().toString().toLowerCase());
        if (s.getParentNamespace() != null && !s.getParentNamespace().isGlobal())
            r.addProperty("namespace", s.getParentNamespace().getName());
        return r;
    }

    // list_symbols { kind="all", filter?, regex=false, offset=0, limit=100 } -> { symbols:[Symbol], has_more }
    private JsonObject listSymbols(JsonObject params) throws Exception {
        Program program = this.attached != null ? this.attached : currentProgram;
        if (program == null) throw new WorkerError("PROGRAM_NOT_OPEN", "attach a program first");
        String kind = params.has("kind") && !params.get("kind").isJsonNull() ? params.get("kind").getAsString() : "all";
        String filter = params.has("filter") && !params.get("filter").isJsonNull() ? params.get("filter").getAsString() : null;
        boolean regex = boolParam(params, "regex");
        int[] ol = readOffsetLimit(params, 100); int offset = ol[0], limit = ol[1];
        ghidra.program.model.symbol.SymbolTable st = program.getSymbolTable();
        java.util.Iterator<ghidra.program.model.symbol.Symbol> src =
            "import".equals(kind) ? st.getExternalSymbols() : st.getAllSymbols(true);
        com.google.gson.JsonArray out = new com.google.gson.JsonArray(); int seen = 0; boolean hasMore = false;
        while (src.hasNext()) {
            ghidra.program.model.symbol.Symbol s = src.next();
            if ("export".equals(kind) && !s.isExternalEntryPoint()) continue;
            if ("defined".equals(kind) && s.isExternal()) continue;
            if (!matchesFilter(filter, regex, s.getName())) continue;
            if (seen++ < offset) continue;
            if (out.size() >= limit) { hasMore = true; break; }
            out.add(symbolJson(s));
        }
        JsonObject res = new JsonObject(); res.add("symbols", out); res.addProperty("has_more", hasMore); return res;
    }

    // list_strings { filter?, regex=false, offset=0, limit=200 } -> { strings:[StringItem], has_more }
    private JsonObject listStrings(JsonObject params) throws Exception {
        Program program = this.attached != null ? this.attached : currentProgram;
        if (program == null) throw new WorkerError("PROGRAM_NOT_OPEN", "attach a program first");
        String filter = params.has("filter") && !params.get("filter").isJsonNull() ? params.get("filter").getAsString() : null;
        boolean regex = boolParam(params, "regex");
        int[] ol = readOffsetLimit(params, 200); int offset = ol[0], limit = ol[1];
        com.google.gson.JsonArray out = new com.google.gson.JsonArray(); int seen = 0; boolean hasMore = false;
        ghidra.program.model.listing.DataIterator it =
            ghidra.program.util.DefinedStringIterator.forProgram(program);
        while (it.hasNext()) {
            ghidra.program.model.listing.Data d = it.next();
            Object val = d.getValue(); String sv = val != null ? val.toString() : "";
            if (!matchesFilter(filter, regex, sv)) continue;
            if (seen++ < offset) continue;
            if (out.size() >= limit) { hasMore = true; break; }
            JsonObject r = new JsonObject();
            r.addProperty("address", addrString(d.getAddress()));
            r.addProperty("value", sv);
            r.addProperty("length", (long) d.getLength());
            r.addProperty("encoding", d.getDataType().getName());
            out.add(r);
        }
        JsonObject res = new JsonObject(); res.add("strings", out); res.addProperty("has_more", hasMore); return res;
    }

    // get_xrefs { target, direction="both", offset=0, limit=100 } -> { xrefs:[Reference], has_more }
    // target resolves as an address OR any symbol (function/data/label) — NOT just functions, so xrefs
    // to a data symbol (e.g. g_banner) work too. NO silent first-hit on an ambiguous name (spec 6).
    private JsonObject getXrefs(JsonObject params) throws Exception {
        Program program = this.attached != null ? this.attached : currentProgram;
        if (program == null) throw new WorkerError("PROGRAM_NOT_OPEN", "attach a program first");
        String target = params.has("target") ? params.get("target").getAsString() : null;
        if (target == null) throw new WorkerError("INVALID_PARAMS", "get_xrefs requires target");
        String dir = params.has("direction") && !params.get("direction").isJsonNull() ? params.get("direction").getAsString() : "both";
        ghidra.program.model.address.Address addr = tryParseAddr(program, target);
        if (addr == null) { // resolve as ANY symbol (function OR data label/string — panel r1 seat-2)
            java.util.List<ghidra.program.model.symbol.Symbol> syms = program.getSymbolTable().getGlobalSymbols(target);
            if (syms.isEmpty()) throw new WorkerError("SYMBOL_NOT_FOUND", "no symbol named '" + target + "'");
            if (syms.size() > 1) { // NO silent first-hit (spec §6) — panel r2: surface candidates like inspect_function
                com.google.gson.JsonArray cands = new com.google.gson.JsonArray();
                for (ghidra.program.model.symbol.Symbol s : syms) { JsonObject c = new JsonObject(); c.addProperty("name", s.getName()); c.addProperty("address", addrString(s.getAddress())); cands.add(c); }
                throw new AmbiguousError("'" + target + "' matches " + syms.size() + " symbols", cands);
            }
            addr = syms.get(0).getAddress(); // xrefs to a data symbol (e.g. g_banner) must work, not just functions
        }
        if (program.getMemory().getBlock(addr) == null)
            throw new WorkerError("ADDRESS_NOT_FOUND", "address not mapped: " + target);
        ghidra.program.model.symbol.ReferenceManager rm = program.getReferenceManager();
        int[] ol = readOffsetLimit(params, 100); int offset = ol[0], limit = ol[1];
        java.util.List<ghidra.program.model.symbol.Reference> refs = new java.util.ArrayList<>();
        if (!"from".equals(dir)) for (ghidra.program.model.symbol.Reference r : rm.getReferencesTo(addr)) refs.add(r);
        if (!"to".equals(dir)) for (ghidra.program.model.symbol.Reference r : rm.getReferencesFrom(addr)) refs.add(r);
        com.google.gson.JsonArray out = new com.google.gson.JsonArray(); int seen = 0; boolean hasMore = false;
        for (ghidra.program.model.symbol.Reference r : refs) {
            if (seen++ < offset) continue;
            if (out.size() >= limit) { hasMore = true; break; }
            JsonObject j = new JsonObject();
            j.addProperty("from_address", addrString(r.getFromAddress()));
            j.addProperty("to_address", addrString(r.getToAddress()));
            j.addProperty("ref_type", r.getReferenceType().getName());
            Function ff = program.getFunctionManager().getFunctionContaining(r.getFromAddress());
            if (ff != null) j.addProperty("from_function", ff.getName());
            out.add(j);
        }
        JsonObject res = new JsonObject(); res.add("xrefs", out); res.addProperty("has_more", hasMore); return res;
    }

    // get_disassembly { target, offset=0, limit=200 } -> { instructions:[Instruction], has_more, total }
    // target resolves via the shared function resolver (name-or-address; can throw AMBIGUOUS_SYMBOL).
    private JsonObject getDisassembly(JsonObject params) throws Exception {
        Program program = this.attached != null ? this.attached : currentProgram;
        if (program == null) throw new WorkerError("PROGRAM_NOT_OPEN", "attach a program first");
        Function fn = resolveFunction(program, remap(params, "target")); // reuse §6 resolver
        int[] ol = readOffsetLimit(params, 200); int offset = ol[0], limit = ol[1];
        ghidra.program.model.listing.Listing lst = program.getListing();
        // Collect first so total = EXACT instruction count — cheap for one bounded function, and spec §3.6
        // mandates total here (unlike the O(N^2) filtered-table case) — panel r1 seat-3.
        java.util.List<ghidra.program.model.listing.Instruction> all = new java.util.ArrayList<>();
        for (ghidra.program.model.listing.Instruction i0 : lst.getInstructions(fn.getBody(), true)) all.add(i0);
        long total = all.size();
        com.google.gson.JsonArray out = new com.google.gson.JsonArray(); boolean hasMore = false;
        for (int idx = offset; idx < all.size(); idx++) {
            if (out.size() >= limit) { hasMore = true; break; }
            ghidra.program.model.listing.Instruction ins = all.get(idx);
            JsonObject j = new JsonObject();
            j.addProperty("address", addrString(ins.getAddress()));
            StringBuilder hex = new StringBuilder();
            try { for (byte b : ins.getBytes()) hex.append(String.format("%02x", b & 0xFF)); } catch (Throwable ignore) {}
            j.addProperty("bytes", hex.toString());
            j.addProperty("mnemonic", ins.getMnemonicString());
            StringBuilder ops = new StringBuilder();
            for (int i = 0; i < ins.getNumOperands(); i++) { if (i > 0) ops.append(", "); ops.append(ins.getDefaultOperandRepresentation(i)); }
            j.addProperty("operands", ops.toString());
            JsonObject cmts = commentsAt(lst, ins.getAddress());
            if (cmts != null) j.add("comments", cmts);
            out.add(j);
        }
        JsonObject res = new JsonObject(); res.add("instructions", out); res.addProperty("has_more", hasMore); res.addProperty("total", total); return res;
    }

    // read_bytes { address, offset=0 (decimal), length=256 (clamped <=4096) } -> { address, length, bytes, truncated }
    private JsonObject readBytes(JsonObject params) throws Exception {
        Program program = this.attached != null ? this.attached : currentProgram;
        if (program == null) throw new WorkerError("PROGRAM_NOT_OPEN", "attach a program first");
        String a = params.has("address") ? params.get("address").getAsString() : null;
        if (a == null) throw new WorkerError("INVALID_PARAMS", "read_bytes requires address");
        ghidra.program.model.address.Address base = tryParseAddr(program, a);
        if (base == null) throw new WorkerError("INVALID_PARAMS", "unparseable address: " + a);
        long offset = params.has("offset") ? params.get("offset").getAsLong() : 0L;
        long length = params.has("length") ? params.get("length").getAsLong() : 256L;
        boolean truncated = false; if (length > 4096) { length = 4096; truncated = true; } if (length < 0) length = 0;
        ghidra.program.model.address.Address start;
        try { start = base.add(offset); }
        catch (ghidra.program.model.address.AddressOutOfBoundsException oob) {
            throw new WorkerError("ADDRESS_NOT_FOUND", "address+offset out of bounds: " + a); }
        byte[] buf = new byte[(int) length];
        int got;
        try { got = program.getMemory().getBytes(start, buf); }
        catch (ghidra.program.model.mem.MemoryAccessException mae) {
            throw new WorkerError("ADDRESS_NOT_FOUND", "memory not readable at " + addrString(start)); }
        StringBuilder hex = new StringBuilder(); for (int i = 0; i < got; i++) hex.append(String.format("%02x", buf[i] & 0xFF));
        JsonObject res = new JsonObject();
        res.addProperty("address", addrString(start)); res.addProperty("length", (long) got);
        res.addProperty("bytes", hex.toString()); res.addProperty("truncated", truncated);
        return res;
    }

    // get_datatype { name } -> DataTypeInfo (struct/union/enum/other); AMBIGUOUS_DATATYPE if >1 hit.
    private JsonObject getDatatype(JsonObject params) throws Exception {
        Program program = this.attached != null ? this.attached : currentProgram;
        if (program == null) throw new WorkerError("PROGRAM_NOT_OPEN", "attach a program first");
        String name = params.has("name") ? params.get("name").getAsString() : null;
        if (name == null) throw new WorkerError("INVALID_PARAMS", "get_datatype requires name");
        java.util.List<ghidra.program.model.data.DataType> hits = new java.util.ArrayList<>();
        program.getDataTypeManager().findDataTypes(name, hits);
        if (hits.isEmpty()) throw new WorkerError("DATATYPE_NOT_FOUND", "no data type named '" + name + "'");
        if (hits.size() > 1) {
            com.google.gson.JsonArray cands = new com.google.gson.JsonArray();
            for (ghidra.program.model.data.DataType dt : hits) { JsonObject c = new JsonObject(); c.addProperty("name", dt.getPathName()); cands.add(c); }
            throw new AmbiguousError("AMBIGUOUS_DATATYPE", "'" + name + "' matches " + hits.size() + " types", cands);
        }
        return dataTypeJson(hits.get(0));
    }
    private JsonObject dataTypeJson(ghidra.program.model.data.DataType dt) {
        JsonObject r = new JsonObject();
        r.addProperty("name", dt.getName());
        r.addProperty("size", (long) dt.getLength());
        if (dt instanceof ghidra.program.model.data.Structure || dt instanceof ghidra.program.model.data.Union) {
            r.addProperty("kind", dt instanceof ghidra.program.model.data.Union ? "union" : "struct");
            com.google.gson.JsonArray members = new com.google.gson.JsonArray();
            for (ghidra.program.model.data.DataTypeComponent c : ((ghidra.program.model.data.Composite) dt).getComponents()) {
                JsonObject m = new JsonObject();
                m.addProperty("name", c.getFieldName() != null ? c.getFieldName() : ("field_" + c.getOrdinal()));
                m.addProperty("type", c.getDataType().getName());
                m.addProperty("offset", (long) c.getOffset());
                m.addProperty("size", (long) c.getLength());
                members.add(m);
            }
            r.add("members", members);
        } else if (dt instanceof ghidra.program.model.data.Enum) {
            r.addProperty("kind", "enum");
            ghidra.program.model.data.Enum en = (ghidra.program.model.data.Enum) dt;
            com.google.gson.JsonArray vals = new com.google.gson.JsonArray();
            for (String n : en.getNames()) { JsonObject v = new JsonObject(); v.addProperty("name", n); v.addProperty("value", Long.toString(en.getValue(n))); vals.add(v); }
            r.add("values", vals);
        } else {
            r.addProperty("kind", dt.getClass().getSimpleName().toLowerCase());
        }
        return r;
    }

    // list_segments {} -> { segments:[Segment] } (NOT paginated — block counts are small).
    private JsonObject listSegments(JsonObject params) {
        Program program = this.attached != null ? this.attached : currentProgram;
        if (program == null) throw new WorkerError("PROGRAM_NOT_OPEN", "attach a program first");
        com.google.gson.JsonArray out = new com.google.gson.JsonArray();
        for (ghidra.program.model.mem.MemoryBlock b : program.getMemory().getBlocks()) {
            JsonObject j = new JsonObject();
            j.addProperty("name", b.getName());
            j.addProperty("start", addrString(b.getStart()));
            j.addProperty("end", addrString(b.getEnd()));
            j.addProperty("size", b.getSize());
            j.addProperty("readable", b.isRead());
            j.addProperty("writable", b.isWrite());
            j.addProperty("executable", b.isExecute());
            j.addProperty("initialized", b.isInitialized());
            out.add(j);
        }
        JsonObject res = new JsonObject(); res.add("segments", out); return res;
    }

    // list_data_items { filter?, regex=false, offset=0, limit=200 } -> { data:[DataItem], has_more }
    private JsonObject listDataItems(JsonObject params) throws Exception {
        Program program = this.attached != null ? this.attached : currentProgram;
        if (program == null) throw new WorkerError("PROGRAM_NOT_OPEN", "attach a program first");
        String filter = params.has("filter") && !params.get("filter").isJsonNull() ? params.get("filter").getAsString() : null;
        boolean regex = boolParam(params, "regex");
        int[] ol = readOffsetLimit(params, 200); int offset = ol[0], limit = ol[1];
        com.google.gson.JsonArray out = new com.google.gson.JsonArray(); int seen = 0; boolean hasMore = false;
        java.util.Iterator<ghidra.program.model.listing.Data> it = program.getListing().getDefinedData(true).iterator();
        while (it.hasNext()) {
            ghidra.program.model.listing.Data d = it.next();
            String label = d.getLabel();
            if (filter != null && !matchesFilter(filter, regex, label != null ? label : "")) continue;
            if (seen++ < offset) continue;
            if (out.size() >= limit) { hasMore = true; break; }
            JsonObject j = new JsonObject();
            j.addProperty("address", addrString(d.getAddress()));
            if (label != null) j.addProperty("name", label);
            j.addProperty("data_type", d.getDataType().getName());
            try { Object v = d.getValue(); if (v != null) j.addProperty("value", v.toString()); } catch (Throwable ignore) {}
            j.addProperty("size", (long) d.getLength());
            out.add(j);
        }
        JsonObject res = new JsonObject(); res.add("data", out); res.addProperty("has_more", hasMore); return res;
    }

    // describe_address { address } -> AddressInfo (spec 3.x, M1b Task 17). TOTAL: an unmapped or
    // unparseable address is a valid answer (mapped:false), never a WorkerError.
    private JsonObject describeAddress(JsonObject params) {
        Program program = this.attached != null ? this.attached : currentProgram;
        if (program == null) throw new WorkerError("PROGRAM_NOT_OPEN", "attach a program first");
        String a = params.has("address") ? params.get("address").getAsString() : null;
        if (a == null) throw new WorkerError("INVALID_PARAMS", "describe_address requires address");
        ghidra.program.model.address.Address addr = tryParseAddr(program, a);
        JsonObject res = new JsonObject();
        if (addr == null || program.getMemory().getBlock(addr) == null) {
            res.addProperty("address", a); res.addProperty("mapped", false); res.addProperty("is_code", false);
            return res; // unmapped is a valid answer, not an error (spec §3.11)
        }
        res.addProperty("address", addrString(addr)); res.addProperty("mapped", true);
        res.addProperty("segment", program.getMemory().getBlock(addr).getName());
        res.addProperty("is_code", program.getListing().getInstructionContaining(addr) != null);
        Function cf = program.getFunctionManager().getFunctionContaining(addr);
        if (cf != null) { JsonObject j = new JsonObject(); j.addProperty("name", cf.getName()); j.addProperty("entry_point", addrString(cf.getEntryPoint())); res.add("containing_function", j); }
        ghidra.program.model.symbol.Symbol s = program.getSymbolTable().getPrimarySymbol(addr);
        if (s != null) { JsonObject j = new JsonObject(); j.addProperty("name", s.getName()); j.addProperty("kind", s.getSymbolType().toString().toLowerCase()); res.add("symbol", j); }
        ghidra.program.model.listing.Data d = program.getListing().getDataContaining(addr);
        if (d != null && d.isDefined()) res.addProperty("data_type", d.getDataType().getName());
        JsonObject cmts = commentsAt(program.getListing(), addr);
        if (cmts != null) res.add("comments", cmts);
        return res;
    }

    // Required string param: absent or JSON-null -> INVALID_PARAMS (no NPE — checks presence before getAsString).
    private static String reqStr(JsonObject params, String key) {
        if (!params.has(key) || params.get(key).isJsonNull())
            throw new WorkerError("INVALID_PARAMS", "missing required parameter: " + key);
        return params.get(key).getAsString();
    }

    @FunctionalInterface interface TxBody { void run() throws Exception; }

    // Wraps ONLY start/end (spec §4.1). save() + revert are orchestrated by rename() (§4.3), NOT here.
    // Operates on the caller-supplied program (the effective attached-or-bootstrap program).
    private void withTransaction(Program program, String desc, TxBody body) {
        int id = program.startTransaction(desc);
        boolean commit = false;
        try {
            body.run();
            commit = true;
        } catch (ghidra.util.exception.DuplicateNameException | ghidra.util.exception.InvalidInputException e) {
            // spec §4 table: exact Ghidra message goes in details.reason so the LLM can self-correct.
            com.google.gson.JsonObject d = new com.google.gson.JsonObject();
            d.addProperty("reason", e.getMessage());
            throw new WorkerError("INVALID_PARAMS", "invalid new name", d);
        } catch (WorkerError we) {
            throw we;
        } catch (Throwable t) {
            throw new WorkerError("TRANSACTION_FAILED", String.valueOf(t));
        } finally {
            program.endTransaction(id, commit); // commit=false => rollback
        }
    }

    // comment { target, comment_type, new_comment, expected_comment? } -> CommentResult (M2b §3.1).
    // Set/clear a comment on the code unit at the resolved address. already_applied FIRST (§3.1 precedence),
    // then optional CAS guard (STATE_CONFLICT), then apply + auto-save (durable). Empty new_comment clears.
    private JsonObject comment(JsonObject params) throws Exception {
        Program program = this.attached != null ? this.attached : currentProgram;
        if (program == null) throw new WorkerError("PROGRAM_NOT_OPEN", "no program is open");
        String target = reqStr(params, "target");
        String typeStr = reqStr(params, "comment_type");
        String newComment = reqStr(params, "new_comment"); // "" clears
        ghidra.program.model.listing.CommentType ctype = parseCommentType(typeStr);

        ghidra.program.model.address.Address addr = resolveTargetAddress(program, target);
        ghidra.program.model.listing.Listing listing = program.getListing();
        // Offcut guard (panel R4-S3): setComment stores at ANY address, but the listing only RENDERS comments
        // anchored at a code unit's START — an offcut comment (inside a multi-byte instruction/data) is a
        // permanent "ghost" the human never sees, though this tool's own re-read still finds it (false
        // already_applied). Reject true offcuts. NOTE: an instruction AT its start IS a valid comment target
        // (unlike set_datatype), so this guard only trips when addr != the containing unit's min address.
        ghidra.program.model.listing.CodeUnit cuc = listing.getCodeUnitContaining(addr);
        if (cuc != null && !cuc.getMinAddress().equals(addr)) {
            throw new WorkerError("INVALID_PARAMS",
                    "address " + addr + " is inside a code unit starting at " + cuc.getMinAddress()
                    + "; comment that start address (an offcut comment would be invisible in the listing)");
        }
        String currentRaw = listing.getComment(ctype, addr); // null when none
        String current = currentRaw == null ? "" : currentRaw;

        JsonObject res = new JsonObject();
        res.addProperty("address", addr.toString());
        res.addProperty("comment_type", typeStr);
        res.addProperty("durable", true);

        if (current.equals(newComment)) {                 // already_applied — FIRST, no tx/save (§3.1)
            res.addProperty("status", "already_applied");
            if (!current.isEmpty()) res.addProperty("previous_comment", current);
            return res;
        }
        if (params.has("expected_comment") && !params.get("expected_comment").isJsonNull()) {
            String expected = params.get("expected_comment").getAsString();
            if (!current.equals(expected)) {              // drift -> STATE_CONFLICT (§4.2)
                JsonObject d = new JsonObject();
                d.addProperty("address", addr.toString());
                d.addProperty("field", "comment");
                d.addProperty("comment_type", typeStr);
                d.addProperty("expected", expected);
                d.addProperty("actual", current);
                throw new WorkerError("STATE_CONFLICT",
                        "current " + typeStr + " comment differs from expected_comment", d);
            }
        }

        final String toSet = newComment.isEmpty() ? null : newComment; // null clears
        withTransaction(program, "comment " + typeStr + " @ " + addr,
                () -> program.getListing().setComment(addr, ctype, toSet));
        // M2a save dance (oracle: rename L908-929). end(true) closes the script tx so save() can lock; on
        // failure re-apply the captured previous comment and re-start() before throwing (R4 tx-state invariant).
        try {
            end(true);
            program.getDomainFile().save(monitor);
        } catch (Throwable saveFail) {
            try {
                final String revert = currentRaw; // restore prior (null clears)
                withTransaction(program, "revert failed comment save",
                        () -> program.getListing().setComment(addr, ctype, revert));
            } catch (Throwable revertFail) {
                // Double-fault (save AND revert failed): in-memory is dirty vs disk. A RETURNED
                // WORKER_UNAVAILABLE keeps THIS JVM alive (execute.rs treats a Failure frame as a domain
                // error, NOT a crash), so a retry would read the dirty in-memory state and falsely report
                // already_applied/durable (phantom durability). Halt so the host sees a TRANSPORT crash and
                // respawns a CLEAN JVM from disk; the transparent retry then re-applies (panel R2-F4).
                Runtime.getRuntime().halt(70);
            }
            start();
            throw new WorkerError("TRANSACTION_FAILED", "edit rolled back (save to disk failed): " + saveFail);
        }
        start();
        res.addProperty("status", newComment.isEmpty() ? "cleared" : "set");
        if (!current.isEmpty()) res.addProperty("previous_comment", current);
        return res;
    }

    // Map the wire enum-string to Ghidra's modern CommentType. Unknown -> INVALID_PARAMS (defence in depth;
    // the Rust schema already rejects bad values with -32602).
    private ghidra.program.model.listing.CommentType parseCommentType(String s) {
        switch (s) {
            case "eol":        return ghidra.program.model.listing.CommentType.EOL;
            case "pre":        return ghidra.program.model.listing.CommentType.PRE;
            case "post":       return ghidra.program.model.listing.CommentType.POST;
            case "plate":      return ghidra.program.model.listing.CommentType.PLATE;
            case "repeatable": return ghidra.program.model.listing.CommentType.REPEATABLE;
            default: throw new WorkerError("INVALID_PARAMS",
                    "comment_type must be one of eol|pre|post|plate|repeatable, got: " + s);
        }
    }

    // Build a {type: text} comments object for an address via the modern CommentType API; null if none.
    private JsonObject commentsAt(ghidra.program.model.listing.Listing listing,
            ghidra.program.model.address.Address addr) {
        JsonObject c = new JsonObject();
        putCmt(c, "eol", listing.getComment(ghidra.program.model.listing.CommentType.EOL, addr));
        putCmt(c, "pre", listing.getComment(ghidra.program.model.listing.CommentType.PRE, addr));
        putCmt(c, "post", listing.getComment(ghidra.program.model.listing.CommentType.POST, addr));
        putCmt(c, "plate", listing.getComment(ghidra.program.model.listing.CommentType.PLATE, addr));
        putCmt(c, "repeatable", listing.getComment(ghidra.program.model.listing.CommentType.REPEATABLE, addr));
        return c.size() > 0 ? c : null;
    }
    private static void putCmt(JsonObject c, String key, String val) {
        if (val != null && !val.isEmpty()) c.addProperty(key, val);
    }

    // set_datatype { target, datatype_name, expected_datatype? } -> SetDatatypeResult (M2b §3.2).
    // Retypes DATA at the resolved address (variables/params are M2c). datatype_name "undefined" is the
    // CLEAR sentinel. already_applied via DataType.isEquivalent (R3); optional CAS on display-name;
    // CLEAR_SINGLE_DATA only (R1, non-destructive); dynamic-length sized by Ghidra (R2); auto-save.
    private JsonObject setDatatype(JsonObject params) throws Exception {
        Program program = this.attached != null ? this.attached : currentProgram;
        if (program == null) throw new WorkerError("PROGRAM_NOT_OPEN", "no program is open");
        String target = reqStr(params, "target");
        String typeName = reqStr(params, "datatype_name");
        ghidra.program.model.address.Address addr = resolveTargetAddress(program, target);
        ghidra.program.model.listing.Listing listing = program.getListing();

        // Offcut / code guard (panel R3-S5). getDataAt/getInstructionAt are START-anchored: they return null
        // for an address INSIDE a unit, so without this an OFFCUT target (e.g. addr+1 inside a dword) would be
        // silently mis-handled — a clear would falsely report already_applied ("nothing here"), and an apply
        // would clear the containing unit and leave a gap. getCodeUnitContaining returns the Instruction/Data
        // actually covering addr; reject CODE and OFFCUTs up-front so the getDataAt(addr) below is reliable.
        // (This subsumes the clear-path instruction guard — instructions are rejected here for BOTH paths.)
        ghidra.program.model.listing.CodeUnit cu = listing.getCodeUnitContaining(addr);
        if (cu instanceof ghidra.program.model.listing.Instruction) {
            throw new WorkerError("INVALID_PARAMS",
                    "that address is code (instruction at " + cu.getMinAddress() + "), not data; this tool "
                    + "targets DATA. Retyping a function variable or parameter arrives with set_prototype (M2c).");
        }
        if (cu != null && !cu.getMinAddress().equals(addr)) {
            throw new WorkerError("INVALID_PARAMS",
                    "address " + addr + " is inside a defined data unit starting at " + cu.getMinAddress()
                    + "; pass that start address");
        }

        // getDataAt (now reliable — addr is a unit start or undefined): UNDEFINED bytes -> a non-null Data whose
        // isDefined()==false (panel-F5-r2 — Ghidra's data model; do NOT treat null as the only "no data" signal).
        ghidra.program.model.listing.Data existing = listing.getDataAt(addr);
        boolean hasDefinedData = existing != null && existing.isDefined();
        ghidra.program.model.data.DataType prevDt = hasDefinedData ? existing.getDataType() : null;
        final int prevLen = hasDefinedData ? existing.getLength() : 0; // CONCRETE instance length (panel-F5), for a lossless revert
        String prevDisplay = hasDefinedData ? prevDt.getDisplayName() : "undefined"; // undefined location reads as "undefined" (spec §7 D1)

        JsonObject res = new JsonObject();
        res.addProperty("address", addr.toString());
        res.addProperty("durable", true);

        boolean isClear = "undefined".equals(typeName);

        // Resolve the target type up-front (real types only), so already_applied + guard can use it.
        ghidra.program.model.data.DataType dt = null;
        if (!isClear) {
            dt = resolveDataType(program, typeName); // throws DATATYPE_NOT_FOUND / AMBIGUOUS_DATATYPE
        }

        // (Instruction + offcut targets were rejected up-front by the getCodeUnitContaining guard above —
        //  R4/F1 footgun closed there for BOTH the clear and apply paths.)

        // --- already_applied (§3.1 precedence). Semantic equivalence, NOT name-string (R3). ---
        if (isClear) {
            if (!hasDefinedData) { // already undefined (getDataAt null OR non-null-but-undefined) — panel-F5-r2
                res.addProperty("status", "already_applied");
                res.addProperty("datatype", "undefined");
                res.addProperty("length", 0);
                return res;
            }
        } else {
            if (hasDefinedData && existing.getDataType().isEquivalent(dt)) {
                res.addProperty("status", "already_applied");
                res.addProperty("datatype", existing.getDataType().getDisplayName());
                res.addProperty("length", existing.getLength());
                return res;
            }
        }

        // --- optional CAS guard: compare caller's belief against the current DISPLAY NAME (§3.2). ---
        if (params.has("expected_datatype") && !params.get("expected_datatype").isJsonNull()) {
            String expected = params.get("expected_datatype").getAsString();
            if (!prevDisplay.equals(expected)) {
                JsonObject d = new JsonObject();
                d.addProperty("address", addr.toString());
                d.addProperty("field", "datatype");
                d.addProperty("expected", expected);
                d.addProperty("actual", prevDisplay);
                throw new WorkerError("STATE_CONFLICT",
                        "current datatype '" + prevDisplay + "' differs from expected_datatype '" + expected + "'", d);
            }
        }

        // --- clear sentinel: instruction target already rejected above (F1); `existing` is defined DATA here. ---
        if (isClear) {
            final ghidra.program.model.address.Address clearEnd = existing.getMaxAddress(); // span the whole unit
            withTransaction(program, "clear data @ " + addr,
                    () -> program.getListing().clearCodeUnits(addr, clearEnd, false));
            saveOrRevertDatatype(program, addr, prevDt, prevLen); // save dance + R4 revert (below)
            res.addProperty("status", "cleared");
            res.addProperty("datatype", "undefined");
            res.addProperty("previous_datatype", prevDisplay);
            res.addProperty("length", 0);
            return res;
        }

        // --- apply a real type. CLEAR_SINGLE_DATA (R1); concrete length for dynamic types (panel-F2). ---
        final ghidra.program.model.data.DataType applyDt = dt;
        final int length = concreteLength(program, addr, dt); // NEVER pass dt.getLength()==-1 into createData (F2)
        withTransaction(program, "set_datatype " + typeName + " @ " + addr, () -> {
            try {
                ghidra.program.model.data.DataUtilities.createData(program, addr, applyDt, length,
                        ghidra.program.model.data.DataUtilities.ClearDataMode.CLEAR_SINGLE_DATA);
            } catch (ghidra.program.model.util.CodeUnitInsertionException cie) {
                // overlaps an instruction, or the type won't fit / would hit a following defined unit (R1):
                // user-fixable -> INVALID_PARAMS with the exact Ghidra message (M2a granularity choice).
                JsonObject d = new JsonObject();
                d.addProperty("reason", cie.getMessage());
                throw new WorkerError("INVALID_PARAMS",
                        "cannot apply '" + typeName + "' at " + addr + ": " + cie.getMessage()
                        + " (pick a data address, or clear the neighbour first with datatype_name:\"undefined\")", d);
            }
        });
        saveOrRevertDatatype(program, addr, prevDt, prevLen);

        ghidra.program.model.listing.Data now = program.getListing().getDataAt(addr);
        res.addProperty("status", "set");
        res.addProperty("datatype", now != null ? now.getDataType().getDisplayName() : typeName);
        if (prevDt != null) res.addProperty("previous_datatype", prevDisplay);
        res.addProperty("length", now != null ? now.getLength() : 0);
        return res;
    }

    // set_prototype { target, return_type, calling_convention, params:[{name?,type}], variadic?,
    //   expected_signature? } -> SetPrototypeResult (M2c §3). Whole-function signature replace on the
    //   M2a/M2b withTransaction + save-dance + halt(70) plumbing. All Ghidra APIs javac-pinned (spec §7).
    private JsonObject setPrototype(JsonObject params) throws Exception {
        Program program = this.attached != null ? this.attached : currentProgram;
        if (program == null) throw new WorkerError("PROGRAM_NOT_OPEN", "no program is open");
        String returnTypeName = reqStr(params, "return_type");
        String callingConvention = reqStr(params, "calling_convention");
        reqStr(params, "target"); // presence check (resolved via remap below)
        if (!params.has("params") || !params.get("params").isJsonArray())
            throw new WorkerError("INVALID_PARAMS", "set_prototype requires a params array (empty [] = no arguments)");
        com.google.gson.JsonArray paramArr = params.getAsJsonArray("params");
        boolean variadic = boolParam(params, "variadic");

        // 1) Resolve target -> FUNCTION (name or address; reuse §6 resolver). All of §1-6 below are PURE
        //    READS (no DB mutation) so a rejected request mutates nothing (panel R3-Seat1); the only
        //    mutation is the tx-guarded apply/synthesis in §7-8.
        Function fn = resolveFunction(program, remap(params, "target"));
        if (fn.isThunk()) {
            Function tf = fn.getThunkedFunction(true);
            throw new WorkerError("INVALID_PARAMS",
                "can't set the signature of a thunk; edit the thunked function"
                + (tf != null ? " at " + addrString(tf.getEntryPoint()) : "") + " instead");
        }
        if (fn.isExternal())
            throw new WorkerError("INVALID_PARAMS",
                "can't set the signature of external function '" + fn.getName() + "' (an import has no body)");
        if (fn.hasCustomVariableStorage())
            throw new WorkerError("INVALID_PARAMS",
                "'" + fn.getName() + "' uses custom variable storage (__usercall/explicit registers); "
                + "set_prototype applies dynamic storage and would discard it — not supported yet");

        // 2) Validate calling_convention against the PROGRAM's set (P6). No host-side sentinel (R1-Seat2).
        java.util.Collection<String> ccNames = program.getFunctionManager().getCallingConventionNames();
        if (ccNames == null || !ccNames.contains(callingConvention)) {
            JsonObject d = new JsonObject();
            d.addProperty("reason", "unknown calling convention '" + callingConvention + "'");
            d.add("valid", gson.toJsonTree(ccNames));
            throw new WorkerError("INVALID_PARAMS",
                "unknown calling_convention '" + callingConvention + "'; valid: " + ccNames, d);
        }

        // 3) Validate each param entry (pure). Empty [] = no-arg; [{type:"void"}] REJECTED (R2-Seat1);
        //    name "" -> null so ParameterImpl auto-names (R2-Seat5).
        java.util.List<String> paramTypeNames = new java.util.ArrayList<>();
        java.util.List<String> paramNames = new java.util.ArrayList<>();
        for (int i = 0; i < paramArr.size(); i++) {
            // Defence in depth (agy plan-panel R2-Seat4): the host schema already rejects a non-object
            // element with -32602, but a direct/buggy caller could send params:["int"]; getAsJsonObject()
            // would throw IllegalStateException -> WORKER_UNAVAILABLE. Reject cleanly as INVALID_PARAMS.
            if (!paramArr.get(i).isJsonObject())
                throw new WorkerError("INVALID_PARAMS", "params[" + i + "] must be an object with a 'type' field");
            JsonObject p = paramArr.get(i).getAsJsonObject();
            if (!p.has("type") || p.get("type").isJsonNull())
                throw new WorkerError("INVALID_PARAMS", "params[" + i + "] missing 'type'");
            String pt = p.get("type").getAsString();
            if ("void".equalsIgnoreCase(pt))
                throw new WorkerError("INVALID_PARAMS",
                    "params[" + i + "] type 'void' is not a valid parameter type; use empty params:[] for a no-argument function");
            paramTypeNames.add(pt);
            String pn = (p.has("name") && !p.get("name").isJsonNull()) ? p.get("name").getAsString() : "";
            paramNames.add(pn.isEmpty() ? null : pn);
        }

        // 4) Read the CURRENT DB prototype string (previous_signature + CAS comparand; NOT the decompiler).
        String currentProto = fn.getSignature().getPrototypeString();

        // 5) Name-resolve every type (pure). A name MISS is deferred to the §8 tx-synthesis path (the
        //    DataTypeParser fallback is a DB mutation). Ambiguous -> AMBIGUOUS_DATATYPE now.
        ghidra.program.model.data.DataType retByName = resolveTypeByName(program, returnTypeName);
        ghidra.program.model.data.DataType[] paramByName =
                new ghidra.program.model.data.DataType[paramTypeNames.size()];
        boolean needsSynth = (retByName == null);
        for (int i = 0; i < paramTypeNames.size(); i++) {
            paramByName[i] = resolveTypeByName(program, paramTypeNames.get(i));
            if (paramByName[i] == null) needsSynth = true;
        }

        JsonObject res = new JsonObject();
        res.addProperty("address", fn.getEntryPoint().toString());
        res.addProperty("name", fn.getName());
        res.addProperty("durable", true);

        // 6) FAST PATH — all types name-resolved: already_applied + CAS with NO transaction (§3 steps 3-4;
        //    already_applied FIRST for respawn-retry-safety, M2b precedence).
        if (!needsSynth) {
            ghidra.program.model.data.FunctionDefinitionDataType desired =
                    buildDesiredDef(retByName, paramByName, paramNames, callingConvention, variadic);
            if (signatureAlreadyApplied(fn, desired, paramNames, callingConvention, variadic)) {
                res.addProperty("status", "already_applied");
                res.addProperty("signature", currentProto);
                return res;
            }
            casCheck(params, currentProto, fn); // STATE_CONFLICT if expected_signature drifted
            ghidra.program.model.data.FunctionDefinitionDataType prevDef =
                    new ghidra.program.model.data.FunctionDefinitionDataType(fn.getSignature());
            withTransaction(program, "set_prototype " + fn.getName(),
                    () -> applyFunctionDefinition(program, fn, desired));
            saveOrRevertPrototype(program, fn, prevDef);
            disposeDecompiler(); // signature change rebuilds the AST — drop the cached DecompInterface so the
                                 // next inspect_function re-decompiles against the NEW signature (agy plan-panel
                                 // R2-Seat1: a cached decompiler would serve stale C, breaking the read-mutate-read
                                 // loop + e2e test 3). Reuses the shipped dispose (worker re-attach path).
            res.addProperty("status", "set");
            res.addProperty("signature", fn.getSignature().getPrototypeString());
            res.addProperty("previous_signature", currentProto);
            return res;
        }

        // 7) CAS can still run outside the tx (needs only currentProto).
        casCheck(params, currentProto, fn);

        // 8) SYNTHESIS PATH — an un-nameable type (fn-pointer/anon). Synthesize + apply INSIDE the tx so an
        //    orphan synthesized type rolls back on any failure (§4.1). already_applied is NOT offered here
        //    (always "set"): the deterministic-name reuse makes re-apply idempotent + dup-free; e2e test 6
        //    asserts no duplicate TYPE, not the status. Documented, intentional simplification.
        final ghidra.program.model.data.FunctionDefinitionDataType prevDef =
                new ghidra.program.model.data.FunctionDefinitionDataType(fn.getSignature());
        withTransaction(program, "set_prototype " + fn.getName(), () -> {
            ghidra.program.model.data.DataType rt =
                    (retByName != null) ? retByName : synthesizeType(program, returnTypeName);
            ghidra.program.model.data.DataType[] pts =
                    new ghidra.program.model.data.DataType[paramTypeNames.size()];
            for (int i = 0; i < pts.length; i++) {
                pts[i] = (paramByName[i] != null) ? paramByName[i]
                        : synthesizeType(program, paramTypeNames.get(i));
            }
            ghidra.program.model.data.FunctionDefinitionDataType desired =
                    buildDesiredDef(rt, pts, paramNames, callingConvention, variadic);
            applyFunctionDefinition(program, fn, desired);
        });
        saveOrRevertPrototype(program, fn, prevDef);
        disposeDecompiler(); // drop the stale cached decompiler after the write (agy plan-panel R2-Seat1).
        res.addProperty("status", "set");
        res.addProperty("signature", fn.getSignature().getPrototypeString());
        res.addProperty("previous_signature", currentProto);
        return res;
    }

    // set_local { target, variable, new_type?, new_name?, expected_type?, expected_name? } -> SetLocalResult.
    // Retype and/or rename ONE decompiler-visible local, keyed on its STORAGE handle (name is a fallback
    // selector). Mirrors setPrototype: §1-6 are PURE READS (a rejected request mutates nothing); the only
    // mutation is the single tx-guarded updateDBVariable in §7. All Ghidra HighFunction APIs Task-0-pinned.
    private JsonObject setLocal(JsonObject params) throws Exception {
        Program program = this.attached != null ? this.attached : currentProgram;
        if (program == null) throw new WorkerError("PROGRAM_NOT_OPEN", "no program is open");
        String variable = reqStr(params, "variable");
        boolean hasType = params.has("new_type") && !params.get("new_type").isJsonNull();
        boolean hasName = params.has("new_name") && !params.get("new_name").isJsonNull();
        String newTypeName = hasType ? params.get("new_type").getAsString() : null;
        String newName = hasName ? params.get("new_name").getAsString() : null;

        // 1) At least one mutation field (spec §4.1).
        if (!hasType && !hasName)
            throw new WorkerError("INVALID_PARAMS",
                "set_local requires at least one of new_type / new_name");
        // 2) Reject void-as-variable-type up-front (spec §4.1 R2-Seat5): 'void' name-resolves but is illegal
        //    as a variable type and only fails deep inside updateDBVariable.
        if (hasType && "void".equalsIgnoreCase(newTypeName))
            throw new WorkerError("INVALID_PARAMS",
                "'void' is not a valid variable type; give the local a concrete type");
        // 3) Reject namespace in new_name (reuse rename's rule, §4.1).
        if (hasName && newName.contains("::"))
            throw new WorkerError("INVALID_PARAMS", "pass a bare local name (no '::')");

        // 4) Resolve target -> FUNCTION (reuse §6 resolver via remap).
        Function fn = resolveFunction(program, remap(params, "target"));

        // 5) Decompile + locate the HighSymbol by STORAGE first (stable), else by NAME. Reuse the cached
        //    decompiler. hf/getLocalSymbolMap/getSymbols per Task-0 pins.
        DecompInterface di = decompiler(program);
        DecompileResults r = di.decompileFunction(fn, 30, monitor);
        ghidra.program.model.pcode.HighFunction hf = (r != null) ? r.getHighFunction() : null;
        if (hf == null)
            throw new WorkerError("DECOMPILATION_FAILED", "decompiler produced no HighFunction for " + fn.getName());
        ghidra.program.model.pcode.HighSymbol match = null;
        ghidra.program.model.pcode.HighSymbol paramMatch = null; // a PARAMETER whose handle/name the caller passed
        java.util.List<ghidra.program.model.pcode.HighSymbol> byName = new java.util.ArrayList<>();
        java.util.List<String> allStorages = new java.util.ArrayList<>();
        java.util.Iterator<ghidra.program.model.pcode.HighSymbol> it = hf.getLocalSymbolMap().getSymbols();
        while (it.hasNext()) {
            ghidra.program.model.pcode.HighSymbol hs = it.next();
            String sh = storageHandle(hs.getStorage());
            if (hs.isParameter()) {
                // Params live in the prototype, not locals[], so they are NOT selectable targets — but if the
                // caller passed a param's handle/name, remember it so we can point them at set_prototype below
                // (spec §4.1) instead of the less-helpful VARIABLE_NOT_FOUND. Keep params out of allStorages/byName.
                if (sh.equals(variable) || hs.getName().equals(variable)) paramMatch = hs;
                continue;
            }
            allStorages.add(sh);
            if (sh.equals(variable)) { match = hs; break; }       // storage handle wins
            if (hs.getName().equals(variable)) byName.add(hs);     // name fallback candidate
        }
        if (match == null) {
            if (byName.size() == 1) {
                match = byName.get(0);
            } else if (byName.size() > 1) {
                com.google.gson.JsonArray cands = new com.google.gson.JsonArray();
                for (ghidra.program.model.pcode.HighSymbol hs : byName) cands.add(storageHandle(hs.getStorage()));
                throw new AmbiguousError("AMBIGUOUS_SYMBOL",
                    "'" + variable + "' matches " + byName.size() + " locals; use a storage handle", cands);
            } else if (paramMatch != null) {
                // Caller targeted a parameter — belongs to set_prototype (spec §4.1). INVALID_PARAMS, not
                // VARIABLE_NOT_FOUND (the param IS in the function, just not a set_local target).
                throw new WorkerError("INVALID_PARAMS",
                    "'" + variable + "' is a parameter; edit it with set_prototype, not set_local");
            } else {
                // VARIABLE_NOT_FOUND: echo the <=5 nearest storages, NOT the whole list (spec §4.1 R1-Seat5).
                JsonObject d = new JsonObject();
                d.add("nearest", nearestStorages(allStorages, variable, 5));
                d.addProperty("hint", "call inspect_function for the full locals[] list");
                throw new WorkerError("VARIABLE_NOT_FOUND",
                    "no local with storage or name '" + variable + "' in " + fn.getName(), d);
            }
        }

        // 6) Reject a parameter target (spec §4.1) — belongs to set_prototype.
        if (match.isParameter())
            throw new WorkerError("INVALID_PARAMS",
                "'" + variable + "' is a parameter; edit it with set_prototype, not set_local");
        // 6b) Q4 storage-class gate (spike M2d Task 0: STACK ONLY for v1; register edits ghost-duplicate the
        //     decompiler SSA name, unique locals aren't exposed, custom-storage is unsafe to edit).
        if (fn.hasCustomVariableStorage())
            throw new WorkerError("INVALID_PARAMS",
                "function '" + fn.getName() + "' uses custom variable storage; set_local cannot safely edit its locals");
        ghidra.program.model.listing.VariableStorage tvs = match.getStorage();
        if (tvs == null || !tvs.isStackStorage())
            throw new WorkerError("INVALID_PARAMS",
                "set_local v1 edits STACK locals only; '" + variable + "' is a "
                + storageKind(tvs) + " local (register/unique locals render unreliably after edit)");

        // 7) Capture current, compute already_applied (EVERY provided field matches) BEFORE the CAS guard
        //    (respawn-retry precedence, M2b/M2c). previous_* only for a field that actually changed.
        String curName = match.getName();
        ghidra.program.model.data.DataType curType = match.getDataType();
        String curTypeName = curType != null ? curType.getName() : "undefined";
        String storage = storageHandle(match.getStorage());

        // Resolve new type by name -> synthesis fallback (reuse M2c). null means "unchanged" (rename-only).
        ghidra.program.model.data.DataType resolvedType = null;
        boolean typeChanges = false;
        if (hasType) {
            resolvedType = resolveTypeByName(program, newTypeName); // may throw AMBIGUOUS_DATATYPE
            // synthesis (fn-pointer/anon) happens inside the tx below if name-resolve missed.
            typeChanges = (resolvedType == null) || !resolvedType.isEquivalent(curType);
        }
        boolean nameChanges = hasName && !newName.equals(curName);

        JsonObject res = new JsonObject();
        res.addProperty("function", fn.getName());
        res.addProperty("storage", storage);
        res.addProperty("durable", true);

        // already_applied iff no provided field changes (spec §4.1 D-CAS-LOCAL: never short-circuit on a
        // partial match — if type matches but name differs we still apply).
        boolean typeSatisfied = !hasType || (resolvedType != null && resolvedType.isEquivalent(curType));
        boolean nameSatisfied = !hasName || newName.equals(curName);
        if (typeSatisfied && nameSatisfied) {
            res.addProperty("status", "already_applied");
            res.addProperty("name", curName);
            res.addProperty("type", curTypeName);
            return res;
        }
        // CAS guards (STATE_CONFLICT) compare caller belief vs current, AFTER already_applied.
        if (params.has("expected_type") && !params.get("expected_type").getAsString().equals(curTypeName))
            throw stateConflict("type", params.get("expected_type").getAsString(), curTypeName);
        if (params.has("expected_name") && !params.get("expected_name").getAsString().equals(curName))
            throw stateConflict("name", params.get("expected_name").getAsString(), curName);

        // Omitted-field passthrough (spec §4.1 R3-Seat3): updateDBVariable needs concrete name AND type;
        // a null would NPE. Retype-only -> pass current name; rename-only -> pass current DataType.
        final String applyName = hasName ? newName : curName;
        final ghidra.program.model.pcode.HighSymbol sym = match;
        final ghidra.program.model.data.DataType nameResolved = resolvedType;
        // NPE GUARD (panel R1-Ghidra-seat): a HighSymbol's getDataType() can be null (Task 5 coalesces it
        // for display). updateDBVariable needs a concrete type, so a rename-only edit on a null-typed local
        // must fall back to the default undefined type, never pass null.
        final ghidra.program.model.data.DataType curTypeOrDefault =
                (curType != null) ? curType : ghidra.program.model.data.DataType.DEFAULT;
        withTransaction(program, "set_local " + storage + " in " + fn.getName(), () -> {
            ghidra.program.model.data.DataType applyType = !hasType ? curTypeOrDefault
                    : (nameResolved != null ? nameResolved : synthesizeType(program, newTypeName));
            ghidra.program.model.pcode.HighFunctionDBUtil.updateDBVariable(
                    sym, applyName, applyType, ghidra.program.model.symbol.SourceType.USER_DEFINED);
        });
        // Save-dance: end(true)+save. On save failure set_local CANNOT cheaply revert in-memory the way
        // rename/set_prototype do (they kept the prior symbol/def; the post-updateDBVariable HighSymbol
        // handle is stale and re-resolving needs a fresh decompile that may itself fail). An un-revertable
        // dirty in-memory Program is the phantom-durability hazard (M2b §3): a later successful edit's save()
        // would flush THIS failed edit to disk. So save-failure is treated as unrecoverable -> halt(70) so
        // the host respawns a CLEAN JVM from disk (which never received the failed edit).
        saveOrHaltLocal(program);
        disposeDecompiler(); // drop the cached AST so the next inspect_function re-decompiles (M2c R2-Seat1).

        // Read back the NEW values from a fresh symbol lookup would require a re-decompile; instead report
        // the values we applied (type display name via the resolved/curr type).
        String newTypeDisplay = !hasType ? curTypeName
                : (nameResolved != null ? nameResolved.getName() : newTypeName);
        res.addProperty("name", applyName);
        res.addProperty("type", newTypeDisplay);
        if (nameChanges) res.addProperty("previous_name", curName);
        if (typeChanges) res.addProperty("previous_type", curTypeName);
        res.addProperty("status", (nameChanges && typeChanges) ? "set" : (nameChanges ? "renamed" : "retyped"));
        return res;
    }

    // <=N nearest storage strings to `q` by simple edit distance (VARIABLE_NOT_FOUND details; §4.1 R1-Seat5).
    // Guard the edit-distance cost against a pathological `q` (panel R2-Security-seat): a huge `variable`
    // string would make each editDistance allocate O(|q|) arrays. A real storage handle is < ~32 chars, so a
    // q longer than that cannot fuzzy-match anything useful — skip the distance sort and return the first N.
    private com.google.gson.JsonArray nearestStorages(java.util.List<String> all, String q, int n) {
        com.google.gson.JsonArray out = new com.google.gson.JsonArray();
        if (q.length() <= 64) {
            all.sort(java.util.Comparator.comparingInt(s -> editDistance(s, q)));
        } // else: q is not a plausible handle; leave `all` unsorted and just surface the first N.
        for (int i = 0; i < Math.min(n, all.size()); i++) out.add(all.get(i));
        return out;
    }

    private int editDistance(String a, String b) {
        int[] prev = new int[b.length() + 1];
        for (int j = 0; j <= b.length(); j++) prev[j] = j;
        for (int i = 1; i <= a.length(); i++) {
            int[] cur = new int[b.length() + 1];
            cur[0] = i;
            for (int j = 1; j <= b.length(); j++) {
                int cost = a.charAt(i - 1) == b.charAt(j - 1) ? 0 : 1;
                cur[j] = Math.min(Math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
            }
            prev = cur;
        }
        return prev[b.length()];
    }

    private WorkerError stateConflict(String field, String expected, String actual) {
        JsonObject d = new JsonObject();
        d.addProperty("field", field);
        d.addProperty("expected", expected);
        d.addProperty("actual", actual);
        return new WorkerError("STATE_CONFLICT",
            "current " + field + " is '" + actual + "', not '" + expected + "'", d);
    }

    // Save for set_local. Unlike rename/set_prototype (which keep the prior symbol/def and revert-in-memory
    // on save failure, then report TRANSACTION_FAILED), set_local's post-updateDBVariable HighSymbol handle
    // is stale and cannot be cheaply re-resolved without a fresh decompile. So a save failure leaves an
    // UN-REVERTABLE dirty in-memory Program — the exact phantom-durability hazard (M2b §3): if this JVM
    // stayed alive, a later successful edit's save() would flush THIS failed edit to disk. Therefore
    // save-failure is unrecoverable -> halt(70) so the host respawns a CLEAN JVM from disk (which never
    // received the failed edit). The agent sees the connection reset and re-reads state (WORKER_RESTARTED).
    private void saveOrHaltLocal(Program program) throws Exception {
        try {
            end(true);
            program.getDomainFile().save(monitor);
        } catch (Throwable saveFail) {
            Runtime.getRuntime().halt(70); // unrecoverable dirty in-memory state; respawn clean from disk
        }
        start();
    }

    // Name-lookup a type via findDataTypes: 0 -> null (caller uses the parse fallback), 1 -> it, >1 ->
    // AMBIGUOUS_DATATYPE. (Sibling of resolveDataType, which throws DATATYPE_NOT_FOUND on empty; here empty
    // means "try to synthesize".)
    private ghidra.program.model.data.DataType resolveTypeByName(Program program, String name) {
        java.util.List<ghidra.program.model.data.DataType> list = new java.util.ArrayList<>();
        program.getDataTypeManager().findDataTypes(name, list);
        if (list.isEmpty()) return null;
        if (list.size() > 1) {
            com.google.gson.JsonArray cands = new com.google.gson.JsonArray();
            for (ghidra.program.model.data.DataType d : list) cands.add(d.getPathName());
            throw new AmbiguousError("AMBIGUOUS_DATATYPE",
                    name + " resolves to " + list.size() + " data types", cands);
        }
        return list.get(0);
    }

    // Single-type parse fallback for an un-nameable type (fn-pointer/anon). DataTypeParser is javac-pinned
    // (agy's CParserUtils.parseDataType does not exist). Give the result a DETERMINISTIC name looked up
    // FIRST so a retry REUSES it via DEFAULT_HANDLER rather than spawning FunctionDef_1/_2 (R2-Seat2). MUST
    // run inside an open transaction (addDataType mutates the DB).
    private ghidra.program.model.data.DataType synthesizeType(Program program, String typeStr) {
        ghidra.program.model.data.DataTypeManager dtm = program.getDataTypeManager();
        String synthName = "mcp_synth_"
                + Integer.toHexString(typeStr.trim().replaceAll("\\s+", " ").hashCode());
        java.util.List<ghidra.program.model.data.DataType> existing = new java.util.ArrayList<>();
        dtm.findDataTypes(synthName, existing);
        if (!existing.isEmpty()) return existing.get(0);
        ghidra.program.model.data.DataType parsed;
        try {
            ghidra.util.data.DataTypeParser parser = new ghidra.util.data.DataTypeParser(
                    dtm, dtm, null, ghidra.util.data.DataTypeParser.AllowedDataTypes.ALL);
            parsed = parser.parse(typeStr);
        } catch (Exception parseErr) {
            throw new WorkerError("DATATYPE_NOT_FOUND",
                    "no data type named '" + typeStr + "', and it did not parse as a type: " + parseErr.getMessage());
        }
        if (parsed == null)
            throw new WorkerError("DATATYPE_NOT_FOUND", "no data type named '" + typeStr + "'");
        // Name it deterministically where nameable (a Pointer's name lives on its base FunctionDefinition;
        // setName may be a no-op for a pointer — DEFAULT_HANDLER still dedups structurally, gated by test 6).
        try { parsed.setName(synthName); } catch (Exception ignore) { /* pointer/array not directly nameable */ }
        return dtm.addDataType(parsed, ghidra.program.model.data.DataTypeConflictHandler.DEFAULT_HANDLER);
    }

    // Build the desired FunctionDefinitionDataType from resolved components (used for the isEquivalent
    // already_applied check AND for the apply). All setters javac-pinned (spec §7 CAS-build).
    private ghidra.program.model.data.FunctionDefinitionDataType buildDesiredDef(
            ghidra.program.model.data.DataType retType,
            ghidra.program.model.data.DataType[] paramTypes,
            java.util.List<String> paramNames,
            String callingConvention, boolean variadic) throws Exception {
        ghidra.program.model.data.FunctionDefinitionDataType def =
                new ghidra.program.model.data.FunctionDefinitionDataType("mcp_set_prototype");
        def.setReturnType(retType);
        ghidra.program.model.data.ParameterDefinition[] pdefs =
                new ghidra.program.model.data.ParameterDefinition[paramTypes.length];
        for (int i = 0; i < paramTypes.length; i++) {
            pdefs[i] = new ghidra.program.model.data.ParameterDefinitionImpl(
                    paramNames.get(i), paramTypes[i], null); // null name -> auto param_N
        }
        def.setArguments(pdefs);
        def.setVarArgs(variadic);
        def.setCallingConvention(callingConvention);
        return def;
    }

    // Idempotency (D-CAS3): desired isEquivalent current, PLUS explicit cc + varargs equality (defensive —
    // isEquivalent ignores calling convention/varargs) PLUS caller-specified param NAMES (isEquivalent also
    // ignores param names — agy plan-panel R3-Seat1: without this, a rename-only edit param_1->count would
    // silently return already_applied and drop the rename). Semantic TYPE equivalence (dword==uint) still
    // comes from isEquivalent. A caller who OMITTED a name (paramNames[i]==null -> auto-name) is a WILDCARD
    // that never blocks already_applied (so auto-named callers still get correct idempotency).
    private boolean signatureAlreadyApplied(Function fn,
            ghidra.program.model.data.FunctionDefinitionDataType desired,
            java.util.List<String> paramNames, String callingConvention, boolean variadic) {
        ghidra.program.model.data.FunctionDefinitionDataType current =
                new ghidra.program.model.data.FunctionDefinitionDataType(fn.getSignature());
        // Compare signature COMPONENTS explicitly rather than desired.isEquivalent(current): the whole-def
        // isEquivalent also compares the generic calling convention, but building a FunctionDefinitionDataType
        // from fn.getSignature() does NOT carry the cc that setCallingConvention() set on `desired`, so an
        // otherwise-identical re-apply never matched (verified live: idempotency returned "set" every time).
        // Return type + each arg's type are the semantic TYPE equivalence (dword==uint via isEquivalent);
        // calling convention, varargs, and caller-specified param names are checked EXPLICITLY below.
        ghidra.program.model.data.ParameterDefinition[] cur = current.getArguments();
        ghidra.program.model.data.ParameterDefinition[] des = desired.getArguments();
        if (des.length != cur.length) return false;
        if (!desired.getReturnType().isEquivalent(current.getReturnType())) return false;
        for (int i = 0; i < des.length; i++) {
            if (!des[i].getDataType().isEquivalent(cur[i].getDataType())) return false;
        }
        String curCc = fn.getCallingConventionName();
        if (curCc == null || !curCc.equals(callingConvention)) return false;
        if (fn.hasVarArgs() != variadic) return false;
        for (int i = 0; i < paramNames.size() && i < cur.length; i++) {
            String want = paramNames.get(i);
            if (want != null && !want.equals(cur[i].getName())) return false; // specified name must match
        }
        return true;
    }

    // Optional expected_signature guard -> STATE_CONFLICT (§4.2). Comparand is the current DB prototype
    // string (read it from inspect_function.signature, NOT the decompiled C body — R3-Seat5).
    private void casCheck(JsonObject params, String currentProto, Function fn) {
        if (params.has("expected_signature") && !params.get("expected_signature").isJsonNull()) {
            String expected = params.get("expected_signature").getAsString();
            if (!currentProto.equals(expected)) {
                JsonObject d = new JsonObject();
                d.addProperty("address", fn.getEntryPoint().toString());
                d.addProperty("name", fn.getName());
                d.addProperty("expected", expected);
                d.addProperty("actual", currentProto);
                throw new WorkerError("STATE_CONFLICT",
                        "current signature differs from expected_signature", d);
            }
        }
    }

    // Apply a FunctionDefinitionDataType to a live Function via the javac-pinned updateFunction overload
    // (P3). Shared by the forward apply and the save-failure revert. updateFunction throws
    // InvalidInputException/DuplicateNameException -> caught by withTransaction -> INVALID_PARAMS with the
    // Ghidra message in details.reason (M2a granularity: user-fixable validation is INVALID_PARAMS).
    private void applyFunctionDefinition(Program program, Function fn,
            ghidra.program.model.data.FunctionDefinitionDataType def) throws Exception {
        ghidra.program.model.listing.Variable ret =
                new ghidra.program.model.listing.ReturnParameterImpl(def.getReturnType(), program);
        java.util.List<ghidra.program.model.listing.Parameter> ps = new java.util.ArrayList<>();
        for (ghidra.program.model.data.ParameterDefinition pd : def.getArguments()) {
            ps.add(new ghidra.program.model.listing.ParameterImpl(pd.getName(), pd.getDataType(), program));
        }
        fn.updateFunction(def.getCallingConventionName(), ret, ps,
                Function.FunctionUpdateType.DYNAMIC_STORAGE_ALL_PARAMS, true,
                ghidra.program.model.symbol.SourceType.USER_DEFINED);
        fn.setVarArgs(def.hasVarArgs());
    }

    // The M2a/M2b save dance (oracle: saveOrRevertDatatype + rename save path). On save failure restore the
    // PREVIOUS signature via applyFunctionDefinition(prevDef); re-start() before throwing (tx-state
    // invariant). Save-then-revert double fault -> halt(70) (phantom-durability guard, M2b §3). The
    // save-failure edge is document-and-best-effort (not an e2e), as M2a §4.3.
    private void saveOrRevertPrototype(Program program, Function fn,
            ghidra.program.model.data.FunctionDefinitionDataType prevDef) throws Exception {
        try {
            end(true);
            program.getDomainFile().save(monitor);
        } catch (Throwable saveFail) {
            try {
                withTransaction(program, "revert failed set_prototype save",
                        () -> applyFunctionDefinition(program, fn, prevDef));
            } catch (Throwable revertFail) {
                Runtime.getRuntime().halt(70);
            }
            start();
            throw new WorkerError("TRANSACTION_FAILED", "edit rolled back (save to disk failed): " + saveFail);
        }
        start();
    }

    // Resolve a data type name via DataTypeManager.findDataTypes: 0 -> DATATYPE_NOT_FOUND, >1 ->
    // AMBIGUOUS_DATATYPE (candidates in details), 1 -> that type. (Mirrors M1b get_datatype resolution.)
    private ghidra.program.model.data.DataType resolveDataType(Program program, String name) {
        java.util.List<ghidra.program.model.data.DataType> list = new java.util.ArrayList<>();
        program.getDataTypeManager().findDataTypes(name, list);
        if (list.isEmpty())
            throw new WorkerError("DATATYPE_NOT_FOUND", "no data type named '" + name + "'");
        if (list.size() > 1) {
            com.google.gson.JsonArray cands = new com.google.gson.JsonArray();
            for (ghidra.program.model.data.DataType d : list) cands.add(d.getPathName());
            throw new AmbiguousError("AMBIGUOUS_DATATYPE",
                    name + " resolves to " + list.size() + " data types", cands);
        }
        return list.get(0);
    }

    // Compute a CONCRETE length for createData. createData throws IllegalArgumentException for a dynamically-
    // sized DataType if length <= 0 (panel-F2) — so a `string`/dynamic struct (getLength()==-1) must be sized
    // at the address via a MemBuffer. Fixed types return their static length. The exact Dynamic.getLength /
    // DumbMemBufferImpl signatures are pinned by the javac step (§7 D4); if they differ, use the createData
    // overload Ghidra provides that sizes the type itself.
    private int concreteLength(Program program, ghidra.program.model.address.Address addr,
            ghidra.program.model.data.DataType dt) {
        int len = dt.getLength();
        if (len > 0) return len; // fixed-size type
        // Unwrap typedefs (panel R4-S1): a typedef OF a dynamic type reports getLength()==-1 but is NOT
        // `instanceof Dynamic` (it implements TypeDef) — without this, dynamic typedefs are permanently
        // rejected. Size from the resolved base; createData still applies the ORIGINAL `dt` (typedef identity
        // preserved) — only the LENGTH is taken from the base.
        ghidra.program.model.data.DataType base = dt;
        while (base instanceof ghidra.program.model.data.TypeDef) {
            base = ((ghidra.program.model.data.TypeDef) base).getBaseDataType();
        }
        if (base instanceof ghidra.program.model.data.Dynamic) {
            ghidra.program.model.mem.MemBuffer buf =
                    new ghidra.program.model.mem.DumbMemBufferImpl(program.getMemory(), addr);
            int dl = ((ghidra.program.model.data.Dynamic) base).getLength(buf, -1);
            if (dl > 0) return dl;
        }
        throw new WorkerError("INVALID_PARAMS",
                "could not determine a concrete length for dynamic type '" + dt.getName() + "' at " + addr);
    }

    // The M2a save dance (oracle: rename L908-929), factored so both the clear and apply paths reuse it.
    // On save failure: revert to the captured previous type (or clear if none), re-start() before throwing
    // (R4 tx-state invariant) so the outer callers' subsequent requests find a live script tx. `prevLen` is
    // the CONCRETE instance length captured pre-mutation (panel-F5) — a dynamic prevDt's getLength()==-1 would
    // otherwise throw in the revert createData and wedge the worker.
    private void saveOrRevertDatatype(Program program, ghidra.program.model.address.Address addr,
            ghidra.program.model.data.DataType prevDt, int prevLen) throws Exception {
        try {
            end(true);
            program.getDomainFile().save(monitor);
        } catch (Throwable saveFail) {
            try {
                withTransaction(program, "revert failed set_datatype save", () -> {
                    ghidra.program.model.listing.Data cur = program.getListing().getDataAt(addr);
                    ghidra.program.model.address.Address end = cur != null ? cur.getMaxAddress() : addr;
                    program.getListing().clearCodeUnits(addr, end, false);
                    if (prevDt != null) {
                        ghidra.program.model.data.DataUtilities.createData(program, addr, prevDt, prevLen,
                                ghidra.program.model.data.DataUtilities.ClearDataMode.CLEAR_SINGLE_DATA);
                    }
                });
            } catch (Throwable revertFail) {
                // Double-fault: dirty in-memory vs disk. Halt so the host respawns a CLEAN JVM from disk
                // rather than a returned WORKER_UNAVAILABLE leaving this JVM alive to serve dirty state on a
                // retry (phantom durability). See the comment-method twin (panel R2-F4).
                Runtime.getRuntime().halt(70);
            }
            start();
            throw new WorkerError("TRANSACTION_FAILED", "edit rolled back (save to disk failed): " + saveFail);
        }
        start();
    }

    // rename { target, expected_name, new_name } -> RenameResult (spec §3). Renames the PRIMARY symbol
    // at the resolved address. CAS: already_applied checked FIRST (§3.3); auto-save (§5); durable=true.
    private JsonObject rename(JsonObject params) throws Exception {
        // Operate on the attached program, or the bootstrap currentProgram when nothing is explicitly
        // attached — same effective-program resolution the read tools use. (The e2e drives the bootstrap
        // program without an explicit attach_program; requiring attach here would wrongly reject it.)
        Program program = this.attached != null ? this.attached : currentProgram;
        if (program == null) throw new WorkerError("PROGRAM_NOT_OPEN", "no program is open");
        String target = reqStr(params, "target");
        String expected = reqStr(params, "expected_name");
        String newName = reqStr(params, "new_name");
        if (newName.contains("::"))
            throw new WorkerError("INVALID_PARAMS", "namespace moves are not supported in M2a; pass a bare local name");
        ghidra.program.model.address.Address addr = resolveTargetAddress(program, target);
        ghidra.program.model.symbol.Symbol sym = program.getSymbolTable().getPrimarySymbol(addr);
        if (sym == null) throw new WorkerError("SYMBOL_NOT_FOUND", "no primary symbol at " + addr);
        String current = sym.getName();

        JsonObject res = new JsonObject();
        res.addProperty("address", addr.toString());
        res.addProperty("durable", true);
        if (current.equals(newName)) {                    // already_applied — FIRST, no tx/save (§3.3)
            res.addProperty("status", "already_applied");
            res.addProperty("name", newName);
            return res;
        }
        if (!current.equals(expected)) {                  // drift -> RENAME_CONFLICT (§4.2)
            JsonObject d = new JsonObject();
            d.addProperty("address", addr.toString());
            d.addProperty("expected", expected);
            d.addProperty("actual", current);
            throw new WorkerError("RENAME_CONFLICT", "current name is '" + current + "', not '" + expected + "'", d);
        }
        // CAS matched -> apply in a transaction, then save (§3.3/§4.3).
        ghidra.program.model.symbol.SourceType origSource = sym.getSource();
        withTransaction(program, "rename " + current + " -> " + newName,
                () -> program.getSymbolTable().getPrimarySymbol(addr).setName(newName,
                        ghidra.program.model.symbol.SourceType.USER_DEFINED));
        // U1 FIX (Task-0 spike): close the persistent script-framework tx so save() can lock, then reopen.
        // end()/start() (FlatProgramAPI) act on currentProgram, which == `program` here: attach_program
        // calls openProgram(attached), and with no attach `program` IS currentProgram (the bootstrap).
        try {
            end(true);
            program.getDomainFile().save(monitor);
        } catch (Throwable saveFail) {
            // §4.3: in-memory ahead of disk. Re-fetch (dynamic-DEFAULT rename can invalidate the handle),
            // revert with the ORIGINAL source type, then report TRANSACTION_FAILED.
            try {
                withTransaction(program, "revert failed save", () -> {
                    ghidra.program.model.symbol.Symbol fresh = program.getSymbolTable().getPrimarySymbol(addr);
                    fresh.setName(current, origSource);
                });
            } catch (Throwable revertFail) {
                // Double-fault: dirty in-memory vs disk. A returned WORKER_UNAVAILABLE keeps THIS JVM alive
                // (execute.rs treats a Failure frame as a domain error, not a crash), so a rename retry would
                // read the dirty in-memory name and falsely report already_applied/durable (phantom durability).
                // Halt so the host respawns a CLEAN JVM from disk (panel R2-F4, user-approved).
                Runtime.getRuntime().halt(70);
            }
            start();      // reopen the script tx before returning the error
            throw new WorkerError("TRANSACTION_FAILED", "edit rolled back (save to disk failed): " + saveFail);
        }
        start();          // reopen the script tx for subsequent requests (happy path)
        res.addProperty("status", "renamed");
        res.addProperty("name", newName);
        res.addProperty("previous_name", current);
        return res;
    }

    // target = an address string OR a global symbol name (spec §3.2). Reuses established resolution.
    private ghidra.program.model.address.Address resolveTargetAddress(Program program, String target) {
        ghidra.program.model.address.Address a = program.getAddressFactory().getAddress(target);
        if (a != null) return a;
        java.util.List<ghidra.program.model.symbol.Symbol> syms = program.getSymbolTable().getGlobalSymbols(target);
        if (syms.isEmpty()) throw new WorkerError("SYMBOL_NOT_FOUND", "no symbol or address: " + target);
        if (syms.size() > 1) {
            com.google.gson.JsonArray cands = new com.google.gson.JsonArray();
            for (ghidra.program.model.symbol.Symbol s : syms) cands.add(s.getAddress().toString());
            throw new AmbiguousError("AMBIGUOUS_SYMBOL", target + " resolves to " + syms.size() + " symbols", cands);
        }
        return syms.get(0).getAddress();
    }

    // Adapt a {target} param to the {function} key resolveFunction expects (L293).
    private JsonObject remap(JsonObject p, String key) {
        JsonObject q = new JsonObject();
        if (p.has(key)) q.add("function", p.get(key));
        return q;
    }

    // Build a JSON array of {name,address,external} edges from a set of functions (spec 3.3).
    private com.google.gson.JsonArray edges(java.util.Set<Function> fns) {
        com.google.gson.JsonArray arr = new com.google.gson.JsonArray();
        for (Function f : fns) {
            JsonObject e = new JsonObject();
            e.addProperty("name", f.getName());
            e.addProperty("address", addrString(f.getEntryPoint()));
            e.addProperty("external", f.isExternal());
            arr.add(e);
        }
        return arr;
    }

    // Canonical storage handle for a decompiler local: "stack:-0x<hex>"/"stack:0x<hex>" (SIGNED,
    // `0x`-prefixed to match spec §3 / DESC_SET_LOCAL examples), "<reg>:<size>", "unique:0x<hex>", else a
    // stable fallback. The SAME string the set_local resolver matches on (read<->write parity; M2c
    // getPrototypeString-parity lesson). VariableStorage accessors are Task-0-javac-pinned (M2d spike).
    private String storageHandle(ghidra.program.model.listing.VariableStorage vs) {
        if (vs == null) return "unknown";
        if (vs.isStackStorage()) {
            long off = vs.getStackOffset();
            return off < 0 ? "stack:-0x" + Long.toHexString(-off) : "stack:0x" + Long.toHexString(off);
        }
        if (vs.isRegisterStorage()) {
            ghidra.program.model.lang.Register reg = vs.getRegister();
            return (reg != null ? reg.getName() : "reg") + ":" + vs.size();
        }
        if (vs.isUniqueStorage()) return "unique:0x" + Long.toHexString(vs.getFirstVarnode().getOffset());
        return vs.toString(); // other: the pinned canonical form from Task 0
    }

    // Coarse class for the agent's trust model: which handles survive edits. MUST emit the full spec §3
    // domain kind ∈ stack|register|unique|other — do NOT lump `unique` into `other` (panel R3-Spec-seat:
    // that violates the LocalEntry wire contract). `isUniqueStorage` is Task-0-javac-pinned.
    private String storageKind(ghidra.program.model.listing.VariableStorage vs) {
        if (vs == null) return "other";
        if (vs.isStackStorage()) return "stack";
        if (vs.isRegisterStorage()) return "register";
        if (vs.isUniqueStorage()) return "unique";
        return "other";
    }

    // Build (or return) the DecompInterface bound to the currently-attached program. Cached so a
    // read-heavy loop of inspect_function calls keeps decompiler warmth instead of re-spinning it.
    private DecompInterface decompiler(Program program) {
        if (this.decomp == null) {
            DecompInterface di = new DecompInterface();
            di.openProgram(program);
            this.decomp = di;
        }
        return this.decomp;
    }

    private void disposeDecompiler() {
        if (this.decomp != null) {
            this.decomp.closeProgram();
            this.decomp.dispose();
            this.decomp = null;
        }
    }

    // ---- JSON-RPC envelope helpers ----
    private String success(JsonObject req, JsonObject result) {
        JsonObject resp = new JsonObject();
        resp.addProperty("jsonrpc", "2.0");
        resp.add("id", req.has("id") ? req.get("id") : com.google.gson.JsonNull.INSTANCE);
        resp.add("result", result);
        return gson.toJson(resp);
    }

    private String failure(JsonObject req, String code, String message) {
        JsonObject err = new JsonObject();
        err.addProperty("code", code);
        err.addProperty("message", message);
        JsonObject resp = new JsonObject();
        resp.addProperty("jsonrpc", "2.0");
        resp.add("id", req.has("id") ? req.get("id") : com.google.gson.JsonNull.INSTANCE);
        resp.add("error", err);
        return gson.toJson(resp);
    }

    private String failure(JsonObject req, String code, String message, com.google.gson.JsonObject details) {
        JsonObject err = new JsonObject();
        err.addProperty("code", code);
        err.addProperty("message", message);
        if (details != null) err.add("details", details);
        JsonObject resp = new JsonObject();
        resp.addProperty("jsonrpc", "2.0");
        resp.add("id", req.has("id") ? req.get("id") : com.google.gson.JsonNull.INSTANCE);
        resp.add("error", err);
        return gson.toJson(resp);
    }

    private String failureWithCandidates(JsonObject req, String code, String message,
                                         com.google.gson.JsonArray candidates) {
        JsonObject err = new JsonObject();
        err.addProperty("code", code);
        err.addProperty("message", message);
        err.add("candidates", candidates);
        JsonObject resp = new JsonObject();
        resp.addProperty("jsonrpc", "2.0");
        resp.add("id", req.has("id") ? req.get("id") : com.google.gson.JsonNull.INSTANCE);
        resp.add("error", err);
        return gson.toJson(resp);
    }

    // Parse-error reply for an unparseable frame: id is null (we could not read one). JSON-RPC 2.0 §5.
    private String parseError() {
        JsonObject err = new JsonObject();
        err.addProperty("code", "PARSE_ERROR");
        err.addProperty("message", "malformed JSON frame");
        JsonObject resp = new JsonObject();
        resp.addProperty("jsonrpc", "2.0");
        resp.add("id", com.google.gson.JsonNull.INSTANCE);
        resp.add("error", err);
        return gson.toJson(resp);
    }

    private static class WorkerError extends RuntimeException {
        final String code;
        final com.google.gson.JsonObject details; // nullable; surfaced at error.details
        WorkerError(String code, String message) { this(code, message, null); }
        WorkerError(String code, String message, com.google.gson.JsonObject details) {
            super(message);
            this.code = code;
            this.details = details;
        }
    }

    // Ambiguous name/lookup: carries the candidate list so the server can surface it in the error's
    // details and the agent can re-call with a disambiguating value (spec 6). Generalized (M1b Task 13)
    // to carry its own `code` — most callers still mean AMBIGUOUS_SYMBOL (2-arg ctor delegates to it),
    // but get_datatype throws AMBIGUOUS_DATATYPE via the 3-arg ctor. dispatch()'s catch reads ae.code,
    // not a hardcoded string, so this flows through unchanged.
    private static final class AmbiguousError extends WorkerError {
        final com.google.gson.JsonArray candidates;
        AmbiguousError(String message, com.google.gson.JsonArray candidates) { this("AMBIGUOUS_SYMBOL", message, candidates); }
        AmbiguousError(String code, String message, com.google.gson.JsonArray candidates) { super(code, message); this.candidates = candidates; }
    }

    // ---- framing: 4-byte big-endian length prefix + UTF-8 body (matches ghidra-ipc) ----
    private void writeFrame(OutputStream out, String json) throws Exception {
        byte[] body = json.getBytes(StandardCharsets.UTF_8);
        if (body.length > MAX_FRAME_LEN) {
            throw new IllegalStateException("frame exceeds MAX_FRAME_LEN");
        }
        byte[] prefix = new byte[4];
        prefix[0] = (byte) (body.length >>> 24);
        prefix[1] = (byte) (body.length >>> 16);
        prefix[2] = (byte) (body.length >>> 8);
        prefix[3] = (byte) (body.length);
        out.write(prefix);
        out.write(body);
        out.flush();
    }

    private byte[] readFrame(DataInputStream in) throws Exception {
        byte[] prefix = new byte[4];
        try {
            in.readFully(prefix);
        } catch (java.io.EOFException eof) {
            return null; // clean close
        }
        long len = ((long) (prefix[0] & 0xFF) << 24)
                | ((prefix[1] & 0xFF) << 16)
                | ((prefix[2] & 0xFF) << 8)
                | (prefix[3] & 0xFF);
        if (len > MAX_FRAME_LEN) {
            throw new IllegalStateException("declared frame length exceeds MAX_FRAME_LEN");
        }
        byte[] body = new byte[(int) len];
        in.readFully(body);
        return body;
    }
}
