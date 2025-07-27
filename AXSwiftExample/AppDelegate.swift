import Cocoa
import AXSwift

class ApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Check that we have permission
        UIElement.isProcessTrusted(withPrompt: true) { trusted, error in
            if let error = error {
                NSLog("Error checking trust: \(error)")
                NSRunningApplication.current.terminate()
                return
            }
            
            guard let trusted = trusted, trusted else {
                NSLog("No accessibility API permission, exiting")
                NSRunningApplication.current.terminate()
                return
            }
            
            self.runAXTests()
        }
    }
    
    private func runAXTests() {

        // Get Active Application
        if let application = NSWorkspace.shared.frontmostApplication {
            NSLog("localizedName: \(String(describing: application.localizedName)), processIdentifier: \(application.processIdentifier))")
            let uiApp = Application(application)!
            
            uiApp.windows { windows, error in
                if let error = error {
                    NSLog("error getting windows: \(error)")
                } else {
                    NSLog("windows: \(String(describing: windows))")
                }
            }
            
            uiApp.attributes { attributes, error in
                if let error = error {
                    NSLog("error getting attributes: \(error)")
                } else {
                    NSLog("attributes: \(attributes ?? [])")
                }
            }
            
            uiApp.elementAtPosition(0, 0) { element, error in
                if let error = error {
                    NSLog("error getting element at position: \(error)")
                } else {
                    NSLog("at 0,0: \(String(describing: element))")
                }
            }
        }

        // Get Application by bundleIdentifier
        if let app = Application.allForBundleID("com.apple.finder").first {
            NSLog("finder: \(app)")
            
            app.role { role, error in
                if let error = error {
                    NSLog("error getting role: \(error)")
                } else if let role = role {
                    NSLog("role: \(role)")
                }
            }
            
            app.windows { windows, error in
                if let error = error {
                    NSLog("error getting windows: \(error)")
                } else if let windows = windows {
                    NSLog("windows: \(windows)")
                }
            }
            
            app.attribute(.title) { (title: String?, error: Error?) in
                if let error = error {
                    NSLog("error getting title: \(error)")
                } else if let title = title {
                    NSLog("title: \(title)")
                }
            }
        }

        // Try to set an unsettable attribute (commented out as it needs window from async call)
        // This would need to be moved inside the windows callback above

        NSLog("system wide:")
        systemWideElement.role { role, error in
            if let error = error {
                NSLog("error getting system role: \(error)")
            } else if let role = role {
                NSLog("role: \(role)")
            }
        }
        
        systemWideElement.attributes { attributes, error in
            if let error = error {
                NSLog("error getting system attributes: \(error)")
            } else {
                NSLog("attributes: \(attributes ?? [])")
            }
        }
        
        // Terminate after a delay to allow async operations to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            NSRunningApplication.current.terminate()
        }
    }
}
