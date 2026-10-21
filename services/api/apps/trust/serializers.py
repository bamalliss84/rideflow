from rest_framework import serializers

from .models import (
    Appeal,
    Dispute,
    DisputeCategory,
    DisputeNote,
    EnforcementAction,
    Rating,
    TrustSnapshot,
    Violation,
    ViolationKind,
)

ALLOWED_TAGS = [
    "punctual",
    "polite",
    "clean_vehicle",
    "safe_driving",
    "late",
    "rude",
    "unsafe",
    "price_dispute",
    "wrong_location",
    "great_service",
]


class RatingCreateSerializer(serializers.Serializer):
    stars = serializers.IntegerField(min_value=1, max_value=5)
    tags = serializers.ListField(child=serializers.ChoiceField(choices=ALLOWED_TAGS), required=False, max_length=5)
    comment = serializers.CharField(max_length=500, required=False, allow_blank=True, default="")


class RatingSerializer(serializers.ModelSerializer):
    class Meta:
        model = Rating
        fields = ["id", "ride", "rater_role", "ratee_role", "stars", "tags", "comment", "created_at"]
        read_only_fields = fields


class TrustSnapshotSerializer(serializers.ModelSerializer):
    class Meta:
        model = TrustSnapshot
        fields = [
            "user",
            "role",
            "score",
            "rating_avg",
            "rating_count",
            "completed_rides",
            "completion_rate",
            "tier",
            "components",
            "method_version",
            "config_version",
            "updated_at",
        ]
        read_only_fields = fields


class TrustSummarySerializer(serializers.Serializer):
    rating_avg = serializers.FloatField()
    rating_count = serializers.IntegerField()
    completed_rides = serializers.IntegerField()
    completion_rate = serializers.FloatField(allow_null=True)
    tier = serializers.CharField()
    score = serializers.FloatField()


class ViolationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Violation
        fields = [
            "id",
            "subject",
            "subject_role",
            "kind",
            "ride",
            "dispute",
            "status",
            "evidence",
            "reported_by",
            "reviewed_by",
            "reviewed_at",
            "review_note",
            "created_at",
        ]
        read_only_fields = fields


class ViolationReviewSerializer(serializers.Serializer):
    verify = serializers.BooleanField()
    note = serializers.CharField(max_length=500)


class EnforcementSerializer(serializers.ModelSerializer):
    class Meta:
        model = EnforcementAction
        fields = [
            "id",
            "subject",
            "subject_role",
            "violation",
            "level",
            "action_type",
            "status",
            "duration_hours",
            "starts_at",
            "ends_at",
            "reason",
            "decided_by",
            "created_at",
        ]
        read_only_fields = fields


class NoteSerializer(serializers.Serializer):
    note = serializers.CharField(max_length=2000, required=False, allow_blank=True, default="")


class AppealCreateSerializer(serializers.Serializer):
    reason = serializers.CharField(max_length=2000)


class AppealSerializer(serializers.ModelSerializer):
    class Meta:
        model = Appeal
        fields = ["id", "violation", "appellant", "reason", "status", "decided_by", "decided_at", "decision_note", "created_at"]
        read_only_fields = fields


class AppealDecisionSerializer(serializers.Serializer):
    uphold = serializers.BooleanField()
    note = serializers.CharField(max_length=1000)


class DisputeCreateSerializer(serializers.Serializer):
    category = serializers.ChoiceField(choices=DisputeCategory.choices)
    description = serializers.CharField(max_length=2000)


class DisputeNoteSerializer(serializers.ModelSerializer):
    class Meta:
        model = DisputeNote
        fields = ["id", "author", "author_role", "note", "created_at"]
        read_only_fields = ["id", "author", "author_role", "created_at"]


class DisputeSerializer(serializers.ModelSerializer):
    notes = DisputeNoteSerializer(many=True, read_only=True)

    class Meta:
        model = Dispute
        fields = [
            "id",
            "ride",
            "opened_by",
            "opened_by_role",
            "against",
            "against_role",
            "category",
            "description",
            "is_safety",
            "status",
            "resolution_note",
            "resolved_by",
            "resolved_at",
            "notes",
            "created_at",
        ]
        read_only_fields = fields


class DisputeResolveSerializer(serializers.Serializer):
    uphold = serializers.BooleanField()
    note = serializers.CharField(max_length=1000)
    violation_kind = serializers.ChoiceField(choices=ViolationKind.choices, required=False, allow_null=True)


class RewardEligibilitySerializer(serializers.Serializer):
    enabled = serializers.BooleanField()
    eligible = serializers.BooleanField()
    tier = serializers.CharField()
    min_tier = serializers.CharField()
    recent_verified_violations = serializers.BooleanField()
    discount_pct = serializers.IntegerField()


class RoleQuerySerializer(serializers.Serializer):
    role = serializers.ChoiceField(choices=["rider", "driver"])
