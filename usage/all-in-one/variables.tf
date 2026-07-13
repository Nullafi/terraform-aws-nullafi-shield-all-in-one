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
  description = "Nullafi license key string."
  type        = string
  default     = null
  sensitive   = true
}

variable "proxy_mitm_cert" {
  description = "Path to the Squid MITM certificate file."
  type        = string
  default     = null
}

variable "proxy_mitm_key" {
  description = "Path to the Squid MITM private key file."
  type        = string
  default     = null
  sensitive   = true
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
