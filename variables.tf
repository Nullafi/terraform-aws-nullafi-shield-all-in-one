# ------------------------------------------------------------------------------
# all-in-one – single EC2 instance running docker-compose
# ------------------------------------------------------------------------------

variable "region" {
  description = "AWS region the resources are deployed into. Must match the region configured on the AWS provider passed in by the caller."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "nullafi"
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
  default     = "public.ecr.aws/nullafi/proxy:latest"
}

variable "activity_image" {
  description = "Elasticsearch container image for Activity."
  type        = string
  default     = "docker.elastic.co/elasticsearch/elasticsearch:8.7.0"
}

variable "redis_image" {
  description = "Redis container image."
  type        = string
  default     = "public.ecr.aws/docker/library/redis:6.2-alpine"
}

# ------------------------------------------------------------------------------
# Secrets and certificates
# ------------------------------------------------------------------------------

variable "nullafi_license_key" {
  description = "Nullafi license key string."
  type        = string
  default     = null
  sensitive   = true
}

variable "proxy_mitm_cert" {
  description = "Path to Squid MITM certificate file."
  type        = string
  default     = null
}

variable "proxy_mitm_key" {
  description = "Path to Squid MITM private key file."
  type        = string
  default     = null
  sensitive   = true
}

variable "elastic_password" {
  description = "Password for Elasticsearch."
  type        = string
  default     = "elastic"
  sensitive   = true
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

variable "acme_dns01_env" {
  description = "Environment variables for DNS-01 provider credentials. Keys and values depend on the provider (e.g. CF_API_TOKEN for Cloudflare, AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY for Route53)."
  type        = map(string)
  default     = {}
  sensitive   = true
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
