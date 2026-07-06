# ============================================================
# 02. Seasonality in Order Volume and Service Quality
# ============================================================

# 1. Question
# Is there seasonality in order volume?
# Does service quality (delivery time, review score) degrade during peak months?

# 2. What I did in simple English
# Step 1 : Checked monthly order volume.
# Step 2 : Checked monthly revenue.
# Step 3 : Checked monthly average delivery days and average review score.
# Step 4 : Combined all metrics into one final query per month.

# 3. Tables and Columns Used
# olist_orders_dataset_staging_1
#   order_id, order_status, order_purchase_timestamp,
#   order_delivered_customer_date, order_estimated_delivery_date
#
# olist_order_items_dataset_staging_2
#   order_id, price
#
# olist_order_reviews_dataset_staging_2
#   order_id, review_score, review_creation_date
#
# JOINs used:
#   orders -> order_items : LEFT JOIN
#     Reason: want all orders in the count even if no item record exists.
#   orders -> reviews     : LEFT JOIN
#     Reason: not all orders have a review. Keeping all orders preserves volume count accuracy.

# 4. Observations and Assumptions
#   order_purchase_timestamp is used as the month anchor (not delivery date).
#   Delivery day average only counts delivered orders (order_delivered_customer_date IS NOT NULL).
#   Latest review CTE resolves the multi-review-per-order issue (Block 6: 547 orders, 789 review_ids).
#   Revenue = SUM(price) from order_items, not payment_value.
#   price is item-level and correctly attributable per month.
#   payment_value includes freight, vouchers and installment splits.

# NOTE: Filtered out the least recent 3 months and most recent 2 months in the dataset.
#       because, recently placed orders had less time to be delivered.
#				 reviews may be updated later.
#				 only very few orders (data yet to be inserted or error in data collection in initial months).
# order_month, order_count
# '2016-09', 	'4'
# '2016-10', 	'324'
# '2016-12', 	'1'
# '2018-09', 	'16'
# '2018-10', 	'4'

# ============================================================
# Step 1 : Monthly Order Volume
# ============================================================
drop table if exists monthly_orders;

create table monthly_orders
SELECT
    DATE_FORMAT(order_purchase_timestamp, '%Y-%m')  	AS order_month,
    COUNT(order_id)                                  	AS order_count
FROM 
	`olist_orders_dataset_staging_1`
WHERE 
	order_purchase_timestamp IS NOT NULL
    AND order_purchase_timestamp > '2016-12-31'
    AND order_purchase_timestamp < '2018-08-31'
GROUP BY 
	DATE_FORMAT(order_purchase_timestamp, '%Y-%m')
ORDER BY 
	order_month;


# ============================================================
# Step 2 : Monthly Revenue
# ============================================================
drop table if exists monthly_revenue;
create table monthly_revenue
SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')    	AS order_month,
#    COUNT(DISTINCT o.order_id)                           	AS order_count,
    ROUND(SUM(oi.price), 2)                              	AS total_revenue
FROM `olist_orders_dataset_staging_1`       	 AS o
LEFT JOIN `olist_order_items_dataset_staging_2`  AS oi ON o.order_id = oi.order_id
WHERE o.order_purchase_timestamp IS NOT NULL
	AND order_purchase_timestamp > '2016-12-31'
    AND order_purchase_timestamp < '2018-08-31'
GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
ORDER BY order_month DESC;


# ============================================================
# Step 3 : Monthly Average Delivery Days and Review Score
# ============================================================
drop table if exists monthly_summary;
create table monthly_summary
WITH latest_review AS (
    SELECT
        order_id,
        review_score,
        ROW_NUMBER() OVER(
			PARTITION BY order_id 
			ORDER BY review_creation_date DESC
		) AS rn
    FROM `olist_order_reviews_dataset_staging_2`
)
SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')                                                    AS order_month,
    ROUND(AVG(CASE WHEN o.order_delivered_customer_date IS NOT NULL
                   THEN DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp) END), 1)  AS avg_delivery_days,
    ROUND(AVG(r.review_score), 2)                                                                       AS avg_review_score
FROM `olist_orders_dataset_staging_1` AS o
LEFT JOIN latest_review               AS r 
	ON o.order_id = r.order_id 
	AND r.rn = 1
WHERE o.order_purchase_timestamp IS NOT NULL
	AND order_purchase_timestamp > '2016-12-31'
    AND order_purchase_timestamp < '2018-08-31'
GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
ORDER BY order_month;


# ============================================================
# Step 4 : Summary
# ============================================================
WITH latest_review AS (
    SELECT
        order_id,
        review_score,
        ROW_NUMBER() OVER(
			PARTITION BY order_id 
			ORDER BY review_creation_date DESC
        ) AS rn
    FROM `olist_order_reviews_dataset_staging_2`
)
SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')                                                    AS order_month,
    COUNT(DISTINCT o.order_id)                                                                          AS order_count,
    ROUND(SUM(oi.price), 0)                                                                             AS total_revenue,
    ROUND(AVG(CASE WHEN o.order_delivered_customer_date IS NOT NULL
                   THEN DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp) END), 1)  AS avg_delivery_days,
    ROUND(
        COUNT(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 END)
        / NULLIF(COUNT(o.order_delivered_customer_date), 0) * 100, 1)                                   AS late_delivery_pct,
	ROUND(AVG(r.review_score), 1)                                                                       AS avg_review_score
FROM `olist_orders_dataset_staging_1`               AS o
LEFT JOIN `olist_order_items_dataset_staging_2`     AS oi ON o.order_id = oi.order_id
LEFT JOIN latest_review                             AS r  ON o.order_id = r.order_id AND r.rn = 1
WHERE o.order_purchase_timestamp IS NOT NULL
	AND order_purchase_timestamp > '2016-12-31'
    AND order_purchase_timestamp < '2018-08-31'
GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
ORDER BY order_month;
# Average_delivery_days and Average_review_score is positively correlated.
# Faster the delivery higher the review_score.

# After 2017-10 till 2018-03 "total_revenue", "avg_delivery_days" and "late_delivery_pct" increased and "avg_review_score" dropped.
# Need to focus more on delivering on time when volume and traffic is getting higher.
# suggestion: Further analysis for lower rated months based on order_id.


# 5. Conclusion
# Q4 2017 generated the most revenue and drop in average review score.
# This trend continues to Q1 2018.
# Peak months with high order_count and high late_delivery_pct alongside low avg_review_score directly support an operations-capacity argument.