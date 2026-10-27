# ------------------------------------------------------------------------------
# all-in-one – single EC2 instance running docker-compose
# All 6 containers on one box: shield-web-ui, shield-icap, shield-alert,
# squid, activity (Elasticsearch), redis
# ------------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

# Amazon Linux 2023 AMI
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  az        = data.aws_availability_zones.available.names[0]
  host_name = var.host_name != null ? var.host_name : aws_eip.main.public_ip

  docker_compose_version = "v5.6.1"
  docker_compose_sha256  = "47737f4236e6d3ccea7291995203f8f018058783b4c3a9469119811a0b5db8c0"
}

# ------------------------------------------------------------------------------
# Secrets Manager – license key, proxy CA and DNS-01 credentials
# ------------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "license_key" {
  name_prefix             = "${var.name_prefix}/license-key-"
  description             = "Nullafi Shield license key"
  kms_key_id              = var.secrets_kms_key_arn
  recovery_window_in_days = var.secrets_recovery_window_in_days
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "license_key" {
  secret_id                = aws_secretsmanager_secret.license_key.id
  secret_string_wo         = var.nullafi_license_key
  secret_string_wo_version = var.secrets_version
}

resource "aws_secretsmanager_secret" "proxy_ca" {
  name_prefix             = "${var.name_prefix}/proxy-ca-"
  description             = "Nullafi Shield Squid MITM CA certificate and private key"
  kms_key_id              = var.secrets_kms_key_arn
  recovery_window_in_days = var.secrets_recovery_window_in_days
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "proxy_ca" {
  secret_id                = aws_secretsmanager_secret.proxy_ca.id
  secret_string_wo         = jsonencode({ cert = var.proxy_ca_cert, key = var.proxy_ca_key })
  secret_string_wo_version = var.secrets_version
}

resource "aws_secretsmanager_secret" "acme_dns01_env" {
  name_prefix             = "${var.name_prefix}/acme-dns01-env-"
  description             = "Nullafi Shield DNS-01 provider credentials"
  kms_key_id              = var.secrets_kms_key_arn
  recovery_window_in_days = var.secrets_recovery_window_in_days
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "acme_dns01_env" {
  secret_id                = aws_secretsmanager_secret.acme_dns01_env.id
  secret_string_wo         = jsonencode(var.acme_dns01_env)
  secret_string_wo_version = var.secrets_version
}

locals {
  secret_arns = [
    aws_secretsmanager_secret.license_key.arn,
    aws_secretsmanager_secret.proxy_ca.arn,
    aws_secretsmanager_secret.acme_dns01_env.arn,
  ]
}

# ------------------------------------------------------------------------------
# VPC – simple: one public subnet, internet gateway, no NAT needed
# ------------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpc" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-igw" })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 0)
  availability_zone       = local.az
  map_public_ip_on_launch = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-public" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-public" })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ------------------------------------------------------------------------------
# Security Group – HTTP, HTTPS, Squid proxy, optional SSH
# ------------------------------------------------------------------------------

resource "aws_security_group" "instance" {
  name_prefix = "${var.name_prefix}-"
  description = "All-in-one Nullafi instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP (Shield Web UI)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_web_cidrs
  }

  ingress {
    description = "HTTPS (Shield Web UI)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_web_cidrs
  }

  ingress {
    description = "Squid proxy"
    from_port   = var.proxy_port
    to_port     = var.proxy_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_proxy_cidrs
  }

  dynamic "ingress" {
    for_each = length(var.allowed_ssh_cidrs) > 0 ? [1] : []
    content {
      description = "SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.allowed_ssh_cidrs
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-sg" })
}

# ------------------------------------------------------------------------------
# IAM Role – EC2 instance (SSM access for management, ECR pulls)
# ------------------------------------------------------------------------------

resource "aws_iam_role" "instance" {
  name = "${var.name_prefix}-ec2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy" "route53" {
  count = var.route53_zone_id != null ? 1 : 0
  name  = "route53-dns01"
  role  = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets", "route53:ListResourceRecordSets"]
        Resource = "arn:aws:route53:::hostedzone/${var.route53_zone_id}"
      },
      {
        Effect   = "Allow"
        Action   = ["route53:GetChange", "route53:ListHostedZonesByName", "route53:ListHostedZones"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "secrets" {
  name = "read-shield-secrets"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = local.secret_arns
    }]
  })
}

resource "aws_iam_role_policy" "secrets_kms" {
  count = var.secrets_kms_key_arn != null ? 1 : 0
  name  = "decrypt-shield-secrets"
  role  = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["kms:Decrypt"]
      Resource = var.secrets_kms_key_arn
      Condition = {
        StringEquals = {
          "kms:ViaService" = "secretsmanager.${var.region}.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name_prefix}-ec2"
  role = aws_iam_role.instance.name
}

# ------------------------------------------------------------------------------
# Elastic IP
# ------------------------------------------------------------------------------

resource "aws_eip" "main" {
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name_prefix}-eip" })
}

resource "aws_eip_association" "main" {
  instance_id   = aws_instance.main.id
  allocation_id = aws_eip.main.id
}

# ------------------------------------------------------------------------------
# Route53 A record (optional – auto-creates DNS when route53_zone_id is set)
# ------------------------------------------------------------------------------

resource "aws_route53_record" "main" {
  count   = var.route53_zone_id != null && var.host_name != null ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.host_name
  type    = "A"
  ttl     = 60
  records = [aws_eip.main.public_ip]
}

# ------------------------------------------------------------------------------
# EC2 Instance
# ------------------------------------------------------------------------------

resource "aws_instance" "main" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.instance.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name
  key_name               = var.key_name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
    encrypted   = true
  }

  user_data_base64 = base64encode(templatefile("${path.module}/user_data.sh.tftpl", {
    host_name                 = local.host_name
    docker_compose_version    = local.docker_compose_version
    docker_compose_sha256     = local.docker_compose_sha256
    shield_image              = var.shield_image
    squid_image               = var.squid_image
    activity_image            = var.activity_image
    redis_image               = var.redis_image
    proxy_port                = var.proxy_port
    license_key_secret_arn    = aws_secretsmanager_secret.license_key.arn
    proxy_ca_secret_arn       = aws_secretsmanager_secret.proxy_ca.arn
    acme_dns01_env_secret_arn = aws_secretsmanager_secret.acme_dns01_env.arn
    secrets_version           = var.secrets_version
    has_domain                = var.host_name != null
    acme_challenge_type       = var.acme_challenge_type
    acme_dns01_provider       = var.acme_dns01_provider
    route53_zone_id           = var.route53_zone_id
    region                    = var.region
    dns_wait_iterations       = var.dns_wait_timeout / 10
  }))

  # Image or config changes must reach the host; replacing it keeps the Elastic IP.
  user_data_replace_on_change = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-all-in-one" })

  depends_on = [
    aws_iam_role_policy.secrets,
    aws_iam_role_policy.secrets_kms,
    aws_secretsmanager_secret_version.license_key,
    aws_secretsmanager_secret_version.proxy_ca,
    aws_secretsmanager_secret_version.acme_dns01_env,
  ]

  lifecycle {
    ignore_changes = [ami]
  }
}
