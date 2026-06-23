output "server_ip" {
  value       = aws_eip.app.public_ip
  description = "Server public IP (use for SSH and as API_BASE_URL)"
}

output "ecr_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "image_cdn" {
  value = aws_cloudfront_distribution.images.domain_name
}

output "ssh_command" {
  value = "ssh ec2-user@${aws_eip.app.public_ip}"
}
