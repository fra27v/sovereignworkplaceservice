# Family Infrastructure Environment

This environment is the first family operational target for Kubernetes planning.

The files are placeholders and examples only; they do not migrate the existing
Docker services.

Tenant OpenBao runs in this environment and uses Global OpenBao transit
autounseal. The Global OpenBao transit address is environment-specific
configuration and must not be hardcoded in reusable platform components.

Applications in this environment use Tenant OpenBao, not Global OpenBao.

Example files must not contain real secrets. Seal key files and transit tokens
must never be committed to Git.
