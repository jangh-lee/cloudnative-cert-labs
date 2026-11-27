# cloudnative-cert-labs

| 항목 | 내용 |
|---|---|
| 내용 | 클라우드 네이티브 자격 대비 강의 실습 스크립트·YAML·가이드(`guide.html`) |
| 구조 | `<강의>/<강의>_<NN>/` 회차별 폴더, 현재 `KCA/`, 추후 `CBA/` 등 추가 |
| 릴리스 | `v2026.11.27`, 자산 `<강의>_<NN>_lab.zip` |
| 실행 | 각 폴더의 `guide.html` 순서 |
| 라이선스 | 스크립트·YAML(`*.sh`, `*.yaml`): MIT (`LICENSE`) / 가이드 문서(`guide.html`, `README.md` 등 문서): CC BY-NC-ND 4.0 (`LICENSE-docs`) |
| 고지 | 본 자료는 Linux Foundation·CNCF와 무관한 독립 교육자료입니다. Kubernetes·Kyverno는 각 소유자의 상표입니다. |

## 받기

```bash
curl -fsSLO https://github.com/jangh-lee/cloudnative-cert-labs/releases/download/v2026.11.27/KCA_<NN>_lab.zip
unzip KCA_<NN>_lab.zip
```

```bash
git clone --depth 1 https://github.com/jangh-lee/cloudnative-cert-labs.git
```

## KCA

| 회차 | 주제 | 폴더 | 릴리스 자산 |
|---|---|---|---|
| 01 | kind 실습 환경 | `KCA/KCA_01/` | `KCA_01_lab.zip` |
| 02 | Policy · Rule · YAML | `KCA/KCA_02/` | `KCA_02_lab.zip` |
| 03 | Admission Enforce · Audit | `KCA/KCA_03/` | `KCA_03_lab.zip` |
| 10 | Policy · ClusterPolicy | `KCA/KCA_10/` | `KCA_10_lab.zip` |
| 11 | match · exclude | `KCA/KCA_11/` | `KCA_11_lab.zip` |
| 23 | Autogen | `KCA/KCA_23/` | `KCA_23_lab.zip` |
