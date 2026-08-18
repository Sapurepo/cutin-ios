#!/usr/bin/env python3
"""효과음 넷을 합성해 `Cutin/Resources/Sounds/*.caf`로 쓴다.

의존성 없음(표준 라이브러리 + macOS `afconvert`). 샘플을 다운로드하지 않고 만드는 이유는
라이선스 문구가 필요 없고, 이 파일을 고쳐 다시 돌리면 같은 소리가 나오기 때문이다.

  tap      부품을 눌렀다 — 아주 짧은 톡(설정 톱니 · 알림 종 · 배치 고르기).
  tick     카운트다운 3·2·1 — tap보다 조금 길고 낮은 톡. 셔터에는 안 얹는다(시스템 셔터음이 이미 난다).
  pop      반응을 남길 때 — 아래로 미끄러지는 짧은 팝.
  success  발행 완료 — 두 음(G5→D6)이 잠깐 겹치며 사라진다. Haptics.success와 함께.

`AVAudioPlayer`(`SoundEffects`)로 재생한다. 16-bit 모노 44.1kHz. 피크는 -4~-5 dBFS — 미디어
볼륨을 따르니 옆면 버튼으로 줄일 수 있고, 아이폰 스피커는 500Hz 아래를 거의 못 내므로 전부
600Hz 위에서 논다(처음 -9 dBFS · 350Hz까지 내려가던 pop은 스피커에서 거의 안 들렸다).

    python3 Scripts/sounds/make.py            # Cutin/Resources/Sounds/ 에 쓴다
"""

import math
import os
import struct
import subprocess
import sys
import tempfile
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "Cutin", "Resources", "Sounds")


def env(t, attack, tau):
    """attack초 선형으로 켜지고, 그 뒤 시정수 tau로 지수 감쇠."""
    if t < attack:
        return t / attack
    return math.exp(-(t - attack) / tau)


def tap():
    dur = 0.022
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / RATE
        s = math.sin(2 * math.pi * 2200 * t) + 0.3 * math.sin(2 * math.pi * 4400 * t)
        out.append(s * env(t, 0.001, 0.006))
    return out


def tick():
    dur = 0.045
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / RATE
        s = math.sin(2 * math.pi * 1600 * t) + 0.35 * math.sin(2 * math.pi * 3200 * t)
        out.append(s * env(t, 0.002, 0.012))
    return out


def pop():
    dur = 0.08
    n = int(RATE * dur)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        f = 1100 * (650 / 1100) ** (t / dur)   # 1100→650Hz 지수 글라이드
        phase += 2 * math.pi * f / RATE
        out.append(math.sin(phase) * env(t, 0.003, 0.025))
    return out


def success():
    dur = 0.5
    n = int(RATE * dur)
    notes = [(784.0, 0.0), (1175.0, 0.11)]   # G5, 그 다음 D6 — 완전5도 위
    out = []
    for i in range(n):
        t = i / RATE
        s = 0.0
        for f, start in notes:
            u = t - start
            if u < 0:
                continue
            tone = (math.sin(2 * math.pi * f * u)
                    + 0.25 * math.sin(2 * math.pi * 2 * f * u)
                    + 0.08 * math.sin(2 * math.pi * 3 * f * u))
            s += tone * env(u, 0.005, 0.12)
        out.append(s)
    return out


def normalize(samples, peak):
    m = max(abs(s) for s in samples) or 1.0
    return [s / m * peak for s in samples]


def write(name, samples, peak):
    samples = normalize(samples, peak)
    tmp = os.path.join(tempfile.gettempdir(), f"cutin-{name}.wav")
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))
    caf = os.path.join(OUT, f"{name}.caf")
    subprocess.run(["afconvert", "-f", "caff", "-d", "LEI16", tmp, caf], check=True)
    os.remove(tmp)
    print(f"{caf}  {len(samples) / RATE * 1000:.0f}ms  peak {20 * math.log10(peak):.0f} dBFS")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    write("tap", tap(), 0.55)
    write("tick", tick(), 0.6)
    write("pop", pop(), 0.6)
    write("success", success(), 0.6)
