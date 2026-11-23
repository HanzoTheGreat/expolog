use crate::db::validate_safety_behaviors_belong_to_item;
use crate::model::{
    ContextEvent, ContextEventInput, ContextEventType, DatePrecision, ExposureSessionMarker,
    FuzzyDate, SessionStatus, Severity, TimelineCategoryLane, TimelineItemTrack, TimelinePhase,
    TimelinePhaseInput, TimelineViewportData, TransitionPhaseInput,
};
use anyhow::{bail, Result};
use rusqlite::{params, Connection, OptionalExtension};
use std::collections::HashMap;

fn parse_optional_fuzzy(day: Option<i32>, prec: Option<i64>) -> Result<Option<FuzzyDate>> {
    match (day, prec) {
        (Some(d), Some(p)) => Ok(Some(FuzzyDate {
            day: d,
            precision: DatePrecision::from_db(p)?,
        })),
        (None, None) => Ok(None),
        _ => bail!("Inkonsistentes Enddatum in der Datenbank."),
    }
}

fn load_phase_safety_behaviors_map(conn: &Connection) -> Result<HashMap<i64, Vec<i64>>> {
    let mut stmt = conn.prepare(
        "SELECT phase_id, safety_behavior_id
         FROM phase_safety_behaviors
         ORDER BY phase_id ASC, safety_behavior_id ASC",
    )?;
    let rows = stmt.query_map([], |row| Ok((row.get::<_, i64>(0)?, row.get::<_, i64>(1)?)))?;
    let mut map: HashMap<i64, Vec<i64>> = HashMap::new();
    for r in rows {
        let (phase_id, sb_id) = r?;
        map.entry(phase_id).or_default().push(sb_id);
    }
    Ok(map)
}

pub fn upsert_timeline_phase(conn: &mut Connection, input: TimelinePhaseInput) -> Result<i64> {
    if let Some(end) = input.end {
        if end.day < input.start.day {
            bail!("Enddatum darf nicht vor dem Startdatum liegen.");
        }
    }

    let tx = conn.transaction()?;
    validate_safety_behaviors_belong_to_item(
        &tx,
        input.exposure_item_id,
        &input.active_safety_behavior_ids,
    )?;

    let (end_day, end_prec) = match input.end {
        Some(e) => (Some(e.day), Some(e.precision.to_db())),
        None => (None, None),
    };

    let phase_id = match input.id {
        Some(id) => {
            let changed = tx.execute(
                "UPDATE timeline_phases
                 SET exposure_item_id = ?1,
                     start_day = ?2,
                     start_precision = ?3,
                     end_day = ?4,
                     end_precision = ?5,
                     severity = ?6,
                     notes = ?7
                 WHERE id = ?8",
                params![
                    input.exposure_item_id,
                    input.start.day,
                    input.start.precision.to_db(),
                    end_day,
                    end_prec,
                    input.severity.to_db(),
                    input.notes.trim(),
                    id
                ],
            )?;
            if changed == 0 {
                bail!("Zeitstrahl-Phase {id} nicht gefunden.");
            }
            id
        }
        None => {
            tx.execute(
                "INSERT INTO timeline_phases
                 (exposure_item_id, start_day, start_precision, end_day, end_precision, severity, notes)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                params![
                    input.exposure_item_id,
                    input.start.day,
                    input.start.precision.to_db(),
                    end_day,
                    end_prec,
                    input.severity.to_db(),
                    input.notes.trim(),
                ],
            )?;
            tx.last_insert_rowid()
        }
    };

    tx.execute(
        "DELETE FROM phase_safety_behaviors WHERE phase_id = ?1",
        params![phase_id],
    )?;
    for sb_id in &input.active_safety_behavior_ids {
        tx.execute(
            "INSERT OR IGNORE INTO phase_safety_behaviors (phase_id, safety_behavior_id)
             VALUES (?1, ?2)",
            params![phase_id, sb_id],
        )?;
    }

    tx.commit()?;
    Ok(phase_id)
}

/// Bequemer Zustandswechsel für den Alltag („Ab heute: Status X“):
/// Schließt eine eventuell laufende Phase sauber zum Vortag und startet die neue Phase.
pub fn transition_item_phase(conn: &mut Connection, input: TransitionPhaseInput) -> Result<i64> {
    let tx = conn.transaction()?;
    validate_safety_behaviors_belong_to_item(
        &tx,
        input.exposure_item_id,
        &input.active_safety_behavior_ids,
    )?;

    let open_phase: Option<(i64, i32)> = tx
        .query_row(
            "SELECT id, start_day
             FROM timeline_phases
             WHERE exposure_item_id = ?1 AND end_day IS NULL
             ORDER BY start_day DESC, id DESC
             LIMIT 1",
            params![input.exposure_item_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()?;

    let phase_id = match open_phase {
        Some((open_id, open_start_day)) if open_start_day == input.effective_day => {
            tx.execute(
                "UPDATE timeline_phases
                 SET severity = ?1, notes = ?2
                 WHERE id = ?3",
                params![input.severity.to_db(), input.notes.trim(), open_id],
            )?;
            open_id
        }
        Some((_, open_start_day)) if open_start_day > input.effective_day => {
            bail!("Es existiert bereits eine laufende Phase ab einem späteren Datum.");
        }
        Some((open_id, _)) => {
            // Laufende Phase zum Vortag beenden
            tx.execute(
                "UPDATE timeline_phases
                 SET end_day = ?1, end_precision = ?2
                 WHERE id = ?3",
                params![
                    input.effective_day - 1,
                    DatePrecision::Day.to_db(),
                    open_id
                ],
            )?;
            tx.execute(
                "INSERT INTO timeline_phases
                 (exposure_item_id, start_day, start_precision, end_day, end_precision, severity, notes)
                 VALUES (?1, ?2, ?3, NULL, NULL, ?4, ?5)",
                params![
                    input.exposure_item_id,
                    input.effective_day,
                    DatePrecision::Day.to_db(),
                    input.severity.to_db(),
                    input.notes.trim(),
                ],
            )?;
            tx.last_insert_rowid()
        }
        None => {
            tx.execute(
                "INSERT INTO timeline_phases
                 (exposure_item_id, start_day, start_precision, end_day, end_precision, severity, notes)
                 VALUES (?1, ?2, ?3, NULL, NULL, ?4, ?5)",
                params![
                    input.exposure_item_id,
                    input.effective_day,
                    DatePrecision::Day.to_db(),
                    input.severity.to_db(),
                    input.notes.trim(),
                ],
            )?;
            tx.last_insert_rowid()
        }
    };

    tx.execute(
        "DELETE FROM phase_safety_behaviors WHERE phase_id = ?1",
        params![phase_id],
    )?;
    for sb_id in &input.active_safety_behavior_ids {
        tx.execute(
            "INSERT OR IGNORE INTO phase_safety_behaviors (phase_id, safety_behavior_id)
             VALUES (?1, ?2)",
            params![phase_id, sb_id],
        )?;
    }

    tx.commit()?;
    Ok(phase_id)
}

pub fn delete_timeline_phase(conn: &Connection, id: i64) -> Result<()> {
    let changed = conn.execute("DELETE FROM timeline_phases WHERE id = ?1", params![id])?;
    if changed == 0 {
        bail!("Zeitstrahl-Phase {id} nicht gefunden.");
    }
    Ok(())
}

pub fn list_phases_for_item(
    conn: &Connection,
    exposure_item_id: i64,
) -> Result<Vec<TimelinePhase>> {
    let mut sb_map = load_phase_safety_behaviors_map(conn)?;
    let mut stmt = conn.prepare(
        "SELECT id, exposure_item_id, start_day, start_precision, end_day, end_precision, severity, notes
         FROM timeline_phases
         WHERE exposure_item_id = ?1
         ORDER BY start_day ASC, id ASC",
    )?;
    let rows = stmt.query_map(params![exposure_item_id], |row| {
        Ok((
            row.get::<_, i64>(0)?,
            row.get::<_, i64>(1)?,
            row.get::<_, i32>(2)?,
            row.get::<_, i64>(3)?,
            row.get::<_, Option<i32>>(4)?,
            row.get::<_, Option<i64>>(5)?,
            row.get::<_, i64>(6)?,
            row.get::<_, String>(7)?,
        ))
    })?;

    let mut phases = Vec::new();
    for r in rows {
        let (id, iid, s_day, s_prec, e_day, e_prec, sev, notes) = r?;
        phases.push(TimelinePhase {
            id,
            exposure_item_id: iid,
            start: FuzzyDate {
                day: s_day,
                precision: DatePrecision::from_db(s_prec)?,
            },
            end: parse_optional_fuzzy(e_day, e_prec)?,
            severity: Severity::from_db(sev)?,
            active_safety_behavior_ids: sb_map.remove(&id).unwrap_or_default(),
            notes,
        });
    }
    Ok(phases)
}

// --- Kontext-Ereignisse ---

pub fn upsert_context_event(conn: &Connection, input: ContextEventInput) -> Result<i64> {
    let title = input.title.trim();
    if title.is_empty() {
        bail!("Titel des Kontext-Ereignisses darf nicht leer sein.");
    }
    if input.is_ongoing && input.end.is_some() {
        bail!("Ein laufendes Ereignis darf kein Enddatum haben.");
    }
    if let Some(end) = input.end {
        if end.day < input.start.day {
            bail!("Enddatum darf nicht vor dem Startdatum liegen.");
        }
    }

    let (end_day, end_prec) = match input.end {
        Some(e) => (Some(e.day), Some(e.precision.to_db())),
        None => (None, None),
    };
    let ongoing_int = if input.is_ongoing { 1 } else { 0 };

    match input.id {
        Some(id) => {
            let changed = conn.execute(
                "UPDATE context_events
                 SET title = ?1,
                     event_type = ?2,
                     start_day = ?3,
                     start_precision = ?4,
                     end_day = ?5,
                     end_precision = ?6,
                     is_ongoing = ?7,
                     notes = ?8
                 WHERE id = ?9",
                params![
                    title,
                    input.event_type.to_db(),
                    input.start.day,
                    input.start.precision.to_db(),
                    end_day,
                    end_prec,
                    ongoing_int,
                    input.notes.trim(),
                    id
                ],
            )?;
            if changed == 0 {
                bail!("Kontext-Ereignis {id} nicht gefunden.");
            }
            Ok(id)
        }
        None => {
            conn.execute(
                "INSERT INTO context_events
                 (title, event_type, start_day, start_precision, end_day, end_precision, is_ongoing, notes)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
                params![
                    title,
                    input.event_type.to_db(),
                    input.start.day,
                    input.start.precision.to_db(),
                    end_day,
                    end_prec,
                    ongoing_int,
                    input.notes.trim(),
                ],
            )?;
            Ok(conn.last_insert_rowid())
        }
    }
}

pub fn delete_context_event(conn: &Connection, id: i64) -> Result<()> {
    let changed = conn.execute("DELETE FROM context_events WHERE id = ?1", params![id])?;
    if changed == 0 {
        bail!("Kontext-Ereignis {id} nicht gefunden.");
    }
    Ok(())
}

pub fn list_context_events(conn: &Connection) -> Result<Vec<ContextEvent>> {
    let mut stmt = conn.prepare(
        "SELECT id, title, event_type, start_day, start_precision, end_day, end_precision, is_ongoing, notes
         FROM context_events
         ORDER BY start_day ASC, id ASC",
    )?;
    let rows = stmt.query_map([], |row| {
        Ok((
            row.get::<_, i64>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, i64>(2)?,
            row.get::<_, i32>(3)?,
            row.get::<_, i64>(4)?,
            row.get::<_, Option<i32>>(5)?,
            row.get::<_, Option<i64>>(6)?,
            row.get::<_, i64>(7)?,
            row.get::<_, String>(8)?,
        ))
    })?;

    let mut events = Vec::new();
    for r in rows {
        let (id, title, ev_type, s_day, s_prec, e_day, e_prec, ongoing, notes) = r?;
        events.push(ContextEvent {
            id,
            title,
            event_type: ContextEventType::from_db(ev_type)?,
            start: FuzzyDate {
                day: s_day,
                precision: DatePrecision::from_db(s_prec)?,
            },
            end: parse_optional_fuzzy(e_day, e_prec)?,
            is_ongoing: ongoing != 0,
            notes,
        });
    }
    Ok(events)
}

// --- Viewport-Abfrage für den CustomPainter ---

pub fn get_timeline_viewport(
    conn: &Connection,
    from_day: i32,
    to_day: i32,
    include_session_markers: bool,
    include_archived: bool,
) -> Result<TimelineViewportData> {
    if to_day < from_day {
        bail!("Ungültiger Zeitraum: to_day liegt vor from_day.");
    }

    // 1. Sichtbare Kontext-Ereignisse
    let mut ctx_stmt = conn.prepare(
        "SELECT id, title, event_type, start_day, start_precision, end_day, end_precision, is_ongoing, notes
         FROM context_events
         WHERE start_day <= ?2
           AND (is_ongoing = 1 OR COALESCE(end_day, start_day) >= ?1)
         ORDER BY start_day ASC, id ASC",
    )?;
    let ctx_rows = ctx_stmt.query_map(params![from_day, to_day], |row| {
        Ok((
            row.get::<_, i64>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, i64>(2)?,
            row.get::<_, i32>(3)?,
            row.get::<_, i64>(4)?,
            row.get::<_, Option<i32>>(5)?,
            row.get::<_, Option<i64>>(6)?,
            row.get::<_, i64>(7)?,
            row.get::<_, String>(8)?,
        ))
    })?;
    let mut context_events = Vec::new();
    for r in ctx_rows {
        let (id, title, ev_type, s_day, s_prec, e_day, e_prec, ongoing, notes) = r?;
        context_events.push(ContextEvent {
            id,
            title,
            event_type: ContextEventType::from_db(ev_type)?,
            start: FuzzyDate {
                day: s_day,
                precision: DatePrecision::from_db(s_prec)?,
            },
            end: parse_optional_fuzzy(e_day, e_prec)?,
            is_ongoing: ongoing != 0,
            notes,
        });
    }

    // 2. Sichtbare Phasen nach exposure_item_id gruppiert
    let mut sb_map = load_phase_safety_behaviors_map(conn)?;
    let mut phase_stmt = conn.prepare(
        "SELECT id, exposure_item_id, start_day, start_precision, end_day, end_precision, severity, notes
         FROM timeline_phases
         WHERE start_day <= ?2
           AND (end_day IS NULL OR end_day >= ?1)
         ORDER BY start_day ASC, id ASC",
    )?;
    let phase_rows = phase_stmt.query_map(params![from_day, to_day], |row| {
        Ok((
            row.get::<_, i64>(0)?,
            row.get::<_, i64>(1)?,
            row.get::<_, i32>(2)?,
            row.get::<_, i64>(3)?,
            row.get::<_, Option<i32>>(4)?,
            row.get::<_, Option<i64>>(5)?,
            row.get::<_, i64>(6)?,
            row.get::<_, String>(7)?,
        ))
    })?;
    let mut phases_by_item: HashMap<i64, Vec<TimelinePhase>> = HashMap::new();
    for r in phase_rows {
        let (id, iid, s_day, s_prec, e_day, e_prec, sev, notes) = r?;
        phases_by_item.entry(iid).or_default().push(TimelinePhase {
            id,
            exposure_item_id: iid,
            start: FuzzyDate {
                day: s_day,
                precision: DatePrecision::from_db(s_prec)?,
            },
            end: parse_optional_fuzzy(e_day, e_prec)?,
            severity: Severity::from_db(sev)?,
            active_safety_behavior_ids: sb_map.remove(&id).unwrap_or_default(),
            notes,
        });
    }

    // 3. Optional: Expositions-Marker im Detail-Zoom
    let mut markers_by_item: HashMap<i64, Vec<ExposureSessionMarker>> = HashMap::new();
    if include_session_markers {
        let from_ts = i64::from(from_day) * 86_400;
        let to_ts_exclusive = (i64::from(to_day) + 1) * 86_400;
        let mut m_stmt = conn.prepare(
            "SELECT id, exposure_item_id, started_at, status
             FROM exposure_sessions
             WHERE started_at >= ?1 AND started_at < ?2 AND status != ?3
             ORDER BY started_at ASC, id ASC",
        )?;
        let m_rows = m_stmt.query_map(
            params![from_ts, to_ts_exclusive, SessionStatus::Running.to_db()],
            |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, i64>(2)?,
                    row.get::<_, i64>(3)?,
                ))
            },
        )?;
        for r in m_rows {
            let (session_id, iid, started_at, status_raw) = r?;
            let day = started_at.div_euclid(86_400) as i32;
            markers_by_item
                .entry(iid)
                .or_default()
                .push(ExposureSessionMarker {
                    session_id,
                    day,
                    status: SessionStatus::from_db(status_raw)?,
                });
        }
    }

    // 4. Kategorien & Themen zu Bündel-Spuren zusammensetzen
    let item_sql = if include_archived {
        "SELECT id, category_id, title FROM exposure_items ORDER BY id ASC"
    } else {
        "SELECT id, category_id, title FROM exposure_items WHERE archived = 0 ORDER BY id ASC"
    };
    let mut item_stmt = conn.prepare(item_sql)?;
    let item_rows = item_stmt.query_map([], |row| {
        Ok((
            row.get::<_, i64>(0)?,
            row.get::<_, i64>(1)?,
            row.get::<_, String>(2)?,
        ))
    })?;
    let mut tracks_by_category: HashMap<i64, Vec<TimelineItemTrack>> = HashMap::new();
    for r in item_rows {
        let (iid, cat_id, title) = r?;
        tracks_by_category
            .entry(cat_id)
            .or_default()
            .push(TimelineItemTrack {
                exposure_item_id: iid,
                title,
                phases: phases_by_item.remove(&iid).unwrap_or_default(),
                exposure_session_markers: markers_by_item.remove(&iid).unwrap_or_default(),
            });
    }

    let mut cat_stmt = conn.prepare(
        "SELECT id, name, color_hex
         FROM categories
         ORDER BY sort_order ASC, id ASC",
    )?;
    let cat_rows = cat_stmt.query_map([], |row| {
        Ok((
            row.get::<_, i64>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, String>(2)?,
        ))
    })?;

    let mut groups = Vec::new();
    for r in cat_rows {
        let (cat_id, name, color_hex) = r?;
        groups.push(TimelineCategoryLane {
            category_id: cat_id,
            name,
            color_hex,
            items: tracks_by_category.remove(&cat_id).unwrap_or_default(),
        });
    }

    Ok(TimelineViewportData {
        from_day,
        to_day,
        context_events,
        groups,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::catalog::{upsert_category, upsert_exposure_item, upsert_safety_behavior};
    use crate::db::open_in_memory_for_test;
    use crate::model::{CategoryInput, ExposureItemInput, SafetyBehaviorInput};

    #[test]
    fn timeline_phases_transition_and_viewport_clipping() {
        let mut conn = open_in_memory_for_test();

        let cat = upsert_category(
            &conn,
            CategoryInput {
                id: None,
                name: "Kontrolle".into(),
                color_hex: "#10B981".into(),
                sort_order: 0,
            },
        )
        .unwrap();
        let item = upsert_exposure_item(
            &conn,
            ExposureItemInput {
                id: None,
                category_id: cat,
                title: "Herd".into(),
                trigger_desc: "".into(),
                core_fear: "".into(),
                typical_response: "".into(),
            },
        )
        .unwrap();
        let sb = upsert_safety_behavior(
            &conn,
            SafetyBehaviorInput {
                id: None,
                exposure_item_id: item,
                label: "Foto".into(),
                notes: "".into(),
            },
        )
        .unwrap();

        // Phase 1: rückwirkend grob im Jahr 2022
        upsert_timeline_phase(
            &mut conn,
            TimelinePhaseInput {
                id: None,
                exposure_item_id: item,
                start: FuzzyDate {
                    day: 19000,
                    precision: DatePrecision::Year,
                },
                end: Some(FuzzyDate {
                    day: 19360,
                    precision: DatePrecision::Year,
                }),
                severity: Severity::Acute,
                active_safety_behavior_ids: vec![sb],
                notes: "Alte Akutphase".into(),
            },
        )
        .unwrap();

        // Phase 2: ab Tag 20000 offen (belastend)
        transition_item_phase(
            &mut conn,
            TransitionPhaseInput {
                exposure_item_id: item,
                effective_day: 20000,
                severity: Severity::Moderate,
                active_safety_behavior_ids: vec![sb],
                notes: "Wieder aktiver".into(),
            },
        )
        .unwrap();

        // Statuswechsel an Tag 20100 -> schließt Phase 2 an Tag 20099 und startet ruhend
        transition_item_phase(
            &mut conn,
            TransitionPhaseInput {
                exposure_item_id: item,
                effective_day: 20100,
                severity: Severity::Dormant,
                active_safety_behavior_ids: vec![],
                notes: "Nach Exposition im Griff".into(),
            },
        )
        .unwrap();

        let all_phases = list_phases_for_item(&conn, item).unwrap();
        assert_eq!(all_phases.len(), 3);
        assert_eq!(all_phases[1].end.unwrap().day, 20099);
        assert_eq!(all_phases[2].severity, Severity::Dormant);
        assert!(all_phases[2].end.is_none());

        // Kontext-Ereignis (Tagesklinik)
        upsert_context_event(
            &conn,
            ContextEventInput {
                id: None,
                title: "Tagesklinik".into(),
                event_type: ContextEventType::Clinic,
                start: FuzzyDate {
                    day: 20050,
                    precision: DatePrecision::Day,
                },
                end: None,
                is_ongoing: true,
                notes: "".into(),
            },
        )
        .unwrap();

        // Viewport 19900..20200 sollte Phase 1 rausfiltern, Phase 2 & 3 + Kontext enthalten
        let vp = get_timeline_viewport(&conn, 19900, 20200, false, false).unwrap();
        assert_eq!(vp.context_events.len(), 1);
        assert_eq!(vp.groups.len(), 1);
        assert_eq!(vp.groups[0].items[0].phases.len(), 2);
        assert_eq!(
            vp.groups[0].items[0].phases[0].active_safety_behavior_ids,
            vec![sb]
        );
    }
}