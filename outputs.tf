# ------------------------------------------------------------------------------
# all-in-one – outputs
# ------------------------------------------------------------------------------

output "public_ip" {
  description = "Elastic IP address of the instance."
  value       = aws_eip.main.public_ip
}

output "shield_url" {
  description = "Shield base URL, without a path."
  value       = var.host_name != null ? "https://${var.host_name}" : "http://${aws_eip.main.public_ip}"
}

output "shield_web_ui_url" {
  description = "Shield Web UI URL."
  value       = var.host_name != null ? "https://${var.host_name}/login" : "http://${aws_eip.main.public_ip}/login"
}

output "dns_instructions" {
  description = "Create a DNS A record pointing to this IP before HTTPS will activate."
  value       = var.host_name != null ? "Create a DNS A record: ${var.host_name} → ${aws_eip.main.public_ip}" : "No hostname set — HTTPS disabled. Set host_name to enable Let's Encrypt."
}

output "squid_proxy_endpoint" {
  description = "Squid proxy endpoint (configure as HTTP proxy)."
  value       = "${aws_eip.main.public_ip}:${var.proxy_port}"
}

output "ssh_command" {
  description = "SSH command (requires key_name to be set)."
  value       = var.key_name != null ? "ssh -i ~/.ssh/${var.key_name}.pem ec2-user@${aws_eip.main.public_ip}" : "SSH disabled (no key_name set)"
}

output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.main.id
}

output "instance_arn" {
  description = "EC2 instance ARN."
  value       = aws_instance.main.arn
}

output "ami_id" {
  description = "AMI the instance was launched from."
  value       = aws_instance.main.ami
}

output "security_group_id" {
  description = "Security group attached to the instance."
  value       = aws_security_group.instance.id
}

output "eip_allocation_id" {
  description = "Allocation ID of the Elastic IP."
  value       = aws_eip.main.allocation_id
}

output "route53_record_fqdn" {
  description = "FQDN of the Route53 A record, or null when the module does not manage DNS."
  value       = one(aws_route53_record.main[*].fqdn)
}

output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.main.id
}
