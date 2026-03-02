# Changelog

All notable changes to sheme are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

> **Note**: The Emacs-like editor (`em.scm` / `em.scm.sh`) that was originally
> developed as part of sheme has been spun out to its own project:
> [shemacs](https://github.com/jordanhubbard/shemacs).
> sheme is now a pure Scheme interpreter for shell programmers.

## [Unreleased]

## [1.0.7] - 2026-03-01


## [1.0.6] - 2026-03-01


## [1.0.5] - 2026-03-01

### Fixed
- split dsusp from terminal-raw! stty call for Linux compatibility


## [1.0.4] - 2026-03-01


## [1.0.3] - 2026-03-01


## [1.0.2] - 2026-03-01

### Fixed
- correct bash regex patterns in changelog categorizer

### Other
- Rename bad-scheme → sheme, bad-emacs → shemacs
- Address @forthrin's remaining feedback on shemacs issue #5
- Fix dsusp conflict in terminal-raw! (shemacs issue #2)
- Move editor to shemacs; replace examples with Scheme programs
- Add new builtins for shemacs em.scm; spin off editor to shemacs; clean up docs
- Update README to reflect choice of 'sheme'


## [1.0.2] - 2026-03-01

### Fixed
- correct bash regex patterns in changelog categorizer

### Other
- Rename bad-scheme → sheme, bad-emacs → shemacs
- Address @forthrin's remaining feedback on shemacs issue #5
- Fix dsusp conflict in terminal-raw! (shemacs issue #2)
- Move editor to shemacs; replace examples with Scheme programs
- Add new builtins for shemacs em.scm; spin off editor to shemacs; clean up docs
- Update README to reflect choice of 'sheme'


## [1.0.1] - 2026-02-28

### Added
- `string->list` and `list->string` builtins

## [1.0.0] - 2026-02-28

### Added
- Scheme interpreter implemented as sourceable bash functions (`bs.sh`)
- Zsh-native Scheme interpreter (`bs.zsh`) with full R5RS subset support
- Terminal I/O builtins: `read-byte`, `write-stdout`, file I/O, `eval-string`
- Comprehensive bash test suite (BATS format, 177 tests)
- Zsh test suite (202 tests)
- R5RS compatibility tests (123 tests) and I/O builtin tests (41 tests)
- Performance benchmark suite
- Example scripts: feature demo, algorithms, concurrency patterns, interactive REPL
- `make release` target for automated versioning and GitHub releases

### Changed
- Encapsulated interpreter internals behind a public API (`bs` / `bs-eval`)
- Renamed source files from `bad-scheme` to `bs.{sh,zsh}`
- Rewrote editor as vector-based with `eval-buffer` support

### Fixed
- Duplicate comment and dead code in initial implementation
