#!/usr/bin/env python3
"""하니스가 찍은 `ENC <스펙DTO> <json>` 줄을 openapi.json 스키마와 대조한다.

Swift가 만든 요청 바디가 서버가 받아들이는 모양인지 보는 것이 목적이다. 확인 항목:
  - 필수 키 누락
  - 스펙에 없는 키(서버 Zod는 strict가 아닐 수 있지만, 없는 키는 의도 착오다)
  - 타입 불일치 · 열거형 위반
  - nullable 아닌 필드에 null
"""
import json, re, sys

spec = json.load(open(sys.argv[1]))
S = spec['components']['schemas']
lines = open(sys.argv[2], encoding='utf-8', errors='replace').read().splitlines()

def resolve(s):
    if '$ref' in s: return resolve(S[s['$ref'].split('/')[-1]])
    if 'allOf' in s and len(s['allOf']) == 1: return resolve(s['allOf'][0])
    return s

problems = []

def check(value, schema, path):
    schema = resolve(schema)
    if value is None:
        if not schema.get('nullable'):
            problems.append(f"{path}: null인데 스키마는 nullable이 아니다")
        return
    if 'enum' in schema:
        allowed = [v for v in schema['enum'] if v is not None]
        if value not in allowed:
            problems.append(f"{path}: 열거형 위반 {value!r} not in {allowed}")
        return
    t = schema.get('type')
    if t == 'object':
        props = schema.get('properties') or {}
        if props:
            for k in schema.get('required', []):
                if k not in value:
                    problems.append(f"{path}.{k}: 필수 키 누락")
            for k, v in value.items():
                if k not in props:
                    problems.append(f"{path}.{k}: 스펙에 없는 키")
                else:
                    check(v, props[k], f"{path}.{k}")
        else:
            extra = schema.get('additionalProperties')
            if isinstance(extra, dict):
                for k, v in value.items():
                    check(v, extra, f"{path}.{k}")
        return
    if t == 'array':
        if not isinstance(value, list):
            problems.append(f"{path}: 배열이 아니다 ({type(value).__name__})"); return
        for i, item in enumerate(value):
            check(item, schema.get('items', {}), f"{path}[{i}]")
        return
    expect = {'string': str, 'integer': int, 'number': (int, float), 'boolean': bool}.get(t)
    if expect and not isinstance(value, expect):
        problems.append(f"{path}: {t} 자리에 {type(value).__name__}")
    if t == 'string' and schema.get('pattern'):
        if not re.match(schema['pattern'], value):
            problems.append(f"{path}: pattern 불일치 {value!r} vs {schema['pattern']}")

count = 0
for line in lines:
    if not line.startswith('ENC '):
        continue
    _, name, payload = line.split(' ', 2)
    if name not in S:
        problems.append(f"{name}: 스펙에 없는 DTO"); continue
    count += 1
    check(json.loads(payload), S[name], name)

print(f"대조한 요청 바디 {count}건")
if problems:
    print(f"문제 {len(problems)}건:")
    for p in problems: print("  -", p)
    sys.exit(1)
print("전부 스펙과 일치")
