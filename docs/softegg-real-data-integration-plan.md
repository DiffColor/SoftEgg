# SoftEgg 실데이터 연동 작업 개요

## 목적

SoftEgg를 목데이터 기반 UI에서 운영 데이터 기반 패키징 도구로 전환한다.

최종 흐름은 아래와 같다.

1. 사용자가 5자리 회사 코드를 입력한다.
2. 공개 카탈로그 API에서 회사와 허용 소프트웨어 목록을 조회한다.
3. 사용자가 소프트웨어와 버전을 선택한다.
4. 선택한 메인 바이너리와 의존성을 FTP에서 내려받는다.
5. 로컬에서 체크섬 검증 후 `.segg` 패키지를 생성한다.
6. 생성 결과와 파일 경로를 UI에 표시한다.

## 운영 연동 전제

- API Base URL: `https://licensehub.ilycode.app`
- 카탈로그 조회 API: `GET /api/public/software-catalog/{companyCode}`
- 파일 저장소: FTP
- 운영 연결 정보는 단일 실행 파일 배포를 위해 앱 내부 런타임 구성에 포함한다.

주의:

- 민감정보는 UI에 노출하지 않는다.
- 앱 내부 포함 정보는 바이너리 분석으로 추출될 수 있으므로 릴리즈 배포 시 난독화와 배포 통제가 필요하다.
- 운영 API는 정상 응답을 반환하며, 회사 코드별로 소프트웨어 할당 여부가 다르다.
- 일부 소프트웨어는 `mainBinary.uri`가 비어 있으므로 선택 불가 처리 또는 패키징 차단이 필요하다.

## 백엔드 기준 실제 사용 데이터

카탈로그 응답에서 SoftEgg가 직접 사용하는 필드는 다음과 같다.

### 회사 정보

- `company.companyName`
- `company.companyCode`
- `company.issuedAt`
- `company.expiresAt`

### 소프트웨어 정보

- `softwarePackages[].id`
- `softwarePackages[].name`
- `softwarePackages[].codeName`
- `softwarePackages[].productId`
- `softwarePackages[].version`
- `softwarePackages[].os`
- `softwarePackages[].releaseChannel`
- `softwarePackages[].price`

### 메인 바이너리

- `softwarePackages[].mainBinary.name`
- `softwarePackages[].mainBinary.version`
- `softwarePackages[].mainBinary.uri`
- `softwarePackages[].mainBinary.checksum`

### 의존성 바이너리

- `softwarePackages[].dependencies[].name`
- `softwarePackages[].dependencies[].version`
- `softwarePackages[].dependencies[].uri`
- `softwarePackages[].dependencies[].checksum`

### 설치 옵션

- `softwarePackages[].installOptions.desktopShortcuts`
- `softwarePackages[].installOptions.startupPrograms`

## 제거하기로 한 항목

백엔드 실데이터와 맞지 않거나 중요하지 않은 항목은 UI와 모델에서 제거한다.

- 의존성 설명
- 예상 바이너리 수
- 추정 용량 표시를 위한 목데이터 필드
- 목데이터 기반 `versions[]` 구조
- 목데이터 기반 `sizeMb`

## 구현 개요

### 1. 데이터 모델 재설계

현재 Flutter 모델은 목카탈로그 기준이므로 운영 API 기준으로 다시 정의한다.

필요 모델:

- `CompanyCatalog`
- `RemoteSoftwarePackage`
- `RemoteSoftwareBinary`
- `RemoteInstallOptions`
- `RemoteInstallEntry`

추가 가공 모델:

- `SoftwareGroupViewModel`
  - 같은 제품을 UI에서 묶어 보여주기 위한 그룹 모델
  - 그룹 기준: `name + codeName + os + releaseChannel`
- `SoftwareVersionViewModel`
  - 실제 패키징 가능한 단일 버전 단위

핵심 규칙:

- 백엔드는 버전별 개별 레코드를 반환하므로 UI에서 그룹화해야 한다.
- `mainBinary.uri`가 없으면 해당 버전은 패키징 불가 상태로 표시한다.
- 의존성은 사용자가 선택 해제할 수 있는 구조인지 먼저 정책을 정해야 한다.
  - 기본안: 백엔드가 내려준 의존성은 기본 포함
  - 선택형이 필요하면 UI에서 체크박스 유지

### 2. API 계층 구현

필요 클래스:

- `CatalogApiClient`
- `CatalogRepository`
- `CatalogException`

주요 책임:

- 회사 코드 정규화
- HTTP GET 호출
- 200 응답 파싱
- 400/403/500 응답에서 `error`, `message`, `requestId` 추출
- 네트워크 예외와 서버 예외 구분

조회 규칙:

- 회사 코드 입력 완료 후 조회
- 필요 시 재조회 버튼 제공
- 응답 캐시는 현재 세션 메모리 수준으로만 유지

### 3. Step 1 재구성

현재 Step 1은 단순 로컬 상태 전환만 수행한다. 이를 실데이터 진입 단계로 바꾼다.

변경 내용:

- 회사 코드 입력 완료 후 API 호출
- 로딩 상태 표시
- 성공 시:
  - 회사명 저장
  - 유효시간 저장
  - 카탈로그 저장
  - Step 2 이동
- 실패 시:
  - 상단 알림 표시
  - Step 1 유지

실패 메시지 처리 기준:

- `할당된 소프트웨어가 없습니다.`: 회사는 유효하지만 현재 배포 가능 항목 없음
- `회사 코드가 만료되었거나 일치하지 않습니다.`: 코드 오류 또는 만료
- 네트워크 실패: 서버 연결 실패 안내

### 4. Step 2 재구성

Step 2는 현재 목데이터 기반 콤보박스를 운영 카탈로그 기반으로 바꾼다.

구성안:

- 상단 요약
  - 회사명
  - 회사 코드
  - 코드 유효시간
- 소프트웨어 선택 영역
  - 소프트웨어 그룹 콤보박스
  - 버전 콤보박스
  - OS / release channel 배지
- 메인 바이너리 정보
  - 파일명
  - checksum
  - 다운로드 가능 여부
- 의존성 목록
  - 파일명
  - 버전
  - checksum
  - 선택 가능 여부 또는 필수 포함 상태
- 설치 옵션 요약
  - desktop shortcut 항목
  - startup program 항목

중요 정책:

- `mainBinary.uri`가 비어 있으면 `Continue` 비활성화
- `dependencies[].uri`가 비어 있으면 해당 항목은 오류로 표시하고 전체 진행 차단 또는 제외 정책 필요
- Android용 소프트웨어가 내려와도 현재 SoftEgg가 Windows/macOS 패키징 용도라면 OS 필터링이 필요하다

기본 필터 권장:

- 현재 데스크톱 앱에서는 `windows`, `macos`, `all`만 우선 노출
- `android`, `ios`, `web`는 후순위 또는 숨김 처리

### 5. Step 3 실제 패키징 단계

현재는 타이머 기반 가짜 진행률이다. 이를 실제 작업 단계로 변경한다.

세부 단계:

1. 선택한 소프트웨어의 메인 바이너리와 의존성 목록 확정
2. 임시 작업 디렉터리 생성
3. FTP 다운로드 수행
4. 다운로드 완료 후 checksum 검증
5. 설치 옵션 메타데이터 생성
6. 패키지 매니페스트 생성
7. `.segg` 압축 생성
8. 결과 경로 반환

실행 로그 예시:

- 카탈로그 선택 확인
- 메인 바이너리 다운로드 시작
- 의존성 다운로드 시작/완료
- 체크섬 검증 성공/실패
- 매니페스트 생성 완료
- `.segg` 생성 완료

### 6. FTP 다운로드 구현 방식

현재 전제상 SoftEgg가 FTP에 직접 접속한다.

필요 구현:

- FTP URL 파서
- FTP 인증정보 주입 방식
- 파일 다운로드 스트림 처리
- 가능하면 파일 크기 사전 조회
- 실패 시 재시도 정책

주의:

- 운영 자격증명은 앱 UI에서 출력하지 않는다.
- 릴리즈 빌드는 난독화 옵션과 함께 배포한다.

### 7. 체크섬 검증

백엔드 응답의 `checksum`은 다운로드 검증에 사용한다.

구현 기준:

- 메인 바이너리 1회 검증
- 의존성 각각 검증
- 하나라도 실패하면 패키징 중단
- 실패한 파일명과 기대 checksum을 로그에 남김

주의:

- 현재 백엔드 `checksum`이 xxHash64 기반으로 보이므로 동일 알고리즘을 맞춰야 한다.
- Flutter만으로 구현 가능하지만 대용량 스트림 처리와 속도 측면에서 Rust 확장 여지를 남긴다.

### 8. `.segg` 패키지 구조

초기 버전에서는 단순하고 재현 가능한 구조가 중요하다.

권장 구성:

- `manifest.json`
- `main/`
- `dependencies/`
- `install-options.json`

`manifest.json` 포함 항목:

- 회사명
- 회사코드
- 소프트웨어 id
- productId
- name
- codeName
- version
- os
- releaseChannel
- main binary 정보
- dependency 목록
- 생성 시각
- 생성 도구 버전

### 9. Step 4 완료 화면

완료 단계는 실제 결과 기준으로 다시 구성한다.

표시 항목:

- 생성 파일명
- 생성 파일 절대 경로
- 회사명 / 회사코드
- 선택 소프트웨어 / 버전 / OS
- 포함된 메인 바이너리 파일명
- 포함된 의존성 파일명 목록
- 설치 옵션 요약
- 검증 성공 여부

제거 항목:

- 예상 바이너리 수
- 추정 패키지 크기

### 10. 예외 처리 기준

반드시 UI에서 명확히 구분해야 하는 실패 케이스:

- 회사 코드 만료 또는 불일치
- 회사에 할당된 소프트웨어 없음
- 메인 바이너리 미등록
- 의존성 URI 누락
- FTP 인증 실패
- FTP 다운로드 실패
- 체크섬 불일치
- 압축 생성 실패

각 실패는 상단 알림 + 로그 패널 + 진행 중단 상태로 처리한다.

## 구체적인 구현 대상 파일

예상 변경 범위:

- `lib/src/models/packaging_models.dart`
- `lib/src/features/wizard/packaging_wizard_page.dart`
- `lib/src/data/mock_catalog.dart`
- `lib/src/data/` 아래 API DTO/Repository 추가
- `lib/src/services/` 아래 FTP 다운로드/패키징 서비스 추가
- `lib/src/state/` 또는 동등한 상태 관리 계층 추가

신규 파일 후보:

- `lib/src/models/catalog_models.dart`
- `lib/src/data/catalog_api_client.dart`
- `lib/src/data/catalog_repository.dart`
- `lib/src/services/ftp_download_service.dart`
- `lib/src/services/package_builder_service.dart`
- `lib/src/services/checksum_service.dart`
- `lib/src/services/local_settings_service.dart`

## 체크리스트

### 분석 및 설계

- [x] 운영 카탈로그 DTO 정의
- [x] UI용 그룹화 모델 정의
- [x] FTP 인증정보 주입 방식 결정
- [x] checksum 알고리즘 확인
- [x] `.segg` 내부 manifest 스키마 확정
- [x] 운영 연동 스모크 실행 스크립트 추가

### Step 1

- [x] 회사 코드 입력 검증 로직 정리
- [x] 카탈로그 조회 API 연결
- [x] 로딩 상태 추가
- [x] 오류 응답 메시지 표시
- [x] 회사명/유효시간 상태 저장

### Step 2

- [x] 목카탈로그 제거
- [x] 운영 응답 기반 소프트웨어 그룹화
- [x] 버전 선택 UI 연결
- [x] 메인 바이너리 정보 표시
- [x] 의존성 목록 표시
- [x] 설치 옵션 요약 표시
- [x] 패키징 불가 항목 비활성화
- [x] 런타임 상태 표시

### Step 3

- [x] 임시 작업 디렉터리 생성
- [x] FTP 다운로드 구현
- [x] 다운로드 로그 표시
- [x] checksum 검증 구현
- [x] manifest 생성
- [x] `.segg` 압축 생성
- [x] 실패 시 롤백 또는 임시 파일 정리
- [x] 로그 저장/복사 기능 연결

### Step 4

- [x] 실제 생성 결과 화면 표시
- [x] 생성 파일 경로 복사 기능 유지
- [x] 검증 성공 여부 표시
- [x] 포함 파일 목록 표시
- [x] 폴더 열기 기능 추가

### 설정 및 보안

- [x] 운영 연결 정보 앱 내장
- [x] FTP host/id/password UI 비노출
- [x] 민감정보 취급 정책 정의
- [x] 단일 실행 파일 기준 동작 정리

### 검증

- [x] 유효한 회사 코드로 카탈로그 조회 확인
- [x] 소프트웨어 미할당 회사 코드 처리 확인
- [x] 메인 바이너리 누락 항목 차단 확인
- [x] FTP 다운로드 성공 확인
- [x] 체크섬 불일치 실패 처리 확인
- [x] `.segg` 생성 성공 확인
- [x] macOS 동작 확인
- [ ] Windows 동작 확인
- [x] `flutter analyze` 통과
- [x] `flutter test` 통과
- [x] Windows 검증용 PowerShell 스모크 스크립트 추가
- [x] Windows 수동 검증 체크리스트 문서 추가

## 추가 개발 항목

- [ ] Windows 실기기에서 `ftpconnect` 기반 FTP 다운로드와 `explorer /select` 동작 검증
- [ ] 대용량 바이너리용 스트리밍 checksum 최적화
- [x] Step 2에서 FTP 원격 용량 사전 조회 UI 도입

## 구현 우선순위

1. 카탈로그 DTO/Repository 구현
2. Step 1 실연동
3. Step 2 실데이터 UI 재구성
4. FTP 다운로드 서비스
5. 체크섬 검증
6. `.segg` 생성
7. Step 4 결과 화면 정리

## 보류 사항

아래 항목은 현재 범위에서 보류한다.

- 백엔드 다운로드 프록시 API 추가
- 라이선스 발급/회수/모바일 스캔 기능 연계
- Rust 브리지 도입
- 대용량 병렬 다운로드 최적화
- 서명 URL 발급 구조로 변경
