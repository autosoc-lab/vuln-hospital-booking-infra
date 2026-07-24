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
    curl -sO https://packages.wazuh.com/4.9/wazuh-install.sh
    bash wazuh-install.sh -a --ignore-check

    # wodle aws-s3: CloudTrail/VPC Flow Logs/GuardDuty를 S3에서 읽어오도록 설정
    printf '%s\n' \
      '  <wodle name="aws-s3">' \
      '    <disabled>no</disabled>' \
      '    <interval>10m</interval>' \
      '    <run_on_start>yes</run_on_start>' \
      '    <bucket type="cloudtrail">' \
      "      <name>${var.log_bucket_name}</name>" \
      '      <path>AWSLogs</path>' \
      '    </bucket>' \
      '    <bucket type="vpcflow">' \
      "      <name>${var.log_bucket_name}</name>" \
      '    </bucket>' \
      '    <bucket type="guardduty">' \
      "      <name>${var.log_bucket_name}</name>" \
      '      <path>guardduty</path>' \
      '    </bucket>' \
      '  </wodle>' > /tmp/wodle_block.xml

    sed -i '/<ossec_config>/r /tmp/wodle_block.xml' /var/ossec/etc/ossec.conf

    # SSRF -> IMDSv1 -> S3 sync(exfil) -> SSE-C 재암호화 -> lifecycle 삭제 체인 탐지용 커스텀 룰.
    # GuardDuty가 이미 잡아주는 "탈취한 임시자격증명이 EC2 밖에서 쓰임"(InstanceCredentialExfiltration)
    # 단계는 별도 룰 없이 기본 aws 룰셋으로 커버되므로 여기서는 다루지 않음.
    printf '%s\n' \
      '<group name="vuln_hospital,">' \
      '' \
      '  <!-- SSRF: 앱 요청 로그의 url 파라미터가 내부망/클라우드 메타데이터 주소를 가리킴 -->' \
      '  <rule id="100010" level="0">' \
      '    <decoded_as>json</decoded_as>' \
      '    <field name="event">app_request</field>' \
      '    <description>vuln-hospital-booking application request log</description>' \
      '  </rule>' \
      '' \
      '  <rule id="100011" level="12">' \
      '    <if_sid>100010</if_sid>' \
      '    <field name="query_string" type="pcre2">(?i)url=.*(169\.254\.169\.254|127\.0\.0\.1|localhost|10\.\d+\.\d+\.\d+|172\.(1[6-9]|2\d|3[01])\.\d+\.\d+|192\.168\.\d+\.\d+)</field>' \
      '    <description>SSRF suspected: fetched url parameter targets internal network or cloud metadata address</description>' \
      '    <mitre>' \
      '      <id>T1190</id>' \
      '    </mitre>' \
      '    <group>ssrf,</group>' \
      '  </rule>' \
      '' \
      '  <!-- S3 대량 다운로드(sync)를 통한 외부 유출 -->' \
      '  <rule id="100020" level="3">' \
      '    <decoded_as>json</decoded_as>' \
      '    <field name="aws.eventName">^GetObject$</field>' \
      '    <field name="aws.requestParameters.bucketName" type="pcre2">-documents-</field>' \
      '    <description>Document bucket object download (GetObject)</description>' \
      '    <group>s3_exfil,</group>' \
      '  </rule>' \
      '' \
      '  <rule id="100021" level="12" frequency="5" timeframe="120">' \
      '    <if_matched_sid>100020</if_matched_sid>' \
      '    <same_field>aws.userIdentity.arn</same_field>' \
      '    <description>Bulk document bucket download by same identity in short window - s3 sync exfil suspected</description>' \
      '    <mitre>' \
      '      <id>T1530</id>' \
      '    </mitre>' \
      '    <group>s3_exfil,</group>' \
      '  </rule>' \
      '' \
      '  <!-- SSE-C 커스텀 키 재암호화 (Codefinger 랜섬웨어 패턴) -->' \
      '  <rule id="100030" level="12">' \
      '    <decoded_as>json</decoded_as>' \
      '    <field name="aws.eventName">^PutObject$</field>' \
      '    <field name="aws.requestParameters.x-amz-server-side-encryption-customer-algorithm" type="pcre2">.+</field>' \
      '    <description>S3 object re-encrypted with SSE-C customer key - Codefinger ransomware pattern</description>' \
      '    <mitre>' \
      '      <id>T1486</id>' \
      '    </mitre>' \
      '    <group>s3_ransomware,</group>' \
      '  </rule>' \
      '' \
      '  <!-- 라이프사이클 정책 변경으로 자동삭제 설정 (복구 불능화) -->' \
      '  <rule id="100031" level="10">' \
      '    <decoded_as>json</decoded_as>' \
      '    <field name="aws.eventName">^PutBucketLifecycleConfiguration$</field>' \
      '    <field name="aws.requestParameters.bucketName" type="pcre2">-documents-</field>' \
      '    <description>Document bucket lifecycle policy changed - possible SSE-C ransomware auto-delete stage</description>' \
      '    <mitre>' \
      '      <id>T1485</id>' \
      '    </mitre>' \
      '    <group>s3_ransomware,</group>' \
      '  </rule>' \
      '' \
      '</group>' > /var/ossec/etc/rules/local_rules.xml

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
