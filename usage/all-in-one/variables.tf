variable "region" {
  description = "AWS region to deploy into."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "nullafi"
}

variable "host_name" {
  description = "Public hostname for Shield. Uses the instance's Elastic IP if null."
  type        = string
  default     = null
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID. Optional; enables auto-DNS and DNS-01 challenges."
  type        = string
  default     = null
}

variable "acme_challenge_type" {
  description = "ACME challenge type for Let's Encrypt: HTTP-01, TLS-ALPN-01, or DNS-01."
  type        = string
  default     = "TLS-ALPN-01"
}

variable "nullafi_license_key" {
  description = "Nullafi license key. Prefer setting it with the TF_VAR_nullafi_license_key environment variable."
  type        = string
  ephemeral   = true
  sensitive   = true
}

variable "proxy_ca_cert_file" {
  description = "Path to the Squid MITM CA certificate (PEM)."
  type        = string
}

variable "proxy_ca_key_file" {
  description = "Path to the Squid MITM CA private key (PEM)."
  type        = string
}

variable "secrets_version" {
  description = "Increment after changing the license key or CA files to push the new values."
  type        = number
  default     = 1
}

variable "allowed_web_cidrs" {
  description = "IPv4 CIDR blocks allowed to reach the Shield Web UI on ports 80 and 443."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_proxy_cidrs" {
  description = "IPv4 CIDR blocks allowed to use the Squid proxy."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "key_name" {
  description = "EC2 key pair name for SSH access. Leave null to disable SSH."
  type        = string
  default     = null
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
