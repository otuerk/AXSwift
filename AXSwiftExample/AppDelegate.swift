import Cocoa
import AXSwift

@available(macOS 10.15, *)
class ApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        Task {
            await self.runApplication()
        }
    }
    
    @available(macOS 10.15, *)
    private func runApplication() async {
        do {
            // Check that we have permission
            let trusted = try await UIElement.isProcessTrusted(withPrompt: true)
            
            guard trusted else {
                NSLog("No accessibility API permission, exiting")
                NSRunningApplication.current.terminate()
                return
            }
            
            await self.runAXTests()
        } catch {
            NSLog("Error checking trust: \(error)")
            NSRunningApplication.current.terminate()
        }
    }
    
    @available(macOS 10.15, *)
    private func runAXTests() async {

        // Get Active Application
        if let application = NSWorkspace.shared.frontmostApplication {
            NSLog("localizedName: \(String(describing: application.localizedName)), processIdentifier: \(application.processIdentifier))")
            let uiApp = Application(application)!
            
            do {
                let windows = try await uiApp.windows()
                NSLog("windows: \(String(describing: windows))")
                
                let attributes = try await uiApp.attributes()
                NSLog("attributes: \(attributes)")
                
                let element = try await uiApp.elementAtPosition(0, 0)
                NSLog("at 0,0: \(String(describing: element))")
            } catch {
                NSLog("error getting app info: \(error)")
            }
        }

        // Get Application by bundleIdentifier
        if let app = Application.allForBundleID("com.apple.finder").first {
            NSLog("finder: \(app)")
            
            do {
                let role = try await app.role()
                NSLog("role: \(role ?? Role.unknown)")
                
                let windows = try await app.windows()
                NSLog("windows: \(windows ?? [])")
                
                let title: String? = try await app.attribute(.title)
                if let title = title {
                    NSLog("title: \(title)")
                }
            } catch {
                NSLog("error getting finder info: \(error)")
            }
        }

        // Try to set an unsettable attribute (commented out as it needs window from async call)
        // This would need to be moved inside the windows callback above

        NSLog("system wide:")
        do {
            let role = try await systemWideElement.role()
            NSLog("system role: \(role ?? Role.unknown)")
            
            let attributes = try await systemWideElement.attributes()
            NSLog("system attributes: \(attributes)")
        } catch {
            NSLog("error getting system info: \(error)")
        }
        
        // Terminate after a short delay
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        NSRunningApplication.current.terminate()
    }
}
