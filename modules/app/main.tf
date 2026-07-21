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

# EC2가 문서 저장용 S3 버킷을 읽고 쓸 수 있도록 부여하는 최소 권한
resource "aws_iam_role_policy" "documents_s3" {
  name = "${var.project_name}-ec2-documents-s3-policy"
  role = aws_iam_role.ec2_ssm.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.documents.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.documents.arn}/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${var.project_name}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name
}

# --- 문서 저장용 S3 버킷 (환자 문서/생성 PDF) ---
resource "aws_s3_bucket" "documents" {
  bucket = "${var.project_name}-documents-${var.account_id}"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-documents"
  })
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket = aws_s3_bucket.documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# INTENTIONALLY WEAK - FOR LAB USE ONLY
# SSE-C(Codefinger) 랜섬웨어 실습용 IAM 사용자 — GitHub 등에 액세스 키가
# 유출된 상황을 가정. documents 버킷에 대한 최소 권한만 부여.
resource "aws_iam_user" "leaked_s3_key" {
  name = "${var.project_name}-leaked-s3-key"
  tags = var.common_tags
}

resource "aws_iam_user_policy" "leaked_s3_key" {
  name = "${var.project_name}-leaked-s3-key-policy"
  user = aws_iam_user.leaked_s3_key.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.documents.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.documents.arn}/*"
      }
    ]
  })
}

resource "aws_iam_access_key" "leaked_s3_key" {
  user = aws_iam_user.leaked_s3_key.name
}

# --- EC2 SSH 키페어 (로컬에서 생성한 공개키를 AWS에 등록) ---
resource "aws_key_pair" "app" {
  key_name   = var.key_pair_name
  public_key = file("${path.root}/ssh/vuln-hospital-lab.pub")

  tags = var.common_tags
}

# --- EC2 인스턴스 ---
resource "aws_instance" "app" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [var.ec2_security_group_id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.app.key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm.name

  # INTENTIONALLY WEAK - FOR LAB USE ONLY
  # IMDSv1(토큰 없는 요청)을 허용해서 SSRF를 통한 IAM 자격증명 탈취 시나리오(SSRF.md)를 재현 가능하게 함
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "optional"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e
    apt-get update -y
    apt-get install -y git postgresql-client ca-certificates curl
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ubuntu

    # 앱 클론 (SQLi 실습 코드가 병합된 브랜치)
    git clone -b ${var.app_git_ref} https://github.com/autosoc-lab/vuln-hospital-booking /opt/app
    cd /opt/app

    # RDS를 바라보도록 DATABASE_URL 교체 — 로컬 db 컨테이너는 띄우지 않음
    sed -i "s|postgresql+psycopg://hospital:hospital@db:5432/hospital|postgresql+psycopg://${var.db_username}:${var.db_password}@${aws_db_instance.postgres.address}:5432/hospital|" docker-compose.yml

    # 문서 저장소를 S3로 지정
    sed -i '/DATABASE_URL:/a\      STORAGE_BACKEND: "s3"' docker-compose.yml
    sed -i '/DATABASE_URL:/a\      DOCUMENT_STORAGE_BUCKET: "${aws_s3_bucket.documents.bucket}"' docker-compose.yml
    sed -i '/DATABASE_URL:/a\      AWS_REGION: "ap-northeast-2"' docker-compose.yml

    docker compose up -d --no-deps web

    # RDS 연결이 가능해질 때까지 대기 (최대 5분)
    for i in $(seq 1 30); do
      if PGPASSWORD='${var.db_password}' psql -h ${aws_db_instance.postgres.address} -U ${var.db_username} -d hospital -c 'select 1' >/dev/null 2>&1; then
        break
      fi
      sleep 10
    done

    # 스키마 생성 및 실습 데이터 시드
    docker compose exec -T web flask --app run init-db
    docker compose exec -T web flask --app run seed-db

    # 시드된 문서 원본 파일을 S3로 마이그레이션 (SSE-C 실습 대상)
    docker compose exec -T web flask --app run migrate-storage-to-s3
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
