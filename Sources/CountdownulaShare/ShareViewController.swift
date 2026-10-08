import PDFKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Vision

/// "Count Downcula" in the share sheet: turns a ticket, invite, confirmation or screenshot into a
/// countdown. Everything runs on the device. The person checks the draft before it's added.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let root = ShareView(model: model) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        let host = UIHostingController(rootView: root.tint(.countdownulaBlood))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        Task { await model.read(providers) }
    }
}

@MainActor
@Observable
final class ShareModel {
    enum Phase { case reading, ready, added }

    var phase = Phase.reading
    var draft = CountdownDraft(title: "", date: nil, place: nil, scene: .midnight)
    var date = Date() + 7 * 86_400
    var usedModel = false

    func read(_ providers: [NSItemProvider]) async {
        let text = await SharedText.collect(from: providers)
        let extracted = await DraftReader.read(text)
        draft = extracted.draft
        usedModel = extracted.usedModel
        if let found = extracted.draft.date { date = found }
        phase = .ready
    }

    func add() {
        var confirmed = draft
        confirmed.date = date
        confirmed.title = confirmed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        DraftHandoff.add(confirmed)
        phase = .added
    }
}

/// The text inside whatever was shared: recognized text from an image, a PDF's text, or the text
/// or link itself.
enum SharedText {
    static func collect(from providers: [NSItemProvider]) async -> String {
        var pieces: [String] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier),
               let data = try? await loadData(provider, type: .pdf),
               let text = PDFDocument(data: data)?.string {
                pieces.append(text)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                      let data = try? await loadData(provider, type: .image),
                      let image = UIImage(data: data)?.cgImage {
                pieces.append(await recognize(image))
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                      let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                pieces.append(url.absoluteString)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                      let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                pieces.append(text)
            }
        }
        // Enough for any ticket; keeps the model's prompt small.
        return String(pieces.joined(separator: "\n").prefix(4_000))
    }

    private static func loadData(_ provider: NSItemProvider, type: UTType) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(for: type) { data, error in
                if let data { continuation.resume(returning: data) } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    /// On-device text recognition, line by line.
    static func recognize(_ image: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation] ?? []).compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(cgImage: image).perform([request])
            } catch {
                continuation.resume(returning: "")
            }
        }
    }
}

struct ShareView: View {
    @Bindable var model: ShareModel
    let done: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .reading:
                    ProgressView("Reading it…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .ready:
                    form
                case .added:
                    ContentUnavailableView {
                        Label("Added", systemImage: "checkmark.circle.fill")
                    } description: {
                        Text("“\(model.draft.title)” is waiting in Count Downcula. Open the app to see it.")
                    } actions: {
                        Button("Done", action: done).buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("New Countdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.phase == .ready {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: done)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") { model.add() }
                            .disabled(model.draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                SceneArt(scene: model.draft.scene)
                    .frame(height: 120)
                    .overlay(alignment: .bottomLeading) {
                        Text(model.draft.title.isEmpty ? "New Countdown" : model.draft.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .shadow(radius: 6)
                            .padding(12)
                    }
                    .listRowInsets(EdgeInsets())
            }
            Section {
                TextField("Title", text: $model.draft.title)
                DatePicker("When", selection: $model.date, displayedComponents: [.date, .hourAndMinute])
                TextField("Where", text: Binding(get: { model.draft.place ?? "" },
                                                 set: { model.draft.place = $0.isEmpty ? nil : $0 }))
                Picker("Scene", selection: $model.draft.scene) {
                    ForEach(SceneID.allCases) { Text($0.name).tag($0) }
                }
            } footer: {
                Text(model.draft.date == nil
                     ? "Couldn't find a date in it. Pick one, and check the title."
                     : "Check it looks right. It's read on your device and never leaves it.")
            }
        }
    }
}
