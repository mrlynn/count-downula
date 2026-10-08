import Foundation

/// What a save does to a countdown's photo.
enum ImageUpdate {
    case unchanged
    case remove
    case set(image: Data, thumbnail: Data)
}
