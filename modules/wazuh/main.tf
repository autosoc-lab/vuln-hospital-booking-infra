# --- 최신 Ubuntu 22.04 LTS AMI 조회 ---
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# --- 보안그룹: Wazuh 매니저용 ---
# INTENTIONALLY PERMISSIVE - FOR LAB USE ONLY
# API(55000)/대시보드(443)는 실습 편의를 위해 0.0.0.0/0으로 개방 (다른 EC2 SG와 동일한 패턴)
resource "aws_security_group" "wazuh" {
  # create_before_destroy 사용 시 고정 name은 신규/기존이 겹쳐 충돌하므로 name_prefix 사용
  name_prefix = "${var.project_name}-wazuh-sg-"
  description = "Wazuh manager/indexer/dashboard"
  vpc_id      = var.vpc_id

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
    description = "Wazuh Dashboard"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Wazuh API"
    from_port   = 55000
    to_port     = 55000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description     = "Agent event intake from app EC2"
    from_port       = 1514
    to_port         = 1514
    protocol        = "tcp"
    security_groups = [var.app_security_group_id]
  }

  ingress {
    description     = "Agent event intake (UDP) from app EC2"
    from_port       = 1514
    to_port         = 1514
    protocol        = "udp"
    security_groups = [var.app_security_group_id]
  }

  ingress {
    description     = "Agent enrollment from app EC2"
    from_port       = 1515
    to_port         = 1515
    protocol        = "tcp"
    security_groups = [var.app_security_group_id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-wazuh-sg"
  })
}

# --- IAM 역할: 로그 버킷(CloudTrail/VPC Flow Logs/GuardDuty) 읽기 전용 ---
resource "aws_iam_role" "wazuh_ec2" {
  name = "${var.project_name}-wazuh-ec2-role"

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

resource "aws_iam_role_policy" "wazuh_logs_read" {
  name = "${var.project_name}-wazuh-logs-read-policy"
  role = aws_iam_role.wazuh_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = var.log_bucket_arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${var.log_bucket_arn}/*"
      },
      {
        # wodle aws-s3의 vpcflow 버킷 타입이 로그 포맷 확인을 위해 호출함.
        # Describe류 EC2 API라 리소스 단위 제한이 불가능해 Resource="*" 필요.
        Effect   = "Allow"
        Action   = ["ec2:DescribeFlowLogs"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "wazuh_ssm" {
  role       = aws_iam_role.wazuh_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "wazuh_ec2" {
  name = "${var.project_name}-wazuh-ec2-profile"
  role = aws_iam_role.wazuh_ec2.name
}

# vuln_hospital_sqli_pdf_rce.xml/디코더는 EC2 user_data 16KB 한도를 넘어서 직접 임베드할 수 없다.
# 이미 CloudTrail/VPC Flow Logs가 쌓이는 로그 버킷에 별도 prefix로 얹어두고, wazuh EC2 역할이
# 이미 그 버킷 전체에 대해 가진 s3:GetObject/ListBucket 권한(wazuh_logs_read)을 그대로 재사용한다.
resource "aws_s3_object" "hospital_rules" {
  bucket      = var.log_bucket_name
  key         = "wazuh-rules/vuln_hospital_sqli_pdf_rce.xml"
  content     = file("${path.module}/files/vuln_hospital_sqli_pdf_rce.xml")
  etag        = filemd5("${path.module}/files/vuln_hospital_sqli_pdf_rce.xml")
}

resource "aws_s3_object" "hospital_decoders" {
  bucket      = var.log_bucket_name
  key         = "wazuh-rules/vuln_hospital_decoders.xml"
  content     = file("${path.module}/files/vuln_hospital_decoders.xml")
  etag        = filemd5("${path.module}/files/vuln_hospital_decoders.xml")
}

# --- Wazuh 매니저/인덱서/대시보드 (all-in-one 단일 노드) ---
resource "aws_instance" "wazuh" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.small"
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.wazuh.id]
  associate_public_ip_address = true
  key_name                    = var.key_pair_name
  iam_instance_profile        = aws_iam_instance_profile.wazuh_ec2.name
  # user_data는 최초 부팅 때만 실행되므로, 바뀔 때마다 인스턴스를 새로 만들어 cloud-init이 다시 돌게 함
  user_data_replace_on_change = true
  # S3에 룰/디코더 파일이 먼저 올라가 있어야 user_data의 aws s3 cp가 성공한다
  depends_on = [aws_s3_object.hospital_rules, aws_s3_object.hospital_decoders]

  lifecycle {
    ignore_changes = [user_data]
  }

  # 기본 8GB로는 indexer(850MB+)/manager/filebeat/dashboard 설치 중 디스크가 꽉 참
  root_block_device {
    volume_size = 50
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # t3.small(2GB RAM)에서 OpenSearch 기반 indexer가 안정적으로 뜨도록 스왑 추가
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab

    # Wazuh all-in-one 설치 (manager + indexer + dashboard)
    curl -sO https://packages.wazuh.com/${var.wazuh_version}/wazuh-install.sh
    bash wazuh-install.sh -a --ignore-check

    # wazuh-install.sh -a가 opensearch_dashboards.yml의 opensearch.username/password를
    # 주석 처리된 채로 남겨둬서(기본값 kibanaserver/kibanaserver 사용) 대시보드가 인덱서 인증에
    # 실패하고 500(Authentication Exception)을 낸다. 설치 스크립트가 생성한 실제 kibanaserver
    # 비밀번호로 채워 넣어야 한다.
    KIBANASERVER_PASSWORD=$(tar -O -xf /wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt \
      | grep -A1 "kibanaserver'" | grep indexer_password | sed -E "s/.*'(.*)'.*/\1/")
    sed -i "s/# opensearch.username: kibanaserver/opensearch.username: kibanaserver/" /etc/wazuh-dashboard/opensearch_dashboards.yml
    sed -i "s/# opensearch.password: kibanaserver/opensearch.password: '$KIBANASERVER_PASSWORD'/" /etc/wazuh-dashboard/opensearch_dashboards.yml
    systemctl restart wazuh-dashboard

    # wodle aws-s3: CloudTrail/VPC Flow Logs/GuardDuty를 S3에서 읽어오도록 설정
    cat > /tmp/wodle_block.xml <<'WODLE_XML'
    ${templatefile("${path.module}/files/wodle_aws_s3.xml.tpl", { log_bucket_name = var.log_bucket_name })}
    WODLE_XML

    sed -i '/<ossec_config>/r /tmp/wodle_block.xml' /var/ossec/etc/ossec.conf

    # SSRF -> IMDSv1 -> S3 sync(exfil) -> SSE-C 재암호화 -> lifecycle 삭제 체인 탐지용 커스텀 룰.
    # GuardDuty가 이미 잡아주는 "탈취한 임시자격증명이 EC2 밖에서 쓰임"(InstanceCredentialExfiltration)
    # 단계는 별도 룰 없이 기본 aws 룰셋으로 커버되므로 여기서는 다루지 않음.
    cat > /var/ossec/etc/rules/local_rules.xml <<'LOCAL_RULES_XML'
    ${file("${path.module}/files/local_rules.xml")}
    LOCAL_RULES_XML

    # access.log SQLi/문서다운로드/킬체인 + Flask stdout app_event/security_event(세션 하이재킹, PDF RCE) +
    # audit/네트워크 상관분석까지 포함하는 통합 룰셋. 앱 레포 detection-rules/vuln_hospital_rules.xml은
    # 이 파일로 대체되었으므로 더 이상 받아오지 않는다(룰 ID 100300번대가 겹쳐 동시 로드 시 충돌함).
    # 이 파일(+디코더)은 EC2 user_data의 16KB 한도를 넘어서 직접 임베드할 수 없어 S3에 올려두고 받아온다.
    apt-get update -y
    apt-get install -y awscli
    aws s3 cp "s3://${var.log_bucket_name}/wazuh-rules/vuln_hospital_sqli_pdf_rce.xml" /var/ossec/etc/rules/vuln_hospital_sqli_pdf_rce.xml
    aws s3 cp "s3://${var.log_bucket_name}/wazuh-rules/vuln_hospital_decoders.xml" /var/ossec/etc/decoders/vuln_hospital_decoders.xml

    systemctl restart wazuh-manager
  EOF

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-wazuh-server"
  })
}

# --- Elastic IP ---
resource "aws_eip" "wazuh" {
  instance = aws_instance.wazuh.id
  domain   = "vpc"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-wazuh-eip"
  })
}
