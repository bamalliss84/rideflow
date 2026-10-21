from rest_framework import serializers

from apps.core.fields import name_field

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
    rater_name = name_field("rater.full_name")
    ratee_name = name_field("ratee.full_name")

    class Meta:
        model = Rating
        fields = ["rater_name", "ratee_name", "id", "ride", "rater_role", "ratee_role", "stars", "tags", "comment", "created_at"]
        read_only_fields = fields


class TrustSnapshotSerializer(serializers.ModelSerializer):
    user_name = name_field("user.full_name")
    user_phone = name_field("user.phone")

    class Meta:
        model = TrustSnapshot
        fields = [
            "user_name",
            "user_phone",
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
    subject_name = name_field("subject.full_name")
    subject_phone = name_field("subject.phone")
    reviewed_by_name = name_field("reviewed_by.full_name")

    class Meta:
        model = Violation
        fields = [
            "subject_name",
            "subject_phone",
            "reviewed_by_name",
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
    subject_name = name_field("subject.full_name")
    decided_by_name = name_field("decided_by.full_name")

    class Meta:
        model = EnforcementAction
        fields = [
            "subject_name",
            "decided_by_name",
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
    appellant_name = name_field("appellant.full_name")
    decided_by_name = name_field("decided_by.full_name")

    class Meta:
        model = Appeal
        fields = [
            "appellant_name",
            "decided_by_name",
            "id",
            "violation",
            "appellant",
            "reason",
            "status",
            "decided_by",
            "decided_at",
            "decision_note",
            "created_at",
        ]
        read_only_fields = fields


class AppealDecisionSerializer(serializers.Serializer):
    uphold = serializers.BooleanField()
    note = serializers.CharField(max_length=1000)


class DisputeCreateSerializer(serializers.Serializer):
    category = serializers.ChoiceField(choices=DisputeCategory.choices)
    description = serializers.CharField(max_length=2000)


class DisputeNoteSerializer(serializers.ModelSerializer):
    author_name = name_field("author.full_name")

    class Meta:
        model = DisputeNote
        fields = ["author_name", "id", "author", "author_role", "note", "created_at"]
        read_only_fields = ["id", "author", "author_role", "created_at"]


class DisputeSerializer(serializers.ModelSerializer):
    opened_by_name = name_field("opened_by.full_name")
    against_name = name_field("against.full_name")
    resolved_by_name = name_field("resolved_by.full_name")
    notes = DisputeNoteSerializer(many=True, read_only=True)

    class Meta:
        model = Dispute
        fields = [
            "opened_by_name",
            "against_name",
            "resolved_by_name",
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
