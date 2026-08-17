#!/bin/zsh
# 전 화면을 찍고 콘택트 시트 둘(라이트/다크)을 만든다. 사전 조건은 README.
#   shoot-all.sh <내 포스트 id> <타인 포스트 id> <타인 user id> [출력 디렉터리]
set -e
HERE=${0:A:h}
DEV=${CUTIN_SIM:-F4A70383-9134-477E-BCCA-B7824317EDE0}
APP=com.sapurepo.cutin
MINE=$1; OTHER=$2; USER=$3
export OUT=${4:-$HERE/shots}
export WAIT=${WAIT:-4}
S=$HERE/shoot.sh
xcrun simctl status_bar $DEV override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3

# 로그인 — 키체인을 비우고 토큰 없이 켠다
xcrun simctl terminate $DEV $APP 2>/dev/null || true
xcrun simctl keychain $DEV reset
for scheme in light dark; do
  xcrun simctl ui $DEV appearance $scheme; xcrun simctl launch $DEV $APP >/dev/null; sleep 3
  xcrun simctl io $DEV screenshot $OUT/login-$scheme.png >/dev/null 2>&1; xcrun simctl terminate $DEV $APP; echo login-$scheme
done

# 첫 실행 팁 — tips.seen을 지우고 켠다(토큰은 shoot.sh가 심는다)
xcrun simctl spawn $DEV defaults delete $APP tips.seen 2>/dev/null || true
$S tips-first feed light
xcrun simctl spawn $DEV defaults write $APP tips.seen -bool true

$S feed feed
$S notifications notifications
AUDIT_POST=$MINE $S postDetail-mine postDetail
AUDIT_POST=$OTHER $S postDetail-other postDetail
$S friends friends
AUDIT_USER=$USER $S userProfile userProfile
$S profile profile
$S archive archive
$S notificationSettings notificationSettings
$S tips tips
$S captureSetup captureSetup
$S camera camera

# 편집 3단계 — 컷 파일을 컨테이너에 넣고 훅이 draft를 만든다
C=$(xcrun simctl get_app_container $DEV $APP data)
mkdir -p "$C/Documents/Drafts"
for i in 0 1 2 3; do cp $HERE/seed/out/m1/cut$i.jpg "$C/Documents/Drafts/cut-$i.jpg"; done
WAIT=6 $S template template
WAIT=6 $S filter filter
WAIT=6 $S finish finish

# 콘택트 시트
cd $OUT
ORDER=(login onboarding tips-first feed notifications postDetail-mine postDetail-other friends userProfile profile archive notificationSettings tips captureSetup camera template filter finish)
L=(); D=()
for n in $ORDER; do [ -f $n-light.png ] && L+=("$n=$n-light.png"); [ -f $n-dark.png ] && D+=("$n=$n-dark.png"); done
swift $HERE/montage.swift $OUT/contact-light.png 260 5 $L
swift $HERE/montage.swift $OUT/contact-dark.png 260 5 $D
sips -s format jpeg -s formatOptions 82 $OUT/contact-light.png --out $OUT/contact-light.jpg >/dev/null
sips -s format jpeg -s formatOptions 82 $OUT/contact-dark.png --out $OUT/contact-dark.jpg >/dev/null
echo "→ $OUT/contact-{light,dark}.jpg"
