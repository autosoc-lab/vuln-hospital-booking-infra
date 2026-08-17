#!/var/ossec/framework/python/bin/python3
# Wazuh -> Shuffle 커스텀 integration.
#
# ossec.conf 설정 (enable-shuffle-integration.sh 가 자동으로 추가해줌):
#   <integration>
#     <name>custom-shuffle</name>
#     <hook_url>http://<shuffle-ip>:3001/api/v1/hooks/webhook_XXXXXXXX</hook_url>
#     <level>6</level>
#     <alert_format>json</alert_format>
#   </integration>
#
# Wazuh integrator 데몬이 이 스크립트를 다음 인자로 호출한다:
#   argv[1] = 발화한 알림 하나가 담긴 임시 JSON 파일 경로
#   argv[2] = api_key (사용 안 함, 빈 문자열)
#   argv[3] = hook_url (위 설정의 <hook_url>)
#   argv[4] = "debug" (선택, ossec.conf 최상단 <integration_debug> 설정 시)
#
# 알림 JSON을 그대로(가공 없이) Shuffle 웹훅으로 POST한다. 필드 기반 분기(레벨/그룹별로
# 다른 조치를 취하는 것)는 Wazuh 쪽이 아니라 Shuffle 워크플로 안에서 처리한다 — 그래야
# Wazuh EC2를 재기동하지 않고도 Shuffle UI에서 대응 로직을 바꿀 수 있다.

import json
import os
import sys
from datetime import datetime

import requests

LOG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "logs", "integrations.log")


def log(msg):
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        with open(LOG_FILE, "a") as f:
            f.write("{} custom-shuffle: {}\n".format(now, msg))
    except OSError:
        pass


def main(args):
    debug_enabled = len(args) > 4 and args[4] == "debug"

    alert_file_location = args[1]

    # Wazuh 버전에 따라 integrator가 넘기는 인자 순서/개수가 달라진다(예: options 블록이
    # 끼면 hook_url이 argv[3]가 아니라 뒤로 밀리고, argv[3]에 '10' 같은 숫자 옵션이 들어와
    # 'Invalid URL 10' 에러가 났다). 위치로 고정하지 말고 http(s):// 로 시작하는 인자를
    # 찾아 hook_url로 쓴다.
    hook_url = next((a for a in args[1:] if a.startswith("http")), None)
    if not hook_url:
        log("hook_url을 인자에서 찾지 못함 args={}".format(args[1:]))
        return

    with open(alert_file_location) as f:
        alert_json = json.loads(f.read())

    if debug_enabled:
        log("alert_file={} hook_url={}".format(alert_file_location, hook_url))

    headers = {"content-type": "application/json"}
    response = requests.post(hook_url, headers=headers, data=json.dumps(alert_json), timeout=10, verify=False)

    if debug_enabled or response.status_code >= 300:
        log("POST {} -> {} {}".format(hook_url, response.status_code, response.text[:500]))


if __name__ == "__main__":
    try:
        main(sys.argv)
    except Exception as e:
        log("error: {}".format(e))
        sys.exit(1)
