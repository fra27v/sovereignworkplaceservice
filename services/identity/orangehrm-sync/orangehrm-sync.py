#!/usr/bin/env python3

import html
import json
import logging
import os
import sys
import uuid
import xml.etree.ElementTree as ET

import pymysql
import requests


LOG = logging.getLogger("orangehrm-sync")

EXCLUDED_USERNAMES = {
    "breakglass",
    "administrator",
}

NS_COMMON = "http://midpoint.evolveum.com/xml/ns/public/common/common-3"
NS = {"c": NS_COMMON}

HR_ORG_ASSIGNMENT_DESCRIPTION = "managed-by-orangehrm-sync:org"


with open(
    os.getenv("ORG_MAPPING_FILE", "/app/org-mapping.json"),
    "r",
    encoding="utf-8",
) as f:
    ORG_MAPPING = json.load(f)


QUERY = """
SELECT
  e.emp_number,
  e.employee_id,
  u.user_name,
  u.status AS user_status,
  u.deleted AS user_deleted,
  e.emp_firstname,
  e.emp_middle_name,
  e.emp_lastname,
  e.emp_work_email,
  e.termination_id,
  e.work_station,
  s.name AS subunit_name
FROM hs_hr_employee e
LEFT JOIN ohrm_user u
  ON u.emp_number = e.emp_number
LEFT JOIN ohrm_subunit s
  ON s.id = e.work_station
WHERE e.purged_at IS NULL
AND (
  u.user_name IS NULL
  OR u.user_name NOT IN ('breakglass', 'administrator')
)
"""


def env(name, default=None):
    value = os.getenv(name, default)
    if value is None:
        raise RuntimeError(f"Missing env: {name}")
    return value


def read_secret_file(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read().strip()


def read_secret_env(name):
    file_var = os.getenv(f"{name}_FILE")
    if file_var:
        return read_secret_file(file_var)
    return env(name)


def xml_escape(v):
    return html.escape("" if v is None else str(v), quote=True)


def deterministic_oid(employee_number):
    return str(
        uuid.uuid5(
            uuid.NAMESPACE_URL,
            f"sovereign:orangehrm:{employee_number}",
        )
    )


def enabled(row):
    if row["termination_id"] is not None:
        return False
    if row["user_deleted"] == 1:
        return False
    if row["user_status"] == 0:
        return False
    return True


def user_values(row):
    given = row["emp_firstname"] or ""
    middle = row["emp_middle_name"] or ""
    family = row["emp_lastname"] or ""
    full_name = " ".join(x for x in [given, middle, family] if x).strip()

    username = row["user_name"] or row["employee_id"]
    if not username:
        username = f"emp-{row['emp_number']}"

    return {
        "username": username,
        "given": given,
        "family": family,
        "full_name": full_name,
        "personal_number": str(row["emp_number"]),
        "email": row["emp_work_email"] or "",
        "status": "enabled" if enabled(row) else "disabled",
        "subunit": row["subunit_name"],
    }


def build_xml(row):
    oid = deterministic_oid(row["emp_number"])
    values = user_values(row)

    assignments = ""
    subunit = values["subunit"]

    if subunit in ORG_MAPPING:
        assignments = f"""
    <assignment>
        <description>{xml_escape(HR_ORG_ASSIGNMENT_DESCRIPTION)}</description>
        <targetRef oid="{xml_escape(ORG_MAPPING[subunit])}" type="OrgType"/>
    </assignment>
"""
    elif subunit:
        LOG.warning("No org mapping for subunit=%s", subunit)

    email_xml = ""
    if values["email"]:
        email_xml = f"""
    <emailAddress>{xml_escape(values["email"])}</emailAddress>
"""

    return f"""<user xmlns="{NS_COMMON}"
    oid="{xml_escape(oid)}">
    <name>{xml_escape(values["username"])}</name>
    <givenName>{xml_escape(values["given"])}</givenName>
    <familyName>{xml_escape(values["family"])}</familyName>
    <fullName>{xml_escape(values["full_name"])}</fullName>
    <personalNumber>{xml_escape(values["personal_number"])}</personalNumber>{email_xml}
    <activation>
        <administrativeStatus>{xml_escape(values["status"])}</administrativeStatus>
    </activation>{assignments}
</user>
"""


def build_simple_patch_xml(row):
    values = user_values(row)

    email_delta = ""
    if values["email"]:
        email_delta = f"""
    <itemDelta>
        <modificationType>replace</modificationType>
        <path>emailAddress</path>
        <value>{xml_escape(values["email"])}</value>
    </itemDelta>"""

    return f"""<objectModification xmlns="http://midpoint.evolveum.com/xml/ns/public/common/api-types-3">
    <itemDelta>
        <modificationType>replace</modificationType>
        <path>name</path>
        <value>{xml_escape(values["username"])}</value>
    </itemDelta>
    <itemDelta>
        <modificationType>replace</modificationType>
        <path>givenName</path>
        <value>{xml_escape(values["given"])}</value>
    </itemDelta>
    <itemDelta>
        <modificationType>replace</modificationType>
        <path>familyName</path>
        <value>{xml_escape(values["family"])}</value>
    </itemDelta>
    <itemDelta>
        <modificationType>replace</modificationType>
        <path>fullName</path>
        <value>{xml_escape(values["full_name"])}</value>
    </itemDelta>
    <itemDelta>
        <modificationType>replace</modificationType>
        <path>personalNumber</path>
        <value>{xml_escape(values["personal_number"])}</value>
    </itemDelta>{email_delta}
    <itemDelta>
        <modificationType>replace</modificationType>
        <path>activation/administrativeStatus</path>
        <value>{xml_escape(values["status"])}</value>
    </itemDelta>
</objectModification>
"""


def find_current_hr_org_assignment(existing_xml):
    root = ET.fromstring(existing_xml.encode("utf-8"))
    org_oids = set(ORG_MAPPING.values())

    for assignment in root.findall("c:assignment", NS):
        assignment_id = assignment.attrib.get("id")
        desc = assignment.find("c:description", NS)
        target_ref = assignment.find("c:targetRef", NS)

        target_oid = target_ref.attrib.get("oid") if target_ref is not None else None
        target_type = target_ref.attrib.get("type") if target_ref is not None else None

        marked = (
            desc is not None
            and (desc.text or "").strip() == HR_ORG_ASSIGNMENT_DESCRIPTION
        )

        old_hr_org = (
            target_oid in org_oids
            and target_type in ("OrgType", "c:OrgType")
        )

        if marked or old_hr_org:
            return {
                "id": assignment_id,
                "oid": target_oid,
            }

    return None


def build_delete_assignment_patch_xml(assignment_id):
    return f"""<objectModification xmlns="http://midpoint.evolveum.com/xml/ns/public/common/api-types-3">
    <itemDelta>
        <modificationType>delete</modificationType>
        <path>assignment</path>
        <value id="{xml_escape(assignment_id)}"/>
    </itemDelta>
</objectModification>
"""


def build_add_org_assignment_patch_xml(org_oid):
    return f"""<objectModification xmlns="http://midpoint.evolveum.com/xml/ns/public/common/api-types-3"
    xmlns:c="http://midpoint.evolveum.com/xml/ns/public/common/common-3">
    <itemDelta>
        <modificationType>add</modificationType>
        <path>assignment</path>
        <value>
            <c:description>{xml_escape(HR_ORG_ASSIGNMENT_DESCRIPTION)}</c:description>
            <c:targetRef oid="{xml_escape(org_oid)}" type="c:OrgType"/>
        </value>
    </itemDelta>
</objectModification>
"""


def midpoint_patch(session, base_url, username, password, oid, patch_body):
    r = session.patch(
        f"{base_url}/ws/rest/users/{oid}",
        auth=(username, password),
        headers={"Content-Type": "application/xml"},
        data=patch_body.encode("utf-8"),
        timeout=30,
        verify=os.getenv("REQUESTS_CA_BUNDLE"),
    )

    if r.status_code >= 400:
        LOG.error("midPoint PATCH error status=%s", r.status_code)
        LOG.error("midPoint PATCH error body=%s", r.text)
        LOG.error("Submitted PATCH=%s", patch_body)

    r.raise_for_status()


def midpoint_upsert(session, base_url, username, password, oid, body, row):
    get_response = session.get(
        f"{base_url}/ws/rest/users/{oid}",
        auth=(username, password),
        headers={"Accept": "application/xml"},
        timeout=30,
        verify=os.getenv("REQUESTS_CA_BUNDLE"),
    )

    exists = get_response.status_code == 200

    if not exists:
        LOG.info("User oid=%s does not exist; creating", oid)

        r = session.post(
            f"{base_url}/ws/rest/users",
            auth=(username, password),
            headers={"Content-Type": "application/xml"},
            data=body.encode("utf-8"),
            timeout=30,
            verify=os.getenv("REQUESTS_CA_BUNDLE"),
        )

        if r.status_code >= 400:
            LOG.error("midPoint POST error status=%s", r.status_code)
            LOG.error("midPoint POST error body=%s", r.text)
            LOG.error("Submitted XML=%s", body)

        r.raise_for_status()
        return

    LOG.info("User oid=%s exists; patching HR-managed fields", oid)

    midpoint_patch(
        session=session,
        base_url=base_url,
        username=username,
        password=password,
        oid=oid,
        patch_body=build_simple_patch_xml(row),
    )

    values = user_values(row)
    desired_org_oid = ORG_MAPPING.get(values["subunit"]) if values["subunit"] else None
    current_org = find_current_hr_org_assignment(get_response.text)
    current_org_oid = current_org["oid"] if current_org else None

    if current_org_oid == desired_org_oid:
        LOG.info("HR org already correct oid=%s", current_org_oid)
        return

    if current_org and current_org.get("id"):
        LOG.info(
            "Deleting previous HR org assignment id=%s oid=%s",
            current_org["id"],
            current_org["oid"],
        )

        midpoint_patch(
            session=session,
            base_url=base_url,
            username=username,
            password=password,
            oid=oid,
            patch_body=build_delete_assignment_patch_xml(current_org["id"]),
        )

    if desired_org_oid:
        LOG.info("Adding HR org assignment oid=%s", desired_org_oid)

        midpoint_patch(
            session=session,
            base_url=base_url,
            username=username,
            password=password,
            oid=oid,
            patch_body=build_add_org_assignment_patch_xml(desired_org_oid),
        )
    else:
        LOG.warning("No desired HR org for subunit=%s", values["subunit"])


def main():
    logging.basicConfig(
        level=os.getenv("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(message)s",
    )

    db_user = read_secret_env("DB_USER")
    db_password = read_secret_env("DB_PASSWORD")

    mp_user = env("MIDPOINT_USERNAME")
    mp_password = read_secret_env("MIDPOINT_PASSWORD")

    conn = pymysql.connect(
        host=env("DB_HOST"),
        port=int(env("DB_PORT")),
        user=db_user,
        password=db_password,
        database=env("DB_NAME"),
        cursorclass=pymysql.cursors.DictCursor,
    )

    session = requests.Session()
    dry_run = os.getenv("DRY_RUN", "true").lower() == "true"

    with conn.cursor() as cur:
        cur.execute(QUERY)

        for row in cur.fetchall():
            username = row["user_name"]

            if username in EXCLUDED_USERNAMES:
                LOG.info("Skipping excluded username=%s", username)
                continue

            xml = build_xml(row)
            oid = deterministic_oid(row["emp_number"])

            LOG.info(
                "employee=%s username=%s enabled=%s org=%s oid=%s",
                row["emp_number"],
                username,
                enabled(row),
                row["subunit_name"],
                oid,
            )

            if dry_run:
                LOG.info("DRY RUN ONLY")
                continue

            midpoint_upsert(
                session=session,
                base_url=env("MIDPOINT_BASE_URL"),
                username=mp_user,
                password=mp_password,
                oid=oid,
                body=xml,
                row=row,
            )

            LOG.info("Upserted oid=%s", oid)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        LOG.exception(exc)
        sys.exit(1)