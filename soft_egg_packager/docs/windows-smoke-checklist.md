# SoftEgg Windows 스모크 검증 체크리스트

## 목적

Windows 실기기에서 SoftEgg가 아래 흐름을 정상 수행하는지 검증한다.

1. 앱 내장 런타임 초기화
2. 회사 코드 기반 카탈로그 조회
3. FTP 원격 용량 조회
4. FTP 다운로드
5. xxHash64 검증
6. `.segg` 생성
7. Windows debug build
8. 결과 폴더 열기

## 준비

- Flutter for Windows 설치 완료
- 내장 FTP 라이브러리(`ftpconnect`) 동작 가능

## 자동 검증

PowerShell에서 아래 명령을 실행한다.

```powershell
pwsh -File .\tool\smoke_real_packaging.ps1 U4HHP
```

기대 결과:

- `flutter analyze` 성공
- `flutter test` 성공
- `dart run tool/smoke_real_packaging.dart U4HHP` 성공
- `flutter build windows --debug` 성공

## 수동 UI 검증

1. `flutter run -d windows`
2. Step 1에서 유효 회사 코드 입력
3. Step 2에서 아래 항목 확인
   - 회사명, 회사코드, 유효시간
   - 메인 바이너리와 의존성 원격 용량
   - 메인 바이너리 미등록 항목 진행 차단
4. `Start Packaging` 실행
5. Step 3에서 아래 항목 확인
   - 단계별 진행 카드 상태 변화
   - 로그 누적
   - 실패 시 상단 알림
6. Step 4에서 아래 항목 확인
   - 생성 파일 경로
   - manifest 경로
   - 포함 파일 목록
   - `Open Folder` 버튼 동작

## 기록 항목

- 검증 일시
- Windows 버전
- Flutter 버전
- 회사 코드
- 선택 패키지
- 생성 `.segg` 경로
- 실패 시 오류 로그
