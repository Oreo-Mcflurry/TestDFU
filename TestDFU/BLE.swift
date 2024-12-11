//
//  BLE.swift
//  TestDFU
//
//  Created by A_Mcflurry on 12/11/24.
//

import Foundation
import CoreBluetooth
import iOSMcuManagerLibrary
import UniformTypeIdentifiers
import UIKit
import Combine

class BluetoothFirmwareManager: NSObject {
    // Singleton instance
    static let shared = BluetoothFirmwareManager()
    
    // Central Manager for Bluetooth scanning and connection
    private var centralManager: CBCentralManager!
    var discoverdPeripheralsSubject = CurrentValueSubject<[CBPeripheral], Never>([])
    
    // Current connected peripheral
    private var connectedPeripheral: CBPeripheral?
    
    // Firmware Upgrade Manager
    private var firmwareUpgradeManager: FirmwareUpgradeManager?
    
    // Completion handlers
    private var scanCompletionHandler: ((CBPeripheral?) -> Void)?
    private var firmwareUpdateHandler: ((Result<Void, Error>) -> Void)?
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }
    
    // Scan for Bluetooth devices
    func scanForDevices(withServiceUUID serviceUUID: CBUUID?,
                        timeout: TimeInterval = 10,
                        completion: @escaping (CBPeripheral?) -> Void) {
        guard centralManager.state == .poweredOn else {
            completion(nil)
            return
        }
        
        scanCompletionHandler = completion
        
        // Start scanning
        if let serviceUUID = serviceUUID {
            centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
        } else {
            centralManager.scanForPeripherals(withServices: nil, options: nil)
        }
        
        // Set a timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.centralManager.stopScan()
            self?.scanCompletionHandler?(nil)
        }
    }
    
    func connect(to peripheral: CBPeripheral) {
        centralManager.connect(peripheral, options: nil)
    }
    
    // Update Firmware from a file
    func updateFirmware(peripheral: CBPeripheral,
                        fileURL: URL,
                        configuration: FirmwareUpgradeConfiguration? = nil,
                        completion: @escaping (Result<Void, Error>) -> Void) {
        // Ensure we're connected to the peripheral
        guard centralManager.state == .poweredOn else {
            completion(.failure(BluetoothError.bluetoothNotReady))
            return
        }
        
        // Create BLE Transport
        let bleTransport = McuMgrBleTransport(peripheral)
        
        // Create Firmware Upgrade Manager
        let dfuManager = FirmwareUpgradeManager(transport: bleTransport, delegate: self)
        self.firmwareUpgradeManager = dfuManager
        
        // Store completion handler
        firmwareUpdateHandler = completion
        
        do {
            // Create firmware package
            let package = try McuMgrPackage(from: fileURL)
            
            // Start upgrade with optional configuration
            if let config = configuration {
                try dfuManager.start(package: package, using: config)
            } else {
                // Use default configuration
                let defaultConfig = FirmwareUpgradeConfiguration(
                    estimatedSwapTime: 10.0,
                    eraseAppSettings: false,
                    pipelineDepth: 2
                )
                try dfuManager.start(package: package, using: defaultConfig)
            }
        } catch {
            completion(.failure(error))
        }
    }
    
    // File Selection Helper
    func selectFirmwareFile(from viewController: UIViewController,
                            completion: @escaping (URL?) -> Void) {
        let documentPicker = UIDocumentPickerViewController(
            forOpeningContentTypes: [
                .zip,
                .init(filenameExtension: "bin")!,
                .init(filenameExtension: "suit")!
            ],
            asCopy: true
        )
        documentPicker.delegate = self
        documentPicker.modalPresentationStyle = .formSheet
        
        // Store completion handler
        self.fileSelectionCompletion = completion
        
        viewController.present(documentPicker, animated: true)
    }
    
    // Private file selection completion handler
    private var fileSelectionCompletion: ((URL?) -> Void)?
    
    // Error enum for custom errors
    enum BluetoothError: Error {
        case bluetoothNotReady
        case deviceNotConnected
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothFirmwareManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on")
        case .poweredOff:
            print("Bluetooth is powered off")
        case .unsupported:
            print("Bluetooth is not supported")
        default:
            print("Unknown bluetooth state")
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
//        guard let name = peripheral.name, name.contains("Ggrip") else {
//            return
//        }
        // Append the discovered peripheral to the list
        var peripherals = discoverdPeripheralsSubject.value
        if !peripherals.contains(peripheral) {
            peripherals.append(peripheral)
            discoverdPeripheralsSubject.send(peripherals)
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        scanCompletionHandler?(peripheral)
        scanCompletionHandler = nil
        print("Connected to peripheral: \(peripheral.name ?? "Unknown")")
    }
    
    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        scanCompletionHandler?(nil)
        scanCompletionHandler = nil
    }
}

// MARK: - UIDocumentPickerDelegate
extension BluetoothFirmwareManager: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        guard let fileURL = urls.first else {
            fileSelectionCompletion?(nil)
            return
        }
        fileSelectionCompletion?(fileURL)
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        fileSelectionCompletion?(nil)
    }
}

// MARK: - FirmwareUpgradeDelegate
extension BluetoothFirmwareManager: FirmwareUpgradeDelegate {
    func upgradeDidStart(controller: any iOSMcuManagerLibrary.FirmwareUpgradeController) {
        print("Upgrade started")
    }
    
    func upgradeStateDidChange(from previousState: iOSMcuManagerLibrary.FirmwareUpgradeState, to newState: iOSMcuManagerLibrary.FirmwareUpgradeState) {
        print("Upgrade State Changed: \(newState)")
    }
    
    func upgradeDidFail(inState state: iOSMcuManagerLibrary.FirmwareUpgradeState, with error: any Error) {
        print("Upgrade failed: \(error)")
    }
    
    func upgradeDidCancel(state: iOSMcuManagerLibrary.FirmwareUpgradeState) {
        print("Upgrade cancelled")
    }
    
    func uploadProgressDidChange(bytesSent: Int, imageSize: Int, timestamp: Date) {
        print("Progress: \(bytesSent) / \(imageSize)")
    }
    
    func upgradeStateDidChange(_ state: FirmwareUpgradeState) {
        print("Firmware Upgrade State: \(state)")
    }
    
    func upgradeDidComplete() {
        firmwareUpdateHandler?(.success(()))
        firmwareUpdateHandler = nil
    }
    
    func upgradeDidFail(withError error: Error) {
        firmwareUpdateHandler?(.failure(error))
        firmwareUpdateHandler = nil
    }
}
