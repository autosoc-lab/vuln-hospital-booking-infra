# --- 최신 Ubuntu 22.04 LTS AMI 조회 ---
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# --- EC2 IAM Instance Profile (SSM Session Manager 접근용) ---
resource "aws_iam_role" "ec2_ssm" {
  name = "${var.project_name}-ec2-ssm-role"

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

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${var.project_name}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name
}

# --- EC2 인스턴스 ---
resource "aws_instance" "app" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [var.ec2_security_group_id]
  associate_public_ip_address = true
  key_name                    = var.key_pair_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm.name

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y docker.io docker-compose-plugin git
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ubuntu
    # 앱 클론 및 실행
    git clone https://github.com/jhlee-codes/vuln-hospital-booking /opt/app
    cd /opt/app
    docker compose up -d
  EOF

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-app-server"
  })
}

# --- Elastic IP ---
resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-app-eip"
  })
}

# --- RDS PostgreSQL ---
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = var.common_tags
}

resource "aws_db_instance" "postgres" {
  identifier     = "${var.project_name}-db"
  engine         = "postgres"
  engine_version = "15"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = "hospital"
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_security_group_id]
  publicly_accessible    = false

  backup_retention_period = 0
  deletion_protection     = false
  skip_final_snapshot     = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-db"
  })
}
