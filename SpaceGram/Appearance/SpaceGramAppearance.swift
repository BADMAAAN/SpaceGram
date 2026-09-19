import ItemListUI
import TelegramPresentationData

/// Follow the selected Telegram theme, including automatic light/dark changes.
public func spaceGramItemListPresentationData(_ presentationData: PresentationData) -> ItemListPresentationData {
    return ItemListPresentationData(
        theme: presentationData.theme,
        fontSize: presentationData.listsFontSize,
        strings: presentationData.strings,
        nameDisplayOrder: presentationData.nameDisplayOrder,
        dateTimeFormat: presentationData.dateTimeFormat
    )
}
