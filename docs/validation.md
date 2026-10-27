# 검증 기록

기준일: 2026-10-27. Source·문서 버전: **0.2.2**.

## 환경

- macOS 26.7.1, Apple Silicon arm64
- Apple Swift 6.3.3 (`swiftlang-6.3.3.1.3`)
- Xcode Command Line Tools의 SDK·toolchain
- 외부 Swift package 의존성 없음

## 실행한 검사

| 명령·검사 | 결과 |
| --- | --- |
| `swift run --scratch-path .build/public-review CoreChecks` | 12개 검증 그룹 통과, 실패 0 |
| `swift build --scratch-path .build/public-review --product MixManifest` | 통과 |
| `bash scripts/build-app.sh` | release 앱 bundle 생성 통과 |
| `codesign --verify --deep --strict dist/MixManifest.app` | 통과, ad-hoc 서명 |
| bundle metadata | short version 0.2.2, build 4 |
| 공개 source의 symlink 검사 | source tree에 symlink 없음 |
| upstream LICENSE·NOTICE hash 비교 | 원문 2개와 byte 일치 |

검사에는 `DEVELOPER_DIR`를 Command Line Tools로 지정했습니다. 제품이 지원 대상으로 선언한 최소 macOS 13·Swift 5.9 환경을 이번에 별도로 실행한 것은 아닙니다.

## 회귀 범위

테스트는 임시 폴더에 만든 synthetic 입력만 사용합니다.

1. 없거나 잘못된 프로젝트 경로·일반 파일·빈 패키지 거부
2. 손상된 header·잘린 payload의 명시적 진단과 metadata 보존
3. ProjectData symbolic link의 외부 경로 읽기 거부
4. bounded record·class version·합성 native/AU descriptor·pan·연결 미확인 처리
5. Alternative 선택·metadata 출처·JSON roundtrip
6. 잘못된 JSON 및 32 MiB 초과 import 거부
7. JSON export 총량 한도
8. schema·NUL 문자열·중복 식별자·잘못된 hash 거부
9. 256 MiB 초과 ProjectData의 사전 거부
10. 직접·다른 프로젝트·symbolic link·새 leaf·끊어진 link의 export 보호
11. metadata·root package symbolic link 거부
12. 8 MiB 초과 metadata plist 사전 거부

JSON export 크기 회귀는 수정 전 실패를 확인한 뒤 guard를 추가했습니다. 새 파일을 export할 때 Foundation이 상위 symbolic link를 해석하지 않는 경우도 회귀에서 실패를 확인했고, 기존 상위 경로를 먼저 해석하도록 수정한 뒤 통과했습니다.

## 확인하지 않은 범위

이 기록은 모든 실제 Logic Pro 세션·버전·플러그인·장치 호환성, 포맷 전체의 정확성, fuzzing·정식 보안 감사, notarization·배포, 모든 UI 동작을 보증하지 않습니다. 실제 프로젝트·음원·개인 manifest·관리 자료는 검사나 공개 source에 포함하지 않았습니다. 앱 UI의 별도 확인과 공개 저장소 반영은 이 로컬 build 검사와 구분합니다.
