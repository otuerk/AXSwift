import Foundation

// Example of your use case
@available(macOS 10.15, *)
class BarInfoUpdater {
    var axElement: UIElement?
    var barInfo: BarInfo?
    var screen: NSScreen?
    var windowNumber: Int = 0
    
    struct BarInfo {
        let screenId: String
        let barFrame: CGRect
        let screenSize: CGSize
    }
    
    func updateBarInfo(forceUpdateAX: Bool = false) async {
        // Make sure the window is valid
        guard windowNumber >= 0 else {
            return
        }
        
        if axElement == nil || forceUpdateAX {
            // axElement = UIElement.forWindow(pid: NSRunningApplication.current.processIdentifier, windowId: CGWindowID(windowNumber))
        }
        
        do {
            if let axElement = axElement {
                // This is your simplified use case!
                if let axBarFrame: CGRect = try await axElement.attribute(.frame),
                   let screenSize = screen?.visibleFrame.size {
                    // Only switch to main actor when updating UI-related properties
                    await MainActor.run {
                        barInfo = BarInfo(screenId: screen!.screenUUID, barFrame: axBarFrame, screenSize: screenSize)
                    }
                }
            }
        } catch {
            print("Error while determining bar frame on screen \\(screen?.screenUUID ?? \"unknown\"): \\(error)")
        }
    }
}

// Example showing multiple attributes at once
@available(macOS 10.15, *)
extension BarInfoUpdater {
    func updateBarInfoMultiple() async {
        guard windowNumber >= 0, let axElement = axElement else { return }
        
        do {
            // Get multiple attributes at once - more efficient!
            let attributes = try await axElement.getMultipleAttributes(.frame, .title, .position)
            
            if let frame = attributes[.frame] as? CGRect,
               let title = attributes[.title] as? String,
               let position = attributes[.position] as? CGPoint {
                print("Window: \\(title) at \\(position) with frame \\(frame)")
                
                // Update bar info - switch to main actor only for UI updates
                if let screenSize = screen?.visibleFrame.size {
                    await MainActor.run {
                        barInfo = BarInfo(screenId: screen!.screenUUID, barFrame: frame, screenSize: screenSize)
                    }
                }
            }
        } catch {
            print("Error: \\(error)")
        }
    }
}

@available(macOS 10.15, *)
extension NSScreen {
    var screenUUID: String {
        return "mock-uuid"
    }
}