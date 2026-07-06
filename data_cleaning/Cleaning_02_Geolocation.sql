-- ============================================================
-- BLOCK 3 OF 9 : GEOLOCATION - STAGING AND CLEANING
-- ============================================================
-- 1. Trim whitespaces and transfer into olist_geolocation_dataset_staging_1.
-- 2. Add index on zip_code_prefix before the deduplication step. (a performance optimize to the script)
-- 3. Dropped duplicates based on "geolocation_zip_code_prefix" and transferred into olist_geolocation_dataset_staging_2.
--    Dataset contains multiple GPS coordinates (geolocation_lat, geolocation_lng) per zip code prefix.
--    This analysis only requires regional mapping (zip code and state).
--    Therefore dropping duplicates based on the "geolocation_zip_code_prefix" can simplify the dataset
-- 4. Set "geolocation_zip_code_prefix" as the PRIMARY KEY.

-- ============================================================

USE _olist_dataset;

-- 1. Create staging_1 (trim and cast)

DROP TABLE IF EXISTS olist_geolocation_dataset_staging_1;

CREATE TABLE olist_geolocation_dataset_staging_1 (
    geolocation_zip_code_prefix VARCHAR(10),
    geolocation_lat             DECIMAL(23,20),
    geolocation_lng             DECIMAL(23,20),
    geolocation_city            VARCHAR(30),
    geolocation_state           VARCHAR(5)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO olist_geolocation_dataset_staging_1
SELECT
    TRIM(geolocation_zip_code_prefix),
    CAST(TRIM(geolocation_lat) AS DECIMAL(23,20)),
    CAST(TRIM(geolocation_lng) AS DECIMAL(23,20)),
    TRIM(geolocation_city),
    TRIM(geolocation_state)
FROM 
	olist_geolocation_dataset;

-- 2. Add index on zip_code_prefix before the deduplication step.
CREATE INDEX idx_zip ON olist_geolocation_dataset_staging_1 (geolocation_zip_code_prefix);

WITH row_counter AS (
    SELECT
        (SELECT COUNT(*) FROM olist_geolocation_dataset)           AS initial_row_count,
        (SELECT COUNT(*) FROM olist_geolocation_dataset_staging_1) AS staging_1_row_count
)
SELECT
    initial_row_count,
    staging_1_row_count,
    CASE 
		WHEN initial_row_count = staging_1_row_count THEN 'PASS' 
        ELSE 'FAIL' 
	END AS status
FROM 
	row_counter; -- expect 1000163

-- 3. Droped duplicates based on "geolocation_zip_code_prefix" and transferred into olist_geolocation_dataset_staging_2.

-- Count duplicate rows
WITH find_duplicates_cte AS (
    SELECT *,
        ROW_NUMBER() OVER(
			PARTITION BY geolocation_zip_code_prefix
        ) AS row_num
    FROM olist_geolocation_dataset_staging_1
)
SELECT
	COUNT(*) AS duplicate_row_count
FROM 
	find_duplicates_cte
WHERE 
	row_num > 1; -- output 981148

-- Create staging_2
DROP TABLE IF EXISTS olist_geolocation_dataset_staging_2;

CREATE TABLE olist_geolocation_dataset_staging_2 (
    geolocation_zip_code_prefix VARCHAR(10) NOT NULL,
    geolocation_lat             DECIMAL(23,20),
    geolocation_lng             DECIMAL(23,20),
    geolocation_city            VARCHAR(30),
    geolocation_state           VARCHAR(5),
    PRIMARY KEY (geolocation_zip_code_prefix)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO olist_geolocation_dataset_staging_2
SELECT 
	geolocation_zip_code_prefix, 
    geolocation_lat, 
    geolocation_lng, 
    geolocation_city, 
    geolocation_state
FROM (
    SELECT *,
        ROW_NUMBER() OVER (
			PARTITION BY geolocation_zip_code_prefix
            ORDER BY geolocation_lat
        ) AS row_num
    FROM 
		olist_geolocation_dataset_staging_1
) AS temp
WHERE row_num = 1;

-- 3. Validate row counts after deduplication.

WITH row_counter AS (
    SELECT
        (SELECT COUNT(*) FROM olist_geolocation_dataset_staging_1)                                    AS staging_1_row_count,
        (SELECT COUNT(*) FROM olist_geolocation_dataset_staging_2)                                    AS staging_2_row_count,
        (SELECT COUNT(DISTINCT geolocation_zip_code_prefix) FROM olist_geolocation_dataset_staging_2) AS distinct_zip_codes
)
SELECT
    staging_1_row_count,
    staging_2_row_count,
    distinct_zip_codes,
    CASE
        WHEN ((staging_1_row_count - staging_2_row_count) = 981148)
             AND (distinct_zip_codes = staging_2_row_count) 
	    THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM row_counter;