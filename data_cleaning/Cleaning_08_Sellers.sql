-- ============================================================
-- BLOCK 9 OF 9 : SELLERS - STAGING AND CLEANING
-- ============================================================
-- 1. Trim and nullify sellers into olist_sellers_dataset_staging_1.
-- 2. Duplicate check.
-- 3. Add PRIMARY KEY on seller_id.
-- ============================================================

USE _olist_dataset;

-- 1. Create staging_1 (trim and nullify)
DROP TABLE IF EXISTS olist_sellers_dataset_staging_1;

CREATE TABLE olist_sellers_dataset_staging_1 (
    seller_id              VARCHAR(50),
    seller_zip_code_prefix VARCHAR(10),
    seller_city            VARCHAR(25),
    seller_state           VARCHAR(5)
);

INSERT INTO olist_sellers_dataset_staging_1
SELECT
    TRIM(seller_id),
    NULLIF(TRIM(seller_zip_code_prefix), ''),
    NULLIF(TRIM(seller_city), ''),
    NULLIF(TRIM(seller_state), '')
FROM 
	olist_sellers_dataset;

-- 2. Duplicate check on seller_id
WITH view_duplicates_cte AS (
    SELECT 
		*, 
		ROW_NUMBER() OVER(
			PARTITION BY 
				seller_id
		) AS row_num
    FROM 
		olist_sellers_dataset_staging_1
)
SELECT 
	COUNT(*) AS duplicate_count
FROM 
	view_duplicates_cte
WHERE 
	row_num > 1; --  no duplicates

-- 3. Add PRIMARY KEY on seller_id.
ALTER TABLE olist_sellers_dataset_staging_1
    MODIFY COLUMN seller_id VARCHAR(50) NOT NULL,
    ADD PRIMARY KEY (seller_id);

WITH row_counter AS (
	SELECT
		(SELECT COUNT(*) FROM olist_sellers_dataset) AS imported_row_count,
		(SELECT COUNT(*) FROM olist_sellers_dataset_staging_1) AS staging_1_row_count
)
SELECT 
	imported_row_count,
    staging_1_row_count,
	CASE
		WHEN imported_row_count = staging_1_row_count THEN 'PASS'
        ELSE 'FAIL'
	END AS status
FROM
	row_counter; -- expect 3095

-- DONE