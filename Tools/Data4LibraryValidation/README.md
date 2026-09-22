# 도서관 정보나루 검증 도구

밑줄 앱의 프로덕션 타깃과 분리해 도서관 정보나루의 검색·상세·인기대출·대출 급상승 API를 검증하는 macOS Swift 실행 도구입니다.

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
