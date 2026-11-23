use crate::db::{now_unix_secs, validate_safety_behaviors_belong_to_item};
use crate::model::{
    AddExposureDatapointInput, DatapointFlag, ExposureDatapoint, ExposureSession, FearOutcome,
    FinishExposureSessionInput, SessionStatus, StartExposureSessionInput, UrgeDelay, UrgeOutcome,
};
use anyhow::{bail, Result};
use rusqlite::{params, Connection, OptionalExtension};

fn load_session_by_id(conn: &Connection, session_id: i64) -> Result<Option<ExposureSession>> {
    let row_opt = conn
        .query_row(
            "SELECT id, exposure_item_id, started_at, ended_at, interval_secs, scale_max,
                    expected_fear, expected_conviction_pct, fear_occurred, status, notes
             FROM exposure_sessions
             WHERE id = ?1",
            params![session_id],
            |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, i64>(2)?,
                    row.get::<_, Option<i64>>(3)?,
                    row.get::<_, i64>(4)?,
                    row.get::<_, i32>(5)?,
                    row.get::<_, String>(6)?,
                    row.get::<_, Option<i32>>(7)?,
                    row.get::<_, Option<i64>>(8)?,
                    row.get::<_, i64>(9)?,
                    row.get::<_, String>(10)?,
                ))
            },
        )
        .optional()?;

    let Some((
        id,
        exposure_item_id,
        started_at,
        ended_at,
        interval_secs,
        scale_max,
        expected_fear,
        expected_conviction_pct,
        fear_occurred_raw,
        status_raw,
        notes,
    )) = row_opt
    else {
        return Ok(None);
    };

    let fear_occurred = match fear_occurred_raw {
        Some(v) => Some(FearOutcome::from_db(v)?),
        None => None,
    };
    let status = SessionStatus::from_db(status_raw)?;

    let mut dp_stmt = conn.prepare(
        "SELECT id, session_id, recorded_at, sud_value, flag
         FROM exposure_datapoints
         WHERE session_id = ?1
         ORDER BY recorded_at ASC, id ASC",
    )?;
    let dp_rows = dp_stmt.query_map(params![id], |row| {
        Ok((
            row.get::<_, i64>(0)?,
            row.get::<_, i64>(1)?,
            row.get::<_, i64>(2)?,
            row.get::<_, i32>(3)?,
            row.get::<_, i64>(4)?,
        ))
    })?;
    let mut datapoints = Vec::new();
    for item in dp_rows {
        let (dp_id, dp_session_id, recorded_at, sud_value, flag_raw) = item?;
        datapoints.push(ExposureDatapoint {
            id: dp_id,
            session_id: dp_session_id,
            recorded_at,
            sud_value,
            flag: DatapointFlag::from_db(flag_raw)?,
        });
    }

    let mut sb_stmt = conn.prepare(
        "SELECT safety_behavior_id
         FROM session_safety_behaviors
         WHERE session_id = ?1
         ORDER BY safety_behavior_id ASC",
    )?;
    let used_safety_behavior_ids: Vec<i64> = sb_stmt
        .query_map(params![id], |row| row.get(0))?
        .collect::<rusqlite::Result<_>>()?;

    Ok(Some(ExposureSession {
        id,
        exposure_item_id,
        started_at,
        ended_at,
        interval_secs,
        scale_max,
        expected_fear,
        expected_conviction_pct,
        fear_occurred,
        status,
        notes,
        datapoints,
        used_safety_behavior_ids,
    }))
}

pub fn get_active_exposure_session(conn: &Connection) -> Result<Option<ExposureSession>> {
    let active_id: Option<i64> = conn
        .query_row(
            "SELECT id FROM exposure_sessions
             WHERE status = ?1
             ORDER BY started_at DESC, id DESC
             LIMIT 1",
            params![SessionStatus::Running.to_db()],
            |row| row.get(0),
        )
        .optional()?;

    match active_id {
        Some(id) => load_session_by_id(conn, id),
        None => Ok(None),
    }
}

pub fn start_exposure_session(
    conn: &mut Connection,
    input: StartExposureSessionInput,
) -> Result<ExposureSession> {
    if input.interval_secs <= 0 {
        bail!("Intervall muss größer als 0 Sekunden sein.");
    }
    if input.scale_max != 10 && input.scale_max != 100 {
        bail!("Skala muss 10 oder 100 sein.");
    }
    if input.initial_sud < 0 || input.initial_sud > input.scale_max {
        bail!(
            "Start-Anspannung liegt außerhalb der Skala (0..{}).",
            input.scale_max
        );
    }
    if let Some(pct) = input.expected_conviction_pct {
        if !(0..=100).contains(&pct) {
            bail!("Überzeugungsgrad muss zwischen 0 und 100 liegen.");
        }
    }

    let tx = conn.transaction()?;

    let running_count: i64 = tx.query_row(
        "SELECT COUNT(*) FROM exposure_sessions WHERE status = ?1",
        params![SessionStatus::Running.to_db()],
        |row| row.get(0),
    )?;
    if running_count > 0 {
        bail!("Es läuft bereits eine aktive Expositions-Übung.");
    }

    let now = now_unix_secs();
    tx.execute(
        "INSERT INTO exposure_sessions
         (exposure_item_id, started_at, ended_at, interval_secs, scale_max,
          expected_fear, expected_conviction_pct, fear_occurred, status, notes)
         VALUES (?1, ?2, NULL, ?3, ?4, ?5, ?6, NULL, ?7, '')",
        params![
            input.exposure_item_id,
            now,
            input.interval_secs,
            input.scale_max,
            input.expected_fear.trim(),
            input.expected_conviction_pct,
            SessionStatus::Running.to_db(),
        ],
    )?;
    let session_id = tx.last_insert_rowid();

    // Startwert direkt als ersten Datenpunkt protokollieren
    tx.execute(
        "INSERT INTO exposure_datapoints (session_id, recorded_at, sud_value, flag)
         VALUES (?1, ?2, ?3, ?4)",
        params![
            session_id,
            now,
            input.initial_sud,
            DatapointFlag::CheckIn.to_db(),
        ],
    )?;

    let session = load_session_by_id(&tx, session_id)?
        .ok_or_else(|| anyhow::anyhow!("Gerade angelegte Session nicht gefunden."))?;

    tx.commit()?;
    Ok(session)
}

pub fn add_exposure_datapoint(
    conn: &Connection,
    input: AddExposureDatapointInput,
) -> Result<ExposureDatapoint> {
    let session_meta: Option<(i64, i32)> = conn
        .query_row(
            "SELECT status, scale_max FROM exposure_sessions WHERE id = ?1",
            params![input.session_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()?;

    let Some((status_raw, scale_max)) = session_meta else {
        bail!("Expositions-Übung {} nicht gefunden.", input.session_id);
    };

    if SessionStatus::from_db(status_raw)? != SessionStatus::Running {
        bail!("Datenpunkte können nur für eine laufende Übung hinzugefügt werden.");
    }
    if input.sud_value < 0 || input.sud_value > scale_max {
        bail!("Anspannungswert liegt außerhalb der Skala (0..{scale_max}).");
    }

    let now = now_unix_secs();
    conn.execute(
        "INSERT INTO exposure_datapoints (session_id, recorded_at, sud_value, flag)
         VALUES (?1, ?2, ?3, ?4)",
        params![input.session_id, now, input.sud_value, input.flag.to_db()],
    )?;
    let id = conn.last_insert_rowid();

    Ok(ExposureDatapoint {
        id,
        session_id: input.session_id,
        recorded_at: now,
        sud_value: input.sud_value,
        flag: input.flag,
    })
}

pub fn finish_exposure_session(
    conn: &mut Connection,
    input: FinishExposureSessionInput,
) -> Result<ExposureSession> {
    if input.status == SessionStatus::Running {
        bail!("Abschluss-Status darf nicht Running sein.");
    }

    let tx = conn.transaction()?;

    let session_meta: Option<(i64, i64, i32)> = tx
        .query_row(
            "SELECT exposure_item_id, status, scale_max FROM exposure_sessions WHERE id = ?1",
            params![input.session_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .optional()?;

    let Some((exposure_item_id, status_raw, scale_max)) = session_meta else {
        bail!("Expositions-Übung {} nicht gefunden.", input.session_id);
    };
    if SessionStatus::from_db(status_raw)? != SessionStatus::Running {
        bail!("Expositions-Übung {} ist bereits abgeschlossen.", input.session_id);
    }

    validate_safety_behaviors_belong_to_item(
        &tx,
        exposure_item_id,
        &input.used_safety_behavior_ids,
    )?;

    let now = now_unix_secs();

    if let Some(final_sud) = input.final_sud_value {
        if final_sud < 0 || final_sud > scale_max {
            bail!("Abschluss-Anspannung liegt außerhalb der Skala (0..{scale_max}).");
        }
        let flag = if input.status == SessionStatus::Aborted {
            DatapointFlag::Aborted
        } else {
            DatapointFlag::CheckIn
        };
        tx.execute(
            "INSERT INTO exposure_datapoints (session_id, recorded_at, sud_value, flag)
             VALUES (?1, ?2, ?3, ?4)",
            params![input.session_id, now, final_sud, flag.to_db()],
        )?;
    }

    tx.execute(
        "UPDATE exposure_sessions
         SET ended_at = ?1, fear_occurred = ?2, status = ?3, notes = ?4
         WHERE id = ?5",
        params![
            now,
            input.fear_occurred.map(FearOutcome::to_db),
            input.status.to_db(),
            input.notes.trim(),
            input.session_id,
        ],
    )?;

    tx.execute(
        "DELETE FROM session_safety_behaviors WHERE session_id = ?1",
        params![input.session_id],
    )?;
    for sb_id in &input.used_safety_behavior_ids {
        tx.execute(
            "INSERT OR IGNORE INTO session_safety_behaviors (session_id, safety_behavior_id)
             VALUES (?1, ?2)",
            params![input.session_id, sb_id],
        )?;
    }

    let session = load_session_by_id(&tx, input.session_id)?
        .ok_or_else(|| anyhow::anyhow!("Abgeschlossene Session nicht gefunden."))?;

    tx.commit()?;
    Ok(session)
}

/// Liefert abgeschlossene/abgebrochene Sessions eines Themas (neueste zuerst) für Kurven-Überlagerung.
pub fn list_exposure_sessions_for_item(
    conn: &Connection,
    exposure_item_id: i64,
    limit: u32,
) -> Result<Vec<ExposureSession>> {
    if limit == 0 {
        return Ok(Vec::new());
    }

    let mut stmt = conn.prepare(
        "SELECT id
         FROM exposure_sessions
         WHERE exposure_item_id = ?1 AND status != ?2
         ORDER BY started_at DESC, id DESC
         LIMIT ?3",
    )?;
    let ids: Vec<i64> = stmt
        .query_map(
            params![
                exposure_item_id,
                SessionStatus::Running.to_db(),
                i64::from(limit)
            ],
            |row| row.get(0),
        )?
        .collect::<rusqlite::Result<_>>()?;

    let mut sessions = Vec::with_capacity(ids.len());
    for id in ids {
        if let Some(session) = load_session_by_id(conn, id)? {
            sessions.push(session);
        }
    }
    Ok(sessions)
}

pub fn delete_exposure_session(conn: &Connection, id: i64) -> Result<()> {
    let changed = conn.execute("DELETE FROM exposure_sessions WHERE id = ?1", params![id])?;
    if changed == 0 {
        bail!("Expositions-Übung {id} nicht gefunden.");
    }
    Ok(())
}

// --- Alltags-Aufschub-Timer (Urge Delay) ---

fn map_urge_row(
    row: &rusqlite::Row<'_>,
) -> rusqlite::Result<(i64, Option<i64>, i64, i64, Option<i64>, i64)> {
    Ok((
        row.get(0)?,
        row.get(1)?,
        row.get(2)?,
        row.get(3)?,
        row.get(4)?,
        row.get(5)?,
    ))
}

fn tuple_to_urge(t: (i64, Option<i64>, i64, i64, Option<i64>, i64)) -> Result<UrgeDelay> {
    Ok(UrgeDelay {
        id: t.0,
        exposure_item_id: t.1,
        started_at: t.2,
        target_duration_secs: t.3,
        ended_at: t.4,
        outcome: UrgeOutcome::from_db(t.5)?,
    })
}

pub fn get_active_urge_delay(conn: &Connection) -> Result<Option<UrgeDelay>> {
    let row = conn
        .query_row(
            "SELECT id, exposure_item_id, started_at, target_duration_secs, ended_at, outcome
             FROM urge_delays
             WHERE outcome = ?1
             ORDER BY started_at DESC, id DESC
             LIMIT 1",
            params![UrgeOutcome::Running.to_db()],
            map_urge_row,
        )
        .optional()?;

    match row {
        Some(t) => Ok(Some(tuple_to_urge(t)?)),
        None => Ok(None),
    }
}

pub fn start_urge_delay(
    conn: &Connection,
    exposure_item_id: Option<i64>,
    target_duration_secs: i64,
) -> Result<UrgeDelay> {
    if target_duration_secs <= 0 {
        bail!("Aufschub-Dauer muss größer als 0 Sekunden sein.");
    }

    let running: i64 = conn.query_row(
        "SELECT COUNT(*) FROM urge_delays WHERE outcome = ?1",
        params![UrgeOutcome::Running.to_db()],
        |row| row.get(0),
    )?;
    if running > 0 {
        bail!("Es läuft bereits ein aktiver Aufschub-Timer.");
    }

    let now = now_unix_secs();
    conn.execute(
        "INSERT INTO urge_delays (exposure_item_id, started_at, target_duration_secs, ended_at, outcome)
         VALUES (?1, ?2, ?3, NULL, ?4)",
        params![
            exposure_item_id,
            now,
            target_duration_secs,
            UrgeOutcome::Running.to_db()
        ],
    )?;
    let id = conn.last_insert_rowid();

    Ok(UrgeDelay {
        id,
        exposure_item_id,
        started_at: now,
        target_duration_secs,
        ended_at: None,
        outcome: UrgeOutcome::Running,
    })
}

pub fn finish_urge_delay(conn: &Connection, id: i64, outcome: UrgeOutcome) -> Result<UrgeDelay> {
    if outcome == UrgeOutcome::Running {
        bail!("Abschluss-Ergebnis darf nicht Running sein.");
    }

    let now = now_unix_secs();
    let changed = conn.execute(
        "UPDATE urge_delays
         SET ended_at = ?1, outcome = ?2
         WHERE id = ?3 AND outcome = ?4",
        params![now, outcome.to_db(), id, UrgeOutcome::Running.to_db()],
    )?;
    if changed == 0 {
        bail!("Laufender Aufschub-Timer {id} nicht gefunden.");
    }

    let row = conn.query_row(
        "SELECT id, exposure_item_id, started_at, target_duration_secs, ended_at, outcome
         FROM urge_delays
         WHERE id = ?1",
        params![id],
        map_urge_row,
    )?;
    tuple_to_urge(row)
}

pub fn list_recent_urge_delays(conn: &Connection, limit: u32) -> Result<Vec<UrgeDelay>> {
    if limit == 0 {
        return Ok(Vec::new());
    }

    let mut stmt = conn.prepare(
        "SELECT id, exposure_item_id, started_at, target_duration_secs, ended_at, outcome
         FROM urge_delays
         ORDER BY started_at DESC, id DESC
         LIMIT ?1",
    )?;
    let rows = stmt.query_map(params![i64::from(limit)], map_urge_row)?;
    let mut result = Vec::new();
    for r in rows {
        result.push(tuple_to_urge(r?)?);
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::catalog::{upsert_category, upsert_exposure_item, upsert_safety_behavior};
    use crate::db::open_in_memory_for_test;
    use crate::model::{CategoryInput, ExposureItemInput, SafetyBehaviorInput};

    fn seed_item(conn: &Connection) -> (i64, i64) {
        let cat = upsert_category(
            conn,
            CategoryInput {
                id: None,
                name: "ÖPNV & Enge".into(),
                color_hex: "#2563EB".into(),
                sort_order: 0,
            },
        )
        .unwrap();
        let item = upsert_exposure_item(
            conn,
            ExposureItemInput {
                id: None,
                category_id: cat,
                title: "U-Bahn fahren".into(),
                trigger_desc: "Türen schließen sich".into(),
                core_fear: "Keine Luft bekommen / Ohnmacht".into(),
                typical_response: "An der nächsten Station aussteigen".into(),
            },
        )
        .unwrap();
        let sb = upsert_safety_behavior(
            conn,
            SafetyBehaviorInput {
                id: None,
                exposure_item_id: item,
                label: "Direkt an der Tür stehen".into(),
                notes: "".into(),
            },
        )
        .unwrap();
        (item, sb)
    }

    #[test]
    fn exposure_session_full_lifecycle() {
        let mut conn = open_in_memory_for_test();
        let (item_id, sb_id) = seed_item(&conn);

        assert!(get_active_exposure_session(&conn).unwrap().is_none());

        let started = start_exposure_session(
            &mut conn,
            StartExposureSessionInput {
                exposure_item_id: item_id,
                interval_secs: 300,
                scale_max: 100,
                initial_sud: 75,
                expected_fear: "Ich kippe um".into(),
                expected_conviction_pct: Some(80),
            },
        )
        .unwrap();
        assert_eq!(started.status, SessionStatus::Running);
        assert_eq!(started.datapoints.len(), 1);
        assert_eq!(started.datapoints[0].sud_value, 75);

        // Zweite parallele Session muss blockiert werden
        assert!(start_exposure_session(
            &mut conn,
            StartExposureSessionInput {
                exposure_item_id: item_id,
                interval_secs: 300,
                scale_max: 100,
                initial_sud: 50,
                expected_fear: "".into(),
                expected_conviction_pct: None,
            }
        )
        .is_err());

        // Check-ins protokollieren
        add_exposure_datapoint(
            &conn,
            AddExposureDatapointInput {
                session_id: started.id,
                sud_value: 60,
                flag: DatapointFlag::CheckIn,
            },
        )
        .unwrap();
        add_exposure_datapoint(
            &conn,
            AddExposureDatapointInput {
                session_id: started.id,
                sud_value: 45,
                flag: DatapointFlag::SafetyBehavior,
            },
        )
        .unwrap();

        // Abschließen inkl. Sicherheitsverhalten und Abschlusswert
        let finished = finish_exposure_session(
            &mut conn,
            FinishExposureSessionInput {
                session_id: started.id,
                status: SessionStatus::Completed,
                final_sud_value: Some(30),
                fear_occurred: Some(FearOutcome::No),
                used_safety_behavior_ids: vec![sb_id],
                notes: "Nach 15 Min deutlich ruhiger".into(),
            },
        )
        .unwrap();

        assert_eq!(finished.status, SessionStatus::Completed);
        assert_eq!(finished.datapoints.len(), 4);
        assert_eq!(finished.datapoints[3].sud_value, 30);
        assert_eq!(finished.used_safety_behavior_ids, vec![sb_id]);
        assert_eq!(finished.fear_occurred, Some(FearOutcome::No));
        assert!(get_active_exposure_session(&conn).unwrap().is_none());

        let history = list_exposure_sessions_for_item(&conn, item_id, 10).unwrap();
        assert_eq!(history.len(), 1);
        assert_eq!(history[0].id, started.id);
    }

    #[test]
    fn urge_delay_lifecycle() {
        let conn = open_in_memory_for_test();
        let (item_id, _) = seed_item(&conn);

        let running = start_urge_delay(&conn, Some(item_id), 600).unwrap();
        assert_eq!(running.outcome, UrgeOutcome::Running);
        assert!(get_active_urge_delay(&conn).unwrap().is_some());

        // Paralleler Timer wird geblockt
        assert!(start_urge_delay(&conn, None, 300).is_err());

        let done = finish_urge_delay(&conn, running.id, UrgeOutcome::Subsided).unwrap();
        assert_eq!(done.outcome, UrgeOutcome::Subsided);
        assert!(done.ended_at.is_some());
        assert!(get_active_urge_delay(&conn).unwrap().is_none());
        assert_eq!(list_recent_urge_delays(&conn, 5).unwrap().len(), 1);
    }
}