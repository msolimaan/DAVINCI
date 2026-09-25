import CleanerCore
import SwiftUI

/// Owns every module's view model so work and results survive switching between modules.
@MainActor
final class AppState: ObservableObject {
    @Published var selection: Module = .smartScan
    @Published private(set) var hasFullDiskAccess = FullDiskAccess.isGranted
    @Published var fullDiskAccessBannerDismissed = false

    let junk: JunkViewModel
    let smartScan: SmartScanViewModel
    let uninstaller = UninstallerViewModel()
    let spaceLens = SpaceLensViewModel()
    let largeFiles = LargeFilesViewModel()
    let duplicates = DuplicatesViewModel()
    let maintenance = MaintenanceViewModel()
    let loginItems = LoginItemsViewModel()
    let monitor = MonitorViewModel()

    init() {
        let junk = JunkViewModel()
        self.junk = junk
        smartScan = SmartScanViewModel(junk: junk)
        monitor.start()
    }

    func recheckFullDiskAccess() {
        hasFullDiskAccess = FullDiskAccess.isGranted
    }

    func show(_ module: Module) {
        withAnimation(.easeInOut(duration: 0.35)) { selection = module }
    }

    /// Jumps from Smart Scan's clutter card straight to large files found in Downloads.
    func reviewClutter() {
        largeFiles.scope = .downloads
        largeFiles.minimumSize = SmartScanViewModel.clutterThreshold
        largeFiles.scan()
        show(.largeFiles)
    }
}
