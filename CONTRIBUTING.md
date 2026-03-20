# Contributing

## Prerequisites

- Dart SDK 3.10 or newer
- Flutter 3.38 or newer for `comon_otel_flutter`
- Melos 7.x
- Docker Desktop for collector-backed integration flows and the demo stack

Install Melos globally if you do not already have it:

```bash
dart pub global activate melos
```

## Workspace Setup

Clone the repository and bootstrap the workspace from the root:

```bash
dart pub get
melos bootstrap
```

This repository uses a Dart workspace plus Melos. The root `pubspec.yaml` is
the source of truth for workspace configuration.

## Common Commands

Run all package analysis:

```bash
melos run analyze
```

Run all package tests:

```bash
melos run test
```

Format all packages:

```bash
melos run format
```

Validate publishability without uploading:

```bash
melos run publish
```

Generate package documentation:

```bash
melos run doc
```

## Integration and Demo Flows

Some flows require Docker:

- the collector-backed end-to-end demo under `demo/otel_end_to_end`
- collector-oriented validation while working on OTLP export behavior

Start the local demo stack from the repository root:

```bash
docker compose -f demo/otel_end_to_end/docker-compose.yml up -d --build
```

## Code Style

- Keep changes focused and avoid unrelated refactors.
- Preserve existing public APIs unless the change explicitly requires an API adjustment.
- Add documentation for public APIs when introducing new surface area.
- Prefer tests that validate behavior, not implementation details.
- Do not commit generated local workspace artifacts or temporary override files.

## Pull Requests

Before opening a pull request, ensure the following:

- `melos run analyze` passes
- `melos run test` passes
- relevant package `publish --dry-run` checks pass when changing package metadata, README, or examples
- `CHANGELOG.md` is updated when the change affects package behavior or public API

PRs should explain:

- what changed
- why the change is needed
- how the change was validated
- whether there are API, docs, or migration implications

## Reporting Issues

When filing an issue, include:

- package name and version
- Dart and Flutter SDK versions
- operating system
- reproduction steps
- expected behavior
- actual behavior
- logs, stack traces, or collector output when relevant