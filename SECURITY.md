# 보안과 개인정보 처리 경계

## 처리하는 정보

MixManifest는 사용자가 고른 로컬 `.logicx` 또는 JSON을 읽습니다. 선택한 source에는 네트워크 요청·telemetry·외부 명령 실행이 없고, 시스템 서비스나 Logic Pro에 자동 연결하지 않습니다. OS·Swift·Foundation·AppKit의 동작까지 감사한 결과는 아닙니다.

읽어낸 manifest에는 로컬 경로·프로젝트명·트랙명과 플러그인 레코드가 들어갈 수 있습니다. 내보낸 JSON·텍스트와 화면은 개인정보나 미공개 작업물을 포함할 수 있으므로 자동으로 공개하지 마세요. 저장소에는 실제 프로젝트·음원·실사용 manifest를 포함하지 않습니다.

## 파일 경계

- 입력 프로젝트는 read-only로 취급합니다. export는 사용자의 SavePanel 선택 뒤 별도 파일에 atomic write합니다.
- 프로젝트 내부의 symbolic link, 일반 파일이 아닌 payload, 경로 이탈을 거부합니다.
- ProjectData는 최대 256 MiB, metadata plist는 8 MiB, JSON은 32 MiB를 허용합니다.
- Alternative 항목·record·track 수와 schema·식별자·문자열에 한도를 둡니다. JSON export도 import와 같은 크기 한도를 적용합니다.
- `.logicx` 내부 및 해당 내부로 해석되는 symbolic-link 대상에는 export하지 않습니다.
- JSON에 적힌 프로젝트 경로는 자동으로 다시 읽지 않습니다. 사용자의 명시적 다시 읽기 동작이 필요합니다.

이 앱은 적대적 파일의 완전한 sandbox나 정식 binary format verifier가 아닙니다. 신뢰하지 않는 프로젝트를 열지 말고, 읽는 동안 다른 프로그램이 프로젝트·symlink를 변경하지 않는 환경을 사용하세요. 동일 권한 프로세스의 동시 파일 교체, 모든 parser resource-exhaustion, 미지원 포맷의 안전성을 보증하지 않습니다. 우선 복사본에서 확인하고 원본 backup을 유지하세요.

## 실행·배포 경계

검증 대상은 저장소의 source와 synthetic 테스트입니다. 모든 Logic Pro 버전·plug-in·장치·실제 세션을 검증하지 않았습니다. build script는 로컬 `dist/`에 ad-hoc 서명된 앱만 만들며 notarized 배포물이 아닙니다.

## 제보

개인정보가 없는 재현 절차·지원 format/version·오류 위치로 GitHub Issue를 작성해주세요. 실제 프로젝트·음원·manifest·절대 경로·credential을 공개 Issue에 첨부하지 마세요. 민감한 자료가 필요한 경우 공개 포트폴리오의 [문의](https://p1zza.kr/inquiry)에서 안전한 전달 방법을 먼저 협의하세요.
