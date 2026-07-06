-- ============================================================
-- BLOCK 6 OF 9 : ORDER REVIEWS - STAGING AND CLEANING
-- ============================================================
-- 1. Trim whitespaces into staging_1.
-- 2. Convert review_creation_date and review_answer_timestamp from VARCHAR to DATETIME into staging_2.
-- 3. Duplicate analysis — two structural patterns documented and retained.
-- 4. review_score range check (valid range: 1 to 5).
-- 5. Orphan check: every order_id must exist in olist_orders_dataset.
-- NOTE: No PRIMARY KEY added — see duplicate analysis section.
-- ============================================================

USE _olist_dataset;

-- 1. Create staging_1 (trim)

DROP TABLE IF EXISTS olist_order_reviews_dataset_staging_1;

CREATE TABLE olist_order_reviews_dataset_staging_1 (
    review_id               VARCHAR(50),
    order_id                VARCHAR(50),
    review_score            INT,
    review_comment_title    VARCHAR(100),
    review_comment_message  VARCHAR(500),
    review_creation_date    VARCHAR(20),
    review_answer_timestamp VARCHAR(20)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO olist_order_reviews_dataset_staging_1
SELECT
    TRIM(review_id),
    TRIM(order_id),
    review_score,
    TRIM(review_comment_title),
    TRIM(review_comment_message),
    TRIM(review_creation_date),
    TRIM(review_answer_timestamp)
FROM olist_order_reviews_dataset;

WITH row_counter AS (
	SELECT
		(SELECT COUNT(*) FROM olist_order_reviews_dataset) AS imported_row_count,
		(SELECT COUNT(*) FROM olist_order_reviews_dataset_staging_1) AS staging_1_row_count
)
SELECT 
	imported_row_count,
    staging_1_row_count,
	CASE
		WHEN imported_row_count = staging_1_row_count THEN 'PASS'
        ELSE 'FAIL'
	END AS status
FROM
	row_counter; -- expect 99224

-- 2. Convert review_creation_date and review_answer_timestamp from VARCHAR to DATETIME into staging_2.

DROP TABLE IF EXISTS olist_order_reviews_dataset_staging_2;

CREATE TABLE olist_order_reviews_dataset_staging_2 (
    review_id               VARCHAR(50),
    order_id                VARCHAR(50),
    review_score            INT,
    review_comment_title    VARCHAR(100),
    review_comment_message  VARCHAR(500),
    review_creation_date    VARCHAR(20),
    review_answer_timestamp VARCHAR(20)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO olist_order_reviews_dataset_staging_2
SELECT 
	* 
FROM 
	olist_order_reviews_dataset_staging_1;

WITH row_counter AS (
	SELECT
		(SELECT COUNT(*) FROM olist_order_reviews_dataset_staging_1) AS staging_1_row_count,
		(SELECT COUNT(*) FROM olist_order_reviews_dataset_staging_2) AS staging_2_row_count
)
SELECT 
	staging_1_row_count,
    staging_2_row_count,
	CASE
		WHEN staging_1_row_count = staging_2_row_count THEN 'PASS'
        ELSE 'FAIL'
	END AS status
FROM
	row_counter; -- expect 99224

-- Add new datetime columns.
ALTER TABLE olist_order_reviews_dataset_staging_2
    ADD COLUMN review_creation_date_2    DATETIME,
    ADD COLUMN review_answer_timestamp_2 DATETIME;

UPDATE olist_order_reviews_dataset_staging_2
    SET review_creation_date_2 = STR_TO_DATE(review_creation_date, '%Y-%m-%d %H:%i:%s'),
		review_answer_timestamp_2 = STR_TO_DATE(review_answer_timestamp, '%Y-%m-%d %H:%i:%s');

-- Validate: both counts must equal 99224 (no NULLs introduced by conversion).
SELECT 
	COUNT(*) AS valid_review_creation_date_rows
FROM 
	olist_order_reviews_dataset_staging_2
WHERE 
	review_creation_date IS NOT NULL
	AND 
    review_creation_date_2 IS NOT NULL; -- expect 99224

SELECT 
	COUNT(*) AS valid_review_answer_timestamp_rows
FROM 
	olist_order_reviews_dataset_staging_2
WHERE 
	review_answer_timestamp IS NOT NULL
	AND 
    review_answer_timestamp_2 IS NOT NULL; -- expect 99224

-- Replace text columns with datetime columns.
ALTER TABLE olist_order_reviews_dataset_staging_2
    DROP COLUMN review_creation_date,
    DROP COLUMN review_answer_timestamp;

ALTER TABLE olist_order_reviews_dataset_staging_2
    CHANGE review_creation_date_2    review_creation_date    DATETIME,
    CHANGE review_answer_timestamp_2 review_answer_timestamp DATETIME;

WITH row_counter AS (
	SELECT
		(SELECT COUNT(*) FROM olist_order_reviews_dataset_staging_1) AS staging_1_row_count,
		(SELECT COUNT(*) FROM olist_order_reviews_dataset_staging_2) AS staging_2_row_count
)
SELECT 
	staging_1_row_count,
    staging_2_row_count,
	CASE
		WHEN staging_1_row_count = staging_2_row_count THEN 'PASS'
        ELSE 'FAIL'
	END AS status
FROM
	row_counter; -- expect 99224

-- 3. Duplicate analysis.

-- Initial check on review_id, order_id
WITH view_duplicates_cte AS (
    SELECT *, ROW_NUMBER() OVER(
		PARTITION BY 
			review_id, 
			order_id
		) AS row_num
    FROM 
		olist_order_reviews_dataset_staging_2
)
SELECT 
	COUNT(*) AS duplicate_count_on_review_id_order_id
FROM 
	view_duplicates_cte
WHERE 
	row_num > 1;

-- OBSERVATIONS
-- 1. No duplicates based on ("review_id", "order_id") together.
-- 2. There are duplicates if considered "review_id" and "order_id" separately.
-- 3. same review covering multiple orders. Here the review_score is same for all orders within the same review.
-- 4. same order is covered in multiple reviews.

-- ASSUMPTION:
-- 1. customer reviewed multiple products at once and give overall score.
-- 2. customer may updated the review later.

-- count number of such cases and cross check order_id, review_id and review_score.
-- Intentionally did NOT drop any rows as duplicates.
-- Will handle this situation as analysis go on in the future.

-- Profile: review_ids appearing with more than one order_id.
SELECT 
	review_id, 
    COUNT(review_id) AS review_id_count, 
    COUNT(order_id) AS order_id_count
FROM 
	olist_order_reviews_dataset_staging_2
GROUP BY 
	review_id
HAVING 
	COUNT(order_id) > 1
ORDER BY 
	COUNT(order_id) DESC;

-- Confirm review_score is consistent for the same (review_id, order_id) pair.
SELECT 
	review_id, 
    order_id, 
    COUNT(DISTINCT review_score) AS distinct_scores
FROM 
	olist_order_reviews_dataset_staging_2
GROUP BY 
	review_id, order_id
HAVING 
	COUNT(DISTINCT review_score) > 1; -- expect blank

-- Count of review_ids linked to more than one order_id.
SELECT 
	COUNT(*) AS review_ids_with_multiple_orders
FROM (
    SELECT 
		review_id
    FROM 
		olist_order_reviews_dataset_staging_2
    GROUP BY 
		review_id
    HAVING 
		COUNT(DISTINCT order_id) > 1
) sub; -- output: 789

-- Count of order_ids linked to more than one review_id.
SELECT 
	order_id, 
    COUNT(DISTINCT review_id) AS distinct_reviews
FROM 
	olist_order_reviews_dataset_staging_2
GROUP BY 
	order_id
HAVING 
	COUNT(DISTINCT review_id) > 1; -- 547 rows returned

-- 4. review_score range check (valid range: 1 to 5).
SELECT 
	review_score, 
	COUNT(*) AS row_count
FROM 
	olist_order_reviews_dataset_staging_2
WHERE 
	review_score NOT BETWEEN 1 AND 5
	OR 
    review_score IS NULL
GROUP BY 
	review_score; -- expect blank

-- 5. Orphan check: every order_id must exist in olist_orders_dataset.
    SELECT
	orphaned_order_reviews,
    CASE
		WHEN orphaned_order_reviews = 0 THEN 'PASS'
        ELSE 'FAIL'
	END AS status
FROM (
	SELECT 
		COUNT(*) AS orphaned_order_reviews
	FROM 
		olist_order_reviews_dataset_staging_2 	AS r
	LEFT JOIN 
		olist_orders_dataset 					AS o 
	ON 	r.order_id = o.order_id
	WHERE 
		o.order_id IS NULL
) AS sub;

-- PRIMARY KEY not added: review_id is not unique (789 review_ids map to multiple order_ids).
-- Will be resolved in Phase 2.

WITH row_counter AS (
	SELECT
		(SELECT COUNT(*) FROM olist_order_reviews_dataset_staging_1) AS staging_1_row_count,
		(SELECT COUNT(*) FROM olist_order_reviews_dataset_staging_2) AS staging_2_row_count
)
SELECT 
	staging_1_row_count,
    staging_2_row_count,
	CASE
		WHEN staging_1_row_count = staging_2_row_count THEN 'PASS'
        ELSE 'FAIL'
	END AS status
FROM
	row_counter; -- expect 99224
    
    
-- DONE