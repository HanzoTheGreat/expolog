pub mod catalog;
pub mod exposure;
pub mod timeline;

use anyhow::{bail, Context, Result};
use rusqlite::{params, Connection, OptionalExtension};
use std::time::{SystemTime, UNIX_EPOCH};

const SCHEMA_V1: &str = include_str!("schema_v1.sql");

pub fn open_encrypted_db(db_path: &str, passphrase: &str) -> Result<Connection> {
    let conn = Connection::open(db_path).context("DB-Datei konnte nicht geöffnet werden")?;

    // PRAGMA key muss die allererste Anweisung nach dem Öffnen sein
    conn.pragma_update(None, "key", passphrase)?;
    conn.pragma_update(None, "foreign_keys", "ON")?;

    // Prüft sofort, ob Passphrase korrekt / DB lesbar ist
    let _: i64 = conn
        .query_row("SELECT count(*) FROM sqlite_master;", [], |r| r.get(0))
        .context("Passphrase ungültig oder DB beschädigt")?;

    // Schema-Initialisierung via PRAGMA user_version
    let version: u32 = conn.pragma_query_value(None, "user_version", |r| r.get(0))?;
    if version == 0 {
        conn.execute_batch(SCHEMA_V1)?;
        conn.pragma_update(None, "user_version", 1u32)?;
    }

    Ok(conn)
}

pub fn now_unix_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// Stellt sicher, dass alle angegebenen Sicherheitsverhalten existieren und exakt zu diesem Thema gehören.
pub(crate) fn validate_safety_behaviors_belong_to_item(
    conn: &Connection,
    exposure_item_id: i64,
    safety_behavior_ids: &[i64],
) -> Result<()> {
    for &sb_id in safety_behavior_ids {
        let owner: Option<i64> = conn
            .query_row(
                "SELECT exposure_item_id FROM safety_behaviors WHERE id = ?1",
                params![sb_id],
                |row| row.get(0),
            )
            .optional()?;
        match owner {
            Some(owner_id) if owner_id == exposure_item_id => {}
            Some(_) => {
                bail!("Sicherheitsverhalten {sb_id} gehört nicht zu Thema {exposure_item_id}.")
            }
            None => bail!("Sicherheitsverhalten {sb_id} nicht gefunden."),
        }
    }
    Ok(())
}

#[cfg(test)]
pub(crate) fn open_in_memory_for_test() -> Connection {
    let conn = Connection::open_in_memory().expect("In-Memory-DB fehlgeschlagen");
    conn.pragma_update(None, "foreign_keys", "ON")
        .expect("foreign_keys fehlgeschlagen");
    conn.execute_batch(SCHEMA_V1)
        .expect("Schema-Initialisierung fehlgeschlagen");
    conn.pragma_update(None, "user_version", 1u32)
        .expect("user_version fehlgeschlagen");
    conn
}