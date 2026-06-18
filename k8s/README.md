# Kubernetes Lab Structure

This directory is the starting point for the future k3s-based platform layout.
It documents the intended structure only; it does not install k3s, migrate Docker
services, or define production secrets.

The Docker lab is closed by the `DockerLabEnd` Git tag. Kubernetes work starts
from this directory and should use `.example` files for local or sensitive
configuration samples.

Reusable platform components must not hardcode environment-specific DNS names,
IP addresses, host paths, tokens, or seal material. Values such as the Global
OpenBao transit address for autounseal belong in environment configuration.

Applications use Tenant OpenBao, not Global OpenBao. Global OpenBao is an
operator-plane service used for platform-level functions such as transit
autounseal.
