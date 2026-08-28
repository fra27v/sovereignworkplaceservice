apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${SERVICE_ACCOUNT_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: openbao
    app.kubernetes.io/component: tenant-openbao
    sovereignworkplace.io/tenant: ${TENANT_NAME}
automountServiceAccountToken: false
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${CONFIGMAP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: openbao
    app.kubernetes.io/component: tenant-openbao
    sovereignworkplace.io/tenant: ${TENANT_NAME}
data:
  openbao.hcl: |
${OPENBAO_CONFIG}
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ${STATEFULSET_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: openbao
    app.kubernetes.io/component: tenant-openbao
    sovereignworkplace.io/tenant: ${TENANT_NAME}
spec:
  serviceName: ${STATEFULSET_NAME}-bootstrap-no-service
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: openbao
      app.kubernetes.io/component: tenant-openbao
      sovereignworkplace.io/tenant: ${TENANT_NAME}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: openbao
        app.kubernetes.io/component: tenant-openbao
        sovereignworkplace.io/tenant: ${TENANT_NAME}
    spec:
      serviceAccountName: ${SERVICE_ACCOUNT_NAME}
      automountServiceAccountToken: false
      terminationGracePeriodSeconds: 30
      securityContext:
        runAsNonRoot: true
        runAsUser: 100
        runAsGroup: 1000
        fsGroup: 1000
        fsGroupChangePolicy: OnRootMismatch
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: openbao
          image: ${OPENBAO_IMAGE}
          imagePullPolicy: IfNotPresent
          args:
            - server
            - -config=/openbao/config/openbao.hcl
          env:
            - name: BAO_ADDR
              value: http://127.0.0.1:8200
            - name: VAULT_ADDR
              value: http://127.0.0.1:8200
            - name: VAULT_TOKEN
              valueFrom:
                secretKeyRef:
                  name: ${TRANSIT_TOKEN_SECRET_NAME}
                  key: ${TRANSIT_TOKEN_SECRET_KEY}
          ports: []
          volumeMounts:
            - name: config
              mountPath: /openbao/config
              readOnly: true
            - name: ${DATA_VOLUME_NAME}
              mountPath: /openbao/data
            - name: transit-ca
              mountPath: ${TRANSIT_CA_BUNDLE_PATH}
              subPath: ${TRANSIT_CA_BUNDLE_KEY}
              readOnly: true
          startupProbe:
            exec:
              command:
                - sh
                - -ec
                - |
                  bao status -address=http://127.0.0.1:8200 >/dev/null 2>&1
                  code=$?
                  [ "$code" -eq 0 ] || [ "$code" -eq 2 ]
            failureThreshold: 30
            periodSeconds: 10
          readinessProbe:
            exec:
              command:
                - sh
                - -ec
                - |
                  bao status -address=http://127.0.0.1:8200 >/dev/null 2>&1
                  code=$?
                  [ "$code" -eq 0 ] || [ "$code" -eq 2 ]
            periodSeconds: 10
            failureThreshold: 3
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 768Mi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
            readOnlyRootFilesystem: false
      volumes:
        - name: config
          configMap:
            name: ${CONFIGMAP_NAME}
        - name: transit-ca
          configMap:
            name: ${TRANSIT_CA_BUNDLE_CONFIGMAP_NAME}
  volumeClaimTemplates:
    - metadata:
        name: ${DATA_VOLUME_NAME}
        labels:
          app.kubernetes.io/name: openbao
          app.kubernetes.io/component: tenant-openbao
          sovereignworkplace.io/tenant: ${TENANT_NAME}
      spec:
        accessModes:
          - ReadWriteOnce
        storageClassName: ${STORAGE_CLASS}
        resources:
          requests:
            storage: ${STORAGE_SIZE}
