# family-infra regression tests

`run.sh` is the regression entrypoint for the `family-infra` environment.

It runs these checks in order:

1. k3s baseline verification.
2. whoami routing smoke test apply.
3. whoami routing smoke test verification.

Run the suite:

```bash
sudo ./k8s/tenants/family-infra/tests/regression/run.sh
```

Run the suite and remove the whoami smoke test afterward:

```bash
sudo ./k8s/tenants/family-infra/tests/regression/run.sh --cleanup
```
