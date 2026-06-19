# Operator Artifacts Scripts

Environment-specific helper scripts for the `vps-family-control` operator artifact repository belong here.

Scripts must not embed real tokens, certificates, private keys, or real domains.

Current scripts:

- `prepare-local-operator-artifacts-files.sh`: prepares local public/private artifact directories and a non-secret dummy artifact.
- `create-family-infra-01-artifact-token.sh`: creates local tenant token and BasicAuth material without printing the token.
- `render-operator-artifacts.sh`: renders the operator-artifacts Kubernetes manifest to a temporary file without applying it.
- `install-operator-artifacts.sh`: renders and applies operator-artifacts resources, then verifies metadata and public-only hostPath mounts.
- `verify-operator-artifacts.sh`: verifies deployed operator-artifacts resources without printing tokens, htpasswd contents, or Secret data.
