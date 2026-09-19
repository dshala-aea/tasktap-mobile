// dart format width=100
/// Closed, small, well-known string vocabularies for the Materiale catalog.
///
/// Unlike Marca/Category (free text, tenant-extensible — see `AppLookupField` usages), a
/// materiale's `unitOfMeasure` and a barcode's `barcodeType` are genuinely closed sets: no
/// tenant will ever need a unit of measure or barcode symbology outside these. Not worth a
/// DB-backed lookup table (mirrors the backend's own judgment — see the doc comments on
/// `Materiale.UnitOfMeasure` / `MaterialeBarcode.BarcodeType`) — a shared constant list is
/// enough. Mirrors `frontend/src/features/articoli/constants.ts` — keep the two in sync.
///
/// Existing data is a plain string on the wire, not validated against this list server-side — a
/// row saved before this list existed (or from a since-removed option) must still round-trip
/// through the form untouched. Callers add the current value as a selectable option when it
/// falls outside this list, rather than let the dropdown silently blank it out — see
/// [materialeSelectOptions].
library;

/// Standard Italian-trade unit-of-measure codes.
const List<String> kUnitOfMeasureOptions = ['pz', 'kg', 'lt', 'mt', 'ml', 'm2', 'm3', 'h', 'box'];

/// Standard barcode symbologies. Informational only — BarcodeType is never validated
/// server-side.
const List<String> kBarcodeTypeOptions = [
  'EAN13',
  'EAN8',
  'UPC',
  'CODE128',
  'CODE39',
  'QR',
  'DataMatrix',
];

/// Options for a dropdown, with the current value appended when it falls outside the canonical
/// list — never lose an existing row's real data because it predates (or fell outside) this
/// fixed vocabulary.
List<String> materialeSelectOptions(List<String> canonical, String? currentValue) {
  if (currentValue == null || currentValue.isEmpty || canonical.contains(currentValue)) {
    return canonical;
  }
  return [...canonical, currentValue];
}
