import Foundation
import QuickLook
import SpaceGramMediaArchive
import UIKit

final class SpaceGramMediaPreviewController: QLPreviewController, QLPreviewControllerDataSource {
    private let lease: SpaceGramMediaPreview

    init(lease: SpaceGramMediaPreview) {
        self.lease = lease
        super.init(nibName: nil, bundle: nil)
        self.dataSource = self
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { return 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return lease.url as NSURL
    }
}
