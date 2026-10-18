import ByteCatchLanguage

/// Display names for language ids (the server may return ids outside the catalog).
public enum LanguageName {
    public static func display(_ id: String) -> String {
        LanguageCatalog.displayName(id)
    }
}
