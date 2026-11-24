import Foundation

struct PackingItem: Codable, Identifiable {
    var id = UUID()
    var name: String
    var quantity: Int = 1
    var packed = false
    var catalogID: Int?
}

struct Lodging: Codable {
    struct Location: Codable {
        let address: String
        let latitude: Double
        let longitude: Double
        let countryCode: String?
    }

    let name: String
    var location: Location?
    var website: URL?
    var guide: LodgingGuide?
    var confirmedExtras: [String] = []
}

struct LodgingGuide: Codable {
    let freeItems: [String]
    let note: String
    let sourceURL: URL

    static func lodgingForKnownName(_ input: String) -> Lodging? {
        let alias = key(input).replacingOccurrences(of: "gangneung", with: "")
            .replacingOccurrences(of: "강릉", with: "")
        let name: String
        let location: Lodging.Location
        switch alias {
        case "skybay", "skybayhotel", "skybaygyeongpo", "skybayhotelgyeongpo", "skybaygyeongpohotel",
             "스카이베이", "스카이베이호텔", "스카이베이호텔경포", "스카이베이경포호텔":
            name = "Skybay Hotel Gyeongpo"
            location = .init(address: "강릉시 해안로 476", latitude: 37.8042300, longitude: 128.9078219, countryCode: "KR")
        case "stjohns", "stjohnshotel", "saintjohns", "saintjohnshotel", "세인트존스", "세인트존스호텔":
            name = "St. John's Hotel"
            location = .init(address: "강릉시 창해로 307", latitude: 37.7912800, longitude: 128.9209319, countryCode: "KR")
        default:
            return nil
        }
        let guide = lookup(name: name, address: location.address, website: nil)
        return Lodging(name: name, location: location, guide: guide)
    }

    static func lookup(name: String, address: String, website: URL?) -> LodgingGuide? {
        let nameKey = key(name)
        let addressKey = key(address)
        let host = website?.host?.lowercased() ?? ""

        if (nameKey.contains("스카이베이") || nameKey.contains("skybay")),
           (addressKey.contains("해안로476") || addressKey.contains("476haeanro") ||
            addressKey.contains("haeanro476") || host == "skybay.co.kr" || host.hasSuffix(".skybay.co.kr")) {
            guard let source = URL(string: "https://skybay.co.kr/faq?category=DN242Urz15") else { return nil }
            return LodgingGuide(freeItems: ["와이파이"],
                               note: "호텔 공식 FAQ 기준. 객실 비품은 예약 안내에서 확인하세요.",
                               sourceURL: source)
        }

        if (nameKey.contains("세인트존스") || nameKey.contains("stjohns") || nameKey.contains("saintjohns")),
           (addressKey.contains("창해로307") || addressKey.contains("307changhaero") ||
            addressKey.contains("changhaero307") || host == "stjohns.co.kr" || host.hasSuffix(".stjohns.co.kr")) {
            guard let source = URL(string: "https://new.stjohns.co.kr/accommodation/index/SUP") else { return nil }
            return LodgingGuide(freeItems: ["와이파이", "페이스타월 (기준 인원당 1회, 추가 유료)",
                                             "아기 침대·욕조 대여 (24개월 이하, 사전 예약)"],
                               note: "슈페리어 더블 객실 안내 기준. 예약한 객실의 조건을 확인하세요.",
                               sourceURL: source)
        }

        return nil
    }

    private static func key(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}

struct Trip: Codable, Identifiable {
    var id = UUID()
    var name: String
    var start: Date
    var end: Date
    var kind: String
    var swimming: Bool
    var hiking: Bool
    var camping: Bool
    var towelProvided: Bool
    var dishesProvided: Bool
    var request: String
    var items: [PackingItem] = []
    var source = "기본 목록"
    var lodging: Lodging?
}

struct CatalogEntry {
    let id: Int
    let name: String
    let activity: String?
}

enum PackingCatalog {
    static let entries: [CatalogEntry] = [
        .init(id: 1, name: "여벌 옷", activity: nil),
        .init(id: 2, name: "속옷", activity: nil),
        .init(id: 3, name: "양말", activity: nil),
        .init(id: 4, name: "휴대폰 충전기", activity: nil),
        .init(id: 5, name: "세면도구", activity: nil),
        .init(id: 6, name: "수건", activity: nil),
        .init(id: 7, name: "식기", activity: "camping"),
        .init(id: 8, name: "수영복", activity: "swimming"),
        .init(id: 9, name: "방수팩", activity: "swimming"),
        .init(id: 10, name: "물놀이용 여벌 옷", activity: "swimming"),
        .init(id: 11, name: "등산 스틱", activity: "hiking"),
        .init(id: 12, name: "등산화", activity: "hiking"),
        .init(id: 13, name: "텐트", activity: "camping"),
        .init(id: 14, name: "침낭", activity: "camping"),
        .init(id: 15, name: "손전등", activity: "camping"),
        .init(id: 16, name: "보조 배터리", activity: nil),
        .init(id: 17, name: "모자", activity: nil),
        .init(id: 18, name: "선크림", activity: nil),
        .init(id: 19, name: "물병", activity: nil),
        .init(id: 20, name: "작은 배낭", activity: nil)
    ]

    // 명확한 제외 조건은 AI에 맡기지 않고 Swift 조건문으로 처리합니다.
    static func candidates(for trip: Trip) -> [CatalogEntry] {
        entries.filter { entry in
            if trip.towelProvided && entry.id == 6 { return false }
            if trip.dishesProvided && entry.id == 7 { return false }
            switch entry.activity {
            case "swimming": return trip.swimming
            case "hiking": return trip.hiking
            case "camping": return trip.camping
            default: return true
            }
        }
    }

    static func basicItems(for trip: Trip) -> [PackingItem] {
        let nights = max(1, Calendar.current.dateComponents([.day], from: trip.start, to: trip.end).day ?? 1)
        return candidates(for: trip).filter { $0.id <= 5 || $0.activity != nil || $0.id == 6 }
            .map { entry in
                PackingItem(name: entry.name,
                            quantity: [1, 2, 3].contains(entry.id) ? min(nights, 30) : 1,
                            catalogID: entry.id)
            }
    }
}

@MainActor
final class TripStore {
    static let shared = TripStore()
    private(set) var trips: [Trip] = []
    private let fileURL: URL

    private init() {
        fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("packmate-trips.json")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do { trips = try JSONDecoder().decode([Trip].self, from: Data(contentsOf: fileURL)) }
            catch { loadError = "저장한 여행 정보를 읽을 수 없습니다." }
        }
    }

    private(set) var loadError: String?

    func trip(id: UUID) -> Trip? { trips.first { $0.id == id } }

    func upsert(_ trip: Trip) throws {
        var updated = trips
        if let index = updated.firstIndex(where: { $0.id == trip.id }) { updated[index] = trip }
        else { updated.insert(trip, at: 0) }
        try write(updated)
    }

    func remove(id: UUID) throws { try write(trips.filter { $0.id != id }) }

    private func write(_ updated: [Trip]) throws {
        // 손상된 기존 저장 파일을 자동으로 덮어쓰지 않습니다.
        guard loadError == nil else {
            throw NSError(domain: "PackMate", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "기존 저장 파일을 읽을 수 없습니다. 파일을 백업하거나 앱 데이터를 초기화한 뒤 다시 실행하세요."])
        }
        let data = try JSONEncoder().encode(updated)
        try data.write(to: fileURL, options: .atomic)
        trips = updated
    }
}
