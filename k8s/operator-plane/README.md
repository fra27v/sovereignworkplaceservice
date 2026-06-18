# Operator Plane

The operator plane contains platform administration configuration that is shared
across tenant environments.

This area is for runbooks, architecture decisions, OpenBao bootstrap material,
and family control-plane environment examples.

Global OpenBao runs in the operator plane. Its public hostname, external
address, storage path, audit log path, and seal key path are environment-specific
configuration and must not be hardcoded in reusable component files.

Example files must not contain real secrets. Seal key files and transit tokens
must never be committed to Git.
