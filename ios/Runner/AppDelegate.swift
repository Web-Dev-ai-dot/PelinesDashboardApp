import Flutter
import UIKit
import AVFAudio
import CoreHaptics

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var orderFeedback: OrderAlertFeedback?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    orderFeedback?.dispose()
    orderFeedback = OrderAlertFeedback(
      messenger: engineBridge.applicationRegistrar.messenger()
    )
  }
}

/// Finite foreground effects. No background audio mode or notification service.
private final class OrderAlertFeedback: NSObject, AVAudioPlayerDelegate {
  private let channel: FlutterMethodChannel
  private var player: AVAudioPlayer?
  private var engine: CHHapticEngine?
  private var hapticPlayer: CHHapticPatternPlayer?
  private var observers: [NSObjectProtocol] = []
  private var pulseUntil: TimeInterval = 0
  private var patternGeneration: UInt64 = 0
  private var playerGeneration: UInt64 = 0
  private var remainingSounds = 0
  private var pendingDing: DispatchWorkItem?
  private var foreground = UIApplication.shared.applicationState == .active

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.pelines.admin/order_alert_sound", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "play":
        let arguments = call.arguments as? [String: Any]
        self.play(soundCount: arguments?["soundCount"] as? Int ?? 1)
        result(nil)
      case "stop": self.stop(); result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    for name in [UIApplication.willResignActiveNotification,
                 UIApplication.didEnterBackgroundNotification,
                 UIScene.willDeactivateNotification] {
      observers.append(NotificationCenter.default.addObserver(
        forName: name, object: nil, queue: .main
      ) { [weak self] _ in
        self?.foreground = false
        self?.stop()
      })
    }
    for name in [UIApplication.didBecomeActiveNotification, UIScene.didActivateNotification] {
      observers.append(NotificationCenter.default.addObserver(
        forName: name, object: nil, queue: .main
      ) { [weak self] _ in self?.foreground = true })
    }
    observers.append(NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.stop() })
    observers.append(NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
    ) { [weak self] notification in
      let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
      // Setting our own ambient category can also emit route changes.
      if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
        self?.stop()
      }
    })
  }

  private func play(soundCount: Int) {
    guard foreground, UIApplication.shared.applicationState == .active,
          remainingSounds == 0,
          ProcessInfo.processInfo.systemUptime >= pulseUntil,
          player?.isPlaying != true else { return }
    stop()
    remainingSounds = min(3, max(1, soundCount))
    pulseUntil = ProcessInfo.processInfo.systemUptime + 0.55
    let session = AVAudioSession.sharedInstance()
    do {
      // Ambient respects Silent and mixes with existing audio.
      try session.setCategory(.ambient, mode: .default)
      try session.setActive(true)
    } catch { remainingSounds = 0; return }
    playDing(token: patternGeneration)
    guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
    do {
      let haptics = try CHHapticEngine(audioSession: session)
      haptics.isAutoShutdownEnabled = true
      engine = haptics
      // Do not restart engines from late callbacks or interruptions.
      try haptics.start()
      let events = [0.0, 0.35].map {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
          CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
          CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
        ], relativeTime: $0)
      }
      let pattern = try CHHapticPattern(events: events, parameters: [])
      let effect = try haptics.makePlayer(with: pattern)
      hapticPlayer = effect
      try effect.start(atTime: CHHapticTimeImmediate)
    } catch {
      try? hapticPlayer?.stop(atTime: CHHapticTimeImmediate)
      hapticPlayer = nil
      engine?.stop(completionHandler: nil)
      engine = nil
    }
  }

  private func playDing(token: UInt64) {
    guard token == patternGeneration, remainingSounds > 0,
          foreground, UIApplication.shared.applicationState == .active,
          player == nil else { return }
    do {
      let key = FlutterDartProject.lookupKey(forAsset: "assets/sounds/new_order.wav")
      guard let path = Bundle.main.path(forResource: key, ofType: nil) else {
        remainingSounds = 0
        return
      }
      let audio = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
      audio.numberOfLoops = 0
      audio.delegate = self
      playerGeneration = token
      player = audio
      audio.prepareToPlay()
      if !audio.play() { finishDing(audio, success: false) }
    } catch {
      player = nil
      remainingSounds = 0
    }
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    finishDing(player, success: flag)
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    finishDing(player, success: false)
  }

  private func finishDing(_ finished: AVAudioPlayer, success: Bool) {
    guard player === finished, playerGeneration == patternGeneration else { return }
    finished.delegate = nil
    finished.stop()
    player = nil
    remainingSounds = success ? remainingSounds - 1 : 0
    guard remainingSounds > 0 else { return }
    let token = patternGeneration
    let task = DispatchWorkItem { [weak self] in
      guard let self = self, self.patternGeneration == token else { return }
      self.pendingDing = nil
      self.playDing(token: token)
    }
    pendingDing = task
    // A full 350 ms of silence after completion, never overlapping players.
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(350), execute: task)
  }

  private func stop() {
    patternGeneration &+= 1
    remainingSounds = 0
    pendingDing?.cancel()
    pendingDing = nil
    player?.delegate = nil
    player?.stop()
    player = nil
    try? hapticPlayer?.stop(atTime: CHHapticTimeImmediate)
    hapticPlayer = nil
    let oldEngine = engine
    engine = nil
    oldEngine?.stop(completionHandler: nil)
    pulseUntil = 0
  }

  func dispose() {
    channel.setMethodCallHandler(nil)
    stop()
    observers.forEach { NotificationCenter.default.removeObserver($0) }
    observers.removeAll()
  }

  deinit {
    pendingDing?.cancel()
    player?.delegate = nil
    observers.forEach { NotificationCenter.default.removeObserver($0) }
    player?.stop()
    try? hapticPlayer?.stop(atTime: CHHapticTimeImmediate)
    engine?.stop(completionHandler: nil)
  }
}
