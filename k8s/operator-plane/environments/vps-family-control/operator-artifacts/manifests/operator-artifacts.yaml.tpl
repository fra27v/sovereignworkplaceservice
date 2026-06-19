apiVersion: v1
kind: Namespace
metadata:
  name: ${OPERATOR_ARTIFACTS_NAMESPACE}
---
apiVersion: v1
kind: Secret
metadata:
  name: ${OPERATOR_ARTIFACTS_BASICAUTH_SECRET_NAME}
  namespace: ${OPERATOR_ARTIFACTS_NAMESPACE}
type: Opaque
stringData:
  users: "${OPERATOR_ARTIFACTS_BASICAUTH_USERS_PLACEHOLDER}"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${OPERATOR_ARTIFACTS_SERVICE_NAME}
  namespace: ${OPERATOR_ARTIFACTS_NAMESPACE}
  labels:
    app.kubernetes.io/name: ${OPERATOR_ARTIFACTS_SERVICE_NAME}
    app.kubernetes.io/component: operator-artifacts
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: ${OPERATOR_ARTIFACTS_SERVICE_NAME}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ${OPERATOR_ARTIFACTS_SERVICE_NAME}
        app.kubernetes.io/component: operator-artifacts
    spec:
      containers:
        - name: nginx
          image: nginx:stable-alpine
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 80
          volumeMounts:
            - name: public-artifacts
              mountPath: /usr/share/nginx/html
              readOnly: true
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
      volumes:
        - name: public-artifacts
          hostPath:
            path: ${OPERATOR_ARTIFACTS_PUBLIC_DIR}
            type: Directory
---
apiVersion: v1
kind: Service
metadata:
  name: ${OPERATOR_ARTIFACTS_SERVICE_NAME}
  namespace: ${OPERATOR_ARTIFACTS_NAMESPACE}
  labels:
    app.kubernetes.io/name: ${OPERATOR_ARTIFACTS_SERVICE_NAME}
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: ${OPERATOR_ARTIFACTS_SERVICE_NAME}
  ports:
    - name: http
      port: 80
      targetPort: http
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: ${OPERATOR_ARTIFACTS_SERVICE_NAME}-basicauth
  namespace: ${OPERATOR_ARTIFACTS_NAMESPACE}
spec:
  basicAuth:
    secret: ${OPERATOR_ARTIFACTS_BASICAUTH_SECRET_NAME}
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: ${OPERATOR_ARTIFACTS_SERVICE_NAME}
  namespace: ${OPERATOR_ARTIFACTS_NAMESPACE}
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`${OPERATOR_ARTIFACTS_PUBLIC_HOSTNAME}`)
      kind: Rule
      middlewares:
        - name: ${OPERATOR_ARTIFACTS_SERVICE_NAME}-basicauth
      services:
        - name: ${OPERATOR_ARTIFACTS_SERVICE_NAME}
          port: 80
  tls:
    certResolver: ${OPERATOR_ARTIFACTS_TLS_CERT_RESOLVER}
