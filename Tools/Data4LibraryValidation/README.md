# 도서 API 검증 도구

밑줄 앱의 프로덕션 타깃과 분리해 도서관 정보나루, 국립중앙도서관 ISBN 서지정보, 카카오 책 검색 API를 검증하는 macOS Swift Package입니다.

## 실행

```sh
cd Tools/Data4LibraryValidation
read -s DATA4LIBRARY_API_KEY
export DATA4LIBRARY_API_KEY
swift run data4library-validation
unset DATA4LIBRARY_API_KEY
```

인증키는 환경변수로만 전달하며 리포트나 오류 로그에 기록하지 않습니다. 빠른 스모크 테스트는 다음처럼 실행합니다.
실행 직후 인증키 사전 확인을 수행하며 `authErr`이면 25권 측정을 시작하지 않습니다.

```sh
swift run data4library-validation --preflight-only
```

위 명령이 `인증키 사전 확인 성공`을 출력한 뒤 전체 검증을 실행하세요.

```sh
swift run data4library-validation --repetitions 1 --delay-ms 100 --skip-lists
```

기본 결과는 `.build/validation-report/`의 다음 파일에 생성됩니다.

- `summary.json`: 도서별 원시 측정값과 목록 API 결과
- `results.csv`: 스프레드시트 분석용 도서별 결과
- `report.md`: 균형 합격선 기준 자동 요약과 조건부 채택 판정
- `response-samples/`: 인증 관련 필드를 제거한 엔드포인트별 첫 정상 JSON 응답

## 측정 정의

- 제목·저자 검색은 최대 200개 결과에서 목표 ISBN13의 순위를 찾습니다.
- 검색 결과 200개를 한 페이지로 요청해 기본 3회 전체 검증을 정보나루 API 500회 미만으로 제한합니다.
- ISBN 검색과 상세 조회는 목표 판본의 ISBN13을 기준으로 판정합니다.
- 각 API는 기본 3회 실행하며 요청은 직렬 처리합니다.
- 검색 시간은 페이지가 여러 개인 경우 목표 최대 범위까지의 합산 시간입니다.
- 표지는 HTTP 2xx, 이미지 MIME, 실제 이미지 디코딩을 모두 만족해야 로딩 성공입니다.
- 표지 품질은 현재 앱의 88×117pt 표시 영역을 3배율로 표시할 수 있는 264×351px 이상입니다.
- 정보나루가 HTTP 200 안에 `errCode`를 반환하는 경우도 API 실패로 기록합니다.

## 표본 관리

내장 `books.json`은 2026-09-22에 동결한 25권입니다. 최근 인기·스테디셀러, 국내 소설·번역서·에세이·자기계발·인문사회·IT 전문서를 섞었습니다. 다른 표본을 사용할 때도 정확히 25권을 유지하고 `--catalog`로 경로를 전달합니다.

```sh
swift test
swift run data4library-validation --validate-catalog
swift run data4library-validation --help
```

## 국립중앙도서관 ISBN 서지정보 검증

발급·승인된 인증키를 환경변수로만 전달합니다. `cert_key`는 URL query에 포함되므로 요청 URL이나 로그를 보고서에 저장하지 않으며, 응답 샘플에서도 같은 이름의 필드를 제거합니다.

```sh
cd Tools/Data4LibraryValidation
read -rs "NLK_ISBN_API_KEY?국립중앙도서관 인증키: "
export NLK_ISBN_API_KEY
swift run nlk-isbn-validation --preflight-only
swift run nlk-isbn-validation
unset NLK_ISBN_API_KEY
```

API를 호출하지 않고 공통 25권과 최근 2년 15권 구성을 확인할 수 있습니다.

```sh
swift run nlk-isbn-validation --validate-catalog
```

기본 결과는 `.build/nlk-isbn-validation-report/`에 생성됩니다.

- `summary.json`: 도서별 원시 관찰값
- `results.csv`: 검색·메타데이터·표지·책소개·페이지 수 결과
- `report.md`: 합격선과 해석
- `comparison.md`, `comparison.json`: 정보나루 기준선과 직접 비교
- `policy-inquiry.md`: iOS 직접 호출 및 인증키 정책 문의 초안
- `response-samples/`: 인증정보를 제거한 실제 JSON 구조

페이지 수 정확도를 독립 자료와 대조하려면 다음 배열 형식의 JSON을 전달합니다.

```json
[
  {
    "isbn13": "0000000000000",
    "expectedPageCount": 345,
    "source": "출판사 공식 페이지 URL 또는 실물 판권면"
  }
]
```

```sh
swift run nlk-isbn-validation --page-ground-truth page-ground-truth.json
```

국립중앙도서관 공개 문서에는 iOS 앱 번들에 인증키를 포함해 직접 호출해도 되는지가 명시돼 있지 않습니다. 데이터 품질 결과와 별개로 공식 답변 전에는 프로덕션 채택으로 판정하지 않습니다.

## 카카오 책 검색 검증

카카오디벨로퍼스 애플리케이션의 REST API 키를 환경변수로만 전달합니다. 키는 `Authorization` 헤더에만 포함되며 URL, 응답 샘플, 보고서에 기록하지 않습니다.

```sh
cd Tools/Data4LibraryValidation
read -rs "KAKAO_REST_API_KEY?카카오 REST API 키: "
export KAKAO_REST_API_KEY
swift run kakao-book-validation --preflight-only
swift run kakao-book-validation
unset KAKAO_REST_API_KEY
```

API 호출 없이 기존 25권, 최근 2년 15권, ISBN13 체크섬을 확인할 수 있습니다.

```sh
swift run kakao-book-validation --validate-catalog
swift test --filter KakaoBookValidationTests
```

기본 결과는 `.build/kakao-book-validation-report/`에 생성됩니다.

- `summary.json`: 일반·필드 지정 검색별 원시 관찰값
- `books.csv`: 도서별 순위, 메타데이터, 표지, 응답시간
- `report.md`: Top 50 채택 기준과 분리된 검색·표지 판정
- `comparison.md`, `comparison.json`: 정보나루 Top 50/200 기준선과 직접 비교
- `policy-inquiry.md`: iOS 앱의 REST API 키 사용 정책 문의 초안
- `response-samples/`: 인증키가 포함되지 않은 검색 방식별 첫 정상 응답

일반 검색은 현재 단일 검색창 UX의 주 지표이며, `target=title/person/isbn` 검색은 API의 잠재 정확도를 확인하는 보조 지표입니다. 각 검색은 페이지당 50건, 최대 200건을 수집합니다. 표지는 검색 셀 144×192px와 3배율 책장 264×351px 기준을 각각 기록하며, 표지 미달이 검색 API 판정을 자동으로 탈락시키지는 않습니다.

카카오 공식 문서는 모바일 환경에서 REST API 호출을 지원하지만 App Store 배포 앱에 REST API 키를 내장하는 정책을 명시적으로 확정하지 않습니다. `policy-inquiry.md`의 공식 답변을 받기 전에는 데이터 지표를 통과해도 프로덕션 채택을 보류합니다.

기존 측정값으로 판정 및 비교 리포트만 다시 만들려면 다음 명령을 사용합니다.

```sh
swift run kakao-book-validation \
  --report-from-summary .build/kakao-book-validation-report/summary.json
```
