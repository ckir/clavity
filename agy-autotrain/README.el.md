# agy-autotrain — μάθετε από κάθε κλήση του agy, και κρατήστε την καθοδήγηση ακριβή

[English](README.md) | [Ελληνικά](README.el.md)

Ένα **προαιρετικό** πρόσθετο Claude Code για τον **βρόχο εκμάθησης** καθοδήγησης του agy, **χωρίς
αλλαγές σε δυαδικά αρχεία** (συνθέτει τις υπάρχουσες εντολές `clavity` + markdown). Η καθημερινή χρήση
καθοδήγησης του agy τροφοδοτεί τον βρόχο, και η επιμελημένη γνώση εισάγεται ξανά σε κάθε μελλοντική κλήση.

> **Η ίδια η καθοδήγηση βρίσκεται στα βασικά πρόσθετα (CORE), όχι εδώ.** Το πρωτόκολλο ανάθεσης εργασιών που αποτρέπει
> τα λάθη του agy (REVIEW-ONLY banner, απομόνωση φάσεων, υποχρεωτικό σημείο ελέγχου πριν από μεταβολές,
> αρχικοποίηση αναλλοίωτων) διατίθεται στις βασικές δεξιότητες οδήγησης — `driving` (classic) και
> `ls-driving` (dotnet) — ώστε να μπορείτε να καθοδηγείτε το agy με ή χωρίς αυτό το πρόσθετο. Το agy-autotrain προσθέτει
> τον βρόχο *εκμάθησης* — και τη δεξιότητα `adversarial-panel-review` — επιπλέον.

Τι κάνει αυτό το πρόσθετο: **καταγραφή → επιμέλεια → επαλήθευση → μεταγλώττιση**, στη συνέχεια προώθηση από τοπικό έργο σε καθολικό επίπεδο,
και παραγωγή ενός compiled golden header το οποίο και τα δύο εκτελέσιμα καθοδήγησης (dotnet `clavity-ls` και classic `clavity`)
προσαρτούν πριν από κάθε ερώτημα.

## Πώς λειτουργεί

```
drive agy (core driving skill) ──learn──▶ ~/.clavity/agy-observations.md   (inbox: sanitised general rules)
        ▲                                          │
        │ golden-header (injected by the binary)   │ periodic
        │                                          ▼
 shared golden-header.growth.md ◀──compile+commit── agy-curate ──dedupe vs SEED floor──▶ (SEED is driver-owned,
   (%USERPROFILE%\.clavity\ — GROWTH region)        │            NOT edited here: seed/golden-header.md baseline)
                                                   └──verify (synthetic clavity ask)──▶ verify/assertions.md
```

- **Καταγραφή** (`agy-learn`): τη στιγμή που μαθαίνετε κάτι γενικό για το agy, ένα Structured Abstraction
  Schema αφαιρεί τα ουσιαστικά του έργου σε έναν `[General Rule]`, ταξινομημένο ως `assumption | heuristic |
  anti-pattern`, και τον προσθέτει στα εισερχόμενα (inbox). Γρήγορο, ζωντανό, ανεξάρτητο από το έργο.
- **Επιμέλεια** (`agy-curate`): αδειάζει τα εισερχόμενα στην **περιοχή GROWTH** του κοινόχρηστου golden-header
  βάσει κανόνα προώθησης (heuristic ≥2 παρατηρήσεις μεταξύ συνεδριών· empirical = 100% επιτυχία στο harness — φυσική
  εκτέλεση της δοκιμής), αφαιρώντας διπλότυπα έναντι της βάσης SEED του οδηγού, και **το κατοχυρώνει μέσω του δυαδικού αρχείου**
  (`clavity-ls curate-commit` → `golden-header.growth.md`), αδειάζοντας τα εισερχόμενα. Ποτέ δεν τροποποιεί τα εγχειρίδια SEED.
- **Επαλήθευση** (`verify/`): κάθε Empirical Assumption διαθέτει συνθετική δοκιμή `clavity ask` + pass/fail.
  Το [`verify/README.md`](verify/README.md) την ευρετηριάζει· το [`verify/probe-design.md`](verify/probe-design.md)
  καλύπτει τον σχεδιασμό νέας δοκιμής.
- **Γνώση** (`knowledge/`): διατηρεί τα εισερχόμενα καταγραφής `agy-observations.md` και την καρφιτσωμένη βάση
  `driver-cheatsheet.core.md` (διατηρείται πανομοιότυπη με τις σταθερές και στα δύο εκτελέσιμα αρχεία — δείτε το
  [CONTRIBUTING.md](CONTRIBUTING.md)). Τα επίσημα εγχειρίδια (`agy-capabilities.md` / `agy-assumptions.md`)
  και η βάση SEED `golden-header.md` **ανήκουν στον οδηγό** — αποστέλλονται με τα πρόσθετα οδηγών
  (clavity-dotnet, clavity-classic), όχι εδώ· το agy-curate τα διαβάζει ως βάση αλλά δεν τα επεξεργάζεται ποτέ.

Η δεξιότητα `adversarial-panel-review` (αξιολόγηση AGY-AFTER team-panel) και το hook υπενθύμισης PostToolUse
διατίθενται πλέον με το πρόσθετο κάθε οδηγού (`clavity-dotnet/plugin`, `clavity-classic/plugin`) αντί για εδώ —
το agy-autotrain διατηρεί μόνο τον βρόχο εκμάθησης (learn/curate/verify + τα εισερχόμενα παρατηρήσεων).

### Εύρος

Αρχικά σε τοπικό επίπεδο έργου (επαλήθευση του βρόχου), στη συνέχεια προώθηση δεξιοτήτων + γνώσης στην καθολική διαμόρφωση — το
καθιερωμένο μοτίβο trial-then-globalise. Αναβλήθηκε (δυαδικό, εκτός πεδίου): αυτόματο υποσέλιδο τηλεμετρίας στο
`clavity ask` + ιστορικό `clavity log` — επανεξέταση μόνο με επιτακτικό λόγο.

## Τι περιλαμβάνεται εδώ

```
agy-autotrain/
  .claude-plugin/plugin.json · plugin.json   # διπλά manifests
  skills/agy-learn/          # καταγραφή (sanitise → inbox)
  skills/agy-curate/         # επιμέλεια (promote/verify/recompile → curate-commit)
  knowledge/agy-observations.md         # ΠΡΟΤΥΠΟ ΜΟΡΦΗΣ εισερχομένων καταγραφής
  knowledge/driver-cheatsheet.core.md   # καρφιτσωμένη βάση (βλ. CONTRIBUTING.md)
  verify/assertions.md · run-verification.md   # το ζωντανό harness δοκιμών
```

## Εγκατάσταση

```powershell
claude plugin marketplace add ckir/clavity
claude plugin install agy-autotrain@clavity
```

Αυτό καταχωρεί το agy-autotrain μόνο στο Claude Code (ποτέ στο agy, το οποίο δεν το χρειάζεται). Για απεγκατάσταση:
`claude plugin uninstall agy-autotrain@clavity`.

**Από κλώνο (προγραμματιστές):**

```
claude plugin install ./agy-autotrain
```

Η οδήγηση χρειάζεται μόνο το βασικό πρόσθετο· εγκαταστήστε αυτό το πρόσθετο όταν θέλετε επίσης το agy να *μαθαίνει*. Όταν
μαθαίνετε κάτι για το agy, εκτελέστε το `agy-learn`· περιοδικά εκτελείτε το `agy-curate` για compile + commit του
golden header.

## Ρύθμιση παραμέτρων

- `CLAVITY_GOLDEN_HEADER` — παρακάμπτει τον κατάλογο από τον οποίο διαβάζονται και στον οποίο γράφονται τα κοινόχρηστα αρχεία golden-header (SEED + GROWTH).
  Προεπιλογή `%USERPROFILE%\.clavity\`. Διαβάζεται/ορίζεται από το `agy-curate` (δείτε το
  `skills/agy-curate/SKILL.md`)· μόνο το δυαδικό αρχείο μπορεί να το επιλύσει κατά την εισαγωγή.

## Αντιμετώπιση προβλημάτων

- **Οι κανόνες που αποκτήθηκαν δεν εμφανίζονται ποτέ στο περιβάλλον του agy.** Κανένας οδηγός clavity (clavity-dotnet ή
  clavity-classic) δεν έχει εγκατασταθεί ακόμα — το agy-autotrain λειτουργεί πάνω σε έναν αλλά δεν αποστέλλει δικό του εκτελέσιμο,
  οπότε τίποτα δεν εισάγει το golden header μέχρι να υπάρξει οδηγός. Εγκαταστήστε έναν.

## Ανάκτηση χαμένων παρατηρήσεων ή εσφαλμένης περιοχής GROWTH

Και τα δύο τεχνουργήματα διατηρούν τα 5 νεότερα στιγμιότυπα πριν από κάθε τροποποίηση, με τη διαφορά ότι τα στιγμιότυπα της περιοχής GROWTH γράφονται
μόνο από το `clavity-ls curate-commit` του clavity-dotnet: το `curate-commit` του clavity-classic δεν τα δημιουργεί, επομένως η παρακάτω διαδικασία GROWTH
ισχύει για το clavity-dotnet. Ένα αντίγραφο ασφαλείας από το οποίο κανείς δεν μπορεί να επαναφέρει είναι άχρηστο, επομένως και οι δύο διαδικασίες είναι μία εντολή.

**Τα εισερχόμενα παρατηρήσεων:**

```powershell
$k = "$HOME\.clavity"
Get-ChildItem "$k\agy-observations.md.*.bak" | Sort-Object LastWriteTime -Descending
Copy-Item "$k\agy-observations.md.<stamp>.bak" "$k\agy-observations.md"
```

Τα επαναφερθέντα εισερχόμενα είναι εισερχόμενα ΠΡΙΝ από την εκκαθάριση (drain). Οι καταχωρίσεις τους είχαν ήδη ενσωματωθεί στο GROWTH από την εκκαθάριση που
αναιρείτε, επομένως **συμφιλιώστε πριν από την επόμενη εκκαθάριση**: συγκρίνετε το επαναφερθέν `## Pending` με την τρέχουσα
περιοχή GROWTH και διαγράψτε οτιδήποτε αντιπροσωπεύεται ήδη εκεί.

**Η περιοχή GROWTH — επαναφέρετε πάντα και τα δύο αρχεία:**

```powershell
Get-ChildItem "$HOME\.clavity\golden-header.growth.md.*.bak" | Sort-Object LastWriteTime -Descending
Copy-Item "$HOME\.clavity\golden-header.growth.md.<stamp>.bak"        "$HOME\.clavity\golden-header.growth.md"
Copy-Item "$HOME\.clavity\golden-header.growth.md.<stamp>.bak.sha256" "$HOME\.clavity\golden-header.growth.md.sha256"
```

Η επαναφορά της επικεφαλίδας μόνης της αφήνει το προηγούμενο sidecar στη θέση του· τα hashes δεν ταιριάζουν και η ανάγνωση
απορρίπτει σιωπηρά την περιοχή.

Τα στιγμιότυπα περιστρέφονται μόνο με βάση την κατάληξη `.bak`.

**Τι δεν καλύπτουν τα στιγμιότυπα.** Αυτά προστατεύουν από απώλεια — ένα αποκομμένο αρχείο, μια κακή επεξεργασία, μια εκκαθάριση που
πήγε στραβά. Δεν εντοπίζουν σιωπηλή αλλοίωση: εάν το περιεχόμενο είναι λάθος όταν φτάνει, το στιγμιότυπο διατηρεί πιστά το λάθος περιεχόμενο.

## Τεκμηρίωση

- [ROADMAP.md](ROADMAP.md) — backlog βελτιώσεων για τον βρόχο εκμάθησης.
- [docs/fix-the-tool-backlog/](docs/fix-the-tool-backlog/README.md) — ντετερμινιστικά ελαττώματα οδηγού/εργαλείου που
  το `agy-curate` αρνήθηκε να προωθήσει σε γνώση.

## Συνεισφορά

Δείτε το [CONTRIBUTING.md](CONTRIBUTING.md).

## Άδεια χρήσης

[PolyForm Noncommercial License 1.0.0](LICENSE) (`PolyForm-Noncommercial-1.0.0`) — δωρεάν για
μη εμπορική χρήση. Δείτε το [NOTICE](NOTICE) για τη σημείωση πνευματικών δικαιωμάτων.
