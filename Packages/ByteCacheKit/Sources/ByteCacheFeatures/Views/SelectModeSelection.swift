/// Select mode on the Mac (CP-86). A Mac list's own selection replaces the selection on a click and
/// ignores a click on the only selected row, so Select mode there shows a circle on each row and
/// every click adds or removes that snippet, as on iPhone and iPad.
enum SelectModeSelection {
    static func toggling(_ id: Int, in selection: Set<Int>) -> Set<Int> {
        var result = selection
        if result.contains(id) { result.remove(id) } else { result.insert(id) }
        return result
    }
}
