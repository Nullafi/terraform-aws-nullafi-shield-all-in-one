# ------------------------------------------------------------------------------
# all-in-one – single EC2 instance running docker-compose
# ------------------------------------------------------------------------------

variable "region" {
  description = "AWS region the resources are deployed into. Must match the region configured on the AWS provider passed in by the caller."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names. Lowercase letters, digits and hyphens; must start with a letter and not end with a hyphen."
  type        = string
  default     = "nullafi"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2-40 characters of lowercase letters, digits and hyphens, start with a letter and not end with a hyphen."
  }
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t2.large"
}

variable "key_name" {
  description = "EC2 key pair name for SSH access. Leave null to disable SSH."
  type        = string
  default     = null
}

variable "host_name" {
  description = "Public hostname for Shield (NULLAFI_HTTP_CUSTOM_DOMAIN). Uses EIP if null."
  type        = string
  default     = null
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

# ------------------------------------------------------------------------------
# Container images
# ------------------------------------------------------------------------------

variable "shield_image" {
  description = "Shield container image (runs web-ui, icap, alert modes)."
  type        = string
  default     = "public.ecr.aws/nullafi/shield:latest"
}

variable "squid_image" {
  description = "Squid proxy container image."
  type        = string
  default     = "public.ecr.aws/nullafi/proxy:6.10.12"
}

variable "activity_image" {
  description = "Elasticsearch container image for Activity."
  type        = string
  default     = "docker.elastic.co/elasticsearch/elasticsearch:8.7.0"
}

variable "redis_image" {
  description = "Redis container image."
  type        = string
  default     = "public.ecr.aws/docker/library/redis:7.4.12-alpine"
}

# ------------------------------------------------------------------------------
# Secrets and certificates
# ------------------------------------------------------------------------------

# The values below are ephemeral and written to Secrets Manager as write-only
# arguments, so they never appear in plans or state. The instance reads them at boot.

variable "nullafi_license_key" {
  description = "Nullafi license key."
  type        = string
  ephemeral   = true
  sensitive   = true
}

variable "proxy_ca_cert" {
  description = "Squid MITM CA certificate, PEM content (not a file path)."
  type        = string
  ephemeral   = true

  validation {
    condition     = can(regex("-----BEGIN CERTIFICATE-----", var.proxy_ca_cert))
    error_message = "proxy_ca_cert must be PEM content starting with -----BEGIN CERTIFICATE-----, not a file path."
  }
}

variable "proxy_ca_key" {
  description = "Squid MITM CA private key, PEM content (not a file path)."
  type        = string
  ephemeral   = true
  sensitive   = true

  validation {
    condition     = can(regex("-----BEGIN [A-Z ]*PRIVATE KEY-----", var.proxy_ca_key))
    error_message = "proxy_ca_key must be PEM content containing a PRIVATE KEY block, not a file path."
  }
}

variable "acme_dns01_env" {
  description = "Environment variables for DNS-01 provider credentials (e.g. CF_API_TOKEN for Cloudflare). Not needed for route53, which uses the instance role."
  type        = map(string)
  default     = {}
  ephemeral   = true
  sensitive   = true
}

variable "secrets_version" {
  description = "Increment to push new values of nullafi_license_key, proxy_ca_cert, proxy_ca_key or acme_dns01_env. Terraform cannot detect changes to write-only values, so the new values are only stored, and the instance replaced to read them, when this number changes."
  type        = number
  default     = 1
}

variable "secrets_kms_key_arn" {
  description = "Customer-managed KMS key ARN used to encrypt the Shield secrets. Uses the AWS-managed aws/secretsmanager key when null."
  type        = string
  default     = null
}

variable "secrets_recovery_window_in_days" {
  description = "Days Secrets Manager keeps the Shield secrets after destroy before deleting them (0 deletes immediately, otherwise 7-30)."
  type        = number
  default     = 7

  validation {
    condition     = var.secrets_recovery_window_in_days == 0 || (var.secrets_recovery_window_in_days >= 7 && var.secrets_recovery_window_in_days <= 30)
    error_message = "secrets_recovery_window_in_days must be 0 or between 7 and 30."
  }
}

variable "proxy_port" {
  description = "External port for Squid proxy."
  type        = number
  default     = 44509
}

variable "acme_challenge_type" {
  description = "ACME challenge type for Let's Encrypt. Options: HTTP-01, TLS-ALPN-01, DNS-01. DNS must resolve to the EIP before HTTPS will activate for HTTP-01 and TLS-ALPN-01. DNS-01 requires the Shield container to support your DNS provider."
  type        = string
  default     = "TLS-ALPN-01"

  validation {
    condition     = contains(["HTTP-01", "TLS-ALPN-01", "DNS-01"], var.acme_challenge_type)
    error_message = "acme_challenge_type must be one of: HTTP-01, TLS-ALPN-01, DNS-01"
  }
}

variable "acme_dns01_provider" {
  description = "DNS provider name for DNS-01 challenge (e.g. cloudflare, route53, namecheap). Only used when acme_challenge_type is DNS-01."
  type        = string
  default     = null
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID. When set, Terraform auto-creates the A record and grants the EC2 instance Route53 permissions for DNS-01 challenges."
  type        = string
  default     = null
}

variable "dns_wait_timeout" {
  description = "Seconds to wait for DNS to resolve to the EIP before starting containers. Only applies when host_name is set."
  type        = number
  default     = 900
}

variable "allowed_web_cidrs" {
  description = "IPv4 CIDR blocks allowed to reach the Shield Web UI on ports 80 and 443. Restricting them blocks Let's Encrypt HTTP-01 and TLS-ALPN-01 validation, so use DNS-01."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.allowed_web_cidrs) >= 1 && length(var.allowed_web_cidrs) <= 15
    error_message = "allowed_web_cidrs must contain between 1 and 15 entries."
  }

  validation {
    condition     = alltrue([for c in var.allowed_web_cidrs : can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}/[0-9]{1,2}$", c)) && try(cidrsubnet(c, 0, 0) == c, false)])
    error_message = "allowed_web_cidrs entries must be IPv4 CIDRs in canonical form, e.g. 203.0.113.0/24."
  }
}

variable "allowed_proxy_cidrs" {
  description = "IPv4 CIDR blocks allowed to use the Squid proxy on proxy_port."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.allowed_proxy_cidrs) >= 1 && length(var.allowed_proxy_cidrs) <= 15
    error_message = "allowed_proxy_cidrs must contain between 1 and 15 entries."
  }

  validation {
    condition     = alltrue([for c in var.allowed_proxy_cidrs : can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}/[0-9]{1,2}$", c)) && try(cidrsubnet(c, 0, 0) == c, false)])
    error_message = "allowed_proxy_cidrs entries must be IPv4 CIDRs in canonical form, e.g. 203.0.113.0/24."
  }
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed SSH access. Empty list disables SSH."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}
