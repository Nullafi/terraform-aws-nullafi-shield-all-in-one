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

  has_mitm_cert = var.proxy_mitm_cert != null && var.proxy_mitm_key != null
  mitm_cert     = local.has_mitm_cert ? file(var.proxy_mitm_cert) : ""
  mitm_key      = local.has_mitm_cert ? file(nonsensitive(var.proxy_mitm_key)) : ""

  has_license_key = var.nullafi_license_key != null
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
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS (Shield Web UI)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Squid proxy"
    from_port   = var.proxy_port
    to_port     = var.proxy_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
    host_name           = local.host_name
    shield_image        = var.shield_image
    squid_image         = var.squid_image
    activity_image      = var.activity_image
    redis_image         = var.redis_image
    elastic_password    = var.elastic_password
    proxy_port          = var.proxy_port
    license_key         = var.nullafi_license_key != null ? nonsensitive(var.nullafi_license_key) : ""
    has_license_key     = local.has_license_key
    has_mitm_cert       = local.has_mitm_cert
    mitm_cert           = local.mitm_cert
    mitm_key            = local.has_mitm_cert ? nonsensitive(local.mitm_key) : ""
    has_domain          = var.host_name != null
    acme_challenge_type = var.acme_challenge_type
    acme_dns01_provider = var.acme_dns01_provider
    acme_dns01_env      = var.acme_dns01_env
    route53_zone_id     = var.route53_zone_id
    region              = var.region
    dns_wait_iterations = var.dns_wait_timeout / 10
  }))

  tags = merge(var.tags, { Name = "${var.name_prefix}-all-in-one" })

  lifecycle {
    ignore_changes = [ami, user_data_base64]
  }
}
