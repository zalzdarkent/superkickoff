/// Shared formatting helpers.
String money(int amount) {
  if (amount >= 1000000000) {
    return '\$${(amount / 1000000000).toStringAsFixed(1)}B';
  }
  if (amount >= 1000000) {
    return '\$${(amount / 1000000).toStringAsFixed(1)}M';
  }
  if (amount >= 1000) {
    return '\$${(amount / 1000).toStringAsFixed(0)}K';
  }
  return '\$$amount';
}

String shortDate(String? iso) {
  if (iso == null || iso.length < 10) return iso ?? '';
  return iso.substring(0, 10);
}
