// Renders every app scene (Sources/Shared/Scenes.swift) to server/public/scenes/<scene>.jpg, so pages
// without an uploaded backdrop still show the scene. Run after changing a scene:
//   S=$(mktemp -d); swiftc -parse-as-library -O -o $S/render Sources/Shared/Scenes.swift Sources/Shared/CountdownStyle.swift Sources/Shared/FangMark.swift scripts/render-scenes.swift && $S/render server/public/scenes
import AppKit
import SwiftUI

// Renders every SceneArt to a JPEG for the web, at the app's backdrop size.
@main
struct RenderScenes {
    @MainActor static func main() throws {
        let out = URL(fileURLWithPath: CommandLine.arguments[1])
        for scene in SceneID.allCases {
            let renderer = ImageRenderer(content: SceneArt(scene: scene).frame(width: 1080, height: 1350))
            renderer.scale = 1
            guard let cg = renderer.cgImage else { fatalError("render \(scene)") }
            let rep = NSBitmapImageRep(cgImage: cg)
            let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.78])!
            try data.write(to: out.appendingPathComponent("\(scene.rawValue).jpg"))
            print(scene.rawValue, data.count)
        }
    }
}
