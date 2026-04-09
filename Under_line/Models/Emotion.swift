//
//  Emotion.swift
//  Under_line
//
//  문장 수집 시 선택하는 감정 타입
//

import UIKit

enum Emotion: Int, CaseIterable {
    case joy, calm, sad, touched, pensive, tense

    var emoji: UIImage {
        switch self {
        case .joy:     return .happy
        case .calm:    return .calm
        case .sad:     return .sad
        case .touched: return .moved
        case .pensive: return .meditation
        case .tense:   return .nervous
        }
    }

    var label: String {
        switch self {
        case .joy:     return "기쁨"
        case .calm:    return "평온"
        case .sad:     return "슬픔"
        case .touched: return "감동"
        case .pensive: return "사색"
        case .tense:   return "긴장"
        }
    }

    var assetName: String {
        switch self {
        case .joy:     return "Happy"
        case .calm:    return "Calm"
        case .sad:     return "Sad"
        case .touched: return "Moved"
        case .pensive: return "Meditation"
        case .tense:   return "Nervous"
        }
    }
}
