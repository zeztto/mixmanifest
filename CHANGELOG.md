# 변경 기록

## 0.2.2 - 2026-10-27

- 공개용 source snapshot을 분리하고 프로젝트 파일·결과·운영 이력은 포함하지 않았습니다.
- 모든 회귀 fixture를 직접 생성한 synthetic 데이터로 구성했습니다.
- JSON export·import 크기 계약과 `.logicx` export 보호를 명시적으로 검사합니다.
- 새 export 파일의 상위 경로에서 symbolic link를 해석하고, 프로젝트 내부 대상과 끊어진 link를 거부합니다.
- MIT 적용 범위와 logicxkit 기반 parser의 Apache-2.0 출처를 구분했습니다.
- 빌드·검증 절차와 지원·보안 경계를 정리했습니다.
