# Wazuh 커스텀 탐지 룰

`vuln-hospital-booking-infra`가 배포하는 Wazuh 커스텀 룰 목록입니다. ID 범위는 `100000`~`120000`.
룰 설계 근거(오탐 방지, 인코딩 우회 대응 등)는 각 XML 파일의 인라인 주석을 참고하세요.

## SSRF → EC2 자격증명 탈취 (`modules/wazuh/files/local_rules.xml`)

| Rule ID | Level | 설명 | MITRE |
| --- | --- | --- | --- |
| 100010 | 0 | 앱 요청 로그 디코드 베이스 룰 | - |
| 100011 | 10 | SSRF 의심: `url` 파라미터가 내부망/클라우드 메타데이터 주소 대상 (진법 난독화 우회 포함) | T1190 |
| 100012 | 12 | 알려진 취약 엔드포인트(`/documents/referral-attachment-import`) 대상 SSRF 확증 | T1190 |
| 100013 | 14 | EC2 IMDS IAM 자격증명 조회 시도 (`security-credentials` 경로) | T1552.005 |
| 100014 | 15 | IMDS 자격증명 탈취 **확증** (HTTP 200 응답) | T1552.005 |

## SSE-C 랜섬웨어 (`modules/wazuh/files/local_rules.xml`)

| Rule ID | Level | 설명 | MITRE |
| --- | --- | --- | --- |
| 100030 | 13 | S3 객체 SSE-C 재암호화 (`PutObject`/`CopyObject`) — Codefinger 패턴 | T1486 |
| 100031 | 12 | 문서 버킷 lifecycle 정책 변경 (자동삭제 단계 의심) | T1485 |
| 100032 | 15 | 상관분석 **확증**: 재암호화(100030) 직후 같은 버킷에서 lifecycle 변경(100031) | T1486, T1485 |
| 100033 | 13 | SSE-C 커스텀 키로 문서 버킷 객체 조회 — 반출 정황 | T1005, T1486 |
| 100034 | 15 | 상관분석 **확증**: 재암호화 후 SSE-C 키로 반출 성공 | T1486, T1485, T1530 |

## 유출 SSH 키 → 권한상승 → 데이터 반출 (`modules/wazuh/files/vuln_hospital_ssh_compromise.xml`)

| Rule ID | Level | 설명 | MITRE |
| --- | --- | --- | --- |
| 100170 | 6 | 계정/시스템 정찰 명령 실행 (`whoami`/`id`/`sudo` 등) | T1033, T1082 |
| 100171 | 9 | 백업 스크립트/유닛 파일 열람(read) | T1007, T1083 |
| 100181 | 5 | `systemctl`/`namei` 실행 — 타이머·권한 경로 조사 보조 신호 | T1007, T1083 |
| 100172 | 15 | 백업 헬퍼(`hospital-backup-helper`) FIM 변경 | T1068 |
| 100182 | 13 | 대화형 사용자의 헬퍼 변조 (auditd 상관보강) | T1068 |
| 100173 | 15 | root 권한 표식 파일(`/tmp/wazuh-root-proof`) 생성 (FIM) | T1068 |
| 100174 | 15 | root 전용 앱 설정(`app.env`) 접근/`/tmp` 스테이징 | T1552.001 |
| 100175 | 13 | 의료 데이터가 수집 디렉터리로 스테이징됨 | T1005, T1074.001 |
| 100183 | 8 | DB 클라이언트 실행 (`psql`/`pg_dump` 등) — 보조 신호 | T1005 |
| 100176 | 12 | 수집물 압축 도구 실행 (`tar`/`gzip` 등) | T1560.001 |
| 100177 | 14 | 반출 도구 실행 (`scp`/`curl`/`nc` 등) | T1048 |
| 100178 | 12 | 파일 삭제/소거 도구 실행 (`rm`/`shred` 등) — `history -c` 등 셸 내장 명령 삭제는 auditd로 미탐 | T1070.004 |
| 100180 | 15 | 상관분석 **확증**: 대화형 헬퍼 변조(100182) 후 root 표식(100173) 생성 — 권한상승 성공 | T1068 |
| 100179 | 15 | 상관분석 **확증**: root 표식(100173) 후 root 전용 설정 접근(100174) — 자격증명 탈취 체인 | T1068, T1552.001 |

## SOAR 자동 대응 연동

Shuffle의 `soar-response-api.py`는 다음 룰 ID 발화 시 스크립트를 자동 실행합니다.

| Rule ID | 스크립트 | 승인 필요 여부 |
| --- | --- | --- |
| 100174, 100179, 100180 | `respond-ssh-compromise.sh` | 불필요 (완전자동) |
| 100031, 100032 | `respond-lifecycle-revert.sh` | 불필요 (완전자동) |
| 100014, 100034 | `respond-session-revoke.sh` | 불필요 (확증됨) |
| 100013, 100030, 100033 | `respond-session-revoke.sh` | 필요 (미확증, Discord 승인 링크 클릭 후) |
