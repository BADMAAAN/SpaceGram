import ItemListUI
import TelegramPresentationData

/// Keeps SpaceGram-owned screens on a restrained graphite palette while using
/// Telegram's proven theme primitives and accessibility-aware list components.
public func spaceGramItemListPresentationData(_ presentationData: PresentationData) -> ItemListPresentationData {
    let theme = makeDefaultPresentationTheme(reference: .night, serviceBackgroundColor: nil)
    return ItemListPresentationData(
        theme: theme,
        fontSize: presentationData.listsFontSize,
        strings: presentationData.strings,
        nameDisplayOrder: presentationData.nameDisplayOrder,
        dateTimeFormat: presentationData.dateTimeFormat
    )
}
