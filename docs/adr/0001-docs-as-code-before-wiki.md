# ADR 0001 - Documentation-as-Code Before the Wiki

## Status

Accepted.

## Context

The repository does not yet contain an implemented wiki. It does contain operational configuration, scripts, Compose files, and identity objects that must remain aligned with the code.

## Decision

Primary documentation is kept in `docs/` as versioned Markdown.

## Consequences

- Architectural changes can be reviewed together with code.
- Documentation remains available even without a wiki platform.
- A future wiki can publish or index these files, not replace them as the primary source.

TODO: define whether and how to publish `docs/` in a future wiki.
