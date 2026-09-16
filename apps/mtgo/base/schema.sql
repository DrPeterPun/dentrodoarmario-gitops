CREATE DOMAIN PlayerName AS VARCHAR(255);
  -- CHECK (VALUE ~ '^[a-zA-Z0-9_-]{3,20}$');

CREATE TABLE Players (
  id        INT PRIMARY KEY,
  name      PlayerName UNIQUE
);

CREATE TYPE FormatType AS ENUM (
  'Standard',
  'Modern',
  'Pioneer',
  'Vintage',
  'Legacy',
  'Pauper'
);

CREATE TYPE EventType as ENUM (
  'League',
  'Preliminary',
  'Challenge',
  'Showcase',
  'Qualifier'
);

CREATE TABLE Events (
  id        INT PRIMARY KEY,
  name      VARCHAR(255) NOT NULL,
  date      DATE NOT NULL,
  format    FormatType NOT NULL,
  kind      EventType NOT NULL,
  rounds    INT CHECK (rounds >= 3),
  players   INT CHECK (players >= 4)
);

CREATE DOMAIN Percentage AS FLOAT
  CHECK (VALUE >= 0 AND VALUE <= 100);

CREATE DOMAIN RecordType AS VARCHAR(8)
  CHECK (VALUE ~ '^[0-9]+-[0-9]+-[0-9]+$');

CREATE TABLE Standings (
  event_id  INT
    REFERENCES Events (id)
      ON UPDATE CASCADE
      ON DELETE CASCADE,
  rank      INT NOT NULL,
  player    PlayerName
    REFERENCES Players (name)
      ON UPDATE CASCADE
      ON DELETE CASCADE,
  record    RecordType NOT NULL,
  points    INT,
  omwp      Percentage,
  gwp       Percentage,
  owp       Percentage,

  PRIMARY KEY (event_id, player),
  UNIQUE(event_id, rank)
);

CREATE TYPE ResultType AS ENUM ('win', 'loss', 'draw');
CREATE TYPE GameResult AS (id INT, result ResultType);

CREATE TABLE Matches (
  id        INT NULL,
  event_id  INT
    REFERENCES Events (id)
      ON UPDATE CASCADE
      ON DELETE CASCADE,
  round     INT NOT NULL,
  player    PlayerName
    REFERENCES Players (name)
      ON UPDATE CASCADE
      ON DELETE CASCADE,
  opponent  PlayerName NULL
    REFERENCES Players (name)
      ON UPDATE CASCADE
      ON DELETE CASCADE,
  record    RecordType NOT NULL,
  result    ResultType NOT NULL,
  isBye     BOOLEAN DEFAULT FALSE,
  games     GameResult[] DEFAULT ARRAY[]::GameResult[],

  PRIMARY KEY (event_id, round, player)
);

CREATE TYPE CardQuantityPair AS (id INT, name TEXT, quantity INT);

CREATE TABLE Decks (
  id        INT PRIMARY KEY,
  event_id  INT
    REFERENCES Events (id)
      ON UPDATE CASCADE
      ON DELETE CASCADE,
  player    PlayerName
    REFERENCES Players (name)
      ON UPDATE CASCADE
      ON DELETE CASCADE,
  mainboard CardQuantityPair[] DEFAULT ARRAY[]::CardQuantityPair[],
  sideboard CardQuantityPair[] DEFAULT ARRAY[]::CardQuantityPair[]
);

CREATE TABLE Archetypes (
  id        INT PRIMARY KEY,
  deck_id   INT UNIQUE
    REFERENCES Decks (id)
      ON UPDATE CASCADE
      ON DELETE CASCADE,
  name      TEXT NOT NULL,
  archetype TEXT NULL,
  archetype_id INT NULL
);

DO $$ BEGIN
  CREATE TYPE EloScope AS ENUM ('global', 'format');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS PlayerEloCurrent (
  player       PlayerName NOT NULL
    REFERENCES Players(name)
      ON UPDATE CASCADE
      ON DELETE CASCADE,
  scope        EloScope NOT NULL,
  format       FormatType NULL,
  rating       FLOAT NOT NULL,
  games_played INT NOT NULL DEFAULT 0 CHECK (games_played >= 0),
  wins         INT NOT NULL DEFAULT 0 CHECK (wins >= 0),
  losses       INT NOT NULL DEFAULT 0 CHECK (losses >= 0),
  draws        INT NOT NULL DEFAULT 0 CHECK (draws >= 0),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (
    (scope = 'global' AND format IS NULL) OR
    (scope = 'format' AND format IS NOT NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS playerelocurrent_global_uniq
  ON PlayerEloCurrent(player)
  WHERE scope = 'global';

CREATE UNIQUE INDEX IF NOT EXISTS playerelocurrent_format_uniq
  ON PlayerEloCurrent(player, format)
  WHERE scope = 'format';

CREATE TABLE IF NOT EXISTS PlayerEloHistory (
  id            BIGSERIAL PRIMARY KEY,
  player        PlayerName NOT NULL
    REFERENCES Players(name)
      ON UPDATE CASCADE
      ON DELETE CASCADE,
  scope         EloScope NOT NULL,
  format        FormatType NULL,
  rating_before FLOAT NOT NULL,
  rating_after  FLOAT NOT NULL,
  k_factor      FLOAT NULL,
  source_event_id INT NULL
    REFERENCES Events(id)
      ON UPDATE CASCADE
      ON DELETE SET NULL,
  computed_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (
    (scope = 'global' AND format IS NULL) OR
    (scope = 'format' AND format IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_playerelo_current_leaderboard
  ON PlayerEloCurrent(scope, format, rating DESC);

CREATE INDEX IF NOT EXISTS idx_playerelo_history_player_time
  ON PlayerEloHistory(player, scope, format, computed_at DESC);

CREATE TABLE IF NOT EXISTS MatchupSnapshots (
  format       FormatType NOT NULL,
  window_days  INT NOT NULL CHECK (window_days IN (7, 15, 30, 60)),
  as_of_date   DATE NOT NULL,
  deck_a       TEXT NOT NULL,
  deck_b       TEXT NOT NULL,
  wins_a       INT NOT NULL DEFAULT 0 CHECK (wins_a >= 0),
  wins_b       INT NOT NULL DEFAULT 0 CHECK (wins_b >= 0),
  observed_wr  FLOAT NOT NULL CHECK (observed_wr >= 0 AND observed_wr <= 1),
  bayesian_wr  FLOAT NOT NULL CHECK (bayesian_wr >= 0 AND bayesian_wr <= 1),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (format, window_days, as_of_date, deck_a, deck_b)
);

CREATE TABLE IF NOT EXISTS JobRuns (
  id           BIGSERIAL PRIMARY KEY,
  job_name     TEXT NOT NULL,
  started_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  finished_at  TIMESTAMPTZ NULL,
  status       TEXT NOT NULL CHECK (status IN ('started', 'success', 'failed')),
  rows_touched INT NOT NULL DEFAULT 0,
  error        TEXT NULL
);

