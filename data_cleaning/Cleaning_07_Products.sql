-- ============================================================
-- BLOCK 8 OF 9 : PRODUCTS - STAGING AND CLEANING
-- ============================================================
-- 1. Trim and nullify products into staging_1.
-- 2. Load category name translation reference into product_category_name_reference.
--    Two category names present in the raw data were missing from the translation CSV ('pc_gamer' and 'portateis_cozinha_e_preparadores_de_alimentos'). 
--    These are added via INSERT IGNORE before staging_2 is built.
-- 3. Join staging_1 to the reference table to produce English category names in staging_2.
-- 4. Validate translation coverage.
-- 5. Duplicate check.
-- 6. Zero/negative value check in dimensions.
-- 7. Add PRIMARY KEY on product_id.
-- ============================================================

USE _olist_dataset;

-- 1. Create staging_1 (trim and nullify)

DROP TABLE IF EXISTS olist_products_dataset_staging_1;

CREATE TABLE olist_products_dataset_staging_1 (
    product_id                 VARCHAR(50),
    product_category_name      VARCHAR(50),
    product_name_length        INT,
    product_description_length INT,
    product_photos_qty         INT,
    product_weight_g           DECIMAL(10,2),
    product_length_cm          DECIMAL(10,2),
    product_height_cm          DECIMAL(10,2),
    product_width_cm           DECIMAL(10,2)
);

INSERT INTO olist_products_dataset_staging_1
SELECT
    TRIM(product_id),
    TRIM(product_category_name),
    NULLIF(TRIM(product_name_length), ''),
    NULLIF(TRIM(product_description_length), ''),
    NULLIF(TRIM(product_photos_qty), ''),
    NULLIF(TRIM(product_weight_g), ''),
    NULLIF(TRIM(product_length_cm), ''),
    NULLIF(TRIM(product_height_cm), ''),
    NULLIF(TRIM(product_width_cm), '')
FROM 
	olist_products_dataset;

WITH row_counter AS (
	SELECT
		(SELECT COUNT(*) FROM olist_products_dataset) AS imported_row_count,
		(SELECT COUNT(*) FROM olist_products_dataset_staging_1) AS staging_1_row_count
)
SELECT 
	imported_row_count,
    staging_1_row_count,
	CASE
		WHEN imported_row_count = staging_1_row_count THEN 'PASS'
        ELSE 'FAIL'
	END AS status
FROM
	row_counter; -- expect 32951

-- Validate no product_id was lost in the trim step.
SELECT 
	COUNT(*) AS products_lost_in_trim,
    CASE
		WHEN (COUNT(*) = 0) THEN 'PASS'
        ELSE 'FAIL'
	END AS status
FROM 
	olist_products_dataset 				AS p
JOIN 
	olist_products_dataset_staging_1 	AS s 
ON 	p.product_id = s.product_id
WHERE 
	TRIM(p.product_id) <> ''
	AND 
    s.product_id IS NULL; -- expect 0

-- 2. Load the category name translation reference table.

DROP TABLE IF EXISTS product_category_name_reference;

CREATE TABLE product_category_name_reference (
    product_category_name         VARCHAR(50),
    product_category_name_english VARCHAR(50)
);

SET GLOBAL local_infile = 1;

LOAD DATA LOCAL INFILE 'D:/Z_Data Analysis Projects/01. Olist Dataset/sources/product_category_name_translation.csv'
INTO TABLE product_category_name_reference
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

-- Add a unique key to prevent duplicate entries on re-run.
ALTER TABLE product_category_name_reference
    ADD UNIQUE KEY uq_category_name (product_category_name);

-- Two category names present in the raw data are missing from the translation CSV.
-- Added here so the JOIN in step 3 picks them up correctly.
INSERT IGNORE INTO product_category_name_reference (product_category_name, product_category_name_english)
VALUES
    ('pc_gamer',                                      'pc_gamer'),
    ('portateis_cozinha_e_preparadores_de_alimentos', 'portable_kitchen_food_preparers');

-- Verify one row per category name in the reference table.
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT product_category_name) AS distinct_categories,
    CASE
		WHEN (COUNT(*) = COUNT(DISTINCT product_category_name)) THEN 'PASS'
        ELSE 'FAIL'
	END AS status
FROM 
	product_category_name_reference; -- both should match (73 = 71 from CSV + 2 added above)

-- 3. Create staging_2 (LEFT JOIN to English category names)

DROP TABLE IF EXISTS olist_products_dataset_staging_2;

CREATE TABLE olist_products_dataset_staging_2 AS
SELECT
    product_id,
    product_category_name_english,
    product_name_length,
    product_description_length,
    product_photos_qty,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
FROM 
	olist_products_dataset_staging_1 	AS lft
LEFT JOIN 
	product_category_name_reference 	AS rgt
ON lft.product_category_name = rgt.product_category_name;

WITH row_counter AS (
	SELECT
		(SELECT COUNT(*) FROM olist_products_dataset_staging_1) AS staging_1_row_count,
		(SELECT COUNT(*) FROM olist_products_dataset_staging_2) AS staging_2_row_count
)
SELECT 
	staging_1_row_count,
    staging_2_row_count,
	CASE
		WHEN staging_1_row_count = staging_2_row_count THEN 'PASS'
        ELSE 'FAIL'
	END AS status
FROM
	row_counter; -- expect 32951

SELECT 
	COUNT(DISTINCT product_category_name_english) AS distinct_english_categories,
    73 as expected_value,
    CASE
		WHEN COUNT(DISTINCT product_category_name_english) = 73 THEN 'PASS'
        ELSE 'FAIL'
	END AS status
FROM 
	olist_products_dataset_staging_2; -- expect 73

-- 4. Validate translation coverage.
-- NULL count in staging_2 must match the NULL count in staging_1.
-- Only products with no category name in the raw data should be NULL here.
SELECT 
	COUNT(*) AS null_english_name_count
FROM 
	olist_products_dataset_staging_2
WHERE 
	product_category_name_english IS NULL; -- expect 610

-- 5. Duplicate check on product_id (no duplicates expected).
WITH view_duplicates_cte AS (
    SELECT *, 
		ROW_NUMBER() OVER(
			PARTITION BY 
				product_id
		) AS row_num
    FROM 
		olist_products_dataset_staging_2
)
SELECT 
	COUNT(*) AS duplicate_count
FROM 
	view_duplicates_cte
WHERE 
	row_num > 1;

-- 6. Zero/negative dimension flag.
SELECT *
FROM olist_products_dataset_staging_2
WHERE product_weight_g  <= 0
   OR product_length_cm <= 0
   OR product_height_cm <= 0
   OR product_width_cm  <= 0;

-- 7. Add PRIMARY KEY on product_id.
ALTER TABLE olist_products_dataset_staging_2
    MODIFY COLUMN product_id VARCHAR(50) NOT NULL,
    ADD PRIMARY KEY (product_id);

WITH row_counter AS (
	SELECT
		(SELECT COUNT(*) FROM olist_products_dataset) AS imported_row_count,
		(SELECT COUNT(*) FROM olist_products_dataset_staging_2) AS staging_2_row_count
)
SELECT 
	imported_row_count,
    staging_2_row_count,
	CASE
		WHEN imported_row_count = staging_2_row_count THEN 'PASS'
        ELSE 'FAIL'
	END AS status
FROM
	row_counter; -- expect 32951

-- DONE