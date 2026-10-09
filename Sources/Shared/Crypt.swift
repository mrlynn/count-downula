import Foundation

/// One entry in the public crypt, as the server lists it.
struct CryptEntry: Identifiable, Equatable {
    let slug: String
    let title: String
    let details: String
    let category: String
    let target: Date
    let floating: Bool
    let scene: SceneID?
    let memberCount: Int

    var id: String { slug }
}

extension LiveLinkAPI {
    struct CryptCategory: Decodable, Identifiable, Hashable {
        let slug: String
        let name: String
        var id: String { slug }
    }

    private struct CryptList: Decodable {
        struct Entry: Decodable {
            struct Body: Decodable {
                let slug: String
                let title: String
                let details: String
                let category: String?
                let targetDate: Date
                let floating: String?
                let style: Style?
            }
            struct Style: Decodable {
                struct Background: Decodable {
                    struct Scene: Decodable { let _0: String }
                    let scene: Scene?
                }
                let background: Background?
            }
            let countdown: Body
            let memberCount: Int
        }
        let categories: [CryptCategory]
        let entries: [Entry]
    }

    static func crypt() async throws -> (categories: [CryptCategory], entries: [CryptEntry]) {
        let (data, status) = try await raw("GET", path: "api/crypt", body: nil)
        try check(status, data)
        let list = try decoder.decode(CryptList.self, from: data)
        let entries = list.entries.map { e in
            CryptEntry(
                slug: e.countdown.slug, title: e.countdown.title, details: e.countdown.details,
                category: e.countdown.category ?? "", target: e.countdown.floating.flatMap(RemoteCountdown.localDate) ?? e.countdown.targetDate,
                floating: e.countdown.floating != nil,
                scene: e.countdown.style?.background?.scene.flatMap { SceneID(rawValue: $0._0) },
                memberCount: e.memberCount
            )
        }
        return (list.categories, entries)
    }
}
