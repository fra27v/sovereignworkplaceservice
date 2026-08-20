# Bootstrap family-infra-01 before Git

This runbook covers only the manual steps required before the repository is
available on the Ubuntu Server VM `family-infra-01`.

Expected operating system:

```text
Ubuntu Server 26.04 LTS
architecture: x86_64 / amd64
```

Other Ubuntu releases do not technically block bootstrap, but they are a
divergence from the optimized baseline target and must be reviewed before the
host is considered production-ready. Non-Ubuntu distributions are unsupported
for this baseline.

Do not configure static IP addresses, Netplan tied to a physical NIC, VLANs, or
Synology VMM network details in this phase. The VM can remain temporarily
attached to the current VMM virtual switch.

## 1. First Access

Use the Synology VMM console or the initial SSH access configured during the
Ubuntu installation.

Inspect the current host and network state:

```bash
cat /etc/os-release
uname -m
hostnamectl
ip addr
ip route
resolvectl status
timedatectl
```

Confirm that the OS is Ubuntu 26.04 and the architecture is `x86_64` or `amd64`
before proceeding.

The expected hostname is:

```text
family-infra-01
```

If it is not already set, set it explicitly:

```bash
sudo hostnamectl set-hostname family-infra-01
hostnamectl
```

This identifies the VM consistently without binding the baseline to any
specific interface name, MAC address, gateway, Synology physical NIC, or static
address.

## 2. Install Only the Git Bootstrap Prerequisites

Install only the tools needed to reach GitHub and clone the repository:

```bash
sudo apt update
sudo apt install -y git openssh-client ca-certificates
```

The full package baseline is applied later by the repository script.

## 3. Install an Administrative SSH Public Key

Before password authentication is disabled, the admin user must have at least
one working public key in `authorized_keys`.

On the server, create the SSH directory and file with the expected permissions:

```bash
mkdir -p ~/.ssh
chmod 0700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 0600 ~/.ssh/authorized_keys
```

Append the administrator public key to `authorized_keys`. Do not paste or copy
private keys to the server through this file.

Example for creting the keys on Windows PowerShell
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\family-infra-01_vps -C "family-infra-01 ubuntu"

Linux/macOS example from the administrator workstation:

```bash
cat ~/.ssh/id_ed25519.pub | ssh <admin-user>@<server-address> \
  'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys'
```

Windows PowerShell example from the administrator workstation:

```powershell
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub | ssh <admin-user>@<server-address> "umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys"
```

Open a second terminal and verify key login before closing the current session:

```bash
ssh <admin-user>@<server-address>
```

Keep the original session open until the second session works.

## 4. Create a Dedicated Read-Only GitHub Deploy Key

The server must use a repository-specific read-only deploy key, separate from
the administrative SSH key.

Generate it on `family-infra-01`:

```bash
ssh-keygen -t ed25519 \
  -f ~/.ssh/sovereignworkplaceservice_ro \
  -C "family-infra-01 sovereignworkplaceservice read-only deploy key"
chmod 0600 ~/.ssh/sovereignworkplaceservice_ro
chmod 0644 ~/.ssh/sovereignworkplaceservice_ro.pub
```

Show only the public key and add it manually in GitHub:

```bash
cat ~/.ssh/sovereignworkplaceservice_ro.pub
```

GitHub path:

```text
Repository -> Settings -> Deploy keys -> Add deploy key
```

Use this repository:

```text
fra27v/sovereignworkplaceservice
```

Set:

```text
Allow write access = disabled
```

Do not use a personal SSH key for the repository and do not enable write access.

## 5. Trust the GitHub SSH Host Key

Verify GitHub's current SSH host key fingerprints against GitHub's official
documentation before accepting them. Do not use `StrictHostKeyChecking=no`.

Collect the host keys into a temporary file first:

```bash
tmp_known_hosts="$(mktemp)"
ssh-keyscan github.com > "${tmp_known_hosts}"
ssh-keygen -lf "${tmp_known_hosts}"
```

Compare the displayed fingerprints with GitHub's official SSH host key
fingerprints before continuing.

Only after the fingerprints match, append the verified keys to `known_hosts`:

```bash
touch ~/.ssh/known_hosts
ssh-keygen -R github.com -f ~/.ssh/known_hosts 2>/dev/null || true
cat "${tmp_known_hosts}" >> ~/.ssh/known_hosts
rm -f "${tmp_known_hosts}"
chmod 0644 ~/.ssh/known_hosts
ssh-keygen -F github.com
```

If the fingerprints do not match, do not append the keys and remove the
temporary file:

```bash
rm -f "${tmp_known_hosts}"
```

## 6. Add a Dedicated SSH Alias for the Repository

Add this block to `~/.ssh/config`:

```sshconfig
Host github-sovereignworkplace
    HostName github.com
    User git
    IdentityFile ~/.ssh/sovereignworkplaceservice_ro
    IdentitiesOnly yes
```

Then set the permissions:

```bash
chmod 0600 ~/.ssh/config
```

This prevents the deploy key from being offered implicitly to other GitHub
repositories.

## 7. Clone the Repository

Clone into the standard directory:

```bash
mkdir -p ~/src
cd ~/src
git clone git@github-sovereignworkplace:fra27v/sovereignworkplaceservice.git
cd ~/src/sovereignworkplaceservice
git remote -v
git status
git branch --show-current
```

Do not run `git push` from this server.

After this point, repeatable non-secret configuration must come from the
repository.
