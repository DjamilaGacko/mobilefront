import Flutter
import UIKit
import CoreTelephony

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.yele/telephony",
        binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { (call, reply) in
        if call.method == "getTelephony" {
          reply(AppDelegate.telephonyInfo())
        } else {
          reply(FlutterMethodNotImplemented)
        }
      }
    }

    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  /// Retourne { simOperator, mccMnc, cellularTech }.
  /// ⚠️ Depuis iOS 16, le nom de l'opérateur (carrierName) est indisponible
  /// et renvoie "--" : on le filtre et on renvoie null dans ce cas.
  private static func telephonyInfo() -> [String: Any?] {
    var info: [String: Any?] = [
      "simOperator": nil,
      "mccMnc": nil,
      "cellularTech": nil,
    ]

    let networkInfo = CTTelephonyNetworkInfo()

    // Nom opérateur + MCC/MNC (indisponible sur iOS 16+).
    if let carriers = networkInfo.serviceSubscriberCellularProviders {
      for (_, carrier) in carriers {
        if let name = carrier.carrierName, !name.isEmpty, name != "--" {
          info["simOperator"] = name
        }
        if let mcc = carrier.mobileCountryCode, let mnc = carrier.mobileNetworkCode,
           !mcc.isEmpty, !mnc.isEmpty {
          info["mccMnc"] = mcc + mnc
        }
        if info["simOperator"] != nil { break }
      }
    }

    // Techno radio.
    if let techs = networkInfo.serviceCurrentRadioAccessTechnology,
       let raw = techs.values.first {
      info["cellularTech"] = AppDelegate.techLabel(raw)
    }

    return info
  }

  private static func techLabel(_ raw: String) -> String? {
    switch raw {
    case CTRadioAccessTechnologyGPRS,
         CTRadioAccessTechnologyEdge,
         CTRadioAccessTechnologyCDMA1x:
      return "2G"
    case CTRadioAccessTechnologyWCDMA,
         CTRadioAccessTechnologyHSDPA,
         CTRadioAccessTechnologyHSUPA,
         CTRadioAccessTechnologyCDMAEVDORev0,
         CTRadioAccessTechnologyCDMAEVDORevA,
         CTRadioAccessTechnologyCDMAEVDORevB,
         CTRadioAccessTechnologyeHRPD:
      return "3G"
    case CTRadioAccessTechnologyLTE:
      return "4G"
    default:
      if #available(iOS 14.1, *) {
        if raw == CTRadioAccessTechnologyNRNSA || raw == CTRadioAccessTechnologyNR {
          return "5G"
        }
      }
      return nil
    }
  }
}
