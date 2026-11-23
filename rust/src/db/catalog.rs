use crate::db::now_unix_secs;
use crate::model::{
    Category, CategoryGroup, CategoryInput, ExposureItem, ExposureItemInput, SafetyBehavior,
    SafetyBehaviorInput,
};
use anyhow::{bail, Result};
use rusqlite::{params, Connection};
use std::collections::HashMap;

pub fn list_catalog(conn: &Connection, include_archived: bool) -> Result<Vec<CategoryGroup>> {
    // 1. Kategorien laden
    let mut cat_stmt = conn.prepare(
        "SELECT id, name, color_hex, sort_order
         FROM categories
         ORDER BY sort_order ASC, id ASC",
    )?;
    let categories: Vec<Category> = cat_stmt
        .query_map([], |row| {
            Ok(Category {
                id: row.get(0)?,
                name: row.get(1)?,
                color_hex: row.get(2)?,
                sort_order: row.get(3)?,
            })
        })?
        .collect::<rusqlite::Result<_>>()?;

    // 2. Sicherheitsverhalten / Ersatzhandlungen laden und nach exposure_item_id gruppieren
    let sb_sql = if include_archived {
        "SELECT id, exposure_item_id, label, notes, archived
         FROM safety_behaviors
         ORDER BY id ASC"
    } else {
        "SELECT id, exposure_item_id, label, notes, archived
         FROM safety_behaviors
         WHERE archived = 0
         ORDER BY id ASC"
    };
    let mut sb_stmt = conn.prepare(sb_sql)?;
    let mut behaviors_by_item: HashMap<i64, Vec<SafetyBehavior>> = HashMap::new();
    let sb_rows = sb_stmt.query_map([], |row| {
        Ok(SafetyBehavior {
            id: row.get(0)?,
            exposure_item_id: row.get(1)?,
            label: row.get(2)?,
            notes: row.get(3)?,
            archived: row.get::<_, i64>(4)? != 0,
        })
    })?;
    for sb in sb_rows {
        let sb = sb?;
        behaviors_by_item
            .entry(sb.exposure_item_id)
            .or_default()
            .push(sb);
    }

    // 3. Expositionsthemen laden und nach category_id gruppieren
    let item_sql = if include_archived {
        "SELECT id, category_id, title, trigger_desc, core_fear, typical_response, archived, created_at
         FROM exposure_items
         ORDER BY id ASC"
    } else {
        "SELECT id, category_id, title, trigger_desc, core_fear, typical_response, archived, created_at
         FROM exposure_items
         WHERE archived = 0
         ORDER BY id ASC"
    };
    let mut item_stmt = conn.prepare(item_sql)?;
    let mut items_by_category: HashMap<i64, Vec<ExposureItem>> = HashMap::new();
    let item_rows = item_stmt.query_map([], |row| {
        let id: i64 = row.get(0)?;
        Ok(ExposureItem {
            id,
            category_id: row.get(1)?,
            title: row.get(2)?,
            trigger_desc: row.get(3)?,
            core_fear: row.get(4)?,
            typical_response: row.get(5)?,
            archived: row.get::<_, i64>(6)? != 0,
            created_at: row.get(7)?,
            safety_behaviors: Vec::new(),
        })
    })?;
    for item in item_rows {
        let mut item = item?;
        item.safety_behaviors = behaviors_by_item.remove(&item.id).unwrap_or_default();
        items_by_category
            .entry(item.category_id)
            .or_default()
            .push(item);
    }

    // 4. Sauber zusammensetzen (Reihenfolge bleibt erhalten)
    let groups = categories
        .into_iter()
        .map(|category| {
            let items = items_by_category.remove(&category.id).unwrap_or_default();
            CategoryGroup { category, items }
        })
        .collect();

    Ok(groups)
}

pub fn upsert_category(conn: &Connection, input: CategoryInput) -> Result<i64> {
    let name = input.name.trim();
    if name.is_empty() {
        bail!("Kategoriename darf nicht leer sein.");
    }
    let color_hex = input.color_hex.trim();
    if color_hex.is_empty() {
        bail!("Farbcode darf nicht leer sein.");
    }

    match input.id {
        Some(id) => {
            let changed = conn.execute(
                "UPDATE categories
                 SET name = ?1, color_hex = ?2, sort_order = ?3
                 WHERE id = ?4",
                params![name, color_hex, input.sort_order, id],
            )?;
            if changed == 0 {
                bail!("Kategorie {id} nicht gefunden.");
            }
            Ok(id)
        }
        None => {
            conn.execute(
                "INSERT INTO categories (name, color_hex, sort_order)
                 VALUES (?1, ?2, ?3)",
                params![name, color_hex, input.sort_order],
            )?;
            Ok(conn.last_insert_rowid())
        }
    }
}

pub fn delete_category(conn: &Connection, id: i64) -> Result<()> {
    let count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM exposure_items WHERE category_id = ?1",
        params![id],
        |row| row.get(0),
    )?;
    if count > 0 {
        bail!("Kategorie enthält noch {count} Einträge und kann nicht gelöscht werden.");
    }

    let changed = conn.execute("DELETE FROM categories WHERE id = ?1", params![id])?;
    if changed == 0 {
        bail!("Kategorie {id} nicht gefunden.");
    }
    Ok(())
}

pub fn upsert_exposure_item(conn: &Connection, input: ExposureItemInput) -> Result<i64> {
    let title = input.title.trim();
    if title.is_empty() {
        bail!("Titel darf nicht leer sein.");
    }

    match input.id {
        Some(id) => {
            let changed = conn.execute(
                "UPDATE exposure_items
                 SET category_id = ?1, title = ?2, trigger_desc = ?3, core_fear = ?4, typical_response = ?5
                 WHERE id = ?6",
                params![
                    input.category_id,
                    title,
                    input.trigger_desc.trim(),
                    input.core_fear.trim(),
                    input.typical_response.trim(),
                    id
                ],
            )?;
            if changed == 0 {
                bail!("Eintrag {id} nicht gefunden.");
            }
            Ok(id)
        }
        None => {
            let now = now_unix_secs();
            conn.execute(
                "INSERT INTO exposure_items
                 (category_id, title, trigger_desc, core_fear, typical_response, archived, created_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, 0, ?6)",
                params![
                    input.category_id,
                    title,
                    input.trigger_desc.trim(),
                    input.core_fear.trim(),
                    input.typical_response.trim(),
                    now
                ],
            )?;
            Ok(conn.last_insert_rowid())
        }
    }
}

pub fn set_exposure_item_archived(conn: &Connection, id: i64, archived: bool) -> Result<()> {
    let changed = conn.execute(
        "UPDATE exposure_items SET archived = ?1 WHERE id = ?2",
        params![if archived { 1 } else { 0 }, id],
    )?;
    if changed == 0 {
        bail!("Eintrag {id} nicht gefunden.");
    }
    Ok(())
}

pub fn delete_exposure_item(conn: &Connection, id: i64) -> Result<()> {
    let changed = conn.execute("DELETE FROM exposure_items WHERE id = ?1", params![id])?;
    if changed == 0 {
        bail!("Eintrag {id} nicht gefunden.");
    }
    Ok(())
}

pub fn upsert_safety_behavior(conn: &Connection, input: SafetyBehaviorInput) -> Result<i64> {
    let label = input.label.trim();
    if label.is_empty() {
        bail!("Bezeichnung darf nicht leer sein.");
    }

    match input.id {
        Some(id) => {
            let changed = conn.execute(
                "UPDATE safety_behaviors
                 SET label = ?1, notes = ?2
                 WHERE id = ?3",
                params![label, input.notes.trim(), id],
            )?;
            if changed == 0 {
                bail!("Sicherheitsverhalten {id} nicht gefunden.");
            }
            Ok(id)
        }
        None => {
            conn.execute(
                "INSERT INTO safety_behaviors (exposure_item_id, label, notes, archived)
                 VALUES (?1, ?2, ?3, 0)",
                params![input.exposure_item_id, label, input.notes.trim()],
            )?;
            Ok(conn.last_insert_rowid())
        }
    }
}

pub fn set_safety_behavior_archived(conn: &Connection, id: i64, archived: bool) -> Result<()> {
    let changed = conn.execute(
        "UPDATE safety_behaviors SET archived = ?1 WHERE id = ?2",
        params![if archived { 1 } else { 0 }, id],
    )?;
    if changed == 0 {
        bail!("Sicherheitsverhalten {id} nicht gefunden.");
    }
    Ok(())
}

pub fn delete_safety_behavior(conn: &Connection, id: i64) -> Result<()> {
    let changed = conn.execute("DELETE FROM safety_behaviors WHERE id = ?1", params![id])?;
    if changed == 0 {
        bail!("Sicherheitsverhalten {id} nicht gefunden.");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::open_in_memory_for_test;

    #[test]
    fn catalog_crud_and_archiving_flow() {
        let conn = open_in_memory_for_test();

        let cat_id = upsert_category(
            &conn,
            CategoryInput {
                id: None,
                name: "Kontrolle".into(),
                color_hex: "#3B82F6".into(),
                sort_order: 1,
            },
        )
        .unwrap();

        let item_id = upsert_exposure_item(
            &conn,
            ExposureItemInput {
                id: None,
                category_id: cat_id,
                title: "Herd prüfen".into(),
                trigger_desc: "Wohnung verlassen".into(),
                core_fear: "Wohnung brennt ab".into(),
                typical_response: "Dreimal alle Regler anfassen".into(),
            },
        )
        .unwrap();

        let sb_id = upsert_safety_behavior(
            &conn,
            SafetyBehaviorInput {
                id: None,
                exposure_item_id: item_id,
                label: "Foto vom Herd machen".into(),
                notes: "Schleicht sich statt Anfassen ein".into(),
            },
        )
        .unwrap();

        // Kategorie mit Eintrag darf nicht gelöscht werden
        assert!(delete_category(&conn, cat_id).is_err());

        // Katalog abrufen
        let groups = list_catalog(&conn, false).unwrap();
        assert_eq!(groups.len(), 1);
        assert_eq!(groups[0].items.len(), 1);
        assert_eq!(groups[0].items[0].safety_behaviors.len(), 1);
        assert_eq!(
            groups[0].items[0].safety_behaviors[0].label,
            "Foto vom Herd machen"
        );

        // Sicherheitsverhalten archivieren
        set_safety_behavior_archived(&conn, sb_id, true).unwrap();
        assert_eq!(
            list_catalog(&conn, false).unwrap()[0].items[0]
                .safety_behaviors
                .len(),
            0
        );
        assert_eq!(
            list_catalog(&conn, true).unwrap()[0].items[0]
                .safety_behaviors
                .len(),
            1
        );

        // Eintrag löschen (kaskadiert Sicherheitsverhalten), danach Kategorie löschen
        delete_exposure_item(&conn, item_id).unwrap();
        delete_category(&conn, cat_id).unwrap();
        assert!(list_catalog(&conn, true).unwrap().is_empty());
    }
}