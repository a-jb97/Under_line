# 도서 검색 성능 측정

## 계측 범위

Debug 빌드에서만 `com.jade.UnderLine` subsystem의 `BookSearchPerformance` category에 기록한다. Xcode 콘솔에서 `stage=`로 필터링하거나 시뮬레이터 로그를 확인한다.

```sh
xcrun simctl spawn booted log show --last 15m --style compact \
  --predicate 'subsystem == "com.jade.UnderLine" AND category == "BookSearchPerformance"'
```

| stage | 시작 → 종료 |
| --- | --- |
| `responseDecoded` | API 요청 직전 → Alamofire 응답 디코딩 후 호출자 복귀 |
| `domainMapping` | DTO 배열의 `toDomain()` 시작 → 전체 변환 완료 |
| `firstCellWillDisplay` | Controller의 목록 수신 → 해당 갱신 후 첫 `willDisplayCell` |
| `coverLoaded` | 셀의 Kingfisher `setImage` 호출 → 완료 콜백 |

- `ms`는 단조 증가하는 system uptime으로 측정한 밀리초다.
- API 응답 대기에는 네트워크, 디코딩, 호출자 재개 대기가 포함된다. 순수 서버 처리 시간은 아니다.
- `firstCellWillDisplay`는 화면 합성 완료 시간이 아니다. 페이지 추가 시에는 전체 reload 후 기존 셀의 첫 표시도 포함한다.
- 이미지 요청은 셀 구성 시 시작되므로 화면에 보이기 전의 요청도 포함할 수 있다. 완료된 이미지마다 기록하며, 여러 이미지 시간을 합산하지 않는다.
- API 요청과 DTO 변환은 같은 임의 `id`를 사용한다. 테이블 갱신과 그 갱신에 속한 표지는 별도의 공통 `id`를 사용한다. API와 UI의 id는 직접 연결되지 않는다.
- `source`는 bestseller/newSpecial/search/table이다. `count`는 응답·변환·테이블의 도서 수이며 표지에서는 0이다.
- 표지 성공 시 `cache=none/memory/disk`를 기록한다. `none`은 Kingfisher 캐시 미사용이며 OS·HTTP 캐시까지 비어 있다는 뜻은 아니다.
- `outcome=success`만 정상 표시 표본으로 집계한다. failed/cancelled/superseded/notDisplayed/noURL은 따로 센다. 빈 목록에는 첫 셀 로그가 없다.
- 검색어, 책 제목, ISBN, URL, API 키, 응답 본문, 오류 설명은 기록하지 않는다. Release에서는 계측 코드가 제외된다.

## 기준값 수집 절차

1. 동일 기기·OS·Debug 빌드·네트워크를 사용한다. 기기 부팅과 앱 설치가 끝난 뒤 측정한다.
2. 최초 진입은 앱을 종료·재실행하고 도서 검색을 열어 베스트셀러와 표지가 표시될 때까지 기다린다. 이어 고정 검색어 `어린 왕자`로 검색하고 결과·표지 완료를 기다린다. 총 5회 반복한다.
3. 재진입은 같은 앱 실행 안에서 검색 시트를 닫고 다시 열어 같은 검색어로 검색한다. 총 5회 반복한다.
4. 회차별로 API 응답·DTO 변환·첫 셀·표지 시간을 기록하고, 최초 진입과 재진입 각각의 중앙값 및 범위를 비교한다. 표지는 캐시 종류별로 분리한다.
5. 추천 신간 탭과 추가 페이지 로딩도 별도로 확인한다. 빠른 검색·탭 전환, 빈 결과, 화면 닫기 시 실패·교체 표본이 성공 표본에 섞이지 않는지 확인한다.

앱 재실행은 Kingfisher 디스크 캐시를 지우지 않는다. 위 최초 진입은 **프로세스 재시작 기준**이며 완전한 이미지 캐시 미스라고 가정하지 않는다. 완전한 캐시 미스 비교가 필요하면 별도 테스트용 새 시뮬레이터를 사용한다. 각 후속 단계도 같은 조건으로 비교한다. Debug 로깅 자체의 비용이 포함되므로 배포 빌드의 절대 성능으로 해석하지 않는다.

## 1단계 검증 상태

2026-09-16 검증 결과:

- Debug·Release의 generic iOS Simulator 앱·위젯 빌드 성공.
- Debug 실행 파일에서 계측 식별자 확인, Release 실행 파일에서는 제외됨을 확인.
- iPhone 17 Pro / iOS 26.5 시뮬레이터에 Debug 앱 설치 및 실행 명령 성공. 검색 화면 조작 검증과는 구분한다.
- `git diff --check` 통과.
- 기존 `ReadingActivityManager`의 actor 격리 경고와 앱(1.2.4)·위젯(1.2.3)의 버전 불일치 경고는 이번 수정 범위에 포함하지 않음.

계측을 추가했으며 검색·페이지네이션·HTML 변환·이미지 로딩 정책은 유지한다. 시뮬레이터 UI 제어 도구의 타임아웃으로 최초 진입 및 재진입 각 5회의 기준값은 아직 수집하지 못했다. 실제 지연 수치와 개선율은 미확정이며, 위 절차로 기준값을 수집해야 1단계의 측정 완료 조건을 충족한다.
