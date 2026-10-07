#if DEBUG
import CoreData
import Foundation
import SwiftData

/// Debug-only: pushes every field of the SwiftData model to the CloudKit **Development** schema with
/// `initializeCloudKitSchema()`, so new attributes can then be deployed to Production from the
/// CloudKit Console. Run a signed build signed into iCloud with `-initializeCloudKitSchema`.
/// Uses a throwaway store, so the real one (and its data) is never touched.
enum CloudKitSchemaInitializer {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-initializeCloudKitSchema") else { return }
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: [CountdownRecord.self]) else {
            print("Countdownula schema: couldn't build the managed object model")
            return
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "SchemaInit-\(UUID().uuidString).store")
        let description = NSPersistentStoreDescription(url: url)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: SharedConfig.cloudKitContainer)
        description.shouldAddStoreAsynchronously = false

        let container = NSPersistentCloudKitContainer(name: "Countdownula", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            print("Countdownula schema: store failed to load: \(loadError)")
            return
        }
        do {
            try container.initializeCloudKitSchema()
            print("Countdownula schema: initializeCloudKitSchema succeeded")
        } catch {
            print("Countdownula schema: initializeCloudKitSchema failed: \(error)")
        }
        for store in container.persistentStoreCoordinator.persistentStores {
            try? container.persistentStoreCoordinator.remove(store)
        }
        try? FileManager.default.removeItem(at: url)
    }
}
#endif
