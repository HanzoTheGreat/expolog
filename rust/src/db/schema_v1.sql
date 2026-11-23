PRAGMA foreign_keys = ON;

CREATE TABLE app_meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- Reine visuelle Ordner (kein eigener Akutheits-Status)
CREATE TABLE categories (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    name       TEXT NOT NULL,
    color_hex  TEXT NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0
);

-- Das Kernobjekt für Exposition und Zeitstrahl (Auslöser / Thema / Zwang)
CREATE TABLE exposure_items (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    category_id      INTEGER NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
    title            TEXT NOT NULL,
    trigger_desc     TEXT NOT NULL DEFAULT '',
    core_fear        TEXT NOT NULL DEFAULT '',
    typical_response TEXT NOT NULL DEFAULT '',
    archived         INTEGER NOT NULL DEFAULT 0, -- 0 = aktiv, 1 = archiviert
    created_at       INTEGER NOT NULL
);

-- Strikt an ein konkretes Expositionsthema gebunden (Sicherheitsverhalten / Ersatzhandlung)
CREATE TABLE safety_behaviors (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    exposure_item_id INTEGER NOT NULL REFERENCES exposure_items(id) ON DELETE CASCADE,
    label            TEXT NOT NULL,
    notes            TEXT NOT NULL DEFAULT '',
    archived         INTEGER NOT NULL DEFAULT 0
);

-- Zustandsphasen auf dem Zeitstrahl (Zustandswechsel statt Tageszwang)
CREATE TABLE timeline_phases (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    exposure_item_id INTEGER NOT NULL REFERENCES exposure_items(id) ON DELETE CASCADE,
    start_day        INTEGER NOT NULL,
    start_precision  INTEGER NOT NULL, -- 0=Day, 1=Month, 2=Quarter, 3=Year
    end_day          INTEGER,          -- NULL = laufend bis heute
    end_precision    INTEGER,          -- NULL wenn end_day NULL
    severity         INTEGER NOT NULL, -- 0=ruhend, 1=Hintergrund, 2=belastend, 3=akut
    notes            TEXT NOT NULL DEFAULT ''
);

CREATE TABLE phase_safety_behaviors (
    phase_id           INTEGER NOT NULL REFERENCES timeline_phases(id) ON DELETE CASCADE,
    safety_behavior_id INTEGER NOT NULL REFERENCES safety_behaviors(id) ON DELETE CASCADE,
    PRIMARY KEY (phase_id, safety_behavior_id)
);

-- Kontext-Spur (Klinik, Medikation, Therapie, Lebensereignisse)
CREATE TABLE context_events (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    title           TEXT NOT NULL,
    event_type      INTEGER NOT NULL, -- 0=Klinik, 1=Medikation, 2=Therapie, 3=Leben
    start_day       INTEGER NOT NULL,
    start_precision INTEGER NOT NULL,
    end_day         INTEGER,          -- NULL = punktuelles Ereignis oder offen
    end_precision   INTEGER,
    is_ongoing      INTEGER NOT NULL DEFAULT 0,
    notes           TEXT NOT NULL DEFAULT ''
);

-- Expositions-Übungssitzungen (robust gegen App-Kill via status + started_at)
CREATE TABLE exposure_sessions (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    exposure_item_id        INTEGER NOT NULL REFERENCES exposure_items(id) ON DELETE CASCADE,
    started_at              INTEGER NOT NULL,
    ended_at                INTEGER,          -- NULL solange laufend
    interval_secs           INTEGER NOT NULL,
    scale_max               INTEGER NOT NULL, -- 10 oder 100 (pro Session fixiert)
    expected_fear           TEXT NOT NULL DEFAULT '',
    expected_conviction_pct INTEGER,          -- 0..100, optional
    fear_occurred           INTEGER,          -- NULL=offen, 0=Nein, 1=Teilweise, 2=Ja
    status                  INTEGER NOT NULL, -- 0=Running, 1=Completed, 2=Aborted
    notes                   TEXT NOT NULL DEFAULT ''
);

CREATE TABLE exposure_datapoints (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id  INTEGER NOT NULL REFERENCES exposure_sessions(id) ON DELETE CASCADE,
    recorded_at INTEGER NOT NULL,
    sud_value   INTEGER NOT NULL,
    flag        INTEGER NOT NULL DEFAULT 0 -- 0=CheckIn, 1=AvoidanceOrRitual, 2=SafetyBehavior, 3=Aborted
);

CREATE TABLE session_safety_behaviors (
    session_id         INTEGER NOT NULL REFERENCES exposure_sessions(id) ON DELETE CASCADE,
    safety_behavior_id INTEGER NOT NULL REFERENCES safety_behaviors(id) ON DELETE CASCADE,
    PRIMARY KEY (session_id, safety_behavior_id)
);

-- Spontaner Alltags-Aufschub-Timer
CREATE TABLE urge_delays (
    id                   INTEGER PRIMARY KEY AUTOINCREMENT,
    exposure_item_id     INTEGER REFERENCES exposure_items(id) ON DELETE SET NULL,
    started_at           INTEGER NOT NULL,
    target_duration_secs INTEGER NOT NULL,
    ended_at             INTEGER,
    outcome              INTEGER NOT NULL DEFAULT 0 -- 0=Running, 1=Subsided, 2=Extended, 3=Performed
);

CREATE INDEX idx_phases_item_day ON timeline_phases(exposure_item_id, start_day);
CREATE INDEX idx_sessions_item_time ON exposure_sessions(exposure_item_id, started_at);
CREATE INDEX idx_datapoints_session_time ON exposure_datapoints(session_id, recorded_at);
CREATE INDEX idx_context_day ON context_events(start_day);