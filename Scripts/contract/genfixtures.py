#!/usr/bin/env python3
"""openapi.json에서 응답 페이로드를 생성한다. 손으로 쓰지 않는 것이 요점 —
손으로 쓰면 Swift 타입이 아니라 내 가정을 시험하게 된다."""
import json, sys

SPEC = json.load(open(sys.argv[1]))
S = SPEC['components']['schemas']
UUID = "3f2c1b4a-5d6e-4f70-8a9b-0c1d2e3f4a5b"

def resolve(s):
    if '$ref' in s: return resolve(S[s['$ref'].split('/')[-1]])
    if 'allOf' in s and len(s['allOf']) == 1: return resolve(s['allOf'][0])
    return s

def sample(s, mode, depth=0):
    """mode='full' 모든 키 채움 / mode='sparse' 필수만 + nullable은 null"""
    s = resolve(s)
    if s.get('nullable') and mode == 'sparse':
        return None
    if 'enum' in s:
        vals = [v for v in s['enum'] if v is not None]
        # full은 첫 값, sparse는 마지막 값 — 열거형 파싱이 한 값에만 맞는 것을 잡는다
        return vals[0] if mode == 'full' else vals[-1]
    t = s.get('type')
    if t == 'object':
        props = s.get('properties') or {}
        if not props:
            # z.record(string, T) → additionalProperties. 값 타입을 지키지 않으면
            # 실패가 계약 문제로 오해된다(실제로 한 번 그랬다).
            extra = s.get('additionalProperties')
            if isinstance(extra, dict):
                return {"X-Upload-Token": sample(extra, mode, depth + 1)} if mode == 'full' else {}
            return {"anything": 1} if mode == 'full' else {}
        req = set(s.get('required', []))
        out = {}
        for k, v in props.items():
            if mode == 'sparse' and k not in req:
                continue
            out[k] = sample(v, mode, depth + 1)
        return out
    if t == 'array':
        item = s.get('items', {'type': 'string'})
        return [sample(item, mode, depth + 1)] if mode == 'full' else []
    if t in ('integer',):
        return 0 if mode == 'sparse' else 3
    if t == 'number':
        return 0.0 if mode == 'sparse' else 0.615385
    if t == 'boolean':
        return mode == 'full'
    if t == 'string':
        if s.get('format') == 'uuid':
            return UUID
        if s.get('format') == 'binary':
            return "binary"
        return "s" if mode == 'sparse' else "2026-08-13T04:05:06.000Z"
    return None

# 스펙 스키마 → Swift 타입
PAIRS = [
    ('LoginResponseDto_Output', 'LoginResponse'),
    ('TokensResponseDto_Output', 'TokensResponse'),
    ('UserProfileDto_Output', 'UserProfile'),
    ('NicknameAvailabilityResponseDto_Output', 'NicknameAvailability'),
    ('TemplatesResponseDto_Output', 'TemplatesResponse'),
    ('UploadTargetDto_Output', 'UploadTarget'),
    ('MediaDto_Output', 'Media'),
    ('PostDto_Output', 'Post'),
    ('PostPageDto_Output', 'PostPage'),
    ('ShareLinkDto_Output', 'ShareLinkResponse'),
    ('ErrorResponseDto', 'APIErrorEnvelope'),
]

cases = []
for spec_name, swift in PAIRS:
    if spec_name not in S:
        print(f"!! 스펙에 없음: {spec_name}", file=sys.stderr); sys.exit(1)
    for mode in ('full', 'sparse'):
        payload = json.dumps(sample(S[spec_name], mode), ensure_ascii=False)
        cases.append((f"{swift}/{mode}", swift, payload))

# PostPage의 items가 비면 Post 디코드를 시험하지 않는다 — 항목이 있는 페이지를 하나 더 만든다
page_with_items = {
    "items": [sample(S['PostDto_Output'], 'sparse'), sample(S['PostDto_Output'], 'full')],
    "nextCursor": "eyJ4IjoxfQ==",
}
cases.append(("PostPage/items", "PostPage", json.dumps(page_with_items, ensure_ascii=False)))

lines = []
for name, swift, payload in cases:
    esc = payload.replace('\\', '\\\\').replace('"', '\\"')
    lines.append(f'    Case(name: "{name}", json: "{esc}") {{ try decode({swift}.self, $0) }},')

print("// 생성 파일 — genfixtures.py가 openapi.json에서 만든다. 손으로 고치지 말 것.")
print("#if DEBUG")
print("import Foundation")
print("enum ContractFixtures {")
print("    struct Case: Sendable { let name: String; let json: String; let decode: @Sendable (Data) throws -> Void }")
print("    static let all: [Case] = [")
print("\n".join(lines))
print("    ]")
print("}")
print("#endif")
