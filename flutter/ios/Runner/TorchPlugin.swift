import AVFoundation
import Flutter

/// Torch / flashlight control for remote flashlight toggle (BetterDesk extension).
enum TorchPlugin {
    private static var isFlashlightOn = false

    static func register(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: "com.carriez.flutter_hbb/torch",
            binaryMessenger: messenger
        )
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "set_flashlight":
                let args = call.arguments as? [String: Any]
                let on = (args?["on"] as? Bool) ?? false
                result(setTorch(on: on))
            case "get_flashlight_state":
                result(isFlashlightOn)
            case "has_flashlight":
                result(hasTorchCapability())
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private static func hasTorchCapability() -> Bool {
        guard let device = AVCaptureDevice.default(for: .video) else { return false }
        return device.hasTorch
    }

    private static func setTorch(on: Bool) -> Bool {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            return false
        }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            isFlashlightOn = on
            return true
        } catch {
            return false
        }
    }
}
