# 업데이트 예외 테스트

## 2026-11-13 실행 결과

- 앱과 위젯 및 테스트 타깃 컴파일 완료.
- iOS 18.5 / iPhone 16 Pro: 159개 중 150개 통과, 9개 프로세스 충돌로 실패.
- iOS 26 / iPhone 17 Pro: 160개 중 151개 통과, 동일한 객체 해제 중 메모리 오류로 9개 실패.
- 추가한 누락/null 데이터, 오프라인 복구, 서점 독립 실패, 다른 서점 재선택 테스트 및 기존 데이터 충돌 보존 검증은 iOS 26 실행 로그에서 통과 확인.
- 전체 통과 및 출시 검증 완료로 판정하지 않는다. 실제 서점과 Safari 실패 UI는 아래 수동 검증이 남아 있다.

결과 파일:

```text
/private/tmp/underline-exception-tests-final.xcresult
/private/tmp/underline-exception-tests-ios26.xcresult
/private/tmp/underline-exception-tests-final.log
/private/tmp/underline-exception-tests-ios26.log
```

충돌 로그의 공통 경로는 `swift::TaskLocal::StopLookupScope` →
`swift_task_deinitOnExecutorMainActorBackDeploy` → 객체 해제다.
확인된 객체는 `BookPurchasePreferenceStore`, `BackupService`, `BookSearchPerformance.Span`,
테스트의 `StubResolver`, `StubBookSearchService`다.
이는 원인 조사 단서이며 컴파일러/런타임 결함으로 확정한 것은 아니다.

충돌한 기존 테스트:

- BookPurchaseServiceTests: 설정 불일치 거절, 선호 서점 저장, 설정 화면의 선호 서점 변경
- BookRepositoryTests: 기존 장르 정규화
- BookSearchViewModelTests: 등록 도서 셀, 좁은 셀 레이아웃, 셀 재사용
- WishlistViewModelTests: 구매 셀 재사용, 셀 그림자 레이아웃

## 자동 검증 범위

| 요구사항 | 검증 위치 / 기대 결과 |
| --- | --- |
| ISBN 없음·잘못된 ISBN13 | KakaoBookSearchServiceTests: 해당 항목만 제외, 유효 도서는 유지 |
| 표지·책소개·저자·출판사 없음 | KakaoBookSearchServiceTests: 누락/null 허용, 표지는 nil, 텍스트는 빈 값 |
| 검색 결과 없음·API 오류 | KakaoBookSearchServiceTests, BookSearchViewModelTests: 빈 목록/오류 표시 후 재검색 가능 |
| 네트워크 실패 | KakaoBookSearchServiceTests: URLProtocol로 오프라인 재현, 이후 검색 성공 |
| 빠른 연속 검색 | BookSearchViewModelTests: 같은 요청 중복 차단, 이전 검색의 늦은 응답 무시 |
| 이미 등록된 도서·기존 데이터 충돌 | BookRepositoryTests: 중복 거절, 기존 제목과 설명 보존 |
| 위시리스트 중복·추가/삭제 실패 | WishlistRepositoryTests, BookSearchViewModelTests, WishlistViewModelTests: 원래 상태 유지, 재시도 허용 |
| 등록 도서와 위시리스트 관계 | WishlistRepositoryTests: 같은 ISBN을 독립적으로 저장/삭제, 기존 저장소 확장 후 데이터 보존 |
| 구매 URL 오류·ISBN 오류·서점 독립 실패 | BookPurchaseServiceTests: 오류 전달, 다른 서점 정상 사용 |
| 실패 후 다른 서점 선택 | WishlistViewModelTests: 실패 후 요청 잠금 해제, 다른 서점 연결 가능 |

## 실제 기기/서점 수동 검증 (미실행)

구매 기능은 ISBN 검색 URL을 생성한다. 상품 상세 URL 조회나 재고 API는 사용하지 않는다.
상품 없음·품절·절판은 서점 검색/상품 페이지에서 확인하며 앱이 재고 상태를 판정하지 않는다.

- [ ] 표지/설명/저자/출판사가 없는 도서에서 목록과 펼치기 UI가 깨지지 않는지 확인한다.
- [ ] 비행기 모드에서 검색 오류를 확인하고, 연결 복구 후 같은 검색어로 다시 검색한다.
- [ ] 검색어를 빠르게 바꾸어 마지막 검색 결과만 표시되는지 확인한다.
- [ ] 기존 사용자 백업을 복원하고 같은 ISBN의 신규 검색 결과를 등록해 독서 진행·문장·세션이 유지되는지 확인한다.
- [ ] 각 서점에서 검색 결과 없는 ISBN과 품절/절판 도서를 확인하고, 창을 닫아 다른 서점을 이용한다.
- [ ] 서점 페이지 로딩 전에 네트워크를 끊어 실패 안내 후 위시리스트로 돌아오는지 확인한다.
- [ ] iPhone/iPad에서 서점 선택을 반복하여 세 서점의 검색어가 해당 ISBN인지 확인한다.

SFSafariViewController 초기 로딩 실패는 창을 닫고 연결 확인/다른 서점 선택 안내를 표시한다.
HTTP 오류 페이지가 정상 HTML로 로딩되는 경우와 최초 로딩 이후의 탐색 실패는 이 콜백만으로 판정할 수 없으므로 수동 확인한다.
