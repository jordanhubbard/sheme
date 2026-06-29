# Contributing to sheme

## Filing Bugs

Open a GitHub issue. Include:
- Your shell and version (`bash --version` or `zsh --version`)
- A minimal Scheme expression that reproduces the problem
- Expected vs actual output (include `$__bs_last` if relevant)

## Submitting Pull Requests

1. Fork the repo and create a feature branch from `main`.
2. Make your changes.
3. Before every push, run `make test-all` and `make example` once from the
   repository root. The Makefile invokes Bash or zsh for each target.
4. Verify that no test is reported as failed and that only the six documented
   unsupported R5RS features are skipped.
5. Open a PR against `main` with a clear description of what changed and why.

### PR Checklist

- [ ] `make test-all` passes (Bash, zsh, AOT, R5RS, and I/O suites)
- [ ] `make example` passes (maintained Bash and zsh demos)
- [ ] `make check` passes (syntax validation)
- [ ] New builtins or behaviour changes are covered by tests in `tests/bs.bats`
  and `tests/bs-zsh.zsh`
- [ ] R5RS compatibility is not regressed (`make test-r5rs`)

## Running Tests

```bash
make check          # syntax validation only (fast)
make test           # Bash + zsh interpreter suites and both AOT targets
make test-compiler  # focused Bash/zsh compiler regressions
make test-io        # dedicated 41-case Bash I/O harness
make test-r5rs      # 123 R5RS-subset checks against Bash (6 skips)
make test-examples  # maintained algorithms/channels/todo regressions
make test-all       # all suites above
make benchmark      # performance benchmarks
```

GitHub Actions runs the same `make test-all` and `make example` gates on
Ubuntu and macOS.

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/) — the release
script uses these to categorize changelog entries automatically:

```
feat: add unquote-splicing support
fix: preserve zsh state across nested eval-string calls
docs: document bs-eval vs bs usage
refactor: extract number parser into _bs_parse_number
chore: update CI to use actions/checkout@v4
```

## Code Conventions

- **Bash (`bs.sh`)**: requires Bash 4.3+. The interpreter runs inline and its
  global helpers/state are visible, so all internals must retain the `__bs_` or
  `__bsc_` prefix. This file also hosts both AOT compiler targets.
- **zsh (`bs.zsh`)**: requires zsh 5+. Interpreter internals are local to
  `bs()`, and persistent fields must be serialized through the private,
  owner-only `__BS_STATE_FILE`.
- Keep Scheme semantics and extension builtins aligned across both files even
  where their shell implementation differs.
- Core evaluation should avoid external processes in hot paths. Terminal,
  file, and shell-command extensions intentionally use standard utilities.
- Keep the AOT compiler application-neutral. Programs that need specialized
  nested state should use `--runtime` and, when needed, `--replace-functions`.
  shemacs owns its runtime in `../shemacs/em.aot-runtime.sh`.
- Compiler changes need focused coverage in `tests/compiler-tests.sh` and must
  be checked in both output shells. Changes affecting shemacs also require its
  Bash and zsh integration suites.

## Release Process

Maintainers only:

```bash
make release           # patch bump (default)
make release BUMP=minor
make release BUMP=major
```

This runs the full test and example gates before changing files, updates
`CHANGELOG.md`, tags, and creates a GitHub release. A retry recognizes an
existing version heading or a tag already at `HEAD`, so a transient GitHub
failure does not silently bump the version twice.
