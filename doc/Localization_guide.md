# Localisation and translation

Slicer uses GNU gettext catalogues under [resources/localization](../resources/localization). The build defines extraction, catalogue merging and binary compilation targets in the root [CMakeLists.txt](../CMakeLists.txt).

## Catalogue ownership

The current build and loader consume `PrusaSlicer.pot`, locale-specific `PrusaSlicer*.po` files and `PrusaSlicer.mo`. These filenames are compatibility interfaces; changing the displayed product name does not rename the catalogue domain.

Use this repository's catalogues and source list. Translation changes follow [Contributing](../.github/CONTRIBUTING.md) and stay on `main`.

## Edit an existing translation

1. Open the appropriate locale's PO file in Poedit or another gettext-aware editor.
2. Translate or correct the messages while preserving contexts, plurals, format placeholders and translator comments.
3. Validate with `msgfmt --check-format`, then rebuild the MO catalogue.
4. Run Slicer in that locale and check the affected controls, labels and dialogs.

From a configured application build with its tools already built:

```sh
cmake --build build/native/app --target gettext_po_to_mo
```

Use the actual application build directory if it differs from the native driver's default. For example, the French source is [PrusaSlicer_fr.po](../resources/localization/fr/PrusaSlicer_fr.po); the compiled catalogue is stored alongside it as `PrusaSlicer.mo`.

## Add a language or source string

Create the locale catalogue from [PrusaSlicer.pot](../resources/localization/PrusaSlicer.pot) with the correct language and plural metadata. Follow the existing locale directory and catalogue naming convention, compile the MO file and verify language selection in the application.

Mark new translatable source strings with the applicable existing translation macro and add new source files to [list.txt](../resources/localization/list.txt). Regenerate the template through the build target so all configured extraction keywords and generated hints are included:

```sh
cmake --build build/native/app --target gettext_make_pot
```

Merge the updated template into affected catalogues with gettext-aware tools and review the resulting changes. A regenerated catalogue is not evidence that translations or plural forms are correct.

## Translation contracts

- Preserve placeholders such as `%1%`, `%d`, `%%` and their associated argument semantics.
- Preserve intentional spaces, punctuation and line breaks; do not add line breaks to parameter labels.
- Keep terminology consistent across related controls and use the application's established unit notation.
- Check text length in the actual UI; alternative translations in parentheses can make controls unusably wide.
- Proofread automated changes and report encoding defects with the locale, source revision and affected control.

The gettext manual and Poedit documentation describe tool usage; this guide owns Slicer's catalogue paths and verification boundaries.


