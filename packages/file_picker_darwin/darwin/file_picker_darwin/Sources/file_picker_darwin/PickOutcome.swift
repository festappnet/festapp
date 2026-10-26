/// What a pick completes with, given how many items the user picked and the
/// ones that could actually be loaded.
///
/// Kept free of UIKit, AppKit and Flutter so it can be unit tested on its own.
enum PickOutcome<Item> {
    /// The user picked nothing, which the app sees as a cancellation.
    case cancelled
    /// At least one picked item could be loaded. Items that failed are
    /// dropped.
    case loaded([Item])
    /// The user picked at least one item, but none of them could be loaded.
    case loadFailed

    static func resolve(pickedCount: Int, loaded: [Item]) -> PickOutcome {
        if pickedCount == 0 {
            return .cancelled
        }
        return loaded.isEmpty ? .loadFailed : .loaded(loaded)
    }
}
