# clavity-dotnet — ζευγαρώστε το Claude με έναν ζωντανό ομότιμο agy

[English](README.md) | [Ελληνικά](README.el.md)

Το clavity-dotnet είναι η σύγχρονη ανακατασκευή του clavity σε **.NET 10**: συνδέει το
[Claude Code](https://claude.com/claude-code) με έναν ζωντανό ομότιμο [Antigravity (`agy`)](https://antigravity.google),
και διανέμεται ως καθολικό διπλό πρόσθετο (dual-plugin). Είναι μέλος της [ομπρέλας `clavity`](../README.md) —
δείτε εκείνο το README για να αποφασίσετε εάν αυτή η παραλλαγή ή το `clavity-classic` είναι αυτό που χρειάζεστε.

## Πώς λειτουργεί

Το clavity-dotnet κατευθύνει έναν συνδεδεμένο ομότιμο `agy` από το Claude Code μέσω του τοπικού Language Server του agy (gRPC),
και εκτίθεται στο Claude ως τρία εργαλεία MCP που παρέχονται από το εκτελέσιμο αρχείο `clavity-ls`:

- `agy_look` — ανάγνωση της ενεργής συνομιλίας του agy, οριοθετημένη, χωρίς κατανάλωση quota.
- `agy_status` — έλεγχος λειτουργίας + καταμέτρηση βημάτων (`CascadeId`, `TotalSteps`, `State`, `LastStepKind`).
- `agy_ask` — αποστολή μηνύματος και αναμονή απάντησης από το agy — εγγραφή ορατή στον άνθρωπο, καταναλώνει quota. Κατάλληλο
  για δεύτερη γνώμη, αξιολόγηση σχεδιασμού ή ανάθεση παράλληλης εργασίας.

Κάθε instance του Claude διαχειρίζεται τη δική του απομονωμένη συνεδρία agy (multi-session), και το `agy_ask` στέλνει χρησιμοποιώντας
το μοντέλο που χρησιμοποίησε η συνομιλία σας τελευταία, αντί για μια προκαθορισμένη επιλογή (dynamic send-model).

## Γρήγορη εκκίνηση

### Προαπαιτούμενα

- Εγκατεστημένο το Claude Code ή/και το `agy` (Antigravity) — απαιτείται τουλάχιστον ένας εντοπισμένος πράκτορας για την καθοδήγηση.
- Για μεταγλώττιση από τον πηγαίο κώδικα: το .NET 10 SDK.

### Εγκατάσταση

```powershell
claude plugin marketplace add ckir/clavity
claude plugin install clavity@clavity
```

Το clavity-dotnet είναι διαθέσιμο σε πολλαπλές πλατφόρμες (Windows, Linux, macOS — RIDs `win-x64`, `linux-x64`, `osx-arm64`,
`osx-x64`). Το δυαδικό αρχείο `clavity-ls` δεν περιλαμβάνεται στο πρόσθετο· ένα SessionStart hook του προσθέτου ανακτά το
κατάλληλο εκτελέσιμο RID κατά την πρώτη εκτέλεση από την αντίστοιχη έκδοση `clavity-v<N>` στο GitHub και το επαληθεύει
έναντι του συνοδευτικού αρχείου `.sha256`.

Για μεταγλώττιση από τον πηγαίο κώδικα αντί για χρήση έκδοσης:

```powershell
dotnet build                          # από το clavity-dotnet/
dotnet test tests/Clavity.Ls.Tests    # unit tests — το ci-dotnet.yml εκτελεί επίσης το Clavity.Integration.Tests
```

Τα εκτελέσιμα αρχεία έκδοσης `clavity-ls` παράγονται με single-file publish ανά RID (από το
`.github/workflows/build-dotnet.yml`), π.χ. για `win-x64`:

```powershell
dotnet publish src/Clavity.Cli -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=false -o publish
```

Η ροή εργασιών επαναλαμβάνει τη διαδικασία ανά RID (`win-x64`, `linux-x64`, `osx-arm64`, `osx-x64`) και επισυνάπτει κάθε
δυαδικό αρχείο + `.sha256` στην έκδοση `clavity-v<N>` στο GitHub.

### Πρώτη εκτέλεση

```powershell
clavity-ls start C:\path\to\your\project
```

Ανοίγει μια ορατή καρτέλα `agy` σε αυτόν τον φάκελο, περιμένει μέχρι να συνδεθεί το agy (δημοσιεύει το τελικό σημείο του - μετά από 10 δευτερόλεπτα
σας υπενθυμίζει να ελέγξετε την καρτέλα του agy για προτροπή· το Ctrl+C ακυρώνει· εάν το agy τερματιστεί πρώτο, το `start` διακόπτεται και το αναφέρει),
και στη συνέχεια εκκινεί το Claude Code στο προσκήνιο. Προειδοποιεί (χωρίς να μπλοκάρει) εάν ο φάκελος δεν είναι αποθετήριο git.
Για απεγκατάσταση, εκτελέστε `claude plugin uninstall clavity@clavity`.

Στο Linux, το `start` ανοίγει το agy ως νέα καρτέλα στο τερματικό από το οποίο το εκτελέσατε (mate-terminal, gnome-terminal, konsole ή
xfce4-terminal), διαφορετικά σε `xdg-terminal-exec` ή `x-terminal-emulator`· ορίστε το `CLAVITY_TERMINAL` για να επιλέξετε ένα. Χωρίς
οθόνη (π.χ. μέσω ssh) δεν ξεκινά τίποτα και σας ζητά να εκτελέσετε `clavity-ls agy <folder>`, το οποίο εκτελεί το agy σε
αυτό το τερματικό· σε ένα δεύτερο, το `clavity-ls start <folder> --attach` συνδέει το Claude με αυτό (προσθέστε το session id που
τυπώνει το τερματικό του agy εάν περιμένουν περισσότερα από ένα agy σε αυτόν τον φάκελο). Κάθε agy συνδέεται με ένα Claude: ένα δεύτερο `--attach`
στο ίδιο agy απορρίπτεται. Το `start` επιτρέπει επίσης ΕΝΑ Claude ανά φάκελο: ένα δεύτερο `start`, απλό ή με `--attach`, σε φάκελο που ήδη
έχει ένα απορρίπτεται πριν ανοίξει οτιδήποτε, αποτρέποντας την επανάληψη εργασίας (χρησιμοποιήστε `git worktree add` για ένα δεύτερο
Claude στο ίδιο αποθετήριο). Μόνο το `clavity-ls start` ελέγχεται: η εκτέλεση του `claude` μόνος σας ή η εκκίνηση του `clavity-ls agy`
πριν από το attach δεν μπλοκάρεται. Με ένα id, το Claude ξεκινά στον φάκελο στον οποίο εκτελείται το agy και το αναφέρει εάν διαφέρει από αυτόν
που δηλώσατε· εάν κανένα agy δεν περιμένει στον φάκελό σας αλλά κάποια περιμένουν αλλού (στον ίδιο φάκελο μέσω symlink, για παράδειγμα), το `start`
τα παραθέτει με την κατάλληλη εντολή. Μέσω `ssh -X` (X11 forwarding) το DISPLAY ορίζεται, επομένως το `start` ανοίγει το παράθυρο τερματικού του agy
στο δικό σας μηχάνημα. Σε έναν φάκελο που κανένα από τα δύο δεν έχει ξαναδεί, τόσο το agy όσο και το Claude Code ζητούν επιβεβαίωση εμπιστοσύνης,
το καθένα στο δικό του παράθυρο: απαντήστε στο agy στην καρτέλα του, διαφορετικά δεν θα γίνει ζεύξη.

### Εκτέλεση του Claude με προφίλ

Ο απλούστερος τρόπος είναι το `--profile`, που χρησιμοποιεί το [agent-profile](https://github.com/ckir/aiprofiles) για να κάνει
τη ρύθμιση για εσάς:

```bash
clavity-ls start ~/path/to/your/project --profile work
```

Το `--profile <name>` μπαίνει αμέσως μετά τον φάκελο, με όποια σειρά ως προς το `--attach`. Τα `agent-profile` και `claude` πρέπει
να βρίσκονται και τα δύο στο PATH. Το `start` εκτελεί `agent-profile claude create <name>`, διαβάζει τον κατάλογο του προφίλ από το
`agent-profile claude doctor <name> --json`, εγκαθιστά σε αυτόν τα `clavity@clavity` και `superpowers@superpowers-marketplace`
(προσθέτοντας πρώτα τα marketplaces `ckir/clavity` και `obra/superpowers-marketplace`, εφόσον λείπουν), ενεργοποιεί όποιο από τα δύο
πρόσθετα είναι απενεργοποιημένο, και μετά εκκινεί το Claude με το `CLAUDE_CONFIG_DIR` ορισμένο σε αυτόν τον κατάλογο. Σημειώσεις:

- Εάν το shell σας έχει ήδη διαφορετικό `CLAUDE_CONFIG_DIR`, το `--profile` το παρακάμπτει και τυπώνει μονόγραμμη ειδοποίηση στο stderr.
- Εάν αποτύχει οποιοδήποτε βήμα της ρύθμισης, το `start` τερματίζει με κωδικό 1 χωρίς να ανοίξει τίποτα.
- Ένα νέο προφίλ ξεκινά κενό: το Claude του σάς ζητά να συνδεθείτε (τα διαπιστευτήρια δεν αντιγράφονται από άλλο προφίλ).
- Τη μεταβλητή τη λαμβάνει μόνο η διεργασία του Claude· η καρτέλα του agy όχι.
- Δύο εκτελέσεις `start --profile X` σε διαφορετικούς φακέλους σειριοποιούνται ανά όνομα προφίλ, ώστε να μη ρυθμίζουν το ίδιο προφίλ ταυτόχρονα.

#### Η χειροκίνητη διαδρομή

Χωρίς το `--profile`, το `start` εκκινεί το Claude Code με το περιβάλλον που κληρονόμησε από το shell σας (προσθέτει μόνο τις τρεις μεταβλητές
`CLAVITY_*` παρακάτω), επομένως ένα [προφίλ του Claude Code](https://docs.anthropic.com/en/docs/claude-code/settings)
επιλέγεται όπως και για ένα απλό `claude`: ορίστε το `CLAUDE_CONFIG_DIR` πριν εκτελέσετε το `start`. Όλα όσα διαβάζει το
Claude από αυτόν τον κατάλογο - `settings.json`, `CLAUDE.md`, τα ενεργά πρόσθετα και το εκτελέσιμο `clavity-ls` που έχουν
κατεβάσει - προέρχονται από το προφίλ, άρα το πρόσθετο `clavity` πρέπει να είναι εγκατεστημένο στο ίδιο προφίλ (εκτελέστε
`claude plugin install clavity@clavity` με τη μεταβλητή ορισμένη), διαφορετικά ο MCP server δεν έχει τι να εκκινήσει. Οι
παράμετροι του ίδιου του Claude περνούν μετά τον φάκελο.

Windows (pwsh· η μεταβλητή ισχύει για αυτό το shell):

```powershell
$env:CLAUDE_CONFIG_DIR = "$HOME\.claude-profiles\test"
clavity-ls start C:\path\to\your\project
```

Linux/macOS (πρόθεμα μίας εκτέλεσης, ή `export` για όλο το shell):

```bash
CLAUDE_CONFIG_DIR=~/.claude-profiles/test clavity-ls start ~/path/to/your/project
```

Το `--attach` λειτουργεί με τον ίδιο τρόπο - η μεταβλητή χρειάζεται μόνο στο shell που εκτελεί το `start`, όχι σε αυτό
που εκτελεί το `clavity-ls agy`.

## Αναφορά εντολών

- `clavity-ls start <folder> [--attach [<session-id>]] [--profile <name>] [claude-args...]` — εκκίνηση ορατής καρτέλας agy + Claude Code στον `<folder>`
  (καταγραφή ανά συνεδρία· προεπιλογή ο τρέχων κατάλογος). Το `--attach` εκκινεί μόνο το Claude, συνδεδεμένο με το agy που ξεκίνησε το
  `clavity-ls agy`· χωρίς id επιλέγει το ένα agy που περιμένει σε αυτόν τον φάκελο. Το `--profile` ρυθμίζει και χρησιμοποιεί ένα επώνυμο προφίλ Claude του [agent-profile](https://github.com/ckir/aiprofiles) (βλ. παραπάνω).
- `clavity-ls agy [folder]` — Linux/macOS: εκτέλεση του agy νέας συνεδρίας σε αυτό το τερματικό και εμφάνιση της εντολής `start --attach` για άλλο τερματικό.
- `clavity-ls --mcp` — εκτέλεση του MCP stdio server (`agy_look` / `agy_status` / `agy_ask`)· εκκινείται αυτόματα μέσω του `.mcp.json`.
- `clavity-ls install [--plugin <name>]` — καταχώριση προσθέτου σε κάθε εντοπισμένο πράκτορα (Claude Code και/ή agy)· προεπιλεγμένο είναι το βασικό
  πρόσθετο `clavity`.
- `clavity-ls uninstall [--purge-data]` — κατάργηση καταχώρισης· το `--purge-data` διαγράφει επίσης τον κατάλογο καταγραφών ανά συνεδρία και τον κατάλογο δεδομένων golden-header.
- `clavity-ls is-installed <plugin-name>` — έξοδος με κωδικό 0 εάν το `<plugin-name>` είναι καταχωρημένο σε εντοπισμένο πράκτορα, 1 διαφορετικά.
- `clavity-ls curate-commit` — ανάγνωση μεταγλωττισμένου golden-header από το stdin και ατομική καταγραφή ως περιοχή GROWTH.

## Ρύθμιση παραμέτρων

- `CLAVITY_GOLDEN_HEADER` — παράκαμψη καταλόγου που περιέχει τα `golden-header.seed.md` / `golden-header.growth.md` (πρέπει να είναι κατάλογος, όχι αρχείο). Προεπιλογή: `%USERPROFILE%\.clavity`.
- `CLAVITY_AGY_LOG` — ορίζεται αυτόματα από το `clavity-ls start`· η διαδρομή αρχείου καταγραφής agy ανά συνεδρία που διαβάζει το `--mcp` για να εντοπίσει τη θύρα Language Server.
- `CLAVITY_SESSION_ID` — ορίζεται αυτόματα από το `clavity-ls start`· δεσμευμένο για bus/memory scoping.
- `CLAVITY_AGY_ENDPOINT` — ορίζεται αυτόματα από το `clavity-ls start`· το αρχείο ανά συνεδρία στο οποίο το agy δημοσιεύει το τελικό του σημείο.
- `CLAVITY_AGY_IDLE_MAX_SECONDS` — ανώτατο όριο χρόνου αναμονής του `agy_ask` για να καταστεί αδρανές το agy (προεπιλογή 600· το `.mcp.json` του προσθέτου το αυξάνει σε 1800).
- `CLAVITY_AGY_IDLE_STALL_SECONDS` — πόσο χρόνο μπορεί το agy να μη δείχνει πρόοδο βήματος πριν το `agy_ask` αναφέρει `possible_modal` (stall). Προεπιλογή 120.
- `CLAVITY_AGY_GENERATION_CAP_SECONDS` — πόσο χρόνο μπορεί το agy να γράφει ΜΙΑ μεγάλη απάντηση (βήμα που εμφανώς παράγεται ακόμη) πριν το `agy_ask` σταματήσει να παρατείνει την αναμονή και αναφέρει `possible_modal` (όριο `generation_cap`). Προεπιλογή 600· το `0` απενεργοποιεί την παράταση. Δεν ξεπερνά ποτέ το `CLAVITY_AGY_IDLE_MAX_SECONDS`.
- `CLAVITY_LS_LOG` — πού γράφεται το αρχείο συμβάντων του διακομιστή. Είναι ενεργό από προεπιλογή: `~/.clavity/logs/clavity-ls-<CLAVITY_SESSION_ID>.log`, ή `clavity-ls-pid<pid>.log` όταν δεν υπάρχει αναγνωριστικό συνεδρίας. Κατάλογος (υπάρχων ή με τελικό διαχωριστικό διαδρομής) παίρνει ένα αρχείο ανά διακομιστή με το ίδιο όνομα· κάθε άλλη τιμή είναι το ίδιο το αρχείο, με προσθήκη στο τέλος· η τιμή `off` (με οποιαδήποτε γραφή πεζών/κεφαλαίων) δεν γράφει αρχείο. Μία γραμμή JSON ανά συμβάν (`ts`, `tool`, `phase`, `dur_ms`, `model`, `model_src`, `endpoint_src`, `outcome`, `call`), με εκκένωση σε κάθε γραμμή· δεν περιέχει ποτέ μήνυμα, απάντηση ή το διακριτικό του αρχείου τελικού σημείου. Κάθε κλήση έχει αναγνωριστικό `p<pid>-<6 ψηφία>`, οπότε το `grep <callId> <logPath>` απομονώνει μία κλήση. Η απάντηση μιας αποτυχίας φέρει `logPath` (ή `logNote` όταν το αρχείο είναι μόνο στη μνήμη) και `callId`· μια αποτυχία του `agy_status` φέρει `LogPath` / `LogNote` / `CallId`· μια άρνηση ορισμάτων τελειώνει με «Logged as <callId> in <path>.». Το αρχείο φτάνει τα 10 MB και τότε περιστρέφεται σε ένα `<όνομα>.old.log`· τα αρχεία παλαιότερα των 7 ημερών διαγράφονται κατά την εκκίνηση του διακομιστή. Ο διακομιστής κρατά επίσης στη μνήμη τα τελευταία 20 συμβάντα και τα γράφει στο stderr· μια αποτυχημένη κλήση τα επιστρέφει στην ίδια την απάντηση (`RecentEvents` / `recentEvents`). Όρια: μια κλήση που διασχίζει περιστροφή έχει τη γραμμή έναρξής της στο `.old.log`· δύο διακομιστές που γράφουν στο ίδιο αρχείο (ρητό κοινό αρχείο, ή η προεπιλογή με κοινό αναγνωριστικό συνεδρίας) μπορεί να χάσουν γραμμές στην περιστροφή· κλήση που ακυρώνει ο καλών ξαναρίχνεται στο SDK, άρα η απάντησή της δεν έχει πεδία, αν και η γραμμή `cancelled` καταγράφεται· τα δικά του σφάλματα «An error occurred invoking» του SDK δεν καλύπτονται.
- `CLAVITY_TERMINAL` — Linux: η εντολή τερματικού με την οποία το `start` ανοίγει το agy (π.χ. `gnome-terminal --tab --`).
- `CLAVITY_DATA_DIR` — παρακάμπτει τον κατάλογο που αφαιρείται από το `uninstall --purge-data` (προεπιλογή `%USERPROFILE%\.clavity`).

## Υποστήριξη πλατφορμών

Διαλειτουργικότητα μεταξύ πλατφορμών — το matrix CI δημιουργεί 4 αυτόνομα πακέτα RID (`win-x64`, `linux-x64`, `osx-arm64`, `osx-x64`)· το `clavity-ls` ανακτάται κατά την πρώτη εκτέλεση αντί να περιλαμβάνεται στο πρόσθετο. Συνεισφορές και αναφορές σφαλμάτων για Linux/macOS είναι ευπρόσδεκτες (δείτε το [CONTRIBUTING.md](../CONTRIBUTING.md)).

## Τεκμηρίωση

- [`plugin/README.md`](plugin/README.md) — περιεχόμενα προσθέτου και συνδέσεις MCP.
- [`plugin/knowledge/agy-assumptions.md`](plugin/knowledge/agy-assumptions.md) — επίσημο εγχειρίδιο agy, ανεξάρτητο οδηγού.
- [`plugin/knowledge/agy-capabilities.md`](plugin/knowledge/agy-capabilities.md) — προφίλ δυνατοτήτων/δρομολόγησης agy.
- [`../docs/agy-ls-assumptions.md`](../docs/agy-ls-assumptions.md) — υποθέσεις πρωτοκόλλου .NET Language Server.
- [`CHANGELOG.md`](CHANGELOG.md) — σημειώσεις έκδοσης.

## Συνεισφορά

Δείτε το [CONTRIBUTING.md](../CONTRIBUTING.md)· οι εντολές build/test αυτού του μέλους βρίσκονται στη Γρήγορη εκκίνηση παραπάνω.

## Άδεια χρήσης

PolyForm Noncommercial License 1.0.0 — δείτε το [LICENSE](../LICENSE).

