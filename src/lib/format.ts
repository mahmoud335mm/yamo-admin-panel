const latinArabicLocale = "ar-EG-u-nu-latn";

export const numberFormatter = new Intl.NumberFormat("en-US", {
  maximumFractionDigits: 2,
});

export const integerFormatter = new Intl.NumberFormat("en-US", {
  maximumFractionDigits: 0,
});

export const compactNumberFormatter = new Intl.NumberFormat("en-US", {
  notation: "compact",
  maximumFractionDigits: 1,
});

export function formatNumber(value: unknown, compact = false) {
  const numeric = Number(value ?? 0);
  if (!Number.isFinite(numeric)) return "0";
  return (compact ? compactNumberFormatter : numberFormatter).format(numeric);
}

export function formatInteger(value: unknown) {
  const numeric = Number(value ?? 0);
  return integerFormatter.format(Number.isFinite(numeric) ? numeric : 0);
}

export function formatDateTime(value: unknown) {
  if (!value) return "—";
  const date = new Date(String(value));
  if (Number.isNaN(date.getTime())) return String(value);
  return new Intl.DateTimeFormat(latinArabicLocale, {
    year: "numeric",
    month: "short",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

export function formatMoney(value: unknown, currency = "EGP") {
  return `${formatNumber(value)} ${currency}`;
}

