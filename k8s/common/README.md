# Common Kubernetes Operations

`common/` contains shared host and Kubernetes operational baselines.

Common logic must not contain tenant names, DNS names, IP addresses, tokens, or
secrets. Scripts here are intended to be reused by tenant hosts and future
operator hosts. Configuration differences should be passed explicitly only when
they are truly required.

- `host/` contains the reusable Ubuntu host baseline.
- `k3s/` contains the reusable single-node k3s baseline.
