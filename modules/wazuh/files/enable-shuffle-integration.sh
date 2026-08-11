#!/bin/bash
# Wazuh 매니저 EC2에 이미 배포된 custom-shuffle 스크립트를 실제로 활성화한다.
#
# 순서:
#   1) vuln-hospital-booking-soar 를 배포하고 Shuffle 웹 UI에서 "Wazuh Alert Router"
#      워크플로를 만든 뒤 Webhook 트리거의 URL을 복사한다 (PLAYBOOKS.md 참고).
#   2) 이 wazuh EC2에 SSH 접속해서 실행한다:
#        sudo /opt/soar-integration/enable-shuffle-integration.sh \
#          'http://<shuffle-ip>:3001/api/v1/hooks/webhook_XXXXXXXX' [level]
#
# level(선택, 기본 6)을 넘는 알림만 Shuffle로 전달한다. 기본 6은 SSRF 1차탐지(10),
# S3 대량다운로드(12)/랜섬웨어(12)/로그변조(9~12)/포트스캔(10)/대량반출(10),
# ssh 침해 체인(6~15), GuardDuty 기본 룰(중간 심각도 이상) 대부분을 포함한다.
set -e

HOOK_URL="$1"
LEVEL="${2:-6}"

if [ -z "$HOOK_URL" ]; then
  echo "사용법: $0 <shuffle_webhook_url> [level, 기본값 6]" >&2
  exit 1
fi

OSSEC_CONF=/var/ossec/etc/ossec.conf

if grep -q "<name>custom-shuffle</name>" "$OSSEC_CONF"; then
  echo "custom-shuffle integration이 이미 등록되어 있습니다. ${OSSEC_CONF}에서 <hook_url>을 직접 수정하고 wazuh-manager를 재시작하세요." >&2
  exit 1
fi

cat > /tmp/shuffle_integration_block.xml <<XML
  <integration>
    <name>custom-shuffle</name>
    <hook_url>${HOOK_URL}</hook_url>
    <level>${LEVEL}</level>
    <alert_format>json</alert_format>
  </integration>
XML

# 주의: sed '/re/r file' 은 매칭되는 모든 줄 뒤에 삽입한다. ossec.conf에는 <ossec_config>
# 태그가 여러 개 있을 수 있어서, 그러면 integration 블록이 중복 삽입된다(= 알림 중복 전송).
# 그래서 awk로 '첫 번째 <ossec_config> 뒤에만' 한 번 삽입한다.
awk 'BEGIN{done=0} {print} /<ossec_config>/ && !done {while((getline l < "/tmp/shuffle_integration_block.xml")>0) print l; close("/tmp/shuffle_integration_block.xml"); done=1}' "$OSSEC_CONF" > "$OSSEC_CONF.tmp" && mv "$OSSEC_CONF.tmp" "$OSSEC_CONF"
rm -f /tmp/shuffle_integration_block.xml

systemctl restart wazuh-manager

echo "완료: custom-shuffle integration 등록 (level >= ${LEVEL} 알림을 ${HOOK_URL} 로 전송)"
echo "확인: tail -f /var/ossec/logs/integrations.log"
