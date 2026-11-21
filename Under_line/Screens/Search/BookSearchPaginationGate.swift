/// 하단 영역에 머무르는 동안 같은 요청을 반복하지 않는다.
/// 성공으로 행 수가 갱신되거나 하단을 벗어났다가 다시 진입하면 재요청할 수 있다.
struct BookSearchPaginationGate {
    private var enteredThreshold = false

    mutating func listDidUpdate() {
        enteredThreshold = false
    }

    mutating func shouldRequest(lastVisibleRow: Int?, rowCount: Int, isLoading: Bool) -> Bool {
        // 레이아웃 도중 일시적으로 visible row가 사라져도 실패 재시도를 재무장하지 않는다.
        guard rowCount > 0, let row = lastVisibleRow, row >= 0, row < rowCount else { return false }
        guard row >= max(0, rowCount - 5) else {
            enteredThreshold = false
            return false
        }
        guard !isLoading, !enteredThreshold else { return false }
        enteredThreshold = true
        return true
    }
}
