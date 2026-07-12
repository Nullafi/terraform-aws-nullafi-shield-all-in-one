# ------------------------------------------------------------------------------
# all-in-one – outputs
# ------------------------------------------------------------------------------

output "public_ip" {
  description = "Elastic IP address of the instance."
  value       = aws_eip.main.public_ip
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

output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.main.id
}
