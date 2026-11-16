DROP TABLE IF EXISTS t_items;
CREATE TABLE t_items (
    id   INTEGER,
    name VARCHAR,
    qty  INTEGER,
    amt  DECIMAL(10,2)
);

INSERT INTO t_items VALUES (1, 'alpha', 10, 1.50), (2, 'beta', 20, 2.25), (3, 'gamma', -5, NULL);

DROP TABLE IF EXISTS t_types;
CREATE TABLE t_types (
    id   INTEGER,
    flag BOOLEAN,
    big  BIGINT,
    huge HUGEINT,
    amt  DECIMAL(12,3),
    dbl  DOUBLE,
    ts   TIMESTAMP,
    dtz  TIMESTAMPTZ,
    d    DATE,
    tm   TIME,
    blb  BLOB,
    js   JSON,
    lst  INTEGER[],
    st   STRUCT(a INTEGER, b VARCHAR),
    mp   MAP(VARCHAR, INTEGER)
);

INSERT INTO t_types VALUES
    (1, true, 9007199254740993, 170141183460469231731687303715884105727, 1234.500, 2.25,
     TIMESTAMP '2026-11-13 10:00:00', TIMESTAMPTZ '2026-11-13 10:00:00+08',
     DATE '2026-11-13', TIME '10:30:00', encode('abc'), '{"k": 1}',
     [1, 2, 3], {'a': 7, 'b': 'x'}, MAP {'p': 1, 'q': 2}),
    (2, false, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, [], NULL, NULL);

DROP TABLE IF EXISTS t_cn;
CREATE TABLE t_cn (id INTEGER, name_cn VARCHAR);
INSERT INTO t_cn VALUES (1, '张三'), (2, '李四（测试）'), (3, 'emoji 😀 测试');

DROP TABLE IF EXISTS t_parent;
CREATE TABLE t_parent (id INTEGER);
INSERT INTO t_parent VALUES (1);
