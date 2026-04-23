# Core positioning

A *sovereign, self-hosted digital workplace platform*, operated as a managed service, with:

* collaboration
* communication
* identity
* service management
* automation
* secure multi-tenant hosting

It is *not* a mass-market Microsoft 365 clone. It is a *controlled enterprise platform* for customers that value:

* sovereignty
* auditability
* controlled customization
* predictable operations

---

# 1. Functional stack

## Identity and access

* *midPoint* → identity lifecycle and provisioning brain
* *Keycloak* → authentication, SSO, groups, roles, token issuance

### Identity flow

* *HR* is the source of truth
* *midPoint* applies joiner / mover / leaver logic
* *Keycloak* is the central identity hub for applications
* Applications consume identity from Keycloak whenever possible

### Principle

* Apps should integrate with *Keycloak*, not each separately with midPoint, except where direct provisioning is truly needed.

---

## Collaboration and document workplace

* *Nextcloud* → file storage, sharing, permissions, versioning
* *Euro-Office Document Server* → online office editing and co-authoring
* *Matrix + Element* → chat, rooms, secure communication

This is the core “MS365 replacement layer”.

---

## Email / calendar / tasks

* *Postfix* → SMTP
* *Dovecot* → IMAP
* *SOGo* or equivalent → webmail, calendar, contacts
* *CalDAV / CardDAV* → sync
* *OpenProject* or equivalent → tasks/projects where needed

---

## ITSM

* *iTop* → incident/request/problem/change/CMDB/service catalog as needed

### Important operating rule

* *No plugins*
* Customers may configure iTop functionally
* You control runtime, upgrades, and platform stability

---

## Workflow and automation

* *n8n* → integration glue, notifications, side workflows
* *Camunda* → optional broader business-process orchestration

### Important rule

* Not the core identity engine
* Identity lifecycle stays in *midPoint*
* Automation tools are supporting tools, not the source of truth

---

# 2. Security and secrets stack

## Public TLS

* *Let’s Encrypt*
* DNS managed through *OVH*
* Certificates exposed at the global edge

## Internal TLS

* *Vault PKI*
* Internal traffic encrypted between:

  * global reverse proxy
  * customer ingress
  * internal services

## Secrets

Preferred model:

* *Global/operator Vault* for platform bootstrap and control-plane secrets
* *Per-customer Vault* for customer secrets and portability

This avoids sharing sensitive customer runtime secrets in one central Vault.

---

# 3. Reverse proxy and traffic model

## Global edge

One shared internet-facing reverse proxy layer, for example:

* Traefik or Nginx

Responsibilities:

* public TLS
* public entry
* routing by hostname
* forwarding to customer environments
* rate limiting / basic protection

## Per-customer ingress

One reverse proxy / ingress per customer environment.

Responsibilities:

* tenant-local routing
* internal TLS to services
* separation of customer environments

## Traffic flow

Client
→ public HTTPS at global edge
→ internal HTTPS to customer ingress
→ internal HTTPS to customer services

So there is *no plaintext hop*.

---

# 4. DNS and naming model

## Public DNS

* Managed at *OVH*
* No self-hosted public DNS initially

## Example public names

* auth.customer1.yourplatform.com
* files.customer1.yourplatform.com
* chat.customer1.yourplatform.com
* itsm.customer1.yourplatform.com

## Internal names

Used for internal service-to-service trust, for example:

* customer1-ingress.internal.yourplatform
* itop.customer1.internal.yourplatform

---

# 5. Global vs customer split

## Global control plane

Contains only platform-wide operator functions:

* global reverse proxy
* public DNS management
* public certificate automation
* global PKI root / trust authority
* operator/bootstrap secrets
* provisioning / IaC engine
* tenant inventory / source of truth
* platform observability
* backup orchestration
* operator admin identity

## Per-customer environment

Contains customer-specific runtime:

* customer ingress
* customer Vault
* Keycloak-facing tenant config
* Nextcloud
* Euro-Office
* Matrix
* iTop
* email/calendar stack
* customer data
* customer runtime secrets

## Your own company

Your staff environment should be modeled as a normal *customer-like tenant*:

* your own IAM for staff usage
* your own collaboration apps
* your own iTop
* your own data

But platform automation and operator functions stay global.

---

# 6. Deployment model

## Principles

* Docker first
* IaC from the beginning
* Kubernetes later for industrialization
* immutable deployments
* standard settings everywhere

## Early stage

Can be run on:

* one machine
* one public IP
* router forwarding 80/443 to the host
* Docker networking internally

## Industrialized target

* shared global edge
* per-customer environments
* standardized deployment templates
* optional dedicated resources per customer

---

# 7. Operating model

## Customization policy

* Customers can configure application behavior
* Customers cannot install plugins
* Customers cannot modify runtime or code

### Allowed

* groups, roles, workflows, categories, fields, data, business config

### Not allowed

* plugins
* arbitrary code
* runtime changes
* platform-level modifications

This keeps updates predictable and maintenance low.

---

# 8. Maintenance model

Once standardized and automated, maintenance is mostly:

* release validation
* patch rollout
* cert renewals
* secret rotation
* restore tests
* capacity review
* security hygiene
* incident handling

The main effort driver is not certificates. It is *customer divergence*.

With a strict standard stack and no plugins, the platform remains operationally manageable.

---

# 9. Strategic product definition

This stack is best positioned as:

> *A sovereign managed digital workplace platform*

Not:

* “cheap Microsoft 365”
* “mass-market SaaS”

Best-fit customers:

* public sector
* regulated sectors
* critical infrastructure
* sovereignty-driven organizations
* IP-sensitive organizations

Poor fit:

* very small SMEs buying on price only
* startups wanting maximum speed and AI polish
* customers demanding unlimited customization

---

# 10. Final architecture in one line

*HR → midPoint → Keycloak → apps*, with
*Nextcloud + Euro-Office + Matrix + email/calendar + iTop*, protected by
*global edge TLS + Vault-based internal PKI*, deployed through
*IaC + Docker/Kubernetes*, with
*global control plane + per-customer runtime isolation*.
---

## 🔐 Sicurezza

- TLS ovunque (anche interno)
- Certificati generati dinamicamente
- Nessuna password hardcoded nei container
- Vault Agent per injection dei segreti

---

## 👤 Identity

- Keycloak come Identity Provider
- Modello:
  - utenti
  - gruppi
  - ruoli (RBAC)
- Admin model:
  - `breakglass-admin`
  - gruppo `admins`

## 🧠 Architettura target

```text
Browser
   ↓
Traefik (TLS)
   ↓
OIDC (Keycloak)
   ↓
Servizi (Nextcloud, iTop, ...)


📌 Note
Questo lab privilegia comprensione e architettura rispetto alla semplicità
Alcuni compromessi sono accettati (es. dev security)
Il modello finale sarà portato su Kubernetes

🚀 Visione finale
Una piattaforma:
Zero Trust
Identity-driven
Automatizzata
Portabile su cloud o on-prem