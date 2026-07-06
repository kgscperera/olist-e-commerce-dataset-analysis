# ============================================================
# 01. Regional Performance
# ============================================================

# 1. Question
# Are there regional gaps in delivery performance?
# Which states have the highest late delivery rates and lowest average review scores?

# 2. What I did
# Step 1 : Checked overall delivery completion rate across all orders.
# Step 2 : Calculated total late delivery count and percentage across all delivered orders.
# Step 3 : Broke down late deliveries by customer state. Filtered to states with 1000+ orders to avoid small-sample conclusions.
# Step 4 : Identified where delays happened — shop-to-carrier leg vs carrier-to-customer leg.
# Step 5 : Combined delivery performance metrics and review scores per state in one final query.

# 3. Tables and Columns Used
# olist_orders_dataset_staging_1
#   order_id, customer_id, order_status, order_purchase_timestamp,
#   order_approved_at, order_delivered_carrier_date,
#   order_delivered_customer_date, order_estimated_delivery_date
#
# olist_customers_dataset_staging_1
#   customer_id, customer_state
#
# olist_order_reviews_dataset_staging_2
#   order_id, review_score, review_creation_date
#
# JOINs used:
#   orders -> customers : INNER JOIN
#     Reason: need customer_state to group by state. Orders with no matching customer are invalid records.
#   orders -> reviews   : LEFT JOIN
#     Reason: not all delivered orders have a review. LEFT JOIN keeps all orders in the result.
#     AVG() ignores NULL review_score values automatically, so unreviewed orders do not distort the average.

# 4. Observations and Assumptions
# - All delivery time queries filter to order_status = 'delivered'.
# - Non-delivered orders have NULL delivery dates and would distort averages.
# - States with fewer than 1000 orders are excluded in state-level breakdowns (Step 3, Step 4).
# - "Late" is defined as: order_delivered_customer_date > order_estimated_delivery_date.
# - latest_review CTE in Step 6 picks the most recent review per order.
# - Resolves the multi-review-per-order issue found during data cleaning (Block 6: 547 orders had multiple reviews).


# ============================================================
# Step 1 : How many orders were placed and how many delivered?
# ============================================================

SELECT
    COUNT(order_id) as total_orders,
    COUNT(CASE WHEN order_status = 'delivered' THEN 1 END) as orders_delivered,
    ROUND(
		COUNT(CASE WHEN order_status = 'delivered' THEN 1 END) 
				/ nullif(COUNT(order_id), 0) * 100, 2
	) as delivered_percentage
from `olist_orders_dataset_staging_1`;


# ============================================================
# Step 2 : Overall Late Delivery Count and Percentage
# ============================================================

SELECT
    COUNT(order_id) as total_orders_delivered,
    COUNT(CASE WHEN order_estimated_delivery_date < order_delivered_customer_date THEN 1 END) as late_delivery,
    ROUND(
		COUNT(CASE WHEN order_estimated_delivery_date < order_delivered_customer_date THEN 1 END) 
				/ nullif(COUNT(order_delivered_customer_date), 0) * 100, 2
	) as late_delivery_percentage
from `olist_orders_dataset_staging_1`
where order_status = 'delivered';


# ============================================================
# Step 3 : Late Deliveries by State (1000+ Orders Only)
# ============================================================
drop table if exists regional_late_deliveries;
create table regional_late_deliveries
SELECT
	customer_state as state,
    COUNT(o.order_id) as total_orders_delivered,
    COUNT(CASE WHEN order_estimated_delivery_date < order_delivered_customer_date THEN 1 END) as late_delivery,
    ROUND(
		COUNT(CASE WHEN order_estimated_delivery_date < order_delivered_customer_date THEN 1 END) 
				/ nullif(COUNT(order_delivered_customer_date), 0) * 100, 2
	) as late_delivery_percentage
from `olist_orders_dataset_staging_1` as o
join `olist_customers_dataset_staging_1` as c
	on o.customer_id = c.customer_id
where order_status = 'delivered'
group by customer_state
having 	COUNT(o.order_id) >= 1000
order by late_delivery_percentage desc;


# ===============================================================================
# Step 4 : Where Did the Delay Happen? Shop-to-Carrier vs Carrier-to-Customer
# ===============================================================================
SELECT
	customer_state 																						as state,
#    COUNT(o.order_id) 																					as total_orders_delivered,
    COUNT(CASE WHEN order_estimated_delivery_date < order_delivered_customer_date THEN 1 END) 			as late_deliveries,
    COUNT(CASE WHEN order_estimated_delivery_date < order_delivered_carrier_date THEN 1 END) 			as already_late_to_carrier
from `olist_orders_dataset_staging_1` as o
join `olist_customers_dataset_staging_1` as c
	on o.customer_id = c.customer_id
where order_status = 'delivered'
group by customer_state
having 	COUNT(o.order_id) >= 1000
order by late_deliveries desc;


# ============================================================
# Step 5 : Days Share per Delivery Stage per Order
# ============================================================

# shop_leg: (time_purchased -> time_to_carrier)
# carrier_leg: (time_to_carrier -> time_to_customer)

WITH day_counter AS (
    SELECT
        c.customer_state,
        TIMESTAMPDIFF(DAY, o.order_purchase_timestamp, o.order_delivered_carrier_date)      	AS purchase_to_carrier,
        TIMESTAMPDIFF(DAY, o.order_delivered_carrier_date, o.order_delivered_customer_date)  	AS carrier_to_customer
    FROM olist_orders_dataset_staging_1         AS o
    JOIN olist_customers_dataset_staging_1      AS c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    AND order_estimated_delivery_date < order_delivered_customer_date
)
SELECT
    customer_state																				AS state,
    COUNT(*)																					AS total_late_delivered_orders,
    COUNT(CASE WHEN purchase_to_carrier > carrier_to_customer THEN 1 END)   					AS times_shop_leg_longer,
    COUNT(CASE WHEN carrier_to_customer > purchase_to_carrier THEN 1 END)   					AS times_carrier_leg_longer,
    ROUND(
		(COUNT(CASE WHEN purchase_to_carrier > carrier_to_customer THEN 1 END) ) / (COUNT(*)) * 100, 2
	) 																							AS longer_shop_leg_pct
FROM day_counter
GROUP BY customer_state
ORDER BY longer_shop_leg_pct DESC;


# ============================================================
# Step 6 : Delivery Performance + Review Score by State
# ============================================================

drop table if exists regional_late_deliveries_summary;
create table regional_late_deliveries_summary
WITH latest_review AS (
    SELECT
        order_id,
        review_score,
        ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_creation_date DESC) AS rn
    FROM olist_order_reviews_dataset_staging_2
)
SELECT
    c.customer_state,
    COUNT(o.order_id)                                                                                               AS total_orders,
    ROUND(AVG(CASE WHEN o.order_delivered_customer_date IS NOT NULL
                   THEN DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp) END), 1)             	AS avg_delivery_days,
    ROUND(AVG(r.review_score), 2)                                                                                   AS avg_review_score,
    ROUND(
        SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN o.order_delivered_customer_date IS NOT NULL THEN 1 ELSE 0 END), 0) * 100, 1)        	AS late_delivery_pct
FROM olist_orders_dataset_staging_1             AS o
JOIN olist_customers_dataset_staging_1          AS c  ON o.customer_id = c.customer_id
LEFT JOIN latest_review                         AS r  ON o.order_id    = r.order_id AND r.rn = 1
GROUP BY c.customer_state
ORDER BY avg_review_score DESC;


# 5. Conclusion
# Carrier-to-customer is the dominant bottleneck. Shop-to-carrier delays are marginal by comparison.
# States with the highest late delivery rates correspond with lower average review scores.