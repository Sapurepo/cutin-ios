#!/bin/zsh
# 화면 하나를 라이트/다크로 찍는다.
#   shoot.sh <이름> <AUDIT_SCREEN> [light|dark|both]
# 환경: CUTIN_SIM(기기 UDID) · AUDIT_TOKEN_FILE(seed가 쓴 me.token) · AUDIT_POST · AUDIT_USER · WAIT(초) · OUT(출력 디렉터리)
set -e
HERE=${0:A:h}
DEV=${CUTIN_SIM:-F4A70383-9134-477E-BCCA-B7824317EDE0}
APP=com.sapurepo.cutin
NAME=$1; SCREEN=$2; MODE=${3:-both}
TOKEN=$(cat ${AUDIT_TOKEN_FILE:-$HERE/seed/me.token})
OUT=${OUT:-$HERE/shots}
WAIT=${WAIT:-4}
mkdir -p $OUT
for scheme in ${(s:,:)${MODE/both/light,dark}}; do
  xcrun simctl terminate $DEV $APP 2>/dev/null || true
  xcrun simctl ui $DEV appearance $scheme
  # 값이 있는 것만 넘긴다 — 빈 문자열은 훅이 미설정으로 보지만, 넘기지 않는 편이 분명하다.
  EXTRA=()
  for v in AUDIT_POST AUDIT_USER AUDIT_TEMPLATE AUDIT_FRAME AUDIT_CAPTION AUDIT_SECTION; do
    [ -n "${(P)v}" ] && EXTRA+=("SIMCTL_CHILD_$v=${(P)v}")
  done
  env SIMCTL_CHILD_AUDIT_TOKEN=$TOKEN SIMCTL_CHILD_AUDIT_SCREEN=$SCREEN $EXTRA \
    xcrun simctl launch $DEV $APP >/dev/null
  sleep $WAIT
  xcrun simctl io $DEV screenshot $OUT/$NAME-$scheme.png >/dev/null 2>&1
  echo "$NAME-$scheme"
done
