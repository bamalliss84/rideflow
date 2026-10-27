import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Localized labels for backend enum values. Unknown values fall back to the raw code (never hidden).

String rideStatusLabel(AppLocalizations t, String s) => switch (s) {
      'requested' => t.ride_requested,
      'bidding' => t.ride_bidding,
      'match_pending' => t.ride_match_pending,
      'assigned' => t.ride_assigned,
      'en_route' => t.ride_en_route,
      'arrived' => t.ride_arrived,
      'in_progress' => t.ride_in_progress,
      'completed' => t.ride_completed,
      'cancelled' => t.ride_cancelled,
      'no_show' => t.ride_no_show,
      'disputed' => t.ride_disputed,
      _ => s,
    };

String bidStatusLabel(AppLocalizations t, String s) => switch (s) {
      'open' => t.bid_active,
      'declined' => t.action_decline,
      'selected' => t.bid_selected,
      'withdrawn' => t.bid_withdrawn,
      'expired' => t.bid_expired,
      'lost' => t.bid_lost,
      'accepted' => t.bid_accepted,
      _ => s,
    };

String driverStatusLabel(AppLocalizations t, String s) => switch (s) {
      'pending_documents' => t.status_pending_documents,
      'under_review' => t.status_under_review,
      'approved' => t.status_approved,
      'rejected' => t.status_rejected,
      'suspended' => t.status_suspended,
      'pending' => t.status_pending,
      _ => s,
    };

String claimStatusLabel(AppLocalizations t, String s) => switch (s) {
      'submitted' => t.claim_submitted,
      'first_approved' => t.claim_first_approved,
      'approved' => t.claim_approved,
      'rejected' => t.claim_rejected,
      _ => s,
    };

String docTypeLabel(AppLocalizations t, String s) => switch (s) {
      'national_id' => t.doc_national_id,
      'driving_license' => t.doc_driving_license,
      'vehicle_registration' => t.doc_vehicle_registration,
      'vehicle_photo' => t.doc_vehicle_photo,
      'driver_photo' => t.doc_driver_photo,
      'insurance' => t.doc_insurance,
      _ => s,
    };

String actionLabel(AppLocalizations t, String a) => switch (a) {
      'confirm' => t.action_confirm,
      'decline' => t.action_decline,
      'en_route' => t.action_en_route,
      'arrive' => t.action_arrive,
      'start' => t.action_start,
      'complete' => t.action_complete,
      'driver_cancel' => t.action_driver_cancel,
      'no_show' => t.action_no_show,
      _ => a,
    };

/// Eligibility reasons from apps/drivers/services.eligibility (some carry a value after ':').
String eligibilityReason(AppLocalizations t, String reason) {
  final code = reason.split(':').first;
  final value = reason.contains(':') ? reason.substring(reason.indexOf(':') + 1) : '';
  return switch (code) {
    'driver_pending_documents' => t.reason_driver_pending_documents,
    'driver_under_review' => t.reason_driver_under_review,
    'driver_rejected' => t.reason_driver_rejected,
    'driver_suspended' => t.reason_driver_suspended,
    'documents_missing_or_expired' => t.reason_documents_missing_or_expired,
    'no_approved_vehicle' => t.reason_no_approved_vehicle,
    'subscription_inactive' => t.reason_subscription_inactive,
    'restricted_until' => t.reason_restricted_until(value.length >= 16 ? value.substring(0, 16).replaceFirst('T', ' ') : value),
    'tenant_suspended' => t.reason_tenant_suspended,
    'location_required' => t.reason_location_required,
    _ => t.reason_other(code),
  };
}
