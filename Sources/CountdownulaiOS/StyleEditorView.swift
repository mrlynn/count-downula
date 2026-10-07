import PhotosUI
import SwiftUI

/// Background, font and colors for one countdown, with a live preview on top.
struct StyleEditorView: View {
    let draft: Countdown
    @Binding var style: CountdownStyle
    @Binding var previewImage: UIImage?
    @Binding var imageUpdate: ImageUpdate
    @Binding var isLoadingPhoto: Bool

    @State private var tab: BackgroundTab
    @State private var photoItem: PhotosPickerItem?

    enum BackgroundTab: String, CaseIterable, Identifiable {
        case photo = "Photo", scene = "Scenes", gradient = "Gradient", color = "Color"
        var id: String { rawValue }
    }

    init(draft: Countdown, style: Binding<CountdownStyle>, previewImage: Binding<UIImage?>,
         imageUpdate: Binding<ImageUpdate>, isLoadingPhoto: Binding<Bool>) {
        self.draft = draft
        _style = style
        _previewImage = previewImage
        _imageUpdate = imageUpdate
        _isLoadingPhoto = isLoadingPhoto
        let tab: BackgroundTab = switch style.wrappedValue.background {
        case .automatic: previewImage.wrappedValue == nil ? .scene : .photo
        case .photo: .photo
        case .scene: .scene
        case .gradient: .gradient
        case .solid: .color
        }
        _tab = State(initialValue: tab)
    }

    private var preview: Countdown {
        var countdown = draft
        countdown.style = style
        countdown.hasImage = previewImage != nil
        return countdown
    }

    var body: some View {
        Form {
            Section {
                StyledCountdownCard(countdown: preview, now: Date(), previewImage: previewImage, height: 220)
                    .overlay {
                        if isLoadingPhoto { ProgressView().controlSize(.large).tint(.white) }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Background") {
                Picker("Background", selection: $tab) {
                    ForEach(BackgroundTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                switch tab {
                case .photo: photoPicker
                case .scene: sceneGrid
                case .gradient: gradientPicker
                case .color: colorPicker
                }
            }

            Section("Font") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(CountdownStyle.FontDesign.allCases) { design in
                            fontChip(design)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Picker("Weight", selection: $style.weight) {
                    ForEach(CountdownStyle.FontWeight.allCases) { Text($0.name).tag($0) }
                }
            }

            Section {
                ColorPicker("Text", selection: Binding(
                    get: { style.foregroundColor },
                    set: { style.textColor = RGBAColor($0) }
                ), supportsOpacity: false)
                ColorPicker("Accent", selection: Binding(
                    get: { style.accentColor },
                    set: { style.accent = RGBAColor($0) }
                ), supportsOpacity: false)
            } header: {
                Text("Colors")
            } footer: {
                Text("The accent colors the dial, progress bars and badges.")
            }

            Section {
                Button("Reset to Default Style", role: .destructive) {
                    style = .default
                    tab = previewImage == nil ? .scene : .photo
                }
                .disabled(style == .default)
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            loadPhoto(item)
        }
    }

    // MARK: - Background pickers

    @ViewBuilder
    private var photoPicker: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            Label(previewImage == nil ? "Choose a Photo" : "Replace Photo", systemImage: "photo.on.rectangle")
        }
        if previewImage != nil {
            if !style.background.usesPhoto {
                Button("Use This Photo", systemImage: "checkmark.circle") { style.background = .photo }
            }
            Button("Remove Photo", systemImage: "trash", role: .destructive) {
                previewImage = nil
                photoItem = nil
                imageUpdate = .remove
                if style.background.usesPhoto { style.background = .automatic }
            }
        }
    }

    private var sceneGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
            ForEach(SceneID.allCases) { scene in
                swatch(isSelected: style.background == .scene(scene), label: scene.name) {
                    SceneArt(scene: scene)
                } action: {
                    style.background = .scene(scene)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var gradientPicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 10)], spacing: 10) {
            ForEach(GradientSpec.presets, id: \.name) { preset in
                swatch(isSelected: style.background == .gradient(preset.spec), label: preset.name, height: 54) {
                    preset.spec.linearGradient
                } action: {
                    style.background = .gradient(preset.spec)
                }
            }
        }
        .padding(.vertical, 4)

        if case let .gradient(spec) = style.background {
            ColorPicker("Start", selection: gradientStop(0, of: spec), supportsOpacity: false)
            ColorPicker("End", selection: gradientStop(spec.stops.count - 1, of: spec), supportsOpacity: false)
            LabeledContent("Angle") {
                Slider(value: Binding(
                    get: { spec.angle },
                    set: { var s = spec; s.angle = $0; style.background = .gradient(s) }
                ), in: 0...360)
                .frame(maxWidth: 200)
            }
        }
    }

    @ViewBuilder
    private var colorPicker: some View {
        let swatches: [UInt32] = [0x14080C, 0x7A0F23, 0xD9213A, 0xF28C28, 0xF2C94C, 0x2F9E6E,
                                  0x1F6FB2, 0x5B3E96, 0xF4EDE1, 0x2B2B2B]
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], spacing: 10) {
            ForEach(swatches, id: \.self) { hex in
                let color = RGBAColor(hex: hex)
                Button {
                    style.background = .solid(color)
                    // Light backgrounds read better with dark text.
                    if style.textColor == nil, color.luminance > 0.7 { style.textColor = RGBAColor(hex: 0x1C1C1E) }
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 40, height: 40)
                        .overlay { Circle().strokeBorder(.secondary.opacity(0.3)) }
                        .overlay {
                            if style.background == .solid(color) {
                                Image(systemName: "checkmark").font(.headline)
                                    .foregroundStyle(color.luminance > 0.6 ? .black : .white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color \(String(hex, radix: 16))")
            }
        }
        .padding(.vertical, 4)

        ColorPicker("Custom", selection: Binding(
            get: { if case let .solid(c) = style.background { c.color } else { .countdownulaBlood } },
            set: { style.background = .solid(RGBAColor($0)) }
        ), supportsOpacity: false)
    }

    private func gradientStop(_ index: Int, of spec: GradientSpec) -> Binding<Color> {
        Binding(
            get: { spec.stops[index].color },
            set: { var s = spec; s.stops[index] = RGBAColor($0); style.background = .gradient(s) }
        )
    }

    private func swatch<Content: View>(isSelected: Bool, label: String, height: CGFloat = 70,
                                       @ViewBuilder content: () -> Content, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                content()
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isSelected ? style.accentColor : .clear, lineWidth: 3)
                    }
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func fontChip(_ design: CountdownStyle.FontDesign) -> some View {
        var sample = style
        sample.font = design
        let isSelected = style.font == design
        return Button {
            style.font = design
        } label: {
            VStack(spacing: 2) {
                // Letters show the difference between designs far better than digits do.
                Text("Ag")
                    .font(sample.font(size: 28))
                Text(design.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 72, height: 64)
            .background(Color.primary.opacity(isSelected ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? style.accentColor : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(design.name) font")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Photo

    private func loadPhoto(_ item: PhotosPickerItem) {
        isLoadingPhoto = true
        Task {
            defer { isLoadingPhoto = false }
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            let prepared = await Task.detached(priority: .userInitiated) { PhoneStore.prepareImage(data) }.value
            guard let prepared else { return }
            previewImage = prepared.preview
            imageUpdate = prepared.update
            style.background = .photo
        }
    }
}
