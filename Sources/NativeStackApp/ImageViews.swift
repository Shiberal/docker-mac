import SwiftUI
import NativeStackClient
import NativeStackCore

struct ImageListView: View {
    let images: [ImageRecord]
    @Binding var selectedID: ImageRecord.ID?

    var body: some View {
        Group {
            if images.isEmpty {
                ContentUnavailableView(
                    "No images",
                    systemImage: "cube",
                    description: Text("Pull an image with the toolbar button or `nativestack image pull`.")
                )
            } else {
                Table(images, selection: $selectedID) {
                    TableColumn("Repository") { image in
                        Text(image.repository)
                    }
                    TableColumn("Tag") { image in
                        Text(image.tag)
                    }
                    TableColumn("ID") { image in
                        Text(String(image.id.prefix(12)))
                            .font(.caption.monospaced())
                    }
                    TableColumn("Size") { image in
                        if let size = image.sizeBytes {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        } else {
                            Text("—")
                        }
                    }
                }
            }
        }
        .navigationTitle("Images")
    }
}

struct ImageDetailView: View {
    @Environment(ContainerService.self) private var service
    let image: ImageRecord

    var body: some View {
        Form {
            Section("Image") {
                CopyableRow(label: "Reference", value: image.reference)
                CopyableRow(label: "ID", value: image.id)
                if let size = image.sizeBytes {
                    LabeledContent(
                        "Size",
                        value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                    )
                }
            }

            Section {
                Button("Remove Image", role: .destructive) {
                    Task { try? await service.removeImage(id: image.id) }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(image.reference)
    }
}
