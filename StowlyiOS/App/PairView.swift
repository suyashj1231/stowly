import SwiftUI
import VisionKit

/// First run: connect to the Mac by scanning the QR from Stowly's "Connect iPhone…" window,
/// or pasting the address shown under it.
struct PairView: View {
    @Environment(AppModel.self) private var model
    @State private var address = ""
    @State private var scanning = false

    private var canScan: Bool { DataScannerViewController.isSupported }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "laptopcomputer.and.iphone")
                            .font(.system(size: 44))
                            .foregroundStyle(.tint)
                        Text("Connect to your Mac")
                            .font(.largeTitle.bold())
                        Text("Then tap Share → Stowly in Instagram, TikTok, YouTube, LinkedIn or X, and the post lands in Stowly on your Mac.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Step(number: 1, text: "On your Mac, click the Stowly menu bar icon and choose **Connect iPhone…**")
                        Step(number: 2, text: canScan ? "Scan the code it shows." : "Scan the code with the Camera app, or paste the address below.")
                    }

                    if canScan {
                        Button {
                            scanning = true
                        } label: {
                            Label("Scan Code", systemImage: "qrcode.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Or paste the address").font(.subheadline.weight(.medium))
                        HStack {
                            TextField("Address", text: $address, prompt: Text(verbatim: "https://ntfy.sh/stowly-…"))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .submitLabel(.go)
                                .onSubmit { model.pair(with: address) }
                                .textFieldStyle(.roundedBorder)
                            Button("Connect") { model.pair(with: address) }
                                .buttonStyle(.bordered)
                                .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }

                    if let error = model.pairingError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(24)
            }
            .sheet(isPresented: $scanning) {
                QRScannerSheet { payload in
                    if model.pair(with: payload) { scanning = false }
                }
            }
        }
    }
}

private struct Step: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.bold())
                .frame(width: 26, height: 26)
                .background(.tint.opacity(0.15), in: .circle)
                .foregroundStyle(.tint)
            Text(text)
        }
    }
}

/// Live camera QR scanner. Calls `onScan` for each code it sees; the caller dismisses on success.
struct QRScannerSheet: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QRScanner(onScan: onScan)
                .ignoresSafeArea()
                .navigationTitle("Scan the code on your Mac")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
        }
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let code) in addedItems {
                if let payload = code.payloadStringValue { onScan(payload) }
            }
        }
    }
}
