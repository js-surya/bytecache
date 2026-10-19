import ByteCacheLanguage

/// Display names for language ids (the server may return ids outside the catalog).
public enum LanguageName {
    public static func display(_ id: String) -> String {
        LanguageCatalog.displayName(id)
    }

    /// A Markdown fence tag or alias (`js`, `sh`, `py`) as a catalog id.
    public static func catalogID(_ alias: String) -> String? {
        LanguageCatalog.id(forAlias: alias)
    }
}
