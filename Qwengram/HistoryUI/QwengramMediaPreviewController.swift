import Foundation
import QuickLook
import QwengramMediaArchive
import UIKit

final class QwengramMediaPreviewController: QLPreviewController, QLPreviewControllerDataSource {
    private let lease: QwengramMediaPreview

    init(lease: QwengramMediaPreview) {
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
