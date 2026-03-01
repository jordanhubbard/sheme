# Contributing to sheme

## Filing Bugs

Open a GitHub issue. Include:
- Your shell and version (`bash --version` or `zsh --version`)
- A minimal Scheme expression that reproduces the problem
- Expected vs actual output (include `$__bs_last` if relevant)

## Submitting Pull Requests

1. Fork the repo and create a feature branch from `main`.
2. Make your changes.
3. Verify all tests pass: `make test-all`
4. Open a PR against `main` with a clear description of what changed and why.

### PR Checklist

- [ ] `make test-all` passes (bash, zsh, R5RS, and I/O test suites)
- [ ] `make check` passes (syntax validation)
- [ ] New builtins or behaviour changes are covered by tests in `tests/bs.bats`
  and `tests/bs-zsh.zsh`
- [ ] R5RS compatibility is not regressed (`make test-r5rs`)

## Running Tests

```bash
make check          # syntax validation only (fast)
make test           # bash (BATS) and zsh test suites
make test-io        # terminal I/O builtin tests (bash only)
make test-r5rs      # R5RS compatibility suite
make test-all       # everything above
make benchmark      # performance benchmarks
```

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/) — the release
script uses these to categorize changelog entries automatically:

```
feat: add call/cc (call-with-current-continuation)
fix: correct tail-call optimization for mutual recursion
docs: document bs-eval vs bs usage
refactor: extract number parser into _bs_parse_number
chore: update CI to use actions/checkout@v4
```

## Code Conventions

- **bash version (`bs.sh`)**: requires bash 4.3+; use `[[ ]]`, `local`, arrays.
  Avoid bashisms that fail under `bash -n`.
- **zsh version (`bs.zsh`)**: use native zsh syntax; keep parallel with `bs.sh`.
- Both files are sourced into the user's shell — keep the global namespace clean.
  All internal names are prefixed `_bs_`.
- No external runtime dependencies beyond bash/zsh builtins.
- The interpreter state lives in shell variables (`_bs_env`, `_bs_heap`, etc.);
  avoid subshells in hot paths as they fork the whole interpreter state.

## Release Process

Maintainers only:

```bash
make release           # patch bump (default)
make release BUMP=minor
make release BUMP=major
```

This runs the full test suite, updates `CHANGELOG.md`, tags, and creates a
GitHub release.
