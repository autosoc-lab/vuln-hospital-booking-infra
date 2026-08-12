# --- 최신 Ubuntu 22.04 LTS AMI 조회 ---
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# --- 보안그룹: C2/수집 서버용 ---
# INTENTIONALLY PERMISSIVE - FOR LAB USE ONLY (다른 EC2 SG와 동일한 패턴)
resource "aws_security_group" "c2" {
  name_prefix = "${var.project_name}-c2-sg-"
  description = "vuln-hospital-booking-c2 artifact collector"
  vpc_id      = data.aws_subnet.public.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  ingress {
    description = "SSH - INTENTIONALLY OPEN TO INTERNET FOR LAB USE ONLY"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "nginx to collector app (pingback/upload receiver)"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-c2-sg"
  })
}

data "aws_subnet" "public" {
  id = var.public_subnet_id
}

# --- EC2 IAM Instance Profile (SSM Session Manager 접근용) ---
resource "aws_iam_role" "c2_ec2" {
  name = "${var.project_name}-c2-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "c2_ssm" {
  role       = aws_iam_role.c2_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "c2_ec2" {
  name = "${var.project_name}-c2-ec2-profile"
  role = aws_iam_role.c2_ec2.name
}

# --- EC2 인스턴스: 공격자의 수집(C2) 서버 ---
resource "aws_instance" "c2" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.c2.id]
  associate_public_ip_address = true
  key_name                    = var.key_pair_name
  iam_instance_profile        = aws_iam_instance_profile.c2_ec2.name
  user_data_replace_on_change = true

  user_data = <<-EOF
    #!/bin/bash
    set -e
    apt-get update -y
    apt-get install -y git ca-certificates curl
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ubuntu

    git clone -b ${var.c2_git_ref} https://github.com/autosoc-lab/vuln-hospital-booking-c2 /opt/c2
    cd /opt/c2

    cat > .env <<'ENV_FILE'
    C2_LAB_TOKEN=${var.c2_lab_token}
    ENV_FILE

    docker compose up -d --build
  EOF

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-c2-server"
  })
}

# --- Elastic IP ---
resource "aws_eip" "c2" {
  instance = aws_instance.c2.id
  domain   = "vpc"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-c2-eip"
  })
}
