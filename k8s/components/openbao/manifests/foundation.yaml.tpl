apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: openbao
    app.kubernetes.io/component: tenant-openbao
    sovereignworkplace.io/tenant: ${TENANT_NAME}
