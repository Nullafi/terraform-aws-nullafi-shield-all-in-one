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
  proxy_mitm_cert      = "./nullafi.crt"
  proxy_mitm_key       = "./nullafi.key"
}

output "shield_web_ui_url" {
  value = module.shield.shield_web_ui_url
}
```

This module intentionally does **not** configure an AWS provider or a backend — that's the
calling root config's responsibility (as shown above). See [examples/all-in-one](examples/all-in-one)
for a complete, runnable root config.

### Requirements

| Name | Version |
|---|---|
| terraform | >= 1.9 |
| aws | >= 4.0 |

### Prerequisites

- **An AWS account** with permissions to create VPC, EC2, EIP, IAM, and (optional) Route53 resources
- **AWS credentials** available to the provider via the standard credential chain (env vars, shared config/profile, IMDS role, etc.)
- **A Nullafi license key** (provided by Nullafi)
- **A Squid MITM certificate + private key** (provided by Nullafi)
- **A public DNS hostname** you control (e.g. `shield.yourcompany.com`) if you want HTTPS
- **(Optional) An EC2 key pair** if you want SSH access to the instance

---

## Choosing the ACME challenge type

| Type | When to use | Requirements |
|---|---|---|
| `HTTP-01` | Default web validation | Port 80 open to internet (it is, by default) |
| `TLS-ALPN-01` | Recommended for most users | Port 443 open to internet (it is, by default) |
| `DNS-01` | You want to issue certs without exposing ports 80/443, or you need wildcard certs | Your DNS provider must be supported (Route53, Cloudflare, Namecheap, etc.) and credentials configured |

**DNS-01 with Route53** (fully automated — set `route53_zone_id` and the module creates the A
record and grants the instance the IAM permissions it needs):

```hcl
host_name           = "shield.yourcompany.com"
acme_challenge_type = "DNS-01"
acme_dns01_provider = "route53"
route53_zone_id     = "Z1234ABCDEFG"
```

**DNS-01 with Cloudflare** (example):

```hcl
host_name           = "shield.yourcompany.com"
acme_challenge_type = "DNS-01"
acme_dns01_provider = "cloudflare"
acme_dns01_env = {
  CF_API_TOKEN = "your-cloudflare-api-token"
}
```

If you don't set `route53_zone_id`, you must create the DNS A record yourself, pointing at the
`public_ip` output, before HTTPS will activate.

---

## Inputs

| Variable | Required | Default | Description |
|---|---|---|---|
| `region` | yes | — | AWS region. Must match the region configured on the AWS provider passed in by the caller. |
| `nullafi_license_key` | yes | — | License key provided by Nullafi |
| `proxy_mitm_cert` | yes | — | Path to Squid MITM certificate |
| `proxy_mitm_key` | yes | — | Path to Squid MITM private key |
| `host_name` | no | `null` | Public hostname (enables HTTPS when set) |
| `acme_challenge_type` | no | `TLS-ALPN-01` | `HTTP-01`, `TLS-ALPN-01`, or `DNS-01` |
| `acme_dns01_provider` | no | `null` | DNS provider name (e.g. `route53`, `cloudflare`) |
| `acme_dns01_env` | no | `{}` | Provider-specific credential env vars (sensitive) |
| `route53_zone_id` | no | `null` | Route53 zone ID — auto-creates A record + IAM permissions |
| `dns_wait_timeout` | no | `900` | Seconds to wait for DNS before starting containers |
| `instance_type` | no | `t2.large` | EC2 instance type |
| `key_name` | no | `null` | EC2 key pair for SSH (null disables SSH) |
| `allowed_ssh_cidrs` | no | `[]` | CIDRs allowed SSH access |
| `name_prefix` | no | `nullafi` | Resource name prefix |
| `vpc_cidr` | no | `10.0.0.0/16` | VPC CIDR block |
| `shield_image` | no | `public.ecr.aws/nullafi/shield:latest` | Shield container image |
| `squid_image` | no | `public.ecr.aws/nullafi/proxy:latest` | Squid proxy container image |
| `activity_image` | no | `docker.elastic.co/elasticsearch/elasticsearch:8.7.0` | Elasticsearch container image |
| `redis_image` | no | `public.ecr.aws/docker/library/redis:6.2-alpine` | Redis container image |
| `elastic_password` | no | `elastic` | Elasticsearch password |
| `proxy_port` | no | `44509` | External port for Squid |
| `tags` | no | `{}` | Tags applied to all resources |

## Outputs

| Output | Description |
|---|---|
| `public_ip` | Elastic IP address of the instance |
| `shield_web_ui_url` | Shield Web UI URL |
| `dns_instructions` | Reminder to create a DNS A record, when `host_name` isn't backed by `route53_zone_id` |
| `squid_proxy_endpoint` | Squid proxy endpoint (`ip:port`) to configure as an HTTP proxy |
| `ssh_command` | Ready-to-use SSH command (when `key_name` is set) |
| `instance_id` | EC2 instance ID |
| `vpc_id` | VPC ID |

---

## After `terraform apply`

1. **Point DNS at the Elastic IP** — skip if you set `route53_zone_id` (the A record is already
   created). Otherwise create an A record for `host_name` → the `public_ip` output.
2. **Wait for containers to start** (5–15 minutes). On first boot the instance installs
   Docker + docker-compose, waits for DNS to resolve (up to `dns_wait_timeout` seconds), starts
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

Most config changes (e.g. `acme_challenge_type`, `allowed_ssh_cidrs`) require replacing the EC2
instance; Terraform will prompt before doing this. The Elastic IP is preserved across replacements.

### Tearing down

`terraform destroy` removes the EC2 instance, EIP, VPC, security groups, and any Route53 records
created by this module. DNS records you created manually are not managed by Terraform and must be
deleted manually.

### Troubleshooting

- **Shield Web UI won't load** — check DNS (`dig +short <host_name>` should return the EIP), SSH
  in and check `sudo docker ps` (all containers should be `Up`), and `sudo docker logs shield-web-ui | tail -50`.
- **Let's Encrypt certificate never issues** — for `HTTP-01`/`TLS-ALPN-01`, DNS must point to the
  EIP before the container boots; restart with `sudo docker compose -f /opt/nullafi/docker-compose.yml restart`.
  For `DNS-01`, verify the credentials in `acme_dns01_env`. Let's Encrypt also rate-limits to 5
  certificate requests per domain per week.

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
