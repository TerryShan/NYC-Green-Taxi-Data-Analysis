--
--This program is to get insights from NYC Green Taxi dataset
--
--Modification History
--
--When                      Who                     What
--2022/04/22            ts4271@nyu.edu              Initial creation
--
--Data Overview
SELECT * FROM ts_taxi WHERE ROWNUM <= 10;
SELECT COUNT(*) FROM ts_taxi;
SELECT column_name, data_type FROM all_tab_cols WHERE table_name = 'TS_TAXI';
--Alter date format to see HH:MI:SS on Oracle
ALTER SESSION SET nls_date_format = 'DD-MON-YYYY HH:MI:SS PM';

-- Q1 Trips grouped by vendors
SELECT DISTINCT vendorid, COUNT(*) trips 
FROM ts_taxi
WHERE vendorid IS NOT NULL
GROUP BY vendorid
ORDER BY vendorid;

-- Q2 Vendor that had the most trips

WITH vendor_trips AS
(
SELECT DISTINCT vendorid, COUNT(*) trips 
FROM ts_taxi
WHERE vendorid IS NOT NULL
GROUP BY vendorid
ORDER BY vendorid
)
SELECT vendorid, trips AS most_trips
FROM vendor_trips
WHERE trips IN (SELECT MAX(trips)FROM vendor_trips);

-- Q3 The records with the highest fare

WITH lpep_date AS
(
SELECT TRUNC(lpep_pickup_datetime) AS pickup_date, TRUNC(lpep_dropoff_datetime) AS dropoff_date, fare_amount
FROM ts_taxi
)
SELECT pickup_date, dropoff_date, MAX(fare_amount) AS highest_fare
FROM lpep_date
GROUP BY pickup_date, dropoff_date
HAVING pickup_date = dropoff_date
ORDER BY 1;

-- Q4 Estimate the charged rate for each RateCodeID.

SELECT DISTINCT ratecodeid, round(AVG(fare_amount/trip_distance),2) AS charged_rate FROM ts_taxi
WHERE trip_distance > 0.65 AND fare_amount > 0 
GROUP BY ratecodeid
ORDER BY 1;

-- Q5 The average difference between the driven distance and the haversine distance.
-- The output avg_diff means, in average, trip_distance * avg_diff = haversine_distance

WITH distance AS
(
SELECT trip_distance, pickup_latitude, dropoff_latitude, pickup_longitude, dropoff_longitude,
        3658 * 2 * asin(sqrt(POWER(sin((dropoff_latitude * 3.1415926 / 
                        180 - pickup_latitude * 3.1415926 / 180) / 2), 2) + 
                        cos(dropoff_latitude * 3.1415926 / 180) * 
                        cos(pickup_latitude * 3.1415926 / 180) * 
                        POWER(sin((dropoff_longitude * 3.1415926 / 180 - 
                        pickup_longitude * 3.1415926 / 180) / 2), 2))) AS haversine_distance
FROM
ts_taxi
WHERE pickup_latitude <> dropoff_latitude AND pickup_longitude <> dropoff_longitude
AND pickup_latitude <> pickup_longitude AND  dropoff_latitude <> dropoff_longitude
)
SELECT  round(AVG(ABS(trip_distance - haversine_distance)/trip_distance),4) AS avg_diff
FROM distance
WHERE ROWNUM <= 100000 AND trip_distance > 0.65 AND haversine_distance > 0 AND trip_distance <> haversine_distance;
/*used 100000 rows of data due to device issue.*/

-- Q6 Are there any patterns with tipping over time? If you find one, please provide a possible explanation!
CREATE OR REPLACE VIEW ts_taxi_avgtip AS
    SELECT to_char(lpep_dropoff_datetime, 'hh24') AS HOURS,  round(AVG(tip_amount/fare_amount),4)*100||'%' AS avg_tip_percentage
    FROM ts_taxi
    WHERE tip_amount <> 0 AND fare_amount <> 0 AND payment_type = 1
    GROUP BY to_char(lpep_dropoff_datetime, 'hh24')
    ORDER BY 2 DESC;
SELECT * FROM ts_taxi_avgtip;
-- Expanation: 
/*
We can see that the periods with most tips are 15:00 - 18:00 and 2:00 - 4:00.
15:00 - 18:00 is during the end of a work day, maybe that is why people get generous.
2:00 - 4:00 is early morning. Night shift drivers are more experienced and provide better service, 
and passengers are willing to pay more for service at this time. In addition, many companies 
pay their employees to commute at night.
*/

-- Q7.1 Predict the length of the trip based on factors that are known at pick-up. 
    /* Yes.
    As the relationship could be a linear regression relationship, we can use the machine learning tool-
    - scikit-learn to make predictions.
    The simplified algorithym in Python is shown as beblow:
    ``` from sklearn import datasets, linear_model
        skmodel = linear_model.LinearRegression()
        X = df1_subset[[""]]  # X_train
        y = df1_subset[""]    #y_train
        skmodel.fit(X, y)     # fit the model
        skmodel.predict(['']) # predict the model
      --The train data we use should be time_peiod(dropoff_datetime-pickup_datetime),
        trip_distance, haversine_distance(which can be found in Q5)
    */
    
-- Q7.2 How might you use this information?
    /*
    When we can accurately predict the distance and time of a trip, 
    we can effectively formulate an estimated fare to passengers, 
    which can improve operational transparency, provide passengers 
    with more choices, improve customer loyalty and avoid customer disputes. 
    On the other hand, if the passenger is taking a taxi on the APP or by phone call, 
    predicting the distance and time of the trip allows the driver to freely choose 
    whether he has the ability to take the order, thereby avoiding traffic congestion 
    and improving the customer experience.
    */
    
-- Q8 Present any interesting trends, patterns, or predictions that you notice about this dataset.
/* This query is to see how the tip situation grouped by RateCodeID, 
which is the final rate code in effect at the end of the trip.*/
SELECT DISTINCT ratecodeid,  
        round(AVG(tip_amount/fare_amount),4)*100||'%' AS avg_tip_percentage,
        CASE ratecodeid
            WHEN 1 THEN 'Standard rate'
            WHEN 2 THEN 'JFK'
            WHEN 3 THEN 'Newark'
            WHEN 4 THEN 'Nassau or Westchester'
            WHEN 5 THEN 'Negotiated fare'
            ELSE 'Group ride'
        END codedescription
FROM ts_taxi
WHERE tip_amount > 0 AND fare_amount > 0 AND payment_type = 1
GROUP BY ratecodeid
ORDER BY 2 DESC;
/* I found an interesting thing here: When the fare is negotiated, people are willing to pay 
much more tips than usual. So I want to know if it is becauese the negotiated charged rate is less than others.
*/
SELECT DISTINCT ratecodeid, round(AVG(fare_amount/trip_distance),2) AS charged_rate,
                CASE ratecodeid
                    WHEN 1 THEN 'Standard rate'
                    WHEN 2 THEN 'JFK'
                    WHEN 3 THEN 'Newark'
                    WHEN 4 THEN 'Nassau or Westchester'
                    WHEN 5 THEN 'Negotiated fare'
                    ELSE 'Group ride' -- there are too few data for Group ride, so ignore it when do analysis
                END codedescription
FROM ts_taxi
WHERE trip_distance > 0.65 AND fare_amount > 0 
GROUP BY ratecodeid
ORDER BY 2;
/* it is not the reason at all. negotiated charged rate is the second highest one.
Because the algorithm of this query only considered rates are only charged based on distance,
in reality, it is also influnced by time. However, it is still an interesting trend.
*/