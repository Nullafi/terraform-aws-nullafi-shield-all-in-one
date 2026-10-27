# ------------------------------------------------------------------------------
# Example root config consuming the nullafi-shield-all-in-one module.
# ------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }

  # Remote state backend is the consumer's responsibility. Configure your own,
  # or delete this block to fall back to local state.
  backend "s3" {
    key = "nullafi-shield-all-in-one/terraform.tfstate"
  }
}

provider "aws" {
  region = var.region
}

module "shield" {
  # Local relative source for testing this example against the module in this
  # repo. Once published, replace with:
  #   source  = "Nullafi/nullafi-shield-all-in-one/aws"
  #   version = "~> 1.0"
  source = "../../"

  region              = var.region
  name_prefix         = var.name_prefix
  host_name           = var.host_name
  route53_zone_id     = var.route53_zone_id
  acme_challenge_type = var.acme_challenge_type
  nullafi_license_key = var.nullafi_license_key
  proxy_ca_cert       = file(var.proxy_ca_cert_file)
  proxy_ca_key        = file(var.proxy_ca_key_file)
  secrets_version     = var.secrets_version
  allowed_web_cidrs   = var.allowed_web_cidrs
  allowed_proxy_cidrs = var.allowed_proxy_cidrs
  key_name            = var.key_name
  allowed_ssh_cidrs   = var.allowed_ssh_cidrs
  tags                = var.tags
}

output "shield_web_ui_url" {
  value = module.shield.shield_web_ui_url
}

output "public_ip" {
  value = module.shield.public_ip
}
