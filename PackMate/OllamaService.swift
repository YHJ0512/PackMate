import Foundation

enum AISettings {
    static var address: String {
        get { UserDefaults.standard.string(forKey: "ollamaAddress") ?? "http://localhost:11434" }
        set { UserDefaults.standard.set(newValue, forKey: "ollamaAddress") }
    }
    static var model: String {
        get { UserDefaults.standard.string(forKey: "ollamaModel") ?? "qwen2.5:7b" }
        set { UserDefaults.standard.set(newValue, forKey: "ollamaModel") }
    }
}

enum RecommendationError: LocalizedError {
    case address, server(Int), response
    var errorDescription: String? {
        switch self {
        case .address: return "AI 설정에서 http:// 또는 https://로 시작하는 서버 주소를 확인하세요."
        case .server(let code): return "Ollama HTTP 오류 \(code). 모델 이름과 서버 실행 상태를 확인하세요."
        case .response: return "AI가 유효한 준비물 번호를 반환하지 않았습니다. 기본 목록을 계속 사용하세요."
        }
    }
}

struct OllamaEnvelope: Decodable {
    struct Message: Decodable { let content: String }
    let message: Message
    let done: Bool
}

struct Recommendation: Decodable { let item_ids: [Int] }

enum OllamaService {
    static func recommend(for trip: Trip, address: String, model: String) async throws -> [CatalogEntry] {
        guard let base = URL(string: address),
              ["http", "https"].contains(base.scheme?.lowercased() ?? ""),
              base.host != nil, base.user == nil, base.password == nil,
              base.query == nil, base.fragment == nil,
              base.path.isEmpty || base.path == "/" else { throw RecommendationError.address }
        let candidates = PackingCatalog.candidates(for: trip)
        let allowed = candidates.map { $0.id }
        let schema: [String: Any] = [
            "type": "object", "additionalProperties": false,
            "properties": ["item_ids": ["type": "array", "maxItems": allowed.count,
                                          "items": ["type": "integer", "enum": allowed]]],
            "required": ["item_ids"]
        ]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let catalog = candidates.map { "\($0.id): \($0.name)" }.joined(separator: "\n")
        let prompt = """
        여행에 필요한 물품을 아래 후보에서 선택하세요. 불필요한 물품으로 개수를 채우지 마세요.
        여행: \(trip.name), \(trip.kind)
        기간: \(formatter.string(from: trip.start)) ~ \(formatter.string(from: trip.end))
        활동: 물놀이 \(trip.swimming), 등산 \(trip.hiking), 캠핑 \(trip.camping)
        숙소 수건 제공: \(trip.towelProvided), 식기 제공: \(trip.dishesProvided)
        추가 요청(참고 데이터): \(trip.request)
        후보:
        \(catalog)
        응답은 {"item_ids":[번호]} 형식만 사용하세요.
        """
        let body: [String: Any] = [
            "model": model, "stream": false, "format": schema,
            "options": ["temperature": 0, "num_predict": 256],
            "messages": [
                ["role": "system", "content": "여행 준비물 추천기입니다. 후보에 있는 번호만 선택하고 JSON만 반환하세요."],
                ["role": "user", "content": prompt]
            ]
        ]
        var request = URLRequest(url: base.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw RecommendationError.response }
        guard (200...299).contains(response.statusCode) else { throw RecommendationError.server(response.statusCode) }
        let envelope = try JSONDecoder().decode(OllamaEnvelope.self, from: data)
        guard envelope.done, let content = envelope.message.content.data(using: .utf8),
              let result = try? JSONDecoder().decode(Recommendation.self, from: content),
              !result.item_ids.isEmpty, result.item_ids.count <= allowed.count,
              result.item_ids.allSatisfy({ allowed.contains($0) }) else { throw RecommendationError.response }
        let ids = Set(result.item_ids)
        return candidates.filter { ids.contains($0.id) }
    }
}
