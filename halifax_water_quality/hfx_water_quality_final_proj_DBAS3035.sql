-- Author: Felix Di Nezza

-- PART 1 - #### DATABASE in 3NF ####

/*
*############# HALIFAX COUNTY WATER QUALITY DATABASE #############
*
* DATA SOURCE: 
https://data.novascotia.ca/Nature-and-Environment/Halifax-County-Water-Quality-Data/x9dy-aai9

* INFO: the data contained in the database has been used to forecast algae bloom
*/



/*
-- PART 1 - #### DATABASE in 3NF ####
-- database creation cannot be in the same transaction
-- create the database and switch connection

-- CREATE DATABASE:w

-- DROP DATABASE halifax_wq
CREATE DATABASE halifax_wq
    WITH
    OWNER = postgres
    ENCODING = 'UTF8'
    CONNECTION LIMIT = -1
    IS_TEMPLATE = False;
*/

COMMENT ON DATABASE halifax_wq
IS 'Halifax water quality DB';

-- ### SCHEMAS PREPARATION FOR ETL OPERATIONS ###

-- ### EXTRACT
--DROP SCHEMA data_source CASCADE;
CREATE SCHEMA data_source
AUTHORIZATION postgres;

COMMENT ON SCHEMA data_source
IS 'de-normalized data from source';

-- ### TRANSFORM
--DROP SCHEMA data_transf CASCADE;
CREATE SCHEMA data_transf
AUTHORIZATION postgres;

COMMENT ON SCHEMA data_transf
IS 'transformed data';

-- #### LOAD
--DROP SCHEMA data_dest CASCADE;
CREATE SCHEMA data_dest
AUTHORIZATION postgres;

COMMENT ON SCHEMA data_dest
IS 'normalized data final';


-- ### IMPORT CSV FILE INTO SOURCE SCHEMA ###

-- change schema    
set search_path to 'data_source';

-- table creation for source data csv
--DROP TABLE data_source.halifax_water
CREATE TABLE data_source.halifax_water (
waterbody VARCHAR,
station VARCHAR,
lease VARCHAR,
latitude NUMERIC (10,5),
longitude NUMERIC (10,5),
deployment_period VARCHAR,
"timestamp" TIMESTAMP,
sensor VARCHAR,
"depth" NUMERIC,
variable VARCHAR(150),
"value" NUMERIC (8,3),
units VARCHAR,
mooring VARCHAR
);

-- ### Copy CSV to data_source schema
-- COPY command needs postgre to have rw access to file
-- or use the /tmp folder (best option)
COPY data_source.halifax_water (
waterbody,
station,
lease,
latitude,
longitude,
deployment_period,
"timestamp",
sensor,
"depth",
variable,
"value",
units, mooring)
FROM '/tmp/postgres/Halifax_County_Water_Quality_Data.csv' -- CHECK permissions
WITH(
    DELIMITER ',',
    HEADER TRUE,
    NULL '',
    FORMAT CSV
);


-- PART 1 - #### DATA CLEANSING ####

-- Change SCHEMA search path
set search_path to 'data_transf';

-- DROP TABLE data_transf.halifax_water;
CREATE TABLE data_transf.halifax_water
AS 
(
    SELECT
    hws.waterbody,
    hws.station,
    (
        CASE
            WHEN hws.lease = 'NA'
            THEN hws.lease = NULL
        END
    ) AS lease,
    hws.latitude::NUMERIC,
    hws.longitude::NUMERIC,
    split_part(hws.deployment_period,' to ', 1)::DATE AS deployment_start,
    split_part(hws.deployment_period,' to ', 2)::DATE AS deployment_end,
    hws."timestamp",
    split_part(hws.sensor,'-', 2)::BIGINT AS sns_id,
    split_part(hws.sensor,'-', 1) AS sns_name,
    hws."depth"::NUMERIC,
    hws.variable,
    hws.value::NUMERIC,
    hws.units,
    hws.mooring    
    FROM data_source.halifax_water hws
);

--SELECT * FROM data_transf.halifax_water LIMIT 5;
--SELECT * FROM data_source.halifax_water LIMIT 5;


-- #### CREATE MASTER TABLES IN DESTINATION DATABASE ####

-- Change SCHEMA search path
set search_path to 'data_dest';

-- WATERBODY TABLE
-- DROP TABLE data_dest.waterbody;
CREATE TABLE data_dest.waterbody (
wb_id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
wb_name VARCHAR(250)
);

-- STATION TABLE
-- DROP TABLE data_dest.station;
CREATE TABLE data_dest.station(
st_id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
wb_id_fk BIGINT,
st_name VARCHAR(250)
);

-- LEASE TABLE
-- DROP TABLE data_dest.lease;
CREATE TABLE data_dest.lease (
ls_id BIGINT PRIMARY KEY,
st_id_fk BIGINT
);

-- LOCATION TABLE
-- the location is related to the sensor strips
-- DROP TABLE data_dest."location";
CREATE TABLE data_dest."location" (
lc_id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
st_id_fk BIGINT,
lc_latitude NUMERIC (8,5),
lc_longitude NUMERIC (8,5)
);

-- MOORING TABLE
-- DROP TABLE data_dest.mooring
CREATE TABLE data_dest.mooring (
mo_id INT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
mo_type VARCHAR(50)
);

-- DEPLOYMENT TABLE
-- DROP TABLE data_dest.deployment
CREATE TABLE data_dest.deployment (
dpl_id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
lc_id_fk BIGINT,
mo_id_fk INT, -- mooring used FOR the deploymnet
dpl_start_date DATE, -- start date deployment
dpl_end_date DATE -- end date deployment
);

-- MODEL TABLE
-- DROP TABLE data_dest.model
CREATE TABLE data_dest.model (
m_id INT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
m_name VARCHAR(250)
);

-- SENSOR TABLE
-- DROP TABLE data_dest.sensor;
CREATE TABLE data_dest.sensor (
sns_id BIGINT PRIMARY KEY,
m_id_fk BIGINT
);

-- VARIABLE TABLE
-- DROP TABLE data_dest.variable;
CREATE TABLE data_dest.variable (
var_id INT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
var_name VARCHAR(250)
);

-- UNIT TABLE
-- DROP TABLE data_dest.unit;
CREATE TABLE data_dest.unit (
u_id INT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
u_name VARCHAR(250)
);

-- DEPTH TABLE
-- DROP TABLE data_dest."depth";
CREATE TABLE data_dest."depth" (
dpt_id INT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
dpt_value_mt NUMERIC (8,2)
);

-- #### BRIDGE TABLES destination database ####

-- MEASUREMENT TABLE
-- DROP TABLE data_dest.measurement;
CREATE TABLE data_dest.measurement (
mes_id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
dpl_id_fk BIGINT,
sns_id_fk BIGINT,
var_id_fk INT,
u_id_fk INT,
dpt_id_fk BIGINT,
mes_value NUMERIC (8,2),
mes_timestamp TIMESTAMP
);

-- TABLE for INHERITANCE

-- TABLE INDICANT
-- this table will be used to calculate indexes to use for potential alerts
-- DROP TABLE data_dest.indicant CASCADE;
CREATE TABLE data_dest.indicant (
ind_id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
lc_id_fk BIGINT,
u_id_fk INT,
ind_type VARCHAR (250),
ind_value_p NUMERIC (8,2),
ind_timestamp TIMESTAMP DEFAULT now()
)
;


-- #### SET FOREIGN KEYS CONSTRAINTS ####

-- WATERBODY & STATION
ALTER TABLE data_dest.station
ADD CONSTRAINT FK_station_waterbody  -- FK_foreignKeyTable_primaryKeyTable
FOREIGN KEY (wb_id_fk) REFERENCES data_dest.waterbody(wb_id)
ON UPDATE CASCADE
ON DELETE CASCADE
;

 -- STATION & LOCATION
ALTER TABLE data_dest."location"
ADD CONSTRAINT FK_location_station -- FK_foreignKeyTable_primaryKeyTable
FOREIGN KEY (st_id_fk) REFERENCES data_dest.station(st_id)
ON UPDATE CASCADE
ON DELETE CASCADE
;

 -- STATION & LEASE
ALTER TABLE data_dest.lease
ADD CONSTRAINT FK_lease_station -- FK_foreignKeyTable_primaryKeyTable
FOREIGN KEY (st_id_fk) REFERENCES data_dest.station(st_id)
ON UPDATE CASCADE
ON DELETE CASCADE
;

-- SENSOR & MEASUREMENT
ALTER TABLE data_dest.measurement
ADD CONSTRAINT FK_measurement_sensor -- FK_foreignKeyTable_primaryKeyTable
FOREIGN KEY (sns_id_fk) REFERENCES data_dest.sensor(sns_id)
ON UPDATE CASCADE
ON DELETE CASCADE
;

-- VARIABLE & MEASUREMENT
ALTER TABLE data_dest.measurement
ADD CONSTRAINT FK_measurement_variable -- FK_foreignKeyTable_primaryKeyTable
FOREIGN KEY (var_id_fk) REFERENCES data_dest.variable(var_id)
ON UPDATE CASCADE
ON DELETE CASCADE
;

-- UNIT & MEASUREMENT
ALTER TABLE data_dest.measurement
ADD CONSTRAINT FK_measurement_unit -- FK_foreignKeyTable_primaryKeyTable
FOREIGN KEY (u_id_fk) REFERENCES data_dest.unit(u_id)
ON UPDATE CASCADE
ON DELETE CASCADE
;

 -- DEPLOYMENT & MEASUREMENT
ALTER TABLE data_dest.measurement
ADD CONSTRAINT FK_measurement_deployment -- FK_foreignKeyTable_primaryKeyTable
FOREIGN KEY (dpl_id_fk) REFERENCES data_dest.deployment(dpl_id)
ON UPDATE CASCADE
ON DELETE CASCADE
;

-- DEPTH & MEASUREMENT
ALTER TABLE data_dest.measurement
ADD CONSTRAINT FK_measurement_depth -- FK_foreignKeyTable_primaryKeyTable
FOREIGN KEY (dpt_id_fk) REFERENCES data_dest."depth"(dpt_id)
ON UPDATE CASCADE
ON DELETE CASCADE
;

-- LOCATION & DEPLOYMENT
ALTER TABLE data_dest.deployment
ADD CONSTRAINT FK_deployment_location -- FK_foreignKeyTable_primaryKeyTable
FOREIGN KEY (lc_id_fk) REFERENCES data_dest."location"(lc_id)
ON UPDATE CASCADE
ON DELETE CASCADE
;

-- MOORING & DEPLOYMENT
ALTER TABLE data_dest.deployment
ADD CONSTRAINT FK_deployment_mooring -- FK_foreignKeyTable_primaryKeyTable
FOREIGN KEY (mo_id_fk) REFERENCES data_dest.mooring(mo_id)
ON UPDATE CASCADE
ON DELETE CASCADE
;

-- SENSOR & MODEL
ALTER TABLE data_dest.sensor
ADD CONSTRAINT FK_sensor_model -- FK_foreignKeyTable_primaryKeyTable
FOREIGN KEY (m_id_fk) REFERENCES data_dest.model(m_id)
ON UPDATE CASCADE
ON DELETE CASCADE
;

-- PARENT TABLE FOR INHERITANCE
-- LOCATION & INDICANT
ALTER TABLE data_dest.indicant
ADD CONSTRAINT FK_indicant_location -- FK_foreignKeyTable_primaryKeyTable
FOREIGN KEY (lc_id_fk) REFERENCES data_dest."location"(lc_id)
ON UPDATE CASCADE
ON DELETE CASCADE
;

-- UNIT & INDICANT
ALTER TABLE data_dest.indicant
ADD CONSTRAINT FK_indicant_unit -- FK_foreignKeyTable_primaryKeyTable
FOREIGN KEY (u_id_fk) REFERENCES data_dest.unit(u_id)
ON UPDATE CASCADE
ON DELETE CASCADE
;

-- ##### INHERITED TABLES #####
/*
 * inherited table can recall the parent pk during inserts
 */
-- TABLE ALERT - alert is c_indicant's child
-- DROP TABLE data_dest.alert;
CREATE TABLE data_dest.alert (
al_type VARCHAR (255)
) INHERITS (data_dest.indicant)
;


-- #### POPULATE MASTER TABLES in the destination database ####

-- WATERBODY TABLE
INSERT INTO data_dest.waterbody 
(wb_name) 
(
SELECT DISTINCT waterbody FROM data_source.halifax_water shw
);
-- SELECT * FROM data_dest.waterbody;


--  MOORING TABLE
INSERT INTO data_dest.mooring
(mo_type)
(
    SELECT DISTINCT hws.mooring
    FROM data_source.halifax_water hws
);
--SELECT * FROM data_dest.mooring m;


--  MODEL TABLE
INSERT INTO data_dest.model
(m_name)
(
    SELECT DISTINCT hwt.sns_name
    FROM data_transf.halifax_water hwt
);
--SELECT * FROM data_dest.model;


-- VARIABLE TABLE
INSERT INTO data_dest.variable
(var_name)
(
    SELECT DISTINCT hwt.variable
    FROM data_transf.halifax_water hwt
);
--SELECT * FROM data_dest.variable v;


-- UNIT TABLE 
INSERT INTO data_dest.unit
(u_name)
(
    SELECT DISTINCT hwt.units
    FROM data_transf.halifax_water hwt
);
--SELECT * FROM data_dest.unit u ;

-- DEPTH TABLE
INSERT INTO data_dest."depth" 
(dpt_value_mt)
(
    SELECT DISTINCT hwt."depth"
    FROM data_source.halifax_water hwt
);

--SELECT * FROM data_dest."depth" d;

-- #### POPULATE CHILD TABLES in the destination database ####

-- STATION TABLE
INSERT INTO data_dest.station (
wb_id_fk,
st_name
)
(
    WITH wb_pk
    AS 
    (
    SELECT wb_id, wb_name FROM data_dest.waterbody 
    )
    SELECT DISTINCT wk.wb_id,
    hws.station
    FROM data_source.halifax_water hws
    INNER JOIN wb_pk wk
    ON wk.wb_name = hws.waterbody 
);
-- SELECT DISTINCT station, lease FROM data_source.halifax_water;
-- SELECT * FROM data_dest.station;


-- LEASE TABLE
INSERT INTO data_dest.lease (
ls_id,
st_id_fk
)
(
    WITH st_pk
    AS 
    (
    SELECT st_id, st_name FROM data_dest.station 
    )
    SELECT DISTINCT
    hws.lease::BIGINT,
    sk.st_id
    FROM data_source.halifax_water hws
    INNER JOIN st_pk sk
    ON sk.st_name = hws.station
    WHERE hws.lease <> 'NA'
);

-- SELECT * FROM data_dest.lease;


-- LOCATION TABLE
INSERT INTO data_dest."location" (
st_id_fk,
lc_latitude,
lc_longitude
)
(
    WITH st_pk
    AS 
    (
    SELECT st_id, st_name FROM data_dest.station 
    )
    SELECT DISTINCT sk.st_id,
    hws.latitude,
    hws.longitude
    FROM data_source.halifax_water hws
    INNER JOIN st_pk sk
    ON sk.st_name = hws.station
);

--SELECT DISTINCT hw.latitude, hw.longitude FROM data_source.halifax_water hw;
-- SELECT * FROM data_dest.location;


-- DEPLOYMENT TABLE
INSERT INTO data_dest.deployment
(
lc_id_fk,
mo_id_fk,
dpl_start_date,
dpl_end_date
)
(
    WITH loc_pk
    AS
    (
        SELECT l.lc_id,
        l.lc_latitude,
        l.lc_longitude
        FROM data_dest."location" l
    ),
    mor_pk
    AS
    (
        SELECT m.mo_id,
        m.mo_type
        FROM data_dest.mooring m
    )
    SELECT DISTINCT
    lk.lc_id,
    mk.mo_id,
    hwt.deployment_start,
    hwt.deployment_end
    FROM data_transf.halifax_water hwt    
    INNER JOIN loc_pk lk
    ON hwt.latitude = lk.lc_latitude
    AND hwt.longitude = lk.lc_longitude
    INNER JOIN mor_pk mk
    ON hwt.mooring = mk.mo_type
);
-- SELECT * FROM data_dest.deployment d;


-- SENSOR TABLE
INSERT INTO data_dest.sensor (
sns_id,
m_id_fk
)
(
    WITH 
    sns_serial
    AS
    (
        SELECT DISTINCT
        hwt.sns_id,
        hwt.sns_name
        FROM data_transf.halifax_water hwt
    ),
    model_pk
    AS
    (
        SELECT m_id,
        m_name
        FROM data_dest.model
    )
    SELECT ss.sns_id,
    mk.m_id
    FROM sns_serial ss
    INNER JOIN model_pk mk
    ON mk.m_name = ss.sns_name
);
/*
SELECT (m.m_name ||'-'|| s.sns_id ) AS fn 
FROM data_dest.sensor s
INNER JOIN data_dest.model m 
ON s.m_id_fk = m.m_id ;

SELECT DISTINCT hws.sensor
FROM data_source.halifax_water hws;
*/


-- #### POPULATE BRIDGE TABLES in the destination database ####

-- TABLE MEASUREMENT
INSERT INTO data_dest.measurement (
dpl_id_fk,
sns_id_fk,
var_id_fk,
u_id_fk,
dpt_id_fk,
mes_value,
mes_timestamp 
)
(
    WITH
    dpl_pk
    AS
    (
        SELECT dl.dpl_id,
        l.lc_latitude,
        l.lc_longitude,
        mr.mo_type,
        dl.dpl_start_date,
        dl.dpl_end_date
        FROM data_dest."location" l
        INNER JOIN data_dest.deployment dl
        ON dl.lc_id_fk = l.lc_id
        INNER JOIN data_dest.mooring mr
        ON dl.mo_id_fk = mr.mo_id
    ),
    var_pk
    AS
    (
        SELECT v.var_id,
        v.var_name
        FROM data_dest.variable v
    ),
    unit_pk
    AS
    (
        SELECT u.u_id,
        u.u_name
        FROM data_dest.unit u
    ),
    dpt_pk
    AS
    (
        SELECT dp.dpt_id,
        dp.dpt_value_mt
        FROM data_dest."depth" dp
    )
    SELECT dlk.dpl_id,
    hwt.sns_id,
    vk.var_id,
    uk.u_id,
    dpk.dpt_id,
    hwt.value,
    hwt."timestamp"
    FROM data_transf.halifax_water hwt
    INNER JOIN dpl_pk dlk
    ON hwt.latitude = dlk.lc_latitude
    AND hwt.longitude = dlk.lc_longitude
    AND hwt.deployment_start = dlk.dpl_start_date
    AND hwt.deployment_end = dlk.dpl_end_date
    INNER JOIN var_pk vk
    ON hwt.variable = vk.var_name
    INNER JOIN unit_pk uk
    ON hwt.units = uk.u_name
    INNER JOIN dpt_pk dpk
    ON hwt."depth" = dpk.dpt_value_mt
);

/*
SELECT count(*) FROM (
    SELECT hwt.sns_id,
    hwt.variable,
    hwt.units,
    hwt.value,
    hwt."timestamp"
    FROM data_transf.halifax_water hwt
) sub;

SELECT count (*)
FROM data_dest.measurement m;
*/


-- PART 2 - #### QUERIES ####
/*
Provide tables with data and SQL queries to obtain meaningful results from
the dataset. The number of queries should be more than four. 
The first query should include a SELECT statement involving more than two 
tables, if possible. Also, make sure to use table aliases. In the second
query, use VIEW. In the third query, use CTE. You can add more queries to 
illustrate more skills
up to six in total.

 */


-- #### QUERY 1 #### -- 
/*
INFO: query using SELECT statement involving more than 2 tables

SCOPE: Number of deployments over time in each water body
ordered descendently
*/

SELECT w.wb_name,
count (dpl.dpl_id) AS nr_deployments
FROM data_dest.waterbody w
INNER JOIN data_dest.station s
ON s.wb_id_fk = w.wb_id
INNER JOIN data_dest."location" lc
ON lc.st_id_fk = s.st_id
INNER JOIN data_dest.deployment dpl
ON dpl.lc_id_fk = lc.lc_id
GROUP BY w.wb_name
ORDER BY nr_deployments DESC
;


-- #### QUERY 2 #### -- 
/*
INFO: query using SELECT statement involving more than 2 tables and using a VIEW

SCOPE: all sensors' data realated to all deployments
*/

-- DROP VIEW data_dest.data_dest.vw_all_data_all_deployments;
CREATE VIEW data_dest.vw_all_data_all_deployments
AS
(
    SELECT
    w.wb_name,
    st.st_name,
    lc.lc_latitude,
    lc.lc_longitude,
    mr.mo_type,
    dl.dpl_start_date,
    dl.dpl_end_date,
    sn.sns_id,
    md.m_name,
    dt.dpt_value_mt,
    v.var_name,
    u.u_name,
    m.mes_value,
    m.mes_timestamp
    FROM data_dest.measurement m
    INNER JOIN data_dest."depth" dt
    ON m.dpt_id_fk = dt.dpt_id
    INNER JOIN data_dest.unit u
    ON m.u_id_fk = u.u_id
    INNER JOIN data_dest.variable v
    ON m.var_id_fk = v.var_id
    INNER JOIN data_dest.sensor sn
    ON m.sns_id_fk = sn.sns_id
    INNER JOIN data_dest.model md
    ON sn.m_id_fk = md.m_id
    INNER JOIN data_dest.deployment dl
    ON m.dpl_id_fk = dl.dpl_id
    INNER JOIN data_dest.mooring mr
    ON dl.mo_id_fk = mr.mo_id
    INNER JOIN data_dest."location" lc
    ON dl.lc_id_fk = lc.lc_id
    INNER JOIN data_dest.station st
    ON lc.st_id_fk = st.st_id
    INNER JOIN data_dest.waterbody w
    ON st.wb_id_fk = w.wb_id
);

/*
SELECT * FROM data_dest.vw_all_data_all_deployments;

SELECT DISTINCT  date_part('year',dl.mes_timestamp) AS dp_year
FROM data_dest.vw_all_data_all_deployments dl;
*/


-- #### QUERY 3 #### -- 
/*
SELECT statement involving more than 2 tables and using CTE

SCOPE: compare the average temperature difference by depth in 2018 between
 'St. Margarets Bay' and 'Shad Bay'
*/

WITH 
cte_st_mg_avg_temp_18
AS 
(
    SELECT
    vadd.dpt_value_mt,
    round(avg(vadd.mes_value),2) AS avg_temp_2018_st_margaret_bay
    FROM data_dest.vw_all_data_all_deployments vadd
    WHERE date_part('year',vadd.mes_timestamp) = 2018
    AND vadd.var_name = 'Temperature'
    AND vadd.wb_name = 'St. Margarets Bay'
    GROUP BY vadd.wb_name, vadd.dpt_value_mt
    ORDER BY vadd.dpt_value_mt DESC
), 
cte_st_sb_avg_temp_18
AS 
(
    SELECT
    vadd.dpt_value_mt,
    round(avg(vadd.mes_value),2) AS avg_temp_2018_shad_bay
    FROM data_dest.vw_all_data_all_deployments vadd
    WHERE date_part('year',vadd.mes_timestamp) = 2018
    AND vadd.var_name = 'Temperature'
    AND vadd.wb_name = 'Shad Bay'
    GROUP BY vadd.wb_name, vadd.dpt_value_mt
    ORDER BY vadd.dpt_value_mt DESC
)
SELECT
atm18.dpt_value_mt,
atm18.avg_temp_2018_st_margaret_bay,
ats18.avg_temp_2018_shad_bay,
(abs(atm18.avg_temp_2018_st_margaret_bay 
     - ats18.avg_temp_2018_shad_bay))
AS temp_difference,
(
    CASE 
        WHEN (atm18.avg_temp_2018_st_margaret_bay 
              - ats18.avg_temp_2018_shad_bay) < 0
        THEN 'Shad Bay'
        WHEN (atm18.avg_temp_2018_st_margaret_bay 
              - ats18.avg_temp_2018_shad_bay) > 0
        THEN 'St Margaret Bay'
        WHEN (atm18.avg_temp_2018_st_margaret_bay 
              - ats18.avg_temp_2018_shad_bay) = 0
        THEN 'same temperature'
    END
) AS higher_temp_in
FROM cte_st_mg_avg_temp_18 atm18
INNER JOIN cte_st_sb_avg_temp_18 ats18
ON atm18.dpt_value_mt = ats18.dpt_value_mt
;



-- #### QUERY 4 - OPTIONAL #### -- 
/*
INFO: the average level of oxygen saturation should be 8 mg/L or 73%
below 2mg/L or 18% the water is hypoxic aka dead zone

SCOPE: find location with a oxygen saturation level below 8 mg/L or 73%
and insert the result in the table indicant - this table will be used for the 
INHERITED table example
**/

INSERT INTO data_dest.indicant
(
lc_id_fk, 
u_id_fk,
ind_type,
ind_value_p,
ind_timestamp
)
WITH cte_hypox
AS
(
    SELECT vad.lc_latitude,
    vad.lc_longitude,
    vad.u_name,
    ('below avg DO') AS type_ind,
    vad.mes_value,
    vad.mes_timestamp
    FROM data_dest.vw_all_data_all_deployments vad
    WHERE vad.var_name = 'Dissolved Oxygen'
    AND vad.u_name ='percent saturation'
    AND vad.mes_value <= 75
),
loc_pk
AS 
(
    SELECT lc.lc_id,
    lc.lc_latitude,
    lc.lc_longitude
    FROM data_dest."location" lc
),
unit_pk
AS
(
    SELECT u.u_id,
    u.u_name
    FROM data_dest.unit u
)
SELECT lk.lc_id,
uk.u_id,
ch.type_ind,
ch.mes_value,
ch.mes_timestamp
FROM cte_hypox ch
INNER JOIN loc_pk lk
ON ch.lc_latitude = lk.lc_latitude 
AND ch.lc_longitude = lk.lc_longitude
INNER JOIN unit_pk uk
ON ch.u_name = uk.u_name
;

-- show parent table together with the child
--SELECT * FROM data_dest.indicant i;

-- show only the parent
--SELECT * FROM ONLY data_dest.indicant i;


-- #### QUERY 5 - OPTIONAL #### -- 
/*
INFO: algae bloom appear in areas with low oxygen saturation
 
SCOPE: find location with a oxygen saturation level below 3mg/L or 27%
and insert the result in the table alert to create and mark bloom alert
-- this table is the child of the indicant table
 
INHERITED table example
*/

INSERT INTO data_dest.alert 
(
ind_id,
lc_id_fk, 
u_id_fk,
ind_type,
ind_value_p,
ind_timestamp,
al_type
)
WITH cte_hypox
AS
(
    SELECT vad.lc_latitude,
    vad.lc_longitude,
    vad.u_name,
    ('hypoxia') AS type_ind,
    vad.mes_value,
    vad.mes_timestamp,
    ('algae bloom') AS alert
    FROM data_dest.vw_all_data_all_deployments vad
    WHERE vad.var_name = 'Dissolved Oxygen'
    AND vad.u_name ='percent saturation'
    AND vad.mes_value <= 27
    UNION ALL
    SELECT vad.lc_latitude,
    vad.lc_longitude,
    vad.u_name,
    ('hypoxia') AS type_ind,
    vad.mes_value,
    vad.mes_timestamp,
    ('algae bloom') AS alert
    FROM data_dest.vw_all_data_all_deployments vad
    WHERE vad.var_name = 'Dissolved Oxygen'
    AND vad.u_name  = 'mg/L'
    AND vad.mes_value <= 3
),
loc_pk
AS 
(
    SELECT lc.lc_id,
    lc.lc_latitude,
    lc.lc_longitude
    FROM data_dest."location" lc
),
unit_pk
AS
(
    SELECT u.u_id,
    u.u_name
    FROM data_dest.unit u
)
SELECT  -- trigger parent identity seq
nextval('data_dest.indicant_ind_id_seq') AS parent_pk,
lk.lc_id,
uk.u_id,
ch.type_ind,
ch.mes_value,
ch.mes_timestamp,
ch.alert
FROM cte_hypox ch
INNER JOIN loc_pk lk
ON ch.lc_latitude = lk.lc_latitude 
AND ch.lc_longitude = lk.lc_longitude
INNER JOIN unit_pk uk
ON ch.u_name = uk.u_name
;
-- show content child table only
SELECT * FROM data_dest.alert a;


-- #### QUERY 6 - OPTIONAL ####
/*
SCOPE: create a view with all the zones subject to algae bloom alert
*/
-- DROP VIEW data_dest.vw_algae_bloom_locations;
CREATE VIEW data_dest.vw_algae_bloom_locations
AS
(
    SELECT 
    w.wb_name,
    st.st_name,
    lc.lc_latitude,
    lc.lc_longitude,
    a.al_type AS alert,
    a.ind_type AS indicant,
    a.ind_value_p AS value,
    a.ind_timestamp AS alert_time
    FROM data_dest.alert a
    INNER JOIN data_dest."location" lc
    ON a.lc_id_fk = lc.lc_id
    INNER JOIN data_dest.unit u
    ON a.u_id_fk = u.u_id 
    INNER JOIN data_dest.station st
    ON lc.st_id_fk = st.st_id
    INNER JOIN data_dest.waterbody w
    ON st.wb_id_fk = w.wb_id
)
;

--SELECT * FROM data_dest.vw_algae_bloom_locations vabl;


-- PART 3 ### QUERY PERFORMANCE ANALYSIS AND INDEXES ###

-- #### QUERY 3 ####
/*
SELECT statement involving more than 2 tables and using CTE

SCOPE: avarage temperature difference by depth between 2018 and 2022 
in 'St. Margarets Bay'
*/

-- ANALYZE; 
-- VACUUM ANALYZE;

EXPLAIN (ANALYSE)
WITH 
cte_st_mg_avg_temp_18
AS 
(
    SELECT
    vadd.dpt_value_mt,
    round(avg(vadd.mes_value),2) AS avg_temp_2018_st_margaret_bay
    FROM data_dest.vw_all_data_all_deployments vadd
    WHERE date_part('year',vadd.mes_timestamp) = 2018
    AND vadd.var_name = 'Temperature'
    AND vadd.wb_name = 'St. Margarets Bay'
    GROUP BY vadd.wb_name, vadd.dpt_value_mt
    ORDER BY vadd.dpt_value_mt DESC
), 
cte_st_sb_avg_temp_18
AS 
(
    SELECT
    vadd.dpt_value_mt,
    round(avg(vadd.mes_value),2) AS avg_temp_2018_shad_bay
    FROM data_dest.vw_all_data_all_deployments vadd
    WHERE date_part('year',vadd.mes_timestamp) = 2018
    AND vadd.var_name = 'Temperature'
    AND vadd.wb_name = 'Shad Bay'
    GROUP BY vadd.wb_name, vadd.dpt_value_mt
    ORDER BY vadd.dpt_value_mt DESC
)
SELECT
atm18.dpt_value_mt,
atm18.avg_temp_2018_st_margaret_bay,
ats18.avg_temp_2018_shad_bay,
(abs(atm18.avg_temp_2018_st_margaret_bay - ats18.avg_temp_2018_shad_bay)) 
AS temp_difference,
(
    CASE 
        WHEN (atm18.avg_temp_2018_st_margaret_bay 
              - ats18.avg_temp_2018_shad_bay) < 0
        THEN 'Shad Bay'
        WHEN (atm18.avg_temp_2018_st_margaret_bay 
              - ats18.avg_temp_2018_shad_bay) > 0
        THEN 'St Margaret Bay'
        WHEN (atm18.avg_temp_2018_st_margaret_bay 
              - ats18.avg_temp_2018_shad_bay) = 0
        THEN 'same temperature'
    END
) AS higher_temp_in
FROM cte_st_mg_avg_temp_18 atm18
INNER JOIN cte_st_sb_avg_temp_18 ats18
ON atm18.dpt_value_mt = ats18.dpt_value_mt
;

/*
ANALYSIS:
The query is using a simple view and it takes approximately 14-15 seconds to 
complete. Even if we create indexes, due to the high perfomance of the server 
the parallel scans are still cheaper (very slightly). Therefore, to increase 
the query performance I will change the VIEW that the query is using to a 
MATERIALIZED one.
*/

--DROP MATERIALIZED VIEW data_dest.m_vw_all_data_all_deployments;
CREATE MATERIALIZED VIEW data_dest.m_vw_all_data_all_deployments
AS
(
    SELECT
    w.wb_name,
    st.st_name,
    lc.lc_latitude,
    lc.lc_longitude,
    mr.mo_type,
    dl.dpl_start_date,
    dl.dpl_end_date,
    sn.sns_id,
    md.m_name,
    dt.dpt_value_mt,
    v.var_name,
    u.u_name,
    m.mes_value,
    m.mes_timestamp
    FROM data_dest.measurement m
    INNER JOIN data_dest."depth" dt
    ON m.dpt_id_fk = dt.dpt_id
    INNER JOIN data_dest.unit u
    ON m.u_id_fk = u.u_id
    INNER JOIN data_dest.variable v
    ON m.var_id_fk = v.var_id
    INNER JOIN data_dest.sensor sn
    ON m.sns_id_fk = sn.sns_id
    INNER JOIN data_dest.model md
    ON sn.m_id_fk = md.m_id
    INNER JOIN data_dest.deployment dl
    ON m.dpl_id_fk = dl.dpl_id
    INNER JOIN data_dest.mooring mr
    ON dl.mo_id_fk = mr.mo_id
    INNER JOIN data_dest."location" lc
    ON dl.lc_id_fk = lc.lc_id
    INNER JOIN data_dest.station st
    ON lc.st_id_fk = st.st_id
    INNER JOIN data_dest.waterbody w
    ON st.wb_id_fk = w.wb_id
) WITHOUT DATA;

-- populate the materialize view created
REFRESH MATERIALIZED VIEW data_dest.m_vw_all_data_all_deployments;

--SELECT * FROM data_dest.m_vw_all_data_all_deployments LIMIT 5;


-- ## PERFOMANCE ANALYSIS with materialized view

-- ANALYZE;
-- VACUUM ANALYZE;

EXPLAIN (ANALYZE)
WITH 
cte_st_mg_avg_temp_18
AS 
(
    SELECT
    mvadd.dpt_value_mt,
    round(avg(mvadd.mes_value),2) AS avg_temp_2018_st_margaret_bay
    FROM data_dest.m_vw_all_data_all_deployments mvadd
    WHERE date_part('year',mvadd.mes_timestamp) = 2018
    AND mvadd.var_name = 'Temperature'
    AND mvadd.wb_name = 'St. Margarets Bay'
    GROUP BY mvadd.wb_name, mvadd.dpt_value_mt
    ORDER BY mvadd.dpt_value_mt DESC
), 
cte_st_sb_avg_temp_18
AS 
(
    SELECT
    mvadd.dpt_value_mt,
    round(avg(mvadd.mes_value),2) AS avg_temp_2018_shad_bay
    FROM data_dest.m_vw_all_data_all_deployments mvadd
    WHERE date_part('year',mvadd.mes_timestamp) = 2018
    AND mvadd.var_name = 'Temperature'
    AND mvadd.wb_name = 'Shad Bay'
    GROUP BY mvadd.wb_name, mvadd.dpt_value_mt
    ORDER BY mvadd.dpt_value_mt DESC
)
SELECT
atm18.dpt_value_mt,
atm18.avg_temp_2018_st_margaret_bay,
ats18.avg_temp_2018_shad_bay,
(abs(atm18.avg_temp_2018_st_margaret_bay - ats18.avg_temp_2018_shad_bay))
AS temp_difference,
(
    CASE 
        WHEN (atm18.avg_temp_2018_st_margaret_bay 
              - ats18.avg_temp_2018_shad_bay) < 0
        THEN 'Shad Bay'
        WHEN (atm18.avg_temp_2018_st_margaret_bay 
              - ats18.avg_temp_2018_shad_bay) > 0
        THEN 'St Margaret Bay'
        WHEN (atm18.avg_temp_2018_st_margaret_bay 
              - ats18.avg_temp_2018_shad_bay) = 0
        THEN 'same temperature'
    END
) AS higher_temp_in
FROM cte_st_mg_avg_temp_18 atm18
INNER JOIN cte_st_sb_avg_temp_18 ats18
ON atm18.dpt_value_mt = ats18.dpt_value_mt
;

/*
ANALYSIS:
By using a materialized view, the query takes about 1,2 second to complete 
saving us 13-14 seconds. We can further improve performance by adding an INDEX 
to the MATERIALIZED view.
 */

-- INDEXES on MATERIALIZED VIEW 
--DROP INDEX data_dest.idx_m_vw_all_data_all_deployments_wb_name;
CREATE INDEX idx_m_vw_all_data_all_deployments_wb_name
ON data_dest.m_vw_all_data_all_deployments (wb_name);

/*
ANALYSIS:
By adding the INDEX we can drop the execution time of the query below 1 second
(approx. 0.9). The index is used becase of the WHERE clause with a string value
comparison. 
*/


-- ### ADDITIONAL VIEWS FOR DATA VISUALIZATION ###

-- Change SCHEMA search path
set search_path to 'data_dest';

/*
all deployments done for each waterdoby without group by. The manipulations will
be done in the data visualization software.
*/
-- DROP VIEW data_dest.vw_all_deployments;
CREATE VIEW data_dest.vw_all_deployments
AS 
(
    SELECT
    w.wb_name,
    s.st_name,
    lc.lc_latitude,
    lc.lc_longitude,
    dpl.dpl_id
    FROM data_dest.waterbody w
    INNER JOIN data_dest.station s 
    ON s.wb_id_fk = w.wb_id 
    INNER JOIN data_dest."location" lc 
    ON lc.st_id_fk = s.st_id
    INNER JOIN data_dest.deployment dpl
    ON dpl.lc_id_fk = lc.lc_id 
);

--SELECT * FROM data_dest.vw_all_deployments;



