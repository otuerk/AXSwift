import Cocoa
import AXSwift

class ApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Check that we have permission
        UIElement.isProcessTrusted(withPrompt: true) { trusted in
            guard trusted else {
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
            
            uiApp.windows { result in
                switch result {
                case .success(let windows):
                    NSLog("windows: \(String(describing: windows))")
                case .failure(let error):
                    NSLog("error getting windows: \(error)")
                }
            }
            
            uiApp.attributes { result in
                switch result {
                case .success(let attributes):
                    NSLog("attributes: \(attributes)")
                case .failure(let error):
                    NSLog("error getting attributes: \(error)")
                }
            }
            
            uiApp.elementAtPosition(0, 0) { result in
                switch result {
                case .success(let element):
                    NSLog("at 0,0: \(String(describing: element))")
                case .failure(let error):
                    NSLog("error getting element at position: \(error)")
                }
            }
        }

        // Get Application by bundleIdentifier
        if let app = Application.allForBundleID("com.apple.finder").first {
            NSLog("finder: \(app)")
            
            app.attribute(.role) { (result: Result<Role?, Error>) in
                switch result {
                case .success(let role):
                    NSLog("role: \(role!)")
                case .failure(let error):
                    NSLog("error getting role: \(error)")
                }
            }
            
            app.windows { result in
                switch result {
                case .success(let windows):
                    NSLog("windows: \(windows!)")
                case .failure(let error):
                    NSLog("error getting windows: \(error)")
                }
            }
            
            app.attribute(.title) { (result: Result<String?, Error>) in
                switch result {
                case .success(let title):
                    if let title = title {
                        NSLog("title: \(title)")
                    }
                case .failure(let error):
                    NSLog("error getting title: \(error)")
                }
            }
        }

        // Try to set an unsettable attribute (commented out as it needs window from async call)
        // This would need to be moved inside the windows callback above

        NSLog("system wide:")
        systemWideElement.attribute(.role) { (result: Result<Role?, Error>) in
            switch result {
            case .success(let role):
                NSLog("role: \(role!)")
            case .failure(let error):
                NSLog("error getting system role: \(error)")
            }
        }
        
        systemWideElement.attributes { result in
            switch result {
            case .success(let attributes):
                NSLog("attributes: \(attributes)")
            case .failure(let error):
                NSLog("error getting system attributes: \(error)")
            }
        }
        
        // Terminate after a delay to allow async operations to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            NSRunningApplication.current.terminate()
        }
    }
}
