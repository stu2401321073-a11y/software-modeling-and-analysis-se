
/* =========================================================
   1. CREATE DATABASE
   ========================================================= */

IF DB_ID(N'TennisTV_DB') IS NULL
BEGIN
    EXEC(N'CREATE DATABASE TennisTV_DB');
END;
GO

USE TennisTV_DB;
GO


/* =========================================================
   2. CREATE TABLES
   ========================================================= */

CREATE TABLE dbo.[USER]
(
    user_id INT IDENTITY(1,1) PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    country VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    registration_date DATETIME NOT NULL DEFAULT GETDATE(),
    is_active BIT NOT NULL DEFAULT 1
);
GO

CREATE TABLE dbo.USER_PREFERRED_SURFACE
(
    user_id INT NOT NULL,
    surface VARCHAR(20) NOT NULL,

    CONSTRAINT PK_USER_PREFERRED_SURFACE
        PRIMARY KEY (user_id, surface),

    CONSTRAINT FK_PreferredSurface_User
        FOREIGN KEY (user_id)
        REFERENCES dbo.[USER](user_id)
        ON DELETE CASCADE,

    CONSTRAINT CK_PreferredSurface_Surface
        CHECK (surface IN ('Hard', 'Clay', 'Grass'))
);
GO

CREATE TABLE dbo.SUBSCRIPTION
(
    subscription_id INT IDENTITY(1,1) PRIMARY KEY,
    user_id INT NOT NULL,
    plan_type VARCHAR(20) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    price DECIMAL(6,2) NOT NULL,
    status VARCHAR(20) NOT NULL,

    CONSTRAINT FK_Subscription_User
        FOREIGN KEY (user_id)
        REFERENCES dbo.[USER](user_id)
        ON DELETE CASCADE,

    CONSTRAINT CK_Subscription_Plan
        CHECK (plan_type IN ('Monthly', 'Annual')),

    CONSTRAINT CK_Subscription_Status
        CHECK (status IN ('Active', 'Cancelled', 'Expired')),

    CONSTRAINT CK_Subscription_Dates
        CHECK (end_date >= start_date),

    CONSTRAINT CK_Subscription_Price
        CHECK (price >= 0)
);
GO

CREATE TABLE dbo.PLAYER
(
    player_id INT IDENTITY(1,1) PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    date_of_birth DATE NOT NULL,
    nationality VARCHAR(50) NOT NULL,
    turned_pro INT,
    atp_ranking INT,

    CONSTRAINT CK_Player_TurnedPro
        CHECK (turned_pro IS NULL OR
               turned_pro BETWEEN 1900 AND 2100),

    CONSTRAINT CK_Player_Ranking
        CHECK (atp_ranking IS NULL OR atp_ranking > 0)
);
GO

CREATE TABLE dbo.TOURNAMENT
(
    tournament_id INT IDENTITY(1,1) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    category VARCHAR(30) NOT NULL,
    surface VARCHAR(20) NOT NULL,
    city VARCHAR(50) NOT NULL,
    country VARCHAR(50) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,

    CONSTRAINT CK_Tournament_Category
        CHECK (category IN
        ('ATP 250', 'ATP 500', 'ATP Masters 1000',
         'ATP Finals', 'Grand Slam')),

    CONSTRAINT CK_Tournament_Surface
        CHECK (surface IN ('Hard', 'Clay', 'Grass')),

    CONSTRAINT CK_Tournament_Dates
        CHECK (end_date >= start_date)
);
GO

CREATE TABLE dbo.[MATCH]
(
    match_id INT IDENTITY(1,1) PRIMARY KEY,
    tournament_id INT NULL,
    winner_player_id INT NULL,
    round VARCHAR(30) NOT NULL,
    match_date DATETIME NOT NULL,
    court_name VARCHAR(50),
    status VARCHAR(20) NOT NULL DEFAULT 'Scheduled',
    duration INT NOT NULL DEFAULT 0,

    CONSTRAINT FK_Match_Tournament
        FOREIGN KEY (tournament_id)
        REFERENCES dbo.TOURNAMENT(tournament_id),

    CONSTRAINT FK_Match_Winner
        FOREIGN KEY (winner_player_id)
        REFERENCES dbo.PLAYER(player_id),

    CONSTRAINT CK_Match_Status
        CHECK (status IN
        ('Scheduled', 'Live', 'Completed', 'Cancelled')),

    CONSTRAINT CK_Match_Duration
        CHECK (duration >= 0),

    CONSTRAINT CK_Match_WinnerStatus
        CHECK (
            (status = 'Completed' AND winner_player_id IS NOT NULL)
            OR
            (status <> 'Completed' AND winner_player_id IS NULL)
        )
);
GO

CREATE TABLE dbo.MATCH_PLAYER
(
    match_id INT NOT NULL,
    player_id INT NOT NULL,
    is_seed BIT NOT NULL DEFAULT 0,

    CONSTRAINT PK_MATCH_PLAYER
        PRIMARY KEY (match_id, player_id),

    CONSTRAINT FK_MatchPlayer_Match
        FOREIGN KEY (match_id)
        REFERENCES dbo.[MATCH](match_id)
        ON DELETE CASCADE,

    CONSTRAINT FK_MatchPlayer_Player
        FOREIGN KEY (player_id)
        REFERENCES dbo.PLAYER(player_id)
);
GO

CREATE TABLE dbo.USER_FAVORITE_PLAYER
(
    user_id INT NOT NULL,
    player_id INT NOT NULL,
    added_date DATETIME NOT NULL DEFAULT GETDATE(),
    notifications_enabled BIT NOT NULL DEFAULT 1,

    CONSTRAINT PK_USER_FAVORITE_PLAYER
        PRIMARY KEY (user_id, player_id),

    CONSTRAINT FK_FavoritePlayer_User
        FOREIGN KEY (user_id)
        REFERENCES dbo.[USER](user_id)
        ON DELETE CASCADE,

    CONSTRAINT FK_FavoritePlayer_Player
        FOREIGN KEY (player_id)
        REFERENCES dbo.PLAYER(player_id)
);
GO

CREATE TABLE dbo.STREAM_SESSION
(
    session_id INT IDENTITY(1,1) PRIMARY KEY,
    user_id INT NOT NULL,
    match_id INT NOT NULL,
    ip_address VARCHAR(45),
    start_time DATETIME NOT NULL DEFAULT GETDATE(),
    end_time DATETIME NULL,
    video_quality VARCHAR(10) NOT NULL,

    CONSTRAINT FK_StreamSession_User
        FOREIGN KEY (user_id)
        REFERENCES dbo.[USER](user_id)
        ON DELETE CASCADE,

    CONSTRAINT FK_StreamSession_Match
        FOREIGN KEY (match_id)
        REFERENCES dbo.[MATCH](match_id),

    CONSTRAINT CK_StreamSession_Quality
        CHECK (video_quality IN ('720p', '1080p', '4K')),

    CONSTRAINT CK_StreamSession_Times
        CHECK (end_time IS NULL OR end_time >= start_time)
);
GO


/* =========================================================
   3. FUNCTION: CALCULATE PLAYER AGE
   ========================================================= */

CREATE OR ALTER FUNCTION dbo.fn_CalculatePlayerAge
(
    @date_of_birth DATE
)
RETURNS INT
AS
BEGIN
    IF @date_of_birth IS NULL
        RETURN NULL;

    IF @date_of_birth > CAST(GETDATE() AS DATE)
        RETURN NULL;

    RETURN
        DATEDIFF(YEAR, @date_of_birth, GETDATE())
        -
        CASE
            WHEN DATEADD(
                YEAR,
                DATEDIFF(YEAR, @date_of_birth, GETDATE()),
                @date_of_birth
            ) > CAST(GETDATE() AS DATE)
            THEN 1
            ELSE 0
        END;
END;
GO


/* =========================================================
   4. TRIGGER: VALIDATE STREAM SESSION INSERTS
   ========================================================= */

CREATE OR ALTER TRIGGER dbo.trg_CheckActiveSubscriptionOnStream
ON dbo.STREAM_SESSION
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- Every user must exist, be active and have
    -- a currently valid subscription.

    IF EXISTS
    (
        SELECT 1
        FROM inserted AS I
        INNER JOIN dbo.[USER] AS U
            ON U.user_id = I.user_id
        WHERE U.is_active = 0
    )
    BEGIN
        ROLLBACK TRANSACTION;

        THROW 50004,
              'Inactive users cannot start a stream.',
              1;
    END;

    IF EXISTS
    (
        SELECT 1
        FROM inserted AS I
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dbo.SUBSCRIPTION AS S
            WHERE S.user_id = I.user_id
              AND S.status = 'Active'
              AND S.start_date <= CAST(GETDATE() AS DATE)
              AND S.end_date >= CAST(GETDATE() AS DATE)
        )
    )
    BEGIN
        ROLLBACK TRANSACTION;

        THROW 50005,
              'An active subscription is required to stream.',
              1;
    END;
END;
GO


/* =========================================================
   5. PROCEDURE: START STREAM SESSION
   ========================================================= */

CREATE OR ALTER PROCEDURE dbo.sp_StartStreamSession
    @user_id INT,
    @match_id INT,
    @ip_address VARCHAR(45),
    @quality VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;

    -- Validate user
    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.[USER]
        WHERE user_id = @user_id
    )
    BEGIN
        THROW 50001, 'User does not exist.', 1;
    END;

    -- Validate active user
    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.[USER]
        WHERE user_id = @user_id
          AND is_active = 1
    )
    BEGIN
        THROW 50002, 'User account is inactive.', 1;
    END;

    -- Validate match
    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.[MATCH]
        WHERE match_id = @match_id
    )
    BEGIN
        THROW 50003, 'Match does not exist.', 1;
    END;

    -- Validate video quality
    IF @quality IS NULL
       OR @quality NOT IN ('720p', '1080p', '4K')
    BEGIN
        THROW 50006, 'Invalid video quality.', 1;
    END;

    -- Validate subscription
    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.SUBSCRIPTION
        WHERE user_id = @user_id
          AND status = 'Active'
          AND start_date <= CAST(GETDATE() AS DATE)
          AND end_date >= CAST(GETDATE() AS DATE)
    )
    BEGIN
        THROW 50007,
              'You do not have a valid active subscription.',
              1;
    END;

    -- Insert session. The trigger validates it again.
    INSERT INTO dbo.STREAM_SESSION
    (
        user_id,
        match_id,
        ip_address,
        start_time,
        video_quality
    )
    VALUES
    (
        @user_id,
        @match_id,
        @ip_address,
        GETDATE(),
        @quality
    );

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS new_session_id;
END;
GO


/* =========================================================
6. INSERT SAMPLE DATA (EXTENDED FOR POWER BI)
   ========================================================= */

-- 1. USERS (8 потребители от различни държави)
INSERT INTO dbo.[USER]
    (first_name, last_name, country, email, password_hash, is_active)
VALUES
    ('Ivan', 'Ivanov', 'Bulgaria', 'ivan@tennistv.com', 'hash_123', 1),
    ('John', 'Smith', 'UK', 'john@tennistv.com', 'hash_456', 1),
    ('Marco', 'Rossi', 'Italy', 'marco@tennistv.com', 'hash_789', 1),
    ('Elena', 'Petrova', 'Bulgaria', 'elena@tennistv.com', 'hash_101', 1),
    ('Carlos', 'Gomez', 'Spain', 'carlos@tennistv.com', 'hash_102', 1),
    ('Sophie', 'Dubois', 'France', 'sophie@tennistv.com', 'hash_103', 1),
    ('Lukas', 'Muller', 'Germany', 'lukas@tennistv.com', 'hash_104', 1),
    ('Alex', 'Johnson', 'USA', 'alex@tennistv.com', 'hash_105', 0); -- Неактивен потребител

-- 2. USER PREFERRED SURFACE
INSERT INTO dbo.USER_PREFERRED_SURFACE (user_id, surface)
VALUES
    (1, 'Hard'), (1, 'Grass'),
    (2, 'Clay'),
    (3, 'Hard'), (3, 'Clay'),
    (4, 'Grass'),
    (5, 'Clay'),
    (6, 'Clay'), (6, 'Hard'),
    (7, 'Grass');

-- 3. SUBSCRIPTIONS (10 абонамента за разнообразни приходи)
INSERT INTO dbo.SUBSCRIPTION
    (user_id, plan_type, start_date, end_date, price, status)
VALUES
    (1, 'Annual',  '2026-01-01', '2027-01-01', 109.99, 'Active'),
    (2, 'Monthly', '2026-03-01', '2026-04-01', 14.99,  'Expired'),
    (3, 'Annual',  '2026-02-15', '2027-02-15', 109.99, 'Active'),
    (4, 'Annual',  '2026-01-10', '2027-01-10', 109.99, 'Active'),
    (5, 'Monthly', '2026-05-01', '2026-12-31', 14.99,  'Active'),
    (6, 'Annual',  '2026-04-01', '2027-04-01', 109.99, 'Active'),
    (7, 'Monthly', '2026-06-01', '2026-12-31', 14.99,  'Active'),
    (2, 'Annual',  '2026-05-01', '2027-05-01', 109.99, 'Active'), -- Подновил абонамента
    (8, 'Monthly', '2026-01-01', '2026-02-01', 14.99,  'Cancelled');

-- 4. PLAYERS (8 топ тенисисти)
INSERT INTO dbo.PLAYER
    (first_name, last_name, date_of_birth, nationality, turned_pro, atp_ranking)
VALUES
    ('Jannik', 'Sinner', '2001-08-16', 'Italy', 2018, 1),
    ('Carlos', 'Alcaraz', '2003-05-05', 'Spain', 2018, 2),
    ('Grigor', 'Dimitrov', '1991-05-16', 'Bulgaria', 2008, 10),
    ('Novak', 'Djokovic', '1987-05-22', 'Serbia', 2003, 4),
    ('Alexander', 'Zverev', '1997-04-20', 'Germany', 2013, 3),
    ('Daniil', 'Medvedev', '1996-02-11', 'Russia', 2014, 5),
    ('Taylor', 'Fritz', '1997-10-28', 'USA', 2015, 6),
    ('Casper', 'Ruud', '1998-12-22', 'Norway', 2015, 7);

-- 5. TOURNAMENTS (5 турнира на различни настилки)
INSERT INTO dbo.TOURNAMENT
    (name, category, surface, city, country, start_date, end_date)
VALUES
    ('Indian Wells Open', 'ATP Masters 1000', 'Hard', 'Indian Wells', 'USA', '2026-03-04', '2026-03-17'),
    ('Monte-Carlo Masters', 'ATP Masters 1000', 'Clay', 'Monte Carlo', 'Monaco', '2026-04-05', '2026-04-12'),
    ('Wimbledon', 'Grand Slam', 'Grass', 'London', 'UK', '2026-06-29', '2026-07-12'),
    ('Roland Garros', 'Grand Slam', 'Clay', 'Paris', 'France', '2026-05-24', '2026-06-07'),
    ('US Open', 'Grand Slam', 'Hard', 'New York', 'USA', '2026-08-31', '2026-09-13');

-- 6. MATCHES (8 мача, включително 1 демонстративен без турнир)
INSERT INTO dbo.[MATCH]
    (tournament_id, winner_player_id, round, match_date, court_name, status, duration)
VALUES
    (1, 1, 'Final', '2026-03-17T20:00:00', 'Center Court', 'Completed', 142),
    (2, 2, 'Semi-Final', '2026-04-11T15:30:00', 'Court Rainier III', 'Completed', 115),
    (3, 3, 'Quarter-Final', '2026-07-08T14:00:00', 'Centre Court', 'Completed', 168),
    (4, 2, 'Final', '2026-06-07T15:00:00', 'Court Philippe-Chatrier', 'Completed', 210),
    (4, 4, 'Semi-Final', '2026-06-05T17:30:00', 'Court Philippe-Chatrier', 'Completed', 185),
    (5, 1, 'Final', '2026-09-13T16:00:00', 'Arthur Ashe Stadium', 'Completed', 195),
    (NULL, 3, 'Exhibition', '2026-05-10T19:00:00', 'Arena Sofia', 'Completed', 95), -- Извън турнир
    (5, NULL, 'Round of 16', '2026-09-07T18:00:00', 'Louis Armstrong Stadium', 'Scheduled', 0);

-- 7. MATCH_PLAYER (Участници във всеки мач)
INSERT INTO dbo.MATCH_PLAYER (match_id, player_id, is_seed)
VALUES
    (1, 1, 1), (1, 2, 1),
    (2, 2, 1), (2, 3, 1),
    (3, 3, 1), (3, 1, 1),
    (4, 2, 1), (4, 5, 1),
    (5, 4, 1), (5, 8, 1),
    (6, 1, 1), (6, 6, 1),
    (7, 3, 0), (7, 4, 0),
    (8, 7, 1), (8, 8, 1);

-- 8. USER_FAVORITE_PLAYER
INSERT INTO dbo.USER_FAVORITE_PLAYER
    (user_id, player_id, notifications_enabled)
VALUES
    (1, 3, 1), (1, 1, 1),
    (2, 2, 0),
    (3, 1, 1),
    (4, 3, 1),
    (5, 2, 1),
    (6, 4, 1),
    (7, 5, 0);

-- 9. STREAM_SESSIONS (15 сесии с реални start_time и end_time за Power BI)
INSERT INTO dbo.STREAM_SESSION
    (user_id, match_id, ip_address, start_time, end_time, video_quality)
VALUES
    (1, 1, '195.24.32.1',   '2026-03-17T20:00:00', '2026-03-17T22:20:00', '4K'),
    (3, 1, '79.12.140.22',  '2026-03-17T20:15:00', '2026-03-17T22:10:00', '1080p'),
    (4, 1, '85.11.45.12',   '2026-03-17T20:05:00', '2026-03-17T21:45:00', '4K'),
    (1, 2, '195.24.32.1',   '2026-04-11T15:30:00', '2026-04-11T17:25:00', '4K'),
    (5, 2, '212.45.88.10',  '2026-04-11T15:40:00', '2026-04-11T17:15:00', '1080p'),
    (1, 3, '195.24.32.1',   '2026-07-08T14:00:00', '2026-07-08T16:48:00', '4K'),
    (4, 3, '85.11.45.12',   '2026-07-08T14:10:00', '2026-07-08T16:40:00', '4K'),
    (2, 3, '82.132.21.44',  '2026-07-08T14:30:00', '2026-07-08T16:00:00', '720p'),
    (3, 4, '79.12.140.22',  '2026-06-07T15:00:00', '2026-06-07T18:30:00', '4K'),
    (5, 4, '212.45.88.10',  '2026-06-07T15:05:00', '2026-06-07T18:20:00', '1080p'),
    (6, 4, '90.15.67.89',   '2026-06-07T15:20:00', '2026-06-07T17:50:00', '1080p'),
    (6, 5, '90.15.67.89',   '2026-06-05T17:30:00', '2026-06-05T20:15:00', '720p'),
    (7, 6, '91.64.12.33',   '2026-09-13T16:00:00', '2026-09-13T19:15:00', '4K'),
    (1, 6, '195.24.32.1',   '2026-09-13T16:10:00', '2026-09-13T19:05:00', '4K'),
    (4, 7, '85.11.45.12',   '2026-05-10T19:00:00', '2026-05-10T20:35:00', '1080p'); -- Гледане на демонстративния мач
GO


/* =========================================================
   7. TEST THE FUNCTION
   ========================================================= */

SELECT
    dbo.fn_CalculatePlayerAge('1995-06-15') AS PlayerAge;
GO


/* =========================================================
   8. TEST THE PROCEDURE
   ========================================================= */

EXEC dbo.sp_StartStreamSession
    @user_id = 1,
    @match_id = 1,
    @ip_address = '192.168.1.1',
    @quality = '1080p';
GO


/* =========================================================
   9. TEST THE TRIGGER DIRECTLY
   ========================================================= */

INSERT INTO dbo.STREAM_SESSION
    (user_id, match_id, ip_address, video_quality)
VALUES
    (1, 1, '192.168.1.2', '4K');
GO


/* =========================================================
   10. NEGATIVE TEST: EXPIRED SUBSCRIPTION
   This should fail and insert no session.
   ========================================================= */

BEGIN TRY
    EXEC dbo.sp_StartStreamSession
        @user_id = 8,
        @match_id = 1,
        @ip_address = '192.168.1.3',
        @quality = '1080p';
END TRY
BEGIN CATCH
    SELECT
        ERROR_NUMBER() AS ErrorNumber,
        ERROR_MESSAGE() AS ErrorMessage;
END CATCH;
GO


/* =========================================================
   11. DISPLAY RESULTS
   ========================================================= */

SELECT * FROM dbo.[USER];
SELECT * FROM dbo.USER_PREFERRED_SURFACE;
SELECT * FROM dbo.SUBSCRIPTION;
SELECT * FROM dbo.PLAYER;
SELECT * FROM dbo.TOURNAMENT;
SELECT * FROM dbo.[MATCH];
SELECT * FROM dbo.MATCH_PLAYER;
SELECT * FROM dbo.USER_FAVORITE_PLAYER;
SELECT * FROM dbo.STREAM_SESSION;
GO
