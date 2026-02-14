--------------------- Table Creations -------------------------

------ Games Engagement Table -----------

CREATE TABLE IF NOT EXISTS games_engagement (
    title TEXT,
	genre VARCHAR(20),
	release_date DATE,
	release_year INTEGER,
	team TEXT,
    rating NUMERIC,
	times_listed INTEGER,
	no_of_reviews INTEGER,
	plays INTEGER,
    playing INTEGER,
	backlogs INTEGER,
	wishlist INTEGER
);

------ Sales Table -----------------------

CREATE TABLE IF NOT EXISTS vgsales (
    title TEXT,
    platform TEXT,
    release_year INTEGER,
    genre VARCHAR(20),
    publisher TEXT,
    na_sales NUMERIC,
    eu_sales NUMERIC,
    jp_sales NUMERIC,
    other_sales NUMERIC,
    global_sales NUMERIC,
	platform_category TEXT
);

------ Table for distinct games

CREATE TABLE games_dim (
    game_id SERIAL PRIMARY KEY,
    title TEXT NOT NULL UNIQUE
);

INSERT INTO games_dim (title)
SELECT DISTINCT
       LOWER(TRIM(title)) AS title
FROM games_engagement
WHERE title IS NOT NULL;

INSERT INTO games_dim (title)
SELECT DISTINCT
       LOWER(TRIM(title)) AS title
FROM vgsales
WHERE title IS NOT NULL
ON CONFLICT (title) DO NOTHING;

----------------------------------------------------------------------

SELECT * FROM games_dim;

SELECT COUNT(*) FROM games_dim;

SELECT title, COUNT(*)
FROM games_dim
GROUP BY title
HAVING COUNT(*) > 1;

--------------------------------------------------------------------

ALTER TABLE games_engagement
ADD COLUMN game_id INTEGER;

ALTER TABLE vgsales
ADD COLUMN game_id INTEGER;

UPDATE games_engagement ge
SET game_id = gd.game_id
FROM games_dim gd
WHERE LOWER(TRIM(ge.title)) = gd.title;

UPDATE vgsales vs
SET game_id = gd.game_id
FROM games_dim gd
WHERE LOWER(TRIM(vs.title)) = gd.title;

ALTER TABLE games_engagement
ALTER COLUMN game_id SET NOT NULL;

ALTER TABLE vgsales
ALTER COLUMN game_id SET NOT NULL;

--------------------------------------------------------------------

SELECT COUNT(*) AS missing_game_id
FROM games_engagement
WHERE game_id IS NULL;

SELECT COUNT(*) AS missing_game_id
FROM vgsales
WHERE game_id IS NULL;

--------------------------------------------------------------------

ALTER TABLE games_engagement
ADD CONSTRAINT fk_games_engagement
FOREIGN KEY (game_id)
REFERENCES games_dim (game_id);

ALTER TABLE vgsales
ADD CONSTRAINT fk_vgsales
FOREIGN KEY (game_id)
REFERENCES games_dim (game_id);

CREATE INDEX idx_engagement_game_id
ON games_engagement (game_id);

CREATE INDEX idx_sales_game_id
ON vgsales (game_id);

--------------------------------------------------------------------

CREATE TABLE merged_dataset AS
WITH sales_agg AS (
    SELECT
        game_id,
        SUM(global_sales) AS total_global_sales,
        SUM(na_sales) AS na_sales,
        SUM(eu_sales) AS eu_sales,
        SUM(jp_sales) AS jp_sales,
        SUM(other_sales) AS other_sales
    FROM vgsales
    GROUP BY game_id
),
engagement_agg AS (
    SELECT
        game_id,
        genre,
        ROUND(AVG(rating),1) AS avg_rating,
        SUM(plays) AS total_plays,
        SUM(playing) AS total_playing,
        SUM(backlogs) AS total_backlogs,
        SUM(wishlist) AS total_wishlist,
        SUM(no_of_reviews) AS total_reviews
    FROM games_engagement
    WHERE genre IS NOT NULL
    GROUP BY game_id, genre
)
SELECT
    gd.game_id,
    gd.title,
    ea.genre,

    ea.avg_rating,
    ea.total_plays,
    ea.total_playing,
    ea.total_backlogs,
    ea.total_wishlist,
    ea.total_reviews,

    sa.total_global_sales,
    sa.na_sales,
    sa.eu_sales,
    sa.jp_sales,
    sa.other_sales

FROM games_dim gd
INNER JOIN engagement_agg ea
    ON gd.game_id = ea.game_id
INNER JOIN sales_agg sa
    ON gd.game_id = sa.game_id;

SELECT * FROM merged_dataset;

------------------------------------------------------------------------------

ALTER TABLE merged_dataset
ADD CONSTRAINT fk_merged_dataset
FOREIGN KEY (game_id)
REFERENCES games_dim (game_id);

------------------------------------------------------------------------------

-- 1. Which game genres generate the most global sales?

SELECT
    genre,
    SUM(total_global_sales) AS genre_total_sales
FROM merged_dataset
GROUP BY genre
ORDER BY genre_total_sales DESC;

------------------------------------------------------------------------------

-- Q22 — How does user rating affect global sales?

SELECT
    CASE
        WHEN avg_rating >= 4 THEN '4+'
        WHEN avg_rating >= 3 AND avg_rating < 4 THEN '3 to 4'
		WHEN avg_rating >= 2 AND avg_rating < 3 THEN '2 to 3'
		WHEN avg_rating >= 1 AND avg_rating < 2 THEN '1 to 2'
        ELSE 'Below 1'
    END AS rating_bucket,
    ROUND(AVG(total_global_sales),3) AS avg_sales
FROM merged_dataset
GROUP BY rating_bucket
ORDER BY avg_sales DESC;

------------------------------------------------------------------------------

-- 2. Do highly wishlisted games lead to more sales?

SELECT
    CASE
        WHEN total_wishlist >= 3000 THEN 'Very High'
        WHEN total_wishlist >= 2500 THEN 'High'
        WHEN total_wishlist >= 2000 THEN 'Medium'
        ELSE 'Low'
    END AS wishlist_bucket,
    ROUND(AVG(total_global_sales),3) AS avg_sales
FROM merged_dataset
GROUP BY wishlist_bucket
ORDER BY avg_sales DESC;

------------------------------------------------------------------------------

-- 3. Which genres have highest engagement but lowest sales?

SELECT
    genre,
    SUM(total_plays) AS total_engagement,
    SUM(total_global_sales) AS total_sales,
    ROUND(SUM(total_plays) / NULLIF(SUM(total_global_sales),0)) AS engagement_to_sales_ratio
FROM merged_dataset
GROUP BY genre
ORDER BY engagement_to_sales_ratio DESC;

------------------------------------------------------------------------------

-- Engagement distribution across genres

SELECT
    genre,
    ROUND(AVG(total_plays)) AS avg_plays,
    ROUND(AVG(total_wishlist)) AS avg_wishlist,
    ROUND(AVG(total_backlogs)) AS avg_backlogs
FROM merged_dataset
GROUP BY genre
ORDER BY avg_plays DESC;

--------------------------------------------------------------------------------

-- 4. Which platforms have the most games with high ratings?

WITH high_rated_games AS (
    SELECT
        game_id,
        AVG(rating) AS avg_rating
    FROM games_engagement
    GROUP BY game_id
    HAVING AVG(rating) > 4
)
SELECT
    vs.platform,
    COUNT(DISTINCT vs.game_id) AS high_rated_game_count
FROM vgsales vs
JOIN high_rated_games hr
    ON vs.game_id = hr.game_id
GROUP BY vs.platform
ORDER BY high_rated_game_count DESC;

--------------------------------------------------------------------------------

-- 5. What are the top-performing combinations of Genre + Platform?

SELECT
    genre,
    platform,
    SUM(global_sales) AS total_global_sales
FROM vgsales
GROUP BY genre, platform
ORDER BY total_global_sales DESC
LIMIT 10;


