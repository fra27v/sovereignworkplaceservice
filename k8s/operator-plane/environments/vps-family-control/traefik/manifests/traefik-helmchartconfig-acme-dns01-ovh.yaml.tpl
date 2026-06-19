apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: ${TRAEFIK_HELMCHARTCONFIG_NAME}
  namespace: ${TRAEFIK_NAMESPACE}
spec:
  valuesContent: |-
    envFrom:
      - secretRef:
          name: ${TRAEFIK_OVH_DNS_SECRET_NAME}

    persistence:
      enabled: true
      path: /data

    service:
      spec:
        externalTrafficPolicy: ${TRAEFIK_SERVICE_EXTERNAL_TRAFFIC_POLICY}

    additionalArguments:
      - "--certificatesresolvers.${TRAEFIK_ACME_CERT_RESOLVER}.acme.email=${TRAEFIK_ACME_EMAIL}"
      - "--certificatesresolvers.${TRAEFIK_ACME_CERT_RESOLVER}.acme.storage=${TRAEFIK_ACME_STORAGE_PATH}"
      - "--certificatesresolvers.${TRAEFIK_ACME_CERT_RESOLVER}.acme.dnschallenge=true"
      - "--certificatesresolvers.${TRAEFIK_ACME_CERT_RESOLVER}.acme.dnschallenge.provider=${TRAEFIK_ACME_DNS_PROVIDER}"
      - "--certificatesresolvers.${TRAEFIK_ACME_CERT_RESOLVER}.acme.dnschallenge.resolvers=${TRAEFIK_ACME_DNS_RESOLVERS}"
      - "--certificatesresolvers.${TRAEFIK_ACME_CERT_RESOLVER}.acme.dnschallenge.delaybeforecheck=${TRAEFIK_ACME_DNS_DELAY_BEFORE_CHECK}"
${TRAEFIK_ACME_CA_SERVER_ARGUMENT}
