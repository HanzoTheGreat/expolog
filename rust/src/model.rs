use anyhow::{bail, Result};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DatePrecision {
    Day,
    Month,
    Quarter,
    Year,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Severity {
    Dormant,
    Background,
    Moderate,
    Acute,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ContextEventType {
    Clinic,
    Medication,
    Therapy,
    Life,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionStatus {
    Running,
    Completed,
    Aborted,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DatapointFlag {
    CheckIn,
    AvoidanceOrRitual,
    SafetyBehavior,
    Aborted,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FearOutcome {
    No,
    Partially,
    Yes,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UrgeOutcome {
    Running,
    Subsided,
    Extended,
    Performed,
}

impl DatePrecision {
    pub(crate) fn to_db(self) -> i64 {
        match self {
            Self::Day => 0,
            Self::Month => 1,
            Self::Quarter => 2,
            Self::Year => 3,
        }
    }

    pub(crate) fn from_db(v: i64) -> Result<Self> {
        match v {
            0 => Ok(Self::Day),
            1 => Ok(Self::Month),
            2 => Ok(Self::Quarter),
            3 => Ok(Self::Year),
            _ => bail!("Ungültige DatePrecision: {v}"),
        }
    }
}

impl Severity {
    pub(crate) fn to_db(self) -> i64 {
        match self {
            Self::Dormant => 0,
            Self::Background => 1,
            Self::Moderate => 2,
            Self::Acute => 3,
        }
    }

    pub(crate) fn from_db(v: i64) -> Result<Self> {
        match v {
            0 => Ok(Self::Dormant),
            1 => Ok(Self::Background),
            2 => Ok(Self::Moderate),
            3 => Ok(Self::Acute),
            _ => bail!("Ungültige Severity: {v}"),
        }
    }
}

impl ContextEventType {
    pub(crate) fn to_db(self) -> i64 {
        match self {
            Self::Clinic => 0,
            Self::Medication => 1,
            Self::Therapy => 2,
            Self::Life => 3,
        }
    }

    pub(crate) fn from_db(v: i64) -> Result<Self> {
        match v {
            0 => Ok(Self::Clinic),
            1 => Ok(Self::Medication),
            2 => Ok(Self::Therapy),
            3 => Ok(Self::Life),
            _ => bail!("Ungültiger ContextEventType: {v}"),
        }
    }
}

impl SessionStatus {
    pub(crate) fn to_db(self) -> i64 {
        match self {
            Self::Running => 0,
            Self::Completed => 1,
            Self::Aborted => 2,
        }
    }

    pub(crate) fn from_db(v: i64) -> Result<Self> {
        match v {
            0 => Ok(Self::Running),
            1 => Ok(Self::Completed),
            2 => Ok(Self::Aborted),
            _ => bail!("Ungültiger SessionStatus: {v}"),
        }
    }
}

impl DatapointFlag {
    pub(crate) fn to_db(self) -> i64 {
        match self {
            Self::CheckIn => 0,
            Self::AvoidanceOrRitual => 1,
            Self::SafetyBehavior => 2,
            Self::Aborted => 3,
        }
    }

    pub(crate) fn from_db(v: i64) -> Result<Self> {
        match v {
            0 => Ok(Self::CheckIn),
            1 => Ok(Self::AvoidanceOrRitual),
            2 => Ok(Self::SafetyBehavior),
            3 => Ok(Self::Aborted),
            _ => bail!("Ungültiges DatapointFlag: {v}"),
        }
    }
}

impl FearOutcome {
    pub(crate) fn to_db(self) -> i64 {
        match self {
            Self::No => 0,
            Self::Partially => 1,
            Self::Yes => 2,
        }
    }

    pub(crate) fn from_db(v: i64) -> Result<Self> {
        match v {
            0 => Ok(Self::No),
            1 => Ok(Self::Partially),
            2 => Ok(Self::Yes),
            _ => bail!("Ungültiges FearOutcome: {v}"),
        }
    }
}

impl UrgeOutcome {
    pub(crate) fn to_db(self) -> i64 {
        match self {
            Self::Running => 0,
            Self::Subsided => 1,
            Self::Extended => 2,
            Self::Performed => 3,
        }
    }

    pub(crate) fn from_db(v: i64) -> Result<Self> {
        match v {
            0 => Ok(Self::Running),
            1 => Ok(Self::Subsided),
            2 => Ok(Self::Extended),
            3 => Ok(Self::Performed),
            _ => bail!("Ungültiges UrgeOutcome: {v}"),
        }
    }
}

// --- Katalog ---

#[derive(Debug, Clone)]
pub struct Category {
    pub id: i64,
    pub name: String,
    pub color_hex: String,
    pub sort_order: i32,
}

#[derive(Debug, Clone)]
pub struct CategoryInput {
    pub id: Option<i64>,
    pub name: String,
    pub color_hex: String,
    pub sort_order: i32,
}

#[derive(Debug, Clone)]
pub struct SafetyBehavior {
    pub id: i64,
    pub exposure_item_id: i64,
    pub label: String,
    pub notes: String,
    pub archived: bool,
}

#[derive(Debug, Clone)]
pub struct SafetyBehaviorInput {
    pub id: Option<i64>,
    pub exposure_item_id: i64,
    pub label: String,
    pub notes: String,
}

#[derive(Debug, Clone)]
pub struct ExposureItem {
    pub id: i64,
    pub category_id: i64,
    pub title: String,
    pub trigger_desc: String,
    pub core_fear: String,
    pub typical_response: String,
    pub archived: bool,
    pub created_at: i64,
    pub safety_behaviors: Vec<SafetyBehavior>,
}

#[derive(Debug, Clone)]
pub struct ExposureItemInput {
    pub id: Option<i64>,
    pub category_id: i64,
    pub title: String,
    pub trigger_desc: String,
    pub core_fear: String,
    pub typical_response: String,
}

#[derive(Debug, Clone)]
pub struct CategoryGroup {
    pub category: Category,
    pub items: Vec<ExposureItem>,
}

// --- Zeitstrahl ---

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FuzzyDate {
    pub day: i32,
    pub precision: DatePrecision,
}

#[derive(Debug, Clone)]
pub struct TimelinePhase {
    pub id: i64,
    pub exposure_item_id: i64,
    pub start: FuzzyDate,
    pub end: Option<FuzzyDate>,
    pub severity: Severity,
    pub active_safety_behavior_ids: Vec<i64>,
    pub notes: String,
}

#[derive(Debug, Clone)]
pub struct TimelinePhaseInput {
    pub id: Option<i64>,
    pub exposure_item_id: i64,
    pub start: FuzzyDate,
    pub end: Option<FuzzyDate>,
    pub severity: Severity,
    pub active_safety_behavior_ids: Vec<i64>,
    pub notes: String,
}

#[derive(Debug, Clone)]
pub struct TransitionPhaseInput {
    pub exposure_item_id: i64,
    pub effective_day: i32,
    pub severity: Severity,
    pub active_safety_behavior_ids: Vec<i64>,
    pub notes: String,
}

#[derive(Debug, Clone)]
pub struct ContextEvent {
    pub id: i64,
    pub title: String,
    pub event_type: ContextEventType,
    pub start: FuzzyDate,
    pub end: Option<FuzzyDate>,
    pub is_ongoing: bool,
    pub notes: String,
}

#[derive(Debug, Clone)]
pub struct ContextEventInput {
    pub id: Option<i64>,
    pub title: String,
    pub event_type: ContextEventType,
    pub start: FuzzyDate,
    pub end: Option<FuzzyDate>,
    pub is_ongoing: bool,
    pub notes: String,
}

#[derive(Debug, Clone)]
pub struct ExposureSessionMarker {
    pub session_id: i64,
    pub day: i32,
    pub status: SessionStatus,
}

#[derive(Debug, Clone)]
pub struct TimelineItemTrack {
    pub exposure_item_id: i64,
    pub title: String,
    pub phases: Vec<TimelinePhase>,
    pub exposure_session_markers: Vec<ExposureSessionMarker>,
}

#[derive(Debug, Clone)]
pub struct TimelineCategoryLane {
    pub category_id: i64,
    pub name: String,
    pub color_hex: String,
    pub items: Vec<TimelineItemTrack>,
}

#[derive(Debug, Clone)]
pub struct TimelineViewportData {
    pub from_day: i32,
    pub to_day: i32,
    pub context_events: Vec<ContextEvent>,
    pub groups: Vec<TimelineCategoryLane>,
}

// --- Exposition & Aufschub ---

#[derive(Debug, Clone)]
pub struct ExposureDatapoint {
    pub id: i64,
    pub session_id: i64,
    pub recorded_at: i64,
    pub sud_value: i32,
    pub flag: DatapointFlag,
}

#[derive(Debug, Clone)]
pub struct ExposureSession {
    pub id: i64,
    pub exposure_item_id: i64,
    pub started_at: i64,
    pub ended_at: Option<i64>,
    pub interval_secs: i64,
    pub scale_max: i32,
    pub expected_fear: String,
    pub expected_conviction_pct: Option<i32>,
    pub fear_occurred: Option<FearOutcome>,
    pub status: SessionStatus,
    pub notes: String,
    pub datapoints: Vec<ExposureDatapoint>,
    pub used_safety_behavior_ids: Vec<i64>,
}

#[derive(Debug, Clone)]
pub struct StartExposureSessionInput {
    pub exposure_item_id: i64,
    pub interval_secs: i64,
    pub scale_max: i32,
    pub initial_sud: i32,
    pub expected_fear: String,
    pub expected_conviction_pct: Option<i32>,
}

#[derive(Debug, Clone)]
pub struct AddExposureDatapointInput {
    pub session_id: i64,
    pub sud_value: i32,
    pub flag: DatapointFlag,
}

#[derive(Debug, Clone)]
pub struct FinishExposureSessionInput {
    pub session_id: i64,
    pub status: SessionStatus,
    pub final_sud_value: Option<i32>,
    pub fear_occurred: Option<FearOutcome>,
    pub used_safety_behavior_ids: Vec<i64>,
    pub notes: String,
}

#[derive(Debug, Clone)]
pub struct UrgeDelay {
    pub id: i64,
    pub exposure_item_id: Option<i64>,
    pub started_at: i64,
    pub target_duration_secs: i64,
    pub ended_at: Option<i64>,
    pub outcome: UrgeOutcome,
}