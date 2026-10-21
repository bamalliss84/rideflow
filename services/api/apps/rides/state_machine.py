"""Explicit ride state machine (BUSINESS_RULES §2, R03-01). The only place allowed transitions are defined."""

from dataclasses import dataclass

from apps.core.exceptions import InvalidTransition

from .models import RideStatus as S

RIDER, DRIVER, SYSTEM = "rider", "driver", "system"


@dataclass(frozen=True)
class Transition:
    sources: frozenset
    target: str
    actors: frozenset


TRANSITIONS = {
    "dispatch": Transition(frozenset({S.REQUESTED}), S.BIDDING, frozenset({RIDER, SYSTEM})),
    "select": Transition(frozenset({S.BIDDING}), S.MATCH_PENDING, frozenset({RIDER})),
    "confirm": Transition(frozenset({S.MATCH_PENDING}), S.ASSIGNED, frozenset({DRIVER})),
    "decline": Transition(frozenset({S.MATCH_PENDING}), S.BIDDING, frozenset({DRIVER})),
    "match_timeout": Transition(frozenset({S.MATCH_PENDING}), S.BIDDING, frozenset({SYSTEM})),
    "en_route": Transition(frozenset({S.ASSIGNED}), S.EN_ROUTE, frozenset({DRIVER})),
    "arrive": Transition(frozenset({S.ASSIGNED, S.EN_ROUTE}), S.ARRIVED, frozenset({DRIVER})),
    "start": Transition(frozenset({S.ARRIVED}), S.IN_PROGRESS, frozenset({DRIVER})),
    "complete": Transition(frozenset({S.IN_PROGRESS}), S.COMPLETED, frozenset({DRIVER})),
    "rider_cancel": Transition(
        frozenset({S.REQUESTED, S.BIDDING, S.MATCH_PENDING, S.ASSIGNED, S.EN_ROUTE, S.ARRIVED}),
        S.CANCELLED,
        frozenset({RIDER}),
    ),
    "driver_cancel": Transition(frozenset({S.ASSIGNED, S.EN_ROUTE, S.ARRIVED}), S.CANCELLED, frozenset({DRIVER})),
    "expire": Transition(frozenset({S.REQUESTED, S.BIDDING}), S.CANCELLED, frozenset({SYSTEM})),
    "no_show": Transition(frozenset({S.ARRIVED}), S.NO_SHOW, frozenset({DRIVER})),
    "dispute": Transition(frozenset({S.COMPLETED, S.CANCELLED, S.NO_SHOW}), S.DISPUTED, frozenset({RIDER, DRIVER})),
}


def target_for(status, action, actor):
    transition = TRANSITIONS.get(action)
    if transition is None:
        raise InvalidTransition(f"Unknown action '{action}'.")
    if actor not in transition.actors:
        raise InvalidTransition(f"'{action}' cannot be performed by {actor}.", code="actor_not_allowed")
    if status not in transition.sources:
        raise InvalidTransition(f"'{action}' is not allowed while the ride is {status}.")
    return transition.target


def allowed_actions(status, actor):
    return sorted(a for a, t in TRANSITIONS.items() if status in t.sources and actor in t.actors)
