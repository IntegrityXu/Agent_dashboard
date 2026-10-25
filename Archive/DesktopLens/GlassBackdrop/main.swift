import AppKit
import SwiftUI

// A temporary, separate-process test backdrop. Status Board captures this real
// native window exactly as it captures any other window behind its panel.
struct Backdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red:0.20,green:0.44,blue:0.92),Color(red:0.52,green:0.67,blue:0.97),Color(red:0.22,green:0.34,blue:0.74)],startPoint:.topLeading,endPoint:.bottomTrailing)
            Ellipse().fill(Color(red:0.98,green:0.79,blue:0.72)).frame(width:750,height:150).rotationEffect(.degrees(24)).offset(x:50,y:15).blur(radius:24)
            Ellipse().fill(Color(red:0.67,green:0.79,blue:1)).frame(width:800,height:140).rotationEffect(.degrees(-25)).offset(x:-45,y:150).blur(radius:20)
            Ellipse().stroke(.white.opacity(0.65),lineWidth:2).frame(width:700,height:300).rotationEffect(.degrees(-20)).offset(x:-80,y:150)
            Ellipse().fill(Color(red:0.25,green:0.46,blue:0.88)).frame(width:650,height:170).rotationEffect(.degrees(28)).offset(x:40,y:-180).blur(radius:12)
        }.clipped()
    }
}
@MainActor
final class Demo: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let target = NSRunningApplication.runningApplications(withBundleIdentifier:"local.statusboard.app").first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]],
              let info = windows.first(where: { ($0[kCGWindowOwnerPID as String] as? Int) == Int(target.processIdentifier) && (($0[kCGWindowBounds as String] as? [String:Double])?["Width"] ?? 0) > 50 }),
              let bounds = info[kCGWindowBounds as String] as? [String:Double] else { print("No visible Status Board panel"); NSApp.terminate(nil);return }
        let primaryTop=NSScreen.screens.first?.frame.maxY ?? 900
        let frame=NSRect(x:bounds["X"]!-24,y:primaryTop-bounds["Y"]!-bounds["Height"]!-24,width:max(376,bounds["Width"]!+48),height:max(420,bounds["Height"]!+48))
        window=NSWindow(contentRect:frame,styleMask:.borderless,backing:.buffered,defer:false)
        window.title="Glass verification backdrop";window.isReleasedWhenClosed=false
        window.level = .normal;window.ignoresMouseEvents=true
        window.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        window.contentView=NSHostingView(rootView:Backdrop())
        window.orderFrontRegardless()
        print("Real test backdrop shown at \(frame)")
        DispatchQueue.main.asyncAfter(deadline:.now()+180) {NSApp.terminate(nil)}
    }
}
@main @MainActor struct Main {
    static func main(){let app=NSApplication.shared;let demo=Demo();app.delegate=demo;app.setActivationPolicy(.accessory);withExtendedLifetime(demo){app.run()}}
}
