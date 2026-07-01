# Changelog

All notable changes to this project will be documented in this file.

## [0.2.0] - 2026-07-01

### Added

- feat: add Codex CLI plugin variant alongside Claude

### Documentation

- docs: refresh README install/update layout and correct direnv requirement note
- docs: point Codex install at procrastivity/codex-plugins marketplace

### Fixed

- fix: surface direnv load errors instead of silently applying partial env
- fix: address Codex review feedback
- fix(codex): probe direnv before caching envrc_dir
- fix(codex): don't wrap `direnv` commands
- fix(codex): cache direnv abs path + partition cache by session_id
- fix(codex): cache direnv_bin before the probe
- fix(codex): re-probe direnv after recovery + fix install command
- fix(codex): match direnv by basename in reprobe hook

## [0.1.1] - 2026-05-31

### Documentation

- release: notify claude-plugins marketplace on release
- docs: refocus README on install/update for end users

### Infrastructure

- release: distinguish missing gh from unauthenticated gh

## [0.1.0] - 2026-05-29

### Fixed

- fix: support nix-direnv better

## [0.0.1] - 2026-05-29

### Other

- Initialize project


