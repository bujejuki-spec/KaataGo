/// Indonesia doesn't observe daylight saving, so WIB is a fixed UTC+7
/// offset year-round. Timestamps that come from Supabase (`created_at`
/// etc.) are UTC — formatting them directly would show the backend's
/// clock instead of Indonesia time. Call [toWib] right before formatting
/// a backend timestamp for display (never store/compare the shifted
/// value — it's for display only, comparisons should stay on the real
/// UTC instant).
extension IndonesiaTime on DateTime {
  DateTime toWib() => toUtc().add(const Duration(hours: 7));
}
