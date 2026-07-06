-- ==========================================================================
-- BLOCK 2 OF 9 : CUSTOMERS - STAGING AND CLEANING
-- ==========================================================================
-- 1. Trim whitespace on all columns into olist_customers_dataset_staging_1.
-- 2. Duplicate check on customer_unique_id and customer_id separately.
-- 3. Verify customer_id is unique before adding primary key.
-- 4. Add PRIMARY KEY on customer_id.
-- ==========================================================================

USE _olist_dataset;

-- 1. Trim whitespace on all columns into olist_customers_dataset_staging_1.

DROP TABLE IF EXISTS olist_customers_dataset_staging_1;

CREATE TABLE olist_customers_dataset_staging_1 (
    customer_id              VARCHAR(50),
    customer_unique_id       VARCHAR(50),
    customer_zip_code_prefix VARCHAR(10),
    customer_city            VARCHAR(30),
    customer_state           VARCHAR(5)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO olist_customers_dataset_staging_1 (customer_id, customer_unique_id, customer_zip_code_prefix, customer_city, customer_state)
SELECT
    TRIM(customer_id),
    TRIM(customer_unique_id),
    NULLIF(TRIM(customer_zip_code_prefix), ''),
    NULLIF(TRIM(customer_city), ''),
    NULLIF(TRIM(customer_state), '')
FROM 
	olist_customers_dataset;

WITH row_counter AS (
    SELECT
        (SELECT COUNT(*) FROM olist_customers_dataset)           AS imported_row_count,
        (SELECT COUNT(*) FROM olist_customers_dataset_staging_1) AS staging_1_row_count
)
SELECT
    imported_row_count,
    staging_1_row_count,
    CASE 
		WHEN imported_row_count = staging_1_row_count THEN 'PASS' 
		ELSE 'FAIL' 
    END AS status
FROM 
	row_counter; -- expect 99441

-- 2. Duplicate check on customer_unique_id.

WITH check_duplicate_cte AS (
    SELECT *,
        ROW_NUMBER() OVER(
			PARTITION BY customer_unique_id # customer_id -- checked duplicates separately for customer_unique_id and customer_id.
            ORDER BY customer_id
		) AS row_num
    FROM olist_customers_dataset_staging_1
)
SELECT COUNT(*) AS duplicate_count_on_customer_unique_id
FROM check_duplicate_cte
WHERE row_num > 1;

-- Same "customer_unique_id" with different "customer_id" values represents the same person placing multiple orders. 
-- Each order has a distinct "customer_id", which is the join key into "olist_orders_dataset".
-- Deleting rows based oon "customer_unique_id" would erase records on repeated purchases from same customer.
-- Therefore "customer_id" should be the Primary key for this table.

-- 3. Verify customer_id (the true row-level key) has no duplicates before adding primary key.

SELECT
    COUNT(*)                    AS total_rows,
    COUNT(DISTINCT customer_id) AS distinct_customer_id,
    CASE 
		WHEN COUNT(*) = COUNT(DISTINCT customer_id) THEN 'PASS' 
        ELSE 'FAIL' 
	END AS status
FROM 
	olist_customers_dataset_staging_1; -- expect 99441 for all

-- 4. Add PRIMARY KEY on customer_id.

ALTER TABLE olist_customers_dataset_staging_1
    MODIFY COLUMN customer_id VARCHAR(50) NOT NULL,
    ADD PRIMARY KEY (customer_id);

SELECT 
	COUNT(*) AS final_row_count 
FROM 
	olist_customers_dataset_staging_1; -- expect 99441

-- DONE