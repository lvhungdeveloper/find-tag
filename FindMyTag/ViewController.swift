import UIKit
import NearbyInteraction
import CoreBluetooth
import simd
import os

// MARK: - BLE UUIDs
struct TransferService {
    static let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let rxCharacteristicUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    static let txCharacteristicUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
}

enum MessageId: UInt8 {
    case accessoryConfigurationData = 0x1
    case accessoryUwbDidStart = 0x2
    case accessoryUwbDidStop = 0x3
    case initialize = 0xA
    case configureAndStart = 0xB
    case stop = 0xC
}

class ViewController: UIViewController {
    // MARK: - Configuration
    // TODO: Replace with device ID from your server
    let TARGET_DEVICE_NAME = "4423"  // 🔧 HARDCODED - Change this to your device name
    
    // MARK: - BLE + UWB
    var centralManager: CBCentralManager!
    var peripheral: CBPeripheral?
    var rxCharacteristic: CBCharacteristic?
    var txCharacteristic: CBCharacteristic?

    var discoveredPeripheralName: String?
    var discoveredPeripherals: [(CBPeripheral, String)] = []

    var niSession = NISession()
    var configuration: NINearbyAccessoryConfiguration?
    var accessoryMap = [NIDiscoveryToken: String]()
    var lastUpdateTime: Date?
    var isSessionRunning = false
    var currentAccessoryName: String?
    
    // MARK: - UI Elements
    let connectionLabel = UILabel()
    let uwbStateLabel = UILabel()
    let infoLabel = UILabel()
    let distanceLabel = UILabel()
    let logoLabel = UILabel()
    let findButton = UIButton(type: .system)
    let runSessionButton = UIButton(type: .system)
    
    // Direction finding view (fullscreen, like Find My)
    let directionView = DirectionView()
    let directionBackButton = UIButton(type: .system)

    let logger = Logger(subsystem: "com.findmy.aletag", category: "ViewController")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        centralManager = CBCentralManager(delegate: self, queue: nil)
        niSession.delegate = self

        setupUI()
    }

    func setupUI() {
        logoLabel.text = "FindMy AleTag"
        logoLabel.font = UIFont.boldSystemFont(ofSize: 28)
        logoLabel.textColor = .systemBlue
        logoLabel.textAlignment = .center

        connectionLabel.text = "Connection State: Not Connected"
        connectionLabel.textColor = .systemBlue
        connectionLabel.isUserInteractionEnabled = true
        let tapConnect = UITapGestureRecognizer(target: self, action: #selector(handleConnectionTap))
        connectionLabel.addGestureRecognizer(tapConnect)

        uwbStateLabel.text = "Accessory UWB state: OFF"
        uwbStateLabel.textColor = .systemBlue

        infoLabel.textColor = .systemBlue
        infoLabel.numberOfLines = 0
        infoLabel.textAlignment = .center

        distanceLabel.textColor = .systemBlue
        distanceLabel.numberOfLines = 0
        distanceLabel.textAlignment = .center
        
        // Find button (like Find My app)
        findButton.setTitle("🧭 Find", for: .normal)
        findButton.setTitleColor(.white, for: .normal)
        findButton.backgroundColor = .systemGreen
        findButton.layer.cornerRadius = 8
        findButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 32, bottom: 12, right: 32)
        findButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        findButton.isHidden = true // Hide until session starts
        findButton.addTarget(self, action: #selector(showDirectionView), for: .touchUpInside)

        runSessionButton.setTitle("Start Session", for: .normal)
        runSessionButton.setTitleColor(.white, for: .normal)
        runSessionButton.backgroundColor = .systemRed
        runSessionButton.layer.cornerRadius = 8
        runSessionButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        runSessionButton.isEnabled = false
        runSessionButton.alpha = 0.5
        runSessionButton.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [logoLabel, connectionLabel, uwbStateLabel, infoLabel, distanceLabel, findButton, runSessionButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])
        
        // Setup direction finding view (fullscreen overlay)
        setupDirectionView()
    }
    
    func setupDirectionView() {
        // Direction view setup (hidden by default) - Green background like Find My
        directionView.translatesAutoresizingMaskIntoConstraints = false
        directionView.isHidden = true
        directionView.alpha = 0
        view.addSubview(directionView)
        
        // Close button (X like Find My)
        directionBackButton.setTitle("✕", for: .normal)
        directionBackButton.titleLabel?.font = UIFont.systemFont(ofSize: 28, weight: .regular)
        directionBackButton.setTitleColor(.white, for: .normal)
        directionBackButton.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        directionBackButton.layer.cornerRadius = 25
        directionBackButton.translatesAutoresizingMaskIntoConstraints = false
        directionBackButton.addTarget(self, action: #selector(hideDirectionView), for: .touchUpInside)
        directionView.addSubview(directionBackButton)
        
        NSLayoutConstraint.activate([
            directionView.topAnchor.constraint(equalTo: view.topAnchor),
            directionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            directionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            directionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Close button at bottom center (like Find My) - moved higher to not overlap hint text
            directionBackButton.centerXAnchor.constraint(equalTo: directionView.centerXAnchor),
            directionBackButton.bottomAnchor.constraint(equalTo: directionView.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            directionBackButton.widthAnchor.constraint(equalToConstant: 50),
            directionBackButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    @objc func showDirectionView() {
        // Set tag name
        if let name = currentAccessoryName {
            directionView.setTagName(name)
        }
        
        // Reset tracking for fresh start
        directionView.resetTracking()
        
        directionView.isHidden = false
        UIView.animate(withDuration: 0.3) {
            self.directionView.alpha = 1
        }
    }
    
    @objc func hideDirectionView() {
        UIView.animate(withDuration: 0.3) {
            self.directionView.alpha = 0
        } completion: { _ in
            self.directionView.isHidden = true
        }
    }

    @objc func handleConnectionTap() {
        if peripheral != nil {
            let alert = UIAlertController(title: "Disconnect", message: "Do you want to disconnect from the accessory?", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Disconnect", style: .destructive, handler: { _ in
                self.centralManager.cancelPeripheralConnection(self.peripheral!)
                self.peripheral = nil
                self.connectionLabel.text = "Connection State: Not Connected"
                self.runSessionButton.isEnabled = false
                self.runSessionButton.alpha = 0.5
                self.distanceLabel.text = ""
                self.findButton.isHidden = true
                self.hideDirectionView()
            }))
            present(alert, animated: true)
        } else {
            if discoveredPeripherals.isEmpty {
                updateInfo("No devices found. Make sure your tag is on.")
                return
            }
            let alert = UIAlertController(title: "Select Device", message: nil, preferredStyle: .actionSheet)
            for (device, name) in discoveredPeripherals {
                alert.addAction(UIAlertAction(title: name, style: .default, handler: { _ in
                    self.centralManager.connect(device, options: nil)
                }))
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alert, animated: true)
        }
    }

    @objc func buttonTapped() {
        guard peripheral != nil else { return }

        if isSessionRunning {
        // Gửi stop (0xC)
        let stopMsg = Data([MessageId.stop.rawValue])
        sendData(stopMsg)
        niSession.invalidate()
        isSessionRunning = false
        runSessionButton.setTitle("Start Session", for: .normal)
        updateInfo("Sent stop session")

        uwbStateLabel.text = "Accessory UWB state: OFF"
        distanceLabel.text = ""
        findButton.isHidden = true
        hideDirectionView()
        } else {
            // Gửi initialize (0xA)
            let initMsg = Data([MessageId.initialize.rawValue])
            sendData(initMsg)
            updateInfo("Sent initialize request")
        }
    }


    func sendData(_ data: Data) {
        guard let peripheral = peripheral, 
        peripheral.state == .connected,
        let rx = rxCharacteristic else {
            updateInfo("❌ Cannot send data – peripheral not connected")
            return
        }

        peripheral.writeValue(data, for: rx, type: .withResponse)
    }

    func accessorySharedData(data: Data, accessoryName: String) {
        guard let messageId = data.first else {
            updateInfo("Empty data")
            return
        }
        guard let messageId = MessageId(rawValue: data.first!) else {
            updateInfo("Invalid messageId")
            return
        }
        switch messageId {
        case .accessoryConfigurationData:
            let configData = data.advanced(by: 1)
            do {
                configuration = try NINearbyAccessoryConfiguration(data: configData)
                cacheToken(configuration!.accessoryDiscoveryToken, accessoryName: accessoryName)
                
                niSession = NISession()
                niSession.delegate = self
                niSession.run(configuration!)
                
                isSessionRunning = true
                currentAccessoryName = accessoryName
                runSessionButton.setTitle("End Session", for: .normal)
                updateInfo("\(accessoryName) connected.\nUWB session running")
                
                // Show Find button
                findButton.isHidden = false
            } catch {
                updateInfo("Invalid config data: \(error)")
            }
        case .accessoryUwbDidStart:
            updateInfo("UWB Started signal received")
            uwbStateLabel.text = "Accessory UWB state: ON"
        case .accessoryUwbDidStop:
            updateInfo("UWB Stopped signal received")
            uwbStateLabel.text = "Accessory UWB state: OFF"
        default:
            break
        }
    }

    func cacheToken(_ token: NIDiscoveryToken, accessoryName: String) {
        accessoryMap[token] = accessoryName
    }

    func updateInfo(_ text: String) {
        infoLabel.text = text
        logger.info("\(text)")
    }
}

// MARK: - CBCentralManagerDelegate
extension ViewController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: [TransferService.serviceUUID], options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? "Unnamed Device"
        if !discoveredPeripherals.contains(where: { $0.0.identifier == peripheral.identifier }) {
            discoveredPeripherals.append((peripheral, name))
        }
        
        // 🔥 AUTO-CONNECT: Connect to target device automatically
        if name == TARGET_DEVICE_NAME && self.peripheral == nil {
            logger.info("🎯 Found target device: \(name) - Auto-connecting...")
            updateInfo("Found \(name) - Connecting...")
            central.stopScan()  // ✅ Correct method name
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        self.peripheral = peripheral
        self.discoveredPeripheralName = peripheral.name ?? "Accessory"
        peripheral.delegate = self
        peripheral.discoverServices([TransferService.serviceUUID])
        
        let tagName = peripheral.name ?? "Tag"
        connectionLabel.text = "Connection State: Connected"
        updateInfo("The tag \(tagName) is connected")
        
        runSessionButton.isEnabled = true
        runSessionButton.alpha = 1.0
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        updateInfo("Peripheral disconnected")
        self.peripheral = nil
        self.rxCharacteristic = nil
        self.txCharacteristic = nil
        self.isSessionRunning = false

        connectionLabel.text = "Connection State: Not Connected"
        runSessionButton.setTitle("Start Session", for: .normal)
        runSessionButton.isEnabled = false
        runSessionButton.alpha = 0.5
        uwbStateLabel.text = "Accessory UWB state: OFF"
        distanceLabel.text = ""
        findButton.isHidden = true
        hideDirectionView()
    }
}

// MARK: - CBPeripheralDelegate
extension ViewController: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == TransferService.serviceUUID {
            peripheral.discoverCharacteristics([TransferService.rxCharacteristicUUID, TransferService.txCharacteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for char in service.characteristics ?? [] {
            if char.uuid == TransferService.rxCharacteristicUUID {
                rxCharacteristic = char
            } else if char.uuid == TransferService.txCharacteristicUUID {
                txCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }

        // ✅ Thêm log BLE nhận được tại đây
        print("🔁 BLE received:", data.map { String(format: "%02X", $0) }.joined(separator: " "))

        if let name = discoveredPeripheralName {
            accessorySharedData(data: data, accessoryName: name)
        }
    }
}

// MARK: - NISessionDelegate
extension ViewController: NISessionDelegate {
    func session(_ session: NISession, didGenerateShareableConfigurationData shareableConfigurationData: Data, for object: NINearbyObject) {
        guard object.discoveryToken == configuration?.accessoryDiscoveryToken else { return }
        var msg = Data([MessageId.configureAndStart.rawValue])
        msg.append(shareableConfigurationData)
        sendData(msg)
        updateInfo("Sent UWB config")
    }

    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let obj = nearbyObjects.first else { return }

        if let name = accessoryMap[obj.discoveryToken] {
            let now = Date()
            var intervalText = ""
            var intervalEmoji = ""

            if let last = lastUpdateTime {
                let interval = now.timeIntervalSince(last)
                
                // Classify update rate quality
                if interval < 0.1 {
                    intervalEmoji = "🟢" // Excellent: < 100ms
                } else if interval < 0.2 {
                    intervalEmoji = "🟡" // Good: 100-200ms
                } else {
                    intervalEmoji = "🔴" // Slow: > 200ms
                }
                
                intervalText = String(format: "%@ %.0f ms", intervalEmoji, interval * 1000)
            }

            lastUpdateTime = now

            // Update distance label on main screen (show 0.0m if negative)
            if let distance = obj.distance {
                let displayDistance = max(distance, 0.0)  // Clamp to 0 minimum
                distanceLabel.text = String(format: "%@ is %.2f m\n%@", name, displayDistance, intervalText)
            } else {
                distanceLabel.text = String(format: "%@\n%@", name, intervalText)
            }
            
            // 🔍 DEBUG LOG: Log distance and direction data
            logger.info("📊 UWB Data:")
            if let distance = obj.distance {
                let displayDistance = max(distance, 0.0)  // Clamp to 0 minimum
                logger.info("  Distance: \(String(format: "%.2f", displayDistance)) m ✅")
            } else {
                logger.info("  Distance: nil ❌")
            }
            
            if let direction = obj.direction {
                logger.info("  Direction: x=\(String(format: "%.3f", direction.x)), y=\(String(format: "%.3f", direction.y)), z=\(String(format: "%.3f", direction.z)) ✅")
                
                // Calculate angle and magnitude for debugging
                let angle = atan2(direction.x, -direction.z)
                let degrees = angle * 180.0 / Float.pi
                let horizontalMagnitude = sqrt(direction.x * direction.x + direction.z * direction.z)
                
                logger.info("  Calculated Angle: \(String(format: "%.1f", degrees))° | H-Mag: \(String(format: "%.3f", horizontalMagnitude))")
            } else {
                logger.info("  Direction: nil ❌")
            }
            
            // Update direction view if it's visible
            if !directionView.isHidden {
                if let direction = obj.direction {
                    // UWB direction is RELATIVE to device - no heading adjustment needed
                    directionView.updateDirection(direction: direction, distance: obj.distance, deviceHeading: nil)
                    directionView.showHasDirection()
                } else {
                    // Direction is nil - update distance but keep arrow dim
                    directionView.updateDistanceOnly(distance: obj.distance)
                    directionView.showNoDirection()
                }
            }
        }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        updateInfo("NI session invalidated: \(error.localizedDescription)")
        niSession = NISession()
        niSession.delegate = self
    }
}
