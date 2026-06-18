#!/bin/sh
set -eu

BASE_URL="${MIDPOINT_URL:-https://midpoint:8443/midpoint}"
USER="${MIDPOINT_USER:-administrator}"
PASS_FILE="${MIDPOINT_PASSWORD_FILE:-/secrets/midpoint_adm_password}"

PASS="$(cat "$PASS_FILE")"

echo "Using midPoint at: $BASE_URL"
echo "Using user: $USER"

cd /import/bootstrap

echo "Waiting for midPoint..."
until curl -k -sS "$BASE_URL" >/dev/null 2>&1; do
  echo "midPoint not ready yet..."
  sleep 3
done

echo "midPoint is reachable."

get_type_and_oid() {
  file="$1"

  root="$(grep -m1 -Eo '<(role|org|user|archetype|resource|objectTemplate|objectCollection|systemConfiguration|task)[^>]*' "/import/objects/$file" | sed 's/^<//' | awk '{print $1}')"
  oid="$(grep -m1 -Eo 'oid="[^"]+"' "/import/objects/$file" | sed 's/oid="//;s/"//')"

  case "$root" in
    role) collection="roles" ;;
    org) collection="orgs" ;;
    user) collection="users" ;;
    archetype) collection="archetypes" ;;
    resource) collection="resources" ;;
    objectTemplate) collection="objectTemplates" ;;
    objectCollection) collection="objectCollections" ;;
    systemConfiguration) collection="systemConfigurations" ;;
    task) collection="tasks" ;;
    *)
      echo "ERROR: unsupported root element '$root' in $file" >&2
      exit 1
      ;;
  esac

  if [ -z "$oid" ]; then
    echo "ERROR: missing oid in $file" >&2
    exit 1
  fi

  echo "$collection $oid"
}

import_object() {
  file="$1"

  set -- $(get_type_and_oid "$file")
  collection="$1"
  oid="$2"

  url="$BASE_URL/ws/rest/$collection/$oid"

  echo "Importing $file -> $collection/$oid"

  http_code="$(curl -k -sS -o /tmp/midpoint-import-result.xml -w "%{http_code}" \
    -u "$USER:$PASS" \
    -H "Content-Type: application/xml" \
    -X PUT "$url" \
    --data-binary "@/import/objects/$file")"

  if [ "$http_code" = "200" ] || [ "$http_code" = "201" ] || [ "$http_code" = "204" ]; then
    echo "OK HTTP $http_code"
  else
    echo "FAILED HTTP $http_code"
    cat /tmp/midpoint-import-result.xml
    exit 1
  fi

  echo ""
}

apply_patch() {
  patch="$1"

  echo "Patching system configuration with $patch"

  http_code="$(curl -k -sS -o /tmp/midpoint-patch-result.xml -w "%{http_code}" \
    -u "$USER:$PASS" \
    -H "Content-Type: application/xml" \
    -X PATCH "$BASE_URL/ws/rest/systemConfigurations/00000000-0000-0000-0000-000000000001" \
    --data-binary "@/import/$patch")"

  if [ "$http_code" = "200" ] || [ "$http_code" = "204" ]; then
    echo "OK HTTP $http_code"
  else
    echo "FAILED HTTP $http_code"
    cat /tmp/midpoint-patch-result.xml
    exit 1
  fi

  echo ""
}

while IFS= read -r item || [ -n "$item" ]; do
  case "$item" in
    ""|\#*) continue ;;
  esac

  case "$item" in
    patches/*.xml)
      apply_patch "$item"
      ;;
    *)
      import_object "$item"
      ;;
  esac
done < order.txt

echo "Import completed."