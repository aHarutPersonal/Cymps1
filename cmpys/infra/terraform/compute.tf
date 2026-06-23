# Latest Amazon Linux 2023 ARM64 AMI (us-east-1)
data "aws_ami" "al2023_arm" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-arm64"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

# SSH key pair
resource "aws_key_pair" "deploy" {
  key_name   = "cmpys-${var.env}"
  public_key = var.ssh_public_key
}

# Security group: SSH + HTTP + HTTPS
resource "aws_security_group" "app" {
  name        = "cmpys-${var.env}-app"
  description = "cmpys app server"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IAM instance profile: pull from ECR + read secrets
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "cmpys-${var.env}-app"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy" "app" {
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.app.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = ["${aws_s3_bucket.images.arn}/*"]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "cmpys-${var.env}-app"
  role = aws_iam_role.app.name
}

# The EC2 instance
resource "aws_instance" "app" {
  ami                    = data.aws_ami.al2023_arm.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deploy.key_name
  iam_instance_profile   = aws_iam_instance_profile.app.name
  vpc_security_group_ids = [aws_security_group.app.id]

  root_block_device {
    volume_size = 20 # GB — enough for Docker images + DB data
    volume_type = "gp3"
  }

  # Bootstrap: install Docker + Docker Compose + nginx + aws CLI
  user_data = <<-EOF
    #!/bin/bash
    set -e
    dnf update -y
    dnf install -y docker nginx aws-cli
    systemctl enable --now docker
    usermod -aG docker ec2-user

    # Docker Compose v2 plugin
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-aarch64" \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

    # App directory
    mkdir -p /opt/cmpys
    chown ec2-user:ec2-user /opt/cmpys
  EOF

  tags = {
    Name = "cmpys-${var.env}"
  }
}

# Elastic IP so the address never changes on reboot
resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"
}
