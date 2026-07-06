-- ============================================================
-- BLOCK 5 OF 9 : ORDER PAYMENTS - STAGING AND CLEANING
-- ============================================================
-- 1. Trim whitespace into olist_order_payments_dataset_staging_1.
-- 2. Duplicate check.
-- 3. Orphan check: every order_id must exist in olist_orders_dataset.
-- 4. Add composite PRIMARY KEY (order_id, payment_sequential).
-- ============================================================

USE _olist_dataset;

-- 1. Create staging_1 (trim text columns only)

DROP TABLE IF EXISTS olist_order_payments_dataset_staging_1;

CREATE TABLE olist_order_payments_dataset_staging_1 (
    order_id             VARCHAR(50),
    payment_sequential   INT,
    payment_type         VARCHAR(20),
    payment_installments INT,
    payment_value        DECIMAL(10,2)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO olist_order_payments_dataset_staging_1 (order_id, payment_sequential, payment_type, payment_installments, payment_value)
SELECT
    TRIM(order_id),
    TRIM(payment_sequential),
    TRIM(payment_type),
    payment_installments,
    payment_value
FROM olist_order_payments_dataset;

WITH row_counter AS (
	SELECT
		(SELECT COUNT(*) FROM olist_order_payments_dataset) AS imported_row_count,
		(SELECT COUNT(*) FROM olist_order_payments_dataset_staging_1) AS staging_1_row_count
)
SELECT 
	imported_row_count,
    staging_1_row_count,
	CASE
		WHEN imported_row_count = staging_1_row_count THEN 'PASS'
        ELSE 'FAIL'
	END AS status
FROM
	row_counter; -- expect 103886

-- 2. Duplicate check

WITH view_duplicates_cte AS (
    SELECT *,
        ROW_NUMBER() OVER(
			PARTITION BY 
				order_id, 
                payment_sequential, 
                payment_type, 
                payment_installments, 
                payment_value
		) AS row_num
    FROM 
		olist_order_payments_dataset_staging_1
)
SELECT 
	COUNT(*) AS duplicate_count
FROM 
	view_duplicates_cte
WHERE 
	row_num > 1; -- no duplicates

-- 3. Orphan check: every order_id must exist in olist_orders_dataset.

SELECT
	orphaned_order_payments,
    CASE
		WHEN orphaned_order_payments = 0 THEN 'PASS'
        ELSE 'FAIL'
	END AS status
FROM (
	SELECT 
		COUNT(*) AS orphaned_order_payments
	FROM 
		olist_order_payments_dataset_staging_1 AS op
	LEFT JOIN 
		olist_orders_dataset                   AS o 
	ON  op.order_id = o.order_id
	WHERE 
		o.order_id IS NULL
) AS sub;

-- 4. Add composite PRIMARY KEY (an order can have multiple payment lines, e.g. split payments).

ALTER TABLE olist_order_payments_dataset_staging_1
    MODIFY COLUMN order_id VARCHAR(50) NOT NULL,
    MODIFY COLUMN payment_sequential INT NOT NULL,
    ADD PRIMARY KEY (order_id, payment_sequential);

SELECT 
	COUNT(*) AS final_row_count,
    CASE
		WHEN COUNT(*) = 103886 THEN 'PASS'
        ELSE 'FAIL'
	END as status
FROM 
	olist_order_payments_dataset_staging_1; -- expect PASS
    
-- DONE