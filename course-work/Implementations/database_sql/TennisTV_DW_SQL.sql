/* =========================================================
1. CREATE DATA WAREHOUSE DATABASE
   ========================================================= */

IF DB_ID(N'TennisTV_DW') IS NULL
BEGIN
    EXEC(N'CREATE DATABASE TennisTV_DW');
END;
GO

USE TennisTV_DW;
GO


/* =========================================================
2. CREATE DIMENSION TABLES (6 DIMENSIONS)
   ========================================================= */

CREATE TABLE dbo.Dim_User
(
    user_key INT IDENTITY(1,1) PRIMARY KEY,
    user_id INT NOT NULL,
    full_name VARCHAR(101) NOT NULL,
    country VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL,
    is_active BIT NOT NULL
);
GO

CREATE TABLE dbo.Dim_Player
(
    player_key INT IDENTITY(1,1) PRIMARY KEY,
    player_id INT NOT NULL,
    full_name VARCHAR(101) NOT NULL,
    nationality VARCHAR(50) NOT NULL,
    turned_pro INT NULL,
    atp_ranking INT NULL
);
GO

CREATE TABLE dbo.Dim_Tournament
(
    tournament_key INT IDENTITY(1,1) PRIMARY KEY,
    tournament_id INT NOT NULL,
    name VARCHAR(100) NOT NULL,
    category VARCHAR(30) NOT NULL,
    surface VARCHAR(20) NOT NULL,
    city VARCHAR(50) NOT NULL,
    country VARCHAR(50) NOT NULL
);
GO

CREATE TABLE dbo.Dim_Match
(
    match_key INT IDENTITY(1,1) PRIMARY KEY,
    match_id INT NOT NULL,
    round VARCHAR(30) NOT NULL,
    court_name VARCHAR(50) NULL,
    status VARCHAR(20) NOT NULL
);
GO

CREATE TABLE dbo.Dim_Plan
(
    plan_key INT IDENTITY(1,1) PRIMARY KEY,
    plan_type VARCHAR(20) NOT NULL,
    status VARCHAR(20) NOT NULL
);
GO

CREATE TABLE dbo.Dim_Date
(
    date_key INT PRIMARY KEY, -- YYYYMMDD
    full_date DATE NOT NULL,
    [year] INT NOT NULL,
    [quarter] INT NOT NULL,
    month_number INT NOT NULL,
    month_name VARCHAR(20) NOT NULL,
    day_of_week VARCHAR(15) NOT NULL
);
GO


/* =========================================================
3. CREATE FACT TABLES (3 FACT TABLES)
   ========================================================= */

CREATE TABLE dbo.Fact_Stream_Sessions
(
    stream_fact_id INT IDENTITY(1,1) PRIMARY KEY,
    user_key INT NOT NULL,
    match_key INT NOT NULL,
    tournament_key INT NULL, -- NULL за демонстративни мачове извън турнир
    date_key INT NOT NULL,
    video_quality VARCHAR(10) NOT NULL,
    watch_duration_min INT NOT NULL,
    session_count INT NOT NULL DEFAULT 1,

    CONSTRAINT FK_FactStream_User FOREIGN KEY (user_key) REFERENCES dbo.Dim_User(user_key),
    CONSTRAINT FK_FactStream_Match FOREIGN KEY (match_key) REFERENCES dbo.Dim_Match(match_key),
    CONSTRAINT FK_FactStream_Tournament FOREIGN KEY (tournament_key) REFERENCES dbo.Dim_Tournament(tournament_key),
    CONSTRAINT FK_FactStream_Date FOREIGN KEY (date_key) REFERENCES dbo.Dim_Date(date_key)
);
GO

CREATE TABLE dbo.Fact_Subscriptions
(
    sub_fact_id INT IDENTITY(1,1) PRIMARY KEY,
    user_key INT NOT NULL,
    plan_key INT NOT NULL,
    date_key INT NOT NULL,
    revenue_amount DECIMAL(6,2) NOT NULL,
    duration_days INT NOT NULL,

    CONSTRAINT FK_FactSub_User FOREIGN KEY (user_key) REFERENCES dbo.Dim_User(user_key),
    CONSTRAINT FK_FactSub_Plan FOREIGN KEY (plan_key) REFERENCES dbo.Dim_Plan(plan_key),
    CONSTRAINT FK_FactSub_Date FOREIGN KEY (date_key) REFERENCES dbo.Dim_Date(date_key)
);
GO

CREATE TABLE dbo.Fact_Match_Performance
(
    perf_fact_id INT IDENTITY(1,1) PRIMARY KEY,
    match_key INT NOT NULL,
    tournament_key INT NULL, -- NULL за демонстративни мачове извън турнир
    player_key INT NOT NULL,
    date_key INT NOT NULL,
    match_duration_min INT NOT NULL,
    is_winner INT NOT NULL,
    is_seed INT NOT NULL,

    CONSTRAINT FK_FactPerf_Match FOREIGN KEY (match_key) REFERENCES dbo.Dim_Match(match_key),
    CONSTRAINT FK_FactPerf_Tournament FOREIGN KEY (tournament_key) REFERENCES dbo.Dim_Tournament(tournament_key),
    CONSTRAINT FK_FactPerf_Player FOREIGN KEY (player_key) REFERENCES dbo.Dim_Player(player_key),
    CONSTRAINT FK_FactPerf_Date FOREIGN KEY (date_key) REFERENCES dbo.Dim_Date(date_key)
);
GO


/* =========================================================
4. ETL: POPULATE DIMENSIONS FROM TennisTV_DB
   ========================================================= */

-- Генериране на календар за 2026 г.
DECLARE @d DATE = '2026-01-01';
WHILE @d <= '2026-12-31'
BEGIN
    INSERT INTO dbo.Dim_Date (date_key, full_date, [year], [quarter], month_number, month_name, day_of_week)
    VALUES (
        CONVERT(INT, FORMAT(@d, 'yyyyMMdd')),
        @d,
        YEAR(@d),
        DATEPART(QUARTER, @d),
        MONTH(@d),
        DATENAME(MONTH, @d),
        DATENAME(WEEKDAY, @d)
    );
    SET @d = DATEADD(DAY, 1, @d);
END;

INSERT INTO dbo.Dim_User (user_id, full_name, country, email, is_active)
SELECT user_id, first_name + ' ' + last_name, country, email, is_active
FROM TennisTV_DB.dbo.[USER];

INSERT INTO dbo.Dim_Player (player_id, full_name, nationality, turned_pro, atp_ranking)
SELECT player_id, first_name + ' ' + last_name, nationality, turned_pro, atp_ranking
FROM TennisTV_DB.dbo.PLAYER;

INSERT INTO dbo.Dim_Tournament (tournament_id, name, category, surface, city, country)
SELECT tournament_id, name, category, surface, city, country
FROM TennisTV_DB.dbo.TOURNAMENT;

INSERT INTO dbo.Dim_Match (match_id, round, court_name, status)
SELECT match_id, round, court_name, status
FROM TennisTV_DB.dbo.[MATCH];

INSERT INTO dbo.Dim_Plan (plan_type, status)
SELECT DISTINCT plan_type, status
FROM TennisTV_DB.dbo.SUBSCRIPTION;
GO


/* =========================================================
5. ETL: POPULATE FACT TABLES
   ========================================================= */

INSERT INTO dbo.Fact_Subscriptions (user_key, plan_key, date_key, revenue_amount, duration_days)
SELECT 
    du.user_key,
    dp.plan_key,
    CONVERT(INT, FORMAT(s.start_date, 'yyyyMMdd')),
    s.price,
    DATEDIFF(DAY, s.start_date, s.end_date)
FROM TennisTV_DB.dbo.SUBSCRIPTION AS s
INNER JOIN dbo.Dim_User AS du ON du.user_id = s.user_id
INNER JOIN dbo.Dim_Plan AS dp ON dp.plan_type = s.plan_type AND dp.status = s.status;

INSERT INTO dbo.Fact_Stream_Sessions (user_key, match_key, tournament_key, date_key, video_quality, watch_duration_min, session_count)
SELECT 
    du.user_key,
    dm.match_key,
    dt.tournament_key,
    CONVERT(INT, FORMAT(CAST(ss.start_time AS DATE), 'yyyyMMdd')),
    ss.video_quality,
    ISNULL(DATEDIFF(MINUTE, ss.start_time, ss.end_time), 90),
    1
FROM TennisTV_DB.dbo.STREAM_SESSION AS ss
INNER JOIN TennisTV_DB.dbo.[MATCH] AS m ON m.match_id = ss.match_id
INNER JOIN dbo.Dim_User AS du ON du.user_id = ss.user_id
INNER JOIN dbo.Dim_Match AS dm ON dm.match_id = ss.match_id
LEFT JOIN dbo.Dim_Tournament AS dt ON dt.tournament_id = m.tournament_id;

INSERT INTO dbo.Fact_Match_Performance (match_key, tournament_key, player_key, date_key, match_duration_min, is_winner, is_seed)
SELECT 
    dm.match_key,
    dt.tournament_key,
    dpl.player_key,
    CONVERT(INT, FORMAT(CAST(m.match_date AS DATE), 'yyyyMMdd')),
    m.duration,
    CASE WHEN m.winner_player_id = mp.player_id THEN 1 ELSE 0 END,
    CAST(mp.is_seed AS INT)
FROM TennisTV_DB.dbo.MATCH_PLAYER AS mp
INNER JOIN TennisTV_DB.dbo.[MATCH] AS m ON m.match_id = mp.match_id
INNER JOIN dbo.Dim_Match AS dm ON dm.match_id = m.match_id
LEFT JOIN dbo.Dim_Tournament AS dt ON dt.tournament_id = m.tournament_id
INNER JOIN dbo.Dim_Player AS dpl ON dpl.player_id = mp.player_id;
GO

/* =========================================================
6. VERIFY DATA WAREHOUSE
   ========================================================= */
SELECT * FROM dbo.Fact_Stream_Sessions;
SELECT * FROM dbo.Fact_Subscriptions;
SELECT * FROM dbo.Fact_Match_Performance;
GO