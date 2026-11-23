use crate::db::{catalog, exposure, open_encrypted_db, timeline};
use crate::model::{
    AddExposureDatapointInput, CategoryGroup, CategoryInput, ContextEvent, ContextEventInput,
    ExposureDatapoint, ExposureItemInput, ExposureSession, FinishExposureSessionInput,
    SafetyBehaviorInput, StartExposureSessionInput, TimelinePhase, TimelinePhaseInput,
    TimelineViewportData, TransitionPhaseInput, UrgeDelay, UrgeOutcome,
};
use anyhow::Result;
use flutter_rust_bridge::frb;
use rusqlite::Connection;
use std::sync::{Mutex, MutexGuard};

fn lock_conn(mutex: &Mutex<Connection>) -> Result<MutexGuard<'_, Connection>> {
    mutex
        .lock()
        .map_err(|_| anyhow::anyhow!("Datenbank-Mutex ist korrupt (poisoned)"))
}

#[frb(opaque)]
pub struct AppCore {
    conn: Mutex<Connection>,
}

impl AppCore {
    pub fn open(db_path: String, passphrase: String) -> Result<AppCore> {
        let conn = open_encrypted_db(&db_path, &passphrase)?;
        Ok(AppCore {
            conn: Mutex::new(conn),
        })
    }

    pub fn schema_version(&self) -> Result<u32> {
        let conn = lock_conn(&self.conn)?;
        let v: u32 = conn.pragma_query_value(None, "user_version", |r| r.get(0))?;
        Ok(v)
    }

    // --- Katalog ---

    pub fn list_catalog(&self, include_archived: bool) -> Result<Vec<CategoryGroup>> {
        let conn = lock_conn(&self.conn)?;
        catalog::list_catalog(&conn, include_archived)
    }

    pub fn upsert_category(&self, input: CategoryInput) -> Result<i64> {
        let conn = lock_conn(&self.conn)?;
        catalog::upsert_category(&conn, input)
    }

    pub fn delete_category(&self, id: i64) -> Result<()> {
        let conn = lock_conn(&self.conn)?;
        catalog::delete_category(&conn, id)
    }

    pub fn upsert_exposure_item(&self, input: ExposureItemInput) -> Result<i64> {
        let conn = lock_conn(&self.conn)?;
        catalog::upsert_exposure_item(&conn, input)
    }

    pub fn set_exposure_item_archived(&self, id: i64, archived: bool) -> Result<()> {
        let conn = lock_conn(&self.conn)?;
        catalog::set_exposure_item_archived(&conn, id, archived)
    }

    pub fn delete_exposure_item(&self, id: i64) -> Result<()> {
        let conn = lock_conn(&self.conn)?;
        catalog::delete_exposure_item(&conn, id)
    }

    pub fn upsert_safety_behavior(&self, input: SafetyBehaviorInput) -> Result<i64> {
        let conn = lock_conn(&self.conn)?;
        catalog::upsert_safety_behavior(&conn, input)
    }

    pub fn set_safety_behavior_archived(&self, id: i64, archived: bool) -> Result<()> {
        let conn = lock_conn(&self.conn)?;
        catalog::set_safety_behavior_archived(&conn, id, archived)
    }

    pub fn delete_safety_behavior(&self, id: i64) -> Result<()> {
        let conn = lock_conn(&self.conn)?;
        catalog::delete_safety_behavior(&conn, id)
    }

    // --- Exposition & Aufschub-Timer ---

    pub fn get_active_exposure_session(&self) -> Result<Option<ExposureSession>> {
        let conn = lock_conn(&self.conn)?;
        exposure::get_active_exposure_session(&conn)
    }

    pub fn start_exposure_session(
        &self,
        input: StartExposureSessionInput,
    ) -> Result<ExposureSession> {
        let mut conn = lock_conn(&self.conn)?;
        exposure::start_exposure_session(&mut conn, input)
    }

    pub fn add_exposure_datapoint(
        &self,
        input: AddExposureDatapointInput,
    ) -> Result<ExposureDatapoint> {
        let conn = lock_conn(&self.conn)?;
        exposure::add_exposure_datapoint(&conn, input)
    }

    pub fn finish_exposure_session(
        &self,
        input: FinishExposureSessionInput,
    ) -> Result<ExposureSession> {
        let mut conn = lock_conn(&self.conn)?;
        exposure::finish_exposure_session(&mut conn, input)
    }

    pub fn list_exposure_sessions_for_item(
        &self,
        exposure_item_id: i64,
        limit: u32,
    ) -> Result<Vec<ExposureSession>> {
        let conn = lock_conn(&self.conn)?;
        exposure::list_exposure_sessions_for_item(&conn, exposure_item_id, limit)
    }

    pub fn delete_exposure_session(&self, id: i64) -> Result<()> {
        let conn = lock_conn(&self.conn)?;
        exposure::delete_exposure_session(&conn, id)
    }

    pub fn get_active_urge_delay(&self) -> Result<Option<UrgeDelay>> {
        let conn = lock_conn(&self.conn)?;
        exposure::get_active_urge_delay(&conn)
    }

    pub fn start_urge_delay(
        &self,
        exposure_item_id: Option<i64>,
        target_duration_secs: i64,
    ) -> Result<UrgeDelay> {
        let conn = lock_conn(&self.conn)?;
        exposure::start_urge_delay(&conn, exposure_item_id, target_duration_secs)
    }

    pub fn finish_urge_delay(&self, id: i64, outcome: UrgeOutcome) -> Result<UrgeDelay> {
        let conn = lock_conn(&self.conn)?;
        exposure::finish_urge_delay(&conn, id, outcome)
    }

    pub fn list_recent_urge_delays(&self, limit: u32) -> Result<Vec<UrgeDelay>> {
        let conn = lock_conn(&self.conn)?;
        exposure::list_recent_urge_delays(&conn, limit)
    }

    // --- Zeitstrahl ---

    pub fn get_timeline_viewport(
        &self,
        from_day: i32,
        to_day: i32,
        include_session_markers: bool,
        include_archived: bool,
    ) -> Result<TimelineViewportData> {
        let conn = lock_conn(&self.conn)?;
        timeline::get_timeline_viewport(
            &conn,
            from_day,
            to_day,
            include_session_markers,
            include_archived,
        )
    }

    pub fn upsert_timeline_phase(&self, input: TimelinePhaseInput) -> Result<i64> {
        let mut conn = lock_conn(&self.conn)?;
        timeline::upsert_timeline_phase(&mut conn, input)
    }

    pub fn transition_item_phase(&self, input: TransitionPhaseInput) -> Result<i64> {
        let mut conn = lock_conn(&self.conn)?;
        timeline::transition_item_phase(&mut conn, input)
    }

    pub fn delete_timeline_phase(&self, id: i64) -> Result<()> {
        let conn = lock_conn(&self.conn)?;
        timeline::delete_timeline_phase(&conn, id)
    }

    pub fn list_phases_for_item(&self, exposure_item_id: i64) -> Result<Vec<TimelinePhase>> {
        let conn = lock_conn(&self.conn)?;
        timeline::list_phases_for_item(&conn, exposure_item_id)
    }

    pub fn upsert_context_event(&self, input: ContextEventInput) -> Result<i64> {
        let conn = lock_conn(&self.conn)?;
        timeline::upsert_context_event(&conn, input)
    }

    pub fn delete_context_event(&self, id: i64) -> Result<()> {
        let conn = lock_conn(&self.conn)?;
        timeline::delete_context_event(&conn, id)
    }

    pub fn list_context_events(&self) -> Result<Vec<ContextEvent>> {
        let conn = lock_conn(&self.conn)?;
        timeline::list_context_events(&conn)
    }
}