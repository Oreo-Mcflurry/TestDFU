//
//  ContentView.swift
//  TestDFU
//
//  Created by A_Mcflurry on 12/11/24.
//

import SwiftUI

struct ContentView: View {
    
    var body: some View {
        FirmwareUpdateView()
    }
}

#Preview {
    ContentView()
}

import SwiftUI
import CoreBluetooth
import iOSMcuManagerLibrary
import UniformTypeIdentifiers
import Combine

class FirmwareUpdateViewModel: ObservableObject {
    @Published var isScanning = false
    @Published var isUpdateInProgress = false
    @Published var selectedDevice: CBPeripheral? = nil
    @Published var selectedFileURL: URL? = nil
    @Published var updateStatus: String = ""
    @Published var showFilePicker = false
    @Published var discoveredPeripherals = [CBPeripheral]()
    
    var cancellables = Set<AnyCancellable>()
    
    var bluetoothManager = BluetoothFirmwareManager.shared
    
    init() {
        bluetoothManager.discoverdPeripheralsSubject
            .sink { [weak self] peripherals in
                self?.discoveredPeripherals = peripherals
            }.store(in: &cancellables)
    }
    
    func scanForDevices() {
        isScanning = true
        updateStatus = "Scanning for devices..."
        
        bluetoothManager.scanForDevices { _ in }
    }
    
    func selectFirmwareFile() {
        // In SwiftUI, we'll use DocumentPickerView instead
        showFilePicker = true
    }
    
    func updateFirmware() {
        guard let device = selectedDevice, let fileURL = selectedFileURL else {
            updateStatus = "Please select a device and firmware file"
            return
        }
        
        isUpdateInProgress = true
        updateStatus = "Starting firmware update..."
        
        bluetoothManager.updateFirmware(
            peripheral: device,
            fileURL: fileURL
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.isUpdateInProgress = false
                switch result {
                case .success:
                    self?.updateStatus = "Firmware update successful!"
                case .failure(let error):
                    self?.updateStatus = "Update failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct DocumentPickerView: UIViewControllerRepresentable {
    @Binding var selectedURL: URL?
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [
                .zip,
                .init(filenameExtension: "bin")!,
                .init(filenameExtension: "suit")!
            ],
            asCopy: true
        )
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPickerView
        
        init(_ parent: DocumentPickerView) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.selectedURL = urls.first
            parent.isPresented = false
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}

struct FirmwareUpdateView: View {
    @StateObject private var viewModel = FirmwareUpdateViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Firmware Update")
                .font(.title)
            
            // Device Scanning Section
            Button(action: viewModel.scanForDevices) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text(viewModel.isScanning ? "Scanning..." : "Scan Devices")
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(viewModel.isScanning)
            
            // Selected Device Display
            if let device = viewModel.selectedDevice {
                Text("Selected Device: \(device.name ?? "Unknown")")
                    .foregroundColor(.green)
            }
            
            // Firmware File Selection
            Button(action: viewModel.selectFirmwareFile) {
                HStack {
                    Image(systemName: "doc")
                    Text(viewModel.selectedFileURL != nil ?
                         "Change Firmware File" : "Select Firmware File")
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            
            // Selected File Display
            if let fileURL = viewModel.selectedFileURL {
                Text("Selected File: \(fileURL.lastPathComponent)")
                    .foregroundColor(.green)
            }
            
            // Update Button
            Button(action: viewModel.updateFirmware) {
                HStack {
                    Image(systemName: "arrow.up.circle")
                    Text("Update Firmware")
                }
                .padding()
                .background(viewModel.selectedDevice != nil && viewModel.selectedFileURL != nil ?
                            Color.green : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(viewModel.selectedDevice == nil ||
                      viewModel.selectedFileURL == nil ||
                      viewModel.isUpdateInProgress)
            
            // Status Message
            ForEach(viewModel.discoveredPeripherals, id: \.self) { periphral in
                Button {
                    viewModel.bluetoothManager.connect(to: periphral)
                    viewModel.selectedDevice = periphral
                } label: {
                    Text(periphral.name ?? "Unknown")
                }
            }
        }
        .padding()
        .sheet(isPresented: $viewModel.showFilePicker) {
            DocumentPickerView(
                selectedURL: $viewModel.selectedFileURL,
                isPresented: $viewModel.showFilePicker
            )
        }
    }
}
