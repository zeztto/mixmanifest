# MixManifest

**저장된 Logic Pro 프로젝트를 읽고, 해석한 정보와 근거를 기록하는 macOS 앱입니다.**

`.logicx` 패키지에서 프로젝트 메타데이터, 트랙·채널, 해석 가능한 플러그인 레코드를 살펴보고 JSON 또는 텍스트로 내보냅니다. Logic Pro를 실행하거나 프로젝트를 수정하지 않습니다.

문서·앱 버전: **0.2.2**

## 주요 기능

- 저장된 프로젝트의 Alternative를 선택해 읽습니다.
- 트랙 순서·이름과 연결 가능한 채널의 pan·fader 원시값을 표시합니다.
- 지원하는 저장 레코드에서 해석한 플러그인 이름·slot·종류를 표시합니다.
- 각 필드의 원본 파일·offset과 미확인 진단을 확인할 수 있습니다.
- JSON·텍스트 내보내기와 schema 검증을 거친 JSON 다시 열기를 지원합니다.
- export 대상이 `.logicx` 내부이면 거부해 원본 프로젝트를 보호합니다.

## 실행

macOS 13 이상과 Swift 5.9 이상을 요구합니다. Xcode Command Line Tools가 설치된 환경에서 빌드합니다. 외부 Swift package 의존성은 없습니다.

```sh
git clone https://github.com/zeztto/mixmanifest.git
cd mixmanifest
swift build --product MixManifest
swift run MixManifest
```

macOS 앱 bundle을 만들려면 다음 명령을 실행합니다.

```sh
bash scripts/build-app.sh
open dist/MixManifest.app
```

이 스크립트는 저장소의 `dist/`에만 앱을 만들고 ad-hoc 서명합니다. 배포자 인증서 서명이나 Apple notarization을 제공하지 않습니다. 앱을 시스템 폴더에 자동 설치하거나 Logic Pro를 실행하지 않습니다.

## 사용 흐름

1. Logic Pro에서 작업을 저장합니다. 저장되지 않은 편집 내용은 읽을 수 없습니다.
2. MixManifest의 프로젝트 열기에서 본인이 접근 권한을 가진 `.logicx`를 선택합니다.
3. 프로젝트 개요와 트랙·채널, 해석 근거·진단을 확인합니다.
4. 필요하면 프로젝트 밖의 별도 폴더에 JSON 또는 텍스트를 저장합니다.

JSON을 열었다고 기록된 프로젝트 경로를 자동으로 읽지는 않습니다. 다시 읽기 동작은 사용자가 명시적으로 실행합니다. 내보낸 자료에는 로컬 경로·프로젝트명·트랙명·플러그인 정보가 포함될 수 있으므로 그대로 공개하지 마세요.

## 해석 범위

- Apple의 비공개 포맷을 제한적으로 해석합니다. 전체 포맷이나 모든 Logic Pro 버전의 호환성을 보증하지 않습니다.
- 지원하지 않거나 모호한 framing·class version·연결은 진단으로 표시합니다. 트랙을 추정해 채우지 않습니다.
- BPM·박자·조성은 저장된 메타데이터 값입니다. 곡 전체의 tempo·signature 변화가 아닙니다.
- Fader는 8.24 원시값입니다. 이를 dB로 환산하거나 실제 믹서 레벨이라고 표현하지 않습니다.
- 플러그인은 저장된 일부 레코드입니다. 현재 활성 상태, 전체 slot 연결, 전체 parameter·automation·send·mute·solo는 지원하지 않습니다.
- 이름 인코딩은 지원 범위가 제한되어 있으며, 해석하지 못한 이름을 임의로 변환하지 않습니다.

## 테스트

```sh
swift run --scratch-path .build/public-review CoreChecks
swift build --scratch-path .build/public-review --product MixManifest
```

테스트는 임시 폴더의 synthetic package와 직접 생성한 descriptor만 사용합니다. 실제 세션·음원·고객 자료는 포함하지 않습니다. framing·version·symlink·파일 크기·schema·export 경계와 JSON roundtrip을 확인합니다. 이 테스트가 모든 실제 프로젝트나 DAW 호환성을 검증하는 것은 아닙니다.

검증 환경과 명령은 [검증 기록](docs/validation.md), 파일·개인정보 처리 경계는 [SECURITY.md](SECURITY.md)에 정리합니다.

## 라이선스와 출처

직접 작성한 앱·manifest 코드·테스트·도구는 [MIT](LICENSE)로 공개합니다. `LogicProjectReader.swift`는 [logicxkit](https://github.com/phierceweb/logicxkit/tree/75b58fbf597a2ea1296b68323c09c7e3bed84ff6)의 포맷 정보와 일부 parsing logic을 이식한 **Apache-2.0** adaptation이며 별도 고지를 유지합니다. root MIT 라이선스가 이 파일이나 외부 코드의 라이선스를 덮어쓰지 않습니다.

[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) · [변경 기록](CHANGELOG.md)

Logic Pro와 Apple은 Apple Inc.의 상표입니다. 이 프로젝트는 Apple과 제휴하거나 Apple의 보증을 받은 제품이 아닙니다.
