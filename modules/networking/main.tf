# --- VPC ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

# --- 서브넷 ---
# Public subnet — EC2 배치용
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-public-subnet"
  })
}

# Private subnet — RDS 배치용
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block         = "10.0.2.0/24"
  availability_zone  = "ap-northeast-2c"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-private-subnet"
  })
}

# Private subnet 2 — RDS DB Subnet Group은 최소 2개 AZ가 필요하므로 추가
resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block         = "10.0.3.0/24"
  availability_zone  = "ap-northeast-2a"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-private-subnet-2"
  })
}

# --- Internet Gateway ---
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-igw"
  })
}

# --- Public Route Table ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- VPC Flow Logs ---
# CloudWatch Logs로 전송할 IAM Role — Flow Logs 서비스가 로그 스트림에 쓸 수 있어야 함
resource "aws_iam_role" "flow_log" {
  name = "${var.project_name}-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy" "flow_log" {
  name = "${var.project_name}-flow-log-policy"
  role = aws_iam_role.flow_log.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "${var.flow_log_group_arn}:*"
    }]
  })
}

resource "aws_flow_log" "vpc" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = var.flow_log_group_arn
  iam_role_arn         = aws_iam_role.flow_log.arn

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpc-flow-log"
  })
}

# --- 보안그룹: EC2용 (의도적으로 느슨하게) ---
# INTENTIONALLY PERMISSIVE - FOR LAB USE ONLY
# 0.0.0.0/0 에서 SSH(22) 포함 다중 포트 인바운드 허용 — SIEM/SOAR 탐지 실습을 위한 의도적 취약 설정
resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "INTENTIONALLY PERMISSIVE - FOR LAB USE ONLY"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH - INTENTIONALLY OPEN TO INTERNET FOR LAB USE ONLY"
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

  ingress {
    description = "App port 5000"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "App port 5001"
    from_port   = 5001
    to_port     = 5001
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
    Name = "${var.project_name}-ec2-sg"
  })
}

# --- 보안그룹: RDS용 ---
# EC2 보안그룹에서만 PostgreSQL(5432) 인바운드 허용 — 퍼블릭 노출 없음
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "RDS PostgreSQL access restricted to EC2 security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from EC2 security group"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-rds-sg"
  })
}
