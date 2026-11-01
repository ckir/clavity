<!-- Thanks for contributing to clavity! -->

## What & why

<!-- What does this PR change, and why? -->

## How verified

<!-- Run verification relevant to the modified member(s): -->

- [ ] `just test` passes locally across all tools
- [ ] `just lint` is clean
- [ ] `dotnet test tests/Clavity.Ls.Tests` *(if touching clavity-dotnet)*
- [ ] `cargo test --all --features test-fakes` *(if touching clavity-classic)*
- [ ] `python3 -m unittest discover -s .github/site-checks` *(if touching site/)*
- [ ] `python3 .github/site-checks/check_site.py --site site --readme README.md` *(if touching site/)*
- [ ] `just check-control-bytes` is clean *(if touching markdown or scripts)*

## Notes

<!-- Platform(s) tested, follow-ups, anything reviewers should know. -->
