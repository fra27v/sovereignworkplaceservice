# Lab Sovrano

Lab Sovrano is a sovereign, self-hosted digital workplace lab. The objective is to build a managed platform that can provide identity, collaboration, secure access, secrets management, and tenant isolation with a strong preference for open, controllable components.

Documentation-as-code is available in [docs/README.md](docs/README.md).

The platform is not intended to be a low-cost Microsoft 365 clone. It is a controlled enterprise environment for organizations that value sovereignty, auditability, predictable operations, and limited, governed customization.

During development, some products changed from the original target stack. This README reflects the current implementation state and separates implemented components from future developments.

---

# 1. Current Implemented Stack

## Identity and Access

Implemented components:

* OrangeHRM as the HR source
* midPoint as the identity lifecycle and provisioning engine
* Keycloak as the identity provider, SSO hub, group authority, role authority, and token issuer

Identity flow:

```text
OrangeHRM -> midPoint -> Keycloak -> applications
```

Principles:

* HR data is the source of truth for people and organizational structure.
* midPoint applies joiner, mover, and leaver logic.
* Keycloak is the central identity hub consumed by applications.
* Applications should integrate with Keycloak whenever possible.
* Direct provisioning from midPoint to an application is used only where it is technically necessary.

Governed identity model:

* Entitlements are modeled from the HR organization structure, so access follows business membership instead of ad hoc application-local administration.
* Standard user access is provisioned from authoritative lifecycle data and reusable roles.
* Temporary or sensitive access, especially administrative access, is handled through midPoint request and approval workflows.
* Administrative access uses separate privileged accounts, not the normal daily user account.
* Privileged accounts follow a fixed naming convention such as `adm_<username>`.
* Privileged accounts are retained for audit continuity when temporary rights expire, but they are disabled when the approval, entitlement, or primary user status no longer allows use.
* When the primary identity is deleted, related application accounts, including any privileged account, are removed through the normal provisioning lifecycle.

This model is part of the intended platform differentiation. The same identity governance pattern should be reusable across tenants, customers, and production environments rather than being treated as a one-off lab configuration.

## Collaboration and Documents

Implemented components:

* Nextcloud for file storage, sharing, permissions, and versioning
* Collabora Online for browser-based document editing

Original office-product assumptions were changed during implementation. The current office integration is based on Collabora, not Euro-Office Document Server.

## Password Management

Implemented component:

* Vaultwarden for shared password management

Vaultwarden is part of the current workplace stack and is integrated as a managed application in the lab.

## Security and Secrets

Implemented components:

* HashiCorp Vault for secrets and internal PKI
* Vault Agent templates for service secrets
* internal TLS certificates issued per service
* Traefik as the reverse proxy and routing layer

Security principles:

* TLS is used for both external and internal service traffic.
* Runtime secrets are injected from Vault-managed material.
* Secrets should not be hardcoded into containers or application configuration.
* Internal service certificates are generated and renewed through the platform tooling.

---

# 2. Components Not Implemented Yet

The following components were part of the broader platform vision but are not currently implemented in this lab.

## ITSM

Future development:

* incident management
* request management
* problem management
* change management
* CMDB
* service catalog

Candidate product:

* iTop, or another ITSM tool selected after validation

Operating rule:

* no customer-installed plugins
* functional configuration is allowed
* platform runtime, upgrades, and stability remain under operator control

## Chat and Video Conferencing

Future development:

* secure chat
* rooms and channels
* audio/video conferencing
* identity-aware access through Keycloak

Possible candidates:

* Matrix and Element for chat
* Jitsi or another conferencing stack for video meetings

These services are not part of the current implementation.

## Wiki and Knowledge Base

Future development:

* internal wiki
* customer documentation space
* operational knowledge base
* integration with Keycloak for authentication and authorization

The exact wiki product has not been selected yet.

## Email, Calendar, and Tasks

Future development:

* SMTP and IMAP mail service
* webmail
* calendar and contacts
* CalDAV and CardDAV synchronization
* task/project management where required

Possible candidates:

* Postfix
* Dovecot
* SOGo or equivalent
* OpenProject or equivalent

---

# 3. Traffic and DNS Model

## Reverse Proxy

Implemented direction:

* Traefik acts as the platform reverse proxy.
* Services are exposed through internal hostnames such as `auth.internal`, `files.internal`, `office.internal`, `identity.internal`, `hr.internal`, and `passwords.internal`.
* TLS is terminated and routed through the platform edge.

Target traffic flow:

```text
Browser
  -> HTTPS at platform edge
  -> HTTPS to service route
  -> application
```

The target model avoids plaintext service hops.

## Public DNS

Target direction:

* public DNS managed externally
* public TLS certificates at the global edge
* internal names used for service-to-service trust

Example future public names:

* `auth.customer.example.com`
* `files.customer.example.com`
* `office.customer.example.com`
* `passwords.customer.example.com`

Future names for services not yet implemented:

* `meet.customer.example.com`
* `wiki.customer.example.com`
* `itsm.customer.example.com`

---

# 4. Global and Customer Split

## Global Control Plane

Target platform-wide responsibilities:

* global reverse proxy
* public DNS management
* public certificate automation
* global PKI root and trust authority
* operator/bootstrap secrets
* tenant inventory and source of truth
* platform observability
* backup orchestration
* operator admin identity

## Per-Customer Environment

Target customer-specific runtime:

* customer ingress
* customer Vault or customer-scoped secrets
* Keycloak-facing tenant configuration
* Nextcloud
* Collabora
* Vaultwarden
* customer data
* customer runtime secrets

Customer identity governance should be standardized:

* HR-derived organizations and entitlements are customer-specific data, but the governance pattern is platform-standard.
* Administrative roles should be temporary, approved, auditable, and separated from daily user identities.
* The privileged-account lifecycle should remain consistent across lab, tenant, and production environments: create on first approved need, disable when not entitled, re-enable on reapproval, and delete only with the primary identity lifecycle.

Future customer services may include:

* ITSM
* chat
* video conferencing
* wiki
* email/calendar/tasks

The operator environment should remain separate from customer runtime environments. The operator company's own tools should be modeled as a normal tenant where possible.

---

# 5. Deployment Model

Current lab direction:

* Docker-first deployment
* service-level `docker-compose.yml` files
* infrastructure and service configuration kept as code in this repository
* Vault-managed secrets
* internal TLS per service
* Traefik routing

Infrastructure as Code principles:

* all platform components should be reproducible from versioned configuration
* service definitions, routing, PKI automation, identity bootstrap objects, and operational scripts belong in the repository
* manual changes are acceptable during lab exploration only when they are later captured as code
* customer environments should be created from standard templates, not hand-built snowflakes

Target industrialized direction:

* infrastructure as code from the beginning
* standardized deployment templates
* immutable or repeatable deployments
* k3s for future orchestration and deployment
* optional dedicated resources per customer

---

# 6. Operating Model

Customization policy:

* customers can configure application behavior
* customers cannot install plugins
* customers cannot modify runtime or code
* platform updates must remain predictable

Allowed examples:

* groups
* roles
* workflows
* categories
* fields
* business configuration
* customer-owned data

Not allowed:

* plugins
* arbitrary code
* unmanaged runtime changes
* platform-level modifications

The main maintenance risk is customer divergence. A strict standard stack and a no-plugin policy keep the platform operationally manageable.

---

# 7. Maintenance Model

Expected recurring operations:

* release validation
* patch rollout
* certificate renewal
* secret rotation
* restore tests
* capacity review
* security hygiene
* incident handling

Certificates and secrets should be automated as much as possible. Long-term platform cost is driven more by divergence and exceptions than by the base services themselves.

---

# 8. Strategic Product Definition

Best positioning:

> A sovereign managed digital workplace platform.

Not:

* cheap Microsoft 365
* mass-market SaaS
* unlimited customization platform

Best-fit customers:

* public sector
* regulated sectors
* critical infrastructure
* sovereignty-driven organizations
* IP-sensitive organizations

Poor fit:

* very small SMEs buying only on price
* startups that need maximum speed and consumer-style polish
* customers demanding unrestricted customization

---

# 9. Architecture Summary

Current implemented lab:

```text
OrangeHRM -> midPoint -> Keycloak -> Nextcloud / Collabora / Vaultwarden
```

Protected by:

```text
Traefik + Vault-managed secrets + internal TLS + Docker Compose + repository-managed IaC
```

Future developments:

End user services:
* ITSM
* chat
* video conferencing
* wiki
* email, calendar, and tasks
* broader process automation if justified

Operations:
* backup
* monitoring
* orchestration and deployment via k3s
