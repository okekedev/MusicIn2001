//
//  Music2001iOSApp.swift
//  Music2001iOS
//
//  Created by Christian Okeke on 1/5/26.
//

import SwiftUI
import AVFoundation

// Setup audio session at app launch - must happen before ANY audio code
private let _audioSessionSetup: Void = {
    do {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
        print("[Music2001] Static init: Audio session configured for background playback")
    } catch {
        print("[Music2001] Static init ERROR: \(error)")
    }
}()

// Lock to portrait mode
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Force audio session setup (already done by static init, but ensure it's called)
        _ = _audioSessionSetup
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .portrait
    }
}

@main
struct Music2001iOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var state = iPodState()

    init() {
        // Ensure audio session is set up before state is created
        _ = _audioSessionSetup
    }

    var body: some Scene {
        WindowGroup {
            ZunePlayerView()
                .environment(state)
        }
    }
}
