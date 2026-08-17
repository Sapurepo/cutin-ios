/* 시각을 사람 말로 — 카드·상세·댓글이 같은 규칙을 쓴다.
 *
 * "2026년 8월 17일"은 문서의 시각이고, 친구의 오늘을 보는 피드에는 "3시간 전"이 맞다
 * (레퍼런스 BeReal·setlog — 하루 한 번의 시간 감각). 일주일이 지나면 날짜로 돌아간다 —
 * "43일 전"은 세는 사람이 없다. 올해 안이면 연도를 뺀다.
 *
 * `RelativeDateTimeFormatter`를 쓰지 않는 이유: "1주 전"·"1개월 전"처럼 단위를 스스로 고르는데,
 * 여기서는 일주일 넘으면 날짜로 바꾸고 싶어서다. */

import Foundation

extension Date {
    /// "방금" · "N분 전" · "N시간 전" · "N일 전" · "8월 17일" · "2025년 8월 17일"
    func casual(now: Date = .now, calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(self)
        if seconds < 60 { return "방금" }
        if seconds < 3600 { return "\(Int(seconds / 60))분 전" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))시간 전" }
        if seconds < 7 * 86_400 { return "\(Int(seconds / 86_400))일 전" }
        let sameYear = calendar.component(.year, from: self) == calendar.component(.year, from: now)
        return formatted(sameYear
            ? .dateTime.month(.defaultDigits).day()
            : .dateTime.year().month(.defaultDigits).day())
    }
}
