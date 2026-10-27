# terraform-aws-nullafi-shield-all-in-one

[![Static analysis](https://github.com/Nullafi/terraform-aws-nullafi-shield-all-in-one/actions/workflows/static-analysis.yml/badge.svg)](https://github.com/Nullafi/terraform-aws-nullafi-shield-all-in-one/actions/workflows/static-analysis.yml)

Terraform module that deploys the entire **Nullafi Shield** stack on a single EC2 instance
running docker-compose. Best for evaluation, small deployments, and environments where
simplicity matters more than redundancy.

**What you get:**
- One EC2 instance with a static public IP (Elastic IP), its own VPC/subnet/IGW, and security group
- Shield Web UI, ICAP, Alert, Squid proxy, Activity (Elasticsearch), Redis — all running via docker-compose
- Optional HTTPS via Let's Encrypt (three validation methods supported)
- Auto-reboot with docker-compose `restart: unless-stopped`

**Static analysis:** Terraform (fmt, validate) · TFLint · tfsec · Checkov — [View runs](https://github.com/Nullafi/terraform-aws-nullafi-shield-all-in-one/actions/workflows/static-analysis.yml). Results appear in the Security tab and on PRs.

---

## Usage

```hcl
provider "aws" {
  region = "us-east-1"
}

module "shield" {
  source  = "Nullafi/nullafi-shield-all-in-one/aws"
  version = "~> 1.0"

  region              = "us-east-1"
  host_name           = "shield.yourcompany.com"
  acme_challenge_type = "TLS-ALPN-01"

  nullafi_license_key = var.nullafi_license_key
  proxy_ca_cert       = file("./nullafi.crt")
  proxy_ca_key        = file("./nullafi.key")
}

variable "nullafi_license_key" {
  type      = string
  ephemeral = true
  sensitive = true
}

output "shield_web_ui_url" {
  value = module.shield.shield_web_ui_url
}
```

This module intentionally does **not** configure an AWS provider or a backend — that's the
calling root config's responsibility (as shown above). See [usage/all-in-one](usage/all-in-one)
for a complete, runnable root config.

### Requirements

| Name | Version |
|---|---|
| terraform | >= 1.11 |
| aws | >= 6.0 |

### Prerequisites

- **An AWS account** with permissions to create VPC, EC2, EIP, IAM, Secrets Manager, and (optional) Route53 resources
- **AWS credentials** available to the provider via the standard credential chain (env vars, shared config/profile, IMDS role, etc.)
- **A Nullafi license key** (provided by Nullafi)
- **A Squid MITM certificate + private key** (provided by Nullafi), as PEM content
- **A public DNS hostname** you control (e.g. `shield.yourcompany.com`) if you want HTTPS
- **(Optional) An EC2 key pair** if you want SSH access to the instance

### Secrets

You pass the license key, the proxy CA certificate and private key, and any DNS-01 credentials as
variables. The module stores them in **AWS Secrets Manager**, and the instance reads them at boot
with its own IAM role, which can read only these secrets.

- These variables are **ephemeral**, and the module writes them to Secrets Manager as **write-only**
  values. They never appear in `terraform plan` output, saved plan files, Terraform state or EC2
  user data. Declare the root variables you pass in as `ephemeral = true` too, and supply them again
  when applying a saved plan.
- Pass PEM **content**, not file paths. In a root config you can use `file("./nullafi.crt")`.
- Terraform cannot detect changes to write-only values. **To push new values, increment
  `secrets_version`.** That updates the secrets and replaces the instance so it reads them.
- Secrets are named `<name_prefix>/license-key-…`, `<name_prefix>/proxy-ca-…` and
  `<name_prefix>/acme-dns01-env-…`. They are encrypted with `secrets_kms_key_arn` when set, otherwise
  with the AWS-managed `aws/secretsmanager` key.
- The Elasticsearch password is generated randomly on the instance at boot.

---

## Choosing the ACME challenge type

| Type | When to use | Requirements |
|---|---|---|
| `HTTP-01` | Default web validation | Port 80 open to internet (it is, by default) |
| `TLS-ALPN-01` | Recommended for most users | Port 443 open to internet (it is, by default) |
| `DNS-01` | You want to issue certs without exposing ports 80/443, or you need wildcard certs | Your DNS provider must be supported (Route53, Cloudflare, Namecheap, etc.) and credentials configured. **Required when `allowed_web_cidrs` is restricted.** |

**DNS-01 with Route53** (fully automated — set `route53_zone_id` and the module creates the A
record and grants the instance the IAM permissions it needs):

```hcl
host_name           = "shield.yourcompany.com"
acme_challenge_type = "DNS-01"
acme_dns01_provider = "route53"
route53_zone_id     = "Z1234ABCDEFG"
```

**DNS-01 with Cloudflare** (example). The credentials are stored in Secrets Manager like the other secrets:

```hcl
host_name           = "shield.yourcompany.com"
acme_challenge_type = "DNS-01"
acme_dns01_provider = "cloudflare"
acme_dns01_env = {
  CF_API_TOKEN = var.cloudflare_api_token
}
```

If you don't set `route53_zone_id`, you must create the DNS A record yourself, pointing at the
`public_ip` output, before HTTPS will activate.

---

## Inputs

| Variable | Required | Default | Description |
|---|---|---|---|
| `region` | yes | — | AWS region. Must match the region configured on the AWS provider passed in by the caller. |
| `nullafi_license_key` | yes | — | License key provided by Nullafi (ephemeral, sensitive) |
| `proxy_ca_cert` | yes | — | Squid MITM CA certificate, PEM content (ephemeral) |
| `proxy_ca_key` | yes | — | Squid MITM CA private key, PEM content (ephemeral, sensitive) |
| `secrets_version` | no | `1` | Increment to push new secret values; replaces the instance |
| `secrets_kms_key_arn` | no | `null` | Customer-managed KMS key for the secrets (AWS-managed key when null) |
| `secrets_recovery_window_in_days` | no | `7` | Days deleted secrets stay recoverable (0, or 7–30) |
| `allowed_web_cidrs` | no | `["0.0.0.0/0"]` | IPv4 CIDRs allowed on ports 80/443 (1–15) |
| `allowed_proxy_cidrs` | no | `["0.0.0.0/0"]` | IPv4 CIDRs allowed on the Squid port (1–15) |
| `host_name` | no | `null` | Public hostname (enables HTTPS when set) |
| `acme_challenge_type` | no | `TLS-ALPN-01` | `HTTP-01`, `TLS-ALPN-01`, or `DNS-01` |
| `acme_dns01_provider` | no | `null` | DNS provider name (e.g. `route53`, `cloudflare`) |
| `acme_dns01_env` | no | `{}` | DNS-01 provider credential env vars (ephemeral, sensitive) |
| `route53_zone_id` | no | `null` | Route53 zone ID — auto-creates A record + IAM permissions |
| `dns_wait_timeout` | no | `900` | Seconds to wait for DNS before starting containers |
| `instance_type` | no | `t2.large` | EC2 instance type |
| `key_name` | no | `null` | EC2 key pair for SSH (null disables SSH) |
| `allowed_ssh_cidrs` | no | `[]` | CIDRs allowed SSH access |
| `name_prefix` | no | `nullafi` | Resource name prefix: 2–40 lowercase letters, digits and hyphens, starting with a letter |
| `vpc_cidr` | no | `10.0.0.0/16` | VPC CIDR block |
| `shield_image` | no | `public.ecr.aws/nullafi/shield:latest` | Shield container image |
| `squid_image` | no | `public.ecr.aws/nullafi/proxy:6.10.12` | Squid proxy container image |
| `activity_image` | no | `docker.elastic.co/elasticsearch/elasticsearch:8.7.0` | Elasticsearch container image |
| `redis_image` | no | `public.ecr.aws/docker/library/redis:7.4.12-alpine` | Redis container image |
| `proxy_port` | no | `44509` | External port for Squid |
| `tags` | no | `{}` | Tags applied to all resources |

## Outputs

| Output | Description |
|---|---|
| `public_ip` | Elastic IP address of the instance |
| `shield_url` | Shield base URL, without a path |
| `shield_web_ui_url` | Shield Web UI URL |
| `dns_instructions` | Reminder to create a DNS A record, when `host_name` isn't backed by `route53_zone_id` |
| `squid_proxy_endpoint` | Squid proxy endpoint (`ip:port`) to configure as an HTTP proxy |
| `ssh_command` | Ready-to-use SSH command (when `key_name` is set) |
| `instance_id` | EC2 instance ID |
| `instance_arn` | EC2 instance ARN |
| `ami_id` | AMI the instance was launched from |
| `security_group_id` | Security group attached to the instance |
| `eip_allocation_id` | Allocation ID of the Elastic IP |
| `route53_record_fqdn` | FQDN of the Route53 A record, or null when the module does not manage DNS |
| `vpc_id` | VPC ID |

---

## After `terraform apply`

1. **Point DNS at the Elastic IP** — skip if you set `route53_zone_id` (the A record is already
   created). Otherwise create an A record for `host_name` → the `public_ip` output.
2. **Wait for containers to start** (5–15 minutes). On first boot the instance installs
   Docker and a pinned docker-compose release (verified against its SHA-256; boot stops if it
   doesn't match), waits for DNS to resolve (up to `dns_wait_timeout` seconds), starts
   the Nullafi stack, and — if `host_name` is set — requests a Let's Encrypt certificate.
   Watch progress via SSH (requires `key_name`):
   ```bash
   ssh -i ~/.ssh/<key_name>.pem ec2-user@<public_ip>
   sudo tail -f /var/log/cloud-init-output.log
   sudo docker logs -f shield-web-ui
   ```
3. **Log in to the Shield Web UI** at the `shield_web_ui_url` output, using the credentials
   provided by Nullafi. A certificate warning means Let's Encrypt hasn't issued yet — wait and reload.
4. **Configure the Squid proxy** (optional) at the `squid_proxy_endpoint` output. Install the
   MITM certificate as a trusted root CA on any client routing traffic through Squid.

### Updating

Any change to the instance's boot configuration replaces the EC2 instance. That includes container
images (e.g. a new Shield digest), `host_name`, `acme_challenge_type` and `secrets_version`. Terraform
shows the replacement in the plan. The Elastic IP and the Route53 record are preserved. Data held on
the instance (Activity/Elasticsearch, Redis, issued certificates) is **not** preserved; a replacement
starts fresh and requests a new Let's Encrypt certificate.

Security group changes (`allowed_web_cidrs`, `allowed_proxy_cidrs`, `allowed_ssh_cidrs`) apply in place.

> **Upgrading from 1.x:** requires Terraform >= 1.11 and AWS provider >= 6.0. `proxy_mitm_cert` and
> `proxy_mitm_key` (file paths) are replaced by `proxy_ca_cert` and `proxy_ca_key` (PEM content).
> `elastic_password` is removed. `nullafi_license_key`, `proxy_ca_*` and `acme_dns01_env` are now
> ephemeral, so root variables passing them must be declared `ephemeral = true`. The first apply
> creates the secrets and replaces the instance.

### Tearing down

`terraform destroy` removes the EC2 instance, EIP, VPC, security groups, any Route53 records
created by this module, and the Secrets Manager secrets (recoverable for
`secrets_recovery_window_in_days`). DNS records you created manually are not managed by Terraform and must be
deleted manually.

### Troubleshooting

- **Shield Web UI won't load** — check DNS (`dig +short <host_name>` should return the EIP), SSH
  in and check `sudo docker ps` (all containers should be `Up`), and `sudo docker logs shield-web-ui | tail -50`.
- **Let's Encrypt certificate never issues** — for `HTTP-01`/`TLS-ALPN-01`, DNS must point to the
  EIP before the container boots; restart with `sudo docker compose -f /opt/nullafi/docker-compose.yml restart`.
  For `DNS-01`, verify the credentials passed in `acme_dns01_env`. Let's Encrypt also rate-limits to 5
  certificate requests per domain per week.
- **Boot stops at "Secret not readable yet"** — the instance role can't read a secret. With
  `secrets_kms_key_arn` set, check that the key policy lets the account's IAM principals use the key.
- **New license key or CA not picked up** — increment `secrets_version`; changing the values alone
  does nothing.

---

## Contributing

**Default branch:** `main`. Use `develop` for day-to-day work; merge to `main` via pull request.

### Release strategy (release branch)

We use a **release branch** so `main` stays protected (changes only via PR) and the changelog still gets updated.

| Branch      | Purpose |
|------------|---------|
| `develop`      | Day-to-day work. Merge to `main` via PR when a feature set is ready. |
| `main`     | Production. Protected; only updated via pull request. |
| `release/*`| Cut a release. Create from `main`, push to trigger the release workflow, then open a PR into `main`. |

**Flow:**

1. Merge work from `develop` → `main` via PR as usual.
2. When ready to **release**: create a release branch from `main` (e.g. `release/1.2.0` or `release/next`), push it.
3. The **Release** workflow runs on that branch: it updates [CHANGELOG.md](CHANGELOG.md) and version, commits to the release branch, creates the git tag and GitHub Release.
4. Open a **PR from the release branch into `main`**, then merge. `main` gets the changelog and version bump via the PR—no direct push to `main` by the bot.

See [docs/RELEASE.md](docs/RELEASE.md) for step-by-step instructions.

### Releasing (release workflow)

Versions and [CHANGELOG.md](CHANGELOG.md) are produced by [semantic-release](https://github.com/semantic-release/semantic-release) when the **Release** workflow runs on a `release/*` branch. It uses [Conventional Commits](https://www.conventionalcommits.org/) to decide the next version. The version tags this produces (e.g. `v1.2.0`) are what the Terraform Registry uses to publish module versions.

#### Commit message format

Use these prefixes so the next version and changelog are correct:

| Prefix     | Version bump | Use for |
|-----------|---------------|--------|
| `feat:`   | **Minor** (1.0.0 → 1.1.0) | New feature |
| `fix:`    | **Patch** (1.0.0 → 1.0.1) | Bug fix |
| `docs:`   | — | Documentation only |
| `chore:`  | — | Maintenance (e.g. deps, config) |
| `perf:`   | **Patch** | Performance improvement |
| `refactor:` | — | Code change, no feature/fix |
| `BREAKING CHANGE:` in body or `feat!:` / `fix!:` | **Major** (1.0.0 → 2.0.0) | Incompatible change |

**Examples:**
- `feat: add S3 bucket for backups`
- `fix: correct IAM policy for Lambda`
- `docs: update README`
- `feat!: drop support for Terraform 0.14` (major bump)
