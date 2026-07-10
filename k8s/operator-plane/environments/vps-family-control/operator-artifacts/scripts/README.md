# Operator Artifacts Scripts

Environment-specific helper scripts for the `vps-family-control` operator artifact repository belong here.

Scripts must not embed real tokens, certificates, private keys, or real domains.
Scripts load operational configuration from the central
`operator-plane.env` file. They ignore `operator-artifacts.env`; component
real env files are not steady-state sources of truth.

Current scripts:

- `prepare-local-operator-artifacts-files.sh`: prepares local public/private artifact directories and a non-secret dummy artifact.
- `create-family-infra-01-artifact-token.sh`: creates local tenant token and BasicAuth material without printing the token.
- `render-operator-artifacts.sh`: renders the operator-artifacts Kubernetes manifest to a temporary file without applying it.
- `install-operator-artifacts.sh`: renders and applies operator-artifacts resources, then verifies metadata and public-only hostPath mounts.
- `verify-operator-artifacts.sh`: verifies deployed operator-artifacts resources without printing tokens, htpasswd contents, or Secret data.
- `update-operator-artifacts-ip-allowlist.sh`: updates the central environment allowlist, reapplies operator-artifacts, and verifies the deployment.

Use `update-operator-artifacts-ip-allowlist.sh` when the home public IP changes.
The script updates the real local `operator-plane.env` file, creates a
timestamped backup, reapplies `operator-artifacts`, and runs verification.

Examples:

```bash
sudo ./k8s/operator-plane/environments/vps-family-control/operator-artifacts/scripts/update-operator-artifacts-ip-allowlist.sh --home-ip <home-public-ip> --dry-run --show-masked

sudo ./k8s/operator-plane/environments/vps-family-control/operator-artifacts/scripts/update-operator-artifacts-ip-allowlist.sh --home-ip <home-public-ip>

sudo ./k8s/operator-plane/environments/vps-family-control/operator-artifacts/scripts/update-operator-artifacts-ip-allowlist.sh --set-ranges "127.0.0.1/32,::1/128,<home-public-ip>/32"
```

Do not paste real IPs, tokens, htpasswd contents, Secret data, or rendered
manifests into chat, logs, tickets, or Git.
